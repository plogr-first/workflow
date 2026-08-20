[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$RootCauseKind,
  [string]$RootCauseOpenCodeModel,
  [string[]]$RootCauseFullAccessArgs,
  [string]$RootCauseCommand,
  [string]$TaskKind,
  [string]$TaskOpenCodeModel,
  [string[]]$TaskFullAccessArgs,
  [string]$TaskCommand,
  [string]$VerificationKind,
  [string]$VerificationOpenCodeModel,
  [string[]]$VerificationFullAccessArgs,
  [string]$VerificationCommand,
  [string]$ResearchKind,
  [string]$ResearchOpenCodeModel,
  [string[]]$ResearchFullAccessArgs,
  [string]$ResearchCommand,
  [string]$HerdrSessionName,
  [ValidateSet('manual','after_merge','create_pr')][string]$PushPolicy,
  [string]$PushRemote,
  [string[]]$SkillTargetAgents,
  [switch]$SkipGitInit,
  [switch]$SkipSkillsInstall,
  [switch]$Help
)
$ErrorActionPreference = 'Stop'
if ($Help) {
@"
Herdr Project Initialization

Run from a project root:
  npx plogr-workflow

The interactive flow selects root-cause, task, verification, and research agents, validates
their terminal executables, installs official mattpocock/skills, verifies the engineering skill hashes,
then writes herdr\dispatch-profile.json.

Automation/testing options:
  -ProjectRoot <path>
  -RootCauseKind <kind> -TaskKind <kind> -VerificationKind <kind> -ResearchKind <kind>
  -RootCauseOpenCodeModel <id> -TaskOpenCodeModel <id> -VerificationOpenCodeModel <id> -ResearchOpenCodeModel <id>
  -SkipSkillsInstall
"@ | Write-Output
  exit 0
}

function Show-HerdrBanner {
  $e = [char]27
  function Write-Gradient([string]$text, [int[]]$startRgb, [int[]]$endRgb) {
    $len = $text.Length
    if ($len -le 1) { Write-Host $text; return }
    $out = ""
    for ($i = 0; $i -lt $len; $i++) {
      $ratio = $i / ($len - 1)
      $r = [int]($startRgb[0] + ($endRgb[0] - $startRgb[0]) * $ratio)
      $g = [int]($startRgb[1] + ($endRgb[1] - $startRgb[1]) * $ratio)
      $b = [int]($startRgb[2] + ($endRgb[2] - $startRgb[2]) * $ratio)
      $out += "$e[38;2;${r};${g};${b}m" + $text[$i]
    }
    $out += "$e[0m"
    Write-Host $out
  }

  $bannerLines = @(
    "  ____   _       ___    ____  ____  ",
    " |  _ \ | |     / _ \  / ___||  _ \ ",
    " | |_) || |    | | | || |  _ | |_) |",
    " |  __/ | |___ | |_| || |_| ||  _ < ",
    " |_|    |_____| \___/  \____||_| \_\"
  )

  Write-Host ""
  foreach ($line in $bannerLines) {
    Write-Gradient $line @(56, 189, 248) @(236, 72, 153) # Sky Blue -> Vibrant Magenta Gradient
  }
  Write-Host ""
  Write-Host "  $e[38;2;168;85;247m◆$e[0m $e[1;37mMulti-Agent Orchestrator$e[0m $e[38;2;100;116;139m•$e[0m $e[38;2;56;189;248mZero-Collision Workflows$e[0m $e[38;2;168;85;247m◆$e[0m"
  Write-Host ""
}

