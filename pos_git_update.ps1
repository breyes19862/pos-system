param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentScript,

    [Parameter(Mandatory = $true)]
    [string]$RepoDir,

    [Parameter(Mandatory = $true)]
    [string]$CurrentVersion,

    [string]$VersionFileName = 'pos_version.txt',

    [string]$LauncherFileName = 'POS_Watchdog.bat'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:GIT_TERMINAL_PROMPT = '0'

function Add-PortableGitToPath {
    $portableGitRoot = Join-Path $env:USERPROFILE 'Documents\POS_System\PortableGit'
    $portableGit = Join-Path $portableGitRoot 'cmd\git.exe'

    if (Test-Path -LiteralPath $portableGit -PathType Leaf) {
        $env:PATH = (Join-Path $portableGitRoot 'cmd') + ';' + (Join-Path $portableGitRoot 'bin') + ';' + $env:PATH
    }
}

function Write-Result {
    param(
        [string]$Status,
        [string]$Branch = '',
        [string]$Before = '',
        [string]$After = '',
        [string]$Message = ''
    )

    if (-not $Branch) { $Branch = '-' }
    if (-not $Before) { $Before = '-' }
    if (-not $After) { $After = '-' }
    $safeMessage = $Message -replace '\|', '/'
    Write-Output "$Status|$Branch|$Before|$After|$safeMessage"
}

function Get-VersionFromText {
    param([string]$Content)

    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match '^\s*VER\s*=\s*([0-9]+(?:\.[0-9]+)*)\s*$') {
            return $Matches[1]
        }
    }

    return $null
}

function Get-VersionFromBatch {
    param([string]$Content)

    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match '^\s*set\s+"?SCRIPT_VERSION\s*=\s*([0-9]+(?:\.[0-9]+)*)"?\s*$') {
            return $Matches[1]
        }
    }

    return $null
}

function Invoke-Git {
    param(
        [string]$RepoPath,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & git -C $RepoPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed: $text"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $text
    }
}

try {
    Add-PortableGitToPath

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Result -Status 'SETUP_REQUIRED' -Message 'Git is not installed or not on PATH'
        exit 0
    }

    if (-not (Test-Path -LiteralPath $CurrentScript -PathType Leaf)) {
        Write-Result -Status 'ERROR' -Message 'Current script was not found'
        exit 1
    }

    if (-not (Test-Path -LiteralPath $RepoDir -PathType Container)) {
        Write-Result -Status 'SETUP_REQUIRED' -Message "Git repo folder '$RepoDir' was not found"
        exit 0
    }

    $repoResult = Invoke-Git -RepoPath $RepoDir -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
    if ($repoResult.ExitCode -ne 0 -or -not $repoResult.Output) {
        Write-Result -Status 'SETUP_REQUIRED' -Message 'POS_Server is not inside a Git checkout'
        exit 0
    }

    $repoRoot = $repoResult.Output
    $branch = (Invoke-Git -RepoPath $repoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')).Output
    if (-not $branch -or $branch -eq 'HEAD') {
        Write-Result -Status 'SETUP_REQUIRED' -Message 'POS_Server Git checkout is detached'
        exit 0
    }

    $remote = (Invoke-Git -RepoPath $repoRoot -Arguments @('config', "--get", "branch.$branch.remote") -AllowFailure).Output
    $mergeRef = (Invoke-Git -RepoPath $repoRoot -Arguments @('config', "--get", "branch.$branch.merge") -AllowFailure).Output

    if (-not $remote) {
        $remote = 'origin'
    }

    $remoteBranch = $branch
    if ($mergeRef -match '^refs/heads/(.+)$') {
        $remoteBranch = $Matches[1]
    }

    $localCommit = (Invoke-Git -RepoPath $repoRoot -Arguments @('rev-parse', 'HEAD')).Output
    $CurrentVersion = $CurrentVersion.Trim()

    $dirty = (Invoke-Git -RepoPath $repoRoot -Arguments @('status', '--porcelain', '--untracked-files=no')).Output
    if ($dirty) {
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $CurrentVersion -After $CurrentVersion -Message 'Local tracked files have changes'
        exit 0
    }

    Invoke-Git -RepoPath $repoRoot -Arguments @(
        'fetch',
        '--prune',
        $remote,
        "+refs/heads/${remoteBranch}:refs/remotes/${remote}/${remoteBranch}"
    ) | Out-Null

    $remoteRef = "$remote/$remoteBranch"
    $remoteCommit = (Invoke-Git -RepoPath $repoRoot -Arguments @('rev-parse', $remoteRef)).Output
    $remoteVersionContent = (Invoke-Git -RepoPath $repoRoot -Arguments @('show', "${remoteRef}:${VersionFileName}") -AllowFailure).Output
    if (-not $remoteVersionContent) {
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $CurrentVersion -After $CurrentVersion -Message "Remote version file '$VersionFileName' was not found"
        exit 0
    }

    $remoteVersion = Get-VersionFromText -Content $remoteVersionContent
    if (-not $remoteVersion) {
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $CurrentVersion -After $CurrentVersion -Message "Remote version file must contain VER=number"
        exit 0
    }

    if ($remoteVersion -eq $CurrentVersion) {
        Write-Result -Status 'CURRENT' -Branch $branch -Before $CurrentVersion -After $remoteVersion
        exit 0
    }

    if ($localCommit -eq $remoteCommit) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message 'Version file differs, but this checkout is already at the remote commit'
        exit 1
    }

    if ($localCommit -ne $remoteCommit) {
        $ancestorCheck = Invoke-Git -RepoPath $repoRoot -Arguments @('merge-base', '--is-ancestor', $localCommit, $remoteCommit) -AllowFailure
        if ($ancestorCheck.ExitCode -ne 0) {
            Write-Result -Status 'SKIPPED' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message 'Local branch has diverged from upstream'
            exit 0
        }

        Invoke-Git -RepoPath $repoRoot -Arguments @('pull', '--ff-only', $remote, $remoteBranch) | Out-Null
    }

    $updatedVersionPath = Join-Path $repoRoot $VersionFileName
    if (-not (Test-Path -LiteralPath $updatedVersionPath -PathType Leaf)) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message 'Updated checkout is missing the version file'
        exit 1
    }

    $updatedVersion = Get-VersionFromText -Content (Get-Content -LiteralPath $updatedVersionPath -Raw)
    if ($updatedVersion -ne $remoteVersion) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message 'Updated checkout version does not match remote version'
        exit 1
    }

    $repoLauncherPath = Join-Path $repoRoot $LauncherFileName
    if (-not (Test-Path -LiteralPath $repoLauncherPath -PathType Leaf)) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message "Updated checkout is missing '$LauncherFileName'"
        exit 1
    }

    $updatedScriptVersion = Get-VersionFromBatch -Content (Get-Content -LiteralPath $repoLauncherPath -Raw)
    if ($updatedScriptVersion -ne $remoteVersion) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message 'Updated launcher SCRIPT_VERSION does not match remote version'
        exit 1
    }

    $applyPath = Join-Path $env:TEMP 'apply_pos_update.bat'
    $applyContent = @"
@echo off
setlocal
timeout /t 1 >nul
copy /y "$repoLauncherPath" "$CurrentScript" >nul
if %errorlevel% neq 0 exit /b 1
start "" "$CurrentScript"
exit /b 0
"@

    Set-Content -LiteralPath $applyPath -Value $applyContent -Encoding ASCII

    Write-Result -Status 'UPDATED' -Branch $branch -Before $CurrentVersion -After $remoteVersion -Message $applyPath
    exit 0
} catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
    exit 1
}
