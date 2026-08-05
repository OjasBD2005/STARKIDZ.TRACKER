# Article / colour / photo audit -> Article-Colour-Photo-Audit.xlsx
#
# One row per IN-STOCK article + colour, with the photo that will actually be shown and
# a status of Matched or NO PHOTO. The rules match what the app does, and both are about
# never showing a customer the wrong shoe:
#   Matched  - the index holds a photo of that exact shade, and that file is not used by
#              any other colour of the same article
#   NO PHOTO - anything else. No article photo stands in, no placeholder is invented.
# It also lists, separately, every file the index maps to more than one colour of one
# article, which is the failure that puts one image under three colour names.
#
# Needs, in -out: stock_parsed.csv   (parse_stock_xlsx.ps1)
# Reads the shipped star-kidz-photo-index.js, so it audits what is really deployed.
param([string]$out=$env:SC_WORKDIR)
if(-not $out){throw "Pass -out <workdir> (or set SC_WORKDIR)"}
. "$PSScriptRoot\make_xlsx.ps1"
$app="C:\Users\VINAY\OneDrive - Ojas Footwear India Private Limited\Desktop\CLAUDE DATA"
$dest="$app\Article-Colour-Photo-Audit.xlsx"

$rows=Import-Csv "$out\stock_parsed.csv"

# ---- the index as shipped ----
$idxTxt=Get-Content "$app\star-kidz-photo-index.js" -Raw
$idxJson=$idxTxt.Substring($idxTxt.IndexOf('{')).TrimEnd()
if($idxJson.EndsWith(';')){ $idxJson=$idxJson.Substring(0,$idxJson.Length-1) }
$idx=@{}
($idxJson|ConvertFrom-Json).PSObject.Properties|ForEach-Object{ $idx[$_.Name]=$_.Value }

# ---- in-stock articles and their colours ----
$art=[ordered]@{}
foreach($r in $rows){
  if([int]$r.Qty -le 0){continue}
  $k=$r.Article.ToUpper()
  if(-not $art.Contains($k)){
    $art[$k]=@{ Raw=$r.Article; Family=(($r.Article -split '-')[0].Trim()); Machine=$r.Machine
                Season=$r.Season; Colours=[ordered]@{} }
  }
  if(-not $r.Colour){continue}
  $c=$r.Colour.ToUpper()
  if(-not $art[$k].Colours.Contains($c)){
    $art[$k].Colours[$c]=@{ Ctn=0; Pairs=0; Sizes=@{}; MRPs=@{} }
  }
  $e=$art[$k].Colours[$c]
  $e.Ctn+=[int]$r.Qty; $e.Pairs+=[int]$r.Pairs
  if($r.Size){ $e.Sizes[$r.Size]=$true }
  if($r.MRP){ $e.MRPs[$r.MRP]=$true }
}

# ---- resolve each colour, and count how many colours of the article claim each file ----
$audit=New-Object System.Collections.ArrayList
$dupes=New-Object System.Collections.ArrayList
$matched=0;$noPhoto=0;$sharedBlocked=0
foreach($k in $art.Keys){
  $a=$art[$k]
  # how many colours of THIS article map to each file
  $use=@{}
  foreach($c in $a.Colours.Keys){
    $f=$idx["$k|$c"]
    if($f){ $use[$f]=[int]$use[$f]+1 }
  }
  foreach($f in $use.Keys){
    if($use[$f] -gt 1){
      $cols=@($a.Colours.Keys|Where-Object{ $idx["$k|$_"] -eq $f })
      [void]$dupes.Add([PSCustomObject]@{
        Article=$a.Raw; File=$f; Colours=($cols -join ', '); Count=$use[$f] })
    }
  }
  foreach($c in $a.Colours.Keys){
    $e=$a.Colours[$c]
    $f=$idx["$k|$c"]
    $status='NO PHOTO'; $shown=''; $why=''
    if(-not $f){
      $noPhoto++
      $why=if($idx.ContainsKey($k)){'only an article photo exists - not a photo of this shade'}
           else{'no photo named for this article'}
    }
    elseif([int]$use[$f] -gt 1){
      $sharedBlocked++
      $why="file is mapped to $($use[$f]) colours of this article - withheld from all of them"
    }
    else{ $status='Matched'; $shown=$f; $matched++ }
    [void]$audit.Add([PSCustomObject]@{
      Article=$a.Raw; Family=$a.Family; Machine=$a.Machine; Season=$a.Season; Colour=$c
      Ctn=$e.Ctn; Pairs=$e.Pairs
      Sizes=(($e.Sizes.Keys|Sort-Object) -join ', ')
      MRP=(($e.MRPs.Keys|Sort-Object{[double]$_}) -join ', ')
      Photo=$(if($shown){$shown}else{'NO PHOTO'})
      Status=$status; Reason=$why })
  }
}

