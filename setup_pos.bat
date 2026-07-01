@echo off
setlocal EnableDelayedExpansion

set "AUTO_MODE=0"
if /I "%~1"=="/auto" set "AUTO_MODE=1"

:: Setup Registry for Kiosk Lockdown
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f >nul 2>&1

:: POS_Server is the folder this setup script is running from.
set "SERVER_DIR=%~dp0"
if "!SERVER_DIR:~-1!"=="\" set "SERVER_DIR=!SERVER_DIR:~0,-1!"
set "REPO_URL=https://github.com/breyes19862/pos-system.git"
set "REPO_BRANCH=main"
set "GIT_USER_EMAIL=pandora.voters.0q@icloud.com"
set "GIT_USER_NAME=POS System"

:: POS_Watchdog.bat is installed one folder above POS_Server, which is the Desktop in this layout.
for %%I in ("!SERVER_DIR!\..") do set "DESKTOP_DIR=%%~fI"
set "DESKTOP_LAUNCHER=!DESKTOP_DIR!\POS_Watchdog.bat"

:: Create secure storage in the current Windows user's Documents folder.
set "POS_DIR=%USERPROFILE%\Documents\POS_System"
set "UNLOCK_FILE=!POS_DIR!\unlock_pins.txt"
set "ADMIN_FILE=!POS_DIR!\admin_pins.txt"
set "PORTABLE_GIT_DIR=!POS_DIR!\PortableGit"
set "PORTABLE_GIT_CMD=!PORTABLE_GIT_DIR!\cmd\git.exe"

if not exist "!POS_DIR!" mkdir "!POS_DIR!"

if not exist "!UNLOCK_FILE!" (
    echo 1975> "!UNLOCK_FILE!"
)

if not exist "!ADMIN_FILE!" (
    echo 462362> "!ADMIN_FILE!"
)

attrib +h "!POS_DIR!\*.*" >nul 2>&1

call :ENSURE_GIT
if !errorlevel! neq 0 exit /b !errorlevel!

call :CONFIGURE_GIT_SAFE_DIRECTORY
if !errorlevel! neq 0 exit /b !errorlevel!

call :CONFIGURE_GIT_IDENTITY
if !errorlevel! neq 0 exit /b !errorlevel!

call :SYNC_REPO
if !errorlevel! neq 0 exit /b !errorlevel!

if not exist "!SERVER_DIR!\POS_Watchdog.bat" (
    echo [ERROR] POS_Watchdog.bat was not found in !SERVER_DIR!.
    exit /b 1
)

if not exist "!SERVER_DIR!\pos_git_update.ps1" (
    echo [ERROR] pos_git_update.ps1 was not found in !SERVER_DIR!.
    exit /b 1
)

copy /y "!SERVER_DIR!\POS_Watchdog.bat" "!DESKTOP_LAUNCHER!" >nul
if !errorlevel! neq 0 (
    echo [ERROR] Failed to install POS_Watchdog.bat to Desktop.
    exit /b 1
)

echo [+] POS launcher installed to !DESKTOP_LAUNCHER!.
echo [+] POS data folder ready at !POS_DIR!.
echo [+] POS Environment Initialized.
if "!AUTO_MODE!"=="0" pause
exit /b 0

:ENSURE_GIT
git --version >nul 2>&1
if !errorlevel! equ 0 (
    echo [+] Git is installed.
    goto :EOF
)

if exist "!PORTABLE_GIT_CMD!" (
    set "PATH=!PORTABLE_GIT_DIR!\cmd;!PORTABLE_GIT_DIR!\bin;!PATH!"
    git --version >nul 2>&1
    if !errorlevel! equ 0 (
        echo [+] Portable Git is installed.
        goto :EOF
    )
)

echo [WARN] Git is not installed. Installing Git...
winget --version >nul 2>&1
if !errorlevel! equ 0 (
    winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
    if !errorlevel! equ 0 (
        set "PATH=%ProgramFiles%\Git\cmd;%ProgramFiles(x86)%\Git\cmd;!PATH!"
        git --version >nul 2>&1
        if !errorlevel! equ 0 (
            echo [+] Git installed successfully.
            goto :EOF
        )
    )
    echo [WARN] winget Git installation did not complete. Trying Portable Git...
) else (
    echo [WARN] winget is not available. Trying Portable Git...
)

