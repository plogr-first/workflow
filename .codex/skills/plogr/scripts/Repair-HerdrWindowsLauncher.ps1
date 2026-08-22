[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('opencode','codex','gemini')][string]$Tool)
$ErrorActionPreference = 'Stop'
$bin = Join-Path $env:APPDATA 'npm'
$launcher = Join-Path $bin "$Tool.cmd"
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
  throw "Expected Windows launcher was not found: $launcher"
}
$p = Start-Process -FilePath $launcher -ArgumentList '--version' -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "$Tool launcher validation failed with exit $($p.ExitCode)." }
"$Tool launcher passed Start-Process validation."
