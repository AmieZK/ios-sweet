#!/bin/bash
# Surya: ensure MakeInc.def supports SURYA, board_config.h defines MAX_*, proc_reg.h defines MMU_CLINE, arch string stays plain arm64, and SURYA.h exists.
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
set -euo pipefail

# 0. Create SURYA.h if missing
if [[ ! -f pexpert/pexpert/arm64/SURYA.h ]]; then
  mkdir -p pexpert/pexpert/arm64
  cat > pexpert/pexpert/arm64/SURYA.h <<'SURYA_H_EOF'
/*
 * Board config for the Poco X3 NFC ("surya", Qualcomm SM7150 / Snapdragon 732G):
 * Kryo 470 = Cortex-A76 + Cortex-A55, ARMv8.2, no PAC.
 */
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
#endif /* ! ASSEMBLER */

#define SURYA_VTIMER_INTID        27
#define SURYA_IPI_SGI             1

#define GIC_SPURIOUS_IRQ          1023

#define GICR_PE_SIZE              0x20000

#define GICD_CTLR                 0x0
#define GICD_CTLR_ENABLEGRP1      0x1
#define GICD_CTLR_ENABLEGRP1A     0x2
#define GICD_CTLR_ARE_NS          0x10
#define GICD_CTLR_RWP             0x80000000

#define GICR_TYPER                              0x08
#define GICR_WAKER                              0x14
#define GICR_IGROUPR0                           0x10080
#define GICR_ISENABLER0                         0x10100
#define GICR_IPRIORITYR0                        0x10400

#define GICR_TYPER_AFFINITY_VALUE_SHIFT         32
#define GICR_TYPER_LAST                         0x10

#define GICR_WAKER_PROCESSORSLEEP               0x2
#define GICR_WAKER_CHILDRENASLEEP               0x4

#define ICC_CTLR_EOIMODE                        0x2
#define ICC_SRE_SRE                             0x1

#endif /* ! _PEXPERT_ARM64_SURYA_H */
SURYA_H_EOF
  echo "Surya.h created"
fi

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
  python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "ifneq ($(filter arm64,$(ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG)),)\nexport ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG := arm64e\nendif"
new = "ifneq ($(filter arm64,$(ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG)),)\nifneq ($(CURRENT_MACHINE_CONFIG),SWEET)\nifneq ($(CURRENT_MACHINE_CONFIG),SURYA)\nexport ARCH_STRING_FOR_CURRENT_MACHINE_CONFIG := arm64e\nendif\nendif\nendif"
if old in s and new not in s:
    s = s.replace(old, new, 1)
    open(p, 'w').write(s)
    print('arch string guard added')
PY
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

# 3. proc_reg.h: add SURYA block if missing (MMU_CLINE)
if [[ -f osfmk/arm64/proc_reg.h ]]; then
  F=osfmk/arm64/proc_reg.h
  if ! grep -q "ARM64_BOARD_CONFIG_SURYA" "$F"; then
    python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
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
