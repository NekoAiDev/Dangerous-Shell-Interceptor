# Dangerous Shell Interceptor (DSI)

A shell command safety interception module for Android (Magisk / KernelSU) and ADB (non-root) environments.
When a dangerous command is detected -- such as recursive deletion of `/data`, writing to a block device with `dd`,
formatting a partition, flashing `boot`, or disabling SELinux -- it automatically intercepts the command
and presents a confirmation dialog. The user decides whether to **reject** or **allow** execution,
with a detailed explanation of why the command is considered dangerous.

**Author:** xiaohondan  |  **Organization:** [NekoAiDev](https://github.com/NekoAiDev)

## Features

- **Broad detection**: Covers over a dozen danger categories including deletion, formatting, partitioning,
  permissions, redirection, flashing, privilege escalation, and supply-chain attacks.
- **Precise allow-through**: Normal operations like `rm file.txt`, `dd` writing to regular files,
  `chmod +x`, etc. are never intercepted.
- **Interactive dialog**: Renders a confirmation dialog inside the terminal showing the command,
  risk level, reason, and target. Provides three options: **Reject**, **Allow**, or **Allow & Whitelist**.
- **Safe default**: In non-interactive environments (pipes, scripts), commands are **rejected by default**
  with a log entry to prevent accidental damage.
- **Dual mode**: Root module (Magisk / KernelSU) auto-deploys on boot; non-root ADB users can also use
  it via `install-adb.sh`.
- **WebUI**: Rule toggles, whitelist management, interception log viewer, command checker, and built-in
  terminal (KernelSU / MMRL).
- **WebUI Terminal**: Run `dsi` subcommands directly from the web page (`help`, `check rm -rf /data`,
  `config`, `log`, `update`).
- **One-click update**: Click "Update" in the WebUI footer to download and flash the latest version
  automatically on root; ADB non-root only downloads the package without auto-flashing.
- **Banner**: Module and WebUI display the project banner image.
- **Chinese-friendly UI**: All dialogs and descriptions are in Chinese with character-width-aware line
  wrapping, compatible across locales.

## Danger Command Coverage

| Rule | Trigger Example | Risk |
| --- | --- | --- |
| Recursive delete | `rm -rf /data`, `rm -rf /system`, `rm -rf /` | Critical |
| Block device write | `dd if=/dev/zero of=/dev/block/by-name/boot` | Critical |
| Format / Partition | `mkfs.ext4 /dev/sdb1`, `parted /dev/sda mklabel` | Critical / High |
| Permission / Owner change | `chmod -R 000 /system`, `chown -R root:root /data` | Critical / High |
| Redirect overwrite | `> /etc/passwd`, `echo x > /system/build.prop` | High |
| Move / Rename | `mv /data/app /data/app_bak` | Medium |
| Wipe / Format | `wipe data` | Critical |
| Flash / Erase partition | `fastboot flash boot boot.img` | Critical |
| SELinux disable | `setenforce 0` | Medium |
| System partition remount RW | `mount -o remount,rw /system` | Medium |
| System app uninstall | `pm uninstall com.android.packageinstaller` | High |
| Remote script execution | `curl http://x.sh \| sh` | Medium |
| Critical process kill | `kill -9 1` | Critical |
| Fork bomb | `:(){:|:&};:` | Critical |

Normal operations (such as `rm file.txt`, `rm -rf ./build`,
`dd if=/dev/zero of=image.img`, `chmod +x script.sh`, cleanup under `/data/local/tmp`)
are judged as safe and passed through directly.

## How It Works

1. **Detection engine** (`dsi/lib/detect.sh`): Normalizes the entire input command, extracts the command
   name and path arguments, evaluates each rule sequentially, and takes the highest severity level among
   matches. Detection is based on "command name + protected path + destructive behavior" rather than a
   simple keyword blacklist, so it can distinguish between normal `rm` and dangerous `rm -rf /data`.
2. **Dialog confirmation** (`dsi/lib/dialog.sh`): When a rule is hit, renders a terminal dialog box.
   If running in an interactive terminal, waits for user selection; if in a non-interactive environment
   (no TTY), safely defaults to reject and logs the event (can be changed to default-allow via
   environment variable `DSI_NONINTERACTIVE=allow`).
3. **Allow execution**: Only after the user selects "Allow" does the command actually run.
   Selecting "Allow & Whitelist" records the pattern in configuration so future matches are no longer asked.

## Installation

### Method 1: Magisk / KernelSU Module (Root)

Package the repository root directory as a ZIP (see "Build" below), flash it through Magisk or KernelSU's
"Install from local storage", then reboot. The module deploys tools to `/data/adb/dsi` on boot and creates
a symlink at `/data/adb/bin/dsi` (already in PATH). You can then use the `dsi` command directly.

### Method 2: ADB (Non-root)

Enable USB debugging on your device and connect it to your computer, then run from the project `dsi/`
directory:

```sh
./install-adb.sh
```

The script pushes the tool to `/data/local/tmp/dsi` on the device and sets executable permissions.
Then use it on the device:

```sh
adb shell /data/local/tmp/dsi/bin/dsi shell
adb shell /data/local/tmp/dsi/bin/dsi run "rm -rf /data"
```

> Note: Non-root cannot transparently intercept every command typed inside adb shell. Use `dsi run` for
> explicit execution, or enter `dsi shell` for a protected interactive environment.

## Usage

After installation, all operations go through `dsi` subcommands (ADB mode requires the full path
`/data/local/tmp/dsi/bin/dsi` or entering `dsi shell`; see below).

### Command Line

| Command | Description |
| --- | --- |
| `dsi run <command>` | Intercept and execute one command; dangerous ones show dialog first |
| `dsi check <command>` | Risk analysis only -- outputs severity and reason, does not execute |
| `dsi shell` | Start an interactive shell with interception functions loaded |
| `dsi log` | View interception log |
| `dsi allow <pattern>` | Add command pattern to whitelist (substring match) |
| `dsi unallow <pattern>` | Remove pattern from whitelist |
| `dsi set <key> <value>` | Modify config option (e.g., `dsi set rule.rm off`) |
| `dsi config` | Show current configuration |
| `dsi update` | Check and upgrade to the latest version from GitHub |
| `dsi help` | Display help |

Common examples:

```sh
# Check if a command is dangerous (does not execute)
dsi check rm -rf /data
dsi check "dd if=/dev/zero of=/dev/block/by-name/boot"
dsi check "curl http://x.sh | sh"

# Intercept and execute (dangerous commands trigger dialog on root)
dsi run rm -rf /system
dsi run pm uninstall com.android.packageinstaller

# Enter a protected interactive shell (every command is intercepted)
dsi shell

# Add patterns to whitelist so they are never asked again
dsi allow "rm -rf ./build"
dsi allow "dd if=/dev/zero of=image.img"

# View interception history and current config
dsi log
dsi config
```

### ADB (Non-root) Examples

Non-root cannot transparently intercept every command inside adb shell. Use `dsi run` for explicit
execution, or enter `dsi shell` for a protected interactive environment:

```sh
# Install (see "Installation - Method 2")
./dsi/install-adb.sh

# Detect / execute
adb shell /data/local/tmp/dsi/bin/dsi check "rm -rf /data"
adb shell /data/local/tmp/dsi/bin/dsi run "rm -rf /data"

# Protected interactive shell
adb shell /data/local/tmp/dsi/bin/dsi shell
```

### WebUI (KernelSU / MMRL)

After flashing the module on root, open this module's WebUI in KernelSU or MMRL. It provides:

- **Danger Rules**: Toggle each detection rule individually.
- **Command Checker**: Type a command for instant risk analysis.
- **Terminal**: Run `dsi` subcommands directly (`help`, `check rm -rf /data`, `config`, `log`, `update`).
- **Interception Log**: Browse historical interception records.
- **Whitelist**: Add or remove whitelist patterns online.
- **One-click Update**: Upgrade to the latest version with a single click.

### Transparent Interception (Optional)

To make every command you type in your current shell session intercepted transparently, source the
interception functions:

```sh
source /data/adb/dsi/lib/dsi-functions.sh
```

From that point, `rm`, `dd`, `chmod`, `chown`, `chgrp`, `mv` and other commands are automatically wrapped
and intercepted. Exit the session or run `exec $SHELL` to restore normal behavior. This method does not
affect any other system processes -- safe and controllable.

## One-click Update

The module is published in the GitHub repository Releases. The update logic works as follows:

- **Command line**: Run `dsi update`. The script queries the GitHub Releases API, compares the version
  number in the local `VERSION` file against the latest release, and downloads the new package if the
  local version is older.
- **WebUI**: Click the "Update" button in the page footer. Equivalent to running `dsi update`.

Download and flash behavior differs by runtime environment:

| Environment | Behavior |
| --- | --- |
| Root (Magisk installed) | Downloads then calls `magisk --install-module` to auto-flash; reboot required |
| Root (KernelSU installed) | Downloads then calls `ksud module install` to auto-flash |
| ADB / Non-root | Downloads the package locally only; manual flash required, **will not** auto-flash |

> Note: Due to permission restrictions, non-root environments cannot auto-flash modules. The update
> package is downloaded to the device (root mode: `/data/adb/dsi/update/`, ADB mode:
> `/data/local/tmp/`). Flash manually through Magisk / KernelSU.

## Configuration

The config file is located at `/data/adb/dsi/config.conf` (ADB mode: under the pushed directory),
see example at `dsi/config.example.conf`.

- `global.intercept=on|off`: Global interception master switch.
- `rule.<name>=on|off`: Individual rule toggle switches.
- `allow.*=<pattern>`: Whitelist entries; matching commands pass through immediately (substring match).

You can also toggle rules, manage whitelists, and view logs graphically via WebUI (KernelSU / MMRL).

## Directory Structure

```
DangerousShellInterceptor/
├── module.prop          Module metadata (id=dsi)
├── service.sh           Boot-time deployment (Magisk / KernelSU)
├── action.sh            Executed when module is enabled/applied (KernelSU)
├── post-fs-data.sh      Early-stage deployment supplement
├── customize.sh         Executed during Magisk installation phase
├── dsi-install.sh       Deployment logic (reused by scripts above)
├── banner               Module banner text
├── webroot/             WebUI (index.html / style.css / script.js)
├── dsi/
│   ├── bin/dsi          Main command binary
│   ├── lib/             Shared library / Detection engine / Dialog / Interception functions
│   ├── config.example.conf  Configuration example
│   └── install-adb.sh   ADB installation script
├── README.md            This document (Chinese)
├── README_EN.md         English documentation
├── LICENSE              MIT License
└── build.sh             Build script for module ZIP
```

## Building the Module ZIP

```sh
./build.sh
```

The generated ZIP is located at `dist/DangerousShellDSI.zip` and can be flashed directly into
Magisk / KernelSU.

## Notes

- Detection is based on heuristic analysis of command form. It effectively intercepts common dangerous
  operations but cannot replace complete understanding of command semantics.
- In non-interactive environments, execution is rejected by default. To allow in automation scripts,
  use the whitelist or set `DSI_NONINTERACTIVE=allow`.
- Scripts follow POSIX sh compatibility, working with Android mksh / busybox ash and Linux bash / dash.

## License

[MIT](LICENSE) - Copyright (c) 2026 xiaohondan (NekoAiDev)
