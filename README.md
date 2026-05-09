# mt7902e NULL Pointer Fix

> [中文版本](README.zh-CN.md)

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

## Compatibility

- **Kernel module:** `mt7902e.ko`
- **Hardware:** MediaTek MT7902 802.11ax PCIe (Filogic 310)
- **PCIE ID:** `14c3:7902`
- **Affected kernels:** 6.19 through 7.0.3-zen (any `mt7902e.ko` compiled before the upstream fix)
- **Tested on:** Gigabyte B850M FORCE WIFI6E, Arch Linux

## Usage

### Option 1: Use pre-patched module (quick)

```bash
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

### Option 3: Manual patch

See `patch.sh` for exact bytes and offsets.

## After Kernel Updates

`pacman -Syu` (or equivalent) installs a fresh `mt7902e.ko.zst` for the new kernel. Re-run `patch.sh` to re-apply.

> Note: The patch invalidates the kernel's module signature. Since `CONFIG_MODULE_SIG_FORCE` is not set on most distros, the module loads with a warning but works fine.

## Files

| File | Description |
|------|-------------|
| `patch.sh` | Auto-detection and patching script |
| `mt7902e_patched.ko.zst` | Pre-patched module |
| `mt7902e_original.ko.zst` | Stock module for reference |

## License

GPL-2.0
