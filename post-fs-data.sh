#!/system/bin/sh
# 危险Shell拦截 DSI - post-fs-data.sh
# Magisk / KernelSU 在早期（post-fs-data 阶段，root）执行。
# 作为 service.sh 的补充，确保即便晚启动失败也能就位。

MODDIR=${0%/*}
. "$MODDIR/dsi-install.sh"

install_dsi "$MODDIR"
exit 0
