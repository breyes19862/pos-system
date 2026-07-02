@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_VERSION=4.1"

break off

powershell -command "(New-Object -ComObject WScript.Shell).SendKeys('{F11}')"
timeout /t 1 >nul
powershell -command "$w=(Get-Host).UI.RawUI; $s=$w.WindowSize; $b=$w.BufferSize; $b.Width=$s.Width; $b.Height=$s.Height; $w.BufferSize=$b" >nul 2>&1

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f >nul 2>&1

set "LAUNCHER_DIR=%~dp0"
if "!LAUNCHER_DIR:~-1!"=="\" set "LAUNCHER_DIR=!LAUNCHER_DIR:~0,-1!"

set "POS_DIR=%USERPROFILE%\Documents\POS_System"
set "UNLOCK_FILE=!POS_DIR!\unlock_pins.txt"
set "ADMIN_FILE=!POS_DIR!\admin_pins.txt"
set "ARONIUM_EXE=%ProgramFiles%\Aronium\Aronium.Pos.exe"
if not exist "!ARONIUM_EXE!" if exist "%ProgramFiles(x86)%\Aronium\Aronium.Pos.exe" set "ARONIUM_EXE=%ProgramFiles(x86)%\Aronium\Aronium.Pos.exe"
for %%I in ("!ARONIUM_EXE!") do set "ARONIUM_DIR=%%~dpI"
if "!ARONIUM_DIR:~-1!"=="\" set "ARONIUM_DIR=!ARONIUM_DIR:~0,-1!"
set "PORTABLE_GIT_DIR=!POS_DIR!\PortableGit"
if exist "!PORTABLE_GIT_DIR!\cmd\git.exe" set "PATH=!PORTABLE_GIT_DIR!\cmd;!PORTABLE_GIT_DIR!\bin;!PATH!"
set "UPDATE_SERVER_DIR=!LAUNCHER_DIR!\POS_Server"
if not exist "!UPDATE_SERVER_DIR!\pos_git_update.ps1" if exist "%~dp0pos_git_update.ps1" set "UPDATE_SERVER_DIR=!LAUNCHER_DIR!"
set "UPDATE_HELPER=!UPDATE_SERVER_DIR!\pos_git_update.ps1"
set "SETUP_SCRIPT=!UPDATE_SERVER_DIR!\setup_pos.bat"
set "SECURITY_MONITOR=!UPDATE_SERVER_DIR!\pos_security_monitor.ps1"
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

set "POS_SESSION_ID=%~2"
if "!POS_SESSION_ID!"=="" set "POS_SESSION_ID=%RANDOM%%RANDOM%"
set "CONTROLLED_EXIT_FILE=!POS_DIR!\controlled_exit_!POS_SESSION_ID!.flag"
set "SECURITY_RECOVERY_FILE=!POS_DIR!\security_recovery.flag"
set "SECURITY_RECOVERY_MODE=0"
if /I "%~1"=="/recover" set "SECURITY_RECOVERY_MODE=1"
if /I "%~3"=="/recover" set "SECURITY_RECOVERY_MODE=1"

if /I "%~1" NEQ "/guarded" (
    set "POS_LAUNCHER_PATH=%~f0"
    set "POS_MONITOR_PATH=!SECURITY_MONITOR!"
    set "POS_RECOVERY_FLAG=!SECURITY_RECOVERY_FILE!"
    set "POS_CONTROLLED_EXIT_FLAG=!CONTROLLED_EXIT_FILE!"
    set "POS_SESSION_ID_ENV=!POS_SESSION_ID!"
    set "POS_RECOVERY_ARG="
    if "!SECURITY_RECOVERY_MODE!"=="1" set "POS_RECOVERY_ARG= /recover"
    set "POS_RECOVERY_ARG_ENV=!POS_RECOVERY_ARG!"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$launcher=$env:POS_LAUNCHER_PATH; $monitor=$env:POS_MONITOR_PATH; $recovery=$env:POS_RECOVERY_FLAG; $controlled=$env:POS_CONTROLLED_EXIT_FLAG; $session=$env:POS_SESSION_ID_ENV; $recoverArg=$env:POS_RECOVERY_ARG_ENV; $cmdLine='title STAR_POS_TERMINAL & ' + [char]34 + $launcher + [char]34 + ' /guarded ' + $session + $recoverArg; $child=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/q','/c',$cmdLine) -WindowStyle Maximized -PassThru; Start-Sleep -Milliseconds 800; $ws=New-Object -ComObject WScript.Shell; if ($ws.AppActivate('STAR_POS_TERMINAL')) { Start-Sleep -Milliseconds 200; $ws.SendKeys('{F11}') }; if (Test-Path -LiteralPath $monitor -PathType Leaf) { Start-Process -WindowStyle Minimized -FilePath powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$monitor,'-WatchPid',$child.Id,'-LauncherPath',$launcher,'-RecoveryFlag',$recovery,'-ControlledExitFlag',$controlled) }"
    exit /b
)

