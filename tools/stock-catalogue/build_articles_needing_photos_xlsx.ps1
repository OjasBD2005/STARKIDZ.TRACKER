# Articles-Needing-Photos.xlsx — one focused list: what we hold stock in but cannot
# show a photo of. Two sheets, nothing else:
#   Articles  — in stock, no photo of that article in the archive
#   Colours   — in stock, article has a photo but not of that colour
# Needs stock_parsed.csv + photo_coverage_zip.csv in -out, and star-kidz-photo-index.js
# next to the app (parse_stock_xlsx.ps1 -> build_full_catalogue.ps1).
param([string]$out=$env:SC_WORKDIR)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR)"}
. "$PSScriptRoot\make_xlsx.ps1"
$app=$out   # write into the checkout that was passed in, not a hardcoded one
$dest="$app\Articles-Needing-Photos.xlsx"

$rows=Import-Csv "$out\stock_parsed.csv"
$cov =Import-Csv "$out\photo_coverage_zip.csv"

$stockDate='unknown'
$tl=Select-String -Path "$out\stock_table_full.txt" -Pattern 'STOCK-\d{2}-\d{2}-\d{4}' | Select-Object -First 1
if($tl){ $stockDate=([regex]::Match($tl.Line,'STOCK-\d{2}-\d{2}-\d{4}')).Value }

# photo index, so a colour can be checked against what is actually on disk
$idxTxt=Get-Content "$app\star-kidz-photo-index.js" -Raw
$idxJson=$idxTxt.Substring($idxTxt.IndexOf('{')).TrimEnd()
if($idxJson.EndsWith(';')){ $idxJson=$idxJson.Substring(0,$idxJson.Length-1) }
$idx=@{}
($idxJson|ConvertFrom-Json).PSObject.Properties | ForEach-Object { $idx[$_.Name]=$_.Value }

# fold the report by article, on the code exactly as written
$rep=@{}
foreach($r in $rows){
  $k=$r.Article.ToUpper()
  if(-not $rep.ContainsKey($k)){
    $rep[$k]=@{ Raw=$r.Article; Family=(($r.Article -split '-')[0].Trim().ToUpper())
                Machine=$r.Machine; Season=$r.Season; Series=$r.Series
                Colours=@{}; Sizes=@{}; MRPs=@{}; Qty=0; Pairs=0
                ByColour=@{}; PairsByColour=@{}; SizesByColour=@{}; MrpByColour=@{} }
  }
  $e=$rep[$k]
  # Qty is CARTONS (the report's own unit); Pairs is worked out per line because
  # pairs-per-carton differs by size. Never label one as the other.
  $e.Qty+=[int]$r.Qty
  $e.Pairs+=[int]$r.Pairs
  if($r.Size){ $e.Sizes[$r.Size]=$true }
  if($r.MRP){ $e.MRPs[$r.MRP]=$true }
  if($r.Colour){
    $c=$r.Colour.ToUpper()
    $e.Colours[$c]=$true
    $e.ByColour[$c]=[int]$e.ByColour[$c]+[int]$r.Qty
    $e.PairsByColour[$c]=[int]$e.PairsByColour[$c]+[int]$r.Pairs
    if(-not $e.SizesByColour.ContainsKey($c)){ $e.SizesByColour[$c]=@{} }
    if($r.Size){ $e.SizesByColour[$c][$r.Size]=$true }
    if(-not $e.MrpByColour.ContainsKey($c)){ $e.MrpByColour[$c]=@{} }
    if($r.MRP){ $e.MrpByColour[$c][$r.MRP]=$true }
  }
}
# Coverage may be keyed on the code as the report writes it or on the normalised form.
# Try both, or an article Busy spells with a leading zero (CRETA-09) reads as "no photo"
# when it actually has one.
function Norm-Article([string]$a){
  $a=$a.ToUpper().Trim() -replace '\s+',' '
  if($a -match '^(?<head>.*?)-(?<num>\d+)(?<tail>.*)$'){ $a=$Matches['head']+'-'+[int]$Matches['num']+$Matches['tail'] }
  return $a
}
$covBy=@{}; $covByN=@{}
foreach($c in $cov){ $covBy[$c.Article.ToUpper()]=$c; $covByN[(Norm-Article $c.Article)]=$c }
function Cov($a){
  $u="$a".ToUpper()
  if($covBy.ContainsKey($u)){ return $covBy[$u] }
  $n=Norm-Article $a
  if($covByN.ContainsKey($n)){ return $covByN[$n] }
  return $null
}

# ---------------- Sheet 1: whole articles with no photo ----------------
$s1=@()
$s1+=,@('Article','Series','Machine','Season','Stock (cartons)','Stock (pairs)','Colours in stock','Sizes in stock',
        'MRP (as in report)','What is missing','Action')
