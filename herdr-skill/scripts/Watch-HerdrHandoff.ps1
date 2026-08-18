[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AgentName,
  [Parameter(Mandatory)][string]$StatusPath,
  [string]$OutcomePath,
  [int]$StartTimeoutSeconds = 120,
  [int]$PollSeconds = 5
)
$ErrorActionPreference = 'Stop'
$status = Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json
$resultPath = [string]$status.result_path
if (-not $OutcomePath) { $OutcomePath = [string]$status.outcome_path }
$pane = [string]$status.pane_id
$kind = [string]$status.kind
$deadline = (Get-Date).AddSeconds($StartTimeoutSeconds)
$observedWork = $false
function Notify([string]$Title,[string]$Body,[string]$Sound = 'done') {
  & herdr notification show $Title --body $Body --sound $Sound | Out-Null
}
while ((Get-Date) -lt $deadline) {
  $agent = (& herdr agent get $AgentName | ConvertFrom-Json).result.agent
  if ($agent.agent_status -eq 'working') { $observedWork = $true }
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
  & herdr pane send-text $pane $reminder
  & herdr pane send-keys $pane enter
} else {
  & herdr agent prompt $AgentName $reminder | Out-Null
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
