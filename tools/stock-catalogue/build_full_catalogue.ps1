# Builds the FULL article catalogue - every article and colour the photo archive holds,
# in stock or not - on top of the same file-name matching build_photos_from_zip.ps1 uses.
#
#   article-photos/                  one image per article and per article+colour
#   star-kidz-photo-index.js         ARTICLE|COLOUR -> file, ARTICLE -> file
#   star-kidz-article-catalogue-data.js
#                                    every article, its colours, and the stock the
#                                    04-08 report carries for it (0 where it has none)
#
# Vocabulary comes from two places, never guessed:
#   articles / colours in the stock report  (stock_parsed.csv - authoritative)
#   articles / colours in articles-data.js  (the STAR Kidz article master)
# A trailing token that is neither is kept as the article's variant suffix (-V, -L, -CL)
# when it is one of those, and otherwise left out of the colour rather than invented.
param(
  [string]$out=$env:SC_WORKDIR,
  [string]$zip="C:\Users\VINAY\Downloads\ALL PHOTOS 1.zip",
  [int]$max=1000,
  [int]$quality=80,
  [switch]$SkipPhotos   # reuse the images already in article-photos/; rebuild only the data
)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR); it must hold stock_parsed.csv"}
if(-not (Test-Path $zip)){throw "Photo archive not found: $zip"}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$app ="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA"
$dest="$app\article-photos"

function Norm-Article([string]$a){
  $a=$a.ToUpper().Trim() -replace '\s+',' '
  if($a -match '^(?<head>.*?)-(?<num>\d+)(?<tail>.*)$'){ $a=$Matches['head']+'-'+[int]$Matches['num']+$Matches['tail'] }
  return $a
}
function Squash([string]$s){ ((Norm-Article $s) -replace '[^A-Z0-9]','') }
function SquashCol([string]$c){ ($c.ToUpper().Trim() -replace '[^A-Z0-9]','') }
function SafeName([string]$s){ ($s -replace '[^A-Za-z0-9_\.]','-') }

# ------------------------------------------------------------------ vocabulary
$artVocab=@{}; $colVocab=@{}
$stockRows=Import-Csv "$out\stock_parsed.csv"
foreach($r in $stockRows){
  $artVocab[(Squash $r.Article)]=$r.Article.ToUpper()
  if($r.Colour){ $colVocab[(SquashCol $r.Colour)]=$r.Colour.ToUpper() }
}
$mraw=Get-Content "$app\articles-data.js" -Raw
$mjson=$mraw.Substring($mraw.IndexOf('[',$mraw.IndexOf('ARTICLES_RAW')))
$mjson=$mjson.Substring(0,$mjson.LastIndexOf(']')+1)
foreach($r in ($mjson|ConvertFrom-Json)){
  $a=[string]$r[0]; $c=[string]$r[2]
  if($a -and -not $artVocab.ContainsKey((Squash $a))){ $artVocab[(Squash $a)]=$a.ToUpper() }
  if($c){
    $c=($c.ToUpper() -replace '/\d{2}(-N\d)?$','')     # strip the /22, /22-N1 season tail
    if($c -and -not $colVocab.ContainsKey((SquashCol $c))){ $colVocab[(SquashCol $c)]=$c }
  }
}
$variantSuffix=@('V','L','CL','PAD','NEW','PLUS','N','M','A','B','C','T')

# ------------------------------------------------------------ stock, by article
$stock=@{}   # squashed article -> @{ Raw; Colours = squashedColour -> @{Raw;Sizes;Qty} ; Sizes; MRPs; Qty; Machine; Season }
foreach($r in $stockRows){
  $k=Squash $r.Article
  if(-not $stock.ContainsKey($k)){
    $stock[$k]=@{ Raw=$r.Article.ToUpper(); Colours=@{}; Sizes=@{}; MRPs=@{}; Qty=0; Pairs=0
                  Machine=$r.Machine; Season=$r.Season }
  }
  $e=$stock[$k]
  if($r.Size){ $e.Sizes[$r.Size]=$true }
  if($r.MRP){ $e.MRPs[$r.MRP]=$true }
  $e.Qty+=[int]$r.Qty          # CARTONS - the report's own unit
  $e.Pairs+=[int]$r.Pairs      # summed per line; pairs-per-carton varies by size
  if($r.Colour){
    $ck=SquashCol $r.Colour
    if(-not $e.Colours.ContainsKey($ck)){ $e.Colours[$ck]=@{ Raw=$r.Colour.ToUpper(); Sizes=[ordered]@{}; PairSizes=[ordered]@{}; Qty=0; Pairs=0; MRPs=@{} } }
    $c=$e.Colours[$ck]
    if($r.MRP){ $c.MRPs[$r.MRP]=$true }   # the report prices colours of one article differently
    $s=if($r.Size){$r.Size}else{'—'}
    $c.Sizes[$s]=[int]$c.Sizes[$s]+[int]$r.Qty
    $c.PairSizes[$s]=[int]$c.PairSizes[$s]+[int]$r.Pairs
    $c.Qty+=[int]$r.Qty
    $c.Pairs+=[int]$r.Pairs
  }
}

