# Formal Verification Test Suite Master Runner
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Cyan
Write-Host "HERDR MULTI-AGENT ORCHESTRATOR - FORMAL AUDIT SUITE" -ForegroundColor Cyan
Write-Host "Full lifecycle state-machine verification and stress test" -ForegroundColor Cyan
Write-Host "===========================================================================" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

$testSuites = @(
  @{ Name = 'Flow A: Single Task -> 5-Gate Independent Verification -> Safe Merge & Prune'; Script = (Join-Path $PSScriptRoot 'Test-FlowA-SingleTask-5Gates.ps1') },
  @{ Name = 'Flow B: Bugfix Audit Triage -> Gate Rejection -> Repair Loop -> Knowledge Harvest'; Script = (Join-Path $PSScriptRoot 'Test-FlowB-Bugfix-Repair-KnowledgeHarvest.ps1') },
  @{ Name = 'Flow C: Matrix Parallel Multi-Agent Pipeline -> Integration -> Pruning'; Script = (Join-Path $PSScriptRoot 'Test-FlowC-Matrix-Parallel-Integration-Prune.ps1') },
  @{ Name = 'Flow D: Reboot Recovery -> Session Lock -> Generational Naming (-rN) -> Takeover'; Script = (Join-Path $PSScriptRoot 'Test-FlowD-Reboot-SessionLock-GenerationNaming.ps1') },
  @{ Name = 'Boundaries: Windows Paths, JSON Atomicity, Lease Lock Race & GitHub CLI Gate'; Script = (Join-Path $PSScriptRoot 'Test-Boundaries-Robustness.ps1') }
)

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($suite in $testSuites) {
  $suiteStart = Get-Date
  Write-Host ">>> Executing Suite: $($suite.Name)..." -ForegroundColor White
  $status = 'PASS'
  $errorMsg = ''
  try {
    & $suite.Script
  } catch {
    $status = 'FAIL'
    $errorMsg = $_.Exception.Message
    Write-Host "FAIL: Suite failed: $errorMsg" -ForegroundColor Red
  }
  $duration = ((Get-Date) - $suiteStart).TotalMilliseconds
  $results.Add([pscustomobject]@{
    Suite = $suite.Name
    Status = $status
    DurationMs = [Math]::Round($duration, 2)
    Error = $errorMsg
  })
}

$totalDuration = ((Get-Date) - $startTime).TotalSeconds

Write-Host ""
Write-Host "===========================================================================" -ForegroundColor Cyan
Write-Host "  FORMAL VERIFICATION & STRESS TEST SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "===========================================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($r in $results) {
  $color = if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }
  $symbol = if ($r.Status -eq 'PASS') { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} ({2} ms)" -f $symbol, $r.Suite, $r.DurationMs) -ForegroundColor $color
  if ($r.Error) {
    Write-Host ("      Error: {0}" -f $r.Error) -ForegroundColor Red
  }
}

$allPassed = @($results | Where-Object { $_.Status -ne 'PASS' }).Count -eq 0
Write-Host "`nTotal Test Execution Time: $([Math]::Round($totalDuration, 2))s" -ForegroundColor Cyan

if ($allPassed) {
  Write-Host ">>> FORMAL AUDIT RESULT: PASS <<<`n" -ForegroundColor Green
  exit 0
} else {
  Write-Host ">>> FORMAL AUDIT RESULT: FAILED <<<`n" -ForegroundColor Red
  exit 1
}
