<#
.SYNOPSIS
    Deploys the student shop backend to the Supabase project BMC-ecom1.

.DESCRIPTION
    * links the local project to the Supabase project
    * uploads the edge function secrets (Xendit key + webhook token)
    * deploys the two edge functions
    * applies the SQL migrations

    The secrets are read from supabase/.env.local (which is git ignored).

.PARAMETER Token
    A Supabase personal access token. If it is not given the script uses the
    SUPABASE_ACCESS_TOKEN environment variable or an existing CLI login.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Token sbp_xxxxxxxx
#>
param(
    [string]$Token = $env:SUPABASE_ACCESS_TOKEN
)

$ErrorActionPreference = 'Stop'
$projectRef = 'iiznhatxciycwghihnaq'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$secretsFile = Join-Path $root 'supabase\.env.local'

function Get-Supabase {
    # The .cmd wrapper is used on purpose: PowerShell refuses to run the
    # .ps1 shim when the execution policy is restrictive.
    $npm = Join-Path $env:APPDATA 'npm\supabase.cmd'
    if (Test-Path $npm) { return $npm }

    $command = Get-Command supabase.cmd -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $command = Get-Command supabase -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    throw 'The Supabase CLI was not found. Install it with: npm install -g supabase'
}

$supabase = Get-Supabase
Write-Host "Using $supabase" -ForegroundColor DarkGray

if (-not (Test-Path $secretsFile)) {
    throw "Missing $secretsFile - copy supabase/.env.local.example and add the secrets."
}

# all CLI commands run in the project root (the migrations live in supabase/migrations)
Set-Location $root

# The CLI needs an access token: either a personal access token or a login.
$tokenFile = Join-Path $env:USERPROFILE '.supabase\access-token'
if (-not $Token -and -not (Test-Path $tokenFile)) {
    Write-Host 'No Supabase access token found.' -ForegroundColor Yellow
    Write-Host 'Run "supabase login" first (it opens the browser) and then start this script again.' -ForegroundColor Yellow
    Write-Host 'or create a personal access token (Dashboard -> Account -> Access Tokens) and run:' -ForegroundColor Yellow
    Write-Host '   powershell -ExecutionPolicy Bypass -File deploy.ps1 -Token sbp_xxxxxxxx' -ForegroundColor Yellow
    exit 1
}

$linkArgs = @('link', '--project-ref', $projectRef)
if ($Token) { $linkArgs += @('--token', $Token) }
if ($env:SUPABASE_DB_PASSWORD) { $linkArgs += @('--password', $env:SUPABASE_DB_PASSWORD) }

Write-Host 'Linking the project ...' -ForegroundColor Cyan
& $supabase @linkArgs
if ($LASTEXITCODE -ne 0) { throw 'supabase link failed' }

Write-Host 'Uploading the edge function secrets ...' -ForegroundColor Cyan
& $supabase secrets set --env-file $secretsFile --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw 'supabase secrets set failed' }

Write-Host 'Deploying the edge functions ...' -ForegroundColor Cyan
& $supabase functions deploy create-invoice --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw 'deploying create-invoice failed' }
& $supabase functions deploy xendit-webhook --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw 'deploying xendit-webhook failed' }

Write-Host 'Applying the database migrations ...' -ForegroundColor Cyan
$pushArgs = @('db', 'push', '--project-ref', $projectRef)
if ($env:SUPABASE_DB_PASSWORD) { $pushArgs += @('--password', $env:SUPABASE_DB_PASSWORD) }
& $supabase @pushArgs

Write-Host 'Done. The webhook url for the Xendit dashboard is:' -ForegroundColor Green
Write-Host "  https://$projectRef.supabase.co/functions/v1/xendit-webhook"
