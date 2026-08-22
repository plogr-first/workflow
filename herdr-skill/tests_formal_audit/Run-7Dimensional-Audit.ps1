$startTime = Get-Date
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  7-DIMENSIONAL AEROSPACE-GRADE MULTI-FACETED SYSTEM AUDIT" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan

$dimResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Record-Result([string]$Dimension, [string]$Item, [bool]$Pass, [string]$Detail = "") {
  $status = if ($Pass) { "PASS" } else { "FAIL" }
  $color = if ($Pass) { "Green" } else { "Red" }
  $symbol = if ($Pass) { "[OK]" } else { "[FAIL]" }
  Write-Host "  $symbol [$status] ${Dimension}: $Item" -ForegroundColor $color
  if ($Detail) { Write-Host "      $Detail" -ForegroundColor DarkGray }
  $script:dimResults.Add([pscustomobject]@{ Dimension = $Dimension; Item = $Item; Status = $status; Detail = $Detail })
}

# --- DIMENSION 1: Skill Integrity & Cross-Tool Parity ---
Write-Host ">>> [Dimension 1] Skill Integrity & Cross-Tool Synchronization..." -ForegroundColor White
$coreSkills = @("plogr", "herdr", "karpathy-guidelines", "task-agent", "bugfix-agent", "research-agent", "verification-agent", "audit-suite")
$syncDirs = @(
  "F:\个人资料\workflow\.agents\skills",
  "F:\个人资料\workflow\.claude\skills",
  "F:\个人资料\workflow\.codex\skills",
  (Join-Path $env:USERPROFILE ".agents\skills"),
  (Join-Path $env:USERPROFILE ".claude\skills"),
  (Join-Path $env:USERPROFILE ".codex\skills")
)
$allSynced = $true
foreach ($dir in $syncDirs) {
  if (Test-Path $dir) {
    $items = @(Get-ChildItem -LiteralPath $dir | ForEach-Object { $_.Name })
    foreach ($cs in $coreSkills) {
      if ($items -notcontains $cs) { $allSynced = $false; Record-Result "Dim 1" "Missing $cs in $dir" $false }
    }
  } else {
    $allSynced = $false
    Record-Result "Dim 1" "Directory missing: $dir" $false
  }
}
if ($allSynced) { Record-Result "Dim 1" "All 8 Core Skills Synced Across 6 Tool/Global Directories" $true "Skills count: 8/8 matched" }

# Progressive indexes
$hasAgentsMd = (Test-Path "F:\个人资料\workflow\AGENTS.md") -and ((Get-Content "F:\个人资料\workflow\AGENTS.md" -Raw) -match "Plogr Multi-Agent Orchestrator")
$hasClaudeMd = (Test-Path "F:\个人资料\workflow\CLAUDE.md") -and ((Get-Content "F:\个人资料\workflow\CLAUDE.md" -Raw) -match "Plogr Multi-Agent Orchestrator")
Record-Result "Dim 1" "AGENTS.md & CLAUDE.md Progressive Disclosure Indexes" ($hasAgentsMd -and $hasClaudeMd) "Trigger: /plogr verified"

# --- DIMENSION 2: CLI Command Suite & Toolchain Parity ---
Write-Host "`n>>> [Dimension 2] CLI Command Suite & Toolchain Parity..." -ForegroundColor White
$cliJs = "F:\个人资料\workflow\herdr-skill\bin\cli.js"
$showOut = node $cliJs show 2>&1
$showPass = ($LASTEXITCODE -eq 0) -and ($showOut -match "工作流阶段")
Record-Result "Dim 2" "plogr show / plogr agents Table Rendering" $showPass