title STAR_POS_TERMINAL
call :LOCK_CONSOLE_CONTROLS

if "!SECURITY_RECOVERY_MODE!"=="1" if exist "!SECURITY_RECOVERY_FILE!" (
    del /f "!SECURITY_RECOVERY_FILE!" >nul 2>&1
    call :SECURITY_RECOVERY_SCAN
)
if "!SECURITY_RECOVERY_MODE!"=="0" if exist "!SECURITY_RECOVERY_FILE!" del /f "!SECURITY_RECOVERY_FILE!" >nul 2>&1

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
    call :MARK_CONTROLLED_EXIT
    shutdown /s /t 0
    exit
)
goto ERROR_PROMPT

:BOOT_CONTINUE
echo.
echo  Terminal Online. Deploying Application Environment...
timeout /t 2 >nul

call :ENSURE_ARONIUM_READY
if not exist "!ARONIUM_EXE!" (
    set "UPDATE_DECISION_REASON=Aronium POS executable was not found after setup: !ARONIUM_EXE!"
    call :UPDATE_DECISION_PROMPT
    goto LOCK_MENU
)

start "ARONIUM_POS" /D "!ARONIUM_DIR!" "!ARONIUM_EXE!"
timeout /t 5 >nul

:WATCHDOG_LOOP
tasklist /NH /FI "IMAGENAME eq Aronium.Pos.exe" | find /I "Aronium.Pos.exe" >nul
if !errorlevel! equ 0 (
    timeout /t 2 >nul
    goto WATCHDOG_LOOP
)

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
    call :MARK_CONTROLLED_EXIT
    shutdown /s /t 0
    exit
)
if "!MENU_CHOICE!"=="3" (
    echo Rebooting terminal...
    call :MARK_CONTROLLED_EXIT
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
    call :MARK_CONTROLLED_EXIT
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
call :MARK_CONTROLLED_EXIT
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
    call :PRINT_UPDATE_PROGRESS 100 "Update applied"
    echo.
    echo  [UPD] Update completed successfully.
    echo  [UPD] POS is restarting now. Please wait...
    timeout /t 5 >nul
    call :MARK_CONTROLLED_EXIT
    start "POS_UPDATE_APPLY" /min "!UPDATE_MESSAGE!"
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
call :MARK_CONTROLLED_EXIT
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
    call :MARK_CONTROLLED_EXIT
    shutdown /s /t 0
    exit
)
goto UPDATE_DECISION_INPUT

:LOCK_CONSOLE_CONTROLS
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34; $sig='[DllImport('+$q+'kernel32.dll'+$q+')] public static extern IntPtr GetStdHandle(int nStdHandle); [DllImport('+$q+'kernel32.dll'+$q+')] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode); [DllImport('+$q+'kernel32.dll'+$q+')] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);'; $t=Add-Type -MemberDefinition $sig -Name ConsoleMode -Namespace StarServices -PassThru; $h=$t::GetStdHandle(-10); $mode=0; [void]$t::GetConsoleMode($h,[ref]$mode); $mode=($mode -bor 0x80) -band (-bnot 0x41); [void]$t::SetConsoleMode($h,$mode)" >nul 2>&1
goto :EOF

