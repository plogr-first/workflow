# Flow B Formal Verification Test: Bugfix Audit Triage -> Gate Rejection -> Repair Loop -> Knowledge Auto-Harvesting
param(
  [string]$TestRoot = (Join-Path $PSScriptRoot 'sandbox_flow_b')
)
$ErrorActionPreference = 'Stop'

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  [FLOW B] FORMAL VERIFICATION: BUGFIX REPAIR & KNOWLEDGE HARVEST" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$env:HERDR_ENV = '1'
$env:PATH = "$PSScriptRoot;$env:PATH"
$mockLog = Join-Path $PSScriptRoot 'herdr_mock_flow_b.log'
$env:HERDR_MOCK_LOG = $mockLog
if (Test-Path $mockLog) { Remove-Item $mockLog -Force }

if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$projectRoot = Join-Path $TestRoot 'project_beta'
New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null

# 1. Setup Git Baseline
& git -C $projectRoot init 2>&1 | Out-Null
& git -C $projectRoot config user.name "Formal Auditor"
& git -C $projectRoot config user.email "auditor@zero-tolerance.test"
Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Value '{"name":"beta-service","version":"1.0.0"}' -Encoding utf8
& git -C $projectRoot add package.json
& git -C $projectRoot commit -m "chore: initial baseline" 2>&1 | Out-Null
$baseSha = (& git -C $projectRoot rev-parse HEAD).Trim()

# 2. Setup Dispatch Profile with Required Bugfix Skills
$herdrDir = Join-Path $projectRoot 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDir | Out-Null
$profile = [ordered]@{
  schema_version = 4
  project_root = $projectRoot
  herdr_session = [ordered]@{ name = 'test-session' }
  root_cause_agent = [ordered]@{ kind = 'codex' }
  task_agent = [ordered]@{ kind = 'codex' }
  verification_agent = [ordered]@{ kind = 'codex' }
  research_agent = [ordered]@{ kind = 'codex' }
  mattpocock_skills = [ordered]@{
    'diagnosing-bugs' = [ordered]@{ available = $true; verified_official = $true; path = 'mock/diagnosing-bugs' }
    'implement' = [ordered]@{ available = $true; verified_official = $true; path = 'mock/implement' }
    'code-review' = [ordered]@{ available = $true; verified_official = $true; path = 'mock/code-review' }
  }
  git = [ordered]@{
    repository = $true
    has_commit = $true
    target_branch = 'master'
    push_policy = 'manual'
  }
}
$profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $herdrDir 'dispatch-profile.json') -Encoding utf8

# 3. Dispatch Bugfix Workflow
$scriptsDir = Join-Path $PSScriptRoot '..\scripts'
$startScript = Join-Path $scriptsDir 'Start-HerdrWorkflow.ps1'
$monitorScript = Join-Path $scriptsDir 'Monitor-HerdrWorkflow.ps1'

Write-Host "[Step 1] Dispatching Bugfix Workflow..." -ForegroundColor Yellow
$dispatchOut = & $startScript -Mode bugfix -Slug "mem-leak" -Prompt "Diagnose and fix WebSocket memory leak on disconnect" -ProjectRoot $projectRoot | ConvertFrom-Json

$wfPath = [string]$dispatchOut.workflow
$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.mode -ne 'bugfix') { throw "ASSERTION FAILED: Mode must be 'bugfix'" }
if ($wfObj.repair_round -ne 0) { throw "ASSERTION FAILED: Initial repair_round must be 0" }
Write-Host "  ✔ Bugfix workflow created with 3-skill prerequisite checks passed" -ForegroundColor Green

# 4. Task Agent submits Initial Candidate (Round 0)
Write-Host "[Step 2] Task Agent Submits Candidate (Round 0)..." -ForegroundColor Yellow
$taskWorktree = Join-Path $projectRoot '.worktrees\wf-mem-leak'
$taskBranch = 'wf/mem-leak'
& git -C $projectRoot worktree add -b $taskBranch $taskWorktree HEAD 2>&1 | Out-Null

$serverJs = Join-Path $taskWorktree 'server.js'
Set-Content -LiteralPath $serverJs -Value "function onDisconnect() { /* flawed fix */ }" -Encoding utf8
& git -C $taskWorktree add .
& git -C $taskWorktree commit -m "fix: attempt to clear disconnect handler" 2>&1 | Out-Null
$candSha0 = (& git -C $taskWorktree rev-parse HEAD).Trim()

