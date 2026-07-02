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

function Start-Recovery {
    if (Test-Path -LiteralPath $ControlledExitFlag -PathType Leaf) {
        Remove-Item -LiteralPath $ControlledExitFlag -Force
        exit 0
    }

    try {
        $watched = Get-Process -Id $WatchPid -ErrorAction SilentlyContinue
        if ($watched) {
            Stop-Process -Id $WatchPid -Force
        }
    } catch {
        # The watched process may already be gone.
    }

    $recoveryDir = Split-Path -Parent $RecoveryFlag
    if ($recoveryDir -and -not (Test-Path -LiteralPath $recoveryDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $recoveryDir | Out-Null
    }

    Set-Content -LiteralPath $RecoveryFlag -Value "UNEXPECTED_TERMINATION" -Encoding ASCII

    if (Test-Path -LiteralPath $LauncherPath -PathType Leaf) {
        $cmdLine = 'call ' + [char]34 + $LauncherPath + [char]34 + ' /recover & exit'
        Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/q', '/c', $cmdLine) -WindowStyle Maximized
    }

    exit 0
}

while ($true) {
    if (Test-Path -LiteralPath $ControlledExitFlag -PathType Leaf) {
        Remove-Item -LiteralPath $ControlledExitFlag -Force
        exit 0
    }

    $process = Get-Process -Id $WatchPid -ErrorAction SilentlyContinue
    if (-not $process) {
        Start-Sleep -Milliseconds 500
        Start-Recovery
    }

    $title = $process.MainWindowTitle
    if ($title -and $title -notlike '*STAR_POS_TERMINAL*') {
        Start-Recovery
    }

    Start-Sleep -Seconds 1
}
