#!/system/bin/sh
# 危险Shell拦截 DSI - 检测引擎
# 分析一条 shell 命令，判断其危险等级并给出中文原因。
# 设计原则：
#   1. 广度优先：覆盖删除、格式化、分区、权限、重定向、刷写、提权、供应链等场景。
#   2. 精准放行：普通 rm 文件、非受保护路径的常规操作不会被拦截。
#   3. 严重程度：none < low < medium < high < critical，取命中的最高等级。
#
# 输出（全局变量，由 dsi_detect 填充）：
#   DSI_RISK     风险等级字符串（none/low/medium/high/critical）
#   DSI_RULE     命中的规则 id
#   DSI_REASON   危险原因（中文，面向用户）
#   DSI_TARGET   具体危险目标（路径/设备/包名等）
#   DSI_SEV      数值化严重程度
#   DSI_CMDLINE  归一化后的命令

# 提取命令中的“路径型”参数。
# 参数: <skip> <命令>  skip=1 时跳过首个 token（命令名），skip=0 不跳过。
# 仅输出看起来像路径的 token（以 / ~ ./ ../ 开头，或含 /）。
dsi_path_tokens_impl() {
    _skip="$1"; shift
    _c=$(dsi_strip_prefixes "$1")
    for _t in $_c; do
        if [ "$_skip" -eq 1 ]; then _skip=0; continue; fi
        case "$_t" in
            -*) continue ;;
        esac
        case "$_t" in
            /*|~*|./*|../*|*/bin/*)
                printf '%s\n' "$_t" ;;
            */*)
                printf '%s\n' "$_t" ;;
        esac
    done
}

# 默认跳过命令名。
dsi_path_tokens() {
    dsi_path_tokens_impl 1 "$1"
}

# 提取输出重定向（> / >>）后面的目标路径。
# 仅分析重定向符号之后的片段，避免误伤 mv/ls/cat 等普通命令。
dsi_path_tokens_redirect() {
    _c=$(dsi_strip_prefixes "$1")
    # 用换行标记重定向点，仅处理其后的片段
    _c=$(printf '%s' "$_c" | sed -e 's/>>/\nREDIRECT /g' -e 's/>/\nREDIRECT /g' 2>/dev/null)
    printf '%s\n' "$_c" | while IFS= read -r _line; do
        case "$_line" in
            REDIRECT\ *) dsi_path_tokens_impl 0 "${_line#REDIRECT }" ;;
        esac
    done
}

# 命中上报：仅在严重程度更高时覆盖全局结果。
dsi_rule_report() {
    _s="$1"; _rule="$2"; _reason="$3"; _target="$4"
    if [ "$_s" -gt "$DSI_SEV" ]; then
        DSI_SEV="$_s"
        DSI_RISK=$(dsi_sev_name "$_s")
        DSI_RULE="$_rule"
        DSI_REASON="$_reason"
        DSI_TARGET="$_target"
    fi
}

# ---------------------------------------------------------------------------
# 规则集合
# 每个规则函数接收归一化命令字符串，命中时调用 dsi_rule_report。
# ---------------------------------------------------------------------------

# 1. fork 炸弹
dsi_rule_forkbomb() {
    case "$1" in
        *":(){:|:&};:"*|*":(): :|: & };:"*|*":(){ :|:& };:"*|*"():(){ :|:& };:"*)
            dsi_rule_enabled forkbomb || return
            dsi_rule_report "$DSI_SEV_CRITICAL" "forkbomb" \
                "检测到 fork 炸弹（无限递归衍生进程）。这会迅速耗尽系统进程表与内存，导致设备死机、需要强制重启。" ""
            ;;
    esac
}