# ------------------------------------------------------------------- read names
$z=[System.IO.Compression.ZipFile]::OpenRead($zip)
$photos=New-Object System.Collections.ArrayList
foreach($e in $z.Entries){
  if(-not $e.Name){continue}
  if(@('.jpg','.jpeg','.png') -notcontains ([System.IO.Path]::GetExtension($e.Name).ToLower())){continue}
  $base=[System.IO.Path]::GetFileNameWithoutExtension($e.Name)
  $base=($base -replace '\(\s*\d+\s*\)','' -replace '(?i)\s*-\s*Copy\s*$','').Trim()
  $toks=@(($base -split '\s+')|Where-Object{$_})
  if(-not $toks.Count){continue}

  $art='';$used=0;$known=$false
  for($j=$toks.Count;$j -ge 1;$j--){
    $c=(($toks[0..($j-1)]) -join ' ')
    if($artVocab.ContainsKey((Squash $c))){ $art=$artVocab[(Squash $c)];$used=$j;$known=$true;break }
  }
  # Photos are filed per series, so the folder's part of the name is often dropped:
  # "GOLA V.jpg" inside SCHOOL SHOES is the article STAR GOLA-V, and "BOLT-06.jpg" is
  # FIRE BOLT-06. Accept a name that is the tail of exactly one known article - one
  # candidate only, so an ambiguous tail is left unmatched instead of guessed.
  if(-not $art){
    for($j=$toks.Count;$j -ge 1;$j--){
      $c=Squash (($toks[0..($j-1)]) -join ' ')
      if($c.Length -lt 4){continue}
      $hits=@($artVocab.Keys|Where-Object{ $_ -ne $c -and $_.EndsWith($c) })
      if($hits.Count -eq 1){ $art=$artVocab[$hits[0]];$used=$j;$known=$true;break }
    }
  }
  if(-not $art){
    $art=[string]$toks[0];$used=1
    if($toks.Count -ge 2 -and ([string]$toks[1]) -match '^[A-Za-z]+-\S+$' -and $art -notmatch '-'){
      $art="$art $($toks[1])";$used=2
    }
    $art=Norm-Article $art
  }
  $rest=@(); if($toks.Count -gt $used){ $rest=@($toks[$used..($toks.Count-1)]) }
  while($rest.Count -and ($variantSuffix -contains ([string]$rest[0]).ToUpper().Trim('()'))){
    $art="$art-"+([string]$rest[0]).ToUpper().Trim('()')
    if($rest.Count -gt 1){ $rest=@($rest[1..($rest.Count-1)]) } else { $rest=@() }
  }
  $colRaw=($rest -join ' ')

  $col=''
  if($colRaw){
    $parts=@(($colRaw -split '[-\s]')|Where-Object{$_})
    $cands=@($colRaw)
    if($parts.Count -ge 2){ $cands+="$($parts[0])/$($parts[1])" }
    if($parts.Count -ge 1){ $cands+=$parts[0] }
    if($parts.Count -ge 2){ $cands+=$parts[$parts.Count-1] }
    foreach($c in $cands){ $k=SquashCol $c; if($colVocab.ContainsKey($k)){ $col=$colVocab[$k];break } }
  }
  # a file whose name is a GUID or a bare number tells us nothing - skip it
  if($art -notmatch '^[A-Z][A-Z0-9 ]*(-[A-Z0-9()/\.\-]+)*$' -or $art.Length -gt 26){ continue }

  # where the report knows this article+colour, use the report's own spelling
  $sq=Squash $art
  if($stock.ContainsKey($sq)){
    $art=$stock[$sq].Raw
    if($col){
      $ck=SquashCol $col
      if($stock[$sq].Colours.ContainsKey($ck)){ $col=$stock[$sq].Colours[$ck].Raw }
    }
  }
  [void]$photos.Add([PSCustomObject]@{
    Entry=$e.FullName;Folder=(($e.FullName -split '/')[1]);Bytes=$e.Length
    Article=$art;Squash=$sq;Colour=$col;KnownArticle=$known;InStock=$stock.ContainsKey($sq)
  })
}

