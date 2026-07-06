# init-selector

A POSIX-compliant early-boot init selector for Linux. It allows you to choose between multiple init systems (systemd, OpenRC, runit, dinit) **before** PID 1 is started on the real root filesystem.

This project is inspired by the early-stage selection mechanism used in Bedrock Linux, but is designed to be minimal, portable, and non-invasive.

**Key properties:**
- Runs entirely in initramfs as PID 1
- Uses only POSIX `sh` + BusyBox standard utilities
- Does **not** replace your kernel or modify existing init systems
- Works with dracut, mkinitcpio, and initramfs-tools (`update-initramfs`)

---

## How Early Linux Boot Works

1. **Bootloader** (GRUB, systemd-boot, etc.) loads the kernel image + initramfs into memory.
2. **Kernel** initializes hardware, decompresses itself, and starts the initramfs as its initial root filesystem (`/`).
3. The kernel looks for and executes `/init` inside the initramfs. **This `/init` becomes PID 1**.
4. The initramfs `/init` is responsible for:
   - Mounting essential virtual filesystems (`/proc`, `/sys`, `/dev`)
   - Loading kernel modules if needed
   - Discovering and mounting the real root filesystem (from `root=` kernel parameter)
   - Switching from the temporary initramfs to the real root using `switch_root`
5. After `switch_root`, the real root's `/sbin/init` (or equivalent) becomes the new PID 1.

**Important:** The initramfs init script **is** PID 1 until `switch_root` is called. After the switch, the original initramfs contents are discarded from memory.

---

## Why Init Must Be PID 1

- The Linux kernel treats PID 1 specially:
  - It is the ancestor of all other processes.
  - It reaps zombie processes (orphaned children).
  - It receives special signals (`SIGINT`, `SIGTERM`, `SIGPWR` etc.) for shutdown/reboot.
  - Many daemons and the kernel itself expect PID 1 to be the "init" process.
- If your chosen init is not executed as PID 1, services will not start correctly, and the system may become unusable or hang on shutdown.
- `switch_root` (BusyBox) or `pivot_root` + `exec` is the **only** correct way to hand over control to a real root's init while preserving PID 1 semantics.

---

## How `switch_root` Works

BusyBox `switch_root` performs the following atomically (from the point of view of the new root):

1. `chroot` into the new root directory.
2. Delete all files and directories in the old root (the initramfs) to free RAM.
3. Use `pivot_root` (or equivalent) to make the new root the actual `/`.
4. `exec` the new init program.

Example usage (what our script does):
```sh
cd /mnt/root
exec switch_root . /usr/lib/systemd/systemd
```

After this call:
- The process that was running the initramfs `/init` is replaced by the real init.
- PID remains 1.
- The old initramfs memory is released.

If `switch_root` fails, the system usually panics or drops to a rescue shell.

---

## Supported Init Systems

- **systemd** (`/usr/lib/systemd/systemd` or `/lib/systemd/systemd`)
- **OpenRC** (`/sbin/openrc-init` or `/usr/sbin/openrc-init`)
- **runit** (`/sbin/runit-init` or `/lib/runit/runit-init`)
- **dinit** (`/sbin/dinit` or `/usr/sbin/dinit`)

The detection script looks in the most common locations used by major distributions (Arch, Debian, Gentoo, Void, Alpine, Artix, etc.).

---

## Project Structure

```
init-selector/
├── install.sh      # Main installer (run as root)
├── init            # The actual PID 1 script (runs inside initramfs)
├── detect.sh       # Helper used by install.sh to find inits
├── config          # Example / generated configuration
└── README.md
```

---

## Installation

### Prerequisites

- A Linux system with an initramfs (almost all do).
- Root access.
- One or more of the supported init systems installed.
- One of:
  - `dracut`
  - `mkinitcpio`
  - `update-initramfs` (Debian/Ubuntu family)

### Steps

1. Clone or copy the project:
   ```sh
   git clone ... init-selector
   cd init-selector
   ```

2. Run the installer:
   ```sh
   sudo ./install.sh
   ```

3. The script will:
   - Detect installed init systems
   - Generate `/etc/init-selector/config`
   - Install `/usr/lib/init-selector/init`
   - Add the appropriate hook/module for your initramfs generator
   - Attempt to rebuild initramfs images

4. Reboot:
   ```sh
   sudo reboot
   ```

At boot you should see a menu similar to:
```
========================================
  init-selector: Choose init system
========================================

Available init systems:
  1) systemd - /usr/lib/systemd/systemd (default)
  2) openrc - /sbin/openrc-init
  3) runit - /sbin/runit-init

Enter number (or name) or wait 5s for default (systemd):
>
```

