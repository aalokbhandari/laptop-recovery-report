# Photo/video health: extension vs real format, Windows decode test, ffprobe truncation check. Read-only.
param([string]$Folder = "$env:USERPROFILE\Pictures\iphone", [string]$OutCsv = '.\photo-health.csv')
Add-Type -AssemblyName PresentationCore

function RealFormat([byte[]]$b) {
  $box = [Text.Encoding]::ASCII.GetString($b, 4, 4); $brand = [Text.Encoding]::ASCII.GetString($b, 8, 4)
  if ($box -eq 'ftyp') { if ($brand -match 'heic|heix|mif1|hevc') { 'heic' } elseif ($brand -match 'qt') { 'mov' } else { 'mp4' } }
  elseif ($b[0] -eq 0xFF -and $b[1] -eq 0xD8) { 'jpg' }
  elseif ($b[0] -eq 0x89 -and $b[1] -eq 0x50) { 'png' }
  elseif (($b | Where-Object { $_ -ne 0 }).Count -eq 0) { 'zeros' }
  else { 'unknown' }
}

$rows = foreach ($f in Get-ChildItem $Folder -Recurse -File | Where-Object Extension -match '^\.(heic|jpe?g|png|mov|mp4)$') {
  $fs = [IO.File]::OpenRead($f.FullName); $b = New-Object byte[] 12; [void]$fs.Read($b, 0, 12); $fs.Close()
  $ext = $f.Extension.TrimStart('.').ToLower() -replace 'jpeg', 'jpg'
  $real = RealFormat $b

  $state = 'ok'
  if ($real -in 'jpg', 'png', 'heic') {
    try { $s = [IO.File]::OpenRead($f.FullName); $d = [Windows.Media.Imaging.BitmapDecoder]::Create($s, 'None', 'OnLoad'); $null = $d.Frames[0].PixelWidth }
    catch { $state = 'does not decode' } finally { if ($s) { $s.Close() } }
  }
  if ($real -in 'mov', 'mp4', 'heic' -and (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    $err = & ffprobe -v error -show_entries format=duration -of csv=p=0 $f.FullName 2>&1 | Out-String
    if ($err -match 'moov atom not found') { $state = 'truncated: no moov index' }
    elseif ($err -match 'partial file') { $state = 'truncated: partial data' }
  }
  [pscustomobject]@{ File = $f.Name; Ext = $ext; Real = $real; ExtensionWrong = ($ext -ne $real); State = $state; Bytes = $f.Length }
}

$rows | Export-Csv $OutCsv -NoTypeInformation
"Files: $($rows.Count)   wrong extension: $(($rows | Where-Object ExtensionWrong).Count)"
$rows | Group-Object Ext, Real | Where-Object { $_.Group[0].ExtensionWrong } | Sort-Object Count -Descending | Select-Object Count, Name
$rows | Group-Object State | Select-Object Count, Name
