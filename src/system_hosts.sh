# shellcheck shell=bash
# Hostname and /etc/hosts management workflows.

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
