# shellcheck shell=bash
# Firewall rule management workflows.

port_connlimit_comment() {
    local port="$1"
    printf 'VPSO_CONN_LIMIT_PORT_%s' "$port"
}

is_valid_connlimit_value() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value > 0 ))
}

ensure_connlimit_tool() {
    local cmd="$1"
    local family_label="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${YELLOW}⚠️ 未检测到 ${cmd}，正在尝试安装 iptables 兼容工具...${PLAIN}"
    install_pkg iptables || true

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${RED}❌ 未检测到 ${cmd}，无法写入 ${family_label} connlimit 规则。${PLAIN}"
    echo -e "${YELLOW}请先安装 iptables/ip6tables 兼容工具，再重新进入本菜单。${PLAIN}"
    return 1
}

try_load_connlimit_module() {
    if command -v modprobe >/dev/null 2>&1; then
        modprobe xt_connlimit >/dev/null 2>&1 || true
    fi
}

port_connlimit_loopback_only_listener() {
    local port="$1"
    command -v ss >/dev/null 2>&1 || return 1

    ss -Htlpn 2>/dev/null | awk -v port="$port" '
        function is_target(addr) {
            return addr ~ (":" port "$") || addr ~ ("\\]:" port "$")
        }
        is_target($4) {
            if ($4 ~ /^(127\.0\.0\.1|localhost):/ || $4 ~ /^\[::1\]:/) {
                loopback = 1
            } else {
                public = 1
            }
        }
        END {
            exit (loopback && !public ? 0 : 1)
        }
    '
}

print_port_connlimit_scope_notice() {
    local port="$1"

    echo -e "${YELLOW}说明：本功能写入的是额外 iptables/ip6tables connlimit 规则，不等同于 UFW/firewalld 的端口放行规则。${PLAIN}"
    echo -e "${YELLOW}默认按“每个来源 IP”限制 TCP 并发连接数，不做全局总连接数限制。${PLAIN}"
    echo -e "${YELLOW}规则是否重启后保留取决于系统已有 iptables 持久化机制；本功能不额外改写 UFW/firewalld 放行配置。${PLAIN}"

    if [[ "$port" == "443" ]]; then
        echo -e "${RED}⚠️ 443 强提醒：如果当前启用了 443 单入口/端口复用，本限制会作用于整个公网 443。${PLAIN}"
        echo -e "${RED}它不能精准限制某一个 Xray/3x-ui 入站、某一个 SNI、某一个 UUID 或某一个用户。${PLAIN}"
    fi

    if port_connlimit_loopback_only_listener "$port"; then
        echo -e "${YELLOW}⚠️ 检测到该端口可能只监听 127.0.0.1/::1。本功能建议限制公网监听端口。${PLAIN}"
        echo -e "${YELLOW}如果限制本地后端端口，可能只能限制本机代理到后端的连接，不能代表真实公网来源。${PLAIN}"
    fi
}

port_connlimit_has_rule_for_port() {
    local cmd="$1"
    local port="$2"
    local comment
    comment=$(port_connlimit_comment "$port")

    "$cmd" -S INPUT 2>/dev/null | grep -Fq "$comment"
}

