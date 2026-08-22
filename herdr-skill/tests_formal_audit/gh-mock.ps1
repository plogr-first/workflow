param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CliArgs
)

$logFile = $env:GH_MOCK_LOG
if (-not $logFile) {
  $logFile = Join-Path $PSScriptRoot 'gh_mock_calls.log'
}

$callRecord = ($CliArgs -join ' ')
Add-Content -LiteralPath $logFile -Value "[$(Get-Date -Format o)] gh $callRecord" -Encoding utf8

$cmd = $CliArgs[0]

if ($cmd -eq 'auth') {
  # gh auth status
  exit 0
}

if ($cmd -eq 'pr') {
  $sub = $CliArgs[1]
  if ($sub -eq 'create') {
    # gh pr create --repo ... --head ... --base ... --title ... --body ...
    Write-Output "https://github.com/mock-org/mock-repo/pull/42"
    exit 0
  }
}

exit 0
