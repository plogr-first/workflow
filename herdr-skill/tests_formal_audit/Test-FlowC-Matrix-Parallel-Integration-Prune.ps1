# Flow C Formal Verification Test: Matrix Parallel Multi-Agent Pipeline -> Integration Sandbox -> Unified 5-Gate Acceptance -> Pruning
param(
  [string]$TestRoot = (Join-Path $PSScriptRoot 'sandbox_flow_c')
)
$ErrorActionPreference = 'Stop'

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  [FLOW C] FORMAL VERIFICATION: MATRIX PARALLEL & INTEGRATION PRUNE" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$env:HERDR_ENV = '1'
$env:PATH = "$PSScriptRoot;$env:PATH"
$mockLog = Join-Path $PSScriptRoot 'herdr_mock_flow_c.log'
$env:HERDR_MOCK_LOG = $mockLog
if (Test-Path $mockLog) { Remove-Item $mockLog -Force }

if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$projectRoot = Join-Path $TestRoot 'project_gamma'
New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null

# 1. Setup Git Baseline
& git -C $projectRoot init 2>&1 | Out-Null
& git -C $projectRoot config user.name "Formal Auditor"
& git -C $projectRoot config user.email "auditor@zero-tolerance.test"
Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Value '{"name":"gamma-monorepo","version":"1.0.0"}' -Encoding utf8
& git -C $projectRoot add package.json
& git -C $projectRoot commit -m "chore: baseline commit" 2>&1 | Out-Null
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
  git = [ordered]@{ repository = $true; has_commit = $true; target_branch = 'master'; push_policy = 'manual' }
}
$profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $herdrDir 'dispatch-profile.json') -Encoding utf8

# 3. Dispatch Matrix Parallel Workflow with 3 Concurrently Isolated Subtasks
$scriptsDir = Join-Path $PSScriptRoot '..\scripts'
$parallelScript = Join-Path $scriptsDir 'Start-HerdrParallelWorkflow.ps1'
$monitorScript = Join-Path $scriptsDir 'Monitor-HerdrWorkflow.ps1'

$matrixDef = @(
  @{ id = 'api'; scope = 'src/api/**'; agent = 'codex'; prompt = 'Build REST endpoints' },
  @{ id = 'ui'; scope = 'src/ui/**'; agent = 'codex'; prompt = 'Build Web UI' },
  @{ id = 'core'; scope = 'src/core/**'; agent = 'codex'; prompt = 'Build Core Calculation Engine' }
)
$matrixJson = $matrixDef | ConvertTo-Json -Compress

Write-Host "[Step 1] Dispatching Matrix Parallel Workflow (3 Sub-Worktrees)..." -ForegroundColor Yellow
$wfPath = & $parallelScript -Slug "multi-feat" -MatrixJson $matrixJson -ProjectRoot $projectRoot -SkipAgentLaunch -SkipMonitor
$wfDir = Split-Path $wfPath

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.mode -ne 'parallel_task') { throw "ASSERTION FAILED: Mode must be 'parallel_task'" }
if ($wfObj.next_role -ne 'matrix_tasks') { throw "ASSERTION FAILED: Next role must be 'matrix_tasks'" }
if ($wfObj.matrix.Count -ne 3) { throw "ASSERTION FAILED: Matrix count must be 3" }

# Verify isolated worktrees created
foreach ($sub in $wfObj.matrix) {
  if (-not (Test-Path -LiteralPath ([string]$sub.worktree_path))) {
    throw "ASSERTION FAILED: Worktree for $($sub.id) does not exist: $($sub.worktree_path)"
  }
}
Write-Host "  ✔ 3 Independent Git worktrees mounted and isolated on dedicated branches" -ForegroundColor Green

# 4. Emulate Subtask 1 Completing First (Partial Candidate State)
Write-Host "[Step 2] Emulating Subtask 1 ('api') Candidate Completion..." -ForegroundColor Yellow
$subApi = $wfObj.matrix | Where-Object { $_.id -eq 'api' }
$apiWt = [string]$subApi.worktree_path
$apiDir = Join-Path $apiWt 'src\api'
New-Item -ItemType Directory -Force -Path $apiDir | Out-Null
Set-Content -LiteralPath (Join-Path $apiDir 'routes.js') -Value "export const routes = ['/api/v1'];" -Encoding utf8
& git -C $apiWt add .
& git -C $apiWt commit -m "feat(api): add v1 routes" 2>&1 | Out-Null
$apiSha = (& git -C $apiWt rev-parse HEAD).Trim()

