# 危险Shell拦截 DSI

Dangerous Shell Interceptor

一个用于 Android（面具 / KernelSU）与 ADB（非 root）环境的 shell 命令安全拦截模块。
当检测到危险命令（例如递归删除 `/data`、向块设备写入 `dd`、格式化分区、刷写 `boot`、
关闭 SELinux 等）时，自动拦截并弹出确认对话框，由用户决定「拒绝执行」或「允许执行」，
同时在对话框中说明该命令的具体危险点。

## 功能特性

- 广度检测：覆盖删除、格式化、分区、权限、重定向、刷写、提权、供应链等十余类危险场景。
- 精准放行：普通 `rm 文件`、`dd` 写普通文件、`chmod +x` 等操作不会被拦截。
- 交互弹窗：终端内渲染确认对话框，展示命令、风险等级、危险原因与危险目标，提供「拒绝执行 / 允许执行 / 允许并加入白名单」三个选项。
- 安全默认：非交互环境（管道、脚本）下一律默认「拒绝执行」并记录日志，避免误伤。
- 双模式：root 模块（面具 / KernelSU）开机自动部署；非 root 的 ADB 用户也可通过 `install-adb.sh` 使用。
- WebUI：提供规则开关、白名单管理、拦截日志查看、命令检测与内置终端（KernelSU / MMRL）。
- WebUI 终端：可直接在网页端运行 dsi 子命令（如 `help`、`check rm -rf /data`、`update`）。
- 一键更新：网页端点击「一键更新」，root 环境自动下载并刷入新版本；ADB 非 root 仅下载更新包，不自动刷入。
- 横幅：模块与 WebUI 展示项目横幅图。
- 中文友好：对话框与说明均为中文，折行按字符宽度处理，兼容各类 locale。

作者：小红蛋 ｜ 组织团队：NekoAiDev

## 危险命令覆盖范围

| 规则 | 触发示例 | 风险 |
| --- | --- | --- |
| 递归删除 | `rm -rf /data`、`rm -rf /system`、`rm -rf /` | 严重 |
| 块设备写入 | `dd if=/dev/zero of=/dev/block/by-name/boot` | 严重 |
| 格式化 / 分区 | `mkfs.ext4 /dev/sdb1`、`parted /dev/sda mklabel` | 严重 / 高 |
| 权限 / 属主修改 | `chmod -R 000 /system`、`chown -R root:root /data` | 严重 / 高 |
| 重定向覆盖 | `> /etc/passwd`、`echo x > /system/build.prop` | 高 |
| 移动 / 重命名 | `mv /data/app /data/app_bak` | 中 |
| 擦除 / 格式化 | `wipe data` | 严重 |
| 刷写 / 擦除分区 | `fastboot flash boot boot.img` | 严重 |
| SELinux 关闭 | `setenforce 0` | 中 |
| 系统分区改写挂载 | `mount -o remount,rw /system` | 中 |
| 系统应用卸载 | `pm uninstall com.android.packageinstaller` | 高 |
| 网络脚本直执行 | `curl http://x.sh \| sh` | 中 |
| 关键进程终止 | `kill -9 1` | 严重 |
| fork 炸弹 | `:(){:|:&};:` | 严重 |

普通操作（如 `rm file.txt`、`rm -rf ./build`、`dd if=/dev/zero of=image.img`、
`chmod +x script.sh`、`/data/local/tmp` 下的清理）均判定为安全并直接放行。

## 工作原理

1. **检测引擎**（`dsi/lib/detect.sh`）：对输入的整条命令做归一化、提取命令名与路径参数，
   依次评估各规则，取命中的最高严重程度。检测以「命令名 + 受保护路径 + 破坏性行为」为判定依据，
   而非简单的关键字黑名单，因此能区分正常 `rm` 与危险的 `rm -rf /data`。
2. **弹窗确认**（`dsi/lib/dialog.sh`）：命中危险时渲染终端对话框。若处于交互终端，等待用户选择；
   若处于非交互环境（无 TTY），安全默认拒绝并写日志（可通过环境变量 `DSI_NONINTERACTIVE=allow` 改为默认放行）。
3. **放行执行**：用户选择「允许执行」后，命令才会真正运行；选择「允许并加入白名单」会将其记入配置，后续不再询问。

## 安装方式

### 方式一：面具 / KernelSU 模块（root）

将仓库根目录打包为 ZIP（见下方「构建」），通过面具或 KernelSU 的「从本地安装」刷入，重启即可。
模块会在开机后把工具部署到 `/data/adb/dsi`，并链接到 PATH（`/data/adb/bin/dsi`），之后可直接使用 `dsi` 命令。

### 方式二：ADB（非 root 也可用）

设备开启 USB 调试并连接电脑后，在项目 `dsi/` 目录下执行：

```sh
./install-adb.sh
```

脚本会把工具推送到设备的 `/data/local/tmp/dsi`，并设置可执行权限。随后在设备上使用：

```sh
adb shell /data/local/tmp/dsi/bin/dsi shell
adb shell /data/local/tmp/dsi/bin/dsi run "rm -rf /data"
```

> 说明：非 root 无法透明拦截 adb shell 内输入的每一条命令。请通过 `dsi run` 显式执行，
> 或进入 `dsi shell` 获得受保护的交互式环境。

## 使用方式

安装完成后，所有操作通过 `dsi` 子命令完成（ADB 模式需用完整路径
`/data/local/tmp/dsi/bin/dsi` 或进入 `dsi shell`，见下方说明）。

### 命令行

