$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$skillPath = Join-Path $packageRoot 'SKILL.md'
$protocolPath = Join-Path $packageRoot 'references\workflow-protocol.md'
$initializerPath = Join-Path $packageRoot 'scripts\Initialize-HerdrProject.ps1'
$singleLauncherPath = Join-Path $packageRoot 'scripts\Start-HerdrWorkflow.ps1'
$parallelLauncherPath = Join-Path $packageRoot 'scripts\Start-HerdrParallelWorkflow.ps1'
$canonicalPlogrPath = Join-Path $packageRoot 'bundled_skills\plogr\SKILL.md'
$agentLauncherPath = Join-Path $packageRoot 'scripts\Start-HerdrAgent.ps1'

foreach ($path in @($skillPath, $protocolPath, $initializerPath, $singleLauncherPath, $parallelLauncherPath, $canonicalPlogrPath, $agentLauncherPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Workflow contract dependency is missing: $path" }
}

$skill = Get-Content -LiteralPath $skillPath -Raw
$protocol = Get-Content -LiteralPath $protocolPath -Raw
$initializer = Get-Content -LiteralPath $initializerPath -Raw
$singleLauncher = Get-Content -LiteralPath $singleLauncherPath -Raw
$parallelLauncher = Get-Content -LiteralPath $parallelLauncherPath -Raw
$canonicalPlogr = Get-Content -LiteralPath $canonicalPlogrPath -Raw
$agentLauncher = Get-Content -LiteralPath $agentLauncherPath -Raw

if ($skill -match 'C:\\Users\\') { throw 'Canonical skill contains a user-specific Windows path.' }
if ($protocol -match 'C:\\Users\\') { throw 'Workflow protocol contains a user-specific Windows path.' }
if ($canonicalPlogr -match 'C:\\Users\\' -or $agentLauncher -match 'C:\\Users\\') { throw 'Distributed plogr/agent payload contains a user-specific Windows path.' }
foreach ($requiredScript in @('Start-HerdrWorkflow.ps1', 'Start-HerdrParallelWorkflow.ps1')) {
  if ($skill -notmatch [regex]::Escape($requiredScript)) { throw "Canonical skill no longer documents required launcher: $requiredScript" }
}
if ($protocol -notmatch 'project-skills\.json') { throw 'Workflow protocol does not point bugfix audit to the project skill registry.' }
foreach ($script in @($initializer, $singleLauncher, $parallelLauncher)) {
  if ($script -notmatch 'project_skill_registry') { throw 'Runtime launcher/initializer no longer enforces the documented project skill registry.' }
}
if ($protocol -notmatch 'Use Git for local commits, worktrees, branch objects, and the actual branch push') { throw 'GitHub/Git publication contract drifted from runtime policy.' }
Write-Output 'Workflow skill-to-runtime contract: PASS'
