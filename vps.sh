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
                echo -e "${YELLOW}⚠️ 快捷指令本地注册挂起，请稍后在面板中使用 [23] 更新脚本完成注册。${PLAIN}"
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
        echo -e "${BOLD}🛡️  系统安全防火墙深度管理${PLAIN}"
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
        echo -e "${GREEN}  1. 开启防火墙并智能追加当前活动端口${PLAIN} ${YELLOW}(不覆盖原有规则)${PLAIN}"
        echo -e "${GREEN}  2. 手动添加允许列表 (支持批量/范围)${PLAIN}"
        echo -e "${GREEN}  3. 从列表中删除端口 (支持批量/范围)${PLAIN}"
        echo -e "${GREEN}  4. 查看当前已放行端口列表${PLAIN}"
        echo -e "${RED}  5. 禁用并彻底关闭防火墙${PLAIN}"
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
        echo -e "${BOLD}⚙️  系统高级开关与设置${PLAIN}"
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
        echo -e "${GREEN}  1. 管理 IPv6 网络状态${PLAIN}    当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. IPv4 出站优先级增强${PLAIN}   当前: [ $str_ipv4_first ]"
        echo -e "${GREEN}  3. 管理 被人Ping状态${PLAIN}     当前: [ $str_ping ]"
        echo -e "${GREEN}  4. 管理 自动安全更新${PLAIN}     当前: [ $str_update ]"
        echo -e "${GREEN}  5. 彻底清理系统垃圾${PLAIN}      (日志/缓存/无用包)"
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

