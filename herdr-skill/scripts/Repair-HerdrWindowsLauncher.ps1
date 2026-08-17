[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('opencode','codex','gemini')][string]$Tool)
$ErrorActionPreference = 'Stop'
$bin = Join-Path $env:APPDATA 'npm'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
foreach ($item in @(@{ path=(Join-Path $bin $Tool); suffix=".sh.$stamp" }, @{ path=(Join-Path $bin "$Tool.ps1"); suffix=".ps1.disabled.$stamp" })) {
  if (Test-Path -LiteralPath $item.path) {
    Move-Item -LiteralPath $item.path -Destination ($item.path + $item.suffix)
  }
}
$p = Start-Process -FilePath $Tool -ArgumentList '--version' -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "$Tool launcher validation failed with exit $($p.ExitCode)." }
"$Tool launcher passed Start-Process validation."
