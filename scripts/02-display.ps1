# Display-drift checks: theme, AMD Vari-Bright, Night light, per-plan display settings. Read-only.

"== Theme"
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' | Select-Object AppsUseLightTheme, SystemUsesLightTheme

"== AMD driver keys (Vari-Bright / ABM)"
$class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
Get-ChildItem $class -ErrorAction SilentlyContinue | ForEach-Object {
  $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
  $p.PSObject.Properties | Where-Object Name -match 'Vari|ABM' | ForEach-Object { "$($p.DriverDesc): $($_.Name) = $($_.Value)" }
}

"== Display settings in every power plan (AC/DC)"
$video = '7516b95f-f776-4464-8c53-06167f40cc99'
$settings = [ordered]@{
  'Brightness %'        = 'aded5e82-b909-4619-9949-f5d71dac0bcb'
  'Dim after (s)'       = '17aaa29b-8b43-4b94-aafe-35f64daaf1ee'
  'Adaptive brightness' = 'fbd9aa66-9553-4097-ba44-ed6e9d65eab8'
  'Adv. color bias'     = '684c3e69-a4f7-4014-8754-d45179a56167'
}
foreach ($line in powercfg /l | Select-String 'GUID: ([0-9a-f-]{36})\s+\((.+?)\)') {
  $guid = $line.Matches[0].Groups[1].Value; $name = $line.Matches[0].Groups[2].Value
  $values = foreach ($k in $settings.Keys) {
    $o = powercfg /qh $guid $video $settings[$k] | Out-String
    $m = [regex]::Matches($o, 'Current (AC|DC) Power Setting Index: 0x([0-9a-f]+)')
    if ($m.Count -eq 2) { '{0}={1}/{2}' -f $k, [Convert]::ToInt32($m[0].Groups[2].Value,16), [Convert]::ToInt32($m[1].Groups[2].Value,16) }
  }
  "$name : $($values -join '  ')"
}

"== Armoury Crate scenario profile (current state)"
$ac = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter '*ArmouryCrate*' | Select-Object -First 1
if ($ac) { Get-Content "$($ac.FullName)\LocalState\ScenarioProfile\Config\CurrentStatusCache.json" -Raw -ErrorAction SilentlyContinue }
