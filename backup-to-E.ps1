$ErrorActionPreference = 'Continue'
$dest = "E:\Backup-2026-05-16"
$logDir = "$dest\_robocopy-logs"
$summary = "$dest\_SUMMARY.txt"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$jobs = @(
    @{ Src = "$env:USERPROFILE\Downloads";                     Dst = "$dest\Downloads";                       Name = "Downloads" },
    @{ Src = "$env:USERPROFILE\Videos";                        Dst = "$dest\Videos";                          Name = "Videos" },
    @{ Src = "$env:USERPROFILE\Music";                         Dst = "$dest\Music";                           Name = "Music" },
    @{ Src = "$env:USERPROFILE\OneDrive\Desktop";              Dst = "$dest\Desktop";                         Name = "Desktop" },
    @{ Src = "$env:USERPROFILE\OneDrive\Pictures";             Dst = "$dest\Pictures";                        Name = "Pictures" },
    @{ Src = "$env:USERPROFILE\OneDrive\Documents";            Dst = "$dest\Documents";                       Name = "Documents" },
    @{ Src = "$env:USERPROFILE\OneDrive\Claude Stuff";         Dst = "$dest\Claude Stuff";                    Name = "ClaudeStuff" },
    @{ Src = "$env:USERPROFILE\OneDrive\Audacity";             Dst = "$dest\Other\Audacity";                  Name = "Audacity" },
    @{ Src = "$env:USERPROFILE\OneDrive\Training Videos";      Dst = "$dest\Other\Training Videos";           Name = "TrainingVideos" },
    @{ Src = "$env:USERPROFILE\OneDrive\Attachments";          Dst = "$dest\Other\Attachments";               Name = "Attachments" },
    @{ Src = "$env:USERPROFILE\OneDrive\Transcribed Files";    Dst = "$dest\Other\Transcribed Files";         Name = "TranscribedFiles" },
    @{ Src = "$env:USERPROFILE\OneDrive\Bigequipment brochures"; Dst = "$dest\Other\Bigequipment brochures"; Name = "Brochures" },
    @{ Src = "$env:USERPROFILE\OneDrive\CustomerTestimonials"; Dst = "$dest\Other\CustomerTestimonials";      Name = "Testimonials" },
    @{ Src = "$env:USERPROFILE\OneDrive\Warranty Stuff";       Dst = "$dest\Other\Warranty Stuff";            Name = "Warranty" }
)

"Backup started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $summary
"Source machine: $env:COMPUTERNAME" | Out-File $summary -Append
"Destination: $dest" | Out-File $summary -Append
"" | Out-File $summary -Append

$overallStart = Get-Date
foreach ($j in $jobs) {
    if (-not (Test-Path $j.Src)) {
        "[SKIP] $($j.Name) - source not found: $($j.Src)" | Out-File $summary -Append
        continue
    }
    $start = Get-Date
    "[$(Get-Date -Format 'HH:mm:ss')] Starting $($j.Name) ..." | Out-File $summary -Append
    & robocopy $j.Src $j.Dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /MT:16 /XJ /NP /LOG+:"$logDir\$($j.Name).log"
    $code = $LASTEXITCODE
    $elapsed = (Get-Date) - $start
    "[$(Get-Date -Format 'HH:mm:ss')] Finished $($j.Name) - exit $code - elapsed $($elapsed.ToString('hh\:mm\:ss'))" | Out-File $summary -Append
}
$totalElapsed = (Get-Date) - $overallStart
"" | Out-File $summary -Append
"Backup finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $summary -Append
"Total elapsed: $($totalElapsed.ToString('hh\:mm\:ss'))" | Out-File $summary -Append

# Final size report
$finalSize = (Get-ChildItem $dest -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
"Total copied: $([math]::Round($finalSize/1GB,2)) GB" | Out-File $summary -Append
