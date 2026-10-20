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
    @{ Path = 'tooling/architecture_checks'; Dirs = @('test') },
    @{ Path = 'packages/core'; Dirs = @('lib', 'test') },
    @{ Path = 'packages/domain'; Dirs = @('lib', 'test') },
    @{ Path = 'infrastructure/storage'; Dirs = @('lib', 'bin', 'test'); Workers = @('bin/crash_worker.dart', 'bin/posting_worker.dart') },
    @{ Path = 'infrastructure/vault'; Dirs = @('lib', 'test') },
    @{ Path = 'infrastructure/market'; Dirs = @('lib', 'test') },
    @{ Path = 'apps/expense_tracker'; Dirs = @('lib', 'test'); Flutter = $true }
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
        if (-not (Test-Path 'pubspec.lock')) {
            # A new package: resolve once and print the lock to commit.
            Invoke-CheckCommand $driver @('pub', 'get')
            Get-Content 'pubspec.lock'
            throw "$($check.Path) has no pubspec.lock; commit the lock printed above."
        }
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
        if ($check.ContainsKey('Workers')) {
            # Each worker is built on its own, then gathered in one bundle
            # where the tests look for it.
            New-Item -ItemType Directory -Force '.dart_tool/worker/bundle' | Out-Null
            foreach ($worker in $check.Workers) {
                $out = ".dart_tool/build-$([IO.Path]::GetFileNameWithoutExtension($worker))"
                Invoke-CheckCommand $Dart @('build', 'cli', '--target', $worker, '--output', $out)
                Copy-Item -Recurse -Force "$out/bundle/*" '.dart_tool/worker/bundle/'
            }
        }
        $testArguments = @('test', '--reporter', 'expanded')
        if ($isFlutter) { $testArguments += '--concurrency=1' }
        Invoke-CheckCommand $driver $testArguments
    } finally {
        Pop-Location
    }
}
Write-Host "Passed all selected host checks ($($selected.Count) packages). Device and cloud gates are separate."
