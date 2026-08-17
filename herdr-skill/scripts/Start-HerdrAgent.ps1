[CmdletBinding()]
param(
  [string]$Kind,
  [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_-]{0,31}$')][string]$Name,
  [Parameter(Mandatory)][ValidateSet('research','task','bugfix')][string]$Category,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$Slug,
  [Parameter(Mandatory)][string]$Prompt,
  [ValidateSet('full','plan')][string]$Access = 'full',
  [string]$OpenCodeModel,
  [ValidateSet('task','verification')][string]$Profile,
  [string]$ProjectRoot = (Get-Location).Path,
  [ValidateSet('right','down')][string]$Direction = 'right'
)
$ErrorActionPreference = 'Stop'
function Resolve-OpenCodeModel([string]$Requested) {
  $models = @((& opencode models 2>$null) -replace "`e\[[0-9;]*m", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if (-not $models.Count) { throw "Unable to obtain models from 'opencode models'." }
  $aliases = @{ 'zen'='opencode/deepseek-v4-flash-free'; 'zen-free'='opencode/deepseek-v4-flash-free'; 'deepseek-v4-flash-free'='opencode/deepseek-v4-flash-free'; 'go'='opencode-go/deepseek-v4-flash'; 'go-flash'='opencode-go/deepseek-v4-flash'; 'deepseek-v4-flash'='opencode-go/deepseek-v4-flash' }
  $key = $Requested.Trim().ToLowerInvariant(); if ($aliases.ContainsKey($key)) { $key = $aliases[$key] }
  $match = @($models | Where-Object { $_.Equals($key,[System.StringComparison]::OrdinalIgnoreCase) })
  if ($match.Count -eq 1) { return $match[0] }
  $normal = $key -replace '[^a-z0-9]',''; $match = @($models | Where-Object { (($_ -replace '[^a-z0-9]','').ToLowerInvariant()).Contains($normal) })
  if ($match.Count -eq 1) { return $match[0] }
  if ($match.Count -gt 1) { throw "Ambiguous OpenCode model '$Requested'. Candidates: $($match -join ', ')" }
  throw "OpenCode model '$Requested' was not found."
}
function Invoke-HerdrJson([string[]]$Arguments) {
  $raw = & herdr @Arguments 2>&1
  $text = $raw -join "`n"
  try { return @{ exit=$LASTEXITCODE; json=($text | ConvertFrom-Json); text=$text } }
  catch { throw "Herdr returned non-JSON output: $text" }
}
function Start-AgentWhenPaneReady([string]$Pane,[string[]]$NativeArgs) {
  $deadline = (Get-Date).AddSeconds(20)
  do {
    $command = @('agent','start',$Name,'--kind',$Kind,'--pane',$Pane,'--timeout','60000')
    if ($NativeArgs.Count) { $command += '--'; $command += $NativeArgs }
    $attempt = Invoke-HerdrJson $command
    if ($attempt.exit -eq 0 -and $attempt.json.result.agent.interactive_ready -and $attempt.json.result.agent.agent -eq $Kind) { return $attempt.json.result.agent }
    if ([string]$attempt.json.error.code -eq 'agent_pane_busy') { Start-Sleep -Milliseconds 750; continue }
    throw "Herdr agent start failed: $($attempt.text)"
  } while ((Get-Date) -lt $deadline)
  throw "New pane $Pane did not become an available shell within 20 seconds."
}if ($env:HERDR_ENV -ne '1') { throw 'HERDR_ENV is not 1. Run this from a Herdr-managed pane.' }
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profileNativeArgs = @()
if ($Profile) {
  if ($Kind) { throw 'Use either -Kind or -Profile, not both.' }
  $profilePath = Join-Path $project 'herdr\dispatch-profile.json'
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Herdr dispatch profile not found: $profilePath. Run 'herdr init' from the project root first." }
  try { $dispatchProfile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json } catch { throw "Invalid Herdr dispatch profile: $profilePath" }
  $entry = if ($Profile -eq 'task') { $dispatchProfile.task_agent } else { $dispatchProfile.verification_agent }
  if (-not $entry -or -not $entry.kind) { throw "Profile '$Profile' is incomplete in $profilePath." }
  $Kind = [string]$entry.kind
  if ($entry.model) { $OpenCodeModel = [string]$entry.model }
  $profileNativeArgs = @($entry.full_access_args | ForEach-Object { [string]$_ } | Where-Object { $_ })
}
if (-not $Kind) { throw 'Specify -Kind or -Profile task|verification.' }
$Kind = $Kind.Trim().ToLowerInvariant()
if ($Kind -notmatch '^[a-z][a-z0-9_-]{0,31}$') { throw "Invalid Herdr agent kind '$Kind'." }
if ($Kind -ne 'opencode' -and $OpenCodeModel) { throw '-OpenCodeModel is valid only for an opencode profile or -Kind opencode.' }
$nativeArgs = @()
if ($Access -eq 'full' -and $profileNativeArgs.Count) {
  $nativeArgs += $profileNativeArgs
} else {
  switch ($Kind) {
    'claude' { if($Access -eq 'full'){$nativeArgs+='--dangerously-skip-permissions'}else{$nativeArgs+=@('--permission-mode','plan')} }
    'gemini' { if($Access -eq 'full'){$nativeArgs+='--yolo'}else{$nativeArgs+=@('--approval-mode','plan')} }
    'codex' { if($Access -eq 'full'){$nativeArgs+='--dangerously-bypass-approvals-and-sandbox'}else{$nativeArgs+=@('-s','workspace-write','-a','on-request')} }
    'opencode' { if($Access -eq 'full'){$nativeArgs+='--auto'} }
    default { if($Access -eq 'full'){throw "Custom Herdr kind '$Kind' requires a project profile with full_access_args. Run 'herdr init'."}else{throw "Plan mode is not defined for custom Herdr kind '$Kind'."} }
  }
}
if ($Kind -eq 'opencode' -and $OpenCodeModel) { $OpenCodeModel=Resolve-OpenCodeModel $OpenCodeModel; $nativeArgs+=@('-m',$OpenCodeModel) }
$date=Get-Date -Format 'yyyy-MM-dd';$stamp=Get-Date -Format 'HHmmss';$handoff=Join-Path $project "herdr\$Category\$date\$stamp--$Name--$Slug";New-Item -ItemType Directory -Force -Path $handoff|Out-Null
$resultPath=Join-Path $handoff 'result.md';$briefPath=Join-Path $handoff 'brief.md';$statusPath=Join-Path $handoff 'status.json';$pane=$null;$agent=$null
try {
@"
# Brief

- Agent: $Name
- Kind: $Kind
- Access: $Access

## Task
$Prompt

## Worktree and integration contract
For `task` or `bugfix`, before any edit, inspect Git status, target branch, existing worktrees, and concurrent/overlapping edits. Independently decide whether a dedicated worktree is required to avoid conflicts; do not skip this decision because the user did not explicitly request one. Use a dedicated branch and worktree whenever the shared tree is dirty with unrelated changes, implementation is concurrent, or overlap risk exists. If you use one: verify inside it, safely merge its branch into the intended target worktree only after confirming that target is clean and unchanged as expected, then run the applicable verification again after the merge. Do not force a merge, reset, clean, stash, or overwrite other changes. If safe merge or post-merge verification is blocked, write the exact blocker and replay steps in the result and send a `需要处理` Herdr notification; do not claim completion.

Your `result.md` must state: worktree decision and reason; worktree path/branch/commit SHA if used; merge command/result; verification before and after merge; conclusion, commands/tests and outcomes, evidence, changed files, blockers, and confirmation that no secrets were recorded. For `research`, remain read-only unless the user explicitly requests changes.

## Mandatory completion contract
Only after the required verification and (when applicable) successful safe merge, write full Markdown evidence to `$resultPath` and run:
`herdr notification show "Herdr: $Name 已完成" --body "$resultPath" --sound done`
Do not report completion only in the TUI.
"@ | Set-Content -LiteralPath $briefPath -Encoding utf8
  $split=(Invoke-HerdrJson @('pane','split','--current','--direction',$Direction,'--cwd',$project,'--no-focus')).json
  $pane=[string]$split.result.pane.pane_id;if(-not $pane){throw 'Herdr did not return a pane ID.'}
  # Wait for the newly split PowerShell pane to reach its interactive prompt before agent start.
  Start-Sleep -Seconds 7
  $agent=Start-AgentWhenPaneReady $pane $nativeArgs
  if(-not $agent -or $agent.agent -ne $Kind -or -not $agent.interactive_ready){throw 'Herdr did not return a confirmed interactive agent.'}
  $status=[ordered]@{name=$Name;kind=$Kind;access=$Access;model=$OpenCodeModel;pane_id=$pane;started_at=(Get-Date -Format o);brief_path=$briefPath;result_path=$resultPath;start_result=$agent}
  $status|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statusPath -Encoding utf8
  $message="Read $briefPath. Complete the task. For task/bugfix, make the mandatory worktree decision before editing and do not claim completion until safe merge plus post-merge verification have succeeded. Before completion write $resultPath, then send the exact Herdr completion notification stated in the brief. Final reply: summary plus result path only."
  if($Kind -eq 'opencode'){Start-Sleep -Seconds 10;& herdr pane send-text $pane $message;& herdr pane send-keys $pane enter}else{& herdr agent prompt $Name $message|Out-Null}
  $watcher=Join-Path $PSScriptRoot 'Watch-HerdrHandoff.ps1';$watchArgs="-NoProfile -ExecutionPolicy Bypass -File `"$watcher`" -AgentName `"$Name`" -StatusPath `"$statusPath`"";$watch=Start-Process -FilePath powershell.exe -ArgumentList $watchArgs -WindowStyle Hidden -PassThru
  [pscustomobject]@{name=$Name;pane_id=$pane;handoff=$handoff;brief=$briefPath;result=$resultPath;status=$statusPath;watcher_pid=$watch.Id}|ConvertTo-Json -Depth 4
} catch {
  [pscustomobject]@{failed_at=(Get-Date -Format o);error=$_.Exception.Message;pane_id=$pane;agent_detected=($null-ne $agent)}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $handoff 'failure.json') -Encoding utf8
  if($pane -and -not $agent){& herdr pane close $pane 2>$null|Out-Null}
  throw
}
