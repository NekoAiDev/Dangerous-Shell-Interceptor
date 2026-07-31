#!/system/bin/sh
# 危险Shell拦截 DSI - service.sh
# Magisk / KernelSU 开机后（late_start 服务阶段）执行，以 root 运行。
# 负责把拦截工具部署到持久目录并挂载到 PATH。

MODDIR=${0%/*}
. "$MODDIR/dsi-install.sh"

install_dsi "$MODDIR"
exit 0
