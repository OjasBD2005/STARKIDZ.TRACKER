# Writes Article-Photos-Missing.xlsx: what the photo archive does NOT cover, plus a
# line-by-line reconciliation of the built catalogue against the stock report
# (colours, sizes, MRP and quantity - MRP always as written in the report).
# Needs, in -out: stock_parsed.csv, catalogue.json, photo_coverage_zip.csv
# (parse_stock.ps1 -> build_photos_from_zip.ps1 -> build_catalogue.ps1).
param([string]$out=$env:SC_WORKDIR)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR)"}
. "$PSScriptRoot\make_xlsx.ps1"
$app="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA"
$dest="$app\Article-Photos-Missing.xlsx"

$rows=Import-Csv "$out\stock_parsed.csv"
$cov =Import-Csv "$out\photo_coverage_zip.csv"
$cat =Get-Content "$out\catalogue.json" -Raw | ConvertFrom-Json

$stockDate='unknown'
$tl=Select-String -Path "$out\stock_table_full.txt" -Pattern 'STOCK-(\d{2})-(\d{2})-(\d{4})' | Select-Object -First 1
if($tl){ $stockDate=([regex]::Match($tl.Line,'STOCK-\d{2}-\d{2}-\d{4}')).Value }

function Norm-Article([string]$a){
  $a=$a.ToUpper().Trim() -replace '\s+',' '
  if($a -match '^(?<head>.*?)-(?<num>\d+)(?<tail>.*)$'){ $a=$Matches['head']+'-'+[int]$Matches['num']+$Matches['tail'] }
  return $a
}

# ---- fold the report by article, straight from the parsed rows ----
# Keyed on the article code EXACTLY as the report writes it: Busy carries CRETA-09 and
# CRETA-9 as two separate item codes, and folding them together would report a
# quantity mismatch that is really a duplicate in the item master (see Duplicate Codes).
$rep=@{}
foreach($r in $rows){
  $k=$r.Article.ToUpper()
  if(-not $rep.ContainsKey($k)){
    $rep[$k]=@{ Raw=$r.Article; Family=(($r.Article -split '-')[0].Trim().ToUpper())
                Machine=$r.Machine; Season=$r.Season
                Colours=@{}; Sizes=@{}; MRPs=@{}; Qty=0; Pairs=0; CtnByColour=@{}; PairsByColour=@{} }
  }
  $e=$rep[$k]
  # Qty is CARTONS (the report's unit); Pairs is summed per line because pairs-per-carton
  # varies by size. The two are never interchangeable.
  if($r.Colour){
    $c=$r.Colour.ToUpper()
    $e.Colours[$c]=$true
    $e.CtnByColour[$c]=[int]$e.CtnByColour[$c]+[int]$r.Qty
    $e.PairsByColour[$c]=[int]$e.PairsByColour[$c]+[int]$r.Pairs
  }
  if($r.Size){ $e.Sizes[$r.Size]=$true }
  if($r.MRP){ $e.MRPs[$r.MRP]=$true }
  $e.Qty+=[int]$r.Qty
  $e.Pairs+=[int]$r.Pairs
}

# ---- fold the built catalogue the same way, so the two can be compared ----
$built=@{}
foreach($a in $cat){
  $k=$a.a.ToUpper()
  $cols=@{}; $q=0
  foreach($c in $a.c){
    $cols[$c.c.ToUpper()]=$true
    foreach($p in $c.q.PSObject.Properties){ $q+=[int]$p.Value }
  }
  $built[$k]=@{ Colours=$cols; Sizes=@($a.s); MRPs=@($a.m); Qty=$q; Photo=$a.p }
}

# Coverage may be keyed on the item code exactly as the report writes it (the current
# builder) or on the normalised form (older ones) — try both before giving up, or every
# article with a leading zero reads as "no photo".
$covBy=@{}; $covByN=@{}
foreach($c in $cov){ $covBy[$c.Article.ToUpper()]=$c; $covByN[(Norm-Article $c.Article)]=$c }
function Cov($rawArticle){
  $u="$rawArticle".ToUpper()
  if($covBy.ContainsKey($u)){ return $covBy[$u] }
  $n=Norm-Article $rawArticle
  if($covByN.ContainsKey($n)){ return $covByN[$n] }
  return $null
}

