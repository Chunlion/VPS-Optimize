#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 全能控制面板 
#  Features: 智能防火墙/DNS流媒体解锁/安全加固/IP工具/环境部署/一键反代
#  Shortcut: cy
# =========================================================

# --- 颜色与格式定义 ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# --- 权限检查 ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 错误：请以 root 用户身份运行本脚本！${PLAIN}"
    exit 1
fi

# --- 系统识别增强 ---
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    OS_LIKE=${ID_LIKE:-""}
else
    OS="unknown"
    OS_LIKE="unknown"
fi

is_debian() {
    [[ "$OS" =~ debian|ubuntu ]] || [[ "$OS_LIKE" =~ debian|ubuntu ]]
}

is_redhat() {
    [[ "$OS" =~ centos|rhel|rocky|almalinux|fedora ]] || [[ "$OS_LIKE" =~ centos|rhel|fedora ]]
}
# --- 全局包管理抽象  ---
install_pkg() {
    local pkgs="$*"
    if is_debian; then
        # 使用 apt-get 代替 apt，消除 "stable CLI interface" 警告 
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq $pkgs >/dev/null 2>&1
        unset DEBIAN_FRONTEND
    elif is_redhat; then
        yum install -y -q $pkgs >/dev/null 2>&1
    fi
}

remove_pkg() {
    local pkgs="$*"
    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y -qq $pkgs >/dev/null 2>&1
        unset DEBIAN_FRONTEND
    elif is_redhat; then
        yum remove -y -q $pkgs >/dev/null 2>&1
    fi
}
UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh"

# --- 全局快捷键注册 ---
create_shortcut() {
    local script_path="/usr/local/bin/cy"
    if [[ ! -f "$script_path" ]]; then
        # 优先尝试从远端直接拉取
        if ! curl -fsL "$UPDATE_URL" -o "$script_path" 2>/dev/null; then
            # 若远端拉取失败，且检测到 $0 确实是本地存在的物理文件，才允许复制
            if [[ -f "$0" ]]; then
                cp "$(readlink -f "$0")" "$script_path" 2>/dev/null
            else
                echo -e "${YELLOW}⚠️ 快捷指令本地注册挂起，请稍后在主菜单 [17] 更新脚本完成注册。${PLAIN}"
                return
            fi
        fi
        chmod +x "$script_path"
        echo -e "${GREEN}✅ 快捷指令 'cy' 已全局注册！下次可直接输入 cy 唤出面板。${PLAIN}"
        sleep 1
    fi
}

# ---------------------------------------------------------
# 1. 基础环境初始化 (抽象精简版)
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在更新系统软件包、安装基础工具、限制日志并开启基础 BBR...${PLAIN}"
    
    # 更新系统软件包并优雅调用全局安装函数
    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y && apt-get upgrade -y
        unset DEBIAN_FRONTEND
        install_pkg curl wget git nano unzip htop iptables iproute2 sqlite3 jq
    elif is_redhat; then
        yum update -y
        install_pkg curl wget git nano unzip htop iptables iproute epel-release sqlite jq
    fi

    # 限制系统日志最大 100M
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    
    # 设置时区为上海
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    
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
        echo -e "${BLUE}  0. 返回上一级菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local fw_choice
        read -p "👉 请选择操作: " fw_choice
        
        case $fw_choice in
            1)
                echo -e "${CYAN}👉 正在嗅探活动端口并配置防火墙...${PLAIN}"
                local active_ports
                active_ports=$(ss -tuln | grep -E 'LISTEN|UNCONN' | grep -v '127.0.0.1' | awk '{print $5}' | rev | cut -d: -f1 | rev | sort -nu | grep -E '^[0-9]+$')
                
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
                read -p "👉 请输入要放行的端口号: " add_p
                
                # 放宽正则，允许数字、逗号、冒号和减号
                if [[ -n "$add_p" && "$add_p" =~ ^[0-9]+([,:-][0-9]+)*$ ]]; then
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
                    echo -e "${RED}❌ 无效的输入格式！请确保只包含数字、逗号、减号或冒号。${PLAIN}"
                fi
                sleep 2
                ;;
            3)
                local del_p
                echo -e "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}"
                read -p "👉 请输入要删除放行的端口号: " del_p
                
                if [[ -n "$del_p" && "$del_p" =~ ^[0-9]+([,:-][0-9]+)*$ ]]; then
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
                    echo -e "${RED}❌ 无效的输入格式！请确保只包含数字、逗号、减号或冒号。${PLAIN}"
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
                echo -e "${RED}⚠️ 正在关闭防火墙...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    ufw disable >/dev/null 2>&1
                else
                    systemctl disable --now firewalld >/dev/null 2>&1
                fi
                echo -e "${GREEN}✅ 防火墙已彻底禁用！${PLAIN}"
                sleep 2
                ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
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

        # 完美修复：一字不落的菜单显示
        echo -e "${GREEN}  1. IPv6 开关${PLAIN}              当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. IPv4 出站优先${PLAIN}          当前: [ $str_ipv4_first ]"
        echo -e "${GREEN}  3. Ping 响应开关${PLAIN}          当前: [ $str_ping ]"
        echo -e "${GREEN}  4. 自动安全更新开关${PLAIN}       当前: [ $str_update ]"
        echo -e "${GREEN}  5. 清理系统垃圾${PLAIN}           (日志/缓存/无用包)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local tweak_choice
        read -p "👉 请选择操作: " tweak_choice
        
        case $tweak_choice in
            1) 
                read -p "❓ 开启 IPv6？(y 开启 / n 关闭): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    rm -f /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1
                    echo -e "${RED}✅ IPv6 已禁用${PLAIN}"
                fi; sleep 1 ;;
            2) 
                read -p "❓ 设置 IPv4 为最高出站优先级？(y 开启 / n 恢复默认): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf
                    echo -e "${GREEN}✅ 已设为 IPv4 优先${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
                    echo -e "${BLUE}已恢复系统默认${PLAIN}"
                fi; sleep 1 ;;
            3) 
                read -p "❓ 允许被 Ping？(y 允许 / n 禁止): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    rm -f /etc/sysctl.d/99-disable-ping.conf
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ 已允许被 Ping${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1
                    echo -e "${RED}✅ 已开启禁 Ping 保护${PLAIN}"
                fi; sleep 1 ;;
            4) 
                read -p "❓ 开启系统自动更新？(y 开启 / n 关闭): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        apt install -y unattended-upgrades -qq >/dev/null 2>&1
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1
                    else
                        yum install -y dnf-automatic -q >/dev/null 2>&1
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1
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
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 统一包管理与执行守卫 (新增：请放在 func_env_install 函数上方)
# ---------------------------------------------------------
run_safe() {
    local desc="$1"
    shift
    echo -e "${CYAN}▶ 正在执行: ${desc}...${PLAIN}"
    # 丢弃正常输出保留错误输出，若执行失败则阻断并告警
    if "$@" >/dev/null; then
        echo -e "${GREEN}✅ ${desc} - 成功！${PLAIN}"
    else
        echo -e "${RED}❌ ${desc} - 失败！请检查系统网络或依赖源。${PLAIN}"
        return 1
    fi
}

download_remote_script() {
    local url="$1"
    local output_file="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 90 "$url" -o "$output_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$output_file" "$url"
    else
        echo -e "${RED}❌ 缺少 curl/wget，无法下载远程脚本。${PLAIN}"
        return 1
    fi
    [[ -s "$output_file" ]]
}

run_remote_script() {
    local desc="$1"
    local url="$2"
    shift 2
    local yn tmp_file rc
    echo -e "${CYAN}▶ ${desc}${PLAIN}"
    echo -e "${YELLOW}脚本来源：${url}${PLAIN}"
    read -p "确认下载并执行该远程脚本？(y/N): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}已取消执行。${PLAIN}"
        return 1
    fi

    tmp_file=$(mktemp /tmp/vps-remote.XXXXXX.sh)
    if ! download_remote_script "$url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败，请检查网络或脚本来源。${PLAIN}"
        return 1
    fi
    if ! bash -n "$tmp_file" >/dev/null 2>&1; then
        echo -e "${RED}❌ 远程脚本未通过 Bash 语法检查，已中止执行。${PLAIN}"
        echo -e "${YELLOW}已保留下载文件用于排查：${tmp_file}${PLAIN}"
        return 1
    fi

    chmod +x "$tmp_file"
    bash "$tmp_file" "$@"
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

pause_after_external_script() {
    local prompt="${1:-按回车键继续...}"
    local junk

    if [[ -r /dev/tty ]]; then
        while IFS= read -r -s -n 1 -t 0.05 junk < /dev/tty; do :; done
        read -r -p "$prompt" junk < /dev/tty
    else
        read -r -p "$prompt" junk
    fi
}

install_acme_sh() {
    local acme_email="$1"
    local tmp_file rc
    tmp_file=$(mktemp /tmp/vps-acme.XXXXXX.sh)
    echo -e "${CYAN}▶ 正在安装 acme.sh...${PLAIN}"
    if ! download_remote_script "https://get.acme.sh" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ acme.sh 安装脚本下载失败。${PLAIN}"
        return 1
    fi
    if ! sh -n "$tmp_file" >/dev/null 2>&1; then
        echo -e "${RED}❌ acme.sh 安装脚本未通过 sh 语法检查，已中止。${PLAIN}"
        echo -e "${YELLOW}已保留下载文件用于排查：${tmp_file}${PLAIN}"
        return 1
    fi
    sh "$tmp_file" "email=${acme_email}" >/dev/null 2>&1
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

is_valid_domain() {
    local domain="$1"
    echo "$domain" | grep -Eq '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
}

get_acme_account_email() {
    local account_conf="/root/.acme.sh/account.conf"
    if [[ -f "$account_conf" ]]; then
        local existing_email
        existing_email=$(grep '^ACCOUNT_EMAIL=' "$account_conf" 2>/dev/null | cut -d"'" -f2 | cut -d'"' -f2)
        if echo "$existing_email" | grep -Eq '^[a-zA-Z0-9._%+-]+@(gmail\.com|outlook\.com|yahoo\.com|hotmail\.com)$'; then
            echo "$existing_email"
            return
        fi
    fi

    local prefix
    prefix=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 12 2>/dev/null || echo "user$RANDOM$RANDOM")
    local domains=("gmail.com" "outlook.com" "yahoo.com" "hotmail.com")
    local domain="${domains[$((RANDOM % ${#domains[@]}))]}"
    echo "${prefix}@${domain}"
}

prepare_acme_account() {
    local acme_bin="$1"
    local acme_email="$2"
    local account_log="${3:-/tmp/vps_acme_account_$(date +%s).log}"
    local account_conf="/root/.acme.sh/account.conf"
    local le_ca_dir="/root/.acme.sh/ca/acme-v02.api.letsencrypt.org"

    if [[ ! -x "$acme_bin" ]]; then
        return 1
    fi

    mkdir -p /root/.acme.sh
    if [[ -f "$account_conf" ]]; then
        if grep -q '^ACCOUNT_EMAIL=' "$account_conf"; then
            sed -i "s|^ACCOUNT_EMAIL=.*|ACCOUNT_EMAIL='${acme_email}'|" "$account_conf"
        else
            printf "ACCOUNT_EMAIL='%s'\n" "$acme_email" >> "$account_conf"
        fi
    else
        printf "ACCOUNT_EMAIL='%s'\n" "$acme_email" > "$account_conf"
    fi

    export ACCOUNT_EMAIL="$acme_email"
    "$acme_bin" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

    if "$acme_bin" --register-account --server letsencrypt --accountemail "$acme_email" >"$account_log" 2>&1 || \
       "$acme_bin" --register-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt --accountemail "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1; then
        return 0
    fi

    # 若历史账户状态异常（例如旧邮箱残留），清理 LE 账户缓存后重试。
    rm -rf "$le_ca_dir" "/root/.acme.sh/ca/acme-staging-v02.api.letsencrypt.org" >/dev/null 2>&1 || true
    if "$acme_bin" --register-account --server letsencrypt --accountemail "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --register-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt --accountemail "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1; then
        return 0
    fi

    return 1
}

quarantine_legacy_caddy_443_configs() {
    local conf_dir="/etc/caddy/conf.d"
    local quarantine_dir="/etc/caddy/conf.d_quarantine_443_$(date +%s)"
    local moved_count=0

    if [[ ! -d "$conf_dir" ]]; then
        return 0
    fi

    while IFS= read -r conf_file; do
        local first_site_line
        first_site_line=$(grep -m1 -E '^[[:space:]]*[^#[:space:]].*\{' "$conf_file" 2>/dev/null | sed 's/^[[:space:]]*//')

        [[ -z "$first_site_line" ]] && continue

        # Reality+CF 向导的新规范：https://domain:port { + bind 127.0.0.1
        if [[ "$first_site_line" =~ ^https://[^[:space:]]+:[0-9]+[[:space:]]*\{ ]]; then
            continue
        fi

        mkdir -p "$quarantine_dir"
        mv "$conf_file" "$quarantine_dir/" >/dev/null 2>&1
        ((moved_count++))
    done < <(find "$conf_dir" -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)

    if [[ "$moved_count" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已自动隔离 ${moved_count} 个旧站点配置（可能抢占 443）到：${quarantine_dir}${PLAIN}"
    fi
}

issue_cf_dns_cert_with_retry() {
    local domain="$1"
    local cf_token_raw="$2"
    local acme_bin="$3"
    local cf_token
    local acme_log
    local acme_email

    cf_token=$(echo "$cf_token_raw" | tr -d '\r\n')
    if [[ -z "$cf_token" || ! -x "$acme_bin" || -z "$domain" ]]; then
        return 1
    fi

    acme_log="/tmp/vps_acme_${domain}_$(date +%s).log"
    acme_email=$(get_acme_account_email)

    # 强制使用 Let's Encrypt，避免 ZeroSSL 触发 EAB 依赖导致签发失败。
    if ! prepare_acme_account "$acme_bin" "$acme_email" "$acme_log"; then
        mkdir -p /root/cert
        cp -f "$acme_log" /root/cert/acme_last_error.log >/dev/null 2>&1 || true
        echo -e "${RED}❌ acme 账户初始化失败：${domain}${PLAIN}"
        echo -e "${YELLOW}   最近错误日志: /root/cert/acme_last_error.log${PLAIN}"
        local account_hint
        account_hint=$(grep -Ei 'error|invalid|unauthorized|forbidden|failed|contact|account' "$acme_log" | tail -n 12)
        if [[ -n "$account_hint" ]]; then
            echo -e "${YELLOW}   关键报错如下：${PLAIN}"
            echo "$account_hint"
        fi
        return 1
    fi

    if CF_Token="$cf_token" "$acme_bin" --issue --server letsencrypt --dns dns_cf -d "$domain" --keylength ec-256 >"$acme_log" 2>&1; then
        return 0
    fi

    # 旧残留常导致“删除后重签失败”，先清理历史状态再强制签发。
    "$acme_bin" --remove -d "$domain" --ecc >/dev/null 2>&1 || true
    rm -rf "/root/.acme.sh/${domain}_ecc" >/dev/null 2>&1 || true
    rm -rf "/root/.acme.sh/${domain}" >/dev/null 2>&1 || true

    if CF_Token="$cf_token" "$acme_bin" --issue --server letsencrypt --dns dns_cf -d "$domain" --keylength ec-256 --force >>"$acme_log" 2>&1; then
        return 0
    fi

    if CF_Token="$cf_token" "$acme_bin" --renew --server letsencrypt -d "$domain" --force --ecc >>"$acme_log" 2>&1; then
        return 0
    fi

    mkdir -p /root/cert
    cp -f "$acme_log" /root/cert/acme_last_error.log >/dev/null 2>&1 || true
    echo -e "${RED}❌ acme.sh 最终失败：${domain}${PLAIN}"
    echo -e "${YELLOW}   最近错误日志: /root/cert/acme_last_error.log${PLAIN}"

    local acme_hint
    acme_hint=$(grep -Ei 'error|invalid|unauthorized|forbidden|failed|timeout|SERVFAIL|NXDOMAIN|permission' "$acme_log" | tail -n 12)
    if [[ -n "$acme_hint" ]]; then
        echo -e "${YELLOW}   关键报错如下：${PLAIN}"
        echo "$acme_hint"
    else
        echo -e "${YELLOW}   未提取到关键错误，展示日志尾部：${PLAIN}"
        tail -n 12 "$acme_log"
    fi

    return 1
}

verify_cf_token_online() {
    local cf_token_raw="$1"
    local cf_token
    local verify_resp

    cf_token=$(echo "$cf_token_raw" | tr -d '\r\n')
    if [[ -z "$cf_token" ]]; then
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        return 2
    fi

    verify_resp=$(curl -s --max-time 10 -H "Authorization: Bearer ${cf_token}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
    if echo "$verify_resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
        return 0
    fi
    return 1
}

generate_caddy_cf_manifest() {
    local summary_file="/root/cert/caddy_cf_manifest.txt"
    mkdir -p /root/cert
    : > "$summary_file"
    echo "Caddy CF DNS 自动化清单 - $(date '+%F %T')" >> "$summary_file"
    echo "------------------------------------------------" >> "$summary_file"

    local found=false
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            local domain
            local listen_port
            local backend
            domain=$(basename "$conf_file" .caddy)

            if [[ ! -f "/etc/caddy/certs/${domain}.crt" || ! -f "/etc/caddy/certs/${domain}.key" ]]; then
                continue
            fi

            listen_port=$(sed -n '1{s@^https://[^:]*:\([0-9]\+\)[[:space:]]*{.*$@\1@p;q}' "$conf_file")
            backend=$(grep -E '^[[:space:]]*reverse_proxy[[:space:]]+127.0.0.1:[0-9]+' "$conf_file" | awk '{print $2}' | head -n1)

            [[ -z "$listen_port" ]] && listen_port="未知"
            [[ -z "$backend" ]] && backend="未知"

            echo "域名: ${domain}" >> "$summary_file"
            echo "  后端: ${backend}" >> "$summary_file"
            echo "  Caddy监听: 127.0.0.1:${listen_port}" >> "$summary_file"
            echo "  证书CRT: /root/cert/${domain}.crt" >> "$summary_file"
            echo "  证书KEY: /root/cert/${domain}.key" >> "$summary_file"
            echo "  配置文件: ${conf_file}" >> "$summary_file"
            echo "------------------------------------------------" >> "$summary_file"
            found=true
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi

    if ! $found; then
        echo "当前未检测到可管理的 CF DNS 站点配置。" >> "$summary_file"
        echo "------------------------------------------------" >> "$summary_file"
    fi
}

# ---------------------------------------------------------
# 3. 常用环境及软件 (重构版：防覆盖、严格容错、剔除静默失败)
# ---------------------------------------------------------
func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📦 软件安装与反代分流中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}${BLUE}▶ 基础运行环境${PLAIN}"
        echo -e "${GREEN}  1. Docker 引擎        ${YELLOW}  2. Python 环境        ${GREEN}  3. iperf3 测速工具${PLAIN}"
        echo -e "${BOLD}${BLUE}▶ 转发、隧道与常用服务${PLAIN}"
        echo -e "${GREEN}  4. Realm 端口转发     ${YELLOW}  5. Gost 隧道          ${GREEN}  6. 极光面板${PLAIN}"
        echo -e "${GREEN}  7. 哪吒监控           ${YELLOW}  8. WARP 解锁/网络     ${GREEN}  9. Aria2 下载${PLAIN}"
        echo -e "${GREEN} 10. 宝塔面板           ${YELLOW} 11. PVE 虚拟化工具     ${GREEN} 12. Argox 节点${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ Caddy 普通反代${PLAIN}"
        echo -e "${CYAN} 13. 普通 Caddy 反代${PLAIN}          ${YELLOW}(适合普通网站/面板反代，不是 443 单入口)${PLAIN}"
        echo -e "${CYAN} 14. 查看 Caddy 证书路径${PLAIN}       ${YELLOW}(查看证书和私钥位置)${PLAIN}"
        echo -e "${CYAN} 15. Caddy 跳过后端证书校验${PLAIN}   ${YELLOW}(后端自签 HTTPS 时使用)${PLAIN}"
        echo -e "${CYAN} 16. 清空 Caddy 配置${PLAIN}           ${YELLOW}(危险操作，清理反代配置)${PLAIN}"
        echo -e "${RED} 17. 删除底层 ACME 证书${PLAIN}        ${YELLOW}(危险操作，清理签发记录)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 443 单入口分流${PLAIN} ${YELLOW}(推荐：Nginx Stream + Caddy + REALITY)${PLAIN}"
        echo -e "${GREEN} 18. 首次配置 443 单入口${PLAIN}       ${YELLOW}(面板/订阅/REALITY/网站共用公网 443)${PLAIN}"
        echo -e "${GREEN} 19. 443 单入口维护中心${PLAIN}        ${YELLOW}(体检/重签/修复/回滚/订阅提示)${PLAIN}"
        echo -e "${GREEN} 20. 管理 443 网站/反代${PLAIN}        ${YELLOW}(后续新增/删除网站，不重跑完整向导)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local env_choice
        read -p "👉 选择: " env_choice
        
        case $env_choice in
            1) 
                echo -e "${CYAN}▶ 正在拉取 Docker 引擎...${PLAIN}"
                run_remote_script "安装 Docker 引擎" "https://get.docker.com" || echo -e "${RED}❌ Docker 安装失败，请检查网络！${PLAIN}"
                ;;
            2) run_remote_script "安装 Python 环境" "https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh" ;;
            3) 
                if is_debian; then run_safe "安装 iperf3" apt install iperf3 -y; else run_safe "安装 iperf3" yum install iperf3 -y; fi 
                ;;
            4) run_remote_script "安装 Realm 端口转发" "https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh" -i ;;
            5) run_remote_script "安装 Gost 隧道" "https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh" ;;
            6) run_remote_script "安装极光面板" "https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh" ;;
            7) 
                if run_remote_script "安装哪吒监控" "https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh"; then
                    echo -e "\n${YELLOW}💡 哪吒自定义代码提示 (去除动效并固定顶部)：${PLAIN}"
                    echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
                fi
                ;;
            8) run_remote_script "安装 WARP 解锁/网络工具" "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" ;;
            9) run_remote_script "安装 Aria2 下载工具" "https://git.io/aria2.sh" ;;
            10) run_remote_script "安装宝塔面板" "http://v7.hostcli.com/install/install-ubuntu_6.0.sh" ;;
            11) run_remote_script "安装 PVE 虚拟化工具" "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh" ;;
            12) run_remote_script "安装 Argox 节点" "https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh" ;;
            13)
                echo -e "${CYAN}▶ 正在检查并安装 Caddy...${PLAIN}"
                if ! command -v caddy >/dev/null 2>&1; then
                    if is_debian; then 
                        apt install -y debian-keyring debian-archive-keyring apt-transport-https -qq >/dev/null 2>&1
                        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
                        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
                        apt update -qq && apt install caddy -y >/dev/null 2>&1
                    else 
                        yum install -y yum-utils >/dev/null 2>&1 && yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo >/dev/null 2>&1 && yum install caddy -y >/dev/null 2>&1
                    fi
                fi
                
                mkdir -p /etc/caddy/conf.d
                if [[ -f /etc/caddy/Caddyfile ]] && ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
                    echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
                fi
                
                local domain port is_https
                read -p "请输入解析后的域名 (如 panel.site.com): " domain
                read -p "请输入面板本地映射端口 (如 40000): " port
                domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
                
                # 增加了端口只能是纯数字的防呆校验
                if ! is_valid_domain "$domain" || ! is_valid_port "$port"; then
                    echo -e "${RED}❌ 域名或端口格式错误！域名不要带 http(s)://、路径或端口，端口必须是 1-65535。${PLAIN}"
                else
                    # 严谨的冲突判定，同时检查 Caddyfile 和 conf.d 目录
                    if grep -q "^[[:space:]]*$domain" /etc/caddy/Caddyfile 2>/dev/null || ls /etc/caddy/conf.d/${domain}.caddy >/dev/null 2>&1; then
                        echo -e "${RED}❌ 错误：已存在该域名的配置块！请先使用功能 [17] 彻底清理，然后再添加。${PLAIN}"
                    else
                        read -p "❓ 后端面板是否开启了自带的 SSL 证书？(y/n): " is_https
                        
                        local backup_file="/etc/caddy/Caddyfile.bak_$(date +%s)"
                        [[ -f /etc/caddy/Caddyfile ]] && cp /etc/caddy/Caddyfile "$backup_file"
                        
                        if [[ "$is_https" =~ ^[Yy]$ ]]; then
                            cat <<EOF > "/etc/caddy/conf.d/${domain}.caddy"
