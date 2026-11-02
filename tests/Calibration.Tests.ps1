# Simulate missing apps and failed launches without uninstalling or opening anything.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Get-AppxPackage($Name) {
    if ($script:queryFails) { throw 'Package query unavailable' }
    if ($Name -eq 'MicrosoftCorporationII.WindowsHDRCalibration' -and $script:appInstalled) {
        return [pscustomobject]@{PackageFamilyName='MicrosoftCorporationII.WindowsHDRCalibration_8wekyb3d8bbwe'}
    }
    if ($Name -eq 'Microsoft.WindowsStore' -and $script:storeInstalled) { return [pscustomobject]@{Name=$Name} }
}
function Start-Process($FilePath,$ArgumentList) {
    $kind=if ($ArgumentList -like 'shell:AppsFolder\*') {'App'} elseif ($FilePath -like 'ms-windows-store:*') {'Store'} else {'Web'}
    [void]$script:launches.Add($kind)
    if ($kind -in $script:failLaunch) { throw 'Launch unavailable' }
}
function Show-HdrMessage($Message) { $script:message=$Message }
foreach ($case in @(
    @{App=$true;Store=$true;Expected='App'},
    @{App=$true;Store=$false;Expected='App'},
    @{App=$false;Store=$true;Expected='Store'},
    @{App=$false;Store=$false;Expected='Web'},
    @{App=$true;Store=$true;Fail=@('App');Expected='App,Store'},
    @{App=$false;Store=$true;Fail=@('Store');Expected='Store,Web'},
    @{QueryFails=$true;Expected='Web'},
    @{App=$true;Store=$true;Fail=@('App','Store','Web');Expected='App,Store,Web';Message=$true}
)) {
    $script:appInstalled=$case.App; $script:storeInstalled=$case.Store; $script:queryFails=$case.QueryFails
    $script:failLaunch=$case.Fail; $script:message=$null; $script:launches=New-Object 'Collections.Generic.List[string]'
    Open-HdrCalibration
    Assert (($script:launches -join ',') -eq $case.Expected) ('Incorrect fallback sequence: '+($script:launches -join ','))
    Assert ([bool]$script:message -eq [bool]$case.Message) 'Only total launch failure should show an error'
}
Write-Output 'PASS: calibration app, Store, browser, and launch-failure fallbacks (8 scenarios).'
