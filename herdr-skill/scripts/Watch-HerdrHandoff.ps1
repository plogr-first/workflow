[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AgentName,
  [Parameter(Mandatory)][string]$StatusPath,
  [string]$OutcomePath,
  [string]$SessionName,
  [int]$StartTimeoutSeconds = 120,
  [int]$PollSeconds = 5
)
$ErrorActionPreference = 'Stop'
$status = $null
$statusDeadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $statusDeadline -and -not $status) {
  try { $status = Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $status) { throw "Watcher could not read a valid agent status file within 30 seconds: $StatusPath" }
$resultPath = [string]$status.result_path
if (-not $OutcomePath) { $OutcomePath = [string]$status.outcome_path }
if (-not $SessionName -and $status.session_name) { $SessionName = [string]$status.session_name }
$prefix = if ($SessionName) { @('--session', $SessionName) } else { @() }
$pane = [string]$status.pane_id
$kind = [string]$status.kind
$deadline = (Get-Date).AddSeconds($StartTimeoutSeconds)
$observedWork = $false
function Notify([string]$Title,[string]$Body,[string]$Sound = 'done') {
  & herdr @prefix notification show $Title --body $Body --sound $Sound 2>$null | Out-Null
}
function Get-AgentSnapshot {
  try {
    $raw = @(& herdr @prefix agent get $AgentName 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    return (($raw -join "`n") | ConvertFrom-Json).result.agent
  } catch { return $null }
}
while ((Get-Date) -lt $deadline) {
  $agent = Get-AgentSnapshot
  if (-not $agent) { Start-Sleep -Seconds $PollSeconds; continue }
  # A fast agent can complete before the first poll observes `working`. An
  # interactive idle/done agent is still proof that startup succeeded; only a
  # missing or blocked agent should be treated as unavailable.
  # "idle" directly after startup only proves a live terminal; it is not a completed run.\n  # A handoff reminder is permitted only after real execution was observed.\n  if ($agent.interactive_ready -eq $true -and $agent.agent_status -in @('working','done')) { $observedWork = $true }
  if ($agent.agent_status -eq 'blocked') {
    Notify "Herdr: $AgentName 需要处理" "Agent 被阻塞；请检查 $StatusPath" 'request'
    exit 0
  }
  if ((Test-Path -LiteralPath $resultPath) -and ((Get-Item -LiteralPath $resultPath).Length -gt 0) -and (Test-Path -LiteralPath $OutcomePath) -and ((Get-Item -LiteralPath $OutcomePath).Length -gt 0)) {
    Notify "Herdr: $AgentName 交接已就绪" $resultPath
    exit 0
  }
  if ($observedWork -and $agent.agent_status -in @('idle','done')) { break }
  Start-Sleep -Seconds $PollSeconds
}
if (-not $observedWork) {
  Notify "Herdr: $AgentName 未开始" "未观察到 working；请检查 $StatusPath" 'request'
  exit 0
}
$reminder = "交接检查发现你已返回但缺少完整交接。立即将完整结果写入 $resultPath，并将有效 workflow state JSON 写入 $OutcomePath，再运行 Herdr 完成通知。"
if ($kind -eq 'opencode') {
  & herdr @prefix pane send-text $pane $reminder 2>$null
  & herdr @prefix pane send-keys $pane enter 2>$null
} else {
  & herdr @prefix agent prompt $AgentName $reminder 2>$null | Out-Null
}
$repairDeadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $repairDeadline) {
  if ((Test-Path -LiteralPath $resultPath) -and ((Get-Item -LiteralPath $resultPath).Length -gt 0) -and (Test-Path -LiteralPath $OutcomePath) -and ((Get-Item -LiteralPath $OutcomePath).Length -gt 0)) {
    Notify "Herdr: $AgentName 补交已就绪" $resultPath
    exit 0
  }
  Start-Sleep -Seconds $PollSeconds
}
Notify "Herdr: $AgentName 交接违规" "Agent 已返回但未交 result.md；请检查 $StatusPath" 'request'
exit 1
