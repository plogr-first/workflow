[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkflowPath,
  [int]$Passes = 3,
  [int]$DelaySeconds = 15,
  [switch]$Once
)
$ErrorActionPreference = 'Stop'
$monitor = Join-Path $PSScriptRoot 'Monitor-HerdrWorkflow.ps1'
$resume = Join-Path $PSScriptRoot 'Resume-HerdrWorkflows.ps1'
$path = (Resolve-Path -LiteralPath $WorkflowPath).Path
for ($pass = 1; $pass -le $Passes; $pass++) {
  & $monitor -WorkflowPath $path -Once
  $workflow = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if ([string]$workflow.state -in @('merged','passed','blocked')) { break }
  if ([string]$workflow.state -eq 'recovering') {
    & $resume -WorkflowId ([string]$workflow.workflow_id) -ProjectRoot ([string]$workflow.project_root) -FromBash
  }
  if ($pass -lt $Passes -and -not $Once) { Start-Sleep -Seconds $DelaySeconds }
}
Get-Content -LiteralPath $path -Raw
