param(
    [Parameter(Mandatory)][string]$EnvFile,
    [string]$ComposeFile,
    [Parameter(Mandatory)][string]$BackupDirectory,
    [string]$Database
)
if (!$ComposeFile) { $ComposeFile = Join-Path $PSScriptRoot '../docker-compose.prod.yml' }
. (Join-Path $PSScriptRoot 'postgres-common.ps1')
$config = Get-DatabaseConfig $EnvFile
if (!$Database) { $Database = $config.POSTGRES_DB }
if ($Database -notmatch '^[a-z][a-z0-9_]{0,62}$') { throw 'Invalid database name' }
New-Item -ItemType Directory -Force -Path $BackupDirectory | Out-Null
$backupRoot = (Resolve-Path -LiteralPath $BackupDirectory).Path
$name = 'zedbiz_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '_' + ([guid]::NewGuid().ToString('N').Substring(0,8)) + '.dump'
$destination = Join-Path $backupRoot $name
$remote = '/tmp/' + $name
$container = (Invoke-DatabaseCompose @('ps', '-q', 'db')).Trim()
if (!$container) { throw 'Database container is not running' }
try {
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'pg_dump', '-U', $config.POSTGRES_USER, '-d', $Database, '--format=custom', '--file', $remote)
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'pg_restore', '--list', $remote) | Out-Null
    & docker cp "${container}:$remote" $destination
    if ($LASTEXITCODE -ne 0) { throw 'Backup copy failed' }
    if ((Get-Item -LiteralPath $destination).Length -eq 0) { throw 'Empty backup' }
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Set-Content -LiteralPath "$destination.sha256" -Encoding ASCII
    Write-Output "Backup verified as a readable archive: $destination"
    Write-Output 'A restore drill is required to prove recovery. No older backups were removed.'
} finally {
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'rm', '-f', $remote)
}