$taskResultPath = [string]$wfObj.task.result
$taskOutcomePath = [string]$wfObj.task.outcome
Set-Content -LiteralPath $taskResultPath -Value @"
# Bugfix Attempt: Memory Leak
- Diagnosis: Unclosed listeners
- Seam: server.js
"@ -Encoding utf8

[ordered]@{
  state = 'candidate'
  summary = 'Attempted fix for socket disconnect'
  worktree_decision = 'isolated'
  worktree_path = $taskWorktree
  branch = $taskBranch
  base_sha = $baseSha
  candidate_sha = $candSha0
  changed_files = @('server.js')
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskOutcomePath -Encoding utf8

# 5. Monitor transitions candidate -> verifying
& $monitorScript -WorkflowPath $wfPath -Once

# 6. Verifier rejects candidate -> fix_required (Round 1 Trigger)
Write-Host "[Step 3] Verifier Rejects Round 0 Candidate (Gate 2 Regression Blocker)..." -ForegroundColor Yellow
$verResultPath = [string]$wfObj.verifier.result
$verOutcomePath = [string]$wfObj.verifier.outcome
$verHandoffDir = [string]$wfObj.verifier.handoff

Set-Content -LiteralPath $verResultPath -Value @"
# Verification Findings
- Gate 2 (Regression): FAILED. Reproduction loop still demonstrates leak on socket abort.
- Blocker: Listener reference not unbound from global EventEmitter.
"@ -Encoding utf8

Set-Content -LiteralPath (Join-Path $verHandoffDir 'verification.md') -Value @"
## Verification Blocker (P0)
1. Rule: Acceptance Gate 2 (Regression Seam)
2. Evidence: `node test/leak.test.js` exits with code 1; 4MB retained.
3. Repair: Remove EventEmitter subscription on socket close event.
"@ -Encoding utf8

[ordered]@{
  state = 'fix_required'
  summary = 'Reproduction loop still fails under heavy socket churn'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verOutcomePath -Encoding utf8

# 7. Monitor detects fix_required -> Increments repair_round to 1 -> Wakes Task Agent
Write-Host "[Step 4] Monitor Increments Repair Round to 1 & Wakes Task Agent..." -ForegroundColor Yellow
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'repairing') { throw "ASSERTION FAILED: State must transition to 'repairing', got '$($wfObj.state)'" }
if ($wfObj.next_role -ne 'task') { throw "ASSERTION FAILED: Next role must be 'task', got '$($wfObj.next_role)'" }
if ($wfObj.repair_round -ne 1) { throw "ASSERTION FAILED: repair_round must be 1, got $($wfObj.repair_round)" }
Write-Host "  ✔ State machine safely incremented repair_round to 1 and entered 'repairing'" -ForegroundColor Green

# 8. Task Agent applies true root cause fix (Round 1)
Write-Host "[Step 5] Task Agent Applies True Root Cause Fix..." -ForegroundColor Yellow
Set-Content -LiteralPath $serverJs -Value @"
function onDisconnect(socket) {
  socket.removeAllListeners();
  globalEmitter.off('data', socket.handler);
}
"@ -Encoding utf8
& git -C $taskWorktree add server.js
& git -C $taskWorktree commit -m "fix(ws): explicitly unbind global emitter on disconnect" 2>&1 | Out-Null
$candSha1 = (& git -C $taskWorktree rev-parse HEAD).Trim()

Set-Content -LiteralPath $taskResultPath -Value @"
# Task Result (Round 1 Fix)
### Root Cause
Global EventEmitter retained socket reference in listener closure after disconnect.

- Changed Files: server.js
- Reproduction Test: Green (0 bytes retained)
"@ -Encoding utf8

[ordered]@{
  state = 'candidate'
  summary = 'Completely eliminated socket listener retention leak'
  worktree_decision = 'isolated'
  worktree_path = $taskWorktree
  branch = $taskBranch
  base_sha = $baseSha
  candidate_sha = $candSha1
  changed_files = @('server.js')
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskOutcomePath -Encoding utf8

# 9. Monitor transitions to verifying
& $monitorScript -WorkflowPath $wfPath -Once

# 10. Verifier passes and merges
Write-Host "[Step 6] Verifier Confirms Fix Across All Gates & Merges..." -ForegroundColor Yellow
& git -C $projectRoot merge --ff-only $taskBranch 2>&1 | Out-Null
$mergeSha = (& git -C $projectRoot rev-parse HEAD).Trim()

Set-Content -LiteralPath $verResultPath -Value "# Verification Passed\nAll 5 gates verified; regression green." -Encoding utf8
Set-Content -LiteralPath (Join-Path $verHandoffDir 'verification.md') -Value "## Verification 5 Gates: ALL PASS" -Encoding utf8
[ordered]@{
  state = 'merged'
  summary = 'Memory leak verified fixed; clean merge'
  merge_sha = $mergeSha
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verOutcomePath -Encoding utf8

# 11. Monitor Finalizes Merge & Triggers Knowledge Harvesting
Write-Host "[Step 7] Monitor Finalizes Terminal Merge & Auto-Harvests Knowledge..." -ForegroundColor Yellow
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'merged') { throw "ASSERTION FAILED: Final state must be 'merged', got '$($wfObj.state)'" }

# 12. Verify Knowledge Base Auto-Harvesting Artifacts
Write-Host "[Step 8] Validating Pitfalls & Golden Rules Knowledge Artifacts..." -ForegroundColor Yellow
$jsonlPath = Join-Path $projectRoot '.knowledge\pitfalls.jsonl'
$mdPath = Join-Path $projectRoot '.knowledge\pitfalls.md'

if (-not (Test-Path -LiteralPath $jsonlPath)) { throw "ASSERTION FAILED: '$jsonlPath' was not generated" }
if (-not (Test-Path -LiteralPath $mdPath)) { throw "ASSERTION FAILED: '$mdPath' was not generated" }

$jsonlContent = Get-Content -LiteralPath $jsonlPath -Raw
$harvestedEntry = $jsonlContent.Trim() | ConvertFrom-Json
if ($harvestedEntry.slug -ne 'mem-leak') { throw "ASSERTION FAILED: Harvested slug mismatch" }
if ($harvestedEntry.root_cause -notmatch 'EventEmitter retained socket reference') {
  throw "ASSERTION FAILED: Root cause failed to extract correctly: $($harvestedEntry.root_cause)"
}
Write-Host "  ✔ JSONL Knowledge Record verified: $($harvestedEntry.id)" -ForegroundColor Green

$mdContent = Get-Content -LiteralPath $mdPath -Raw
if ($mdContent -notmatch '表象 \(Symptom\)' -or $mdContent -notmatch '根因 \(Root Cause\)') {
  throw "ASSERTION FAILED: Markdown knowledge document structure incomplete"
}
Write-Host "  ✔ Markdown Knowledge Document verified" -ForegroundColor Green

# 13. Test Max Repair Rounds Overflow Guard (Zero Infinite Loops)
Write-Host "[Step 9] Validating Max Repair Rounds Overflow Guard (Bounded at 2)..." -ForegroundColor Yellow
$testOverflowDir = Join-Path $TestRoot 'overflow_test'
New-Item -ItemType Directory -Force -Path $testOverflowDir | Out-Null
$overflowWfPath = Join-Path $testOverflowDir 'workflow.json'
$overflowEvents = Join-Path $testOverflowDir 'events.jsonl'

$overflowWf = [ordered]@{
  schema_version = 3
  workflow_id = 'wf-test-overflow'
  mode = 'bugfix'
  slug = 'overflow-bug'
  session_name = 'test-session'
  project_root = $projectRoot
  state = 'verifying'
  next_role = 'verification'
  repair_round = 2
  max_repair_rounds = 2
  last_processed = [ordered]@{ task_outcome_hash = 'aaa'; verifier_outcome_hash = 'bbb' }
  verifier = [ordered]@{
    name = 'wf-verifier-test'
    result = (Join-Path $testOverflowDir 'verify-result.md')
    outcome = (Join-Path $testOverflowDir 'verify-outcome.json')
    handoff = $testOverflowDir
  }
}
Set-Content -LiteralPath (Join-Path $testOverflowDir 'verify-result.md') -Value "Still broken" -Encoding utf8
Set-Content -LiteralPath (Join-Path $testOverflowDir 'verification.md') -Value "Still broken" -Encoding utf8
[ordered]@{ state = 'fix_required'; summary = 'Failed round 3' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testOverflowDir 'verify-outcome.json') -Encoding utf8
$overflowWf | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $overflowWfPath -Encoding utf8

& $monitorScript -WorkflowPath $overflowWfPath -Once
$overflowWfRes = Get-Content -LiteralPath $overflowWfPath -Raw | ConvertFrom-Json

if ($overflowWfRes.state -ne 'blocked') {
  throw "ASSERTION FAILED: Workflow exceeding max_repair_rounds must transition to 'blocked', got '$($overflowWfRes.state)'"
}
Write-Host "  ✔ Max repair bounds strictly enforced: state transitioned directly to 'blocked'" -ForegroundColor Green

Write-Host "`n>>> [FLOW B] PASSED ALL FORMAL ASSERTIONS (100% SUCCESS) <<<`n" -ForegroundColor Green