function Select-InteractiveMenu {
  param(
    [string]$Title,
    [string]$Subtitle = '',
    [array]$Options,
    [int]$DefaultIndex = 0
  )
  if ([Console]::IsInputRedirected) {
    Write-Host "$Title" -ForegroundColor Cyan
    if ($Subtitle) { Write-Host "$Subtitle" -ForegroundColor DarkGray }
    for ($i = 0; $i -lt $Options.Count; $i++) {
      $label = if ($Options[$i] -is [hashtable] -or $Options[$i] -is [System.Collections.IDictionary]) { $Options[$i].Label } else { $Options[$i] }
      Write-Host ("  [{0}] {1}" -f ($i + 1), $label)
    }
    $choice = Read-Host "Choice (1-$($Options.Count)) [1]"
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $Options.Count) {
      $val = $Options[$idx - 1]
      return if ($val -is [hashtable] -or $val -is [System.Collections.IDictionary]) { $val.Value } else { $val }
    }
    $def = $Options[0]
    return if ($def -is [hashtable] -or $def -is [System.Collections.IDictionary]) { $def.Value } else { $def }
  }

  $cursor = [Math]::Max(0, [Math]::Min($DefaultIndex, $Options.Count - 1))
  $origCursorVisible = $true
  try { $origCursorVisible = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}

  $startTop = [Console]::CursorTop
  while ($true) {
    [Console]::SetCursorPosition(0, $startTop)
    Write-Host "┌─ $Title " -ForegroundColor Cyan -NoNewline
    Write-Host "────────────────────────────────────────────────" -ForegroundColor DarkGray
    if ($Subtitle) {
      Write-Host "│  $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host "│  Use ↑/↓ to navigate • Enter to select" -ForegroundColor DarkYellow
    Write-Host "│" -ForegroundColor DarkGray
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
      $opt = $Options[$i]
      $label = if ($opt -is [hashtable] -or $opt -is [System.Collections.IDictionary]) { $opt.Label } else { $opt }
      if ($i -eq $cursor) {
        Write-Host "│  " -ForegroundColor DarkGray -NoNewline
        Write-Host " ❯ ● " -ForegroundColor Green -NoNewline
        Write-Host "$label" -ForegroundColor White
      } else {
        Write-Host "│  " -ForegroundColor DarkGray -NoNewline
        Write-Host "   ○ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$label" -ForegroundColor Gray
      }
    }
    Write-Host "└─────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'UpArrow' { if ($cursor -gt 0) { $cursor-- } else { $cursor = $Options.Count - 1 } }
      'DownArrow' { if ($cursor -lt ($Options.Count - 1)) { $cursor++ } else { $cursor = 0 } }
      'Enter' {
        try { [Console]::CursorVisible = $origCursorVisible } catch {}
        Write-Host ""
        $sel = $Options[$cursor]
        return if ($sel -is [hashtable] -or $sel -is [System.Collections.IDictionary]) { $sel.Value } else { $sel }
      }
      'Escape' {
        try { [Console]::CursorVisible = $origCursorVisible } catch {}
        throw "Selection cancelled by user."
      }
    }
  }
}

