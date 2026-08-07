#!/usr/bin/env python3
"""
STAR Kidz — OCR catalogue text -> minimal JSON -> printable distributor catalogue.

    python parse_ocr.py --in ocr.txt --out catalogue.pdf
    python parse_ocr.py --in ocr.txt --out catalogue.html --no-pdf
    python parse_ocr.py --in ocr.txt --json-only > catalogue.json

Install once:

    pip install anthropic pydantic jinja2 weasyprint

--------------------------------------------------------------------------------------
TOKEN EFFICIENCY — WHERE THE SAVINGS ACTUALLY COME FROM

Ranked by how much they save, largest first:

 1. SCHEMA-ENFORCED OUTPUT (biggest win, and it is free).
    `client.messages.parse()` with `output_config` makes the API constrain the response
    to the Pydantic schema server-side. That removes, in one step: the "output only JSON,
    no preamble, no post-amble" instruction, every retry after a malformed parse, and any
    JSON-repair code. A prompt-only approach pays those tokens on every failure and has
    no upper bound on retries.

 2. PRE-COMPRESSION (large, and it costs nothing at inference time).
    Strip the boilerplate before it is ever sent: "VERTICAL CLOSE", "EVA OPEN", "PHOTO",
    "oldest lot 1 d", repeated headers and page furniture. On a real catalogue page this
    is a large share of the characters and none of the information.

 3. SHORT KEYS (small, but free).
    art / col / sz / ctn / mrp instead of the long names — a few tokens per item, which
    adds up across hundreds of rows.

 4. LOW EFFORT (moderate).
    Extraction is not an intelligence-sensitive task. `effort: "low"` cuts thinking spend
    with no measurable accuracy loss here.

A note on what NOT to do for token efficiency: do not shrink `max_tokens` to force
brevity. The output length is set by how many rows the page holds, and a low cap
truncates mid-JSON — which costs a whole retry and is strictly worse than the tokens it
saved. Chunk the input instead; that is what --chunk-chars does.
--------------------------------------------------------------------------------------
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------------------
# Schema — short keys, as requested. These names go on the wire in every response.
# ---------------------------------------------------------------------------------------


class Item(BaseModel):
    """One colour line of one article."""

    col: str = Field(description="Colour code exactly as printed, e.g. B.PNK, DGR, R.GOLD")
    sz: str = Field(description="Size breakdown, e.g. '4X7:9 5X8:20 6X9:9'. Empty if absent.")
    ctn: int = Field(description="Cartons in stock for this colour")
    mrp: str = Field(description="MRP or MRP range as printed, e.g. '429.99' or '419.99-429.99'")


class ArticleGroup(BaseModel):
    art: str = Field(description="Article name, e.g. ALIA-04")
    cat: str = Field(default="", description="Category/series, e.g. ALIA. Empty if absent.")
    items: list[Item]


class Catalogue(BaseModel):
    catalog: list[ArticleGroup]


# ---------------------------------------------------------------------------------------
# Prompt — 47 words. The schema does the specification work, so the prompt does not
# repeat field names, types, or "return only JSON": all three are enforced server-side.
# ---------------------------------------------------------------------------------------

SYSTEM_PROMPT = (
    "Extract footwear catalogue rows from OCR text. One group per article; one item per "
    "colour. Copy colours, sizes and MRP exactly as printed - never normalise spelling or "
    "round prices. Cartons are integers. Omit total and subtotal rows. Omit anything you "
    "cannot read rather than guessing."
)

# Boilerplate that carries no information. Stripped before the text is sent.
NOISE = re.compile(
    r"""(?ix)
    \b(VERTICAL|EVA|PU|ROTARY|STUCKON|AIR|OUT\s?SIDE)\s+(CLOSE|OPEN)\b
  | \bPHOTO\b
  | \boldest\s+lot\s+\d+\s*d\b
  | \bstock\s+as\s+on\b
  | \bcolour[- ]matched\s+photos?\b
  | \bArticle\s+/\s+Colour\s+/\s+Size\b
  | \bOjas\s+Footwear\s+India\s+Pvt\.?\s+Ltd\.?\b
  | \bPage\s+\d+\s+of\s+\d+\b
  | \bGenerated\s+\d.*$
    """,
    re.MULTILINE,
)


def compress(text: str) -> str:
    """Strip boilerplate and collapse whitespace. Pure text work — costs no tokens."""
    text = NOISE.sub(" ", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return "\n".join(line.strip() for line in text.splitlines() if line.strip())


def chunks(text: str, limit: int) -> list[str]:
    """Split on blank lines, never mid-row, so no article is cut in half."""
    if len(text) <= limit:
        return [text]
    out, cur = [], ""
    for para in text.split("\n\n"):
        if cur and len(cur) + len(para) + 2 > limit:
            out.append(cur)
            cur = para
        else:
            cur = f"{cur}\n\n{para}" if cur else para
    if cur:
        out.append(cur)
    return out


def parse_catalogue(raw_ocr_text: str, chunk_chars: int = 12000) -> Catalogue:
    """OCR text -> validated Catalogue. Groups are merged across chunks by article name."""
    import anthropic

    client = anthropic.Anthropic()
    text = compress(raw_ocr_text)
    parts = chunks(text, chunk_chars)

    merged: dict[str, ArticleGroup] = {}
    for i, part in enumerate(parts, 1):
        print(f"  parsing chunk {i}/{len(parts)} ({len(part):,} chars)...", file=sys.stderr)
        # NOTE ON FALLBACKS: for claude-opus-5 the recommended default is the server-side
        # `fallbacks` parameter, which re-runs a policy-declined request on another model.
        # It lives on client.beta.messages, while .parse() (schema enforcement) lives on
        # client.messages — so the two can't be combined in one call. Schema enforcement is
        # the bigger win for extraction, and a footwear catalogue carries no refusal risk,
        # so .parse() wins here. If you ever need both, drop to client.beta.messages.create
        # with output_config.format plus fallbacks="default".
        response = client.messages.parse(
            model="claude-opus-5",
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            output_format=Catalogue,
            output_config={"effort": "low"},   # extraction is not intelligence-sensitive
            messages=[{"role": "user", "content": part}],
        )
        result = response.parsed_output
        if result is None:                     # refusal or truncation — never silently skip
            raise SystemExit(
                f"Chunk {i} returned no parsed output (stop_reason="
                f"{response.stop_reason!r}). Lower --chunk-chars and retry."
            )
        for group in result.catalog:
            if group.art in merged:
                merged[group.art].items.extend(group.items)
            else:
                merged[group.art] = group

    return Catalogue(catalog=[merged[k] for k in sorted(merged)])


# ---------------------------------------------------------------------------------------
# Audit — what text can actually verify
# ---------------------------------------------------------------------------------------

APP_DIR = Path(r"C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA")
PHOTO_DIR = APP_DIR / "article-photos"
PHOTO_INDEX_JS = APP_DIR / "star-kidz-photo-index.js"


def load_photo_index() -> dict[str, str]:
    """ARTICLE and ARTICLE|COLOUR -> filename, from the app's generated index."""
    if not PHOTO_INDEX_JS.exists():
        return {}
    m = re.search(r"PHOTO_INDEX\s*=\s*(\{.*?\})\s*;", PHOTO_INDEX_JS.read_text("utf-8", "replace"), re.S)
    if not m:
        return {}
    try:
        return {k.upper(): v for k, v in json.loads(m.group(1)).items()}
    except json.JSONDecodeError:
        return {}