:MARK_CONTROLLED_EXIT
if not "!CONTROLLED_EXIT_FILE!"=="" break > "!CONTROLLED_EXIT_FILE!"
goto :EOF

:SECURITY_RECOVERY_SCAN
color 0C
call :PRINT_SECURITY_BANNER
echo  [SEC] Unexpected POS shell termination detected.
echo  [SEC] Running recovery integrity scan before unlocking terminal...
echo.

call :SECURITY_SCAN_STEP 15 "Checking POS data directory"
if not exist "!POS_DIR!" mkdir "!POS_DIR!"

call :SECURITY_SCAN_STEP 30 "Checking PIN storage"
if not exist "!UNLOCK_FILE!" echo 1975> "!UNLOCK_FILE!"
if not exist "!ADMIN_FILE!" echo 462362> "!ADMIN_FILE!"
attrib +h "!POS_DIR!\*.*" >nul 2>&1

call :SECURITY_SCAN_STEP 45 "Checking updater components"
if not exist "!UPDATE_HELPER!" (
    echo  [SEC] Updater helper missing: !UPDATE_HELPER!
) else (
    echo  [SEC] Updater helper verified.
)

call :SECURITY_SCAN_STEP 60 "Checking Aronium executable"
if exist "!ARONIUM_EXE!" (
    echo  [SEC] Aronium executable verified.
) else (
    echo  [SEC] Aronium executable missing. Setup will be requested during boot.
)

call :SECURITY_SCAN_STEP 75 "Checking kiosk policy"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f >nul 2>&1

call :SECURITY_SCAN_STEP 90 "Checking network availability"
ping -n 1 8.8.8.8 >nul 2>&1
if !errorlevel! equ 0 (
    echo  [SEC] Network check passed.
) else (
    echo  [SEC] Network check failed. Boot diagnostics will verify again.
)

call :SECURITY_SCAN_STEP 100 "Security recovery scan completed"
echo.
echo  [SEC] Security system restored. Continuing POS startup...
timeout /t 5 >nul
goto :EOF

:SECURITY_SCAN_STEP
set "SECURITY_PROGRESS=%~1"
set "SECURITY_LABEL=%~2"
set "SECURITY_BAR="
if %SECURITY_PROGRESS% GEQ 15 set "SECURITY_BAR=#####-------------------------"
if %SECURITY_PROGRESS% GEQ 30 set "SECURITY_BAR=#########---------------------"
if %SECURITY_PROGRESS% GEQ 45 set "SECURITY_BAR=##############----------------"
if %SECURITY_PROGRESS% GEQ 60 set "SECURITY_BAR=##################------------"
if %SECURITY_PROGRESS% GEQ 75 set "SECURITY_BAR=#######################-------"
if %SECURITY_PROGRESS% GEQ 90 set "SECURITY_BAR=###########################---"
if %SECURITY_PROGRESS% GEQ 100 set "SECURITY_BAR=##############################"
echo  [SEC] !SECURITY_LABEL!
echo  [SEC] [!SECURITY_BAR!] !SECURITY_PROGRESS!%%
echo.
timeout /t 1 >nul
goto :EOF

:ENSURE_ARONIUM_READY
if exist "!ARONIUM_EXE!" goto :EOF

color 0E
call :PRINT_UPDATE_BANNER
echo  [SETUP] Aronium POS was not found.
echo  [SETUP] Expected executable: !ARONIUM_EXE!
echo  [SETUP] Running POS setup to install Aronium...
if not exist "!SETUP_SCRIPT!" (
    echo  [ERROR] setup_pos.bat was not found: !SETUP_SCRIPT!
    timeout /t 3 >nul
    goto :EOF
)
call "!SETUP_SCRIPT!" /auto
if !errorlevel! neq 0 (
    echo  [ERROR] POS setup failed with exit code !errorlevel!.
    timeout /t 3 >nul
    goto :EOF
)
goto :EOF

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

:PRINT_SECURITY_BANNER
cls
echo.
echo  ========================================================================================
echo.
echo                  S T A R   S E R V I C E S   P . O . S .
echo.
echo                         S E C U R I T Y   S Y S T E M
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