$domain {
    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
                        else
                            cat <<EOF > "/etc/caddy/conf.d/${domain}.caddy"
$domain {
    reverse_proxy localhost:$port
}
EOF
                        fi
                        
                        echo -e "${CYAN}▶ 正在校验 Caddy 配置文件...${PLAIN}"
                        if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                            systemctl reload caddy >/dev/null 2>&1
                            echo -e "${GREEN}✅ Caddy 反代配置已追加并生效！请访问 https://$domain${PLAIN}"
                        else
                            echo -e "${RED}❌ 致命错误：生成的配置存在语法异常！正在自动回滚...${PLAIN}"
                            [[ -f "$backup_file" ]] && mv "$backup_file" /etc/caddy/Caddyfile
                            rm -f "/etc/caddy/conf.d/${domain}.caddy" # 核心修复：清理掉错误的模块化文件
                        fi
                    fi
                fi
                ;;
            14) func_view_caddy_cert ;;
            15) func_caddy_add_insecure ;;
            16) func_caddy_clear_config ;;
            17) func_caddy_delete_cert ;;
            18) func_caddy_cf_reality_wizard ;;
            19) func_caddy_cf_maintenance_menu ;;
            20) manage_sni_stack_sites ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}" ;;
        esac
        echo ""
        pause_after_external_script "按回车键继续..."
    done
}

