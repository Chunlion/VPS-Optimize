# shellcheck shell=bash
# Base system initialization, hostname, hosts, and system toggles.

configure_system_timezone_for_init() {
    local current_tz choice custom_tz target_tz

    if ! command -v timedatectl >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 timedatectl，已保持当前系统时区。${PLAIN}" "${YELLOW}⚠️ timedatectl not detected, current system time zone has been maintained.${PLAIN}" "${YELLOW}⚠️ timedatectl не обнаружен, текущий часовой пояс системы сохранен.${PLAIN}")"
        return 0
    fi

    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    [[ -z "$current_tz" ]] && current_tz="$(localized_text "未设置/未知" "Not set/unknown" "Не установлено/неизвестно")"

    echo -e "$(localized_text "${CYAN}当前系统时区：${current_tz}${PLAIN}" "${CYAN}Current system time zone: ${current_tz}${PLAIN}" "${CYAN}Текущий часовой пояс системы: ${current_tz}${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  1. 保持当前时区${PLAIN} ${YELLOW}(默认)${PLAIN}" "${GREEN}1. Keep the current time zone (default)${PLAIN}" "${GREEN}1. Сохранить текущий часовой пояс (по умолчанию)${PLAIN}")"
    echo -e "${GREEN}  2. Asia/Shanghai${PLAIN}"
    echo -e "${GREEN}  3. Asia/Tokyo${PLAIN}"
    echo -e "${GREEN}  4. UTC${PLAIN}"
    echo -e "$(localized_text "${GREEN}  5. 自定义时区${PLAIN}" "${GREEN}5. Custom time zone${PLAIN}" "${GREEN}5. Пользовательский часовой пояс${PLAIN}")"
    read_trimmed choice "$(localized_text "请选择基础初始化时区处理方式（默认 1）: " "Please select the basic initialization time zone processing method (default 1):" "Пожалуйста, выберите основной метод обработки часового пояса при инициализации (по умолчанию 1):")"

    case "${choice:-1}" in
        1)
            echo -e "$(localized_text "${BLUE}已保持当前时区：${current_tz}${PLAIN}" "${BLUE}Has maintained the current time zone: ${current_tz}${PLAIN}" "${BLUE}сохранил текущий часовой пояс: ${current_tz}.${PLAIN}")"
            return 0
            ;;
        2) target_tz="Asia/Shanghai" ;;
        3) target_tz="Asia/Tokyo" ;;
        4) target_tz="UTC" ;;
        5)
            read_trimmed custom_tz "$(localized_text "请输入 IANA 时区名称（例如 Europe/London）: " "Please enter the IANA time zone name (e.g. Europe/London):" "Введите название часового пояса IANA (например, Европа/Лондон):")"
            target_tz="$custom_tz"
            ;;
        *)
            echo -e "$(localized_text "${YELLOW}⚠️ 未选择有效选项，已保持当前时区：${current_tz}${PLAIN}" "${YELLOW}⚠️ No valid option selected, current time zone has been maintained: ${current_tz}${PLAIN}" "${YELLOW}⚠️ Не выбран правильный вариант, текущий часовой пояс сохранен: ${current_tz}${PLAIN}")"
            return 0
            ;;
    esac

    if [[ -z "$target_tz" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 自定义时区为空，已保持当前时区：${current_tz}${PLAIN}" "${YELLOW}⚠️ The custom time zone is empty, the current time zone has been maintained: ${current_tz}${PLAIN}" "${YELLOW}⚠️ Пользовательский часовой пояс пуст, текущий часовой пояс сохранен: ${current_tz}${PLAIN}")"
        return 0
    fi

    if timedatectl set-timezone "$target_tz" >/dev/null 2>&1; then
        echo -e "$(localized_text "${GREEN}✅ 系统时区已设置为：${target_tz}${PLAIN}" "${GREEN}✅ The system time zone has been set to: ${target_tz}${PLAIN}" "${GREEN}. Часовой пояс системы установлен на: ${target_tz}.${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 时区设置失败，已保持当前时区：${current_tz}${PLAIN}" "${YELLOW}⚠️ Time zone setting failed, current time zone has been maintained: ${current_tz}${PLAIN}" "${YELLOW}⚠️ Не удалось настроить часовой пояс, текущий часовой пояс сохранен: ${current_tz}${PLAIN}")"
        return 1
    fi
}

func_base_init() {
    local failed_steps=()
    local current_cc current_qdisc

    clear
    echo -e "$(localized_text "${CYAN}👉 正在更新系统软件包、安装基础工具、限制日志并开启基础 BBR...${PLAIN}" "${CYAN}👉 Updating system software packages, installing basic tools, limiting logs and enabling basics BBR...${PLAIN}" "${CYAN}👉 Обновление пакетов системного ПО, установка базовых инструментов, ограничение журналов и включение базовых функций BBR...${PLAIN}")"

    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        if apt-get update -y && apt-get upgrade -y; then
            APT_UPDATED=1
        else
            failed_steps+=("$(localized_text "系统软件包更新" "System package update" "Обновление системных пакетов")")
        fi
        unset DEBIAN_FRONTEND
        install_pkg sudo curl wget git nano unzip htop lsof net-tools iputils-ping dnsutils iptables iproute2 sqlite3 jq \
            || failed_steps+=("$(localized_text "基础工具安装" "Base tool installation" "Установка базовых инструментов")")
    elif is_redhat; then
        if command -v dnf >/dev/null 2>&1; then
            dnf update -y || failed_steps+=("$(localized_text "系统软件包更新" "System package update" "Обновление системных пакетов")")
        else
            yum update -y || failed_steps+=("$(localized_text "系统软件包更新" "System package update" "Обновление системных пакетов")")
        fi
        install_pkg sudo curl wget git nano unzip htop lsof net-tools iputils bind-utils iptables iproute epel-release sqlite jq \
            || failed_steps+=("$(localized_text "基础工具安装" "Base tool installation" "Установка базовых инструментов")")
    else
        failed_steps+=("$(localized_text "当前发行版不受支持" "Unsupported distribution" "Дистрибутив не поддерживается")")
    fi

    ensure_minimal_system_compat || failed_steps+=("$(localized_text "精简系统兼容组件" "Minimal-system compatibility components" "Компоненты совместимости минимальной системы")")

    if ! mkdir -p /etc/systemd/journald.conf.d/ || ! cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    then
        failed_steps+=("$(localized_text "journald 日志限制" "journald log limit" "Ограничение журнала journald")")
    elif ! systemctl restart systemd-journald >/dev/null 2>&1; then
        failed_steps+=("$(localized_text "journald 重启" "journald restart" "Перезапуск journald")")
    fi

    configure_system_timezone_for_init || failed_steps+=("$(localized_text "时区设置" "Timezone configuration" "Настройка часового пояса")")

    modprobe tcp_bbr >/dev/null 2>&1 || true
    if ! {
        printf '%s\n' \
            "net.core.default_qdisc = fq" \
            "net.ipv4.tcp_congestion_control = bbr" \
            > /etc/sysctl.d/99-bbr-init.conf
    }; then
        failed_steps+=("$(localized_text "BBR 配置写入" "Write BBR configuration" "Запись конфигурации BBR")")
    elif ! sysctl -p /etc/sysctl.d/99-bbr-init.conf >/dev/null 2>&1; then
        failed_steps+=("$(localized_text "BBR 参数加载" "Load BBR parameters" "Загрузка параметров BBR")")
    else
        current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
        current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
        if [[ "$current_cc" != "bbr" || "$current_qdisc" != "fq" ]]; then
            failed_steps+=("$(localized_text "BBR 状态验证" "Validate BBR status" "Проверка состояния BBR")")
        fi
    fi

    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 基础初始化完成，已验证 BBR 与 fq 生效。${PLAIN}" "${GREEN}✅ Basic initialization is completed, and BBR and fq have been verified to be effective.${PLAIN}" "${GREEN}✅ Базовая инициализация завершена, эффективность BBR и fq подтверждена.${PLAIN}")"
        if [[ "${VPSO_BEGINNER_FLOW:-0}" != "1" ]]; then
            read -n 1 -s -r -p "$(localized_text "按任意键返回主菜单..." "Press any key to return to the main menu..." "Нажмите любую клавишу, чтобы вернуться в главное меню...")"
        fi
        return 0
    fi

    echo -e "$(localized_text "${RED}❌ 基础初始化未完整完成，失败步骤：${PLAIN}" "${RED}❌ Basic initialization is not completely completed, failed step:${PLAIN}" "${RED}❌ Базовая инициализация не полностью завершена, не удалось выполнить шаг:${PLAIN}")"
    printf '  - %s\n' "${failed_steps[@]}"
    echo -e "$(localized_text "${YELLOW}已保留成功完成的步骤；请修复上述问题后重新运行基础初始化。${PLAIN}" "${YELLOW}Has retained successfully completed steps; please fix the above issue and rerun the basic initialization.${PLAIN}" "${YELLOW}сохранил успешно выполненные шаги; пожалуйста, исправьте вышеуказанную проблему и повторите базовую инициализацию.${PLAIN}")"
    if [[ "${VPSO_BEGINNER_FLOW:-0}" != "1" ]]; then
        read -n 1 -s -r -p "$(localized_text "按任意键返回主菜单..." "Press any key to return to the main menu..." "Нажмите любую клавишу, чтобы вернуться в главное меню...")"
    fi
    return 1
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
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}⚙️ 系统开关与清理${PLAIN}" "${BOLD}⚙️ System switch and cleaning${PLAIN}" "${BOLD}⚙️ Системный переключатель и очистка${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        # 状态获取
        local ipv6_status
        local str_ipv6
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="$(localized_text "${GREEN}开启中${PLAIN}" "${GREEN}Is opening${PLAIN}" "${GREEN}открывает${PLAIN}")"; else str_ipv6="$(localized_text "${RED}已禁用${PLAIN}" "${RED}Disabled${PLAIN}" "${RED}отключен${PLAIN}")"; fi

        local str_ipv4_first
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
            str_ipv4_first="$(localized_text "${GREEN}已优先${PLAIN}" "${GREEN}Has given priority to${PLAIN}" "${GREEN}отдал приоритет${PLAIN}")"
        else
            str_ipv4_first="$(localized_text "${RED}默认(IPv6优先)${PLAIN}" "${RED}Default (IPv6 takes priority)${PLAIN}" "${RED}по умолчанию (IPv6 имеет приоритет)${PLAIN}")"
        fi

        local ping_status
        local str_ping
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="$(localized_text "${GREEN}允许被Ping${PLAIN}" "${GREEN}Is allowed to be Ping${PLAIN}" "${GREEN}может быть Ping${PLAIN}")"; else str_ping="$(localized_text "${RED}禁Ping中${PLAIN}" "${RED}Ping banned${PLAIN}" "${RED}Пинг запрещен${PLAIN}")"; fi

        local update_status
        local str_update
        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
        fi
        if [[ "$update_status" == "active" ]]; then str_update="$(localized_text "${GREEN}开启中${PLAIN}" "${GREEN}Is opening${PLAIN}" "${GREEN}открывает${PLAIN}")"; else str_update="$(localized_text "${RED}已关闭${PLAIN}" "${RED}Has closed${PLAIN}" "${RED}закрылся${PLAIN}")"; fi

        local current_hostname
        current_hostname=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
        current_hostname="$(trim_input "$current_hostname")"
        current_hostname="$(localized_text "${current_hostname:-未知}" "${current_hostname:-未知}" "${current_hostname:-未知}")"

        # 完美修复：一字不落的菜单显示
        echo -e "$(localized_text "${GREEN}  1. IPv6 开关${PLAIN}              当前: [ $str_ipv6 ]" "${GREEN}1. IPv6 switch${PLAIN} Current: [ $str_ipv6 ]" "${GREEN}1. Переключатель IPv6${PLAIN} Ток: [ $str_ipv6 ]")"
        echo -e "$(localized_text "${GREEN}  2. IPv4 出站优先${PLAIN}          当前: [ $str_ipv4_first ]" "${GREEN}2. IPv4 Outbound priority${PLAIN} Current: [ $str_ipv4_first ]" "${GREEN}2. IPv4 Приоритет исходящего вызова${PLAIN} Текущий: [ $str_ipv4_first ]")"
        echo -e "$(localized_text "${GREEN}  3. Ping 响应开关${PLAIN}          当前: [ $str_ping ]" "${GREEN}3. Ping response switch${PLAIN} Current: [ $str_ping ]" "${GREEN}3. Переключатель ответа на запрос Ping${PLAIN} Ток: [ $str_ping ]")"
        echo -e "$(localized_text "${GREEN}  4. 本机 hosts 解析管理${PLAIN}    (/etc/hosts 本机域名解析)" "${GREEN}4. Local hosts resolution management${PLAIN} (/etc/hosts local domain resolution)" "${GREEN}4. Управление разрешением локальных хостов${PLAIN} (разрешение локального доменного имени /etc/hosts)")"
        echo -e "$(localized_text "${GREEN}  5. 修改主机名${PLAIN}             当前: [ ${CYAN}${current_hostname}${PLAIN} ]" "${GREEN}5. Modify the host name${PLAIN} Current: [ ${CYAN}${current_hostname}${PLAIN} ]" "${GREEN}5. Измените имя хоста${PLAIN} Текущее: [ ${CYAN}${current_hostname}${PLAIN} ]")"
        echo -e "$(localized_text "${GREEN}  6. 自动安全更新开关${PLAIN}       当前: [ $str_update ]" "${GREEN}6. Automatic security update switch${PLAIN} Current: [ $str_update ]" "${GREEN}6. Переключатель автоматического обновления безопасности${PLAIN} Текущая версия: [ $str_update ]")"
        echo -e "$(localized_text "${GREEN}  7. 清理系统垃圾${PLAIN}           (日志/缓存/无用包)" "${GREEN}7. Clean up system garbage${PLAIN} (log/cache/useless packages)" "${GREEN}7. Очистка системного мусора${PLAIN} (журнал/кеш/бесполезные пакеты)")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local tweak_choice
        read_trimmed tweak_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"

        case $tweak_choice in
            1)
                read_trimmed yn "$(localized_text "❓ 开启 IPv6？(y 开启 / n 关闭): " "❓ Turn on IPv6? (y on / n off):" "❓ Включить IPv6? (да вкл./нет выкл.):")"
                if is_yes "$yn"; then
                    quarantine_path /etc/sysctl.d/99-disable-ipv6.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ IPv6 已开启${PLAIN}" "${GREEN}✅ IPv6 has opened${PLAIN}" "${GREEN}✅ IPv6 открылся${PLAIN}")"
                elif is_no "$yn"; then
                    [[ -f /etc/sysctl.d/99-disable-ipv6.conf ]] && cp -p /etc/sysctl.d/99-disable-ipv6.conf "/etc/sysctl.d/99-disable-ipv6.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1
                    echo -e "$(localized_text "${RED}✅ IPv6 已禁用${PLAIN}" "${RED}✅ IPv6 has disabled${PLAIN}" "${RED}✅ IPv6 отключил${PLAIN}")"
                fi; sleep 1 ;;
            2)
                read_trimmed yn "$(localized_text "❓ 设置 IPv4 为最高出站优先级？(y 开启 / n 恢复默认): " "❓ Set IPv4 as the highest outbound priority? (y turns on / n returns to default):" "❓ Установить IPv4 как наивысший исходящий приоритет? (y включается/n возвращается к настройкам по умолчанию):")"
                if is_yes "$yn"; then
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf
                    echo -e "$(localized_text "${GREEN}✅ 已设为 IPv4 优先${PLAIN}" "${GREEN}✅ has been set to IPv4, giving priority to${PLAIN}" "${GREEN}Для вещества установлено значение IPv4, что дает приоритет.${PLAIN}")"
                elif is_no "$yn"; then
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
                    echo -e "$(localized_text "${BLUE}已恢复系统默认${PLAIN}" "${BLUE}Has restored the system default${PLAIN}" "${BLUE}восстановил системные настройки по умолчанию${PLAIN}")"
                fi; sleep 1 ;;
            3)
                read_trimmed yn "$(localized_text "❓ 允许被 Ping？(y 允许 / n 禁止): " "❓ Allow to be pinged? (y allowed / n forbidden):" "❓ Разрешить пинговать? (y разрешено/n запрещено):")"
                if is_yes "$yn"; then
                    quarantine_path /etc/sysctl.d/99-disable-ping.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ 已允许被 Ping${PLAIN}" "${GREEN}✅ has been allowed to be Ping${PLAIN}" "${GREEN}веществу разрешено быть Ping${PLAIN}")"
                elif is_no "$yn"; then
                    [[ -f /etc/sysctl.d/99-disable-ping.conf ]] && cp -p /etc/sysctl.d/99-disable-ping.conf "/etc/sysctl.d/99-disable-ping.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1
                    echo -e "$(localized_text "${RED}✅ 已开启禁 Ping 保护${PLAIN}" "${RED}✅ Ping ban protection has been enabled${PLAIN}" "${RED}✅ Защита от блокировки Ping включена${PLAIN}")"
                fi; sleep 1 ;;
            4) func_hosts_manage ;;
            5) func_change_hostname; sleep 1 ;;
            6)
                read_trimmed yn "$(localized_text "❓ 开启系统自动更新？(y 开启 / n 关闭): " "❓ Turn on automatic system updates? (y on / n off):" "❓ Включить автоматическое обновление системы? (да вкл./нет выкл.):")"
                if is_yes "$yn"; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg unattended-upgrades || { echo -e "$(localized_text "${RED}❌ unattended-upgrades 安装失败。${PLAIN}" "${RED}❌ unattended-upgrades Installation failed.${PLAIN}" "${RED}❌ автоматические обновления Установка не удалась.${PLAIN}")"; sleep 1; continue; }
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}⚠️ unattended-upgrades 服务启用失败，请手动检查。${PLAIN}" "${YELLOW}⚠️ unattended-upgrades Service activation failed, please check manually.${PLAIN}" "${YELLOW}⚠️ unattended-upgrades Не удалось активировать службу, проверьте вручную.${PLAIN}")"
                    else
                        install_pkg dnf-automatic || { echo -e "$(localized_text "${RED}❌ dnf-automatic 安装失败。${PLAIN}" "${RED}❌ dnf-automatic installation failed.${PLAIN}" "${RED}❌ dnf-автоматическая установка не удалась.${PLAIN}")"; sleep 1; continue; }
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}⚠️ dnf-automatic.timer 启用失败，请手动检查。${PLAIN}" "${YELLOW}⚠️ dnf-automatic.timer failed to be enabled, please check manually.${PLAIN}" "${YELLOW}⚠️ Не удалось включить dnf-automatic.timer, проверьте вручную.${PLAIN}")"
                    fi
                    echo -e "$(localized_text "${GREEN}✅ 自动更新已开启${PLAIN}" "${GREEN}✅ Automatic update is turned on${PLAIN}" "${GREEN}✅ Автоматическое обновление включено${PLAIN}")"
                elif is_no "$yn"; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null 2>&1
                    else systemctl disable --now dnf-automatic.timer >/dev/null 2>&1; fi
                    echo -e "$(localized_text "${GREEN}✅ 自动更新已关闭${PLAIN}" "${GREEN}✅ Automatic updates are turned off${PLAIN}" "${GREEN}✅ Автоматические обновления отключены${PLAIN}")"
                fi; sleep 1 ;;
            7)
                echo -e "$(localized_text "${CYAN}👉 正在深度清理系统垃圾...${PLAIN}" "${CYAN}👉 Deep cleaning of system junk...${PLAIN}" "${CYAN}👉 Глубокая очистка системного мусора...${PLAIN}")"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    apt autoremove --purge -y >/dev/null 2>&1
                    apt clean >/dev/null 2>&1
                else
                    yum autoremove -y >/dev/null 2>&1
                    yum clean all >/dev/null 2>&1
                fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                echo -e "$(localized_text "${GREEN}✅ 清理完成！${PLAIN}" "${GREEN}✅ Cleanup completed!${PLAIN}" "${GREEN}✅ Очистка завершена!${PLAIN}")"
                sleep 1 ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 统一包管理与执行守卫 (新增：请放在 func_env_install 函数上方)
# ---------------------------------------------------------
