[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$WorkflowPath,
  [ValidateSet('single_line', 'multiline', 'popup', 'live')][string]$DisplayMode = 'single_line',
  [switch]$Loop,
  [int]$RefreshIntervalMs = 150
)

$ErrorActionPreference = 'Stop'

function Get-ActiveWorkflow([string]$Root, [string]$ExplicitPath) {
  if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
    try { return (Get-Content -LiteralPath $ExplicitPath -Raw | ConvertFrom-Json) } catch { return $null }
  }
  $herdrDir = Join-Path $Root 'herdr'
  if (-not (Test-Path -LiteralPath $herdrDir)) { return $null }

  $wfFiles = @(Get-ChildItem -LiteralPath $herdrDir -Recurse -Filter 'workflow.json' -File | Sort-Object LastWriteTime -Descending)
  foreach ($wfFile in $wfFiles) {
    try {
      $wf = Get-Content -LiteralPath $wfFile.FullName -Raw | ConvertFrom-Json
      if ($wf.state -in @('executing', 'verifying', 'repairing')) {
        $wf | Add-Member -Force -NotePropertyName _filePath -NotePropertyValue $wfFile.FullName
        return $wf
      }
    } catch {}
  }
  if ($wfFiles.Count -gt 0) {
    try {
      $wf = Get-Content -LiteralPath $wfFiles[0].FullName -Raw | ConvertFrom-Json
      $wf | Add-Member -Force -NotePropertyName _filePath -NotePropertyValue $wfFiles[0].FullName
      return $wf
    } catch {}
  }
  return $null
}

function Get-GlowColor([double]$PhaseOffset = 0) {
  $t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 400.0 + $PhaseOffset
  # Oscillate smoothly between Sky Blue (56, 189, 248), Neon Purple (168, 85, 247), and Vibrant Magenta (236, 72, 153)
  $r = [int](146 + 90 * [Math]::Sin($t))
  $g = [int](130 + 59 * [Math]::Sin($t + 2.094))
  $b = [int](200 + 48 * [Math]::Sin($t + 4.188))
  return @($r, $g, $b)
}

function Render-SingleLineHud($wf) {
  $e = [char]27
  if (-not $wf) {
    Write-Host "`r$e[38;2;100;116;139m 🚀 PLOGR ❯❯ [ ○ 空闲 IDLE ] • 暂无活跃工作流 $e[K" -NoNewline
    return
  }

  $mode = [string]$wf.mode
  $state = [string]$wf.state
  $nextRole = [string]$wf.next_role
  $repairRound = [int]$wf.repair_round
  $matrix = $wf.matrix

  $rgb = Get-GlowColor 0
  $glowAnsi = "$e[1;38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
  $reset = "$e[0m"
  $green = "$e[38;2;34;197;94m"
  $gray = "$e[38;2;100;116;139m"
  $white = "$e[1;37m"

  # Check if in Matrix Parallel Mode
  if ($matrix -and $matrix.Count -gt 0) {
    $parallelBadges = @()
    $idx = 0
    foreach ($item in $matrix) {
      $pStatus = [string]$item.status
      $pName = [string]$item.id
      $pAgent = [string]$item.agent
      if ($pStatus -eq 'candidate' -or $pStatus -eq 'merged' -or $pStatus -eq 'done') {
        $parallelBadges += "$green[✔ $pName]$reset"
      } else {
        $pColor = Get-GlowColor ($idx * 1.5)
        $pGlow = "$e[1;38;2;$($pColor[0]);$($pColor[1]);$($pColor[2])m"
        $parallelBadges += "$pGlow⟪⚙️ $pName ($pAgent)⟫$reset"
      }
      $idx++
    }

    $verIcon = if ($state -eq 'verifying') { "$glowAnsi⟪🛡️ VERIFIER 验收中⟫$reset" } elseif ($state -eq 'merged') { "$green[✔ VERIFIER]$reset" } else { "$gray[○ VERIFIER]$reset" }
    $mergeIcon = if ($state -eq 'merged') { "$green[✨ MERGED]$reset" } else { "$gray[○ MERGE]$reset" }

    $out = "`r$glowAnsi 🚀 PLOGR$reset $gray❯❯$reset $gray[✔ INIT]$reset $gray══▶$reset $glowAnsi⟪⚡ 并行($($matrix.Count)): $($parallelBadges -join ' ') ⟫$reset $gray══▶$reset $verIcon $gray┄▷$reset $mergeIcon $e[K"
    [Console]::Out.Write($out)
    Write-Output $out
    return
  }

  # Standard 4-Node Pipeline (Audit -> Task -> Verifier -> Merged)
  $auditNode = if ($mode -eq 'bugfix') {
    if ($state -eq 'executing' -and $nextRole -eq 'task' -and $repairRound -eq 0) {
      "$glowAnsi⟪🔍 ROOT-CAUSE 诊断中⟫$reset"
    } else {
      "$green[✔ ROOT-CAUSE]$reset"
    }
  } else {
    "$green[✔ INIT]$reset"
  }

  $taskNode = if ($state -eq 'executing' -or $state -eq 'repairing') {
    $agentName = if ($wf.task.active_agent_name) { $wf.task.active_agent_name } else { 'Task' }
    $repairText = if ($repairRound -gt 0) { " (修复轮次: $repairRound)" } else { '' }
    "$glowAnsi⟪⚙️ TASK $agentName$repairText⟫$reset"
  } elseif ($state -in @('verifying', 'merged', 'passed')) {
    "$green[✔ TASK]$reset"
  } else {
    "$gray[○ TASK]$reset"
  }

  $verifierNode = if ($state -eq 'verifying') {
    "$glowAnsi⟪🛡️ VERIFIER (5重门禁独立验收)⟫$reset"
  } elseif ($state -in @('merged', 'passed')) {
    "$green[✔ VERIFIER]$reset"
  } else {
    "$gray[○ VERIFIER]$reset"
  }

  $mergedNode = if ($state -eq 'merged' -or $state -eq 'passed') {
    "$green⟪✨ MERGED 已合入主分支⟫$reset"
  } elseif ($state -eq 'blocked') {
    "$e[1;38;2;239;68;68m⟪⛔ BLOCKED 熔断阻断⟫$reset"
  } else {
    "$gray[○ MERGE]$reset"
  }

  # Build arrows based on progress
  $a1 = if ($state -in @('executing', 'verifying', 'merged', 'passed')) { "$green──▶$reset" } else { "$gray┄▷$reset" }
  $a2 = if ($state -in @('verifying', 'merged', 'passed')) { "$green──▶$reset" } elseif ($state -eq 'executing' -or $state -eq 'repairing') { "$glowAnsi══▶$reset" } else { "$gray┄▷$reset" }
  $a3 = if ($state -in @('merged', 'passed')) { "$green──▶$reset" } elseif ($state -eq 'verifying') { "$glowAnsi══▶$reset" } else { "$gray┄▷$reset" }

  $out = "`r$glowAnsi 🚀 PLOGR$reset $gray❯❯$reset $auditNode $a1 $taskNode $a2 $verifierNode $a3 $mergedNode $e[K"
  [Console]::Out.Write($out)
  Write-Output $out
}

