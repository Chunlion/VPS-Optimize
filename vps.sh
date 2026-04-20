#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 全能控制面板 
#  Features: IPv4优先/智能防火墙/面板救砖/DNS流媒体解锁/热更新/安全加固
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

UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh"

# --- 全局快捷键注册 ---
create_shortcut() {
    local script_path="/usr/local/bin/cy"
    if [[ ! -f "$script_path" ]]; then
        # 优先尝试从远端直接拉取最新版本作为快捷方式 (完美兼容 curl 管道运行)
        curl -sL "$UPDATE_URL" -o "$script_path" 2>/dev/null || cp "$(readlink -f "$0")" "$script_path" 2>/dev/null
        chmod +x "$script_path"
        echo -e "${GREEN}✅ 快捷指令 'cy' 已全局注册！下次可直接输入 cy 唤出面板。${PLAIN}"
        sleep 1
    fi
}

# ---------------------------------------------------------
# 1. 基础环境初始化
# ---------------------------------------------------------
func_base_init() {
    clear
    echo -e "${CYAN}👉 正在安装基础工具、限制日志并开启基础 BBR...${PLAIN}"
    
    if is_debian; then
        apt update -qq
        apt install -y curl wget git nano unzip htop iptables iproute2 sqlite3 jq -qq > /dev/null 2>&1
    elif is_redhat; then
        yum install -y curl wget git nano unzip htop iptables iproute epel-release sqlite jq -q > /dev/null 2>&1
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
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础初始化完成，原生 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# ★ 防火墙专属管理面板 (新增功能)
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
        
        if [[ "$fw_status" == "active" || -n "$fw_status" ]]; then 
            str_fw="${GREEN}运行中${PLAIN}"
        else 
            str_fw="${RED}已关闭 / 未配置${PLAIN}"
        fi

        echo -e "当前防火墙状态: [ $str_fw ]"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 开启防火墙并智能放行当前活动端口${PLAIN}"
        echo -e "${GREEN}  2. 手动添加允许列表 (放行新端口)${PLAIN}"
        echo -e "${GREEN}  3. 从列表中删除端口 (取消放行)${PLAIN}"
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
                    apt install ufw -y >/dev/null 2>&1
                    ufw --force reset >/dev/null 2>&1
                    ufw default deny incoming >/dev/null 2>&1
                    ufw default allow outgoing >/dev/null 2>&1
                    for p in $active_ports; do ufw allow "$p" >/dev/null 2>&1; done
                    ufw --force enable >/dev/null 2>&1
                else
                    yum install firewalld -y >/dev/null 2>&1
                    systemctl enable --now firewalld >/dev/null 2>&1
                    for p in $active_ports; do
                        firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1
                        firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1
                    done
                    firewall-cmd --reload >/dev/null 2>&1
                fi
                echo -e "${GREEN}✅ 防火墙已成功开启！自动放行了以下端口: $(echo $active_ports | tr '\n' ' ')${PLAIN}"
                sleep 2
                ;;
            2)
                local add_p
                read -p "👉 请输入要放行的端口号 (如 443): " add_p
                if [[ -n "$add_p" && "$add_p" =~ ^[0-9]+$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        ufw allow "$add_p" >/dev/null 2>&1
                    else
                        firewall-cmd --permanent --add-port="${add_p}/tcp" >/dev/null 2>&1
                        firewall-cmd --permanent --add-port="${add_p}/udp" >/dev/null 2>&1
                        firewall-cmd --reload >/dev/null 2>&1
                    fi
                    echo -e "${GREEN}✅ 端口 $add_p 已成功添加至允许列表！${PLAIN}"
                else
                    echo -e "${RED}❌ 无效的端口号！${PLAIN}"
                fi
                sleep 2
                ;;
            3)
                local del_p
                read -p "👉 请输入要删除放行的端口号 (如 8080): " del_p
                if [[ -n "$del_p" && "$del_p" =~ ^[0-9]+$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        ufw delete allow "$del_p" >/dev/null 2>&1
                    else
                        firewall-cmd --permanent --remove-port="${del_p}/tcp" >/dev/null 2>&1
                        firewall-cmd --permanent --remove-port="${del_p}/udp" >/dev/null 2>&1
                        firewall-cmd --reload >/dev/null 2>&1
                    fi
                    echo -e "${GREEN}✅ 端口 $del_p 已从允许列表中移除！${PLAIN}"
                else
                    echo -e "${RED}❌ 无效的端口号！${PLAIN}"
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
            0) 
                break 
                ;;
            *)
                echo -e "${RED}❌ 无效的选择！${PLAIN}"
                sleep 1
                ;;
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
        echo -e "${GREEN}  5. 防火墙深度管理面板${PLAIN}  (放行/端口控制/开关)"
        echo -e "${GREEN}  6. 彻底清理系统垃圾${PLAIN}      (日志/缓存/无用包)"
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
                # 调用独立的防火墙面板
                func_firewall_manage
                ;;
            6) 
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
# 3. 常用环境及软件 (Caddy 防覆盖优化)
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
        echo -e "${GREEN} 10. 宝塔面板      ${YELLOW} 11. PVE 虚拟化    ${GREEN} 12. Argox 节点${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${CYAN} 13. 配置 Caddy 反代   ${YELLOW} 14. 查看 Caddy 证书路径${PLAIN}"
        echo -e "${CYAN} 15. Caddy独立跳过验证 ${YELLOW} 16. 清空 Caddy 配置文件${PLAIN}"
        echo -e "${RED} 17. 删除底层 ACME证书${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "------------------------------------------------"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local env_choice
        read -p "👉 选择: " env_choice
        
        case $env_choice in
            1) bash <(curl -sL 'https://get.docker.com') ;;
            2) curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh ;;
            3) if is_debian; then apt install iperf3 -y; else yum install iperf3 -y; fi ;;
            4) bash <(curl -L https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh) -i ;;
            5) wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh && chmod +x gost.sh && ./gost.sh ;;
            6) bash <(curl -fsSL https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh) ;;
            7) 
                curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh 
                echo -e "\n${YELLOW}💡 哪吒自定义代码提示 (去除动效并固定顶部)：${PLAIN}"
                echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
                ;;
            8) wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
            9) wget -N git.io/aria2.sh && chmod +x aria2.sh && ./aria2.sh ;;
            10) wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh && sudo bash install.sh ;;
            11) bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh) ;;
            12) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
            13)
                if is_debian; then 
                    apt install -y debian-keyring debian-archive-keyring apt-transport-https -qq && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && apt update && apt install caddy -y
                else 
                    yum install -y yum-utils && yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo && yum install caddy -y
                fi
                
                local domain
                local port
                local is_https
                
                read -p "请输入解析后的域名 (如 panel.site.com): " domain
                read -p "请输入面板本地映射端口 (如 40000): " port
                
                if [[ -z "$domain" || -z "$port" ]]; then
                    echo -e "${RED}❌ 域名或端口不能为空！已取消配置。${PLAIN}"
                else
                    echo -e "${YELLOW}❓ 后端面板是否开启了自带的 SSL 证书？(y/n)${PLAIN}"
                    read -p "👉 您的选择 (选 n 则正常反代 http): " is_https
                    
                    # 备份原始 Caddyfile
                    # 1. 备份时锁定时间戳变量，防止秒级误差导致回滚失败
                    local backup_file="/etc/caddy/Caddyfile.bak_$(date +%s)"
                    
                    if [[ -f /etc/caddy/Caddyfile ]]; then
                        cp /etc/caddy/Caddyfile "$backup_file"
                        echo -e "${BLUE}已备份原配置为 $backup_file${PLAIN}"
                    fi
                    
                    if [[ "$is_https" =~ ^[Yy]$ ]]; then
                        cat <<EOF >> /etc/caddy/Caddyfile