run_port_connlimit_rule_action() {
    local cmd="$1"
    local action="$2"
    local port="$3"
    local limit="$4"
    local mask="$5"
    local family_label="$6"
    local comment output
    comment=$(port_connlimit_comment "$port")

    local args=(
        -p tcp --dport "$port" --syn
        -m connlimit --connlimit-above "$limit" --connlimit-mask "$mask" --connlimit-saddr
        -m comment --comment "$comment"
        -j REJECT --reject-with tcp-reset
    )

    case "$action" in
        add)
            if "$cmd" -C INPUT "${args[@]}" >/dev/null 2>&1; then
                echo -e "${BLUE}ℹ️ ${family_label} 已存在相同规则：端口 ${port}，每来源 IP 超过 ${limit} 条新连接将被拒绝。${PLAIN}"
                return 0
            fi
            if port_connlimit_has_rule_for_port "$cmd" "$port"; then
                echo -e "${YELLOW}⚠️ ${family_label} 已存在同端口脚本规则。继续添加会叠加限制；如需替换，建议先按端口和连接数删除旧规则。${PLAIN}"
            fi
            if output=$("$cmd" -I INPUT "${args[@]}" 2>&1); then
                echo -e "${GREEN}✅ ${family_label} 已添加：端口 ${port}，每来源 IP 最大并发 ${limit}。${PLAIN}"
                return 0
            fi
            echo -e "${RED}❌ ${family_label} 添加失败：${output}${PLAIN}"
            return 1
            ;;
        delete)
            if ! "$cmd" -C INPUT "${args[@]}" >/dev/null 2>&1; then
                echo -e "${YELLOW}⚠️ ${family_label} 未找到匹配规则：端口 ${port}，连接数 ${limit}。${PLAIN}"
                return 1
            fi
            if output=$("$cmd" -D INPUT "${args[@]}" 2>&1); then
                echo -e "${GREEN}✅ ${family_label} 已删除：端口 ${port}，连接数 ${limit}。${PLAIN}"
                return 0
            fi
            echo -e "${RED}❌ ${family_label} 删除失败：${output}${PLAIN}"
            return 1
            ;;
        *)
            echo -e "${RED}❌ 未知 connlimit 操作：${action}${PLAIN}"
            return 1
            ;;
    esac
}

read_connlimit_port() {
    local __target="$1"
    local port

    read_trimmed port "请输入要限制的端口号（1-65535，回车或 0 取消）: "
    if [[ -z "$port" || "$port" == "0" ]]; then
        echo -e "${BLUE}已取消端口并发连接限制操作。${PLAIN}"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "${RED}❌ 端口无效，必须是 1-65535。${PLAIN}"
        return 1
    fi

    printf -v "$__target" '%s' "$((10#$port))"
}

read_connlimit_limit() {
    local __target="$1"
    local limit

    read_trimmed limit "请输入每个来源 IP 最大 TCP 并发连接数（正整数，回车或 0 取消）: "
    if [[ -z "$limit" || "$limit" == "0" ]]; then
        echo -e "${BLUE}已取消端口并发连接限制操作。${PLAIN}"
        return 1
    fi
    if ! is_valid_connlimit_value "$limit"; then
        echo -e "${RED}❌ 连接数无效，必须是正整数。${PLAIN}"
        return 1
    fi

    printf -v "$__target" '%s' "$((10#$limit))"
}

func_add_port_connlimit_rule() {
    local port limit apply_ipv6 rc=0

    read_connlimit_port port || return 0
    read_connlimit_limit limit || return 0
    read_trimmed apply_ipv6 "是否同时应用 IPv6？(y/n，默认 n): "

    print_port_connlimit_scope_notice "$port"
    echo -e "${CYAN}即将添加规则标记：$(port_connlimit_comment "$port")${PLAIN}"

    ensure_connlimit_tool iptables "IPv4" || return 1
    if is_yes "$apply_ipv6"; then
        ensure_connlimit_tool ip6tables "IPv6" || return 1
    fi
    try_load_connlimit_module

    confirm_risk_action "添加端口 ${port} 并发连接限制" \
        "iptables/ip6tables INPUT 链 connlimit 规则，超过 ${limit} 条并发的新 TCP 连接将被拒绝" \
        "回到本菜单按同一端口和连接数删除规则；必要时通过云控制台/VNC 清理 iptables 规则" \
        "该规则是额外连接数限制，不代表端口已被 UFW/firewalld 放行。" || {
        echo -e "${BLUE}已取消添加端口并发连接限制。${PLAIN}"
        return 0
    }

    run_port_connlimit_rule_action iptables add "$port" "$limit" 32 "IPv4" || rc=1
    if is_yes "$apply_ipv6"; then
        run_port_connlimit_rule_action ip6tables add "$port" "$limit" 128 "IPv6" || rc=1
    fi
    return "$rc"
}

