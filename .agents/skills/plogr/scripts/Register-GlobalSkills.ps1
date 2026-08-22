$ErrorActionPreference = 'Stop'
$sourcePkg = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$bundled = Join-Path $sourcePkg 'bundled_skills'
$allCoreSkills = @('plogr', 'herdr', 'karpathy-guidelines', 'task-agent', 'bugfix-agent', 'research-agent', 'verification-agent', 'audit-suite')
$globalPlatforms = @(
  (Join-Path $env:USERPROFILE '.gemini\skills'),
  (Join-Path $env:USERPROFILE '.gemini\config\skills'),
  (Join-Path $env:USERPROFILE '.config\opencode\skills'),
  (Join-Path $env:USERPROFILE '.opencode\skills'),
  (Join-Path $env:USERPROFILE '.agents\skills'),
  (Join-Path $env:USERPROFILE '.claude\skills'),
  (Join-Path $env:USERPROFILE '.codex\skills')
)

function Get-SkillSource([string]$Skill) {
  if ($Skill -eq 'plogr') { return $sourcePkg }
  return (Join-Path $bundled $Skill)
}
function Get-Sha256([string]$Path) {
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $stream = [System.IO.File]::OpenRead($Path)
    try { return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '') }
    finally { $stream.Dispose() }
  } finally { $sha256.Dispose() }
}

function Get-ManagedManifest([string]$Root) {
  $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
  return @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\\/](?:node_modules|\.git|tests_formal_audit)([\\/]|$)' } |
    ForEach-Object {
      [pscustomobject]@{
        relative_path = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]@('\','/'))
        sha256 = Get-Sha256 $_.FullName
      }
    } | Sort-Object relative_path)
}

function Assert-SkillCopy([string]$Source, [string]$Destination, [string]$Skill) {
  if (-not (Test-Path -LiteralPath (Join-Path $Destination 'SKILL.md') -PathType Leaf)) { throw "$Skill is missing SKILL.md at $Destination" }
  $sourceManifest = @(Get-ManagedManifest $Source)
  $destinationManifest = @(Get-ManagedManifest $Destination)
  if ($sourceManifest.Count -ne $destinationManifest.Count) {
    throw "$Skill managed file count mismatch at $Destination (source=$($sourceManifest.Count), destination=$($destinationManifest.Count))"
  }
  for ($i = 0; $i -lt $sourceManifest.Count; $i++) {
    if ($sourceManifest[$i].relative_path -ne $destinationManifest[$i].relative_path -or
        $sourceManifest[$i].sha256 -ne $destinationManifest[$i].sha256) {
      throw "$Skill full-tree hash mismatch at ${Destination}: $($sourceManifest[$i].relative_path)"
    }
  }
}

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($platform in $globalPlatforms) {
  try { New-Item -ItemType Directory -Force -Path $platform | Out-Null } catch { $failures.Add("${platform}: $($_.Exception.Message)"); continue }
  Write-Host ">>> Target Platform: $platform" -ForegroundColor Yellow
  foreach ($skill in $allCoreSkills) {
    $source = Get-SkillSource $skill
    $destination = Join-Path $platform $skill
    try {
      if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) { throw "Source skill is incomplete: $source" }
      # Global skill directories are managed deployment targets. Recreate the
      # exact target before copying so stale files cannot evade full-tree checks.
      if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
      }
      New-Item -ItemType Directory -Force -Path $destination | Out-Null
      Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force -Exclude 'node_modules','.git','tests_formal_audit'
      Assert-SkillCopy $source $destination $skill
      Write-Host "  Registered: $skill" -ForegroundColor Green
    } catch { $failures.Add("${destination}: $($_.Exception.Message)") }
  }
}

if ($failures.Count) { throw "Global skill registration failed:`n$($failures -join "`n")" }
Write-Host 'Global skill registration verified with full managed-tree SHA256 hashes.' -ForegroundColor Green
