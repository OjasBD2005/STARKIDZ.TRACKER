$roots=@(
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\Article photos",
 "C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\PRODUCT PHOTOS\Article photos"
)
$out=if($env:SC_WORKDIR){$env:SC_WORKDIR}else{throw "Set SC_WORKDIR to the folder holding stock_parsed.csv"}
$alias=@{'STANLAY'='Stanley series';'TODDLER'='TOODLER';'GIRL'='SCHOOL SHOES';'DLX'='SCHOOL SHOES';
 'GOLA'='SCHOOL SHOES';'EVA'='SCHOOL SHOES';'PLAIN'='SCHOOL SHOES';'SS'='SCHOOL SHOES';'SKID'='SCHOOL SHOES';
 'GSD'='ksd';'GCS'='ksd';'GSL'='ksd';'GSJ'='ksj';'KIARA'='kiaraa';'FIRE'='fire bolt';'BOLT'='fire bolt';
 'ROME'='pluto';'CUST'='sports';'CUT'='pub'}

# union of folder names across both roots, with combined photo counts
$folderCnt=@{}
foreach($r in $roots){
  if(-not (Test-Path $r)){continue}
  foreach($d in Get-ChildItem $r -Directory -ErrorAction SilentlyContinue){
    $n=@(Get-ChildItem $d.FullName -File -Recurse -Include *.jpg,*.jpeg,*.png,*.webp -ErrorAction SilentlyContinue).Count
    if($folderCnt.ContainsKey($d.Name)){ $folderCnt[$d.Name]=[Math]::Max($folderCnt[$d.Name],$n) } else { $folderCnt[$d.Name]=$n }
  }
}
$folders=@($folderCnt.Keys)

$rows=Import-Csv "$out\stock_parsed.csv"
$art=$rows|Group-Object Article|ForEach-Object{
  [PSCustomObject]@{Article=$_.Name;Fam=(($_.Name -split '-')[0].Trim());Qty=($_.Group|Measure-Object Qty -Sum).Sum
    Colours=(@($_.Group|Where-Object{$_.Colour}|Select-Object -ExpandProperty Colour -Unique)).Count
    Sizes=(@($_.Group|Where-Object{$_.Size}|Select-Object -ExpandProperty Size -Unique)).Count
    MRP=(@($_.Group|Where-Object{$_.MRP}|Select-Object -ExpandProperty MRP -Unique) -join ' / ')
    Machine=($_.Group[0].Machine); Season=($_.Group[0].Season)}
}

$res=foreach($a in $art){
  $fld=$null
  if($alias.ContainsKey($a.Fam)){ $fld=$alias[$a.Fam] }
  else{
    $k=$a.Fam.ToUpper().Replace(' ','')
    $h=$folders|Where-Object{$_.ToUpper().Replace(' ','') -eq $k}
    if(-not $h){$h=$folders|Where-Object{$k.StartsWith($_.ToUpper().Replace(' ','')) -or $_.ToUpper().Replace(' ','').StartsWith($k)}}
    if($h){$fld=($h|Select-Object -First 1)}
  }
  $ph=0; if($fld -and $folderCnt.ContainsKey($fld)){ $ph=$folderCnt[$fld] }
  $status = if(-not $fld -or $ph -eq 0){'NO PHOTOS'} else {'SERIES PHOTOS EXIST'}
  [PSCustomObject]@{
    Article=$a.Article; Series=$a.Fam; Machine=$a.Machine; Season=$a.Season
    StockPairs=$a.Qty; Colours=$a.Colours; Sizes=$a.Sizes; MRP=$a.MRP
    PhotoFolder=$(if($fld){$fld}else{'— none —'}); PhotosInSeries=$ph; Status=$status
  }
}
$res|Sort-Object @{e='Status';Descending=$true},@{e='StockPairs';Descending=$true}|Export-Csv "$out\photo_coverage.csv" -NoTypeInformation -Encoding utf8

"TOTAL ARTICLES        : $($res.Count)"
$no=@($res|Where-Object{$_.Status -eq 'NO PHOTOS'})
"ARTICLES WITH NO PHOTOS: $($no.Count)"
"  their stock pairs    : " + (($no|Measure-Object StockPairs -Sum).Sum)
""
"SERIES WITH NO PHOTOS:"
$no|Group-Object Series|ForEach-Object{[PSCustomObject]@{Series=$_.Name;Articles=$_.Count;Pairs=($_.Group|Measure-Object StockPairs -Sum).Sum}}|Sort-Object Pairs -Descending|Format-Table -AutoSize
