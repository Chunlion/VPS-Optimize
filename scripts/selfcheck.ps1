Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "wsl.exe not found. Run this validation from Windows with WSL installed." -ForegroundColor Red
    exit 1
}

$wslRepoRoot = (& wsl.exe -e wslpath -a -u $repoRoot 2>$null)
$wslPathExitCode = $LASTEXITCODE
if ($wslPathExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($wslRepoRoot)) {
    Write-Host "Failed to convert repository path to a WSL path: $repoRoot" -ForegroundColor Red
    exit $(if ($wslPathExitCode -ne 0) { $wslPathExitCode } else { 1 })
}
$wslRepoRoot = $wslRepoRoot.Trim()

function ConvertTo-BashLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Invoke-WslBash {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Command
    )

    Write-Host "==> $Label (WSL)"
    $quotedRepoRoot = ConvertTo-BashLiteral $script:wslRepoRoot
    $bashCommand = "set -euo pipefail; cd $quotedRepoRoot; $Command"
    & wsl.exe -e bash -lc $bashCommand
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host "WSL validation step failed: $Label (exit $exitCode)" -ForegroundColor Red
        exit $exitCode
    }
}

Invoke-WslBash "build release artifact" "bash scripts/build.sh"
Invoke-WslBash "bash syntax" @'
bash -n scripts/build.sh scripts/selfcheck.sh scripts/compat-smoke.sh scripts/validate-traffic-guard-checker.sh tests/golden-render.sh tests/smoke.sh
bash -n vps.sh dist/vps.sh dog.sh xui-custom-manager.sh
for module in src/*.sh; do
    bash -n "$module"
done
'@
Invoke-WslBash "compat smoke" "bash scripts/compat-smoke.sh"
Invoke-WslBash "full smoke" "bash tests/smoke.sh"
Invoke-WslBash "selfcheck" "bash scripts/selfcheck.sh"

Write-Host "WSL selfcheck passed."
exit 0
