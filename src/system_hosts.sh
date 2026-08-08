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

    echo -e "$(localized_text "当前主机名: ${CYAN}${current_name}${PLAIN}" "Current host name: ${CYAN}${current_name}${PLAIN}" "Текущее имя хоста: ${CYAN}${current_name}${PLAIN}.")"
    echo -e "$(localized_text "${YELLOW}主机名建议只使用字母、数字、连字符和点号；每段不能以连字符开头或结尾。${PLAIN}" "${YELLOW}It is recommended to use only letters, numbers, hyphens and periods for the host name; each paragraph cannot begin or end with a hyphen.${PLAIN}" "${YELLOW}В имени хоста рекомендуется использовать только буквы, цифры, дефисы и точки; каждый абзац не может начинаться или заканчиваться дефисом.${PLAIN}")"
    read_trimmed new_name "$(localized_text "请输入新的主机名（回车取消）: " "Please enter a new hostname (press enter to cancel):" "Пожалуйста, введите новое имя хоста (нажмите Enter, чтобы отменить):")"
    [[ -z "$new_name" || "$new_name" == "0" ]] && { echo -e "$(localized_text "${BLUE}已取消修改主机名。${PLAIN}" "${BLUE}The modification of the host name has been cancelled.${PLAIN}" "${BLUE}Изменение имени хоста отменено.${PLAIN}")"; return 0; }

    if ! is_valid_hostname "$new_name"; then
        echo -e "$(localized_text "${RED}❌ 主机名格式无效。示例：vps01 或 node-1.example.com${PLAIN}" "${RED}❌ The hostname format is invalid. Example: vps01 or node-1.example.com${PLAIN}" "${RED}❌ Неверный формат имени хоста. Пример: vps01 или node-1.example.com.${PLAIN}")"
        return 1
    fi

    if [[ "$new_name" == "$current_name" ]]; then
        echo -e "$(localized_text "${BLUE}主机名未变化。${PLAIN}" "${BLUE}The host name has not changed.${PLAIN}" "${BLUE}Имя хоста не изменилось.${PLAIN}")"
        return 0
    fi

    confirm_risk_action "$(localized_text "修改主机名为 ${new_name}" "Modify the host name to ${new_name}" "Измените имя хоста на ${new_name}.")" \
        "$(localized_text "/etc/hostname、/etc/hosts 和当前运行时 hostname" "/etc/hostname、/etc/hosts and current runtime hostname" "/etc/hostname、/etc/hosts и текущее имя хоста среды выполнения.")" \
        "$(localized_text "使用本功能改回 ${current_name}，或从 /etc/*.bak_时间戳 恢复" "Use this function to change back to ${current_name} or restore from /etc/*.bak_时间戳" "Используйте эту функцию для возврата к ${current_name} или восстановления с /etc/*.bak_时间戳.")" \
        "$(localized_text "少数服务会在重启后才读取新主机名。" "A few services will not read the new hostname until they are restarted." "Некоторые службы не будут считывать новое имя хоста до тех пор, пока не будут перезапущены.")" || return 1

    ts=$(date +%s)
    [[ -f /etc/hostname ]] && cp -p /etc/hostname "/etc/hostname.bak_${ts}" 2>/dev/null || true
    [[ -f /etc/hosts ]] && cp -p /etc/hosts "/etc/hosts.bak_${ts}" 2>/dev/null || true

    echo "$new_name" > /etc/hostname || {
        echo -e "$(localized_text "${RED}❌ 写入 /etc/hostname 失败。${PLAIN}" "${RED}❌ Failed to write /etc/hostname.${PLAIN}" "${RED}❌ Не удалось записать /etc/hostname.${PLAIN}")"
        return 1
    }

    if [[ -f /etc/hosts ]]; then
        update_hosts_hostname_entry "$current_name" "$new_name" || echo -e "$(localized_text "${YELLOW}⚠️ /etc/hosts 更新失败，请稍后手动检查。${PLAIN}" "${YELLOW}⚠️ /etc/hosts update failed, please check manually later.${PLAIN}" "${YELLOW}⚠️ Обновление /etc/hosts не удалось, проверьте вручную позже.${PLAIN}")"
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

    echo -e "$(localized_text "${GREEN}✅ 主机名已修改为：${new_name}${PLAIN}" "${GREEN}✅ The host name has been changed to: ${new_name}${PLAIN}" "${GREEN}. Имя хоста изменено на: ${new_name}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如部分服务仍显示旧名称，重启对应服务或下次重启系统后会完全生效。${PLAIN}" "${YELLOW}If some services still display the old names, restart the corresponding services or the next time the system is restarted, it will take full effect.${PLAIN}" "${YELLOW}Если некоторые службы по-прежнему отображают старые имена, перезапустите соответствующие службы или при следующем перезапуске системы это вступит в полную силу.${PLAIN}")"
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
    raw="${raw//、/,}"
    raw="${raw//；/,}"
    raw="${raw//;/,}"
    raw="${raw//,/ }"
    out_array=()
    for item in $raw; do
        normalized=$(normalize_domain_input "$item")
        [[ -z "$normalized" ]] && continue
        if ! is_valid_hostname "$normalized"; then
            echo -e "$(localized_text "${RED}❌ 主机名/域名格式无效：${normalized}${PLAIN}" "${RED}❌ Invalid host name/domain format: ${normalized}${PLAIN}" "${RED}❌ Неверный формат имени хоста/доменного имени: ${normalized}.${PLAIN}")"
            return 1
        fi
        case "$normalized" in
            localhost|localhost.localdomain|ip6-localhost|ip6-loopback)
                echo -e "$(localized_text "${RED}❌ 为避免破坏系统解析，不能管理保留名称：${normalized}${PLAIN}" "${RED}❌ To avoid damaging system resolution, the reserved name cannot be managed: ${normalized}${PLAIN}" "${RED}❌ Чтобы не повредить разрешение системы, нельзя управлять зарезервированным именем: ${normalized}.${PLAIN}")"
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
    read_trimmed ip "$(localized_text "请输入解析 IP（IPv4/IPv6）: " "Please enter the resolution IP (IPv4/IPv6):" "Пожалуйста, введите IP-адрес разрешения (IPv4/IPv6):")"
    if ! hosts_is_valid_ip "$ip"; then
        echo -e "$(localized_text "${RED}❌ IP 格式无效。${PLAIN}" "${RED}❌ IP format is invalid.${PLAIN}" "${RED}❌ Неверный формат IP.${PLAIN}")"
        return 1
    fi
    read_trimmed names_input "$(localized_text "请输入要绑定的域名/主机名（多个用空格或逗号分隔）: " "Please enter the domain/host name to be bound (separate multiple names with spaces or commas):" "Пожалуйста, введите имя домена/имя хоста, к которому будет привязываться (разделяйте несколько имен пробелами или запятыми):")"
    if ! hosts_normalize_names "$names_input" names; then
        return 1
    fi
    names_csv=$(IFS=','; printf '%s' "${names[*]}")
    names_joined=$(IFS=' '; printf '%s' "${names[*]}")
    confirm_risk_action "$(localized_text "写入本机 hosts 解析" "Write to local hosts parsing" "Запись на локальные хосты, парсинг")" \
        "$(localized_text "/etc/hosts 本机解析表" "/etc/hosts local parsing table" "/etc/hosts локальная таблица синтаксического анализа")" \
        "$(localized_text "从 /etc/vps-optimize/backups/hosts 恢复最近备份，或在本菜单删除对应条目" "Restore the latest backup from /etc/vps-optimize/backups/hosts, or delete the corresponding entry in this menu" "Восстановите последнюю резервную копию из /etc/vps-optimize/backups/hosts или удалите соответствующую запись в этом меню.")" \
        "$(localized_text "本功能只影响当前 VPS 本机解析，不会修改公网 DNS。" "This function only affects the local resolution of the current VPS and will not modify the public DNS." "Эта функция влияет только на локальное разрешение текущего VPS и не изменяет публичную сеть DNS.")" || return 1

    backup_file=$(hosts_backup_current) || {
        echo -e "$(localized_text "${RED}❌ /etc/hosts 备份失败，已取消。${PLAIN}" "${RED}❌ /etc/hosts Backup failed and has been cancelled.${PLAIN}" "${RED}❌ /etc/hosts Резервное копирование не выполнено и было отменено.${PLAIN}")"
        return 1
    }
    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    if hosts_remove_names_to_tmp "$names_csv" "$tmp_file"; then
        printf '%s\t%s\t%s\n' "$ip" "$names_joined" "$(hosts_managed_marker)" >> "$tmp_file"
        cp "$tmp_file" /etc/hosts
        echo -e "$(localized_text "${GREEN}✅ 已写入本机 hosts：${ip} -> ${names_joined}${PLAIN}" "${GREEN}✅ has been written to this machine hosts: ${ip} -> ${names_joined}${PLAIN}" "${GREEN}✅ был записан на хосты этой машины: ${ip} -> ${names_joined}${PLAIN}")"
        echo -e "$(localized_text "${CYAN}备份已保留：${backup_file}${PLAIN}" "${CYAN}Backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия сохранена: ${backup_file}.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 生成 hosts 临时文件失败，已取消。${PLAIN}" "${RED}❌ Failed to generate hosts temporary file and has been cancelled.${PLAIN}" "${RED}❌ Не удалось создать временный файл хостов, работа была отменена.${PLAIN}")"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"
}

hosts_remove_entry() {
    local names_input names_csv names_joined backup_file tmp_file
    local -a names=()
    read_trimmed names_input "$(localized_text "请输入要删除解析的域名/主机名（多个用空格或逗号分隔）: " "Please enter the domain/host name to be deleted (separate multiple by spaces or commas):" "Пожалуйста, введите имя домена/хоста, которое необходимо удалить (разделяйте кратные пробелами или запятыми):")"
    if ! hosts_normalize_names "$names_input" names; then
        return 1
    fi
    names_csv=$(IFS=','; printf '%s' "${names[*]}")
    names_joined=$(IFS=' '; printf '%s' "${names[*]}")
    confirm_risk_action "$(localized_text "删除本机 hosts 解析" "Delete local hosts resolution" "Удалить разрешение локальных хостов")" \
        "$(localized_text "/etc/hosts 中与 ${names_joined} 匹配的解析项" "Parse items in /etc/hosts that match ${names_joined}" "Разобрать элементы в /etc/hosts, соответствующие ${names_joined}.")" \
        "$(localized_text "从 /etc/vps-optimize/backups/hosts 恢复最近备份" "Restore recent backup from /etc/vps-optimize/backups/hosts" "Восстановите последнюю резервную копию из /etc/vps-optimize/backups/hosts.")" \
        "$(localized_text "只删除匹配主机名，保留同一行其他别名。" "Remove only matching hostnames, leaving other aliases on the same line." "Удалите только совпадающие имена хостов, оставив другие псевдонимы в одной строке.")" || return 1

    backup_file=$(hosts_backup_current) || {
        echo -e "$(localized_text "${RED}❌ /etc/hosts 备份失败，已取消。${PLAIN}" "${RED}❌ /etc/hosts Backup failed and has been cancelled.${PLAIN}" "${RED}❌ /etc/hosts Резервное копирование не выполнено и было отменено.${PLAIN}")"
        return 1
    }
    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    if hosts_remove_names_to_tmp "$names_csv" "$tmp_file"; then
        cp "$tmp_file" /etc/hosts
        echo -e "$(localized_text "${GREEN}✅ 已删除匹配的本机 hosts 解析：${names_joined}${PLAIN}" "${GREEN}✅ The matching local hosts have been deleted. Resolution: ${names_joined}${PLAIN}" "${GREEN}✅ Соответствующие локальные хосты были удалены. Разрешение: ${names_joined}${PLAIN}")"
        echo -e "$(localized_text "${CYAN}备份已保留：${backup_file}${PLAIN}" "${CYAN}Backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия сохранена: ${backup_file}.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 生成 hosts 临时文件失败，已取消。${PLAIN}" "${RED}❌ Failed to generate hosts temporary file and has been cancelled.${PLAIN}" "${RED}❌ Не удалось создать временный файл хостов, работа была отменена.${PLAIN}")"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"
}

hosts_restore_latest_backup() {
    local latest
    latest=$(find /etc/vps-optimize/backups/hosts -maxdepth 1 -type f -name 'hosts.*.bak' 2>/dev/null | sort -r | head -n1)
    if [[ -z "$latest" ]]; then
        echo -e "$(localized_text "${YELLOW}未找到 hosts 备份。${PLAIN}" "${YELLOW}Hosts backup not found.${PLAIN}" "${YELLOW}Резервная копия хостов не найдена.${PLAIN}")"
        return 1
    fi
    confirm_risk_action "$(localized_text "恢复最近 hosts 备份" "Restore recent hosts backup" "Восстановить резервную копию последних хостов")" \
        "$(localized_text "/etc/hosts 将恢复为 ${latest}" "/etc/hosts will revert to ${latest}" "/etc/hosts вернется к ${latest}.")" \
        "$(localized_text "重新进入本菜单添加/删除解析，或手动恢复更新前备份" "Re-enter this menu to add/delete parses, or manually restore the backup before the update" "Повторно войдите в это меню, чтобы добавить/удалить анализы или вручную восстановить резервную копию перед обновлением.")" \
        "$(localized_text "恢复会覆盖当前本机 hosts 解析。" "Restoring overwrites the current native hosts resolution." "При восстановлении перезаписывается текущее собственное разрешение хостов.")" || return 1
    cp -p "$latest" /etc/hosts || {
        echo -e "$(localized_text "${RED}❌ 恢复失败。${PLAIN}" "${RED}❌ Recovery failed.${PLAIN}" "${RED}❌ Восстановление не удалось.${PLAIN}")"
        return 1
    }
    echo -e "$(localized_text "${GREEN}✅ 已恢复：${latest}${PLAIN}" "${GREEN}✅ Restored: ${latest}${PLAIN}" "${GREEN}✅ Восстановлено: ${latest}${PLAIN}")"
}

func_hosts_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "系统开关与清理 > 本机 hosts 解析" "System switch and cleanup > Local hosts resolution" "Переключение и очистка системы > Разрешение локальных хостов")"
        echo -e "$(localized_text "${BOLD}🧭 本机 hosts 解析管理${PLAIN}" "${BOLD}🧭 Local hosts resolution management${PLAIN}" "${BOLD}🧭 Управление разрешением локальных хостов${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：修改当前 VPS 的 /etc/hosts，本地指定域名解析到某个 IP。不会影响公网 DNS。${PLAIN}" "${YELLOW}Purpose: Modify the /etc/hosts of the current VPS and resolve the local specified domain to a certain IP. It will not affect the public DNS.${PLAIN}" "${YELLOW}Назначение: изменить /etc/hosts текущего VPS и разрешить указанное локальное доменное имя в определенный IP-адрес. Это не повлияет на публичную сеть DNS.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看当前 hosts${PLAIN}" "${GREEN}1. View current hosts${PLAIN}" "${GREEN}1. Просмотр текущих хостов${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 添加 / 更新本机解析${PLAIN}" "${GREEN}2. Add/update local resolution${PLAIN}" "${GREEN}2. Добавить/обновить локальное разрешение.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  3. 删除本机解析${PLAIN}" "${YELLOW}3. Delete local resolution${PLAIN}" "${YELLOW}3. Удалить локальное разрешение.${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  4. 恢复最近一次 hosts 备份${PLAIN}" "${CYAN}4. Restore the latest hosts backup${PLAIN}" "${CYAN}4. Восстановите последнюю резервную копию хостов.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
        case "$choice" in
            1)
                echo -e "${CYAN}--- /etc/hosts ---${PLAIN}"
                sed -n '1,120p' /etc/hosts 2>/dev/null || echo "$(localized_text "未检测到 /etc/hosts" "/etc/hosts not detected" "/etc/hosts не обнаружен")"
                pause_return
                ;;
            2) hosts_add_or_update_entry; pause_return ;;
            3) hosts_remove_entry; pause_return ;;
            4) hosts_restore_latest_backup; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 2. 系统高级开关 (已修复显示丢失问题)
# ---------------------------------------------------------
