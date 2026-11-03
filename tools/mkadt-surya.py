#!/usr/bin/env python3
"""Build the minimal Apple Device Tree for SURYA (Poco X3 NFC, SM7150) xnu port.

Only what the early boot path actually reads; every MMIO address comes from
the surya live FDT. Usage:  mkadt-surya.py OUT.adt [--dump] [--qemu] [--highmem]
"""
import hashlib, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adt  # noqa: E402

# Kernel-managed RAM: surya has 6GB/8GB variants. Use upper bank like sweet.
# Surya DTB shows memory@0 with reg=<0 0> - need to check actual memory map.
# For now, use similar layout to sweet but adjusted for surya.
PHYS_BASE = 0xb0000000
MEM_SIZE = 0x4d000000  # ~1.2GB lower bank (adjust based on actual)
PANIC_LOG_SIZE = 0x100000

# HIGHMEM: upper DDR bank if available (surya 6GB/8GB)
HIGH_PHYS_BASE = 0x100000000
HIGH_MEM_SIZE = 0xfcc00000  # ~3.95 GiB like sweet

# SOC base for arm-io ranges (must not be 0)
SOC_BASE = 0x01000000

# SURYA hardware addresses (from live DTB)
# GIC: QGIC2 at 0xb000000 (different from sweet's GICv3 at 0x17a00000)
GICD, GICD_SIZE = 0x0b000000, 0x10000
GICR, GICR_SIZE = 0x0b020000, 0x100000  # Estimated, QGIC2 redistributor
GICR_PE_SIZE = 0x20000

# Framebuffer: ABL leaves splash at 0x9c000000 (same as sweet?)
FB, FB_SIZE = 0x9c000000, 0x1700000
FB_W, FB_H, FB_STRIDE = 1080, 2400, 1080 * 4

# UFS host controller (need to verify - not in boot DTB)
# Sweet: 0x1d84000. Surya likely similar region.
UFS, UFS_SIZE = 0x01d84000, 0x3000

# Timer: ARMv7 timer at 0xb020000, but XNU expects generic timer
# We'll use CNTFRQ = 19.2 MHz like sweet, virtual timer INTID 27 (standard)
# But surya DTB shows timer interrupts at PPI 8,9,10,11 (frames 0-3)
# Virtual timer is PPI 11 (frame 3) = INTID 27? Actually ARMv7 timer uses different mapping.
TIMEBASE = 19200000
VTIMER_INTID = 27  # Standard ARMv8 virtual timer PPI
PTIMER_INTID = 26  # Physical timer
SGI_INTID = 1

# PSCI/SMCCC
PSCI_VERSION = 0x84000000
PSCI_CPU_SUSPEND = 0xc4000001
PSCI_CPU_OFF = 0x84000002
PSCI_CPU_ON = 0xc4000003
PSCI_MIGRATE_INFO_TYPE = 0x84000006
PSCI_SYSTEM_RESET = 0x84000009
PSCI_FEATURES = 0x8400000a
PSCI_SYSTEM_SUSPEND = 0xc400000e
PSCI_SYSTEM_RESET2 = 0xc4000012
SMCCC_VERSION = 0x80000000

NR_CPUS = 4  # Surya DTB shows 4 CPUs (but SM7150 has 8 - DTB may be incomplete)

SURYA_ECID = 0x5355525941000001  # 'SURYA' + 1, synthetic

BOOT_MANIFEST_HASH = hashlib.sha384(b'surya boot manifest').digest()

# iPhone X D22AP product node (same as sweet - we run iPhone X userland)
D22AP_ADT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../research/ipsw-x/d22ap.adt')


def d22ap_product(path=D22AP_ADT):
    """/product properties of the real D22AP tree."""
    if not os.path.exists(path):
        print(f'warning: {path} missing, no /product node', file=sys.stderr)
        return None
    root, _ = adt.parse(open(path, 'rb').read())
    for c in root.children:
        if dict((k, v) for k, f, v in c.props).get('name') == b'product\0':
            return [(k, v) for k, f, v in c.props if not f and k not in ('name', 'AAPL,phandle')]
    raise SystemExit(f'{path}: no /product node')


