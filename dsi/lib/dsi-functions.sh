#!/system/bin/sh
# 危险Shell拦截 DSI - 交互式 shell 拦截函数
# 由 `dsi shell` 或模块注入的 rc 文件 source，将危险命令重定义为函数，
# 实现“敲命令即拦截”。非 root 的 ADB 用户可通过 `dsi shell` 使用。

DSI_LIB_DIR="${DSI_LIB_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
DSI_ROOT="${DSI_ROOT:-$DSI_LIB_DIR/..}"
export DSI_LIB_DIR DSI_ROOT
: "${DSI_CONFIG:=$DSI_ROOT/config.conf}"
: "${DSI_LOG:=$DSI_ROOT/dsi.log}"
export DSI_CONFIG DSI_LOG

# 仅当库文件齐全且全局拦截开启时，才定义拦截函数，
# 避免模块异常时拖累所有 shell 会话。
if [ -f "$DSI_LIB_DIR/common.sh" ] && [ -f "$DSI_LIB_DIR/detect.sh" ] && [ -f "$DSI_LIB_DIR/dialog.sh" ]; then
    _enabled=$(dsi_config_get "global.intercept" "on" 2>/dev/null)
    if [ "$_enabled" != "off" ]; then
        . "$DSI_LIB_DIR/common.sh"
        . "$DSI_LIB_DIR/detect.sh"
        . "$DSI_LIB_DIR/dialog.sh"

        # 通用包装：检测 -> 弹窗 -> 放行则执行真实命令
        _dsi_wrap() {
            _name="$1"; shift
            dsi_detect "$_name $*"
            if [ "$DSI_RISK" != "none" ]; then
                dsi_dialog "$DSI_CMDLINE" "$DSI_RISK" "$DSI_RULE" "$DSI_REASON" "$DSI_TARGET"
                _rc=$?
                if [ "$_rc" -ne 0 ]; then
                    echo "[危险Shell拦截] 已拒绝执行: $_name $*" >&2
                    return 1
                fi
            fi
            command "$_name" "$@"
        }

        rm()    { _dsi_wrap rm "$@"; }
        dd()    { _dsi_wrap dd "$@"; }
        chmod() { _dsi_wrap chmod "$@"; }
        chown() { _dsi_wrap chown "$@"; }
        chgrp() { _dsi_wrap chgrp "$@"; }
        mv()    { _dsi_wrap mv "$@"; }
    fi
fi
