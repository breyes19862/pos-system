param(
    [Parameter(Mandatory = $true)]
    [int]$WatchPid,

    [Parameter(Mandatory = $true)]
    [string]$LauncherPath,

    [Parameter(Mandatory = $true)]
    [string]$RecoveryFlag,

    [Parameter(Mandatory = $true)]
    [string]$ControlledExitFlag
)

$ErrorActionPreference = 'SilentlyContinue'

try {
    $process = Get-Process -Id $WatchPid -ErrorAction Stop
    Wait-Process -Id $WatchPid
} catch {
    # If the watched process is already gone, continue and decide below.
}

Start-Sleep -Milliseconds 500

if (Test-Path -LiteralPath $ControlledExitFlag -PathType Leaf) {
    Remove-Item -LiteralPath $ControlledExitFlag -Force
    exit 0
}

$recoveryDir = Split-Path -Parent $RecoveryFlag
if ($recoveryDir -and -not (Test-Path -LiteralPath $recoveryDir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $recoveryDir | Out-Null
}

Set-Content -LiteralPath $RecoveryFlag -Value "UNEXPECTED_TERMINATION" -Encoding ASCII

if (Test-Path -LiteralPath $LauncherPath -PathType Leaf) {
    Start-Process -FilePath $LauncherPath
}
