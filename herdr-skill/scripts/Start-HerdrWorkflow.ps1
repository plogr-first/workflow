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
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Herdr dispatch profile not found: $profilePath. Run 'herdr init' first." }
$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$session = [string]$profile.herdr_session.name
if ([string]::IsNullOrWhiteSpace($session)) { throw "Herdr profile is missing herdr_session.name: $profilePath" }
$git = $profile.git
if (-not $git) { $git = [ordered]@{ repository = $false; has_commit = $false; target_branch = $null; push_policy = 'manual'; push_remote = $null } }
if ($Mode -ne 'research' -and $git.repository -and -not $git.has_commit) { throw "Git is initialized but has no baseline commit in $project. Review the project, create the first commit, rerun 'herdr init', then dispatch task/bugfix." }
$requiredSkills = if($Mode -eq 'research'){@('research')}elseif($Mode -eq 'bugfix'){@('diagnosing-bugs','implement','code-review')}else{@('implement','code-review')}
foreach($skill in $requiredSkills){$entry=$profile.mattpocock_skills.$skill;if(-not $entry -or -not $entry.available -or $entry.verified_official -ne $true){throw "Required mattpocock skill '$skill' is unavailable. Re-run 'herdr init' after installing the skill."}}
$stamp = Get-Date -Format 'HHmmssfff'
function New-AgentName([string]$Prefix) {
  # Preserve the role suffix inside Herdr's 32-character name limit; truncating
  # the whole name can make task and verifier collide for long workflow slugs.
  $safePrefix = $Prefix.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
  $safeSlug = $Slug.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
  $head = "wf-$stamp-"
  $suffix = "-$safePrefix"
  $maxSlugLength = 32 - $head.Length - $suffix.Length
  if ($maxSlugLength -lt 1) { throw 'Cannot construct a distinct Herdr agent name within 32 characters.' }
  $shortSlug = $safeSlug.Substring(0, [Math]::Min($maxSlugLength, $safeSlug.Length)).TrimEnd('-')
  if ([string]::IsNullOrWhiteSpace($shortSlug)) { $shortSlug = 'job' }
  return "$head$shortSlug$suffix"
}
if (-not $TaskName) { $TaskName = New-AgentName $(if($Mode -eq 'research'){'research'}elseif($Mode -eq 'bugfix'){'bugfix'}else{'task'}) }
if (-not $VerifierName) { $VerifierName = New-AgentName 'verify' }
if ($TaskName -eq $VerifierName) { throw 'Task and verification Agent names must differ.' }
$launcher = Join-Path $PSScriptRoot 'Start-HerdrAgent.ps1'
$taskProfile = if ($Mode -eq 'research') { 'research' } else { 'task' }
$task = & $launcher -Profile $taskProfile -Name $TaskName -Category $Mode -Slug $Slug -Prompt $Prompt -ProjectRoot $project | ConvertFrom-Json
if (-not $task.name -or -not $task.outcome) { throw 'Task Agent dispatch did not return a durable handoff.' }
$task | Add-Member -Force -NotePropertyName original_agent_name -NotePropertyValue ([string]$task.name)
$task | Add-Member -Force -NotePropertyName active_agent_name -NotePropertyValue ([string]$task.name)
$waitPrompt = "You are the deferred verification Agent for workflow $Mode/$Slug. Do not begin review and do not write result.md until the workflow monitor wakes you with the candidate handoff path. When awakened, use the configured official mattpocock /code-review skill and write result.md, verification.md, and outcome.json."
$verifier = & $launcher -Profile verification -DeferActivation -Name $VerifierName -Category $Mode -Slug "$Slug-verify" -Prompt $waitPrompt -ProjectRoot $project | ConvertFrom-Json
if (-not $verifier.name -or -not $verifier.outcome) { throw 'Verification Agent dispatch did not return a durable handoff.' }
$verifier | Add-Member -Force -NotePropertyName original_agent_name -NotePropertyValue ([string]$verifier.name)
$verifier | Add-Member -Force -NotePropertyName active_agent_name -NotePropertyValue ([string]$verifier.name)
$workflowRoot = Join-Path $project ("herdr\$Mode\{0}\{1}--workflow--{2}" -f (Get-Date -Format 'yyyy-MM-dd'), $stamp, $Slug)
New-Item -ItemType Directory -Force -Path $workflowRoot | Out-Null
$workflowPath = Join-Path $workflowRoot 'workflow.json'
$eventsPath = Join-Path $workflowRoot 'events.jsonl'
$workflow = [ordered]@{
  schema_version = 3; workflow_id = "wf-$stamp-$Slug"; mode = $Mode; slug = $Slug; session_name = $session; project_root = $project; git = $git; required_skills = $requiredSkills
  state = 'executing'; next_role = 'task'; repair_round = 0; max_repair_rounds = 2; recovery_attempts = [ordered]@{ task = 0; verification = 0; max = 2 }; created_at = (Get-Date -Format o); updated_at = (Get-Date -Format o)
  last_processed = [ordered]@{ task_outcome_hash = $null; verifier_outcome_hash = $null }
  task = $task; verifier = $verifier
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
Append-Event 'workflow_created' @{ workflow_id = $workflow.workflow_id; session = $session; next_role = 'task' }
$monitor = Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
$monitorArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`" -WorkflowPath `"$workflowPath`""
$process = Start-Process -FilePath pwsh.exe -ArgumentList $monitorArgs -WindowStyle Hidden -PassThru
[pscustomobject]@{workflow=$workflowPath; monitor_pid=$process.Id; workflow_id=$workflow.workflow_id; session=$session; task=$task; verifier=$verifier} | ConvertTo-Json -Depth 12