$domain {
    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
                    else
                        cat <<EOF >> /etc/caddy/Caddyfile

$domain {
    reverse_proxy localhost:$port
}
EOF
                    fi
                    # 引入 caddy validate 语法检查机制
                    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                        systemctl reload caddy >/dev/null 2>&1
                        echo -e "${GREEN}✅ Caddy 反代配置已追加并生效！请访问 https://$domain${PLAIN}"
                    else
                        echo -e "${RED}❌ 致命错误：生成的 Caddyfile 存在语法错误！${PLAIN}"
                        echo -e "${YELLOW}正在回滚配置以防止网站整体宕机...${PLAIN}"
                        mv "$backup_file" /etc/caddy/Caddyfile
                    fi
                fi
                ;;
            14) func_view_caddy_cert ;;
            15) func_caddy_add_insecure ;;
            16) func_caddy_clear_config ;;
            17) func_caddy_delete_cert ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}" ;;
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
    
    # 提取 Caddyfile 中的域名 (排除注释，简单匹配)
    local domains
    domains=$(grep -vE '^[[:space:]]*#' /etc/caddy/Caddyfile | grep '{' | awk '{print $1}' | tr -d '{')
    
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
# 新增功能：独立追加 Caddy 跳过不安全证书反代块
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
    
    if [[ -z "$domain" || -z "$port" ]]; then
        echo -e "${RED}❌ 域名或端口不能为空！已取消操作。${PLAIN}"
    else
        # 备份配置
        local backup_file="/etc/caddy/Caddyfile.bak_$(date +%s)"
        cp /etc/caddy/Caddyfile "$backup_file"
        
        # 直接追加跳过验证的逻辑块
        cat <<EOF >> /etc/caddy/Caddyfile

