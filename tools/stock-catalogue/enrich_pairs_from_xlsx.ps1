# Adds PairPerCtn / Pairs to a PDF-derived stock_parsed.csv by carrying pairs-per-carton
# forward from an earlier EXCEL-derived parse.
#
# Pairs-per-carton is a property of the item master (article + size assortment), not of a
# day's stock, so carrying it forward on an exact article+size match is safe. Anything
# without an exact match is left at 0 rather than averaged - a made-up pair count on a
# sheet people order from is worse than a blank one.
#
# This is a fallback for a PDF-only day. The Excel export carries the Pair column itself
# and needs none of this; it also keeps article names the PDF merges (STAR GOLA-V etc).
param(
  [string]$out=$env:SC_WORKDIR,
  [string]$from                      # earlier Excel-derived stock_parsed.csv
)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR)"}
if(-not $from -or -not (Test-Path $from)){throw "Pass -from <earlier Excel-derived stock_parsed.csv>"}

$prev=Import-Csv $from
$rows=Import-Csv "$out\stock_parsed.csv"

function K([string]$a,[string]$s){ (($a.ToUpper().Trim()) -replace '[^A-Z0-9]','')+'|'+(($s.ToUpper().Trim()) -replace '[^A-Z0-9]','') }

# article+size -> pairs per carton, only where the earlier parse is unambiguous
$ppc=@{}; $conflict=@{}
foreach($r in $prev){
  $p=[int]$r.PairPerCtn
  if($p -le 0){continue}
  $k=K $r.Article $r.Size
  if($ppc.ContainsKey($k)){ if($ppc[$k] -ne $p){ $conflict[$k]=$true } }
  else{ $ppc[$k]=$p }
}
foreach($k in $conflict.Keys){ [void]$ppc.Remove($k) }   # same article+size, two assortments: don't guess

$hit=0;$miss=0
$outRows=New-Object System.Collections.ArrayList
foreach($r in $rows){
  $k=K $r.Article $r.Size
  $p=0
  if($ppc.ContainsKey($k)){ $p=$ppc[$k]; $hit++ } else { $miss++ }
  [void]$outRows.Add([PSCustomObject]@{
    Article=$r.Article; Colour=$r.Colour; Size=$r.Size; MRP=$r.MRP; SP=$r.SP
    Qty=[int]$r.Qty; PairPerCtn=$p; Pairs=([int]$r.Qty*$p)
    Machine=$r.Machine; Season=$r.Season
    Series=$(if($r.PSObject.Properties['Series']){$r.Series}else{''})
    Mould=$(if($r.PSObject.Properties['Mould']){$r.Mould}else{''})
  })
}
$outRows|Export-Csv "$out\stock_parsed.csv" -NoTypeInformation -Encoding utf8

"CARRIED FROM : $from"
"  article+size assortments known : $($ppc.Keys.Count)  (dropped $($conflict.Keys.Count) ambiguous)"
"ROWS         : $($outRows.Count)"
"  pairs resolved : $hit"
"  pairs unknown  : $miss   <- these carry 0 pairs; cartons are still exact"
"TOTAL CARTONS: " + (($outRows|Measure-Object Qty -Sum).Sum)
"TOTAL PAIRS  : " + (($outRows|Measure-Object Pairs -Sum).Sum) + "   (only from resolved rows)"
