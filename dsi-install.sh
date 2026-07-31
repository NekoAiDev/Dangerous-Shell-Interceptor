#!/system/bin/sh
# 危险Shell拦截 DSI - 安装/初始化逻辑
# 被 service.sh / action.sh / customize.sh / post-fs-data.sh 调用。
# 职责：把 dsi 工具部署到 /data/adb/dsi，并链接到 PATH，确保配置文件存在。

# ui_print：若调用方（如 Magisk customize.sh）已提供则复用，否则退化为 echo。
if ! command -v ui_print >/dev/null 2>&1; then
    ui_print() { echo "[危险Shell拦截 DSI] $1"; }
fi

install_dsi() {
    MODDIR="$1"
    SRC="$MODDIR/dsi"
    DST="/data/adb/dsi"
    BIN_DST="/data/adb/bin/dsi"

    if [ ! -d "$SRC" ]; then
        ui_print "找不到源文件目录: $SRC"
        return 1
    fi

    ui_print "部署拦截工具到 $DST ..."
    mkdir -p "$DST/bin" "$DST/lib" "/data/adb/bin"

    cp -f "$SRC/bin/dsi"        "$DST/bin/dsi"     2>/dev/null
    cp -f "$SRC/lib/"*.sh       "$DST/lib/"        2>/dev/null
    cp -f "$SRC/install-adb.sh" "$DST/"            2>/dev/null

    if [ ! -f "$DST/config.conf" ]; then
        cp -f "$SRC/config.example.conf" "$DST/config.conf" 2>/dev/null
    fi

    chmod 0755 "$DST/bin/dsi"
    chmod 0644 "$DST/lib/"*.sh "$DST/config.conf" 2>/dev/null
    chmod 0755 "$DST/install-adb.sh" 2>/dev/null

    # Magisk 与 KernelSU 均将 /data/adb/bin 加入 PATH，链接后即可直接使用 dsi 命令
    ln -sf "$DST/bin/dsi" "$BIN_DST" 2>/dev/null

    ui_print "安装完成。使用方式："
    ui_print "  dsi run \"命令\"        拦截并执行一条命令"
    ui_print "  dsi shell              进入受保护的交互式 shell"
    ui_print "  dsi check \"命令\"      仅检测不执行"
    return 0
}

# 当本脚本被直接执行时（source 时不会走到这里）
case "${0##*/}" in
    dsi-install.sh)
        MODDIR=$(cd "$(dirname "$0")" && pwd)
        install_dsi "$MODDIR"
        ;;
esac
