# Disk use: free space, cache sizes, biggest profile folders. Read-only.

Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}}, HealthStatus
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus

function SizeGB($path) { [math]::Round(((Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2) }

"== Caches"
foreach ($p in "$env:TEMP", 'C:\Windows\Temp', "$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip\cache",
               "$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\AMD\DxCache", "$env:LOCALAPPDATA\CrashDumps") {
  if (Test-Path $p) { '{0,8} GB  {1}' -f (SizeGB $p), $p }
}

"== Biggest folders in the profile"
Get-ChildItem $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
  ForEach-Object { [pscustomobject]@{ GB = SizeGB $_.FullName; Name = $_.Name } } |
  Sort-Object GB -Descending | Select-Object -First 10
