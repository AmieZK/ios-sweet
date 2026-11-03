# iOS on Poco X3 NFC (surya) - Porting Guide

## Summary

This document describes the port of the `ios-sweet` project (iOS 16 on Redmi Note 10 Pro) to **Poco X3 NFC (surya, SM7150)**.

## Hardware Differences: sweet vs surya

| Component | sweet (Redmi Note 10 Pro) | surya (Poco X3 NFC) |
|-----------|---------------------------|---------------------|
| **SoC** | SM7150 (Snapdragon 732G) | SM7150 (Snapdragon 732G) ✓ Same |
| **CPU** | 8 cores (6×A55 + 2×A76) | 8 cores (6×A55 + 2×A76) ✓ Same |
| **GIC** | GICv3 @ 0x17a00000 | **QGIC2 @ 0x0b000000** |
| **Timer** | Generic 19.2MHz (INTID 19) | **ARMv7 timer @ 0x0b020000 (INTID 27)** |
| **PMIC** | PM6150L (SPMI + RPMh) | **PM8916 (SPMI + RPM)** |
| **Display** | Direct MIPI DSI | **ADV7533 HDMI bridge @ I2C4 (0x39)** |
| **Touch** | Goodix GT9896 @ GENI SE7 | **TBD: Goodix/FocalTech on I2C2/4/6** |
| **Buttons** | PMIC PON + PM6150L GPIO | **PMIC PWRKEY + GPIO keys (Vol+/Vol-)** |
| **Power Mgmt** | RPMh | **RPM (Resource Power Manager)** |
| **UFS** | UFSHC @ 0x1d84000 | Likely same address |

## Files Created

### Tools
1. **`tools/mkadt-surya.py`** - Apple Device Tree generator for surya
2. **`tools/mkpayload-surya.py`** - Payload packer for surya
3. **`shim/shim-surya.c`** - Boot shim with surya hardware addresses
4. **`shim/build-surya.sh`** - Shim build script
5. **`build-surya.sh`** - Full build orchestration script

### Kernel Patches (in `xnu/patches/`)
1. **`0001-surya-machine-config.patch`** - Machine config (SURYA board config)
2. **`0002-surya-device-tree-virtual-timer-irq.patch`** - Timer INTID handling
3. **`0003-surya-timer-driver.patch`** - ARMv7 timer driver
4. **`0004-surya-pmic-pm8916.patch`** - PM8916 PMIC driver (SPMI)
5. **`0005-surya-display-adv7533.patch`** - ADV7533 display bridge driver
6. **`0006-surya-buttons.patch`** - Buttons driver (PMIC power + GPIO volume)
7. **`0007-surya-touch.patch`** - Touch driver (probes Goodix/FocalTech)
8. **`0008-surya-rpm.patch`** - RPM (Resource Power Manager) driver

### CI/CD
- **`.github/workflows/xnu-surya.yml`** - GitHub Actions workflow for surya kernel build

## Build Instructions

### Prerequisites
- Linux/macOS build machine
- GitHub account (for free macOS runners)
- Fork of this repository
- `gh` CLI installed
- Poco X3 NFC with **unlocked bootloader**
- OrangeFox/TWRP recovery installed

### 1. Prepare Repository
```bash
# Fork https://github.com/dipa-studio/ios-sweet to your account
# Clone your fork
git clone https://github.com/YOUR_USERNAME/ios-sweet.git
cd ios-sweet
```

### 2. Apply Patches Locally (for testing)
```bash
cd xnu
for patch in ../xnu/patches/*.patch; do
  git apply --whitespace=nowarn "$patch"
done
```

### 3. Build Kernel via GitHub Actions
```bash
# Trigger build
gh workflow run xnu-surya.yml -R YOUR_USERNAME/ios-sweet

# Monitor build
gh run watch RUN_ID -R YOUR_USERNAME/ios-sweet

# Download kernel
gh run download RUN_ID -R YOUR_USERNAME/ios-sweet -n xnu-kernel-surya -D xnu/out-surya
```

