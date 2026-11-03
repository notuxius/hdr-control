# Solar decisions only; no Windows location request or display writes.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path (Split-Path $PSScriptRoot) 'TrayTheme.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase
function Assert($Condition,$Message) { if(-not $Condition) { throw $Message } }
foreach($case in @(
    @('2026-06-21',40.71,-74.01,'Eastern Standard Time',325,1231),
    @('2026-12-21',-33.87,151.21,'AUS Eastern Standard Time',341,1205),
    @('2026-03-20',51.48,0,'GMT Standard Time',362,1094),
    @('2026-06-21',35.68,139.69,'Tokyo Standard Time',265,1140)
)) {
    $date=[DateTime]$case[0]; $zone=[TimeZoneInfo]::FindSystemTimeZoneById($case[3])
    $rise=[LocalHdrMenu.BrightnessSun]::Crossing($date,$case[1],$case[2],$zone,$true)
    $set=[LocalHdrMenu.BrightnessSun]::Crossing($date,$case[1],$case[2],$zone,$false)
    Assert ($null -ne $rise -and $null -ne $set) ('Missing crossing: '+$case[3])
    Assert ([Math]::Abs($rise.TimeOfDay.TotalMinutes-$case[4]) -lt 10) ('Unexpected sunrise: '+$rise+' '+$case[3])
    Assert ([Math]::Abs($set.TimeOfDay.TotalMinutes-$case[5]) -lt 10) ('Unexpected sunset: '+$set+' '+$case[3])
    $utc=[TimeZoneInfo]::ConvertTimeToUtc($rise,$zone)
    Assert (-not [LocalHdrMenu.BrightnessSun]::IsDay($utc.AddMinutes(-1),$case[1],$case[2])) 'Sunrise switched early'
    Assert ([LocalHdrMenu.BrightnessSun]::IsDay($utc.AddMinutes(1),$case[1],$case[2])) 'Sunrise did not switch'
    $utc=[TimeZoneInfo]::ConvertTimeToUtc($set,$zone)
    Assert ([LocalHdrMenu.BrightnessSun]::IsDay($utc.AddMinutes(-1),$case[1],$case[2])) 'Sunset switched early'
    Assert (-not [LocalHdrMenu.BrightnessSun]::IsDay($utc.AddMinutes(1),$case[1],$case[2])) 'Sunset did not switch'
}
$zone=[TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time')
foreach($case in @(@('2026-06-21',$true),@('2026-12-21',$false))) {
    $date=[DateTime]$case[0]
    Assert ($null -eq [LocalHdrMenu.BrightnessSun]::Crossing($date,78.22,15.65,$zone,$true)) 'Polar day/night must not invent sunrise'
    Assert ($null -eq [LocalHdrMenu.BrightnessSun]::Crossing($date,78.22,15.65,$zone,$false)) 'Polar day/night must not invent sunset'
    foreach($hour in @(0,6,12,18)) {
        Assert ([LocalHdrMenu.BrightnessSun]::IsDay($date.AddHours($hour),78.22,15.65) -eq $case[1]) 'Polar brightness phase incorrect'
    }
}
# Local daylight-saving days have 23/25 hours; crossing must use each date's offset.
$zone=[TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
foreach($date in @([DateTime]'2026-03-08',[DateTime]'2026-11-01',[DateTime]'2028-02-29')) {
    $rise=[LocalHdrMenu.BrightnessSun]::Crossing($date,40.71,-74.01,$zone,$true)
    Assert ($rise.Date -eq $date.Date -and $rise.Hour -ge 5 -and $rise.Hour -le 8) 'DST or leap-day conversion failed'
}
'PASS: solar boundaries, both hemispheres, date-line offsets, polar day/night, daylight-saving transitions, and leap day.'
