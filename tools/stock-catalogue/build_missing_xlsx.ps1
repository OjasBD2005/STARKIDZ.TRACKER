. "C:\Users\VINAY\AppData\Local\Temp\claude\C--Users-VINAY-OneDrive---Ojas-Footwear-India-Private-Limited-Desktop-CLAUDE-DATA\2913ead1-0722-4ed7-98d5-ecf0be6986f3\scratchpad\make_xlsx.ps1"
$out="C:\Users\VINAY\AppData\Local\Temp\claude\C--Users-VINAY-OneDrive---Ojas-Footwear-India-Private-Limited-Desktop-CLAUDE-DATA\2913ead1-0722-4ed7-98d5-ecf0be6986f3\scratchpad"
$dest="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA\Article-Photos-Missing.xlsx"

$cov=Import-Csv "$out\photo_coverage.csv"
$stockDate='27-07-2026'

# ---- Sheet 1: Missing Photos (no photo available at all) ----
$missing=@($cov | Where-Object { $_.Status -eq 'NO PHOTOS' } | Sort-Object {[int]$_.StockPairs} -Descending)
$s1=@()
$s1+=,@('Article','Series','Stock (pairs)','Colours','Sizes','MRP','Machine','Season','Photo folder found?','Action needed')
foreach($r in $missing){
  $s1+=,@($r.Article,$r.Series,[int]$r.StockPairs,[int]$r.Colours,[int]$r.Sizes,$r.MRP,$r.Machine,$r.Season,'No folder','SHOOT PHOTO')
}
$s1+=,@('TOTAL','',[int](($missing|Measure-Object StockPairs -Sum).Sum),'','','','','','','')

# ---- Sheet 2: Series Coverage ----
$bySeries=$cov | Group-Object Series | ForEach-Object {
  $g=$_.Group
  [PSCustomObject]@{
    Series=$_.Name
    Articles=$g.Count
    Pairs=($g|Measure-Object StockPairs -Sum).Sum
    Folder=$g[0].PhotoFolder
    Photos=[int]$g[0].PhotosInSeries
  }
} | Sort-Object Pairs -Descending
$s2=@()
$s2+=,@('Series','Articles in stock','Stock (pairs)','Photo folder','Photos in folder','Photos per article','Coverage risk')
foreach($r in $bySeries){
  $ratio=if($r.Articles -gt 0){[math]::Round($r.Photos/$r.Articles,1)}else{0}
  $risk=if($r.Photos -eq 0){'NO PHOTOS'} elseif($ratio -lt 1){'HIGH - fewer photos than articles'} elseif($ratio -lt 2){'MEDIUM - check per article'} else {'LOW'}
  $s2+=,@($r.Series,[int]$r.Articles,[int]$r.Pairs,$r.Folder,[int]$r.Photos,[double]$ratio,$risk)
}

# ---- Sheet 3: All Articles ----
$s3=@()
$s3+=,@('Article','Series','Machine','Season','Stock (pairs)','Colours','Sizes','MRP','Photo folder','Photos in folder','Photo status')
foreach($r in ($cov | Sort-Object {[int]$_.StockPairs} -Descending)){
  $s3+=,@($r.Article,$r.Series,$r.Machine,$r.Season,[int]$r.StockPairs,[int]$r.Colours,[int]$r.Sizes,$r.MRP,$r.PhotoFolder,[int]$r.PhotosInSeries,$(if($r.Status -eq 'NO PHOTOS'){'MISSING'}else{'Series photos exist'}))
}

# ---- Sheet 4: Read me ----
$s4=@(
 ,@('STAR KIDZ - ARTICLE PHOTO COVERAGE','')
 ,@('','')
 ,@('Stock report',"STOCK-$stockDate.pdf")
 ,@('Articles in stock',[int]$cov.Count)
 ,@('Articles with NO photo available',[int]$missing.Count)
 ,@('Their stock',[int](($missing|Measure-Object StockPairs -Sum).Sum))
 ,@('','')
 ,@('SHEET','WHAT IT SHOWS')
 ,@('Missing Photos','Articles with no photo folder at all. These definitely need a photo shoot.')
 ,@('Series Coverage','Per series: articles in stock vs photos on hand, with a risk flag.')
 ,@('All Articles','Every article in stock with its photo status.')
 ,@('','')
 ,@('IMPORTANT - HOW TO READ THIS','')
 ,@('Photos are per-article catalogue cards.','Each photo has the article name, colour, sizes and MRP printed inside the image (e.g. "Creta-03 / OLV / 4X7 I 5X8 I 6X9 / MRP 549.99").')
 ,@('Photo names do not carry the article.','Files are named creta (11).jpg, diya (11).jpg etc, so the folder tells us the SERIES but not WHICH article each photo is.')
 ,@('So "Series photos exist" is not a guarantee.','It means the series has photos - not that this exact article has one. Only the "Missing Photos" sheet is a certainty.')
 ,@('To get an exact per-article list','The images have to be read one by one (1,796 photos). Ask and this can be done series by series, starting with the highest-stock ones.')
 ,@('Quick win','Renaming photos to the article + colour (e.g. CRETA-03 OLV.jpg) would make this exact and automatic in future.')
 ,@('','')
 ,@('Note on folders','Two photo folders exist: Desktop\Article photos and PRODUCT PHOTOS\Article photos. They are NOT identical - SCHOOL SHOES has 16 photos in PRODUCT PHOTOS but 0 on the Desktop copy. Both were counted here.')
)

$sheets=[ordered]@{
  'Missing Photos'  =@{rows=$s1;widths=@(18,14,14,10,8,26,12,10,18,14)}
  'Series Coverage' =@{rows=$s2;widths=@(16,16,14,18,16,18,32)}
  'All Articles'    =@{rows=$s3;widths=@(18,14,12,10,14,10,8,26,18,16,20)}
  'Read me'         =@{rows=$s4;widths=@(38,110)}
}
WriteXlsx $dest $sheets
"WROTE: $dest"
"  size: " + [math]::Round((Get-Item $dest).Length/1KB) + " KB"
"  Missing Photos rows : " + ($s1.Count-2)
"  Series Coverage rows: " + ($s2.Count-1)
"  All Articles rows   : " + ($s3.Count-1)
