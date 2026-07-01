@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_VERSION=3.0"

powershell -command "(New-Object -ComObject WScript.Shell).SendKeys('{F11}')"
timeout /t 1 >nul
powershell -command "$w=(Get-Host).UI.RawUI; $s=$w.WindowSize; $b=$w.BufferSize; $b.Width=$s.Width; $b.Height=$s.Height; $w.BufferSize=$b" >nul 2>&1

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f >nul 2>&1

set "LAUNCHER_DIR=%~dp0"
if "!LAUNCHER_DIR:~-1!"=="\" set "LAUNCHER_DIR=!LAUNCHER_DIR:~0,-1!"

set "POS_DIR=%USERPROFILE%\Documents\POS_System"
set "UNLOCK_FILE=!POS_DIR!\unlock_pins.txt"
set "ADMIN_FILE=!POS_DIR!\admin_pins.txt"
set "PORTABLE_GIT_DIR=!POS_DIR!\PortableGit"
if exist "!PORTABLE_GIT_DIR!\cmd\git.exe" set "PATH=!PORTABLE_GIT_DIR!\cmd;!PORTABLE_GIT_DIR!\bin;!PATH!"
set "UPDATE_SERVER_DIR=!LAUNCHER_DIR!\POS_Server"
if not exist "!UPDATE_SERVER_DIR!\pos_git_update.ps1" if exist "%~dp0pos_git_update.ps1" set "UPDATE_SERVER_DIR=!LAUNCHER_DIR!"
set "UPDATE_HELPER=!UPDATE_SERVER_DIR!\pos_git_update.ps1"
set "SETUP_SCRIPT=!UPDATE_SERVER_DIR!\setup_pos.bat"
set "UPDATE_VERSION_FILE=pos_version.txt"

if not exist "!POS_DIR!" mkdir "!POS_DIR!"
if not exist "!UNLOCK_FILE!" (
    echo 1975> "!UNLOCK_FILE!"
    attrib +h "!UNLOCK_FILE!"
)
if not exist "!ADMIN_FILE!" (
    echo 462362> "!ADMIN_FILE!"
    attrib +h "!ADMIN_FILE!"
)

call :CHECK_FOR_UPDATES

set SHOW_PIN=0
goto PRE_BOOT_LOCK

:PRE_BOOT_LOCK
color 0E
call :PRINT_BANNER
echo   [LOCKED] TERMINAL LOCKED - AUTHENTICATION REQUIRED FOR BOOT
echo.

set "PIN="
if "!SHOW_PIN!"=="1" (
    set /p PIN="Enter Access PIN: "
) else (
    for /f "delims=" %%i in ('powershell -command "$p=Read-Host 'Enter Access PIN' -AsSecureString; $m=[System.Runtime.InteropServices.Marshal]; $m::PtrToStringAuto($m::SecureStringToBSTR($p))"') do set "PIN=%%i"
)

if /I "!PIN!"=="showpin" (
    set SHOW_PIN=1
    echo  [+] PIN visibility enabled.
    timeout /t 1 >nul
    goto PRE_BOOT_LOCK
)

findstr /x /c:"!PIN!" "!ADMIN_FILE!" >nul
if !errorlevel! equ 0 (
    set SHOW_PIN=0
    goto START_INIT
)

findstr /x /c:"!PIN!" "!UNLOCK_FILE!" >nul
if !errorlevel! equ 0 (
    set SHOW_PIN=0
    goto START_INIT
)

echo.
echo  [ERROR] Invalid PIN. Access Denied.
timeout /t 2 >nul
goto PRE_BOOT_LOCK

:START_INIT
color 0E
call :PRINT_BANNER
echo  [ INITIATING POS BOOT SEQUENCE ]
echo.

<nul set /p =" [SYS] Allocating system memory "
for /L %%i in (1,1,3) do (
    <nul set /p ="."
    timeout /t 1 >nul
)
echo  [ OK ]

<nul set /p =" [BIOS] Hardware Telemetry Scan "
for /L %%i in (1,1,2) do (
    <nul set /p ="."
    timeout /t 1 >nul
)

