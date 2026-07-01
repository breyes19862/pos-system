param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentScript,

    [Parameter(Mandatory = $true)]
    [string]$StateDir,

    [string]$VersionFileName = 'pos_version.txt'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Result {
    param(
        [string]$Status,
        [string]$Branch = '',
        [string]$Before = '',
        [string]$After = '',
        [string]$Message = ''
    )

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

function Convert-ToVersion {
    param([string]$Value)

    try {
        return [version]$Value
    } catch {
        throw "Invalid version number '$Value'"
    }
}

function Save-InstalledVersion {
    param(
        [string]$StatePath,
        [string]$Version
    )

    Set-Content -LiteralPath $StatePath -Value "VER=$Version" -Encoding ASCII
    try {
        & attrib +h $StatePath 2>$null | Out-Null
    } catch {
        # Attribute hiding is best-effort and only applies on Windows.
    }
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
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Result -Status 'SKIPPED' -Message 'Git is not installed or not on PATH'
        exit 0
    }

    if (-not (Test-Path -LiteralPath $CurrentScript -PathType Leaf)) {
        Write-Result -Status 'ERROR' -Message 'Current script was not found'
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

    $scriptDir = Split-Path -Parent $CurrentScript
    $repoResult = Invoke-Git -RepoPath $scriptDir -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
    if ($repoResult.ExitCode -ne 0 -or -not $repoResult.Output) {
        Write-Result -Status 'SKIPPED' -Message 'Launcher is not inside a Git checkout'
        exit 0
    }

    $repoRoot = $repoResult.Output
    $branch = (Invoke-Git -RepoPath $repoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')).Output
    if (-not $branch -or $branch -eq 'HEAD') {
        Write-Result -Status 'SKIPPED' -Message 'Git checkout is detached'
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
    $versionStatePath = Join-Path $StateDir 'installed_pos_version.txt'
    $localVersionPath = Join-Path $repoRoot $VersionFileName
    $installedVersion = $null

    if (Test-Path -LiteralPath $versionStatePath -PathType Leaf) {
        $installedVersion = Get-VersionFromText -Content (Get-Content -LiteralPath $versionStatePath -Raw)
    }

    if (-not $installedVersion -and (Test-Path -LiteralPath $localVersionPath -PathType Leaf)) {
        $installedVersion = Get-VersionFromText -Content (Get-Content -LiteralPath $localVersionPath -Raw)
    }

    if (-not $installedVersion) {
        $installedVersion = '0.0'
    }

    $dirty = (Invoke-Git -RepoPath $repoRoot -Arguments @('status', '--porcelain', '--untracked-files=no')).Output
    if ($dirty) {
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $localCommit -After $localCommit -Message 'Local tracked files have changes'
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
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $installedVersion -After $installedVersion -Message "Remote version file '$VersionFileName' was not found"
        exit 0
    }

    $remoteVersion = Get-VersionFromText -Content $remoteVersionContent
    if (-not $remoteVersion) {
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $installedVersion -After $installedVersion -Message "Remote version file must contain VER=number"
        exit 0
    }

    $installedVersionValue = Convert-ToVersion -Value $installedVersion
    $remoteVersionValue = Convert-ToVersion -Value $remoteVersion

    if ($remoteVersionValue -le $installedVersionValue) {
        Save-InstalledVersion -StatePath $versionStatePath -Version $installedVersion
        Write-Result -Status 'CURRENT' -Branch $branch -Before $installedVersion -After $remoteVersion
        exit 0
    }

    if ($localCommit -ne $remoteCommit) {
        $ancestorCheck = Invoke-Git -RepoPath $repoRoot -Arguments @('merge-base', '--is-ancestor', $localCommit, $remoteCommit) -AllowFailure
        if ($ancestorCheck.ExitCode -ne 0) {
            Write-Result -Status 'SKIPPED' -Branch $branch -Before $installedVersion -After $remoteVersion -Message 'Local branch has diverged from upstream'
            exit 0
        }

        Invoke-Git -RepoPath $repoRoot -Arguments @('pull', '--ff-only', $remote, $remoteBranch) | Out-Null
    }

    $updatedVersionPath = Join-Path $repoRoot $VersionFileName
    if (-not (Test-Path -LiteralPath $updatedVersionPath -PathType Leaf)) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $installedVersion -After $remoteVersion -Message 'Updated checkout is missing the version file'
        exit 1
    }

    $updatedVersion = Get-VersionFromText -Content (Get-Content -LiteralPath $updatedVersionPath -Raw)
    if ($updatedVersion -ne $remoteVersion) {
        Write-Result -Status 'ERROR' -Branch $branch -Before $installedVersion -After $remoteVersion -Message 'Updated checkout version does not match remote version'
        exit 1
    }

    Save-InstalledVersion -StatePath $versionStatePath -Version $remoteVersion

    if ($localCommit -eq $remoteCommit) {
        Write-Result -Status 'CURRENT' -Branch $branch -Before $remoteVersion -After $remoteVersion
        exit 0
    }

    Write-Result -Status 'UPDATED' -Branch $branch -Before $installedVersion -After $remoteVersion
    exit 0
} catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
    exit 1
}
