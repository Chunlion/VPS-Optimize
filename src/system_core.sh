# shellcheck shell=bash
# Base system initialization, firewall, hostname, hosts, and system toggles.

configure_system_timezone_for_init() {
    local current_tz choice custom_tz target_tz

    if ! command -v timedatectl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 timedatectl，已保持当前系统时区。${PLAIN}"
        return 0
    fi

    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    [[ -z "$current_tz" ]] && current_tz="未设置/未知"

    echo -e "${CYAN}当前系统时区：${current_tz}${PLAIN}"
    echo -e "${GREEN}  1. 保持当前时区${PLAIN} ${YELLOW}(默认)${PLAIN}"
    echo -e "${GREEN}  2. Asia/Shanghai${PLAIN}"
    echo -e "${GREEN}  3. Asia/Tokyo${PLAIN}"
    echo -e "${GREEN}  4. UTC${PLAIN}"
    echo -e "${GREEN}  5. 自定义时区${PLAIN}"
    read_trimmed choice "请选择基础初始化时区处理方式（默认 1）: "

    case "${choice:-1}" in
        1)
            echo -e "${BLUE}已保持当前时区：${current_tz}${PLAIN}"
            return 0
            ;;
        2) target_tz="Asia/Shanghai" ;;
        3) target_tz="Asia/Tokyo" ;;
        4) target_tz="UTC" ;;
        5)
            read_trimmed custom_tz "请输入 IANA 时区名称（例如 Europe/London）: "
            target_tz="$custom_tz"
            ;;
        *)
            echo -e "${YELLOW}⚠️ 未选择有效选项，已保持当前时区：${current_tz}${PLAIN}"
            return 0
            ;;
    esac

    if [[ -z "$target_tz" ]]; then
        echo -e "${YELLOW}⚠️ 自定义时区为空，已保持当前时区：${current_tz}${PLAIN}"
        return 0
    fi

    if timedatectl set-timezone "$target_tz" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 系统时区已设置为：${target_tz}${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 时区设置失败，已保持当前时区：${current_tz}${PLAIN}"
    fi
}

func_base_init() {
    clear
    echo -e "${CYAN}👉 正在更新系统软件包、安装基础工具、限制日志并开启基础 BBR...${PLAIN}"
    
    # 更新系统软件包并优雅调用全局安装函数
    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y && apt-get upgrade -y && APT_UPDATED=1
        unset DEBIAN_FRONTEND
        install_pkg curl wget git nano unzip htop iptables iproute2 sqlite3 jq
    elif is_redhat; then
        yum update -y
        install_pkg curl wget git nano unzip htop iptables iproute epel-release sqlite jq
    fi

    ensure_minimal_system_compat

    # 限制系统日志最大 100M
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    
    # 时区默认保持当前设置，必要时由用户选择
    configure_system_timezone_for_init
    
    # 强制激活基础 BBR
    modprobe tcp_bbr >/dev/null 2>&1 # 先主动唤醒/加载 BBR 内核模块
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础初始化完成，原生 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# ★ 防火墙专属管理面板 (安全追加模式 + 批量多端口支持)
# ---------------------------------------------------------
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
            "?"|help) echo "防火墙菜单用于放行、删除、查看或关闭系统防火墙规则。删除规则和关闭防火墙都必须输入 YES。"; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

update_hosts_hostname_entry() {
    local old_name="$1"
    local new_name="$2"
    local tmp_file

    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    awk -v old="$old_name" -v new="$new_name" '
        BEGIN { updated = 0 }
        $1 == "127.0.1.1" {
            print "127.0.1.1\t" new
            updated = 1
            next
        }
        {
            for (i = 2; i <= NF; i++) {
                if ($i == old) {
                    $i = new
                    updated = 1
                }
            }
            print
        }
        END {
            if (!updated) {
                print "127.0.1.1\t" new
            }
        }
    ' /etc/hosts > "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
    }
    cp "$tmp_file" /etc/hosts
    rm -f "$tmp_file"
}

