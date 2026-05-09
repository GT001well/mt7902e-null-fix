#!/bin/bash
# mt7902e NULL pointer fix re-patch script
# Run after kernel update if the new kernel's mt7902e.ko still has the bug

KERNEL_VER=$(uname -r)
MOD_PATH="/lib/modules/${KERNEL_VER}/kernel/drivers/net/wireless/mediatek/mt7902e/mt7902e.ko.zst"
TMP_KO="/tmp/mt7902e_patch_temp.ko"

if [ ! -f "$MOD_PATH" ]; then
    echo "Module not found: $MOD_PATH"
    exit 1
fi

# Decompress
zstd -d "$MOD_PATH" -o "$TMP_KO" --no-progress -f 2>/dev/null

# Verify the function still has the bug (check for the pointer chain pattern)
if ! grep -c '48 8b 47 58 48 8b 40 08' <(xxd -p "$TMP_KO") > /dev/null 2>&1; then
    echo "Warning: Expected byte pattern not found. The bug may already be fixed."
    echo "Patch aborted - verify manually."
    exit 1
fi

python3 << 'PYTHON'
import struct, sys

with open('/tmp/mt7902e_patch_temp.ko', 'r+b') as f:
    # .text section: VMA=0x1140, file_offset=0x2550
    def va_to_file(va):
        return 0x2550 + (va - 0x1140)
    
    # Patch __pfx area
    f.seek(va_to_file(0x25e50))
    patch1 = bytes([0x48, 0x85, 0xc0, 0x74, 0x09, 0x48, 0x8b, 0x40, 0x08,
                    0xe9, 0x13, 0x00, 0x00, 0x00, 0xc3, 0x90])
    assert f.read(16) == bytes([0x90]*16), "__pfx not all NOPs"
    f.seek(va_to_file(0x25e50))
    f.write(patch1)
    
    # Patch function body
    f.seek(va_to_file(0x25e6d))
    assert f.read(4) == bytes([0x48, 0x8b, 0x40, 0x08]), "Body pattern mismatch"
    f.seek(va_to_file(0x25e6d))
    f.write(bytes([0xeb, 0xe1, 0x90, 0x90]))
    
    print("Patch applied successfully.")
PYTHON

# Re-compress and install
zstd --compress -f "$TMP_KO" -o /tmp/mt7902e_patched.ko.zst 2>/dev/null
sudo cp /tmp/mt7902e_patched.ko.zst "$MOD_PATH"
rm -f "$TMP_KO"

echo "Done! Patched module installed for kernel ${KERNEL_VER}"
echo "Reboot to load the patched driver, or run:"
echo "  sudo modprobe -r mt7902e && sudo modprobe mt7902e"
