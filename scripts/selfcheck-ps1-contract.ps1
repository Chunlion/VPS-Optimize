Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$wrapperPath = Join-Path $repoRoot "scripts/selfcheck.ps1"

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($wrapperPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    exit 1
}

$scriptText = Get-Content -Raw -Path $wrapperPath
foreach ($needle in @("wsl.exe", "bash scripts/selfcheck.sh", 'exit $exitCode')) {
    if (-not $scriptText.Contains($needle)) {
        Write-Error "scripts/selfcheck.ps1 is missing required WSL delegation contract: $needle"
        exit 1
    }
}

foreach ($needle in @("bash scripts/build.sh", "bash scripts/compat-smoke.sh", "bash tests/smoke.sh", "bash tests/golden-render.sh", "go test ./...", "go vet ./...")) {
    if ($scriptText.Contains($needle)) {
        Write-Error "scripts/selfcheck.ps1 must delegate to scripts/selfcheck.sh instead of inlining: $needle"
        exit 1
    }
}

$pwshCommand = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($pwshCommand)) {
    $pwshCommand = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
}
if ([string]::IsNullOrWhiteSpace($pwshCommand)) {
    $pwshCommand = (Get-Command powershell -ErrorAction Stop).Source
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vpso-selfcheck-ps1-" + [guid]::NewGuid().ToString("N"))
$mockWsl = Join-Path $tmpDir "mock-wsl.cmd"
$logPath = Join-Path $tmpDir "wsl.log"
$failFlagPath = Join-Path $tmpDir "bash-exit-37.flag"
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    @'
@echo off
setlocal

if "%VPSO_WSL_MOCK_LOG%"=="" exit /b 98
>>"%VPSO_WSL_MOCK_LOG%" echo args=%*

if "%~1"=="-e" if "%~2"=="wslpath" if "%~3"=="-a" if "%~4"=="-u" (
    echo /mnt/c/Users/O'Brian/VPS-Optimize
    exit /b 0
)

if "%~1"=="-e" if "%~2"=="bash" if "%~3"=="-lc" goto bash

exit /b 99

:bash
>>"%VPSO_WSL_MOCK_LOG%" echo bash-command=%~4
if exist "%~dp0bash-exit-37.flag" exit /b 37
exit /b 0
'@ | Set-Content -LiteralPath $mockWsl -Encoding ASCII

    $env:VPSO_WSL_EXE = $mockWsl
    $env:VPSO_WSL_MOCK_LOG = $logPath
    Remove-Item -LiteralPath $logPath -ErrorAction SilentlyContinue

    $wrapperOutput = & $pwshCommand -NoLogo -NoProfile -File $wrapperPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $wrapperOutput | Out-Host
        Write-Error "scripts/selfcheck.ps1 should pass when mocked WSL succeeds; exit $LASTEXITCODE."
        exit 1
    }

    $log = Get-Content -Raw -LiteralPath $logPath
    $expectedCd = "cd '/mnt/c/Users/O'\''Brian/VPS-Optimize'"
    if ($log -notlike "*bash-command=set -euo pipefail; $expectedCd; bash scripts/selfcheck.sh*") {
        Write-Error "Mocked WSL bash command did not preserve quoted repo path and selfcheck delegation."
        exit 1
    }

    New-Item -ItemType File -Path $failFlagPath | Out-Null
    Remove-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
    $wrapperOutput = & $pwshCommand -NoLogo -NoProfile -File $wrapperPath 2>&1
    if ($LASTEXITCODE -ne 37) {
        $wrapperOutput | Out-Host
        Write-Error "scripts/selfcheck.ps1 must pass through mocked WSL bash exit code 37; got $LASTEXITCODE."
        exit 1
    }
}
finally {
    Remove-Item Env:VPSO_WSL_EXE -ErrorAction SilentlyContinue
    Remove-Item Env:VPSO_WSL_MOCK_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "selfcheck.ps1 WSL contract passed."