# ---------------------------------------------------------
# 旧版 Reality+CF 向导已禁用，菜单 [18] 使用下方新的 SNI stack 向导。
# ---------------------------------------------------------
func_caddy_cf_reality_wizard_legacy_disabled() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧩 Reality 443 复用 + Cloudflare DNS 自动化向导${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}本向导会让 Caddy 仅监听本地端口，不占用公网 80/443。${PLAIN}"
    echo -e "${YELLOW}推荐用于：3x-ui Reality 已占用 443，同时 Web 服务需要同域名 HTTPS。${PLAIN}"
    echo -e "------------------------------------------------"

    read -p "❓ 当前 443 端口是否已被 3x-ui VLESS-Reality 占用？(y/n): " reality_occupied
    if [[ "$reality_occupied" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}ℹ️ 您选择了未占用 443，本向导仍将使用本地端口模式，避免与未来业务冲突。${PLAIN}"
    fi

    local listen_port
    read -p "👉 请输入 Caddy 本地 TLS 监听端口 (默认 8443): " listen_port
    listen_port=${listen_port:-8443}
    if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [[ "$listen_port" -lt 1 || "$listen_port" -gt 65535 ]]; then
        echo -e "${RED}❌ 监听端口无效！必须是 1-65535 的纯数字。${PLAIN}"
        return
    fi
    if [[ "$reality_occupied" =~ ^[Yy]$ ]] && [[ "$listen_port" -eq 443 ]]; then
        echo -e "${RED}❌ 443 已用于 Reality，请改用本地高位端口 (如 8443/9443)。${PLAIN}"
        return
    fi

    local cf_token
    echo -e "${CYAN}👇 请输入 Cloudflare API Token（需 Zone.DNS 编辑权限）${PLAIN}"
    read -p "CF Token: " cf_token
    echo ""
    if [[ -z "$cf_token" || ${#cf_token} -lt 20 ]]; then
        echo -e "${RED}❌ Token 长度异常，已取消。${PLAIN}"
        return
    fi
    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
    verify_cf_token_online "$cf_token"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "${GREEN}✅ Token 校验通过。${PLAIN}"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
    else
        echo -e "${RED}❌ Token 在线校验失败：请检查权限或确认 Token 未填错。${PLAIN}"
        echo -e "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}"
        return
    fi

    if ! command -v caddy >/dev/null 2>&1; then
        echo -e "${CYAN}▶ 未检测到 Caddy，正在安装...${PLAIN}"
        if is_debian; then
            apt install -y debian-keyring debian-archive-keyring apt-transport-https -qq >/dev/null 2>&1
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
            apt update -qq >/dev/null 2>&1
            apt install caddy -y -qq >/dev/null 2>&1
        elif is_redhat; then
            yum install -y yum-utils -q >/dev/null 2>&1
            yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo >/dev/null 2>&1
            yum install caddy -y -q >/dev/null 2>&1
        fi
    fi
    if ! command -v caddy >/dev/null 2>&1; then
        echo -e "${RED}❌ Caddy 安装失败，请检查网络后重试。${PLAIN}"
        return
    fi

    local acme_bin="/root/.acme.sh/acme.sh"
    local acme_email
    acme_email=$(get_acme_account_email)
    if [[ ! -x "$acme_bin" ]]; then
        if ! install_acme_sh "$acme_email"; then
            echo -e "${RED}❌ acme.sh 安装失败，请检查网络后重试。${PLAIN}"
            return
        fi
    fi
    if [[ ! -x "$acme_bin" ]]; then
        echo -e "${RED}❌ 未找到 acme.sh，可执行文件异常。${PLAIN}"
        return
    fi
    if ! prepare_acme_account "$acme_bin" "$acme_email"; then
        echo -e "${RED}❌ acme 账户初始化失败，请检查邮箱配置后重试。${PLAIN}"
        return
    fi

    local cf_env_dir="/root/.config/vps-panel"
    local cf_env_file="${cf_env_dir}/cloudflare.env"
    mkdir -p "$cf_env_dir"
    chmod 700 "$cf_env_dir"
    local escaped_token
    escaped_token=${cf_token//\'/\'"\'"\'}
    printf "CF_Token='%s'\n" "$escaped_token" > "$cf_env_file"
    chmod 600 "$cf_env_file"

    mkdir -p /etc/caddy/conf.d /etc/caddy/certs /root/cert

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    fi

    echo -e "${CYAN}▶ 正在扫描并隔离旧式 Caddy 配置（防止抢占 443）...${PLAIN}"
    quarantine_legacy_caddy_443_configs

    echo -e "${YELLOW}👇 开始添加域名反代规则（可连续添加多个）${PLAIN}"
    echo -e "${YELLOW}格式：域名 -> 本地端口，例如 panel.example.com -> 8000${PLAIN}"
    echo -e "------------------------------------------------"

    local success_count=0
    local fail_count=0
    local summary_file="/root/cert/caddy_cf_manifest.txt"

    while true; do
        local domain backend_port continue_add
        read -p "👉 请输入域名 (回车结束添加): " domain
        if [[ -z "$domain" ]]; then
            break
        fi

        if ! is_valid_domain "$domain"; then
            echo -e "${RED}❌ 域名格式无效：$domain${PLAIN}"
            ((fail_count++))
            continue
        fi

        read -p "👉 请输入该域名反代的本地端口: " backend_port
        if ! [[ "$backend_port" =~ ^[0-9]+$ ]] || [[ "$backend_port" -lt 1 || "$backend_port" -gt 65535 ]]; then
            echo -e "${RED}❌ 端口无效：$backend_port${PLAIN}"
            ((fail_count++))
            continue
        fi

        local conf_file="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$conf_file" ]]; then
            echo -e "${RED}❌ 已存在域名配置：$conf_file，请先删除后再添加。${PLAIN}"
            ((fail_count++))
            continue
        fi

        # shellcheck disable=SC1090
        source "$cf_env_file"
        echo -e "${CYAN}▶ 正在为 ${domain} 申请 DNS 证书...${PLAIN}"
        if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
            echo -e "${RED}❌ 证书申请失败：${domain}${PLAIN}"
            echo -e "${YELLOW}   提示：可进入 [19]-[9] 一键自动修复后再重试。${PLAIN}"
            ((fail_count++))
            continue
        fi

        local cert_file="/etc/caddy/certs/${domain}.crt"
        local key_file="/etc/caddy/certs/${domain}.key"

        if ! "$acme_bin" --install-cert -d "$domain" --ecc \
            --fullchain-file "$cert_file" \
            --key-file "$key_file" \
            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
            echo -e "${RED}❌ 证书安装失败：${domain}${PLAIN}"
            ((fail_count++))
            continue
        fi

        if id caddy >/dev/null 2>&1; then
            chown root:caddy "$cert_file" "$key_file" >/dev/null 2>&1
            chmod 640 "$cert_file" "$key_file"
        else
            chmod 600 "$cert_file" "$key_file"
        fi

        ln -sfn "$cert_file" "/root/cert/${domain}.crt"
        ln -sfn "$key_file" "/root/cert/${domain}.key"

        cat <<EOF > "$conf_file"
https://${domain}:${listen_port} {
    bind 127.0.0.1
    tls ${cert_file} ${key_file}
    reverse_proxy 127.0.0.1:${backend_port}
}
EOF

        echo -e "${GREEN}✅ 域名 ${domain} 已完成：证书签发 + 反代配置 + 证书挂载。${PLAIN}"
        ((success_count++))

        read -p "继续添加下一个域名？(y/n): " continue_add
        if [[ ! "$continue_add" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    echo -e "${CYAN}▶ 正在校验并加载 Caddy 配置...${PLAIN}"
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl enable caddy >/dev/null 2>&1
        systemctl restart caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ Caddy 已成功重载，配置生效。${PLAIN}"
    else
        echo -e "${RED}❌ Caddy 配置校验失败！请检查 /etc/caddy/conf.d/ 下新增文件语法。${PLAIN}"
        echo -e "${YELLOW}已保留证书文件，您修正配置后可手动执行: systemctl restart caddy${PLAIN}"
    fi

    generate_caddy_cf_manifest

    echo -e "------------------------------------------------"
    echo -e "${GREEN}🎯 向导执行完成：成功 ${success_count} 个，失败 ${fail_count} 个。${PLAIN}"
    echo -e "${CYAN}证书软链接目录:${PLAIN} /root/cert"
    echo -e "${CYAN}清单文件路径:${PLAIN} ${summary_file}"
    echo -e "${YELLOW}💡 3x-ui 手动配置提示：${PLAIN}"
    echo -e "1) 在 Reality 节点里设置 fallback/dest 指向: 127.0.0.1:${listen_port}"
    echo -e "2) 每个回落域名需与本向导录入域名一致，SNI 才能命中对应证书和反代规则"
    echo -e "3) 如业务强依赖真实访客IP，请后续再单独启用 PROXY Protocol 高阶方案"
}

# ---------------------------------------------------------
# 新增功能：CF DNS 证书二次维护菜单
# ---------------------------------------------------------
ask_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input
    read -p "${prompt} (默认: ${default_value}): " input
    echo "${input:-$default_value}"
}

split_csv_to_array() {
    local input="$1"
    local -n out_array=$2
    local idx cleaned
    out_array=()
    local raw_array=()
    IFS=',' read -ra raw_array <<< "$input"
    for idx in "${!raw_array[@]}"; do
        cleaned=$(echo "${raw_array[$idx]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        [[ -n "$cleaned" ]] && out_array+=("$cleaned")
    done
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

is_valid_listen_addr() {
    local addr="$1"
    if [[ "$addr" == "127.0.0.1" || "$addr" == "localhost" || "$addr" == "0.0.0.0" || "$addr" == "::1" || "$addr" == "::" ]]; then
        return 0
    fi
    if [[ "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS=.
        local -a octets=($addr)
        local octet
        for octet in "${octets[@]}"; do
            [[ "$octet" -ge 0 && "$octet" -le 255 ]] || return 1
        done
        return 0
    fi
    return 1
}

warn_if_public_bind() {
    local service_name="$1"
    local listen_addr="$2"
    local listen_port="$3"
    local confirm
    if [[ "$listen_addr" == "0.0.0.0" || "$listen_addr" == "::" ]]; then
        echo -e "${RED}⚠️  高风险：${service_name} 将监听公网 ${listen_addr}:${listen_port}${PLAIN}"
        echo -e "${RED}这会破坏默认的本地监听安全模型，可能导致端口直接暴露。${PLAIN}"
        read -p "如确认继续，请输入 YES: " confirm
        [[ "$confirm" == "YES" ]] || return 1
    fi
    return 0
}

confirm_danger() {
    local title="$1"
    local impact="$2"
    local rollback="$3"
    local confirm
    echo -e "${RED}⚠️ 高风险操作：${title}${PLAIN}"
    echo -e "${YELLOW}影响：${impact}${PLAIN}"
    echo -e "${BLUE}回退：${rollback}${PLAIN}"
    read -p "确认继续请输入 YES: " confirm
    [[ "$confirm" == "YES" ]]
}

format_hostport() {
    local addr="$1"
    local port="$2"
    if [[ "$addr" == "::" || "$addr" == "::1" ]]; then
        echo "[${addr}]:${port}"
    else
        echo "${addr}:${port}"
    fi
}

sni_stack_backup_dir() {
    echo "/etc/vps-optimize/backups/sni-stack_$(date +%Y%m%d_%H%M%S)"
}

create_sni_stack_backup() {
    local backup_dir
    backup_dir=$(sni_stack_backup_dir)
    mkdir -p "$backup_dir/nginx_stream.d" "$backup_dir/caddy_conf.d" "$backup_dir/vps-optimize"
    [[ -f /etc/nginx/nginx.conf ]] && cp -a /etc/nginx/nginx.conf "$backup_dir/nginx.conf" 2>/dev/null || true
    [[ -d /etc/nginx/stream.d ]] && cp -a /etc/nginx/stream.d/vps_sni_*.conf "$backup_dir/nginx_stream.d/" 2>/dev/null || true
    [[ -f /etc/caddy/Caddyfile ]] && cp -a /etc/caddy/Caddyfile "$backup_dir/Caddyfile" 2>/dev/null || true
    [[ -d /etc/caddy/conf.d ]] && cp -a /etc/caddy/conf.d/*.caddy "$backup_dir/caddy_conf.d/" 2>/dev/null || true
    [[ -f /etc/vps-optimize/sni-stack.env ]] && cp -a /etc/vps-optimize/sni-stack.env "$backup_dir/vps-optimize/sni-stack.env" 2>/dev/null || true
    echo "$backup_dir" > /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true
    echo -e "${GREEN}✅ 已创建配置备份：${backup_dir}${PLAIN}"
}

cleanup_old_nginx_sni_stream_configs() {
    mkdir -p /etc/nginx/stream.d
    local old_dir="/etc/nginx/stream.d/backup_vps_sni_$(date +%Y%m%d_%H%M%S)"
    local moved=0
    while IFS= read -r conf_file; do
        mkdir -p "$old_dir"
        mv "$conf_file" "$old_dir/" >/dev/null 2>&1 && ((moved++))
    done < <(find /etc/nginx/stream.d -maxdepth 1 -type f -name 'vps_sni_*.conf' 2>/dev/null | sort)
    if [[ "$moved" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已隔离 ${moved} 个旧 Nginx SNI 配置到：${old_dir}${PLAIN}"
    fi
}

probe_reality_sni() {
    local sni="$1"
    echo -e "${CYAN}▶ 正在检测 REALITY 伪装 SNI 连通性：${sni}:443${PLAIN}"
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 openssl，跳过 SNI 连通性检测。${PLAIN}"
        return 0
    fi
    if timeout 12 openssl s_client -connect "${sni}:443" -servername "$sni" </dev/null 2>/tmp/vps_reality_sni_probe.log | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${GREEN}✅ REALITY SNI 可连通并返回证书。${PLAIN}"
        return 0
    fi
    echo -e "${RED}❌ REALITY SNI 检测失败：${sni}:443 未正常返回证书。${PLAIN}"
    echo -e "${YELLOW}请更换一个外部真实 HTTPS 站点域名，不要使用模板域名或自己的面板域名。${PLAIN}"
    return 1
}

print_sni_stack_preview() {
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}即将写入的 443 单入口分流配置预览${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Nginx stream"
    echo -e "面板域名：${PANEL_DOMAIN} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "网站/反代域名：${SITE_DOMAINS[$i]} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
        done
    fi
    echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "默认/未知 SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e ""
    echo -e "${YELLOW}确认后会备份现有配置，并隔离旧的 /etc/nginx/stream.d/vps_sni_*.conf。${PLAIN}"
    local confirm
    read -p "确认写入并重启 Nginx/Caddy？输入 YES 继续: " confirm
    [[ "$confirm" == "YES" ]]
}

caddy_format_configs() {
    command -v caddy >/dev/null 2>&1 || return 0
    caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            caddy fmt --overwrite "$conf_file" >/dev/null 2>&1 || true
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi
}

load_sni_stack_env() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED}❌ 未找到 ${env_file}，请先运行 [18] 初始化。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$env_file"
    PANEL_INTERNAL_SSL=${PANEL_INTERNAL_SSL:-off}
    normalize_site_stack_arrays
}

normalize_site_stack_arrays() {
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()

    if [[ -n "${SITE_DOMAINS_CSV:-}" ]]; then
        split_csv_to_array "$SITE_DOMAINS_CSV" SITE_DOMAINS
        split_csv_to_array "${SITE_BACKEND_ADDRS_CSV:-}" SITE_BACKEND_ADDRS
        split_csv_to_array "${SITE_BACKEND_PORTS_CSV:-}" SITE_BACKEND_PORTS
    elif [[ -n "${SITE_DOMAIN:-}" ]]; then
        SITE_DOMAINS=("$SITE_DOMAIN")
        SITE_BACKEND_ADDRS=("${SITE_BACKEND_ADDR:-127.0.0.1}")
        SITE_BACKEND_PORTS=("${SITE_BACKEND_PORT:-3000}")
    fi

    local i default_port
    default_port=3000
    for i in "${!SITE_DOMAINS[@]}"; do
        SITE_BACKEND_ADDRS[$i]="${SITE_BACKEND_ADDRS[$i]:-127.0.0.1}"
        SITE_BACKEND_PORTS[$i]="${SITE_BACKEND_PORTS[$i]:-$default_port}"
        default_port=$((default_port + 1))
    done

    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
}

sni_stack_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 443 单入口分流链路体检${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local ok=0 warn=0 fail=0
    check_listen() {
        local name="$1"
        local port="$2"
        local expect_addr="$3"
        if ss -lntp 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            local line
            line=$(ss -lntp 2>/dev/null | grep ":${port}[[:space:]]" | head -n1)
            echo -e "${GREEN}✅ ${name} 端口 ${port} 有监听：${line}${PLAIN}"
            if [[ -n "$expect_addr" ]] && ! echo "$line" | grep -q "$expect_addr"; then
                echo -e "${YELLOW}⚠️ ${name} 期望监听 ${expect_addr}:${port}，请确认是否被改成公网监听。${PLAIN}"
                ((warn++))
            else
                ((ok++))
            fi
        else
            echo -e "${RED}❌ ${name} 端口 ${port} 未监听。${PLAIN}"
            ((fail++))
        fi
    }

    check_listen "Nginx 公网入口" "$NGINX_LISTEN_PORT" ""
    check_listen "Caddy 本地 TLS" "$CADDY_LISTEN_PORT" "$CADDY_LISTEN_ADDR"
    check_listen "Xray/3x-ui REALITY" "$XRAY_LISTEN_PORT" "$XRAY_LISTEN_ADDR"
    check_listen "3x-ui 面板" "$PANEL_LISTEN_PORT" "$PANEL_LISTEN_ADDR"
    check_listen "3x-ui 订阅" "$SUB_LISTEN_PORT" "$SUB_LISTEN_ADDR"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            check_listen "网站后端 ${SITE_DOMAINS[$i]}" "${SITE_BACKEND_PORTS[$i]}" "${SITE_BACKEND_ADDRS[$i]}"
        done
    fi

    echo -e "------------------------------------------------"
    nginx -t >/dev/null 2>&1 && echo -e "${GREEN}✅ nginx -t 通过${PLAIN}" && ((ok++)) || { echo -e "${RED}❌ nginx -t 失败${PLAIN}"; ((fail++)); }
    caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && echo -e "${GREEN}✅ Caddy 配置校验通过${PLAIN}" && ((ok++)) || { echo -e "${RED}❌ Caddy 配置校验失败${PLAIN}"; ((fail++)); }
    if grep -Eq '^[[:space:]]*server_tokens[[:space:]]+off;' /etc/nginx/nginx.conf 2>/dev/null; then
        echo -e "${GREEN}✅ Nginx 已关闭版本号显示 server_tokens off${PLAIN}"
        ((ok++))
    else
        echo -e "${YELLOW}⚠️ 未确认 Nginx server_tokens off，错误页可能显示版本号。${PLAIN}"
        ((warn++))
    fi
    if [[ -f /etc/nginx/conf.d/00-vps-default-drop.conf ]]; then
        echo -e "${GREEN}✅ Nginx 80 默认站点已设置为丢弃连接${PLAIN}"
        ((ok++))
    else
        echo -e "${YELLOW}⚠️ 未找到 80 默认丢弃配置，错误域名可能命中默认页。${PLAIN}"
        ((warn++))
    fi

    if command -v openssl >/dev/null 2>&1; then
        if timeout 10 openssl s_client -connect "127.0.0.1:${NGINX_LISTEN_PORT}" -servername "$PANEL_DOMAIN" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
            echo -e "${GREEN}✅ 面板 SNI 可从 Nginx 命中 Caddy 证书链${PLAIN}"
            ((ok++))
        else
            echo -e "${YELLOW}⚠️ 面板 SNI 测试未拿到证书，请检查 Nginx stream 与 Caddy。${PLAIN}"
            ((warn++))
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "体检结果：${GREEN}通过 ${ok}${PLAIN} / ${YELLOW}警告 ${warn}${PLAIN} / ${RED}失败 ${fail}${PLAIN}"
}

check_sni_stack_subscription_hint() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔎 订阅端口与 External Proxy 检查提示${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "请在 3x-ui 的 REALITY 入站里开启 External Proxy，并确保："
    echo -e "  类型：相同"
    echo -e "  地址：你的节点域名或服务器 IP"
    echo -e "  端口：${NGINX_LISTEN_PORT}"
    echo -e ""
    echo -e "复制节点链接后应该看到："
    echo -e "  vless://...@节点地址:${NGINX_LISTEN_PORT}?security=reality&sni=${REALITY_SNI}&..."
    echo -e ""
    echo -e "${YELLOW}如果链接里还是 :${XRAY_LISTEN_PORT}，说明 3x-ui 订阅仍在输出本地入站端口，请回到入站设置检查 External Proxy。${PLAIN}"
}

reapply_sni_stack_from_env() {
    load_sni_stack_env || return 1
    print_sni_stack_preview || return 1
    create_sni_stack_backup
    install_nginx_stream_stack || return 1
    harden_nginx_public_errors
    ensure_caddy_local_base_config || return 1
    cleanup_old_nginx_sni_stream_configs
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    write_nginx_sni_stream_config || return 1
    systemctl restart caddy || return 1
    systemctl restart nginx || return 1
    print_sni_stack_result
}

rollback_sni_stack_config() {
    local backup_dir
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        backup_dir=$(find /etc/vps-optimize/backups -maxdepth 1 -type d -name 'sni-stack_*' 2>/dev/null | sort | tail -n1)
    fi
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        echo -e "${RED}❌ 未找到可回滚的 SNI stack 备份。${PLAIN}"
        return 1
    fi
    echo -e "${YELLOW}即将回滚到备份：${backup_dir}${PLAIN}"
    local confirm
    read -p "这会覆盖当前 Nginx/Caddy 的相关配置，输入 YES 继续: " confirm
    [[ "$confirm" == "YES" ]] || return 1

    [[ -f "$backup_dir/nginx.conf" ]] && cp -a "$backup_dir/nginx.conf" /etc/nginx/nginx.conf
    mkdir -p /etc/nginx/stream.d /etc/caddy/conf.d
    rm -f /etc/nginx/stream.d/vps_sni_*.conf 2>/dev/null || true
    cp -a "$backup_dir/nginx_stream.d/"*.conf /etc/nginx/stream.d/ 2>/dev/null || true
    [[ -f "$backup_dir/Caddyfile" ]] && cp -a "$backup_dir/Caddyfile" /etc/caddy/Caddyfile
    if [[ -d "$backup_dir/caddy_conf.d" ]]; then
        cp -a "$backup_dir/caddy_conf.d/"*.caddy /etc/caddy/conf.d/ 2>/dev/null || true
    fi
    [[ -f "$backup_dir/vps-optimize/sni-stack.env" ]] && cp -a "$backup_dir/vps-optimize/sni-stack.env" /etc/vps-optimize/sni-stack.env

    nginx -t && caddy validate --config /etc/caddy/Caddyfile && {
        systemctl restart nginx >/dev/null 2>&1 || true
        systemctl restart caddy >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ 回滚完成。${PLAIN}"
    }
}

collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Nginx Stream + Caddy + REALITY 443 单入口分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}公网 443 只允许 Nginx stream 监听；Caddy/Xray/3x-ui 默认全部绑定 127.0.0.1。${PLAIN}"
    echo -e "------------------------------------------------"

    read -p "面板域名（必填，例如 panel.example.com）: " PANEL_DOMAIN
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()
    local site_domains_input
    site_domains_input=$(ask_with_default "网站/反代域名（可选，多个用英文逗号分隔，例如 site1.example.com,site2.example.com）" "")
    split_csv_to_array "$site_domains_input" SITE_DOMAINS
    echo -e "${YELLOW}REALITY 伪装 SNI 请填写外部真实 HTTPS 站点域名，不要填写面板域名或节点域名。${PLAIN}"
    echo -e "${YELLOW}模板示例：your-reality-sni.example.com（请替换成你自己选择的真实站点）${PLAIN}"
    read -p "REALITY 伪装 SNI（必填）: " REALITY_SNI
    NGINX_LISTEN_ADDR=$(ask_with_default "Nginx 公网监听地址" "0.0.0.0")
    NGINX_LISTEN_PORT=$(ask_with_default "Nginx 公网监听端口" "443")

    local advanced_mode
    read -p "是否进入高级模式并允许修改本地服务监听地址？(y/n，默认 n): " advanced_mode
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        CADDY_LISTEN_ADDR=$(ask_with_default "Caddy 本地监听地址" "127.0.0.1")
        XRAY_LISTEN_ADDR=$(ask_with_default "Xray REALITY 本地监听地址" "127.0.0.1")
        PANEL_LISTEN_ADDR=$(ask_with_default "3x-ui 面板监听地址" "127.0.0.1")
        SUB_LISTEN_ADDR=$(ask_with_default "3x-ui 订阅服务监听地址" "127.0.0.1")
    else
        CADDY_LISTEN_ADDR="127.0.0.1"
        XRAY_LISTEN_ADDR="127.0.0.1"
        PANEL_LISTEN_ADDR="127.0.0.1"
        SUB_LISTEN_ADDR="127.0.0.1"
        echo -e "${GREEN}普通模式：Caddy/Xray/3x-ui/订阅/网站后端均使用 127.0.0.1。${PLAIN}"
    fi

    CADDY_LISTEN_PORT=$(ask_with_default "Caddy 本地监听端口" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "Xray REALITY 本地监听端口" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "3x-ui 面板端口" "40000")
    SUB_LISTEN_PORT=$(ask_with_default "3x-ui 订阅服务端口（若与面板同端口请输入 40000）" "2096")
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i default_site_port
        default_site_port=3000
        for i in "${!SITE_DOMAINS[@]}"; do
            if [[ -z "${SITE_DOMAINS[$i]}" ]]; then
                continue
            fi
            if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端监听地址" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端端口" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    PANEL_INTERNAL_SSL="off"
    local panel_ssl_enabled
    read -p "3x-ui 面板是否已经开启内置 SSL/填写证书路径？(y/n，默认 n): " panel_ssl_enabled
    if [[ "$panel_ssl_enabled" =~ ^[Yy]$ ]]; then
        PANEL_INTERNAL_SSL="on"
        echo -e "${RED}⚠️  当前架构要求 3x-ui 面板关闭内置 SSL，证书只给 Caddy 使用。${PLAIN}"
        echo -e "${YELLOW}如果 3x-ui 继续启用 SSL，Caddy 默认会用 HTTP 连接 HTTPS 后端，常见结果是 502 或面板打不开。${PLAIN}"
        read -p "请确认稍后会在 3x-ui 中关闭面板 SSL 并清空证书路径，输入 YES 继续: " panel_ssl_confirm
        [[ "$panel_ssl_confirm" == "YES" ]] || return 1
    fi

    echo -e "${CYAN}请输入 Cloudflare API Token（需 Zone.DNS.Edit + Zone.Zone.Read）${PLAIN}"
    read -p "CF Token: " CF_TOKEN

    PANEL_DOMAIN=$(echo "$PANEL_DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    REALITY_SNI=$(echo "$REALITY_SNI" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    if ! is_valid_domain "$PANEL_DOMAIN"; then echo -e "${RED}❌ 面板域名无效。${PLAIN}"; return 1; fi
    if ! is_valid_domain "$REALITY_SNI"; then echo -e "${RED}❌ REALITY SNI 无效。${PLAIN}"; return 1; fi
    local site_domain seen_domains
    seen_domains=" ${PANEL_DOMAIN} ${REALITY_SNI} "
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -z "$site_domain" ]] && continue
        if ! is_valid_domain "$site_domain"; then echo -e "${RED}❌ 网站/反代域名无效：${site_domain}${PLAIN}"; return 1; fi
        if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" || "$seen_domains" == *" ${site_domain} "* ]]; then
            echo -e "${RED}❌ 面板域名、网站/反代域名、REALITY SNI 不能相同：${site_domain}${PLAIN}"
            return 1
        fi
        seen_domains+=" ${site_domain} "
    done

    local p a
    for p in "$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}"; do
        is_valid_port "$p" || { echo -e "${RED}❌ 端口无效：${p}${PLAIN}"; return 1; }
    done
    for a in "$NGINX_LISTEN_ADDR" "$CADDY_LISTEN_ADDR" "$XRAY_LISTEN_ADDR" "$PANEL_LISTEN_ADDR" "$SUB_LISTEN_ADDR" "${SITE_BACKEND_ADDRS[@]}"; do
        is_valid_listen_addr "$a" || { echo -e "${RED}❌ 监听地址无效：${a}${PLAIN}"; return 1; }
    done
    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
    [[ "$NGINX_LISTEN_PORT" != "443" ]] && echo -e "${YELLOW}⚠️  Nginx 公网端口不是 443，不推荐。${PLAIN}"

    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 面板" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 订阅服务" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then echo -e "${RED}❌ Cloudflare Token 长度异常。${PLAIN}"; return 1; fi
    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
    verify_cf_token_online "$CF_TOKEN"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
    else
        echo -e "${RED}❌ Cloudflare Token 校验失败。${PLAIN}"
        return 1
    fi
}

install_caddy_if_needed() {
    command -v caddy >/dev/null 2>&1 && return 0
    echo -e "${CYAN}▶ 未检测到 Caddy，正在安装...${PLAIN}"
    if is_debian; then
        install_pkg debian-keyring debian-archive-keyring apt-transport-https curl gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
        install_pkg caddy
    elif is_redhat; then
        install_pkg yum-utils
        yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo >/dev/null 2>&1 || true
        install_pkg caddy
    fi
    command -v caddy >/dev/null 2>&1
}

install_nginx_stream_stack() {
    echo -e "${CYAN}▶ 正在安装 Nginx stream 组件...${PLAIN}"
    if is_debian; then
        install_pkg nginx libnginx-mod-stream
    elif is_redhat; then
        install_pkg nginx
        yum install -y -q nginx-mod-stream >/dev/null 2>&1 || true
    fi
    command -v nginx >/dev/null 2>&1 || { echo -e "${RED}❌ Nginx 安装失败。${PLAIN}"; return 1; }
    mkdir -p /etc/nginx/stream.d
    if ! grep -Eq '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        cat <<'EOF' >> /etc/nginx/nginx.conf

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF
    elif ! grep -q '/etc/nginx/stream.d/\*.conf' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        sed -i '/^[[:space:]]*stream[[:space:]]*{/a\    include /etc/nginx/stream.d/*.conf;' /etc/nginx/nginx.conf
    fi
}

harden_nginx_public_errors() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local drop_conf="/etc/nginx/conf.d/00-vps-default-drop.conf"
    local quarantine_dir="/etc/vps-optimize/nginx-default-sites-disabled_$(date +%s)"
    local moved=0
    local default_file

    command -v nginx >/dev/null 2>&1 || return 0
    mkdir -p /etc/nginx/conf.d /etc/vps-optimize

    if [[ -f "$nginx_conf" ]]; then
        if grep -Eq '^[#[:space:]]*server_tokens[[:space:]]+' "$nginx_conf"; then
            sed -i 's/^[#[:space:]]*server_tokens[[:space:]].*;/    server_tokens off;/' "$nginx_conf"
        elif grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$nginx_conf"; then
            sed -i '/^[[:space:]]*http[[:space:]]*{/a\    server_tokens off;' "$nginx_conf"
        fi
    fi

    for default_file in \
        /etc/nginx/sites-enabled/default \
        /etc/nginx/sites-available/default \
        /etc/nginx/conf.d/default.conf; do
        if [[ -e "$default_file" ]]; then
            mkdir -p "$quarantine_dir"
            mv "$default_file" "$quarantine_dir/" >/dev/null 2>&1 && ((moved++))
        fi
    done

    cat <<'EOF' > "$drop_conf"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
EOF

    if [[ "$moved" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已隔离 ${moved} 个 Nginx 默认站点配置到：${quarantine_dir}${PLAIN}"
    fi
    echo -e "${GREEN}✅ 已关闭 Nginx 版本号显示，并写入 80 端口默认丢弃规则。${PLAIN}"
}

write_nginx_sni_stream_config() {
    local conf_file="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    local first_listen="listen ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT};"
    local second_listen="    listen [::]:${NGINX_LISTEN_PORT};"
    local caddy_backend
    local xray_backend
    [[ "$NGINX_LISTEN_ADDR" == "::" || "$NGINX_LISTEN_ADDR" == "::1" ]] && first_listen="listen [${NGINX_LISTEN_ADDR}]:${NGINX_LISTEN_PORT};"
    [[ "$NGINX_LISTEN_ADDR" == "::" ]] && second_listen=""
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    cat <<EOF > "$conf_file"
map \$ssl_preread_server_name \$vps_sni_backend {
    ${PANEL_DOMAIN} caddy_backend;
EOF
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local site_domain
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -n "$site_domain" ]] && echo "    ${site_domain} caddy_backend;" >> "$conf_file"
        done
    fi
    cat <<EOF >> "$conf_file"
    ${REALITY_SNI} xray_backend;
    default xray_backend;
}

upstream caddy_backend {
    server ${caddy_backend};
}

upstream xray_backend {
    server ${xray_backend};
}

server {
    ${first_listen}
${second_listen}
    ssl_preread on;
    proxy_pass \$vps_sni_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 24h;
}
EOF
    nginx -t
}

ensure_caddy_local_base_config() {
    install_caddy_if_needed || return 1
    mkdir -p /etc/caddy/conf.d /etc/caddy/certs
    cp -f /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null || true
    cat <<'EOF' > /etc/caddy/Caddyfile
{
    auto_https off
}

import conf.d/*
EOF
}

write_caddy_panel_config() {
    local panel_backend
    local sub_backend
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    cat <<EOF > "/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy"
https://${PANEL_DOMAIN}:${CADDY_LISTEN_PORT} {
    bind ${CADDY_LISTEN_ADDR}
    tls /etc/caddy/certs/${PANEL_DOMAIN}.crt /etc/caddy/certs/${PANEL_DOMAIN}.key
    encode gzip

    @sub path /sub /sub/*
    handle @sub {
        reverse_proxy ${sub_backend} {
            header_up Host {http.request.host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
            header_up X-Real-IP {remote_host}
        }
    }

    handle {
        reverse_proxy ${panel_backend} {
            header_up Host {http.request.host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
            header_up X-Real-IP {remote_host}
        }
    }
}
EOF
}

write_caddy_site_config() {
    [[ ${#SITE_DOMAINS[@]} -eq 0 ]] && return 0
    local i site_domain site_backend
    for i in "${!SITE_DOMAINS[@]}"; do
        site_domain="${SITE_DOMAINS[$i]}"
        [[ -z "$site_domain" ]] && continue
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        cat <<EOF > "/etc/caddy/conf.d/${site_domain}.caddy"
https://${site_domain}:${CADDY_LISTEN_PORT} {
    bind ${CADDY_LISTEN_ADDR}
    tls /etc/caddy/certs/${site_domain}.crt /etc/caddy/certs/${site_domain}.key
    encode gzip

    reverse_proxy ${site_backend} {
        header_up Host {http.request.host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
        header_up X-Real-IP {remote_host}
    }
}
EOF
    done
}

issue_and_install_cert_for_domain() {
    local domain="$1"
    local cf_token="$2"
    local acme_bin="/root/.acme.sh/acme.sh"
    local acme_email
    acme_email=$(get_acme_account_email)
    if [[ ! -x "$acme_bin" ]]; then
        install_acme_sh "$acme_email" || return 1
    fi
    prepare_acme_account "$acme_bin" "$acme_email" || return 1
    mkdir -p /etc/caddy/certs /root/cert
    echo -e "${CYAN}▶ 正在为 ${domain} 申请 Cloudflare DNS 证书...${PLAIN}"
    issue_cf_dns_cert_with_retry "$domain" "$cf_token" "$acme_bin" || return 1
    "$acme_bin" --install-cert -d "$domain" --ecc \
        --fullchain-file "/etc/caddy/certs/${domain}.crt" \
        --key-file "/etc/caddy/certs/${domain}.key" \
        --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1 || return 1
    if id caddy >/dev/null 2>&1; then
        chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
        chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
    else
        chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
    fi
    ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
    ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
}

save_sni_stack_env() {
    mkdir -p /etc/vps-optimize
    local site_domains_csv site_backend_addrs_csv site_backend_ports_csv
    site_domains_csv=$(IFS=','; echo "${SITE_DOMAINS[*]}")
    site_backend_addrs_csv=$(IFS=','; echo "${SITE_BACKEND_ADDRS[*]}")
    site_backend_ports_csv=$(IFS=','; echo "${SITE_BACKEND_PORTS[*]}")
    cat <<EOF > /etc/vps-optimize/sni-stack.env
PANEL_DOMAIN='${PANEL_DOMAIN}'
SITE_DOMAIN='${SITE_DOMAINS[0]:-}'
SITE_DOMAINS_CSV='${site_domains_csv}'
REALITY_SNI='${REALITY_SNI}'
NGINX_LISTEN_ADDR='${NGINX_LISTEN_ADDR}'
NGINX_LISTEN_PORT='${NGINX_LISTEN_PORT}'
CADDY_LISTEN_ADDR='${CADDY_LISTEN_ADDR}'
CADDY_LISTEN_PORT='${CADDY_LISTEN_PORT}'
XRAY_LISTEN_ADDR='${XRAY_LISTEN_ADDR}'
XRAY_LISTEN_PORT='${XRAY_LISTEN_PORT}'
PANEL_LISTEN_ADDR='${PANEL_LISTEN_ADDR}'
PANEL_LISTEN_PORT='${PANEL_LISTEN_PORT}'
SUB_LISTEN_ADDR='${SUB_LISTEN_ADDR}'
SUB_LISTEN_PORT='${SUB_LISTEN_PORT}'
SITE_BACKEND_ADDR='${SITE_BACKEND_ADDRS[0]:-127.0.0.1}'
SITE_BACKEND_PORT='${SITE_BACKEND_PORTS[0]:-3000}'
SITE_BACKEND_ADDRS_CSV='${site_backend_addrs_csv}'
SITE_BACKEND_PORTS_CSV='${site_backend_ports_csv}'
PANEL_INTERNAL_SSL='${PANEL_INTERNAL_SSL}'
EOF
    chmod 600 /etc/vps-optimize/sni-stack.env
}

harden_single_443_firewall() {
    local yn ssh_port remove_ports port
    echo -e "${YELLOW}可选：防火墙只保留 SSH 与 Nginx 公网入口端口。${PLAIN}"
    echo -e "${YELLOW}提醒：若 3x-ui 仍监听 0.0.0.0:${PANEL_LISTEN_PORT}，脚本的“自动追加当前活动端口”功能可能再次放行它。${PLAIN}"
    read -p "是否现在收紧防火墙？(y/n，默认 n): " yn
    [[ "$yn" =~ ^[Yy]$ ]] || return 0
    ssh_port=$(ss -lntp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | head -n1)
    ssh_port=${ssh_port:-22}
    remove_ports=("$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}" "40000" "8443" "1443" "2096" "3000")
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
        ufw allow "${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || true
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
            ufw delete allow "${port}/udp" >/dev/null 2>&1 || true
        done
    elif command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable --now firewalld >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || true
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --permanent --remove-port="${port}/udp" >/dev/null 2>&1 || true
        done
        firewall-cmd --reload >/dev/null 2>&1 || true
    else
        echo -e "${YELLOW}⚠️ 未检测到 ufw/firewalld，跳过防火墙收紧。${PLAIN}"
    fi
}

print_sni_stack_result() {
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}✅ 443 单入口分流配置完成${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}一、以后从外面只访问这些地址${PLAIN}"
    echo -e "  面板入口：      https://${PANEL_DOMAIN}/"
    echo -e "  订阅入口：      https://${PANEL_DOMAIN}/sub/"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "  网站/反代入口： https://${SITE_DOMAINS[$i]}/"
        done
    fi
    echo -e "  REALITY 端口：  ${NGINX_LISTEN_PORT}"
    echo -e ""
    echo -e "${YELLOW}不要从公网访问这些内部端口：${CADDY_LISTEN_PORT}/${XRAY_LISTEN_PORT}/${PANEL_LISTEN_PORT}/${SUB_LISTEN_PORT}/${SITE_BACKEND_PORTS[*]}${PLAIN}"
    echo -e "${YELLOW}它们应该只给本机内部服务互相连接，不是浏览器入口。${PLAIN}"
    echo -e ""
    echo -e "${BOLD}二、3x-ui 面板设置建议${PLAIN}"
    echo -e "  面板监听地址：${PANEL_LISTEN_ADDR}"
    echo -e "  面板端口：    ${PANEL_LISTEN_PORT}"
    echo -e "  webBasePath： /"
    echo -e "  面板 SSL/HTTPS：关闭"
    echo -e "  证书路径/私钥路径：留空，不要填写 Caddy 证书"
    echo -e "  Panel URL / Public URL / External URL：https://${PANEL_DOMAIN}/"
    echo -e "  Subscription URI Path：/sub/"
    echo -e "  Subscription External URL：https://${PANEL_DOMAIN}/sub/"
    if [[ "$PANEL_INTERNAL_SSL" == "on" ]]; then
        echo -e "${RED}  重要：你刚才表示 3x-ui 已启用内置 SSL，请先关闭它，否则容易 404/502/重定向循环。${PLAIN}"
    fi
    echo -e ""
    echo -e "${BOLD}三、Xray / 3x-ui REALITY 入站这样填${PLAIN}"
    echo -e "  入站监听地址 listen：${XRAY_LISTEN_ADDR}"
    echo -e "  入站监听端口 port：  ${XRAY_LISTEN_PORT}"
    echo -e "  协议 protocol：      VLESS"
    echo -e "  传输 network：       tcp"
    echo -e "  安全 security：      reality"
    echo -e "  REALITY dest：       ${REALITY_SNI}:443"
    echo -e "  serverNames：        ${REALITY_SNI}"
    echo -e "  SpiderX：            /"
    echo -e "  客户端连接地址：     你的服务器 IP 或解析到服务器的域名"
    echo -e "  客户端连接端口：     ${NGINX_LISTEN_PORT}"
    echo -e "  客户端 SNI/serverName：${REALITY_SNI}"
    echo -e "${YELLOW}  注意：REALITY 的 dest/serverNames 必须是外部真实站点，不要写面板域名。${PLAIN}"
    echo -e ""
    echo -e "${BOLD}四、常见错误怎么判断${PLAIN}"
    echo -e "  ERR_SSL_PROTOCOL_ERROR：通常是访问了内部端口，外部只访问 https://${PANEL_DOMAIN}/"
    echo -e "  ERR_TOO_MANY_REDIRECTS：通常是 3x-ui 面板还开着 SSL/强制 HTTPS，请关闭并清空证书路径"
    echo -e "  HTTP 404：先检查 3x-ui 的 webBasePath 是否为 /，再检查 Caddy 是否反代到 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "  502 Bad Gateway：通常是 3x-ui 没启动、端口不对，或 3x-ui 开了 HTTPS 但 Caddy 按 HTTP 连接"
    echo -e ""
    echo -e "${BOLD}五、监听状态应该长这样${PLAIN}"
    echo -e "  ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> nginx"
    echo -e "  ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> caddy"
    echo -e "  ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT} -> xray"
    echo -e "  ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} -> 3x-ui"
    echo -e "  ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} -> 3x-ui subscription"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "  ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]} -> ${SITE_DOMAINS[$i]} 网站后端"
        done
    fi
    echo -e ""
    echo -e "${BOLD}六、检查命令${PLAIN}"
    echo -e "  ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096|:3000'"
    echo -e "  nginx -t"
    echo -e "  caddy validate --config /etc/caddy/Caddyfile"
    echo -e "  curl -I http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}/"
    echo -e "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}"
    echo -e "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${REALITY_SNI}"
    echo -e "  journalctl -u caddy -n 80 --no-pager"
    echo -e "  journalctl -u x-ui -u 3x-ui -n 80 --no-pager"
    echo -e ""
    echo -e "${RED}绝对不要做：Caddy 监听公网 443；Xray 监听公网 443；3x-ui 面板暴露公网；把 Caddy 证书填进 3x-ui 面板 SSL；把 REALITY dest/serverNames 写成面板域名。${PLAIN}"
}

apply_sni_stack_runtime_config() {
    create_sni_stack_backup
    install_nginx_stream_stack || return 1
    harden_nginx_public_errors
    ensure_caddy_local_base_config || return 1
    cleanup_old_nginx_sni_stream_configs
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    write_nginx_sni_stream_config || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx || return 1
    save_sni_stack_env
    generate_caddy_cf_manifest
}

list_sni_stack_sites() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}当前 443 单入口网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "面板域名：${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "------------------------------------------------"
    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有额外的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} https://${SITE_DOMAINS[$i]}/ -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
}

add_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}添加 443 网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "${RED}❌ 未找到 Cloudflare Token，请先进入维护菜单 [2] 写入 Token。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "${RED}❌ Cloudflare Token 为空，请先进入维护菜单 [2] 更新。${PLAIN}"
        return 1
    fi

    echo -e "这个入口适合后续新增网站，例如 SublinkPro、Dockge、博客、订阅管理工具等。"
    echo -e "${YELLOW}新增域名会走：公网 ${NGINX_LISTEN_PORT} -> Nginx SNI -> Caddy -> 本地后端。${PLAIN}"
    echo -e ""

    local site_domain site_addr site_port advanced_mode existing idx confirm
    read -p "请输入新网站/反代域名（例如 sub.example.com）: " site_domain
    site_domain=$(echo "$site_domain" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    if ! is_valid_domain "$site_domain"; then
        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
        return 1
    fi
    if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ 新域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经在 443 分流列表中。${PLAIN}"
            return 1
        fi
    done

    read -p "是否进入高级模式并允许修改后端监听地址？(y/n，默认 n): " advanced_mode
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        site_addr=$(ask_with_default "后端监听地址" "127.0.0.1")
    else
        site_addr="127.0.0.1"
        echo -e "${GREEN}普通模式：后端地址使用 127.0.0.1。${PLAIN}"
    fi
    site_port=$(ask_with_default "后端端口" "$((3000 + ${#SITE_DOMAINS[@]}))")

    is_valid_listen_addr "$site_addr" || { echo -e "${RED}❌ 后端监听地址无效：${site_addr}${PLAIN}"; return 1; }
    is_valid_port "$site_port" || { echo -e "${RED}❌ 后端端口无效：${site_port}${PLAIN}"; return 1; }
    warn_if_public_bind "网站/反代后端 ${site_domain}" "$site_addr" "$site_port" || return 1

    echo -e ""
    echo -e "${CYAN}即将添加：${site_domain} -> ${site_addr}:${site_port}${PLAIN}"
    read -p "确认申请证书并更新 Nginx/Caddy？输入 YES 继续: " confirm
    [[ "$confirm" == "YES" ]] || return 1

    idx=${#SITE_DOMAINS[@]}
    SITE_DOMAINS[$idx]="$site_domain"
    SITE_BACKEND_ADDRS[$idx]="$site_addr"
    SITE_BACKEND_PORTS[$idx]="$site_port"

    issue_and_install_cert_for_domain "$site_domain" "$CF_Token" || return 1
    apply_sni_stack_runtime_config || return 1
    echo -e "${GREEN}✅ 已添加网站入口：https://${site_domain}/${PLAIN}"
    echo -e "${YELLOW}提醒：后端服务需要监听 ${site_addr}:${site_port}，浏览器只访问 https://${site_domain}/。${PLAIN}"
}

remove_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 443 网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num choice idx domain confirm delete_cert new_domains new_addrs new_ports
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read -p "请输入要删除的序号: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    read -p "确认从 443 分流中删除 ${domain}？输入 YES 继续: " confirm
    [[ "$confirm" == "YES" ]] || return 1

    new_domains=()
    new_addrs=()
    new_ports=()
    for i in "${!SITE_DOMAINS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_domains+=("${SITE_DOMAINS[$i]}")
        new_addrs+=("${SITE_BACKEND_ADDRS[$i]}")
        new_ports+=("${SITE_BACKEND_PORTS[$i]}")
    done
    SITE_DOMAINS=("${new_domains[@]}")
    SITE_BACKEND_ADDRS=("${new_addrs[@]}")
    SITE_BACKEND_PORTS=("${new_ports[@]}")
    rm -f "/etc/caddy/conf.d/${domain}.caddy"

    apply_sni_stack_runtime_config || return 1

    read -p "是否同时删除 ${domain} 的 Caddy 证书文件？(y/n，默认 n): " delete_cert
    if [[ "$delete_cert" =~ ^[Yy]$ ]]; then
        rm -f "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
        rm -f "/root/cert/${domain}.crt" "/root/cert/${domain}.key"
        generate_caddy_cf_manifest
        echo -e "${GREEN}✅ 已删除 ${domain} 的配置与本地证书文件。${PLAIN}"
    else
        echo -e "${GREEN}✅ 已删除 ${domain} 的分流配置，证书文件已保留。${PLAIN}"
    fi
}

manage_sni_stack_sites() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🌐 443 网站/反代域名管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "用于已经完成 [18] 443 单入口初始化后的日常维护。"
        echo -e "新增网站不需要重跑完整向导，只需要把域名指向本机后端端口。"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前网站/反代域名${PLAIN}"
        echo -e "${GREEN}  2. 新增网站/反代域名${PLAIN}"
        echo -e "${GREEN}  3. 删除网站/反代域名${PLAIN}"
        echo -e "${GREEN}  4. 重新应用并重启 Nginx/Caddy${PLAIN}"
        echo -e "${GREEN}  5. 443 单入口链路体检${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read -p "👉 请选择操作: " choice
        case "$choice" in
            1) list_sni_stack_sites ;;
            2) add_sni_stack_site ;;
            3) remove_sni_stack_site ;;
            4) reapply_sni_stack_from_env ;;
            5) sni_stack_health_check ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

func_caddy_cf_reality_wizard() {
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}检测到已有 443 单入口配置${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}如果只是新增网站或反代域名，请返回并选择 [2] 管理网站/反代域名。${PLAIN}"
        echo -e "${YELLOW}继续首次配置会重写 Nginx/Caddy/REALITY 分流核心配置。${PLAIN}"
        echo -e "------------------------------------------------"
        grep -E '^(PANEL_DOMAIN|REALITY_SNI|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_PORT|XRAY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null || true
        echo -e "------------------------------------------------"
        confirm_danger "重新执行 443 首次配置" "将基于新输入重写 443 单入口核心配置，并重启 Nginx/Caddy。" "脚本会先创建备份，可从 443 维护菜单或备份目录回滚。" || return 1
    fi
    collect_sni_stack_config || return 1
    probe_reality_sni "$REALITY_SNI" || return 1
    print_sni_stack_preview || return 1
    local cf_env_dir="/root/.config/vps-panel"
    local cf_env_file="${cf_env_dir}/cloudflare.env"
    local escaped_token
    mkdir -p "$cf_env_dir"
    chmod 700 "$cf_env_dir"
    escaped_token=${CF_TOKEN//\'/\'"\'"\'}
    printf "CF_Token='%s'\n" "$escaped_token" > "$cf_env_file"
    chmod 600 "$cf_env_file"

    create_sni_stack_backup
    install_nginx_stream_stack || return 1
    harden_nginx_public_errors
    ensure_caddy_local_base_config || return 1
    cleanup_old_nginx_sni_stream_configs
    quarantine_legacy_caddy_443_configs
    issue_and_install_cert_for_domain "$PANEL_DOMAIN" "$CF_TOKEN" || return 1
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local site_domain
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -z "$site_domain" ]] && continue
            issue_and_install_cert_for_domain "$site_domain" "$CF_TOKEN" || return 1
        done
    fi
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    write_nginx_sni_stream_config || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx || return 1
    save_sni_stack_env
    harden_single_443_firewall
    generate_caddy_cf_manifest
    print_sni_stack_result
}

func_caddy_cf_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🩺 CF DNS 一键体检${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"

    echo -e "${YELLOW}▶ [1/5] 检查 Cloudflare Token ...${PLAIN}"
    if [[ -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            if command -v curl >/dev/null 2>&1; then
                local verify_resp
                verify_resp=$(curl -s --max-time 8 -H "Authorization: Bearer ${CF_Token}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
                if echo "$verify_resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
                    echo -e "${GREEN}✅ Cloudflare Token 校验通过${PLAIN}"
                    ((ok_count++))
                else
                    echo -e "${YELLOW}⚠️ Token 文件存在，但在线校验失败（可能权限不足/网络异常）${PLAIN}"
                    ((warn_count++))
                fi
            else
                echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
                ((warn_count++))
            fi
        else
            echo -e "${RED}❌ Token 文件为空，请在维护菜单 [2] 重新写入。${PLAIN}"
            ((err_count++))
        fi
    else
        echo -e "${RED}❌ 未找到 Token 文件: ${cf_env_file}${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [2/5] 检查 Caddy 服务状态...${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            echo -e "${GREEN}✅ Caddy 服务运行中${PLAIN}"
            ((ok_count++))
        else
            echo -e "${YELLOW}⚠️ Caddy 已安装但未运行${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${RED}❌ 未安装 Caddy${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [3/5] 检查域名配置、证书与软链接...${PLAIN}"
    local domain_count=0
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            local domain
            local listen_port
            local backend
            local backend_port
            local cert_file
            local key_file
            local cert_end
            local cert_ts
            local now_ts
            local days_left

            domain=$(basename "$conf_file" .caddy)
            cert_file="/etc/caddy/certs/${domain}.crt"
            key_file="/etc/caddy/certs/${domain}.key"

            if ! head -n1 "$conf_file" | grep -q '^https://'; then
                continue
            fi
            ((domain_count++))

            listen_port=$(sed -n '1{s@^https://[^:]*:\([0-9]\+\)[[:space:]]*{.*$@\1@p;q}' "$conf_file")
            backend=$(grep -E '^[[:space:]]*reverse_proxy[[:space:]]+127.0.0.1:[0-9]+' "$conf_file" | awk '{print $2}' | head -n1)
            backend_port=$(echo "$backend" | awk -F: '{print $2}')

            echo -e "${CYAN}  - 域名: ${domain}${PLAIN}"

            if [[ -f "$cert_file" && -f "$key_file" ]]; then
                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -n "$cert_end" && "$days_left" -gt 15 ]]; then
                    echo -e "    ${GREEN}证书状态: 正常 (剩余约 ${days_left} 天)${PLAIN}"
                    ((ok_count++))
                elif [[ -n "$cert_end" ]]; then
                    echo -e "    ${YELLOW}证书状态: 即将到期 (剩余约 ${days_left} 天)${PLAIN}"
                    ((warn_count++))
                else
                    echo -e "    ${RED}证书状态: 无法读取有效期${PLAIN}"
                    ((err_count++))
                fi
            else
                echo -e "    ${RED}证书状态: 缺失 /etc/caddy/certs/${domain}.crt|.key${PLAIN}"
                ((err_count++))
            fi

            if [[ -L "/root/cert/${domain}.crt" && -e "/root/cert/${domain}.crt" && -L "/root/cert/${domain}.key" && -e "/root/cert/${domain}.key" ]]; then
                echo -e "    ${GREEN}软链接状态: /root/cert 已正确挂载${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}软链接状态: 缺失或失效，建议执行维护菜单 [4]${PLAIN}"
                ((warn_count++))
            fi

            if [[ -n "$listen_port" ]] && ss -lnt 2>/dev/null | awk '{print $4}' | grep -q "127.0.0.1:${listen_port}$"; then
                echo -e "    ${GREEN}监听状态: Caddy 本地端口 127.0.0.1:${listen_port} 可见${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}监听状态: 未检测到 127.0.0.1:${listen_port} 在监听${PLAIN}"
                ((warn_count++))
            fi

            if [[ -n "$backend_port" ]] && ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ":${backend_port}$"; then
                echo -e "    ${GREEN}后端状态: 127.0.0.1:${backend_port} 有服务监听${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}后端状态: 127.0.0.1:${backend_port} 未检测到监听${PLAIN}"
                ((warn_count++))
            fi
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi

    if [[ "$domain_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ 未检测到本功能托管的域名配置（https://域名:端口）。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [4/5] 检查清单文件...${PLAIN}"
    if [[ -f /root/cert/caddy_cf_manifest.txt ]]; then
        echo -e "${GREEN}✅ 清单文件存在: /root/cert/caddy_cf_manifest.txt${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 清单文件不存在，建议执行维护菜单 [7] 重建。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/5] 总结...${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${CYAN}体检结果: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "${RED}建议优先修复异常项，再继续业务切流。${PLAIN}"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "${YELLOW}当前可继续运行，但建议处理警告项提高稳定性。${PLAIN}"
    else
        echo -e "${GREEN}环境健康，可放心使用 Reality 回落 + Caddy 反代链路。${PLAIN}"
    fi
}

func_caddy_cf_auto_fix() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧰 CF DNS 一键自动修复${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local fixed_count=0
    local warn_count=0
    local fail_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    local acme_bin="/root/.acme.sh/acme.sh"

    echo -e "${YELLOW}▶ [1/7] 修复基础目录与主配置...${PLAIN}"
    mkdir -p /root/cert /etc/caddy/certs /etc/caddy/conf.d /root/.config/vps-panel
    chmod 700 /root/.config/vps-panel >/dev/null 2>&1

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
        ((fixed_count++))
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
        ((fixed_count++))
    fi

    echo -e "${YELLOW}▶ [1.5/7] 隔离旧式站点配置（避免抢占 443）...${PLAIN}"
    quarantine_legacy_caddy_443_configs

    echo -e "${YELLOW}▶ [2/7] 修复证书权限...${PLAIN}"
    if [[ -d /etc/caddy/certs ]]; then
        if id caddy >/dev/null 2>&1; then
            chown root:caddy /etc/caddy/certs/* 2>/dev/null
            chmod 640 /etc/caddy/certs/* 2>/dev/null
        else
            chmod 600 /etc/caddy/certs/* 2>/dev/null
        fi
        ((fixed_count++))
    else
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [3/7] 全量重建 /root/cert 软链接...${PLAIN}"
    local relink_count=0
    if [[ -d /etc/caddy/certs ]]; then
        while IFS= read -r cert_path; do
            local domain
            domain=$(basename "$cert_path" .crt)
            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                ((relink_count++))
            fi
        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
    fi
    echo -e "${GREEN}✅ 已重建 ${relink_count} 组软链接。${PLAIN}"
    ((fixed_count++))

    echo -e "${YELLOW}▶ [4/7] 近效期证书自动续签...${PLAIN}"
    local renew_count=0
    local renew_fail=0
    if [[ -x "$acme_bin" && -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            while IFS= read -r conf_file; do
                local domain
                local cert_file
                local cert_end
                local cert_ts
                local now_ts
                local days_left

                domain=$(basename "$conf_file" .caddy)
                cert_file="/etc/caddy/certs/${domain}.crt"

                if ! head -n1 "$conf_file" | grep -q '^https://'; then
                    continue
                fi
                if [[ ! -f "$cert_file" ]]; then
                    continue
                fi

                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -z "$cert_end" || "$days_left" -le 15 ]]; then
                    if issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                        "$acme_bin" --install-cert -d "$domain" --ecc \
                            --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                            --key-file "/etc/caddy/certs/${domain}.key" \
                            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1
                        ((renew_count++))
                    else
                        ((renew_fail++))
                    fi
                fi
            done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)

            if [[ "$renew_fail" -gt 0 ]]; then
                ((warn_count+=renew_fail))
            fi
            echo -e "${GREEN}✅ 自动续签完成，成功 ${renew_count} 个，失败 ${renew_fail} 个。${PLAIN}"
            ((fixed_count++))
        else
            echo -e "${YELLOW}⚠️ Token 为空，跳过自动续签。${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${YELLOW}⚠️ 未检测到 acme.sh 或 Token 文件，跳过自动续签。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/7] 校验并重载 Caddy...${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            systemctl enable caddy >/dev/null 2>&1
            if systemctl restart caddy >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Caddy 配置校验通过并重启成功。${PLAIN}"
                ((fixed_count++))
            else
                echo -e "${RED}❌ Caddy 重启失败，请手动检查日志。${PLAIN}"
                ((fail_count++))
            fi
        else
            echo -e "${RED}❌ Caddy 配置校验失败，未执行重启。${PLAIN}"
            ((fail_count++))
        fi
    else
        echo -e "${RED}❌ 未安装 Caddy，无法执行重载。${PLAIN}"
        ((fail_count++))
    fi

    echo -e "${YELLOW}▶ [6/7] 重建清单文件...${PLAIN}"
    generate_caddy_cf_manifest
    ((fixed_count++))
    echo -e "${GREEN}✅ 清单已重建: /root/cert/caddy_cf_manifest.txt${PLAIN}"

    echo -e "${YELLOW}▶ [7/7] 补全 acme 自动续签任务...${PLAIN}"
    if [[ -x "$acme_bin" ]]; then
        if "$acme_bin" --install-cronjob >/dev/null 2>&1; then
            echo -e "${GREEN}✅ acme.sh 自动续签任务已确认。${PLAIN}"
            ((fixed_count++))
        else
            echo -e "${YELLOW}⚠️ 无法确认 acme.sh 续签任务，请手动检查 crontab。${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${YELLOW}⚠️ 未安装 acme.sh，跳过续签任务补全。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "${CYAN}自动修复结果: ${GREEN}${fixed_count} 已修复${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${fail_count} 失败${PLAIN}"
    if [[ "$fail_count" -gt 0 ]]; then
        echo -e "${RED}存在失败项，建议先执行维护菜单 [8] 体检复查并查看 caddy 日志。${PLAIN}"
    else
        echo -e "${GREEN}自动修复流程完成，可执行维护菜单 [8] 复检确认。${PLAIN}"
    fi
}

func_caddy_cf_maintenance_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🛠️ 443 / Caddy / Cloudflare 维护中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}${BLUE}▶ 443 单入口常用${PLAIN}"
        echo -e "${GREEN}  1. 443 链路与安全体检${PLAIN}       ${YELLOW}(Nginx/Caddy/REALITY/面板/版本隐藏)${PLAIN}"
        echo -e "${GREEN}  2. 管理 443 网站/反代域名${PLAIN}    ${YELLOW}(新增/删除/查看，最常用)${PLAIN}"
        echo -e "${GREEN}  3. 重新应用上次 443 配置${PLAIN}     ${YELLOW}(读取 sni-stack.env 重建配置)${PLAIN}"
        echo -e "${GREEN}  4. 订阅端口 / External Proxy 提示${PLAIN} ${YELLOW}(节点链接应输出公网 443)${PLAIN}"
        echo -e "${RED}  5. 回滚 443 单入口配置${PLAIN}       ${YELLOW}(从最近备份恢复)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 证书与 Cloudflare${PLAIN}"
        echo -e "${GREEN}  6. 查看已管理域名 / 证书路径${PLAIN}"
        echo -e "${GREEN}  7. 更新 Cloudflare API Token${PLAIN}"
        echo -e "${GREEN}  8. 重新签发某个域名证书${PLAIN}"
        echo -e "${GREEN}  9. 重建 /root/cert 证书软链接${PLAIN}"
        echo -e "${GREEN} 10. 重建证书清单文件${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ Caddy 修复与清理${PLAIN}"
        echo -e "${GREEN} 11. 校验并重载 Caddy${PLAIN}"
        echo -e "${GREEN} 12. Caddy/证书一键体检${PLAIN}       ${YELLOW}(Token/证书/监听/后端)${PLAIN}"
        echo -e "${GREEN} 13. 一键自动修复常见问题${PLAIN}"
        echo -e "${GREEN} 14. 隔离旧 Caddy 配置${PLAIN}        ${YELLOW}(避免抢占 443)${PLAIN}"
        echo -e "${RED} 15. 删除某个域名的 Caddy 配置与证书${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local m_choice
        read -p "👉 请选择操作: " m_choice

        case "$m_choice" in
            1) m_choice=11 ;;
            2) m_choice=15 ;;
            3) m_choice=12 ;;
            4) m_choice=13 ;;
            5) m_choice=14 ;;
            6) m_choice=1 ;;
            7) m_choice=2 ;;
            8) m_choice=3 ;;
            9) m_choice=4 ;;
            10) m_choice=7 ;;
            11) m_choice=6 ;;
            12) m_choice=8 ;;
            13) m_choice=9 ;;
            14) m_choice=10 ;;
            15) m_choice=5 ;;
        esac

        case $m_choice in
            1)
                generate_caddy_cf_manifest
                echo -e "${CYAN}👇 当前清单内容：${PLAIN}"
                cat /root/cert/caddy_cf_manifest.txt 2>/dev/null
                ;;

            2)
                local new_token escaped_token
                mkdir -p /root/.config/vps-panel
                chmod 700 /root/.config/vps-panel
                echo -e "${CYAN}👇 请输入新的 Cloudflare API Token${PLAIN}"
                read -p "CF Token: " new_token
                echo ""
                if [[ -z "$new_token" || ${#new_token} -lt 20 ]]; then
                    echo -e "${RED}❌ Token 长度异常，更新取消。${PLAIN}"
                else
                    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
                    verify_cf_token_online "$new_token"
                    local verify_rc=$?
                    if [[ "$verify_rc" -eq 1 ]]; then
                        echo -e "${RED}❌ Token 在线校验失败，未写入。${PLAIN}"
                        echo -e "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    elif [[ "$verify_rc" -eq 2 ]]; then
                        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验，继续写入。${PLAIN}"
                    else
                        echo -e "${GREEN}✅ Token 校验通过。${PLAIN}"
                    fi

                    escaped_token=${new_token//\'/\'"\'"\'}
                    printf "CF_Token='%s'\n" "$escaped_token" > /root/.config/vps-panel/cloudflare.env
                    chmod 600 /root/.config/vps-panel/cloudflare.env
                    echo -e "${GREEN}✅ Cloudflare Token 已更新。${PLAIN}"
                fi
                ;;

            3)
                local domain
                local acme_bin="/root/.acme.sh/acme.sh"
                local cf_env_file="/root/.config/vps-panel/cloudflare.env"

                read -p "👉 请输入要重签的域名: " domain
                if ! is_valid_domain "$domain"; then
                    echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "${RED}❌ 未检测到 acme.sh，请先运行 [18] 初始化。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                if [[ ! -f "$cf_env_file" ]]; then
                    echo -e "${RED}❌ 未检测到 Cloudflare Token，请先执行本菜单 [2]。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                # shellcheck disable=SC1090
                source "$cf_env_file"
                echo -e "${CYAN}▶ 正在重签证书: ${domain}${PLAIN}"

                if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                    echo -e "${RED}❌ 证书签发失败：${domain}${PLAIN}"
                    echo -e "${YELLOW}   提示：建议先执行本菜单 [9] 自动修复再重试。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                mkdir -p /etc/caddy/certs /root/cert
                if ! "$acme_bin" --install-cert -d "$domain" --ecc \
                    --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                    --key-file "/etc/caddy/certs/${domain}.key" \
                    --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
                    echo -e "${RED}❌ 证书安装失败：${domain}${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if id caddy >/dev/null 2>&1; then
                    chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
                    chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                else
                    chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                fi

                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ 重签完成并已更新 /root/cert 软链接。${PLAIN}"
                ;;

            4)
                local link_mode domain
                mkdir -p /root/cert
                read -p "❓ 重建全部链接还是单域名？(all/one): " link_mode

                if [[ "$link_mode" == "all" ]]; then
                    local relink_count=0
                    if [[ -d /etc/caddy/certs ]]; then
                        while IFS= read -r cert_path; do
                            domain=$(basename "$cert_path" .crt)
                            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                                ((relink_count++))
                            fi
                        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
                    fi
                    generate_caddy_cf_manifest
                    echo -e "${GREEN}✅ 已重建 ${relink_count} 个域名的证书软链接。${PLAIN}"
                else
                    read -p "👉 请输入域名: " domain
                    if ! is_valid_domain "$domain"; then
                        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    if [[ -f "/etc/caddy/certs/${domain}.crt" && -f "/etc/caddy/certs/${domain}.key" ]]; then
                        ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                        ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                        generate_caddy_cf_manifest
                        echo -e "${GREEN}✅ 软链接已重建：/root/cert/${domain}.crt 与 /root/cert/${domain}.key${PLAIN}"
                    else
                        echo -e "${RED}❌ 未找到该域名证书文件。${PLAIN}"
                    fi
                fi
                ;;

            5)
                local domain purge_acme
                read -p "👉 请输入要删除的域名: " domain
                if ! is_valid_domain "$domain"; then
                    echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                read -p "❓ 确认删除 ${domain} 的配置与证书？(y/n): " yn
                if [[ ! "$yn" =~ ^[Yy]$ ]]; then
                    echo -e "${BLUE}已取消删除。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                rm -f "/etc/caddy/conf.d/${domain}.caddy"
                rm -f "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                rm -f "/root/cert/${domain}.crt" "/root/cert/${domain}.key"

                read -p "❓ 是否同时删除 acme.sh 历史记录？(y/n，默认n，建议保留): " purge_acme
                if [[ "$purge_acme" =~ ^[Yy]$ ]]; then
                    /root/.acme.sh/acme.sh --remove -d "$domain" --ecc >/dev/null 2>&1 || true
                    rm -rf "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/${domain}"
                fi

                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                fi
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ ${domain} 已清理完成。${PLAIN}"
                ;;

            6)
                caddy_format_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "${GREEN}✅ Caddy 配置已格式化，校验通过并重启生效。${PLAIN}"
                else
                    echo -e "${RED}❌ Caddy 配置校验失败，请检查 /etc/caddy/conf.d/*.caddy${PLAIN}"
                fi
                ;;

            7)
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ 清单已重建：/root/cert/caddy_cf_manifest.txt${PLAIN}"
                ;;

            8)
                func_caddy_cf_health_check
                ;;

            9)
                func_caddy_cf_auto_fix
                ;;

            10)
                quarantine_legacy_caddy_443_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "${GREEN}✅ 隔离完成，Caddy 已重载。${PLAIN}"
                else
                    echo -e "${RED}❌ 当前 Caddy 配置校验失败，请先修复语法错误。${PLAIN}"
                fi
                ;;

            11)
                sni_stack_health_check
                ;;

            12)
                reapply_sni_stack_from_env
                ;;

            13)
                check_sni_stack_subscription_hint
                ;;

            14)
                rollback_sni_stack_config
                ;;

            15)
                manage_sni_stack_sites
                ;;

            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac

        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 新增功能：查看 Caddy 已申请证书路径
# ---------------------------------------------------------
func_view_caddy_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 Caddy 已申请证书路径查询${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    if [[ ! -f "/etc/caddy/Caddyfile" ]]; then
        echo -e "${RED}❌ 未检测到 /etc/caddy/Caddyfile，请先配置反代！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 提取 Caddyfile 与 conf.d 中的域名 (排除注释，简单匹配)
    local domains
    domains=$(cat /etc/caddy/Caddyfile /etc/caddy/conf.d/*.caddy 2>/dev/null | grep -vE '^[[:space:]]*#' | grep '{' | awk '{print $1}' | tr -d '{')
    
    if [[ -z "$domains" ]]; then
        echo -e "${YELLOW}⚠️ Caddyfile 中没有配置明确的域名。${PLAIN}"
    else
        # Caddy 默认的证书存储根路径
        local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
        [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"
        
        for domain in $domains; do
            # 过滤掉本地回环等无意义的块
            if [[ "$domain" == ":80" || "$domain" == "localhost" ]]; then continue; fi
            
            echo -e "${BLUE}🌐 域名: ${BOLD}${domain}${PLAIN}"
            
            local found=false
            if [[ -d "$cert_root" ]]; then
                # 递归查找对应的 .crt 和 .key 文件
                local cert_file
                local key_file
                cert_file=$(find "$cert_root" -name "${domain}.crt" -print -quit 2>/dev/null)
                key_file=$(find "$cert_root" -name "${domain}.key" -print -quit 2>/dev/null)
                
                if [[ -n "$cert_file" && -n "$key_file" ]]; then
                    echo -e "   ${GREEN}📄 公钥 (CRT):${PLAIN} ${cert_file}"
                    echo -e "   ${YELLOW}🔑 密钥 (KEY):${PLAIN} ${key_file}"
                    found=true
                fi
            fi
            
            if ! $found; then
                echo -e "   ${RED}❌ 未找到证书，可能尚未签发成功或路径异常。${PLAIN}"
            fi
            echo -e "------------------------------------------------"
        done
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：清空 Caddy 配置文件 (适配模块化安全架构)
# ---------------------------------------------------------
func_caddy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清空 Caddy 配置文件 (模块化版本)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 检查主文件与模块化目录是否存在
    if [[ -f /etc/caddy/Caddyfile ]] || [[ -d /etc/caddy/conf.d ]]; then
        echo -e "${YELLOW}将清空 /etc/caddy/conf.d/*.caddy，并重置 /etc/caddy/Caddyfile 为模块化初始状态。${PLAIN}"
        if confirm_danger "清空 Caddy 反代配置" "所有独立 Caddy 反代配置会失效，相关网站/面板可能暂时打不开。" "脚本会备份 Caddyfile 和 conf.d 目录，可按备份路径手动恢复。"; then
            
            # 1. 备份现有的模块化配置目录
            if [[ -d /etc/caddy/conf.d ]]; then
                local backup_dir="/etc/caddy/conf.d_bak_$(date +%s)"
                cp -r /etc/caddy/conf.d "$backup_dir" 2>/dev/null
                echo -e "${BLUE}已备份原配置目录为 $backup_dir${PLAIN}"
                
                # 精准清空所有 .caddy 配置文件
                rm -f /etc/caddy/conf.d/*.caddy 2>/dev/null
            fi
            
            # 2. 守护主文件架构，重置为极简模式并注入模块化指令
            cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null
            echo "# Caddyfile Cleared and Reset to Modular Architecture" > /etc/caddy/Caddyfile
            echo "import conf.d/*" >> /etc/caddy/Caddyfile
            
            # 3. 重启生效
            systemctl restart caddy >/dev/null 2>&1
            echo -e "${GREEN}✅ 所有反代配置已清空并成功重载！系统已恢复纯净的模块化初始状态。${PLAIN}"
        else
            echo -e "${BLUE}已取消清空操作。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 未检测到 Caddy 配置文件或模块化目录！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 优化重构：核弹级域名证书清理与解除端口占用 (模块化安全版)
# ---------------------------------------------------------
func_caddy_delete_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}☢️ 核弹级：彻底清理域名证书与配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：该脚本将彻底清理指定域名的证书与配置，确保服务器环境干净。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read -p "👉 请输入要强杀清理的精准域名 (如 panel.site.com): " domain
    if [[ -z "$domain" ]]; then
        echo -e "${RED}❌ 域名不能为空！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "\n${CYAN}▶ 正在执行核弹级清理流程...${PLAIN}"
    echo -e "${YELLOW}此操作将永久删除该域名的证书与配置，无法恢复！${PLAIN}"
    echo -e "请确认操作...${PLAIN}"
    if confirm_danger "彻底清理 ${domain} 的证书与配置" "会停止 Caddy，删除该域名证书、acme.sh 残留和 Caddy 配置，再启动 Caddy。" "请先确认已有系统快照或 Caddy 备份；删除后的证书需要重新签发。"; then
        # 1. 停止 Caddy，强制释放 80/443 端口
        systemctl stop caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ [1/4] 已强制停止 Caddy 服务，释放网络端口。${PLAIN}"
        
        # 2. 深度清理 Caddy 底层证书缓存
        local caddy_paths=("/var/lib/caddy/.local/share/caddy/certificates" "/root/.local/share/caddy/certificates")
        local caddy_found=false
        for cp in "${caddy_paths[@]}"; do
            if [[ -d "$cp" ]]; then
                local target=$(find "$cp" -type d -name "${domain}" -print -quit 2>/dev/null)
                if [[ -n "$target" ]]; then
                    rm -rf "$target"
                    caddy_found=true
                fi
            fi
        done
        if $caddy_found; then
            echo -e "${GREEN}✅ [2/4] Caddy 引擎中关于 ${domain} 的密钥与证书已抹除。${PLAIN}"
        else
            echo -e "${BLUE}ℹ️ [2/4] 未在 Caddy 引擎中发现该域名的证书。${PLAIN}"
        fi
        
        # 3. 清理 acme.sh 残留
        if [[ -d "/root/.acme.sh" ]]; then
            local acme_target=$(find "/root/.acme.sh" -type d -name "*${domain}*" -print -quit 2>/dev/null)
            if [[ -n "$acme_target" ]]; then
                rm -rf "$acme_target"
                echo -e "${GREEN}✅ [3/4] 面板底层 (~/.acme.sh) 关于 ${domain} 的残留已抹除。${PLAIN}"
            else
                echo -e "${BLUE}ℹ️ [3/4] 未在 acme.sh 引擎中发现残留。${PLAIN}"
            fi
        else
            echo -e "${BLUE}ℹ️ [3/4] 系统未安装独立 acme.sh 环境，已跳过。${PLAIN}"
        fi
        
        # 4. 外科手术：模块化安全删除
        local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$domain_conf" ]]; then
            echo -e "${YELLOW}⏳ [4/4] 检测到专属配置文件，正在销毁...${PLAIN}"
            rm -f "$domain_conf"
            echo -e "${GREEN}✅ [4/4] 专属配置文件 ($domain_conf) 已安全移除！${PLAIN}"
        else
            echo -e "${GREEN}✅ [4/4] 未发现该域名的专属配置文件。${PLAIN}"
        fi

        # 重启 Caddy 以加载干净的配置
        systemctl start caddy >/dev/null 2>&1

        echo -e "------------------------------------------------"
        echo -e "${GREEN}🎉 清理彻底完成！当前域名环境已处于出厂真空状态。${PLAIN}"
    else
        echo -e "${BLUE}操作已取消。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：独立追加 Caddy 跳过不安全证书反代块 (模块化版)
# ---------------------------------------------------------
func_caddy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 独立配置：追加 Caddy 跳过证书验证反代${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "${RED}❌ 未检测到 Caddy 配置文件，请先运行 [13] 安装 Caddy！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    local domain
    local port
    read -p "👉 请输入解析后的域名 (如 panel.site.com): " domain
    read -p "👉 请输入面板 HTTPS 本地映射端口 (如 40000): " port
    
    if [[ -z "$domain" || -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ 域名为空或端口格式错误！已取消操作。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    # 确保主文件包含模块化目录
    grep -q "import conf.d/\*" /etc/caddy/Caddyfile || echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    
    mkdir -p /etc/caddy/conf.d
    local conf_file="/etc/caddy/conf.d/${domain}.caddy"
    
    cat <<EOF > "$conf_file"
$domain {
    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl reload caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ 独立跳过验证配置已成功建立并生效！${PLAIN}"
    else
        echo -e "${RED}❌ 致命错误：追加的配置导致语法错误！正在回滚...${PLAIN}"
        rm -f "$conf_file"
    fi

    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 4. SSH 安全加固 (终极完美版：防截断、防覆盖、防 Socket 冲突)
# ---------------------------------------------------------
func_security() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ SSH 安全加固 (端口修改与防失联)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：该脚本将修改 SSH 端口并配置防失联机制，确保服务稳定。${PLAIN}"
    echo -e "------------------------------------------------"
    
    # 1. 极致精准：读取内存和进程，获取当前真实生效的 SSH 端口
    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    if [[ -z "$current_p" ]]; then
        current_p=$(sshd -T 2>/dev/null | grep -i "^port " | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}

    local final_p
    # 交互提示优化：引导用户使用高位端口避开特权冲突
    read -p "👉 当前生效的 SSH 端口为 $current_p, 请输入新端口 [10000-65535] (回车保持不变): " final_p
    final_p=${final_p:-$current_p}

    if [[ "$final_p" != "$current_p" ]]; then
        
        # [严格检验] 端口合法性
        if ! [[ "$final_p" =~ ^[0-9]+$ ]] || [ "$final_p" -lt 10000 ] || [ "$final_p" -gt 65535 ]; then
            echo -e "${RED}❌ 错误：无效的端口号！必须是 1-65535 之间的纯数字。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${CYAN}▶ 正在备份原生 SSH 配置文件...${PLAIN}"
        local backup_file="/etc/ssh/sshd_config.bak_$(date +%s)"
        cp /etc/ssh/sshd_config "$backup_file"

        # 2. 核心黑科技：安全的置顶替换
        # - 先安全删除所有带 Port 的行 (忽略注释符和空格)
        # - 然后在文件绝对第一行 (1i) 插入新端口，秒杀所有 include 配置覆盖！
        sed -i '/^[[:space:]]*#\?Port /d' /etc/ssh/sshd_config
        sed -i "1i Port $final_p" /etc/ssh/sshd_config

        # 3. [CentOS 专属] SELinux 放行
        if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
            echo -e "${YELLOW}检测到 SELinux 开启，正在配置底层端口安全策略...${PLAIN}"
            if command -v semanage >/dev/null 2>&1; then
                semanage port -a -t ssh_port_t -p tcp "$final_p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$final_p" 2>/dev/null
            else
                echo -e "${RED}❌ 致命错误：缺少 semanage 工具！已触发安全回滚。${PLAIN}"
                mv "$backup_file" /etc/ssh/sshd_config
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi

        # 4. 防失联核心：验证新配置语法
        if ! sshd -t; then
            echo -e "${RED}❌ 致命错误：SSH 配置存在语法异常！正在全盘恢复...${PLAIN}"
            mv "$backup_file" /etc/ssh/sshd_config
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        
        # 5. 放行全栈防火墙
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_p"/tcp >/dev/null 2>&1; fi
        if command -v firewall-cmd >/dev/null 2>&1; then 
            firewall-cmd --permanent --add-port="$final_p"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        iptables -I INPUT -p tcp --dport "$final_p" -j ACCEPT 2>/dev/null
        
        # 6. Ubuntu 的 Socket 端口接管 (防宕机冲突)
        local use_socket=false
        if systemctl is-active --quiet ssh.socket; then
            use_socket=true
            echo -e "${YELLOW}检测到 Ubuntu ssh.socket，正在覆写底层监听端口...${PLAIN}"
            mkdir -p /etc/systemd/system/ssh.socket.d
            cat <<EOF > /etc/systemd/system/ssh.socket.d/port.conf
[Socket]
ListenStream=
ListenStream=$final_p
EOF
            systemctl daemon-reload >/dev/null 2>&1
        fi
        
        # 7. 严格隔离的服务重启逻辑
        echo -e "${CYAN}▶ 正在重启底层 SSH 引擎...${PLAIN}"
        local restart_ok=false
        if $use_socket; then
            systemctl restart ssh.socket >/dev/null 2>&1 && restart_ok=true
        else
            (systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null) && restart_ok=true
        fi
        
        if $restart_ok; then
            rm -f "$backup_file" 
            echo -e "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行！${PLAIN}"
        else
            echo -e "${RED}❌ 致命错误：重启 SSH 服务失败！正在回滚至原端口...${PLAIN}"
            mv "$backup_file" /etc/ssh/sshd_config
            $use_socket && systemctl restart ssh.socket >/dev/null 2>&1 || (systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null)
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
        echo -e "${YELLOW}⚠️ 终极保命提示：${PLAIN}"
        echo -e "现在的这扇 SSH 窗口【千万不要关闭】！"
        echo -e "请立刻使用新端口 $final_p 新建一个连接进行测试。"
        echo -e "如果云平台有【安全组】，请确保也已放行 $final_p 端口！"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
    else
        echo -e "${BLUE}端口未做更改。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增：Fail2ban 防爆破系统管理 (抽象精简版)
# ---------------------------------------------------------
func_fail2ban() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Fail2ban 防爆破系统管理${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -z "$current_p" ]]; then
        current_p=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}
    
    echo -e "${YELLOW}👉 当前系统检测到的 SSH 端口为: ${GREEN}$current_p${PLAIN}"
    echo -e "------------------------------------------------"
    
    local f2b_status="${RED}未安装${PLAIN}"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_status="${GREEN}已运行${PLAIN}"
        else
            f2b_status="${YELLOW}已停止${PLAIN}"
        fi
    fi
    
    echo -e "当前 Fail2ban 状态: [ $f2b_status ]"
    echo -e "  ${GREEN}1.${PLAIN} 一键安装并配置 Fail2ban ${YELLOW}(自动绑定当前 SSH 端口)${PLAIN}"
    echo -e "  ${BLUE}2.${PLAIN} 更新防护端口 ${YELLOW}(如果您刚改了 SSH 端口，选此项重载)${PLAIN}"
    echo -e "  ${RED}3.${PLAIN} 彻底卸载 Fail2ban"
    echo -e "  ${RED}0.${PLAIN} 返回主菜单"
    echo -e "------------------------------------------------"
    
    local f_choice
    read -p "👉 请选择操作: " f_choice
    
    case $f_choice in
        1|2)
            if [[ "$f_choice" == "1" ]]; then
                echo -e "${CYAN}正在安装 Fail2ban...${PLAIN}"
                install_pkg fail2ban # <--- 核心修改：一句话代替之前的多行系统判定
            fi
            
            if command -v fail2ban-server >/dev/null 2>&1; then
                echo -e "${CYAN}正在写入配置并绑定端口 $current_p ...${PLAIN}"
                cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $current_p
EOF
                systemctl enable fail2ban >/dev/null 2>&1
                systemctl restart fail2ban >/dev/null 2>&1
                echo -e "${GREEN}✅ Fail2ban 配置完成并已启动！(保护端口: $current_p)${PLAIN}"
                echo -e "${YELLOW}💡 规则：10分钟内密码错误5次，自动封禁该IP 24小时。${PLAIN}"
            else
                echo -e "${RED}❌ Fail2ban 安装或检测失败，请检查网络源。${PLAIN}"
            fi
            ;;
        3)
            echo -e "${CYAN}正在卸载 Fail2ban...${PLAIN}"
            remove_pkg fail2ban # <--- 核心修改：一句话极简卸载
            rm -rf /etc/fail2ban
            echo -e "${GREEN}✅ Fail2ban 已彻底卸载！${PLAIN}"
            ;;
        0) return ;;
        *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
    esac
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增功能：添加 SSH 公钥登录
# ---------------------------------------------------------
func_add_ssh_key() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 添加 SSH 公钥登录 (免密安全认证)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}使用 SSH 密钥登录不仅免去输密码的烦恼，更能彻底免疫密码爆破！${PLAIN}"
    echo -e "请准备好您的公钥 (通常以 ssh-rsa, ssh-ed25519 或 ecdsa 开头)。"
    echo -e "------------------------------------------------"
    
    # 确保根目录的 .ssh 文件夹和权限正确 (极为重要，权限错了一律无法登录)
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    echo -e "👇 ${CYAN}请在下方右键粘贴您的 SSH 公钥内容，粘贴后按回车键：${PLAIN}"
    read -r ssh_key
    
    if [[ -z "$ssh_key" ]]; then
        echo -e "${RED}❌ 输入为空，已取消操作。${PLAIN}"
    elif [[ "$ssh_key" == ssh-* || "$ssh_key" == ecdsa-* ]]; then
        # 检查是否已经存在相同公钥 (采用绝对精确全行匹配)
        if grep -q -F -x "$ssh_key" ~/.ssh/authorized_keys; then
            echo -e "${YELLOW}⚠️ 该公钥已存在于 ~/.ssh/authorized_keys 中，无需重复添加。${PLAIN}"
        else
            echo "$ssh_key" >> ~/.ssh/authorized_keys
            
            # 自动修改 sshd_config 确保开启了公钥登录选项
            sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
            
            echo -e "${GREEN}✅ 公钥添加成功！现在您可以尝试使用对应的私钥免密登录本服务器了。${PLAIN}"
            echo -e "${YELLOW}💡 进阶建议：当您确认公钥登录 100% 成功后，可以手动编辑 /etc/ssh/sshd_config 将 PasswordAuthentication 改为 no，彻底关闭密码登录。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 格式错误：看起来不像有效的 SSH 公钥。操作已取消。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 5. Docker 深度管理 (重构版：非破坏性修改与防宕机回滚)
# ---------------------------------------------------------
func_docker_manage() {
    if ! command -v docker >/dev/null 2>&1; then 
        clear
        echo -e "${RED}❌ 错误：检测到系统尚未安装 Docker 引擎！${PLAIN}"
        echo -e "${YELLOW}💡 请先在主菜单进入 [3 软件安装与反代分流] 安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 确保依赖工具存在 (使用我们抽象的 install_pkg)
    if ! command -v jq >/dev/null 2>&1; then install_pkg jq; fi

    while true; do
        clear
        local docker_ver
        docker_ver=$(docker -v | awk '{print $3}' | tr -d ',')
        
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🐳 Docker 安全管理 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 开启 Docker 本地防穿透${PLAIN} ${YELLOW}(限制映射端口仅 127.0.0.1 访问)${PLAIN}"
        echo -e "${GREEN}  2. 解除 Docker 本地防穿透${PLAIN} ${YELLOW}(恢复全网可访，不破坏原配置)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        
        local c
        read -p "👉 请选择操作: " c
        case $c in
            1) 
                echo -e "${CYAN}▶ 正在配置 Docker 安全策略...${PLAIN}"
                mkdir -p /etc/docker
                local conf_file="/etc/docker/daemon.json"
                local backup_file="${conf_file}.bak_$(date +%s)"
                
                # 检查并备份
                if [[ -f "$conf_file" ]]; then
                    cp "$conf_file" "$backup_file"
                    echo -e "${YELLOW}⚠️ 已备份原有配置至 $backup_file${PLAIN}"
                    
                    # 使用 jq 进行非破坏性合并，保留用户原有配置
                    if ! jq '. + {"ip": "127.0.0.1", "log-driver": "json-file", "log-opts": {"max-size": "50m", "max-file": "3"}}' "$conf_file" > /tmp/daemon_tmp.json 2>/dev/null; then
                        echo -e "${RED}❌ 原 daemon.json 格式损坏，合并失败！操作中止。${PLAIN}"
                        rm -f "$backup_file"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    mv /tmp/daemon_tmp.json "$conf_file"
                else
                    # 文件不存在时初始生成
                    cat <<EOF > "$conf_file"
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
                fi
                
                # 防宕机重启机制：如果新配置导致引擎崩溃，立刻回滚！
                if systemctl restart docker >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ 已开启安全保护，Docker 容器端口仅限本地反代访问！${PLAIN}"
                    [[ -f "$backup_file" ]] && rm -f "$backup_file" # 成功则清理备份
                else
                    echo -e "${RED}❌ 致命错误：新配置导致 Docker 引擎无法启动！正在自动回滚...${PLAIN}"
                    if [[ -f "$backup_file" ]]; then
                        mv "$backup_file" "$conf_file"
                    else
                        rm -f "$conf_file"
                    fi
                    systemctl restart docker >/dev/null 2>&1
                fi
                sleep 2
                ;;
            2) 
                local conf_file="/etc/docker/daemon.json"
                if [[ -f "$conf_file" ]]; then
                    echo -e "${CYAN}▶ 正在安全移除 Docker 端口限制...${PLAIN}"
                    local backup_file="${conf_file}.bak_$(date +%s)"
                    cp "$conf_file" "$backup_file"

                    # 核心修复：只精准删除 ip 限制，绝不误删国内镜像源等其他配置！
                    if ! jq 'del(.ip)' "$conf_file" > /tmp/daemon_tmp.json 2>/dev/null; then
                        echo -e "${RED}❌ JSON 解析失败，操作中止。${PLAIN}"
                        rm -f "$backup_file"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    mv /tmp/daemon_tmp.json "$conf_file"

                    if systemctl restart docker >/dev/null 2>&1; then
                        echo -e "${GREEN}✅ 已解除限制，容器端口恢复公网可访状态！${PLAIN}"
                        rm -f "$backup_file"
                    else
                        echo -e "${RED}❌ 卸载异常：导致引擎无法启动！正在回滚...${PLAIN}"
                        mv "$backup_file" "$conf_file"
                        systemctl restart docker >/dev/null 2>&1
                    fi
                else
                    echo -e "${BLUE}未检测到限制配置文件，当前已是全网开放状态。${PLAIN}"
                fi
                sleep 2
                ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
        esac
    done
}
# ---------------------------------------------------------
# 6. BBR 增强管理
# ---------------------------------------------------------
func_bbr_manage() {
    clear
    echo -e "${CYAN}👉 正在调用 ylx2016 网络极速脚本...${PLAIN}"
    wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (修复版：放宽正则以兼容多值与特殊符号)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚀 动态 TCP 极致调优 (Omnitt)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "👉 推荐浏览器访问: ${BLUE}https://omnitt.com/${PLAIN} 获取针对您网络的定制参数"
    echo -e "------------------------------------------------"
    
    read -p "❓ 准备好粘贴参数了吗？(y 继续 / n 取消): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then return; fi
    
    local temp_f="/etc/sysctl.d/99-omnitt-tune.conf"
    local backup_f="${temp_f}.bak_$(date +%s)"
    
    # 事务起点：备份原配置
    if [[ -f "$temp_f" ]]; then
        cp "$temp_f" "$backup_f"
    fi
    
    > "$temp_f"
    echo -e "\n${YELLOW}👇 请在下方直接【右键粘贴】代码。${PLAIN}"
    echo -e "${YELLOW}💡 粘贴完成后，请按下【回车键】，然后输入 ${RED}EOF${YELLOW} 并再次回车保存：${PLAIN}"
    
    local has_content=false
    while IFS= read -r line; do
        # 极简清洗：去除回车符和前后多余空格
        line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        
        # 结束符匹配（忽略大小写）
        if [[ "${line,,}" == "eof" ]]; then
            break
        fi
        
        # 【核心修复】：放宽等号右侧的值校验，允许包含空格(如 tcp_rmem) 和特殊符号(如 %)
        if [[ -z "$line" || "$line" =~ ^# || "$line" =~ ^[a-zA-Z0-9_.-]+[[:space:]]*=[[:space:]]*.+$ ]]; then
            echo "$line" >> "$temp_f"
            # 标记确实写入了有效参数，而不是只敲了几个回车
            [[ -n "$line" && ! "$line" =~ ^# ]] && has_content=true
        else
            echo -e "${RED}⚠️ 已自动过滤非法参数行: $line${PLAIN}"
        fi
    done
    
    if $has_content; then
        echo -e "${CYAN}▶ 正在校验并应用新 TCP 参数...${PLAIN}"
        # 验证新配置是否被内核完全接受
        if sysctl -p "$temp_f" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 动态 TCP 调优参数应用成功！网络吞吐量已提升。${PLAIN}"
            rm -f "$backup_f" # 成功则删除备份
        else
            echo -e "${RED}❌ 致命错误：您粘贴的部分参数当前内核不支持或语法错误！${PLAIN}"
            echo -e "${YELLOW}正在触发安全回滚...${PLAIN}"
            if [[ -f "$backup_f" ]]; then
                mv "$backup_f" "$temp_f"
                sysctl -p "$temp_f" >/dev/null 2>&1
            else
                rm -f "$temp_f"
            fi
            echo -e "${BLUE}✅ 已恢复系统原 TCP 状态，未造成任何破坏。${PLAIN}"
        fi
    else
        echo -e "${YELLOW}⚠️ 未检测到有效的 TCP 调优参数，操作已取消。${PLAIN}"
        if [[ -f "$backup_f" ]]; then mv "$backup_f" "$temp_f"; else rm -f "$temp_f"; fi
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 8. 智能内存调优 (重构版：安全接管与 DRY 化)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    local mem
    mem=$(free -m | awk '/^Mem:/{print $2}')
    echo -e "${CYAN}💡 硬件自适应调优 (检测到本机 ${mem}MB 物理内存)${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e " ${GREEN}1. 激进档 (适合 1G 以下小鸡)${PLAIN}"
    echo -e "    - ZRAM 100% 压缩, Swappiness=100。全力防止宕机。"
    echo -e " ${GREEN}2. 积极档 (适合 2-4G 主流机型)${PLAIN}"
    echo -e "    - ZRAM 70% 压缩, Swappiness=60。平衡性能与空间。"
    echo -e " ${GREEN}3. 保守档 (适合 8G 以上性能怪兽)${PLAIN}"
    echo -e "    - ZRAM 25% 压缩, Swappiness=10。追求极致响应速度。"
    echo -e "------------------------------------------------"
    
    local choice
    read -p "👉 请选择您的调优挡位 [1/2/3] (直接回车按内存自动匹配): " choice
    
    if [[ -z "$choice" ]]; then
        if [[ "$mem" -lt 1024 ]]; then choice=1
        elif [[ "$mem" -le 4096 ]]; then choice=2
        else choice=3
        fi
        echo -e "${YELLOW}💡 系统已根据本机内存 (${mem}MB) 自动选择：[ 挡位 $choice ]${PLAIN}"
        sleep 1.5
    fi
    
    # 提早阻断，避免非 Debian 机器运行破坏性 Swap 卸载指令
    if ! is_debian; then
        echo -e "${RED}❌ 抱歉，当前系统并非 Debian/Ubuntu 衍生系，暂不支持自动化 ZRAM 调优。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${CYAN}▶ 正在进行第一阶段：整理底层磁盘 Swap (保留 512M 保底防假死)...${PLAIN}"
    
    swapoff -a >/dev/null 2>&1
    rm -f /swapfile /swap.img /var/swap /var/swapfile >/dev/null 2>&1
    
    dd if=/dev/zero of=/swapfile bs=1M count=512 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1
    
    sed -i -E 's/^([^#].*[[:space:]]swap[[:space:]].*)/#\1/' /etc/fstab
    sed -i '\@^/swapfile@d' /etc/fstab
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo -e "${GREEN}✅ 已建立 512M 极小磁盘 Swap 作为系统崩溃的最后防线！${PLAIN}"
    
    echo -e "${CYAN}▶ 正在进行第二阶段：配置 ZRAM 内存压缩引擎...${PLAIN}"
    
    # 核心修改：使用全局包安装器
    install_pkg zram-tools
    modprobe zram >/dev/null 2>&1
    
    local zram_conf="/etc/default/zramswap"
    local percent=70
    local swap_val=60
    
    case $choice in
        1) percent=100; swap_val=100 ;;
        2) percent=70; swap_val=60 ;;
        3) percent=25; swap_val=10 ;;
        *) percent=70; swap_val=60 ;;
    esac
    
    cat <<EOF > "$zram_conf"
ALGO=zstd
PERCENT=$percent
PRIORITY=100
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1
    systemctl restart zramswap >/dev/null 2>&1
    
    if ! grep -q zram /proc/swaps; then
        if command -v zramswap >/dev/null 2>&1; then
            zramswap start >/dev/null 2>&1
        elif [[ -x /usr/sbin/zramswap ]]; then
            /usr/sbin/zramswap start >/dev/null 2>&1
        fi
    fi
    
    echo "vm.swappiness = $swap_val" > /etc/sysctl.d/99-zram-swappiness.conf
    sysctl -p /etc/sysctl.d/99-zram-swappiness.conf >/dev/null 2>&1
    
if grep -q zram /proc/swaps; then
        echo -e "${GREEN}✅ ZRAM 调优落地完成！(已设置: ${percent}% 压缩比, ${swap_val} 交换倾向)${PLAIN}"
    else
        echo -e "${RED}❌ 警告：内核拒绝挂载 ZRAM (常见于 LXC/OpenVZ 架构)。${PLAIN}"
        echo -e "${CYAN}▶ 正在启动降级优化方案：传统 Swap 扩容与内核防假死调优...${PLAIN}"
        
        # 1. 扩容保底 Swap：从 512M 升级至 1024M (1GB)
        swapoff /swapfile >/dev/null 2>&1
        rm -f /swapfile >/dev/null 2>&1
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        
        # 2. 注入降级专属的内核内存管理参数
        # swappiness=30 : 只有内存比较吃紧时才使用较慢的磁盘 Swap
        # vfs_cache_pressure=50 : 降低系统回收目录/文件系统缓存的频率，提高小鸡流畅度
        # overcommit_memory=1 : 允许内核分配超过物理内存的空间，防止 Redis/数据库 等服务在启动时被直接 Kill
        cat <<EOF > /etc/sysctl.d/99-fallback-mem.conf
vm.swappiness = 30
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
EOF
        sysctl -p /etc/sysctl.d/99-fallback-mem.conf >/dev/null 2>&1
        
        echo -e "${GREEN}✅ 降级优化落地：已动态扩充 1GB 磁盘 Swap，并激活保守内存回收策略！${PLAIN}"
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 9. 安装/切换优化内核 (Cloud/KVM 稳定优先 + XanMod 高级可选)
# ---------------------------------------------------------
set_grub_default_kernel_by_keyword() {
    local kernel_keyword="$1"
    local target_v menu_1 menu_2

    target_v=$(dpkg -l | awk '/^ii[[:space:]]+linux-image-[0-9]/ && /'"$kernel_keyword"'/ {print $2}' | sed 's/linux-image-//' | sort -V | tail -n 1)
    if [[ -z "$target_v" ]]; then
        echo -e "${RED}❌ 错误：未找到已安装的 ${kernel_keyword} 内核包，请检查安装日志。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在接管 GRUB 底层引导，锁定启动内核为: $target_v ...${PLAIN}"
    sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    grep -q "^GRUB_SAVEDEFAULT=true" /etc/default/grub || echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
    update-grub >/dev/null 2>&1

    menu_1=$(grep -i "submenu 'Advanced options for" /boot/grub/grub.cfg | cut -d"'" -f2 | head -n 1)
    menu_2=$(grep -i "menuentry '.*$target_v.*'" /boot/grub/grub.cfg | grep -iv "recovery" | cut -d"'" -f2 | head -n 1)

    if [[ -n "$menu_1" && -n "$menu_2" ]]; then
        grub-set-default "$menu_1>$menu_2"
        echo -e "${GREEN}✅ GRUB 引导接管成功！重启后将优先进入：$target_v${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}⚠️ 警告：GRUB 菜单寻址失败。系统可能仍以最高版本号内核启动。${PLAIN}"
    return 1
}

install_cloud_kvm_kernel() {
    local kernel_keyword=""

    if uname -r | grep -qE "kvm|cloud"; then
        echo -e "${GREEN}✅ 系统当前已运行 KVM/Cloud 优化内核 ($(uname -r))，无需重复安装！${PLAIN}"
        return 0
    fi

    echo -e "${CYAN}▶ 正在安装发行版官方 Cloud/KVM 内核...${PLAIN}"
    if [[ "$OS" == "debian" ]]; then
        install_pkg linux-image-cloud-amd64 || return 1
        kernel_keyword="cloud"
    elif [[ "$OS" == "ubuntu" ]]; then
        install_pkg linux-image-kvm || return 1
        kernel_keyword="kvm"
    else
        echo -e "${RED}❌ Cloud/KVM 内核功能目前仅支持 Debian 和 Ubuntu。${PLAIN}"
        return 1
    fi

    set_grub_default_kernel_by_keyword "$kernel_keyword"
}

install_xanmod_kernel() {
    local codename confirm

    if uname -r | grep -qi "xanmod"; then
        echo -e "${GREEN}✅ 系统当前已运行 XanMod 内核 ($(uname -r))，无需重复安装！${PLAIN}"
        return 0
    fi

    if ! is_debian; then
        echo -e "${RED}❌ XanMod 自动安装目前仅支持 Debian/Ubuntu 衍生系统。${PLAIN}"
        return 1
    fi

    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi
    if [[ -z "$codename" ]]; then
        echo -e "${RED}❌ 无法识别系统代号，无法安全添加 XanMod 源。${PLAIN}"
        return 1
    fi

    echo -e "${RED}⚠️  XanMod 是第三方性能内核，可能影响 DKMS/驱动/部分云厂商兼容性。${PLAIN}"
    echo -e "${YELLOW}建议先确认有快照、救援控制台，且知道如何从 GRUB 切回旧内核。${PLAIN}"
    read -p "确认安装 XanMod LTS 兼容版内核请输入 YES: " confirm
    [[ "$confirm" == "YES" ]] || { echo -e "${BLUE}已取消 XanMod 安装。${PLAIN}"; return 1; }

    echo -e "${CYAN}▶ 正在添加 XanMod 官方 APT 源并安装 LTS 兼容版内核...${PLAIN}"
    install_pkg ca-certificates curl gpg || return 1
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/xanmod-archive-keyring.gpg
    if ! curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg; then
        echo -e "${RED}❌ XanMod GPG key 下载或写入失败。${PLAIN}"
        return 1
    fi
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${codename} main" > /etc/apt/sources.list.d/xanmod-release.list

    apt-get update -qq || return 1
    apt-get install -y -qq linux-xanmod-lts-x64v1 || {
        echo -e "${RED}❌ XanMod 内核安装失败，可能是当前系统代号暂未被 XanMod 源支持。${PLAIN}"
        return 1
    }

    set_grub_default_kernel_by_keyword "xanmod"
}

func_install_kernel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}☁️  安装/切换优化内核${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Cloud/KVM 官方云内核${PLAIN} ${YELLOW}(推荐：稳定、轻量、云厂商兼容更好)${PLAIN}"
    echo -e "     适合：普通 VPS、节点、Caddy、Docker、生产环境、小内存机器。"
    echo -e "${GREEN}  2. XanMod LTS 性能内核${PLAIN} ${YELLOW}(高级：BBRv3/新调度/第三方性能 patch)${PLAIN}"
    echo -e "     适合：愿意折腾、追求低延迟/新特性；需要快照或救援控制台兜底。"
    echo -e "------------------------------------------------"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local kernel_choice virt
    read -p "👉 请选择要安装的内核类型 [推荐 1]: " kernel_choice
    kernel_choice="${kernel_choice:-1}"
    [[ "$kernel_choice" == "0" ]] && return

    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    if [[ "$virt" =~ lxc|openvz ]]; then
        echo -e "${RED}❌ 致命错误：检测到当前 VPS 为 $virt 容器架构！${PLAIN}"
        echo -e "${YELLOW}💡 容器与母机共享内核，无法更改内核。操作已安全中止。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        echo -e "${RED}❌ 致命错误：优化内核仅支持 x86_64 (amd64) 架构，本机为 $(uname -m)！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    local install_rc=0
    case "$kernel_choice" in
        1) install_cloud_kvm_kernel ;;
        2) install_xanmod_kernel ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return ;;
    esac
    install_rc=$?
    if [[ "$install_rc" -ne 0 ]]; then
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}⚠️ 内核安装/切换未完成，未继续提示重启。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}⚠️ 核心生效指引：${PLAIN}"
    echo -e "1. 新内核引导已配置完毕，请先选择主菜单的 ${RED}[18] 重启服务器${PLAIN}。"
    echo -e "2. 重启后请运行 ${GREEN}uname -r${PLAIN} 确认实际进入的新内核。"
    echo -e "3. 确认稳定后，再进入本菜单选择 ${GREEN}[5] 清理旧内核${PLAIN}。"

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 10. 清理冗余旧内核 (数组菜单驱动 + 核心防砖拦截版)
# ---------------------------------------------------------
func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    local current_k
    current_k=$(uname -r)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清理冗余旧内核${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "当前正在运行的内核为: ${GREEN}${current_k}${PLAIN}"
    echo -e "${RED}⚠️ 系统已自动为您屏蔽正在运行的内核以及基础元包。${PLAIN}"
    echo -e "------------------------------------------------"
    
    # 自动提取所有非当前的内核包存入数组 (排除元包，采用高可用字段匹配)
    mapfile -t old_kernels < <(dpkg -l | awk '$1 == "ii" && $2 ~ /^linux-image-[0-9]/ {print $2}' | grep -v "$current_k" | grep -vE "linux-image-(generic|virtual|kvm|cloud-amd64)")

    if [[ ${#old_kernels[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 系统非常干净，没有发现需要清理的冗余旧内核。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${YELLOW}扫描到以下冗余内核可供清理：${PLAIN}"
    for i in "${!old_kernels[@]}"; do
        echo -e " [${CYAN}$((i+1))${PLAIN}] ${old_kernels[$i]}"
    done
    echo -e " [${RED}0${PLAIN}] 取消并返回"
    echo -e "------------------------------------------------"

    local k_choice
    read -p "👉 请输入要卸载的序号: " k_choice

    if [[ "$k_choice" == "0" ]]; then
        echo -e "${BLUE}已取消卸载操作。${PLAIN}"
    elif [[ "$k_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$k_choice" -le "${#old_kernels[@]}" ]]; then
        local target_k="${old_kernels[$((k_choice-1))]}"
        confirm_danger "卸载旧内核 ${target_k}" "会删除内核包并刷新 GRUB，引导异常时可能影响下次启动。" "建议先创建 VPS 快照；当前运行内核已自动排除，如失败请从快照或救援模式恢复。" || {
            echo -e "${BLUE}已取消卸载操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        }
        echo -e "${CYAN}正在静默卸载 $target_k 并刷新引导...${PLAIN}"
        export DEBIAN_FRONTEND=noninteractive
        if apt-get purge -yq "$target_k" && update-grub >/dev/null 2>&1 && apt-get autoremove --purge -yq >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 旧内核 [$target_k] 清理完成！磁盘空间已释放。${PLAIN}"
        else
            echo -e "${RED}❌ 清理失败！存在依赖问题或执行被中断。${PLAIN}"
        fi
        unset DEBIAN_FRONTEND
    else
        echo -e "${RED}❌ 无效的选择！${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 11. 极速硬件探针
# ---------------------------------------------------------
func_system_info() {
    clear
    local os_name
    os_name=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🖥️  本机详细硬件与网络信息大屏${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}系统 OS  :${PLAIN} $os_name ($(uname -m))"
    echo -e "${YELLOW}内核版本 :${PLAIN} $(uname -r)"
    echo -e "${YELLOW}虚拟架构 :${PLAIN} $(systemd-detect-virt 2>/dev/null || echo "未知")"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}CPU 型号 :${PLAIN} $(lscpu | grep "Model name:" | sed 's/Model name:\s*//')"
    echo -e "${YELLOW}CPU 核心 :${PLAIN} $(nproc) 核心"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}物理内存 :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "${YELLOW}交换内存 :${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')"
    echo -e "${YELLOW}硬盘空间 :${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}IPv4 地址:${PLAIN} $(curl -s4 --max-time 3 icanhazip.com || echo "无公网IPv4")"
    echo -e "${YELLOW}IPv6 地址:${PLAIN} $(curl -s6 --max-time 3 icanhazip.com || echo "无公网IPv6")"
    echo -e "${YELLOW}运行时间 :${PLAIN} $(uptime -p | sed 's/up //')"
    echo -e "${CYAN}================================================${PLAIN}"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 12. 综合测试合集
# ---------------------------------------------------------
func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测速与质量检验合集库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 硬件性能测试      ${YELLOW}  2. 融合怪详细测速${PLAIN}"
        echo -e "${GREEN}  3. SuperBench 综合测速    ${YELLOW}  4. bench.sh 基础测试${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁检测         ${YELLOW}  6. 三网回程路由测试${PLAIN}"
        echo -e "${GREEN}  7. IP 质量 / 欺诈度检测   ${YELLOW}  8. NodeSeek 综合测试${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local t
        local ran_test=false
        read -p "👉 请输入对应序号选择: " t
        case $t in
            1) ran_test=true; run_remote_script "运行 YABS 硬件性能测试" "https://yabs.sh" ;;
            2) ran_test=true; run_remote_script "运行融合怪详细测速" "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh" ;;
            3) ran_test=true; run_remote_script "运行 SuperBench 综合测速" "https://about.superbench.pro" ;;
            4) ran_test=true; run_remote_script "运行 bench.sh 基础测试" "https://bench.sh" ;;
            5) ran_test=true; run_remote_script "运行流媒体解锁检测" "https://check.unlock.media" ;;
            6) ran_test=true; run_remote_script "运行三网回程路由测试" "https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh" ;;
            7) ran_test=true; run_remote_script "运行 IP 质量 / 欺诈度检测" "https://IP.Check.Place" ;;
            8) ran_test=true; run_remote_script "运行 NodeSeek 综合测试" "https://run.NodeQuality.com" ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1; continue ;;
        esac
        echo ""
        if [[ "$ran_test" == "true" ]]; then
            pause_after_external_script "操作结束，按回车键返回测试菜单..."
        fi
    done
}
# ---------------------------------------------------------
# 13, 14, 15 面板与流量狗快速部署
# ---------------------------------------------------------
func_port_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取并执行 Port Traffic Dog 监控狗...${PLAIN}"
    run_remote_script "安装 Port Traffic Dog 监控狗" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xpanel() {
    clear
    echo -e "${CYAN}👉 正在拉取 mhsanaei 的官方 x-panel 一键脚本...${PLAIN}"
    run_remote_script "安装 3x-ui / x-ui 面板" "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox() {
    clear
    echo -e "${CYAN}👉 正在拉取甬哥的 Sing-box 四合一脚本...${PLAIN}"
    run_remote_script "安装 Sing-box 甬哥四合一脚本" "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox_233boy() {
    clear
    echo -e "${CYAN}👉 正在拉取 233boy 的 Sing-box 一键脚本...${PLAIN}"
    echo -e "${YELLOW}脚本来源：https://github.com/233boy/sing-box${PLAIN}"
    echo -e "${YELLOW}使用文档：https://233boy.com/sing-box/sing-box-script/${PLAIN}"
    echo -e "${GREEN}安装完成后通常可使用 sing-box 或 sb 命令进入管理面板。${PLAIN}"
    run_remote_script "安装 Sing-box 233boy 一键脚本" "https://github.com/233boy/sing-box/raw/main/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xray_233boy() {
    clear
    echo -e "${CYAN}👉 正在拉取 233boy 的 Xray 一键脚本...${PLAIN}"
    echo -e "${YELLOW}脚本来源：https://github.com/233boy/Xray${PLAIN}"
    echo -e "${YELLOW}使用文档：https://233boy.com/xray/xray-script/${PLAIN}"
    echo -e "${GREEN}安装完成后通常可使用 xray 命令进入管理面板。${PLAIN}"
    run_remote_script "安装 Xray 233boy 一键脚本" "https://github.com/233boy/Xray/raw/main/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 17. DNS 流媒体分流解锁 (Alice DNS)
# ---------------------------------------------------------
func_dns_unlock() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔓 DNS 流媒体分流解锁 (DNS-Alice-Unlock)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍与使用说明：${PLAIN}"
    echo -e " 1. 该脚本通过修改本地 DNS 解析，实现 Netflix, Disney+ 等特定区域流媒体的解锁。"
    echo -e " 2. ${GREEN}仅对流媒体域名进行分流${PLAIN}，不影响您的原生 IP 和普通上网速度。"
    echo -e " 3. 项目地址：${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}⚠️  风险提示：运行此脚本会修改您服务器的 /etc/resolv.conf 配置。${PLAIN}"
    echo -e "    如果您不懂如何自行配置解锁机的 DNS 记录，请务必先查阅项目文档！"
    echo -e "------------------------------------------------"
    
    local yn
    read -p "❓ 确认现在运行 Alice DNS 解锁脚本吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        wget https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh && bash dns-unlock.sh
    else
        echo -e "${BLUE}已安全取消操作。${PLAIN}"
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}
# ---------------------------------------------------------
# 新增功能：安装 IP Sentinel (防止 IP 送中)
# ---------------------------------------------------------
func_ip_sentinel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 安装 IP Sentinel (防止 IP 送中)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}该脚本将持续监控并修正路由，防止服务器 IP 被错误定位至中国大陆。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read -p "❓ 确定要安装并配置 IP Sentinel(公共网关) 吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        run_remote_script "安装并配置 IP Sentinel" "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 新增功能：安装 SublinkPro (强大的订阅转换与管理面板)
# ---------------------------------------------------------
ensure_docker_compose_ready() {
    DOCKER_COMPOSE_CMD=""
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 软件安装与反代分流] 中安装 Docker。${PLAIN}"
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您安装...${PLAIN}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null
        chmod +x /usr/local/bin/docker-compose
        DOCKER_COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi
}

