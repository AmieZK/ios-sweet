#!/bin/bash
# Surya: ensure MakeInc.def supports SURYA, board_config.h defines MAX_*, proc_reg.h defines MMU_CLINE, arch string stays plain arm64, and SURYA.h exists.
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
set -euo pipefail

# 0. Create SURYA.h if missing
if [[ ! -f pexpert/pexpert/arm64/SURYA.h ]]; then
  mkdir -p pexpert/pexpert/arm64
  cat > pexpert/pexpert/arm64/SURYA.h <<'SURYA_H_EOF'
#ifndef _PEXPERT_ARM64_SURYA_H
#define _PEXPERT_ARM64_SURYA_H
#define NO_MONITOR                1
#define NO_ECORE                  1
#define SURYA                     1
#define ARM_ARCH_TIMER
#define __ARM_ARCH__              8
#define __ARM_VMSA__              8
#define __ARM_VFP__               4
#define __ARM_COHERENT_CACHE__    1
#define __ARM_DEBUG__             7
#define __ARM_ENABLE_SWAP__       1
#define __ARM_V8_CRYPTO_EXTENSIONS__ 1
#define __ARM_PAN_AVAILABLE__     1
#define __ARM_16K_PG__            1
#define HAS_GIC_V3                1
#ifndef ASSEMBLER
#define PLATFORM_PANIC_LOG_DISABLED
#endif
#define SURYA_VTIMER_INTID        27
#define SURYA_IPI_SGI             1
#define GIC_SPURIOUS_IRQ          1023
#endif /* ! _PEXPERT_ARM64_SURYA_H */
SURYA_H_EOF
  echo "Surya.h created"
fi

# 1. MakeInc.def (Python-based, robust)
if [[ -f makedefs/MakeInc.def ]]; then
  python3 - <<'PY'
import re
p = 'makedefs/MakeInc.def'
s = open(p).read()
# SUPPORTED list
if 'SURYA' not in s.split('SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837')[1].split('\n')[0]:
    s = s.replace('SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE',
                  'SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET SURYA')
    s = s.replace('SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET',
                  'SUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837 T6000 T8101 T8103 VMAPPLE SWEET SURYA')
# MACHINE_FLAGS
if 'MACHINE_FLAGS_ARM64_SURYA' not in s:
    s = s.replace('MACHINE_FLAGS_ARM64_BCM2837 = -DARM64_BOARD_CONFIG_BCM2837',
                  'MACHINE_FLAGS_ARM64_BCM2837 = -DARM64_BOARD_CONFIG_BCM2837\nMACHINE_FLAGS_ARM64_SWEET = -DARM64_BOARD_CONFIG_SWEET                -march=armv8.2-a+crypto\nMACHINE_FLAGS_ARM64_SURYA = -DARM64_BOARD_CONFIG_SURYA                -march=armv8.2-a+crypto')
# arch string guard
old = "ifneq ($(filter arm64,$(ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG)),)\nexport ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG := arm64e\nendif"
new = "ifneq ($(filter arm64,$(ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG)),)\nifneq ($(CURRENT_MACHINE_CONFIG),SWEET)\nifneq ($(CURRENT_MACHINE_CONFIG),SURYA)\nexport ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG := arm64e\nendif\nendif\nendif"
if old in s and new not in s:
    s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('MakeInc.def updated')
PY
  echo "Surya MakeInc fix applied"
  grep "SUPPORTED_ARM64_MACHINE_CONFIGS = BCM" makedefs/MakeInc.def
  grep "MACHINE_FLAGS_ARM64_SURYA" makedefs/MakeInc.def
fi

# 2. board_config.h: add SURYA block if missing
if [[ -f pexpert/pexpert/arm64/board_config.h ]]; then
  if ! grep -q "ARM64_BOARD_CONFIG_SURYA" pexpert/pexpert/arm64/board_config.h; then
    python3 - <<'PY'
p = 'pexpert/pexpert/arm64/board_config.h'
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

# 3. proc_reg.h: add SURYA block if missing (MMU_CLINE)
if [[ -f osfmk/arm64/proc_reg.h ]]; then
  if ! grep -q "ARM64_BOARD_CONFIG_SURYA" osfmk/arm64/proc_reg.h; then
    python3 - <<'PY'
p = 'osfmk/arm64/proc_reg.h'
s = open(p).read()
old = '''#elif defined (VMAPPLE)

/* I-Cache. */
#define MMU_I_CLINE 6

/* D-Cache. */
#define MMU_CLINE   6
'''
new = '''#elif defined (ARM64_BOARD_CONFIG_SURYA)

/* I-Cache. */
#define MMU_I_CLINE 6

/* D-Cache. */
#define MMU_CLINE   6

#elif defined (VMAPPLE)

/* I-Cache. */
#define MMU_I_CLINE 6

/* D-Cache. */
#define MMU_CLINE   6
'''
assert old in s, 'context not found'
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('Surya proc_reg block added')
PY
  fi
fi