function Get-SupportedKinds {
  $help = ((& herdr agent start --help 2>&1) -join "`n")
  if ($LASTEXITCODE -ne 0) { throw "Unable to read Herdr agent kinds: $help" }
  $match = [regex]::Match($help, '\[possible values:\s*([^\]]+)\]')
  if (-not $match.Success) { throw 'Herdr did not expose supported agent kinds.' }
  return @($match.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Get-OpenCodeModels {
  $defaultModels = @(
    'opencode/deepseek-v4-flash-free',
    'opencode-go/deepseek-v4-flash',
    'opencode/claude-3-7-sonnet',
    'opencode/claude-3-5-sonnet',
    'opencode/gpt-4o'
  )
  try {
    $models = @((& opencode models 2>$null) -replace "`e\[[0-9;]*m", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($models -and $models.Count -gt 0) { return $models }
  } catch {}
  return $defaultModels
}

function Resolve-OpenCodeModel([string]$Requested, [string[]]$Models) {
  $aliases = @{ 'zen'='opencode/deepseek-v4-flash-free'; 'zen-free'='opencode/deepseek-v4-flash-free'; 'deepseek-v4-flash-free'='opencode/deepseek-v4-flash-free'; 'go'='opencode-go/deepseek-v4-flash'; 'go-flash'='opencode-go/deepseek-v4-flash'; 'deepseek-v4-flash'='opencode-go/deepseek-v4-flash' }
  $key = $Requested.Trim().ToLowerInvariant(); if($aliases.ContainsKey($key)){$key=$aliases[$key]}
  $exact=@($Models|Where-Object{$_.Equals($key,[StringComparison]::OrdinalIgnoreCase)}); if($exact.Count -eq 1){return $exact[0]}
  $normal=$key -replace '[^a-z0-9]',''; $fuzzy=@($Models|Where-Object{(($_ -replace '[^a-z0-9]','').ToLowerInvariant()).Contains($normal)})
  if($fuzzy.Count -eq 1){return $fuzzy[0]}; if($fuzzy.Count -gt 1){throw "OpenCode model '$Requested' is ambiguous: $($fuzzy -join ', ')"}; throw "OpenCode model '$Requested' is not currently available."
}

function Select-OpenCodeModelInteractive([string]$Role, [string[]]$Models) {
  $options = @($Models | ForEach-Object { @{ Label = $_; Value = $_ } })
  return Select-InteractiveMenu -Title "Select OpenCode Model for $Role" -Subtitle "Choose the LLM backend for this agent" -Options $options
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

  $options = @()
  foreach ($s in $sessions) {
    $options += @{ Label = "Use existing session: $s"; Value = $s }
  }
  $options += @{ Label = "[+] Create a new named session"; Value = '__NEW__' }

  $choice = Select-InteractiveMenu -Title "Select Herdr Persistent Session" -Subtitle "All workflows for this project will run isolated in this session" -Options $options
  if ($choice -eq '__NEW__') {
    Write-Host "Enter new Herdr session name (e.g. dev, project-flow):" -ForegroundColor Cyan
    $newName = (Read-Host "Session Name").Trim().ToLowerInvariant()
    if ($newName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$') { throw "Invalid session name '$newName'." }
    if ($sessions -notcontains $newName) {
      $null = & herdr --session $newName status server 2>&1
      if ($LASTEXITCODE -ne 0) { throw "Unable to create or open Herdr session '$newName'." }
    }
    return $newName
  }
  return $choice
}

function Install-HerdrSkills([string]$Project, [string[]]$TargetAgents, [bool]$SkipInstall) {
  if ($SkipInstall) {
    Write-Host "Skipped skills installation by request." -ForegroundColor DarkGray
    return
  }

  $agentArgs = if ($TargetAgents -and $TargetAgents.Count) {
    ($TargetAgents | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | ForEach-Object {
      switch ($_.ToLowerInvariant()) {
        'claude' { 'claude-code' }
        'claude-code' { 'claude-code' }
        'codex' { 'codex' }
        'opencode' { 'opencode' }
        'gemini' { 'gemini' }
        'cursor' { 'cursor' }
        default { $_ }
      }
    }
  } else { @('*') }

  Write-Host "Installing Matt Pocock skills via npx skills (Agents: $($agentArgs -join ', '))..." -ForegroundColor Cyan
  Push-Location $Project
  try {
    & npx skills@latest add mattpocock/skills --copy -a $agentArgs -y 2>&1 | Out-Null
  } catch {
    Write-Host "Notice: npx skills install finished, ensuring bundled fallback..." -ForegroundColor DarkGray
  } finally {
    Pop-Location
  }

  # Install bundled audit-suite to project and agent directories
  $bundledAuditSuite = Join-Path $PSScriptRoot '..\bundled_skills\audit-suite'
  if (Test-Path -LiteralPath $bundledAuditSuite) {
    Write-Host "Deploying bundled audit-suite skill to project & agent directories..." -ForegroundColor Cyan
    $destinations = @(
      (Join-Path $Project '.agents\skills\audit-suite'),
      (Join-Path $env:USERPROFILE '.agents\skills\audit-suite')
    )
    foreach ($ag in $agentArgs) {
      if ($ag -eq 'claude-code' -or $ag -eq '*') { $destinations += Join-Path $Project '.claude\skills\audit-suite' }
      if ($ag -eq 'codex' -or $ag -eq '*') { $destinations += Join-Path $Project '.codex\skills\audit-suite' }
      if ($ag -eq 'opencode' -or $ag -eq '*') { $destinations += Join-Path $Project '.opencode\skills\audit-suite' }
      if ($ag -eq 'cursor' -or $ag -eq '*') { $destinations += Join-Path $Project '.cursor\skills\audit-suite' }
      if ($ag -eq 'gemini' -or $ag -eq '*') { $destinations += Join-Path $Project '.gemini\skills\audit-suite' }
    }
    foreach ($dest in ($destinations | Select-Object -Unique)) {
      try {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Path "$bundledAuditSuite\*" -Destination $dest -Recurse -Force
      } catch {}
    }
  }
}

function Get-MattpockSkills([string]$Project) {
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
    (Join-Path $Project '.claude\skills'),
    (Join-Path $Project '.codex\skills'),
    (Join-Path $Project '.opencode\skills'),
    (Join-Path $Project '.cursor\skills'),
    (Join-Path $Project '.gemini\skills'),
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
      if($expectedHash -and $hash -eq $expectedHash){$hit=$candidateFile;$actualHash=$hash;break}
      if(-not $hit){$hit=$candidateFile;$actualHash=$hash}
    }
    $verified = ($expectedHash -and $actualHash -eq $expectedHash)
    $out[$name] = [ordered]@{
      available = [bool]$hit
      path = $hit
      hash = $actualHash
      verified_official = $verified
      expected_hash = $expectedHash
    }
  }

  # Check audit-suite (project agent folders, global user folder, or bundled skill)
  $auditRoots = $roots + @(Join-Path $PSScriptRoot '..\bundled_skills')
  $auditCandidates = @($auditRoots | ForEach-Object { Join-Path $_ 'audit-suite\SKILL.md' } | Where-Object { Test-Path -LiteralPath $_ })
  $hasAuditSuite = ($auditCandidates.Count -gt 0)
  $out['audit_suite'] = [ordered]@{
    available = [bool]$hasAuditSuite
    path = if ($hasAuditSuite) { $auditCandidates[0] } else { $null }
    verified_official = $true
  }
  return $out
}

function Get-GitSetup([string]$Project, [bool]$AllowInit, [string]$RequestedPolicy, [string]$RequestedRemote, [bool]$Interactive) {
  $isGit = (& git -c core.quotepath=false -C $Project rev-parse --is-inside-work-tree 2>$null)
  $initialized = $false
  if ($LASTEXITCODE -ne 0 -or [string]$isGit -ne 'true') {
    if (-not $AllowInit) {
      return [ordered]@{ repository = $false; initialized_by_herdr = $false; has_commit = $false; target_branch = $null; push_policy = 'manual'; push_remote = $null; remotes = @(); use_gh_cli = $false; github = $null }
    }
    & git -c core.quotepath=false -C $Project init 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize Git repository in $Project." }
    $initialized = $true
  }
  $head = (& git -c core.quotepath=false -C $Project rev-parse --verify HEAD 2>$null)
  $hasCommit = ($LASTEXITCODE -eq 0)
  $branch = if ($hasCommit) { (& git -c core.quotepath=false -C $Project rev-parse --abbrev-ref HEAD 2>$null) } else { $null }
  $remotes = @((& git -c core.quotepath=false -C $Project remote 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $hasGh = [bool](Get-Command -Name 'gh' -CommandType Application -ErrorAction SilentlyContinue)
  $policy = if ($RequestedPolicy) { $RequestedPolicy } else { 'manual' }
  $remote = $RequestedRemote

  $githubInfo = [ordered]@{ is_github = $false; remote_url = $null; repo = $null; gh_authenticated = $false }
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
    $options = @()
    $options += @{ Label = "Keep merges local (manual push / no auto-push)"; Value = 'manual' }
    foreach ($r in $remotes) {
      $options += @{ Label = "Push after merge to $r (using git/gh)"; Value = "push:$r" }
    }
    if ($githubInfo.is_github -and $hasGh) {
      $options += @{ Label = "Create GitHub Pull Request via gh CLI automatically"; Value = 'create_pr' }
    }

    $chosen = Select-InteractiveMenu -Title "Select Post-Merge Submission Policy" -Subtitle "How should Herdr handle code after independent verification passes?" -Options $options
    if ($chosen -eq 'manual') {
      $policy = 'manual'
      $remote = $null
    } elseif ($chosen -eq 'create_pr') {
      $policy = 'create_pr'
      $remote = $remotes[0]
    } elseif ($chosen -like 'push:*') {
      $policy = 'after_merge'
      $remote = $chosen.Substring(5)
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
  if (-not $Interactive) { throw "Custom agent '$Kind' requires full-access launch arguments." }
  Write-Host "Enter the full-access launch arguments for '$Kind' (space separated, e.g. --yolo):" -ForegroundColor Cyan
  $raw = Read-Host "Full Access Args"
  $args = @($raw -split '\s+' | Where-Object { $_ })
  if (-not $args.Count) { throw "Custom agent '$Kind' requires explicit full-access launch arguments." }
  return $args
}

function Select-Agent([string]$RoleTitle, [string]$RoleKey, [string]$RequestedKind, [string]$RequestedModel, [string[]]$ProvidedArgs, [string]$CustomCommand, [string[]]$SupportedKinds) {
  $interactive = [string]::IsNullOrWhiteSpace($RequestedKind)
  if ($interactive) {
    $options = @(
      @{ Label = "claude   - Anthropic Claude Code CLI (Recommended for research/audit)"; Value = 'claude' },
      @{ Label = "codex    - OpenAI Codex CLI (Recommended for verification)"; Value = 'codex' },
      @{ Label = "opencode - OpenCode Full-Screen TUI / DeepSeek Models"; Value = 'opencode' },
      @{ Label = "gemini   - Google Gemini CLI"; Value = 'gemini' },
      @{ Label = "custom   - Custom command executable (User defined in PowerShell)"; Value = 'custom' }
    )
    $chosen = Select-InteractiveMenu -Title "Configure $RoleTitle ($RoleKey)" -Subtitle "Select the AI Agent engine for this specific workflow node" -Options $options
    if ($chosen -eq 'custom') {
      Write-Host "Enter custom executable or PowerShell command for ${RoleTitle}:" -ForegroundColor Cyan
      $cmd = (Read-Host "Command").Trim()
      if (-not $cmd) { throw "Custom command for $RoleTitle cannot be empty." }
      $RequestedKind = $cmd
    } else {
      $RequestedKind = $chosen
    }
  }

  $kind = $RequestedKind.Trim().ToLowerInvariant()
  $executable = $kind
  if ($SupportedKinds -contains $kind) {
    $executable = Assert-TerminalAgent $kind $SupportedKinds
  } else {
    $cmdObj = Get-Command -Name $kind -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmdObj) { $executable = $cmdObj.Source }
  }

  $model = $null
  if ($kind -eq 'opencode') {
    $models = Get-OpenCodeModels
    if ([string]::IsNullOrWhiteSpace($RequestedModel)) {
      $model = Select-OpenCodeModelInteractive $RoleTitle $models
    } else { $model = Resolve-OpenCodeModel $RequestedModel $models }
  }

  return [ordered]@{
    role = $RoleKey
    kind = $kind
    executable = $executable
    model = $model
    full_access_args = @(Get-FullAccessArgs $kind $ProvidedArgs $interactive)
  }
}

# --- Main Execution Flow ---
Show-HerdrBanner

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$interactiveSetup = [string]::IsNullOrWhiteSpace($TaskKind) -or [string]::IsNullOrWhiteSpace($VerificationKind) -or [string]::IsNullOrWhiteSpace($ResearchKind)
$git = Get-GitSetup $project (-not $SkipGitInit) $PushPolicy $PushRemote $interactiveSetup
$session = Select-HerdrSession $HerdrSessionName
$supportedKinds = Get-SupportedKinds

$rootCause = Select-Agent 'Root-Cause & Audit Agent' 'root_cause' $RootCauseKind $RootCauseOpenCodeModel $RootCauseFullAccessArgs $RootCauseCommand $supportedKinds
$task = Select-Agent 'Task & Implementation Agent' 'task' $TaskKind $TaskOpenCodeModel $TaskFullAccessArgs $TaskCommand $supportedKinds
$verification = Select-Agent 'Verification & Integration Agent' 'verification' $VerificationKind $VerificationOpenCodeModel $VerificationFullAccessArgs $VerificationCommand $supportedKinds
$research = Select-Agent 'Deep Research Agent' 'research' $ResearchKind $ResearchOpenCodeModel $ResearchFullAccessArgs $ResearchCommand $supportedKinds

# Interactive Skill Target Agents Selection
$configuredAgents = @($rootCause.kind, $task.kind, $verification.kind, $research.kind) | Select-Object -Unique
$targetAgents = $SkillTargetAgents
if (-not $targetAgents -and $interactiveSetup) {
  $skillOptions = @(
    @{ Label = "Install for all configured workflow agents ($($configuredAgents -join ', ')) [Recommended]"; Value = 'configured' },
    @{ Label = "Install for ALL supported agent tools (* - Claude, Codex, OpenCode, Cursor, Gemini)"; Value = 'all' },
    @{ Label = "Claude Code only (claude-code)"; Value = 'claude-code' },
    @{ Label = "Codex only (codex)"; Value = 'codex' },
    @{ Label = "OpenCode only (opencode)"; Value = 'opencode' },
    @{ Label = "Universal .agents directory only (.agents/skills)"; Value = 'agents_only' }
  )
  $chosenSkillTarget = Select-InteractiveMenu -Title "Select Target Agents for Project Skill Installation" -Subtitle "Which agent tool directories should Matt Pocock & Audit-Suite skills be installed to?" -Options $skillOptions
  $targetAgents = switch ($chosenSkillTarget) {
    'configured' { $configuredAgents }
    'all' { @('*') }
    'agents_only' { @() }
    default { @($chosenSkillTarget) }
  }
}

Install-HerdrSkills $project $targetAgents $SkipSkillsInstall

$herdrDirectory = Join-Path $project 'herdr'
New-Item -ItemType Directory -Force -Path $herdrDirectory | Out-Null
$profilePath = Join-Path $herdrDirectory 'dispatch-profile.json'
$mattpockSkills = Get-MattpockSkills $project

$profile = [ordered]@{
  schema_version = 4
  initialized_at = (Get-Date -Format o)
  project_root = $project
  herdr_session = [ordered]@{ name = $session; bound_at = (Get-Date -Format o) }
  root_cause_agent = $rootCause
  task_agent = $task
  verification_agent = $verification
  research_agent = $research
  target_skill_agents = if($targetAgents){@($targetAgents)}else{@('*')}
  mattpocock_skills = $mattpockSkills
  git = $git
  skills_install_command = 'npx skills@latest add mattpocock/skills'
}
$profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding utf8

Write-Host ""
Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│  HERDR PROFILE INITIALIZED SUCCESSFULLY                     │" -ForegroundColor Green
Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Green
Write-Host "  Profile: $profilePath" -ForegroundColor White
Write-Host "  Session: $session" -ForegroundColor Cyan
Write-Host "  Root-Cause Agent: $($rootCause.kind)$($(if($rootCause.model){' / ' + $rootCause.model}else{''}))" -ForegroundColor White
Write-Host "  Task Agent:       $($task.kind)$($(if($task.model){' / ' + $task.model}else{''}))" -ForegroundColor White
Write-Host "  Verifier Agent:   $($verification.kind)$($(if($verification.model){' / ' + $verification.model}else{''}))" -ForegroundColor White
Write-Host "  Research Agent:   $($research.kind)$($(if($research.model){' / ' + $research.model}else{''}))" -ForegroundColor White
Write-Host "  Skill Target:     $(if($targetAgents){$targetAgents -join ', '}else{'all (*)'})" -ForegroundColor White
Write-Host ""