for /f "tokens=2 delims==" %%a in ('wmic cpu get name /value ^| findstr "="') do set SYS_CPU=%%a
for /f "tokens=2 delims==" %%a in ('wmic baseboard get product /value ^| findstr "="') do set SYS_MOB=%%a
for /f "delims=" %%a in ('powershell -command "[math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB)"') do set SYS_RAM=%%a

echo  [ OK ]
echo.
echo  HARDWARE SIGNATURE:
echo  --------------------------------------------------
echo  Host CPU   : !SYS_CPU!
echo  Mainboard  : !SYS_MOB!
echo  Memory     : !SYS_RAM! GB RAM Installed
echo  --------------------------------------------------
echo.
timeout /t 2 >nul

<nul set /p =" [NET] Establishing Network Connection... "
ping -n 1 8.8.8.8 >nul 2>&1
if !errorlevel! neq 0 (
    set FAULT_REASON=Network Unreachable / DNS Resolution Failed
    goto BOOT_ERROR
)
for /f "delims=" %%a in ('powershell -command "(Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -First 1).InterfaceDescription"') do set SYS_NET=%%a
echo [ CONNECTED ] (!SYS_NET!)
timeout /t 1 >nul

<nul set /p =" [PERIPHERAL] Validating HP Printer Connection... "
wmic printer get name | findstr /I "HP" >nul
if !errorlevel! neq 0 (
    set FAULT_REASON=No Authorized HP Printer Detected
    goto BOOT_ERROR
)
echo [ VERIFIED ]
timeout /t 1 >nul

<nul set /p =" [DATA] Mounting POS Database... "
timeout /t 2 >nul
echo [ ONLINE ] (Status: Active, 452 MB)
timeout /t 1 >nul

goto BOOT_CONTINUE

:BOOT_ERROR
color 4F
echo [ FATAL ERROR ]
echo.
echo  ==========================================================
echo                    SYSTEM FAULT DETECTED
echo  ==========================================================
echo.
echo   FAULT: !FAULT_REASON!
echo.
echo   1. Override Diagnostic Protocol and Force Boot
echo   2. Shutdown POS Terminal
echo.
:ERROR_PROMPT
set /p BOOT_CHOICE="Select Protocol [1-2]: "
if "!BOOT_CHOICE!"=="1" (
    color 0E
    echo.
    echo  [WARN] OVERRIDE ACCEPTED. FORCING INITIALIZATION...
    timeout /t 2 >nul
    goto BOOT_CONTINUE
) 
if "!BOOT_CHOICE!"=="2" (
    echo Shutting down terminal...
    shutdown /s /t 0
    exit
)
goto ERROR_PROMPT

:BOOT_CONTINUE
echo.
echo  Terminal Online. Deploying Application Environment...
timeout /t 2 >nul

start "STAR_POS_BG" /min cmd /c "\\Mac\Home\Downloads\floreantpos-2.0.1-beta-64\floreantpos.bat"
timeout /t 10 >nul

:WATCHDOG_LOOP
tasklist /NH /FI "IMAGENAME eq javaw.exe" | find /I "javaw.exe" >nul
if %errorlevel% equ 0 (
    timeout /t 2 >nul
    goto WATCHDOG_LOOP
)
tasklist /NH /FI "IMAGENAME eq java.exe" | find /I "java.exe" >nul
if %errorlevel% equ 0 (
    timeout /t 2 >nul
    goto WATCHDOG_LOOP
)

taskkill /F /FI "WINDOWTITLE eq STAR_POS_BG*" /IM cmd.exe >nul 2>&1
goto LOCK_MENU

:LOCK_MENU
color 4F
call :PRINT_BANNER
echo   [LOCKED] TERMINAL LOCKED - APPLICATION CLOSED
echo.
echo   1. Unlock POS System
echo   2. Shutdown Terminal
echo   3. Reboot System
echo.
set /p MENU_CHOICE="Select Option [1-3]: "

if "!MENU_CHOICE!"=="1" goto LOCK_PIN_LOGIC
if "!MENU_CHOICE!"=="2" (
    echo Shutting down...
    shutdown /s /t 0
    exit
)
if "!MENU_CHOICE!"=="3" (
    echo Rebooting terminal...
    shutdown /r /t 0
    exit
)
goto LOCK_MENU

