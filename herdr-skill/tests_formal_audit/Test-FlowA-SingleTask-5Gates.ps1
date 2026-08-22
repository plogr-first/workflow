# Flow A Formal Verification Test: Single Task -> 5-Gate Independent Verification -> Safe Merge & Prune
param(
  [string]$TestRoot = (Join-Path $PSScriptRoot 'sandbox_flow_a')
)
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  [FLOW A] FORMAL VERIFICATION: SINGLE TASK & 5-GATE AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$env:HERDR_ENV = '1'
$env:PATH = "$PSScriptRoot;$env:PATH"
$mockLog = Join-Path $PSScriptRoot 'herdr_mock_flow_a.log'
$env:HERDR_MOCK_LOG = $mockLog
if (Test-Path $mockLog) { Remove-Item $mockLog -Force }

if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$projectRoot = Join-Path $TestRoot 'project_alpha'
New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null

# 1. Setup Git baseline
& git -C $projectRoot init 2>&1 | Out-Null
& git -C $projectRoot config user.name "Formal Auditor"
& git -C $projectRoot config user.email "auditor@zero-tolerance.test"
Set-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Value "# Project Alpha Baseline" -Encoding utf8
& git -C $projectRoot add README.md
& git -C $projectRoot commit -m "Initial baseline commit" 2>&1 | Out-Null
$baseSha = (& git -C $projectRoot rev-parse HEAD).Trim()

# 2. Setup Dispatch Profile
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

# 3. Dispatch Task Workflow
$scriptsDir = Join-Path $PSScriptRoot '..\scripts'
$startScript = Join-Path $scriptsDir 'Start-HerdrWorkflow.ps1'
$monitorScript = Join-Path $scriptsDir 'Monitor-HerdrWorkflow.ps1'

Write-Host "[Step 1] Dispatching Task Workflow..." -ForegroundColor Yellow
$dispatchOut = & $startScript -Mode task -Slug "user-auth" -Prompt "Implement User OAuth2 Login Flow" -ProjectRoot $projectRoot | ConvertFrom-Json

# Stop background monitor process to allow deterministic step-by-step state verification
if ($dispatchOut.monitor_pid) {
  Stop-Process -Id $dispatchOut.monitor_pid -Force -ErrorAction SilentlyContinue
}

$wfPath = [string]$dispatchOut.workflow
$wfDir = Split-Path $wfPath
Remove-Item (Join-Path $wfDir 'workflow.lock') -Force -ErrorAction SilentlyContinue

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json

# Assert Initial State
if ($wfObj.state -ne 'executing') { throw "ASSERTION FAILED: Initial state must be 'executing', got '$($wfObj.state)'" }
if ($wfObj.next_role -ne 'task') { throw "ASSERTION FAILED: Next role must be 'task', got '$($wfObj.next_role)'" }
if ($wfObj.repair_round -ne 0) { throw "ASSERTION FAILED: Initial repair_round must be 0" }
if ($wfObj.task.name -eq $wfObj.verifier.name) { throw "ASSERTION FAILED: Task and Verifier names must not collide" }
Write-Host "  ✔ Dispatch state initialized correctly: ID=$($wfObj.workflow_id)" -ForegroundColor Green

# 4. Create Task Worktree Sandbox & Candidate Commit
Write-Host "[Step 2] Emulating Task Agent Execution in Isolated Sandbox..." -ForegroundColor Yellow
$taskWorktree = Join-Path $projectRoot '.worktrees\wf-user-auth'
$taskBranch = 'wf/user-auth'
& git -C $projectRoot worktree add -b $taskBranch $taskWorktree HEAD 2>&1 | Out-Null

# Make code changes in worktree
$srcDir = Join-Path $taskWorktree 'src'
New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
Set-Content -LiteralPath (Join-Path $srcDir 'auth.js') -Value "export function login(user) { return 'token_ok'; }" -Encoding utf8
& git -C $taskWorktree add .
& git -C $taskWorktree commit -m "feat(auth): implement user oauth2 login" 2>&1 | Out-Null
$candidateSha = (& git -C $taskWorktree rev-parse HEAD).Trim()

# Write Task result.md and outcome.json
$taskResultPath = [string]$wfObj.task.result
$taskOutcomePath = [string]$wfObj.task.outcome
Set-Content -LiteralPath $taskResultPath -Value @"
# Task Result: OAuth2 Implementation
- Acceptance Checks: All 5 checks passed.
- Changed Files: src/auth.js
- Commands Executed: npm test (OK)
"@ -Encoding utf8

