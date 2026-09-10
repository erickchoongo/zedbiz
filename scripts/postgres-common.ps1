Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Get-DatabaseConfig([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $config = @{}
    foreach ($line in [IO.File]::ReadAllLines($resolved)) {
        if ($line -match '^([A-Z_]+)=(.*)$') { $config[$Matches[1]] = $Matches[2] }
    }
    foreach ($key in @('POSTGRES_USER', 'POSTGRES_DB')) {
        if (!$config.ContainsKey($key) -or $config[$key] -notmatch '^[a-z][a-z0-9_]{0,62}$') { throw "Invalid $key" }
    }
    return $config
}
function Invoke-DatabaseCompose([string[]]$CommandArgs) {
    & docker compose --env-file $EnvFile -f $ComposeFile @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw 'Database command failed. Credentials are not logged by this script.' }
}
