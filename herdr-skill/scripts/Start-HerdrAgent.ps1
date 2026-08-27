[CmdletBinding()]
param(
  [string]$Kind,
  [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_-]{0,31}$')][string]$Name,
  [Parameter(Mandatory)][ValidateSet('research','task','bugfix')][string]$Category,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$Slug,
  [Parameter(Mandatory)][string]$Prompt,
  [ValidateSet('full','plan')][string]$Access = 'full',
  [string]$OpenCodeModel,
  [ValidateSet('root_cause','task','verification','research')][string]$Profile,
  [switch]$DeferActivation,
  [string]$ProjectRoot = (Get-Location).Path,
  [ValidateSet('right','down')][string]$Direction = 'right',
  [string]$SessionName,
  [string]$HandoffDirectory,
  [switch]$SkipAgentLaunch
)
$ErrorActionPreference = 'Stop'
function Resolve-OpenCodeModel([string]$Requested) {
  $aliases = @{
    'zen'='opencode/deepseek-v4-flash-free'; 'zen-free'='opencode/deepseek-v4-flash-free'; 'deepseek-v4-flash-free'='opencode/deepseek-v4-flash-free'
    'go'='opencode-go/deepseek-v4-flash'; 'go-flash'='opencode-go/deepseek-v4-flash'; 'deepseek-v4-flash'='opencode-go/deepseek-v4-flash'
    'go-pro'='opencode-go/deepseek-v4-pro'; 'flash'='opencode-go/deepseek-v4-flash'
    'sol'='pixel/gpt-5.6-sol'; 'terra'='pixel/gpt-5.6-Terra'; 'luna'='pixel/gpt-5.6-Luna'
    'glm'='opencode-go/glm-5.3'; 'glm-5.3'='opencode-go/glm-5.3'; 'glm-5.2'='opencode-go/glm-5.2'
    'qwen'='opencode-go/qwen3.8-max'; 'qwen3.8'='opencode-go/qwen3.8-max'; 'qwen3.7'='opencode-go/qwen3.7-max'
    'kimi'='opencode-go/kimi-k2.7-code'; 'kimi-code'='opencode-go/kimi-k2.7-code'; 'kimi-k3'='opencode-go/kimi-k3'
    'grok'='opencode-go/grok-4.5'; 'mimo'='opencode-go/mimo-v2.5'; 'minimax'='opencode-go/minimax-m3'
    'claude-3-7'='anthropic/claude-3-7-sonnet'; 'claude-3-7-sonnet'='anthropic/claude-3-7-sonnet'; 'sonnet-3.7'='anthropic/claude-3-7-sonnet'
    'claude-3-5'='anthropic/claude-3-5-sonnet'; 'claude-3-5-sonnet'='anthropic/claude-3-5-sonnet'; 'sonnet-3.5'='anthropic/claude-3-5-sonnet'
    'r1'='deepseek/deepseek-reasoner'; 'reasoner'='deepseek/deepseek-reasoner'; 'deepseek-r1'='deepseek/deepseek-reasoner'
    'deepseek'='deepseek/deepseek-chat'; 'deepseek-v3'='deepseek/deepseek-chat'; 'chat'='deepseek/deepseek-chat'
    'o3-mini'='openai/o3-mini'; 'o3'='openai/o3-mini'
    'o1'='openai/o1'; 'o1-preview'='openai/o1'
    'gpt-4o'='openai/gpt-4o'; '4o'='openai/gpt-4o'
    'gemini-pro'='google/gemini-2.5-pro'; 'gemini-2.5-pro'='google/gemini-2.5-pro'
    'gemini-flash'='google/gemini-2.0-flash'; 'gemini-2.0-flash'='google/gemini-2.0-flash'
  }
  $key = $Requested.Trim().ToLowerInvariant()
  if ($aliases.ContainsKey($key)) { return $aliases[$key] }
  if ($key -match '^[a-z0-9_-]+/[a-z0-9._-]+$') { return $Requested.Trim() }
  $models = @()
  try {
    $models = @((& opencode models 2>$null) -replace "`e\[[0-9;]*m", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('-') })
  } catch { }
  if (-not $models.Count) { return $Requested.Trim() }
  $match = @($models | Where-Object { $_.Equals($key,[System.StringComparison]::OrdinalIgnoreCase) })
  if ($match.Count -eq 1) { return $match[0] }
  $normal = $key -replace '[^a-z0-9]',''
  $match = @($models | Where-Object { (($_ -replace '[^a-z0-9]','').ToLowerInvariant()).Contains($normal) })
  if ($match.Count -eq 1) { return $match[0] }
  if ($match.Count -gt 1) { throw "Ambiguous OpenCode model '$Requested'. Candidates: $($match -join ', ')" }
  return $Requested.Trim()
}
function Ensure-HerdrSessionRunning([string]$SessionName) {
  if (-not $SessionName -or $SkipAgentLaunch) { return }
  $status = & herdr --session $SessionName status server 2>&1
  if ($LASTEXITCODE -ne 0 -or ($status -match 'not running')) {
    Start-Process -FilePath herdr -ArgumentList @('--session', $SessionName, 'server') -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 1000
    try { & herdr --session $SessionName workspace create 2>$null | Out-Null } catch { }
  }
}
function Invoke-HerdrJson([string[]]$Arguments) {
  if (-not $script:HerdrSession) { throw "Herdr session name is not configured. Direct operations must be isolated to a named session." }
  Ensure-HerdrSessionRunning $script:HerdrSession
  $raw = & herdr --session $script:HerdrSession @Arguments 2>&1
  $text = $raw -join "`n"
  try { return @{ exit=$LASTEXITCODE; json=($text | ConvertFrom-Json); text=$text } }
  catch { throw "Herdr returned non-JSON output: $text" }
}
function Start-AgentWhenPaneReady([string]$Pane,[string[]]$NativeArgs) {
  $deadline = (Get-Date).AddSeconds(45)
  do {
    $command = @('agent','start',$Name,'--kind',$Kind,'--pane',$Pane,'--timeout','60000')
    if ($NativeArgs.Count) { $command += '--'; $command += $NativeArgs }
    $attempt = Invoke-HerdrJson $command
    if ($attempt.exit -eq 0 -and $attempt.json.result.agent.interactive_ready -and $attempt.json.result.agent.agent -eq $Kind -and @('blocked','error') -notcontains [string]$attempt.json.result.agent.agent_status) { return $attempt.json.result.agent }
    # Claude Code may pause on its one-time workspace trust dialog. It is safe
    # to accept only when the visible pane explicitly contains the confirmation
    # prompt; otherwise leave the agent untouched and surface the real error.
    try {
      $visible = (& herdr --session $script:HerdrSession pane read $Pane --source recent --lines 40 2>$null) -join "`n"
      if ($visible -match 'Enter to confirm|Yes, I trust this folder|Yes, continue|Press enter to continue') {
        & herdr --session $script:HerdrSession pane send-keys $Pane enter 2>$null | Out-Null
        if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 1000; continue }
      }
    } catch { }
    if ([string]$attempt.json.error.code -in @('agent_pane_busy','agent_pane_not_ready','pane_busy','pane_not_ready','shell_not_ready') -or $attempt.exit -ne 0) {
      if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 750; continue }
    }
    throw "Herdr agent start failed: $($attempt.text)"
  } while ((Get-Date) -lt $deadline)
  throw "New pane $Pane did not become an available shell within 45 seconds."
}
function Ensure-WindowsAgentShim([string]$Project,[string]$AgentKind,[string]$Executable,[string]$Pane) {
  if ($env:OS -ne 'Windows_NT' -or $AgentKind -ne 'opencode') { return }
  $exe = if ($Executable) { $Executable } else { (Get-Command opencode.cmd -ErrorAction SilentlyContinue).Source }
  if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'OpenCode Windows executable (.cmd) was not found.' }
  $shimDir = Join-Path $Project '.herdr-bin'
  New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
  $shim = Join-Path $shimDir 'opencode.cmd'
  $shimContent = '@echo off' + [Environment]::NewLine + 'call "' + $exe + '" %*' + [Environment]::NewLine
  Set-Content -LiteralPath $shim -Encoding ascii -Value $shimContent
  $pathCommand = '$env:PATH = "' + $shimDir.Replace('"','`"') + ';$env:PATH"'
  & herdr --session $script:HerdrSession pane send-text $Pane $pathCommand 2>$null | Out-Null
  & herdr --session $script:HerdrSession pane send-keys $Pane enter 2>$null | Out-Null
  Start-Sleep -Milliseconds 300
}
if ($env:HERDR_ENV -ne '1' -and [string]::IsNullOrWhiteSpace($SessionName)) { throw 'HERDR_ENV is not 1. Run from a Herdr-managed pane or provide the bound -SessionName.' }
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profileNativeArgs = @()
$script:HerdrSession = if($SessionName){ $SessionName } else { $null }
$gitProfile = $null
$skillManifest = $null
if ($Profile) {
  if ($Kind) { throw 'Use either -Kind or -Profile, not both.' }
  $profilePath = Join-Path $project 'herdr\dispatch-profile.json'
 if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Herdr dispatch profile not found: $profilePath. Run 'plogr init' from the project root first." }
  try { $dispatchProfile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json } catch { throw "Invalid Herdr dispatch profile: $profilePath" }
  if (-not $script:HerdrSession) { $script:HerdrSession = [string]$dispatchProfile.herdr_session.name }
  if ([string]::IsNullOrWhiteSpace($script:HerdrSession)) { throw "Herdr profile is missing herdr_session.name: $profilePath. Session must be strictly specified." }
  Ensure-HerdrSessionRunning $script:HerdrSession
  $gitProfile = $dispatchProfile.git
  $skillManifest = $dispatchProfile.mattpocock_skills
  $entry = switch ($Profile) { 'root_cause' { if ($dispatchProfile.root_cause_agent) { $dispatchProfile.root_cause_agent } else { $dispatchProfile.task_agent } }; 'task' { $dispatchProfile.task_agent }; 'verification' { $dispatchProfile.verification_agent }; 'research' { $dispatchProfile.research_agent } }
  if (-not $entry -or -not $entry.kind) { throw "Profile '$Profile' is incomplete in $profilePath." }
  $Kind = [string]$entry.kind
  if ($entry.model) { $OpenCodeModel = [string]$entry.model }
  $profileNativeArgs = @($entry.full_access_args | ForEach-Object { [string]$_ } | Where-Object { $_ })
}
if (-not $Kind) { throw 'Specify -Kind or -Profile task|verification.' }
$Kind = $Kind.Trim().ToLowerInvariant()
if ($Kind -notmatch '^[a-z][a-z0-9_-]{0,31}$') { throw "Invalid Herdr agent kind '$Kind'." }
if ($Kind -ne 'opencode' -and $OpenCodeModel) { throw '-OpenCodeModel is valid only for an opencode profile or -Kind opencode.' }
$nativeArgs = @()
if ($Access -eq 'full' -and $profileNativeArgs.Count) {
  $nativeArgs += $profileNativeArgs
} else {
  switch ($Kind) {
    'claude' { if($Access -eq 'full'){$nativeArgs+='--dangerously-skip-permissions'}else{$nativeArgs+=@('--permission-mode','plan')} }
    'gemini' { if($Access -eq 'full'){$nativeArgs+='--yolo'}else{$nativeArgs+=@('--approval-mode','plan')} }
    'codex' { if($Access -eq 'full'){$nativeArgs+='--dangerously-bypass-approvals-and-sandbox'}else{$nativeArgs+=@('-s','workspace-write','-a','on-request')} }
    'opencode' { if($Access -eq 'full'){$nativeArgs+='--auto'} }
 default { if($Access -eq 'full'){throw "Custom Herdr kind '$Kind' requires a project profile with full_access_args. Run 'plogr init'."}else{throw "Plan mode is not defined for custom Herdr kind '$Kind'."} }
  }
}
if ($Kind -eq 'opencode' -and $OpenCodeModel) { $OpenCodeModel=Resolve-OpenCodeModel $OpenCodeModel; $nativeArgs+=@('-m',$OpenCodeModel) }
$date = Get-Date -Format 'yyyy-MM-dd'
$stamp = Get-Date -Format 'HHmmss'
$handoff = if ($HandoffDirectory) { $HandoffDirectory } else { Join-Path $project "herdr\$Category\$date\$stamp--$Name--$Slug" }
New-Item -ItemType Directory -Force -Path $handoff | Out-Null