| 命令 | 说明 |
| --- | --- |
| `dsi run <命令>` | 拦截并执行一条命令；危险则弹窗确认，放行才真正运行 |
| `dsi check <命令>` | 仅做风险分析并输出等级与原因，不执行 |
| `dsi shell` | 启动一个加载了拦截函数的交互式 shell（敲命令即拦截） |
| `dsi log` | 查看拦截日志 |
| `dsi allow <模式>` | 将命令模式加入白名单（子串匹配） |
| `dsi unallow <模式>` | 从白名单移除 |
| `dsi set <键> <值>` | 修改配置项（如 `dsi set rule.rm off`） |
| `dsi config` | 查看当前配置 |
| `dsi update` | 检查并升级到 GitHub 上的最新版本 |
| `dsi help` | 显示帮助 |

常用示例：

```sh
# 检测一条命令是否危险（不执行）
dsi check rm -rf /data
dsi check "dd if=/dev/zero of=/dev/block/by-name/boot"
dsi check "curl http://x.sh | sh"

# 拦截并执行（root 环境危险时会弹窗确认）
dsi run rm -rf /system
dsi run pm uninstall com.android.packageinstaller

# 进入受保护的交互式 shell，敲命令即拦截
dsi shell

# 把某类命令加入白名单，之后不再询问
dsi allow "rm -rf ./build"
dsi allow "dd if=/dev/zero of=image.img"

# 查看拦截记录与当前配置
dsi log
dsi config
```

### ADB（非 root）使用示例

非 root 无法透明拦截 adb shell 内输入的每一条命令，请用 `dsi run` 显式执行，
或进入 `dsi shell` 获得受保护的交互环境：

```sh
# 安装（见「安装方式 - 方式二」）
./dsi/install-adb.sh

# 检测 / 执行
adb shell /data/local/tmp/dsi/bin/dsi check "rm -rf /data"
adb shell /data/local/tmp/dsi/bin/dsi run "rm -rf /data"

# 受保护的交互式 shell
adb shell /data/local/tmp/dsi/bin/dsi shell
```

### WebUI（KernelSU / MMRL）

root 环境刷入模块后，可在 KernelSU 或 MMRL 中打开本模块 WebUI，提供：

- **危险规则**：逐条开关各检测规则。
- **命令检测**：在线输入命令做风险分析。
- **终端**：直接运行 dsi 子命令（如 `help`、`check rm -rf /data`、`config`、`log`、`update`）。
- **拦截日志**：查看历史拦截记录。
- **白名单**：在线增删白名单模式。
- **一键更新**：点击即可升级到最新版本。

### 透明拦截（可选）

若希望在当前 shell 会话中「敲命令即拦截」，可 source 拦截函数：

```sh
source /data/adb/dsi/lib/dsi-functions.sh
```

此后 `rm`、`dd`、`chmod`、`chown`、`chgrp`、`mv` 等命令会被自动包裹并拦截。
退出会话或执行 `exec $SHELL` 重新进入即可恢复原样。该方式不会影响系统其他进程，安全可控。

## 一键更新

模块发布在 GitHub 仓库的 Releases 中，更新逻辑如下：

- **命令行**：执行 `dsi update`，脚本会访问 GitHub Releases 接口，
  比对当前 `VERSION` 文件中的版本号与最新发布版本，若本地较旧则下载新版本包。
- **WebUI**：点击页脚的「一键更新」按钮，等效于执行 `dsi update`。

下载与刷入行为按运行环境自动区分：

| 环境 | 行为 |
| --- | --- |
| root（已安装面具） | 下载后调用 `magisk --install-module` 自动刷入，重启生效 |
| root（已安装 KernelSU） | 下载后调用 `ksud module install` 自动刷入 |
| ADB / 非 root | 仅下载新版本包到本地，需用户手动刷入，**不会**自动刷入 |

> 说明：非 root 环境因权限限制无法自动刷入模块，所以只会把更新包下载到设备
> （root 模式为 `/data/adb/dsi/update/`，ADB 模式为 `/data/local/tmp/`），
> 由用户自行通过面具 / KernelSU 安装。

## 配置说明

配置文件位于 `/data/adb/dsi/config.conf`（ADB 模式为推送目录下的 `config.conf`），示例见 `dsi/config.example.conf`。

- `global.intercept=on|off`：全局拦截总开关。
- `rule.<名称>=on|off`：各规则独立开关。
- `allow.*=<模式>`：白名单，匹配到的命令直接放行（子串匹配）。

也可通过 WebUI（KernelSU / MMRL）在图形界面中切换规则、管理白名单与查看日志。

## 目录结构

```
危险Shell拦截DSI/
├── module.prop          模块元数据（id=dsi）
├── service.sh           开机部署（Magisk / KernelSU）
├── action.sh            模块启用/应用时执行（KernelSU）
├── post-fs-data.sh      早期部署补充
├── customize.sh         面具安装阶段执行
├── dsi-install.sh       部署逻辑（被上述脚本复用）
├── banner               模块横幅
├── webroot/             WebUI（index.html / style.css / script.js）
├── dsi/
│   ├── bin/dsi          主命令
│   ├── lib/             公共库 / 检测引擎 / 弹窗 / 拦截函数
│   ├── config.example.conf  配置示例
│   └── install-adb.sh   ADB 安装脚本
├── README.md
├── LICENSE
└── build.sh             构建模块 ZIP
```

## 构建模块 ZIP

```sh
./build.sh
```

生成的 ZIP 位于 `dist/危险Shell拦截DSI.zip`，可直接刷入面具 / KernelSU。

## 注意事项

- 检测基于命令形态启发式分析，能有效拦截常见危险操作，但不能替代对命令语义的完整理解。
- 非交互环境下默认拒绝执行，若需在自动化脚本中放行，请使用白名单或将 `DSI_NONINTERACTIVE` 设为 `allow`。
- 脚本遵循 POSIX sh，兼容 Android 的 mksh / busybox ash 与 Linux 的 bash / dash。