func_delete_port_connlimit_rule() {
    local port limit delete_ipv6 rc=0

    read_connlimit_port port || return 0
    read_connlimit_limit limit || return 0
    read_trimmed delete_ipv6 "是否同时删除 IPv6 对应规则？(Y/n，默认 yes): "

    print_port_connlimit_scope_notice "$port"
    echo -e "${CYAN}将按端口和连接数精确删除规则标记：$(port_connlimit_comment "$port")${PLAIN}"

    ensure_connlimit_tool iptables "IPv4" || return 1
    if ! is_no "$delete_ipv6"; then
        ensure_connlimit_tool ip6tables "IPv6" || return 1
    fi

    confirm_risk_action "删除端口 ${port} 并发连接限制" \
        "仅删除端口 ${port}、连接数 ${limit}、脚本标记为 $(port_connlimit_comment "$port") 的 connlimit 规则" \
        "如误删，可回到本菜单重新添加同端口同连接数限制" \
        "本操作不会清空 UFW/firewalld，也不会批量清空 iptables。" || {
        echo -e "${BLUE}已取消删除端口并发连接限制。${PLAIN}"
        return 0
    }

    run_port_connlimit_rule_action iptables delete "$port" "$limit" 32 "IPv4" || rc=1
    if ! is_no "$delete_ipv6"; then
        run_port_connlimit_rule_action ip6tables delete "$port" "$limit" 128 "IPv6" || rc=1
    fi
    return "$rc"
}

func_show_port_connlimit_rules() {
    local found=0

    echo -e "${CYAN}当前由 VPS-Optimize 添加的端口并发连接限制规则：${PLAIN}"
    echo -e "${YELLOW}标记格式：VPSO_CONN_LIMIT_PORT_<端口>${PLAIN}"
    echo ""

    if command -v iptables >/dev/null 2>&1; then
        echo -e "${BOLD}IPv4:${PLAIN}"
        if iptables -S INPUT 2>/dev/null | grep -F 'VPSO_CONN_LIMIT_PORT_'; then
            found=1
        else
            echo "  未发现 IPv4 脚本规则。"
        fi
    else
        echo -e "${YELLOW}IPv4: 未检测到 iptables。${PLAIN}"
    fi

    echo ""
    if command -v ip6tables >/dev/null 2>&1; then
        echo -e "${BOLD}IPv6:${PLAIN}"
        if ip6tables -S INPUT 2>/dev/null | grep -F 'VPSO_CONN_LIMIT_PORT_'; then
            found=1
        else
            echo "  未发现 IPv6 脚本规则。"
        fi
    else
        echo -e "${YELLOW}IPv6: 未检测到 ip6tables。${PLAIN}"
    fi

    echo ""
    if [[ "$found" -eq 0 ]]; then
        echo -e "${BLUE}当前没有检测到本脚本添加的 connlimit 规则。${PLAIN}"
    fi
    echo -e "${YELLOW}提示：这些规则是连接数限制，不等同于 UFW/firewalld 的端口放行规则。${PLAIN}"
}

