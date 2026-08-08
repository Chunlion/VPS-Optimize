# shellcheck shell=bash
# Base initialization and timezone setup.

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
    fi
}

func_base_init() {
    clear
    echo -e "$(localized_text "${CYAN}👉 正在更新系统软件包、安装基础工具、限制日志并开启基础 BBR...${PLAIN}" "${CYAN}👉 Updating system software packages, installing basic tools, limiting logs and enabling basics BBR...${PLAIN}" "${CYAN}👉 Обновление пакетов системного ПО, установка базовых инструментов, ограничение журналов и включение базовых функций BBR...${PLAIN}")"
    
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
    
    echo -e "$(localized_text "${GREEN}✅ 基础初始化完成，原生 BBR 已激活！${PLAIN}" "${GREEN}✅ Basic initialization completed, native BBR has been activated!${PLAIN}" "${GREEN}✅ Базовая инициализация завершена, родной BBR активирован!${PLAIN}")"
    read -n 1 -s -r -p "$(localized_text "按任意键返回主菜单..." "Press any key to return to the main menu..." "Нажмите любую клавишу, чтобы вернуться в главное меню...")"
}

# ---------------------------------------------------------
# ★ 防火墙专属管理面板 (安全追加模式 + 批量多端口支持)
# ---------------------------------------------------------
