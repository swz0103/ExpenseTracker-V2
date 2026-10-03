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
    @{ Path = 'packages/app_core'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/bookkeeping'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/accounts'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/categories'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/tags'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/merchants'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/entry_drafts'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/amount_input'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/ledger'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/reports'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/budgets'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/credit_cards'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/investments'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/market_data'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/recurring_transactions'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/data_exchange'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/persistent_jobs'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/cloud_backup'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/modular_persistence'; Dirs = @('lib', 'test') },
    @{ Path = 'prototypes/backup_envelope'; Dirs = @('lib', 'test') },
    @{ Path = 'infrastructure/backup_security'; Dirs = @('lib', 'test') },
    @{ Path = 'infrastructure/ledger_sqlcipher'; Dirs = @('lib', 'test') },
    @{ Path = 'infrastructure/storage_sqlcipher'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/crash_worker.dart' },
    @{ Path = 'prototypes/validated_restore'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/restore_worker.dart' },
    @{ Path = 'prototypes/encrypted_storage'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/restore_worker.dart' },
    @{ Path = 'prototypes/storage_generation'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/generation_worker.dart' },
    @{ Path = 'prototypes/ledger_generation'; Dirs = @('lib', 'bin', 'test'); Worker = 'bin/ledger_worker.dart' },
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
        & $Dart (@('format', '--output=none', '--set-exit-if-changed') + $check.Dirs)
        if ($LASTEXITCODE -ne 0) {
            # Show the expected layout so a fix needs no local SDK.
            & $Dart (@('format') + $check.Dirs) | Out-Null
            git --no-pager diff -- .
            throw "dart format found unformatted files in $($check.Path)."
        }
        Invoke-CheckCommand $driver @('analyze')
        if ($check.ContainsKey('Worker')) {
            Invoke-CheckCommand $Dart @('build', 'cli', '--target', $check.Worker, '--output', '.dart_tool/worker')
        }
        $testArguments = @('test', '--reporter', 'expanded')
        if ($isFlutter) { $testArguments += '--concurrency=1' }
        Invoke-CheckCommand $driver $testArguments
        if ($check.ContainsKey('Architecture')) {
            Invoke-CheckCommand $Dart @('run', 'bin/check.dart', '../..')
        }
    } finally {
        Pop-Location
    }
}
Write-Host "Passed all selected host checks ($($selected.Count) packages). Device and cloud gates are separate."
