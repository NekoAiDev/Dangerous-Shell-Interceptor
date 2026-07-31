#!/system/bin/sh
# 危险Shell拦截 DSI - customize.sh
# Magisk 安装阶段（recovery / 临时系统）执行。
# 此时 $MODPATH 指向模块安装目录，可提前把工具部署好。

# Magisk 会注入 ui_print；若未定义则退化为 echo。
if ! command -v ui_print >/dev/null 2>&1; then
    ui_print() { echo "$1"; }
fi

MODDIR="${MODPATH:-${0%/*}}"
. "$MODDIR/dsi-install.sh"

ui_print "*******************************"
ui_print "   危险Shell拦截 DSI 安装中"
ui_print "*******************************"
install_dsi "$MODDIR"
ui_print "安装完成，重启后生效。"
