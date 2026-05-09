# mt7902e NULL Pointer Fix

A binary patch for the `mt7902e` kernel driver that fixes a NULL pointer dereference in `mt7921_channel_switch_rx_beacon` — the root cause of random system freezes on **MediaTek MT7902 (Filogic 310)** WiFi chipsets.

## The Problem

Systems with an MT7902 WiFi adapter (common on **Gigabyte B850M** series boards and other recent AMD AM5 motherboards) may experience **complete system freezes** where:

- The system becomes unresponsive (mouse moves but nothing works)
- TTY switching fails (Ctrl+Alt+Fx does nothing)
- Only a hard power-off can recover

**Root cause:** A NULL pointer dereference in the `mt7921_channel_switch_rx_beacon` function. When the AP sends a Channel Switch Announcement (CSA) beacon, the driver follows a three-level pointer chain without NULL checks — if any pointer in the chain is NULL, the kernel crashes with an Oops.

```
25e69:  mov    0x58(%rdi),%rax      # phy → ptr1 (might be NULL)
25e6d:  mov    0x8(%rax),%rax       # (NO CHECK) ptr1 → ptr2 → CRASH if NULL
25e71:  mov    0x92c8(%rax),%rax    # (NO CHECK) ptr2 → ptr3
25e78:  mov    (%rax),%rcx          # (NO CHECK) dereference ptr3
```

## The Fix

A minimal binary patch that inserts a NULL check before the pointer dereference chain:

```
test   %rax,%rax         # Is pointer NULL?
je     safe_return        # Yes → return safely (CSA ignored, WiFi might briefly reconnect)
mov    0x8(%rax),%rax     # No → continue normally
jmp    back_to_function
safe_return:
  ret
```

**What happens when the fix triggers:** The channel switch is silently skipped. In the worst case, WiFi briefly disconnects and reconnects — **much better than a system freeze**.

## Symptoms / Compatibility

- **Kernel module:** `mt7902e.ko`
- **Hardware:** MediaTek MT7902 802.11ax PCIe (Filogic 310)
- **PCIE ID:** `14c3:7902`
- **Kernel versions:** Known to affect kernels **6.19 through 7.0.3-zen** (the bug exists in any `mt7902e.ko` compiled before the upstream fix)
- **Driver source:** The driver is built from the mainline `mt76` tree (same author as `mt7921e`), this bug existed in the upstream `mt7921_channel_switch_rx_beacon` function until a rewrite landed in wireless.git

**Affects:** Arch Linux, Fedora, and any distribution using a kernel that bundles `mt7902e` support without the upstream fix.

## Usage

### Option 1: Use pre-patched module (quick)

```bash
# Replace the stock module with the patched one
sudo cp mt7902e_patched.ko.zst /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt7902e/mt7902e.ko.zst
# Reboot, or reload:
sudo modprobe -r mt7902e && sudo modprobe mt7902e
```

### Option 2: Run the auto-patch script (safe)

```bash
chmod +x patch.sh
sudo ./patch.sh
```

The script verifies the expected byte pattern in the driver before applying — if the kernel has already shipped a fixed version, it aborts harmlessly.

### Option 3: Manual patch (educational)

Decompress the `.ko.zst`, find the function at offset `0x25e50` (relative to `.text` section), and:

1. Replace the 16 NOP bytes at `__pfx_mt7921_channel_switch_rx_beacon` (VA `0x25e50`) with NULL check code
2. Replace `mov 0x8(%rax),%rax` at VA `0x25e6d` with a `jmp` to the patch area

See `patch.sh` for exact bytes.

## Important

- **After kernel updates:** `pacman -Syu` (or equivalent) will install a fresh `mt7902e.ko.zst` in the new kernel's module directory. Re-run `patch.sh` to re-apply.
- **Module signature:** The patch invalidates the kernel's module signature. Since `CONFIG_MODULE_SIG_FORCE` is not set on most distros, the module loads with a warning but works fine.

## Files

| File | Description |
|------|-------------|
| `patch.sh` | Auto-detection and patching script |
| `mt7902e_patched.ko.zst` | Pre-patched module for current kernel |
| `mt7902e_original.ko.zst` | Stock (unpatched) module for reference |

## License

GPL-2.0 — same as the kernel driver itself.