# ------------------------------------------------------------------ pick photos
function Score($p){ $kb=$p.Bytes/1KB; if($kb -lt 25){return 0}; if($kb -gt 1500){return 1}; return 2 }
$exact=@{};$artLevel=@{};$famLevel=@{}
foreach($p in $photos){
  $s=Score $p
  if($p.Colour){
    $k="$($p.Article)|$($p.Colour)"
    if(-not $exact.ContainsKey($k) -or $s -gt (Score $exact[$k])){ $exact[$k]=$p }
  }
  if(-not $artLevel.ContainsKey($p.Article) -or $s -gt (Score $artLevel[$p.Article])){ $artLevel[$p.Article]=$p }
  $fam=($p.Article -split '-')[0].Trim()
  if(-not $famLevel.ContainsKey($fam) -or $s -gt (Score $famLevel[$fam])){ $famLevel[$fam]=$p }
}

# NO COLOUR IS EVER INFERRED. There was a rule here that read "if an article holds stock
# in exactly ONE colour, its photo must be that colour" - it is wrong, and ALEXA-201 is
# the proof: the archive holds two unnamed ALEXA-201 photos, the one picked is the PCH
# colourway, and the only colour in stock is B.PNK, so the rule captioned a PCH shoe as
# B.PNK. The archive carries colourways that are not in stock, so "one colour in stock"
# says nothing about which colour a photo shows. A colour is matched only when the FILE
# NAME says so.
$inferred=0

# --------------------------------------------------------------- copy + resize
New-Item -ItemType Directory -Force $dest | Out-Null
if(-not $SkipPhotos){ Get-ChildItem $dest -File | Remove-Item -Force }
$entries=@{}; foreach($e in $z.Entries){ $entries[$e.FullName]=$e }
$jpegEnc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object{$_.MimeType -eq 'image/jpeg'}
$encPars=New-Object System.Drawing.Imaging.EncoderParameters(1)
$encPars.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[int]$quality)
$written=@{}; $bytesOut=0

function SaveResized($ms,$name){
  $ms.Position=0
  try{ $img=[System.Drawing.Image]::FromStream($ms) }catch{ $ms.Dispose(); return '' }
  $scale=[math]::Min(1.0,$max/[math]::Max($img.Width,$img.Height))
  $nw=[math]::Max(1,[int]($img.Width*$scale)); $nh=[math]::Max(1,[int]($img.Height*$scale))
  $bmp=New-Object System.Drawing.Bitmap($nw,$nh)
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($img,0,0,$nw,$nh)
  $g.Dispose()
  $path=Join-Path $dest $name
  $bmp.Save($path,$jpegEnc,$encPars)
  $bmp.Dispose();$img.Dispose();$ms.Dispose()
  $script:bytesOut+=(Get-Item $path).Length
  return $name
}
function Emit($entry,$name){
  if($written.ContainsKey($entry)){ return $written[$entry] }
  if($SkipPhotos){
    if(Test-Path (Join-Path $dest $name)){ $written[$entry]=$name; return $name }
    return ''
  }
  $e=$entries[$entry]; if(-not $e){ return '' }
  $ms=New-Object System.IO.MemoryStream
  $s=$e.Open(); $s.CopyTo($ms); $s.Dispose()
  $r=SaveResized $ms $name
  if($r){ $written[$entry]=$r }
  return $r
}
function EmitFile($path,$name){
  if($written.ContainsKey($path)){ return $written[$path] }
  if($SkipPhotos){
    if(Test-Path (Join-Path $dest $name)){ $written[$path]=$name; return $name }
    return ''
  }
  if(-not (Test-Path $path)){ return '' }
  $ms=New-Object System.IO.MemoryStream
  $fs=[System.IO.File]::OpenRead($path); $fs.CopyTo($ms); $fs.Dispose()
  $r=SaveResized $ms $name
  if($r){ $written[$path]=$r }
  return $r
}

