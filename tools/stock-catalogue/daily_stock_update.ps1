# Daily stock update, unattended.
#
# Picks up the newest STOCK-DD-MM-YYYY.xlsx from a watched folder, parses it, VERIFIES it
# against the report's own Grand Total, and only then rebuilds the catalogue data files.
#
# The verify step is the whole point. A stock catalogue is not an internal artifact - it
# goes out to parties as a PDF - so a build that disagrees with the report by even one
# carton must not ship. On any failure this script stops and changes nothing.
#
#   powershell -File daily_stock_update.ps1 -repo "C:\...\CLAUDE DATA"
#
# Options:
#   -watch <dir>   where the daily export lands            (default: the user's Downloads)
#   -file  <xlsx>  use this file instead of searching
#   -Commit        git-commit the rebuilt data files
#   -Push          git-push after committing (implies -Commit)
#
# Register it to run every weekday at 10:30:
#   $a=New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\...\tools\stock-catalogue\daily_stock_update.ps1" -repo "C:\...\CLAUDE DATA" -Commit'
#   $t=New-ScheduledTaskTrigger -Daily -At 10:30
#   Register-ScheduledTask -TaskName "STAR Kidz daily stock" -Action $a -Trigger $t
param(
  [Parameter(Mandatory=$true)][string]$repo,
  [string]$watch="$env:USERPROFILE\Downloads",
  [string]$file,
  [switch]$Commit,
  [switch]$Push
)
$ErrorActionPreference='Stop'
if($Push){$Commit=$true}
$tools=$PSScriptRoot
function Say($m){ "[{0:HH:mm:ss}] {1}" -f (Get-Date),$m }

if(-not (Test-Path "$repo\star-kidz-production-system.html")){
  throw "-repo does not look like the app checkout (no star-kidz-production-system.html): $repo"
}

# 1. Find the report -------------------------------------------------------------------
if(-not $file){
  if(-not (Test-Path $watch)){ throw "Watch folder not found: $watch" }
  $cand=Get-ChildItem $watch -Filter 'STOCK-*.xlsx' -File -ErrorAction SilentlyContinue |
        Where-Object{ $_.Name -match 'STOCK-\d{2}-\d{2}-\d{4}' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $cand){ Say "No STOCK-DD-MM-YYYY.xlsx in $watch - nothing to do."; exit 0 }
  $file=$cand.FullName
}
if(-not (Test-Path $file)){ throw "Not found: $file" }
$mm=[regex]::Match([System.IO.Path]::GetFileName($file),'STOCK-(\d{2})-(\d{2})-(\d{4})')
if(-not $mm.Success){ throw "Cannot read a date out of the file name (expected STOCK-DD-MM-YYYY.xlsx): $file" }
$date="$($mm.Groups[3].Value)-$($mm.Groups[2].Value)-$($mm.Groups[1].Value)"
Say "report : $([System.IO.Path]::GetFileName($file))  (stock as on $date)"

# Skip a report already built, so a daily trigger is harmless when nothing new arrived.
$dataFile="$repo\star-kidz-stock-catalogue-data.js"
if(Test-Path $dataFile){
  $cur=Select-String -Path $dataFile -Pattern 'STOCK_CATALOGUE_DATE\s*=\s*"([\d-]+)"' | Select-Object -First 1
  if($cur -and $cur.Matches[0].Groups[1].Value -eq $date){
    Say "catalogue is already built for $date - nothing to do."; exit 0
  }
}

# 2. Parse -----------------------------------------------------------------------------
Say "parsing..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\parse_stock_xlsx.ps1" -out $repo -file $file | Out-Host
if($LASTEXITCODE -ne 0){ throw "parse_stock_xlsx.ps1 failed ($LASTEXITCODE)" }

# 3. Verify - the gate ------------------------------------------------------------------
Say "verifying against the report's own Grand Total..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\verify_stock.ps1" -out $repo -file $file | Out-Host
if($LASTEXITCODE -ne 0){
  Say "VERIFY FAILED - the parse disagrees with the report. Nothing was rebuilt."
  exit 1
}

# 4. Rebuild ----------------------------------------------------------------------------
# -SkipPhotos reuses the images already in article-photos/; the image pass only needs
# rerunning when the photo archive itself changes, and it takes ~20 minutes.
Say "rebuilding photo index and full article catalogue..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\build_full_catalogue.ps1" -out $repo -SkipPhotos -date $date | Out-Host
if($LASTEXITCODE -ne 0){ throw "build_full_catalogue.ps1 failed ($LASTEXITCODE)" }

Say "rebuilding the stock catalogue data file..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\build_catalogue.ps1" -out $repo -date $date | Out-Host
if($LASTEXITCODE -ne 0){ throw "build_catalogue.ps1 failed ($LASTEXITCODE)" }

# 5. Report ------------------------------------------------------------------------------
$rows=Import-Csv "$repo\stock_parsed.csv"
$ctn=($rows|Measure-Object Qty -Sum).Sum
$prs=($rows|Measure-Object Pairs -Sum).Sum
$arts=@($rows|Select-Object -ExpandProperty Article -Unique).Count
Say "BUILT  $ctn ctn / $prs pairs / $arts articles as on $date"

# 6. Commit ------------------------------------------------------------------------------
if($Commit){
  $changed=git -C $repo status --porcelain -- star-kidz-stock-catalogue-data.js star-kidz-article-catalogue-data.js star-kidz-photo-index.js
  if(-not $changed){ Say "no data-file changes to commit."; exit 0 }
  git -C $repo add star-kidz-stock-catalogue-data.js star-kidz-article-catalogue-data.js star-kidz-photo-index.js
  git -C $repo commit -m "data: stock as on $date ($ctn cartons, $arts articles)" -m "Built by tools/stock-catalogue/daily_stock_update.ps1 from $([System.IO.Path]::GetFileName($file)) and verified against the report's own Grand Total." | Out-Host
  if($LASTEXITCODE -ne 0){ throw "git commit failed" }
  Say "committed."
  if($Push){
    git -C $repo push | Out-Host
    if($LASTEXITCODE -ne 0){ throw "git push failed" }
    Say "pushed."
  }
}
exit 0
