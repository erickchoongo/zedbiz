$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$python = Join-Path $projectRoot 'backend/.venv/Scripts/python.exe'
$previousFixture = $env:ZEDBIZ_SUSPENSION_FIXTURE
Push-Location (Join-Path $projectRoot 'mobile')
try {
    $preparation = & $python (Join-Path $projectRoot 'backend/ops/prepare_zedbiz_suspension_fixture.py')
    if ($LASTEXITCODE -ne 0) { throw 'Local fixture preparation failed; test not started.' }
    $pathLine = @($preparation | Where-Object { $_ -like 'Fixture path: *' })
    if ($pathLine.Count -ne 1) { throw 'Expected exactly one newly generated fixture path.' }
    $env:ZEDBIZ_SUSPENSION_FIXTURE = $pathLine[0].Substring('Fixture path: '.Length)
    & flutter test --no-pub test/admin_access_live_test.dart --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Local Admin Access integration test failed.' }
} finally {
    $env:ZEDBIZ_SUSPENSION_FIXTURE = $previousFixture
    Pop-Location
}