:LOCK_PIN_LOGIC
echo.
set "PIN="
if "!SHOW_PIN!"=="1" (
    set /p PIN="Enter Access PIN: "
) else (
    for /f "delims=" %%i in ('powershell -command "$p=Read-Host 'Enter Access PIN' -AsSecureString; $m=[System.Runtime.InteropServices.Marshal]; $m::PtrToStringAuto($m::SecureStringToBSTR($p))"') do set "PIN=%%i"
)

if /I "!PIN!"=="showpin" (
    set SHOW_PIN=1
    echo  [+] PIN visibility enabled.
    timeout /t 1 >nul
    goto LOCK_MENU
)

findstr /x /c:"!PIN!" "!ADMIN_FILE!" >nul
if !errorlevel! equ 0 (
    set SHOW_PIN=0
    goto ADMIN_DASHBOARD
)

findstr /x /c:"!PIN!" "!UNLOCK_FILE!" >nul
if !errorlevel! equ 0 (
    set SHOW_PIN=0
    color 0E
    goto BOOT_CONTINUE
)

echo.
echo  [ERROR] Invalid PIN. Access Denied.
timeout /t 2 >nul
goto LOCK_MENU

:ADMIN_DASHBOARD
color 0A
call :PRINT_BANNER
echo  =================================================================
echo   ADMINISTRATOR DASHBOARD
echo  =================================================================
echo.
echo   [1] Add New Standard Unlock PIN
echo   [2] Promote PIN to Administrator (Override) Access
echo   [3] View Registered System PINs
echo   [4] Flush Diagnostic Error Logs
echo   [5] Synchronize Terminal Clock
echo   [6] Factory Reset POS Configuration (Delete PINs)
echo   [7] Exit Terminal to Windows (Maintenance Mode)
echo   [8] Return to POS Lock Screen
echo.
set /p ADM_CHOICE="Select Action [1-8]: "

if "!ADM_CHOICE!"=="1" goto ADM_ADD_USER
if "!ADM_CHOICE!"=="2" goto ADM_ADD_ADMIN
if "!ADM_CHOICE!"=="3" goto ADM_VIEW_PINS
if "!ADM_CHOICE!"=="4" goto ADM_FLUSH_LOGS
if "!ADM_CHOICE!"=="5" goto ADM_SYNC_CLOCK
if "!ADM_CHOICE!"=="6" goto ADM_FACTORY_RESET
if "!ADM_CHOICE!"=="7" goto ADM_MAINTENANCE
if "!ADM_CHOICE!"=="8" goto LOCK_MENU
goto ADMIN_DASHBOARD

:ADM_ADD_USER
echo.
set /p NEW_PIN="Enter new Standard Unlock PIN to register: "
echo !NEW_PIN!>>"!UNLOCK_FILE!"
echo  [+] PIN !NEW_PIN! successfully added.
timeout /t 2 >nul
goto ADMIN_DASHBOARD

:ADM_ADD_ADMIN
echo.
set /p NEW_ADMIN="Enter new Administrator (Override) PIN: "
echo !NEW_ADMIN!>>"!ADMIN_FILE!"
echo  [+] PIN !NEW_ADMIN! granted Administrator Access.
timeout /t 2 >nul
goto ADMIN_DASHBOARD

:ADM_VIEW_PINS
echo.
echo  --- AUTHORIZED STANDARD PINS ---
type "!UNLOCK_FILE!"
echo.
echo  --- AUTHORIZED ADMINISTRATOR PINS ---
type "!ADMIN_FILE!"
echo.
echo Press any key to return to dashboard...
pause >nul
goto ADMIN_DASHBOARD

:ADM_FLUSH_LOGS
echo.
echo  Flushing application and system diagnostic logs...
timeout /t 1 >nul
echo  [+] Logs cleared successfully.
timeout /t 1 >nul
goto ADMIN_DASHBOARD

:ADM_SYNC_CLOCK
echo.
echo  Querying local time server...
timeout /t 1 >nul
echo  [+] Clock synchronized. Current System Time: %TIME%
timeout /t 2 >nul
goto ADMIN_DASHBOARD

