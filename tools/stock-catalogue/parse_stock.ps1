param([string]$out=$env:SC_WORKDIR)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR); it must hold stock_table_full.txt"}
$lines=Get-Content "$out\stock_table_full.txt"

# Words that belong to the Mould/Upper description, never a colour
$mouldWords=@('KNITTED','WITHOUT','WITH','LACE','LINING','MESH','OTHERS','REXINE','SUEDE','PU','PVC','EVA','FOAM','LYCRA','CANVAS','NET','VELVET','SYNTHETIC','LEATHER','FUR','DENIM','SHINER','GLITTER','PRINT','PLAIN','TPR','AIRMIX','STUCKON','ROTARY','REGULAR','CUSTOM','CUT','BELLY','SANDAL','SHOE','SLIPPER','CLOG','BOOT')
$sizeRe='^\d+X\d+[A-Z]?$'
# Article codes: ASH-02, FIRE BOLT-06, KSD-340-NEW, and the awkward ones the report
# also carries - GSD-250/CL, LITTLE-1(SHARK), KSJ-201(BLK-SOLE), LUKE-4(L).
$artRe='^[A-Z][A-Z0-9]*(?:\s+[A-Z]+)?-[A-Z0-9()/\.\-]+$'

$curArticle='';$curColour='';$curSize='';$curSeries='';$curMachine='';$curSeason='';$curMould='';$curType='';$curMrp=''
$rows=New-Object System.Collections.ArrayList

$lineNo=-1
foreach($ln in $lines){
  $lineNo++
  if(-not $ln.Trim()){continue}
  if($ln -match 'Season\s+MACHINE'){continue}
  if($ln -match 'STOCK-\d{2}-\d{2}-\d{4}'){continue}   # report title, repeats per page
  if($ln -match '(?i)\bTotal\b'){continue}   # subtotal / grand total rows

  # Stable tail: MRP  SP  QTY
  $m=[regex]::Match($ln,'^(?<left>.*?)\s+(?<mrp>\d+(?:\.\d+)?)\s+(?<sp>\d+)\s+(?<qty>\d+)\s*$')
  $inheritMrp=$false
  if(-not $m.Success){
    # Same row but MRP cell blank (grouped report) -> SP + QTY only; inherit MRP.
    # Bare single numbers are group-subtotal echoes and must stay excluded.
    if($ln -notmatch '^\s*\d+\s*$'){
      $m=[regex]::Match($ln,'^(?<left>.*?)\s+(?<sp>\d+)\s+(?<qty>\d+)\s*$')
      if($m.Success){$inheritMrp=$true}
    }
  }
  if(-not $m.Success){
    # No numeric tail: may still carry grouping labels (article/series) to remember
    $toks=($ln -split '\s{2,}') | ForEach-Object {$_.Trim()} | Where-Object {$_}
    foreach($t in $toks){ if($t -match $artRe){$curArticle=$t;$curColour='';$curSize=''} }
    continue
  }

  $mrp=if($inheritMrp){$curMrp}else{$m.Groups['mrp'].Value}
  $sp=$m.Groups['sp'].Value; $qty=[int]$m.Groups['qty'].Value
  if($mrp){$curMrp=$mrp}
  $left=$m.Groups['left'].Value
  $toks=@(($left -split '\s+') | Where-Object {$_})

  # size = trailing token.  Forms seen in the Busy report:
  #   6X9 / 6X9K / 11X13 (ranges), 8K / 4K (kids), "8 NO" (size number), bare 5 / 6
  $size=''
  if($toks.Count -gt 0){
    $last=[string]$toks[$toks.Count-1]
    $prev=if($toks.Count -ge 2){[string]$toks[$toks.Count-2]}else{''}
    if($last -match '^(?i)NO\.?$' -and $prev -match '^\d{1,2}$'){
      $size="$prev NO"
      if($toks.Count -ge 3){ $toks=@($toks[0..($toks.Count-3)]) } else { $toks=@() }
    }
    elseif($last -match $sizeRe -or $last -match '^\d+K$' -or $last -match '^\d{1,2}$'){
      $size=$last
      if($toks.Count -ge 2){ $toks=@($toks[0..($toks.Count-2)]) } else { $toks=@() }
    }
  }

  # Article = the Item Name cell. Preferred: the token straight after the TYPE cell
  # ("... REGULAR  SOLDIER  EVA ..."), which is the only way to catch article names
  # that carry no -NN suffix (SOLDIER, VENUS). Falls back to the ARTICLE-NN pattern
  # for rows that repeat the article without a TYPE cell.
  $article=''
  for($i=0;$i -lt $toks.Count-1;$i++){
    if(@('REGULAR','CUSTOM') -contains ([string]$toks[$i]).ToUpper()){
      $cand=[string]$toks[$i+1]
      if($cand -and ($mouldWords -notcontains $cand.ToUpper()) -and $cand -notmatch '^\d+(\.\d+)?$' -and $cand -notmatch $sizeRe){
        $article=$cand
      }
      break
    }
  }
  if(-not $article){
    for($i=0;$i -lt $toks.Count;$i++){
      $t=[string]$toks[$i]
      if($t -match $artRe -and $t -notmatch '^\d'){ $article=$t }
    }
  }

  # colour = last token that is not a mould word, not the article, not a size
  $colour=''
  for($i=$toks.Count-1;$i -ge 0;$i--){
    $t=[string]$toks[$i]
    if($t -eq $article){break}
    if($mouldWords -contains $t.ToUpper()){break}
    if($t -match $sizeRe){continue}
    if($t -match '^\d+$'){continue}
    $colour=$t; break
  }

  # Season is safe to read inline. MACHINE is NOT: some series share a machine's
  # name (the EVA school-shoe series sits under the STUCKON machine), so reading
  # it inline mislabels those rows. Machine is assigned in a second pass below,
  # using the report's own "<MACHINE> Total" boundaries.
  foreach($t in $toks){
    $u=([string]$t).ToUpper()
    if($u -eq 'CLOSE' -or $u -eq 'OPEN'){ $curSeason=$u }
  }

  if($article){ $curArticle=$article; $curColour=''; $curSize='' }
  if($colour){ $curColour=$colour }
  if($size){ $curSize=$size }
  if(-not $curArticle){continue}
  if($qty -le 0){continue}

  [void]$rows.Add([PSCustomObject]@{
    Article=$curArticle; Colour=$curColour; Size=$curSize; MRP=$mrp; SP=$sp; Qty=$qty
    Machine=''; Season=$curSeason; Line=$lineNo
  })
}

