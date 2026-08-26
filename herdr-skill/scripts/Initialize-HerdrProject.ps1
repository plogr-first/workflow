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
  plogr init

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

  function Get-OptionValue($opt) {
    if ($opt -is [hashtable] -or $opt -is [System.Collections.IDictionary]) { return $opt.Value }
    return $opt
  }

  function Get-OptionLabel($opt) {
    if ($opt -is [hashtable] -or $opt -is [System.Collections.IDictionary]) { return $opt.Label }
    return $opt
  }

  if ([Console]::IsInputRedirected) {
    Write-Host "$Title" -ForegroundColor Cyan
    if ($Subtitle) { Write-Host "$Subtitle" -ForegroundColor DarkGray }
    for ($i = 0; $i -lt $Options.Count; $i++) {
      Write-Host ("  [{0}] {1}" -f ($i + 1), (Get-OptionLabel $Options[$i]))
    }
    $choice = Read-Host "Choice (1-$($Options.Count)) [1]"
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $Options.Count) {
      return (Get-OptionValue $Options[$idx - 1])
    }
    return (Get-OptionValue $Options[0])
  }

  $cursor = [Math]::Max(0, [Math]::Min($DefaultIndex, $Options.Count - 1))
  $origCursorVisible = $true
  try { $origCursorVisible = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}

  $e = [char]27
  $linesRendered = 0

  try {
    while ($true) {
      if ($linesRendered -gt 0) {
        try {
          $targetTop = [Console]::CursorTop - $linesRendered
          if ($targetTop -ge 0) {
            [Console]::SetCursorPosition(0, $targetTop)
          } else {
            Write-Host "$e[${linesRendered}F" -NoNewline
          }
        } catch {
          Write-Host "$e[${linesRendered}F" -NoNewline
        }
        Write-Host "$e[J" -NoNewline
      }

      $linesCount = 0

      Write-Host "┌─ $Title $e[K" -ForegroundColor Cyan -NoNewline
      Write-Host "────────────────────────────────────────────────$e[K" -ForegroundColor DarkGray
      $linesCount++

      if ($Subtitle) {
        Write-Host "│  $Subtitle$e[K" -ForegroundColor DarkGray
        $linesCount++
      }

      Write-Host "│  Use ↑/↓ to navigate • Enter to select$e[K" -ForegroundColor DarkYellow
      $linesCount++

      Write-Host "│$e[K" -ForegroundColor DarkGray
      $linesCount++

      for ($i = 0; $i -lt $Options.Count; $i++) {
        $label = Get-OptionLabel $Options[$i]
        if ($i -eq $cursor) {
          Write-Host "│  " -ForegroundColor DarkGray -NoNewline
          Write-Host " ❯ ● " -ForegroundColor Green -NoNewline
          Write-Host "$label$e[K" -ForegroundColor White
        } else {
          Write-Host "│  " -ForegroundColor DarkGray -NoNewline
          Write-Host "   ○ " -ForegroundColor DarkGray -NoNewline
          Write-Host "$label$e[K" -ForegroundColor Gray
        }
        $linesCount++
      }

      Write-Host "└─────────────────────────────────────────────────────$e[K" -ForegroundColor DarkGray
      $linesCount++

      $linesRendered = $linesCount

      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow' { if ($cursor -gt 0) { $cursor-- } else { $cursor = $Options.Count - 1 } }
        'DownArrow' { if ($cursor -lt ($Options.Count - 1)) { $cursor++ } else { $cursor = 0 } }
        'Enter' {
          Write-Host ""
          return (Get-OptionValue $Options[$cursor])
        }
        'Escape' {
          throw "Selection cancelled by user."
        }
      }
    }
  } finally {
    try { [Console]::CursorVisible = $origCursorVisible } catch {}
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
  $models = [System.Collections.Generic.List[string]]::new()

  # 1. Dynamically execute `opencode models` CLI to get live registered models
  try {
    $cliModels = @((& opencode models 2>$null) -replace "`e\[[0-9;]*m", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('-') })
    foreach ($cm in $cliModels) {
      if ($cm -match '^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$' -and -not $models.Contains($cm)) {
        $models.Add($cm)
      }
    }
  } catch {}

  # 2. Dynamically read custom models from ~/.config/opencode/opencode.jsonc and opencode.json
  $configPaths = @(
    (Join-Path $env:USERPROFILE '.config\opencode\opencode.jsonc'),
    (Join-Path $env:USERPROFILE '.config\opencode\opencode.json'),
    (Join-Path $env:USERPROFILE '.opencode\opencode.json'),
    (Join-Path $env:USERPROFILE '.opencode\opencode.jsonc'),
    (Join-Path $env:APPDATA 'opencode\opencode.json'),
    (Join-Path $env:LOCALAPPDATA 'opencode\opencode.json')
  )

  foreach ($cfg in $configPaths) {
    if (Test-Path -LiteralPath $cfg) {
      try {
        $raw = Get-Content -LiteralPath $cfg -Raw
        $cleanJson = $raw -replace '(?m)^\s*//.*$', ''
        $data = $cleanJson | ConvertFrom-Json
        if ($data.provider) {
          foreach ($provProp in $data.provider.psobject.Properties) {
            $provName = $provProp.Name
            $provVal = $provProp.Value
            if ($provVal.models) {
              foreach ($mProp in $provVal.models.psobject.Properties) {
                $mName = $mProp.Name
                $fullModelId = "${provName}/${mName}"
                if (-not $models.Contains($fullModelId)) {
                  $models.Add($fullModelId)
                }
              }
            }
          }
        }
      } catch {}
    }
  }

  # 3. Add mainstream standard official models and Go/Zen/Pixel fallbacks
  $standardModels = @(
    'opencode-go/deepseek-v4-flash',
    'opencode-go/gpt-5.6-luna',
    'opencode-go/qwen3.8-max',
    'opencode-go/kimi-k2.7-code',
    'opencode-go/glm-5.3',
    'opencode-go/deepseek-v4-pro',
    'opencode-go/grok-4.5',
    'opencode-go/mimo-v2.5',
    'opencode-go/minimax-m3',
    'pixel/gpt-5.6-sol',
    'pixel/gpt-5.6-Terra',
    'pixel/gpt-5.6-Luna',
    'opencode/deepseek-v4-flash-free',
    'opencode/hy3-free',
    'opencode/big-pickle',
    'deepseek/deepseek-chat',
    'deepseek/deepseek-reasoner',
    'anthropic/claude-3-7-sonnet',
    'anthropic/claude-3-5-sonnet',
    'openai/o3-mini',
    'openai/o1',
    'openai/gpt-4o',
    'google/gemini-2.5-pro',
    'google/gemini-2.0-flash'
  )

  foreach ($sm in $standardModels) {
    if (-not $models.Contains($sm)) {
      $models.Add($sm)
    }
  }

  return @($models)
}

