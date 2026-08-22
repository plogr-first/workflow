[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')][string]$Slug,
  [Parameter(Mandatory)][string]$MatrixJson,
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$SessionName,
  [switch]$SkipAgentLaunch,
  [switch]$SkipMonitor
)

$ErrorActionPreference = 'Stop'

if ($env:HERDR_ENV -ne '1') {
  throw "Start-HerdrParallelWorkflow requires HERDR_ENV=1. Run within a Herdr-managed project."
}

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profilePath = Join-Path $project 'herdr\dispatch-profile.json'
if (-not (Test-Path -LiteralPath $profilePath)) {
 throw "Project dispatch profile not found at '$profilePath'. Run 'plogr init' first."
}

$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
if ($profile.project_skill_registry_required -eq $true) {
  $registryRelative = if ($profile.project_skill_registry) { [string]$profile.project_skill_registry } else { '.agents/project-skills.json' }
  $registryPath = Join-Path $project $registryRelative
 try { $projectSkillRegistry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json } catch { throw "Project skill registration is missing or invalid: $registryPath. Re-run 'plogr init' to register project skills." }
 if (-not $projectSkillRegistry.registrations -or @($projectSkillRegistry.registrations).Count -eq 0) { throw "Project skill registration has no active platform entries: $registryPath. Re-run 'plogr init'." }
}
$boundSession = if ($profile.herdr_session.name) { [string]$profile.herdr_session.name } elseif ($profile.herdr_session) { [string]$profile.herdr_session } else { 'default' }
$targetSession = if ($SessionName) { $SessionName } else { $boundSession }
if ($targetSession -ne $boundSession) {
  throw "Session mismatch: Project is bound to Herdr session '$boundSession', but '$targetSession' was requested."
}

$matrix = $MatrixJson | ConvertFrom-Json
if (-not $matrix -or $matrix.Count -lt 1) {
  throw "Matrix must contain at least 1 parallel task definition."
}

# Verify Git baseline
$isGit = (& git -C $project rev-parse --is-inside-work-tree 2>&1)
if ($isGit.Trim() -ne 'true') {
  throw "Project at '$project' is not a valid Git repository."
}
$headCommit = (& git -C $project rev-parse --verify HEAD 2>&1)
if ($LASTEXITCODE -ne 0) {
  throw "Git repository has no initial baseline commit."
}

$dateStr = Get-Date -Format 'yyyy-MM-dd'
$timeStr = Get-Date -Format 'HHmmss'
$wfId = "wf-$Slug-$timeStr"
$wfDir = Join-Path $project "herdr\parallel\$dateStr\$timeStr--workflow--$Slug"
New-Item -ItemType Directory -Force -Path $wfDir | Out-Null

$eventsPath = Join-Path $wfDir 'events.jsonl'
$wfPath = Join-Path $wfDir 'workflow.json'

