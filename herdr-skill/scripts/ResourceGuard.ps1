function Get-WorkflowResourceSnapshot {
  [CmdletBinding()]
  param()
  $names=@('codex','opencode','claude','gemini')
  $processes=@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$names -contains $_.ProcessName.ToLowerInvariant()})
  $memory=[int64](($processes | Measure-Object -Property WorkingSet64 -Sum).Sum)
  [pscustomobject]@{
    captured_at=(Get-Date -Format o)
    agent_processes=$processes.Count
    memory_bytes=$memory
    memory_mb=[math]::Round($memory/1MB,1)
    processes=@($processes | ForEach-Object {[ordered]@{pid=$_.Id;name=$_.ProcessName;memory_mb=[math]::Round($_.WorkingSet64/1MB,1)}})
  }
}

function Test-WorkflowResourceBudget {
  [CmdletBinding()]
  param([int]$MaxAgentProcesses=12,[int]$MaxMemoryMB=6144)
  $snapshot=Get-WorkflowResourceSnapshot
  $reasons=@()
  if($snapshot.agent_processes -gt $MaxAgentProcesses){$reasons += "agent_processes=$($snapshot.agent_processes)>$MaxAgentProcesses"}
  if($snapshot.memory_mb -gt $MaxMemoryMB){$reasons += "memory_mb=$($snapshot.memory_mb)>$MaxMemoryMB"}
  [pscustomobject]@{ok=($reasons.Count -eq 0);reasons=$reasons;snapshot=$snapshot;limits=[ordered]@{max_agent_processes=$MaxAgentProcesses;max_memory_mb=$MaxMemoryMB}}
}

function Write-WorkflowResourceSnapshot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$WorkflowDirectory,[int]$MaxAgentProcesses=12,[int]$MaxMemoryMB=6144)
  $budget=Test-WorkflowResourceBudget $MaxAgentProcesses $MaxMemoryMB
  $path=Join-Path $WorkflowDirectory 'resource.json'
  $budget|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding utf8
  return $budget
}
