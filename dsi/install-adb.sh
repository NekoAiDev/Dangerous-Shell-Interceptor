#!/bin/sh
# 危险Shell拦截 DSI - ADB 安装脚本（非 root 也可用）
# 将 dsi 工具推送到设备的 /data/local/tmp/dsi，并配置好可执行权限。
# 非 root 用户无法透明拦截所有 shell 命令，但可通过以下方式使用：
#   1) dsi run "命令"        一次性拦截执行
#   2) dsi shell             进入受保护的交互式 shell
#   3) source dsi-aliases    为 rm/dd/chmod 等设置临时别名
#
# 用法: ./install-adb.sh [设备序列号(可选)]

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/data/local/tmp/dsi"

echo "[危险Shell拦截] 检查 adb ..."
if ! command -v adb >/dev/null 2>&1; then
    echo "未找到 adb，请先安装 Android Platform Tools 并加入 PATH。" >&2
    exit 1
fi

SERIAL=""
[ -n "${1:-}" ] && SERIAL="$1"
ADB="adb ${SERIAL:+ -s $SERIAL}"

echo "[危险Shell拦截] 检查设备连接 ..."
if ! $ADB get-state >/dev/null 2>&1; then
    echo "未检测到已连接的设备，请开启 USB 调试并授权。" >&2
    exit 1
fi

echo "[危险Shell拦截] 推送文件到 $DEST ..."
$ADB shell "mkdir -p $DEST" 2>/dev/null || true
$ADB push "$HERE/bin" "$DEST/" >/dev/null
$ADB push "$HERE/lib" "$DEST/" >/dev/null
$ADB push "$HERE/config.example.conf" "$DEST/config.conf" >/dev/null

echo "[危险Shell拦截] 设置可执行权限 ..."
$ADB shell "chmod -R 0755 $DEST/bin $DEST/lib" 2>/dev/null || true
$ADB shell "chmod 0644 $DEST/config.conf" 2>/dev/null || true

echo ""
echo "[危险Shell拦截] 安装完成。在设备上的使用方式："
echo "  进入受保护 shell : adb shell $DEST/bin/dsi shell"
echo "  拦截执行一条命令 : adb shell $DEST/bin/dsi run \"rm -rf /data\""
echo "  仅检测不执行     : adb shell $DEST/bin/dsi check \"dd if=/dev/zero of=/dev/block/by-name/boot\""
echo "  查看日志         : adb shell $DEST/bin/dsi log"
echo ""
echo "提示：非 root 无法透明拦截 adb shell 内所有命令，请使用 dsi run / dsi shell。"
echo "若已 root（面具/KernelSU 模块已刷入），模块会在开机后自动注入拦截。"