$domain {
    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
        # 引入 caddy validate 语法检查机制
        if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            systemctl reload caddy >/dev/null 2>&1
            echo -e "${GREEN}✅ 独立跳过验证配置已成功追加到 Caddyfile 并生效！${PLAIN}"
        else
            echo -e "${RED}❌ 致命错误：追加的配置导致语法错误！${PLAIN}"
            echo -e "${YELLOW}正在回滚配置以防止网站整体宕机...${PLAIN}"
            mv "$backup_file" /etc/caddy/Caddyfile
        fi
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：清空 Caddy 配置文件
# ---------------------------------------------------------
func_caddy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清空 Caddy 配置文件${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ -f /etc/caddy/Caddyfile ]]; then
        echo -e "${YELLOW}⚠️ 警告：此操作将删除您所有的 Caddy 反代配置（原文件会自动备份）。${PLAIN}"
        read -p "❓ 确定要清空 Caddyfile 吗？(y/n): " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)"
            # 写入一行注释，防止 Caddy 因为文件完全空而报警告
            echo "# Caddyfile Cleared" > /etc/caddy/Caddyfile
            systemctl restart caddy
            echo -e "${GREEN}✅ 配置文件已清空并重启服务。现在您可以重新添加纯净的配置了！${PLAIN}"
        else
            echo -e "${BLUE}已取消清空操作。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 未检测到 Caddy 配置文件！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 优化重构：核弹级域名证书清理与解除端口占用
