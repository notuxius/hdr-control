# Exercise the real change/verification logic against simulated displays only.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'HdrSdrMenu.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Runtime has parse errors' }
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-HdrChange'},$true)
Invoke-Expression $function.Extent.Text
function Start-Sleep { param($Milliseconds) }
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
Add-Type @'
using System;
using System.Collections.Generic;
namespace LocalHdrMenu {
    public class Display {
        public string Name = "Same model";
        public string DisplayId;
        public bool HdrSupported = true;
        public bool HdrEnabled;
        public Display Copy() { return (Display)MemberwiseClone(); }
    }
    public static class DisplayApi {
        public static Display[] Displays;
        public static List<string> Calls = new List<string>();
        public static bool IgnoreChanges;
        public static string FailId;
        public static bool ReplaceAfterSet;
        public static Display[] Read() { return Array.ConvertAll(Displays, d => d.Copy()); }
        public static string Identity(Display d) { return d.DisplayId; }
        public static void Set(Display d, bool enabled) {
            Calls.Add(d.DisplayId + ":" + enabled);
            if (d.DisplayId == FailId) throw new Exception("Simulated driver failure");
            foreach (var current in Displays) {
                if (current.DisplayId != d.DisplayId) continue;
                if (!IgnoreChanges) current.HdrEnabled = enabled;
                if (ReplaceAfterSet) current.DisplayId = "Replacement";
            }
        }
    }
}
'@
function Reset-Displays {
    $a = New-Object LocalHdrMenu.Display
    $a.DisplayId = 'QQ=='
    $a.HdrEnabled = $true
    $b = New-Object LocalHdrMenu.Display
    $b.DisplayId = 'Qg=='
    [LocalHdrMenu.DisplayApi]::Displays = @($a,$b)
    [LocalHdrMenu.DisplayApi]::Calls.Clear()
    [LocalHdrMenu.DisplayApi]::IgnoreChanges = $false
    [LocalHdrMenu.DisplayApi]::FailId = $null
    [LocalHdrMenu.DisplayApi]::ReplaceAfterSet = $false
}
function Expect-Failure($Work, $Message) {
    $failed = $false
    try { & $Work | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
Reset-Displays
$after = @(Invoke-HdrChange 'Toggle' ([LocalHdrMenu.DisplayApi]::Read()) 'QQ==')
Assert (-not $after[0].HdrEnabled -and -not $after[1].HdrEnabled) 'Target toggle must use only its own state, not the mixed global state'
Assert (([LocalHdrMenu.DisplayApi]::Calls -join ',') -eq 'QQ==:False') 'Target toggle changed another monitor'
$after = @(Invoke-HdrChange 'On' ([LocalHdrMenu.DisplayApi]::Read()) 'Qg==')
Assert (-not $after[0].HdrEnabled -and $after[1].HdrEnabled) 'Explicit On changed the wrong monitor'
$after = @(Invoke-HdrChange 'Off' ([LocalHdrMenu.DisplayApi]::Read()) 'Qg==')
Assert (-not $after[0].HdrEnabled -and -not $after[1].HdrEnabled) 'Explicit Off did not apply'
[LocalHdrMenu.DisplayApi]::Calls.Clear()
$null = Invoke-HdrChange 'Off' ([LocalHdrMenu.DisplayApi]::Read()) 'Qg=='
Assert ([LocalHdrMenu.DisplayApi]::Calls.Count -eq 0) 'Already applied explicit action should be a no-op'

foreach ($id in @('Missing','qg==')) {
    Expect-Failure { Invoke-HdrChange 'On' ([LocalHdrMenu.DisplayApi]::Read()) $id } 'Stale or case-mismatched IDs must fail, never fall back to all displays'
}
[LocalHdrMenu.DisplayApi]::Displays[1].HdrSupported = $false
Expect-Failure { Invoke-HdrChange 'On' ([LocalHdrMenu.DisplayApi]::Read()) 'Qg==' } 'Unsupported monitor must fail'
Assert ([LocalHdrMenu.DisplayApi]::Calls.Count -eq 0) 'Invalid selection must not make any display changes'

Reset-Displays
$after = @(Invoke-HdrChange 'Toggle' ([LocalHdrMenu.DisplayApi]::Read()) '')
Assert ($after[0].HdrEnabled -and $after[1].HdrEnabled) 'Global toggle must still enable all in mixed state'
$after = @(Invoke-HdrChange 'Toggle' ([LocalHdrMenu.DisplayApi]::Read()) '')
Assert (-not $after[0].HdrEnabled -and -not $after[1].HdrEnabled) 'Global toggle must still disable all when all are enabled'

Reset-Displays
[LocalHdrMenu.DisplayApi]::IgnoreChanges = $true
Expect-Failure { Invoke-HdrChange 'On' ([LocalHdrMenu.DisplayApi]::Read()) 'Qg==' } 'Unconfirmed change must fail'
Assert (([LocalHdrMenu.DisplayApi]::Calls -join ',') -eq 'Qg==:True,Qg==:False') 'Failure must restore only the selected monitor'

Reset-Displays
[LocalHdrMenu.DisplayApi]::Displays[0].HdrEnabled = $false
[LocalHdrMenu.DisplayApi]::FailId = 'Qg=='
Expect-Failure { Invoke-HdrChange 'On' ([LocalHdrMenu.DisplayApi]::Read()) '' } 'Driver failure must propagate'
Assert (-not [LocalHdrMenu.DisplayApi]::Displays[0].HdrEnabled) 'Partial global failure must restore the first monitor'

Reset-Displays
[LocalHdrMenu.DisplayApi]::ReplaceAfterSet = $true
Expect-Failure { Invoke-HdrChange 'On' ([LocalHdrMenu.DisplayApi]::Read()) 'Qg==' } 'Disconnected target must fail verification'
Assert (([LocalHdrMenu.DisplayApi]::Calls -join ',') -eq 'Qg==:True') 'Rollback must not change a replacement display'
'PASS: per-monitor On/Off/Toggle, duplicate names, stale IDs, unavailable displays, global toggles, verification, and rollback.'
