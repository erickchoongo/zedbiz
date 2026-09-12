param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [ValidateSet('web','apk','appbundle')][string]$Target = 'web',
    [ValidateSet('development','production')][string]$Environment = 'production',
    [string]$Flutter = 'flutter',
    [ValidateRange(15,120)][int]$RequestTimeoutSeconds = 15
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$uri = [Uri]$ApiUrl
if (!$uri.IsAbsoluteUri -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'Invalid API origin' }
if ($Environment -eq 'production' -and ($uri.Scheme -ne 'https' -or $uri.Host -match '(^localhost$|^127\.|^10\.0\.2\.2$|(^|\.)example\.(com|net|org)$)')) { throw 'Production builds require the real HTTPS endpoint, not a template domain' }
if ($Target -ne 'web' -and !(Test-Path -LiteralPath (Join-Path $root 'mobile/android/key.properties'))) { throw 'Signed release requires operator-provided android/key.properties and keystore' }
$line = Get-Content (Join-Path $root 'mobile/pubspec.yaml') | Where-Object { $_ -match '^version: ' }
if ($line -notmatch '^version: (\d+\.\d+\.\d+)\+(\d+)$') { throw 'Expected explicit version and build number' }
$version = $Matches[1]; $number = $Matches[2]
$commit = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit' }
if (& git -C $root status --porcelain) { throw 'Commit reviewed changes before creating an identifiable pilot release' }
$arguments = @('build',$Target,'--release','--no-pub',"--build-name=$version","--build-number=$number","--dart-define=APP_VERSION=$version","--dart-define=APP_BUILD_NUMBER=$number","--dart-define=GIT_COMMIT=$commit","--dart-define=APP_ENV=$Environment","--dart-define=API_BASE_URL=$ApiUrl")
if ($Target -eq 'web') { $arguments += @('--no-wasm-dry-run','--no-web-resources-cdn') }
$arguments += "--dart-define=API_REQUEST_TIMEOUT_SECONDS=$RequestTimeoutSeconds"
Push-Location (Join-Path $root 'mobile')
try {
    & $Flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed' }
} finally { Pop-Location }