$taskOutcome = [ordered]@{
  state = 'candidate'
  summary = 'Implemented OAuth2 login flow with comprehensive tests'
  worktree_decision = 'isolated'
  worktree_path = $taskWorktree
  branch = $taskBranch
  base_sha = $baseSha
  candidate_sha = $candidateSha
  changed_files = @('src/auth.js')
}
$taskOutcome | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskOutcomePath -Encoding utf8

# 5. Execute Monitor Cycles (Candidate -> Verification Wakeup)
Write-Host "[Step 3] Executing Monitor Transitions (Candidate -> Verifying)..." -ForegroundColor Yellow
& $monitorScript -WorkflowPath $wfPath -Once
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'verifying') { throw "ASSERTION FAILED: State must transition to 'verifying', got '$($wfObj.state)'" }
if ($wfObj.next_role -ne 'verification') { throw "ASSERTION FAILED: Next role must be 'verification', got '$($wfObj.next_role)'" }
Write-Host "  ✔ Monitor safely verified 5-gate candidate evidence and transitioned to 'verifying'" -ForegroundColor Green

# 6. Emulate Verifier Agent Performing 5-Gate Independent Audit & Merging
Write-Host "[Step 4] Emulating Verifier 5-Gate Audit & Safe Merge..." -ForegroundColor Yellow
$verResultPath = [string]$wfObj.verifier.result
$verOutcomePath = [string]$wfObj.verifier.outcome
$verHandoffDir = [string]$wfObj.verifier.handoff

# Independent fast-forward merge into main
& git -C $projectRoot merge --ff-only $taskBranch 2>&1 | Out-Null
$mergeSha = (& git -C $projectRoot rev-parse HEAD).Trim()

Set-Content -LiteralPath $verResultPath -Value @"
# Verification Report: User Auth
- Gate 1 (Outcome): Passed.
- Gate 2 (Regression): Passed.
- Gate 3 (Spec/Scope): Passed.
- Gate 4 (Standards/Integration): Passed.
- Gate 5 (API Contract): Passed.
- Merge SHA: $mergeSha
"@ -Encoding utf8

Set-Content -LiteralPath (Join-Path $verHandoffDir 'verification.md') -Value @"
## 5-Gate Formal Audit
1. Outcome Gate: PASS
2. Regression Gate: PASS
3. Spec/Scope Gate: PASS
4. Standards Gate: PASS
5. API Contract Gate: PASS
"@ -Encoding utf8

$verOutcome = [ordered]@{
  state = 'merged'
  summary = 'All 5 gates verified independently; clean fast-forward merge succeeded'
  merge_sha = $mergeSha
}
$verOutcome | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verOutcomePath -Encoding utf8

# 7. Execute Final Monitor Cycle (Verifying -> Merged & Auto-Prune)
Write-Host "[Step 5] Executing Final Monitor Cycle (Terminal Merge & Auto-Prune)..." -ForegroundColor Yellow
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'merged') { throw "ASSERTION FAILED: Terminal state must be 'merged', got '$($wfObj.state)'" }
if ($wfObj.next_role -ne '') { throw "ASSERTION FAILED: Terminal next_role must be empty, got '$($wfObj.next_role)'" }

# Verify events.jsonl contains completion event
$eventsPath = Join-Path (Split-Path $wfPath) 'events.jsonl'
$events = Get-Content -LiteralPath $eventsPath | ForEach-Object { $_ | ConvertFrom-Json }
$completedEvent = $events | Where-Object { $_.event -eq 'workflow_completed' }
if (-not $completedEvent) { throw "ASSERTION FAILED: events.jsonl must record 'workflow_completed'" }
Write-Host "  ✔ Completion event correctly persisted in events.jsonl" -ForegroundColor Green

# Verify Auto-Prune of isolated worktree
if (Test-Path -LiteralPath $taskWorktree) {
  throw "ASSERTION FAILED: Isolated worktree '$taskWorktree' should have been auto-pruned upon merge"
}
Write-Host "  ✔ Merged worktree was cleanly and automatically pruned" -ForegroundColor Green

Write-Host "`n>>> [FLOW A] PASSED ALL FORMAL ASSERTIONS (100% SUCCESS) <<<`n" -ForegroundColor Green
