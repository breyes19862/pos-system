param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentVersion,

    [Parameter(Mandatory = $true)]
    [string]$Endpoint,

    [Parameter(Mandatory = $true)]
    [string]$CurrentScript,

    [Parameter(Mandatory = $true)]
    [string]$StageDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Result {
    param(
        [string]$Status,
        [string]$Version = '',
        [string]$StagePath = '',
        [string]$ApplyPath = '',
        [string]$Message = ''
    )

    $safeMessage = $Message -replace '\|', '/'
    Write-Output "$Status|$Version|$StagePath|$ApplyPath|$safeMessage"
}

function Get-VersionFromBatch {
    param([string]$Content)

    $match = [regex]::Match(
        $Content,
        '(?im)^\s*set\s+"?SCRIPT_VERSION\s*=\s*([^"\r\n]+)"?\s*$'
    )

    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value.Trim()
}

try {
    if (-not (Test-Path -LiteralPath $CurrentScript -PathType Leaf)) {
        Write-Result -Status 'ERROR' -Message 'Current script was not found'
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

    $separator = if ($Endpoint.Contains('?')) { '&' } else { '?' }
    $requestUri = "$Endpoint${separator}version=$([uri]::EscapeDataString($CurrentVersion))"
    $response = Invoke-WebRequest -Uri $requestUri -UseBasicParsing -TimeoutSec 15
    $responseBody = [string]$response.Content

    if ([string]::IsNullOrWhiteSpace($responseBody)) {
        Write-Result -Status 'SKIPPED' -Message 'Update service returned an empty response'
        exit 0
    }

    $remoteVersion = $null
    $downloadUrl = $null
    $updateContent = $null

    try {
        $payload = $responseBody | ConvertFrom-Json
        $remoteVersion = [string]$payload.version
        if (-not $remoteVersion) {
            $remoteVersion = [string]$payload.latest_version
        }
        if (-not $remoteVersion) {
            $remoteVersion = [string]$payload.latestVersion
        }
        $downloadUrl = [string]$payload.download_url

        if (-not $downloadUrl) {
            $downloadUrl = [string]$payload.downloadUrl
        }

        if ($payload.script) {
            $updateContent = [string]$payload.script
        } elseif ($payload.content) {
            $updateContent = [string]$payload.content
        } elseif ($payload.update) {
            $updateContent = [string]$payload.update
        }
    } catch {
        $updateContent = $responseBody
        $remoteVersion = Get-VersionFromBatch -Content $updateContent
    }

    if (-not $remoteVersion) {
        Write-Result -Status 'SKIPPED' -Message 'Remote version was not provided'
        exit 0
    }

    if ($remoteVersion.Trim() -eq $CurrentVersion.Trim()) {
        Write-Result -Status 'CURRENT' -Version $remoteVersion
        exit 0
    }

    if (-not $updateContent -and $downloadUrl) {
        $downloadResponse = Invoke-WebRequest -Uri $downloadUrl -UseBasicParsing -TimeoutSec 30
        $updateContent = [string]$downloadResponse.Content
    }

    if ([string]::IsNullOrWhiteSpace($updateContent)) {
        Write-Result -Status 'ERROR' -Version $remoteVersion -Message 'No update script was supplied'
        exit 1
    }

    $scriptVersion = Get-VersionFromBatch -Content $updateContent
    if (-not $scriptVersion) {
        Write-Result -Status 'ERROR' -Version $remoteVersion -Message 'Downloaded script has no SCRIPT_VERSION'
        exit 1
    }

    if ($scriptVersion.Trim() -ne $remoteVersion.Trim()) {
        Write-Result -Status 'ERROR' -Version $remoteVersion -Message 'Downloaded script version mismatch'
        exit 1
    }

    if ($updateContent -notmatch '(?im)^\s*@echo\s+off\s*$') {
        Write-Result -Status 'ERROR' -Version $remoteVersion -Message 'Downloaded script is not a batch launcher'
        exit 1
    }

    $stagePath = Join-Path $StageDir 'POS_Watchdog.update.bat'
    $applyPath = Join-Path $StageDir 'apply_pos_update.bat'
    $backupPath = Join-Path $StageDir ('POS_Watchdog.' + $CurrentVersion + '.bak')
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false

    [System.IO.File]::WriteAllText($stagePath, $updateContent, $utf8NoBom)

    $applyContent = @"
@echo off
setlocal
timeout /t 1 >nul
copy /y "$CurrentScript" "$backupPath" >nul
copy /y "$stagePath" "$CurrentScript" >nul
start "" "$CurrentScript"
exit
"@

    [System.IO.File]::WriteAllText($applyPath, $applyContent, $utf8NoBom)
    Write-Result -Status 'UPDATED' -Version $remoteVersion -StagePath $stagePath -ApplyPath $applyPath
    exit 0
} catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
    exit 1
}
