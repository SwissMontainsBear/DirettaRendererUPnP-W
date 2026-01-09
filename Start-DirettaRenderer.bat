@echo off
:: Diretta UPnP Renderer - Launcher Wrapper
:: Double-click this file to start the renderer
:: (Will auto-elevate to Administrator)

title Diretta Renderer

:: Launch PowerShell script with execution policy bypass
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DirettaRenderer.ps1" %*
