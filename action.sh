#!/system/bin/sh
# 危险Shell拦截 DSI - action.sh
# KernelSU：模块被启用 / 应用时执行；也兼容 Magisk 手动触发。
# 复用安装逻辑，确保工具就位。

MODDIR=${0%/*}
. "$MODDIR/dsi-install.sh"

install_dsi "$MODDIR"
exit 0
