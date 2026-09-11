param(
    [Parameter(Mandatory)][string]$EnvFile,
    [Parameter(Mandatory)][string]$BackupDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$ApiUrl,
    [Parameter(Mandatory)][string]$Python,
    [string]$TaskPrefix = 'ZedBiz-Pilot1',
    [switch]$LocalRehearsal
)
$ErrorActionPreference = 'Stop'
if ($TaskPrefix -notmatch '^[A-Za-z0-9-]+$') { throw 'Invalid task prefix' }
$EnvFile = (Resolve-Path -LiteralPath $EnvFile).Path
$Python = (Resolve-Path -LiteralPath $Python).Path
foreach ($value in @($EnvFile,$BackupDirectory,$OutputDirectory,$ApiUrl,$Python,$PSScriptRoot)) {
    if ($value -match '["\r\n]') { throw 'Invalid command argument' }
}
$operator = [Security.Principal.WindowsIdentity]::GetCurrent().Name
# Interactive token: no password stored. Docker Desktop requires this login session.
$principal = New-ScheduledTaskPrincipal -UserId $operator -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$shell = (Get-Command powershell.exe).Source
$backupScript = Join-Path $PSScriptRoot 'run-pilot-backup.ps1'
$backupArgs = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -EnvFile "{1}" -BackupDirectory "{2}" -Prune' -f $backupScript,$EnvFile,$BackupDirectory
$backupAction = New-ScheduledTaskAction -Execute $shell -Argument $backupArgs
$backupTrigger = New-ScheduledTaskTrigger -Daily -At '02:00'
$monitorScript = Join-Path $PSScriptRoot 'pilot_monitor.py'
$monitorArgs = '"{0}" --env-file "{1}" --backup-directory "{2}" --output-directory "{3}" --api-url "{4}"' -f $monitorScript,$EnvFile,$BackupDirectory,$OutputDirectory,$ApiUrl
if ($LocalRehearsal) { $monitorArgs += ' --local-rehearsal' }
$monitorAction = New-ScheduledTaskAction -Execute $Python -Argument $monitorArgs
$monitorTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
foreach ($name in @("$TaskPrefix-Backup", "$TaskPrefix-Monitor")) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) { throw "Task already exists: $name. Review it before replacement." }
}
Register-ScheduledTask -TaskName "$TaskPrefix-Backup" -Action $backupAction -Trigger $backupTrigger -Settings $settings -Principal $principal -Description 'Daily verified ZedBiz backup; 14 daily and 4 weekly retention.' | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix-Monitor" -Action $monitorAction -Trigger $monitorTrigger -Settings $settings -Principal $principal -Description 'Five-minute ZedBiz health, log counters and backup freshness checks.' | Out-Null
Write-Output 'Tasks registered for the current logged-in operator. Production unattended scheduling requires the chosen host service account.'
