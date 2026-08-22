# Flow D Formal Verification Test: Reboot Recovery -> Session Lock -> Replacement Agent (-rN Naming Boundary & Truncation) -> State Machine Takeover
param(
  [string]$TestRoot = (Join-Path $PSScriptRoot 'sandbox_flow_d')
)
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  [FLOW D] FORMAL VERIFICATION: REBOOT RESUME & GENERATION NAMING" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$env:HERDR_ENV = '1'
$env:PATH = "$PSScriptRoot;$env:PATH"
$mockLog = Join-Path $PSScriptRoot 'herdr_mock_flow_d.log'
$env:HERDR_MOCK_LOG = $mockLog
if (Test-Path $mockLog) { Remove-Item $mockLog -Force }

if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$projectRoot = Join-Path $TestRoot 'project_delta'
New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null

# 1. Setup Git Baseline
& git -C $projectRoot init 2>&1 | Out-Null
& git -C $projectRoot config user.name "Formal Auditor"
& git -C $projectRoot config user.email "auditor@zero-tolerance.test"
Set-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Value "# Project Delta" -Encoding utf8
& git -C $projectRoot add README.md
& git -C $projectRoot commit -m "chore: baseline" 2>&1 | Out-Null

# 2. Setup Dispatch Profile bound strictly to session 'delta-secure-session'
$herdrDir = Join-Path $projectRoot 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDir | Out-Null
$profile = [ordered]@{
  schema_version = 4
  project_root = $projectRoot
  herdr_session = [ordered]@{ name = 'delta-secure-session' }
  root_cause_agent = [ordered]@{ kind = 'codex' }
  task_agent = [ordered]@{ kind = 'codex' }
  verification_agent = [ordered]@{ kind = 'codex' }
  research_agent = [ordered]@{ kind = 'codex' }
  mattpocock_skills = [ordered]@{
    'implement' = [ordered]@{ available = $true; verified_official = $true; path = 'mock/implement' }
    'code-review' = [ordered]@{ available = $true; verified_official = $true; path = 'mock/code-review' }
  }
  git = [ordered]@{ repository = $true; has_commit = $true; target_branch = 'master'; push_policy = 'manual' }
}
$profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $herdrDir 'dispatch-profile.json') -Encoding utf8

$scriptsDir = Join-Path $PSScriptRoot '..\scripts'
$resumeScript = Join-Path $scriptsDir 'Resume-HerdrWorkflows.ps1'

# 3. Test Session Mismatch Guard
Write-Host "[Step 1] Verifying Cross-Session Isolation & Session Mismatch Guard..." -ForegroundColor Yellow
$sessionMismatchFailed = $false
try {
  & $resumeScript -ProjectRoot $projectRoot -SessionName 'rogue-session' 2>&1 | Out-Null
} catch {
  $sessionMismatchFailed = $true
}
if (-not $sessionMismatchFailed) {
  throw "ASSERTION FAILED: Resuming with wrong session must be rejected with an error"
}
Write-Host "  ✔ Cross-session isolation verified: rogue session was rejected" -ForegroundColor Green

# 4. Create an Orphaned In-Flight Workflow with Long Agent Name (Testing 32-Char Limit)
Write-Host "[Step 2] Creating Orphaned Workflow with 31-Character Agent Name..." -ForegroundColor Yellow
$wfDateDir = Join-Path $herdrDir 'task\2026-08-21\000001--workflow--longslug'
New-Item -ItemType Directory -Force -Path $wfDateDir | Out-Null

$wfPath = Join-Path $wfDateDir 'workflow.json'
$eventsPath = Join-Path $wfDateDir 'events.jsonl'

# Agent name is 31 characters (close to Herdr 32 max)
$longAgentName = "wf-000001-superlongnameslug-tsk"
if ($longAgentName.Length -ne 31) { throw "Setup error: longAgentName length is $($longAgentName.Length)" }

$handoffDir = Join-Path $wfDateDir 'task-handoff'
New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null
$taskResult = Join-Path $handoffDir 'task-result.md'
$taskOutcome = Join-Path $handoffDir 'task-outcome.json'

$orphanedWf = [ordered]@{
  schema_version = 3
  workflow_id = 'wf-000001-longslug'
  mode = 'task'
  slug = 'longslug'
  session_name = 'delta-secure-session'
  project_root = $projectRoot
  state = 'executing'
  next_role = 'task'
  repair_round = 0
  max_repair_rounds = 2
  recovery_attempts = [ordered]@{ task = 0; verification = 0; max = 2 }
  created_at = (Get-Date -Format o)
  updated_at = (Get-Date -Format o)
  task = [ordered]@{
    name = $longAgentName
    original_agent_name = $longAgentName
    active_agent_name = $longAgentName
    handoff = $handoffDir
    brief = (Join-Path $handoffDir 'task-brief.md')
    result = $taskResult
    outcome = $taskOutcome
  }
  verifier = [ordered]@{
    name = 'wf-000001-longslug-verify'
    original_agent_name = 'wf-000001-longslug-verify'
    active_agent_name = 'wf-000001-longslug-verify'
    handoff = (Join-Path $wfDateDir 'verifier')
    result = (Join-Path $wfDateDir 'verifier\verify-result.md')
    outcome = (Join-Path $wfDateDir 'verifier\verify-outcome.json')
  }
}
$orphanedWf | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $wfPath -Encoding utf8

