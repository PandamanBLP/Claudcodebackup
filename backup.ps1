$repoPath = "C:\Users\jlync\OneDrive\Desktop\ClaudeCode"
$logFile = Join-Path $repoPath ".backup.log"

Set-Location $repoPath

function Log($msg) {
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" -Encoding utf8
}

$status = git status --porcelain
if ($LASTEXITCODE -ne 0) { Log "git status failed (exit $LASTEXITCODE)"; exit 1 }
if (-not $status) {
    Log "no changes - skipping"
    exit 0
}

git add -A *> $null
if ($LASTEXITCODE -ne 0) { Log "git add failed (exit $LASTEXITCODE)"; exit 1 }

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
git commit -m "Auto-backup $ts" *> $null
if ($LASTEXITCODE -ne 0) { Log "git commit failed (exit $LASTEXITCODE)"; exit 1 }

git push origin main *> $null
if ($LASTEXITCODE -ne 0) { Log "git push failed (exit $LASTEXITCODE) - check network or credentials"; exit 1 }

Log "backup successful: Auto-backup $ts"
exit 0
