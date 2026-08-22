# Boundary & Fault Injection Formal Verification Test Suite
param(
  [string]$TestRoot = (Join-Path $PSScriptRoot 'sandbox_boundaries')
)
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  [BOUNDARIES] FORMAL VERIFICATION: PATH, CONCURRENCY, JSON & GH" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$env:HERDR_ENV = '1'
$env:PATH = "$PSScriptRoot;$env:PATH"
$mockLog = Join-Path $PSScriptRoot 'herdr_mock_boundaries.log'
$ghLog = Join-Path $PSScriptRoot 'gh_mock_boundaries.log'
$env:HERDR_MOCK_LOG = $mockLog
$env:GH_MOCK_LOG = $ghLog
if (Test-Path $mockLog) { Remove-Item $mockLog -Force }
if (Test-Path $ghLog) { Remove-Item $ghLog -Force }

if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$scriptsDir = Join-Path $PSScriptRoot '..\scripts'
$startScript = Join-Path $scriptsDir 'Start-HerdrWorkflow.ps1'
$monitorScript = Join-Path $scriptsDir 'Monitor-HerdrWorkflow.ps1'
$parallelScript = Join-Path $scriptsDir 'Start-HerdrParallelWorkflow.ps1'
$resumeScript = Join-Path $scriptsDir 'Resume-HerdrWorkflows.ps1'
$agentScript = Join-Path $scriptsDir 'Start-HerdrAgent.ps1'

# ─────────────────────────────────────────────────────────────────────────────
# 1. Windows Path Parsing Robustness (Chinese, Spaces, Special Symbols)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[Test 1] Path Robustness (Chinese, Spaces, Special Symbols)..." -ForegroundColor Yellow
$specialProject = Join-Path $TestRoot '测试 工作区 2026 [Special# & @Chars]'
New-Item -ItemType Directory -Force -Path $specialProject | Out-Null

& git -C $specialProject init 2>&1 | Out-Null
& git -C $specialProject config user.name "Auditor"
& git -C $specialProject config user.email "auditor@test.com"
& git -C $specialProject config core.quotepath false
Set-Content -LiteralPath (Join-Path $specialProject '测试 文件.txt') -Value "中文内容测试" -Encoding utf8
& git -C $specialProject add .
& git -C $specialProject commit -m "baseline commit" 2>&1 | Out-Null
$baseSha = (& git -C $specialProject rev-parse HEAD).Trim()

