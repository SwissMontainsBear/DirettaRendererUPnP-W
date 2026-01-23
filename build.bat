@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: DirettaRendererUPnP Build Script
:: Builds both x64 and ARM64 Release configurations
:: ============================================================================

echo.
echo ============================================================================
echo   DirettaRendererUPnP Build Script
echo ============================================================================
echo.

:: Check if running from Developer Command Prompt
where cl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run from Developer Command Prompt for VS
    echo.
    echo         Open: Start Menu ^> Visual Studio 2022 ^> Developer Command Prompt
    echo         Then: cd to this directory and run build.bat
    echo.
    pause
    exit /b 1
)

:: Parse arguments
set BUILD_X64=1
set BUILD_ARM64=1
set BUILD_CONFIG=Release
set CLEAN_FIRST=0

:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="x64" (
    set BUILD_X64=1
    set BUILD_ARM64=0
    shift
    goto :parse_args
)
if /i "%~1"=="arm64" (
    set BUILD_X64=0
    set BUILD_ARM64=1
    shift
    goto :parse_args
)
if /i "%~1"=="debug" (
    set BUILD_CONFIG=Debug
    shift
    goto :parse_args
)
if /i "%~1"=="release" (
    set BUILD_CONFIG=Release
    shift
    goto :parse_args
)
if /i "%~1"=="clean" (
    set CLEAN_FIRST=1
    shift
    goto :parse_args
)
if /i "%~1"=="help" goto :show_help
if /i "%~1"=="/?" goto :show_help
if /i "%~1"=="-h" goto :show_help
shift
goto :parse_args

:done_args

:: Clean if requested
if %CLEAN_FIRST%==1 (
    echo [INFO] Cleaning build directories...
    if exist bin rmdir /s /q bin
    if exist obj rmdir /s /q obj
    echo.
)

:: Build x64
if %BUILD_X64%==1 (
    echo ============================================================================
    echo   Building x64 %BUILD_CONFIG%
    echo ============================================================================
    echo.

    msbuild DirettaRendererUPnP.vcxproj /p:Configuration=%BUILD_CONFIG% /p:Platform=x64 /v:minimal /nologo

    if errorlevel 1 (
        echo.
        echo [ERROR] x64 build failed!
        set X64_RESULT=FAILED
    ) else (
        echo.
        echo [OK] x64 build successful
        set X64_RESULT=OK
    )
    echo.
)

:: Build ARM64
if %BUILD_ARM64%==1 (
    echo ============================================================================
    echo   Building ARM64 %BUILD_CONFIG%
    echo ============================================================================
    echo.

    msbuild DirettaRendererUPnP.vcxproj /p:Configuration=%BUILD_CONFIG% /p:Platform=ARM64 /v:minimal /nologo

    if errorlevel 1 (
        echo.
        echo [ERROR] ARM64 build failed!
        set ARM64_RESULT=FAILED
    ) else (
        echo.
        echo [OK] ARM64 build successful
        set ARM64_RESULT=OK
    )
    echo.
)

:: Summary
echo ============================================================================
echo   Build Summary
echo ============================================================================
echo.

if %BUILD_X64%==1 (
    if exist "bin\x64\%BUILD_CONFIG%\DirettaRendererUPnP.exe" (
        echo   x64   : bin\x64\%BUILD_CONFIG%\DirettaRendererUPnP.exe [OK]
    ) else (
        echo   x64   : NOT FOUND [FAILED]
    )
)

if %BUILD_ARM64%==1 (
    if exist "bin\ARM64\%BUILD_CONFIG%\DirettaRendererUPnP.exe" (
        echo   ARM64 : bin\ARM64\%BUILD_CONFIG%\DirettaRendererUPnP.exe [OK]
    ) else (
        echo   ARM64 : NOT FOUND [FAILED]
    )
)

echo.
echo ============================================================================
goto :eof

:show_help
echo.
echo Usage: build.bat [options]
echo.
echo Options:
echo   (no args)    Build both x64 and ARM64 Release
echo   x64          Build x64 only
echo   arm64        Build ARM64 only
echo   debug        Build Debug configuration
echo   release      Build Release configuration (default)
echo   clean        Clean before building
echo   help         Show this help
echo.
echo Examples:
echo   build.bat                    Build both x64 and ARM64 Release
echo   build.bat x64                Build x64 Release only
echo   build.bat arm64 debug        Build ARM64 Debug only
echo   build.bat clean              Clean and build both architectures
echo.
goto :eof
