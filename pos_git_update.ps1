param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentScript
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

    if ($localCommit -eq $remoteCommit) {
        Write-Result -Status 'CURRENT' -Branch $branch -Before $localCommit -After $remoteCommit
        exit 0
    }

    $ancestorCheck = Invoke-Git -RepoPath $repoRoot -Arguments @('merge-base', '--is-ancestor', $localCommit, $remoteCommit) -AllowFailure
    if ($ancestorCheck.ExitCode -ne 0) {
        Write-Result -Status 'SKIPPED' -Branch $branch -Before $localCommit -After $remoteCommit -Message 'Local branch has diverged from upstream'
        exit 0
    }

    Invoke-Git -RepoPath $repoRoot -Arguments @('pull', '--ff-only', $remote, $remoteBranch) | Out-Null
    $updatedCommit = (Invoke-Git -RepoPath $repoRoot -Arguments @('rev-parse', 'HEAD')).Output

    if ($updatedCommit -eq $localCommit) {
        Write-Result -Status 'CURRENT' -Branch $branch -Before $localCommit -After $updatedCommit
        exit 0
    }

    Write-Result -Status 'UPDATED' -Branch $branch -Before $localCommit -After $updatedCommit
    exit 0
} catch {
    Write-Result -Status 'ERROR' -Message $_.Exception.Message
    exit 1
}