function Render-MultilinePopup($wf) {
  $e = [char]27
  $rgb = Get-GlowColor 0
  $glow = "$e[1;38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
  $green = "$e[38;2;34;197;94m"
  $cyan = "$e[38;2;56;189;248m"
  $yellow = "$e[38;2;234;179;8m"
  $gray = "$e[38;2;100;116;139m"
  $white = "$e[1;37m"
  $reset = "$e[0m"

  Clear-Host
  Write-Host ""
  Write-Host "  $glow╔═════════════════════════════════════════════════════════════════════════════╗$reset"
  Write-Host "  $glow║$reset  $white PLOGR WORKFLOW HUD • REAL-TIME MULTI-AGENT OBSERVABILITY$reset          $glow║$reset"
  Write-Host "  $glow╚═════════════════════════════════════════════════════════════════════════════╝$reset"
  Write-Host ""

  if (-not $wf) {
    Write-Host "    $gray[ ○ 空闲 IDLE ] 暂无活跃工作流。$reset"
    Write-Host ""
    return
  }

  $wfId = [string]$wf.workflow_id
  $mode = [string]$wf.mode
  $state = [string]$wf.state
  $slug = [string]$wf.slug
  $session = [string]$wf.session_name
  $repairRound = [int]$wf.repair_round

  Write-Host "    $cyan• Workflow ID :$reset $white$wfId$reset  $gray($mode/$slug)$reset"
  Write-Host "    $cyan• Session Name:$reset $yellow$session$reset"
  Write-Host "    $cyan• Current State:$reset $glow$($state.ToUpper())$reset $gray(Repair Round: $repairRound/2)$reset"
  Write-Host ""

  Write-Host "    $white拓扑流水线 (Pipeline Flow):$reset"
  Render-SingleLineHud $wf
  Write-Host "`n"

  if ($wf.task.worktree_path) {
    Write-Host "    $white物理沙盒 (Worktree Isolation):$reset"
    Write-Host "      $cyan🌿 Path  :$reset $($wf.task.worktree_path)"
    Write-Host "      $cyan🌿 Branch:$reset $($wf.task.branch)"
    Write-Host ""
  }

  Write-Host "  $gray─────────────────────────────────────────────────────────────────────────$reset"
  Write-Host "  $gray按 Ctrl+C 或 'q' 退出看板$reset"
}

# --- Execution Entry ---
if ($Loop) {
  $origCursor = $true
  try { $origCursor = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}
  try {
    while ($true) {
      $wf = Get-ActiveWorkflow $ProjectRoot $WorkflowPath
      if ($DisplayMode -eq 'single_line') {
        Render-SingleLineHud $wf
      } else {
        Render-MultilinePopup $wf
      }
      Start-Sleep -Milliseconds $RefreshIntervalMs
    }
  } finally {
    try { [Console]::CursorVisible = $origCursor } catch {}
    Write-Host ""
  }
} else {
  $wf = Get-ActiveWorkflow $ProjectRoot $WorkflowPath
  if ($DisplayMode -eq 'single_line') {
    Render-SingleLineHud $wf
    Write-Host ""
  } else {
    Render-MultilinePopup $wf
  }
}
