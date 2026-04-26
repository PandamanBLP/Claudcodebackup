# Wrapper for callback_queue.py — runs the analyzer, pops a Windows toast
# with the Tier A count, and opens the CSV in the default app.
#
# Triggered by the CallbackQueue scheduled task (M/W/F 8:00 AM).

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\jlync\OneDrive\Desktop\ClaudeCode'
$script = Join-Path $repo 'callback_queue.py'
$csv = 'C:\Users\jlync\Downloads\callback-queue.csv'
$log = Join-Path $repo '.callback_queue.log'

function Write-Log($msg) {
    "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) $msg" | Out-File -FilePath $log -Append -Encoding utf8
}

function Show-Toast($title, $body) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $tpl = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $nodes = $tpl.GetElementsByTagName('text')
        $nodes.Item(0).AppendChild($tpl.CreateTextNode($title)) | Out-Null
        $nodes.Item(1).AppendChild($tpl.CreateTextNode($body)) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($tpl)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch {
        Write-Log "Toast failed: $_"
    }
}

try {
    Write-Log 'Run started'
    $py = (Get-Command python).Source
    & $py $script 2>&1 | ForEach-Object { Write-Log "py: $_" }

    if (-not (Test-Path $csv)) {
        Show-Toast 'Callback queue: error' 'CSV not produced — check log.'
        Write-Log 'No CSV produced — aborting'
        exit 1
    }

    $rows = Import-Csv $csv
    $hot = @($rows | Where-Object { $_.Tier -eq 'A-hot-unviewed' }).Count
    $warm = @($rows | Where-Object { $_.Tier -eq 'B-warm-unviewed' }).Count
    $silent = @($rows | Where-Object { $_.Tier -eq 'D-viewed-silent' }).Count

    $exportAge = ((Get-Date) - (Get-ChildItem 'C:\Users\jlync\Downloads\Quotes_Report_*.csv' | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime).TotalHours

    if ($exportAge -gt 36) {
        Show-Toast 'Callback queue: stale export' ("Jobber export is {0:N0}h old — re-run the report." -f $exportAge)
    } elseif ($hot -eq 0 -and $warm -eq 0) {
        Show-Toast 'Callback queue: all clear' 'No unviewed quotes to chase today.'
    } else {
        Show-Toast 'Callback queue ready' "$hot hot, $warm warm, $silent viewed-silent. Opening CSV..."
        Start-Process $csv
    }

    Write-Log "Run done — hot=$hot warm=$warm silent=$silent exportAgeH=$([int]$exportAge)"
} catch {
    Write-Log "ERROR: $_"
    Show-Toast 'Callback queue: error' "$_"
    exit 1
}