# ---------------------------------------------------------
func_caddy_delete_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}☢️ 核弹级：彻底清理域名证书与解除占用${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}💡 场景：当 Caddy 与面板 (如 x-ui) 申请证书起冲突，或需要彻底释放域名时使用。${PLAIN}"

    read -p "👉 请输入要强杀清理的精准域名 (如 panel.site.com): " domain
    if [[ -z "$domain" ]]; then
        echo -e "${RED}❌ 域名不能为空！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "\n${CYAN}▶ 正在执行核弹级清理流程...${PLAIN}"

    # 1. 停止 Caddy，强制释放 80/443 端口
    systemctl stop caddy >/dev/null 2>&1
    echo -e "${GREEN}✅ [1/4] 已强制停止 Caddy 服务，释放 80/443 端口。${PLAIN}"

    # 2. 深度清理 Caddy 底层证书缓存
    local caddy_paths=("/var/lib/caddy/.local/share/caddy/certificates" "/root/.local/share/caddy/certificates")
    local caddy_found=false
    for cp in "${caddy_paths[@]}"; do
        if [[ -d "$cp" ]]; then
            # 查找并删除对应域名的目录
            local target=$(find "$cp" -type d -name "*${domain}*" -print -quit 2>/dev/null)
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

    # 3. 清理 acme.sh 残留 (x-ui/宝塔常用的底层工具)
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

    # 4. 检查 Caddyfile 死灰复燃风险
    if grep -q "$domain" /etc/caddy/Caddyfile 2>/dev/null; then
        echo -e "${YELLOW}⚠️ [4/4] 警告: /etc/caddy/Caddyfile 中仍然包含该域名的配置块！${PLAIN}"
        echo -e "   如果此时执行 systemctl start caddy，它会立刻再次抢占端口去申请证书。"
        echo -e "   ${RED}👉 请使用主菜单的 [16] 清空配置，或手动编辑文件删掉该域名。${PLAIN}"
    else
        echo -e "${GREEN}✅ [4/4] Caddyfile 中未发现该域名绑定。${PLAIN}"
    fi

    echo -e "------------------------------------------------"
    echo -e "${GREEN}🎉 清理彻底完成！当前系统 80/443 端口已处于完全解绑的真空状态。${PLAIN}"
    echo -e "${CYAN}下一步建议：${PLAIN}"
    echo -e "A. 如果你想让 x-ui 自己去申请证书，现在就可以去了。"
    echo -e "B. 如果你想遵循最佳实践，请在 x-ui 关闭 TLS，然后使用主菜单的 [13] 让 Caddy 反代 HTTP。"
    
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 4. SSH 安全加固 (完美兼容 Ubuntu Socket 与 CentOS SELinux)
# ---------------------------------------------------------
func_security() {
    clear
    local current_p
    current_p=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    current_p=${current_p:-22}
    
    local final_p
    read -p "当前 SSH 端口为 $current_p, 请输入新端口 [1-65535] (直接回车保持不变): " final_p
    final_p=${final_p:-$current_p}
    
    if [[ "$final_p" != "$current_p" ]]; then
        
        # [检查项 1]: 严格的端口合法性校验
        if ! [[ "$final_p" =~ ^[0-9]+$ ]] || [ "$final_p" -lt 1 ] || [ "$final_p" -gt 65535 ]; then
            echo -e "${RED}❌ 错误：无效的端口号！必须是 1-65535 之间的纯数字。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 1. 修改传统配置文件
        sed -i '/^[[:space:]]*#\?Port /d' /etc/ssh/sshd_config
        echo "Port $final_p" >> /etc/ssh/sshd_config
        
        # 2. [CentOS 专属修复]: SELinux 底层策略放行
        if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
            echo -e "${YELLOW}检测到 SELinux 处于开启状态，正在配置底层端口安全策略...${PLAIN}"
            if command -v semanage >/dev/null 2>&1; then
                # -a 是添加，-m 是修改（如果端口已被其他规则占用但允许复用）
                semanage port -a -t ssh_port_t -p tcp "$final_p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$final_p" 2>/dev/null
            else
                echo -e "${RED}❌ 致命错误：SELinux 已开启但缺少 semanage 工具，强行重启将导致 SSH 彻底瘫痪失联！${PLAIN}"
                echo -e "${YELLOW}已自动为您回滚配置。请先运行命令安装工具：${PLAIN}"
                echo -e "CentOS 7: ${GREEN}yum install policycoreutils-python${PLAIN}"
                echo -e "CentOS 8/9+: ${GREEN}yum install policycoreutils-python-utils${PLAIN}"
                
                # 触发防砖回滚机制
                sed -i '/^[[:space:]]*Port /d' /etc/ssh/sshd_config
                echo "Port $current_p" >> /etc/ssh/sshd_config
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi

        # [检查项 2]: 重启前配置语法核验 (防失联核心机制)
        if ! sshd -t; then
            echo -e "${RED}❌ 致命错误：SSH 配置存在语法异常，已终止重启以防止失联！${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        
        # 3. 尝试放行防火墙 (UFW / Firewalld / iptables)
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_p"/tcp >/dev/null 2>&1; fi
        if command -v firewall-cmd >/dev/null 2>&1; then 
            firewall-cmd --permanent --add-port="$final_p"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        iptables -I INPUT -p tcp --dport "$final_p" -j ACCEPT 2>/dev/null
        
        # 4. 核心修复：兼容新版 Ubuntu 的 ssh.socket 机制
        if systemctl list-unit-files | grep -q "^ssh.socket"; then
            echo -e "${YELLOW}检测到 Ubuntu 新版 ssh.socket 机制，正在进行底层端口覆写...${PLAIN}"
            mkdir -p /etc/systemd/system/ssh.socket.d
            cat <<EOF > /etc/systemd/system/ssh.socket.d/port.conf
[Socket]
ListenStream=
ListenStream=$final_p
EOF
            systemctl daemon-reload >/dev/null 2>&1
            systemctl restart ssh.socket >/dev/null 2>&1
        fi
        
        # 5. 重启传统服务
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        
        echo -e "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行系统防火墙/SELinux！${PLAIN}"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
        echo -e "${YELLOW}⚠️ 终极保命提示：${PLAIN}"
        echo -e "现在的这扇 SSH 窗口【千万不要关闭】！"
        echo -e "请立刻打开您的 SSH 客户端使用新端口 $final_p 新建一个连接进行测试。"
        echo -e "如果云服务商（如阿里云/腾讯云）网页端有【安全组】，请确保也已放行 $final_p 端口！"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
    else
        echo -e "${BLUE}端口未做更改。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增：Fail2ban 防爆破系统管理 (动态端口检测)
# ---------------------------------------------------------
func_fail2ban() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Fail2ban 防爆破系统管理${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 核心逻辑：实时提取当前系统生效的 SSH 端口
    local current_p
    # 尝试从系统底层网络状态中提取 (支持 Systemd Socket 激活机制)
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    
    # 如果 ss 命令失败或被精简，回退到文件正则解析
    if [[ -z "$current_p" ]]; then
        current_p=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    fi
    
    # 最终默认值兜底
    current_p=${current_p:-22}
    
    echo -e "${YELLOW}👉 当前系统检测到的 SSH 端口为: ${GREEN}$current_p${PLAIN}"
    echo -e "------------------------------------------------"
    
    # 检查安装状态
    local f2b_status="${RED}未安装${PLAIN}"
    if command -v fail2ban-server >/dev/null 2>&1; then
        f2b_status="${GREEN}已运行${PLAIN}"
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
                if is_debian; then
                    apt update -qq >/dev/null 2>&1
                    apt install fail2ban -y -qq >/dev/null 2>&1
                elif is_redhat; then
                    yum install fail2ban -y -q >/dev/null 2>&1
                fi
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
            if is_debian; then
                apt purge fail2ban -y -qq >/dev/null 2>&1
            elif is_redhat; then
                yum remove fail2ban -y -q >/dev/null 2>&1
            fi
            rm -rf /etc/fail2ban
            echo -e "${GREEN}✅ Fail2ban 已彻底卸载！${PLAIN}"
            ;;
        0) return ;;
        *) echo -e "${RED}❌ 无效的输入！${PLAIN}" ;;
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
        # 检查是否已经存在相同公钥
        if grep -q "$ssh_key" ~/.ssh/authorized_keys; then
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
# 5. Docker 深度管理 (防覆盖备份版)
# ---------------------------------------------------------
func_docker_manage() {
    if ! command -v docker >/dev/null 2>&1; then 
        clear
        echo -e "${RED}❌ 错误：检测到系统尚未安装 Docker 引擎！${PLAIN}"
        echo -e "${YELLOW}💡 请先在主菜单进入 [3 常用环境及软件] 安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    while true; do
        clear
        local docker_ver
        docker_ver=$(docker -v | awk '{print $3}' | tr -d ',')
        
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🐳 Docker 深度管理面板 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 开启本地防穿透保护${PLAIN} (限制映射端口仅 127.0.0.1 访问)"
        echo -e "${GREEN}  2. 解除本地防穿透保护${PLAIN} (允许 0.0.0.0 全网直接通过IP访问)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        
        local c
        read -p "👉 请选择操作: " c
        case $c in
            1) 
                mkdir -p /etc/docker
                # 检查并备份
                if [[ -f /etc/docker/daemon.json ]]; then
                    cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak_$(date +%s)"
                    echo -e "${YELLOW}⚠️ 已将原有 Docker 配置文件备份为 .bak 时间戳文件。${PLAIN}"
                    # 使用 jq 进行非破坏性合并，保留用户原有配置
                    if jq '. + {"ip": "127.0.0.1", "log-driver": "json-file", "log-opts": {"max-size": "50m", "max-file": "3"}}' /etc/docker/daemon.json > /tmp/daemon_tmp.json 2>/dev/null; then
                        mv /tmp/daemon_tmp.json /etc/docker/daemon.json
                    else
                        echo -e "${RED}❌ 原 daemon.json JSON 格式已损坏，防穿透配置合并失败！${PLAIN}"
                        # 恢复刚备份的文件
                        mv "/etc/docker/daemon.json.bak_$(date +%s -d 'now')" /etc/docker/daemon.json 2>/dev/null
                    fi
                else
                    # 文件不存在时初始生成
                    cat <<EOF > /etc/docker/daemon.json
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
                systemctl restart docker >/dev/null 2>&1
                echo -e "${GREEN}✅ 已开启安全保护，Docker 容器端口仅限本地反代访问！${PLAIN}" 
                sleep 2
                ;;
            2) 
                if [[ -f /etc/docker/daemon.json ]]; then
                    rm -f /etc/docker/daemon.json
                    systemctl restart docker >/dev/null 2>&1
                    echo -e "${GREEN}✅ 已解除限制，容器端口恢复公网可访状态。${PLAIN}" 
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
# 7. 动态 TCP 调优 (Omnitt)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "请浏览器打开: ${BLUE}https://omnitt.com/${PLAIN} 生成针对您网络环境的 TCP 参数"
    read -p "👉 您准备好粘贴代码了吗？(y 继续 / n 取消): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then return; fi
    
    local temp_f="/etc/sysctl.d/99-omnitt-tune.conf"
    > "$temp_f"
    echo -e "\n${CYAN}👇 请在此右键粘贴代码，完成后在新的一行输入 EOF 并回车：${PLAIN}"
    
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ "$line" == "EOF" || "$line" == "eof" ]] && break
        echo "$line" >> "$temp_f"
    done
    
    if [[ -s "$temp_f" ]]; then
        sysctl -p "$temp_f" >/dev/null 2>&1
        echo -e "${GREEN}✅ 调优参数应用成功！${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 未检测到有效输入，已取消。${PLAIN}"
        rm -f "$temp_f"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 8. 智能内存调优 (修复版：全自动匹配 + 强制挂载保障)
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
    
    # 【修复 1】：自动根据内存分配挡位
    if [[ -z "$choice" ]]; then
        if [[ "$mem" -lt 1024 ]]; then
            choice=1
        elif [[ "$mem" -le 4096 ]]; then
            choice=2
        else
            choice=3
        fi
        echo -e "${YELLOW}💡 您按下了回车，系统已根据本机内存 (${mem}MB) 自动选择：[ 挡位 $choice ]${PLAIN}"
        sleep 1.5
    fi
    
    if is_debian; then
        echo -e "${CYAN}正在配置 ZRAM 内存压缩引擎...${PLAIN}"
        apt update -qq >/dev/null 2>&1
        apt install zram-tools -y -qq >/dev/null 2>&1
        
        # 【修复 2】：强制加载内核模块，防止精简系统缺失
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
        
        # 写入配置文件
        cat <<EOF > "$zram_conf"
