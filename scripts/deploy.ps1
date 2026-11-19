#!/usr/bin/env pwsh
# Deploy configuration repositories on Windows.
#
# Windows sibling of scripts/deploy.sh. Reads config/repos.tsv, keeps entries
# whose os column contains "win", and runs the repo deploy script (.ps1 or .bat)
# from inside the repo directory.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string[]]$Only,
    [string[]]$Skip,
    [string]$ExtraArgs = "",
    [switch]$List,
    [switch]$FailFast
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$hubDir = Split-Path -Parent $scriptDir
$manifest = Join-Path $hubDir "config/repos.tsv"

if (-not (Test-Path $manifest)) { throw "manifest not found: $manifest" }

$rows = @()
foreach ($line in Get-Content $manifest) {
    if ($line -match '^\s*(#|$)') { continue }
    $f = $line -split "`t"
    while ($f.Count -lt 7) { $f += "" }
    $rows += [pscustomobject]@{
        Order  = $f[0]
        Name   = $f[1]
        Path   = $f[2]
        Branch = $f[3]
        Deploy = $f[4]
        Os     = $f[5]
        Args   = $f[6]
    }
}

function Test-InList($name, $path, $list) {
    if (-not $list -or $list.Count -eq 0) { return $false }
    foreach ($item in $list) {
        if ($item -eq $name -or $item -eq $path) { return $true }
    }
    return $false
}

$winRows = $rows | Where-Object { ($_.Os -split ',') -contains 'win' }

if ($List) {
    "{0,-6} {1,-24} {2,-32} {3,-8} {4}" -f "order", "name", "path", "branch", "deploy"
    foreach ($r in $winRows) {
        "{0,-6} {1,-24} {2,-32} {3,-8} {4}" -f $r.Order, $r.Name, $r.Path, $r.Branch, $r.Deploy
    }
    return
}

$total = 0; $ok = 0; $failed = 0; $skipped = 0
$failedNames = @()

foreach ($r in $winRows) {
    if ($Only.Count -gt 0 -and -not (Test-InList $r.Name $r.Path $Only)) { continue }
    if (Test-InList $r.Name $r.Path $Skip) { continue }

    $total++
    $repoDir = Join-Path $hubDir $r.Path

    if (-not (Test-Path $repoDir)) {
        "[{0}] {1,-24} FAIL (not cloned: {2})" -f $total, $r.Name, $r.Path
        $failed++; $failedNames += $r.Name
        if ($FailFast) { break }
        continue
    }

    $deployRel = $r.Deploy
    $candidates = @()
    if ($deployRel -match '\.ps1$') {
        $candidates += $deployRel
    }
    elseif ($deployRel -match '\.(sh|bat|cmd)$') {
        $base = $deployRel -replace '\.(sh|bat|cmd)$', ''
        $candidates += "$base.ps1"
        $candidates += "$base.bat"
        $candidates += "$base.cmd"
    }
    else {
        $candidates += $deployRel
    }

    $scriptPath = $null
    foreach ($c in $candidates) {
        $p = Join-Path $repoDir $c
        if (Test-Path $p) { $scriptPath = $p; break }
    }

    if (-not $scriptPath) {
        "[{0}] {1,-24} FAIL (missing {2})" -f $total, $r.Name, $r.Deploy
        $failed++; $failedNames += $r.Name
        if ($FailFast) { break }
        continue
    }

    $deployArgs = @()
    if ($r.Args -and $r.Args -ne "-") { $deployArgs += ($r.Args -split '\s+') }
    if ($ExtraArgs) { $deployArgs += ($ExtraArgs -split '\s+') }

    ""
    "==> [{0}] {1} ({2})" -f $total, $r.Name, $r.Path

    if ($DryRun) {
        "    [dry-run] cd {0} && {1} {2}" -f $r.Path, (Split-Path -Leaf $scriptPath), ($deployArgs -join ' ')
        $ok++
        continue
    }

    Push-Location $repoDir
    try {
        if ($scriptPath -match '\.ps1$') {
            & $scriptPath @deployArgs
            $code = $LASTEXITCODE
        }
        else {
            $argString = ($deployArgs -join ' ')
            & cmd.exe /c "`"$scriptPath`" $argString"
            $code = $LASTEXITCODE
        }
        if ($null -eq $code -or $code -eq 0) { $ok++ }
        else {
            "    FAIL: {0} exited {1}" -f $r.Name, $code
            $failed++; $failedNames += $r.Name
            if ($FailFast) { break }
        }
    }
    catch {
        "    FAIL: {0}: {1}" -f $r.Name, $_.Exception.Message
        $failed++; $failedNames += $r.Name
        if ($FailFast) { break }
    }
    finally {
        Pop-Location
    }
}

""
"---- summary ----"
"ok: {0}  failed: {1}  skipped: {2}  total: {3}" -f $ok, $failed, $skipped, $total
if ($failed -gt 0) {
    "failed: {0}" -f ($failedNames -join ', ')
    exit 1
}
