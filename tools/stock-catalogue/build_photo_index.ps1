# Builds star-kidz-photo-index.js from photo_index.csv.
# Each row says which SOURCE photo shows which ARTICLE in which COLOUR - read off the
# card printed inside the image itself. Add rows as more photos are identified; rerun.
$roots=@(
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\Article photos",
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\PRODUCT PHOTOS\Article photos"
)
$out=if($env:SC_WORKDIR){$env:SC_WORKDIR}else{$PSScriptRoot}
$app="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA"
$dest="$app\article-photos"
New-Item -ItemType Directory -Force $dest | Out-Null

$idx=Import-Csv "$out\photo_index.csv"
$map=[ordered]@{}
$copied=0;$missing=@()
foreach($r in $idx){
  $src=$null
  foreach($root in $roots){
    $p=Join-Path (Join-Path $root $r.SourceFolder) $r.SourceFile
    if(Test-Path $p){ $src=$p; break }
  }
  if(-not $src){ $missing+=("$($r.SourceFolder)\$($r.SourceFile)"); continue }
  $art=$r.Article.ToUpper().Trim()
  $col=$r.Colour.ToUpper().Trim()
  $safe=(($art+'__'+$col) -replace '[^A-Za-z0-9_\.]','-')
  $ext=[System.IO.Path]::GetExtension($src).ToLower()
  $name="$safe$ext"
  Copy-Item $src (Join-Path $dest $name) -Force
  $map["$art|$col"]=$name
  if(-not $map.Contains($art)){ $map[$art]=$name }   # article-level fallback
  $copied++
}
$json=($map|ConvertTo-Json -Compress)
$js=@"
/* STAR Kidz - per-article / per-colour photo index.
   The article name, colour, sizes and MRP are printed INSIDE each catalogue photo
   (e.g. "Creta-03 / OLV / 4X7 I 5X8 I 6X9 / MRP 549.99"), and the file names do not
   carry them - so each entry below was read off the image itself.
   Keys: "ARTICLE|COLOUR" for an exact match, "ARTICLE" as a per-article fallback.
   The catalogue falls back to the series photo when an article isn't listed here.
   Extend: add rows to tools/stock-catalogue/photo_index.csv and rerun build_photo_index.ps1 */
window.PHOTO_INDEX = $json;
"@
Set-Content "$app\star-kidz-photo-index.js" $js -Encoding utf8
"PHOTOS INDEXED : $copied"
"INDEX KEYS     : $($map.Count)"
if($missing.Count){ "SOURCE NOT FOUND:"; $missing|ForEach-Object{"   $_"} }
"JS             : $app\star-kidz-photo-index.js"
