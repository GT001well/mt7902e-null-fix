# mt7902e 空指针修复

> [English version](README.md)

针对 `mt7902e` 内核驱动的二进制补丁，修复 `mt7921_channel_switch_rx_beacon` 中的 NULL 指针解引用——**MediaTek MT7902 (Filogic 310)** WiFi 芯片随机系统锁死的根本原因。

## 问题描述

MT7902 无线网卡（常见于 **技嘉 B850M** 系列主板及近期 AMD AM5 主板）可能遇到**系统完全锁死**的情况：

- 鼠标能动但点不了任何东西
- TTY 切换无效（Ctrl+Alt+Fx 无反应）
- 只能长按电源键强制关机

**根本原因：** 驱动 `mt7921_channel_switch_rx_beacon` 函数中的三层指针链缺少空值检查。AP 发送信道切换信标（CSA）时，链中某层指针为 NULL，内核直接 Oops 崩溃。

```
25e69:  mov    0x58(%rdi),%rax      # phy → ptr1（可能为 NULL）
25e6d:  mov    0x8(%rax),%rax       # （无判空）ptr1 → ptr2 → NULL 则崩溃
25e71:  mov    0x92c8(%rax),%rax    # ptr2 → ptr3
25e78:  mov    (%rax),%rcx          # 解引用 ptr3
```

## 修复方案

在指针解引用链前插入空值检查：

```
test   %rax,%rax         # 指针是否为 NULL？
je     safe_return        # 是 → 安全返回（跳过 CSA 处理）
mov    0x8(%rax),%rax     # 否 → 继续正常流程
jmp    back_to_function
safe_return:
  ret                     # 安全返回
```

**触发修复时的表现：** 信道切换被静默跳过，最坏情况是 WiFi 短暂断连后重连——**相比系统锁死好得多**。

## 兼容性

- **内核模块：** `mt7902e.ko`
- **硬件：** MediaTek MT7902 802.11ax PCIe (Filogic 310)
- **PCI ID：** `14c3:7902`
- **受影响内核：** 6.19 ~ 7.0.3-zen（上游修复前编译的任何 `mt7902e.ko`）
- **测试平台：** Gigabyte B850M FORCE WIFI6E, Arch Linux

## 使用方法

### 选项 1：直接替换预补丁模块（快速）

```bash
sudo cp mt7902e_patched.ko.zst /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt7902e/mt7902e.ko.zst
# 重启，或重载：
sudo modprobe -r mt7902e && sudo modprobe mt7902e
```

### 选项 2：运行自动打补丁脚本（安全）

```bash
chmod +x patch.sh
sudo ./patch.sh
```

脚本会自动检测驱动中的字节模式，确认 bug 存在后再打补丁。如果内核已经包含修复，脚本会安全退出。

### 选项 3：手动打补丁

具体字节和偏移详见 `patch.sh`。

## 内核更新后

`pacman -Syu`（或其他发行版的更新命令）会为内核安装全新的 `mt7902e.ko.zst`。重新运行 `patch.sh` 即可。

> 注意：补丁会使内核模块签名失效。大多数发行版未启用 `CONFIG_MODULE_SIG_FORCE`，模块可正常加载，仅出现签名警告。

## 文件说明

| 文件 | 说明 |
|------|------|
| `patch.sh` | 自动检测与补丁脚本 |
| `mt7902e_patched.ko.zst` | 预补丁模块 |
| `mt7902e_original.ko.zst` | 原版模块备份 |

## 环境信息

```
系统：    Arch Linux
内核：    7.0.3-zen1-2-zen (SMP PREEMPT_DYNAMIC)
主板：    Gigabyte B850M FORCE WIFI6E
CPU：     AMD Ryzen 7 9700X 8-Core
内存：    30GB
网卡：    MediaTek MT7902 (Filogic 310) PCIe [14c3:7902]
驱动：    mt7902e.ko (编译于 2025-12-12)
```

## 许可

GPL-2.0