func_show_port_current_connections() {
    local port rows

    read_connlimit_port port || return 0

    if ! command -v ss >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 ss，正在尝试安装 iproute2/iproute...${PLAIN}"
        install_pkg iproute2 || install_pkg iproute || true
    fi
    if ! command -v ss >/dev/null 2>&1; then
        echo -e "${RED}❌ 未检测到 ss，无法查看当前连接情况。${PLAIN}"
        return 1
    fi

    print_port_connlimit_scope_notice "$port"
    echo -e "${CYAN}端口 ${port} 当前 ESTABLISHED TCP 连接按来源 IP 统计：${PLAIN}"
    rows=$(ss -Htan state established 2>/dev/null | awk -v port="$port" '
        function is_local_port(endpoint) {
            return endpoint ~ (":" port "$") || endpoint ~ ("\\]:" port "$")
        }
        function remote_ip(endpoint) {
            if (endpoint ~ /^\[/) {
                sub(/^\[/, "", endpoint)
                sub(/\]:[0-9]+$/, "", endpoint)
                return endpoint
            }
            sub(/:[0-9]+$/, "", endpoint)
            return endpoint
        }
        is_local_port($4) {
            print remote_ip($5)
        }
    ' | sort | uniq -c | sort -nr)

    if [[ -z "$rows" ]]; then
        echo "  当前没有 ESTABLISHED 连接。"
    else
        printf '%s\n' "$rows" | awk '{count=$1; $1=""; sub(/^ /, ""); printf "  %-45s %s\n", $0, count}'
    fi
}

show_firewall_menu_help() {
    echo "防火墙菜单用于放行、删除、查看或关闭系统防火墙规则。删除规则和关闭防火墙都必须输入 yes 确认，大小写均可。"
    echo "端口并发连接限制用于按公网端口限制每来源 IP 的 TCP 并发连接数，IPv4 使用 iptables connlimit，IPv6 使用 ip6tables connlimit。"
    echo "该限制是额外连接数限制规则，不等同于 UFW/firewalld 的端口放行规则；两者可能并存。"
    echo "规则是否重启后保留取决于系统已有 iptables 持久化机制，本功能不额外改写 UFW/firewalld 放行配置。"
    echo "如果限制公网 443 且当前启用了 443 单入口/端口复用，限制粒度只能是整个公网 443，不能精准到某个入站、SNI、UUID 或用户。"
}

func_port_connlimit_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "防火墙规则管理 > 端口并发连接限制"
        echo -e "${BOLD}端口并发连接限制${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：按公网端口限制每来源 IP 的 TCP 并发连接数。${PLAIN}"
        echo -e "${YELLOW}说明：这是额外 connlimit 规则，不等同于 UFW/firewalld 放行规则。${PLAIN}"
        echo -e "${YELLOW}持久化：是否重启后保留取决于系统已有 iptables 持久化机制。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 添加端口并发连接限制${PLAIN}"
        echo -e "${GREEN}  2. 删除端口并发连接限制${PLAIN}"
        echo -e "${GREEN}  3. 查看当前连接数限制规则${PLAIN}"
        echo -e "${GREEN}  4. 查看某端口当前连接情况${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local connlimit_choice
        read_trimmed connlimit_choice "👉 请选择操作: "
        case "$connlimit_choice" in
            1) func_add_port_connlimit_rule; pause_return ;;
            2) func_delete_port_connlimit_rule; pause_return ;;
            3) func_show_port_connlimit_rules; pause_return ;;
            4) func_show_port_current_connections; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_firewall_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "防火墙规则管理"
        echo -e "${BOLD}🛡️ 防火墙规则管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local fw_status
        local str_fw
        if [[ "$OS" =~ debian|ubuntu ]]; then
            fw_status=$(ufw status 2>/dev/null | grep -wi active)
        else
            fw_status=$(systemctl is-active firewalld 2>/dev/null)
        fi

        if [[ "$fw_status" == *"active"* ]]; then
            str_fw="${GREEN}运行中${PLAIN}"
        else
            str_fw="${RED}已关闭 / 未配置${PLAIN}"
        fi

        echo -e "当前防火墙状态: [ $str_fw ]"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 启用防火墙 + 自动放行当前公网端口${PLAIN} ${YELLOW}(不覆盖原有规则)${PLAIN}"
        echo -e "${GREEN}  2. 手动放行端口${PLAIN} ${YELLOW}(支持 80,443 或 8000-9000)${PLAIN}"
        echo -e "${GREEN}  3. 删除已放行端口${PLAIN} ${YELLOW}(支持批量/范围)${PLAIN}"
        echo -e "${GREEN}  4. 查看防火墙放行列表${PLAIN}"
        echo -e "${RED}  5. 关闭防火墙${PLAIN}"
        echo -e "${GREEN}  6. 端口并发连接限制${PLAIN} ${YELLOW}(按每来源 IP 限制 TCP 并发)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${BLUE}  0. 返回上一级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local fw_choice
        read_trimmed fw_choice "👉 请选择操作: "

        case $fw_choice in
            1)
                echo -e "${CYAN}👉 正在嗅探活动端口并配置防火墙...${PLAIN}"
                local active_ports
                active_ports=$(ss -tuln 2>/dev/null | grep -E 'LISTEN|UNCONN' | awk '{print $5}' | grep -Ev '^(127\.0\.0\.1:|\[?::1\]?:)' | rev | cut -d: -f1 | rev | sort -nu | grep -E '^[0-9]+$' || true)

                local ssh_port
                ssh_port=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
                [[ -z "$ssh_port" ]] && ssh_port=$(grep -i '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
                ssh_port=${ssh_port:-22}
                if is_valid_port "$ssh_port" && ! printf '%s\n' "$active_ports" | grep -qx "$ssh_port"; then
                    active_ports=$(printf '%s\n%s\n' "$active_ports" "$ssh_port" | grep -E '^[0-9]+$' | sort -nu)
                fi

                if [[ -z "$active_ports" ]]; then
                    echo -e "${RED}❌ 未能识别到需要放行的监听端口，已取消启用防火墙，避免误锁 SSH。${PLAIN}"
                    echo -e "${YELLOW}请先确认 ss/iproute2 可用，或使用 [2] 手动添加 SSH 端口后再启用。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if [[ "$OS" =~ debian|ubuntu ]]; then
                    install_pkg ufw
                    ufw default deny incoming >/dev/null 2>&1
                    ufw default allow outgoing >/dev/null 2>&1

                    for p in $active_ports; do ufw allow "$p" >/dev/null 2>&1; done
                    ufw --force enable >/dev/null 2>&1
                else
                    install_pkg firewalld
                    systemctl enable --now firewalld >/dev/null 2>&1

                    for p in $active_ports; do
                        firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1
                        firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1
                    done
                    firewall-cmd --reload >/dev/null 2>&1
                fi
                echo -e "${GREEN}✅ 防火墙已成功配置！已为您安全追加放行了以下端口: $(echo "$active_ports" | tr '\n' ' ')${PLAIN}"
                sleep 2
                ;;
            2)
                local add_p
                echo -e "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}"
                read_trimmed add_p "👉 请输入要放行的端口号: "
                add_p=$(normalize_port_rule_input "$add_p")
                if [[ -z "$add_p" || "$add_p" == "0" ]]; then
                    echo -e "${BLUE}已取消添加端口规则。${PLAIN}"
                    sleep 1
                    continue
                fi

                # 放宽正则，允许数字、逗号、冒号和减号
                if is_valid_port_rule_input "$add_p"; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg ufw
                        if ! command -v ufw >/dev/null 2>&1; then
                            echo -e "${RED}❌ 未检测到 ufw，无法写入规则。${PLAIN}"
                            sleep 2
                            continue
                        fi
                        if ! ufw status 2>/dev/null | grep -qi active; then
                            echo -e "${YELLOW}⚠️ UFW 当前未启用，本次只写入规则；需要启用时请回到 [1] 自动放行活动端口。${PLAIN}"
                        fi
                    elif ! systemctl is-active --quiet firewalld 2>/dev/null; then
                        echo -e "${RED}❌ Firewalld 未运行。为避免误关端口，请先使用 [1] 启用并自动放行当前活动端口。${PLAIN}"
                        sleep 2
                        continue
                    fi
                    # 将输入的逗号分隔符转换为数组，按个循环处理
                    IFS=',' read -ra PORT_ARRAY <<< "$add_p"
                    for p in "${PORT_ARRAY[@]}"; do
                        if [[ "$OS" =~ debian|ubuntu ]]; then
                            # UFW 语法转换：将减号强转为冒号
                            local p_ufw="${p//-/:}"
                            if [[ "$p_ufw" == *":"* ]]; then
                                ufw allow "$p_ufw/tcp" >/dev/null 2>&1
                                ufw allow "$p_ufw/udp" >/dev/null 2>&1
                            else
                                ufw allow "$p_ufw" >/dev/null 2>&1
                            fi
                        else
                            # Firewalld 语法转换：将冒号强转为减号
                            local p_fwd="${p//:/-}"
                            firewall-cmd --permanent --add-port="${p_fwd}/tcp" >/dev/null 2>&1
                            firewall-cmd --permanent --add-port="${p_fwd}/udp" >/dev/null 2>&1
                        fi
                    done

                    if [[ ! "$OS" =~ debian|ubuntu ]]; then
                        firewall-cmd --reload >/dev/null 2>&1
                    fi

                    echo -e "${GREEN}✅ 端口规则 [$add_p] 已成功添加至允许列表！${PLAIN}"
                else
                    echo -e "${RED}❌ 无效的端口格式！端口必须是 1-65535，范围起始值不能大于结束值。${PLAIN}"
                fi
                sleep 2
                ;;
            3)
                local del_p
                echo -e "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}"
                read_trimmed del_p "👉 请输入要删除放行的端口号: "
                del_p=$(normalize_port_rule_input "$del_p")
                if [[ -z "$del_p" || "$del_p" == "0" ]]; then
                    echo -e "${BLUE}已取消删除端口规则。${PLAIN}"
                    sleep 1
                    continue
                fi

                if is_valid_port_rule_input "$del_p"; then
                    confirm_risk_action "删除防火墙放行规则 ${del_p}" \
                        "系统防火墙端口放行规则" \
                        "重新进入防火墙菜单手动放行端口，或通过云厂商控制台/VNC 修复" \
                        "确认不会删除当前 SSH 端口或业务必需端口。" || {
                        echo -e "${BLUE}已取消删除端口规则。${PLAIN}"
                        sleep 1
                        continue
                    }
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg ufw
                        if ! command -v ufw >/dev/null 2>&1; then
                            echo -e "${RED}❌ 未检测到 ufw，无法删除规则。${PLAIN}"
                            sleep 2
                            continue
                        fi
                    elif ! systemctl is-active --quiet firewalld 2>/dev/null; then
                        echo -e "${RED}❌ Firewalld 未运行，无法读取/删除运行时规则。${PLAIN}"
                        sleep 2
                        continue
                    fi
                    IFS=',' read -ra PORT_ARRAY <<< "$del_p"
                    for p in "${PORT_ARRAY[@]}"; do
                        if [[ "$OS" =~ debian|ubuntu ]]; then
                            # UFW 语法转换：将减号强转为冒号
                            local p_ufw="${p//-/:}"
                            if [[ "$p_ufw" == *":"* ]]; then
                                ufw delete allow "$p_ufw/tcp" >/dev/null 2>&1
                                ufw delete allow "$p_ufw/udp" >/dev/null 2>&1
                            else
                                ufw delete allow "$p_ufw" >/dev/null 2>&1
                            fi
                        else
                            # Firewalld 语法转换：将冒号强转为减号
                            local p_fwd="${p//:/-}"
                            firewall-cmd --permanent --remove-port="${p_fwd}/tcp" >/dev/null 2>&1
                            firewall-cmd --permanent --remove-port="${p_fwd}/udp" >/dev/null 2>&1
                        fi
                    done

                    if [[ ! "$OS" =~ debian|ubuntu ]]; then
                        firewall-cmd --reload >/dev/null 2>&1
                    fi

                    echo -e "${GREEN}✅ 端口规则 [$del_p] 已成功从允许列表中移除！${PLAIN}"
                else
                    echo -e "${RED}❌ 无效的端口格式！端口必须是 1-65535，范围起始值不能大于结束值。${PLAIN}"
                fi
                sleep 2
                ;;
            4)
                echo -e "${CYAN}👇 当前防火墙规则列表：${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    ufw status numbered
                else
                    firewall-cmd --list-ports
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            5)
                confirm_risk_action "关闭系统防火墙" \
                    "ufw/firewalld 服务状态和系统侧访问控制" \
                    "重新启用防火墙并恢复放行规则；必要时从云厂商安全组限制暴露面" \
                    "确认关闭后不会暴露数据库、面板或内部服务。" || {
                    echo -e "${BLUE}已取消关闭防火墙。${PLAIN}"
                    sleep 1
                    continue
                }
                echo -e "${RED}⚠️ 正在关闭防火墙...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    ufw disable >/dev/null 2>&1
                else
                    systemctl disable --now firewalld >/dev/null 2>&1
                fi
                echo -e "${GREEN}✅ 防火墙已彻底禁用！${PLAIN}"
                sleep 2
                ;;
            6) func_port_connlimit_menu ;;
            "?"|help) show_firewall_menu_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}
