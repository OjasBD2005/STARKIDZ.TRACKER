# Builds article-photos/ + star-kidz-photo-index.js + photomap.json straight from a
# photo archive whose FILE NAMES carry the article and colour, e.g.
#     ALL PHOTOS/AIR/AIR-2010 BLK-BLK-WHT.jpeg   -> article AIR-2010, colour BLK
# This is the "quick win" the old README asked for: nothing here reads the image, so
# no photo has to be identified by eye. Requires stock_parsed.csv in -out (run
# parse_stock.ps1 first) - the report is what decides which names are articles and
# which trailing tokens are colours.
param(
  [string]$out=$env:SC_WORKDIR,
  [string]$zip="C:\Users\VINAY\Downloads\ALL PHOTOS 1.zip",
  [int]$max=1000,          # longest side, px
  [int]$quality=80,        # JPEG quality
  [switch]$KeepExisting    # skip wiping article-photos/ first
)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR); it must hold stock_parsed.csv"}
if(-not (Test-Path $zip)){throw "Photo archive not found: $zip"}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$app ="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA"
$dest="$app\article-photos"

function Norm-Article([string]$a){
  $a=$a.ToUpper().Trim() -replace '\s+',' '
  if($a -match '^(?<head>.*?)-(?<num>\d+)(?<tail>.*)$'){
    $a=$Matches['head']+'-'+[int]$Matches['num']+$Matches['tail']
  }
  return $a
}
function Squash([string]$s){ ((Norm-Article $s) -replace '[^A-Z0-9]','') }
function SquashCol([string]$c){ ($c.ToUpper().Trim() -replace '[^A-Z0-9]','') }

# ---------------------------------------------------------------- stock report
$rows=Import-Csv "$out\stock_parsed.csv"
$stock=@{}   # normArticle -> @{ Raws; Family; Colours = squashedColour -> rawColour }
foreach($r in $rows){
  $k=Norm-Article $r.Article
  if(-not $stock.ContainsKey($k)){
    $stock[$k]=@{ Raws=@{}; Family=(($r.Article -split '-')[0].Trim().ToUpper()); Colours=@{} }
  }
  $stock[$k].Raws[$r.Article.ToUpper()]=$true
  if($r.Colour){ $stock[$k].Colours[(SquashCol $r.Colour)]=$r.Colour.ToUpper() }
}
$stockSquash=@{}
foreach($k in $stock.Keys){ $stockSquash[(Squash $k)]=$k }

# ---------------------------------------------------------------- read archive
$z=[System.IO.Compression.ZipFile]::OpenRead($zip)
$photos=New-Object System.Collections.ArrayList
foreach($e in $z.Entries){
  if(-not $e.Name){continue}
  if(@('.jpg','.jpeg','.png') -notcontains ([System.IO.Path]::GetExtension($e.Name).ToLower())){continue}
  $base=[System.IO.Path]::GetFileNameWithoutExtension($e.Name)
  $base=($base -replace '\(\s*\d+\s*\)','' -replace '(?i)\s*-\s*Copy\s*$','').Trim()
  $toks=@(($base -split '\s+') | Where-Object {$_})
  if($toks.Count -eq 0){continue}

  # Article = longest leading run of tokens that is an article in the report. This is
  # what tells "KSJ-101 V" (article KSJ-101-V, no colour) apart from "AIR-2010 BLK-..."
  # (article AIR-2010, colour BLK) - the -V / -L / (L) suffixes are real Busy article
  # variants, not colours, and first-token-wins would silently merge them.
  $art='';$used=0
  for($j=$toks.Count;$j -ge 1;$j--){
    $cand=(($toks[0..($j-1)]) -join ' ')
    if($stockSquash.ContainsKey((Squash $cand))){ $art=$cand;$used=$j;break }
  }
  if(-not $art){ $art=[string]$toks[0];$used=1 }
  $colRaw=''
  if($toks.Count -gt $used){ $colRaw=(($toks[$used..($toks.Count-1)]) -join ' ') }

  $sq=Squash $art
  [void]$photos.Add([PSCustomObject]@{
    Entry=$e.FullName; Folder=(($e.FullName -split '/')[1]); Bytes=$e.Length
    Article=$(if($stockSquash.ContainsKey($sq)){$stockSquash[$sq]}else{Norm-Article $art})
    InStock=$stockSquash.ContainsKey($sq); ColourRaw=$colRaw
  })
}

# --------------------------------------------- resolve colours against the report
$exact=@{};$artLevel=@{};$famLevel=@{}
$colUnmatched=New-Object System.Collections.ArrayList
function Score($p){ $kb=$p.Bytes/1KB; if($kb -lt 25){return 0}; if($kb -gt 1500){return 1}; return 2 }