$briefName = if ($Kind -eq 'research') { 'research-brief.md' } elseif ($Profile -eq 'verification') { 'verifier-brief.md' } else { 'task-brief.md' }
$resultPath = Join-Path $handoff 'result.md'
$outcomePath = Join-Path $handoff 'outcome.json'
$briefPath = Join-Path $handoff $briefName
$statusPath = Join-Path $handoff 'status.json'
$progressPath = Join-Path $handoff 'progress.json'
$pane = $null
$agent = $null
$workflowReference = Join-Path $PSScriptRoot '..\references\workflow-protocol.md'
if (Test-Path -LiteralPath $workflowReference) {
  $workflowReference = (Resolve-Path -LiteralPath $workflowReference).Path
} else {
  $workflowReference = 'references/workflow-protocol.md'
}
function Get-AgentSpecificSkillPath([string]$ProjectRoot, [string]$SkillName, [string]$AgentKind, [string]$FallbackPath) {
  $candidateDirs = @()
  switch ($AgentKind) {
    'claude'   { $candidateDirs += (Join-Path $ProjectRoot '.claude\skills'); $candidateDirs += (Join-Path $env:USERPROFILE '.claude\skills') }
    'opencode' { $candidateDirs += (Join-Path $ProjectRoot '.opencode\skills') }
    'codex'    { $candidateDirs += (Join-Path $ProjectRoot '.codex\skills') }
    'cursor'   { $candidateDirs += (Join-Path $ProjectRoot '.cursor\skills') }
    'gemini'   { $candidateDirs += (Join-Path $ProjectRoot '.gemini\skills') }
  }
  $candidateDirs += (Join-Path $ProjectRoot '.agents\skills')
  $candidateDirs += (Join-Path $env:USERPROFILE '.agents\skills')
  $candidateDirs += (Join-Path $PSScriptRoot '..\bundled_skills')

  foreach ($dir in $candidateDirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $p = Join-Path $dir "$SkillName\SKILL.md"
    if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    $pDirect = Join-Path $dir $SkillName
    if (Test-Path -LiteralPath $pDirect) {
      $nested = Join-Path $pDirect 'SKILL.md'
      if (Test-Path -LiteralPath $nested) { return (Resolve-Path -LiteralPath $nested).Path }
    }
  }
  if ($FallbackPath -and (Test-Path -LiteralPath $FallbackPath)) {
    return (Resolve-Path -LiteralPath $FallbackPath).Path
  }
  return $FallbackPath
}

