@echo off
:: Quick Start - Diretta UPnP Renderer
:: Right-click and "Run as administrator"

title Diretta Renderer - Quick Start

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges required!
    echo Right-click this file and select "Run as administrator"
    pause
    exit /b 1
)

set "BIN_DIR=%~dp0bin\x64\Release"
set "EXE=%BIN_DIR%\DirettaRendererUPnP.exe"
set "VCPKG_BIN=C:\vcpkg\installed\x64-windows\bin"

:: Copy DLLs if needed
if not exist "%BIN_DIR%\libupnp.dll" (
    echo Copying DLLs...
    copy "%VCPKG_BIN%\*.dll" "%BIN_DIR%\" >nul 2>&1
)

echo.
echo ============================================================
echo   Diretta UPnP Renderer - Quick Start
echo ============================================================
echo.
echo Starting with auto-detected target...
echo Press Ctrl+C to stop the renderer.
echo.

"%EXE%"

pause
