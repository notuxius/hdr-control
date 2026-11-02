# Exercise the .NET Framework / Windows renderer used by NotifyIcon.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$repo=Split-Path $PSScriptRoot
$expected=@{HdrEnabled=1;HdrEnabledPaused=1;HdrAutoEnabled=1;HdrAutoIdle=2;HdrDisabled=2;HdrUnavailable=0;HdrEnableAction=1;HdrDisableAction=2;HdrUnavailableAction=0}
foreach($name in $expected.Keys) {
    foreach($size in @(16,20,24,32,48,64)) {
        $icon=[Drawing.Icon]::new((Join-Path $repo ($name+'.ico')),[Drawing.Size]::new($size,$size))
        $bitmap=[Drawing.Bitmap]::new($size,$size)
        $g=[Drawing.Graphics]::FromImage($bitmap)
        try {
            $g.Clear([Drawing.Color]::Transparent)
            $g.DrawIcon($icon,0,0)
            if ($size -eq 16 -and $name -in @('HdrDisabled','HdrEnabledPaused','HdrAutoIdle','HdrAutoEnabled')) {
                # Read the dark symbol inside the colored badge. Color alone cannot distinguish play from pause.
                $rows = foreach ($y in 9..12) {
                    -join $(foreach ($x in 8..13) { if ($bitmap.GetPixel($x,$y).G -lt 110) { '#' } else { '.' } })
                }
                $symbol = if ($name -in @('HdrDisabled','HdrEnabledPaused')) { @('.#..#.') * 4 }
                          else { @('.##...','.####.','.####.','.##...') }
                if (($rows -join '/') -ne ($symbol -join '/')) { throw "$name rendered the wrong tray badge: $rows" }
            }
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
'PASS: all nine icons render with the correct status colors at 16, 20, 24, 32, 48, and 64 pixels.'
