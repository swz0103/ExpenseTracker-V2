# Run the existing host checks locally without starting GitHub Actions.
[CmdletBinding()]
param(
    [string[]]$Package = @('all'),
    [string]$Dart = 'dart',
    [string]$Flutter = 'flutter',
    [switch]$Offline,
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$checks = @(
    @{ Path = 'tooling/architecture_checks'; Dirs = @('lib', 'bin', 'test'); Architecture = $true },
    @{ Path = 'packages/foundation_values'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/accounts'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/categories'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/tags'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/ledger'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/modular_persistence'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/backup_envelope'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/validated_restore'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/restore_worker.dart' },
    @{ Path = 'prototypes/encrypted_storage'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/restore_worker.dart' },
    @{ Path = 'prototypes/storage_generation'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/generation_worker.dart' },
    @{ Path = 'prototypes/ledger_generation'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/ledger_worker.dart' },
    @{ Path = 'prototypes/transaction_boundary'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/worker.dart' },
    @{ Path = 'prototypes/android_foundation'; Dirs = @('lib', 'test', 'integration_test'); Flutter = $true },
    @{ Path = 'prototypes/expense_preview'; Dirs = @('lib', 'test', 'tool'); Flutter = $true }
)

if ($Package.Count -eq 0) { throw 'Select at least one package, or all.' }
foreach ($selection in $Package) {
    if ($selection -ne 'all' -and $selection -notin $checks.Path) {
        throw "Unknown package: $selection"
    }
}
$selected = @($checks | Where-Object { 'all' -in $Package -or $_.Path -in $Package })
if ($PlanOnly) {
    $selected | ForEach-Object { $_.Path }
    return
}

function Invoke-CheckCommand {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

# Sequential execution avoids native worker/DLL locks on Windows.
foreach ($check in $selected) {
    Write-Host "Checking $($check.Path)"
    Push-Location (Join-Path $repoRoot $check.Path)
    try {
        $isFlutter = $check.ContainsKey('Flutter')
        $driver = if ($isFlutter) { $Flutter } else { $Dart }
        $pubArguments = @('pub', 'get', '--enforce-lockfile')
        if ($Offline) { $pubArguments += '--offline' }
        Invoke-CheckCommand $driver $pubArguments
        Invoke-CheckCommand $Dart (@('format', '--output=none', '--set-exit-if-changed') + $check.Dirs)
        Invoke-CheckCommand $driver @('analyze')
        if ($check.ContainsKey('Worker')) {
            Invoke-CheckCommand $Dart @('build', 'cli', '--target', $check.Worker, '--output', '.dart_tool/worker')
        }
        Invoke-CheckCommand $driver @('test', '--reporter', 'expanded')
        if ($check.ContainsKey('Architecture')) {
            Invoke-CheckCommand $Dart @('run', 'bin/check.dart', '../..')
        }
    } finally {
        Pop-Location
    }
}
Write-Host "Passed all selected host checks ($($selected.Count) packages). Device and cloud gates are separate."
