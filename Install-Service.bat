@echo off
:: Diretta UPnP Renderer - Service Installer
:: Run as Administrator to install/manage the Windows service

title Diretta Renderer - Service Manager

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

:: Launch PowerShell script
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Service.ps1" %*