func_change_hostname() {
    local current_name new_name ts
    current_name=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
    current_name="$(trim_input "$current_name")"
    current_name="${current_name:-localhost}"

    echo -e "当前主机名: ${CYAN}${current_name}${PLAIN}"
    echo -e "${YELLOW}主机名建议只使用字母、数字、连字符和点号；每段不能以连字符开头或结尾。${PLAIN}"
    read_trimmed new_name "请输入新的主机名（回车取消）: "
    [[ -z "$new_name" || "$new_name" == "0" ]] && { echo -e "${BLUE}已取消修改主机名。${PLAIN}"; return 0; }

    if ! is_valid_hostname "$new_name"; then
        echo -e "${RED}❌ 主机名格式无效。示例：vps01 或 node-1.example.com${PLAIN}"
        return 1
    fi

    if [[ "$new_name" == "$current_name" ]]; then
        echo -e "${BLUE}主机名未变化。${PLAIN}"
        return 0
    fi

    confirm_risk_action "修改主机名为 ${new_name}" \
        "/etc/hostname、/etc/hosts 和当前运行时 hostname" \
        "使用本功能改回 ${current_name}，或从 /etc/*.bak_时间戳 恢复" \
        "少数服务会在重启后才读取新主机名。" || return 1

    ts=$(date +%s)
    [[ -f /etc/hostname ]] && cp -p /etc/hostname "/etc/hostname.bak_${ts}" 2>/dev/null || true
    [[ -f /etc/hosts ]] && cp -p /etc/hosts "/etc/hosts.bak_${ts}" 2>/dev/null || true

    echo "$new_name" > /etc/hostname || {
        echo -e "${RED}❌ 写入 /etc/hostname 失败。${PLAIN}"
        return 1
    }

    if [[ -f /etc/hosts ]]; then
        update_hosts_hostname_entry "$current_name" "$new_name" || echo -e "${YELLOW}⚠️ /etc/hosts 更新失败，请稍后手动检查。${PLAIN}"
    else
        {
            echo "127.0.0.1	localhost"
            echo "127.0.1.1	$new_name"
        } > /etc/hosts
    fi

    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$new_name" >/dev/null 2>&1 || hostname "$new_name" 2>/dev/null || true
    else
        hostname "$new_name" 2>/dev/null || true
    fi

    echo -e "${GREEN}✅ 主机名已修改为：${new_name}${PLAIN}"
    echo -e "${YELLOW}如部分服务仍显示旧名称，重启对应服务或下次重启系统后会完全生效。${PLAIN}"
}

hosts_managed_marker() {
    printf '%s' '# VPS-Optimize local-hosts'
}