def audit(cat: Catalogue, index: dict[str, str]) -> list[dict]:
    """
    Cross-checks that are possible from text, plus an explicit note for the one that is not.

    Verifiable here: article/colour/size/MRP internal consistency, duplicate colour rows,
    non-positive cartons, and whether a photo file for that exact article+colour exists.

    NOT verifiable here: whether the colour printed inside the photo matches the row. That
    needs a vision call on the image itself; OCR text of the page cannot answer it. Rows
    that resolve only to an article-level photo are reported as 'shade unverified' rather
    than passed, so the gap is visible instead of implied.
    """
    findings: list[dict] = []
    for g in cat.catalog:
        seen: set[str] = set()
        for it in g.items:
            where = f"{g.art} / {it.col}"
            if it.col in seen:
                findings.append({"article": g.art, "colour": it.col, "issue": "duplicate colour row", "detail": where})
            seen.add(it.col)

            if it.ctn <= 0:
                findings.append({"article": g.art, "colour": it.col, "issue": "cartons not positive", "detail": str(it.ctn)})

            if it.mrp and not re.fullmatch(r"[\d.]+(\s*[-–]\s*[\d.]+)?", it.mrp.strip()):
                findings.append({"article": g.art, "colour": it.col, "issue": "MRP not numeric", "detail": it.mrp})

            if it.sz and not re.search(r"\d", it.sz):
                findings.append({"article": g.art, "colour": it.col, "issue": "size breakdown has no digits", "detail": it.sz})

            key = f"{g.art}|{it.col}".upper()
            if key in index and (PHOTO_DIR / index[key]).exists():
                pass                                        # exact colour photo on disk
            elif g.art.upper() in index:
                findings.append({
                    "article": g.art, "colour": it.col,
                    "issue": "shade unverified — article photo only",
                    "detail": "no photo of this colour; the image shown is the article's own. "
                              "Confirming the printed shade requires reading the image, not the text.",
                })
            else:
                findings.append({"article": g.art, "colour": it.col, "issue": "no photo at all", "detail": ""})
    return findings


