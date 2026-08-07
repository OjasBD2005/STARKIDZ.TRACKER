#!/usr/bin/env python3
"""
STAR Kidz - distributor catalogue builder.

Reads the daily Busy stock export, compares it against the previous snapshot, resolves a
photo for every article/colour, and lays the result out as an A4 distributor catalogue.

    python distributor_catalogue.py                     # newest STOCK-*.xlsx it can find
    python distributor_catalogue.py --file STOCK-07-08-2026.xlsx
    python distributor_catalogue.py --no-verify         # skip the Grand Total gate (not advised)

Install once:

    pip install pandas openpyxl reportlab pillow tqdm

--------------------------------------------------------------------------------------
ON MERGING YESTERDAY AND TODAY - READ THIS BEFORE CHANGING IT

The Busy stock report is a COMPLETE SNAPSHOT, not a day's movement. Today's file already
contains the whole warehouse. Adding yesterday's quantities to it does not "combine" the
two - it counts the same cartons twice. That is not hypothetical: it is the bug that made
the catalogue read 34,474 cartons against a report whose Grand Total said 17,237.

So "combine yesterday and today" is implemented as:

    today's quantities REPLACE yesterday's, and yesterday is used ONLY to work out what
    moved - sold, added, newly arrived, and gone.

An article dispatched yesterday is simply absent from today's file, so it drops out of the
catalogue on its own. That is the intended behaviour, not data loss.

If you ever do want a true sum (two warehouses exported separately, say), pass
--merge-mode sum. It is deliberately not the default, and it prints a loud warning,
because on two snapshots of the SAME warehouse it is always wrong.
--------------------------------------------------------------------------------------

ON VERIFYING PHOTOS

This script checks that every article/colour in stock resolves to a photo file that exists
on disk, and reports what had to fall back to a less specific image. It does NOT read
pixels, so it cannot confirm that a photo labelled BLK actually shows a black shoe - the
colour is only ever taken from the file name. Anything it cannot resolve is listed in the
verification CSV rather than quietly given a wrong picture.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path

# ---------------------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------------------

BASE_DIR = Path(r"C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop")
APP_DIR = BASE_DIR / "CLAUDE DATA"           # the checkout holding article-photos/ etc.
PHOTO_DIR = APP_DIR / "article-photos"
PHOTO_INDEX_JS = APP_DIR / "star-kidz-photo-index.js"
SNAPSHOT_DIR = APP_DIR / "stock-snapshots"   # one JSON per stock date, for the comparison
OUTPUT_DIR = BASE_DIR / "Distributor Catalogues"

# Where a daily export might land. First match wins.
SEARCH_DIRS = [BASE_DIR, Path.home() / "Downloads", APP_DIR]
STOCK_RE = re.compile(r"STOCK-(\d{2})-(\d{2})-(\d{4})", re.I)

# Layout: 2 columns x 3 rows of article cards per A4 page.
CARDS_ACROSS, CARDS_DOWN = 2, 3


# ---------------------------------------------------------------------------------------
# Progress reporting
# ---------------------------------------------------------------------------------------

class Progress:
    """tqdm when available, otherwise a plain one-line counter. Never a hard dependency."""

    def __init__(self, total: int, label: str):
        self.total, self.label, self.n = total, label, 0
        try:
            from tqdm import tqdm
            self._bar = tqdm(total=total, desc=label, unit="item", leave=True)
        except ImportError:
            self._bar = None
            print(f"{label}: 0/{total}", end="", flush=True)

    def step(self, n: int = 1) -> None:
        self.n += n
        if self._bar:
            self._bar.update(n)
        else:
            print(f"\r{self.label}: {self.n}/{self.total}", end="", flush=True)

    def done(self) -> None:
        if self._bar:
            self._bar.close()
        else:
            print(f"\r{self.label}: {self.n}/{self.total}  done")


def say(msg: str) -> None:
    print(f"[{datetime.now():%H:%M:%S}] {msg}", flush=True)


# ---------------------------------------------------------------------------------------
# Locating the stock file
# ---------------------------------------------------------------------------------------

def stock_date_from_name(p: Path) -> date | None:
    m = STOCK_RE.search(p.name)
    if not m:
        return None
    d, mo, y = (int(g) for g in m.groups())
    try:
        return date(y, mo, d)
    except ValueError:
        return None


def find_stock_file(explicit: str | None) -> tuple[Path, date]:
    if explicit:
        p = Path(explicit)
        if not p.is_absolute():
            for root in SEARCH_DIRS:
                if (root / p).exists():
                    p = root / p
                    break
        if not p.exists():
            raise SystemExit(f"Not found: {p}")
        d = stock_date_from_name(p)
        if not d:
            raise SystemExit(f"Cannot read a date from the file name (expect STOCK-DD-MM-YYYY.xlsx): {p.name}")
        return p, d

    found: list[tuple[Path, date]] = []
    for root in SEARCH_DIRS:
        if not root.exists():
            continue
        for p in root.glob("STOCK-*.xlsx"):
            if p.name.startswith("~$"):        # Excel lock file
                continue
            d = stock_date_from_name(p)
            if d:
                found.append((p, d))
    if not found:
        raise SystemExit("No STOCK-DD-MM-YYYY.xlsx found in:\n  " + "\n  ".join(str(r) for r in SEARCH_DIRS))
    # newest stock DATE first, then newest file on disk - a re-export of the same day wins
    found.sort(key=lambda t: (t[1], t[0].stat().st_mtime), reverse=True)
    return found[0]


# ---------------------------------------------------------------------------------------
# Parsing the report
# ---------------------------------------------------------------------------------------

@dataclass
class Line:
    article: str
    colour: str
    size: str
    mrp: str
    qty: int          # CARTONS - the report's Unit column says Carton
    pairs: int
    machine: str = ""
    season: str = ""


def _norm_header(v) -> str:
    """Busy numbers its columns ('7-Item Name'), so strip any leading '<n>-'."""
    return re.sub(r"^\s*\d+\s*[-\s]\s*", "", str(v or "")).strip().lower()


def _qty_score(h: str) -> int:
    """
    Score a header as the CARTON quantity column.

    Exact-name matching is not enough: real exports use 'QTY (CTN)' and 'STOCK QTY (CTN)'.
    Anything counting PAIRS, or holding money or ratios, is disqualified - otherwise
    'QTY (PAIRS)' or a bare 'IN CTN' (an assortment figure) wins over the real column.
    """
    if re.search(r"mrp|cost|gst|ratio|assort|status|match|key|basis|flag|s\.?no", h):
        return 0
    if re.search(r"\bpairs?\b", h):
        return 0
    score = 0
    if re.search(r"\b(qty|quantity|stock|closing|balance|total)\b", h):
        score += 3
    if re.search(r"\b(ctn|ctns|carton|cartons)\b", h):
        score += 2
    return score


def _pick(cols: list[str], names: list[str], pattern: str | None = None) -> str | None:
    for n in names:
        for c in cols:
            if _norm_header(c) == n:
                return c
    if pattern:
        for c in cols:
            if re.search(pattern, _norm_header(c)):
                return c
    return None


def read_grand_total(path: Path) -> int | None:
    """
    The report's own Grand Total, read from the GROUPED sheet.

    The parse below reads the flat sheet, so this is an independent check of the same
    stock. A workbook also holds small working sheets that print their own totals, so each
    sheet is tallied separately and the largest Grand Total is taken as the report's.
    """
    import openpyxl

    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    best = None
    for ws in wb.worksheets:
        for row in ws.iter_rows(values_only=True):
            cells = [str(c).strip() if c is not None else "" for c in row]
            if not any(re.fullmatch(r"(?i)grand\s+total", c) for c in cells):
                continue
            nums = [int(float(c)) for c in cells if re.fullmatch(r"-?\d+(\.\d+)?", c)]
            if nums:
                total = max(nums)
                best = total if best is None else max(best, total)
    wb.close()
    return best


def parse_stock(path: Path) -> list[Line]:
    """
    Read every sheet, keep the one yielding the most stock that also parses cleanly.

    Two row types are dropped:
      * anything containing the word 'Total'  - Busy's labelled subtotals
      * a row whose ONLY populated cell is the quantity - Busy's UNLABELLED subtotal

    The second test must be 'every other column is empty', never 'no size': Size is a
    grouped column, so a genuine line carrying a second MRP under the same size also has
    an empty Size cell. Keying on size alone silently deletes real stock.
    """
    import pandas as pd

    sheets = pd.read_excel(path, sheet_name=None, header=None, dtype=object)
    best: list[Line] = []

    for name, raw in sheets.items():
        if raw.empty:
            continue
        # locate the header row: needs an article column and a quantity column
        header_row = None
        for i in range(min(30, len(raw))):
            cells = [_norm_header(v) for v in raw.iloc[i].tolist()]
            has_art = any(c in ("item name", "article name", "article", "item", "sku", "item sku code") for c in cells)
            if has_art and any(_qty_score(c) > 0 for c in cells):
                header_row = i
                break
        if header_row is None:
            continue

        df = pd.read_excel(path, sheet_name=name, header=header_row, dtype=object)
        df = df.dropna(axis=1, how="all")
        cols = [str(c) for c in df.columns]

        art_col = _pick(cols, ["item name", "article name", "article", "item", "sku", "item sku code"])
        qty_col = max(cols, key=lambda c: _qty_score(_norm_header(c)))
        if not art_col or _qty_score(_norm_header(qty_col)) == 0:
            continue
        col_col = _pick(cols, ["colour", "color"], r"\bcolou?r\b")
        size_col = _pick(cols, ["size"], r"\bsize\b")
        mrp_col = _pick(cols, ["mrp"], r"\bmrp\b")
        ppc_col = _pick(cols, ["pair", "pairs"], r"\bpairs?\b\s*[/\-]?\s*(per\s*)?\b(ctn|carton)\b")
        prs_col = next((c for c in cols if re.search(r"\b(qty|quantity|stock)\b.*\bpairs?\b", _norm_header(c))), None)
        mach_col = _pick(cols, ["machine"])
        seas_col = _pick(cols, ["season"])

        def num(v) -> int:
            s = re.sub(r"[^0-9\-]", "", str(v if v is not None else ""))
            return int(s) if s and s not in ("-",) else 0

        def blank(v) -> bool:
            return str(v).strip() in ("", "nan", "None", "NaT")

        lines: list[Line] = []
        # grouped reports leave repeated cells empty - carry the last value down
        last = {"art": "", "col": "", "size": "", "mrp": "", "mach": "", "seas": ""}

        for _, r in df.iterrows():
            values = {c: r[c] for c in cols}
            if any(re.search(r"\btotal\b", str(v), re.I) for v in values.values()):
                continue
            qty = num(values[qty_col])
            if qty > 0 and all(blank(v) for c, v in values.items() if c != qty_col):
                continue                                   # unlabelled subtotal line

            if mach_col and not blank(values[mach_col]):
                last["mach"] = str(values[mach_col]).strip().upper()
            if seas_col and not blank(values[seas_col]):
                last["seas"] = str(values[seas_col]).strip().upper()
            if not blank(values[art_col]):
                last["art"] = str(values[art_col]).strip()
            if col_col and not blank(values[col_col]):
                last["col"] = str(values[col_col]).strip()
            if size_col and not blank(values[size_col]):
                last["size"] = str(values[size_col]).strip()
            if mrp_col and not blank(values[mrp_col]):
                last["mrp"] = str(values[mrp_col]).strip()

            if not last["art"] or qty <= 0:
                continue

            if prs_col and num(values[prs_col]) > 0:
                pairs = num(values[prs_col])
            elif ppc_col:
                pairs = qty * num(values[ppc_col])
            else:
                pairs = 0

            lines.append(Line(last["art"], last["col"] or "—", last["size"] or "—",
                              last["mrp"], qty, pairs, last["mach"], last["seas"]))

        if sum(l.qty for l in lines) > sum(l.qty for l in best):
            best = lines

    if not best:
        raise SystemExit(f"No sheet in {path.name} produced any stock rows.")
    return best


# ---------------------------------------------------------------------------------------
# Article model
# ---------------------------------------------------------------------------------------

@dataclass
class Article:
    name: str
    machine: str = ""
    season: str = ""
    sizes: list[str] = field(default_factory=list)
    # colour -> {size -> cartons}
    colours: dict[str, dict[str, int]] = field(default_factory=dict)
    mrps: set[str] = field(default_factory=set)
    photo: Path | None = None
    photo_level: str = "none"        # colour | article | series | none

    @property
    def cartons(self) -> int:
        return sum(q for row in self.colours.values() for q in row.values())

    @property
    def family(self) -> str:
        return self.name.split("-")[0].strip().upper()

    @property
    def size_ratio(self) -> str:
        """The size run as the distributor reads it, e.g. '4X7 · 5X8 · 6X9'."""
        return " · ".join(self.sizes)


def build_articles(lines: list[Line]) -> dict[str, Article]:
    arts: dict[str, Article] = {}
    for l in lines:
        a = arts.setdefault(l.article, Article(l.article, l.machine, l.season))
        if not a.machine and l.machine:
            a.machine = l.machine
        if not a.season and l.season:
            a.season = l.season
        if l.mrp:
            a.mrps.add(l.mrp)
        if l.size not in a.sizes:
            a.sizes.append(l.size)
        # NOTE: += not =. The same article/colour/size legitimately appears more than once
        # when the report is split by godown or batch; those quantities add.
        a.colours.setdefault(l.colour, {})
        a.colours[l.colour][l.size] = a.colours[l.colour].get(l.size, 0) + l.qty
    for a in arts.values():
        a.sizes.sort()
    return arts


# ---------------------------------------------------------------------------------------
# Photos
# ---------------------------------------------------------------------------------------

def load_photo_index() -> dict[str, str]:
    """
    Parse star-kidz-photo-index.js - keys are 'ARTICLE|COLOUR' and 'ARTICLE'.

    It is a JS file, not JSON, so the object literal is extracted and read as JSON. That
    works because the builder writes plain double-quoted keys and values.
    """
    if not PHOTO_INDEX_JS.exists():
        return {}
    text = PHOTO_INDEX_JS.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"PHOTO_INDEX\s*=\s*(\{.*?\})\s*;", text, re.S)
    if not m:
        return {}
    try:
        return {k.upper(): v for k, v in json.loads(m.group(1)).items()}
    except json.JSONDecodeError:
        return {}


def resolve_photos(arts: dict[str, Article], index: dict[str, str]) -> list[dict]:
    """
    Give each article the most specific photo available and report what it settled for.

    Order: exact article+colour -> article -> any photo of the same series -> none.
    A file named in the index but missing on disk counts as no photo, never a blank box.
    """
    issues: list[dict] = []
    series_photo: dict[str, Path] = {}
    for key, fname in index.items():
        if "|" in key:
            continue
        fam = key.split("-")[0].strip().upper()
        p = PHOTO_DIR / fname
        if fam not in series_photo and p.exists():
            series_photo[fam] = p

    bar = Progress(len(arts), "Resolving photos")
    for a in arts.values():
        chosen, level = None, "none"
        for colour in a.colours:
            f = index.get(f"{a.name}|{colour}".upper())
            if f and (PHOTO_DIR / f).exists():
                chosen, level = PHOTO_DIR / f, "colour"
                break
        if not chosen:
            f = index.get(a.name.upper())
            if f and (PHOTO_DIR / f).exists():
                chosen, level = PHOTO_DIR / f, "article"
        if not chosen and a.family in series_photo:
            chosen, level = series_photo[a.family], "series"

        a.photo, a.photo_level = chosen, level

        for colour, row in a.colours.items():
            key = f"{a.name}|{colour}".upper()
            has_colour_photo = key in index and (PHOTO_DIR / index[key]).exists()
            if not has_colour_photo:
                issues.append({
                    "article": a.name, "colour": colour,
                    "size_ratio": " ".join(sorted(row)),
                    "cartons": sum(row.values()),
                    "photo_used": a.photo.name if a.photo else "",
                    "photo_level": level,
                    "issue": "no colour-specific photo" if level != "none" else "no photo at all",
                })
        bar.step()
    bar.done()
    return issues


# ---------------------------------------------------------------------------------------
# Snapshots and movement
# ---------------------------------------------------------------------------------------

def snapshot_path(d: date) -> Path:
    return SNAPSHOT_DIR / f"stock-{d:%Y-%m-%d}.json"


def save_snapshot(d: date, arts: dict[str, Article]) -> None:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"date": f"{d:%Y-%m-%d}",
               "articles": {n: {"cartons": a.cartons,
                                "colours": {c: dict(r) for c, r in a.colours.items()}}
                            for n, a in arts.items()}}
    snapshot_path(d).write_text(json.dumps(payload, indent=1), encoding="utf-8")


def previous_snapshot(before: date) -> dict | None:
    if not SNAPSHOT_DIR.exists():
        return None
    best, best_d = None, None
    for p in SNAPSHOT_DIR.glob("stock-*.json"):
        m = re.search(r"stock-(\d{4})-(\d{2})-(\d{2})\.json", p.name)
        if not m:
            continue
        d = date(*(int(g) for g in m.groups()))
        if d < before and (best_d is None or d > best_d):
            best, best_d = p, d
    if not best:
        return None
    try:
        return json.loads(best.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def movement(prev: dict | None, arts: dict[str, Article]) -> dict:
    """
    What changed since the previous snapshot. Today REPLACES yesterday - see the module
    docstring. Yesterday exists here only to explain the difference.
    """
    if not prev:
        return {"from": None, "sold": 0, "added": 0, "new": [], "gone": []}
    old = prev.get("articles", {})
    sold = added = 0
    for name, a in arts.items():
        delta = a.cartons - old.get(name, {}).get("cartons", 0)
        if delta > 0:
            added += delta
        else:
            sold += -delta
    for name, o in old.items():
        if name not in arts:
            sold += o.get("cartons", 0)
    return {"from": prev.get("date"),
            "sold": sold, "added": added,
            "new": sorted(n for n in arts if n not in old),
            "gone": sorted(n for n in old if n not in arts)}


# ---------------------------------------------------------------------------------------
# PDF
# ---------------------------------------------------------------------------------------

def build_pdf(out: Path, stock_day: date, arts: dict[str, Article], move: dict) -> None:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas
    from reportlab.lib.utils import ImageReader

    PAGE_W, PAGE_H = A4
    M = 12 * mm
    HEADER_H, FOOTER_H = 20 * mm, 10 * mm
    GUT = 6 * mm

    grid_w = PAGE_W - 2 * M
    grid_h = PAGE_H - 2 * M - HEADER_H - FOOTER_H
    card_w = (grid_w - GUT * (CARDS_ACROSS - 1)) / CARDS_ACROSS
    card_h = (grid_h - GUT * (CARDS_DOWN - 1)) / CARDS_DOWN
    per_page = CARDS_ACROSS * CARDS_DOWN

    ordered = sorted(arts.values(), key=lambda a: (a.family, a.name))
    total_ctn = sum(a.cartons for a in ordered)
    pages = (len(ordered) + per_page - 1) // per_page

    c = canvas.Canvas(str(out), pagesize=A4)
    c.setTitle(f"STAR Kidz Distributor Catalogue - {stock_day:%d %b %Y}")

    def header(page_no: int) -> None:
        c.setFillColor(colors.HexColor("#0c1733"))
        c.rect(M, PAGE_H - M - HEADER_H, grid_w, HEADER_H, fill=1, stroke=0)
        c.setFillColor(colors.white)
        c.setFont("Helvetica-Bold", 13)
        c.drawString(M + 5 * mm, PAGE_H - M - 8 * mm, "STAR KIDZ - DISTRIBUTOR CATALOGUE")
        c.setFont("Helvetica", 8)
        c.drawString(M + 5 * mm, PAGE_H - M - 14 * mm,
                     f"Stock as on {stock_day:%d %b %Y}   |   {total_ctn:,} cartons   |   {len(ordered)} articles")
        c.setFont("Helvetica", 8)
        c.drawRightString(M + grid_w - 5 * mm, PAGE_H - M - 14 * mm, f"Page {page_no} of {pages}")

    def footer() -> None:
        c.setFillColor(colors.HexColor("#94a3b8"))
        c.setFont("Helvetica", 7)
        c.drawString(M, M - 2 * mm,
                     "Quantities are CARTONS. Availability changes daily - confirm before ordering.")
        c.drawRightString(M + grid_w, M - 2 * mm, f"Generated {datetime.now():%d %b %Y %H:%M}")

    def draw_card(a: Article, x: float, y: float) -> None:
        """One article. The photo sits in a FIXED box so cards line up across the grid."""
        c.setStrokeColor(colors.HexColor("#e2e8f0"))
        c.setLineWidth(0.6)
        c.roundRect(x, y, card_w, card_h, 2 * mm, fill=0, stroke=1)

        pad = 3 * mm
        img_h = card_h * 0.42
        img_x, img_y = x + pad, y + card_h - pad - img_h
        img_w = card_w - 2 * pad

        # Aspect-preserving fit, centred in its box. Never stretched, never overflowing
        # into the next card - that is what makes the grid read cleanly.
        if a.photo and a.photo.exists():
            try:
                ir = ImageReader(str(a.photo))
                iw, ih = ir.getSize()
                scale = min(img_w / iw, img_h / ih)
                dw, dh = iw * scale, ih * scale
                c.drawImage(ir, img_x + (img_w - dw) / 2, img_y + (img_h - dh) / 2,
                            width=dw, height=dh, mask="auto")
            except Exception:
                a.photo = None
        if not a.photo:
            c.setFillColor(colors.HexColor("#f1f5f9"))
            c.rect(img_x, img_y, img_w, img_h, fill=1, stroke=0)
            c.setFillColor(colors.HexColor("#94a3b8"))
            c.setFont("Helvetica-Oblique", 8)
            c.drawCentredString(img_x + img_w / 2, img_y + img_h / 2, "NO PHOTO")

        ty = img_y - 5 * mm
        c.setFillColor(colors.HexColor("#0f172a"))
        c.setFont("Helvetica-Bold", 10)
        c.drawString(x + pad, ty, a.name[:28])

        c.setFont("Helvetica", 7)
        c.setFillColor(colors.HexColor("#64748b"))
        mrp = ("MRP " + "/".join(sorted(a.mrps, key=lambda v: float(v or 0)))) if a.mrps else ""
        c.drawString(x + pad, ty - 4 * mm, f"{a.machine or '-'} | {mrp}"[:44])
        c.drawString(x + pad, ty - 7.5 * mm, f"Size ratio: {a.size_ratio}"[:52])
        c.setFillColor(colors.HexColor("#059669"))
        c.setFont("Helvetica-Bold", 8)
        c.drawRightString(x + card_w - pad, ty, f"{a.cartons:,} ctn")

        # colour x size table
        th_y = ty - 12 * mm
        sizes = a.sizes[:6]
        col_w = 15 * mm
        name_w = card_w - 2 * pad - col_w * len(sizes)
        c.setFont("Helvetica-Bold", 6.5)
        c.setFillColor(colors.HexColor("#475569"))
        c.drawString(x + pad, th_y, "COLOUR")
        for i, s in enumerate(sizes):
            c.drawCentredString(x + pad + name_w + col_w * i + col_w / 2, th_y, s[:7])

        c.setFont("Helvetica", 7)
        row_y = th_y - 4 * mm
        # tallest colours first - a distributor scanning the page sees the depth first
        for colour, row in sorted(a.colours.items(), key=lambda kv: -sum(kv[1].values())):
            if row_y < y + pad:
                c.setFillColor(colors.HexColor("#94a3b8"))
                c.setFont("Helvetica-Oblique", 6.5)
                c.drawString(x + pad, row_y + 1 * mm, "... more colours in stock")
                break
            c.setFillColor(colors.HexColor("#0f172a"))
            c.drawString(x + pad, row_y, colour[:14])
            for i, s in enumerate(sizes):
                q = row.get(s, 0)
                c.setFillColor(colors.HexColor("#0f172a") if q else colors.HexColor("#cbd5e1"))
                c.drawCentredString(x + pad + name_w + col_w * i + col_w / 2, row_y, str(q) if q else "-")
            row_y -= 3.6 * mm

    bar = Progress(len(ordered), "Laying out pages")
    for i, a in enumerate(ordered):
        slot = i % per_page
        if slot == 0:
            if i:
                footer()
                c.showPage()
            header(i // per_page + 1)
        col, row = slot % CARDS_ACROSS, slot // CARDS_ACROSS
        x = M + col * (card_w + GUT)
        y = PAGE_H - M - HEADER_H - (row + 1) * card_h - row * GUT
        draw_card(a, x, y)
        bar.step()
    bar.done()

    footer()
    c.showPage()

    # closing summary page - what moved since the previous snapshot
    c.setFont("Helvetica-Bold", 13)
    c.setFillColor(colors.HexColor("#0f172a"))
    c.drawString(M, PAGE_H - M - 10 * mm, "Stock movement")
    c.setFont("Helvetica", 9)
    yy = PAGE_H - M - 20 * mm
    if move["from"]:
        for label, value in [
            ("Compared with", move["from"]),
            ("Cartons dispatched / reduced", f"{move['sold']:,}"),
            ("Cartons added", f"{move['added']:,}"),
            ("New articles", str(len(move["new"]))),
            ("No longer in stock", str(len(move["gone"]))),
        ]:
            c.drawString(M, yy, f"{label}: {value}")
            yy -= 6 * mm
        c.setFont("Helvetica", 7.5)
        c.setFillColor(colors.HexColor("#64748b"))
        for label, names in (("New", move["new"]), ("Gone", move["gone"])):
            if names:
                yy -= 3 * mm
                c.drawString(M, yy, f"{label}: " + ", ".join(names[:40])
                             + (f" ... +{len(names) - 40} more" if len(names) > 40 else ""))
                yy -= 5 * mm
    else:
        c.drawString(M, yy, "No previous snapshot - this is the first run, so nothing to compare against.")
    c.showPage()
    c.save()


# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Build the STAR Kidz distributor catalogue PDF.")
    ap.add_argument("--file", help="stock workbook; otherwise the newest STOCK-DD-MM-YYYY.xlsx is used")
    ap.add_argument("--out", help="output PDF path")
    ap.add_argument("--merge-mode", choices=["snapshot", "sum"], default="snapshot",
                    help="snapshot (default, correct): today replaces yesterday. "
                         "sum: add yesterday to today - only for separately exported warehouses")
    ap.add_argument("--no-verify", action="store_true", help="skip the Grand Total check")
    args = ap.parse_args()

    path, stock_day = find_stock_file(args.file)
    say(f"report : {path.name}  (stock as on {stock_day:%d %b %Y})")

    say("parsing...")
    lines = parse_stock(path)
    parsed = sum(l.qty for l in lines)
    say(f"parsed : {parsed:,} cartons over {len(lines):,} rows")

    # The gate. A catalogue that disagrees with the report goes out to distributors as a
    # PDF, so it must not be built at all rather than built and quietly wrong.
    if not args.no_verify:
        grand = read_grand_total(path)
        if grand is None:
            say("WARNING: this workbook prints no Grand Total, so the parse could not be verified.")
        elif grand != parsed:
            say(f"VERIFY FAILED: parsed {parsed:,} ctn but the report's Grand Total says {grand:,} ctn.")
            if parsed == grand * 2:
                say("The parse is exactly double the report - the sheet is carrying subtotal lines.")
            say("Nothing was built.")
            return 1
        else:
            say(f"verified: {parsed:,} ctn matches the report's Grand Total exactly.")

    arts = build_articles(lines)

    prev = previous_snapshot(stock_day)
    if args.merge_mode == "sum" and prev:
        say("WARNING: --merge-mode sum adds yesterday's cartons to today's. On two snapshots "
            "of the same warehouse this double-counts. Continuing because you asked for it.")
        for name, o in prev.get("articles", {}).items():
            a = arts.setdefault(name, Article(name))
            for colour, row in o.get("colours", {}).items():
                a.colours.setdefault(colour, {})
                for size, q in row.items():
                    a.colours[colour][size] = a.colours[colour].get(size, 0) + q
                    if size not in a.sizes:
                        a.sizes.append(size)

    index = load_photo_index()
    if not index:
        say(f"WARNING: no photo index at {PHOTO_INDEX_JS} - the catalogue will have no photos.")
    issues = resolve_photos(arts, index)

    levels: dict[str, int] = {}
    for a in arts.values():
        levels[a.photo_level] = levels.get(a.photo_level, 0) + 1
    say("photos : " + ", ".join(f"{k}={v}" for k, v in sorted(levels.items())))

    move = movement(prev, arts)
    if move["from"]:
        say(f"movement vs {move['from']}: -{move['sold']:,} dispatched, +{move['added']:,} added, "
            f"{len(move['new'])} new, {len(move['gone'])} gone")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out = Path(args.out) if args.out else OUTPUT_DIR / f"STAR-Kidz-Distributor-Catalogue-{stock_day:%Y-%m-%d}.pdf"
    say(f"building {out.name} ...")
    build_pdf(out, stock_day, arts, move)

    report = out.with_suffix(".verification.csv")
    import csv
    with report.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["article", "colour", "size_ratio", "cartons",
                                           "photo_used", "photo_level", "issue"])
        w.writeheader()
        w.writerows(issues)

    save_snapshot(stock_day, arts)
    say(f"PDF    : {out}")
    say(f"check  : {report.name}  ({len(issues)} article/colour rows without an exact colour photo)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
