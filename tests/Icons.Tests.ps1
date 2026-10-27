# Exercise the .NET Framework / Windows renderer used by NotifyIcon.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$repo=Split-Path $PSScriptRoot
$expected=@{HdrEnabled=1;HdrDisabled=2;HdrUnavailable=0;HdrEnableAction=1;HdrDisableAction=2;HdrUnavailableAction=0}
foreach($name in $expected.Keys) {
    foreach($size in @(16,20,24,32,48,64)) {
        $icon=[Drawing.Icon]::new((Join-Path $repo ($name+'.ico')),[Drawing.Size]::new($size,$size))
        $bitmap=[Drawing.Bitmap]::new($size,$size)
        $g=[Drawing.Graphics]::FromImage($bitmap)
        try {
            $g.Clear([Drawing.Color]::Transparent)
            $g.DrawIcon($icon,0,0)
            $counts=@(0,0,0)
            for($x=0;$x -lt $size;$x++) {for($y=0;$y -lt $size;$y++) {
                $p=$bitmap.GetPixel($x,$y)
                if($p.A -lt 128) {continue}
                if($p.R -gt $p.G*1.4 -and $p.R -gt $p.B*1.4) {$counts[0]++}
                if($p.G -gt $p.R*1.4 -and $p.G -gt $p.B*1.1) {$counts[1]++}
                if($p.R -gt $p.B*2 -and $p.G -gt $p.B*2) {$counts[2]++}
            }}
            $correct=$counts[$expected[$name]]
            $other=($counts | Measure-Object -Sum).Sum-$correct
            if($correct -lt $size -or $other -gt [Math]::Max(2,$correct*.05)) {
                throw "$name at $size pixels rendered with incorrect colors: $counts"
            }
        } finally {$g.Dispose();$bitmap.Dispose();$icon.Dispose()}
    }
}
'PASS: all six icons render with the correct status colors at 16, 20, 24, 32, 48, and 64 pixels.'
