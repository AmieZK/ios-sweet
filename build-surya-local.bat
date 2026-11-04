@echo off
echo ========================================
echo  BUILD SURYA BOOT IMAGE - POCO X3 NFC
echo ========================================
echo.

set ROOT_DIR=%~dp0
set SHIM_DIR=%ROOT_DIR%shim
set XNU_OUT=%ROOT_DIR%xnu\out-surya
set ADT_OUT=%SHIM_DIR%\out\surya.adt
set PAYLOAD_OUT=%SHIM_DIR%\out\payload-surya.bin
set BOOT_OUT=%SHIM_DIR%\out\shim-boot-surya.img

echo [1/5] Checking kernel file...
if not exist "%XNU_OUT%\kernel.development.surya" (
    echo ERROR: Kernel not found at %XNU_OUT%\kernel.development.surya
    echo Please download from GitHub Actions and place it there.
    pause
    exit /b 1
)
echo Kernel found.

echo.
echo [2/5] Generating ADT for SURYA...
python "%ROOT_DIR%tools\mkadt-surya.py" "%ADT_OUT%" --highmem
if errorlevel 1 (
    echo ERROR: ADT generation failed
    pause
    exit /b 1
)
echo ADT generated.

echo.
echo [3/5] Building SURYA shim...
cd /d "%SHIM_DIR%"
call build-surya.sh
if errorlevel 1 (
    echo ERROR: Shim build failed
    pause
    exit /b 1
)
echo Shim built.

echo.
echo [4/5] Creating payload...
cd /d "%ROOT_DIR%"
python "%ROOT_DIR%tools\mkpayload-surya.py" ^
    "%XNU_OUT%\kernel.development.surya" ^
    "%ADT_OUT%" ^
    "%PAYLOAD_OUT%" ^
    --cmdline "debug=0xc serial=3 cpus=6 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_noconsole=1 sweetfb_hz=30"
if errorlevel 1 (
    echo ERROR: Payload creation failed
    pause
    exit /b 1
)
echo Payload created.

echo.
echo [5/5] Building boot image...
cd /d "%SHIM_DIR%"
call build.sh ..\..\shim\out\payload-surya.bin
copy "out\shim-boot.img" "out\shim-boot-surya.img"
cd /d "%ROOT_DIR%"
if errorlevel 1 (
    echo ERROR: Boot image build failed
    pause
    exit /b 1
)
echo Boot image built.

echo.
echo ========================================
echo  BUILD SELESAI!
echo ========================================
echo Boot image: %BOOT_OUT%
echo.
echo Langkah selanjutnya:
echo  1. Flash rootfs iOS (butuh WSL2)
echo  2. fastboot boot %BOOT_OUT%
echo ========================================
pause