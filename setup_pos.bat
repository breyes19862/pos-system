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

:: POS_Watchdog.bat is installed one folder above POS_Server, which is the Desktop in this layout.
for %%I in ("!SERVER_DIR!\..") do set "DESKTOP_DIR=%%~fI"
set "DESKTOP_LAUNCHER=!DESKTOP_DIR!\POS_Watchdog.bat"

:: Create secure storage in the current Windows user's Documents folder.
set "POS_DIR=%USERPROFILE%\Documents\POS_System"
set "UNLOCK_FILE=!POS_DIR!\unlock_pins.txt"
set "ADMIN_FILE=!POS_DIR!\admin_pins.txt"

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

call :SYNC_REPO
if !errorlevel! neq 0 exit /b !errorlevel!

if not exist "!SERVER_DIR!\POS_Watchdog.bat" (
    echo [!] POS_Watchdog.bat was not found in !SERVER_DIR!.
    exit /b 1
)

if not exist "!SERVER_DIR!\pos_git_update.ps1" (
    echo [!] pos_git_update.ps1 was not found in !SERVER_DIR!.
    exit /b 1
)

copy /y "!SERVER_DIR!\POS_Watchdog.bat" "!DESKTOP_LAUNCHER!" >nul
if !errorlevel! neq 0 (
    echo [!] Failed to install POS_Watchdog.bat to Desktop.
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

echo [!] Git is not installed. Installing Git...
winget --version >nul 2>&1
if !errorlevel! neq 0 (
    echo [!] winget is required to install Git automatically.
    exit /b 1
)

winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
if !errorlevel! neq 0 (
    echo [!] Git installation failed.
    exit /b 1
)

set "PATH=%ProgramFiles%\Git\cmd;%ProgramFiles(x86)%\Git\cmd;%PATH%"
git --version >nul 2>&1
if !errorlevel! neq 0 (
    echo [!] Git installed, but it is not available in this command session yet.
    echo [!] Close this window and run setup_pos.bat again.
    exit /b 1
)

echo [+] Git installed successfully.
goto :EOF

:SYNC_REPO
if not exist "!SERVER_DIR!" mkdir "!SERVER_DIR!"

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
if !errorlevel! neq 0 exit /b 1

git -C "!SERVER_DIR!" checkout -B "!REPO_BRANCH!" "origin/!REPO_BRANCH!"
if !errorlevel! neq 0 exit /b 1

git -C "!SERVER_DIR!" reset --hard "origin/!REPO_BRANCH!"
if !errorlevel! neq 0 exit /b 1

echo [+] POS_Server Git checkout is ready.
goto :EOF
