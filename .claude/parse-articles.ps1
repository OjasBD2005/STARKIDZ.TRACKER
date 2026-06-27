# Regenerates articles-data.js from articles-raw.txt
# Each raw line is "CODE SIZE COLOUR" where CODE may contain spaces.
# Rule: the SIZE starts at the first whitespace token that begins with a digit;
#       a following "NO", "NO." or "K" token is folded into the size.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$raw  = Join-Path $root 'articles-raw.txt'
$out  = Join-Path $root 'articles-data.js'

$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$rows = New-Object 'System.Collections.Generic.List[string]'

function Esc([string]$s){ return $s.Replace('\','\\').Replace('"','\"') }

foreach($line in Get-Content -LiteralPath $raw -Encoding UTF8){
  $t = ($line -replace '\s+',' ').Trim()
  if($t -eq ''){ continue }
  $tokens = $t -split ' '
  $idx = -1
  for($i=0; $i -lt $tokens.Count; $i++){ if($tokens[$i] -match '^[0-9]'){ $idx = $i; break } }

  if($idx -lt 1){
    # no size token (or line starts with a number) -> treat whole line as a code
    $code = $t; $size = ''; $colour = ''
  } else {
    $code = ($tokens[0..($idx-1)] -join ' ')
    $size = $tokens[$idx]
    $cstart = $idx + 1
    if($cstart -lt $tokens.Count -and $tokens[$cstart] -match '^(NO\.?|K)$'){ $size = "$size $($tokens[$cstart])"; $cstart++ }
    if($cstart -lt $tokens.Count){ $colour = ($tokens[$cstart..($tokens.Count-1)] -join ' ') } else { $colour = '' }
  }

  $key = "$code|$size|$colour"
  if($seen.Add($key)){
    $rows.Add('["' + (Esc $code) + '","' + (Esc $size) + '","' + (Esc $colour) + '"]')
  }
}

$nl = "`n"
$header = "// Auto-generated from articles-raw.txt - STAR Kidz article master$nl// Format: [ articleName, size, colour ]${nl}window.ARTICLES_RAW = [$nl"
$footer = "$nl];$nl"
Set-Content -LiteralPath $out -Value ($header + ($rows -join (",$nl")) + $footer) -Encoding utf8
Write-Host "Wrote $($rows.Count) unique article rows to articles-data.js"