function Resolve-OpenCodeModel([string]$Requested, [string[]]$Models) {
  $aliases = @{
    'zen'='opencode/deepseek-v4-flash-free'; 'zen-free'='opencode/deepseek-v4-flash-free'; 'deepseek-v4-flash-free'='opencode/deepseek-v4-flash-free'
    'go'='opencode-go/deepseek-v4-flash'; 'go-flash'='opencode-go/deepseek-v4-flash'; 'deepseek-v4-flash'='opencode-go/deepseek-v4-flash'
    'go-pro'='opencode-go/deepseek-v4-pro'; 'flash'='opencode-go/deepseek-v4-flash'
    'sol'='pixel/gpt-5.6-sol'; 'terra'='pixel/gpt-5.6-Terra'; 'luna'='pixel/gpt-5.6-Luna'
    'glm'='opencode-go/glm-5.3'; 'glm-5.3'='opencode-go/glm-5.3'; 'glm-5.2'='opencode-go/glm-5.2'
    'qwen'='opencode-go/qwen3.8-max'; 'qwen3.8'='opencode-go/qwen3.8-max'; 'qwen3.7'='opencode-go/qwen3.7-max'
    'kimi'='opencode-go/kimi-k2.7-code'; 'kimi-code'='opencode-go/kimi-k2.7-code'; 'kimi-k3'='opencode-go/kimi-k3'
    'grok'='opencode-go/grok-4.5'; 'mimo'='opencode-go/mimo-v2.5'; 'minimax'='opencode-go/minimax-m3'
    'claude-3-7'='anthropic/claude-3-7-sonnet'; 'claude-3-7-sonnet'='anthropic/claude-3-7-sonnet'; 'sonnet-3.7'='anthropic/claude-3-7-sonnet'
    'claude-3-5'='anthropic/claude-3-5-sonnet'; 'claude-3-5-sonnet'='anthropic/claude-3-5-sonnet'; 'sonnet-3.5'='anthropic/claude-3-5-sonnet'
    'r1'='deepseek/deepseek-reasoner'; 'reasoner'='deepseek/deepseek-reasoner'; 'deepseek-r1'='deepseek/deepseek-reasoner'
    'deepseek'='deepseek/deepseek-chat'; 'deepseek-v3'='deepseek/deepseek-chat'; 'chat'='deepseek/deepseek-chat'
    'o3-mini'='openai/o3-mini'; 'o3'='openai/o3-mini'
    'o1'='openai/o1'; 'o1-preview'='openai/o1'
    'gpt-4o'='openai/gpt-4o'; '4o'='openai/gpt-4o'
    'gemini-pro'='google/gemini-2.5-pro'; 'gemini-2.5-pro'='google/gemini-2.5-pro'
    'gemini-flash'='google/gemini-2.0-flash'; 'gemini-2.0-flash'='google/gemini-2.0-flash'
  }
  $key = $Requested.Trim().ToLowerInvariant(); if($aliases.ContainsKey($key)){$key=$aliases[$key]}
  $exact=@($Models|Where-Object{$_.Equals($key,[StringComparison]::OrdinalIgnoreCase)}); if($exact.Count -eq 1){return $exact[0]}
  $normal=$key -replace '[^a-z0-9]',''; $fuzzy=@($Models|Where-Object{(($_ -replace '[^a-z0-9]','').ToLowerInvariant()).Contains($normal)})
  if($fuzzy.Count -eq 1){return $fuzzy[0]}; if($fuzzy.Count -gt 1){throw "OpenCode model '$Requested' is ambiguous: $($fuzzy -join ', ')"}; return $Requested.Trim()
}