generate_random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        echo "secret_$(date +%s)_$RANDOM$RANDOM"
    fi
}

func_sublinkpro() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔗 安装 SublinkPro (节点订阅转换与管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 1. 检查 Docker 引擎
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 软件安装与反代分流] 中安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 2. 检查并兼容 Docker Compose
    local compose_cmd=""
    if docker compose version >/dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您静默安装...${PLAIN}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null
        chmod +x /usr/local/bin/docker-compose
        compose_cmd="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi

    # 3. 部署目录初始化
    local install_dir="/opt/sublinkpro"
    local sublink_port="8000"
    while true; do
        sublink_port=$(ask_with_default "请输入 SublinkPro 对外访问端口" "$sublink_port")
        if is_valid_port "$sublink_port"; then
            break
        fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    echo -e "${YELLOW}💡 SublinkPro 将被安全部署在: ${CYAN}$install_dir${PLAIN}"
    echo -e "${YELLOW}💡 SublinkPro 对外访问端口将使用: ${CYAN}$sublink_port${PLAIN}"
    echo -e "------------------------------------------------"
    
    read -p "❓ 确认现在开始一键安装吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir"
        cd "$install_dir" || return

        # 生成 docker-compose.yml 文件
        cat <<EOF > docker-compose.yml
services:
  sublinkpro:
    image: zerodeng/sublink-pro
    container_name: sublinkpro
    ports:
      - "${sublink_port}:8000"
    volumes:
      - "./db:/app/db"
      - "./template:/app/template"
      - "./logs:/app/logs"
    restart: unless-stopped
