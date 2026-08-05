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

## The report counts CARTONS, not pairs

The Grand Total of 17,055 on STOCK-04-08-2026 is **17,055 cartons** — the export's own
`Unit` column says `Carton`. Pairs come from the `Pair` column (pairs per carton), which
runs 24–36 and **varies by size**, so no single multiplier is right: pairs are summed
line by line. The same report is **493,184 pairs**.

Everything downstream carries both — `q`/`t` are cartons, `p`/`tp` are pairs — and the
catalogue grid shows a **Ctn** and a **Prs** column side by side. Read a bare number in
this report as cartons unless it says otherwise.

## 0. Prefer the Excel export over the PDF

```bash
powershell -File parse_stock_xlsx.ps1 -out "$SC_WORKDIR" -file "STOCK-<date>.xlsx"
```

Busy's **detailed Excel export is the accurate source** and should be used whenever it
is available. It is one flat row per item with its own columns, so there is no column
drift, no grouped cells and no subtotal lines — and it carries the **full item name**
and the real **machine** column.

The PDF route is lossy in a way its own totals cannot reveal. On STOCK-04-08-2026 both
routes totalled exactly 17,055, yet the PDF produced 438 articles against the Excel's
451, because a name split across table cells reads back as its first word only:

| PDF read it as | it is really |
|---|---|
| `STAR` (1,523 prs in one lump) | 10 school-shoe articles — `STAR GOLA-L` 249, `STAR BOY DLX-L` 368, `STAR GIRL BUCKLE PLAIN` 239, … |
| `BOLT-06`, `BOLT-104`, `BOLT-155` | `FIRE BOLT-06`, `FIRE BOLT-104`, `FIRE BOLT-155` |
| `CANDY-11` (87) | `CANDY-11` (56) + `CANDY-11 L` (31) |
| `DIYA-02` (29) | `DIYA-02` (15) + `DIYA-02 PLUS` (14) |
| `ITALY-01` (104) | `ITALY-01` (87) + `ITALY-01 7X10` (17) |

The PDF also has no machine column of its own — machines are inferred from block
totals, which folded `OUT SIDE` (95 prs) into EVA and `AIR` (1) into ROTARY.

Busy numbers the export's column headers (`7-Item Name`, `9-Colour`, `14 STOCK`), and
the workbook holds several sheets — the stock report is **not** the first one. Both the
script and the in-app uploader strip the `<n>-` prefix and try every sheet until one
parses.

Use the PDF route below only when no Excel export exists.

## 1. Export the text layer (PDF route only)

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

## 3. Copy photos — superseded

**Use `build_photos_from_zip.ps1` (section 3–4c below) instead.** `copy_photos.ps1`
predates the named photo archive: it only picks one photo per *series* out of the
loose `Desktop\Article photos` folders, so it can't tell one article from another
and never produces a colour match. Kept only for those older folders.

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

## 3–4c. Photos and the photo index — from a named archive

Since **2026-08-04** the photos come from an archive whose **file names carry the
article and the colour** (`ALL PHOTOS/AIR/AIR-2010 BLK-BLK-WHT.jpeg`). That is the
"quick win" the older notes asked for, so steps 3 and 4c are now one command that
reads no images at all:

```bash
powershell -File build_photos_from_zip.ps1 -out "$SC_WORKDIR" -zip "C:\path\ALL PHOTOS 1.zip"
```

It wipes and rebuilds `article-photos/`, and writes `star-kidz-photo-index.js` plus
`photomap.json` (the series photos `build_catalogue.ps1` needs). Images are resized to
1000 px on the longest side at JPEG q80 — 3,435 source photos (350 MB) reduce to the
~500 the current stock actually needs, about 43 MB.

How a file name is read:
- **Article = the longest leading run of tokens that is an article in the report.**
  `KSJ-101 V.jpg` is article `KSJ-101-V`, *not* `KSJ-101` in colour "V" — the `-V`,
  `-L`, `(L)` suffixes are real Busy article variants. First-token-wins silently
  merges them, which is why the match is driven by the report, not by the name alone.
- **Colour = whatever follows**, matched against the colours the report carries for
  that article: `BLK-GRY-BLK` → `BLK`, `BLK-WHT` → `BLK/WHT`, `11X13 AQUA` → `AQUA`.
  A colour the report doesn't have for that article is **left out** rather than shown
  under a wrong label.

The catalogue then picks the most specific match available: exact article+colour →
article → series photo → placeholder.

**Why colour coverage is low, and what actually fixes it.** Of the 1,396 archive photos
for articles we hold stock in, only **157 carry a colour in the file name** — 1,239 are
named `creta (11).jpg`, `JAZZY-03.png` and so on. The matcher is not losing those: a
check of every in-stock article+colour against every file name for that article found
**zero** cases where a name mentions the colour and it failed to resolve. The colour is
printed *inside* the image, and nothing here reads pixels.

One inference needs no reading and is exact: **if an article holds stock in exactly one
colour, a photo of that article is a photo of that colour.** That is applied
automatically and adds 133 colour matches. Articles with two or more colours are left
alone — there the photo would be a guess, and a wrong shade on an order sheet is worse
than no shade.

**To close a photo gap:** rename the photo `ARTICLE COLOUR.jpg` (e.g. `CRETA-05 OLV.jpg`),
put it in the archive, rerun. Nothing else.

`build_photo_index.ps1` + `photo_index.csv` remain for hand-identifying a one-off photo
from an unnamed source folder; the archive route supersedes them for bulk work.

## 4e. The FULL article catalogue (everything we have a photo of)

```bash
powershell -File build_full_catalogue.ps1 -out "$SC_WORKDIR" -zip "C:\path\ALL PHOTOS 1.zip"
```

Does everything `build_photos_from_zip.ps1` does **and** writes
`star-kidz-article-catalogue-data.js` — every article in the archive, in stock or not
(1,211 articles: 449 with stock on 04-08, 762 without). The catalogue view's
**Catalogue** dropdown switches between "In the stock report" and "Every article we
have a photo of"; out-of-stock articles show a red *no stock* pill and an empty grid.

Article names are resolved against the stock report **and** `articles-data.js`, and a
name that is the tail of exactly one known article is accepted — that is how
`GOLA V.jpg` (filed under SCHOOL SHOES) reaches `STAR GOLA-V` and `BOLT-06.jpg` reaches
`FIRE BOLT-06`. A tail matching more than one article is left unmatched rather than
guessed.

`-SkipPhotos` rebuilds only the data files, reusing the images already in
`article-photos/` (the image pass takes ~20 minutes; the data pass takes seconds).

## 4d. Photo gaps + report reconciliation

```bash
powershell -File build_photo_gap_xlsx.ps1 -out "$SC_WORKDIR"
```

Writes `Article-Photos-Missing.xlsx`: articles with no photo of their own (and whether
that needs a shoot or just a rename), every article+colour with no colour photo, a
full reconciliation of the built catalogue against the report (colours, sizes, MRP,
quantity — **MRP always as written in the report**, never averaged or filled in), and
articles Busy carries under two codes that differ only by a leading zero
(`CRETA-09` / `CRETA-9`), whose stock is split across both.

## 5. Verify in the app

Open the app → **Stock Catalogue**. The green badge should show the new pair
count and article count. Then click **🔄 Sync to FG Stock**.