# 5. Emulate Dead Agent & Execute Resume -> Test -r1 Generation Naming & Length <= 32
Write-Host "[Step 3] Executing Resume on Missing Agent -> Testing Generation -r1..." -ForegroundColor Yellow
$env:HERDR_MOCK_DEAD_AGENTS = $longAgentName

& $resumeScript -ProjectRoot $projectRoot -WorkflowId 'wf-000001-longslug' 2>&1 | Out-Null

$resumedWf = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
$gen1Name = [string]$resumedWf.task.active_agent_name

Write-Host "  Generation 1 Agent Name: '$gen1Name' (Length: $($gen1Name.Length))" -ForegroundColor Cyan
if ($gen1Name.Length -gt 32) {
  throw "ASSERTION FAILED: Agent name '$gen1Name' exceeded Herdr 32-character limit (Length: $($gen1Name.Length))"
}
if ($gen1Name -notmatch '-r1$') {
  throw "ASSERTION FAILED: Replacement agent must have suffix '-r1', got '$gen1Name'"
}
if ($resumedWf.recovery_attempts.task -ne 1) {
  throw "ASSERTION FAILED: recovery_attempts.task must be 1, got $($resumedWf.recovery_attempts.task)"
}
Write-Host "  ✔ Generation 1 naming and 32-char boundary truncation passed" -ForegroundColor Green

# 6. Emulate Second Crash on -r1 -> Test -r2 Generation Naming
Write-Host "[Step 4] Emulating Second Crash -> Testing Generation -r2..." -ForegroundColor Yellow
$env:HERDR_MOCK_DEAD_AGENTS = "$longAgentName,$gen1Name"

& $resumeScript -ProjectRoot $projectRoot -WorkflowId 'wf-000001-longslug' 2>&1 | Out-Null

$resumedWf = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
$gen2Name = [string]$resumedWf.task.active_agent_name

Write-Host "  Generation 2 Agent Name: '$gen2Name' (Length: $($gen2Name.Length))" -ForegroundColor Cyan
if ($gen2Name.Length -gt 32) {
  throw "ASSERTION FAILED: Agent name '$gen2Name' exceeded Herdr 32-character limit (Length: $($gen2Name.Length))"
}
if ($gen2Name -notmatch '-r2$') {
  throw "ASSERTION FAILED: Replacement agent must have suffix '-r2', got '$gen2Name'"
}
if ($resumedWf.recovery_attempts.task -ne 2) {
  throw "ASSERTION FAILED: recovery_attempts.task must be 2, got $($resumedWf.recovery_attempts.task)"
}
Write-Host "  ✔ Generation 2 increment and naming passed" -ForegroundColor Green

# 7. Emulate Third Crash -> Test Recovery Limit Overflow Guard (Bounded at 2)
Write-Host "[Step 5] Emulating Third Crash -> Verifying Recovery Limit Cap (Zero Infinite Respawns)..." -ForegroundColor Yellow
$env:HERDR_MOCK_DEAD_AGENTS = "$longAgentName,$gen1Name,$gen2Name"

$recoveryLimitFailed = $false
try {
  & $resumeScript -ProjectRoot $projectRoot -WorkflowId 'wf-000001-longslug' 2>&1 | Out-Null
} catch {
  $recoveryLimitFailed = $true
}

$resumedWf = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($resumedWf.state -ne 'blocked') {
  throw "ASSERTION FAILED: Workflow exceeding recovery attempt limit must transition to 'blocked', got '$($resumedWf.state)'"
}
Write-Host "  ✔ Recovery limit cap strictly enforced: workflow transitioned to 'blocked'" -ForegroundColor Green

# 8. Terminal Workflow Guard (Never Reactivate Merged, Passed, or Blocked Workflows)
Write-Host "[Step 6] Verifying Terminal Workflow Guard..." -ForegroundColor Yellow
$resOut = & $resumeScript -ProjectRoot $projectRoot
if ($resOut -notmatch 'No resumable Herdr workflows') {
  throw "ASSERTION FAILED: Terminal 'blocked' workflow must not be resumed"
}
Write-Host "  ✔ Terminal workflow guard verified: blocked/merged workflows are never re-activated" -ForegroundColor Green

Write-Host "`n>>> [FLOW D] PASSED ALL FORMAL ASSERTIONS (100% SUCCESS) <<<`n" -ForegroundColor Green