EOF
        
        echo -e "${CYAN}▶ 正在拉取镜像并启动 SublinkPro 容器...${PLAIN}"
        $compose_cmd up -d
        
        local ip
        ip=$(curl -s4 icanhazip.com 2>/dev/null || echo "您的服务器IP")
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}🎉 SublinkPro 部署并启动成功！${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "🌐 ${BOLD}面板访问地址:${PLAIN} http://$ip:${sublink_port}"
        echo -e "👤 ${BOLD}默认后台账号:${PLAIN} admin"
        echo -e "🔑 ${BOLD}默认后台密码:${PLAIN} 123456"
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}⚠️ 核心防丢提示：${PLAIN}"
        echo -e "系统产生的数据库、模板和日志都已持久化映射在 ${CYAN}$install_dir${PLAIN} 下。"
        echo -e "如果您日后需要升级容器或重装 VPS，请务必提前打包备份该目录下的 ${GREEN}./db${PLAIN} 和 ${GREEN}./template${PLAIN} 文件夹！"
        echo -e "------------------------------------------------"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_miaomiaowu() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 妙妙屋订阅管理 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/miaomiaowu"
    local mmw_port="8080"
    local jwt_secret

    while true; do
        mmw_port=$(ask_with_default "请输入 妙妙屋 对外访问端口" "$mmw_port")
        if is_valid_port "$mmw_port"; then
            break
        fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    jwt_secret=$(ask_with_default "JWT_SECRET（回车自动生成随机密钥）" "")
    if [[ -z "$jwt_secret" ]]; then
        jwt_secret=$(generate_random_secret)
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}访问端口：${CYAN}${mmw_port}${PLAIN}"
    echo -e "${YELLOW}数据目录：${CYAN}${install_dir}/data、subscribes、rule_templates${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read -p "确认现在部署 妙妙屋订阅管理 吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir"/{data,subscribes,rule_templates}
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'