ALGO=zstd
PERCENT=$percent
PRIORITY=100
EOF
        
        # 重载并强制重启服务
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable zramswap >/dev/null 2>&1
        systemctl restart zramswap >/dev/null 2>&1
        
        # 【修复 3】：双重检查机制。如果重启服务后仍未生成 swap，强制调用底层脚本挂载
        if ! grep -q zram /proc/swaps; then
            if command -v zramswap >/dev/null 2>&1; then
                zramswap start >/dev/null 2>&1
            elif [[ -x /usr/sbin/zramswap ]]; then
                /usr/sbin/zramswap start >/dev/null 2>&1
            fi
        fi
        
        # 修改内核 Swappiness 倾向
        echo "vm.swappiness = $swap_val" > /etc/sysctl.d/99-zram-swappiness.conf
        sysctl -p /etc/sysctl.d/99-zram-swappiness.conf >/dev/null 2>&1
        
        # 最终验证结果
        if grep -q zram /proc/swaps; then
            echo -e "${GREEN}✅ ZRAM 调优落地完成！(已设置: ${percent}% 压缩比, ${swap_val} 交换倾向)${PLAIN}"
        else
            echo -e "${RED}❌ 警告：配置已下发，但系统内核似乎拒绝挂载 ZRAM。这通常是因为 VPS 商家阉割了内核功能（例如廉价的 LXC 容器）。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 抱歉，当前系统并非 Debian/Ubuntu 衍生系，暂不支持自动化 ZRAM 调优。${PLAIN}"
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 9. 换装 Cloud/KVM 优化内核 (防卡死与架构硬拦截版)
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
        echo -e "${RED}❌ 致命错误：当前脚本的优化包仅支持 x86_64 (amd64) 架构！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 设置非交互环境变量，防止 apt 安装内核时弹出 GRUB 紫色界面导致脚本假死
    export DEBIAN_FRONTEND=noninteractive

    if [[ "$OS" == "debian" ]]; then
        echo -e "${CYAN}👉 检测到 Debian，正在静默安装 linux-image-cloud-amd64...${PLAIN}"
        if apt-get update -qq && apt-get install -yq linux-image-cloud-amd64; then
            update-grub >/dev/null 2>&1
            echo -e "${GREEN}✅ Debian Cloud 内核安装并已刷新引导！${PLAIN}"
        else
            echo -e "${RED}❌ 安装失败！请检查系统源。${PLAIN}"
        fi
        
    elif [[ "$OS" == "ubuntu" ]]; then
        echo -e "${CYAN}👉 检测到 Ubuntu，正在静默安装 linux-image-kvm...${PLAIN}"
        if apt-get update -qq && apt-get install -yq linux-image-kvm; then
            update-grub >/dev/null 2>&1
            echo -e "${GREEN}✅ Ubuntu KVM 内核安装并已刷新引导！${PLAIN}"
        else
            echo -e "${RED}❌ 安装失败！请检查系统源。${PLAIN}"
        fi
        
    else
        echo -e "${RED}❌ 抱歉，换装优化内核功能目前仅支持 Debian 和 Ubuntu 系统！${PLAIN}"
    fi
    
    # 清理环境变量，防止影响后续面板操作
    unset DEBIAN_FRONTEND

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}⚠️ 核心生效指引 (请务必阅读)：${PLAIN}"
    echo -e "1. 新内核已经躺在您的硬盘里了。请先选择菜单的 ${RED}[21] 重启服务器${PLAIN}。"
    echo -e "2. Linux 默认优先启动版本号最高的内核。如果重启后执行 ${GREEN}uname -r${PLAIN} 发现依然是旧版 (未带 kvm/cloud 字样)；"
    echo -e "3. 请进入面板 ${GREEN}[12] 卸载冗余旧内核${PLAIN}，把带有 generic 字样的旧内核全删掉，再次重启即可强制生效！"
    
    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 10. 清理冗余旧内核 (带 Ubuntu/Debian 提示适配)