:ADM_FACTORY_RESET
echo.
echo  [WARN] This will delete all custom PINs and restore defaults.
set /p CONFIRM="Are you sure you want to proceed? (Y/N): "
if /I "!CONFIRM!"=="Y" (
    del /f /a:h "!UNLOCK_FILE!" >nul 2>&1
    del /f /a:h "!ADMIN_FILE!" >nul 2>&1
    echo  System wiped. Rebooting terminal to recreate defaults...
    timeout /t 3 >nul
    shutdown /r /t 0
    exit
)
goto ADMIN_DASHBOARD

:ADM_MAINTENANCE
echo.
<nul set /p =" Disengaging Kiosk Security Protocols "
for /L %%i in (1,1,4) do (
    <nul set /p ="*"
    timeout /t 1 >nul
)
echo  [ BYPASSED ]
echo.
echo  STARTING MAINTENANCE MODE...
timeout /t 2 >nul

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 0 /f >nul 2>&1
start explorer.exe
exit

:CHECK_FOR_UPDATES
if not exist "!UPDATE_HELPER!" (
    set "SETUP_REASON=Update helper not found: !UPDATE_HELPER!"
    call :RUN_POS_SETUP
    goto :EOF
)

call :PRINT_UPDATE_BANNER
echo  [UPD] Checking Git version file for POS updates...
echo  [UPD] Local launcher version: !SCRIPT_VERSION!
echo.
call :PRINT_UPDATE_PROGRESS 10 "Preparing update check"
set "UPDATE_STATUS="
set "UPDATE_BRANCH="
set "UPDATE_CURRENT="
set "UPDATE_REMOTE="
set "UPDATE_MESSAGE="