$skillsSection = ""
$gitContract = if($gitProfile -and $gitProfile.repository -and -not $gitProfile.has_commit){'Git was initialized but has no baseline commit. For task/bugfix, do not edit or claim candidate: write outcome state blocked and explain that the user must review and create the initial baseline commit first.'}else{'Git baseline status permits normal task/bugfix execution; preserve unrelated changes.'}
$ghGuideline = "GitHub Operations: For any GitHub-related operations (creating PRs, inspecting PRs/issues, checking GitHub Actions/CI runs, or viewing diffs), always use the GitHub CLI (`gh`) tool (e.g. `gh pr create`, `gh pr checks`, `gh issue view`, `gh run list`) rather than manual browser steps or unauthenticated git commands."
function Get-PitfallsWarnings([string]$Project, [string]$PromptText) {
  $pitfallsFiles = @(
    (Join-Path $Project '.agents\skills\knowledge\pitfalls.jsonl'),
    (Join-Path $Project '.agents\skills\audit-suite\knowledge\pitfalls.jsonl'),
    (Join-Path $Project '.knowledge\pitfalls.jsonl'),
    (Join-Path $env:USERPROFILE '.agents\skills\audit-suite\knowledge\pitfalls.jsonl')
  )
  $rules = @()
  foreach ($pf in $pitfallsFiles) {
    if (Test-Path -LiteralPath $pf) {
      try {
        $lines = Get-Content -LiteralPath $pf | Where-Object { $_ -and $_.Trim() }
        foreach ($line in $lines) {
          $entry = $line | ConvertFrom-Json
          if ($entry.golden_rule) {
            $rules += "- **[$($entry.category)]** $($entry.golden_rule) *(历史坑点: $($entry.symptom))*"
          }
        }
      } catch {}
    }
  }
  if ($rules.Count -gt 0) {
    $dedup = @($rules | Select-Object -Unique | Select-Object -First 5)
    return @"

## ⚠️ 历史踩坑防护预警 (Project Pitfalls & Golden Rules)
$($dedup -join "`n")
"@
  }
  return ""
}

