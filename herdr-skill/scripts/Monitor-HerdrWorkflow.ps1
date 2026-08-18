[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkflowPath,
  [int]$PollSeconds = 5,
  [int]$TimeoutMinutes = 240
)
$ErrorActionPreference = 'Stop'
function Notify([string]$Title, [string]$Body, [string]$Sound = 'done') {
  & herdr notification show $Title --body $Body --sound $Sound | Out-Null
}
function Read-Outcome([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  if ((Get-Item -LiteralPath $Path).Length -eq 0) { return $null }
  try { $outcome = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
  $allowed = @('candidate','passed','fix_required','blocked','merged')
  if ($allowed -notcontains [string]$outcome.state) { return $null }
  return $outcome
}
function Save-Workflow($Workflow, [string]$State) {
  $Workflow.state = $State
  $Workflow | Add-Member -Force -NotePropertyName updated_at -NotePropertyValue (Get-Date -Format o)
  $Workflow | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $WorkflowPath -Encoding utf8
}
$workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
$task = $workflow.task
$verifier = $workflow.verifier
$taskOutcomePath = [string]$task.outcome
$taskResultPath = [string]$task.result
$verifierOutcomePath = [string]$verifier.outcome
$verifierResultPath = [string]$verifier.result
$lastTaskWrite = [datetime]::MinValue
$lastVerifierWrite = [datetime]::MinValue
$verifierActivated = $false
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ((Get-Date) -lt $deadline) {
  $taskOutcome = Read-Outcome $taskOutcomePath
  if ((-not $verifierActivated) -and $null -ne $taskOutcome) {
    if ($taskOutcome.state -eq 'blocked') {
      Save-Workflow $workflow 'blocked'
      Notify "Herdr: $($task.name) 已阻塞" $taskResultPath 'request'
      exit 1
    }
    if ($taskOutcome.state -ne 'candidate') {
      Notify "Herdr: $($task.name) 交接状态无效" "Expected candidate or blocked; inspect $taskOutcomePath" 'request'
      exit 1
    }
    $taskWrite = (Get-Item -LiteralPath $taskOutcomePath).LastWriteTimeUtc
    if ($taskWrite -gt $lastTaskWrite) {
      $lastTaskWrite = $taskWrite
      $activation = "Wake-up: you are the verification Agent. Read execution evidence at $taskResultPath and machine state at $taskOutcomePath. Independently apply the workflow gate in your brief. For API-affecting work, also verify docs/OpenAPI/generated client/backend routes and schemas align with an actual endpoint/integration check. Write $verifierResultPath and valid $verifierOutcomePath. State merged only after safe merge and post-merge verification; state fix_required only for reproducible P0/P1 blockers."
      & herdr agent prompt $verifier.name $activation | Out-Null
      $verifierActivated = $true
      Save-Workflow $workflow 'verifying'
      Notify "Herdr: $($verifier.name) 已唤醒验收" $verifierResultPath
    }
  }
  if ($verifierActivated) {
    $verifierOutcome = Read-Outcome $verifierOutcomePath
    if ($null -ne $verifierOutcome) {
      $verifierWrite = (Get-Item -LiteralPath $verifierOutcomePath).LastWriteTimeUtc
      if ($verifierWrite -gt $lastVerifierWrite) {
        $lastVerifierWrite = $verifierWrite
        if (($workflow.mode -eq 'research') -and ($verifierOutcome.state -eq 'passed')) {
          Save-Workflow $workflow 'passed'
          Notify 'Herdr: 资料研究已通过验收' $verifierResultPath
          exit 0
        }
        if (($workflow.mode -ne 'research') -and ($verifierOutcome.state -eq 'merged')) {
          Save-Workflow $workflow 'merged'
          Notify 'Herdr: 任务已验收并合并' $verifierResultPath
          exit 0
        }
        if ($verifierOutcome.state -eq 'blocked') {
          Save-Workflow $workflow 'blocked'
          Notify 'Herdr: 验收或合并被阻塞' $verifierResultPath 'request'
          exit 1
        }
        $repairAvailable = (($verifierOutcome.state -eq 'fix_required') -and (([int]$workflow.repair_round) -lt ([int]$workflow.max_repair_rounds)))
        if ($repairAvailable) {
          $workflow.repair_round = [int]$workflow.repair_round + 1
          Save-Workflow $workflow 'repairing'
          $repair = "Wake-up for the only permitted repair round. Read verification findings at $verifierResultPath and outcome at $verifierOutcomePath. Fix only reproducible P0/P1 blockers in the existing candidate worktree; preserve scope. Re-run affected checks, update $taskResultPath, write valid $taskOutcomePath with state candidate, and notify completion."
          & herdr agent prompt $task.name $repair | Out-Null
          $verifierActivated = $false
          $lastTaskWrite = (Get-Item -LiteralPath $taskOutcomePath).LastWriteTimeUtc
          Notify "Herdr: $($task.name) 已唤醒返工" $taskResultPath 'request'
        }
        if (-not $repairAvailable) {
          Save-Workflow $workflow 'blocked'
          Notify 'Herdr: 验收未通过，停止循环' $verifierResultPath 'request'
          exit 1
        }
      }
    }
  }
  Start-Sleep -Seconds $PollSeconds
}
Save-Workflow $workflow 'blocked'
Notify 'Herdr: 工作流超时' $WorkflowPath 'request'
exit 1
