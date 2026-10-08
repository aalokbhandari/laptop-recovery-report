# Rebuilds HEIC photos that Windows refuses to open because a trailing part of the file is cut off.
# A HEIC photo is a grid of HEVC tiles (an iPhone photo: 8 x 6 tiles of 512 x 512). When the main grid
# is intact and only an extra item at the end (depth map, HDR gain map) is truncated, every tile still
# decodes. This script decodes each tile with ffmpeg, stitches the grid, crops it to the real size,
# applies the photo's rotation and writes a JPG. The input files are only read.
param(
  [Parameter(Mandatory)][string[]]$Files,
  [Parameter(Mandatory)][string]$OutDir
)
New-Item -ItemType Directory -Force $OutDir | Out-Null
$work = Join-Path $env:TEMP "heic-tiles-$PID"

foreach ($file in $Files) {
  $name = [IO.Path]::GetFileNameWithoutExtension($file)
  $info = ffprobe -v error -show_stream_groups -show_streams -of json $file 2>$null | ConvertFrom-Json
  $grid = $info.stream_groups | Where-Object { $_.type -eq 'Tile Grid' } | Select-Object -First 1
  if (-not $grid) { "$name : no tile grid, skipped"; continue }

  $tileIds = $grid.streams | ForEach-Object { $_.index }
  $first = $info.streams | Where-Object index -eq $tileIds[0]
  $cols = [int]($grid.components[0].coded_width / $first.width)
  $rows = [int]($grid.components[0].coded_height / $first.height)
  $w = $grid.components[0].width; $h = $grid.components[0].height
  $rotation = ($grid.components[0].side_data_list | Where-Object rotation -ne $null | Select-Object -First 1).rotation

  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $work | Out-Null
  $i = 0
  foreach ($id in $tileIds) {
    ffmpeg -v quiet -y -i $file -map "0:$id" -frames:v 1 (Join-Path $work ('t{0:D3}.png' -f $i)) 2>$null
    $i++
  }
  $decoded = (Get-ChildItem $work -Filter 't*.png' | Where-Object Length -gt 0).Count
  if ($decoded -lt $tileIds.Count) { "$name : only $decoded of $($tileIds.Count) tiles decode, partial image" }

  $turn = switch ($rotation) { -90 { ',transpose=1' } 90 { ',transpose=2' } { $_ -in 180, -180 } { ',hflip,vflip' } default { '' } }
  $out = Join-Path $OutDir "$name.jpg"
  ffmpeg -v error -y -framerate 1 -i (Join-Path $work 't%03d.png') -vf "tile=${cols}x${rows},crop=${w}:${h}:0:0$turn" -frames:v 1 -q:v 2 $out 2>$null
  if (Test-Path $out) { "$name : rebuilt ${w}x${h} from $decoded tiles" } else { "$name : failed" }
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
