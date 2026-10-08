# Crash and hardware-error scan. Read-only.
param([int]$Days = 30)
$since = (Get-Date).AddDays(-$Days)

"== Hardware"
Get-CimInstance Win32_ComputerSystem | Select-Object Model, @{n='RAM_GB';e={[math]::Round($_.TotalPhysicalMemory/1GB,1)}}
Get-CimInstance Win32_PhysicalMemory | Select-Object DeviceLocator, Manufacturer, PartNumber, @{n='GB';e={$_.Capacity/1GB}}, Speed
Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion, ReleaseDate

"== Unexpected shutdowns (Kernel-Power 41), grouped by bugcheck"
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime=$since} -ErrorAction SilentlyContinue | ForEach-Object {
  $x = [xml]$_.ToXml()
  ($x.Event.EventData.Data | Where-Object Name -in 'BugcheckCode','SleepInProgress' | ForEach-Object { "$($_.Name)=$($_.'#text')" }) -join ' '
} | Group-Object | Select-Object Count, Name

"== Blue screens (WER 1001)"
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$since} -ErrorAction SilentlyContinue |
  ForEach-Object { ($_.Message -split "`n")[0] }

"== Corrected hardware errors (WHEA-Logger), by event id"
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since} -ErrorAction SilentlyContinue |
  Group-Object Id | Select-Object Count, Name
