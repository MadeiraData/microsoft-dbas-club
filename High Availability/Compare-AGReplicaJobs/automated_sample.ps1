Param
(
[string]$ComputerName = "ACMESQL",
[string]$outputFolder = "",
[string]$emailFrom = "alerts@acme.com",
[string]$emailTo = @("john.c@acme.com", "ryan.s@acme.com"),
[string]$emailServerAddress = "ACMESMTP",
[string]$logFileFolderPath = "C:\Madeira\log",
[string]$logFilePrefix = "ag_job_compare_",
[string]$logFileDateFormat = "yyyyMMdd",
[int]$logFileRetentionDays = 30
)
Process {
#region initialization
function Get-TimeStamp {
    Param(
    [switch]$NoWrap,
    [switch]$Utc
    )
    $dt = Get-Date
    if ($Utc -eq $true) {
        $dt = $dt.ToUniversalTime()
    }
    $str = "{0:MM/dd/yy} {0:HH:mm:ss}" -f $dt

    if ($NoWrap -ne $true) {
        $str = "[$str]"
    }
    return $str
}

if ($logFileFolderPath -ne "")
{
    if (!(Test-Path -PathType Container -Path $logFileFolderPath)) {
        Write-Output "$(Get-TimeStamp) Creating directory $logFileFolderPath" | Out-Null
        New-Item -ItemType Directory -Force -Path $logFileFolderPath | Out-Null
    } else {
        $DatetoDelete = $(Get-Date).AddDays(-$logFileRetentionDays)
        Get-ChildItem $logFileFolderPath | Where-Object { $_.Name -like "*$logFilePrefix*" -and $_.LastWriteTime -lt $DatetoDelete } | Remove-Item | Out-Null
    }
    
    $logFilePath = $logFileFolderPath + "\$logFilePrefix" + (Get-Date -Format $logFileDateFormat) + ".LOG"

    try 
    {
        Start-Transcript -Path $logFilePath -Append
    }
    catch [Exception]
    {
        Write-Warning "$(Get-TimeStamp) Unable to start Transcript: $($_.Exception.Message)"
        $logFileFolderPath = ""
    }
}
#endregion initialization


Import-Module C:\Madeira\Compare-AGReplicaJobs.psd1;

Compare-AGReplicaJobs -From $emailFrom -To $emailTo -EmailServer $emailServerAddress -ComputerName $ComputerName -outputFolder $outputFolder -Verbose

Remove-Module Compare-AGReplicaJobs


if ($outputFolder -eq "" -or -not (Test-Path $outputFolder)) {
    $outputFolder = [System.IO.Path]::GetTempPath()
    $DatetoDelete = $(Get-Date).AddDays(-$logFileRetentionDays)
    Get-ChildItem $outputFolder | Where-Object { $_.Name -like "*_align_jobs_*.sql" -and $_.LastWriteTime -lt $DatetoDelete } | Remove-Item | Out-Null
    Get-ChildItem $outputFolder | Where-Object { $_.Name -like "*jobs_comparison_report_*.html" -and $_.LastWriteTime -lt $DatetoDelete } | Remove-Item | Out-Null
}



if ($logFileFolderPath -ne "") { Stop-Transcript }
}