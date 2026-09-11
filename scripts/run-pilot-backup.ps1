param(
    [Parameter(Mandatory)][string]$EnvFile,
    [Parameter(Mandatory)][string]$BackupDirectory,
    [string]$ComposeFile,
    [switch]$Prune
)
$ErrorActionPreference = 'Stop'
if (!$ComposeFile) { $ComposeFile = Join-Path $PSScriptRoot '../docker-compose.prod.yml' }
New-Item -ItemType Directory -Force -Path $BackupDirectory | Out-Null
$backupRoot = (Resolve-Path -LiteralPath $BackupDirectory).Path
$lock = [IO.File]::Open((Join-Path $backupRoot '.pilot-backup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$event = @{ time = [DateTime]::UtcNow.ToString('o'); status = 'failed' }
try {
    $before = @(Get-ChildItem -LiteralPath $backupRoot -Filter '*.dump' -File | ForEach-Object Name)
    & (Join-Path $PSScriptRoot 'backup-postgres.ps1') -EnvFile $EnvFile -ComposeFile $ComposeFile -BackupDirectory $backupRoot | Out-Null
    $created = @(Get-ChildItem -LiteralPath $backupRoot -Filter '*.dump' -File | Where-Object { $_.Name -notin $before })
    if ($created.Count -ne 1) { throw 'Expected one new backup' }
    $archive = $created[0]
    $event.status = 'success'
    $event.file = $archive.Name
    $event.sha256 = (Get-FileHash -LiteralPath $archive.FullName -Algorithm SHA256).Hash
    $event.bytes = $archive.Length
    # Only this wrapper's successful archives are eligible for retention.
    $cataloguePath = Join-Path $backupRoot 'managed-backups.json'
    $catalogue = @()
    if (Test-Path -LiteralPath $cataloguePath) {
        # Windows PowerShell preserves a JSON array as one pipeline object.
        # Assign before wrapping so multiple records are not nested as one item.
        $loaded = Get-Content -LiteralPath $cataloguePath -Raw | ConvertFrom-Json
        $catalogue = @($loaded)
    }
    $catalogue += [pscustomobject]@{ file = $archive.Name; time = $event.time }
    if ($Prune) {
        $days = @{}; $weeks = @{}; $keep = @{}
        foreach ($item in ($catalogue | Sort-Object time -Descending)) {
            $date = [DateTime]::Parse($item.time).ToUniversalTime()
            $day = $date.ToString('yyyy-MM-dd')
            $week = $date.AddDays(-(([int]$date.DayOfWeek + 6) % 7)).ToString('yyyy-MM-dd')
            if ((!$days.ContainsKey($day) -and $days.Count -lt 14) -or (!$weeks.ContainsKey($week) -and $weeks.Count -lt 4)) {
                $keep[$item.file] = $true
            }
            $days[$day] = $true; $weeks[$week] = $true
        }
        foreach ($item in $catalogue) {
            if ($keep.ContainsKey($item.file)) { continue }
            if ($item.file -notmatch '^zedbiz_\d{4}-\d{2}-\d{2}_\d{6}_[a-f0-9]{8}\.dump$') { throw 'Unsafe retention filename' }
            foreach ($suffix in @('', '.sha256')) {
                $candidate = Join-Path $backupRoot ($item.file + $suffix)
                if (!(Test-Path -LiteralPath $candidate)) { continue }
                $resolved = Get-Item -LiteralPath $candidate
                if ($resolved.DirectoryName -ne $backupRoot -or ($resolved.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe retention target' }
                Remove-Item -LiteralPath $resolved.FullName
            }
        }
        $catalogue = @($catalogue | Where-Object { $keep.ContainsKey($_.file) })
    }
    ConvertTo-Json -InputObject @($catalogue) | Set-Content -LiteralPath $cataloguePath -Encoding UTF8
    $event | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupRoot 'latest-backup.json.tmp') -Encoding UTF8
    Move-Item -LiteralPath (Join-Path $backupRoot 'latest-backup.json.tmp') -Destination (Join-Path $backupRoot 'latest-backup.json') -Force
} catch {
    $event.status = 'failed'
    $event.error_type = $_.Exception.GetType().Name
    throw 'Pilot backup failed; inspect backup-events.jsonl and database service health.'
} finally {
    $event | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $backupRoot 'backup-events.jsonl') -Encoding UTF8
    $event | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $backupRoot 'last-backup-attempt.json') -Encoding UTF8
    $lock.Dispose()
}
Write-Output ($event | ConvertTo-Json -Compress)