services:
  miaomiaowu:
    image: ghcr.io/iluobei/miaomiaowu:latest
    container_name: miaomiaowu
    restart: unless-stopped
    user: root
    environment:
      PORT: "${mmw_port}"
      DATABASE_PATH: /app/data/traffic.db
      LOG_LEVEL: info
      JWT_SECRET: "${jwt_secret}"
    ports:
      - "${mmw_port}:${mmw_port}"
    volumes:
      - ./data:/app/data
      - ./subscribes:/app/subscribes
      - ./rule_templates:/app/rule_templates
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:${mmw_port}/"]
      interval: 30s
      timeout: 3s
      start_period: 5s
      retries: 3
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 妙妙屋 容器...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        local ip
        ip=$(curl -s4 icanhazip.com 2>/dev/null || echo "您的服务器IP")
        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ 妙妙屋订阅管理部署完成！${PLAIN}"
        echo -e "访问地址：${BOLD}http://${ip}:${mmw_port}${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        echo -e "${YELLOW}请定期备份 ${install_dir}/data、subscribes、rule_templates。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

func_substore() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Sub-Store (Docker Compose / HTTP-META)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/sub-store"
    local backend_port="3001"
    local meta_port="9876"
    local backend_path="/$(generate_random_secret | cut -c1-48)"

    while true; do
        backend_port=$(ask_with_default "Sub-Store 后端 API 端口" "$backend_port")
        if is_valid_port "$backend_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    while true; do
        meta_port=$(ask_with_default "HTTP-META 本地端口" "$meta_port")
        if is_valid_port "$meta_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    backend_path=$(ask_with_default "前端访问后端路径（建议保留随机路径）" "$backend_path")
    if [[ "$backend_path" != /* ]]; then
        backend_path="/${backend_path}"
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}Sub-Store 后端：${CYAN}127.0.0.1:${backend_port}${PLAIN}"
    echo -e "${YELLOW}HTTP-META：${CYAN}127.0.0.1:${meta_port}${PLAIN}"
    echo -e "${YELLOW}前端后端路径：${CYAN}${backend_path}${PLAIN}"
    echo -e "${YELLOW}默认使用 host 网络并绑定 127.0.0.1，如需公网访问建议再接 Caddy/Nginx 反代。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read -p "确认现在部署 Sub-Store 吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir/data"
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'

services:
  sub-store:
    image: xream/sub-store:http-meta
    container_name: sub-store
    restart: always
    network_mode: host
    environment:
      SUB_STORE_BACKEND_API_HOST: "127.0.0.1"
      SUB_STORE_BACKEND_API_PORT: "${backend_port}"
      SUB_STORE_BACKEND_MERGE: "true"
      SUB_STORE_FRONTEND_BACKEND_PATH: "${backend_path}"
      PORT: "${meta_port}"
      HOST: "127.0.0.1"
    volumes:
      - ./data:/opt/app/data
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Sub-Store 容器...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Sub-Store 部署完成！${PLAIN}"
        echo -e "本地后端地址：${BOLD}http://127.0.0.1:${backend_port}${backend_path}${PLAIN}"
        echo -e "HTTP-META 地址：${BOLD}http://127.0.0.1:${meta_port}${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        echo -e "${YELLOW}请定期备份 ${install_dir}/data。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

update_compose_project() {
    local name="$1"
    local dir="$2"

    if [[ ! -d "$dir" || ! -f "$dir/docker-compose.yml" ]]; then
        echo -e "${YELLOW}⚠️ 未找到 ${name} 的 Compose 配置：${dir}/docker-compose.yml，已跳过。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在更新 ${name}...${PLAIN}"
    (
        cd "$dir" || exit 1
        $DOCKER_COMPOSE_CMD pull
        $DOCKER_COMPOSE_CMD up -d
    )
}

func_update_subscription_tools() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}${YELLOW}UPD 更新订阅管理工具 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}这个菜单只更新订阅管理工具容器，不会更新 3x-ui / Sing-box / Xray。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${BOLD}${YELLOW}  1. UPD 更新 SublinkPro${PLAIN}       ${CYAN}(/opt/sublinkpro)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  2. UPD 更新 妙妙屋订阅管理${PLAIN}     ${CYAN}(/opt/miaomiaowu)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  3. UPD 更新 Sub-Store${PLAIN}        ${CYAN}(/opt/sub-store)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  4. UPD 全部更新${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice
    read -p "请选择要更新的项目: " choice
    [[ "$choice" == "0" ]] && return

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    case "$choice" in
        1) update_compose_project "SublinkPro" "/opt/sublinkpro" ;;
        2) update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" ;;
        3) update_compose_project "Sub-Store" "/opt/sub-store" ;;
        4)
            update_compose_project "SublinkPro" "/opt/sublinkpro" || true
            update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" || true
            update_compose_project "Sub-Store" "/opt/sub-store" || true
            ;;
        *)
            echo -e "${RED}❌ 无效选择！${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
            ;;
    esac

    echo -e "------------------------------------------------"
    echo -e "${GREEN}✅ 更新流程已执行完成。${PLAIN}"
    local prune_confirm
    read -p "是否清理无标签旧镜像以释放磁盘空间？(y/n，默认 n): " prune_confirm
    if [[ "$prune_confirm" =~ ^[Yy]$ ]]; then
        docker image prune -f
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Dockge (Docker Compose 管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}Dockge 用来管理 compose.yaml stack，可创建、编辑、启动、停止、重启和更新镜像。${PLAIN}"
    echo -e "${YELLOW}注意：Dockge 会挂载 Docker socket，建议只监听本地地址，再通过 Caddy/Nginx 反代访问。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/dockge"
    local stacks_dir="/opt/stacks"
    local dockge_bind_addr="127.0.0.1"
    local dockge_port="5001"

    dockge_bind_addr=$(ask_with_default "Dockge 监听地址" "$dockge_bind_addr")
    is_valid_listen_addr "$dockge_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        dockge_port=$(ask_with_default "Dockge 访问端口" "$dockge_port")
        if is_valid_port "$dockge_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "Dockge 管理面板" "$dockge_bind_addr" "$dockge_port" || return 1
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")

    echo -e "${YELLOW}Dockge 目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}Stacks 目录：${CYAN}${stacks_dir}${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${dockge_bind_addr}:${dockge_port}${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read -p "确认现在部署 Dockge 吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir" "$stacks_dir"
        cd "$install_dir" || return

        cat <<EOF > compose.yaml
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - "${dockge_bind_addr}:${dockge_port}:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - ${stacks_dir}:${stacks_dir}
    environment:
      DOCKGE_STACKS_DIR: "${stacks_dir}"
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Dockge...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Dockge 部署完成！${PLAIN}"
        echo -e "访问地址：${BOLD}http://${dockge_bind_addr}:${dockge_port}${PLAIN}"
        echo -e "Stacks 目录：${CYAN}${stacks_dir}${PLAIN}"
        echo -e "${YELLOW}已有 compose 项目可返回部署菜单选择 [10] 迁移到 Dockge 后，在 Dockge 里扫描 stacks 目录。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

find_compose_file() {
    local dir="$1"
    local file
    for file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        if [[ -f "${dir}/${file}" ]]; then
            echo "${dir}/${file}"
            return 0
        fi
    done
    return 1
}

is_dockge_migration_seen() {
    local needle="$1"
    local item
    for item in "${DOCKGE_MIGRATION_DIRS[@]}"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

add_dockge_migration_candidate() {
    local dir="$1"
    local stacks_dir="$2"
    local name

    dir="${dir%/}"
    [[ -d "$dir" ]] || return 0
    [[ "$dir" == "/opt/dockge" ]] && return 0
    [[ "$dir" == "$stacks_dir" || "$dir" == "$stacks_dir"/* ]] && return 0
    find_compose_file "$dir" >/dev/null 2>&1 || return 0
    is_dockge_migration_seen "$dir" && return 0

    name=$(basename "$dir")
    DOCKGE_MIGRATION_NAMES+=("$name")
    DOCKGE_MIGRATION_DIRS+=("$dir")
}

discover_dockge_migration_candidates() {
    local stacks_dir="$1"
    local dir file
    DOCKGE_MIGRATION_NAMES=()
    DOCKGE_MIGRATION_DIRS=()

    for dir in /opt/sublinkpro /opt/miaomiaowu /opt/sub-store; do
        add_dockge_migration_candidate "$dir" "$stacks_dir"
    done

    for file in /opt/*/compose.yaml /opt/*/compose.yml /opt/*/docker-compose.yml /opt/*/docker-compose.yaml; do
        [[ -e "$file" ]] || continue
        add_dockge_migration_candidate "$(dirname "$file")" "$stacks_dir"
    done
}

migrate_compose_project_to_dockge() {
    local source_dir="$1"
    local stacks_dir="$2"
    local source_compose stack_name target_dir compose_name restart_confirm
    local restart_stack="true"

    source_dir="${source_dir%/}"
    source_compose=$(find_compose_file "$source_dir") || {
        echo -e "${RED}❌ 未找到 Compose 配置：${source_dir}${PLAIN}"
        return 1
    }

    stack_name=$(ask_with_default "Dockge stack 名称" "$(basename "$source_dir")")
    if [[ ! "$stack_name" =~ ^[A-Za-z0-9_.-]+$ || "$stack_name" == "." || "$stack_name" == ".." ]]; then
        echo -e "${RED}❌ stack 名称无效，只能使用字母、数字、点、下划线和短横线。${PLAIN}"
        return 1
    fi

    target_dir="${stacks_dir%/}/${stack_name}"
    if [[ "$source_dir" == "$target_dir" ]]; then
        echo -e "${YELLOW}⚠️ ${source_dir} 已经在 Dockge stacks 目录内，已跳过。${PLAIN}"
        return 0
    fi
    if [[ -e "$target_dir" ]]; then
        echo -e "${RED}❌ 目标目录已存在：${target_dir}${PLAIN}"
        echo -e "${YELLOW}请先在 Dockge 中确认是否已有同名 stack，或换一个 stack 名称。${PLAIN}"
        return 1
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}将迁移：${CYAN}${source_dir}${PLAIN}"
    echo -e "${YELLOW}迁移到：${CYAN}${target_dir}${PLAIN}"
    echo -e "${YELLOW}Compose：${CYAN}${source_compose}${PLAIN}"
    echo -e "${YELLOW}说明：会移动整个项目目录，保留相对挂载的数据目录。${PLAIN}"
    echo -e "${YELLOW}如果项目使用 Docker 命名卷，建议保持 stack 名称与原目录名一致。${PLAIN}"
    read -p "确认迁移这个项目吗？(y/n): " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { echo -e "${BLUE}已取消迁移 ${source_dir}。${PLAIN}"; return 0; }

    read -p "是否先停止旧容器并在新目录重新启动？(Y/n): " restart_confirm
    if [[ "$restart_confirm" =~ ^[Nn]$ ]]; then
        restart_stack="false"
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在停止旧目录中的 Compose 项目...${PLAIN}"
        ( cd "$source_dir" && $DOCKER_COMPOSE_CMD down ) || {
            echo -e "${RED}❌ 停止旧项目失败，已中止迁移。${PLAIN}"
            return 1
        }
    fi

    mkdir -p "$stacks_dir" || return 1
    mv "$source_dir" "$target_dir" || {
        echo -e "${RED}❌ 移动目录失败：${source_dir} -> ${target_dir}${PLAIN}"
        return 1
    }

    compose_name=$(basename "$source_compose")
    if [[ "$compose_name" == docker-compose.y* && ! -f "${target_dir}/compose.yaml" ]]; then
        mv "${target_dir}/${compose_name}" "${target_dir}/compose.yaml" || {
            echo -e "${RED}❌ 重命名 Compose 文件失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在新目录中重新启动 Compose 项目...${PLAIN}"
        ( cd "$target_dir" && $DOCKER_COMPOSE_CMD up -d ) || {
            echo -e "${RED}❌ 新目录启动失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    echo -e "${GREEN}✅ 已迁移到 Dockge stacks：${target_dir}${PLAIN}"
    echo -e "${YELLOW}请在 Dockge 页面里扫描/刷新 stacks 目录后接管。${PLAIN}"
}

func_migrate_compose_to_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}迁移已有 Compose 项目到 Dockge${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适合 Dockge 后安装的场景：把已有 docker-compose.yml / compose.yaml 项目移动到 Dockge stacks 目录。${PLAIN}"
    echo -e "${YELLOW}建议先确认相关服务可以短暂停机，并已做好重要数据备份。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local stacks_dir="/opt/stacks"
    local choice custom_dir i
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")
    mkdir -p "$stacks_dir" || { echo -e "${RED}❌ 无法创建 stacks 目录：${stacks_dir}${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    discover_dockge_migration_candidates "$stacks_dir"

    if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -gt 0 ]]; then
        echo -e "${GREEN}检测到以下可迁移 Compose 项目：${PLAIN}"
        for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
            echo -e "${GREEN}  $((i + 1)). ${DOCKGE_MIGRATION_NAMES[$i]}${PLAIN} ${CYAN}(${DOCKGE_MIGRATION_DIRS[$i]})${PLAIN}"
        done
        echo -e "${BOLD}${YELLOW}  a. 迁移全部检测到的项目${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 未在 /opt 下检测到常见 Compose 项目。${PLAIN}"
    fi
    echo -e "${CYAN}  c. 手动输入项目目录${PLAIN}"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "------------------------------------------------"

    read -p "请选择要迁移的项目: " choice
    case "$choice" in
        0) return ;;
        a|A)
            if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -eq 0 ]]; then
                echo -e "${YELLOW}⚠️ 没有可自动迁移的项目。${PLAIN}"
            else
                for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
                    migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$i]}" "$stacks_dir" || true
                    echo -e "------------------------------------------------"
                done
            fi
            ;;
        c|C)
            read -p "请输入已有 Compose 项目目录: " custom_dir
            migrate_compose_project_to_dockge "$custom_dir" "$stacks_dir"
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DOCKGE_MIGRATION_DIRS[@]} )); then
                migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$((choice - 1))]}" "$stacks_dir"
            else
                echo -e "${RED}❌ 无效选择！${PLAIN}"
            fi
            ;;
    esac

    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 18. 面板救砖/重置 SSL (DRY 优化 + 强健寻径)
# ---------------------------------------------------------
func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚑 面板紧急救砖 / SSL 重置工具${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}⚠️ 核心作用：强制修改面板底层数据库，擦除 SSL 证书路径。${PLAIN}"
    echo -e "当您因为面板开启了 HTTPS 导致：打不开网页、重定向次数过多时，用此功能自救。"
    echo -e "------------------------------------------------"
    
    local yn
    read -p "❓ 确定要重置面板为 HTTP 模式吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        
        # 核心修改：使用我们的全局极简包管理器！兼容了包名差异。
        if ! command -v sqlite3 >/dev/null 2>&1; then
            echo -e "${CYAN}▶ 正在安装 sqlite3 数据库工具...${PLAIN}"
            install_pkg sqlite3 sqlite
        fi
        
        # 停服务
        systemctl stop x-ui >/dev/null 2>&1
        systemctl stop x-panel >/dev/null 2>&1
        
        # 找数据库并擦除
        local db_found=false
        for db_path in "/etc/x-ui/x-ui.db" "/etc/x-panel/x-panel.db"; do
            if [[ -f "$db_path" ]]; then
                sqlite3 "$db_path" "update settings set value='' where key='webCertFile';" 2>/dev/null
                sqlite3 "$db_path" "update settings set value='' where key='webKeyFile';" 2>/dev/null
                echo -e "${GREEN}✅ 数据库底层的 SSL 证书路径已成功抹除！(操作数据库: $db_path)${PLAIN}"
                db_found=true
            fi
        done
        
        if ! $db_found; then
            echo -e "${RED}❌ 未检测到常见面板的数据库文件！您可能没有安装 x-ui 或 x-panel。${PLAIN}"
        fi
        
        # 重启服务
        systemctl start x-ui >/dev/null 2>&1
        systemctl start x-panel >/dev/null 2>&1
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ 面板已尝试降级回 HTTP 模式运行。${PLAIN}"
        echo -e "${YELLOW}💡 强烈建议：立刻打开浏览器的【无痕模式】，使用 http://IP:端口 进行访问测试！${PLAIN}"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 新增功能：网络端口占用可视化排查与进程查杀 (底层调用优化版)
# ---------------------------------------------------------
func_port_kill() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🔍 网络端口占用排查与进程释放${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}当前系统中正在监听的活动端口列表：${PLAIN}"
        echo -e "------------------------------------------------"
        printf "%-10s %-15s %-20s\n" "协议" "端口" "关联进程 (PID)"
        
        ss -tulnp | grep -E 'LISTEN|UNCONN' | while read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local port=$(echo "$line" | awk '{print $5}' | awk -F: '{print $NF}')
            local pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
            local proc=$(echo "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
            
            local proc_info=""
            if [[ -z "$proc" || -z "$pid" ]]; then
                proc_info="系统底层 / 无权限读取"
            else
                proc_info="$proc (PID: $pid)"
            fi
            printf "%-10s %-15s %-20s\n" "$proto" "$port" "$proc_info"
        done | sort -n -k2 | uniq
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}👉 指南：找到您想释放的冲突端口，输入它即可强杀对应进程。${PLAIN}"
        echo -e "${RED}⚠️ 高危：请勿随意终止 sshd (通常为 22) 的端口，否则会断网失联！${PLAIN}"
        echo -e "------------------------------------------------"
        
        local p_choice
        read -p "❓ 请输入要强杀释放的端口号 (输入 0 返回主菜单): " p_choice
        
        if [[ "$p_choice" == "0" ]]; then break; fi
        
        if is_valid_port "$p_choice"; then
            local ssh_match
            ssh_match=$(ss -tulnp 2>/dev/null | awk -v port="$p_choice" '$5 ~ ":" port "$" && $0 ~ /(sshd|ssh)/ {print}')
            if [[ -n "$ssh_match" || "$p_choice" == "22" ]]; then
                echo -e "${RED}❌ 检测到你选择的是 SSH 相关端口或默认 SSH 端口，为避免失联，已拒绝强杀。${PLAIN}"
                sleep 2
                continue
            fi
            confirm_danger "强杀占用端口 ${p_choice} 的进程" "会对 TCP/UDP ${p_choice} 占用进程发送 SIGKILL，相关服务会立即中断。" "如果杀错服务，需要手动重启对应 systemd 服务或容器。" || {
                echo -e "${BLUE}已取消强杀操作。${PLAIN}"
                sleep 1
                continue
            }
            echo -e "${CYAN}▶ 正在调用底层系统命令强杀端口 $p_choice ...${PLAIN}"
            
            # [依赖前置检查]: 确保存在 fuser 工具
            if ! command -v fuser >/dev/null 2>&1; then
                install_pkg psmisc
            fi
            
            # [极简实现]: 一行代码杀掉占用该 TCP/UDP 端口的所有进程
            if fuser -k -9 -n tcp "$p_choice" >/dev/null 2>&1 || fuser -k -9 -n udp "$p_choice" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ 目标进程已被系统底层强制回收 (SIGKILL)。端口已释放！${PLAIN}"
            else
                echo -e "${BLUE}ℹ️ 未发现任何可被终止的进程占用该端口，或权限不足。${PLAIN}"
            fi
            sleep 2
        else
            echo -e "${RED}❌ 输入无效！请输入纯数字端口号。${PLAIN}"
            sleep 1
        fi
    done
}

func_reboot_server() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔁 重启服务器${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    confirm_danger "立即重启服务器" "当前 SSH 会话会断开，所有运行中的服务会短暂中断。" "请确认云厂商控制台可用，并确保关键配置已经保存。" || {
        echo -e "${BLUE}已取消重启操作。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    }
    reboot
}
# ---------------------------------------------------------
# 19. 脚本热更新
# ---------------------------------------------------------
func_update_script() {
    clear
    echo -e "${CYAN}👉 正在从 GitHub 源地址拉取最新版本...${PLAIN}"
    if curl -sL "$UPDATE_URL" -o /tmp/cy_new.sh && bash -n /tmp/cy_new.sh; then
        mv /tmp/cy_new.sh /usr/local/bin/cy
        chmod +x /usr/local/bin/cy
        echo -e "${GREEN}✅ 更新下载并覆盖完成！正在重启面板...${PLAIN}"
        sleep 1
        exec bash /usr/local/bin/cy
    else
        echo -e "${RED}❌ 更新失败！请检查您的网络连通性或 GitHub 地址是否正确。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# ---------------------------------------------------------
# 20. 一键运维预检
# ---------------------------------------------------------
func_preflight_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 一键运维预检 (网络/系统/资源/包管理)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0

    echo -e "${YELLOW}▶ [1/8] 检查系统运行状态...${PLAIN}"
    local sys_state
    sys_state=$(systemctl is-system-running 2>/dev/null || echo "unknown")
    if [[ "$sys_state" == "running" ]]; then
        echo -e "${GREEN}✅ systemd 状态正常: $sys_state${PLAIN}"
        ((ok_count++))
    elif [[ "$sys_state" == "degraded" ]]; then
        echo -e "${YELLOW}⚠️ systemd 状态降级: $sys_state${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ systemd 状态异常: $sys_state${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [2/8] 检查公网连通性...${PLAIN}"
    local ipv4
    ipv4=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null)
    if [[ -n "$ipv4" ]]; then
        echo -e "${GREEN}✅ IPv4 连通正常: ${ipv4}${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 未检测到公网 IPv4，可能为纯 IPv6 或网络受限${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [3/8] 检查 DNS 解析能力...${PLAIN}"
    if getent ahosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${GREEN}✅ DNS 解析正常 (raw.githubusercontent.com)${PLAIN}"
        ((ok_count++))
    else
        echo -e "${RED}❌ DNS 解析失败，后续远程脚本可能无法下载${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [4/8] 检查时间同步状态...${PLAIN}"
    local ntp_sync
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "${GREEN}✅ NTP 时间同步正常${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ NTP 未同步，可能影响证书签发与仓库校验${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/8] 检查磁盘空间...${PLAIN}"
    local root_use
    root_use=$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')
    if [[ -n "$root_use" && "$root_use" -lt 80 ]]; then
        echo -e "${GREEN}✅ 根分区使用率健康: ${root_use}%${PLAIN}"
        ((ok_count++))
    elif [[ -n "$root_use" && "$root_use" -lt 90 ]]; then
        echo -e "${YELLOW}⚠️ 根分区使用率偏高: ${root_use}%${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ 根分区使用率危险: ${root_use:-未知}%${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [6/8] 检查可用内存...${PLAIN}"
    local mem_avail
    mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
    [[ -z "$mem_avail" ]] && mem_avail=$(free -m | awk '/^Mem:/ {print $4}')
    if [[ -n "$mem_avail" && "$mem_avail" -ge 300 ]]; then
        echo -e "${GREEN}✅ 可用内存充足: ${mem_avail}MB${PLAIN}"
        ((ok_count++))
    elif [[ -n "$mem_avail" && "$mem_avail" -ge 150 ]]; then
        echo -e "${YELLOW}⚠️ 可用内存偏低: ${mem_avail}MB${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ 可用内存过低: ${mem_avail:-未知}MB${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [7/8] 检查包管理器占用...${PLAIN}"
    local pkg_busy=false
    if is_debian; then
        pgrep -x apt >/dev/null 2>&1 && pkg_busy=true
        pgrep -x apt-get >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dpkg >/dev/null 2>&1 && pkg_busy=true
    elif is_redhat; then
        pgrep -x yum >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dnf >/dev/null 2>&1 && pkg_busy=true
        pgrep -x rpm >/dev/null 2>&1 && pkg_busy=true
    fi

    if $pkg_busy; then
        echo -e "${YELLOW}⚠️ 检测到包管理器正在运行，建议稍后再安装软件${PLAIN}"
        ((warn_count++))
    else
        echo -e "${GREEN}✅ 包管理器空闲，可安全执行安装任务${PLAIN}"
        ((ok_count++))
    fi

    echo -e "${YELLOW}▶ [8/8] 检查关键命令可用性...${PLAIN}"
    local cmd_miss=()
    command -v curl >/dev/null 2>&1 || cmd_miss+=("curl")
    command -v wget >/dev/null 2>&1 || cmd_miss+=("wget")
    command -v ss >/dev/null 2>&1 || cmd_miss+=("ss")
    if [[ ${#cmd_miss[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 关键命令齐全${PLAIN}"
        ((ok_count++))
    else
        echo -e "${RED}❌ 缺少关键命令: ${cmd_miss[*]}${PLAIN}"
        ((err_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "${CYAN}📌 预检汇总: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "${RED}⚠️ 建议先修复异常项，再进行环境部署和系统改造。${PLAIN}"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "${YELLOW}💡 当前可继续操作，但建议先处理警告项以提升稳定性。${PLAIN}"
    else
        echo -e "${GREEN}🎉 当前环境健康，可直接进行后续部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 21. 配置备份与回滚中心
# ---------------------------------------------------------
func_backup_center() {
    local backup_root="/etc/vps-optimize/backups/manual"
    mkdir -p "$backup_root"

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🗂️ 配置备份与回滚中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "当前备份目录: ${YELLOW}${backup_root}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 创建全量配置备份${PLAIN}       ${YELLOW}(系统/面板/Caddy/脚本配置)${PLAIN}"
        echo -e "${GREEN}  2. 查看现有备份列表${PLAIN}"
        echo -e "${GREEN}  3. 从备份一键回滚${PLAIN}"
        echo -e "${GREEN}  4. 清理旧备份${PLAIN}             ${YELLOW}(仅保留最近 5 份)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local b_choice
        read -p "👉 请选择操作: " b_choice

        case $b_choice in
            1)
                local ts
                ts=$(date +%Y%m%d_%H%M%S)
                local work_dir="/tmp/vps_backup_${ts}"
                local tar_file="${backup_root}/backup_${ts}.tar.gz"
                local manifest_file="${work_dir}/manifest.txt"
                local copied=0

                mkdir -p "$work_dir"
                {
                    echo "VPS-Optimize backup manifest"
                    echo "Created: $(date -Is 2>/dev/null || date)"
                    echo "Backup file: ${tar_file}"
                    echo "Included paths:"
                } > "$manifest_file"

                [[ -f /etc/ssh/sshd_config ]] && mkdir -p "$work_dir/etc/ssh" && cp -a /etc/ssh/sshd_config "$work_dir/etc/ssh/" && echo " - /etc/ssh/sshd_config" >> "$manifest_file" && copied=1
                [[ -f /etc/caddy/Caddyfile ]] && mkdir -p "$work_dir/etc/caddy" && cp -a /etc/caddy/Caddyfile "$work_dir/etc/caddy/" && echo " - /etc/caddy/Caddyfile" >> "$manifest_file" && copied=1
                [[ -d /etc/caddy/conf.d ]] && mkdir -p "$work_dir/etc/caddy" && cp -a /etc/caddy/conf.d "$work_dir/etc/caddy/" && echo " - /etc/caddy/conf.d" >> "$manifest_file" && copied=1
                [[ -f /etc/docker/daemon.json ]] && mkdir -p "$work_dir/etc/docker" && cp -a /etc/docker/daemon.json "$work_dir/etc/docker/" && echo " - /etc/docker/daemon.json" >> "$manifest_file" && copied=1
                [[ -f /etc/fail2ban/jail.local ]] && mkdir -p "$work_dir/etc/fail2ban" && cp -a /etc/fail2ban/jail.local "$work_dir/etc/fail2ban/" && echo " - /etc/fail2ban/jail.local" >> "$manifest_file" && copied=1

                if compgen -G "/etc/sysctl.d/*.conf" >/dev/null 2>&1; then
                    mkdir -p "$work_dir/etc/sysctl.d"
                    cp -a /etc/sysctl.d/*.conf "$work_dir/etc/sysctl.d/" 2>/dev/null
                    echo " - /etc/sysctl.d/*.conf" >> "$manifest_file"
                    copied=1
                fi

                if [[ "$copied" -eq 0 ]]; then
                    rm -rf "$work_dir"
                    echo -e "${YELLOW}⚠️ 未检测到可备份配置文件，已取消创建。${PLAIN}"
                else
                    if tar -czf "$tar_file" -C "$work_dir" . >/dev/null 2>&1; then
                        echo -e "${GREEN}✅ 备份创建成功: ${tar_file}${PLAIN}"
                    else
                        echo -e "${RED}❌ 备份打包失败，请检查磁盘空间与权限。${PLAIN}"
                    fi
                    rm -rf "$work_dir"
                fi
                ;;

            2)
                local backups
                backups=$(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ -z "$backups" ]]; then
                    echo -e "${YELLOW}⚠️ 当前没有任何备份文件。${PLAIN}"
                else
                    echo -e "${CYAN}👇 当前备份列表 (新 -> 旧)：${PLAIN}"
                    local idx=1
                    while IFS= read -r f; do
                        echo -e "  ${GREEN}${idx}.${PLAIN} $(basename "$f")"
                        idx=$((idx+1))
                    done <<< "$backups"
                fi
                ;;

            3)
                mapfile -t backups < <(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    echo -e "${YELLOW}⚠️ 没有可用备份，无法回滚。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                echo -e "${CYAN}👇 可回滚备份如下：${PLAIN}"
                for i in "${!backups[@]}"; do
                    echo -e "  ${GREEN}$((i+1)).${PLAIN} $(basename "${backups[$i]}")"
                done

                local r_choice
                read -p "👉 请输入要回滚的序号: " r_choice
                if ! [[ "$r_choice" =~ ^[0-9]+$ ]] || [[ "$r_choice" -lt 1 ]] || [[ "$r_choice" -gt ${#backups[@]} ]]; then
                    echo -e "${RED}❌ 无效序号，已取消回滚。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                local target_file="${backups[$((r_choice-1))]}"
                read -p "❓ 确认从 [$(basename "$target_file")] 回滚系统配置吗？(y/n): " yn
                if [[ ! "$yn" =~ ^[Yy]$ ]]; then
                    echo -e "${BLUE}已取消回滚操作。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                local restore_dir="/tmp/vps_restore_$(date +%s)"
                mkdir -p "$restore_dir"

                if ! tar -xzf "$target_file" -C "$restore_dir" >/dev/null 2>&1; then
                    rm -rf "$restore_dir"
                    echo -e "${RED}❌ 备份解压失败，回滚中止。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                [[ -f "$restore_dir/etc/ssh/sshd_config" ]] && cp -af "$restore_dir/etc/ssh/sshd_config" /etc/ssh/sshd_config
                [[ -f "$restore_dir/etc/caddy/Caddyfile" ]] && cp -af "$restore_dir/etc/caddy/Caddyfile" /etc/caddy/Caddyfile
                [[ -d "$restore_dir/etc/caddy/conf.d" ]] && mkdir -p /etc/caddy && cp -af "$restore_dir/etc/caddy/conf.d" /etc/caddy/
                [[ -f "$restore_dir/etc/docker/daemon.json" ]] && mkdir -p /etc/docker && cp -af "$restore_dir/etc/docker/daemon.json" /etc/docker/daemon.json
                [[ -f "$restore_dir/etc/fail2ban/jail.local" ]] && mkdir -p /etc/fail2ban && cp -af "$restore_dir/etc/fail2ban/jail.local" /etc/fail2ban/jail.local

                if [[ -d "$restore_dir/etc/sysctl.d" ]]; then
                    mkdir -p /etc/sysctl.d
                    cp -af "$restore_dir/etc/sysctl.d/"*.conf /etc/sysctl.d/ 2>/dev/null
                    sysctl --system >/dev/null 2>&1
                fi

                systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
                systemctl restart caddy >/dev/null 2>&1
                systemctl restart docker >/dev/null 2>&1
                systemctl restart fail2ban >/dev/null 2>&1

                rm -rf "$restore_dir"
                echo -e "${GREEN}✅ 回滚完成！建议立即验证 SSH、反代和容器服务状态。${PLAIN}"
                ;;

            4)
                mapfile -t backups < <(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ ${#backups[@]} -le 5 ]]; then
                    echo -e "${BLUE}当前备份数量不超过 5 份，无需清理。${PLAIN}"
                else
                    for i in "${!backups[@]}"; do
                        if [[ "$i" -ge 5 ]]; then
                            rm -f "${backups[$i]}"
                        fi
                    done
                    echo -e "${GREEN}✅ 清理完成，仅保留最近 5 份备份。${PLAIN}"
                fi
                ;;

            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac

        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 22. 服务健康总览
# ---------------------------------------------------------
func_health_dashboard() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}📈 服务健康总览${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ssh_state="${RED}未运行${PLAIN}"
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
        ssh_state="${GREEN}运行中${PLAIN}"
    fi

    local caddy_state="${RED}未安装/未运行${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            caddy_state="${GREEN}运行中${PLAIN}"
        else
            caddy_state="${YELLOW}已安装但未运行${PLAIN}"
        fi
    fi

    local docker_state="${RED}未安装/未运行${PLAIN}"
    if command -v docker >/dev/null 2>&1; then
        if systemctl is-active --quiet docker; then
            docker_state="${GREEN}运行中${PLAIN}"
        else
            docker_state="${YELLOW}已安装但未运行${PLAIN}"
        fi
    fi

    local f2b_state="${RED}未安装${PLAIN}"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_state="${GREEN}运行中${PLAIN}"
        else
            f2b_state="${YELLOW}已安装但未运行${PLAIN}"
        fi
    fi

    local fw_state="${RED}未启用${PLAIN}"
    if is_debian; then
        if ufw status 2>/dev/null | grep -qwi active; then
            fw_state="${GREEN}UFW 运行中${PLAIN}"
        else
            fw_state="${YELLOW}UFW 未启用${PLAIN}"
        fi
    else
        if systemctl is-active --quiet firewalld; then
            fw_state="${GREEN}Firewalld 运行中${PLAIN}"
        else
            fw_state="${YELLOW}Firewalld 未启用${PLAIN}"
        fi
    fi

    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$current_p" ]] && current_p=$(grep -i '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    current_p=${current_p:-22}

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | grep -c .)

    echo -e "SSH 服务状态       : [ $ssh_state ]  监听端口: ${CYAN}${current_p}${PLAIN}"
    echo -e "Caddy 服务状态     : [ $caddy_state ]"
    echo -e "Docker 服务状态    : [ $docker_state ]"
    echo -e "Fail2ban 服务状态  : [ $f2b_state ]"
    echo -e "防火墙服务状态      : [ $fw_state ]"
    echo -e "失败 systemd 单元数 : ${YELLOW}${failed_units}${PLAIN}"
    echo -e "------------------------------------------------"

    echo -e "${CYAN}🔌 当前监听端口 Top 12${PLAIN}"
    ss -tuln 2>/dev/null | grep -E 'LISTEN|UNCONN' | awk '{print $5}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | sort -nu | head -n 12 | tr '\n' ' '
    echo ""

    local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
    [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"

    if [[ -d "$cert_root" ]]; then
        local cert_total=0
        local cert_warn=0
        while IFS= read -r crt; do
            local end_date ts_left days_left
            end_date=$(openssl x509 -enddate -noout -in "$crt" 2>/dev/null | cut -d= -f2-)
            if [[ -n "$end_date" ]]; then
                ts_left=$(( $(date -d "$end_date" +%s 2>/dev/null) - $(date +%s) ))
                days_left=$(( ts_left / 86400 ))
                cert_total=$((cert_total+1))
                if [[ "$days_left" -le 15 ]]; then
                    cert_warn=$((cert_warn+1))
                fi
            fi
        done < <(find "$cert_root" -type f -name "*.crt" 2>/dev/null)

        echo -e "${CYAN}🔐 证书健康摘要${PLAIN}"
        if [[ "$cert_total" -eq 0 ]]; then
            echo -e "${BLUE}ℹ️ 未检索到可分析证书文件。${PLAIN}"
        else
            echo -e "证书总数: ${GREEN}${cert_total}${PLAIN} | 15天内到期: ${YELLOW}${cert_warn}${PLAIN}"
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}💡 若失败单元 > 0，可执行: systemctl --failed 查看详情。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 23. 网络加速与内核优化菜单 (二级直达)
# ---------------------------------------------------------
func_net_kernel_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🚀 网络性能与内核管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. BBR / 拥塞控制管理${PLAIN}   ${YELLOW}(调用 ylx2016 多内核调优脚本)${PLAIN}"
        echo -e "${GREEN}  2. 动态 TCP 参数调优${PLAIN}    ${YELLOW}(粘贴 Omnitt 参数并自动校验)${PLAIN}"
        echo -e "${GREEN}  3. ZRAM / Swap 内存调优${PLAIN} ${YELLOW}(按内存分档优化小鸡)${PLAIN}"
        echo -e "${GREEN}  4. 安装/切换优化内核${PLAIN}   ${YELLOW}(Cloud/KVM 稳定推荐 / XanMod 高级可选)${PLAIN}"
        echo -e "${GREEN}  5. 清理旧内核${PLAIN}           ${YELLOW}(释放磁盘空间，谨慎操作)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local nk_choice
        read -p "👉 请选择操作: " nk_choice
        case $nk_choice in
            1) func_bbr_manage ;;
            2) func_tcp_tune ;;
            3) func_zram_swap ;;
            4) func_install_kernel ;;
            5) func_clean_kernel ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 24. 面板与节点部署菜单 (二级直达)
# ---------------------------------------------------------
func_panel_deploy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🛰️ 面板、节点与订阅工具部署${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 安装 3x-ui 面板${PLAIN}       ${YELLOW}(mhsanaei 官方脚本)${PLAIN}"
        echo -e "${GREEN}  2. 安装 Sing-box${PLAIN}         ${YELLOW}(甬哥四合一脚本)${PLAIN}"
        echo -e "${GREEN}  3. 安装 Sing-box${PLAIN}         ${YELLOW}(233boy 一键脚本 / sb 管理)${PLAIN}"
        echo -e "${GREEN}  4. 安装 Xray${PLAIN}             ${YELLOW}(233boy 一键脚本)${PLAIN}"
        echo -e "${GREEN}  5. 安装 SublinkPro${PLAIN}       ${YELLOW}(订阅转换与管理面板)${PLAIN}"
        echo -e "${GREEN}  6. 安装 妙妙屋订阅管理${PLAIN}     ${YELLOW}(Docker Compose)${PLAIN}"
        echo -e "${GREEN}  7. 安装 Sub-Store${PLAIN}        ${YELLOW}(HTTP-META / Docker Compose)${PLAIN}"
        echo -e "${BOLD}${YELLOW}  8. UPD 更新订阅管理工具${PLAIN}   ${CYAN}(SublinkPro / 妙妙屋 / Sub-Store)${PLAIN}"
        echo -e "${GREEN}  9. 安装 Dockge${PLAIN}           ${YELLOW}(Docker Compose 管理面板)${PLAIN}"
        echo -e "${GREEN} 10. 迁移 Compose 到 Dockge${PLAIN} ${YELLOW}(Dockge 后安装时接管旧项目)${PLAIN}"
        echo -e "${GREEN} 11. 面板救砖 / 重置 SSL${PLAIN}   ${YELLOW}(回退 HTTP 访问)${PLAIN}"
        echo -e "${GREEN} 12. DNS 流媒体解锁${PLAIN}        ${YELLOW}(Alice DNS 分流脚本)${PLAIN}"
        echo -e "${GREEN} 13. 防 IP 送中脚本${PLAIN}        ${YELLOW}(IP-Sentinel)${PLAIN}"
        echo -e "${GREEN} 14. 端口流量监控${PLAIN}          ${YELLOW}(Port Traffic Dog)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local pd_choice
        read -p "👉 请选择操作: " pd_choice
        case $pd_choice in
            1) func_xpanel ;;
            2) func_singbox ;;
            3) func_singbox_233boy ;;
            4) func_xray_233boy ;;
            5) func_sublinkpro ;;
            6) func_miaomiaowu ;;
            7) func_substore ;;
            8) func_update_subscription_tools ;;
            9) func_dockge ;;
            10) func_migrate_compose_to_dockge ;;
            11) func_rescue_panel ;;
            12) func_dns_unlock ;;
            13) func_ip_sentinel ;;
            14) func_port_dog ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_sni_stack_quick_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧩 443 单入口管理中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：公网只开放 443，由 Nginx 按 SNI 分流到 Caddy、REALITY、3x-ui 和本地网站。${PLAIN}"
        echo -e "${YELLOW}如果只是后续加网站，直接选 [2]，不用重跑首次配置。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 新手常用${PLAIN}"
        echo -e "${GREEN}  1. 首次配置 443 单入口${PLAIN}       ${YELLOW}(第一次部署时使用)${PLAIN}"
        echo -e "${GREEN}  2. 管理网站/反代域名${PLAIN}         ${YELLOW}(新增/删除/查看网站，最常用)${PLAIN}"
        echo -e "${GREEN}  3. 443 单入口链路体检${PLAIN}        ${YELLOW}(检查 Nginx/Caddy/REALITY/面板/安全项)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 配置维护${PLAIN}"
        echo -e "${CYAN}  4. 重新应用上次配置${PLAIN}           ${YELLOW}(读取 sni-stack.env 重新生成配置)${PLAIN}"
        echo -e "${CYAN}  5. 订阅端口 / External Proxy 提示${PLAIN} ${YELLOW}(检查订阅节点是否输出 443)${PLAIN}"
        echo -e "${CYAN}  6. CF DNS / Caddy 证书维护${PLAIN}   ${YELLOW}(重签/软链/清理/修复/回滚)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local sni_choice
        read -p "👉 请选择操作: " sni_choice
        case "$sni_choice" in
            1) func_caddy_cf_reality_wizard ;;
            2) manage_sni_stack_sites ;;
            3) sni_stack_health_check ;;
            4) reapply_sni_stack_from_env ;;
            5) check_sni_stack_subscription_hint ;;
            6) func_caddy_cf_maintenance_menu ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 界面主循环 (新增 IP 防送中 & SublinkPro)
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}🚀 VPS 全能控制面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ ① 推荐流程：新机器先跑这里${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 运维预检与风险扫描    ${YELLOW}(部署前先看端口/系统/服务状态)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 基础环境初始化        ${YELLOW}(工具/时区/系统更新/基础 BBR)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 软件安装与反代分流    ${YELLOW}(Docker/Caddy/WARP/443单入口)${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} 面板与节点部署        ${YELLOW}(3x-ui/Sing-box/订阅管理/救砖)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ② 安全与访问控制${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} SSH 安全加固          ${YELLOW}(改端口/防失联/安全登录)${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} 添加 SSH 公钥         ${YELLOW}(免密登录)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} Fail2ban 防爆破       ${YELLOW}(自动封禁 SSH 爆破 IP)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 防火墙规则管理        ${YELLOW}(放行/删除/查看/关闭)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 系统开关与清理        ${YELLOW}(IPv6/IPv4优先/Ping/自动更新/垃圾清理)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ③ 网络性能与容器${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 网络与内核优化        ${YELLOW}(BBR/TCP/ZRAM/轻量内核)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} Docker 安全管理       ${YELLOW}(本地防穿透/恢复访问)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ④ 诊断、备份与维护${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 测速与质量检测        ${YELLOW}(YABS/流媒体/回程/IP质量)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口排查与释放        ${YELLOW}(查看占用并强杀进程)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 系统硬件探针          ${YELLOW}(CPU/内存/磁盘/网络实时信息)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 服务健康总览          ${YELLOW}(服务状态/证书摘要/端口概览)${PLAIN}"
        echo -e " ${GREEN}16.${PLAIN} 配置备份与回滚        ${YELLOW}(备份/列表/恢复/清理)${PLAIN}"
        echo -e " ${BOLD}${YELLOW}17.${PLAIN} UPD 更新脚本          ${CYAN}(同步 GitHub 最新代码)${PLAIN}"
        echo -e " ${RED}18.${PLAIN} 重启服务器"
        echo -e ""
        echo -e " ${BOLD}${BLUE}▶ ⑤ 高频直达${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} 443 单入口管理中心    ${YELLOW}(初始化/加网站/体检/修复都在这里)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local choice
        read -p "👉 请输入对应数字选择功能: " choice
        
        case $choice in
            1) func_preflight_check ;;
            2) func_base_init ;;
            3) func_env_install ;;
            4) func_panel_deploy_menu ;;
            5) func_security ;;
            6) func_add_ssh_key ;;
            7) func_fail2ban ;;
            8) func_firewall_manage ;;
            9) func_system_tweaks ;;
            10) func_net_kernel_menu ;;
            11) func_docker_manage ;;
            12) func_test_scripts ;;
            13) func_port_kill ;;
            14) func_system_info ;;
            15) func_health_dashboard ;;
            16) func_backup_center ;;
            17) func_update_script ;;
            18) func_reboot_server ;;
            19) func_sni_stack_quick_menu ;;
            0) exit 0 ;;
            *) 
                echo -e "${RED}❌ 无效的输入，请输入菜单中存在的数字！${PLAIN}"
                sleep 1 
                ;;
        esac
    done
}

# --- 启动面板 ---
main_menu