### Kernel Parameters (bypass menu)

Add to your bootloader kernel command line:

- `initsel=systemd`
- `initsel=openrc`
- `initsel=runit`
- `initsel=dinit`

Example in GRUB:
```
linux /vmlinuz-linux root=/dev/sda2 rw initsel=runit
```

When present, the menu is skipped and the chosen init is used immediately.

---

## Configuration

After install, edit `/etc/init-selector/config`:

```sh
DEFAULT=systemd
systemd /usr/lib/systemd/systemd
openrc /sbin/openrc-init
runit /sbin/runit-init
dinit /sbin/dinit
```

- `DEFAULT=` sets the fallback when timeout occurs.
- The last successfully chosen init is saved to `/etc/init-selector/last` and used as the new default on next boot.

You can also manually create `/etc/init-selector/last` containing just the name (e.g. `openrc`).

---

## How It Works at Boot

1. Kernel loads initramfs → executes our `/init` (PID 1).
2. Our script:
   - Mounts `/proc`, `/sys`, `/dev`, `/run`
   - Parses kernel command line (`root=`, `initsel=`)
   - Mounts the real root filesystem at `/mnt/root`
   - Loads `/etc/init-selector/config` from real root
   - Loads last selection if present
   - If `initsel=` present → use it directly
   - Else → display interactive menu with 5-second timeout
   - Validates chosen init exists and is executable on real root
   - Saves choice to `last`
   - Calls `switch_root` + `exec` of the chosen init

---

## Error Handling

The script handles:

- Missing root filesystem (`root=` parameter or `/dev/root`)
- Selected init binary not found or not executable
- `switch_root` failure
- Invalid `initsel=` value
- No init systems detected (falls back to safe defaults + rescue shell)

On fatal error it attempts to drop you into an interactive shell on `/dev/console`.

---

## Removing / Uninstalling

### Method 1: Manual (recommended)

```sh
# 1. Remove our files
sudo rm -rf /etc/init-selector
sudo rm -rf /usr/lib/init-selector

# 2. Remove generator-specific integration
# For dracut:
sudo rm -rf /usr/lib/dracut/modules.d/99init-selector

# For mkinitcpio:
sudo rm -f /etc/initcpio/hooks/init-selector
sudo rm -f /etc/initcpio/install/init-selector

# For initramfs-tools:
sudo rm -f /usr/share/initramfs-tools/hooks/init-selector

# 3. Rebuild initramfs (critical!)
# dracut:
sudo dracut --force --regenerate-all

# mkinitcpio:
sudo mkinitcpio -P

# update-initramfs:
sudo update-initramfs -u -k all
```

### Method 2: Restore original initramfs

If you have a backup of your previous initramfs image, restore it.

### Method 3: Reinstall your initramfs package

On most distros reinstalling the kernel or the initramfs package will regenerate a clean image.

---

## Troubleshooting

### Menu does not appear

- Check that the custom `/init` is inside the initramfs:
  ```sh
  lsinitrd /boot/initramfs-*.img | grep -E '(^/init$|init-selector)'
  ```
- Try adding `break=init` or `rd.break=init` to kernel cmdline temporarily.

### "No valid init system" error

- Check `/etc/init-selector/config` on the real root.
- Make sure the paths point to real executables.
- Run `ls -l /usr/lib/init-selector/init` on the installed system.

### Selected init does not start

- The init you chose may require additional setup (e.g. OpenRC may need services enabled).
- Try booting with `initsel=systemd` first to get a working system.

### Want to test without rebooting?

You can manually test parts of the script, but full testing requires a real boot or a VM with serial console.

---

## Design Decisions & Limitations

- **POSIX sh only** — no arrays, no `[[ ]]`, no process substitution.
- **No external interpreters** — only BusyBox applets + coreutils that are usually present.
- **No systemd during selection** — the selector runs before any real-root init.
- **Timeout is 5 seconds** — hardcoded for simplicity (easy to change in `init`).
- **Assumes one real root** — multi-device setups may require additional `root=` handling.
- **Does not support nested initramfs** or very exotic boot configurations out of the box.

---

## Credits & Inspiration

- Bedrock Linux early-boot selection mechanism
- BusyBox `switch_root` and initramfs documentation
- Various custom initramfs examples from Gentoo wiki and Arch forums
- POSIX shell best practices from the Open Group and shellcheck community

---

## License

This project is provided as-is for educational and practical use.  
Feel free to adapt it to your distribution.

**Use at your own risk.** Always keep a known-good kernel/initramfs backup.

---

Happy multi-init booting!
