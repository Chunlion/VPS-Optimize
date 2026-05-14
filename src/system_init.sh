# shellcheck shell=bash
# Base initialization and timezone setup.

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
