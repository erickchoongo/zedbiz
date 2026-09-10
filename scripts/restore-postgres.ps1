param(
    [Parameter(Mandatory)][string]$EnvFile,
    [string]$ComposeFile,
    [Parameter(Mandatory)][string]$BackupFile,
    [Parameter(Mandatory)][string]$RestoreDatabase,
    [string]$ExpectedCountsFile,
    [switch]$RemoveAfterVerification
)
if (!$ComposeFile) { $ComposeFile = Join-Path $PSScriptRoot '../docker-compose.prod.yml' }
. (Join-Path $PSScriptRoot 'postgres-common.ps1')
$config = Get-DatabaseConfig $EnvFile
if ($RestoreDatabase -notmatch '^zedbiz_restore_[a-z0-9_]{1,45}$' -or $RestoreDatabase -eq $config.POSTGRES_DB) {
    throw 'Restore is allowed only into a new disposable zedbiz_restore_ database'
}
$backup = (Resolve-Path -LiteralPath $BackupFile).Path
$expectedHash = (Get-Content -LiteralPath "$backup.sha256" -Raw).Trim()
if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Backup checksum mismatch' }
$container = (Invoke-DatabaseCompose @('ps', '-q', 'db')).Trim()
if (!$container) { throw 'Database container is not running' }
$remote = '/tmp/zedbiz_restore_' + [guid]::NewGuid().ToString('N') + '.dump'
$verified = $false
try {
    # createdb fails if the destination exists. Never overwrite a database.
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'createdb', '-U', $config.POSTGRES_USER, $RestoreDatabase)
    & docker cp $backup "${container}:$remote"
    if ($LASTEXITCODE -ne 0) { throw 'Restore upload failed' }
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'pg_restore', '-U', $config.POSTGRES_USER, '--dbname', $RestoreDatabase, '--no-owner', '--no-privileges', '--exit-on-error', '--single-transaction', $remote)
    $counts = @{}
    foreach ($table in @('users','businesses','products','inventory_movements','sales','sale_items','debts','debt_payments','expenses','audit_logs')) {
        $count = Invoke-DatabaseCompose @('exec', '-T', 'db', 'psql', '-U', $config.POSTGRES_USER, '-d', $RestoreDatabase, '-At', '-v', 'ON_ERROR_STOP=1', '-c', "SELECT count(*) FROM $table")
        $counts[$table] = [long]($count.Trim())
    }
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'psql', '-U', $config.POSTGRES_USER, '-d', $RestoreDatabase, '-At', '-v', 'ON_ERROR_STOP=1', '-c', 'SELECT version_num FROM alembic_version')
    if ($ExpectedCountsFile) {
        $expected = Get-Content -LiteralPath $ExpectedCountsFile -Raw | ConvertFrom-Json
        foreach ($property in $expected.PSObject.Properties) {
            if (!$counts.ContainsKey($property.Name) -or $counts[$property.Name] -ne $property.Value) { throw "Restore count mismatch: $($property.Name)" }
        }
    }
    $counts | ConvertTo-Json
    $verified = $true
    Write-Output 'Restore transaction and domain counts verified. Restored ownership/grants require explicit setup before any production cutover.'
} finally {
    Invoke-DatabaseCompose @('exec', '-T', 'db', 'rm', '-f', $remote)
    if ($RemoveAfterVerification -and $verified) {
        Invoke-DatabaseCompose @('exec', '-T', 'db', 'dropdb', '-U', $config.POSTGRES_USER, $RestoreDatabase)
        Write-Output 'Verified disposable restore database removed.'
    }
}
