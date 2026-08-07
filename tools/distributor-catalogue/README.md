# Distributor catalogue (Python)

Two scripts, different inputs:

| Script | Input | Use when |
|---|---|---|
| `distributor_catalogue.py` | the Busy **stock export** (`.xlsx`) | normal daily catalogue — this is the accurate path |
| `parse_ocr.py` | **OCR text** of an existing catalogue | you only have a scanned/printed catalogue, no source data |

Prefer the xlsx path. OCR is a recovery route: it can only recover what was legible.

## parse_ocr.py — OCR text to catalogue

```bash
pip install anthropic pydantic jinja2 weasyprint
python parse_ocr.py --in ocr.txt --out catalogue.pdf
python parse_ocr.py --in ocr.txt --json-only > catalogue.json
```

Uses `claude-opus-5` with `client.messages.parse()` and the Pydantic schema in the file,
so the API enforces the output shape server-side. Keys are short (`art`, `col`, `sz`,
`ctn`, `mrp`), and boilerplate (`VERTICAL CLOSE`, `PHOTO`, `oldest lot 1 d`, page
furniture) is stripped before the text is sent.

**Where the token savings come from**, largest first: schema-enforced output removes the
"return only JSON" instruction and every parse-failure retry; pre-compression removes a
large share of the characters; short keys save a few tokens per row; `effort: "low"` cuts
thinking spend. Do **not** shrink `max_tokens` to save tokens — a low cap truncates
mid-JSON and costs a whole retry. Chunk with `--chunk-chars` instead.

Output goes through `catalogue_template.html.j2` — A4, photo in a fixed 1:1 box on the
left of the colour×size table, ~6 articles per page. Branding: navy `#1A2B4C`, red
`#E63946`, light grey `#F8F9FA`. Renders with WeasyPrint or Puppeteer.

### What the audit can and cannot check

It verifies internal consistency (duplicate colour rows, non-positive cartons, non-numeric
MRP, size breakdowns with no digits) and whether a photo file exists for that exact
article+colour.

It **cannot** verify that the colour printed *inside* a photo matches its row — that needs
a vision call on the image, not text parsing. Those rows are reported as **shade
unverified** rather than passed, so the gap stays visible.

---

# distributor_catalogue.py — stock export to PDF

Builds an A4 distributor catalogue from the daily Busy stock export: one card per article
with its photo, name, MRP, size ratio and a colour × size carton grid, plus a closing page
showing what moved since the previous snapshot.

> **Untested.** This machine has no Python interpreter, so the script has never been run.
> Everything else in `tools/stock-catalogue/` was verified by execution; this was not.
> Expect to fix something on the first run.

## Install

Python is not installed on this machine. Get it from python.org (tick **Add python.exe to
PATH**) — the `python` that currently answers on the command line is a Microsoft Store
stub that only opens the Store.

```bash
pip install pandas openpyxl reportlab pillow tqdm
```

## Run

```bash
python distributor_catalogue.py                          # newest STOCK-DD-MM-YYYY.xlsx
python distributor_catalogue.py --file STOCK-07-08-2026.xlsx
python distributor_catalogue.py --out "C:\path\catalogue.pdf"
```

It searches the Desktop, Downloads and the app checkout, and picks the newest **stock
date** (not the newest file). Output goes to `Desktop\Distributor Catalogues\`, alongside
a `.verification.csv` listing every article/colour that had no exact colour photo.

## How yesterday and today are combined

Today's quantities **replace** yesterday's. Yesterday is used only to work out what moved.

The Busy report is a complete snapshot of the warehouse, not a day's movement — today's
file already contains everything. Adding yesterday to it counts the same cartons twice,
which is exactly what made the catalogue read 34,474 cartons against a Grand Total of
17,237. An article dispatched yesterday is simply absent from today's file and drops out
on its own; that is intended, not data loss.

`--merge-mode sum` does add them, for the case of two warehouses exported separately. It
warns loudly, because on two snapshots of the same warehouse it is always wrong.

Snapshots are kept as one JSON per stock date in `CLAUDE DATA\stock-snapshots\`.

## The Grand Total gate

Before anything is built, the parse is checked against the report's own Grand Total, read
from the grouped sheet. On a mismatch nothing is written — a catalogue that disagrees with
the report goes to distributors as a PDF, so it must not be built at all rather than built
and quietly wrong. `--no-verify` skips this; don't.

## What "verify the photos" does and does not do

It confirms every article/colour in stock resolves to a file that **exists on disk**, and
records what each card settled for: exact `article+colour`, then `article`, then a series
photo, then none. Missing files count as no photo rather than a blank box.

It does **not** read pixels, so it cannot confirm a photo labelled `BLK` shows a black
shoe — the colour is only ever taken from the file name. Most archive photos carry no
colour in their name, which is why so many cards fall back to an article-level photo. To
fix one, rename it `ARTICLE COLOUR.jpg` into `tools/stock-catalogue/named-photos/`.

## Overlap with what already exists

The app (`star-kidz-production-system.html`) already generates a Distributor PDF, and
`tools/stock-catalogue/` already rebuilds the catalogue data from the same report. This
script is a third path to a similar output. Worth consolidating rather than maintaining
all three.
