$out="C:\Users\VINAY\AppData\Local\Temp\claude\C--Users-VINAY-OneDrive---Ojas-Footwear-India-Private-Limited-Desktop-CLAUDE-DATA\2913ead1-0722-4ed7-98d5-ecf0be6986f3\scratchpad"
$lines=Get-Content "$out\stock_table_full.txt"
$rows=Import-Csv "$out\stock_parsed.csv"

# 1. Pull the report's own subtotal lines:  "<LABEL> Total   <n>"
$pdfTotals=@{}
foreach($ln in $lines){
  $m=[regex]::Match($ln,'^\s*(?<label>[A-Z0-9][A-Z0-9 \.\-/]*?)\s+Total\s+(?<n>\d+)\s*$')
  if($m.Success){
    $lab=$m.Groups['label'].Value.Trim().ToUpper()
    if($lab -eq 'GRAND'){continue}
    $n=[int]$m.Groups['n'].Value
    # A group repeats once per season (CLOSE / OPEN), so its subtotal line appears
    # more than once - sum them rather than keeping one.
    if($pdfTotals.ContainsKey($lab)){ $pdfTotals[$lab]+=$n } else { $pdfTotals[$lab]=$n }
  }
}
$grand=0
foreach($ln in $lines){ $m=[regex]::Match($ln,'Grand\s+Total\s+(\d+)'); if($m.Success){$grand=[int]$m.Groups[1].Value} }

"=========== STOCK CALCULATION CHECK - STOCK-27-07-2026 ==========="
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