# ---------------------------------------------------------
func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}"
    else
        echo -e "当前正在运行的内核为: ${GREEN}$(uname -r)${PLAIN}"
        echo -e "${RED}⚠️  高危警告：绝对不要卸载当前正在运行的内核！${PLAIN}"
        echo -e "${RED}⚠️  也不要卸载带有 cloud (Debian) 或 kvm (Ubuntu) 字样的内核！${PLAIN}"
        echo -e "------------------------------------------------"
        dpkg --list | grep linux-image
        echo -e "------------------------------------------------"
        
        local old_k
        read -p "👉 请复制上方要卸载的旧内核包全名并粘贴 (直接回车取消): " old_k
        if [[ -n "$old_k" ]]; then
            # 同样加入错误捕获
            if apt purge -y "$old_k" && update-grub && apt autoremove --purge -y; then
                echo -e "${GREEN}✅ 旧内核 [$old_k] 清理完成！磁盘空间已释放。${PLAIN}"
            else
                echo -e "${RED}❌ 清理失败！找不到该内核包或存在依赖问题。${PLAIN}"
            fi
        else
            echo -e "${BLUE}已取消卸载操作。${PLAIN}"
        fi
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
        echo -e "${GREEN}  7. IP 质量与欺诈度检测${PLAIN}"
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
    echo -e "${CYAN}👉 正在拉取 xeefei 的官方 x-panel 一键脚本...${PLAIN}"
    bash <(curl -Ls https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh)
}

