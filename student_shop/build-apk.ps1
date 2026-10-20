<#
.SYNOPSIS
    Builds the release APK of the student shop with the configuration of the
    local .env file.

.DESCRIPTION
    * checks that .env exists and contains a real publishable key
    * runs `flutter build apk --release --dart-define-from-file=.env`
    * prints the path of the APK

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build-apk.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root '.env'

if (-not (Test-Path $envFile)) {
    throw "Missing $envFile - copy .env.example to .env and add the publishable key."
}

$values = @{}
foreach ($line in Get-Content $envFile) {
    $trimmed = $line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -le 0) { continue }
    $values[$trimmed.Substring(0, $separator).Trim()] = $trimmed.Substring($separator + 1).Trim()
}

$url = $values['SUPABASE_URL']
$key = $values['SUPABASE_PUBLISHABLE_KEY']

if (-not $url -or $url -notlike 'https://*') {
    throw 'SUPABASE_URL is missing or invalid in .env'
}
if (-not $key) {
    throw 'SUPABASE_PUBLISHABLE_KEY is missing in .env'
}
if ($key -match 'PASTE|YOUR_|<') {
    throw @"
SUPABASE_PUBLISHABLE_KEY still contains a placeholder.

Copy the publishable key of the project into .env:
  Supabase Dashboard -> Project Settings -> API Keys -> Publishable key
"@
}

Write-Host "Using project url: $url" -ForegroundColor DarkGray
Write-Host "Publishable key  : $($key.Substring(0, [Math]::Min(12, $key.Length)))..." -ForegroundColor DarkGray

Set-Location $root
flutter build apk --release --dart-define-from-file=.env
if ($LASTEXITCODE -ne 0) { throw 'the build failed' }

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path $apk) {
    $size = [Math]::Round((Get-Item $apk).Length / 1MB, 1)
    Write-Host "`nAPK ready: $apk ($size MB)" -ForegroundColor Green
    Write-Host 'Install it with: flutter install --release' -ForegroundColor Green
}