foreach($p in $photos){
  $col=''
  if($p.ColourRaw -and $p.InStock){
    $parts=@(($p.ColourRaw -split '[-\s]') | Where-Object {$_})
    $cands=@($p.ColourRaw)
    if($parts.Count -ge 2){ $cands+="$($parts[0])/$($parts[1])" }
    if($parts.Count -ge 1){ $cands+=$parts[0] }
    if($parts.Count -ge 2){ $cands+=$parts[$parts.Count-1] }
    foreach($c in $cands){
      $cs=SquashCol $c
      if($stock[$p.Article].Colours.ContainsKey($cs)){ $col=$cs;break }
    }
    if(-not $col){ [void]$colUnmatched.Add($p) }
  }
  $s=Score $p
  if($col){
    $k="$($p.Article)|$col"
    if(-not $exact.ContainsKey($k) -or $s -gt (Score $exact[$k])){ $exact[$k]=$p }
  }
  if($p.InStock -and (-not $artLevel.ContainsKey($p.Article) -or $s -gt (Score $artLevel[$p.Article]))){
    $artLevel[$p.Article]=$p
  }
  $fam=($p.Article -split '-')[0].Trim()
  if(-not $famLevel.ContainsKey($fam) -or $s -gt (Score $famLevel[$fam])){ $famLevel[$fam]=$p }
}

# ---------------------------------------------------------------- copy + resize
if(-not $KeepExisting){
  New-Item -ItemType Directory -Force $dest | Out-Null
  Get-ChildItem $dest -File | Remove-Item -Force
}
New-Item -ItemType Directory -Force $dest | Out-Null

$entries=@{}
foreach($e in $z.Entries){ $entries[$e.FullName]=$e }
$jpegEnc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object{$_.MimeType -eq 'image/jpeg'}
$encPars=New-Object System.Drawing.Imaging.EncoderParameters(1)
$encPars.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[int]$quality)

$written=@{}   # zip entry -> output file name (so one source is written once)
$bytesOut=0
function SaveResized($ms,$name){
  # $ms: a seekable stream holding the source image. Always re-encoded as JPEG at
  # $max/$quality so a 2 GB archive lands in article-photos/ at a size the app can ship.
  $ms.Position=0
  try{ $img=[System.Drawing.Image]::FromStream($ms) }catch{ $ms.Dispose(); return '' }
  $scale=[math]::Min(1.0,$max/[math]::Max($img.Width,$img.Height))
  $nw=[math]::Max(1,[int]($img.Width*$scale)); $nh=[math]::Max(1,[int]($img.Height*$scale))
  $bmp=New-Object System.Drawing.Bitmap($nw,$nh)
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.Clear([System.Drawing.Color]::White)          # PNG transparency -> white, not black
  $g.DrawImage($img,0,0,$nw,$nh)
  $g.Dispose()
  $path=Join-Path $dest $name
  $bmp.Save($path,$jpegEnc,$encPars)
  $bmp.Dispose();$img.Dispose();$ms.Dispose()
  $script:bytesOut+=(Get-Item $path).Length
  return $name
}
function Emit($entry,$name){
  if($written.ContainsKey($entry)){ return $written[$entry] }   # one source, one output file
  $e=$entries[$entry]; if(-not $e){ return '' }
  $ms=New-Object System.IO.MemoryStream
  $s=$e.Open(); $s.CopyTo($ms); $s.Dispose()
  $r=SaveResized $ms $name
  if($r){ $written[$entry]=$r }
  return $r
}
function EmitFile($path,$name){
  if($written.ContainsKey($path)){ return $written[$path] }
  if(-not (Test-Path $path)){ return '' }
  $ms=New-Object System.IO.MemoryStream
  $fs=[System.IO.File]::OpenRead($path); $fs.CopyTo($ms); $fs.Dispose()
  $r=SaveResized $ms $name
  if($r){ $written[$path]=$r }
  return $r
}
function SafeName([string]$s){ ($s -replace '[^A-Za-z0-9_\.]','-') }

$index=[ordered]@{}
# 1. exact article + colour (most specific, emitted first so it owns its file name)
foreach($k in ($exact.Keys|Sort-Object)){
  $p=$exact[$k]
  $colSq=($k -split '\|')[1]
  $colRaw=$stock[$p.Article].Colours[$colSq]
  $file=Emit $p.Entry ((SafeName "$($p.Article)__$colRaw")+'.jpg')
  if(-not $file){continue}
  foreach($raw in $stock[$p.Article].Raws.Keys){ $index["$raw|$colRaw"]=$file }
}
# 1b. hand-identified matches from photo_index.csv (photos read by eye out of the older
#     unnamed folders). The archive wins where both have the colour; these fill the rest,
#     so re-running this script never throws away work that was already verified.
$handAdded=0
$pidx="$PSScriptRoot\photo_index.csv"
$handRoots=@(
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\Article photos",
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\PRODUCT PHOTOS\Article photos"
)
if(Test-Path $pidx){
  foreach($h in (Import-Csv $pidx)){
    $ha=Norm-Article $h.Article
    if(-not $stock.ContainsKey($ha)){continue}                  # not in this stock report
    $hc=SquashCol $h.Colour
    if(-not $stock[$ha].Colours.ContainsKey($hc)){continue}      # colour not in stock now
    if($exact.ContainsKey("$ha|$hc")){continue}                  # archive already has it
    $src=$null
    foreach($r in $handRoots){
      $p=Join-Path (Join-Path $r $h.SourceFolder) $h.SourceFile
      if(Test-Path $p){ $src=$p;break }
    }
    if(-not $src){continue}
    $colRaw=$stock[$ha].Colours[$hc]
    $name=(SafeName "$ha`__$colRaw")+'.jpg'
    $file=EmitFile $src $name
    if(-not $file){continue}
    foreach($raw in $stock[$ha].Raws.Keys){ $index["$raw|$colRaw"]=$file }
    $exact["$ha|$hc"]=[PSCustomObject]@{Entry=$src;Bytes=0}   # so coverage counts it too
    $handAdded++
  }
}

