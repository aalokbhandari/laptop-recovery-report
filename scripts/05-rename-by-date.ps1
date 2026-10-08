# Renames photos and videos into the order they were taken: NNNN_YYYY-MM-DD_HH-mm.ext
# Date source, in order: EXIF "Date taken", video "Media created", file modified time.
# Writes an undo CSV first. Run with -WhatIf to preview.
param([Parameter(Mandatory)][string]$Folder, [string]$UndoCsv = "$env:USERPROFILE\Desktop\rename-undo.csv", [switch]$WhatIf)

$shell = New-Object -ComObject Shell.Application
$ns = $shell.Namespace((Resolve-Path $Folder).Path)
$col = @{}
0..320 | ForEach-Object { $n = $ns.GetDetailsOf($null, $_); if ($n -in 'Date taken', 'Media created') { $col[$n] = $_ } }

$items = foreach ($it in $ns.Items()) {
  if ($it.IsFolder) { continue }
  $raw = $ns.GetDetailsOf($it, $col['Date taken']); $src = 'taken'
  if (-not $raw) { $raw = $ns.GetDetailsOf($it, $col['Media created']); $src = 'media' }
  $date = $null
  if ($raw) { try { $date = [datetime]::Parse(($raw -replace '[^\d/: APMapm]', '').Trim()) } catch {} }
  if (-not $date) { $date = (Get-Item -LiteralPath $it.Path).LastWriteTime; $src = 'file' }
  [pscustomobject]@{ Path = $it.Path; Date = $date; Source = $src }
}

$i = 0
$plan = $items | Sort-Object Date, { [IO.Path]::GetFileNameWithoutExtension($_.Path) } | ForEach-Object {
  $i++
  $name = '{0:D4}_{1:yyyy-MM-dd_HH-mm}{2}' -f $i, $_.Date, [IO.Path]::GetExtension($_.Path).ToLower()
  [pscustomobject]@{ Old = $_.Path; New = Join-Path (Split-Path $_.Path) $name; Source = $_.Source }
}

$plan | Export-Csv $UndoCsv -NoTypeInformation
if ($WhatIf) { $plan | Select-Object -First 20 | Format-Table -AutoSize; return }
foreach ($p in $plan) { Rename-Item -LiteralPath $p.Old -NewName (Split-Path $p.New -Leaf) }
"Renamed $($plan.Count) files. Undo list: $UndoCsv"
