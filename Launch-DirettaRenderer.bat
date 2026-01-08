@echo off
setlocal EnableDelayedExpansion

:: Diretta UPnP Renderer Launcher for Windows
:: Requires Administrator privileges for network operations

title Diretta UPnP Renderer

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo ============================================================
    echo   Administrator privileges required!
    echo ============================================================
    echo.
    echo Right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: Set paths
set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\x64\Release"
set "EXE=%BIN_DIR%\DirettaRendererUPnP.exe"
set "VCPKG_BIN=C:\vcpkg\installed\x64-windows\bin"

:: Check if executable exists
if not exist "%EXE%" (
    echo.
    echo ERROR: DirettaRendererUPnP.exe not found at:
    echo   %EXE%
    echo.
    echo Please build the project first.
    pause
    exit /b 1
)

:: Copy DLLs if needed
if not exist "%BIN_DIR%\libupnp.dll" (
    echo.
    echo Copying required DLLs...
    if exist "%VCPKG_BIN%" (
        copy "%VCPKG_BIN%\*.dll" "%BIN_DIR%\" >nul
        echo DLLs copied successfully.
    ) else (
        echo WARNING: vcpkg bin folder not found at %VCPKG_BIN%
        echo You may need to copy DLLs manually.
    )
)

:MENU
cls
echo.
echo ============================================================
echo   Diretta UPnP Renderer - Windows Launcher
echo ============================================================
echo.
echo   1. List available Diretta targets
echo   2. Start renderer (auto-select target)
echo   3. Start renderer with specific target
echo   4. Start renderer with custom options
echo   5. Start renderer (verbose mode)
echo   6. Configure Windows Firewall
echo   7. Exit
echo.
set /p choice="Select option [1-7]: "

if "%choice%"=="1" goto LIST_TARGETS
if "%choice%"=="2" goto START_AUTO
if "%choice%"=="3" goto START_TARGET
if "%choice%"=="4" goto START_CUSTOM
if "%choice%"=="5" goto START_VERBOSE
if "%choice%"=="6" goto CONFIGURE_FIREWALL
if "%choice%"=="7" goto END
goto MENU

:LIST_TARGETS
cls
echo.
echo Scanning for Diretta targets...
echo.
"%EXE%" --list-targets
echo.
pause
goto MENU

:START_AUTO
cls
echo.
echo Starting Diretta Renderer...
echo Press Ctrl+C to stop.
echo.
"%EXE%"
pause
goto MENU

:START_TARGET
cls
echo.
set /p target="Enter target number (1, 2, 3...): "
echo.
echo Starting Diretta Renderer with target %target%...
echo Press Ctrl+C to stop.
echo.
"%EXE%" --target %target%
pause
goto MENU

:START_CUSTOM
cls
echo.
echo Current options:
echo   --name, -n ^<name^>       Renderer name
echo   --port, -p ^<port^>       UPnP port
echo   --target, -t ^<index^>    Diretta target index
echo   --verbose               Debug output
echo   --no-gapless            Disable gapless playback
echo.
set /p target="Enter target number: "
set /p name="Enter renderer name (or press Enter for default): "
set /p port="Enter port (or press Enter for auto): "
echo.

set "ARGS=--target %target%"
if not "%name%"=="" set "ARGS=%ARGS% --name "%name%""
if not "%port%"=="" set "ARGS=%ARGS% --port %port%"

echo Starting: DirettaRendererUPnP.exe %ARGS%
echo Press Ctrl+C to stop.
echo.
"%EXE%" %ARGS%
pause
goto MENU

:START_VERBOSE
cls
echo.
set /p target="Enter target number (1, 2, 3...): "
echo.
echo Starting Diretta Renderer in verbose mode...
echo Press Ctrl+C to stop.
echo.
"%EXE%" --target %target% --verbose
pause
goto MENU

:CONFIGURE_FIREWALL
cls
echo.
echo ============================================================
echo   Configuring Windows Firewall
echo ============================================================
echo.
echo Adding firewall rules for Diretta Renderer...
echo.

netsh advfirewall firewall add rule name="Diretta Renderer" dir=in action=allow program="%EXE%" enable=yes profile=any >nul 2>&1
if %errorLevel% equ 0 (echo   [OK] Diretta Renderer - Inbound) else (echo   [SKIP] Diretta Renderer - Inbound already exists)

netsh advfirewall firewall add rule name="Diretta Renderer Out" dir=out action=allow program="%EXE%" enable=yes profile=any >nul 2>&1
if %errorLevel% equ 0 (echo   [OK] Diretta Renderer - Outbound) else (echo   [SKIP] Diretta Renderer - Outbound already exists)

netsh advfirewall firewall add rule name="UPnP SSDP Discovery" dir=in action=allow protocol=udp localport=1900 enable=yes profile=any >nul 2>&1
if %errorLevel% equ 0 (echo   [OK] UPnP SSDP Discovery - Inbound) else (echo   [SKIP] UPnP SSDP Discovery already exists)

netsh advfirewall firewall add rule name="UPnP SSDP Multicast" dir=out action=allow protocol=udp remoteport=1900 enable=yes profile=any >nul 2>&1
if %errorLevel% equ 0 (echo   [OK] UPnP SSDP Multicast - Outbound) else (echo   [SKIP] UPnP SSDP Multicast already exists)

netsh advfirewall firewall add rule name="UPnP HTTP" dir=in action=allow protocol=tcp localport=49152-65535 enable=yes profile=any >nul 2>&1
if %errorLevel% equ 0 (echo   [OK] UPnP HTTP Ports - Inbound) else (echo   [SKIP] UPnP HTTP Ports already exists)

echo.
echo Firewall configuration complete!
echo.
pause
goto MENU

:END
echo.
echo Goodbye!
exit /b 0