hosts_is_valid_ip() {
    local ip="$1"
    [[ "$ip" != */* ]] || return 1
    dns_is_valid_ipv4 "$ip" || dns_is_valid_ipv6 "$ip"
}

hosts_normalize_names() {
    local raw="$1"
    local -n out_array=$2
    local item normalized seen=" "
    raw="${raw//，/,}"
    raw="${raw//;/,}"
    raw="${raw//,/ }"
    out_array=()
    for item in $raw; do
        normalized=$(echo "$(trim_input "$item")" | tr '[:upper:]' '[:lower:]')
        [[ -z "$normalized" ]] && continue
        if ! is_valid_hostname "$normalized"; then
            echo -e "${RED}❌ 主机名/域名格式无效：${normalized}${PLAIN}"
            return 1
        fi
        case "$normalized" in
            localhost|localhost.localdomain|ip6-localhost|ip6-loopback)
                echo -e "${RED}❌ 为避免破坏系统解析，不能管理保留名称：${normalized}${PLAIN}"
                return 1
                ;;
        esac
        if [[ "$seen" != *" ${normalized} "* ]]; then
            out_array+=("$normalized")
            seen+=" ${normalized} "
        fi
    done
    [[ ${#out_array[@]} -gt 0 ]]
}

hosts_backup_current() {
    local backup_dir="/etc/vps-optimize/backups/hosts"
    local backup_file
    mkdir -p "$backup_dir" || return 1
    backup_file="${backup_dir}/hosts.$(date +%Y%m%d_%H%M%S).bak"
    if [[ -f /etc/hosts ]]; then
        cp -p /etc/hosts "$backup_file" || return 1
    else
        : > "$backup_file" || return 1
    fi
    printf '%s' "$backup_file"
}

hosts_remove_names_to_tmp() {
    local names_csv="$1"
    local tmp_file="$2"
    local hosts_file="/etc/hosts"
    [[ -f "$hosts_file" ]] || : > "$hosts_file"
    awk -v names_csv="$names_csv" '
        BEGIN {
            split(names_csv, names, ",")
            for (i in names) target[names[i]] = 1
        }
        /^[[:space:]]*#/ || NF == 0 { print; next }
        {
            keep = 0
            line = $1
            for (i = 2; i <= NF; i++) {
                if ($i == "#") break
                if (!($i in target)) {
                    line = line "\t" $i
                    keep = 1
                }
            }
            if (keep) print line
        }
    ' "$hosts_file" > "$tmp_file"
}

hosts_add_or_update_entry() {
    local ip names_input names_csv names_joined backup_file tmp_file
    local -a names=()
    read_trimmed ip "请输入解析 IP（IPv4/IPv6）: "
    if ! hosts_is_valid_ip "$ip"; then
        echo -e "${RED}❌ IP 格式无效。${PLAIN}"
        return 1
    fi
    read_trimmed names_input "请输入要绑定的域名/主机名（多个用空格或逗号分隔）: "
    if ! hosts_normalize_names "$names_input" names; then
        return 1
    fi
    names_csv=$(IFS=','; printf '%s' "${names[*]}")
    names_joined=$(IFS=' '; printf '%s' "${names[*]}")
    confirm_risk_action "写入本机 hosts 解析" \
        "/etc/hosts 本机解析表" \
        "从 /etc/vps-optimize/backups/hosts 恢复最近备份，或在本菜单删除对应条目" \
        "本功能只影响当前 VPS 本机解析，不会修改公网 DNS。" || return 1

    backup_file=$(hosts_backup_current) || {
        echo -e "${RED}❌ /etc/hosts 备份失败，已取消。${PLAIN}"
        return 1
    }
    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    if hosts_remove_names_to_tmp "$names_csv" "$tmp_file"; then
        printf '%s\t%s\t%s\n' "$ip" "$names_joined" "$(hosts_managed_marker)" >> "$tmp_file"
        cp "$tmp_file" /etc/hosts
        echo -e "${GREEN}✅ 已写入本机 hosts：${ip} -> ${names_joined}${PLAIN}"
        echo -e "${CYAN}备份已保留：${backup_file}${PLAIN}"
    else
        echo -e "${RED}❌ 生成 hosts 临时文件失败，已取消。${PLAIN}"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"
}

hosts_remove_entry() {
    local names_input names_csv names_joined backup_file tmp_file
    local -a names=()
    read_trimmed names_input "请输入要删除解析的域名/主机名（多个用空格或逗号分隔）: "
    if ! hosts_normalize_names "$names_input" names; then
        return 1
    fi
    names_csv=$(IFS=','; printf '%s' "${names[*]}")
    names_joined=$(IFS=' '; printf '%s' "${names[*]}")
    confirm_risk_action "删除本机 hosts 解析" \
        "/etc/hosts 中与 ${names_joined} 匹配的解析项" \
        "从 /etc/vps-optimize/backups/hosts 恢复最近备份" \
        "只删除匹配主机名，保留同一行其他别名。" || return 1

    backup_file=$(hosts_backup_current) || {
        echo -e "${RED}❌ /etc/hosts 备份失败，已取消。${PLAIN}"
        return 1
    }
    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    if hosts_remove_names_to_tmp "$names_csv" "$tmp_file"; then
        cp "$tmp_file" /etc/hosts
        echo -e "${GREEN}✅ 已删除匹配的本机 hosts 解析：${names_joined}${PLAIN}"
        echo -e "${CYAN}备份已保留：${backup_file}${PLAIN}"
    else
        echo -e "${RED}❌ 生成 hosts 临时文件失败，已取消。${PLAIN}"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"
}

hosts_restore_latest_backup() {
    local latest
    latest=$(find /etc/vps-optimize/backups/hosts -maxdepth 1 -type f -name 'hosts.*.bak' 2>/dev/null | sort -r | head -n1)
    if [[ -z "$latest" ]]; then
        echo -e "${YELLOW}未找到 hosts 备份。${PLAIN}"
        return 1
    fi
    confirm_risk_action "恢复最近 hosts 备份" \
        "/etc/hosts 将恢复为 ${latest}" \
        "重新进入本菜单添加/删除解析，或手动恢复更新前备份" \
        "恢复会覆盖当前本机 hosts 解析。" || return 1
    cp -p "$latest" /etc/hosts || {
        echo -e "${RED}❌ 恢复失败。${PLAIN}"
        return 1
    }
    echo -e "${GREEN}✅ 已恢复：${latest}${PLAIN}"
}

func_hosts_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "系统开关与清理 > 本机 hosts 解析"
        echo -e "${BOLD}🧭 本机 hosts 解析管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：修改当前 VPS 的 /etc/hosts，本地指定域名解析到某个 IP。不会影响公网 DNS。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前 hosts${PLAIN}"
        echo -e "${GREEN}  2. 添加 / 更新本机解析${PLAIN}"
        echo -e "${YELLOW}  3. 删除本机解析${PLAIN}"
        echo -e "${CYAN}  4. 恢复最近一次 hosts 备份${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                echo -e "${CYAN}--- /etc/hosts ---${PLAIN}"
                sed -n '1,120p' /etc/hosts 2>/dev/null || echo "未检测到 /etc/hosts"
                pause_return
                ;;
            2) hosts_add_or_update_entry; pause_return ;;
            3) hosts_remove_entry; pause_return ;;
            4) hosts_restore_latest_backup; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 2. 系统高级开关 (已修复显示丢失问题)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️ 系统开关与清理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        # 状态获取
        local ipv6_status
        local str_ipv6
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="${GREEN}开启中${PLAIN}"; else str_ipv6="${RED}已禁用${PLAIN}"; fi
        
        local str_ipv4_first
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then 
            str_ipv4_first="${GREEN}已优先${PLAIN}"
        else 
            str_ipv4_first="${RED}默认(IPv6优先)${PLAIN}"
        fi
        
        local ping_status
        local str_ping
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="${GREEN}允许被Ping${PLAIN}"; else str_ping="${RED}禁Ping中${PLAIN}"; fi
        
        local update_status
        local str_update
        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
        fi
        if [[ "$update_status" == "active" ]]; then str_update="${GREEN}开启中${PLAIN}"; else str_update="${RED}已关闭${PLAIN}"; fi

        local current_hostname
        current_hostname=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
        current_hostname="$(trim_input "$current_hostname")"
        current_hostname="${current_hostname:-未知}"

        # 完美修复：一字不落的菜单显示
        echo -e "${GREEN}  1. IPv6 开关${PLAIN}              当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. IPv4 出站优先${PLAIN}          当前: [ $str_ipv4_first ]"
        echo -e "${GREEN}  3. Ping 响应开关${PLAIN}          当前: [ $str_ping ]"
        echo -e "${GREEN}  4. 自动安全更新开关${PLAIN}       当前: [ $str_update ]"
        echo -e "${GREEN}  5. 清理系统垃圾${PLAIN}           (日志/缓存/无用包)"
        echo -e "${GREEN}  6. 修改主机名${PLAIN}             当前: [ ${CYAN}${current_hostname}${PLAIN} ]"
        echo -e "${GREEN}  7. 本机 hosts 解析管理${PLAIN}    (/etc/hosts 本机域名解析)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local tweak_choice
        read_trimmed tweak_choice "👉 请选择操作: "
        
        case $tweak_choice in
            1)
                read_trimmed yn "❓ 开启 IPv6？(y 开启 / n 关闭): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    quarantine_path /etc/sysctl.d/99-disable-ipv6.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/sysctl.d/99-disable-ipv6.conf ]] && cp -p /etc/sysctl.d/99-disable-ipv6.conf "/etc/sysctl.d/99-disable-ipv6.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1
                    echo -e "${RED}✅ IPv6 已禁用${PLAIN}"
                fi; sleep 1 ;;
            2)
                read_trimmed yn "❓ 设置 IPv4 为最高出站优先级？(y 开启 / n 恢复默认): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf
                    echo -e "${GREEN}✅ 已设为 IPv4 优先${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
                    echo -e "${BLUE}已恢复系统默认${PLAIN}"
                fi; sleep 1 ;;
            3)
                read_trimmed yn "❓ 允许被 Ping？(y 允许 / n 禁止): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    quarantine_path /etc/sysctl.d/99-disable-ping.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ 已允许被 Ping${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/sysctl.d/99-disable-ping.conf ]] && cp -p /etc/sysctl.d/99-disable-ping.conf "/etc/sysctl.d/99-disable-ping.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1
                    echo -e "${RED}✅ 已开启禁 Ping 保护${PLAIN}"
                fi; sleep 1 ;;
            4)
                read_trimmed yn "❓ 开启系统自动更新？(y 开启 / n 关闭): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg unattended-upgrades || { echo -e "${RED}❌ unattended-upgrades 安装失败。${PLAIN}"; sleep 1; continue; }
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ unattended-upgrades 服务启用失败，请手动检查。${PLAIN}"
                    else
                        install_pkg dnf-automatic || { echo -e "${RED}❌ dnf-automatic 安装失败。${PLAIN}"; sleep 1; continue; }
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ dnf-automatic.timer 启用失败，请手动检查。${PLAIN}"
                    fi
                    echo -e "${GREEN}✅ 自动更新已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null 2>&1
                    else systemctl disable --now dnf-automatic.timer >/dev/null 2>&1; fi
                    echo -e "${GREEN}✅ 自动更新已关闭${PLAIN}"
                fi; sleep 1 ;;
            5) 
                echo -e "${CYAN}👉 正在深度清理系统垃圾...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then 
                    apt autoremove --purge -y >/dev/null 2>&1
                    apt clean >/dev/null 2>&1
                else 
                    yum autoremove -y >/dev/null 2>&1
                    yum clean all >/dev/null 2>&1
                fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                echo -e "${GREEN}✅ 清理完成！${PLAIN}"
                sleep 1 ;;
            6) func_change_hostname; sleep 1 ;;
            7) func_hosts_manage ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 统一包管理与执行守卫 (新增：请放在 func_env_install 函数上方)
# ---------------------------------------------------------
