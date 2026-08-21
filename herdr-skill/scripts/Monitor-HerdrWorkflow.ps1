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
  # 1. Herdr Notification
  try {
    $prefix = if($script:Session){ @('--session',$script:Session) } else { @() }
    & herdr @prefix notification show $Title --body $Body --sound $Sound 2>$null | Out-Null
  } catch { }

  # 2. Windows Native Crisp Audio Chime
  try {
    if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') {
      if ($Sound -eq 'done' -or $Sound -eq 'passed' -or $Sound -eq 'merged') {
        [Console]::Beep(1046, 100)
        Start-Sleep -Milliseconds 40
        [Console]::Beep(1318, 160)
      } elseif ($Sound -eq 'blocked' -or $Sound -eq 'request' -or $Sound -eq 'error') {
        [Console]::Beep(880, 120)
        Start-Sleep -Milliseconds 40
        [Console]::Beep(587, 200)
      }
    }
  } catch { }

  # 3. Windows Native Toast Notification
  try {
    if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') {
      $escTitle = [System.Security.SecurityElement]::Escape($Title)
      $escBody = [System.Security.SecurityElement]::Escape($Body)
      $toastXml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$escTitle</text>
      <text>$escBody</text>
    </binding>
  </visual>
</toast>
"@
      $xmlDoc = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]::new()
      $xmlDoc.LoadXml($toastXml)
      $toast = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]::new($xmlDoc)
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::CreateToastNotifier("Plogr Workflow").Show($toast)
    }
  } catch {
    try {
      Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
      $balloon = [System.Windows.Forms.NotifyIcon]::new()
      $balloon.Icon = [System.Drawing.SystemIcons]::Information
      $balloon.Visible = $true
      $balloon.ShowBalloonTip(4000, $Title, $Body, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch { }
  }
}
function Read-Outcome([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { $o = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
  if (@('candidate','passed','fix_required','blocked','merged') -notcontains [string]$o.state) { return $null }
  return $o
}
function Test-OutcomeEvidence($Workflow, [string]$Role, $Outcome) {
  $entry = if($Role -eq 'task'){$Workflow.task}else{$Workflow.verifier}
  if (-not (Test-Path -LiteralPath ([string]$entry.result) -PathType Leaf)) { return 'missing result.md' }
  $resultRaw = try { (Get-Content -LiteralPath ([string]$entry.result) -Raw) } catch { '' }
  if ([string]::IsNullOrWhiteSpace($resultRaw)) { return 'missing result.md' }
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
    if ([string]::IsNullOrWhiteSpace([string]$entry.handoff)) { return 'missing handoff directory' }
    $verification = Join-Path ([string]$entry.handoff) 'verification.md'
    if(-not (Test-Path -LiteralPath $verification -PathType Leaf)) { return 'missing verification.md' }
    $verRaw = try { (Get-Content -LiteralPath $verification -Raw) } catch { '' }
    if ([string]::IsNullOrWhiteSpace($verRaw)) { return 'missing verification.md' }
  }
  return $null
}
function Push-MergedWorkflow($Workflow) {
  $policy = [string]$Workflow.git.push_policy
  if (@('after_merge','create_pr') -notcontains $policy) { return 'not_configured' }
  $project=[string]$Workflow.project_root; $remote=[string]$Workflow.git.push_remote; $targetBranch=[string]$Workflow.git.target_branch
  if([string]::IsNullOrWhiteSpace($project) -or [string]::IsNullOrWhiteSpace($remote) -or [string]::IsNullOrWhiteSpace($targetBranch)){throw 'push policy is incomplete in workflow.json'}
  
  $hasGh = [bool](Get-Command -Name 'gh' -CommandType Application -ErrorAction SilentlyContinue)
  $remoteUrl = (& git -c core.quotepath=false -C $project remote get-url $remote 2>$null)
  $isGitHub = ($Workflow.git.github -and $Workflow.git.github.is_github) -or ($remoteUrl -match 'github\.com')

  if ($policy -eq 'create_pr') {
    if (-not $hasGh) { throw "Push policy 'create_pr' requires GitHub CLI ('gh') in PATH." }
    $title = "[$([string]$Workflow.mode)] $([string]$Workflow.slug)"
    $body = if ($Workflow.verifier -and $Workflow.verifier.result -and (Test-Path -LiteralPath ([string]$Workflow.verifier.result))) {
      Get-Content -LiteralPath ([string]$Workflow.verifier.result) -Raw
    } else { "Herdr workflow $([string]$Workflow.workflow_id) verified changes." }
    
    # Determine candidate feature branch to push
    $featureBranch = if ($Workflow.task -and $Workflow.task.outcome -and (Test-Path -LiteralPath ([string]$Workflow.task.outcome))) {
      try { (Get-Content -LiteralPath ([string]$Workflow.task.outcome) -Raw | ConvertFrom-Json).branch } catch { $null }
    } else { $null }
    if (-not $featureBranch -and $Workflow.mode -eq 'parallel_task') {
      $featureBranch = "wf/$([string]$Workflow.slug)/integration"
    }
    if (-not $featureBranch) { $featureBranch = "wf/$([string]$Workflow.slug)" }

    # Push feature branch to remote
    $pushOut = & git -c core.quotepath=false -C $project push $remote "${featureBranch}:${featureBranch}" 2>&1
    if ($LASTEXITCODE -ne 0 -and ($pushOut -notmatch 'Everything up-to-date')) {
      & git -c core.quotepath=false -C $project push $remote $targetBranch 2>&1 | Out-Null
    }

    $prOutput = & gh pr create --repo $remoteUrl --head $featureBranch --base $targetBranch --title $title --body $body 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh pr create failed: $($prOutput -join ' ')" }
    return 'pr_created'
  }

  if ($isGitHub -and $hasGh) {
    & gh auth status 2>$null
  }
  $output=& git -c core.quotepath=false -C $project push $remote $targetBranch 2>&1
  if($LASTEXITCODE -ne 0){throw "git push $remote $targetBranch failed: $($output -join ' ')"}
  return 'pushed'
}
function OutcomeHash([string]$Path) { if(Test-Path -LiteralPath $Path){ return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }; return $null }
function Prompt-Agent([string]$Name, [string]$Message, $Entry = $null) {
  $prefix = if($script:Session){ @('--session',$script:Session) } else { @() }
  $pane = if ($Entry) { [string]$Entry.pane_id } else { $null }
  $statusObj = if ($Entry -and $Entry.status -and (Test-Path -LiteralPath ([string]$Entry.status))) {
    try { Get-Content -LiteralPath ([string]$Entry.status) -Raw | ConvertFrom-Json } catch { $null }
  } else { $null }
  $kind = if ($statusObj -and $statusObj.kind) { [string]$statusObj.kind } else { 'opencode' }
  try {
    if ($kind -eq 'opencode' -and $pane) {
      & herdr @prefix pane send-text $pane $Message 2>$null | Out-Null
      & herdr @prefix pane send-keys $pane 'enter' 2>$null | Out-Null
    } else {
      $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
      & herdr @prefix agent prompt $Name $Message 2>$null | Out-Null
      $code=$LASTEXITCODE; $ErrorActionPreference=$old
      if ($code -ne 0 -and $pane) {
        & herdr @prefix pane send-text $pane $Message 2>$null | Out-Null
        & herdr @prefix pane send-keys $pane 'enter' 2>$null | Out-Null
      }
    }
  } catch { }
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
  if (Test-Path -LiteralPath $lockPath) {
    try {
      $old = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
      $proc = Get-Process -Id $old.pid -ErrorAction SilentlyContinue
      if ($proc -and ([datetime]$old.lease_expires_at) -gt (Get-Date)) { return $false }
      Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    } catch {
      Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
  }
  $lease = [ordered]@{ controller_id = "$PID-$([guid]::NewGuid().ToString('N'))"; pid = $PID; lease_expires_at = (Get-Date).AddSeconds(30).ToString('o') }
  $leaseJson = ($lease | ConvertTo-Json)
  try {
    $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $writer = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
    $writer.Write($leaseJson)
    $writer.Flush()
    $writer.Dispose()
    $fs.Dispose()
    $script:ControllerId = $lease.controller_id
    return $true
  } catch {
    return $false
  }
}
function Renew-Lease { if(Test-Path -LiteralPath $lockPath){ try { $l=Get-Content -LiteralPath $lockPath -Raw|ConvertFrom-Json; if($l.controller_id -eq $script:ControllerId){$l.lease_expires_at=(Get-Date).AddSeconds(30).ToString('o');$l|ConvertTo-Json|Set-Content -LiteralPath $lockPath -Encoding utf8} }catch{} } }
function Release-Lease { if(Test-Path -LiteralPath $lockPath){try{$l=Get-Content -LiteralPath $lockPath -Raw|ConvertFrom-Json;if($l.controller_id -eq $script:ControllerId){Remove-Item -LiteralPath $lockPath -Force}}catch{}} }
if (-not (Acquire-Lease)) { exit 0 }
try {
  $workflow = Read-Workflow; $script:Session = [string]$workflow.session_name
  if ([string]::IsNullOrWhiteSpace($script:Session)) { throw 'workflow.json is missing session_name.' }
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  $missingTaskTicks=0; $missingVerifierTicks=0
  do {
    Renew-Lease; $workflow = Read-Workflow
    if (-not $workflow.last_processed) {
      $workflow | Add-Member -Force -NotePropertyName last_processed -NotePropertyValue ([ordered]@{ task_outcome_hash = $null; verifier_outcome_hash = $null })
    }
    if (@('merged','passed','blocked') -contains [string]$workflow.state) { break }

    # 1. Matrix Parallel Task Handling
    if ($workflow.mode -eq 'parallel_task' -and $workflow.next_role -eq 'matrix_tasks') {
      $matrix = $workflow.matrix
      $allCandidate = $true
      $anyBlocked = $false
      $matrixUpdated = $false

      foreach ($sub in $matrix) {
        $subOutcomePath = [string]$sub.outcome
        $subOutcome = Read-Outcome $subOutcomePath
        if ($subOutcome) {
          if ($subOutcome.state -eq 'blocked') {
            $anyBlocked = $true
            $sub.status = 'blocked'
          } elseif ($subOutcome.state -eq 'candidate' -and $sub.status -ne 'candidate') {
            $sub.status = 'candidate'
            $matrixUpdated = $true
            Append-Event 'matrix_subtask_completed' @{ subtask_id = $sub.id; branch = $sub.branch }
          }
        }
        if ($sub.status -ne 'candidate') {
          $allCandidate = $false
        }
      }

      if ($matrixUpdated) {
        $workflow.matrix = $matrix
        Write-AtomicJson $workflow $workflowPath
      }

      if ($anyBlocked) {
        Save-State $workflow 'blocked' ''
        Append-Event 'workflow_blocked' @{ reason = 'matrix_subtask_blocked' }
        Notify "Herdr: 并行子任务阻塞" $workflowPath 'request'
        break
      }

      if ($allCandidate) {
        # All subagents finished candidates -> Mount Integration Worktree
        $integrationBranch = "wf/$($workflow.slug)/integration"
        $integrationWt = Join-Path $workflow.project_root ".worktrees\wf-$($workflow.slug)-integration"
        $gitProj = [string]$workflow.project_root

        try {
          if (Test-Path -LiteralPath $integrationWt) {
            & git -c core.quotepath=false -C $gitProj worktree remove --force $integrationWt 2>$null | Out-Null
          }
          & git -c core.quotepath=false -C $gitProj branch -D $integrationBranch 2>$null | Out-Null
          & git -c core.quotepath=false -C $gitProj worktree add -b $integrationBranch $integrationWt HEAD 2>&1 | Out-Null

          # Merge each candidate branch
          $mergeFailed = $false
          foreach ($sub in $matrix) {
            $subBranch = [string]$sub.branch
            $mergeOut = & git -c core.quotepath=false -C $integrationWt merge --no-ff $subBranch -m "Integrate subtask $($sub.id)" 2>&1
            if ($LASTEXITCODE -ne 0) {
              $mergeFailed = $true
              Save-State $workflow 'blocked' ''
              Append-Event 'matrix_merge_conflict' @{ subtask_id = $sub.id; error = ($mergeOut -join ' ') }
              Notify "Herdr: 并行分支集成冲突 ($($sub.id))" $integrationWt 'blocked'
              break
            }
          }

          if (-not $mergeFailed) {
            $workflow.next_role = 'verification'
            Save-State $workflow 'candidate' 'verification'
            Append-Event 'matrix_integration_ready' @{ integration_worktree = $integrationWt; branch = $integrationBranch }

            # Wake up Verifier
            $verResultPath = [string]$workflow.verifier.result
            $verOutcomePath = [string]$workflow.verifier.outcome
            $verHandoff = [string]$workflow.verifier.handoff
            if (-not (Test-Path -LiteralPath $verHandoff)) { New-Item -ItemType Directory -Force -Path $verHandoff | Out-Null }

            $msg = "Wake-up: Matrix Parallel subtasks all completed and integrated in $integrationWt (branch: $integrationBranch). Read each subtask result, run unified 5-gate acceptance, update $verResultPath, verification.md, and $verOutcomePath. Report merged only after safe verification and integration."
            Prompt-Agent ([string]$workflow.verifier.name) $msg $workflow.verifier
            Save-State $workflow 'verifying' 'verification'
            Append-Event 'verification_woken' @{ agent = $workflow.verifier.name }
            Notify "Herdr: $($workflow.verifier.name) 已唤醒进行矩阵多分支集成验收" $verResultPath
          }
        } catch {
          Save-State $workflow 'blocked' ''
          Append-Event 'workflow_blocked' @{ reason = 'matrix_integration_failed'; error = $_.Exception.Message }
          Notify "Herdr: 并行集成异常" $workflowPath 'blocked'
          break
        }
      }
    }

    # 2. Standard Single Task Handling
    $taskOutcomePath = if ($workflow.task) { [string]$workflow.task.outcome } else { $null }
    $verOutcomePath = if ($workflow.verifier) { [string]$workflow.verifier.outcome } else { $null }
    $taskOutcome = if ($taskOutcomePath) { Read-Outcome $taskOutcomePath } else { $null }
    $verOutcome = if ($verOutcomePath) { Read-Outcome $verOutcomePath } else { $null }
    $taskHash = if ($taskOutcomePath) { OutcomeHash $taskOutcomePath } else { $null }
    $verHash = if ($verOutcomePath) { OutcomeHash $verOutcomePath } else { $null }

    if ($workflow.next_role -eq 'task' -and $workflow.task -and -not (Agent-Live ([string]$workflow.task.name))) { $missingTaskTicks++ } else { $missingTaskTicks=0 }
    if ($workflow.next_role -eq 'verification' -and $workflow.verifier -and -not (Agent-Live ([string]$workflow.verifier.name))) { $missingVerifierTicks++ } else { $missingVerifierTicks=0 }
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
    } elseif ($workflow.next_role -eq 'verification' -and $taskOutcome -and ($taskOutcome.state -eq 'candidate' -or ($workflow.mode -eq 'research' -and $taskOutcome.state -eq 'passed')) -and $workflow.last_processed.task_outcome_hash -ne $taskHash) {
      $msg="Wake-up: read $($workflow.task.result), $taskOutcomePath and the configured official mattpocock /code-review skill, fixed at the candidate base SHA. Verify API docs/OpenAPI, backend routes/validation, generated client/types, and actual endpoint behavior when applicable. Write $($workflow.verifier.result), verification.md, and $verOutcomePath. Use merged only after safe merge and post-merge checks; use fix_required only for reproducible P0/P1 blockers."
      Prompt-Agent ([string]$workflow.verifier.name) $msg $workflow.verifier; $workflow.last_processed.task_outcome_hash=$taskHash; Save-State $workflow 'verifying' 'verification'; Append-Event 'verification_woken' @{agent=$workflow.verifier.name}; Notify "Herdr: $($workflow.verifier.name) 已唤醒验收" ([string]$workflow.verifier.result)
    } elseif ($workflow.next_role -eq 'task' -and $taskOutcome -and ($taskOutcome.state -eq 'candidate' -or ($workflow.mode -eq 'research' -and $taskOutcome.state -eq 'passed')) -and @('executing','repairing') -contains [string]$workflow.state) {
      Save-State $workflow 'candidate' 'verification'
    }
    # Stream OSC terminal title to Herdr tab
    try {
      $esc = [char]27
      $bel = [char]7
      $oscTitle = "${esc}]0;🚀 [Plogr: $($workflow.state) | $($workflow.mode)/$($workflow.slug)]${bel}"
      [Console]::Write($oscTitle)
    } catch {}

    if ($workflow.next_role -eq 'verification' -and $verOutcome -and (Test-OutcomeEvidence $workflow 'verification' $verOutcome)) {
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
        # Auto-prune merged isolated worktrees
        try {
          if ($workflow.task -and $workflow.task.outcome -and (Test-Path -LiteralPath ([string]$workflow.task.outcome))) {
            $taskOutObj = Get-Content -LiteralPath ([string]$workflow.task.outcome) -Raw | ConvertFrom-Json
            if ($taskOutObj.worktree_decision -eq 'isolated' -and $taskOutObj.worktree_path) {
              $wtPath = [string]$taskOutObj.worktree_path
              if (Test-Path -LiteralPath $wtPath) {
                & git -c core.quotepath=false -C $workflow.project_root worktree remove --force $wtPath 2>$null | Out-Null
                & git -c core.quotepath=false -C $workflow.project_root worktree prune 2>$null | Out-Null
                if (Test-Path -LiteralPath $wtPath) {
                  Remove-Item -LiteralPath $wtPath -Recurse -Force -ErrorAction SilentlyContinue
                }
              }
            }
          }
          if ($workflow.mode -eq 'parallel_task' -and $workflow.matrix) {
            foreach ($sub in $workflow.matrix) {
              $sWt = [string]$sub.worktree_path
              if ($sWt -and (Test-Path -LiteralPath $sWt)) {
                & git -c core.quotepath=false -C $workflow.project_root worktree remove --force $sWt 2>$null | Out-Null
                Remove-Item -LiteralPath $sWt -Recurse -Force -ErrorAction SilentlyContinue
              }
            }
            $intWt = Join-Path $workflow.project_root ".worktrees\wf-$($workflow.slug)-integration"
            if (Test-Path -LiteralPath $intWt) {
              & git -c core.quotepath=false -C $workflow.project_root worktree remove --force $intWt 2>$null | Out-Null
              Remove-Item -LiteralPath $intWt -Recurse -Force -ErrorAction SilentlyContinue
            }
            & git -c core.quotepath=false -C $workflow.project_root worktree prune 2>$null | Out-Null
          }
        } catch {}
        Notify 'Herdr: 工作流已完成' ([string]$workflow.verifier.result) 'done'; break
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

