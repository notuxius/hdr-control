# Test synchronization in isolated storage and a temporary registry key.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'HdrSdrMenu.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Runtime has parse errors' }
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Sync-HdrMenu'},$true)
Invoke-Expression $function.Extent.Text
$id=[guid]::NewGuid().ToString('N')
$installDir=Join-Path ([IO.Path]::GetTempPath()) ('HdrDesktopTest-'+$id)
$menuKey='HKCU:\Software\HdrDesktopTest-'+$id
$owner='HdrSdrMenu.LocalScript.v1'
$installedLauncher=Join-Path $installDir 'Toggle-HdrSdr.vbs'
New-Item -ItemType Directory -Path $installDir | Out-Null
New-Item -Path ($menuKey+'\command') -Force | Out-Null
Set-ItemProperty -LiteralPath $menuKey -Name Owner -Value $owner
function Display($supported,$enabled) { [pscustomobject]@{HdrSupported=$supported;HdrEnabled=$enabled} }
try {
    foreach ($case in @(
        @{Displays=@((Display $true $false));Label='Enable HDR';Icon='HdrDisabled.ico';Hidden=$false},
        @{Displays=@((Display $true $true));Label='Disable HDR';Icon='HdrEnabled.ico';Hidden=$false},
        @{Displays=@((Display $true $true),(Display $true $false));Label='Enable HDR';Icon='HdrEnabled.ico';Hidden=$false},
        @{Displays=@((Display $false $false));Label='HDR: Unavailable';Icon='HdrUnavailable.ico';Hidden=$true},
        @{Displays=@();Label='HDR: Unavailable';Icon='HdrUnavailable.ico';Hidden=$true},
        @{Displays=@((Display $true $false));Label='Enable HDR';Icon='HdrDisabled.ico';Hidden=$false}
    )) {
        Sync-HdrMenu $case.Displays
        $entry=Get-ItemProperty -LiteralPath $menuKey
        if ([IO.File]::ReadAllText((Join-Path $installDir 'MenuLabel.txt')) -ne $case.Label) { throw 'Nilesoft label mismatch' }
        if ([IO.File]::ReadAllText((Join-Path $installDir 'MenuIcon.txt')) -ne $case.Icon) { throw 'Nilesoft icon mismatch' }
        if ($entry.Icon -ne (Join-Path $installDir $case.Icon)) { throw 'Native icon mismatch' }
        if (($null -ne $entry.LegacyDisable) -ne $case.Hidden) { throw 'Native visibility mismatch' }
        if (-not $case.Hidden -and $entry.MUIVerb -ne $case.Label) { throw 'Native label mismatch' }
    }
    'PASS: desktop labels and icons for off, on, mixed, unavailable, no displays, and recovery.'
} finally {
    Remove-Item -LiteralPath $menuKey -Recurse
    foreach ($name in @('MenuLabel.txt','MenuIcon.txt')) { Remove-Item -LiteralPath (Join-Path $installDir $name) -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $installDir
}
