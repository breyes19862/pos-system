@echo off
setlocal EnableDelayedExpansion

:: Setup Registry for Kiosk Lockdown
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f >nul 2>&1

:: POS_Server is the folder this setup script is running from.
set "SERVER_DIR=%~dp0"
if "!SERVER_DIR:~-1!"=="\" set "SERVER_DIR=!SERVER_DIR:~0,-1!"

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
pause
exit /b 0
