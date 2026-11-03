#!/bin/bash
# Build script for surya (Poco X3 NFC) kernel

set -e

IOS_SWEET_DIR="$(dirname "$0")/.."
cd "$IOS_SWEET_DIR"

echo "=== Building iOS-sweet kernel for SURYA (Poco X3 NFC) ==="

# 1. Generate ADT for surya
echo "Generating ADT for surya..."
python3 tools/mkadt-surya.py shim/out/surya.adt --highmem
python3 tools/mkadt-surya.py shim/out/surya-qemu.adt --qemu --highmem

# 2. Build kernel via GitHub Actions (requires fork with public repo)
echo ""
echo "To build the kernel, you need to:"
echo "1. Fork this repo to your GitHub account"
echo "2. Run: gh workflow run xnu.yml -R YOUR_USERNAME/ios-sweet"
echo "3. Download artifacts: gh run download RUN_ID -R YOUR_USERNAME/ios-sweet -n xnu-kernel -D xnu/out-surya"
echo ""
echo "The workflow needs to be modified to build SURYA config instead of SWEET."
echo "Edit .github/workflows/xnu.yml and change:"
echo "  - CURRENT_MACHINE_CONFIG=SWEET"
echo "  to:"
echo "  - CURRENT_MACHINE_CONFIG=SURYA"
echo ""
echo "Or create a separate workflow file for surya."

# 3. Build shim
echo "Building surya shim..."
cd shim
./build-surya.sh

# 4. Create payload
echo "Creating payload..."
cd ..
python3 tools/mkpayload-surya.py \
    xnu/out-surya/kernel.development.surya \
    shim/out/surya.adt \
    shim/out/payload-surya.bin \
    --cmdline "debug=0xc serial=3 cpus=6 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_noconsole=1 sweetfb_hz=30"

# 5. Build boot image
echo "Building boot image..."
cd shim
./build.sh ../shim/out/payload-surya.bin
cp out/shim-boot.img out/shim-boot-surya.img

echo ""
echo "=== Build complete ==="
echo "Boot image: shim/out/shim-boot-surya.img"
echo "ADT: shim/out/surya.adt"
echo ""
echo "To boot on device:"
echo "1. fastboot flash -S 512M userdata ios16-root.simg"
echo "2. fastboot boot shim/out/shim-boot-surya.img"