$pitfallsSection = Get-PitfallsWarnings $project $Prompt

$roleContract = switch ($Profile) {
  'research' { @"
You are the research agent. Use the official mattpocock `/research` skill. Follow $($workflowReference): use primary evidence, keep a decision-critical claim ledger with exact source evidence and access dates, state uncertainty and contradictory evidence, and remain read-only. A verifier audits evidence; do not claim unverified conclusions. $ghGuideline
"@ }
  'verification' { @"
You are the verification and integration agent. Use the official mattpocock `/code-review` skill with the fixed comparison `base_sha...candidate_sha` supplied by the candidate outcome. It performs standards and spec review; it does not replace independent acceptance testing. Read the execution candidate's result/branch/worktree supplied in the task prompt. Evaluate outcome, regression, spec/scope, and standards/integration independently. Report only reproducible P0/P1 blockers (maximum five) with acceptance rule and command/file evidence. Do not turn style suggestions into blockers. If all gates pass, confirm the target tree is clean and at the expected base, merge safely, re-run the applicable checks after merge, and report `merged` with merge SHA. Do not push: the workflow monitor owns the configured post-merge push. If any gate or safe merge fails, report `fix_required` or `blocked`; never force reset, clean, stash, or overwrite other work. $ghGuideline
"@ }
  'root_cause' { @"
You are the root-cause analysis and bugfix execution agent. Follow the mandatory 3-step pipeline:
(1) [PHASE 1 - READ-ONLY STATIC AUDIT & TRIAGE (只读审计与分诊)]: First execute the registered project `audit-suite` skill resolved through `.agents/project-skills.json` in read-only audit mode.
    - STRICT READ-ONLY PRINCIPLE (只读不改代码原则): You are strictly forbidden from modifying any production code during the audit phase.
    - AUDIT REPORT REQUIREMENTS (诊断报告必须标明定位与机理): The generated audit report (`.audit/AUDIT-REPORT-*.md` / `FIX-TASK`) MUST explicitly document:
      1. Exact Bug Location: Specific file path, line number range, and function/seam name.
      2. Root Cause Mechanism: Deeply explain *why* and *how* the current logic, state machine, or async timing causes this bug.
(2) [PHASE 2 - RED-CAPABLE REPRODUCTION (红灯复现证伪环)]: Use official mattpocock `/diagnosing-bugs` to build and run a minimal reproduction script. It MUST fail (RED 🔴) on the unpatched code. Do not ship a guess-based patch when no such reproduction loop exists.
(3) [PHASE 3 - SURGICAL ROOT-CAUSE FIX & TDD (最小切口根治与代码质量)]:
    - MINIMAL CHANGE PRINCIPLE (最小改动原则): Implement the minimal complete fix strictly at the confirmed root-cause seam. Strictly avoid unnecessary wide-scale refactoring or touching innocent files.
    - STRICT CODE QUALITY & TDD GUARANTEE (保证代码质量): Use `/implement` and `/tdd` to ensure the reproduction test turns green (GREEN 🟢), all existing regression tests pass, and all temporary debugging logs/probes are cleaned up before candidate submission.
$gitContract Before editing, make the mandatory worktree decision. Return `candidate` only with outcome fields worktree_decision, worktree_path, branch, base_sha, candidate_sha, changed_files, commands and results; do not merge. $ghGuideline
"@ }
  default { if ($Category -eq 'bugfix') { @"
You are the root-cause analysis and bugfix execution agent. Follow the mandatory 3-step pipeline:
(1) [PHASE 1 - READ-ONLY STATIC AUDIT & TRIAGE (只读审计与分诊)]: First execute the registered project `audit-suite` skill resolved through `.agents/project-skills.json` in read-only audit mode.
    - STRICT READ-ONLY PRINCIPLE (只读不改代码原则): You are strictly forbidden from modifying any production code during the audit phase.
    - AUDIT REPORT REQUIREMENTS (诊断报告必须标明定位与机理): The generated audit report (`.audit/AUDIT-REPORT-*.md` / `FIX-TASK`) MUST explicitly document:
      1. Exact Bug Location: Specific file path, line number range, and function/seam name.
      2. Root Cause Mechanism: Deeply explain *why* and *how* the current logic, state machine, or async timing causes this bug.
(2) [PHASE 2 - RED-CAPABLE REPRODUCTION (红灯复现证伪环)]: Use official mattpocock `/diagnosing-bugs` to build and run a minimal reproduction script. It MUST fail (RED 🔴) on the unpatched code. Do not ship a guess-based patch when no such reproduction loop exists.
(3) [PHASE 3 - SURGICAL ROOT-CAUSE FIX & TDD (最小切口根治与代码质量)]:
    - MINIMAL CHANGE PRINCIPLE (最小改动原则): Implement the minimal complete fix strictly at the confirmed root-cause seam. Strictly avoid unnecessary wide-scale refactoring or touching innocent files.
    - STRICT CODE QUALITY & TDD GUARANTEE (保证代码质量): Use `/implement` and `/tdd` to ensure the reproduction test turns green (GREEN 🟢), all existing regression tests pass, and all temporary debugging logs/probes are cleaned up before candidate submission.
$gitContract Before editing, make the mandatory worktree decision. Return `candidate` only with outcome fields worktree_decision, worktree_path, branch, base_sha, candidate_sha, changed_files, commands and results; do not merge. $ghGuideline
"@ } else { @"
You are the task execution agent. You MUST operate in SUBAGENT-DRIVEN DEVELOPMENT MODE as the lead orchestrator:
(1) [MANDATORY PHASE 0 - EXECUTION TOPOLOGY & CHAIN DESIGN (强制前置：设计执行链路)]:
    Before editing code or dispatching subagents, you MUST FIRST explicitly design the execution chain and dependency topology:
    - SERIAL CHAINS (串行依赖链路): Clearly identify subtasks with upstream dependencies (e.g. data model / API schema -> domain business logic -> UI integration) that MUST execute sequentially to avoid hallucinated interfaces.
    - PARALLEL BATCHES (并行并发批次): Clearly identify decoupled, independent work packages (e.g. separate domain modules, utility helpers, independent test suites) that CAN execute concurrently across subagents to maximize throughput.
    - Record your designed Execution Chain (Serial vs Parallel topology) in your progress tracking and result.md before launching subagents.
(2) [STRUCTURED SUBAGENT DISPATCH (按拓扑派发)]: Dispatch focused subagents according to your designed chain (sequencing serial dependencies strictly and firing parallel batches concurrently).
(3) [COHESIVE INTEGRATION, MINIMAL CHANGE & TDD QUALITY (统一集成、最小改动与质量保证)]:
    - MINIMAL CHANGE PRINCIPLE (最小改动原则): Implement the smallest complete change that fulfills all requirements. Strictly avoid scope creep or touching unrelated code.
    - STRICT CODE QUALITY GUARANTEE (保证代码质量): Enforce clean architecture, type safety, and comprehensive test coverage. Use official mattpocock `/implement` for integration, use `/tdd` at confirmed seams, and run `/code-review` against the candidate before handoff.
$gitContract Before editing, define observable acceptance checks and make the mandatory worktree decision. Use an isolated worktree for dirty shared trees, concurrent work, or overlap risk. Implement the smallest complete change, run focused and relevant full validation, and commit the candidate branch. Return `candidate` only with outcome fields worktree_decision (`isolated` or `in_place`), worktree_path, branch, base_sha, candidate_sha, changed_files, acceptance checks and command results; do not merge. $ghGuideline
"@ } }
}
try {
@"
# Brief

- Agent: $Name
- Kind: $Kind
- Access: $Access
- GitHub CLI Standard: Use `gh` CLI for all GitHub actions (issues, PRs, CI runs).

## Task
$Prompt
$pitfallsSection
## Workflow role contract
$roleContract

Your `progress.json` must be updated at phase boundaries with `{ "phase": "investigating|implementing|testing|candidate_ready|blocked", "updated_at": "...", "completed": [], "next_action": "..." }`. Your `result.md` must state the workflow state (`candidate`, `passed`, `fix_required`, `blocked`, or `merged`), conclusion, commands/tests and outcomes, evidence, changed files, blockers, and confirmation that no secrets were recorded. Include the worktree/branch/commit/merge facts applicable to your role. For `research`, remain read-only unless the user explicitly requests changes.

Before notifying completion, also write valid JSON to `$outcomePath` using this minimum schema:
```json
{ "state": "candidate|passed|fix_required|blocked|merged", "summary": "short evidence-backed result" }
```
Add `branch`, `base_sha`, `candidate_sha`, `merge_sha`, `blockers`, and `verification_commands` whenever applicable. The workflow monitor uses this file to wake the next Agent; a TUI reply alone is invalid.

## Mandatory completion contract
Only after completing your role's required evidence, write full Markdown evidence to `$resultPath` and valid JSON to `$outcomePath`, then run:
`herdr notification show "Herdr: $Name 已完成" --body "$resultPath" --sound done`
Do not report completion only in the TUI.
"@ | Set-Content -LiteralPath $briefPath -Encoding utf8

  if ($SkipAgentLaunch) {
    return [ordered]@{
      name = $Name
      kind = $Kind
      profile = $Profile
      handoff = $handoff
      brief = $briefPath
      result = $resultPath
      outcome = $outcomePath
    }
  }

  $pane = $null
  try {
    $paneList = (Invoke-HerdrJson @('pane','list')).json
    $paneCount = if ($paneList.result.panes) { $paneList.result.panes.Count } else { 0 }
    # External PowerShell callers have no HERDR_PANE_ID, so --current cannot be resolved reliably.
    # A dedicated tab produces a fresh shell for the agent.
    if ($paneCount -ge 4 -or [string]::IsNullOrWhiteSpace([string]$env:HERDR_PANE_ID)) {
      $tabResult = (Invoke-HerdrJson @('tab','create','--cwd',$project)).json
      $pane = [string]$tabResult.result.root_pane.pane_id
    } else {
      $splitResult = (Invoke-HerdrJson @('pane','split','--current','--direction',$Direction,'--cwd',$project,'--no-focus')).json
      $pane = [string]$splitResult.result.pane.pane_id
    }
  } catch {
    $paneList = (Invoke-HerdrJson @('pane','list')).json
    $firstPane = if ($paneList.result.panes.Count -gt 0) { [string]$paneList.result.panes[0].pane_id } else { $null }
    if ($firstPane) {
      try {
        $splitResult = (Invoke-HerdrJson @('pane','split','--pane',$firstPane,'--direction',$Direction,'--cwd',$project,'--no-focus')).json
        $pane = [string]$splitResult.result.pane.pane_id
      } catch {
        $tabResult = (Invoke-HerdrJson @('tab','create','--cwd',$project)).json
        $pane = [string]$tabResult.result.root_pane.pane_id
      }
    } else {
      $tabResult = (Invoke-HerdrJson @('workspace','create')).json
      $pane = [string]$tabResult.result.root_pane.pane_id
    }
  }
  if (-not $pane) { throw 'Herdr did not return a pane ID.' }
  # Wait for the newly split PowerShell pane to reach its interactive prompt before agent start.
  Start-Sleep -Seconds 5
  Ensure-WindowsAgentShim $project $Kind ([string]$entry.executable) $pane
  $agent=Start-AgentWhenPaneReady $pane $nativeArgs
  if(-not $agent -or $agent.agent -ne $Kind -or -not $agent.interactive_ready){throw 'Herdr did not return a confirmed interactive agent.'}
  $status=[ordered]@{name=$Name;kind=$Kind;access=$Access;model=$OpenCodeModel;profile=$Profile;deferred=[bool]$DeferActivation;pane_id=$pane;session_name=$script:HerdrSession;started_at=(Get-Date -Format o);brief_path=$briefPath;result_path=$resultPath;outcome_path=$outcomePath;progress_path=$progressPath;start_result=$agent}
  $status|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statusPath -Encoding utf8
  [ordered]@{phase='investigating';updated_at=(Get-Date -Format o);completed=@();next_action=if($DeferActivation){'wait for workflow monitor activation'}else{'read brief and begin role work'}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $progressPath -Encoding utf8
  $watchPid=$null
  if(-not $DeferActivation){
    $message="Read $briefPath. You are $Name. Follow the workflow role contract exactly; reopen the brief at every phase boundary. Before completion write $resultPath and $outcomePath, then send the exact Herdr completion notification. A TUI reply alone is invalid. Final reply: summary plus result path only."
    if($Kind -eq 'opencode'){Start-Sleep -Seconds 3;Invoke-HerdrJson @('pane','send-text',$pane,$message)|Out-Null;Invoke-HerdrJson @('pane','send-keys',$pane,'enter')|Out-Null}else{Invoke-HerdrJson @('agent','prompt',$Name,$message)|Out-Null}
    $watcher=Join-Path $PSScriptRoot 'Watch-HerdrHandoff.ps1'
    $psHost = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $sessionArg = if ($script:HerdrSession) { " -SessionName `"$script:HerdrSession`"" } else { "" }
    $watchArgs="-NoProfile -ExecutionPolicy Bypass -File `"$watcher`" -AgentName `"$Name`" -StatusPath `"$statusPath`" -OutcomePath `"$outcomePath`"$sessionArg"
    $watch=Start-Process -FilePath $psHost -ArgumentList $watchArgs -WindowStyle Hidden -PassThru
    $watchPid=$watch.Id
  }
  [pscustomobject]@{name=$Name;kind=$Kind;profile=$Profile;pane_id=$pane;handoff=$handoff;brief=$briefPath;result=$resultPath;outcome=$outcomePath;progress=$progressPath;status=$statusPath;watcher_pid=$watchPid;deferred=[bool]$DeferActivation}|ConvertTo-Json -Depth 4
} catch {
  $cleanupError = $null
  if($pane){try { Invoke-HerdrJson @('pane','close',$pane) | Out-Null } catch { $cleanupError = $_.Exception.Message }}
  [pscustomobject]@{failed_at=(Get-Date -Format o);error=$_.Exception.Message;pane_id=$pane;agent_detected=($null-ne $agent);cleanup_attempted=[bool]$pane;cleanup_error=$cleanupError}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $handoff 'failure.json') -Encoding utf8
  throw
}
