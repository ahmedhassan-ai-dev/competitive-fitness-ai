[CmdletBinding()]
param([switch]$Migrate, [ValidateRange(1024,65535)][int]$Port=8000)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$backend = Join-Path $repo 'services/backend'
$settingsFile = Join-Path $backend '.env.local'
$python = Join-Path $backend '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) {
    throw "Create services/backend/.env.local from .env.example (ignored by Git). See RUN_MULTIPLAYER.md"
}
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Backend virtual environment not found. Set up services/backend/.venv first.'
}
$allowed = @('APP_ENV', 'DATABASE_URL', 'JWT_SECRET', 'JWT_ISSUER', 'JWT_AUDIENCE',
             'JWT_ALGORITHM', 'ACCESS_TOKEN_TTL_SECONDS')
foreach ($line in Get-Content -LiteralPath $settingsFile) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    if ($trimmed -notmatch '^([A-Z_][A-Z_0-9]*)=(.*)$') { throw 'Invalid .env.local line format.' }
    $name = $Matches[1]
    $value = $Matches[2]
    if ($name -notin $allowed) { throw "Unexpected environment setting: $name" }
    if ($value -eq '' -or $value -match '^REPLACE_ME') { throw "Fill environment setting: $name" }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
}
foreach ($required in @('APP_ENV','DATABASE_URL','JWT_SECRET','JWT_ISSUER','JWT_AUDIENCE')) {
    if (-not [Environment]::GetEnvironmentVariable($required, 'Process')) { throw "Missing setting: $required" }
}
Push-Location $backend
try {
    if ($Migrate) {
        Write-Host 'Running explicitly authorized Alembic migrations; confirm a database backup exists.' -ForegroundColor Yellow
        & $python -m alembic -x allow_database_migration=true upgrade head
    } else {
        Write-Host "FastAPI listening on LAN port $Port. Use the PC IPv4 address on phones, NOT localhost." -ForegroundColor Cyan
        Write-Host 'Local HTTP is for private Wi-Fi testing only. Never expose this port to the public internet.' -ForegroundColor Yellow
        & $python -m uvicorn 'app.main:create_configured_app' --factory --host 0.0.0.0 --port $Port
    }
    if ($LASTEXITCODE -ne 0) { throw "Backend exited with code $LASTEXITCODE" }
} finally {
    Pop-Location
}