# ---- PASS 2: assign MACHINE from the report's own "<MACHINE> Total" boundaries ----
# Walk the machine-total lines in document order; every row before a boundary (and
# after the previous one) belongs to that machine. Each block is accepted only if
# its row-sum equals the total the report prints, so a wrong guess can't slip through.
$machineNames=@('PU','PVC','ROTARY','VERTICAL','STUCKON','EVA','AIRMIX','AIR')
$bounds=@()
for($i=0;$i -lt $lines.Count;$i++){
  $m=[regex]::Match($lines[$i],'^\s*(?<lab>[A-Z]+)\s+Total\s+(?<n>\d+)\s*$')
  if($m.Success -and ($machineNames -contains $m.Groups['lab'].Value.ToUpper())){
    $bounds+=[PSCustomObject]@{Line=$i;Machine=$m.Groups['lab'].Value.ToUpper();Total=[int]$m.Groups['n'].Value}
  }
}
$prev=-1; $assignedOk=0; $assignedBad=0
foreach($b in $bounds){
  $block=@($rows | Where-Object { $_.Line -gt $prev -and $_.Line -lt $b.Line -and -not $_.Machine })
  if($block.Count){
    $sum=($block|Measure-Object Qty -Sum).Sum
    if($sum -eq $b.Total){
      $block | ForEach-Object { $_.Machine=$b.Machine }
      $assignedOk++
      $prev=$b.Line
    } else { $assignedBad++ }   # not a machine boundary (a series shares the name) - skip it
  }
}
$unassigned=@($rows|Where-Object{-not $_.Machine}).Count


"MACHINE BLOCKS ACCEPTED : $assignedOk   (rejected label matches: $assignedBad)"
"ROWS WITHOUT A MACHINE  : $unassigned"
"PARSED ROWS : $($rows.Count)"
"TOTAL QTY   : " + ($rows | Measure-Object Qty -Sum).Sum
"ARTICLES    : " + ($rows | Select-Object -ExpandProperty Article -Unique).Count
"COLOURS     : " + ($rows | Where-Object{$_.Colour} | Select-Object -ExpandProperty Colour -Unique).Count
"SIZES       : " + ($rows | Where-Object{$_.Size} | Select-Object -ExpandProperty Size -Unique).Count
$rows | Export-Csv "$out\stock_parsed.csv" -NoTypeInformation -Encoding utf8
""
"SIZES FOUND : " + (($rows | Where-Object{$_.Size} | Select-Object -ExpandProperty Size -Unique | Sort-Object) -join ', ')
""
"SAMPLE:"
$rows | Select-Object -First 12 | Format-Table -AutoSize
