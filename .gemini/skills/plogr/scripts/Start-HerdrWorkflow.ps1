[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('research','task','bugfix')][string]$Mode,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$Slug,
  [Parameter(Mandatory)][string]$Prompt,
  [string]$TaskName,
  [string]$VerifierName,
  [string]$ProjectRoot = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
if ($env:HERDR_ENV -ne '1') { throw 'HERDR_ENV is not 1. Start a workflow from a Herdr-managed pane.' }
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profilePath = Join-Path $project 'herdr\dispatch-profile.json'
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Herdr dispatch profile not found: $profilePath. Run 'npx plogr-workflow' first." }
$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
if ($profile.template -eq $true) { throw "Herdr dispatch profile is a template: $profilePath. Run 'npx plogr-workflow' in the target project to create an initialized profile before dispatching work." }
if ($profile.project_skill_registry_required -eq $true) {
  $registryRelative = if ($profile.project_skill_registry) { [string]$profile.project_skill_registry } else { '.agents/project-skills.json' }
  $registryPath = Join-Path $project $registryRelative
  try { $projectSkillRegistry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json } catch { throw "Project skill registration is missing or invalid: $registryPath. Re-run 'npx plogr-workflow' to register project skills." }
  if (-not $projectSkillRegistry.registrations -or @($projectSkillRegistry.registrations).Count -eq 0) { throw "Project skill registration has no active platform entries: $registryPath. Re-run 'npx plogr-workflow'." }
}
$session = [string]$profile.herdr_session.name
if ([string]::IsNullOrWhiteSpace($session)) { throw "Herdr profile is missing herdr_session.name: $profilePath" }
$git = $profile.git
if ($Mode -ne 'research' -and $git.repository -and -not $git.has_commit) { throw "Git is initialized but has no baseline commit in $project. Review the project, create the first commit, rerun 'npx plogr-workflow', then dispatch task/bugfix." }
$requiredSkills = if($Mode -eq 'research'){@('research')}elseif($Mode -eq 'bugfix'){@('diagnosing-bugs','implement','code-review')}else{@('implement','code-review')}
function Test-HerdrSkillAvailable($Manifest, [string]$Skill) {
  $aliases = switch ($Skill) {
    'implement' { @('implement', 'task_agent', 'task-agent') }
    'diagnosing-bugs' { @('diagnosing-bugs', 'bugfix_agent', 'bugfix-agent') }
    'code-review' { @('code-review', 'verification_agent', 'verification-agent') }
    'research' { @('research', 'research_agent', 'research-agent') }
    default { @($Skill, ($Skill -replace '-', '_'), ($Skill -replace '_', '-')) }
  }
  foreach ($name in $aliases) {
    if ($Manifest.psobject.Properties[$name] -and $Manifest.$name.available) { return $true }
  }
  return $false
}
foreach($skill in $requiredSkills){
  if (-not (Test-HerdrSkillAvailable $profile.mattpocock_skills $skill)) {
    throw "Required workflow skill '$skill' is not installed in $profilePath. Re-run 'npx plogr-workflow' in this project to deploy and register skills."
  }
}
$stamp = Get-Date -Format 'HHmmssfff'
function New-AgentName([string]$Prefix) {
  # Preserve the role suffix inside Herdr's 32-character name limit; truncating
  # the whole name can make task and verifier collide for long workflow slugs.
  $safePrefix = ($Prefix.ToLowerInvariant() -replace '[^a-z0-9_-]', '-')
  if ($safePrefix.Length -gt 10) { $safePrefix = $safePrefix.Substring(0, 10).TrimEnd('-') }
  $safeSlug = $Slug.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
  $head = "wf-$stamp-"
  $suffix = "-$safePrefix"
  $maxSlugLength = [Math]::Max(1, 32 - $head.Length - $suffix.Length)
  $shortSlug = $safeSlug.Substring(0, [Math]::Min($maxSlugLength, $safeSlug.Length)).TrimEnd('-')
  if ([string]::IsNullOrWhiteSpace($shortSlug)) { $shortSlug = 'job' }
  return "$head$shortSlug$suffix"
}
if (-not $TaskName) { $TaskName = New-AgentName $(if($Mode -eq 'research'){'research'}elseif($Mode -eq 'bugfix'){'bugfix'}else{'task'}) }
if (-not $VerifierName) { $VerifierName = New-AgentName 'verify' }
if ($TaskName -eq $VerifierName) { throw 'Task and verification Agent names must differ.' }
$launcher = Join-Path $PSScriptRoot 'Start-HerdrAgent.ps1'
$taskProfile = if ($Mode -eq 'research') { 'research' } elseif ($Mode -eq 'bugfix') { 'root_cause' } else { 'task' }
$workflowRoot = Join-Path $project ("herdr\$Mode\{0}\{1}--workflow--{2}" -f (Get-Date -Format 'yyyy-MM-dd'), $stamp, $Slug)
New-Item -ItemType Directory -Force -Path $workflowRoot | Out-Null
$workflowPath = Join-Path $workflowRoot 'workflow.json'
$eventsPath = Join-Path $workflowRoot 'events.jsonl'
$workflow = [ordered]@{
  schema_version = 3; workflow_id = "wf-$stamp-$Slug"; mode = $Mode; slug = $Slug; session_name = $session; project_root = $project; git = $git; required_skills = $requiredSkills
  state = 'initializing'; next_role = 'task'; repair_round = 0; max_repair_rounds = 2; recovery_attempts = [ordered]@{ task = 0; verification = 0; max = 2 }; created_at = (Get-Date -Format o); updated_at = (Get-Date -Format o)
  last_processed = [ordered]@{ task_outcome_hash = $null; verifier_outcome_hash = $null }
  task = $null; verifier = $null
}
function Write-AtomicJson($Value, [string]$Path) {
  $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding utf8
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Append-Event([string]$Event, [hashtable]$Fields = @{}) {
  $record = [ordered]@{ at = (Get-Date -Format o); event = $Event }
  foreach ($key in $Fields.Keys) { $record[$key] = $Fields[$key] }
  ($record | ConvertTo-Json -Compress -Depth 10) | Add-Content -LiteralPath $eventsPath -Encoding utf8
}
Write-AtomicJson $workflow $workflowPath
Append-Event 'workflow_initializing' @{ workflow_id = $workflow.workflow_id; session = $session; next_role = 'task' }
$task = $null
$verifier = $null
try {
  $task = & $launcher -Profile $taskProfile -Name $TaskName -Category $Mode -Slug $Slug -Prompt $Prompt -ProjectRoot $project -SessionName $session | ConvertFrom-Json
  if (-not $task.name -or -not $task.outcome) { throw 'Task Agent dispatch did not return a durable handoff.' }
  $task | Add-Member -Force -NotePropertyName original_agent_name -NotePropertyValue ([string]$task.name)
  $task | Add-Member -Force -NotePropertyName active_agent_name -NotePropertyValue ([string]$task.name)
  $workflow.task = $task
  Write-AtomicJson $workflow $workflowPath
  $waitPrompt = "You are the deferred verification Agent for workflow $Mode/$Slug. Do not begin review and do not write result.md until the workflow monitor wakes you with the candidate handoff path. When awakened, use the configured official mattpocock /code-review skill and write result.md, verification.md, and outcome.json."
  $verifier = & $launcher -Profile verification -DeferActivation -Name $VerifierName -Category $Mode -Slug "$Slug-verify" -Prompt $waitPrompt -ProjectRoot $project -SessionName $session -Direction down | ConvertFrom-Json
  if (-not $verifier.name -or -not $verifier.outcome) { throw 'Verification Agent dispatch did not return a durable handoff.' }
  $verifier | Add-Member -Force -NotePropertyName original_agent_name -NotePropertyValue ([string]$verifier.name)
  $verifier | Add-Member -Force -NotePropertyName active_agent_name -NotePropertyValue ([string]$verifier.name)
  $workflow.verifier = $verifier
  $workflow.state = 'executing'
  Write-AtomicJson $workflow $workflowPath
  Append-Event 'workflow_created' @{ workflow_id = $workflow.workflow_id; session = $session; next_role = 'task' }
} catch {
  foreach ($entry in @($task, $verifier)) { if ($entry -and $entry.pane_id) { try { & herdr --session $session pane close ([string]$entry.pane_id) 2>$null | Out-Null } catch {} } }
  $workflow.state = 'blocked'; $workflow.next_role = ''; $workflow | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue ("workflow initialization failed: " + $_.Exception.Message)
  Write-AtomicJson $workflow $workflowPath
  Append-Event 'workflow_initialization_failed' @{ error = $_.Exception.Message }
  throw
}
$monitor = Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
$psHost = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
$monitorArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`" -WorkflowPath `"$workflowPath`""
try {
  $process = Start-Process -FilePath $psHost -ArgumentList $monitorArgs -WindowStyle Hidden -PassThru
} catch {
  foreach ($entry in @($task, $verifier)) { if ($entry -and $entry.pane_id) { try { & herdr --session $session pane close ([string]$entry.pane_id) 2>$null | Out-Null } catch {} } }
  $workflow.state = 'blocked'; $workflow.next_role = ''; $workflow | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue ("monitor launch failed: " + $_.Exception.Message)
  Write-AtomicJson $workflow $workflowPath
  Append-Event 'workflow_monitor_launch_failed' @{ error = $_.Exception.Message }
  throw
}
[pscustomobject]@{workflow=$workflowPath; monitor_pid=$process.Id; workflow_id=$workflow.workflow_id; session=$session; task=$task; verifier=$verifier} | ConvertTo-Json -Depth 12
