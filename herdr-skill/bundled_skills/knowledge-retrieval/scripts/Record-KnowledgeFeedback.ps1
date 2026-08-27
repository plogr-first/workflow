[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [Parameter(Mandatory)][string]$KnowledgeId,
  [Parameter(Mandatory)][bool]$Helpful,
  [string]$WorkflowId,
  [string]$Phase = 'handoff'
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$dir = Join-Path $project '.knowledge\index'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$record = [ordered]@{
  knowledge_id = $KnowledgeId
  used = $true
  helpful = $Helpful
  workflow_id = $WorkflowId
  phase = $Phase
  recorded_at = (Get-Date -Format o)
}
$record | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $dir 'feedback.jsonl') -Encoding utf8
[ordered]@{ status = 'recorded'; feedback = (Join-Path $dir 'feedback.jsonl') } | ConvertTo-Json -Compress
