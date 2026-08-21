[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkflowPath,
  [int]$PollSeconds = 5,
  [int]$TimeoutMinutes = 240,
  [switch]$Once
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
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
  $Workflow.state = $State; $Workflow.next_role = $NextRole
  $Workflow | Add-Member -Force -NotePropertyName updated_at -NotePropertyValue (Get-Date -Format o)
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
function Test-OutcomeEvidence($Workflow, [string]$Role, $Outcome) {
  $entry = if($Role -eq 'task'){$Workflow.task}else{$Workflow.verifier}
  if (-not (Test-Path -LiteralPath ([string]$entry.result) -PathType Leaf) -or (Get-Item -LiteralPath ([string]$entry.result)).Length -eq 0) { return 'missing result.md' }
  if ($Role -eq 'task' -and $Outcome.state -eq 'candidate' -and $Workflow.mode -ne 'research') {
    foreach($field in @('worktree_decision','worktree_path','branch','base_sha','candidate_sha')) { if([string]::IsNullOrWhiteSpace([string]$Outcome.$field)){return "candidate missing $field"} }
    if(@('isolated','in_place') -notcontains [string]$Outcome.worktree_decision){return 'invalid worktree_decision'}
    $worktree=[string]$Outcome.worktree_path; $project=[string]$Workflow.project_root
    if(-not (Test-Path -LiteralPath $worktree -PathType Container)){return 'candidate worktree_path does not exist'}
    $normWorktree = try { [System.IO.Path]::GetFullPath($worktree).TrimEnd('\').TrimEnd('/') } catch { ($worktree -replace '/', '\').TrimEnd('\') }
    $normProject = if($project){ try { [System.IO.Path]::GetFullPath($project).TrimEnd('\').TrimEnd('/') } catch { ($project -replace '/', '\').TrimEnd('\') } } else { $null }
    if($Outcome.worktree_decision -eq 'in_place' -and $normProject -and -not $normWorktree.Equals($normProject, [System.StringComparison]::OrdinalIgnoreCase)){return 'in_place worktree_path is not project_root'}
    if($Outcome.worktree_decision -eq 'isolated'){
      if($normProject -and $normWorktree.Equals($normProject, [System.StringComparison]::OrdinalIgnoreCase)){return 'isolated worktree_path cannot be project_root'}
      $isInside = (& git -c core.quotepath=false -C $normWorktree rev-parse --is-inside-work-tree 2>$null)
      if ($LASTEXITCODE -ne 0 -or [string]$isInside -ne 'true') { return 'isolated worktree_path is not a registered git worktree' }
    }
    & git -c core.quotepath=false -C $normWorktree cat-file -e "$($Outcome.candidate_sha)^{commit}" 2>$null; if($LASTEXITCODE -ne 0){return 'candidate_sha is not a commit in worktree'}
    & git -c core.quotepath=false -C $normWorktree merge-base --is-ancestor $Outcome.base_sha $Outcome.candidate_sha 2>$null; if($LASTEXITCODE -ne 0){return 'base_sha is not an ancestor of candidate_sha'}
  }
  if ($Role -eq 'verification' -and @('passed','merged','fix_required') -contains [string]$Outcome.state) {
    $verification = Join-Path ([string]$entry.handoff) 'verification.md'
    if(-not (Test-Path -LiteralPath $verification -PathType Leaf) -or (Get-Item -LiteralPath $verification).Length -eq 0){return 'missing verification.md'}
  }
  return $null
}
function Push-MergedWorkflow($Workflow) {
  $policy = [string]$Workflow.git.push_policy
  if (@('after_merge','create_pr') -notcontains $policy) { return 'not_configured' }
  $project=[string]$Workflow.project_root; $remote=[string]$Workflow.git.push_remote; $branch=[string]$Workflow.git.target_branch
  if([string]::IsNullOrWhiteSpace($project) -or [string]::IsNullOrWhiteSpace($remote) -or [string]::IsNullOrWhiteSpace($branch)){throw 'push policy is incomplete in workflow.json'}
  
  $hasGh = [bool](Get-Command -Name 'gh' -CommandType Application -ErrorAction SilentlyContinue)
  $remoteUrl = (& git -c core.quotepath=false -C $project remote get-url $remote 2>$null)
  $isGitHub = ($Workflow.git.github -and $Workflow.git.github.is_github) -or ($remoteUrl -match 'github\.com')

  if ($policy -eq 'create_pr') {
    if (-not $hasGh) { throw "Push policy 'create_pr' requires GitHub CLI ('gh') in PATH." }
    $title = "[$([string]$Workflow.mode)] $([string]$Workflow.slug)"
    $body = if ($Workflow.verifier -and $Workflow.verifier.result -and (Test-Path -LiteralPath ([string]$Workflow.verifier.result))) {
      Get-Content -LiteralPath ([string]$Workflow.verifier.result) -Raw
    } else { "Herdr workflow $([string]$Workflow.workflow_id) verified changes." }
    
    # Push branch first if not pushed
    & git -c core.quotepath=false -C $project push $remote $branch 2>&1 | Out-Null
    $prOutput = & gh pr create --repo $remoteUrl --base $branch --title $title --body $body 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh pr create failed: $($prOutput -join ' ')" }
    return 'pr_created'
  }

  if ($isGitHub -and $hasGh) {
    & gh auth status 2>$null
  }
  $output=& git -c core.quotepath=false -C $project push $remote $branch 2>&1
  if($LASTEXITCODE -ne 0){throw "git push $remote $branch failed: $($output -join ' ')"}
  return 'pushed'
}
function OutcomeHash([string]$Path) { if(Test-Path $Path){ return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }; return $null }
function Prompt-Agent([string]$Name, [string]$Message, $Entry = $null) {
  $prefix = if($script:Session){ @('--session',$script:Session) } else { @() }
  $pane = if ($Entry) { [string]$Entry.pane_id } else { $null }
  $statusObj = if ($Entry -and $Entry.status -and (Test-Path -LiteralPath ([string]$Entry.status))) {
    try { Get-Content -LiteralPath ([string]$Entry.status) -Raw | ConvertFrom-Json } catch { $null }
  } else { $null }
  $kind = if ($statusObj -and $statusObj.kind) { [string]$statusObj.kind } else { 'opencode' }
  if ($kind -eq 'opencode' -and $pane) {
    & herdr @prefix pane send-text $pane $Message | Out-Null
    & herdr @prefix pane send-keys $pane 'enter' | Out-Null
  } else {
    $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
    & herdr @prefix agent prompt $Name $Message 2>$null | Out-Null
    $code=$LASTEXITCODE; $ErrorActionPreference=$old
    if ($code -ne 0 -and $pane) {
      & herdr @prefix pane send-text $pane $Message | Out-Null
      & herdr @prefix pane send-keys $pane 'enter' | Out-Null
    } elseif ($code -ne 0) {
      throw "Unable to prompt Agent '$Name' in Herdr session '$script:Session'."
    }
  }
}
function Agent-Live([string]$Name) {
  try {
    $prefix = if($script:Session){ @('--session',$script:Session) } else { @() }
    $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
    & herdr @prefix agent get $Name 2>$null | Out-Null
    $code=$LASTEXITCODE; $ErrorActionPreference=$old
    return ($code -eq 0)
  } catch {
    $ErrorActionPreference=$old; return $false
  }
}
function Acquire-Lease {
  if (Test-Path $lockPath) {
    try {
      $old = Get-Content $lockPath -Raw | ConvertFrom-Json
      $proc = Get-Process -Id $old.pid -ErrorAction SilentlyContinue
      if ($proc -and ([datetime]$old.lease_expires_at) -gt (Get-Date)) { return $false }
    } catch { }
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
  $missingTaskTicks=0; $missingVerifierTicks=0
  do {
    Renew-Lease; $workflow = Read-Workflow
    if (@('merged','passed','blocked') -contains [string]$workflow.state) { break }
    $taskOutcomePath=[string]$workflow.task.outcome; $verOutcomePath=[string]$workflow.verifier.outcome
    $taskOutcome=Read-Outcome $taskOutcomePath; $verOutcome=Read-Outcome $verOutcomePath
    $taskHash=OutcomeHash $taskOutcomePath; $verHash=OutcomeHash $verOutcomePath
    if ($workflow.next_role -eq 'task' -and -not (Agent-Live ([string]$workflow.task.name))) { $missingTaskTicks++ } else { $missingTaskTicks=0 }
    if ($workflow.next_role -eq 'verification' -and -not (Agent-Live ([string]$workflow.verifier.name))) { $missingVerifierTicks++ } else { $missingVerifierTicks=0 }
    if ($missingTaskTicks -ge 10 -or $missingVerifierTicks -ge 10) {
      $missingRole=if($missingTaskTicks -ge 10){'task'}else{'verification'}; Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='agent_unavailable';role=$missingRole}; Notify "Herdr: $missingRole Agent 不可用，工作流已阻塞" $workflowPath 'request'; break
    }
    if ($taskOutcome -and $taskOutcome.state -eq 'blocked') {
      Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='task_agent_blocked'}; Notify "Herdr: $($workflow.task.name) 已阻塞" ([string]$workflow.task.result) 'request'; break
    } elseif ($taskOutcome -and $taskOutcome.state -eq 'candidate' -and (Test-OutcomeEvidence $workflow 'task' $taskOutcome)) {
      $evidenceError = Test-OutcomeEvidence $workflow 'task' $taskOutcome
      if ($evidenceError) {
        Start-Sleep -Milliseconds 750
        $evidenceError = Test-OutcomeEvidence $workflow 'task' $taskOutcome
      }
      if ($evidenceError) {
        Save-State $workflow 'blocked' ''
        Append-Event 'workflow_blocked' @{reason='invalid_task_handoff';detail=$evidenceError}
        Notify 'Herdr: 任务候选证据无效，工作流已阻塞' ([string]$workflow.task.result) 'blocked'
        break
      }
    } elseif ($workflow.next_role -eq 'verification' -and $taskOutcome -and $taskOutcome.state -eq 'candidate' -and $workflow.last_processed.task_outcome_hash -ne $taskHash) {
      $msg="Wake-up: read $($workflow.task.result), $taskOutcomePath and the configured official mattpocock /code-review skill, fixed at the candidate base SHA. Verify API docs/OpenAPI, backend routes/validation, generated client/types, and actual endpoint behavior when applicable. Write $($workflow.verifier.result), verification.md, and $verOutcomePath. Use merged only after safe merge and post-merge checks; use fix_required only for reproducible P0/P1 blockers."
      Prompt-Agent ([string]$workflow.verifier.name) $msg $workflow.verifier; $workflow.last_processed.task_outcome_hash=$taskHash; Save-State $workflow 'verifying' 'verification'; Append-Event 'verification_woken' @{agent=$workflow.verifier.name}; Notify "Herdr: $($workflow.verifier.name) 已唤醒验收" ([string]$workflow.verifier.result)
    } elseif ($workflow.next_role -eq 'task' -and $taskOutcome -and $taskOutcome.state -eq 'candidate' -and @('executing','repairing') -contains [string]$workflow.state) {
      Save-State $workflow 'candidate' 'verification'
    # Stream OSC terminal title to Herdr tab
    try {
      $oscTitle = "`e]0;🚀 [Plogr: $($workflow.state) | $($workflow.mode)/$($workflow.slug)]`a"
      [Console]::Write($oscTitle)
    } catch {}

    if ($verOutcome -and (Test-OutcomeEvidence $workflow 'verification' $verOutcome)) {
      $reason=Test-OutcomeEvidence $workflow 'verification' $verOutcome; Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='invalid_verification_handoff';detail=$reason}; Notify "Herdr: 验收交接不完整：$reason" ([string]$workflow.verifier.result) 'request'; break
    } elseif ($workflow.next_role -eq 'verification' -and $verOutcome -and $workflow.last_processed.verifier_outcome_hash -ne $verHash) {
      $workflow.last_processed.verifier_outcome_hash=$verHash
      if (($workflow.mode -eq 'research' -and $verOutcome.state -eq 'passed') -or ($workflow.mode -ne 'research' -and $verOutcome.state -eq 'merged')) {
        if($workflow.mode -ne 'research'){ try {$push=Push-MergedWorkflow $workflow; $workflow|Add-Member -Force -NotePropertyName push_status -NotePropertyValue $push} catch {$workflow|Add-Member -Force -NotePropertyName push_status -NotePropertyValue 'failed';$workflow|Add-Member -Force -NotePropertyName push_error -NotePropertyValue $_.Exception.Message;Save-State $workflow 'merged' '';Append-Event 'push_failed' @{error=$_.Exception.Message};Notify 'Herdr: 已合并，但 git push 失败' ([string]$workflow.verifier.result) 'request';break} }
        Save-State $workflow $verOutcome.state ''; Append-Event 'workflow_completed' @{state=$verOutcome.state;push_status=$workflow.push_status}
        # Trigger Pitfalls Knowledge Auto-Harvesting
        try {
          $pitfallsScript = Join-Path $PSScriptRoot 'Update-PitfallsKnowledge.ps1'
          if (Test-Path -LiteralPath $pitfallsScript) {
            & $pitfallsScript -WorkflowPath $workflowPath -ProjectRoot $workflow.project_root | Out-Null
          }
        } catch {}
        Notify 'Herdr: 工作流已完成' ([string]$workflow.verifier.result); break
      }
      if ($verOutcome.state -eq 'blocked' -or $verOutcome.state -eq 'passed' -or $verOutcome.state -eq 'merged') { Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='invalid_terminal_role'}; Notify 'Herdr: 工作流被阻塞' ([string]$workflow.verifier.result) 'request'; break }
      if ($verOutcome.state -eq 'fix_required' -and ([int]$workflow.repair_round -lt [int]$workflow.max_repair_rounds)) {
        $workflow.repair_round=[int]$workflow.repair_round+1; Save-State $workflow 'repairing' 'task'; Append-Event 'fix_required' @{repair_round=$workflow.repair_round}
        $msg="Wake-up for repair round $($workflow.repair_round)/$($workflow.max_repair_rounds). Read $($workflow.verifier.result), $verOutcomePath and the existing worktree. Use mattpocock /diagnosing-bugs then /implement for bugfix, or /implement for task; use /tdd at a confirmed seam, fix only reproducible P0/P1 blockers, re-run affected checks, update $($workflow.task.result), and write $taskOutcomePath with state candidate. Do not merge."
        Prompt-Agent ([string]$workflow.task.name) $msg $workflow.task; Notify "Herdr: $($workflow.task.name) 已唤醒返工" ([string]$workflow.task.result) 'request'
      } else { Save-State $workflow 'blocked' ''; Append-Event 'workflow_blocked' @{reason='repair_limit_or_invalid_outcome'}; Notify 'Herdr: 验收未通过，已停止循环' ([string]$workflow.verifier.result) 'request'; break }
    }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
  } while ((Get-Date) -lt $deadline)
  if ((Get-Date) -ge $deadline -and -not (@('merged','passed','blocked') -contains [string](Read-Workflow).state)) { $workflow=Read-Workflow;Save-State $workflow 'blocked' '';Append-Event 'workflow_timeout' @{};Notify 'Herdr: 工作流超时' $workflowPath 'request' }
} catch {
  try { $failed=Read-Workflow; $failed | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue $_.Exception.Message; Save-State $failed 'blocked' ''; Append-Event 'workflow_blocked' @{reason='controller_error'}; Notify 'Herdr: 工作流控制器异常，已阻塞' $workflowPath 'request' } catch { }
  throw
} finally { Release-Lease }