function Select-OpenCodeModelInteractive([string]$Role, [string[]]$Models) {
  $chineseMap = @{
    'opencode-go/deepseek-v4-flash'            = 'Go 专区 • DeepSeek V4 Flash 极速闪电推理'
    'opencode-go/gpt-5.6-luna'                = 'Go 专区 • GPT-5.6 Luna 深度思考编程'
    'opencode-go/qwen3.8-max'                 = 'Go 专区 • 通义千问 Qwen 3.8 Max 旗舰模型'
    'opencode-go/kimi-k2.7-code'              = 'Go 专区 • Kimi K2.7 Code 长上下文代码模型'
    'opencode-go/glm-5.3'                     = 'Go 专区 • 智谱 GLM 5.3 编程强化模型'
    'opencode-go/deepseek-v4-pro'             = 'Go 专区 • DeepSeek V4 Pro 专家模型'
    'opencode-go/grok-4.5'                    = 'Go 专区 • xAI Grok 4.5 极速模型'
    'opencode-go/mimo-v2.5'                   = 'Go 专区 • Mimo V2.5 多模态模型'
    'opencode-go/minimax-m3'                  = 'Go 专区 • MiniMax M3 旗舰模型'
    'pixel/gpt-5.6-sol'                       = 'Pixel 专区 • GPT-5.6 Sol (用户自定义 Provider)'
    'pixel/gpt-5.6-Terra'                     = 'Pixel 专区 • GPT-5.6 Terra (用户自定义 Provider)'
    'pixel/gpt-5.6-Luna'                      = 'Pixel 专区 • GPT-5.6 Luna (用户自定义 Provider)'
    'opencode/deepseek-v4-flash-free'         = 'Zen/Free 专区 • DeepSeek V4 Flash 免费加速'
    'opencode/hy3-free'                       = 'Zen/Free 专区 • HY3 免费加速模型'
    'opencode/big-pickle'                     = 'Zen/Free 专区 • Big-Pickle 免费模型'
    'deepseek/deepseek-chat'                  = 'DeepSeek 官方 • V3 / Chat 高速代码模型'
    'deepseek/deepseek-reasoner'              = 'DeepSeek 官方 • R1 / Reasoner 强推理'
    'anthropic/claude-3-7-sonnet'             = 'Claude 官方 • 3.7 Sonnet 思考模式旗舰'
    'anthropic/claude-3-5-sonnet'             = 'Claude 官方 • 3.5 Sonnet'
    'openai/o3-mini'                          = 'OpenAI 官方 • o3-mini 编程推理'
    'openai/o1'                               = 'OpenAI 官方 • o1 复杂规划'
    'openai/gpt-4o'                           = 'OpenAI 官方 • GPT-4o 多模态旗舰'
    'google/gemini-2.5-pro'                   = 'Google 官方 • Gemini 2.5 Pro 极长上下文'
    'google/gemini-2.0-flash'                 = 'Google 官方 • Gemini 2.0 Flash 极速响应'
  }
  $options = @()
  foreach ($m in $Models) {
    $desc = if ($chineseMap.ContainsKey($m)) { $chineseMap[$m] } elseif ($m -match '^opencode-go/') { "Go 高速专区模型" } elseif ($m -match '^opencode/') { "Zen/Free 免费专区模型" } elseif ($m -match '^pixel/') { "Pixel 自定义模型" } else { "OpenCode 兼容模型" }
    $options += @{ Label = "$m  ($desc)"; Value = $m }
  }
  $options += @{ Label = "[+] 手动输入其他 OpenCode 模型 ID (provider/model-name)"; Value = '__CUSTOM__' }

  $chosen = Select-InteractiveMenu -Title "配置 OpenCode 模型 ($Role)" -Subtitle "请选择此 Agent 节点底层的 LLM 大语言模型 (支持 Go / Zen / Pixel 自定义模型)" -Options $options
  if ($chosen -eq '__CUSTOM__') {
    Write-Host "请输入 OpenCode 模型标识符 (例如 opencode-go/deepseek-v4-flash 或 pixel/gpt-5.6-sol):" -ForegroundColor Cyan
    $customModel = (Read-Host "模型 ID").Trim()
    if (-not $customModel) { throw "OpenCode 模型 ID 不能为空。" }
    return $customModel
  }
  return $chosen
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
    $cleanReq = $Requested.Trim().ToLowerInvariant()
    if ($cleanReq -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$') { throw "Invalid session name '$Requested'." }
    if ($sessions -notcontains $cleanReq) {
      $null = & herdr --session $cleanReq status server 2>&1
      if ($LASTEXITCODE -ne 0) { throw "Unable to create or open Herdr session '$cleanReq'." }
    }
    return $cleanReq
  }
  if ($sessions.Count -eq 1) { return $sessions[0] }

  $options = @()
  foreach ($s in $sessions) {
    $options += @{ Label = "使用已有 Session: $s (在现有隔离会话中运行)"; Value = $s }
  }
  $options += @{ Label = "[+] 创建新的命名 Session (新建独立会话，杜绝多任务碰撞)"; Value = '__NEW__' }

  $choice = Select-InteractiveMenu -Title "选择 Herdr 持久化 Session (会话物理隔离)" -Subtitle "本项目的所有多 Agent 工作流将在该独立隔离 Session 中安全运行" -Options $options
  if ($choice -eq '__NEW__') {
    Write-Host "请输入新的 Herdr Session 名称 (例如 dev, project-flow):" -ForegroundColor Cyan
    $newName = (Read-Host "Session 名称").Trim().ToLowerInvariant()
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
    Write-Host "Skipped external engineering-skill acquisition; deploying bundled workflow skills and registry." -ForegroundColor DarkGray
  }

  $agentArgs = if ($null -ne $TargetAgents) {
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

  # 1. Deploy AGENTS.md and CLAUDE.md progressive disclosure index
  $indexContent = @"
# Agent Skills

This file is a progressive-disclosure skill index.

## Universal skill

Read this local skill before taking action:

- [Karpathy Guidelines](./.agents/skills/karpathy-guidelines/SKILL.md)

## Master Orchestrator skill

Trigger with `/plogr` (or `/herdr`) to dispatch durable multi-agent workflows:

- [Plogr Multi-Agent Orchestrator](./.agents/skills/plogr/SKILL.md)

## Conditional skills

Load only the skill matching the active task:

- Feature implementation: [Task Agent](./.agents/skills/task-agent/SKILL.md)
- Bug diagnosis or repair: [Bugfix Agent](./.agents/skills/bugfix-agent/SKILL.md)
- Read-only investigation: [Research Agent](./.agents/skills/research-agent/SKILL.md)
- Candidate validation or integration: [Verification Agent](./.agents/skills/verification-agent/SKILL.md)

Do not load all skills at once. After loading a skill, read its ``references/`` files only when the current phase requires them. Do not load unrelated role skills.
"@

  $agentsMdPath = Join-Path $Project 'AGENTS.md'
  if (-not (Test-Path -LiteralPath $agentsMdPath)) {
    Write-Host "Deploying progressive disclosure index: AGENTS.md..." -ForegroundColor Cyan
    Set-Content -LiteralPath $agentsMdPath -Value $indexContent -Encoding utf8
  }

  $claudeMdPath = Join-Path $Project 'CLAUDE.md'
  if (-not (Test-Path -LiteralPath $claudeMdPath)) {
    Write-Host "Deploying progressive disclosure index: CLAUDE.md..." -ForegroundColor Cyan
    Set-Content -LiteralPath $claudeMdPath -Value $indexContent -Encoding utf8
  }

  # 2. Deploy bundled progressive skills & audit-suite
  $bundledSkillsDir = Join-Path $PSScriptRoot '..\bundled_skills'
  $workflowSkillsDir = Join-Path (Split-Path (Split-Path $PSScriptRoot)) '.agents\skills'

  $skillNames = @('plogr', 'herdr', 'karpathy-guidelines', 'task-agent', 'bugfix-agent', 'research-agent', 'verification-agent', 'audit-suite')
  $excludedPayloadNames = @('node_modules', '.git', 'tests_formal_audit')
  function Copy-SkillPayload([string]$Source, [string]$Destination) {
    # Core skill destinations are managed deployment targets. Recreate them so
    # stale files from older payload layouts (especially the herdr alias) cannot
    # remain executable after an upgrade. This never touches project rules or
    # files outside the skill destination.
    if (Test-Path -LiteralPath $Destination) {
      Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Where-Object { $excludedPayloadNames -notcontains $_.Name } | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
  }
  Write-Host "Deploying bundled progressive workflow skills to project & agent directories..." -ForegroundColor Cyan

  foreach ($s in $skillNames) {
    # plogr/herdr are this package itself.  Prefer the canonical package root
    # even when a stale bundled copy happens to exist.
    if ($s -eq 'plogr') {
      $srcPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    } else {
      $srcPath = Join-Path $bundledSkillsDir $s
      if (-not (Test-Path -LiteralPath $srcPath) -and (Test-Path -LiteralPath $workflowSkillsDir)) {
        $srcPath = Join-Path $workflowSkillsDir $s
      }
    }
    if (Test-Path -LiteralPath $srcPath) {
      $destinations = @((Join-Path $Project ".agents\skills\$s"))
      foreach ($ag in $agentArgs) {
        if ($ag -eq 'agents_only') { continue }
        if ($ag -eq 'claude-code' -or $ag -eq '*') {
          $destinations += Join-Path $Project ".claude\skills\$s"
        }
        if ($ag -eq 'codex' -or $ag -eq '*') {
          $destinations += Join-Path $Project ".codex\skills\$s"
        }
        if ($ag -eq 'opencode' -or $ag -eq '*') { $destinations += Join-Path $Project ".opencode\skills\$s" }
        if ($ag -eq 'cursor' -or $ag -eq '*') { $destinations += Join-Path $Project ".cursor\skills\$s" }
        if ($ag -eq 'gemini' -or $ag -eq '*') { $destinations += Join-Path $Project ".gemini\skills\$s" }
      }
      $copyFailures = [System.Collections.Generic.List[string]]::new()
      foreach ($dest in ($destinations | Select-Object -Unique)) {
        try {
          if (-not (Test-Path -LiteralPath $dest)) {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
          }
          Copy-SkillPayload $srcPath $dest
        } catch { $copyFailures.Add("${dest}: $($_.Exception.Message)") }
      }
  if ($copyFailures.Count) { throw "Skill '$s' deployment failed:`n$($copyFailures -join "`n")" }
    }
  }

  # The directory layout is native discovery for Claude/OpenCode/Gemini. This
  # manifest makes registration explicit and gives the dispatcher a durable
  # integrity contract instead of treating an arbitrary folder as a skill.
  $registrationPath = Join-Path $Project '.agents\project-skills.json'
  $platformRoots = [ordered]@{
    agents   = (Join-Path $Project '.agents\skills')
    claude   = (Join-Path $Project '.claude\skills')
    codex    = (Join-Path $Project '.codex\skills')
    opencode = (Join-Path $Project '.opencode\skills')
    gemini   = (Join-Path $Project '.gemini\skills')
    cursor   = (Join-Path $Project '.cursor\skills')
  }
  $registrations = foreach ($platform in $platformRoots.Keys) {
    $root = $platformRoots[$platform]
    if (Test-Path -LiteralPath $root) {
      $registeredSkills = @($skillNames | Where-Object { Test-Path -LiteralPath (Join-Path (Join-Path $root $_) 'SKILL.md') })
      $files = foreach ($skill in $registeredSkills) {
        Get-ChildItem -LiteralPath (Join-Path $root $skill) -File -Recurse | Sort-Object FullName | ForEach-Object {
          [ordered]@{
            relative_path = $_.FullName.Substring($root.Length).TrimStart('\')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
          }
        }
      }
      [ordered]@{
        platform = $platform
        relative_root = (Resolve-Path -LiteralPath $root).Path.Substring($Project.Length).TrimStart('\')
        skills = $registeredSkills
        files = @($files)
        discovery = 'project_native'
      }
    }
  }
  [ordered]@{ schema_version = 2; generated_at = (Get-Date -Format o); registry = '.agents/skills.json'; hash_algorithm = 'SHA256'; registrations = @($registrations) } |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $registrationPath -Encoding utf8

  # 3. Deploy project-level .agents/skills.json for explicit Antigravity/Gemini project skill registration
  $skillsJsonPath = Join-Path $Project '.agents\skills.json'
  if (-not (Test-Path -LiteralPath $skillsJsonPath)) {
    $skillsJsonContent = @"
{
  "entries": [
    {
      "path": ".agents/skills"
    }
  ]
}
"@
    Set-Content -LiteralPath $skillsJsonPath -Value $skillsJsonContent -Encoding utf8
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

  $roots = @(
    (Join-Path $Project '.agents\skills'),
    (Join-Path $Project '.claude\skills'),
    (Join-Path $Project '.codex\skills'),
    (Join-Path $Project '.opencode\skills'),
    (Join-Path $Project '.cursor\skills'),
    (Join-Path $Project '.gemini\skills'),
    (Join-Path $env:USERPROFILE '.agents\skills'),
    (Join-Path $env:USERPROFILE '.claude\skills')
  ) | Select-Object -Unique

  $names = @('research','implement','diagnosing-bugs','code-review','tdd')
  $out = [ordered]@{}
  foreach ($name in $names) {
    $expectedHash = if ($knownOfficialHashes.ContainsKey($name)) { $knownOfficialHashes[$name] } else { $null }
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

  # Check progressive workflow skills & audit-suite
  $bundledSkillsDir = Join-Path $PSScriptRoot '..\bundled_skills'
  $workflowSkillsDir = Join-Path (Split-Path (Split-Path $PSScriptRoot)) '.agents\skills'
  $progressiveSkills = @('karpathy-guidelines', 'task-agent', 'bugfix-agent', 'research-agent', 'verification-agent', 'audit-suite')
  $auditRoots = $roots + @($bundledSkillsDir, $workflowSkillsDir)
  foreach ($ws in $progressiveSkills) {
    $wsCandidates = @($auditRoots | ForEach-Object { Join-Path $_ "$ws\SKILL.md" } | Where-Object { Test-Path -LiteralPath $_ })
    $hasWs = ($wsCandidates.Count -gt 0)
    $keyName = $ws -replace '-', '_'
    $out[$keyName] = [ordered]@{
      available = [bool]$hasWs
      path = if ($hasWs) { $wsCandidates[0] } else { $null }
      verified_official = $true
    }
  }
  return $out
}

function Get-GitSetup([string]$Project, [bool]$AllowInit, [string]$RequestedPolicy, [string]$RequestedRemote, [bool]$Interactive) {
  # A fresh portable checkout has no .git yet. PowerShell 5.1/7 can promote
  # native git's stderr into a terminating error even when redirected, so treat
  # the probe as data instead of letting it abort initialization.
  $isGit = $null
  $probeExit = 0
  try {
    $isGit = (& git -c core.quotepath=false -C $Project rev-parse --is-inside-work-tree 2>$null)
    $probeExit = $LASTEXITCODE
  } catch {
    $probeExit = 1
  }
  $initialized = $false
  if ($probeExit -ne 0 -or [string]$isGit -ne 'true') {
    if (-not $AllowInit) {
      return [ordered]@{ repository = $false; initialized_by_herdr = $false; has_commit = $false; target_branch = $null; push_policy = 'manual'; push_remote = $null; remotes = @(); use_gh_cli = $false; github = $null }
    }
    & git -c core.quotepath=false -C $Project init 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize Git repository in $Project." }
    $initialized = $true
  }
  $head = $null
  $hasCommit = $false
  try {
    $head = (& git -c core.quotepath=false -C $Project rev-parse --verify HEAD 2>$null)
    $hasCommit = ($LASTEXITCODE -eq 0)
  } catch {
    $hasCommit = $false
  }
  $branch = if ($hasCommit) {
    try { (& git -c core.quotepath=false -C $Project rev-parse --abbrev-ref HEAD 2>$null) } catch { $null }
  } else { $null }
  $remotes = @((& git -c core.quotepath=false -C $Project remote 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $hasGh = [bool](Get-Command -Name 'gh' -CommandType Application,ExternalScript -ErrorAction SilentlyContinue)
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
    $options += @{ Label = "manual      - 手动提交 (验证通过后仅保存在本地 Git 仓库，由人工手动 Push) [推荐]"; Value = 'manual' }
    foreach ($r in $remotes) {
      $options += @{ Label = "push:$r     - 自动 Git Push (验证通过后自动推送到远程仓库 $r)"; Value = "push:$r" }
    }
    if ($githubInfo.is_github -and $hasGh) {
      $options += @{ Label = "create_pr   - 自动创建 PR (验证通过后通过 GitHub CLI 自动提交 Pull Request)"; Value = 'create_pr' }
    }

    $chosen = Select-InteractiveMenu -Title "选择代码验证通过后的提交/推送策略 (Push Policy)" -Subtitle "当代码完成独立验收且通过测试后，Herdr 应如何处理 Git 提交？" -Options $options
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
  $npmLauncher = Join-Path (Join-Path $env:APPDATA 'npm') "$Kind.cmd"
  $command = Get-Command -Name $Kind -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command -and -not (Test-Path -LiteralPath $npmLauncher -PathType Leaf)) { throw "Herdr kind '$Kind' has no terminal executable named '$Kind' in PATH." }
  $executable = if (Test-Path -LiteralPath $npmLauncher -PathType Leaf) { $npmLauncher } else { [string]$command.Path }
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
      @{ Label = "claude   - Anthropic Claude Code CLI (推荐用于 根因分析/复盘与复杂编码)"; Value = 'claude' },
      @{ Label = "codex    - OpenAI Codex CLI (推荐用于 任务开发与自动化代码验收)"; Value = 'codex' },
      @{ Label = "opencode - OpenCode 终端全屏 TUI (支持 DeepSeek-V4 / Claude / GPT 模型)"; Value = 'opencode' },
      @{ Label = "gemini   - Google Gemini CLI (谷歌 Gemini 终端工具)"; Value = 'gemini' },
      @{ Label = "custom   - 自定义命令 / 脚本 (自定义 PowerShell 可执行程序)"; Value = 'custom' }
    )
    $chosen = Select-InteractiveMenu -Title "配置 $RoleTitle ($RoleKey)" -Subtitle "请选择该工作流节点所使用的 AI Agent 引擎" -Options $options
    if ($chosen -eq 'custom') {
      Write-Host "请输入用于 $RoleTitle 的自定义可执行文件或 PowerShell 命令:" -ForegroundColor Cyan
      $cmd = (Read-Host "自定义命令").Trim()
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

# Herdr invokes agents through PowerShell Start-Process using the bare name.
# On Windows the npm POSIX shim named `codex` is not a Win32 executable, so
# prefer an installed native codex.exe directory while preserving all PATH
# entries (including Anaconda).
function Ensure-HerdrWindowsAgentPath([string[]]$Kinds) {
  if ($env:OS -ne 'Windows_NT' -or $Kinds -notcontains 'codex') { return }
  $native = Get-Command -Name 'codex.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $native -or -not (Test-Path -LiteralPath $native.Source -PathType Leaf)) {
    Write-Warning 'Herdr codex.exe native launcher was not found; Herdr agent start may fail until one is installed.'
    return
  }
  $nativeDir = Split-Path -Parent $native.Source
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $entries = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() -and $_ -ne $nativeDir })
  [Environment]::SetEnvironmentVariable('Path', ($nativeDir + ';' + ($entries -join ';')), 'User')
  $currentEntries = @($env:Path -split ';' | Where-Object { $_ -and $_.Trim() -and $_ -ne $nativeDir })
  $env:Path = ($nativeDir + ';' + ($currentEntries -join ';'))
  Write-Host "  Herdr native launcher path: $nativeDir (existing PATH preserved)" -ForegroundColor DarkCyan
}

# --- Main Execution Flow ---
Show-HerdrBanner

$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$interactiveSetup = [string]::IsNullOrWhiteSpace($TaskKind) -or [string]::IsNullOrWhiteSpace($VerificationKind) -or [string]::IsNullOrWhiteSpace($ResearchKind)
$git = Get-GitSetup $project (-not $SkipGitInit) $PushPolicy $PushRemote $interactiveSetup
$session = Select-HerdrSession $HerdrSessionName
$supportedKinds = Get-SupportedKinds

$rootCause = Select-Agent '根因分析与审查 Agent (Root-Cause & Audit)' 'root_cause' $RootCauseKind $RootCauseOpenCodeModel $RootCauseFullAccessArgs $RootCauseCommand $supportedKinds
$task = Select-Agent '任务开发与实现 Agent (Task & Implementation)' 'task' $TaskKind $TaskOpenCodeModel $TaskFullAccessArgs $TaskCommand $supportedKinds
$verification = Select-Agent '代码验收与合并 Agent (Verification & Integration)' 'verification' $VerificationKind $VerificationOpenCodeModel $VerificationFullAccessArgs $VerificationCommand $supportedKinds
$research = Select-Agent '深度调研与探索 Agent (Deep Research)' 'research' $ResearchKind $ResearchOpenCodeModel $ResearchFullAccessArgs $ResearchCommand $supportedKinds
Ensure-HerdrWindowsAgentPath @($rootCause.kind, $task.kind, $verification.kind, $research.kind)

# Interactive Skill Target Agents Selection
$configuredAgents = @($rootCause.kind, $task.kind, $verification.kind, $research.kind) | Select-Object -Unique
$targetAgents = $SkillTargetAgents
if (-not $targetAgents -and $interactiveSetup) {
  $skillOptions = @(
    @{ Label = "推荐: 仅安装至当前配置的 Workflow Agents ($($configuredAgents -join ', '))"; Value = 'configured' },
    @{ Label = "全量: 安装至所有支持的 Agent 工具 (* - Claude, Codex, OpenCode, Cursor, Gemini)"; Value = 'all' },
    @{ Label = "仅 Claude Code (.claude/skills)"; Value = 'claude-code' },
    @{ Label = "仅 OpenAI Codex (.codex/skills)"; Value = 'codex' },
    @{ Label = "仅 OpenCode (.opencode/skills)"; Value = 'opencode' },
    @{ Label = "仅 Universal 通用目录 (.agents/skills)"; Value = 'agents_only' }
  )
  $chosenSkillTarget = Select-InteractiveMenu -Title "选择项目 Skill 技能部署的目标 Agent" -Subtitle "决定将 Matt Pocock 官方工程技能与 Audit-Suite 审判技能安装到哪些 Agent 目录" -Options $skillOptions
  $targetAgents = switch ($chosenSkillTarget) {
    'configured' { $configuredAgents }
    'all' { @('*') }
    'agents_only' { @('agents_only') }
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
  target_skill_agents = if($null -ne $targetAgents){@($targetAgents)}else{@('*')}
  project_skill_registry = '.agents/project-skills.json'
  project_skill_registry_required = $true
  mattpocock_skills = $mattpockSkills
  git = $git
  skills_install_command = 'plogr init'
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
Write-Host "  Global Command:   已自动挂载! 之后在任意终端输入 plogr 即可直接浮现 Herdr 复合终端" -ForegroundColor Green
Write-Host "  Live HUD:         plogr hud (开启 24-bit 炫彩流光实时看板)" -ForegroundColor Cyan
Write-Host ""