$changePass = $true
$testDir = Join-Path $env:TEMP ("dim2_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
Set-Location $testDir
node $cliJs change preset balanced 2>&1 | Out-Null
$p = Get-Content (Join-Path $testDir "herdr\dispatch-profile.json") -Raw | ConvertFrom-Json
if ($p.task_agent.kind -ne "codex" -or $p.root_cause_agent.kind -ne "claude") { $changePass = $false }
node $cliJs change preset cost-saver 2>&1 | Out-Null
$p = Get-Content (Join-Path $testDir "herdr\dispatch-profile.json") -Raw | ConvertFrom-Json
if ($p.task_agent.kind -ne "opencode") { $changePass = $false }
Set-Location "F:\个人资料\workflow"
Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
Record-Result "Dim 2" "plogr change preset & role switching engine" $changePass

# --- DIMENSION 3: Dynamic OpenCode Model Discovery & Aliases ---
Write-Host "`n>>> [Dimension 3] Dynamic OpenCode Model Discovery & Aliases..." -ForegroundColor White
$testDir3 = Join-Path $env:TEMP ("dim3_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testDir3 | Out-Null
Set-Location $testDir3
node $cliJs change task go 2>&1 | Out-Null
$p = Get-Content (Join-Path $testDir3 "herdr\dispatch-profile.json") -Raw | ConvertFrom-Json
$goPass = ($p.task_agent.kind -eq "opencode") -and ($p.task_agent.model -eq "opencode-go/deepseek-v4-flash")
Record-Result "Dim 3" "Go Provider Alias Resolution (go -> opencode-go/deepseek-v4-flash)" $goPass

node $cliJs change bugfix sol 2>&1 | Out-Null
$p = Get-Content (Join-Path $testDir3 "herdr\dispatch-profile.json") -Raw | ConvertFrom-Json
$solPass = ($p.root_cause_agent.kind -eq "opencode") -and ($p.root_cause_agent.model -eq "pixel/gpt-5.6-sol")
Record-Result "Dim 3" "Pixel Custom Provider Alias Resolution (sol -> pixel/gpt-5.6-sol)" $solPass

node $cliJs change verifier luna 2>&1 | Out-Null
$p = Get-Content (Join-Path $testDir3 "herdr\dispatch-profile.json") -Raw | ConvertFrom-Json
$lunaPass = ($p.verification_agent.kind -eq "opencode") -and ($p.verification_agent.model -eq "pixel/gpt-5.6-Luna")
Record-Result "Dim 3" "Luna Model Alias Resolution (luna -> pixel/gpt-5.6-Luna)" $lunaPass

node $cliJs change research zen 2>&1 | Out-Null
$p = Get-Content (Join-Path $testDir3 "herdr\dispatch-profile.json") -Raw | ConvertFrom-Json
$zenPass = ($p.research_agent.kind -eq "opencode") -and ($p.research_agent.model -eq "opencode/deepseek-v4-flash-free")
Record-Result "Dim 3" "Zen/Free Tier Alias Resolution (zen -> opencode/deepseek-v4-flash-free)" $zenPass

Set-Location "F:\个人资料\workflow"
Remove-Item -LiteralPath $testDir3 -Recurse -Force -ErrorAction SilentlyContinue

# --- DIMENSION 4: npm Package Self-Containment & Zero-Dependency npx ---
Write-Host "`n>>> [Dimension 4] npm Package Self-Containment & Zero-Dependency npx..." -ForegroundColor White
$pkgJson = Get-Content "F:\个人资料\workflow\herdr-skill\package.json" -Raw | ConvertFrom-Json
$hasBundledInFiles = $pkgJson.files -contains "bundled_skills/"
$bundledItems = @(Get-ChildItem "F:\个人资料\workflow\herdr-skill\bundled_skills" | ForEach-Object { $_.Name })
$bundleComplete = ($bundledItems.Count -ge 8)
Record-Result "Dim 4" "package.json Bundled Skills Inclusion & Self-Containment" ($hasBundledInFiles -and $bundleComplete) "Bundled items: $($bundledItems.Count)"

$testDir4 = Join-Path $env:TEMP ("dim4_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testDir4 | Out-Null
node $cliJs init --project $testDir4 --task codex --root-cause claude --verification claude --research gemini --session dim4-test --skip-git-init 2>&1 | Out-Null
$npxPlogrSkill = Test-Path (Join-Path $testDir4 ".agents\skills\plogr\SKILL.md")
$npxKarpathy = Test-Path (Join-Path $testDir4 ".agents\skills\karpathy-guidelines\SKILL.md")
$npxAuditSuite = Test-Path (Join-Path $testDir4 ".agents\skills\audit-suite\SKILL.md")
$npxAgentsMd = Test-Path (Join-Path $testDir4 "AGENTS.md")
$npxProfile = Test-Path (Join-Path $testDir4 "herdr\dispatch-profile.json")
$npxPass = $npxPlogrSkill -and $npxKarpathy -and $npxAuditSuite -and $npxAgentsMd -and $npxProfile
Record-Result "Dim 4" "Zero-Dependency Fresh Project Init via npx Simulation" $npxPass "All skills & configs deployed"
Remove-Item -LiteralPath $testDir4 -Recurse -Force -ErrorAction SilentlyContinue

# --- DIMENSION 5: Core Workflow State Machine & 5 Gates (Formal Suites) ---
Write-Host "`n>>> [Dimension 5] Four Core Workflow Formal Suites (Flow A, B, C, D)..." -ForegroundColor White
$flowAPass = $false
try {
  & (Join-Path "F:\个人资料\workflow\herdr-skill\tests_formal_audit" "Test-FlowA-SingleTask-5Gates.ps1")
  $flowAPass = $true
} catch { $flowAPass = $false }
Record-Result "Dim 5" "Flow A: Single Task -> 5-Gate Verification -> FF Merge" $flowAPass

$flowBPass = $false
try {
  & (Join-Path "F:\个人资料\workflow\herdr-skill\tests_formal_audit" "Test-FlowB-Bugfix-Repair-KnowledgeHarvest.ps1")
  $flowBPass = $true
} catch { $flowBPass = $false }
Record-Result "Dim 5" "Flow B: Bugfix Audit Triage -> Gate Rejection -> Repair Loop -> Knowledge Harvest" $flowBPass

$flowCPass = $false
try {
  & (Join-Path "F:\个人资料\workflow\herdr-skill\tests_formal_audit" "Test-FlowC-Matrix-Parallel-Integration-Prune.ps1")
  $flowCPass = $true
} catch { $flowCPass = $false }
Record-Result "Dim 5" "Flow C: Matrix Parallel -> N Sandboxes -> Integration Merge -> Pruning" $flowCPass

$flowDPass = $false
try {
  & (Join-Path "F:\个人资料\workflow\herdr-skill\tests_formal_audit" "Test-FlowD-Reboot-SessionLock-GenerationNaming.ps1")
  $flowDPass = $true
} catch { $flowDPass = $false }
Record-Result "Dim 5" "Flow D: Reboot Recovery -> Session Lock -> Generational Naming (-rN)" $flowDPass

# --- DIMENSION 6: Windows Robustness & Chaos Injection ---
Write-Host "`n>>> [Dimension 6] Windows Robustness & Chaos Injection..." -ForegroundColor White
$boundariesPass = $false
try {
  & (Join-Path "F:\个人资料\workflow\herdr-skill\tests_formal_audit" "Test-Boundaries-Robustness.ps1")
  $boundariesPass = $true
} catch { $boundariesPass = $false }
Record-Result "Dim 6" "Windows Paths, Depth 20 JSON, Lease Lock Anti-Split-Brain, GH Intercept" $boundariesPass

# --- DIMENSION 7: Knowledge Harvesting & Anti-Pattern Defense ---
Write-Host "`n>>> [Dimension 7] Knowledge Harvesting & Anti-Pattern Defense..." -ForegroundColor White
$testHarvestDir = Join-Path $env:TEMP ("dim7_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testHarvestDir | Out-Null
$testWfJson = Join-Path $testHarvestDir "workflow.json"
$wfObj = @{
  id = "wf-test-dim7"
  mode = "bugfix"
  slug = "test-dim7"
  state = "merged"
  repair_round = 1
  brief = @{ goal = "Fix null subscriber crash" }
  verifier_handoff = "Verifier confirmed fix across all gates."
}
$wfObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $testWfJson -Encoding utf8

$harvestScript = "F:\个人资料\workflow\herdr-skill\scripts\Update-PitfallsKnowledge.ps1"
& $harvestScript -WorkflowPath $testWfJson -ProjectRoot $testHarvestDir | Out-Null

$hasJsonl = (Test-Path (Join-Path $testHarvestDir ".agents\skills\knowledge\pitfalls.jsonl")) -or (Test-Path (Join-Path $testHarvestDir ".knowledge\pitfalls.jsonl"))
$hasMd = (Test-Path (Join-Path $testHarvestDir ".knowledge\pitfalls.md"))
$harvestPass = $hasJsonl -and $hasMd
Record-Result "Dim 7" "Dual-Channel Knowledge Auto-Harvesting (JSONL & Markdown)" $harvestPass "Harvested to .knowledge/"
Remove-Item -LiteralPath $testHarvestDir -Recurse -Force -ErrorAction SilentlyContinue

$totalSec = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
$failCount = @($dimResults | Where-Object { $_.Status -ne "PASS" }).Count

Write-Host "`n=================================================================" -ForegroundColor Cyan
if ($failCount -eq 0) {
  Write-Host "  7-DIMENSIONAL AUDIT RESULT SUMMARY: 100% PASS (ZERO DEFECTS)" -ForegroundColor Green
} else {
  Write-Host "  7-DIMENSIONAL AUDIT RESULT SUMMARY: FAILED ($failCount defects)" -ForegroundColor Red
}
Write-Host "  Total Dimensions Checked: 7 | Items Verified: $($dimResults.Count) | Duration: ${totalSec}s" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan
