# Distributor catalogue PDF (Python)

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