# 2. article level
foreach($a in ($artLevel.Keys|Sort-Object)){
  $p=$artLevel[$a]
  $file=Emit $p.Entry ((SafeName $a)+'.jpg')
  if(-not $file){continue}
  foreach($raw in $stock[$a].Raws.Keys){ if(-not $index.Contains($raw)){ $index[$raw]=$file } }
}
# 3. series photo, used by build_catalogue.ps1 for articles with no photo of their own
$photomap=[ordered]@{}
$famNeeded=@{}
foreach($a in $stock.Keys){ $famNeeded[$stock[$a].Family]=$true }
foreach($f in ($famNeeded.Keys|Sort-Object)){
  if(-not $famLevel.ContainsKey($f)){continue}
  $p=$famLevel[$f]
  $file=Emit $p.Entry ((SafeName "_series_$f")+'.jpg')
  if($file){ $photomap[$f]=$file }
}
$z.Dispose()

# ---------------------------------------------------------------- emit
$json=($index|ConvertTo-Json -Compress)
$js=@"
/* STAR Kidz - per-article / per-colour photo index.
   Built by tools/stock-catalogue/build_photos_from_zip.ps1 from an archive whose file
   names carry the article and colour ("AIR-2010 BLK-BLK-WHT.jpeg"). No image is read.
   Keys: "ARTICLE|COLOUR" for an exact colour match, "ARTICLE" as the per-article
   fallback; the catalogue falls back to the series photo when neither is present.
   Colours are matched against the stock report, so a photo whose colour the report
   does not carry stays out of the index rather than being shown as that colour. */
window.PHOTO_INDEX = $json;
"@
Set-Content "$app\star-kidz-photo-index.js" $js -Encoding utf8
Set-Content "$out\photomap.json" ($photomap|ConvertTo-Json -Compress) -Encoding utf8

# coverage, for the missing-photo workbook
$cov=New-Object System.Collections.ArrayList
foreach($a in ($stock.Keys|Sort-Object)){
  $fam=$stock[$a].Family
  $cols=@($stock[$a].Colours.Keys)
  $withCol=@($cols|Where-Object{ $exact.ContainsKey("$a|$_") })
  $status=if($artLevel.ContainsKey($a)){'OWN PHOTO'}elseif($photomap.Contains($fam)){'SERIES ONLY'}else{'NO PHOTO'}
  [void]$cov.Add([PSCustomObject]@{
    Article=$a; Family=$fam; Status=$status
    Colours=$cols.Count; ColoursWithPhoto=$withCol.Count
    ColoursMissingPhoto=(($cols|Where-Object{-not $exact.ContainsKey("$a|$_")}|ForEach-Object{$stock[$a].Colours[$_]}) -join ', ')
  })
}
$cov|Export-Csv "$out\photo_coverage_zip.csv" -NoTypeInformation -Encoding utf8
$colUnmatched|Select-Object Entry,Article,ColourRaw|Export-Csv "$out\photo_colour_unmatched.csv" -NoTypeInformation -Encoding utf8

"PHOTO FILES IN ARCHIVE   : $($photos.Count)"
"FILES WRITTEN            : $($written.Count)"
"OUTPUT SIZE              : " + [math]::Round($bytesOut/1MB,1) + " MB"
"INDEX KEYS               : $($index.Count)  (article+colour: " + @($index.Keys|Where-Object{$_ -match '\|'}).Count + ")"
"FROM photo_index.csv     : $handAdded  (hand-identified, still in stock, not in the archive)"
"SERIES PHOTOS            : $($photomap.Count)"
""
"ARTICLES IN STOCK        : $($stock.Keys.Count)"
"  own photo              : " + @($cov|Where-Object{$_.Status -eq 'OWN PHOTO'}).Count
"  series photo only      : " + @($cov|Where-Object{$_.Status -eq 'SERIES ONLY'}).Count
"  NO photo               : " + @($cov|Where-Object{$_.Status -eq 'NO PHOTO'}).Count
"COLOURS IN STOCK         : " + (($cov|Measure-Object Colours -Sum).Sum)
"  with a colour photo    : " + (($cov|Measure-Object ColoursWithPhoto -Sum).Sum)
"JS                       : $app\star-kidz-photo-index.js"