is_valid_domain() {
    local domain="$1"
    echo "$domain" | grep -Eq '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
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

    cf_token=$(echo "$cf_token_raw" | tr -d '\r\n')
    if [[ -z "$cf_token" || ! -x "$acme_bin" || -z "$domain" ]]; then
        return 1
    fi

    acme_log="/tmp/vps_acme_${domain}_$(date +%s).log"

    # 强制使用 Let's Encrypt，避免 ZeroSSL 触发 EAB 依赖导致签发失败。
    "$acme_bin" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

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
        echo -e "${BOLD}📦 常用环境及软件一键安装库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. Docker 引擎   ${YELLOW}  2. Python 环境   ${GREEN}  3. iperf3 工具${PLAIN}"
        echo -e "${GREEN}  4. Realm 转发    ${YELLOW}  5. Gost 隧道     ${GREEN}  6. 极光面板${PLAIN}"
        echo -e "${GREEN}  7. 哪吒监控      ${YELLOW}  8. WARP (CF)     ${GREEN}  9. Aria2 下载${PLAIN}"
        echo -e "${GREEN} 10. 宝塔面板      ${YELLOW}  11. PVE 虚拟化    ${GREEN}  12. Argox 节点${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${CYAN} 13. 配置 Caddy 反代   ${YELLOW}  14. 查看 Caddy 证书路径${PLAIN}"
        echo -e "${CYAN} 15. Caddy独立跳过验证 ${YELLOW}  16. 清空 Caddy 配置文件${PLAIN}"
        echo -e "${RED} 17. 删除底层 ACME证书${PLAIN}"
        echo -e "${GREEN} 18. Reality+CF DNS 一键反代与证书${PLAIN} ${YELLOW}(不占用443/支持多域名)${PLAIN}"
        echo -e "${GREEN} 19. CF DNS 二次维护菜单${PLAIN} ${YELLOW}(重签/重建链接/清理/重载)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local env_choice
        read -p "👉 选择: " env_choice
        
        case $env_choice in
            1) 
                echo -e "${CYAN}▶ 正在拉取 Docker 引擎...${PLAIN}"
                bash <(curl -sL 'https://get.docker.com') || echo -e "${RED}❌ Docker 安装失败，请检查网络！${PLAIN}"
                ;;
            2) run_safe "安装 Python 环境" bash -c "curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh" ;;
            3) 
                if is_debian; then run_safe "安装 iperf3" apt install iperf3 -y; else run_safe "安装 iperf3" yum install iperf3 -y; fi 
                ;;
            4) bash <(curl -L https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh) -i ;;
            5) run_safe "下载 Gost" bash -c "wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh && chmod +x gost.sh && ./gost.sh" ;;
            6) bash <(curl -fsSL https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh) ;;
            7) 
                curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh 
                echo -e "\n${YELLOW}💡 哪吒自定义代码提示 (去除动效并固定顶部)：${PLAIN}"
                echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
                ;;
            8) wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
            9) wget -N git.io/aria2.sh && chmod +x aria2.sh && ./aria2.sh ;;
            10) wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh && bash install.sh ;;
            11) bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh) ;;
            12) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
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
                
                # 增加了端口只能是纯数字的防呆校验
                if [[ -z "$domain" || -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}❌ 域名为空或端口格式错误！已取消配置。${PLAIN}"
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
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 新增功能：Reality 443 复用 + Cloudflare DNS 证书自动化
# ---------------------------------------------------------
func_caddy_cf_reality_wizard() {
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
    if [[ ! -x "$acme_bin" ]]; then
        echo -e "${CYAN}▶ 正在安装 acme.sh...${PLAIN}"
        if ! bash -c "curl -fsSL https://get.acme.sh | sh -s email=admin@localhost" >/dev/null 2>&1; then
            echo -e "${RED}❌ acme.sh 安装失败，请检查网络后重试。${PLAIN}"
            return
        fi
    fi
    if [[ ! -x "$acme_bin" ]]; then
        echo -e "${RED}❌ 未找到 acme.sh，可执行文件异常。${PLAIN}"
        return
    fi
    "$acme_bin" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

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
        echo -e "${BOLD}🛠️ CF DNS 二次维护菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 查看当前 CF DNS 管理域名与路径${PLAIN}"
        echo -e "${GREEN}  2. 更新 Cloudflare API Token${PLAIN}"
        echo -e "${GREEN}  3. 重新签发指定域名证书${PLAIN}"
        echo -e "${GREEN}  4. 重建 /root/cert 证书软链接${PLAIN}"
        echo -e "${GREEN}  5. 删除指定域名配置与证书${PLAIN}"
        echo -e "${GREEN}  6. 校验并重载 Caddy${PLAIN}"
        echo -e "${GREEN}  7. 重建清单文件${PLAIN}"
        echo -e "${GREEN}  8. 一键体检（Token/证书/监听/后端）${PLAIN}"
        echo -e "${GREEN}  9. 一键自动修复（常见问题）${PLAIN}"
        echo -e "${GREEN} 10. 隔离旧配置（避免 Caddy 抢占 443）${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local m_choice
        read -p "👉 请选择操作: " m_choice

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
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "${GREEN}✅ Caddy 配置校验通过，已重启生效。${PLAIN}"
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
        echo -e "${YELLOW}⚠️ 警告：此操作将删除您所有的 Caddy 独立反代配置（原文件会自动备份）。${PLAIN}"
        read -p "❓ 确定要清空 Caddy 配置吗？(y/n): " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            
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
    read -p "❓ 确定要清理吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
        echo -e "${YELLOW}💡 请先在主菜单进入 [3 常用环境及软件] 安装 Docker。${PLAIN}"
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
        echo -e "${BOLD}🐳 Docker 深度管理面板 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 开启本地防穿透保护${PLAIN} (限制映射端口仅 127.0.0.1 访问)"
        echo -e "${GREEN}  2. 解除本地防穿透保护${PLAIN} (恢复全网可访，${YELLOW}且不破坏您的原有配置${PLAIN})"
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
# 9. 换装 Cloud/KVM 优化内核 (终极版：架构强拦截 + GRUB 强接管)
# ---------------------------------------------------------
func_install_kernel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}☁️  换装 Cloud/KVM 优化内核${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # [拦截机制 1]：虚拟化环境判断 (核心防呆)
    local virt
    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    if [[ "$virt" =~ lxc|openvz ]]; then
        echo -e "${RED}❌ 致命错误：检测到当前 VPS 为 $virt 容器架构！${PLAIN}"
        echo -e "${YELLOW}💡 容器与母机共享内核，绝对无法更改内核。操作已安全中止。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # [拦截机制 2]：CPU 架构判断
    if [[ "$(uname -m)" != "x86_64" ]]; then
        echo -e "${RED}❌ 致命错误：优化内核仅支持 x86_64 (amd64) 架构，本机为 $(uname -m)！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # [拦截机制 3]：状态防呆 (判断是否已经是目标内核)
    if uname -r | grep -qE "kvm|cloud"; then
        echo -e "${GREEN}✅ 系统当前已运行 KVM/Cloud 优化内核 ($(uname -r))，无需重复安装！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${CYAN}▶ 正在为您静默安装专属优化内核...${PLAIN}"

    local kernel_keyword=""
    if [[ "$OS" == "debian" ]]; then
        install_pkg linux-image-cloud-amd64
        kernel_keyword="cloud"
    elif [[ "$OS" == "ubuntu" ]]; then
        install_pkg linux-image-kvm
        kernel_keyword="kvm"
    else
        echo -e "${RED}❌ 抱歉，换装优化内核功能目前仅支持 Debian 和 Ubuntu 系统！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # ==========================================
    # 核心黑科技：GRUB 引导层强制接管
    # ==========================================
    # 1. 动态提取刚刚装好的目标内核完整版本号
    local target_v
    target_v=$(dpkg -l | awk '/^ii[[:space:]]+linux-image-[0-9]/ && /'"$kernel_keyword"'/ {print $2}' | sed 's/linux-image-//' | sort -V | tail -n 1)

    if [[ -n "$target_v" ]]; then
        echo -e "${CYAN}▶ 正在接管 GRUB 底层引导，锁定启动内核为: $target_v ...${PLAIN}"
        
        # 修改 GRUB 默认行为，允许保存上一次的启动项
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
        grep -q "^GRUB_SAVEDEFAULT=true" /etc/default/grub || echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
        update-grub >/dev/null 2>&1

        # 精确寻址 GRUB 菜单 ID
        local menu_1
        local menu_2
        menu_1=$(grep -i "submenu 'Advanced options for" /boot/grub/grub.cfg | cut -d"'" -f2 | head -n 1)
        menu_2=$(grep -i "menuentry '.*$target_v.*'" /boot/grub/grub.cfg | grep -iv "recovery" | cut -d"'" -f2 | head -n 1)

        if [[ -n "$menu_1" && -n "$menu_2" ]]; then
            # 强制设定默认启动项为新内核
            grub-set-default "$menu_1>$menu_2"
            echo -e "${GREEN}✅ GRUB 引导接管成功！已为您消除重启死循环的风险。${PLAIN}"
        else
            echo -e "${YELLOW}⚠️ 警告：GRUB 菜单寻址失败。系统可能仍以最高版本号的旧内核启动。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 错误：内核包似乎未成功安装，请检查系统源或网络状况！${PLAIN}"
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}⚠️ 核心生效指引：${PLAIN}"
    echo -e "1. 新内核引导已配置完毕，请先选择主菜单的 ${RED}[24] 重启服务器${PLAIN}。"
    echo -e "2. 重启后系统将自动切入极简 $kernel_keyword 内核。"
    echo -e "3. 届时您可安心进入面板选择 ${GREEN}[12] 卸载冗余旧内核${PLAIN}，清理残余垃圾包。"
    
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
        echo -e "${GREEN}  1. YABS 硬件性能测试  ${YELLOW}  2. 融合怪终极详细测速${PLAIN}"
        echo -e "${GREEN}  3. SuperBench 综合测速${YELLOW}  4. bench.sh 基础测试${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁详细检测 ${YELLOW}  6. 三网回程路由测试${PLAIN}"
        echo -e "${GREEN}  7. IP 质量与欺诈度检测${YELLOW}  8. NodeSeek 综合测试${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local t
        read -p "👉 请输入对应序号选择: " t
        case $t in
            1) wget -qO- yabs.sh | bash ;;
            2) curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && bash ecs.sh ;;
            3) wget -qO- about.superbench.pro | bash ;;
            4) wget -qO- bench.sh | bash ;;
            5) bash <(curl -L -s check.unlock.media) ;;
            6) curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh ;;
            7) bash <(curl -Ls IP.Check.Place) ;;
            8) bash <(curl -sL https://run.NodeQuality.com) ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "测试完成，按任意键继续..."
    done
}
# ---------------------------------------------------------
# 13, 14, 15 面板与流量狗快速部署
# ---------------------------------------------------------
func_port_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取并执行 Port Traffic Dog 监控狗...${PLAIN}"
    wget -qO dog.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh && chmod +x dog.sh && ./dog.sh
}