$need=@()
foreach($k in $rep.Keys){
  $cv=Cov $k
  $st=if($cv){$cv.Status}else{'NO PHOTO'}
  if($st -eq 'OWN PHOTO'){continue}
  $need+=[PSCustomObject]@{K=$k;Status=$st;Qty=$rep[$k].Qty}
}
foreach($n in ($need|Sort-Object @{e={if($_.Status -eq 'NO PHOTO'){0}else{1}}},@{e={$_.Qty};d=$true})){
  $e=$rep[$n.K]
  $what=if($n.Status -eq 'NO PHOTO'){'Nothing in the archive for this article'}
        else{'Series folder has photos, but none is named for this article'}
  $act =if($n.Status -eq 'NO PHOTO'){'SHOOT PHOTO'}else{'RENAME AN EXISTING PHOTO'}
  $s1+=,@($e.Raw,$e.Family,$e.Machine,$e.Season,[int]$e.Qty,[int]$e.Pairs,
          (($e.Colours.Keys|Sort-Object) -join ', '),(($e.Sizes.Keys|Sort-Object) -join ', '),
          (($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', '),$what,$act)
}
$needCtn=0; $needPrs=0
foreach($n in $need){ $needCtn+=[int]$rep[$n.K].Qty; $needPrs+=[int]$rep[$n.K].Pairs }
$s1+=,@('TOTAL','','','',[int]$needCtn,[int]$needPrs,'','','','','')

# ---------------- Sheet 2: colours with no photo of that shade ----------------
$s2=@()
$s2+=,@('Article','Colour','Stock (cartons)','Stock (pairs)','Sizes in stock','MRP (this colour)','Article photo on hand?',
        'What is missing','Rename the photo to')
$missCol=0
foreach($k in ($rep.Keys|Sort-Object)){
  $e=$rep[$k]
  foreach($c in ($e.Colours.Keys|Sort-Object)){
    if($idx.ContainsKey("$k|$c")){continue}
    $missCol++
    $hasArt=$idx.ContainsKey($k)
    $s2+=,@($e.Raw,$c,[int]$e.ByColour[$c],[int]$e.PairsByColour[$c],
            (($e.SizesByColour[$c].Keys|Sort-Object) -join ', '),
            (($e.MrpByColour[$c].Keys|Sort-Object{[double]$_}) -join ', '),
            $(if($hasArt){'Yes - the article photo is shown instead'}else{'No'}),
            'No photo of this exact colour',
            "$($e.Raw) $c.jpg")
  }
}

# ---------------- Sheet 3: how to read it ----------------
$noPhoto=@($need|Where-Object{$_.Status -eq 'NO PHOTO'})
$series =@($need|Where-Object{$_.Status -eq 'SERIES ONLY'})
$s3=@(
 ,@('ARTICLES WE HOLD STOCK IN BUT CANNOT SHOW','')
 ,@('','')
 ,@('Stock report',"$stockDate")
 ,@('Photo archive','ALL PHOTOS 1.zip')
 ,@('Articles in stock',[int]$rep.Keys.Count)
 ,@('  with a photo of their own',[int]($rep.Keys.Count-$need.Count))
 ,@('  WITHOUT one',[int]$need.Count)
 ,@('     needs a photo shoot',[int]$noPhoto.Count)
 ,@('     needs only a rename',[int]$series.Count)
 ,@('  stock sitting behind those (cartons)',[int]$needCtn)
 ,@('  stock sitting behind those (pairs)',[int]$needPrs)
 ,@('Article + colour combinations with no photo of that shade',[int]$missCol)
 ,@('','')
 ,@('SHEET','WHAT IT SHOWS')
 ,@('Articles','An article in stock with no photo of its own. SHOOT PHOTO means nothing in the archive matches it at all. RENAME AN EXISTING PHOTO means its series folder already has photos - one of them just is not named for this article.')
 ,@('Colours','A colour we hold stock in with no photo of that exact shade. The catalogue falls back to the article photo, which shows the customer the wrong colour.')
 ,@('','')
 ,@('UNITS','')
 ,@('Stock is counted in CARTONS.','The Busy report''s Unit column says Carton, so its Grand Total is cartons. Pairs per carton run 24-36 and vary by size, so pairs are summed line by line rather than multiplied. Both columns are shown - never read one as the other.')
 ,@('','')
 ,@('HOW TO FIX EITHER OF THEM','')
 ,@('Rename the file, nothing else.','Name it "ARTICLE COLOUR.jpg" - e.g. "CRETA-05 OLV.jpg" - put it in the archive and the catalogue picks it up on the next rebuild. The last column of the Colours sheet gives the exact file name to use.')
 ,@('Colour codes must match the report.','Use the colour exactly as Busy writes it (B.PNK, T.BLU, LGR/NBL). A colour the report does not carry for that article is ignored rather than shown under a wrong label.')
 ,@('','')
 ,@('WHY AN ARTICLE CAN SAY "RENAME"','The archive is filed per series, and many of its files are still named creta (11).jpg, sports (1).jpg and so on. Those carry no article and no colour, so they can only ever be used as a series fallback.')
)

$sheets=[ordered]@{
  'Articles' =@{rows=$s1;widths=@(24,16,12,10,15,14,34,30,26,52,26)}
  'Colours'  =@{rows=$s2;widths=@(24,14,15,14,26,20,34,30,28)}
  'Read me'  =@{rows=$s3;widths=@(56,104)}
}
WriteXlsx $dest $sheets
"WROTE: $dest"
"  Articles sheet : " + ($s1.Count-2) + " articles  (" + $noPhoto.Count + " need a shoot, " + $series.Count + " need a rename)"
"  Colours sheet  : $missCol article+colour rows"
"  stock behind them : $needCtn cartons = $needPrs pairs"
