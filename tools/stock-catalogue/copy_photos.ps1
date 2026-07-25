$root="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\Article photos"
$dest="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA\article-photos"
$out ="C:\Users\VINAY\AppData\Local\Temp\claude\C--Users-VINAY-OneDrive---Ojas-Footwear-India-Private-Limited-Desktop-CLAUDE-DATA\2913ead1-0722-4ed7-98d5-ecf0be6986f3\scratchpad"
New-Item -ItemType Directory -Force $dest | Out-Null

$alias=@{'STANLAY'='Stanley series';'TODDLER'='TOODLER';'GIRL'='SCHOOL SHOES';'DLX'='SCHOOL SHOES';
 'GOLA'='SCHOOL SHOES';'EVA'='SCHOOL SHOES';'PLAIN'='SCHOOL SHOES';'SS'='SCHOOL SHOES';'SKID'='SCHOOL SHOES';
 'GSD'='ksd';'GCS'='ksd';'GSL'='ksd';'GSJ'='ksj';'KIARA'='kiaraa';'FIRE'='fire bolt';'BOLT'='fire bolt';
 'ROME'='pluto';'CUST'='sports';'CUT'='pub'}
$folders=Get-ChildItem $root -Directory | ForEach-Object { $_.Name }
$rows=Import-Csv "$out\stock_parsed.csv"
$fams=$rows | ForEach-Object { ($_.Article -split '-')[0].Trim() } | Sort-Object -Unique

$lo=40000; $hi=600000
$map=@{}
foreach($fam in $fams){
  $fld=$null
  if($alias.ContainsKey($fam)){ $fld=$alias[$fam] }
  else{
    $k=$fam.ToUpper().Replace(' ','')
    $h=$folders | Where-Object { $_.ToUpper().Replace(' ','') -eq $k }
    if(-not $h){ $h=$folders | Where-Object { $k.StartsWith($_.ToUpper().Replace(' ','')) -or $_.ToUpper().Replace(' ','').StartsWith($k) } }
    if($h){ $fld=($h | Select-Object -First 1) }
  }
  if(-not $fld){ continue }
  $src=Join-Path $root $fld
  if(-not (Test-Path $src)){ continue }
  $imgs=@(Get-ChildItem $src -File -Recurse -Include *.jpg,*.jpeg -ErrorAction SilentlyContinue)
  if($imgs.Count -eq 0){ $imgs=@(Get-ChildItem $src -File -Recurse -Include *.png -ErrorAction SilentlyContinue) }
  if($imgs.Count -eq 0){ continue }
  $pick=$imgs | Where-Object { $_.Length -ge $lo -and $_.Length -le $hi } | Sort-Object Length | Select-Object -First 1
  if(-not $pick){ $pick=$imgs | Sort-Object Length | Select-Object -First 1 }
  $safe=($fam -replace '[^A-Za-z0-9]','_').ToLower()
  $name="$safe$($pick.Extension.ToLower())"
  Copy-Item $pick.FullName (Join-Path $dest $name) -Force
  $map[$fam]=$name
}
$f=Get-ChildItem $dest -File
$bytes=($f | Measure-Object Length -Sum).Sum
$mb=[math]::Round($bytes/1048576,1)
"FILES COPIED : $($f.Count)"
"TOTAL SIZE   : $mb MB"
$map | ConvertTo-Json -Compress | Set-Content "$out\photomap.json" -Encoding utf8
"MAPPED FAMILIES: $($map.Count)"