func_xpanel() {
    clear
    echo -e "${CYAN}👉 正在拉取 mhsanaei 的官方 x-panel 一键脚本...${PLAIN}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
}

func_singbox() {
    clear
    echo -e "${CYAN}👉 正在拉取甬哥的 Sing-box 四合一脚本...${PLAIN}"
    bash <(curl -fsSL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
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
    read -n 1 -s -r -p "按任意键返回..."
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
        echo -e "${CYAN}▶ 正在拉取并执行 hotyue 的 IP-Sentinel 主脚本...${PLAIN}"
        bash <(curl -sL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh)
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 新增功能：安装 SublinkPro (强大的订阅转换与管理面板)
# ---------------------------------------------------------
func_sublinkpro() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔗 安装 SublinkPro (节点订阅转换与管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 1. 检查 Docker 引擎
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 常用环境] 中安装 Docker。${PLAIN}"
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
    echo -e "${YELLOW}💡 SublinkPro 将被安全部署在: ${CYAN}$install_dir${PLAIN}"
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
      - "8000:8000"
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
        echo -e "🌐 ${BOLD}面板访问地址:${PLAIN} http://$ip:8000"
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
        
        if [[ -n "$p_choice" && "$p_choice" =~ ^[0-9]+$ ]]; then
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
    local backup_root="/opt/vps-panel-backups"
    mkdir -p "$backup_root"

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🗂️ 配置备份与回滚中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "当前备份目录: ${YELLOW}${backup_root}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 创建全量配置备份${PLAIN}"
        echo -e "${GREEN}  2. 查看现有备份列表${PLAIN}"
        echo -e "${GREEN}  3. 从备份一键回滚${PLAIN}"
        echo -e "${GREEN}  4. 清理旧备份 (仅保留最近 5 份)${PLAIN}"
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
                local copied=0

                mkdir -p "$work_dir"

                [[ -f /etc/ssh/sshd_config ]] && mkdir -p "$work_dir/etc/ssh" && cp -a /etc/ssh/sshd_config "$work_dir/etc/ssh/" && copied=1
                [[ -f /etc/caddy/Caddyfile ]] && mkdir -p "$work_dir/etc/caddy" && cp -a /etc/caddy/Caddyfile "$work_dir/etc/caddy/" && copied=1
                [[ -d /etc/caddy/conf.d ]] && mkdir -p "$work_dir/etc/caddy" && cp -a /etc/caddy/conf.d "$work_dir/etc/caddy/" && copied=1
                [[ -f /etc/docker/daemon.json ]] && mkdir -p "$work_dir/etc/docker" && cp -a /etc/docker/daemon.json "$work_dir/etc/docker/" && copied=1
                [[ -f /etc/fail2ban/jail.local ]] && mkdir -p "$work_dir/etc/fail2ban" && cp -a /etc/fail2ban/jail.local "$work_dir/etc/fail2ban/" && copied=1

                if compgen -G "/etc/sysctl.d/*.conf" >/dev/null 2>&1; then
                    mkdir -p "$work_dir/etc/sysctl.d"
                    cp -a /etc/sysctl.d/*.conf "$work_dir/etc/sysctl.d/" 2>/dev/null
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
        echo -e "${BOLD}🚀 网络加速与内核优化${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. BBR 增强管理${PLAIN}      ${YELLOW}(调用 ylx2016 多核调优脚本)${PLAIN}"
        echo -e "${GREEN}  2. 动态 TCP 调优${PLAIN}     ${YELLOW}(粘贴 Omnitt 参数并自动校验)${PLAIN}"
        echo -e "${GREEN}  3. 智能内存调优${PLAIN}      ${YELLOW}(ZRAM + Swap 分级策略)${PLAIN}"
        echo -e "${GREEN}  4. 换装轻量内核${PLAIN}      ${YELLOW}(Cloud/KVM 优化内核)${PLAIN}"
        echo -e "${GREEN}  5. 卸载冗余旧内核${PLAIN}    ${YELLOW}(清理磁盘空间)${PLAIN}"
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
        echo -e "${BOLD}🛰️ 面板与节点部署${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 安装 x-panel${PLAIN}        ${YELLOW}(mhsanaei 官方脚本)${PLAIN}"
        echo -e "${GREEN}  2. 安装 Sing-box${PLAIN}      ${YELLOW}(甬哥四合一脚本)${PLAIN}"
        echo -e "${GREEN}  3. 安装 SublinkPro${PLAIN}    ${YELLOW}(订阅转换与管理面板)${PLAIN}"
        echo -e "${GREEN}  4. 面板救砖/重置SSL${PLAIN}   ${YELLOW}(回退 HTTP 访问)${PLAIN}"
        echo -e "${GREEN}  5. DNS 流媒体解锁${PLAIN}     ${YELLOW}(Alice DNS 分流脚本)${PLAIN}"
        echo -e "${GREEN}  6. 防 IP 送中脚本${PLAIN}     ${YELLOW}(IP-Sentinel)${PLAIN}"
        echo -e "${GREEN}  7. 端口流量监控${PLAIN}       ${YELLOW}(Port Traffic Dog)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local pd_choice
        read -p "👉 请选择操作: " pd_choice
        case $pd_choice in
            1) func_xpanel ;;
            2) func_singbox ;;
            3) func_sublinkpro ;;
            4) func_rescue_panel ;;
            5) func_dns_unlock ;;
            6) func_ip_sentinel ;;
            7) func_port_dog ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
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
        
        echo -e " ${BOLD}${BLUE}▶ 高优先直达${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 一键运维预检      ${YELLOW}(先检查再部署，避免踩坑)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 基础环境初始化    ${YELLOW}(工具/时区/基础 BBR)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 常用环境与软件库  ${YELLOW}(Docker/Caddy/WARP/面板等)${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} 系统高级开关      ${YELLOW}(IPv6/IPv4 优先/禁 Ping/自动更新)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} 防火墙深度管理    ${YELLOW}(放行/删除/开关/查看规则)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ 安全与运维${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} SSH 安全加固      ${YELLOW}(端口迁移与防失联)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} Fail2ban 防护     ${YELLOW}(防爆破封禁)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 添加 SSH 公钥     ${YELLOW}(免密登录)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} Docker 深度管理   ${YELLOW}(防穿透与配置回滚)${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 网络与内核优化菜单 ${YELLOW}(BBR/TCP/ZRAM/内核管理)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} 测速与质量检测合集 ${YELLOW}(YABS/流媒体/回程/IP质量)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ 部署与排障${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 面板与节点部署菜单 ${YELLOW}(x-panel/Sing-box/救砖/DNS)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口排查与释放     ${YELLOW}(查看占用并强杀进程)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 极速硬件探针       ${YELLOW}(系统与资源实时信息)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 配置备份与回滚中心 ${YELLOW}(备份/列表/恢复/清理)${PLAIN}"
        echo -e " ${GREEN}16.${PLAIN} 服务健康总览       ${YELLOW}(服务状态/证书摘要/端口概览)${PLAIN}"
        echo -e " ${YELLOW}17.${PLAIN} 一键更新脚本       ${CYAN}(同步 GitHub 最新代码)${PLAIN}"
        echo -e " ${RED}18.${PLAIN} 重启服务器"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local choice
        read -p "👉 请输入对应数字选择功能: " choice
        
        case $choice in
            1) func_preflight_check ;;
            2) func_base_init ;;
            3) func_env_install ;;
            4) func_system_tweaks ;;
            5) func_firewall_manage ;;
            6) func_security ;;
            7) func_fail2ban ;;
            8) func_add_ssh_key ;;
            9) func_docker_manage ;;
            10) func_net_kernel_menu ;;
            11) func_test_scripts ;;
            12) func_panel_deploy_menu ;;
            13) func_port_kill ;;
            14) func_system_info ;;
            15) func_backup_center ;;
            16) func_health_dashboard ;;
            17) func_update_script ;;
            18) reboot ;;
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

