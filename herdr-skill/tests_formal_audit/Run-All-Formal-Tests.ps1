# Formal Verification Test Suite Master Runner
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  🛡️  HERDR MULTI-AGENT ORCHESTRATOR — AEROSPACE-GRADE FORMAL AUDIT SUITE       ║" -ForegroundColor Cyan
Write-Host "║      Zero-Tolerance Full-Lifecycle State Machine Verification & Stress Test   ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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
    Write-Host "❌ Suite Failed: $errorMsg" -ForegroundColor Red
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
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  FORMAL VERIFICATION & STRESS TEST SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

foreach ($r in $results) {
  $color = if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }
  $symbol = if ($r.Status -eq 'PASS') { '✔' } else { '✖' }
  Write-Host ("  {0} [{1}] {2} ({3} ms)" -f $symbol, $r.Status, $r.Suite, $r.DurationMs) -ForegroundColor $color
  if ($r.Error) {
    Write-Host ("      Error: {0}" -f $r.Error) -ForegroundColor Red
  }
}

$allPassed = @($results | Where-Object { $_.Status -ne 'PASS' }).Count -eq 0
Write-Host "`nTotal Test Execution Time: $([Math]::Round($totalDuration, 2))s" -ForegroundColor Cyan

if ($allPassed) {
  Write-Host ">>> ZERO-TOLERANCE AUDIT RESULT: 100% PASS (ZERO DEFECTS DETECTED) <<<`n" -ForegroundColor Green
  exit 0
} else {
  Write-Host ">>> ZERO-TOLERANCE AUDIT RESULT: FAILED <<<`n" -ForegroundColor Red
  exit 1
}
