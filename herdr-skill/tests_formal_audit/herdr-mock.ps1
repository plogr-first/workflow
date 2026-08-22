# Test Mock Herdr Engine
# Provides deterministic simulation of Herdr CLI for formal audit

$allArgs = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) {
  if ($a -ne $null) { $allArgs.Add([string]$a) }
}

$logFile = $env:HERDR_MOCK_LOG
if (-not $logFile) {
  $logFile = Join-Path $PSScriptRoot 'herdr_mock_calls.log'
}

$callRecord = ($allArgs -join ' ')
Add-Content -LiteralPath $logFile -Value "[$(Get-Date -Format o)] herdr $callRecord" -Encoding utf8

$subcmd = if ($allArgs.Count -gt 0) { $allArgs[0] } else { '' }
$session = $null
$subargs = @()

if ($subcmd -eq '--session') {
  $session = if ($allArgs.Count -gt 1) { $allArgs[1] } else { '' }
  $subcmd = if ($allArgs.Count -gt 2) { $allArgs[2] } else { '' }
  if ($allArgs.Count -gt 3) {
    $subargs = @($allArgs[3..($allArgs.Count - 1)])
  }
} else {
  if ($allArgs.Count -gt 1) {
    $subargs = @($allArgs[1..($allArgs.Count - 1)])
  }
}

switch ($subcmd) {
  'notification' {
    # herdr notification show <Title> --body <Body> --sound <Sound>
    [pscustomobject]@{ status = 'ok'; title = if ($subargs.Count -gt 1) { $subargs[1] } else { '' } } | ConvertTo-Json -Compress
    exit 0
  }
  'agent' {
    $op = if ($subargs.Count -gt 0) { $subargs[0] } else { '' }
    if ($op -eq 'get') {
      $agentName = if ($subargs.Count -gt 1) { $subargs[1] } else { '' }
      $deadAgents = if ($env:HERDR_MOCK_DEAD_AGENTS) { $env:HERDR_MOCK_DEAD_AGENTS -split ',' } else { @() }
      if ($deadAgents -contains $agentName) {
        [Console]::Error.WriteLine("Agent $agentName not found")
        exit 1
      }
      $status = if ($env:HERDR_MOCK_AGENT_STATUS) { $env:HERDR_MOCK_AGENT_STATUS } else { 'idle' }
      [pscustomobject]@{
        result = [ordered]@{
          agent = [ordered]@{
            name = $agentName
            agent = 'codex'
            agent_status = $status
            interactive_ready = $true
          }
        }
      } | ConvertTo-Json -Depth 5 -Compress
      exit 0
    }
    if ($op -eq 'prompt') {
      $agentName = if ($subargs.Count -gt 1) { $subargs[1] } else { '' }
      $promptText = if ($subargs.Count -gt 2) { $subargs[2] } else { '' }
      Add-Content -LiteralPath "$logFile.prompts" -Value "PROMPT -> $agentName : $promptText" -Encoding utf8
      [pscustomobject]@{ status = 'ok'; agent = $agentName } | ConvertTo-Json -Compress
      exit 0
    }
    if ($op -eq 'start') {
      $agentName = if ($subargs.Count -gt 1) { $subargs[1] } else { '' }
      [pscustomobject]@{
        result = [ordered]@{
          agent = [ordered]@{
            name = $agentName
            agent = 'codex'
            interactive_ready = $true
            agent_status = 'idle'
          }
        }
      } | ConvertTo-Json -Depth 5 -Compress
      exit 0
    }
  }
  'pane' {
    $op = if ($subargs.Count -gt 0) { $subargs[0] } else { '' }
    if ($op -eq 'list') {
      [pscustomobject]@{
        result = [ordered]@{
          panes = @(
            [ordered]@{ pane_id = 'w1:p1'; title = 'shell' }
          )
        }
      } | ConvertTo-Json -Depth 5 -Compress
      exit 0
    }
    if ($op -eq 'split') {
      $newPaneId = "w1:p$([guid]::NewGuid().ToString('N').Substring(0,4))"
      [pscustomobject]@{
        result = [ordered]@{
          pane = [ordered]@{
            pane_id = $newPaneId
          }
        }
      } | ConvertTo-Json -Depth 5 -Compress
      exit 0
    }
    if ($op -eq 'send-text' -or $op -eq 'send-keys') {
      exit 0
    }
  }
  'tab' {
    $newPaneId = "w1:p$([guid]::NewGuid().ToString('N').Substring(0,4))"
    [pscustomobject]@{
      result = [ordered]@{
        tab = [ordered]@{ tab_id = 'w1:t2' }
        root_pane = [ordered]@{ pane_id = $newPaneId }
      }
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
  }
  'workspace' {
    $newPaneId = "w1:p$([guid]::NewGuid().ToString('N').Substring(0,4))"
    [pscustomobject]@{
      result = [ordered]@{
        workspace = [ordered]@{ workspace_id = 'w2' }
        tab = [ordered]@{ tab_id = 'w2:t1' }
        root_pane = [ordered]@{ pane_id = $newPaneId }
      }
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
  }
  'session' {
    $op = if ($subargs.Count -gt 0) { $subargs[0] } else { '' }
    if ($op -eq 'list') {
      [pscustomobject]@{
        sessions = @(
          [ordered]@{ name = 'default' },
          [ordered]@{ name = 'test-session' },
          [ordered]@{ name = 'delta-secure-session' }
        )
      } | ConvertTo-Json -Depth 5 -Compress
      exit 0
    }
  }
  'status' {
    [pscustomobject]@{ status = 'running' } | ConvertTo-Json -Compress
    exit 0
  }
}

exit 0