set "POS_PORTABLE_GIT_DIR=!PORTABLE_GIT_DIR!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $target=$env:POS_PORTABLE_GIT_DIR; $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest'; $asset=$release.assets | Where-Object { $_.name -like 'PortableGit-*-64-bit.7z.exe' } | Select-Object -First 1; if (-not $asset) { throw 'Portable Git release asset was not found.' }; $installer=Join-Path $env:TEMP $asset.name; Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer; if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }; New-Item -ItemType Directory -Force -Path $target | Out-Null; $p=Start-Process -FilePath $installer -ArgumentList @('-y', ('-o' + $target)) -Wait -PassThru -NoNewWindow; if ($p.ExitCode -ne 0) { throw ('Portable Git extractor failed with exit code ' + $p.ExitCode + '.') }; $git=Join-Path $target 'cmd\git.exe'; if (-not (Test-Path -LiteralPath $git -PathType Leaf)) { throw 'Portable Git extraction completed, but git.exe was not found.' }"
if !errorlevel! neq 0 (
    echo [ERROR] Portable Git installation failed.
    exit /b 1
)

set "PATH=!PORTABLE_GIT_DIR!\cmd;!PORTABLE_GIT_DIR!\bin;!PATH!"
git --version >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] Git was installed, but it is not available in this command session yet.
    exit /b 1
)

echo [+] Portable Git installed successfully.
goto :EOF

:CONFIGURE_GIT_SAFE_DIRECTORY
echo [*] Configuring Git safe directory for POS_Server...
git config --global --add safe.directory "*"
if !errorlevel! neq 0 (
    echo [ERROR] Failed to configure Git safe.directory.
    exit /b 1
)
goto :EOF

:CONFIGURE_GIT_IDENTITY
echo [*] Configuring Git identity...
git config --global user.email "!GIT_USER_EMAIL!"
if !errorlevel! neq 0 exit /b 1
git config --global user.name "!GIT_USER_NAME!"
if !errorlevel! neq 0 exit /b 1
git config --global --unset-all credential.helper >nul 2>&1
git config --global --unset-all credential.https://github.com.username >nul 2>&1
echo [+] Git email configured as !GIT_USER_EMAIL!.
goto :EOF

:SYNC_REPO
if not exist "!SERVER_DIR!" mkdir "!SERVER_DIR!"
set "GIT_TERMINAL_PROMPT=0"

if not exist "!SERVER_DIR!\.git" (
    echo [*] Initializing POS_Server Git checkout...
    git -C "!SERVER_DIR!" init
    if !errorlevel! neq 0 exit /b 1
)

git -C "!SERVER_DIR!" remote get-url origin >nul 2>&1
if !errorlevel! neq 0 (
    git -C "!SERVER_DIR!" remote add origin "!REPO_URL!"
) else (
    git -C "!SERVER_DIR!" remote set-url origin "!REPO_URL!"
)
if !errorlevel! neq 0 exit /b 1

echo [*] Downloading latest POS files from GitHub...
git -C "!SERVER_DIR!" fetch origin "!REPO_BRANCH!"
if !errorlevel! neq 0 (
    echo [ERROR] GitHub download failed.
    echo [ERROR] If this repository is private, GitHub requires a Personal Access Token instead of an account password.
    echo [ERROR] Clear any saved GitHub username/password and authenticate with a token, then run setup again.
    exit /b 1
)

git -C "!SERVER_DIR!" checkout -B "!REPO_BRANCH!" "origin/!REPO_BRANCH!"
if !errorlevel! neq 0 exit /b 1

git -C "!SERVER_DIR!" reset --hard "origin/!REPO_BRANCH!"
if !errorlevel! neq 0 exit /b 1

echo [+] POS_Server Git checkout is ready.
goto :EOF