### 4. Build Shim and Boot Image
```bash
# Generate ADT
python3 tools/mkadt-surya.py shim/out/surya.adt --highmem

# Build shim
cd shim && ./build-surya.sh && cd ..

# Create payload
python3 tools/mkpayload-surya.py \
    xnu/out-surya/kernel.development.surya \
    shim/out/surya.adt \
    shim/out/payload-surya.bin \
    --cmdline "debug=0xc serial=3 cpus=6 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_noconsole=1 sweetfb_hz=30"

# Build boot image
cd shim && ./build.sh ../shim/out/payload-surya.bin && cp out/shim-boot.img out/shim-boot-surya.img
```

### 5. Build iOS Rootfs (same as sweet)
```bash
# Download iPhone X iOS 16.7.16 (20H392) IPSW
# Extract OS.dmg, SystemOS.dmg, AppOS.dmg
tools/mkiosroot.sh OS.dmg SystemOS.dmg AppOS.dmg ios16-root.img 16G
sudo fsck.hfsplus -fy ios16-root.img
sudo mount -t hfsplus -o loop,force ios16-root.img /mnt/iosroot
sudo python3 tools/sweet-root-tweaks.py /mnt/iosroot
sudo umount /mnt/iosroot
img2simg ios16-root.img ios16-root.simg
```

### 6. Flash and Boot
```bash
# Flash rootfs (takes ~7 min)
fastboot -S 512M flash userdata ios16-root.simg
# Re-enter fastboot after flash (Power + Vol Down)

# Boot kernel
fastboot boot shim/out/shim-boot-surya.img
```

## Device Tree Extraction (Already Done)

The surya DTB was extracted from your device:
- **Location**: `dtb_surya_unpacked/dtb` (2.4 MB)
- **Key findings**: QGIC2, ARMv7 timer, PM8916, ADV7533, 4 CPU cores visible (8 actual)

## Next Steps / TODO

### High Priority
1. **Identify touch controller** - Probe I2C2/4/6 for Goodix (0x5d/0x14) or FocalTech (0x38/0x70)
2. **Verify Volume Down GPIO** - DTB only shows Volume Up (GPIO 107)
3. **Implement SPMI interrupt handling** - For PMIC PWRKEY events
4. **Complete RPM/SMD driver** - For clock/power domain control

### Medium Priority
1. **UFS driver verification** - Confirm address 0x1d84000
2. **Display panel timing** - Fine-tune 1080x2400@60Hz
3. **Battery monitoring** - PM8916 VADC channels
4. **Thermal management** - PM8916 temp sensor + MSM thermal

### Low Priority
1. **WiFi/Bluetooth** - WCNSS (QCA6390/QCA6490)
2. **Audio** - PM8916 codec + WCD934x
3. **Camera** - ISP + sensor drivers
4. **Cellular** - MSM modem (q6)

## Debugging

### Kernel Log via USB
```bash
# Boot with sweetusb=2 for CDC-ECM logging
# On host:
tools/sweet-usbnet.sh logs/live-surya.txt
```

### Kernel Log via Recovery
```bash
# After crash/hang:
fastboot boot recovery/recovery.img
tools/sweet-log-pull.sh logs/boot-surya.txt
adb reboot bootloader
```

### Symbolicate Crashes
```bash
tools/sweet-crash.py logs/boot-surya.txt research/dsc/dyld_shared_cache_arm64
```

## Known Issues

1. **Only 4 CPUs in DTB** - SM7150 has 8 cores; need to add big cluster CPUs (6,7) to ADT
2. **RPM vs RPMh** - sweet uses RPMh, surya uses RPM; different SMD channels
3. **Display bridge** - ADV7533 needs proper DSI-to-HDMI configuration
4. **Touch IRQ** - Need to find touch interrupt GPIO from DTBO

## Credits

Based on `ios-sweet` by dipa-studio:
- https://github.com/dipa-studio/ios-sweet
- Reddit: https://www.reddit.com/r/hackios/s/rMV4w6WDTe

Original sweet (Redmi Note 10 Pro) bring-up by dipa-studio.
Surya (Poco X3 NFC) port additions by this project.