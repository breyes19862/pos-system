param(
    [Parameter(Mandatory = $true)]
    [int]$WatchPid,

    [Parameter(Mandatory = $true)]
    [string]$LauncherPath,

    [Parameter(Mandatory = $true)]
    [string]$RecoveryFlag,

    [Parameter(Mandatory = $true)]
    [string]$ControlledExitFlag,

    [Parameter(Mandatory = $true)]
    [string]$HeartbeatFile,

    [int]$HeartbeatMaxAgeSeconds = 4,

    [int]$StartupGraceSeconds = 25
)

$ErrorActionPreference = 'SilentlyContinue'

function Test-ControlledExit {
    if (Test-Path -LiteralPath $ControlledExitFlag -PathType Leaf) {
        Remove-Item -LiteralPath $ControlledExitFlag -Force
        return $true
    }
    return $false
}

function Stop-GuardedTree {
    try {
        & taskkill /PID $WatchPid /T /F 2>&1 | Out-Null
    } catch {
        try { Stop-Process -Id $WatchPid -Force } catch {}
    }
}

function Start-Recovery {
    if (Test-ControlledExit) { exit 0 }

    Stop-GuardedTree

    $recoveryDir = Split-Path -Parent $RecoveryFlag
    if ($recoveryDir -and -not (Test-Path -LiteralPath $recoveryDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $recoveryDir | Out-Null
    }

    Set-Content -LiteralPath $RecoveryFlag -Value "UNEXPECTED_TERMINATION" -Encoding ASCII

    if (Test-Path -LiteralPath $LauncherPath -PathType Leaf) {
        $cmdLine = [char]34 + $LauncherPath + [char]34 + ' /recover'
        Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/q', '/c', $cmdLine) -WindowStyle Maximized
    }

    exit 0
}

$deadline = (Get-Date).AddSeconds($StartupGraceSeconds)
$heartbeatSeen = $false

while ($true) {
    if (Test-ControlledExit) { exit 0 }

    $process = Get-Process -Id $WatchPid -ErrorAction SilentlyContinue
    if (-not $process) {
        Start-Sleep -Milliseconds 250
        Start-Recovery
    }

    $heartbeatOk = $false
    if (Test-Path -LiteralPath $HeartbeatFile -PathType Leaf) {
        $heartbeatSeen = $true
        $age = ((Get-Date) - (Get-Item -LiteralPath $HeartbeatFile).LastWriteTime).TotalSeconds
        if ($age -le $HeartbeatMaxAgeSeconds) {
            $heartbeatOk = $true
        }
    } elseif (-not $heartbeatSeen -and (Get-Date) -lt $deadline) {
        # Still inside the startup grace window before the first heartbeat lands.
        $heartbeatOk = $true
    }

    if (-not $heartbeatOk) {
        Start-Recovery
    }

    Start-Sleep -Seconds 1
}
