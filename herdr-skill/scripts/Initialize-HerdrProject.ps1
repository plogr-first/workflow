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
  [ValidateSet('manual','after_merge','create_pr')][string]$PushPolicy,
  [string]$PushRemote,
  [switch]$SkipGitInit,
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
their terminal executables, installs official mattpocock/skills, verifies the engineering skill hashes,
then writes herdr\dispatch-profile.json.

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
  # Known official hashes for mattpocock engineering skills
  $knownOfficialHashes = @{
    'research'        = '0b6597c453178536b50c044a9e57cbc32dbffa47607a370e40768332f54bf8c2'
    'implement'       = '30cd7bc1ebfb3891e85a1eed3b3b81aea0fa4ad4553a784de7f8e421b2d223e0'
    'diagnosing-bugs' = '571bd503ef1ce9f9d143e705346e437881f6ba7307ecf0097646fc82881026c2'
    'code-review'     = '9e72b65b58b39f0e5705a03f44fc4b31dc7089028d12c85b0a206b7af47cb24d'
    'tdd'             = '3a1102800fa8b3c4e1aa3f1fa9d18d3e4749ee8b5d86a3b560bbd53218dbf858'
  }
  $officialRoot = 'C:\Users\Lenovo\AppData\Local\Temp\mattpocock-skills-audit-20260818\skills\engineering'
  $roots = @(
    (Join-Path $Project '.agents\skills'),
    'F:\mattpock\.agents\skills',
    (Join-Path $env:USERPROFILE '.agents\skills')
  ) | Select-Object -Unique
  $names = @('research','implement','diagnosing-bugs','code-review','tdd')
  $out = [ordered]@{}
  foreach ($name in $names) {
    $expected = Join-Path $officialRoot "$name\SKILL.md"
    $expectedHash = if(Test-Path -LiteralPath $expected){ (Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash.ToLowerInvariant() }elseif($knownOfficialHashes.ContainsKey($name)){$knownOfficialHashes[$name]}else{$null}
    $candidates = @($roots | ForEach-Object { Join-Path $_ $name } | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'SKILL.md') })
    $hit = $null; $actualHash = $null
    foreach($candidate in $candidates) {
      $candidateFile=Join-Path $candidate 'SKILL.md'
      $hash=(Get-FileHash -LiteralPath $candidateFile -Algorithm SHA256).Hash.ToLowerInvariant()
      if(-not $expectedHash -or $hash -eq $expectedHash){$hit=(Resolve-Path -LiteralPath $candidate).Path;$actualHash=$hash;break}
    }
    if (-not $hit -and $candidates.Count -gt 0) {
      $hit = (Resolve-Path -LiteralPath $candidates[0]).Path
      $actualHash = (Get-FileHash -LiteralPath (Join-Path $hit 'SKILL.md') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $verified = if ($expectedHash -and $actualHash) { $expectedHash -eq $actualHash } elseif ($hit) { $true } else { $false }
    $out[$name] = [ordered]@{
      available = [bool]$hit
      path = $hit
      official_sha256 = $expectedHash
      actual_sha256 = $actualHash
      verified_official = $verified
    }
  }
  return $out
}
function Get-GitSetup([string]$Project, [bool]$AllowInit, [string]$RequestedPolicy, [string]$RequestedRemote, [bool]$Interactive) {
  $inside = (& git -C $Project rev-parse --is-inside-work-tree 2>$null)
  $initialized = $false
  if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
    if (-not $AllowInit) { return [ordered]@{ repository = $false; initialized_by_herdr = $false; has_commit = $false; target_branch = $null; push_policy = 'manual'; push_remote = $null } }
    & git -C $Project init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed in $Project." }
    $initialized = $true
    $ignorePath = Join-Path $Project '.gitignore'
    $ignoreLines = if(Test-Path $ignorePath){@(Get-Content -LiteralPath $ignorePath)}else{@()}
    foreach($line in @('herdr/','.worktrees/')) { if($ignoreLines -notcontains $line){Add-Content -LiteralPath $ignorePath -Value $line -Encoding utf8} }
  }
  $branch = (& git -C $Project branch --show-current 2>$null).Trim()
  $hasCommit = ((& git -C $Project rev-parse --verify HEAD 2>$null) -and $LASTEXITCODE -eq 0)
  $remotes = @((& git -C $Project remote 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $hasGh = [bool](Get-Command -Name 'gh' -CommandType Application -ErrorAction SilentlyContinue)
  $githubInfo = [ordered]@{
    is_github = $false
    gh_cli_available = $hasGh
    gh_authenticated = $false
    remote_url = $null
    repo = $null
  }
  if ($remotes.Count -gt 0) {
    $firstRemote = if ($remote) { $remote } else { $remotes[0] }
    $remoteUrl = (& git -c core.quotepath=false -C $Project remote get-url $firstRemote 2>$null)
    if ($remoteUrl -match 'github\.com[:/](.+?)(?:\.git)?$') {
      $githubInfo.is_github = $true
      $githubInfo.remote_url = $remoteUrl.Trim()
      $githubInfo.repo = $Matches[1].Trim()
      if ($hasGh) {
        & gh auth status 2>$null
        $githubInfo.gh_authenticated = ($LASTEXITCODE -eq 0)
      }
    }
  }
  if (-not $RequestedPolicy -and $Interactive -and $remotes.Count -gt 0) {
    Write-Host ''
    Write-Host 'Post-merge submission policy:'
    Write-Host '  0) Keep merges local (manual push)'
    for($i=0;$i -lt $remotes.Count;$i++){
      $remName = $remotes[$i]
      Write-Host ('  {0}) Push after merge to {1} (using {2})' -f ($i+1), $remName, (if($githubInfo.is_github -and $hasGh){'GitHub CLI / gh'}else{'git push'}))
    }
    if ($githubInfo.is_github -and $hasGh) {
      $prIndex = $remotes.Count + 1
      Write-Host ('  {0}) Create GitHub Pull Request via gh CLI' -f $prIndex)
    }
    $maxChoice = if ($githubInfo.is_github -and $hasGh) { $remotes.Count + 1 } else { $remotes.Count }
    $choice=Read-Host 'Choice [0]'; $index=0
    if(-not [string]::IsNullOrWhiteSpace($choice)){
      if(-not ([int]::TryParse($choice,[ref]$index) -and $index -ge 0 -and $index -le $maxChoice)){throw 'Invalid post-merge submission selection.'}
      if($index -gt 0 -and $index -le $remotes.Count){$policy='after_merge';$remote=$remotes[$index-1]}
      elseif($index -eq ($remotes.Count + 1)){$policy='create_pr';$remote=$remotes[0]}
    }
  }
  if (@('after_merge','create_pr') -contains $policy) {
    if (-not $remote) { if($remotes.Count -eq 1){$remote=$remotes[0]}else{throw "Push policy $policy requires -PushRemote or exactly one configured git remote."} }
    if ($remotes -notcontains $remote) { throw "Git remote '$remote' is not configured in $Project." }
  } else { $remote=$null }
  return [ordered]@{
    repository = $true
    initialized_by_herdr = $initialized
    has_commit = [bool]$hasCommit
    target_branch = if($branch){$branch}else{$null}
    push_policy = $policy
    push_remote = $remote
    remotes = $remotes
    use_gh_cli = $hasGh
    github = $githubInfo
  }
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
$interactiveSetup = [string]::IsNullOrWhiteSpace($TaskKind) -or [string]::IsNullOrWhiteSpace($VerificationKind) -or [string]::IsNullOrWhiteSpace($ResearchKind)
$git = Get-GitSetup $project (-not $SkipGitInit) $PushPolicy $PushRemote $interactiveSetup
$session = Select-HerdrSession $HerdrSessionName
$supportedKinds = Get-SupportedKinds
$task = Select-Agent 'task' $TaskKind $TaskOpenCodeModel $TaskFullAccessArgs $supportedKinds
$verification = Select-Agent 'verification' $VerificationKind $VerificationOpenCodeModel $VerificationFullAccessArgs $supportedKinds
$research = Select-Agent 'research' $ResearchKind $ResearchOpenCodeModel $ResearchFullAccessArgs $supportedKinds
$herdrDirectory = Join-Path $project 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDirectory | Out-Null
$profilePath = Join-Path $herdrDirectory 'dispatch-profile.json'
if (-not $SkipSkillsInstall) {
  Write-Host 'Starting project skill installation: npx skills@latest add mattpocock/skills'
  Push-Location $project
  try { & npx skills@latest add mattpocock/skills } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { throw "skills installation failed with exit code $LASTEXITCODE. No Herdr profile was written." }
} else { Write-Host 'Skipped skills installation by request.' }
$mattpockSkills = Get-MattpockSkills $project
$profile = [ordered]@{
  schema_version = 3
  initialized_at = (Get-Date -Format o)
  project_root = $project
  herdr_session = [ordered]@{ name = $session; bound_at = (Get-Date -Format o) }
  task_agent = $task
  verification_agent = $verification
  research_agent = $research
  mattpocock_skills = $mattpockSkills
  git = $git
  skills_install_command = 'npx skills@latest add mattpocock/skills'
}
$profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding utf8
Write-Host "Herdr profile written: $profilePath"
Write-Host "Task: $($task.kind)$($(if($task.model){' / ' + $task.model}else{''}))"
Write-Host "Verification: $($verification.kind)$($(if($verification.model){' / ' + $verification.model}else{''}))"
Write-Host "Research: $($research.kind)$($(if($research.model){' / ' + $research.model}else{''}))"
Write-Host "Git: repository=$($git.repository), initialized_by_herdr=$($git.initialized_by_herdr), has_commit=$($git.has_commit), push_policy=$($git.push_policy)$($(if($git.push_remote){' / ' + $git.push_remote}else{''}))"
