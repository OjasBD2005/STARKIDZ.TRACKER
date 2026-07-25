# Stock Catalogue — regenerating from a new Busy stock report

Rebuilds `star-kidz-stock-catalogue-data.js` (and the `article-photos/` folder)
that powers the **🗂️ Stock Catalogue** view in `star-kidz-production-system.html`.

Run these when a **new stock report** arrives.

## 1. Export the text layer

The Busy report must be read in *table* mode — plain `-layout` misaligns the
columns and silently mispairs colour/size/quantity.

```bash
pdftotext -table "STOCK-<date>.pdf" stock_table_full.txt
```

`pdftotext` ships with Git for Windows (`C:\Program Files\Git\mingw64\bin`).

## 2. Parse rows

```bash
powershell -File parse_stock.ps1
```

Produces `stock_parsed.csv` (Article, Colour, Size, MRP, SP, Qty, Machine, Season).

**Always check the printed `TOTAL QTY` against the report's own `Grand Total`.**
They matched exactly (15,944) for STOCK-25-07-2026. If they differ, the parse is
wrong — do not ship it.

Notes on the report's quirks, all handled:
- Column x-positions **drift between pages**, so rows are parsed from the right
  (the `MRP SP QTY` tail is stable) rather than by fixed slicing.
- Grouped cells are blank on continuation rows and are forward-filled.
- Sizes appear as `6X9`, `6X9K`, `8K`, `8 NO` and bare `5` — all recognised.
- Some rows have a blank MRP; the previous MRP is inherited.
- Subtotal / `Grand Total` lines are excluded.

## 3. Copy photos

```bash
powershell -File copy_photos.ps1
```

Picks one web-sized image (40–600 KB) per article family from
`Desktop\Article photos` into `article-photos/`, and writes `photomap.json`.
`$alias` maps families whose folder name differs (e.g. `STANLAY` →
`Stanley series`, `TODDLER` → `TOODLER`, school series → `SCHOOL SHOES`).

## 4. Build the data file

```bash
powershell -File build_catalogue.ps1
```

Writes `star-kidz-stock-catalogue-data.js` next to the app. Update the `$stamp`
variable to the new stock date so the catalogue header and FG-stock sync show it.

## 5. Verify in the app

Open the app → **Stock Catalogue**. The green badge should show the new pair
count and article count. Then click **🔄 Sync to FG Stock**.