function SetEq($h,$arr){
  $b=@{}; foreach($x in $arr){ $b["$x".ToUpper()]=$true }
  if($h.Keys.Count -ne $b.Keys.Count){return $false}
  foreach($k in $h.Keys){ if(-not $b.ContainsKey("$k".ToUpper())){return $false} }
  return $true
}

# ================= Sheet 1: Photos Missing =================
$s1=@()
$s1+=,@('Article','Series','Machine','Stock (cartons)','Stock (pairs)','Colours in stock','Sizes','MRP (as in report)','Photo status','Action needed')
$missing=@()
foreach($k in ($rep.Keys|Sort-Object)){
  $cv0=Cov $k
  $st=if($cv0){$cv0.Status}else{'NO PHOTO'}
  if($st -eq 'OWN PHOTO'){continue}
  $missing+=[PSCustomObject]@{K=$k;Status=$st;Qty=$rep[$k].Qty}
}
# "NO PHOTO" first: those need a shoot, which takes days. "SERIES ONLY" only needs a
# file renamed. Within each, biggest stock first — that is what is at risk of not being
# shown to a customer.
foreach($m in ($missing|Sort-Object @{e={if($_.Status -eq 'NO PHOTO'){0}else{1}}},@{e={$_.Qty};d=$true})){
  $e=$rep[$m.K]
  $act=if($m.Status -eq 'NO PHOTO'){'SHOOT PHOTO - nothing in the archive'}else{'NAME A PHOTO - series folder has photos, none named for this article'}
  $s1+=,@($e.Raw,$e.Family,$e.Machine,[int]$e.Qty,[int]$e.Pairs,(($e.Colours.Keys|Sort-Object) -join ', '),(($e.Sizes.Keys|Sort-Object) -join ', '),
          (($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', '),$m.Status,$act)
}
$s1+=,@('TOTAL','','',[int](($missing|Measure-Object Qty -Sum).Sum),
        [int](($missing|ForEach-Object{[int]$rep[$_.K].Pairs}|Measure-Object -Sum).Sum),'','','','','')

# ================= Sheet 2: Colour Photos Missing =================
# One row per article|colour that is in stock but has no colour-specific photo.
$idxTxt=Get-Content "$app\star-kidz-photo-index.js" -Raw
$idxJson=$idxTxt.Substring($idxTxt.IndexOf('{'))
$idxJson=$idxJson.TrimEnd()
if($idxJson.EndsWith(';')){ $idxJson=$idxJson.Substring(0,$idxJson.Length-1) }
$idx=@{}
($idxJson|ConvertFrom-Json).PSObject.Properties | ForEach-Object { $idx[$_.Name]=$_.Value }

$s2=@()
$s2+=,@('Article','Colour','Stock (cartons)','Stock (pairs)','Sizes','MRP (as in report)','Has colour photo?','Photo shown instead')
$noColour=0
foreach($k in ($rep.Keys|Sort-Object)){
  $e=$rep[$k]
  foreach($c in ($e.Colours.Keys|Sort-Object)){
    $has=$idx.ContainsKey("$($e.Raw.ToUpper())|$c")
    if($has){continue}
    $noColour++
    $fallback=if($idx.ContainsKey($e.Raw.ToUpper())){'article photo'}
              elseif($built.ContainsKey($k) -and $built[$k].Photo){'series photo'}
              else{'placeholder - no photo'}
    $s2+=,@($e.Raw,$c,[int]$e.CtnByColour[$c],[int]$e.PairsByColour[$c],(($e.Sizes.Keys|Sort-Object) -join ', '),
            (($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', '),'NO',$fallback)
  }
}

# ================= Sheet 3: Article Check (report vs catalogue) =================
$s3=@()
$s3+=,@('Article','Series','Machine','Season','Colours (report)','Sizes (report)','MRP (as in report)',
        'Stock (cartons)','Stock (pairs)','Colours OK','Sizes OK','MRP OK','Qty OK','Verdict','Photo status','Colours with own photo')
$bad=0
foreach($k in ($rep.Keys|Sort-Object)){
  $e=$rep[$k]
  $b=$built[$k]
  if(-not $b){
    $s3+=,@($e.Raw,$e.Family,$e.Machine,$e.Season,(($e.Colours.Keys|Sort-Object) -join ', '),
            (($e.Sizes.Keys|Sort-Object) -join ', '),(($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', '),
            [int]$e.Qty,[int]$e.Pairs,'NO','NO','NO','NO','NOT IN CATALOGUE','','')
    $bad++; continue
  }
  $cOk=SetEq $e.Colours $b.Colours.Keys
  $sOk=SetEq $e.Sizes   $b.Sizes
  $mOk=SetEq $e.MRPs    $b.MRPs
  $qOk=($e.Qty -eq $b.Qty)
  $ok=($cOk -and $sOk -and $mOk -and $qOk)
  if(-not $ok){$bad++}
  $cv=Cov $k
  $s3+=,@($e.Raw,$e.Family,$e.Machine,$e.Season,(($e.Colours.Keys|Sort-Object) -join ', '),
          (($e.Sizes.Keys|Sort-Object) -join ', '),(($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', '),
          [int]$e.Qty,[int]$e.Pairs,
          $(if($cOk){'OK'}else{'NOT OK'}),$(if($sOk){'OK'}else{'NOT OK'}),
          $(if($mOk){'OK'}else{'NOT OK'}),$(if($qOk){'OK'}else{'NOT OK'}),
          $(if($ok){'OK'}else{'CHECK'}),
          $(if($cv){$cv.Status}else{'NO PHOTO'}),
          $(if($cv){"$($cv.ColoursWithPhoto) of $($cv.Colours)"}else{''}))
}

# ========== Sheet 4: Duplicate Codes (same article, two item codes) ==========
# CRETA-09 vs CRETA-9 etc. Busy treats them as different items, so the stock splits
# and the catalogue shows the article twice. Nothing here is guesswork: the two codes
# differ only by a leading zero.
$dupGroups=$rep.Keys | Group-Object { Norm-Article $_ } | Where-Object { $_.Count -gt 1 }
$s5=@()
$s5+=,@('Article (normalised)','Item codes in the report','Code','Stock (cartons)','Stock (pairs)','Colours','Sizes','MRP (as in report)','Effect')
foreach($g in ($dupGroups|Sort-Object Name)){
  foreach($code in ($g.Group|Sort-Object)){
    $e=$rep[$code]
    $s5+=,@($g.Name,(($g.Group|Sort-Object) -join ' | '),$e.Raw,[int]$e.Qty,[int]$e.Pairs,
            (($e.Colours.Keys|Sort-Object) -join ', '),(($e.Sizes.Keys|Sort-Object) -join ', '),
            (($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', '),
            'Stock is split across two codes - the catalogue lists the article twice')
  }
}
if($s5.Count -eq 1){ $s5+=,@('None found','','','','','','','','') }

# ================= Sheet 4: Read me =================
$own=@($cov|Where-Object{$_.Status -eq 'OWN PHOTO'}).Count
$ser=@($cov|Where-Object{$_.Status -eq 'SERIES ONLY'}).Count
$non=@($cov|Where-Object{$_.Status -eq 'NO PHOTO'}).Count
$pairsTotal=(($rep.Values|ForEach-Object{$_.Colours.Keys.Count})|Measure-Object -Sum).Sum
$s4=@(
 ,@('STAR KIDZ - ARTICLE PHOTO GAPS & STOCK CHECK','')
 ,@('','')
 ,@('Stock report',"$stockDate.pdf")
 ,@('Photo archive','ALL PHOTOS 1.zip')
 ,@('Articles in stock',[int]$rep.Keys.Count)
 ,@('  with their own photo',[int]$own)
 ,@('  series photo only (no photo named for the article)',[int]$ser)
 ,@('  NO photo anywhere',[int]$non)
 ,@('Article + colour combinations in stock',[int]$pairsTotal)
 ,@('  with a photo of that exact colour',[int]($pairsTotal-$noColour))
 ,@('  without one',[int]$noColour)
 ,@('Articles failing the report check',[int]$bad)
 ,@('Articles carried under two item codes',[int](@($dupGroups).Count))
 ,@('','')
 ,@('SHEET','WHAT IT SHOWS')
 ,@('Photos Missing','Every article in stock with no photo of its own. "NO PHOTO" means nothing in the archive - it needs a shoot. "SERIES ONLY" means the series has photos but none is named for this article - renaming one fixes it, no shoot needed.')
 ,@('Colour Photos Missing','Every article + colour in stock with no photo of that colour, and what the catalogue shows instead.')
 ,@('Article Check','Every article reconciled against the stock report: colours, sizes, MRP and quantity. Anything other than OK means the catalogue and the report disagree.')
 ,@('Duplicate Codes','Articles the report carries under two item codes that differ only by a leading zero (CRETA-09 / CRETA-9). Their stock is split and the catalogue lists them twice - a fix in the Busy item master, not here.')
 ,@('','')
 ,@('HOW PHOTOS ARE MATCHED','')
 ,@('From the file name only.','A file named "AIR-2010 BLK-BLK-WHT.jpeg" is read as article AIR-2010, colour BLK. Nothing is read out of the image, so the whole index rebuilds in one pass.')
 ,@('The report decides what is a colour.','"KSJ-101 V" is article KSJ-101-V (a real Busy article), not KSJ-101 in colour V. Trailing tokens are only treated as a colour when the report carries that colour for that article.')
 ,@('A colour the report does not have is left out.','Better a correct article photo than a photo labelled as a colour that is not in stock.')
 ,@('To close a gap','Rename the photo to "ARTICLE COLOUR.jpg" - e.g. "CRETA-05 OLV.jpg" - drop it in the archive and rerun. No other step.')
 ,@('','')
 ,@('PRICES','')
 ,@('MRP is taken from the stock report as written.','Where the report carries more than one MRP for an article, every value is listed, comma separated - nothing is averaged, rounded or filled in.')
 ,@('','')
 ,@('UNITS','')
 ,@('Stock is counted in CARTONS.','The report''s Unit column says Carton, so its Grand Total is cartons. Pairs per carton run 24-36 and vary by size, so pairs are summed line by line rather than multiplied. Both are shown side by side - never read one as the other.')
)

$sheets=[ordered]@{
  'Photos Missing'        =@{rows=$s1;widths=@(24,14,12,15,14,34,26,26,14,58)}
  'Colour Photos Missing' =@{rows=$s2;widths=@(20,12,15,14,26,22,16,22)}
  'Article Check'         =@{rows=$s3;widths=@(20,14,12,10,42,26,22,15,14,11,10,9,9,10,14,20)}
  'Duplicate Codes'       =@{rows=$s5;widths=@(22,28,14,15,14,26,26,22,58)}
  'Read me'               =@{rows=$s4;widths=@(52,104)}
}
# Every row of a sheet must be as wide as its header. A short data row silently shifts
# every value left of it into the wrong column - the numbers still look plausible, which
# is exactly what makes it dangerous on a sheet people price and order from.
foreach($name in $sheets.Keys){
  $r=$sheets[$name].rows
  if(-not $r.Count){continue}
  $w=@($r[0]).Count
  for($i=1;$i -lt $r.Count;$i++){
    $n=@($r[$i]).Count
    if($n -ne $w){ throw "Sheet '$name' row $($i+1) has $n cells but the header has $w. Fix the row before writing the workbook." }
  }
  if($sheets[$name].widths -and @($sheets[$name].widths).Count -ne $w){
    throw "Sheet '$name' declares $(@($sheets[$name].widths).Count) column widths for $w columns."
  }
}
WriteXlsx $dest $sheets
"WROTE: $dest"
"  size                  : " + [math]::Round((Get-Item $dest).Length/1KB) + " KB"
"  Photos Missing        : " + ($s1.Count-2) + " articles"
"  Colour Photos Missing : " + ($s2.Count-1) + " article+colour rows"
"  Article Check         : " + ($s3.Count-1) + " articles, failing: $bad"
