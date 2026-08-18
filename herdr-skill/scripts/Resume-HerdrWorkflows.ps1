[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$WorkflowId,
  [switch]$All,
  [string]$SessionName
)
$ErrorActionPreference = 'Stop'
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
function Agent-Live([string]$Name) { & herdr --session $session agent get $Name 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) }
function Ensure-Agent($Workflow,[string]$Role,[string]$WorkflowPath) {
  $entry = if($Role -eq 'task'){$Workflow.task}else{$Workflow.verifier}; $name=[string]$entry.name
  if (Agent-Live $name) { return }
  $generation = 1; if($name -match '-r(\d+)$'){$generation=[int]$Matches[1]+1}
  $newName = "$name-r$generation"; if($newName.Length -gt 32){$newName=$newName.Substring(0,32)}
  $category=[string]$Workflow.mode; $profileName=if($Role -eq 'task'){if($category -eq 'research'){'research'}else{'task'}}else{'verification'}
  $recovery = "This is a post-reboot replacement for workflow $($Workflow.workflow_id). Read the existing handoff files: $($Workflow.task.result), $($Workflow.task.outcome), $($Workflow.verifier.result), $($Workflow.verifier.outcome), and the workflow file $WorkflowPath. Read progress.md/progress.json if present. Continue only the role '$Role' using the configured mattpocock skills. Preserve the existing worktree and scope. Write the role's result and outcome files when complete."
  $launcher=Join-Path $PSScriptRoot 'Start-HerdrAgent.ps1'; $args=@('-Profile',$profileName,'-Name',$newName,'-Category',$category,'-Slug',([string]$Workflow.slug),'-Prompt',$recovery,'-ProjectRoot',$project); if($Role -eq 'verification'){$args += '-DeferActivation'}
  $replacement=& $launcher @args | ConvertFrom-Json
  if(-not $replacement.name){throw "Failed to start replacement $Role Agent '$newName'."}
  $entry.name=$replacement.name; $entry.active_agent_name=$replacement.name; $entry.handoff=$replacement.handoff; $entry.result=$replacement.result; $entry.outcome=$replacement.outcome; $entry.status=$replacement.status
  if($Role -eq 'task'){$Workflow.task=$entry}else{$Workflow.verifier=$entry}; Save-Workflow $Workflow $WorkflowPath; Event $WorkflowPath 'agent_restarted_after_reboot' @{role=$Role;agent=$replacement.name}
}
foreach($wf in $items) {
  $path=($workflowFiles | Where-Object { try { ((Get-Content $_.FullName -Raw | ConvertFrom-Json).workflow_id -eq $wf.workflow_id) } catch { $false } } | Select-Object -First 1).FullName
  if(-not $path){continue}
  if($wf.next_role -in @('task','verification')){ Ensure-Agent $wf ([string]$wf.next_role) $path }
  $monitor=Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
  1..3 | ForEach-Object { & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -WorkflowPath $path -Once; Start-Sleep -Milliseconds 200 }
  $latest=Get-Content $path -Raw|ConvertFrom-Json
  if(@('merged','passed','blocked') -notcontains [string]$latest.state){ Start-Process pwsh.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$monitor`" -WorkflowPath `"$path`"" | Out-Null }
  Write-Output ([ordered]@{workflow_id=$latest.workflow_id;session=$session;state=$latest.state;next_role=$latest.next_role;workflow=$path}|ConvertTo-Json -Compress)
}