$index=[ordered]@{}
# Article-level photos are written FIRST so that a colour whose photo is the same image
# as the article's - every single-colour inference, and any article whose only photo is
# named with its colour - reuses that file instead of writing a second copy of the same
# bytes. Emit returns the name already written for a source it has seen.
foreach($a in ($artLevel.Keys|Sort-Object)){
  $p=$artLevel[$a]
  $file=Emit $p.Entry ((SafeName $a)+'.jpg')
  if($file){ $index[$a]=$file }
}
foreach($k in ($exact.Keys|Sort-Object)){
  $p=$exact[$k]
  $file=Emit $p.Entry ((SafeName "$($p.Article)__$($p.Colour)")+'.jpg')
  if($file){ $index[$k]=$file }
}
# hand-identified matches from the older unnamed folders, for anything still uncovered
$handAdded=0
$pidx="$PSScriptRoot\photo_index.csv"
$handRoots=@(
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\Article photos",
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\PRODUCT PHOTOS\Article photos")
if(Test-Path $pidx){
  foreach($h in (Import-Csv $pidx)){
    $ha=$h.Article.ToUpper(); $hc=$h.Colour.ToUpper()
    $sq=Squash $ha
    if($stock.ContainsKey($sq)){
      $ha=$stock[$sq].Raw
      $ck=SquashCol $hc
      if($stock[$sq].Colours.ContainsKey($ck)){ $hc=$stock[$sq].Colours[$ck].Raw }
    }
    if($index.Contains("$ha|$hc")){continue}
    $src=$null
    foreach($r in $handRoots){
      $p=Join-Path (Join-Path $r $h.SourceFolder) $h.SourceFile
      if(Test-Path $p){ $src=$p;break }
    }
    if(-not $src){continue}
    $file=EmitFile $src ((SafeName "$ha`__$hc")+'.jpg')
    if($file){ $index["$ha|$hc"]=$file; $handAdded++ }
  }
}
# series photos, for articles with nothing of their own
$photomap=[ordered]@{}
foreach($f in ($famLevel.Keys|Sort-Object)){
  $p=$famLevel[$f]
  $file=Emit $p.Entry ((SafeName "_series_$f")+'.jpg')
  if($file){ $photomap[$f]=$file }
}
$z.Dispose()

# ------------------------------------------------------------------ build data
# article -> colours, each colour carrying the stock the report shows for it (0 if none)
$cat=@{}
foreach($p in $photos){
  $a=$p.Article
  if(-not $cat.ContainsKey($a)){
    $sq=$p.Squash
    $st=if($stock.ContainsKey($sq)){$stock[$sq]}else{$null}
    # Build the lists as variables first. A `$(@(...))` subexpression collapses a
    # one-element array to a bare value, and ConvertTo-Json then writes "6X9" where the
    # app expects ["6X9"] - every single-size article breaks the catalogue view.
    $mArr=@(); $sArr=@()
    if($st){
      $mArr=@($st.MRPs.Keys|Sort-Object{[double]$_})
      $sArr=@($st.Sizes.Keys|Sort-Object)
    }
    $cat[$a]=[ordered]@{
      a=$a; f=(($a -split '-')[0].Trim()); colours=[ordered]@{}
      inStock=[bool]$st
      mc=$(if($st){$st.Machine}else{''}); sn=$(if($st){$st.Season}else{''})
      m=$mArr; s=$sArr
      t=$(if($st){$st.Qty}else{0}); tp=$(if($st){$st.Pairs}else{0})
    }
  }
  if($p.Colour -and -not $cat[$a].colours.Contains($p.Colour)){
    $sq=$p.Squash
    $q=[ordered]@{}; $qp=[ordered]@{}; $cm=@()
    if($stock.ContainsKey($sq)){
      $ck=SquashCol $p.Colour
      if($stock[$sq].Colours.ContainsKey($ck)){
        $q=$stock[$sq].Colours[$ck].Sizes
        $qp=$stock[$sq].Colours[$ck].PairSizes
        $cm=@($stock[$sq].Colours[$ck].MRPs.Keys|Sort-Object{[double]$_})
      }
    }
    $cat[$a].colours[$p.Colour]=@{ q=$q; p=$qp; m=$cm }
  }
}
# articles that are in stock but have no photo at all still belong in the catalogue
foreach($sq in $stock.Keys){
  $a=$stock[$sq].Raw
  if($cat.ContainsKey($a)){continue}
  $e=$stock[$sq]
  $cat[$a]=[ordered]@{
    a=$a; f=(($a -split '-')[0].Trim()); colours=[ordered]@{}; inStock=$true
    mc=$e.Machine; sn=$e.Season; m=@($e.MRPs.Keys|Sort-Object{[double]$_}); s=@($e.Sizes.Keys|Sort-Object); t=$e.Qty; tp=$e.Pairs
  }
}
# every in-stock colour must appear, photo or not
foreach($sq in $stock.Keys){
  $a=$stock[$sq].Raw
  foreach($ck in $stock[$sq].Colours.Keys){
    $c=$stock[$sq].Colours[$ck]
    if(-not $cat[$a].colours.Contains($c.Raw)){
      $cat[$a].colours[$c.Raw]=@{ q=$c.Sizes; p=$c.PairSizes; m=@($c.MRPs.Keys|Sort-Object{[double]$_}) }
    }
  }
}

$list=@()
foreach($a in ($cat.Keys|Sort-Object)){
  $e=$cat[$a]
  $cols=@()
  foreach($c in $e.colours.Keys){
    $q=$e.colours[$c].q
    $qp=$e.colours[$c].p
    $sum=0; foreach($k in $q.Keys){ $sum+=[int]$q[$k] }
    $sumP=0; if($qp){ foreach($k in $qp.Keys){ $sumP+=[int]$qp[$k] } }
    $cols+=[ordered]@{ c=$c; q=$q; p=$(if($qp){$qp}else{[ordered]@{}}); m=@($e.colours[$c].m); t=$sum; tp=$sumP }
  }
  $list+=[ordered]@{
    a=$e.a; f=$e.f; mc=$e.mc; sn=$e.sn; m=@($e.m); s=@($e.s); c=@($cols)
    t=$e.t; tp=$e.tp; st=[int][bool]$e.inStock
    p=$(if($photomap.Contains($e.f)){$photomap[$e.f]}else{''})
  }
}
# Prune index entries the catalogue can never look up: an article that is not in the
# catalogue at all, or a colour that article does not have. These come from the
# hand-identified photo_index.csv rows, whose article or colour may have left the
# report since they were recorded. Dead keys are harmless at runtime but they make the
# index lie about its own coverage.
$catKeys=@{}; $catCols=@{}
foreach($e in $list){
  $catKeys[$e.a.ToUpper()]=$true
  foreach($c in $e.c){ $catCols[($e.a.ToUpper()+'|'+$c.c.ToUpper())]=$true }
}
$dead=@()
foreach($k in @($index.Keys)){
  if($k -match '\|'){ if(-not $catCols.ContainsKey($k.ToUpper())){ $dead+=$k } }
  else { if(-not $catKeys.ContainsKey($k.ToUpper())){ $dead+=$k } }
}
foreach($k in $dead){ $index.Remove($k) }
"DEAD INDEX KEYS DROPPED: $($dead.Count)" + $(if($dead.Count){"  ($($dead -join ', '))"}else{''})

$catJson=$list|ConvertTo-Json -Depth 8 -Compress
$stamp='unknown'
$tl=Select-String -Path "$out\stock_table_full.txt" -Pattern 'STOCK-(\d{2})-(\d{2})-(\d{4})'|Select-Object -First 1
if($tl){ $mm=[regex]::Match($tl.Line,'STOCK-(\d{2})-(\d{2})-(\d{4})'); $stamp="$($mm.Groups[3].Value)-$($mm.Groups[2].Value)-$($mm.Groups[1].Value)" }

$inStockN=@($list|Where-Object{$_.st -eq 1}).Count
Set-Content "$app\star-kidz-article-catalogue-data.js" @"
/* STAR Kidz - FULL article catalogue: every article the photo archive holds, in stock
   or not. Built by tools/stock-catalogue/build_full_catalogue.ps1 from the photo file
   names, with articles and colours resolved against the stock report and the article
   master - nothing is inferred from the images.
   Stock quantities are the $stamp report's, and are 0 for articles it does not carry.
   Quantities are CARTONS (the report's own unit); pairs are summed line by line because
   pairs-per-carton differs by size.
   Fields: a=article f=family mc=machine sn=season m=[MRP] s=[sizes]
           c=[{c:colour, q:{size:cartons}, p:{size:pairs}, m:[MRP], t:cartons, tp:pairs}]
           t=total cartons tp=total pairs st=1 when in stock p=series photo */
window.ARTICLE_CATALOGUE_DATE = "$stamp";
window.ARTICLE_CATALOGUE = $catJson;
"@ -Encoding utf8

$json=($index|ConvertTo-Json -Compress)
Set-Content "$app\star-kidz-photo-index.js" @"
/* STAR Kidz - per-article / per-colour photo index, covering the WHOLE photo archive.
   Built by tools/stock-catalogue/build_full_catalogue.ps1 from file names such as
   "AIR-2010 BLK-BLK-WHT.jpeg". No image is read.
   Keys: "ARTICLE|COLOUR" for an exact colour match, "ARTICLE" as the per-article
   fallback; the catalogue falls back to the series photo when neither is present. */
window.PHOTO_INDEX = $json;
"@ -Encoding utf8
Set-Content "$out\photomap.json" ($photomap|ConvertTo-Json -Compress) -Encoding utf8

$photos|Export-Csv "$out\archive_matched.csv" -NoTypeInformation -Encoding utf8

# Photo coverage for the articles the report actually carries — this is what
# build_photo_gap_xlsx.ps1 turns into the "Photos Missing" sheet, so it has to be
# written from the same run that built the index, never left over from an older one.
$cov=New-Object System.Collections.ArrayList
foreach($sq in ($stock.Keys|Sort-Object)){
  $e=$stock[$sq]; $a=$e.Raw
  $fam=($a -split '-')[0].Trim()
  $status=if($index.Contains($a)){'OWN PHOTO'}elseif($photomap.Contains($fam)){'SERIES ONLY'}else{'NO PHOTO'}
  $cols=@($e.Colours.Keys)
  $withCol=@($cols|Where-Object{ $index.Contains("$a|$($e.Colours[$_].Raw)") })
  $missCol=@($cols|Where-Object{ -not $index.Contains("$a|$($e.Colours[$_].Raw)") }|ForEach-Object{$e.Colours[$_].Raw})
  [void]$cov.Add([PSCustomObject]@{
    Article=$a; Family=$fam; Status=$status
    Colours=$cols.Count; ColoursWithPhoto=$withCol.Count
    ColoursMissingPhoto=($missCol -join ', ')
  })
}
$cov|Export-Csv "$out\photo_coverage_zip.csv" -NoTypeInformation -Encoding utf8
"ARTICLES WITH NO OWN PHOTO : " + @($cov|Where-Object{$_.Status -ne 'OWN PHOTO'}).Count

"PHOTO FILES IN ARCHIVE : $($photos.Count) usable"
"FILES WRITTEN          : $($written.Count)"
"OUTPUT SIZE            : " + [math]::Round($bytesOut/1MB,1) + " MB"
"FROM photo_index.csv   : $handAdded"
"INFERRED COLOURS       : $inferred  (always 0 - a colour is only ever read from the file name)"
"INDEX KEYS             : $($index.Count)  (article+colour: " + @($index.Keys|Where-Object{$_ -match '\|'}).Count + ")"
"SERIES PHOTOS          : $($photomap.Count)"
""
"CATALOGUE ARTICLES     : $($list.Count)"
"  in stock ($stamp) : $inStockN"
"  no stock             : " + ($list.Count-$inStockN)
"CATALOGUE COLOURS      : " + (($list|ForEach-Object{$_.c.Count}|Measure-Object -Sum).Sum)
"TOTAL CARTONS          : " + (($list|ForEach-Object{$_.t}|Measure-Object -Sum).Sum)
"TOTAL PAIRS            : " + (($list|ForEach-Object{$_.tp}|Measure-Object -Sum).Sum)
"DATA FILE              : $app\star-kidz-article-catalogue-data.js (" + [math]::Round((Get-Item "$app\star-kidz-article-catalogue-data.js").Length/1KB) + " KB)"
