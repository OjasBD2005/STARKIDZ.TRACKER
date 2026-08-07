# Cross-checks stock_parsed.csv against the report's OWN printed totals.
#
# Two sources, because the two routes leave different artifacts:
#   -file <xlsx>  Excel route. The GROUPED sheet in the workbook carries the totals
#                 ("Grand Total", "VERTICAL Total", "ALEXA Total"). parse_stock_xlsx.ps1
#                 reads the FLAT sheet, so this is a genuine independent check - a
#                 different sheet, printed by Busy, of the same stock.
#   (default)     PDF route, reading stock_table_full.txt.
# Without -file on the Excel route there is nothing to check against and the old script
# printed "report=0 MISMATCH", which looks like a failure but is just a missing source.
param([string]$out=$env:SC_WORKDIR,[string]$file)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR); it must hold stock_parsed.csv"}
$rows=Import-Csv "$out\stock_parsed.csv"
$pdfTotals=@{}
$grand=0
$reportId='STOCK-?'

if($file){
  if(-not (Test-Path $file)){throw "Not found: $file"}
  $reportId=[regex]::Match([System.IO.Path]::GetFileName($file),'STOCK-\d{2}-\d{2}-\d{4}').Value
  if(-not $reportId){$reportId=[System.IO.Path]::GetFileName($file)}
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
  $relMap=@{}
  foreach($m in [regex]::Matches((ReadEntry 'xl/_rels/workbook.xml.rels'),'Id="([^"]+)"[^>]*Target="([^"]+)"')){ $relMap[$m.Groups[1].Value]=$m.Groups[2].Value }
  $sheetPaths=@()
  foreach($m in [regex]::Matches((ReadEntry 'xl/workbook.xml'),'<sheet[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"')){
    $sheetPaths+='xl/'+(($relMap[$m.Groups[2].Value]) -replace '^/xl/','')
  }
  # Each sheet is tallied SEPARATELY and the one printing the largest Grand Total is the
  # report; the workbook also holds small working sheets that print their own totals, and
  # merging them all together let a 1,679 ctn sheet overwrite the real 17,237.
  $perSheet=@()
  foreach($sp in $sheetPaths){
    $x=ReadEntry $sp
    $sGrand=0; $sTotals=@{}
    foreach($rm in [regex]::Matches($x,'(?s)<row[^>]*>(.*?)</row>')){
      $vals=@()
      # Cells carrying a value are "<c ...>...</c>"; empty ones are "<c ... />" and are
      # skipped by this pattern, which is fine - only the label and the number matter.
      foreach($cm in [regex]::Matches($rm.Groups[1].Value,'(?s)<c\b([^>]*?)(?<!/)>(.*?)</c>')){
        $attr=$cm.Groups[1].Value;$inner=$cm.Groups[2].Value;$v=''
        if($attr -match 't="s"'){ $iv=[regex]::Match($inner,'<v>(\d+)</v>'); if($iv.Success){$v=$shared[[int]$iv.Groups[1].Value]} }
        elseif($attr -match 't="inlineStr"'){ $v=-join ([regex]::Matches($inner,'(?s)<t[^>]*>(.*?)</t>')|ForEach-Object{$_.Groups[1].Value}) }
        else { $iv=[regex]::Match($inner,'<v>([^<]*)</v>'); if($iv.Success){$v=$iv.Groups[1].Value} }
        $vals+=[System.Net.WebUtility]::HtmlDecode($v).Trim()
      }
      $label=''
      foreach($v in $vals){ if($v -match '(?i)^(.*\S)\s+Total$'){ $label=$matches[1].Trim().ToUpper(); break } }
      if(-not $label){continue}
      # the quantity is the last numeric cell on the subtotal line
      $n=$null
      for($i=$vals.Count-1;$i -ge 0;$i--){ if($vals[$i] -match '^-?\d+(\.\d+)?$'){ $n=[int][double]$vals[$i]; break } }
      if($null -eq $n){continue}
      if($label -eq 'GRAND'){ $sGrand=$n; continue }
      # a group repeats once per season (CLOSE / OPEN), so sum rather than overwrite
      if($sTotals.ContainsKey($label)){ $sTotals[$label]+=$n } else { $sTotals[$label]=$n }
    }
    if($sGrand){ $perSheet+=[PSCustomObject]@{Grand=$sGrand;Totals=$sTotals} }
  }
  $z.Dispose()
  if(-not $perSheet.Count){throw "No 'Grand Total' row found in $file - cannot verify. Export the GROUPED stock report, not just the flat sheet."}
  $win=$perSheet|Sort-Object Grand -Descending|Select-Object -First 1
  $grand=$win.Grand; $pdfTotals=$win.Totals
} else {
  if(-not (Test-Path "$out\stock_table_full.txt")){
    throw "No stock_table_full.txt in $out. On the Excel route pass -file <STOCK-DD-MM-YYYY.xlsx> so there is something to verify against."
  }
  $lines=Get-Content "$out\stock_table_full.txt"
  # 1. Pull the report's own subtotal lines:  "<LABEL> Total   <n>"
  foreach($ln in $lines){
    $m=[regex]::Match($ln,'^\s*(?<label>[A-Z0-9][A-Z0-9 \.\-/]*?)\s+Total\s+(?<n>\d+)\s*$')
    if($m.Success){
      $lab=$m.Groups['label'].Value.Trim().ToUpper()
      if($lab -eq 'GRAND'){continue}
      $n=[int]$m.Groups['n'].Value
      if($pdfTotals.ContainsKey($lab)){ $pdfTotals[$lab]+=$n } else { $pdfTotals[$lab]=$n }
    }
  }
  foreach($ln in $lines){ $m=[regex]::Match($ln,'Grand\s+Total\s+(\d+)'); if($m.Success){$grand=[int]$m.Groups[1].Value} }
  $tl=Select-String -Path "$out\stock_table_full.txt" -Pattern 'STOCK-\d{2}-\d{2}-\d{4}' | Select-Object -First 1
  if($tl){ $reportId=[regex]::Match($tl.Line,'STOCK-\d{2}-\d{2}-\d{4}').Value }
}
"=========== STOCK CALCULATION CHECK - $reportId ==========="
""
$parsedGrand=($rows|Measure-Object Qty -Sum).Sum
"GRAND TOTAL   report={0}   parsed={1}   {2}" -f $grand,$parsedGrand,$(if($grand -eq $parsedGrand){'MATCH'}else{'MISMATCH'})
""