$s1=@()
$s1+=,@('Article','Series','Machine','Season','Colour','Stock (cartons)','Stock (pairs)','Sizes','MRP (as in report)','Photo','Status','Why not matched')
foreach($r in ($audit|Sort-Object Article,Colour)){
  $s1+=,@($r.Article,$r.Family,$r.Machine,$r.Season,$r.Colour,[int]$r.Ctn,[int]$r.Pairs,$r.Sizes,$r.MRP,$r.Photo,$r.Status,$r.Reason)
}

$s2=@()
$s2+=,@('Article','Photo file','Colours mapped to it','How many','Effect')
foreach($d in ($dupes|Sort-Object Article,File)){
  $s2+=,@($d.Article,$d.File,$d.Colours,[int]$d.Count,'Withheld from every one of them - one image cannot be several colours')
}
if($s2.Count -eq 1){ $s2+=,@('None found','','','','No file is shared across colours of one article') }

$s3=@(
 ,@('ARTICLE / COLOUR / PHOTO AUDIT','')
 ,@('','')
 ,@('Audit run',"$(Get-Date -Format 'yyyy-MM-dd HH:mm')")
 ,@('In-stock article + colour rows',[int]$audit.Count)
 ,@('  Matched',[int]$matched)
 ,@('  NO PHOTO',[int]($audit.Count-$matched))
 ,@('    of which withheld for being shared across colours',[int]$sharedBlocked)
 ,@('Files mapped to more than one colour of an article',[int]$dupes.Count)
 ,@('','')
 ,@('RULES APPLIED','')
 ,@('Matched','The index holds a photo of that exact shade AND no other colour of the same article maps to that file.')
 ,@('NO PHOTO','Everything else. The article photo is never used to stand in for a colour, and nothing is guessed or placeholdered.')
 ,@('Why the article photo is not used','One image shown under three colour names is three wrong pictures, and it reads as if we hold that shade. ASH-09 showed BNT, MINT and PST all as the MINT photo before this rule.')
 ,@('How a colour gets matched','From the file name only - "ASH-09 BNT.jpg" is article ASH-09, colour BNT. Nothing is read out of the image.')
 ,@('The one inference allowed','If an article holds stock in exactly ONE colour, its photo is that colour. Articles with two or more colours are never inferred.')
 ,@('To fix a NO PHOTO','Rename the photo to "ARTICLE COLOUR.jpg" - e.g. "ASH-09 BNT.jpg" - put it in the archive and rerun the build.')
)

$sheets=[ordered]@{
  'Colour Photo Audit' =@{rows=$s1;widths=@(22,14,12,10,14,15,14,26,24,34,12,58)}
  'Shared Photos'      =@{rows=$s2;widths=@(22,34,40,11,58)}
  'Read me'            =@{rows=$s3;widths=@(52,110)}
}
foreach($name in $sheets.Keys){
  $r=$sheets[$name].rows
  $w=@($r[0]).Count
  for($i=1;$i -lt $r.Count;$i++){
    if(@($r[$i]).Count -ne $w){ throw "Sheet '$name' row $($i+1) has $(@($r[$i]).Count) cells, header has $w." }
  }
}
WriteXlsx $dest $sheets
"WROTE: $dest"
"  in-stock article+colour rows : $($audit.Count)"
"  Matched                      : $matched"
"  NO PHOTO                     : $($audit.Count-$matched)"
"  shared-file conflicts        : $($dupes.Count)"
$audit|Export-Csv "$out\colour_photo_audit.csv" -NoTypeInformation -Encoding utf8
