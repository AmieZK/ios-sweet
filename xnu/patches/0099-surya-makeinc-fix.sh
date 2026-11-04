#!/bin/bash
# Surya: ensure makedefs/MakeInc.def supports SURYA (robust to sweet/post-sweet state).
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
set -euo pipefail

[[ -f makedefs/MakeInc.def ]] || exit 0

F=makedefs/MakeInc.def

# Add SURYA to SUPPORTED list (handle both base and post-sweet states).
sed -i '' 's/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE$/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET SURYA/' "$F"
sed -i '' 's/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET$/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET SURYA/' "$F"

# Add MACHINE_FLAGS if missing.
if ! grep -q "MACHINE_FLAGS_ARM64_SURYA" "$F"; then
  sed -i '' '/MACHINE_FLAGS_ARM64_BCM2837/a\
MACHINE_FLAGS_ARM64_SWEET = -DARM64_BOARD_CONFIG_SWEET                -march=armv8.2-a+crypto\
MACHINE_FLAGS_ARM64_SURYA = -DARM64_BOARD_CONFIG_SURYA                -march=armv8.2-a+crypto' "$F"
fi

echo "Surya MakeInc fix applied"
grep "SUPPORTED_ARM64_MACHINE_CONFIGS = BCM" "$F"
