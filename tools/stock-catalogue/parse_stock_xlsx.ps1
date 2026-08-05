# Parses the Busy stock report exported as .xlsx into stock_parsed.csv.
#
# Prefer this over parse_stock.ps1 (the PDF route). The Excel export is one flat row per
# item with its own columns, so there is no column drift, no grouped cells to fill down
# and no subtotal lines to exclude - and it carries the FULL item name. The PDF's table
# splits a name like "STAR GOLA-V" across cells and it reads back as "STAR", which
# silently rolls that article's stock onto its neighbours; the report's own Grand Total
# still matches, so that class of error is invisible on the PDF route.
#
# Busy numbers the export columns ("7-Item Name", "9-Colour"), so headers are matched
# with any leading "<n>-" stripped rather than by exact text.
param(
  [string]$out=$env:SC_WORKDIR,
  [string]$file,
  [string]$sheet   # optional sheet name; otherwise the first sheet with Item Name + Colour
)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR)"}
if(-not $file){throw "Pass -file <STOCK-DD-MM-YYYY.xlsx>"}
if(-not (Test-Path $file)){throw "Not found: $file"}
Add-Type -AssemblyName System.IO.Compression.FileSystem

$z=[System.IO.Compression.ZipFile]::OpenRead($file)
function ReadEntry($n){
  $e=$z.Entries|Where-Object{$_.FullName -eq $n}
  if(-not $e){return ''}
  $r=New-Object System.IO.StreamReader($e.Open()); $t=$r.ReadToEnd(); $r.Dispose(); return $t
}
$shared=@()
foreach($m in [regex]::Matches((ReadEntry 'xl/sharedStrings.xml'),'(?s)<si>(.*?)</si>')){
  $shared+=[System.Net.WebUtility]::HtmlDecode((-join ([regex]::Matches($m.Groups[1].Value,'(?s)<t[^>]*>(.*?)</t>')|ForEach-Object{$_.Groups[1].Value})))
}
$wb=ReadEntry 'xl/workbook.xml'
$rels=ReadEntry 'xl/_rels/workbook.xml.rels'
$relMap=@{}
foreach($m in [regex]::Matches($rels,'Id="([^"]+)"[^>]*Target="([^"]+)"')){ $relMap[$m.Groups[1].Value]=$m.Groups[2].Value }
$sheetList=@()
foreach($m in [regex]::Matches($wb,'<sheet[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"')){
  $sheetList+=[PSCustomObject]@{Name=$m.Groups[1].Value;Path='xl/'+(($relMap[$m.Groups[2].Value]) -replace '^/xl/','')}
}

function ParseSheet($path){
  $x=ReadEntry $path
  $rows=New-Object System.Collections.ArrayList
  foreach($rm in [regex]::Matches($x,'(?s)<row[^>]*r="(\d+)"[^>]*>(.*?)</row>')){
    $cells=@{}
    foreach($cm in [regex]::Matches($rm.Groups[2].Value,'(?s)<c r="([A-Z]+)\d+"([^>]*)>(.*?)</c>')){
      $col=$cm.Groups[1].Value;$attr=$cm.Groups[2].Value;$inner=$cm.Groups[3].Value
      $v=''
      if($attr -match 't="s"'){ $iv=[regex]::Match($inner,'<v>(\d+)</v>'); if($iv.Success){$v=$shared[[int]$iv.Groups[1].Value]} }
      elseif($attr -match 't="inlineStr"'){ $v=-join ([regex]::Matches($inner,'(?s)<t[^>]*>(.*?)</t>')|ForEach-Object{$_.Groups[1].Value}) }
      else { $iv=[regex]::Match($inner,'<v>([^<]*)</v>'); if($iv.Success){$v=$iv.Groups[1].Value} }
      $cells[$col]=[System.Net.WebUtility]::HtmlDecode($v).Trim()
    }
    [void]$rows.Add($cells)
  }
  return $rows
}
function Label([string]$s){ ($s -replace '^\s*\d+\s*[-\s]\s*','').ToUpper().Trim() }

$rows=$null;$colOf=$null;$picked=''
foreach($s in $sheetList){
  if($sheet -and $s.Name -ne $sheet){continue}
  $r=ParseSheet $s.Path
  if(-not $r.Count){continue}
  $map=@{}
  foreach($k in $r[0].Keys){ $map[(Label $r[0][$k])]=$k }
  if($map.ContainsKey('ITEM NAME') -and $map.ContainsKey('COLOUR')){
    $rows=$r;$colOf=$map;$picked=$s.Name;break
  }
}
$z.Dispose()
if(-not $rows){throw "No sheet with an 'Item Name' + 'Colour' header found in $file"}

