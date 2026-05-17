#requires -Version 5.1
<#
.SYNOPSIS
  Auto-backup to an external drive labeled "External HDD" whenever it's connected.
.DESCRIPTION
  Designed to be run by Scheduled Task "BackupOnConnect" every 10 min at logon.
  - Finds the External HDD by volume label (drive letter may vary).
  - Skips if last run was less than $cooldownHours ago.
  - Runs robocopy incrementally (only changed/new files copied).
  - Writes a per-run log and updates a stamp file on the drive.
#>

$ErrorActionPreference = 'Continue'
$cooldownHours = 6
$logFile = "$PSScriptRoot\.backup-on-connect.log"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    $line | Out-File $logFile -Append -Encoding utf8
}

# --- Find the external drive by label ---
$vol = Get-Volume -ErrorAction SilentlyContinue |
       Where-Object { $_.FileSystemLabel -eq 'External HDD' -and $_.DriveLetter }
if (-not $vol) {
    Log "External HDD not connected. Exiting."
    exit 0
}
$driveLetter = $vol.DriveLetter
$drive = "${driveLetter}:"
Log "Found External HDD at $drive"

# --- One-time migration: adopt prior dated snapshot if Backup-auto doesn't exist yet ---
$dest = "$drive\Backup-auto"
if (-not (Test-Path $dest)) {
    $prior = Get-ChildItem -Path $drive -Directory -Filter 'Backup-20*' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($prior) {
        Log "Adopting existing snapshot $($prior.FullName) as $dest"
        Rename-Item -LiteralPath $prior.FullName -NewName 'Backup-auto'
    }
}

# --- Cooldown check ---
$stampFile = "$dest\.last-run"
if (Test-Path $stampFile) {
    $last = (Get-Item $stampFile).LastWriteTime
    $hours = (New-TimeSpan -Start $last -End (Get-Date)).TotalHours
    if ($hours -lt $cooldownHours) {
        Log ("Last run {0:N1}h ago (cooldown {1}h). Skipping." -f $hours, $cooldownHours)
        exit 0
    }
}

# --- Prepare destination ---
$logDir = "$dest\_logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$runStart = Get-Date
Log "Starting incremental backup -> $dest"

$jobs = @(
    @{ Src = "$env:USERPROFILE\Downloads";                       Dst = "$dest\Downloads";                       Name = "Downloads" },
    @{ Src = "$env:USERPROFILE\Videos";                          Dst = "$dest\Videos";                          Name = "Videos" },
    @{ Src = "$env:USERPROFILE\Music";                           Dst = "$dest\Music";                           Name = "Music" },
    @{ Src = "$env:USERPROFILE\OneDrive\Desktop";                Dst = "$dest\Desktop";                         Name = "Desktop" },
    @{ Src = "$env:USERPROFILE\OneDrive\Pictures";               Dst = "$dest\Pictures";                        Name = "Pictures" },
    @{ Src = "$env:USERPROFILE\OneDrive\Documents";              Dst = "$dest\Documents";                       Name = "Documents" },
    @{ Src = "$env:USERPROFILE\OneDrive\Claude Stuff";           Dst = "$dest\Claude Stuff";                    Name = "ClaudeStuff" },
    @{ Src = "$env:USERPROFILE\OneDrive\Audacity";               Dst = "$dest\Other\Audacity";                  Name = "Audacity" },
    @{ Src = "$env:USERPROFILE\OneDrive\Training Videos";        Dst = "$dest\Other\Training Videos";           Name = "TrainingVideos" },
    @{ Src = "$env:USERPROFILE\OneDrive\Attachments";            Dst = "$dest\Other\Attachments";               Name = "Attachments" },
    @{ Src = "$env:USERPROFILE\OneDrive\Transcribed Files";      Dst = "$dest\Other\Transcribed Files";         Name = "TranscribedFiles" },
    @{ Src = "$env:USERPROFILE\OneDrive\Bigequipment brochures"; Dst = "$dest\Other\Bigequipment brochures";    Name = "Brochures" },
    @{ Src = "$env:USERPROFILE\OneDrive\CustomerTestimonials";   Dst = "$dest\Other\CustomerTestimonials";      Name = "Testimonials" },
    @{ Src = "$env:USERPROFILE\OneDrive\Warranty Stuff";         Dst = "$dest\Other\Warranty Stuff";            Name = "Warranty" }
)

foreach ($j in $jobs) {
    if (-not (Test-Path $j.Src)) {
        Log "[SKIP] $($j.Name) - source missing: $($j.Src)"
        continue
    }
    & robocopy $j.Src $j.Dst /E /COPY:DAT /DCOPY:DAT /R:3 /W:5 /MT:8 /XJ /NP /NFL /NDL `
        /LOG+:"$logDir\$($j.Name).log" | Out-Null
    Log "  $($j.Name): robocopy exit $LASTEXITCODE"
}

# --- Flush cache and update stamp ---
Write-VolumeCache -DriveLetter $driveLetter -ErrorAction SilentlyContinue
(Get-Date).ToString('o') | Out-File $stampFile -Force -Encoding utf8

$elapsed = (Get-Date) - $runStart
Log ("Backup complete. Elapsed {0:hh\:mm\:ss}." -f $elapsed)