function Append-Event([string]$EvName, [hashtable]$Payload) {
  $entry = [ordered]@{
    at = (Get-Date -Format o)
    event = $EvName
    workflow_id = $wfId
  }
  foreach ($k in $Payload.Keys) { $entry[$k] = $Payload[$k] }
  ($entry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $eventsPath -Encoding utf8
}

Append-Event 'parallel_workflow_created' @{ slug = $Slug; matrix_count = $matrix.Count }

$matrixItems = [System.Collections.Generic.List[PSCustomObject]]::new()
$masterWf = [ordered]@{
  schema_version = 3; workflow_id = $wfId; mode = 'parallel_task'; slug = $Slug; session_name = $targetSession; project_root = $project
  state = 'initializing'; next_role = 'matrix_tasks'; repair_round = 0; max_repair_rounds = 2; created_at = (Get-Date -Format o); updated_at = (Get-Date -Format o)
  last_processed = [ordered]@{ task_outcome_hash = $null; verifier_outcome_hash = $null }; matrix = $matrixItems; git = $profile.git; verifier = $null
}
function Save-MasterWorkflow { $masterWf.updated_at = (Get-Date -Format o); $tmp = "$wfPath.$([guid]::NewGuid().ToString('N')).tmp"; $masterWf | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding utf8; Move-Item -LiteralPath $tmp -Destination $wfPath -Force }
Save-MasterWorkflow
$worktreeBase = Join-Path $project '.worktrees'
if (-not (Test-Path -LiteralPath $worktreeBase)) {
  New-Item -ItemType Directory -Force -Path $worktreeBase | Out-Null
}

$agentScript = Join-Path $PSScriptRoot 'Start-HerdrAgent.ps1'
function Invoke-ExpectedGitCleanup([string[]]$Arguments) {
  # An absent stale resource is expected. Windows PowerShell can otherwise
  # surface git's non-zero cleanup exit as a terminating NativeCommandError.
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & git @Arguments 2>$null | Out-Null
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

# 1. Mount all parallel Worktrees and launch Agents concurrently
foreach ($sub in $matrix) {
  $subId = [string]$sub.id
  $subSlug = "$Slug-$subId"
  $subAgentKind = if ($sub.agent) { [string]$sub.agent } elseif ($profile.task_agent.kind) { [string]$profile.task_agent.kind } else { 'codex' }
  $subPrompt = [string]$sub.prompt
  $subScope = if ($sub.scope) { [string]$sub.scope } else { '**/*' }

  $wtDir = Join-Path $worktreeBase "wf-$subSlug"
  $branchName = "wf/$Slug/$subId"

  # Clean old worktree/branch if exists
  if (Test-Path -LiteralPath $wtDir) {
    # Removing a stale worktree can legitimately fail when its metadata is
    # already gone.  This cleanup must not turn that expected condition into a
    # native-command exception under PowerShell.
    Invoke-ExpectedGitCleanup @('-C', $project, 'worktree', 'remove', '--force', $wtDir)
  }
  # Likewise, an absent branch is the normal first-run condition.
  Invoke-ExpectedGitCleanup @('-C', $project, 'branch', '-D', $branchName)

  # Create branch and isolated worktree
  # Git reports normal worktree progress on stderr. Capture it while allowing
  # the actual exit code (rather than PowerShell's stderr adaptation) to decide
  # whether creation succeeded.
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $worktreeAddOutput = & git -C $project worktree add -b $branchName $wtDir HEAD 2>&1
    $worktreeAddExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($worktreeAddExit -ne 0) {
    throw "Failed to create isolated worktree '$wtDir' on branch '$branchName': $($worktreeAddOutput -join ' ')"
  }

  $subHandoff = Join-Path $wfDir "sub-$subId"
  New-Item -ItemType Directory -Force -Path $subHandoff | Out-Null

  $subResult = Join-Path $subHandoff 'task-result.md'
  $subOutcome = Join-Path $subHandoff 'task-outcome.json'
  $subBrief = Join-Path $subHandoff 'task-brief.md'

  # Launch agent in its own isolated worktree
  $agentName = "wf-$subSlug-$subAgentKind"
  $fullPrompt = @"
[PARALLEL SUBTASK: $subId]
Scope: $subScope
Prompt: $subPrompt

Worktree Path: $wtDir
Candidate Branch: $branchName
"@

  $subItem = [ordered]@{
    id = $subId
    slug = $subSlug
    agent = $subAgentKind
    agent_name = $agentName
    scope = $subScope
    worktree_path = $wtDir
    branch = $branchName
    handoff = $subHandoff
    result = $subResult
    outcome = $subOutcome
    brief = $subBrief
    status = 'executing'
  }
  $matrixItems.Add([pscustomobject]$subItem)
  $masterWf.matrix = $matrixItems
  Save-MasterWorkflow

  Append-Event 'subtask_dispatched' @{ subtask_id = $subId; branch = $branchName; worktree = $wtDir; agent = $subAgentKind }

  if (-not $SkipAgentLaunch) {
    try {
      & $agentScript `
        -Name $agentName `
        -Profile 'task' `
        -Category 'task' `
        -Prompt $fullPrompt `
        -ProjectRoot $wtDir `
        -HandoffDirectory $subHandoff `
        -SessionName $targetSession 2>&1 | Out-Null
    } catch {
      $subItem.status = 'blocked'; $masterWf.state = 'blocked'; $masterWf.next_role = ''; $masterWf | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue ("parallel agent launch failed: " + $_.Exception.Message)
      Save-MasterWorkflow; Append-Event 'parallel_agent_launch_failed' @{ subtask_id = $subId; error = $_.Exception.Message }
      throw
    }
  } else {
    # Generate brief without pane launch
    $subBriefContent = @"
# Brief: $agentName
- Scope: $subScope
- Worktree: $wtDir
- Branch: $branchName
$fullPrompt
"@
    Set-Content -LiteralPath $subBrief -Value $subBriefContent -Encoding utf8
  }
}

# 2. Prepare Verifier & Master Workflow JSON
$verAgentKind = if ($profile.verification_agent.kind) { [string]$profile.verification_agent.kind } elseif ($profile.verification.agent) { [string]$profile.verification.agent } else { 'codex' }
$verifierName = "wf-verify-$Slug-$verAgentKind"
if ($verifierName.Length -gt 32) { $verifierName = $verifierName.Substring(0, 32) }
$verifierHandoff = Join-Path $wfDir 'verifier'
New-Item -ItemType Directory -Force -Path $verifierHandoff | Out-Null
$verResult = Join-Path $verifierHandoff 'verify-result.md'
$verOutcome = Join-Path $verifierHandoff 'verify-outcome.json'
$verBrief = Join-Path $verifierHandoff 'verifier-brief.md'

if (-not $SkipAgentLaunch) {
  $waitPrompt = "You are the deferred verification Agent for parallel workflow $Slug. Do not begin review until the workflow monitor merges all candidate branches into .worktrees/wf-$Slug-integration and wakes you. When awakened, use /code-review, verify 5 gates, and write result.md, verification.md, and outcome.json."
  try {
    $verObj = & $agentScript -Profile verification -DeferActivation -Name $verifierName -Category 'task' -Slug "$Slug-verify" -Prompt $waitPrompt -ProjectRoot $project -SessionName $targetSession -Direction down -HandoffDirectory $verifierHandoff | ConvertFrom-Json
  } catch { $masterWf.state = 'blocked'; $masterWf.next_role = ''; $masterWf | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue ("parallel verifier launch failed: " + $_.Exception.Message); Save-MasterWorkflow; Append-Event 'parallel_verifier_launch_failed' @{ error = $_.Exception.Message }; throw }
}

$masterWf.state = 'executing'
$masterWf.matrix = $matrixItems
$masterWf.verifier = [ordered]@{
    name = $verifierName
    original_agent_name = $verifierName
    active_agent_name = $verifierName
    handoff = $verifierHandoff
    brief = $verBrief
    result = $verResult
    outcome = $verOutcome
}
Save-MasterWorkflow

# 3. Start Background Monitor
$process = $null
if (-not $SkipMonitor) {
  $monitor = Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
  $psHost = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
  $monitorArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`" -WorkflowPath `"$wfPath`""
  try { $process = Start-Process -FilePath $psHost -ArgumentList $monitorArgs -WindowStyle Hidden -PassThru } catch {
    $masterWf.state='blocked';$masterWf.next_role='';$masterWf|Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue ("monitor launch failed: " + $_.Exception.Message);Save-MasterWorkflow;Append-Event 'parallel_monitor_launch_failed' @{error=$_.Exception.Message};throw
  }
}

Write-Host "`n╔═════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  🚀 PLOGR MATRIX PARALLEL WORKFLOW DISPATCHED                           ║" -ForegroundColor Cyan
Write-Host "║  Master Workflow : $wfId" -ForegroundColor DarkCyan
Write-Host "║  Parallel Matrix : $($matrix.Count) Sub-Worktrees Mounted" -ForegroundColor DarkCyan
Write-Host "║  Monitor Process : $(if($process){'PID ' + $process.Id}else{'Deferred/Manual'})" -ForegroundColor DarkCyan
Write-Host "║  Session Name    : $targetSession" -ForegroundColor DarkCyan
Write-Host "╚═════════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

return $wfPath
