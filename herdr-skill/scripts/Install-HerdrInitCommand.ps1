[CmdletBinding()]
param(
  [string]$BinDirectory = (Join-Path $HOME '.local\bin')
)
$ErrorActionPreference = 'Stop'
$herdrExe = 'C:\Users\Lenovo\AppData\Local\Programs\Herdr\bin\herdr.exe'
$initializer = Join-Path $PSScriptRoot 'Initialize-HerdrProject.ps1'
if (-not (Test-Path -LiteralPath $herdrExe -PathType Leaf)) { throw "Official Herdr executable not found: $herdrExe" }
if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) { throw "Initializer not found: $initializer" }
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
"$herdrExe" %*
exit /b %ERRORLEVEL%
:inithelp
echo Herdr project initialization
 echo Usage: herdr init
 echo Select task and verification agents, write herdr\dispatch-profile.json,
 echo then run npx skills@latest add mattpocock/skills.
exit /b 0
"@
Set-Content -LiteralPath $wrapper -Value $cmd -Encoding ascii
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ })
if ($parts -notcontains $BinDirectory) {
  [Environment]::SetEnvironmentVariable('Path', (($BinDirectory + ';' + $userPath).TrimEnd(';')), 'User')
  $pathChanged = $true
} else { $pathChanged = $false }
[pscustomobject]@{ wrapper = $wrapper; bin_directory = $BinDirectory; user_path_updated = $pathChanged; restart_terminal_required = $true } | ConvertTo-Json
exit 0
