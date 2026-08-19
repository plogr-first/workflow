[CmdletBinding()]
param(
  [string]$WorkflowId,
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$All,
  [string]$SessionName,
  [switch]$FromBash
)
$ErrorActionPreference = 'Stop'
if ($FromBash) { $env:HERDR_ENV='1' }
if ($env:HERDR_ENV -ne '1') { throw 'HERDR_ENV is not 1. Run herdr resume from a Herdr-managed pane.' }
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profilePath = Join-Path $project 'herdr\dispatch-profile.json'
if (-not (Test-Path $profilePath)) { throw "Herdr dispatch profile not found: $profilePath. Run 'herdr init' first." }
$profile = Get-Content $profilePath -Raw | ConvertFrom-Json
$boundSession = [string]$profile.herdr_session.name
if ($SessionName -and $SessionName -ne $boundSession) { throw "Project is bound to Herdr session '$boundSession', not '$SessionName'." }
$session = if($SessionName){$SessionName}else{$boundSession}
$workflowFiles = @(Get-ChildItem -LiteralPath (Join-Path $project 'herdr') -Recurse -Filter 'workflow.json' -File -ErrorAction SilentlyContinue)
$items = @($workflowFiles | ForEach-Object { try { Get-Content $_.FullName -Raw | ConvertFrom-Json } catch { $null } } | Where-Object { $_ -and $_.session_name -eq $session -and @('merged','passed','blocked') -notcontains [string]$_.state })
if ($WorkflowId) { $items = @($items | Where-Object { $_.workflow_id -eq $WorkflowId -or $_.slug -eq $WorkflowId }) }
if (-not $items.Count) { Write-Output "No resumable Herdr workflows for session '$session'."; exit 0 }
if ($items.Count -gt 1 -and -not $All) {
  $items | Select-Object workflow_id,slug,mode,state,next_role,repair_round,session_name | ConvertTo-Json -Depth 5; exit 2
}
function Save-Workflow($Workflow,[string]$Path) { $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"; $Workflow.updated_at=(Get-Date -Format o); $Workflow|ConvertTo-Json -Depth 20|Set-Content $tmp -Encoding utf8; Move-Item $tmp $Path -Force }
function Event([string]$Path,[string]$Name,[hashtable]$Fields=@{}) { $e=[ordered]@{at=(Get-Date -Format o);event=$Name};foreach($k in $Fields.Keys){$e[$k]=$Fields[$k]};($e|ConvertTo-Json -Compress)|Add-Content (Join-Path (Split-Path $Path) 'events.jsonl') -Encoding utf8 }
function Agent-Live([string]$Name) {
  try { $old=$ErrorActionPreference; $ErrorActionPreference='Continue'; & herdr --session $session agent get $Name 2>$null | Out-Null; $code=$LASTEXITCODE; $ErrorActionPreference=$old; return ($code -eq 0) } catch { $ErrorActionPreference=$old; return $false }
}
function Ensure-Agent($Workflow,[string]$Role,[string]$WorkflowPath) {
  $entry = if($Role -eq 'task'){$Workflow.task}else{$Workflow.verifier}; $name=[string]$entry.name
  if (Agent-Live $name) { return }
  if (-not $Workflow.recovery_attempts) { $Workflow | Add-Member -Force -NotePropertyName recovery_attempts -NotePropertyValue ([ordered]@{task=0;verification=0;max=2}) }
  $attempts = [int]$Workflow.recovery_attempts.$Role
  $maxAttempts = [int]$Workflow.recovery_attempts.max
  if ($attempts -ge $maxAttempts) {
    $Workflow.state='blocked'; $Workflow.next_role=''; $Workflow | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue "replacement $Role Agent unavailable after $attempts attempts"; Save-Workflow $Workflow $WorkflowPath; Event $WorkflowPath 'workflow_blocked' @{reason='replacement_attempt_limit';role=$Role}; throw "Replacement limit reached for $Role Agent in workflow $($Workflow.workflow_id)."
  }
  $Workflow.recovery_attempts.$Role = $attempts + 1
  $generation = 1; if($name -match '-r(\d+)$'){$generation=[int]$Matches[1]+1}
  $suffix = "-r$generation"; $base = $name
  if (($base.Length + $suffix.Length) -gt 32) { $base = $base.Substring(0, [Math]::Max(1, 32 - $suffix.Length)) }
  $newName = "$base$suffix"
  $category=[string]$Workflow.mode; $profileName=if($Role -eq 'task'){if($category -eq 'research'){'research'}else{'task'}}else{'verification'}
  $recovery = "This is a post-reboot replacement for workflow $($Workflow.workflow_id). Read the existing handoff files: $($Workflow.task.result), $($Workflow.task.outcome), $($Workflow.verifier.result), $($Workflow.verifier.outcome), and the workflow file $WorkflowPath. Read progress.md/progress.json if present. Continue only the role '$Role' using the configured mattpocock skills. Preserve the existing worktree and scope. Write the role's result and outcome files when complete."
  $launcher=Join-Path $PSScriptRoot 'Start-HerdrAgent.ps1'; $launchParams=@{Profile=$profileName;Name=$newName;Category=$category;Slug=([string]$Workflow.slug);Prompt=$recovery;ProjectRoot=$project}; if($Role -eq 'verification'){$launchParams.DeferActivation=$true}
  try { $replacement=& $launcher @launchParams | ConvertFrom-Json } catch {
    $Workflow.state='blocked'; $Workflow.next_role=''; $Workflow | Add-Member -Force -NotePropertyName blocked_reason -NotePropertyValue ("replacement $Role Agent failed: " + $_.Exception.Message); Save-Workflow $Workflow $WorkflowPath; Event $WorkflowPath 'workflow_blocked' @{reason='replacement_agent_failed';role=$Role}; throw
  }
  if(-not $replacement.name){throw "Failed to start replacement $Role Agent '$newName'."}
  $entry.name=$replacement.name; $entry.active_agent_name=$replacement.name; $entry.pane_id=$replacement.pane_id; $entry.handoff=$replacement.handoff; $entry.brief=$replacement.brief; $entry.result=$replacement.result; $entry.outcome=$replacement.outcome; $entry.progress=$replacement.progress; $entry.status=$replacement.status
  if($Role -eq 'task'){$Workflow.task=$entry}else{$Workflow.verifier=$entry}; Save-Workflow $Workflow $WorkflowPath; Event $WorkflowPath 'agent_restarted_after_reboot' @{role=$Role;agent=$replacement.name;attempt=$Workflow.recovery_attempts.$Role}
}
foreach($wf in $items) {
  $path=($workflowFiles | Where-Object { try { ((Get-Content $_.FullName -Raw | ConvertFrom-Json).workflow_id -eq $wf.workflow_id) } catch { $false } } | Select-Object -First 1).FullName
  if(-not $path){continue}
  if($wf.next_role -in @('task','verification')){ Ensure-Agent $wf ([string]$wf.next_role) $path }
  $monitor=Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
  $psHost = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
  1..3 | ForEach-Object { & $psHost -NoProfile -ExecutionPolicy Bypass -File $monitor -WorkflowPath $path -Once; Start-Sleep -Milliseconds 200 }
  $latest=Get-Content $path -Raw|ConvertFrom-Json
  if(@('merged','passed','blocked') -notcontains [string]$latest.state){ Start-Process $psHost -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`" -WorkflowPath `"$path`"" | Out-Null }
  Write-Output ([ordered]@{workflow_id=$latest.workflow_id;session=$session;state=$latest.state;next_role=$latest.next_role;workflow=$path}|ConvertTo-Json -Compress)
}
