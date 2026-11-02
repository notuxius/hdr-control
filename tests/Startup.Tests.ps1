# Exercise the actual preference helpers and VBS launcher in isolation.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$id = [Guid]::NewGuid().ToString('N')
$temp = Join-Path ([IO.Path]::GetTempPath()) ('hdr-startup-test-' + $id)
$key = 'HKCU:\Software\HdrContextMenu-Test-' + $id
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $source = [IO.File]::ReadAllText((Join-Path $repo 'HdrTray.ps1'))
    $ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
    foreach ($name in @('Get-HdrStartupEnabled','Set-HdrStartupEnabled','Set-HdrAutomationPreference')) {
        $definition = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
        . ([scriptblock]::Create($definition.Extent.Text.Replace('HKCU:\Software\HdrContextMenu',$key)))
    }
    if (-not (Get-HdrStartupEnabled)) { throw 'Missing startup preference should default to enabled' }
    # Toggling the community list creates the settings key before the user has
    # ever saved StartWithWindows. An existing key with a missing value differs
    # from an absent key in Windows PowerShell's registry provider.
    Set-HdrAutomationPreference 'UseCommunityApps' $false
    if (-not (Get-HdrStartupEnabled)) { throw 'Community-list toggle must not break the default startup preference' }
    Set-HdrStartupEnabled $false
    Set-HdrAutomationPreference 'UseCommunityApps' $true
    if (Get-HdrStartupEnabled) { throw 'Disabled preference was not persisted' }
    $vbs = [IO.File]::ReadAllText((Join-Path $repo 'Toggle-HdrSdr.vbs')).Replace('HKCU\Software\HdrContextMenu\',($key.Replace('HKCU:','HKCU')+'\'))
    $launcher = Join-Path $temp 'Toggle-HdrSdr.vbs'
    [IO.File]::WriteAllText($launcher,$vbs)
    [IO.File]::WriteAllText((Join-Path $temp 'HdrSdrMenu.ps1'), 'param($Action) [IO.File]::WriteAllText((Join-Path $PSScriptRoot "result.txt"),$Action)')
    $sentinel = Join-Path $temp 'result.txt'
    function Run-Launcher([string]$Arguments, [bool]$ShouldLaunch) {
        if (Test-Path -LiteralPath $sentinel) { Remove-Item -LiteralPath $sentinel }
        $process = Start-Process -FilePath "$env:SystemRoot\System32\cscript.exe" -ArgumentList ('//NoLogo "'+$launcher+'" '+$Arguments) -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw ('Launcher failed: '+$Arguments) }
        if ((Test-Path -LiteralPath $sentinel) -ne $ShouldLaunch) { throw ('Wrong startup behavior: '+$Arguments) }
        if ($ShouldLaunch -and [IO.File]::ReadAllText($sentinel) -ne 'Watch') { throw 'Launcher chose wrong action' }
    }
    Run-Launcher 'Startup' $false
    Run-Launcher 'Startup ""' $false
    Run-Launcher 'Startup "LaunchNow"' $true
    Run-Launcher 'Watch' $true
    Set-HdrStartupEnabled $true
    Set-HdrAutomationPreference 'UseCommunityApps' $false
    Set-HdrStartupEnabled $true
    if ((Get-ItemPropertyValue -LiteralPath $key -Name UseCommunityApps) -ne 0) { throw 'Startup toggle erased the community-list preference' }
    Run-Launcher 'Startup' $true
    'PASS: startup defaults with missing and partial settings, community-list toggles, persistence, disabled logon, explicit installer launch, and manual launch.'
} finally {
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key }
    # Delete only the known test files, then its empty temporary directory.
    foreach ($name in @('Toggle-HdrSdr.vbs','HdrSdrMenu.ps1','result.txt')) {
        $path = Join-Path $temp $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Remove-Item -LiteralPath $temp
}
