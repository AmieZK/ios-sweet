#!/bin/bash
# Surya: ensure makedefs/MakeInc.def supports SURYA and board_config.h defines MAX_*.
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
set -euo pipefail

# 1. MakeInc.def
if [[ -f makedefs/MakeInc.def ]]; then
  F=makedefs/MakeInc.def
  sed -i '' 's/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE$/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET SURYA/' "$F"
  sed -i '' 's/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET$/SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET SURYA/' "$F"
  if ! grep -q "MACHINE_FLAGS_ARM64_SURYA" "$F"; then
    sed -i '' '/MACHINE_FLAGS_ARM64_BCM2837/a\
MACHINE_FLAGS_ARM64_SWEET = -DARM64_BOARD_CONFIG_SWEET                -march=armv8.2-a+crypto\
MACHINE_FLAGS_ARM64_SURYA = -DARM64_BOARD_CONFIG_SURYA                -march=armv8.2-a+crypto' "$F"
  fi
  echo "Surya MakeInc fix applied"
  grep "SUPPORTED_ARM64_MACHINE_CONFIGS = BCM" "$F"
fi

# 2. board_config.h: add SURYA block if missing
if [[ -f pexpert/pexpert/arm64/board_config.h ]]; then
  F=pexpert/pexpert/arm64/board_config.h
  if ! grep -q "ARM64_BOARD_CONFIG_SURYA" "$F"; then
    python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '#endif  /* ARM64_BOARD_CONFIG_BCM2837 */\n'
block = anchor + '''
#ifdef ARM64_BOARD_CONFIG_SURYA

#define MAX_L2_CLINE                   6
#define MAX_CPUS                       8
#define MAX_CPU_CLUSTERS               1

#define CORE_NCTRS                     8 /* Placeholder; KPC is not enabled for this target */

#endif  /* ARM64_BOARD_CONFIG_SURYA */
'''
assert anchor in s, 'anchor not found'
s = s.replace(anchor, block, 1)
open(p, 'w').write(s)
print('Surya board_config block added')
PY
  fi
fi
