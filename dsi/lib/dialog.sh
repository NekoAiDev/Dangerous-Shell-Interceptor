#!/system/bin/sh
# 危险Shell拦截 DSI - 交互弹窗
# 在终端中渲染危险命令确认对话框。
# 无 TTY（非交互/管道）环境下安全默认“拒绝执行”并记录日志。
# 风格：纯文本边框，不依赖 whiptail/dialog，兼容 Android mksh 与 Linux。

# 按显示宽度折行，与 locale 无关（逐字节解析 UTF-8，绝不截断多字节字符）。
# ASCII 宽度 1，多字节字符（含中文）宽度按 2 近似。
dsi_wrap() {
    _text="$1"; _max="$2"
    _n=$(printf '%s' "$_text" | wc -c 2>/dev/null || echo 0)
    if [ -z "$_text" ] || [ "$_n" -eq 0 ]; then
        printf '%s\n' "$_text"
        return
    fi
    _i=0; _cur=0; _line=""; _char=""; _charw=0
    while [ "$_i" -lt "$_n" ]; do
        _i=$(( _i + 1 ))
        _b=$(printf '%s' "$_text" | cut -b "$_i" 2>/dev/null | od -A n -t u1 2>/dev/null | tr -d ' \n')
        [ -z "$_b" ] && _b=0
        _w=0; _islead=0
        if [ "$_b" -lt 128 ]; then
            _w=1; _islead=1
        elif [ "$_b" -ge 194 ] && [ "$_b" -le 223 ]; then
            _w=2; _islead=1
        elif [ "$_b" -ge 224 ] && [ "$_b" -le 239 ]; then
            _w=2; _islead=1
        elif [ "$_b" -ge 240 ] && [ "$_b" -le 244 ]; then
            _w=2; _islead=1
        fi
        if [ "$_islead" -eq 1 ]; then
            # 上一个字符已完整，先决定是否换行
            if [ $(( _cur + _charw )) -gt "$_max" ] && [ -n "$_line" ]; then
                printf '%s\n' "$_line"
                _line="$_char"; _cur="$_charw"
            else
                _line="${_line}${_char}"; _cur=$(( _cur + _charw ))
            fi
            _char=$(printf '%s' "$_text" | cut -b "$_i" 2>/dev/null)
            _charw="$_w"
        else
            _char="${_char}$(printf '%s' "$_text" | cut -b "$_i" 2>/dev/null)"
        fi
    done
    if [ $(( _cur + _charw )) -gt "$_max" ] && [ -n "$_line" ]; then
        printf '%s\n' "$_line"
        _line="$_char"; _cur="$_charw"
    else
        _line="${_line}${_char}"; _cur=$(( _cur + _charw ))
    fi
    [ -n "$_line" ] && printf '%s\n' "$_line"
}

# 渲染对话框并等待用户决策。
# 参数: <命令> <风险等级> <规则id> <原因> <目标>
# 返回: 0 = 允许执行; 1 = 拒绝执行
# 副作用: 设置 DSI_DECISION (allow/reject/allow_whitelist) 并写入日志。
dsi_dialog() {
    _cmd="$1"; _risk="$2"; _rule="$3"; _reason="$4"; _target="$5"
    DSI_DECISION="reject"

    # 非交互环境：安全默认拒绝
    if [ ! -t 1 ] || [ ! -t 0 ]; then
        if [ "$DSI_NONINTERACTIVE" = "allow" ]; then
            DSI_DECISION="allow"
            dsi_log "$_risk" "allow(auto-noninteractive)" "$_cmd" "非交互环境，按配置放行"
            return 0
        fi
        DSI_DECISION="reject"
        dsi_log "$_risk" "reject(auto-noninteractive)" "$_cmd" "非交互环境，安全默认拒绝"
        return 1
    fi

    # 颜色（tput 不可用时降级为无颜色）
    _bold=$(tput bold 2>/dev/null); _reset=$(tput sgr0 2>/dev/null)
    _red=$(tput setaf 1 2>/dev/null); _yellow=$(tput setaf 3 2>/dev/null)
    _cyan=$(tput setaf 6 2>/dev/null); _green=$(tput setaf 2 2>/dev/null)
    _dim=$(tput dim 2>/dev/null)
    case "$_risk" in
        critical|high) _sev="$_red[严重]$_reset"; _sevplain="严重" ;;
        medium)        _sev="$_yellow[较高]$_reset"; _sevplain="较高" ;;
        low)           _sev="$_cyan[较低]$_reset"; _sevplain="较低" ;;
        *)             _sev="$_green[提示]$_reset"; _sevplain="提示" ;;
    esac

    _rule_name=$(dsi_rule_label "$_rule")

    _sep="================================================================"
    _mid="----------------------------------------------------------------"
    printf '\n%s\n' "$_sep"
    printf '%s 危险命令拦截 - 安全确认 %s\n' "$_bold" "$_reset"
    printf '%s\n' "$_sep"
    printf '  命令 : %s\n' "$_cmd"
    printf '  风险 : %s   类型: %s\n' "$_sev" "$_rule_name"
    if [ -n "$_target" ]; then
        printf '  目标 : %s\n' "$_target"
    fi
    printf '%s\n' "$_mid"
    printf '  危险原因:\n'
    dsi_wrap "$_reason" 64 | while IFS= read -r _l; do
        printf '    %s\n' "$_l"
    done
    printf '%s\n' "$_mid"
    printf '  请选择操作:\n'
    printf '    %s[1]%s 拒绝执行   %s(推荐 / 直接回车)%s\n' "$_bold" "$_reset" "$_dim" "$_reset"
    printf '    %s[2]%s 允许执行\n' "$_bold" "$_reset"
    printf '    %s[3]%s 允许并加入白名单（后续不再询问）\n' "$_bold" "$_reset"
    printf '%s>%s ' "$_cyan" "$_reset"
    read -r _choice 2>/dev/null
    case "$_choice" in
        2)
            DSI_DECISION="allow"
            dsi_log "$_risk" "allow(user)" "$_cmd" "用户手动允许"
            return 0 ;;
        3)
            DSI_DECISION="allow_whitelist"
            dsi_allow_add "$_cmd"
            dsi_log "$_risk" "allow-whitelist(user)" "$_cmd" "用户允许并加入白名单"
            return 0 ;;
        *)
            DSI_DECISION="reject"
            dsi_log "$_risk" "reject(user)" "$_cmd" "用户拒绝执行"
            return 1 ;;
    esac
}

# 把规则 id 翻译成中文标签。
dsi_rule_label() {
    case "$1" in
        forkbomb)    echo "fork 炸弹" ;;
        dd)          echo "块设备写入" ;;
        mkfs)        echo "格式化/分区" ;;
        rm)          echo "递归删除" ;;
        chmod_chown) echo "权限/属主修改" ;;
        redirect)    echo "重定向覆盖" ;;
        mv)          echo "移动/重命名" ;;
        wipe)        echo "擦除/格式化" ;;
        flash)       echo "刷写/擦除分区" ;;
        selinux)     echo "SELinux 关闭" ;;
        mount_rw)    echo "系统分区改写挂载" ;;
        pm_uninstall) echo "系统应用卸载" ;;
        curl_pipe)   echo "网络脚本直执行" ;;
        kill)        echo "关键进程终止" ;;
        *)           echo "$1" ;;
    esac
}
