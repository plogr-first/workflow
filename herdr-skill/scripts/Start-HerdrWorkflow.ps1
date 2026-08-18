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
$stamp = Get-Date -Format 'HHmmss'
function New-AgentName([string]$Prefix) {
  $raw = "$Prefix-$stamp-$Slug".ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
  return $raw.Substring(0, [Math]::Min(32, $raw.Length)).TrimEnd('-')
}
if (-not $TaskName) { $TaskName = New-AgentName $(if($Mode -eq 'research'){'research'}elseif($Mode -eq 'bugfix'){'bugfix'}else{'task'}) }
if (-not $VerifierName) { $VerifierName = New-AgentName 'verify' }
if ($TaskName -eq $VerifierName) { throw 'Task and verification Agent names must differ.' }
$launcher = Join-Path $PSScriptRoot 'Start-HerdrAgent.ps1'
$taskProfile = if ($Mode -eq 'research') { 'research' } else { 'task' }
$task = & $launcher -Profile $taskProfile -Name $TaskName -Category $Mode -Slug $Slug -Prompt $Prompt -ProjectRoot $project | ConvertFrom-Json
if (-not $task.name -or -not $task.outcome) { throw 'Task Agent dispatch did not return a durable handoff.' }
$waitPrompt = "You are the deferred verification Agent for workflow $Mode/$Slug. Do not begin review and do not write result.md until the workflow monitor wakes you with the candidate handoff path. When awakened, follow your brief and write both result.md and outcome.json."
$verifier = & $launcher -Profile verification -DeferActivation -Name $VerifierName -Category $Mode -Slug "$Slug-verify" -Prompt $waitPrompt -ProjectRoot $project | ConvertFrom-Json
if (-not $verifier.name -or -not $verifier.outcome) { throw 'Verification Agent dispatch did not return a durable handoff.' }
$workflowRoot = Join-Path $project ("herdr\\$Mode\\{0}\\{1}--workflow--{2}" -f (Get-Date -Format 'yyyy-MM-dd'), $stamp, $Slug)
New-Item -ItemType Directory -Force -Path $workflowRoot | Out-Null
$workflowPath = Join-Path $workflowRoot 'workflow.json'
$workflow = [ordered]@{
  schema_version = 1; mode = $Mode; slug = $Slug; state = 'running'; repair_round = 0; max_repair_rounds = 1; created_at = (Get-Date -Format o)
  task = $task; verifier = $verifier
}
$workflow | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $workflowPath -Encoding utf8
$monitor = Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
$args = "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`" -WorkflowPath `"$workflowPath`""
$process = Start-Process -FilePath pwsh.exe -ArgumentList $args -WindowStyle Hidden -PassThru
[pscustomobject]@{workflow=$workflowPath; monitor_pid=$process.Id; task=$task; verifier=$verifier} | ConvertTo-Json -Depth 12
