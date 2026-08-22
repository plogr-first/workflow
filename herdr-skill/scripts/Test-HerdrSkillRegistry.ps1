[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
$registryPath = Join-Path $project '.agents\project-skills.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { throw "Project skill registry is missing: $registryPath" }
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
 if ([int]$registry.schema_version -lt 2) { throw "Project skill registry is obsolete. Re-run plogr init: $registryPath" }
if (-not $registry.registrations) { throw "Project skill registry has no platform entries: $registryPath" }

$checked = 0
foreach ($registration in @($registry.registrations)) {
  $root = Join-Path $project ([string]$registration.relative_root)
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Registered skill root is missing for $($registration.platform): $root" }
  foreach ($entry in @($registration.files)) {
    $path = Join-Path $root ([string]$entry.relative_path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Registered skill file is missing: $path" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$entry.sha256) { throw "Registered skill file hash mismatch: $path" }
    $checked++
  }
}
Write-Output "Project skill registry verified: $($registry.registrations.Count) platforms, $checked files."