func_singbox() {
    clear
    echo -e "${CYAN}👉 正在拉取勇哥的 Sing-box 四合一脚本...${PLAIN}"
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
# 18. 面板救砖/重置 SSL
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
        
        # 确保 sqlite3 可用
        if ! command -v sqlite3 >/dev/null 2>&1; then
            if is_debian; then apt install sqlite3 -y >/dev/null; elif is_redhat; then yum install sqlite -y >/dev/null; fi
        fi
        
        # 停服务
        systemctl stop x-ui >/dev/null 2>&1
        systemctl stop x-panel >/dev/null 2>&1
        
        # 找数据库并擦除
        local db_path=""
        [[ -f "/etc/x-ui/x-ui.db" ]] && db_path="/etc/x-ui/x-ui.db"
        [[ -f "/etc/x-panel/x-panel.db" ]] && db_path="/etc/x-panel/x-panel.db"
        
        if [[ -n "$db_path" ]]; then
            sqlite3 "$db_path" "update settings set value='' where key='webCertFile';" 2>/dev/null
            sqlite3 "$db_path" "update settings set value='' where key='webKeyFile';" 2>/dev/null
            echo -e "${GREEN}✅ 数据库底层的 SSL 证书路径已成功抹除！${PLAIN}"
        else
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
# 19. 脚本热更新
# ---------------------------------------------------------
func_update_script() {
    clear
    echo -e "${CYAN}👉 正在从 GitHub 源地址拉取最新版本...${PLAIN}"
    if curl -sL "$UPDATE_URL" -o /tmp/cy_new.sh && bash -n /tmp/cy_new.sh; then
        mv /tmp/cy_new.sh "$0"
        chmod +x "$0"
        cp "$0" /usr/local/bin/cy
        echo -e "${GREEN}✅ 更新下载并覆盖完成！正在重启面板...${PLAIN}"
        sleep 1
        exec bash "$0"
    else
        echo -e "${RED}❌ 更新失败！请检查您的网络连通性或 GitHub 地址是否正确。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# ---------------------------------------------------------
# 界面主循环 (视觉逻辑重排版)
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}🚀 VPS 全能控制面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 基础与系统环境${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 基础环境初始化   ${YELLOW}(必备工具/时区校准/激活BBR)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 系统高级开关     ${YELLOW}(IPv4优先/防火墙开关/禁Ping)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 常用环境与软件   ${YELLOW}(宝塔/Caddy/哪吒探针/WARP等)${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 安全与网络优化${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} SSH 安全加固     ${YELLOW}(修改默认端口/防失联占用检查)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} Fail2ban 防护    ${YELLOW}(自动检测SSH新端口防爆破封禁)${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} 添加 SSH 公钥    ${YELLOW}(配置密钥免密登录，提升安全性)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} Docker 深度管理  ${YELLOW}(配置防穿透隔离机制/自动备份)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} BBR 增强管理     ${YELLOW}(调用 ylx2016 终极多核调优脚本)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 动态 TCP 调优    ${YELLOW}(联动 Omnitt 生成防呆极致参数)${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 内核与内存榨取${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 智能内存调优     ${YELLOW}(ZRAM压缩+Swap 详尽分级策略落地)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} 换装 Cloud内核   ${YELLOW}(释放驱动冗余，KVM 虚拟专属)${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 卸载冗余旧内核   ${YELLOW}(清理磁盘无用空间，需谨慎)${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ 探针与节点建站${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 极速硬件探针     ${YELLOW}(全屏显示本机配置与实时负载)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 综合测试合集     ${YELLOW}(融合怪/流媒体/IP欺诈质量/路由)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 端口流量监控     ${YELLOW}(拉取并运行 Port Traffic Dog)${PLAIN}"
        echo -e " ${GREEN}16.${PLAIN} 安装 x-panel     ${YELLOW}(多协议面板，调用 xeefei 脚本)${PLAIN}"
        echo -e " ${GREEN}17.${PLAIN} 安装 Sing-box    ${YELLOW}(甬哥四合一强大官方一键脚本)${PLAIN}"
        echo -e " ${GREEN}18.${PLAIN} ${RED}${BOLD}面板救砖/重置SSL${PLAIN} ${YELLOW}(无法访问面板时的备用手段)${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} ${CYAN}${BOLD}DNS流媒体解锁${PLAIN}    ${YELLOW}(Alice DNS 区域分流解锁脚本)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${YELLOW}20.${PLAIN} ${BOLD}一键更新脚本${PLAIN}     ${CYAN}(同步 GitHub 最新代码)${PLAIN}"
        echo -e " ${RED}21.${PLAIN} 重启服务器       ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local choice
        read -p "👉 请输入对应数字选择功能: " choice
        
        case $choice in
            1) func_base_init ;;
            2) func_system_tweaks ;;
            3) func_env_install ;;
            4) func_security ;;
            5) func_fail2ban ;;
            6) func_add_ssh_key ;;
            7) func_docker_manage ;;
            8) func_bbr_manage ;;
            9) func_tcp_tune ;;
            10) func_zram_swap ;;
            11) func_install_kernel ;;
            12) func_clean_kernel ;;
            13) func_system_info ;;
            14) func_test_scripts ;;
            15) func_port_dog ;;
            16) func_xpanel ;;
            17) func_singbox ;;
            18) func_rescue_panel ;;
            19) func_dns_unlock ;;
            20) func_update_script ;;
            21) reboot ;;
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
