[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkflowPath,
  [int]$PollSeconds = 5,
  [int]$TimeoutMinutes = 240,
  [switch]$Once
)
$ErrorActionPreference = 'Stop'
$workflowPath = (Resolve-Path -LiteralPath $WorkflowPath).Path
$workflowDir = Split-Path -Parent $workflowPath
$eventsPath = Join-Path $workflowDir 'events.jsonl'
$lockPath = Join-Path $workflowDir 'workflow.lock'
function Read-Workflow { Get-Content -LiteralPath $workflowPath -Raw | ConvertFrom-Json }
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
function Save-State($Workflow, [string]$State, [string]$NextRole) {
  $Workflow.state = $State; $Workflow.next_role = $NextRole; $Workflow.updated_at = (Get-Date -Format o)
  Write-AtomicJson $Workflow $workflowPath
}
function Notify([string]$Title, [string]$Body, [string]$Sound = 'done') {
  $prefix = if($script:Session){ @('--session',$script:Session) } else { @() }
  & herdr @prefix notification show $Title --body $Body --sound $Sound | Out-Null
}
function Read-Outcome([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { $o = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
  if (@('candidate','passed','fix_required','blocked','merged') -notcontains [string]$o.state) { return $null }
  return $o
}
function OutcomeHash([string]$Path) { if(Test-Path $Path){ return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }; return $null }
function Prompt-Agent([string]$Name, [string]$Message) {
  $prefix = if($script:Session){ @('--session',$script:Session) } else { @() }
  & herdr @prefix agent prompt $Name $Message | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Unable to prompt Agent '$Name' in Herdr session '$script:Session'." }
}
function Acquire-Lease {
  if (Test-Path $lockPath) {
    try { $old = Get-Content $lockPath -Raw | ConvertFrom-Json; if(([datetime]$old.lease_expires_at) -gt (Get-Date)){ return $false } } catch { }
  }
  $lease = [ordered]@{ controller_id = "$PID-$([guid]::NewGuid().ToString('N'))"; pid = $PID; lease_expires_at = (Get-Date).AddSeconds(30).ToString('o') }
  $tmp = "$lockPath.$([guid]::NewGuid().ToString('N')).tmp"; $lease | ConvertTo-Json | Set-Content $tmp -Encoding utf8; Move-Item $tmp $lockPath -Force
  $script:ControllerId = $lease.controller_id; return $true
}
function Renew-Lease { if(Test-Path $lockPath){ try { $l=Get-Content $lockPath -Raw|ConvertFrom-Json; if($l.controller_id -eq $script:ControllerId){$l.lease_expires_at=(Get-Date).AddSeconds(30).ToString('o');$l|ConvertTo-Json|Set-Content $lockPath -Encoding utf8} }catch{} } }
function Release-Lease { if(Test-Path $lockPath){try{$l=Get-Content $lockPath -Raw|ConvertFrom-Json;if($l.controller_id -eq $script:ControllerId){Remove-Item $lockPath -Force}}catch{}} }
if (-not (Acquire-Lease)) { exit 0 }
try {
  $workflow = Read-Workflow; $script:Session = [string]$workflow.session_name
  if ([string]::IsNullOrWhiteSpace($script:Session)) { throw 'workflow.json is missing session_name.' }
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  do {
    Renew-Lease; $workflow = Read-Workflow
    if (@('merged','passed','blocked') -contains [string]$workflow.state) { break }
    $taskOutcomePath=[string]$workflow.task.outcome; $verOutcomePath=[string]$workflow.verifier.outcome
    $taskOutcome=Read-Outcome $taskOutcomePath; $verOutcome=Read-Outcome $verOutcomePath
    $taskHash=OutcomeHash $taskOutcomePath; $verHash=OutcomeHash $verOutcomePath
    if ($taskOutcome -and $taskOutcome.state -eq 'blocked') {
      Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='task_agent_blocked'}; Notify "Herdr: $($workflow.task.name) 已阻塞" ([string]$workflow.task.result) 'request'; break
    } elseif ($workflow.next_role -eq 'verification' -and $taskOutcome -and $taskOutcome.state -eq 'candidate' -and $workflow.last_processed.task_outcome_hash -ne $taskHash) {
      $msg="Wake-up: read $($workflow.task.result), $taskOutcomePath and the configured mattpocock review/qa skills. Verify API docs/OpenAPI, backend routes/validation, generated client/types, and actual endpoint behavior when applicable. Write $($workflow.verifier.result), verification.md, and $verOutcomePath. Use merged only after safe merge and post-merge checks; use fix_required only for reproducible P0/P1 blockers."
      Prompt-Agent ([string]$workflow.verifier.name) $msg; $workflow.last_processed.task_outcome_hash=$taskHash; Save-State $workflow 'verifying' 'verification'; Append-Event 'verification_woken' @{agent=$workflow.verifier.name}; Notify "Herdr: $($workflow.verifier.name) 已唤醒验收" ([string]$workflow.verifier.result)
    } elseif ($workflow.next_role -eq 'task' -and $taskOutcome -and $taskOutcome.state -eq 'candidate' -and @('executing','repairing') -contains [string]$workflow.state) {
      Save-State $workflow 'candidate' 'verification'
    } elseif ($workflow.next_role -eq 'verification' -and $verOutcome -and $workflow.last_processed.verifier_outcome_hash -ne $verHash) {
      $workflow.last_processed.verifier_outcome_hash=$verHash
      if (($workflow.mode -eq 'research' -and $verOutcome.state -eq 'passed') -or ($workflow.mode -ne 'research' -and $verOutcome.state -eq 'merged')) { Save-State $workflow $verOutcome.state ''; Append-Event 'workflow_completed' @{state=$verOutcome.state}; Notify 'Herdr: 工作流已完成' ([string]$workflow.verifier.result); break }
      if ($verOutcome.state -eq 'blocked' -or $verOutcome.state -eq 'passed' -or $verOutcome.state -eq 'merged') { Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='invalid_terminal_role'}; Notify 'Herdr: 工作流被阻塞' ([string]$workflow.verifier.result) 'request'; break }
      if ($verOutcome.state -eq 'fix_required' -and ([int]$workflow.repair_round -lt [int]$workflow.max_repair_rounds)) {
        $workflow.repair_round=[int]$workflow.repair_round+1; Save-State $workflow 'repairing' 'task'; Append-Event 'fix_required' @{repair_round=$workflow.repair_round}
        $msg="Wake-up for repair round $($workflow.repair_round)/$($workflow.max_repair_rounds). Read $($workflow.verifier.result), $verOutcomePath and the existing worktree. Use mattpocock /implement (or /systematic-debugging for bugfix), fix only reproducible P0/P1 blockers, re-run affected checks, update $($workflow.task.result), and write $taskOutcomePath with state candidate. Do not merge."
        Prompt-Agent ([string]$workflow.task.name) $msg; Notify "Herdr: $($workflow.task.name) 已唤醒返工" ([string]$workflow.task.result) 'request'
      } else { Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='repair_limit_or_invalid_outcome'}; Notify 'Herdr: 验收未通过，已停止循环' ([string]$workflow.verifier.result) 'request'; break }
    }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
  } while ((Get-Date) -lt $deadline)
  if ((Get-Date) -ge $deadline -and -not (@('merged','passed','blocked') -contains [string](Read-Workflow).state)) { $workflow=Read-Workflow;Save-State $workflow 'blocked' '';Append-Event 'workflow_timeout' @{};Notify 'Herdr: 工作流超时' $workflowPath 'request' }
} finally { Release-Lease }
