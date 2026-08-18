[CmdletBinding()]
param(
  [string]$BinDirectory = (Join-Path $HOME '.local\bin')
)
$ErrorActionPreference = 'Stop'
$herdrExe = 'C:\Users\Lenovo\AppData\Local\Programs\Herdr\bin\herdr.exe'
$initializer = Join-Path $PSScriptRoot 'Initialize-HerdrProject.ps1'
$resumer = Join-Path $PSScriptRoot 'Resume-HerdrWorkflows.ps1'
if (-not (Test-Path -LiteralPath $herdrExe -PathType Leaf)) { throw "Official Herdr executable not found: $herdrExe" }
if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) { throw "Initializer not found: $initializer" }
if (-not (Test-Path -LiteralPath $resumer -PathType Leaf)) { throw "Resumer not found: $resumer" }
New-Item -ItemType Directory -Force -Path $BinDirectory | Out-Null
$wrapper = Join-Path $BinDirectory 'herdr.cmd'
$cmd = @"
@echo off
setlocal
if /I "%~1"=="init" (
  if /I "%~2"=="--help" goto :inithelp
  if /I "%~2"=="-h" goto :inithelp
  shift
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$initializer" %*
  exit /b %ERRORLEVEL%
)
if /I "%~1"=="resume" goto :resume
"$herdrExe" %*
exit /b %ERRORLEVEL%
:inithelp
echo Herdr project initialization
 echo Usage: herdr init
 echo Select task, verification, and research agents, write herdr\dispatch-profile.json,
 echo then run npx skills@latest add mattpocock/skills.
exit /b 0
:resumehelp
echo Herdr workflow recovery
 echo Usage: herdr resume [workflow-id] [--all]
exit /b 0
:resume
if /I "%~2"=="--help" goto :resumehelp
if /I "%~2"=="-h" goto :resumehelp
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$resumer" %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%
"@
Set-Content -LiteralPath $wrapper -Value $cmd -Encoding ascii
$bashWrapper = Join-Path $BinDirectory 'herdr'
$bash = @"
#!/usr/bin/env bash
set -euo pipefail
herdr_exe='/mnt/c/Users/Lenovo/AppData/Local/Programs/Herdr/bin/herdr.exe'
initializer='C:\Users\Lenovo\.codex\skills\herdr\scripts\Initialize-HerdrProject.ps1'
resumer='C:\Users\Lenovo\.codex\skills\herdr\scripts\Resume-HerdrWorkflows.ps1'
if [ "`${1:-}" = "init" ]; then
  shift
  if [ "`${1:-}" = "--help" ] || [ "`${1:-}" = "-h" ]; then
    echo 'Herdr project initialization'
    echo 'Usage: herdr init'
    echo 'Select task, verification, and research agents, then install mattpocock/skills.'
    exit 0
  fi
  if command -v pwsh.exe >/dev/null 2>&1; then
    exec pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "`$initializer" "`$@"
  fi
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`$initializer" "`$@"
fi
if [ "`${1:-}" = "resume" ]; then
  shift
  if [ "`${1:-}" = "--help" ] || [ "`${1:-}" = "-h" ]; then
    echo 'Herdr workflow recovery'
    echo 'Usage: herdr resume [workflow-id] [--all]'
    exit 0
  fi
  if command -v pwsh.exe >/dev/null 2>&1; then
    exec pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "`$resumer" "`$@"
  fi
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`$resumer" "`$@"
fi
exec "`$herdr_exe" "`$@"
"@
[IO.File]::WriteAllText($bashWrapper, ($bash -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
$wslInstalled = $false
$wslError = $null
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
  $wslCommand = 'mkdir -p "$HOME/.local/bin"; install -m 755 /mnt/c/Users/Lenovo/.local/bin/herdr "$HOME/.local/bin/herdr"; touch "$HOME/.bashrc"; grep -Fqx ''# >>> herdr init integration >>>'' "$HOME/.bashrc" || printf ''\n# >>> herdr init integration >>>\nexport PATH="$HOME/.local/bin:$PATH"\n# <<< herdr init integration <<<\n'' >> "$HOME/.bashrc"'
  & wsl.exe -- bash -lc $wslCommand 2>$null
  if ($LASTEXITCODE -eq 0) { $wslInstalled = $true } else { $wslError = "wsl.exe exited $LASTEXITCODE" }
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ })
if ($parts -notcontains $BinDirectory) {
  [Environment]::SetEnvironmentVariable('Path', (($BinDirectory + ';' + $userPath).TrimEnd(';')), 'User')
  $pathChanged = $true
} else { $pathChanged = $false }
[pscustomobject]@{ wrapper = $wrapper; bash_wrapper = $bashWrapper; bin_directory = $BinDirectory; user_path_updated = $pathChanged; wsl_bash_installed = $wslInstalled; wsl_error = $wslError; restart_terminal_required = $true } | ConvertTo-Json
exit 0