$cName=$colOf['ITEM NAME']; $cCol=$colOf['COLOUR']; $cSize=$colOf['SIZE']
$cMrp =$colOf['MRP'];       $cSp =$colOf['SALE PRICE']
$cQty =if($colOf.ContainsKey('STOCK')){$colOf['STOCK']}else{$colOf['QTY.']}
$cPair=if($colOf.ContainsKey('PAIR')){$colOf['PAIR']}else{''}   # pairs per carton
$cMach=if($colOf.ContainsKey('MACHINE')){$colOf['MACHINE']}else{''}
$cSeas=if($colOf.ContainsKey('SEASON')){$colOf['SEASON']}else{''}
$cSer =if($colOf.ContainsKey('ITEM SERIES')){$colOf['ITEM SERIES']}else{''}
$cMould=if($colOf.ContainsKey('MOULD/UPPER')){$colOf['MOULD/UPPER']}else{''}
foreach($n in 'ITEM NAME','COLOUR','SIZE','MRP'){ if(-not $colOf.ContainsKey($n)){throw "Column '$n' missing in $file"} }

$outRows=New-Object System.Collections.ArrayList
$skipped=0
for($i=1;$i -lt $rows.Count;$i++){
  $r=$rows[$i]
  $a="$($r[$cName])"
  $q="$($r[$cQty])"
  # a flat export has no grouped cells: a row without its own name/qty is a total line
  if(-not $a -or $q -notmatch '^-?\d+(\.\d+)?$'){ $skipped++; continue }
  if($a -match '(?i)\btotal\b'){ $skipped++; continue }
  $qty=[int][double]$q
  if($qty -le 0){ $skipped++; continue }
  # The report's quantity is in CARTONS (its Unit column says so). Pairs per carton
  # differ by size, and for a few articles even within one size, so pairs are worked
  # out line by line here rather than by one multiplier per article.
  $ppc=0
  if($cPair -and "$($r[$cPair])" -match '^\d+$'){ $ppc=[int]$r[$cPair] }
  [void]$outRows.Add([PSCustomObject]@{
    Article=$a
    Colour="$($r[$cCol])"
    Size="$($r[$cSize])"
    MRP="$($r[$cMrp])"
    SP=$(if($cSp){"$($r[$cSp])"}else{''})
    Qty=$qty
    PairPerCtn=$ppc
    Pairs=($qty*$ppc)
    Machine=$(if($cMach){"$($r[$cMach])".ToUpper()}else{''})
    Season=$(if($cSeas){"$($r[$cSeas])".ToUpper()}else{''})
    Series=$(if($cSer){"$($r[$cSer])"}else{''})
    Mould=$(if($cMould){"$($r[$cMould])"}else{''})
  })
}
$outRows|Export-Csv "$out\stock_parsed.csv" -NoTypeInformation -Encoding utf8

"SHEET        : $picked"
"ROWS PARSED  : $($outRows.Count)   (skipped $skipped non-stock rows)"
"TOTAL CARTONS: " + (($outRows|Measure-Object Qty -Sum).Sum) + "   <- this is what the report's Grand Total counts"
"TOTAL PAIRS  : " + (($outRows|Measure-Object Pairs -Sum).Sum)
"ARTICLES     : " + (@($outRows|Select-Object -ExpandProperty Article -Unique).Count)
"COLOURS      : " + (@($outRows|Where-Object{$_.Colour}|Select-Object -ExpandProperty Colour -Unique).Count)
"SIZES        : " + (@($outRows|Where-Object{$_.Size}|Select-Object -ExpandProperty Size -Unique).Count)
"MACHINES     : " + ((@($outRows|Where-Object{$_.Machine}|Select-Object -ExpandProperty Machine -Unique)|Sort-Object) -join ', ')
""
"--- per machine ---"
$outRows|Group-Object Machine|Sort-Object {($_.Group|Measure-Object Qty -Sum).Sum} -Descending|ForEach-Object{
  "{0,-10} {1}" -f $_.Name,($_.Group|Measure-Object Qty -Sum).Sum
}
"CSV          : $out\stock_parsed.csv"
