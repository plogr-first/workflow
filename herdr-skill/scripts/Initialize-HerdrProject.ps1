[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$TaskKind,
  [string]$TaskOpenCodeModel,
  [string]$VerificationKind,
  [string]$VerificationOpenCodeModel,
  [string[]]$TaskFullAccessArgs,
  [string[]]$VerificationFullAccessArgs,
  [switch]$SkipSkillsInstall,
  [switch]$Help
)
$ErrorActionPreference = 'Stop'
if ($Help) {
@"
Herdr project initialization

Run from a project root:
  herdr init

The interactive flow selects task and verification agents, validates their
terminal executables, writes herdr\dispatch-profile.json, then runs:
  npx skills@latest add mattpocock/skills

Automation/testing options:
  -ProjectRoot <path> -TaskKind <kind> -VerificationKind <kind>
  -TaskOpenCodeModel <id> -VerificationOpenCodeModel <id>
  -SkipSkillsInstall
"@ | Write-Output
  exit 0
}
function Get-SupportedKinds {
  $help = ((& herdr agent start --help 2>&1) -join "`n")
  if ($LASTEXITCODE -ne 0) { throw "Unable to read Herdr agent kinds: $help" }
  $match = [regex]::Match($help, '\[possible values:\s*([^\]]+)\]')
  if (-not $match.Success) { throw 'Herdr did not expose supported agent kinds.' }
  return @($match.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}
function Get-OpenCodeModels {
  $models = @((& opencode models 2>$null) -replace "`e\[[0-9;]*m", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if (-not $models.Count) { throw "Unable to obtain models from 'opencode models'." }
  return $models
}
function Assert-TerminalAgent([string]$Kind, [string[]]$SupportedKinds) {
  if ($SupportedKinds -notcontains $Kind.ToLowerInvariant()) {
    throw "'$Kind' is not a Herdr-supported kind. Supported kinds: $($SupportedKinds -join ', ')"
  }
  $command = Get-Command -Name $Kind -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command) { throw "Herdr kind '$Kind' has no terminal executable named '$Kind' in PATH." }
  $executable = [string]$command.Path
  $version = @(& $executable --version 2>&1)
  if ($LASTEXITCODE -ne 0) { $version = @(& $executable -v 2>&1) }
  if ($LASTEXITCODE -ne 0) { throw "Terminal executable '$Kind' could not be validated with --version or -v." }
  return $executable
}
function Get-FullAccessArgs([string]$Kind, [string[]]$ProvidedArgs, [bool]$Interactive) {
  $known = @{
    'claude'   = @('--dangerously-skip-permissions')
    'gemini'   = @('--yolo')
    'codex'    = @('--dangerously-bypass-approvals-and-sandbox')
    'opencode' = @('--auto')
  }
  if ($known.ContainsKey($Kind)) { return @($known[$Kind]) }
  if ($ProvidedArgs -and $ProvidedArgs.Count) { return @($ProvidedArgs) }
  if (-not $Interactive) { throw "Custom agent '$Kind' requires -<Role>FullAccessArgs." }
  $raw = Read-Host "Enter the full-access launch arguments for '$Kind' (space separated)"
  $args = @($raw -split '\s+' | Where-Object { $_ })
  if (-not $args.Count) { throw "Custom agent '$Kind' requires explicit full-access launch arguments." }
  return $args
}
function Select-Agent([string]$Role, [string]$RequestedKind, [string]$RequestedModel, [string[]]$ProvidedArgs, [string[]]$SupportedKinds) {
  $interactive = [string]::IsNullOrWhiteSpace($RequestedKind)
  if ($interactive) {
    Write-Host ''
    Write-Host "Select $Role agent (all profiles launch with full access):"
    Write-Host '  1) claude'
    Write-Host '  2) gemini'
    Write-Host '  3) codex'
    Write-Host '  4) opencode'
    Write-Host '  5) custom Herdr-supported kind'
    $choice = Read-Host 'Choice'
    $map = @{ '1'='claude'; '2'='gemini'; '3'='codex'; '4'='opencode' }
    if ($map.ContainsKey($choice)) { $RequestedKind = $map[$choice] }
    elseif ($choice -eq '5') { $RequestedKind = (Read-Host 'Custom Herdr kind').Trim().ToLowerInvariant() }
    else { throw "Invalid $Role agent choice: $choice" }
  }
  $kind = $RequestedKind.Trim().ToLowerInvariant()
  $command = Assert-TerminalAgent $kind $SupportedKinds
  $model = $null
  if ($kind -eq 'opencode') {
    $models = Get-OpenCodeModels
    if ([string]::IsNullOrWhiteSpace($RequestedModel)) {
      Write-Host ''
      Write-Host "Select OpenCode model for $Role agent:"
      for ($i = 0; $i -lt $models.Count; $i++) { Write-Host ('  {0}) {1}' -f ($i + 1), $models[$i]) }
      $modelChoice = Read-Host 'Model number or exact model ID'
      $index = 0
      if ([int]::TryParse($modelChoice, [ref]$index) -and $index -ge 1 -and $index -le $models.Count) { $model = $models[$index - 1] }
      else { $model = @($models | Where-Object { $_.Equals($modelChoice, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1 }
    } else { $model = @($models | Where-Object { $_.Equals($RequestedModel, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1 }
    if (-not $model) { throw "OpenCode model '$RequestedModel' is not currently available." }
  }
  return [ordered]@{
    kind = $kind
    executable = $command
    model = $model
    full_access_args = @(Get-FullAccessArgs $kind $ProvidedArgs $interactive)
  }
}

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$supportedKinds = Get-SupportedKinds
$task = Select-Agent 'task' $TaskKind $TaskOpenCodeModel $TaskFullAccessArgs $supportedKinds
$verification = Select-Agent 'verification' $VerificationKind $VerificationOpenCodeModel $VerificationFullAccessArgs $supportedKinds
$herdrDirectory = Join-Path $project 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDirectory | Out-Null
$profilePath = Join-Path $herdrDirectory 'dispatch-profile.json'
$profile = [ordered]@{
  schema_version = 1
  initialized_at = (Get-Date -Format o)
  project_root = $project
  task_agent = $task
  verification_agent = $verification
  skills_install_command = 'npx skills@latest add mattpocock/skills'
}
$profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding utf8
Write-Host "Herdr profile written: $profilePath"
Write-Host "Task: $($task.kind)$($(if($task.model){' / ' + $task.model}else{''}))"
Write-Host "Verification: $($verification.kind)$($(if($verification.model){' / ' + $verification.model}else{''}))"
if ($SkipSkillsInstall) { Write-Host 'Skipped skills installation by request.'; exit 0 }
Write-Host 'Starting project skill installation: npx skills@latest add mattpocock/skills'
& npx skills@latest add mattpocock/skills
if ($LASTEXITCODE -ne 0) { throw "skills installation failed with exit code $LASTEXITCODE. The Herdr profile was retained at $profilePath." }
