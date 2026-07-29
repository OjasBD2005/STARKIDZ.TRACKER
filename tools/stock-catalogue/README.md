# Stock Catalogue — regenerating from a new Busy stock report

Rebuilds `star-kidz-stock-catalogue-data.js` (and the `article-photos/` folder)
that powers the **🗂️ Stock Catalogue** view in `star-kidz-production-system.html`.

## Two ways to update stock

**Daily → use the app.** The Stock Catalogue view has an **⬆️ Upload daily stock**
panel: export the Busy stock report as **.xlsx / .csv** and upload it. The app parses
it in the browser (grouped cells filled down, `Total` rows skipped), rebuilds the
catalogue, re-matches photos, updates aging and shows a before/after comparison. The
uploaded sheet supersedes the built-in data file and syncs to other devices via
`STARKIDZ_CATALOGUE_V1`. **↩️ Reset to file** reverts to the built-in build.

**Only a PDF available, or re-baselining the shipped build → run the scripts below.**
The PDF can't be uploaded (its table isn't machine-readable), so a PDF-only report has
to go through `pdftotext` here.

All scripts now take the working directory as `-out <dir>` (or `$env:SC_WORKDIR`)
instead of a hardcoded path:

```bash
export SC_WORKDIR=/path/to/workdir
```

## Stock aging

The Busy report carries no manufacture date, so age can't be read from it. The app
stamps each **article|colour|size** line the first time it is seen holding stock
(`STARKIDZ_CAT_AGING_V1`) and measures age from that stamp to the current report date.
A line that sells out and later returns is treated as a new lot and restarts.
**Aging therefore accrues from the first upload onward** — on a fresh install every
line reads 0 days, and the bands fill in as daily uploads accumulate.

- **Screen** hides aging stock (default: 90+ days) so salespeople only pitch fresh stock.
- **Catalogue PDF and CSV always carry every lot**, with the aging cells shaded
  amber (61–90 d) / red (90+ d) and a totals strip in the header, for internal tracking.

Run the steps below when a **new stock report** arrives as a PDF.

## 1. Export the text layer

The Busy report must be read in *table* mode — plain `-layout` misaligns the
columns and silently mispairs colour/size/quantity.

```bash
pdftotext -table "STOCK-<date>.pdf" stock_table_full.txt
```

`pdftotext` ships with Git for Windows (`C:\Program Files\Git\mingw64\bin`).

## 2. Parse rows

```bash
powershell -File parse_stock.ps1 -out "$SC_WORKDIR"
```

Produces `stock_parsed.csv` (Article, Colour, Size, MRP, SP, Qty, Machine, Season).

**Always check the printed `TOTAL QTY` against the report's own `Grand Total`.**
They matched exactly (16,243) for STOCK-29-07-2026. If they differ, the parse is
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
powershell -File copy_photos.ps1 -out "$SC_WORKDIR"
```

Picks one web-sized image (40–600 KB) per article family from
`Desktop\Article photos` into `article-photos/`, and writes `photomap.json`.
`$alias` maps families whose folder name differs (e.g. `STANLAY` →
`Stanley series`, `TODDLER` → `TOODLER`, school series → `SCHOOL SHOES`).

## 4. Build the data file

```bash
powershell -File build_catalogue.ps1 -out "$SC_WORKDIR"
```

Writes `star-kidz-stock-catalogue-data.js` next to the app. Update the `$stamp`
variable to the new stock date so the catalogue header and FG-stock sync show it.

## 4b. Verify the numbers (do not skip)

```bash
powershell -File verify_stock.ps1 -out "$SC_WORKDIR"
```

Checks the parse against the report's own totals: Grand Total, every machine total,
and every series subtotal. On STOCK-29-07-2026 this gave Grand Total 16,243 = 16,243,
all 5 machine totals matching, and 63/63 real series matching.

Three "differences" it prints are expected naming artifacts, not errors:
- **EVA** is both a machine and a series name, so the two totals get compared to each other.
- **PUB / PUB-CUT** and **FIRE / FIRE BOLT** are separate series in the report, but the
  family label (text before the first `-`) merges them. Quantities are correct.

Traps this check has already caught, all now fixed in `parse_stock.ps1`:
- Series that share a machine's name (the EVA school-shoe series sits under the STUCKON
  machine) mislabelled the machine — machine is now assigned from the report's own
  `<MACHINE> Total` boundaries, each block validated against its printed total.
- Article codes the plain `ARTICLE-NN` pattern misses — `GSD-250/CL`, `LITTLE-1(SHARK)`,
  `KSJ-201(BLK-SOLE)`, `LUKE-4(L)` — and names with no number at all (`SOLDIER`, `STAR`,
  `RABBIT`). Missing one silently rolls its stock onto the previous article. The Item
  Name is now read as the token after the TYPE cell, with the pattern as fallback.

## 4c. Photo index (article + colour)

The article name, colour, sizes and MRP are printed **inside** each catalogue photo, and
the file names don't carry them (there is no EXIF/XMP either). So photos are matched by
reading the image and recording it in `photo_index.csv`:

```
SourceFolder,SourceFile,Article,Colour,Verified
creta,creta (11).jpg,CRETA-3,OLV,yes
```

```bash
powershell -File build_photo_index.ps1
```

Copies each listed photo into `article-photos/` as `ARTICLE__COLOUR.ext` and writes
`star-kidz-photo-index.js`. The catalogue picks the most specific match available:
exact article+colour → article → series photo → placeholder.

**Renaming the source photos to `CRETA-03 OLV.jpg` would remove this step entirely** —
the index could then be built from file names with no image reading.

## 5. Verify in the app

Open the app → **Stock Catalogue**. The green badge should show the new pair
count and article count. Then click **🔄 Sync to FG Stock**.