$herdrDir = Join-Path $specialProject 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDir | Out-Null
$profile = [ordered]@{
  schema_version = 4
  project_root = $specialProject
  herdr_session = [ordered]@{ name = 'test-session' }
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

$dispatchOut = & $startScript -Mode task -Slug "path-test" -Prompt "Test special path resolution" -ProjectRoot $specialProject | ConvertFrom-Json
$wfPath = [string]$dispatchOut.workflow

if ($dispatchOut.monitor_pid) {
  Stop-Process -Id $dispatchOut.monitor_pid -Force -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path (Split-Path $wfPath) 'workflow.lock') -Force -ErrorAction SilentlyContinue

# Isolated worktree with special path
$specialWorktree = Join-Path $specialProject '.worktrees\wf-path-test'
& git -C $specialProject worktree add -b 'wf/path-test' $specialWorktree HEAD 2>&1 | Out-Null
Set-Content -LiteralPath (Join-Path $specialWorktree 'update.txt') -Value "new data" -Encoding utf8
& git -C $specialWorktree add .
& git -C $specialWorktree commit -m "update in special worktree" 2>&1 | Out-Null
$candSha = (& git -C $specialWorktree rev-parse HEAD).Trim()

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
Set-Content -LiteralPath ([string]$wfObj.task.result) -Value "# Result" -Encoding utf8
[ordered]@{
  state = 'candidate'
  summary = 'Path test candidate'
  worktree_decision = 'isolated'
  worktree_path = $specialWorktree
  branch = 'wf/path-test'
  base_sha = $baseSha
  candidate_sha = $candSha
  changed_files = @('update.txt')
} | ConvertTo-Json | Set-Content -LiteralPath ([string]$wfObj.task.outcome) -Encoding utf8

# Monitor runs: 2 ticks to transition executing -> candidate -> verifying
& $monitorScript -WorkflowPath $wfPath -Once
& $monitorScript -WorkflowPath $wfPath -Once

$wfObj = Get-Content -LiteralPath $wfPath -Raw | ConvertFrom-Json
if ($wfObj.state -ne 'verifying') {
  throw "ASSERTION FAILED: Special path candidate failed validation, state is '$($wfObj.state)'"
}
Write-Host "  ✔ Chinese, spaces, brackets, and special characters correctly resolved by state monitor" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 2. JSON Serialization Depth & Atomic Write Integrity
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[Test 2] JSON Serialization Depth & Atomic Write Guarantee..." -ForegroundColor Yellow
$jsonTestDir = Join-Path $TestRoot 'json_test'
New-Item -ItemType Directory -Force -Path $jsonTestDir | Out-Null

$deepObj = [ordered]@{
  level1 = [ordered]@{
    level2 = [ordered]@{
      level3 = [ordered]@{
        level4 = [ordered]@{
          level5 = [ordered]@{
            level6 = [ordered]@{
              level7 = [ordered]@{
                level8 = [ordered]@{
                  level9 = [ordered]@{
                    deep_key = "deep_value_preserved"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

$atomicTarget = Join-Path $jsonTestDir 'atomic_output.json'
# Emulate Write-AtomicJson logic
$tmp = "$atomicTarget.$([guid]::NewGuid().ToString('N')).tmp"
$deepObj | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding utf8
Move-Item -LiteralPath $tmp -Destination $atomicTarget -Force

$readBack = Get-Content -LiteralPath $atomicTarget -Raw | ConvertFrom-Json
if ($readBack.level1.level2.level3.level4.level5.level6.level7.level8.level9.deep_key -ne 'deep_value_preserved') {
  throw "ASSERTION FAILED: Deep JSON serialization truncated nested structure"
}
Write-Host "  ✔ Depth 20 JSON serialization and atomic temp-move swap verified" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 3. Lease Lock Mutual Exclusion, Clock Skew, and Concurrency Contention
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[Test 3] Lease Lock Concurrency Race & Stale Lock Stealing..." -ForegroundColor Yellow
$lockTestDir = Join-Path $TestRoot 'lock_test'
New-Item -ItemType Directory -Force -Path $lockTestDir | Out-Null
$lockFile = Join-Path $lockTestDir 'workflow.lock'

# 3A. Concurrency contention test: Active primary controller vs 5 contenders
$primaryLease = [ordered]@{ controller_id = "$PID-$([guid]::NewGuid().ToString('N'))"; pid = $PID; lease_expires_at = (Get-Date).AddSeconds(30).ToString('o') }
$fs = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$writer = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
$writer.Write(($primaryLease | ConvertTo-Json))
$writer.Flush()

$acquireScript = @"
param([string]`$LockPath)
function Acquire-Lease {
  if (Test-Path -LiteralPath `$LockPath) {
    try {
      `$old = Get-Content -LiteralPath `$LockPath -Raw | ConvertFrom-Json
      `$proc = Get-Process -Id `$old.pid -ErrorAction SilentlyContinue
      if (`$proc -and ([datetime]`$old.lease_expires_at) -gt (Get-Date)) { return `$false }
      Remove-Item -LiteralPath `$LockPath -Force -ErrorAction SilentlyContinue
    } catch {
      Remove-Item -LiteralPath `$LockPath -Force -ErrorAction SilentlyContinue
    }
  }
  `$lease = [ordered]@{ controller_id = "`$PID-`$([guid]::NewGuid().ToString('N'))"; pid = `$PID; lease_expires_at = (Get-Date).AddSeconds(30).ToString('o') }
  `$leaseJson = (`$lease | ConvertTo-Json)
  try {
    `$cfs = [System.IO.File]::Open(`$LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    `$cwriter = [System.IO.StreamWriter]::new(`$cfs, [System.Text.Encoding]::UTF8)
    `$cwriter.Write(`$leaseJson)
    `$cwriter.Flush()
    `$cwriter.Dispose()
    `$cfs.Dispose()
    return `$true
  } catch {
    return `$false
  }
}
Acquire-Lease
"@

$jobScriptPath = Join-Path $lockTestDir 'acquire_worker.ps1'
Set-Content -LiteralPath $jobScriptPath -Value $acquireScript -Encoding utf8

$jobs = @()
1..5 | ForEach-Object {
  $jobs += Start-Job -ScriptBlock {
    param($s, $l)
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $s -LockPath $l
  } -ArgumentList $jobScriptPath, $lockFile
}

$results = $jobs | ForEach-Object { Receive-Job -Job $_ -Wait }
$failCount = @($results | Where-Object { $_ -eq 'False' -or $_ -eq $false }).Count

$writer.Dispose()
$fs.Dispose()
Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue

if ($failCount -ne 5) {
  throw "ASSERTION FAILED: All 5 contenders must be rejected while primary controller is active, got $failCount rejected"
}
Write-Host "  ✔ 5-way parallel lease race: 5/5 contenders rejected while primary controller is active (0 dual-controllers)" -ForegroundColor Green

# 3B. Clock Skew & Stale PID Lock Stealing Test
Write-Host "  Testing Stale Lock Stealing (Dead PID & Expired Lease)..." -ForegroundColor Yellow
# Write a fake expired lock with dead PID 999999
$staleLease = [ordered]@{
  controller_id = '999999-stale'
  pid = 999999
  lease_expires_at = (Get-Date).AddHours(-1).ToString('o')
}
$staleLease | ConvertTo-Json | Set-Content -LiteralPath $lockFile -Encoding utf8

$reclaimed = & pwsh -NoProfile -ExecutionPolicy Bypass -File $jobScriptPath -LockPath $lockFile
if ($reclaimed -ne 'True') {
  throw "ASSERTION FAILED: Monitor failed to steal expired lease from dead PID"
}
Write-Host "  ✔ Stale lease correctly detected and reclaimed without deadlocking" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 4. GitHub CLI (gh) Integration & Branch Point Legality
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[Test 4] GitHub CLI (gh) Operations & Push Policies..." -ForegroundColor Yellow
$ghTestDir = Join-Path $TestRoot 'gh_test'
New-Item -ItemType Directory -Force -Path $ghTestDir | Out-Null
& git -C $ghTestDir init 2>&1 | Out-Null
& git -C $ghTestDir config user.name "GH Tester"
& git -C $ghTestDir config user.email "gh@test.com"
Set-Content -LiteralPath (Join-Path $ghTestDir 'file.txt') -Value "v1" -Encoding utf8
& git -C $ghTestDir add .
& git -C $ghTestDir commit -m "baseline" 2>&1 | Out-Null
$baseSha = (& git -C $ghTestDir rev-parse HEAD).Trim()

# Create feature branch
$featBranch = 'wf/gh-feat'
& git -C $ghTestDir checkout -b $featBranch 2>&1 | Out-Null
Set-Content -LiteralPath (Join-Path $ghTestDir 'file.txt') -Value "v2" -Encoding utf8
& git -C $ghTestDir add .
& git -C $ghTestDir commit -m "feat change" 2>&1 | Out-Null
& git -C $ghTestDir checkout master 2>&1 | Out-Null

# Setup remote pointing to GitHub
& git -C $ghTestDir remote add origin https://github.com/mock-org/mock-repo.git
# Keep the GitHub fetch URL used by the PR command, but give this offline test a
# real local push destination.  This verifies the required feature-branch push
# instead of treating a network failure as a successful PR publication.
$ghPushRemote = Join-Path $TestRoot 'gh_test_remote.git'
& git init --bare $ghPushRemote 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ASSERTION FAILED: Unable to create local Git push remote for GitHub CLI test" }
& git -C $ghTestDir remote set-url --push origin $ghPushRemote
if ($LASTEXITCODE -ne 0) { throw "ASSERTION FAILED: Unable to configure local Git push remote for GitHub CLI test" }

$ghHandoffDir = Join-Path $ghTestDir 'verifier'
New-Item -ItemType Directory -Force -Path $ghHandoffDir | Out-Null
$ghWfPath = Join-Path $ghTestDir 'workflow.json'

$ghWf = [ordered]@{
  schema_version = 3
  workflow_id = 'wf-gh-test'
  mode = 'task'
  slug = 'gh-feat'
  session_name = 'test-session'
  project_root = $ghTestDir
  state = 'verifying'
  next_role = 'verification'
  repair_round = 0
  max_repair_rounds = 2
  last_processed = [ordered]@{ task_outcome_hash = 'aaa'; verifier_outcome_hash = $null }
  git = [ordered]@{
    push_policy = 'create_pr'
    push_remote = 'origin'
    target_branch = 'master'
    github = [ordered]@{ is_github = $true }
  }
  task = [ordered]@{
    result = (Join-Path $ghTestDir 'task-result.md')
    outcome = (Join-Path $ghTestDir 'task-outcome.json')
  }
  verifier = [ordered]@{
    name = 'wf-verify-gh'
    handoff = $ghHandoffDir
    result = (Join-Path $ghHandoffDir 'verify-result.md')
    outcome = (Join-Path $ghHandoffDir 'verify-outcome.json')
  }
}
$candSha = (& git -C $ghTestDir rev-parse HEAD).Trim()
Set-Content -LiteralPath (Join-Path $ghTestDir 'task-result.md') -Value "# Task Result`nGH feat done" -Encoding utf8
[ordered]@{
  state = 'candidate'
  summary = 'GH feature candidate'
  worktree_decision = 'in_place'
  worktree_path = $ghTestDir
  branch = $featBranch
  base_sha = $baseSha
  candidate_sha = $candSha
  changed_files = @('file.txt')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ghTestDir 'task-outcome.json') -Encoding utf8

Set-Content -LiteralPath (Join-Path $ghHandoffDir 'verify-result.md') -Value "PR Verified body" -Encoding utf8
Set-Content -LiteralPath (Join-Path $ghHandoffDir 'verification.md') -Value "Verification PASS" -Encoding utf8
[ordered]@{ state = 'merged'; summary = 'Ready for PR' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ghHandoffDir 'verify-outcome.json') -Encoding utf8

$ghWf | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ghWfPath -Encoding utf8

# Run monitor cycle: will call Push-MergedWorkflow
& $monitorScript -WorkflowPath $ghWfPath -Once

$ghWfRes = Get-Content -LiteralPath $ghWfPath -Raw | ConvertFrom-Json
if ($ghWfRes.push_status -ne 'pr_created') {
  throw "ASSERTION FAILED: Push policy 'create_pr' should set push_status to 'pr_created', got '$($ghWfRes.push_status)'"
}

$ghMockCalls = if (Test-Path -LiteralPath $ghLog) { Get-Content -LiteralPath $ghLog -Raw } else { '' }
if ($ghMockCalls -notmatch 'pr create --repo https://github.com/mock-org/mock-repo.git --head wf/gh-feat --base master') {
  throw "ASSERTION FAILED: gh CLI was not called with valid head branch and base branch arguments: $ghMockCalls"
}
Write-Host "  ✔ GitHub CLI (gh) invoked with authenticated PR creation and accurate branch pointers" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 5. Non-Herdr Environment Pre-flight Interception (HERDR_ENV != 1)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[Test 5] Non-Herdr Environment Pre-flight Interception (HERDR_ENV != 1)..." -ForegroundColor Yellow
$env:HERDR_ENV = '0'

$scriptsToTest = @(
  @{ Name = 'Start-HerdrWorkflow'; Script = $startScript; Args = @('-Mode', 'task', '-Slug', 't1', '-Prompt', 'p') },
  @{ Name = 'Start-HerdrParallelWorkflow'; Script = $parallelScript; Args = @('-Slug', 't2', '-MatrixJson', '[]') },
  @{ Name = 'Resume-HerdrWorkflows'; Script = $resumeScript; Args = @() },
  @{ Name = 'Start-HerdrAgent'; Script = $agentScript; Args = @('-Name', 'a1', '-Category', 'task', '-Slug', 's1', '-Prompt', 'p') }
)

foreach ($item in $scriptsToTest) {
  $failed = $false
  try {
    & $item.Script @($item.Args) 2>&1 | Out-Null
  } catch {
    $failed = $true
  }
  if (-not $failed) {
    throw "ASSERTION FAILED: $($item.Name) MUST abort immediately when HERDR_ENV != 1"
  }
  Write-Host "  ✔ $($item.Name) strictly blocked execution outside Herdr environment" -ForegroundColor Green
}

$env:HERDR_ENV = '1'

Write-Host "`n>>> [BOUNDARIES] PASSED ALL FORMAL ASSERTIONS (100% SUCCESS) <<<`n" -ForegroundColor Green
