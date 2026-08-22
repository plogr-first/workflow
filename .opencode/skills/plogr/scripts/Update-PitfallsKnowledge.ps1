[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkflowPath,
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
  Write-Host "Workflow file not found: $WorkflowPath" -ForegroundColor DarkGray
  return
}

try {
  $wf = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json
} catch {
  Write-Host "Invalid workflow JSON: $WorkflowPath" -ForegroundColor DarkGray
  return
}

$mode = [string]$wf.mode
$state = [string]$wf.state
$slug = [string]$wf.slug
$repairRound = [int]$wf.repair_round

# Only harvest pitfalls on terminal merged state from bugfix or workflows with repair rounds
if ($state -ne 'merged' -and $state -ne 'passed') { return }
if ($mode -ne 'bugfix' -and $repairRound -lt 1) { return }

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$wfDir = Split-Path -Parent $WorkflowPath

# Read verifier and task reports
$verifierResultPath = if ($wf.verifier.result) { $wf.verifier.result } else { Join-Path $wfDir 'verify-result.md' }
$verifierReportPath = Join-Path (Split-Path -Parent $verifierResultPath) 'verification.md'
$taskResultPath = if ($wf.task.result) { $wf.task.result } else { Join-Path $wfDir 'task-result.md' }

$verifierContent = if (Test-Path -LiteralPath $verifierReportPath) { Get-Content -LiteralPath $verifierReportPath -Raw } elseif (Test-Path -LiteralPath $verifierResultPath) { Get-Content -LiteralPath $verifierResultPath -Raw } else { '' }
$taskContent = if (Test-Path -LiteralPath $taskResultPath) { Get-Content -LiteralPath $taskResultPath -Raw } else { '' }

# Extract changed files from task outcome if available
$changedFiles = @()
if ($wf.task.outcome -and (Test-Path -LiteralPath $wf.task.outcome)) {
  try {
    $tOut = Get-Content -LiteralPath $wf.task.outcome -Raw | ConvertFrom-Json
    if ($tOut.changed_files) { $changedFiles = @($tOut.changed_files) }
  } catch {}
}

# Determine category
$category = 'BUGFIX'
if ($verifierContent -match 'API|schema|contract|endpoint') { $category = 'API-CONTRACT' }
elseif ($verifierContent -match 'regression|test failure') { $category = 'REGRESSION' }
elseif ($verifierContent -match 'security|token|auth') { $category = 'SECURITY' }
elseif ($verifierContent -match 'concurrency|deadlock|race') { $category = 'CONCURRENCY' }

# Synthesize summary and golden rule
$dateStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$pitfallId = "pitfall-$dateStamp-$slug"

$symptom = if ($wf.task.outcome -and $tOut.summary) { [string]$tOut.summary } else { "Bug resolved in workflow $slug" }
$rootCause = "Root cause identified and repaired in workflow $slug (Mode: $mode, Rounds: $repairRound)"
$goldenRule = "Ensure regression and API contract checks pass before candidate submission for $slug"

if ($taskContent -match '(?m)^[0-9]+\.\s*Root cause:\s*(.+)$') {
  $rootCause = $Matches[1].Trim()
} elseif ($taskContent -match '(?m)###\s*Root Cause\s*\n+([^\n]+)') {
  $rootCause = $Matches[1].Trim()
}

$filePatterns = @()
foreach ($cf in $changedFiles) {
  $dir = Split-Path -Parent $cf
  if ($dir) { $filePatterns += "$dir/**" } else { $filePatterns += $cf }
}
if (-not $filePatterns.Count) { $filePatterns = @('**/*') }
$filePatterns = @($filePatterns | Select-Object -Unique)

$entry = [ordered]@{
  id = $pitfallId
  workflow_id = [string]$wf.workflow_id
  mode = $mode
  category = $category
  slug = $slug
  symptom = $symptom
  root_cause = $rootCause
  golden_rule = $goldenRule
  file_patterns = $filePatterns
  recorded_by = if ($wf.verifier.active_agent_name) { $wf.verifier.active_agent_name } else { 'verifier' }
  recorded_at = (Get-Date -Format o)
}

# Destination paths
$destinations = @(
  (Join-Path $project '.agents\skills\knowledge\pitfalls.jsonl'),
  (Join-Path $project '.knowledge\pitfalls.jsonl'),
  (Join-Path $env:USERPROFILE '.agents\skills\audit-suite\knowledge\pitfalls.jsonl')
)

$jsonLine = ($entry | ConvertTo-Json -Compress -Depth 5)

foreach ($dest in $destinations) {
  try {
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Add-Content -LiteralPath $dest -Value $jsonLine -Encoding utf8
  } catch {}
}

# Also update human-readable markdown knowledge base
$mdPath = Join-Path $project '.knowledge\pitfalls.md'
$mdParent = Split-Path -Parent $mdPath
if (-not (Test-Path -LiteralPath $mdParent)) { New-Item -ItemType Directory -Force -Path $mdParent | Out-Null }

$mdEntry = @"

### 📌 [$category] $slug (`$dateStamp`)
- **表象 (Symptom)**: $symptom
- **根因 (Root Cause)**: $rootCause
- **防护守则 (Golden Rule)**: $goldenRule
- **涉及路径**: $($filePatterns -join ', ')
"@

try {
  if (-not (Test-Path -LiteralPath $mdPath)) {
    Set-Content -LiteralPath $mdPath -Value "# 踩坑知识库与架构反模式守则 (Project Pitfalls & Golden Rules)`n" -Encoding utf8
  }
  Add-Content -LiteralPath $mdPath -Value $mdEntry -Encoding utf8
} catch {}

Write-Host "  🧠 [Knowledge Base] Auto-harvested pitfall rule: $pitfallId ($category)" -ForegroundColor Magenta