# 2. Machine-level check
"--- MACHINE TOTALS ---"
$byMach=$rows|Group-Object Machine|ForEach-Object{[PSCustomObject]@{Machine=$_.Name;Parsed=($_.Group|Measure-Object Qty -Sum).Sum}}
$machOk=0;$machBad=0
foreach($m in ($byMach|Sort-Object Parsed -Descending)){
  $key=$m.Machine.ToUpper()
  if($pdfTotals.ContainsKey($key)){
    $r=$pdfTotals[$key]
    $st=if($r -eq $m.Parsed){'MATCH';$machOk++}else{"DIFF ($($m.Parsed-$r))";$machBad++}
    "{0,-12} report={1,-7} parsed={2,-7} {3}" -f $m.Machine,$r,$m.Parsed,$st
  } else {
    "{0,-12} report=(none)  parsed={1}" -f $m.Machine,$m.Parsed
  }
}
""
# 3. Series-level check
"--- SERIES TOTALS (only those with a subtotal line) ---"
$bySer=$rows|ForEach-Object{$_ | Add-Member -NotePropertyName Fam -NotePropertyValue (($_.Article -split '-')[0].Trim()) -Force -PassThru} |
  Group-Object Fam|ForEach-Object{[PSCustomObject]@{Series=$_.Name;Parsed=($_.Group|Measure-Object Qty -Sum).Sum}}
$ok=0;$bad=0;$absent=0
$badList=@()
foreach($s in ($bySer|Sort-Object Parsed -Descending)){
  $key=$s.Series.ToUpper()
  if($pdfTotals.ContainsKey($key)){
    $r=$pdfTotals[$key]
    if($r -eq $s.Parsed){$ok++} else {$bad++; $badList+=("{0,-12} report={1,-7} parsed={2,-7} diff={3}" -f $s.Series,$r,$s.Parsed,($s.Parsed-$r))}
  } else { $absent++ }
}
"series matching report subtotal : $ok"
"series differing                : $bad"
"series with no subtotal line    : $absent"
if($badList.Count){ ""; "DIFFERENCES:"; $badList | ForEach-Object { $_ } }
""
"--- SANITY ---"
"rows parsed          : $($rows.Count)"
"articles             : " + (@($rows|Select-Object -ExpandProperty Article -Unique).Count)
"rows with no colour  : " + (@($rows|Where-Object{-not $_.Colour}).Count)
"rows with no size    : " + (@($rows|Where-Object{-not $_.Size}).Count)
"rows with qty<=0     : " + (@($rows|Where-Object{[int]$_.Qty -le 0}).Count)
"negative/absurd qty  : " + (@($rows|Where-Object{[int]$_.Qty -gt 5000}).Count)

# Exit code so an unattended run can gate on this: 0 only when the parse equals the
# report's own Grand Total. Anything else must not be shipped to a party.
""
if($grand -ne $parsedGrand){
  Write-Error "VERIFY FAILED: parsed $parsedGrand ctn vs the report's Grand Total $grand ctn (difference $([math]::Abs($parsedGrand-$grand))). Do not ship this build."
  exit 1
}
"VERIFY OK - parsed $parsedGrand ctn equals the report's Grand Total."
exit 0
