[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$TaskKind,
  [string]$TaskOpenCodeModel,
  [string]$VerificationKind,
  [string]$VerificationOpenCodeModel,
  [string]$ResearchKind,
  [string]$ResearchOpenCodeModel,
  [string]$HerdrSessionName,
  [string[]]$TaskFullAccessArgs,
  [string[]]$VerificationFullAccessArgs,
  [string[]]$ResearchFullAccessArgs,
  [switch]$SkipSkillsInstall,
  [switch]$Help
)
$ErrorActionPreference = 'Stop'
if ($Help) {
@"
Herdr project initialization

Run from a project root:
  herdr init

The interactive flow selects task, verification, and research agents, validates
their terminal executables, writes herdr\dispatch-profile.json, then runs:
  npx skills@latest add mattpocock/skills

Automation/testing options:
  -ProjectRoot <path> -TaskKind <kind> -VerificationKind <kind> -ResearchKind <kind>
  -TaskOpenCodeModel <id> -VerificationOpenCodeModel <id> -ResearchOpenCodeModel <id>
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
function Resolve-OpenCodeModel([string]$Requested, [string[]]$Models) {
  $aliases = @{ 'zen'='opencode/deepseek-v4-flash-free'; 'zen-free'='opencode/deepseek-v4-flash-free'; 'deepseek-v4-flash-free'='opencode/deepseek-v4-flash-free'; 'go'='opencode-go/deepseek-v4-flash'; 'go-flash'='opencode-go/deepseek-v4-flash'; 'deepseek-v4-flash'='opencode-go/deepseek-v4-flash' }
  $key = $Requested.Trim().ToLowerInvariant(); if($aliases.ContainsKey($key)){$key=$aliases[$key]}
  $exact=@($Models|Where-Object{$_.Equals($key,[StringComparison]::OrdinalIgnoreCase)}); if($exact.Count -eq 1){return $exact[0]}
  $normal=$key -replace '[^a-z0-9]',''; $fuzzy=@($Models|Where-Object{(($_ -replace '[^a-z0-9]','').ToLowerInvariant()).Contains($normal)})
  if($fuzzy.Count -eq 1){return $fuzzy[0]}; if($fuzzy.Count -gt 1){throw "OpenCode model '$Requested' is ambiguous: $($fuzzy -join ', ')"}; throw "OpenCode model '$Requested' is not currently available."
}
function Select-OpenCodeModelInteractive([string]$Role, [string[]]$Models) {
  if ([Console]::IsInputRedirected) {
    Write-Host "Select OpenCode model for $Role agent:"
    for ($i = 0; $i -lt $Models.Count; $i++) { Write-Host ('  [ ] {0}) {1}' -f ($i + 1), $Models[$i]) }
    $choice = Read-Host 'Select one model number'
    $index = 0
    if (-not ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $Models.Count)) { throw "Select one listed OpenCode model number (1-$($Models.Count))." }
    return $Models[$index - 1]
  }
  $cursor = 0; $selected = -1
  while ($true) {
    Clear-Host
    Write-Host "Select OpenCode model for $Role agent"
    Write-Host '↑/↓ move   Space select   Enter confirm   Esc cancel'
    Write-Host ''
    for ($i = 0; $i -lt $Models.Count; $i++) {
      $pointer = if($i -eq $cursor){'>'}else{' '}; $mark = if($i -eq $selected){'[x]'}else{'[ ]'}
      Write-Host ('{0} {1} {2}' -f $pointer,$mark,$Models[$i])
    }
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    switch ($key.VirtualKeyCode) {
      38 { if($cursor -gt 0){$cursor--}; break }
      40 { if($cursor -lt ($Models.Count - 1)){$cursor++}; break }
      32 { $selected=$cursor; break }
      13 { if($selected -ge 0){ return $Models[$selected] }; break }
      27 { throw 'OpenCode model selection cancelled.' }
    }
  }
}
function Get-HerdrSessions {
  $raw = @(& herdr session list --json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "Unable to list Herdr sessions: $($raw -join ' ')" }
  try { $data = ($raw -join "`n") | ConvertFrom-Json } catch { throw 'Herdr session list did not return JSON.' }
  return @($data.sessions | ForEach-Object { [string]$_.name } | Where-Object { $_ })
}
function Select-HerdrSession([string]$Requested) {
  $sessions = @(Get-HerdrSessions)
  if ($Requested) {
    if ($sessions -notcontains $Requested) { throw "Herdr session '$Requested' does not exist. Available: $($sessions -join ', ')" }
    return $Requested
  }
  if ($sessions.Count -eq 1) { return $sessions[0] }
  Write-Host ''
  Write-Host 'Select the Herdr persistent session for this project:'
  for ($i=0; $i -lt $sessions.Count; $i++) { Write-Host ('  {0}) {1}' -f ($i + 1), $sessions[$i]) }
  Write-Host '  N) Create a new named session'
  $choice = (Read-Host 'Session number or new name').Trim()
  $index = 0
  if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $sessions.Count) { return $sessions[$index - 1] }
  if ($choice -match '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$') {
    $newName = $choice.ToLowerInvariant()
    if ($sessions -contains $newName) { return $newName }
    $null = & herdr --session $newName status server 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to create or open Herdr session '$newName'." }
    return $newName
  }
  throw 'Invalid Herdr session selection.'
}
function Get-MattpockSkills([string]$Project) {
  $roots = @(
    (Join-Path $Project '.agents\skills'),
    (Join-Path $env:USERPROFILE '.agents\skills'),
    'F:\mattpock\.agents\skills'
  ) | Select-Object -Unique
  $names = @('implement','investigate','review','qa','systematic-debugging','test-driven-development','using-git-worktrees')
  $out = [ordered]@{}
  foreach ($name in $names) {
    $hit = $roots | ForEach-Object { Join-Path $_ $name } | Where-Object { Test-Path (Join-Path $_ 'SKILL.md') } | Select-Object -First 1
    $out[$name] = [ordered]@{ available = [bool]$hit; path = if($hit){(Resolve-Path $hit).Path}else{$null} }
  }
  return $out
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
      $model = Select-OpenCodeModelInteractive $Role $models
    } else { $model = Resolve-OpenCodeModel $RequestedModel $models }
  }
  return [ordered]@{
    kind = $kind
    executable = $command
    model = $model
    full_access_args = @(Get-FullAccessArgs $kind $ProvidedArgs $interactive)
  }
}

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$session = Select-HerdrSession $HerdrSessionName
$supportedKinds = Get-SupportedKinds
$task = Select-Agent 'task' $TaskKind $TaskOpenCodeModel $TaskFullAccessArgs $supportedKinds
$verification = Select-Agent 'verification' $VerificationKind $VerificationOpenCodeModel $VerificationFullAccessArgs $supportedKinds
$research = Select-Agent 'research' $ResearchKind $ResearchOpenCodeModel $ResearchFullAccessArgs $supportedKinds
$herdrDirectory = Join-Path $project 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDirectory | Out-Null
$profilePath = Join-Path $herdrDirectory 'dispatch-profile.json'
$profile = [ordered]@{
  schema_version = 2
  initialized_at = (Get-Date -Format o)
  project_root = $project
  herdr_session = [ordered]@{ name = $session; bound_at = (Get-Date -Format o) }
  task_agent = $task
  verification_agent = $verification
  research_agent = $research
  mattpock_skills = (Get-MattpockSkills $project)
  skills_install_command = 'npx skills@latest add mattpocock/skills'
}
$profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding utf8
Write-Host "Herdr profile written: $profilePath"
Write-Host "Task: $($task.kind)$($(if($task.model){' / ' + $task.model}else{''}))"
Write-Host "Verification: $($verification.kind)$($(if($verification.model){' / ' + $verification.model}else{''}))"
Write-Host "Research: $($research.kind)$($(if($research.model){' / ' + $research.model}else{''}))"
if ($SkipSkillsInstall) { Write-Host 'Skipped skills installation by request.'; exit 0 }
Write-Host 'Starting project skill installation: npx skills@latest add mattpocock/skills'
& npx skills@latest add mattpocock/skills
if ($LASTEXITCODE -ne 0) { throw "skills installation failed with exit code $LASTEXITCODE. The Herdr profile was retained at $profilePath." }
