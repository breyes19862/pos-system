param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest'
$asset = $release.assets |
    Where-Object { $_.name -like 'PortableGit-*-64-bit.7z.exe' } |
    Select-Object -First 1

if (-not $asset) {
    throw 'Portable Git release asset was not found.'
}

$installerPath = Join-Path $env:TEMP $asset.name
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath

if (Test-Path -LiteralPath $TargetDir) {
    Remove-Item -LiteralPath $TargetDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

$extractArgs = @(
    '-y',
    "-o$TargetDir"
)

$process = Start-Process -FilePath $installerPath -ArgumentList $extractArgs -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    throw "Portable Git extractor failed with exit code $($process.ExitCode)."
}

$gitPath = Join-Path $TargetDir 'cmd\git.exe'
if (-not (Test-Path -LiteralPath $gitPath -PathType Leaf)) {
    throw 'Portable Git extraction completed, but git.exe was not found.'
}
