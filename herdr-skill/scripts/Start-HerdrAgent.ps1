[CmdletBinding()]
param(
  [string]$Kind,
  [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_-]{0,31}$')][string]$Name,
  [Parameter(Mandatory)][ValidateSet('research','task','bugfix')][string]$Category,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$Slug,
  [Parameter(Mandatory)][string]$Prompt,
  [ValidateSet('full','plan')][string]$Access = 'full',
  [string]$OpenCodeModel,
  [ValidateSet('task','verification','research')][string]$Profile,
  [switch]$DeferActivation,
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
  $prefix = if($script:HerdrSession){ @('--session',$script:HerdrSession) } else { @() }
  $raw = & herdr @prefix @Arguments 2>&1
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
    if ($attempt.exit -eq 0 -and $attempt.json.result.agent.interactive_ready -and $attempt.json.result.agent.agent -eq $Kind -and @('blocked','error') -notcontains [string]$attempt.json.result.agent.agent_status) { return $attempt.json.result.agent }
    if ([string]$attempt.json.error.code -eq 'agent_pane_busy') { Start-Sleep -Milliseconds 750; continue }
    throw "Herdr agent start failed: $($attempt.text)"
  } while ((Get-Date) -lt $deadline)
  throw "New pane $Pane did not become an available shell within 20 seconds."
}if ($env:HERDR_ENV -ne '1') { throw 'HERDR_ENV is not 1. Run this from a Herdr-managed pane.' }
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profileNativeArgs = @()
$script:HerdrSession = $null
if ($Profile) {
  if ($Kind) { throw 'Use either -Kind or -Profile, not both.' }
  $profilePath = Join-Path $project 'herdr\dispatch-profile.json'
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Herdr dispatch profile not found: $profilePath. Run 'herdr init' from the project root first." }
  try { $dispatchProfile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json } catch { throw "Invalid Herdr dispatch profile: $profilePath" }
  $script:HerdrSession = [string]$dispatchProfile.herdr_session.name
  if ([string]::IsNullOrWhiteSpace($script:HerdrSession)) { throw "Herdr profile is missing herdr_session.name: $profilePath" }
  $entry = switch ($Profile) { 'task' { $dispatchProfile.task_agent }; 'verification' { $dispatchProfile.verification_agent }; 'research' { $dispatchProfile.research_agent } }
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
$resultPath=Join-Path $handoff 'result.md';$outcomePath=Join-Path $handoff 'outcome.json';$briefPath=Join-Path $handoff 'brief.md';$statusPath=Join-Path $handoff 'status.json';$progressPath=Join-Path $handoff 'progress.json';$pane=$null;$agent=$null
$workflowReference = 'C:\Users\Lenovo\.codex\skills\herdr\references\workflow-protocol.md'
$roleContract = switch ($Profile) {
  'research' { @"
You are the research agent. Use mattpocock `/investigate` when available, then follow the deep-research protocol in $($workflowReference): use primary evidence, keep a decision-critical claim ledger with exact source evidence and access dates, state uncertainty and contradictory evidence, and remain read-only. A verifier audits evidence; do not claim unverified conclusions.
"@ }
  'verification' { @"
You are the verification and integration agent. Use mattpocock `/review` and `/qa` when available. Read the execution candidate's result/branch/worktree supplied in the task prompt. Evaluate outcome, regression, spec/scope, and standards/integration independently. Report only reproducible P0/P1 blockers (maximum five) with acceptance rule and command/file evidence. Do not turn style suggestions into blockers. If all gates pass, confirm the target worktree is clean and at the expected base, merge safely, re-run the applicable checks after merge, and report `merged` with merge SHA. If any gate or safe merge fails, report `fix_required` or `blocked`; never force reset, clean, stash, or overwrite other work.
"@ }
  default { if ($Category -eq 'bugfix') { @"
You are the bugfix execution agent. Use mattpocock `/systematic-debugging` to establish the loop, then `/implement` for the fix. Before editing, build and run a narrow, red-capable reproduction of the reported symptom. Do not ship a guess-based patch when no such loop exists. Minimise the repro, test falsifiable hypotheses one variable at a time, add a regression test at the correct seam where possible, fix the root cause, re-run the original reproduction, remove temporary debug instrumentation, and commit the candidate branch. Make the mandatory worktree decision before edits. Return `candidate` with branch, base/candidate SHAs, commands and results; do not merge—the verification agent owns the safe merge after independent acceptance.
"@ } else { @"
You are the task execution agent. Use mattpocock `/implement`. Before editing, define observable acceptance checks and make the mandatory worktree decision. Use an isolated worktree for dirty shared trees, concurrent work, or overlap risk. Implement the smallest complete change, run focused and relevant full validation, and commit the candidate branch. Return `candidate` with worktree decision, path, branch, base/candidate SHAs, changed files, acceptance checks, and command results; do not merge—the verification agent owns the safe merge after independent acceptance.
"@ } }
}
try {
@"
# Brief

- Agent: $Name
- Kind: $Kind
- Access: $Access

## Task
$Prompt

## Workflow role contract
$roleContract

Your `progress.json` must be updated at phase boundaries with `{ "phase": "investigating|implementing|testing|candidate_ready|blocked", "updated_at": "...", "completed": [], "next_action": "..." }`. Your `result.md` must state the workflow state (`candidate`, `passed`, `fix_required`, `blocked`, or `merged`), conclusion, commands/tests and outcomes, evidence, changed files, blockers, and confirmation that no secrets were recorded. Include the worktree/branch/commit/merge facts applicable to your role. For `research`, remain read-only unless the user explicitly requests changes.

Before notifying completion, also write valid JSON to `$outcomePath` using this minimum schema:
```json
{ "state": "candidate|passed|fix_required|blocked|merged", "summary": "short evidence-backed result" }
```
Add `branch`, `base_sha`, `candidate_sha`, `merge_sha`, `blockers`, and `verification_commands` whenever applicable. The workflow monitor uses this file to wake the next Agent; a TUI reply alone is invalid.

## Mandatory completion contract
Only after completing your role's required evidence, write full Markdown evidence to `$resultPath` and valid JSON to `$outcomePath`, then run:
`herdr notification show "Herdr: $Name 已完成" --body "$resultPath" --sound done`
Do not report completion only in the TUI.
"@ | Set-Content -LiteralPath $briefPath -Encoding utf8
  $split=(Invoke-HerdrJson @('pane','split','--current','--direction',$Direction,'--cwd',$project,'--no-focus')).json
  $pane=[string]$split.result.pane.pane_id;if(-not $pane){throw 'Herdr did not return a pane ID.'}
  # Wait for the newly split PowerShell pane to reach its interactive prompt before agent start.
  Start-Sleep -Seconds 7
  $agent=Start-AgentWhenPaneReady $pane $nativeArgs
  if(-not $agent -or $agent.agent -ne $Kind -or -not $agent.interactive_ready){throw 'Herdr did not return a confirmed interactive agent.'}
  $status=[ordered]@{name=$Name;kind=$Kind;access=$Access;model=$OpenCodeModel;profile=$Profile;deferred=[bool]$DeferActivation;pane_id=$pane;started_at=(Get-Date -Format o);brief_path=$briefPath;result_path=$resultPath;outcome_path=$outcomePath;progress_path=$progressPath;start_result=$agent}
  $status|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statusPath -Encoding utf8
  [ordered]@{phase='investigating';updated_at=(Get-Date -Format o);completed=@();next_action=if($DeferActivation){'wait for workflow monitor activation'}else{'read brief and begin role work'}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $progressPath -Encoding utf8
  $watchPid=$null
  if(-not $DeferActivation){
    $message="Read $briefPath. You are $Name. Follow the workflow role contract exactly; reopen the brief at every phase boundary. Before completion write $resultPath and $outcomePath, then send the exact Herdr completion notification. A TUI reply alone is invalid. Final reply: summary plus result path only."
    if($Kind -eq 'opencode'){Start-Sleep -Seconds 10;Invoke-HerdrJson @('pane','send-text',$pane,$message)|Out-Null;Invoke-HerdrJson @('pane','send-keys',$pane,'enter')|Out-Null}else{Invoke-HerdrJson @('agent','prompt',$Name,$message)|Out-Null}
    $watcher=Join-Path $PSScriptRoot 'Watch-HerdrHandoff.ps1';$watchArgs="-NoProfile -ExecutionPolicy Bypass -File `"$watcher`" -AgentName `"$Name`" -StatusPath `"$statusPath`" -OutcomePath `"$outcomePath`"";$watch=Start-Process -FilePath powershell.exe -ArgumentList $watchArgs -WindowStyle Hidden -PassThru;$watchPid=$watch.Id
  }
  [pscustomobject]@{name=$Name;pane_id=$pane;handoff=$handoff;brief=$briefPath;result=$resultPath;outcome=$outcomePath;progress=$progressPath;status=$statusPath;watcher_pid=$watchPid;deferred=[bool]$DeferActivation}|ConvertTo-Json -Depth 4
} catch {
  [pscustomobject]@{failed_at=(Get-Date -Format o);error=$_.Exception.Message;pane_id=$pane;agent_detected=($null-ne $agent)}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $handoff 'failure.json') -Encoding utf8
  if($pane -and -not $agent){try { Invoke-HerdrJson @('pane','close',$pane) | Out-Null } catch { }}
  throw
}
