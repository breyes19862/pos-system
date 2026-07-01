@echo off
setlocal EnableDelayedExpansion

set "SERVER_DIR=C:\Mac\Home\Desktop\POS_Server"
set "DESKTOP_LAUNCHER=C:\Mac\Home\Desktop\POS_Watchdog.bat"
set "POS_DIR=C:\Users\bryanreyeslopez\Documents\POS_System"
set "UNLOCK_FILE=!POS_DIR!\unlock_pins.txt"
set "ADMIN_FILE=!POS_DIR!\admin_pins.txt"

if not exist "!POS_DIR!" mkdir "!POS_DIR!"

if not exist "!UNLOCK_FILE!" (
    echo 1975> "!UNLOCK_FILE!"
    attrib +h "!UNLOCK_FILE!" >nul 2>&1
)

if not exist "!ADMIN_FILE!" (
    echo 462362> "!ADMIN_FILE!"
    attrib +h "!ADMIN_FILE!" >nul 2>&1
)

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
exit /b 0