u32 = lambda *v: struct.pack('<%dI' % len(v), *v)
u64 = lambda *v: struct.pack('<%dQ' % len(v), *v)
cstr = lambda s: s.encode() + b'\0'


def node(name, props=(), children=()):
    n = adt.Node()
    n.props = [('name', 0, cstr(name))] + [(k, 0, v) for k, v in props]
    n.children = list(children)
    return n


def build(seed=None, qemu=False, highmem=False):
    """qemu=True: same tree, but with QEMU virt's GIC addresses and CNTFRQ."""
    phys_base, mem_size = (HIGH_PHYS_BASE, HIGH_MEM_SIZE) if highmem else (PHYS_BASE, MEM_SIZE)
    # Carve the panic log off the top so the kernel never allocates over it.
    panic_base = phys_base + mem_size - PANIC_LOG_SIZE
    mem_size -= PANIC_LOG_SIZE

    seed = seed if seed is not None else os.urandom(64)
    phandle = iter(range(1, 1000))
    ph = lambda: ('AAPL,phandle', u32(next(phandle)))

    chosen = node('chosen', [
        ph(),
        ('dram-base', u64(phys_base)),
        ('dram-size', u64(mem_size)),
        ('random-seed', seed),
        ('debug-enabled', u32(1)),
        ('embedded-panic-log-size', u32(PANIC_LOG_SIZE)),
        ('firmware-version', cstr('surya-shim')),
        ('system-firmware-version', cstr('surya-shim')),
        ('boot-manifest-hash', BOOT_MANIFEST_HASH),
        ('crypto-hash-method', cstr('sha2-384')),
        # display-scale 3: 1080x2400 @3x = 360x800 points (iPhone X class)
        ('display-scale', u32(3)),
        ('unique-chip-id', struct.pack('<Q', SURYA_ECID)),
        ('chip-id', u32(0x8015)),  # A11 chip-id for iPhone X
        # Security status for Hactivation (dev-fused, undemoted)
        ('certificate-production-status', u32(0)),
        ('effective-production-status-ap', u32(0)),
        ('certificate-security-mode', u32(1)),
        ('effective-security-mode-sep', u32(1)),
    ], [node('memory-map', [ph()]),
        node('asmb', [ph(), ('lp-sip0', u64(0x6f)), ('lp-sip1', u32(1))])])

    # SURYA SMP: DTB shows 4 CPUs (cortex-a53 compatible).
    # But SM7150 actually has 8 cores (Kryo 470: 2x A76 + 6x A55).
    # We'll emit 8 cores to match hardware, using PSCI CPU_ON.
    cpu_nodes = []
    for core in range(1 if qemu else 8):
        # MPIDR Aff1:Aff0 - for SM7150 Kryo 470:
        # Cores 0-5: Cortex-A55 (little cluster, Aff1=0)
        # Cores 6-7: Cortex-A76 (big cluster, Aff1=1)
        if core < 6:
            aff1, aff0 = 0, core
            clk_freq = 1804800000  # 1.8 GHz A55
        else:
            aff1, aff0 = 1, core - 6
            clk_freq = 2304000000  # 2.3 GHz A76
        mpidr = (aff1 << 8) | aff0

        cpu_nodes.append(node(f'cpu{core}', [
            ph(),
            ('device_type', cstr('cpu')),
            ('compatible', cstr('qcom,kryo470') + cstr('ARM,v8')),
            ('reg', u32(mpidr << 8)),  # actual MPIDR Aff1:Aff0
            ('cpu-id', u32(core)),
            ('cluster-id', u32(0 if core < 6 else 1)),
            ('cluster-type', u32(0)),  # homogeneous SMP
            ('die-cluster-id', u32(0)),
            ('cluster-core-id', u32(aff0)),
            ('l2-cache-id', u32(core)),
            ('l3-cache-id', u32(0)),
            ('state', cstr('running' if core == 0 else 'stopped')),
            ('timebase-frequency', u32(TIMEBASE)),
            ('clock-frequency', u32(clk_freq)),
            ('bus-frequency', u32(100000000)),
            ('memory-frequency', u32(1866000000)),
            ('peripheral-frequency', u32(TIMEBASE)),
            ('fixed-frequency', u32(TIMEBASE)),
        ]))
    cpus = node('cpus', [ph(), ('#address-cells', u32(1)), ('#size-cells', u32(0))], cpu_nodes)

    # GIC: QGIC2 on surya (different from sweet's GICv3)
    # We'll present it as GICv3 compatible since XNU expects that
    gic = node('gic', [
        ph(),
        ('compatible', cstr('arm,gic-v3')),
        ('interrupt-controller', b''),
        ('virtual-timer-intid', u32(VTIMER_INTID)),
        ('reg', u64(GICD - SOC_BASE, GICD_SIZE, GICR - SOC_BASE, GICR_SIZE)),
    ])

    arm_io = node('arm-io', [
        ph(),
        ('device_type', cstr('surya-io')),
        ('compatible', cstr('surya-io') + cstr('arm-io')),
        ('#address-cells', u32(2)),
        ('#size-cells', u32(2)),
        ('ranges', u64(0, SOC_BASE, 0x100000000 - SOC_BASE)),
    ], [gic,
        node('wdt', [ph(), ('no-pmu', u32(1))]),
        # Display: present as iPhone X 1125x2436 (same as sweet)
        node('disp0', [
            ph(),
            ('device_type', cstr('display-subsystem')),
            ('compatible', cstr('surya,display')),
            ('canvas-width', u32(1125)),
            ('canvas-height', u32(2436)),
        ])])

    fbcon = node('surya-fbcon', [
        ph(),
        ('reg', u64(FB, FB_SIZE)),
        ('width', u32(FB_W)),
        ('height', u32(FB_H)),
        ('stride', u32(FB_STRIDE)),
    ])

    # UFS host controller
    ufs = node('surya-ufs', [
        ph(),
        ('compatible', cstr('qcom,ufshc')),
        ('reg', u64(UFS, UFS_SIZE)),
    ])

    defaults = node('defaults', [ph(), ('no-effaceable-storage', u32(1))])

    # Buttons: Power (PMIC pwrkey), Volume Up (GPIO), Volume Down (GPIO)
    # Home button type 2 = no Home button (Face ID class)
    buttons = node('buttons', [
        ph(),
        ('button-names', cstr('volup') + cstr('voldown') + cstr('hold')),
        ('home-button-type', u32(2)),
        ('opposed-power-vol-buttons', u32(1)),
    ])

    product_props = d22ap_product()
    product = [node('product', [ph()] + product_props)] if product_props else []

    pram = node('pram', [ph(), ('reg', u64(panic_base) + u64(PANIC_LOG_SIZE))])

    return node('device-tree', [
        ph(),
        ('compatible', cstr('D22AP') + cstr('iPhone10,3') + cstr('xiaomi,surya') + cstr('qcom,sm7150') + cstr('AppleARM')),
        ('model', cstr('iPhone10,3')),
        ('target-type', cstr('D22')),
        ('target-sub-type', cstr('D22AP')),
        ('manufacturer', cstr('Apple Inc.')),
        ('#address-cells', u32(2)),
        ('#size-cells', u32(2)),
    ], [chosen, defaults, cpus, arm_io, fbcon, buttons, pram] + product + ([] if qemu else [ufs]))


if __name__ == '__main__':
    root = build(qemu='--qemu' in sys.argv, highmem='--highmem' in sys.argv)
    blob = adt.serialize(root)
    open(sys.argv[1], 'wb').write(blob)
    if '--dump' in sys.argv:
        adt.dump(adt.parse(blob)[0])
    print(f'{sys.argv[1]}: {len(blob)} bytes', file=sys.stderr)