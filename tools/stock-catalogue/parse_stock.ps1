$out="C:\Users\VINAY\AppData\Local\Temp\claude\C--Users-VINAY-OneDrive---Ojas-Footwear-India-Private-Limited-Desktop-CLAUDE-DATA\2913ead1-0722-4ed7-98d5-ecf0be6986f3\scratchpad"
$lines=Get-Content "$out\stock_table_full.txt"

# Words that belong to the Mould/Upper description, never a colour
$mouldWords=@('KNITTED','WITHOUT','WITH','LACE','LINING','MESH','OTHERS','REXINE','SUEDE','PU','PVC','EVA','FOAM','LYCRA','CANVAS','NET','VELVET','SYNTHETIC','LEATHER','FUR','DENIM','SHINER','GLITTER','PRINT','PLAIN','TPR','AIRMIX','STUCKON','ROTARY','REGULAR','CUSTOM','CUT','BELLY','SANDAL','SHOE','SLIPPER','CLOG','BOOT')
$sizeRe='^\d+X\d+[A-Z]?$'
$artRe='^[A-Z][A-Z0-9]*(?:\s+[A-Z]+)?-[A-Z0-9\-]+$'

$curArticle='';$curColour='';$curSize='';$curSeries='';$curMachine='';$curSeason='';$curMould='';$curType='';$curMrp=''
$rows=New-Object System.Collections.ArrayList

foreach($ln in $lines){
  if(-not $ln.Trim()){continue}
  if($ln -match 'Season\s+MACHINE'){continue}
  if($ln -match 'STOCK-25-07-2026'){continue}
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

  # article = any token matching ARTICLE-NN
  $article=''
  for($i=0;$i -lt $toks.Count;$i++){
    $t=[string]$toks[$i]
    if($t -match $artRe -and $t -notmatch '^\d'){ $article=$t }
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

  # grouping labels that may appear on the same physical line
  foreach($t in $toks){
    $u=([string]$t).ToUpper()
    if($u -eq 'CLOSE' -or $u -eq 'OPEN'){ $curSeason=$u }
    elseif(@('PU','PVC','ROTARY','VERTICAL','STUCKON','EVA','AIR','AIRMIX') -contains $u){ $curMachine=$u }
  }

  if($article){ $curArticle=$article; $curColour=''; $curSize='' }
  if($colour){ $curColour=$colour }
  if($size){ $curSize=$size }
  if(-not $curArticle){continue}
  if($qty -le 0){continue}

  [void]$rows.Add([PSCustomObject]@{
    Article=$curArticle; Colour=$curColour; Size=$curSize; MRP=$mrp; SP=$sp; Qty=$qty
    Machine=$curMachine; Season=$curSeason
  })
}

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
