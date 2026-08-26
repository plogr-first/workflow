function Read-WorkflowJson {
  param([Parameter(Mandatory)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){throw "artifact missing: $Path"}
  try { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { throw "invalid JSON: $Path ($($_.Exception.Message))" }
}

function Test-WorkflowArtifacts {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$WorkflowDirectory,[switch]$Strict)
  $errors=[System.Collections.Generic.List[string]]::new(); $warnings=[System.Collections.Generic.List[string]]::new()
  try{$status=Read-WorkflowJson (Join-Path $WorkflowDirectory 'issue-status.json')}catch{$errors.Add($_.Exception.Message);$status=$null}
  if($status){
    if(-not $status.schema_version){$errors.Add('issue-status.schema_version missing')}
    if(-not @($status.issues).Count){$errors.Add('issue-status.issues empty')}
    foreach($i in @($status.issues)){
      if(-not $i.id){$errors.Add('issue status id missing');continue}
      if([string]$i.state -ne 'done'){$errors.Add("issue $($i.id) is not done")}
      $sha=if($i.commit_sha){[string]$i.commit_sha}elseif($i.worker_commit){$warnings.Add("issue $($i.id) uses legacy worker_commit; migrate to commit_sha");[string]$i.worker_commit}else{$null}
      if($sha -notmatch '^[0-9a-f]{7,40}$'){$errors.Add("issue $($i.id) commit_sha invalid or missing")}
      if($i.evidence){if(-not $i.evidence.result -or -not $i.evidence.outcome){$errors.Add("issue $($i.id) evidence.result/outcome missing")}}
      elseif($i.evidence_paths){$warnings.Add("issue $($i.id) uses legacy evidence_paths; migrate to evidence.result/outcome")}
      else{$errors.Add("issue $($i.id) evidence missing")}
    }
  }
  foreach($name in @('result.md','outcome.json')){if(-not (Test-Path (Join-Path $WorkflowDirectory $name))){$errors.Add("candidate $name missing")}}
  $review=Join-Path $WorkflowDirectory 'review\outcome.json'
  if(Test-Path $review){try{$ro=Read-WorkflowJson $review;if([string]$ro.state -notin @('merged','fix_required','blocked')){$errors.Add('review outcome state invalid')};if(-not $ro.reviewed_candidate_commit){$errors.Add('reviewed_candidate_commit missing')}}catch{$errors.Add($_.Exception.Message)}}
  $hands=Join-Path $WorkflowDirectory 'handoffs.jsonl'
  if(Test-Path $hands){$n=0;foreach($line in Get-Content $hands){$n++;try{if(-not ($line|ConvertFrom-Json)){throw 'empty object'}}catch{$errors.Add("handoffs.jsonl line $n invalid JSON")}}}
  if($Strict -and $warnings.Count){$errors.AddRange($warnings)}
  [pscustomobject]@{ok=($errors.Count -eq 0);errors=@($errors);warnings=@($warnings);checked_at=(Get-Date -Format o)}
}

function Assert-WorkflowArtifacts {
  param([Parameter(Mandatory)][string]$WorkflowDirectory,[switch]$Strict)
  $r=Test-WorkflowArtifacts $WorkflowDirectory -Strict:$Strict
  if(-not $r.ok){throw "workflow artifact validation failed: $($r.errors -join '; ')"}
  return $r
}

function Normalize-WorkflowArtifacts {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$WorkflowDirectory)
  $path=Join-Path $WorkflowDirectory 'issue-status.json'
  if(-not (Test-Path -LiteralPath $path)){return [pscustomobject]@{changed=$false;path=$path}}
  $status=Read-WorkflowJson $path; $changed=$false
  foreach($i in @($status.issues)){
    if(-not $i.commit_sha -and $i.worker_commit){$i|Add-Member -NotePropertyName commit_sha -NotePropertyValue ([string]$i.worker_commit);$changed=$true}
    if(-not $i.evidence -and $i.evidence_paths){
      $paths=@($i.evidence_paths)
      $i|Add-Member -NotePropertyName evidence -NotePropertyValue ([pscustomobject]@{result=if($paths.Count -gt 1){$paths[1]}else{$null};outcome=if($paths.Count -gt 2){$paths[2]}else{$null}})
      $changed=$true
    }
  }
  if($changed){
    $tmp="$path.tmp"; $status|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $tmp -Encoding utf8; Move-Item -LiteralPath $tmp -Destination $path -Force
  }
  [pscustomobject]@{changed=$changed;path=$path}
}
