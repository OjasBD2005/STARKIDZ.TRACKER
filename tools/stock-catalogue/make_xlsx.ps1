# Minimal multi-sheet .xlsx writer (Open XML, inline strings) - no Python/LibreOffice needed.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function XmlEsc([string]$s){
  if($null -eq $s){return ''}
  $s=$s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&apos;'
  # strip control chars illegal in XML
  return ($s -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]','')
}
function ColName([int]$i){  # 1 -> A
  $n=''; while($i -gt 0){ $m=($i-1)%26; $n=[char](65+$m)+$n; $i=[int](($i-$m-1)/26) }
  return $n
}

# Build one worksheet's XML.
#   $rows  : array of object[] (row 1 = header)
#   $widths: array of int (character widths)
function SheetXml($rows,$widths){
  $sb=New-Object System.Text.StringBuilder
  [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
  if($widths -and $widths.Count){
    [void]$sb.Append('<cols>')
    for($i=0;$i -lt $widths.Count;$i++){
      [void]$sb.Append('<col min="'+($i+1)+'" max="'+($i+1)+'" width="'+$widths[$i]+'" customWidth="1"/>')
    }
    [void]$sb.Append('</cols>')
  }
  [void]$sb.Append('<sheetData>')
  for($r=0;$r -lt $rows.Count;$r++){
    $rowNum=$r+1
    [void]$sb.Append('<row r="'+$rowNum+'">')
    $cells=@($rows[$r])
    for($c=0;$c -lt $cells.Count;$c++){
      $ref=(ColName ($c+1))+$rowNum
      $v=$cells[$c]
      $style=if($rowNum -eq 1){' s="1"'}else{''}
      if($null -eq $v -or $v -eq ''){
        [void]$sb.Append('<c r="'+$ref+'"'+$style+'/>')
      }
      elseif($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){
        [void]$sb.Append('<c r="'+$ref+'"'+$style+'><v>'+$v+'</v></c>')
      }
      else{
        [void]$sb.Append('<c r="'+$ref+'"'+$style+' t="inlineStr"><is><t xml:space="preserve">'+(XmlEsc ([string]$v))+'</t></is></c>')
      }
    }
    [void]$sb.Append('</row>')
  }
  [void]$sb.Append('</sheetData><autoFilter ref="A1:'+(ColName $rows[0].Count)+$rows.Count+'"/></worksheet>')
  return $sb.ToString()
}

# $sheets: ordered hashtable  name -> @{rows=...; widths=...}
function WriteXlsx($path,$sheets){
  if(Test-Path $path){ Remove-Item $path -Force }
  $names=@($sheets.Keys)
  $ms=New-Object System.IO.MemoryStream
  $zip=New-Object System.IO.Compression.ZipArchive($ms,[System.IO.Compression.ZipArchiveMode]::Create,$true)
  function AddEntry($zip,$name,$content){
    $e=$zip.CreateEntry($name,[System.IO.Compression.CompressionLevel]::Optimal)
    $w=New-Object System.IO.StreamWriter($e.Open(),(New-Object System.Text.UTF8Encoding($false)))
    $w.Write($content); $w.Flush(); $w.Dispose()
  }

  # [Content_Types].xml
  $ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
  $ct+='<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
  $ct+='<Default Extension="xml" ContentType="application/xml"/>'
  $ct+='<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
  $ct+='<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
  for($i=1;$i -le $names.Count;$i++){
    $ct+='<Override PartName="/xl/worksheets/sheet'+$i+'.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
  }
  $ct+='</Types>'
  AddEntry $zip '[Content_Types].xml' $ct

  AddEntry $zip '_rels/.rels' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'

  # workbook + rels
  $wb='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
  $rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  for($i=1;$i -le $names.Count;$i++){
    $wb+='<sheet name="'+(XmlEsc $names[$i-1])+'" sheetId="'+$i+'" r:id="rId'+$i+'"/>'
    $rels+='<Relationship Id="rId'+$i+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet'+$i+'.xml"/>'
  }
  $wb+='</sheets></workbook>'
  $rels+='<Relationship Id="rId'+($names.Count+1)+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
  AddEntry $zip 'xl/workbook.xml' $wb
  AddEntry $zip 'xl/_rels/workbook.xml.rels' $rels

  # styles: 0 = normal Arial, 1 = bold white on dark blue (header)
  $st='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
  $st+='<fonts count="2"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font></fonts>'
  $st+='<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0C1733"/><bgColor indexed="64"/></patternFill></fill></fills>'
  $st+='<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
  $st+='<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
  $st+='<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="center"/></xf></cellXfs>'
  $st+='<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
  AddEntry $zip 'xl/styles.xml' $st

  for($i=1;$i -le $names.Count;$i++){
    $s=$sheets[$names[$i-1]]
    AddEntry $zip ('xl/worksheets/sheet'+$i+'.xml') (SheetXml $s.rows $s.widths)
  }

  $zip.Dispose()
  [System.IO.File]::WriteAllBytes($path,$ms.ToArray())
  $ms.Dispose()
}