# ---------------------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------------------

def render_html(cat: Catalogue, findings: list[dict], stock_date: str) -> str:
    from jinja2 import Environment, FileSystemLoader, select_autoescape

    env = Environment(
        loader=FileSystemLoader(str(Path(__file__).parent)),
        autoescape=select_autoescape(["html"]),
    )
    index = load_photo_index()

    def photo_for(art: str, colours: list[str]) -> str:
        for c in colours:
            f = index.get(f"{art}|{c}".upper())
            if f and (PHOTO_DIR / f).exists():
                return (PHOTO_DIR / f).as_uri()
        f = index.get(art.upper())
        return (PHOTO_DIR / f).as_uri() if f and (PHOTO_DIR / f).exists() else ""

    groups = [{
        "art": g.art,
        "cat": g.cat,
        "items": g.items,
        "total": sum(i.ctn for i in g.items),
        "photo": photo_for(g.art, [i.col for i in g.items]),
    } for g in cat.catalog]

    return env.get_template("catalogue_template.html.j2").render(
        groups=groups,
        findings=findings,
        stock_date=stock_date,
        generated=datetime.now().strftime("%d %b %Y %H:%M"),
        total_ctn=sum(g["total"] for g in groups),
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="OCR catalogue text -> distributor catalogue PDF.")
    ap.add_argument("--in", dest="src", required=True, help="file containing the raw OCR text")
    ap.add_argument("--out", default="distributor-catalogue.pdf")
    ap.add_argument("--stock-date", default=datetime.now().strftime("%Y-%m-%d"))
    ap.add_argument("--chunk-chars", type=int, default=12000)
    ap.add_argument("--json-only", action="store_true", help="print the JSON payload and stop")
    ap.add_argument("--no-pdf", action="store_true", help="write HTML instead of rendering a PDF")
    args = ap.parse_args()

    raw = Path(args.src).read_text("utf-8", "replace")
    print(f"[{datetime.now():%H:%M:%S}] input {len(raw):,} chars -> "
          f"{len(compress(raw)):,} after compression", file=sys.stderr)

    cat = parse_catalogue(raw, args.chunk_chars)
    print(f"[{datetime.now():%H:%M:%S}] {len(cat.catalog)} articles, "
          f"{sum(len(g.items) for g in cat.catalog)} colour rows", file=sys.stderr)

    if args.json_only:
        print(cat.model_dump_json(indent=1))
        return 0

    findings = audit(cat, load_photo_index())
    print(f"[{datetime.now():%H:%M:%S}] audit: {len(findings)} finding(s)", file=sys.stderr)

    html = render_html(cat, findings, args.stock_date)
    out = Path(args.out)
    if args.no_pdf or out.suffix.lower() == ".html":
        out.write_text(html, encoding="utf-8")
    else:
        from weasyprint import HTML
        HTML(string=html, base_url=str(Path.cwd())).write_pdf(str(out))
    print(f"[{datetime.now():%H:%M:%S}] wrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
