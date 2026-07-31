#!/system/bin/sh
# 危险Shell拦截 DSI - 公共库
# 提供日志、配置读取、路径工具等共享函数。
# 兼容 Android (mksh / busybox ash) 与 Linux (bash)，遵循 POSIX sh。

DSI_LIB_DIR="${DSI_LIB_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
DSI_ROOT="${DSI_ROOT:-${DSI_LIB_DIR}/..}"

# 配置与日志默认路径，可被环境变量覆盖。
DSI_CONFIG="${DSI_CONFIG:-$DSI_ROOT/config.conf}"
DSI_LOG="${DSI_LOG:-$DSI_ROOT/dsi.log}"

# 风险等级数值映射，用于比较严重程度。
DSI_SEV_NONE=0
DSI_SEV_LOW=1
DSI_SEV_MEDIUM=2
DSI_SEV_HIGH=3
DSI_SEV_CRITICAL=4

# 把人类可读的风险等级转成数值。
dsi_sev_of() {
    case "$1" in
        critical) echo "$DSI_SEV_CRITICAL" ;;
        high)     echo "$DSI_SEV_HIGH" ;;
        medium)   echo "$DSI_SEV_MEDIUM" ;;
        low)      echo "$DSI_SEV_LOW" ;;
        *)        echo "$DSI_SEV_NONE" ;;
    esac
}

# 把数值转成人类可读等级。
dsi_sev_name() {
    case "$1" in
        4) echo "critical" ;;
        3) echo "high" ;;
        2) echo "medium" ;;
        1) echo "low" ;;
        *) echo "none" ;;
    esac
}

# 写入一条拦截/执行日志。
# 用法: dsi_log <级别> <动作> <命令> [备注]
dsi_log() {
    _lvl="$1"; _act="$2"; _cmd="$3"; _note="$4"
    _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    {
        echo "[$_ts] level=$_lvl action=$_act"
        echo "  command: $_cmd"
        [ -n "$_note" ] && echo "  note: $_note"
    } >> "$DSI_LOG" 2>/dev/null
}

# 读取配置项的值。
# 用法: dsi_config_get <键> [默认值]
# 配置格式: 每行 "键=值" 或 "# 注释"。
dsi_config_get() {
    _key="$1"; _def="$2"
    [ -f "$DSI_CONFIG" ] || { echo "$_def"; return; }
    _val=$(grep -E "^[[:space:]]*$_key=" "$DSI_CONFIG" 2>/dev/null | tail -n1 | cut -d= -f2-)
    if [ -z "$_val" ]; then
        echo "$_def"
    else
        echo "$_val"
    fi
}

# 判断某个命令名是否在启用规则集中（白名单式开关）。
# 用法: dsi_rule_enabled <规则名>
dsi_rule_enabled() {
    _rule="$1"
    _state=$(dsi_config_get "rule.$_rule" "on")
    case "$_state" in
        on|1|true|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# 判断某条完整命令是否已被用户加入白名单。
# 用法: dsi_in_allowlist <命令字符串>
dsi_in_allowlist() {
    _cmd="$1"
    [ -f "$DSI_CONFIG" ] || return 1
    while IFS= read -r line; do
        case "$line" in
            allow.*=*) _pat="${line#allow.*=}"; _pat=$(echo "$_pat" | tr -d '"' | tr -d "'");;
            *) continue ;;
        esac
        case "$_cmd" in
            *"$_pat"*) return 0 ;;
        esac
    done < "$DSI_CONFIG"
    return 1
}

# 向白名单追加一条模式。
dsi_allow_add() {
    _pat="$1"
    [ -f "$DSI_CONFIG" ] || { echo "# 危险Shell拦截 DSI 配置文件" > "$DSI_CONFIG" 2>/dev/null; }
    echo "allow.*=$_pat" >> "$DSI_CONFIG" 2>/dev/null
}

# 受保护的系统路径前缀集合（空格分隔）。
# 这些目录下的破坏性操作默认会被拦截。
DSI_PROTECTED_PATHS="/ /system /vendor /data /boot /recovery /cache /persist /metadata /dev/block /dev/mtd /proc /sys /etc /bin /sbin /lib /lib64 /usr /init /default.prop /fstab"

# 判断给定路径是否落在受保护范围内。
# 用法: dsi_is_protected <路径>  -> 返回 0 表示受保护。
# 注意：此处使用单一 case 模式匹配，避免依赖未引号变量的单词分割，
# 以保证在 mksh / busybox ash / bash / zsh 下行为一致。
dsi_is_protected() {
    _p="$1"
    [ -z "$_p" ] && return 1
    # 去掉结尾斜杠，便于精确比较。
    case "$_p" in
        */) _p="${_p%/}" ;;
    esac
    # 展开 ~ 与 $HOME。
    case "$_p" in
        "~"|"~/"*) _p="${HOME:-/data/local/tmp}${_p#\~}" ;;
    esac
    case "$_p" in
        /|/*| \
        /system|/system/*| \
        /vendor|/vendor/*| \
        /data|/data/*| \
        /boot|/boot/*| \
        /recovery|/recovery/*| \
        /cache|/cache/*| \
        /persist|/persist/*| \
        /metadata|/metadata/*| \
        /dev/block|/dev/block/*| \
        /dev/mtd|/dev/mtd/*| \
        /proc|/proc/*| \
        /sys|/sys/*| \
        /etc|/etc/*| \
        /bin|/bin/*| \
        /sbin|/sbin/*| \
        /lib|/lib/*| \
        /lib64|/lib64/*| \
        /usr|/usr/*| \
        /init|/init/*| \
        /default.prop|/default.prop/*| \
        /fstab*|/fstab/*)
            # 安全临时目录除外（可放心递归清理，不视为受保护）
            case "$_p" in
                /data/local/tmp|/data/local/tmp/*| \
                /data/local|/data/local/*| \
                /cache|/cache/*| \
                /data/cache|/data/cache/*)
                    return 1 ;;
            esac
            return 0 ;;
    esac
    return 1
}

# 归一化命令字符串：压缩多余空格、去除首尾空白。
dsi_normalize() {
    _s="$1"
    _s=$(printf '%s' "$_s" | tr -s ' \t' ' ')
    _s=$(printf '%s' "$_s" | sed -e 's/^ //' -e 's/ $//' 2>/dev/null)
    printf '%s' "$_s"
}

# 去除常见命令包装前缀（sudo/doas/env/time/nohup/setsid/busybox/command），
# 以便正确识别被包裹的真实命令名与参数。
dsi_strip_prefixes() {
    _c=$(dsi_normalize "$1")
    _again=1
    while [ $_again -eq 1 ]; do
        _again=0
        case "$_c" in
            sudo\ *|doas\ *|env\ *|time\ *|nohup\ *|setsid\ *|busybox\ *|command\ *)
                _c=$(printf '%s' "$_c" | cut -d' ' -f2-)
                _again=1
                ;;
        esac
    done
    printf '%s' "$_c"
}

# 提取命令的第一个单词（命令名），去除路径前缀与包装前缀。
dsi_cmd_name() {
    _s=$(dsi_strip_prefixes "$1")
    _s=$(printf '%s' "$_s" | cut -d' ' -f1)
    case "$_s" in
        */*) _s=$(basename "$_s") ;;
    esac
    printf '%s' "$_s"
}
