#!/bin/bash
# Build script for surya shim

set -e

SHIM_DIR="$(dirname "$0")"
OUT_DIR="$SHIM_DIR/out"
mkdir -p "$OUT_DIR"

echo "Building surya shim..."

# Compile shim-surya.c
aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/shim-surya.c" -o "$OUT_DIR/shim-surya.o"

# Compile other shim sources
aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/console.c" -o "$OUT_DIR/console.o"

aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/mmu.c" -o "$OUT_DIR/mmu.o"

aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/loader.c" -o "$OUT_DIR/loader.o"

aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/ufs.c" -o "$OUT_DIR/ufs.o"

aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/fdt.c" -o "$OUT_DIR/fdt.o"

aarch64-linux-gnu-gcc -nostdlib -ffreestanding -O2 \
    -I"$SHIM_DIR" \
    -mcmodel=large -mgeneral-regs-only \
    -c "$SHIM_DIR/start.S" -o "$OUT_DIR/start.o"

# Link
aarch64-linux-gnu-ld -nostdlib -T "$SHIM_DIR/shim.ld" \
    "$OUT_DIR/start.o" \
    "$OUT_DIR/shim-surya.o" \
    "$OUT_DIR/console.o" \
    "$OUT_DIR/mmu.o" \
    "$OUT_DIR/loader.o" \
    "$OUT_DIR/ufs.o" \
    "$OUT_DIR/fdt.o" \
    -o "$OUT_DIR/shim-surya.elf"

# Convert to binary
aarch64-linux-gnu-objcopy -O binary "$OUT_DIR/shim-surya.elf" "$OUT_DIR/shim-surya.bin"

echo "Shim binary: $OUT_DIR/shim-surya.bin"
ls -lh "$OUT_DIR/shim-surya.bin"