# 2. dd 写入块设备
dsi_rule_dd() {
    case "$(dsi_cmd_name "$1")" in dd) ;; *) return ;; esac
    dsi_rule_enabled dd || return
    for _t in $1; do
        case "$_t" in
            of=*) _dev="${_t#of=}" ;;
            *) continue ;;
        esac
        case "$_dev" in
            /dev/*|/dev/block/*|/dev/mtd*|/dev/sd*|/dev/mmc*|/dev/nand*)
                dsi_rule_report "$DSI_SEV_CRITICAL" "dd" \
                    "检测到 dd 命令将写入设备节点 \"$_dev\"。直接向块设备写入会覆盖分区数据，可能造成设备无法启动或数据永久损坏。" "$_dev"
                return ;;
        esac
    done
}

# 3. 格式化 / 分区操作
dsi_rule_mkfs() {
    _c=$(dsi_cmd_name "$1")
    case "$_c" in
        mkfs*|mke2fs|mkswap|newfs|wipefs|parted|fdisk|sgdisk|cfdisk|partprobe|mkfs) ;;
        *) return ;;
    esac
    dsi_rule_enabled mkfs || return
    _sev="$DSI_SEV_HIGH"
    _reason="检测到磁盘/分区操作命令 \"$_c\"。该命令会创建、修改或销毁分区表与文件系统，可能导致数据丢失。"
    case "$_c" in
        mkfs*|mke2fs|mkswap|wipefs)
            _sev="$DSI_SEV_CRITICAL"
            _reason="检测到格式化/文件系统创建命令 \"$_c\"。该操作会清空目标分区上的全部数据且不可恢复。" ;;
    esac
    _tgt=""
    for _t in $1; do
        case "$_t" in
            /dev/*) _tgt="$_t" ;;
        esac
    done
    dsi_rule_report "$_sev" "mkfs" "$_reason" "$_tgt"
}

# 4. rm 删除受保护路径
dsi_rule_rm() {
    case "$(dsi_cmd_name "$1")" in rm) ;; *) return ;; esac
    dsi_rule_enabled rm || return
    _rec=0
    for _t in $1; do
        case "$_t" in
            -r|-R|-rf|-fr|--recursive) _rec=1 ;;
        esac
    done
    case "$1" in
        *" -r "*|*" -R "*|*" -rf "*|*" -fr "*|*" --recursive "*|*" -r"|*" -rf"|*" -R"|*" --recursive")
            _rec=1 ;;
    esac

    _hit=0; _sev="$DSI_SEV_NONE"; _reason=""; _target=""
    for _p in $(dsi_path_tokens "$1"); do
        if dsi_is_protected "$_p"; then
            _hit=1
            if [ "$_rec" -eq 1 ]; then
                _s="$DSI_SEV_HIGH"
                _r="检测到对受保护系统目录 \"$_p\" 执行递归删除（rm -r/-rf）。该操作会不可逆地清除系统或用户数据，可能导致设备无法启动、数据永久丢失。"
                case "$_p" in
                    /|/system|/data|/vendor|/boot|/recovery|/etc|/bin|/sbin|/lib|/lib64|/usr|/*)
                        _s="$DSI_SEV_CRITICAL"
                        _r="检测到递归删除关键系统路径 \"$_p\"（含根目录及其核心分区）。此操作极可能破坏系统完整性，造成设备变砖或所有用户数据被清除，且不可恢复。" ;;
                esac
            else
                _s="$DSI_SEV_MEDIUM"
                _r="检测到删除受保护路径 \"$_p\" 下的对象。该路径属于系统或用户数据分区，误删可能影响系统功能或丢失数据。"
            fi
            if [ "$_s" -gt "$_sev" ]; then _sev="$_s"; _reason="$_r"; _target="$_p"; fi
        fi
    done

    # 显式匹配 rm -rf / 与 rm -rf /*
    case "$1" in
        *"rm -rf / "*|*"rm -rf /"|*"rm -rf /*"|*"rm -r / "*|*"rm -r /"|*"rm -r /*")
            if [ "$_sev" -lt "$DSI_SEV_CRITICAL" ]; then
                _sev="$DSI_SEV_CRITICAL"
                _reason="检测到删除根文件系统（rm -rf /）。这会摧毁整个系统分区与全部数据，设备将立即无法使用。"
                _target="/"
            fi ;;
    esac

    if [ "$_hit" -eq 1 ] || [ "$_sev" -ge "$DSI_SEV_CRITICAL" ]; then
        dsi_rule_report "$_sev" "rm" "$_reason" "$_target"
    fi
}

# 5. chmod / chown / chgrp 修改受保护路径
dsi_rule_chmod_chown() {
    _c=$(dsi_cmd_name "$1")
    case "$_c" in chmod|chown|chgrp) ;; *) return ;; esac
    dsi_rule_enabled chmod_chown || return
    _rec=0
    for _t in $1; do
        case "$_t" in -R|--recursive) _rec=1 ;; esac
    done
    # 检测把权限设为 000/0（剥夺全部访问）
    _zero=0
    for _t in $1; do
        case "$_t" in 000|0) _zero=1 ;; esac
    done

    _sev="$DSI_SEV_NONE"; _reason=""; _tgt=""
    for _p in $(dsi_path_tokens "$1"); do
        if dsi_is_protected "$_p"; then
            if [ "$_zero" -eq 1 ]; then
                _s="$DSI_SEV_CRITICAL"
                _r="检测到将受保护路径 \"$_p\" 的权限设为 000/0（完全不可访问）。这会直接导致系统或关键文件不可用，设备可能无法启动。"
            elif [ "$_rec" -eq 1 ]; then
                _s="$DSI_SEV_HIGH"
                _r="检测到对受保护路径 \"$_p\" 递归修改权限/属主（chmod/chown -R）。错误的权限设置会导致系统服务无法运行、设备无法启动。"
            else
                _s="$DSI_SEV_MEDIUM"
                _r="检测到修改受保护路径 \"$_p\" 的权限/属主。不当修改可能影响系统功能。"
            fi
            if [ "$_s" -gt "$_sev" ]; then _sev="$_s"; _reason="$_r"; _tgt="$_p"; fi
        fi
    done
    [ "$_sev" -gt "$DSI_SEV_NONE" ] && dsi_rule_report "$_sev" "chmod_chown" "$_reason" "$_tgt"
}

# 6. 输出重定向覆盖受保护文件
dsi_rule_redirect() {
    dsi_rule_enabled redirect || return
    for _p in $(dsi_path_tokens_redirect "$1"); do
        if dsi_is_protected "$_p"; then
            dsi_rule_report "$DSI_SEV_HIGH" "redirect" \
                "检测到通过输出重定向（> / >>）覆盖受保护路径 \"$_p\"。这会直接改写或清空系统关键文件，可能破坏系统或丢失配置。" "$_p"
            return
        fi
    done
}

# 7. mv 移动受保护路径对象
dsi_rule_mv() {
    case "$(dsi_cmd_name "$1")" in mv) ;; *) return ;; esac
    dsi_rule_enabled mv || return
    for _p in $(dsi_path_tokens "$1"); do
        if dsi_is_protected "$_p"; then
            dsi_rule_report "$DSI_SEV_MEDIUM" "mv" \
                "检测到移动/重命名受保护路径 \"$_p\" 下的对象。对系统分区的移动操作可能破坏文件结构或服务依赖。" "$_p"
            return
        fi
    done
}

# 8. 擦除 / 格式化类命令
dsi_rule_wipe() {
    _c=$(dsi_cmd_name "$1")
    case "$_c" in wipe|format) ;; *) return ;; esac
    dsi_rule_enabled wipe || return
    dsi_rule_report "$DSI_SEV_CRITICAL" "wipe" \
        "检测到擦除/格式化类命令 \"$_c\"。该操作会清除分区或设备数据，且通常不可恢复。" ""
}

# 9. 刷写 / 擦除分区（fastboot / adb）
dsi_rule_flash() {
    case "$1" in
        *"fastboot flash"*|*"fastboot erase"*|*"adb shell recovery --wipe_data"*|*"flash_image"*)
            dsi_rule_enabled flash || return
            _tgt=""
            case "$1" in
                *"fastboot flash "*|*"fastboot erase "*)
                    _tgt=$(printf '%s' "$1" | sed -e 's/.*fastboot \(flash\|erase\) //' | cut -d' ' -f1) ;;
            esac
            dsi_rule_report "$DSI_SEV_CRITICAL" "flash" \
                "检测到刷写/擦除分区命令（fastboot flash/erase）。错误的镜像或分区名会导致设备无法启动（变砖）。" "$_tgt" ;;
    esac
}

# 10. 关闭 SELinux
dsi_rule_selinux() {
    case "$1" in
        *"setenforce 0"*|*"setenforce permissive"*)
            dsi_rule_enabled selinux || return
            dsi_rule_report "$DSI_SEV_MEDIUM" "selinux" \
                "检测到关闭 SELinux 强制模式（setenforce 0）。这会削弱系统安全隔离，使恶意程序更容易获取提权，仅建议在受控调试环境使用。" "" ;;
    esac
}

# 11. 以读写方式重新挂载系统分区
dsi_rule_mount_rw() {
    case "$1" in
        *"mount -o remount,rw"*|*"-o remount rw"*|*"mount -o rw,remount"*|*"remount,rw /system"*|*"remount,rw /"*)
            dsi_rule_enabled mount_rw || return
            dsi_rule_report "$DSI_SEV_MEDIUM" "mount_rw" \
                "检测到以可读写方式重新挂载系统分区（mount -o remount,rw）。这允许修改本应只读的系统文件，误操作会破坏系统完整性。" "" ;;
    esac
}

# 12. 卸载 / 禁用系统核心应用
dsi_rule_pm_uninstall() {
    case "$1" in
        *"pm uninstall"*|*"pm disable"*|*"pm clear"*)
            dsi_rule_enabled pm_uninstall || return
            _pkg=""
            for _t in $1; do
                case "$_t" in com.android.*|com.google.*) _pkg="$_t" ;; esac
            done
            if [ -n "$_pkg" ]; then
                dsi_rule_report "$DSI_SEV_HIGH" "pm_uninstall" \
                    "检测到卸载/禁用系统核心应用 \"$_pkg\"（pm uninstall/disable）。移除核心组件会导致系统功能异常、界面崩溃甚至无法开机。" "$_pkg"
            else
                dsi_rule_report "$DSI_SEV_LOW" "pm_uninstall" \
                    "检测到包管理操作（pm uninstall/disable/clear）。卸载或清除应用会丢失该应用的数据。" ""
            fi ;;
    esac
}

# 13. 网络下载脚本并直接执行（供应链风险）
dsi_rule_curl_pipe() {
    case "$1" in
        *"curl"*"|"*"sh"*|*"curl"*"|"*"bash"*|*"wget"*"|"*"sh"*|*"wget"*"|"*"bash"*)
            dsi_rule_enabled curl_pipe || return
            dsi_rule_report "$DSI_SEV_MEDIUM" "curl_pipe" \
                "检测到从网络下载脚本并直接执行（curl/wget | sh）。这属于供应链风险：若来源被篡改或劫持，会直接在设备上运行任意代码。" "" ;;
    esac
}

# 14. 终止关键进程
dsi_rule_kill() {
    case "$(dsi_cmd_name "$1")" in kill|pkill|killall) ;; *) return ;; esac
    dsi_rule_enabled kill || return
    case "$1" in
        *"kill -9 1"*|*"kill -9 init"*|*"kill -KILL 1"*|*"kill -9 0"*|*"killall -9"*|*"pkill -9"*|*"killall "*|*"pkill "*)
            dsi_rule_report "$DSI_SEV_CRITICAL" "kill" \
                "检测到终止关键进程（kill -9 1/init 或 killall/pkill）。结束 init 或系统核心进程会导致系统立即重启或进入不稳定状态（软变砖）。" "" ;;
    esac
}

# ---------------------------------------------------------------------------
# 主入口
# 用法: dsi_detect <命令字符串>
# ---------------------------------------------------------------------------
dsi_detect() {
    DSI_CMDLINE=$(dsi_normalize "$1")
    DSI_RISK="none"; DSI_RULE=""; DSI_REASON=""; DSI_TARGET=""; DSI_SEV="$DSI_SEV_NONE"

    # 白名单命中直接放行
    if dsi_in_allowlist "$DSI_CMDLINE"; then
        DSI_RISK="none"
        return 0
    fi

    dsi_rule_forkbomb "$DSI_CMDLINE"
    dsi_rule_dd "$DSI_CMDLINE"
    dsi_rule_mkfs "$DSI_CMDLINE"
    dsi_rule_rm "$DSI_CMDLINE"
    dsi_rule_chmod_chown "$DSI_CMDLINE"
    dsi_rule_redirect "$DSI_CMDLINE"
    dsi_rule_mv "$DSI_CMDLINE"
    dsi_rule_wipe "$DSI_CMDLINE"
    dsi_rule_flash "$DSI_CMDLINE"
    dsi_rule_selinux "$DSI_CMDLINE"
    dsi_rule_mount_rw "$DSI_CMDLINE"
    dsi_rule_pm_uninstall "$DSI_CMDLINE"
    dsi_rule_curl_pipe "$DSI_CMDLINE"
    dsi_rule_kill "$DSI_CMDLINE"
    return 0
}