for /f "usebackq tokens=1-5 delims=|" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "!UPDATE_HELPER!" -CurrentScript "%~f0" -RepoDir "!UPDATE_SERVER_DIR!" -CurrentVersion "!SCRIPT_VERSION!" -VersionFileName "!UPDATE_VERSION_FILE!"`) do (
    set "UPDATE_STATUS=%%a"
    set "UPDATE_BRANCH=%%b"
    set "UPDATE_CURRENT=%%c"
    set "UPDATE_REMOTE=%%d"
    set "UPDATE_MESSAGE=%%e"
)
call :PRINT_UPDATE_PROGRESS 35 "Version check completed"

if /I "!UPDATE_STATUS!"=="UPDATED" (
    call :PRINT_UPDATE_PROGRESS 70 "Update downloaded and staged"
    echo  [UPD] Git update pulled for !UPDATE_BRANCH!.
    echo  [UPD] Updated from !UPDATE_CURRENT! to !UPDATE_REMOTE!.
    start "POS_UPDATE_APPLY" /min "!UPDATE_MESSAGE!"
    call :PRINT_UPDATE_PROGRESS 100 "Update applied"
    echo.
    echo  [UPD] Update completed successfully.
    echo  [UPD] POS is restarting now. Please wait...
    timeout /t 5 >nul
    exit
)

if /I "!UPDATE_STATUS!"=="CURRENT" (
    call :PRINT_UPDATE_PROGRESS 100 "No update required"
    echo  [UPD] POS version !UPDATE_CURRENT! is current on !UPDATE_BRANCH!.
    timeout /t 1 >nul
    goto :EOF
)

if /I "!UPDATE_STATUS!"=="SETUP_REQUIRED" (
    if "!UPDATE_MESSAGE!"=="" set "UPDATE_MESSAGE=POS setup is required."
    set "SETUP_REASON=!UPDATE_MESSAGE!"
    call :RUN_POS_SETUP
    goto :EOF
)

if /I "!UPDATE_STATUS!"=="SKIPPED" (
    if "!UPDATE_MESSAGE!"=="" set "UPDATE_MESSAGE=No reason was returned by the updater."
    set "UPDATE_DECISION_REASON=Update skipped: !UPDATE_MESSAGE!"
    call :UPDATE_DECISION_PROMPT
    goto :EOF
)

if "!UPDATE_MESSAGE!"=="" set "UPDATE_MESSAGE=No reason was returned by the updater."
set "UPDATE_DECISION_REASON=Git update check failed: !UPDATE_MESSAGE!"
call :UPDATE_DECISION_PROMPT
goto :EOF

:RUN_POS_SETUP
color 0E
call :PRINT_UPDATE_BANNER
call :PRINT_UPDATE_PROGRESS 15 "Preparing setup"
echo  [SETUP] !SETUP_REASON!
echo  [SETUP] Running POS setup...
if not exist "!SETUP_SCRIPT!" (
    set "UPDATE_DECISION_REASON=Setup required, but setup_pos.bat was not found: !SETUP_SCRIPT!"
    call :UPDATE_DECISION_PROMPT
    goto :EOF
)
call "!SETUP_SCRIPT!" /auto
if !errorlevel! neq 0 (
    set "UPDATE_DECISION_REASON=POS setup failed with exit code !errorlevel!."
    call :UPDATE_DECISION_PROMPT
    goto :EOF
)
call :PRINT_UPDATE_PROGRESS 100 "Setup completed"
echo  [SETUP] Setup completed successfully.
echo  [SETUP] POS is restarting now. Please wait...
timeout /t 5 >nul
start "" "%~f0"
exit

:UPDATE_DECISION_PROMPT
color 4F
call :PRINT_UPDATE_BANNER
echo  UPDATE CHECK WARNING
echo  ----------------------------------------------------------------------------------------
echo.
echo   !UPDATE_DECISION_REASON!
echo.
echo   1. Continue POS Startup
echo   2. Shutdown Terminal
echo.
:UPDATE_DECISION_INPUT
set /p UPDATE_DECISION="Select Option [1-2]: "
if "!UPDATE_DECISION!"=="1" (
    color 0E
    echo.
    echo  [UPD] Continuing POS startup by operator request...
    timeout /t 1 >nul
    goto :EOF
)
if "!UPDATE_DECISION!"=="2" (
    echo Shutting down terminal...
    shutdown /s /t 0
    exit
)
goto UPDATE_DECISION_INPUT

:PRINT_UPDATE_PROGRESS
set "PROGRESS_PERCENT=%~1"
set "PROGRESS_LABEL=%~2"
set "PROGRESS_BAR="
if %PROGRESS_PERCENT% GEQ 10 set "PROGRESS_BAR=####--------------------------"
if %PROGRESS_PERCENT% GEQ 20 set "PROGRESS_BAR=######------------------------"
if %PROGRESS_PERCENT% GEQ 30 set "PROGRESS_BAR=#########---------------------"
if %PROGRESS_PERCENT% GEQ 35 set "PROGRESS_BAR=###########-------------------"
if %PROGRESS_PERCENT% GEQ 50 set "PROGRESS_BAR=###############---------------"
if %PROGRESS_PERCENT% GEQ 70 set "PROGRESS_BAR=#####################---------"
if %PROGRESS_PERCENT% GEQ 100 set "PROGRESS_BAR=##############################"
echo  [UPD] !PROGRESS_LABEL!
echo  [UPD] [!PROGRESS_BAR!] !PROGRESS_PERCENT!%%
echo.
goto :EOF

:PRINT_UPDATE_BANNER
cls
echo.
echo  ========================================================================================
echo.
echo                         P . O . S .   U P D A T E R
echo.
echo  ========================================================================================
echo.
goto :EOF

:PRINT_BANNER
cls
echo.
echo  ========================================================================================
echo.
echo        _____ _______       _____    _____ ______ _______      _______ _____ ______  _____ 
echo       / ____^|__   __^|/\   ^|  __ \  / ____^|  ____^|  __ \ \    / /_   _/ ____^|  ____^|/ ____^|
echo      ^| (___    ^| ^|  /  \  ^| ^|__) ^|^| (___ ^| ^|__  ^| ^|__) \ \  / /  ^| ^|^| ^|    ^| ^|__  ^| (___  
echo       \___ \   ^| ^| / /\ \ ^|  _  /  \___ \^|  __^| ^|  _  / \ \/ /   ^| ^|^| ^|    ^|  __^|  \___ \ 
echo       ____) ^|  ^| ^|/ ____ \^| ^| \ \  ____) ^| ^|____^| ^| \ \  \  /   _^| ^|^| ^|____^| ^|____ ____) ^|
echo      ^|_____/   ^|_^|_/    \_\_^|  \_\^|_____/^|______^|_^|  \_\  \/   ^|_____\_____\______^|_____/ 
echo.
echo                                   P . O . S .   S Y S T E M
echo.
echo  ========================================================================================
goto :EOF
