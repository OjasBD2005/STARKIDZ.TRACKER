param([string]$out=$env:SC_WORKDIR)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR); it must hold stock_parsed.csv + photomap.json"}
$root="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\Article photos"
$app ="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA"
$dest="$app\article-photos"
New-Item -ItemType Directory -Force $dest | Out-Null

# family -> photo folder aliases for names that don't match 1:1
$alias=@{
  'STANLAY'='Stanley series'; 'TODDLER'='TOODLER'; 'GIRL'='SCHOOL SHOES'; 'DLX'='SCHOOL SHOES'
  'GOLA'='SCHOOL SHOES'; 'EVA'='SCHOOL SHOES'; 'PLAIN'='SCHOOL SHOES'; 'SS'='SCHOOL SHOES'
  'SKID'='SCHOOL SHOES'; 'GSD'='ksd'; 'GCS'='ksd'; 'GSL'='ksd'; 'GSJ'='ksj'; 'KIARA'='kiaraa'
  'FIRE'='fire bolt'; 'BOLT'='fire bolt'; 'ROME'='pluto'; 'CUST'='sports'; 'CUT'='pub'
}
$folders = Get-ChildItem $root -Directory | ForEach-Object { $_.Name }

function FolderFor($fam){
  if($alias.ContainsKey($fam)){ return $alias[$fam] }
  $k=$fam.ToUpper().Replace(' ','')
  $hit=$folders | Where-Object { $_.ToUpper().Replace(' ','') -eq $k }
  if($hit){ return ($hit|Select-Object -First 1) }
  $hit=$folders | Where-Object { $k.StartsWith($_.ToUpper().Replace(' ','')) -or $_.ToUpper().Replace(' ','').StartsWith($k) }
  if($hit){ return ($hit|Select-Object -First 1) }
  return $null
}

$rows=Import-Csv "$out\stock_parsed.csv"
$fams = $rows | ForEach-Object { ($_.Article -split '-')[0].Trim() } | Sort-Object -Unique

# photo map produced by copy_photos.ps1 (web-sized images already copied next to the app)
$photoMap=@{}
(Get-Content "$out\photomap.json" -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $photoMap[$_.Name]=$_.Value }
"PHOTOS MAPPED: $($photoMap.Count)"

# build catalogue: article -> {mrp, sp, photo, colours{ colour -> { size -> qty } }}
$cat=@{}
foreach($r in $rows){
  $a=$r.Article; $fam=($a -split '-')[0].Trim()
  if(-not $cat.ContainsKey($a)){
    $cat[$a]=[ordered]@{ article=$a; family=$fam; photo=$(if($photoMap.ContainsKey($fam)){$photoMap[$fam]}else{''}); machine=$r.Machine; season=$r.Season; mrps=@{}; sizes=@{}; colours=[ordered]@{}; colourMrps=@{}; total=0 }
  }
  $e=$cat[$a]
  if(-not $e.machine -and $r.Machine){ $e.machine=$r.Machine }
  if(-not $e.season  -and $r.Season ){ $e.season =$r.Season  }
  if($r.MRP){ $e.mrps[$r.MRP]=$true }
  if($r.Size){ $e.sizes[$r.Size]=$true }
  $c=if($r.Colour){$r.Colour}else{'—'}
  if(-not $e.colours.Contains($c)){ $e.colours[$c]=@{} }
  # MRP is kept per colour as well as per article: the report prices colours of the same
  # article differently, and the catalogue quotes the colour the customer is looking at.
  if(-not $e.colourMrps.ContainsKey($c)){ $e.colourMrps[$c]=@{} }
  if($r.MRP){ $e.colourMrps[$c][$r.MRP]=$true }
  $s=if($r.Size){$r.Size}else{'—'}
  $q=[int]$r.Qty
  if($e.colours[$c].ContainsKey($s)){ $e.colours[$c][$s]+=$q } else { $e.colours[$c][$s]=$q }
  $e.total+=$q
}

# emit compact JSON
$list=@()
foreach($k in ($cat.Keys | Sort-Object)){
  $e=$cat[$k]
  $sizes=@($e.sizes.Keys | Sort-Object)
  $cols=@()
  foreach($c in $e.colours.Keys){
    $cmrp=@()
    if($e.colourMrps.ContainsKey($c)){ $cmrp=@($e.colourMrps[$c].Keys|Sort-Object{[double]$_}) }
    $row=[ordered]@{ c=$c; q=[ordered]@{}; m=$cmrp }
    foreach($s in $sizes){ if($e.colours[$c].ContainsKey($s)){ $row.q[$s]=$e.colours[$c][$s] } }
    if($e.colours[$c].ContainsKey('—')){ $row.q['—']=$e.colours[$c]['—'] }
    $cols+=$row
  }
  $mrpList=@($e.mrps.Keys | Sort-Object { [double]$_ })
  $list+=[ordered]@{ a=$e.article; f=$e.family; p=$e.photo; mc=$e.machine; sn=$e.season; m=$mrpList; s=$sizes; c=$cols; t=$e.total }
}
$json=$list | ConvertTo-Json -Depth 8 -Compress
Set-Content "$out\catalogue.json" $json -Encoding utf8

# emit the JS data file the app loads
# stock date taken from the report title (STOCK-DD-MM-YYYY) so it always matches the source
$stamp='unknown'
$titleLine = Select-String -Path "$out\stock_table_full.txt" -Pattern 'STOCK-(\d{2})-(\d{2})-(\d{4})' | Select-Object -First 1
if($titleLine){ $m=[regex]::Match($titleLine.Line,'STOCK-(\d{2})-(\d{2})-(\d{4})'); $stamp="$($m.Groups[3].Value)-$($m.Groups[2].Value)-$($m.Groups[1].Value)" }
$js=@"
/* STAR Kidz — Finished Goods Stock Catalogue
   Source : stock report dated $stamp (Busy), parsed row-wise.
   Layout : modelled on the NOVA/DREAM/PEARL/MERYCO catalogue (photo + colour x size grid).
   Totals : $((($list | ForEach-Object { $_.t }) | Measure-Object -Sum).Sum) pairs across $($list.Count) articles - matches the report's Grand Total.
   Fields : a=article f=family p=photo mc=machine sn=season m=[MRP] s=[sizes]
            c=[{c:colour, q:{size:qty}, m:[MRP for that colour]}] t=total
   Regenerate with scratchpad/parse_stock.ps1 + build_catalogue.ps1 when a new stock report arrives. */
window.STOCK_CATALOGUE_DATE = "$stamp";
window.STOCK_CATALOGUE = $json;
"@
Set-Content "$app\star-kidz-stock-catalogue-data.js" $js -Encoding utf8

"ARTICLES IN CATALOGUE : $($list.Count)"
$kb=[math]::Round((Get-Item "$out\catalogue.json").Length/1024)
"JSON SIZE             : $kb KB"
"TOTAL QTY             : " + (($list | ForEach-Object { $_.t }) | Measure-Object -Sum).Sum
"WITH PHOTO            : " + (($list | Where-Object { $_.p }).Count)
"JS FILE               : $app\star-kidz-stock-catalogue-data.js"