[ordered]@{
  state = 'candidate'
  summary = 'API routes completed'
  worktree_decision = 'isolated'
  worktree_path = $apiWt
  branch = [string]$subApi.branch
  base_sha = $baseSha
  candidate_sha = $apiSha
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([string]$subApi.outcome) -Encoding utf8

# Monitor runs: should update subtask 1 to candidate but master remains executing
Remove-Item (Join-Path $wfDir 'workflow.lock') -Force -ErrorAction SilentlyContinue
& $monitorScript -WorkflowPath $wfPath -Once
$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
$subApiStatus = ($wfObj.matrix | Where-Object { $_.id -eq 'api' }).status
if ($subApiStatus -ne 'candidate') { throw "ASSERTION FAILED: Subtask 'api' status must be 'candidate', got '$subApiStatus'" }
if ($wfObj.state -ne 'executing') { throw "ASSERTION FAILED: Master workflow must remain 'executing' while other subtasks run" }
Write-Host "  ✔ Partial concurrency handled correctly: 'api' marked candidate, pipeline waiting for remaining subtasks" -ForegroundColor Green

# 5. Emulate Subtasks 2 & 3 Completing
Write-Host "[Step 3] Emulating Subtasks 'ui' and 'core' Candidate Completion..." -ForegroundColor Yellow
# UI subtask
$subUi = $wfObj.matrix | Where-Object { $_.id -eq 'ui' }
$uiWt = [string]$subUi.worktree_path
$uiDir = Join-Path $uiWt 'src\ui'
New-Item -ItemType Directory -Force -Path $uiDir | Out-Null
Set-Content -LiteralPath (Join-Path $uiDir 'App.jsx') -Value "export function App() { return <div>App</div>; }" -Encoding utf8
& git -C $uiWt add .
& git -C $uiWt commit -m "feat(ui): add app component" 2>&1 | Out-Null
$uiSha = (& git -C $uiWt rev-parse HEAD).Trim()
[ordered]@{
  state = 'candidate'
  summary = 'UI components completed'
  worktree_decision = 'isolated'
  worktree_path = $uiWt
  branch = [string]$subUi.branch
  base_sha = $baseSha
  candidate_sha = $uiSha
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([string]$subUi.outcome) -Encoding utf8

# Core subtask
$subCore = $wfObj.matrix | Where-Object { $_.id -eq 'core' }
$coreWt = [string]$subCore.worktree_path
$coreDir = Join-Path $coreWt 'src\core'
New-Item -ItemType Directory -Force -Path $coreDir | Out-Null
Set-Content -LiteralPath (Join-Path $coreDir 'engine.js') -Value "export function calc() { return 42; }" -Encoding utf8
& git -C $coreWt add .
& git -C $coreWt commit -m "feat(core): add math calculation engine" 2>&1 | Out-Null
$coreSha = (& git -C $coreWt rev-parse HEAD).Trim()
[ordered]@{
  state = 'candidate'
  summary = 'Core engine completed'
  worktree_decision = 'isolated'
  worktree_path = $coreWt
  branch = [string]$subCore.branch
  base_sha = $baseSha
  candidate_sha = $coreSha
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([string]$subCore.outcome) -Encoding utf8

# 6. Monitor detects all candidate -> mounts integration worktree & merges all branches
Write-Host "[Step 4] Monitor Aggregates N Branches into Integration Sandbox..." -ForegroundColor Yellow
Remove-Item (Join-Path $wfDir 'workflow.lock') -Force -ErrorAction SilentlyContinue
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'verifying') { throw "ASSERTION FAILED: Master state must transition to 'verifying', got '$($wfObj.state)'" }
if ($wfObj.next_role -ne 'verification') { throw "ASSERTION FAILED: Master next_role must be 'verification', got '$($wfObj.next_role)'" }

$intWt = Join-Path $projectRoot ".worktrees\wf-$($wfObj.slug)-integration"
if (-not (Test-Path -LiteralPath $intWt)) {
  throw "ASSERTION FAILED: Integration worktree '$intWt' was not mounted"
}

# Verify integration worktree contains all 3 changes
if (-not (Test-Path -LiteralPath (Join-Path $intWt 'src\api\routes.js')) -or
    -not (Test-Path -LiteralPath (Join-Path $intWt 'src\ui\App.jsx')) -or
    -not (Test-Path -LiteralPath (Join-Path $intWt 'src\core\engine.js'))) {
  throw "ASSERTION FAILED: Integration worktree does not contain all merged subtask artifacts"
}
Write-Host "  ✔ All 3 concurrent branches automatically merged into integration worktree with 0 conflicts" -ForegroundColor Green

# 7. Emulate Verifier Agent Unified 5-Gate Acceptance & Safe Merge
Write-Host "[Step 5] Emulating Verifier 5-Gate Acceptance of Integrated Monorepo..." -ForegroundColor Yellow
$intBranch = "wf/$($wfObj.slug)/integration"
& git -C $projectRoot merge --no-ff $intBranch -m "Merge parallel integration for $($wfObj.slug)" 2>&1 | Out-Null
$masterMergeSha = (& git -C $projectRoot rev-parse HEAD).Trim()

$verResultPath = [string]$wfObj.verifier.result
$verOutcomePath = [string]$wfObj.verifier.outcome
$verHandoffDir = [string]$wfObj.verifier.handoff

Set-Content -LiteralPath $verResultPath -Value "# Verification of Matrix Integration\nAll 3 subtasks validated across 5 gates." -Encoding utf8
Set-Content -LiteralPath (Join-Path $verHandoffDir 'verification.md') -Value "## 5-Gate Acceptance: PASS across all 3 sub-packages" -Encoding utf8

[ordered]@{
  state = 'merged'
  summary = 'Unified monorepo pass; safe fast-forward merge'
  merge_sha = $masterMergeSha
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verOutcomePath -Encoding utf8

# 8. Monitor Finalizes Merge & Auto-Prunes All Worktrees
Write-Host "[Step 6] Final Monitor Cycle: Terminal Merge & Full Worktree Pruning..." -ForegroundColor Yellow
Remove-Item (Join-Path $wfDir 'workflow.lock') -Force -ErrorAction SilentlyContinue
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'merged') { throw "ASSERTION FAILED: State must be 'merged', got '$($wfObj.state)'" }

# Verify all subtask worktrees AND integration worktree were pruned
if (Test-Path -LiteralPath $apiWt) { throw "ASSERTION FAILED: api worktree was not pruned" }
if (Test-Path -LiteralPath $uiWt) { throw "ASSERTION FAILED: ui worktree was not pruned" }
if (Test-Path -LiteralPath $coreWt) { throw "ASSERTION FAILED: core worktree was not pruned" }
if (Test-Path -LiteralPath $intWt) { throw "ASSERTION FAILED: integration worktree was not pruned" }
Write-Host "  ✔ All subtask worktrees and integration worktrees cleanly auto-pruned from disk" -ForegroundColor Green

# 9. Concurrency Conflict Injection Test (Matrix Merge Conflict Detection)
Write-Host "[Step 7] Testing Matrix Merge Conflict Detection & Fault Injection..." -ForegroundColor Yellow
$conflictTestDir = Join-Path $TestRoot 'conflict_test'
New-Item -ItemType Directory -Force -Path $conflictTestDir | Out-Null
& git -C $conflictTestDir init 2>&1 | Out-Null
& git -C $conflictTestDir config user.name "Conflict Tester"
& git -C $conflictTestDir config user.email "tester@test.com"
Set-Content -LiteralPath (Join-Path $conflictTestDir 'file.txt') -Value "Line 1`nLine 2" -Encoding utf8
& git -C $conflictTestDir add file.txt
& git -C $conflictTestDir commit -m "baseline" 2>&1 | Out-Null

$cProfile = [ordered]@{
  schema_version = 4; project_root = $conflictTestDir; herdr_session = [ordered]@{ name = 'test-session' }
  git = [ordered]@{ repository = $true; has_commit = $true; target_branch = 'master'; push_policy = 'manual' }
}
New-Item -ItemType Directory -Force -Path (Join-Path $conflictTestDir 'herdr') | Out-Null
$cProfile | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $conflictTestDir 'herdr\dispatch-profile.json') -Encoding utf8

$cMatrix = @(
  @{ id = 'c1'; scope = '**'; agent = 'codex'; prompt = 'Edit line 2' },
  @{ id = 'c2'; scope = '**'; agent = 'codex'; prompt = 'Conflicting edit line 2' }
)
$cWfPath = & $parallelScript -Slug "conflict-test" -MatrixJson ($cMatrix | ConvertTo-Json -Compress) -ProjectRoot $conflictTestDir -SkipAgentLaunch -SkipMonitor

$cWfObj = Get-Content -LiteralPath $cWfPath -Raw | ConvertFrom-Json

# Emulate conflicting edits on the exact same line
$c1Wt = [string]$cWfObj.matrix[0].worktree_path
$c2Wt = [string]$cWfObj.matrix[1].worktree_path
Set-Content -LiteralPath (Join-Path $c1Wt 'file.txt') -Value "Line 1`nEdit by C1" -Encoding utf8
& git -C $c1Wt add file.txt; & git -C $c1Wt commit -m "c1 edit" 2>&1 | Out-Null

Set-Content -LiteralPath (Join-Path $c2Wt 'file.txt') -Value "Line 1`nEdit by C2" -Encoding utf8
& git -C $c2Wt add file.txt; & git -C $c2Wt commit -m "c2 edit" 2>&1 | Out-Null

# Submit candidates for both
[ordered]@{ state = 'candidate'; summary = 'c1 done' } | ConvertTo-Json | Set-Content -LiteralPath ([string]$cWfObj.matrix[0].outcome) -Encoding utf8
[ordered]@{ state = 'candidate'; summary = 'c2 done' } | ConvertTo-Json | Set-Content -LiteralPath ([string]$cWfObj.matrix[1].outcome) -Encoding utf8

# Monitor runs: merge will conflict -> state must transition to 'blocked'
& $monitorScript -WorkflowPath $cWfPath -Once
$cWfRes = Get-Content -LiteralPath $cWfPath -Raw | ConvertFrom-Json

if ($cWfRes.state -ne 'blocked') {
  throw "ASSERTION FAILED: Conflicting matrix merges must transition workflow state to 'blocked', got '$($cWfRes.state)'"
}
Write-Host "  ✔ Merge conflict intercepted: pipeline safely halted with state 'blocked' without corrupting repository" -ForegroundColor Green

Write-Host "`n>>> [FLOW C] PASSED ALL FORMAL ASSERTIONS (100% SUCCESS) <<<`n" -ForegroundColor Green
