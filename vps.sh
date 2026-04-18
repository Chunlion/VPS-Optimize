#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能控制面板 (Alice DNS 集成版)
#  Features: IPv4优先/智能防火墙/面板救砖/DNS流媒体解锁/热更新
#  Shortcut: cy
# =========================================================

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 权限检查
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 错误：请以 root 运行本脚本！${PLAIN}"
    exit 1
fi

# 系统识别
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh"

# 快捷指令注册
create_shortcut() {
    local script_path="/usr/local/bin/cy"
    if [[ ! -f "$script_path" ]] && [[ -f "$0" ]]; then
        cp "$(readlink -f "$0")" "$script_path"
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
    if [[ "$OS" =~ debian|ubuntu ]]; then
        apt update -qq && apt install -y curl wget git nano unzip htop iptables iproute2 sqlite3 -qq > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y curl wget git nano unzip htop iptables iproute epel-release sqlite -q > /dev/null 2>&1
    fi

    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础初始化完成，原生 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 系统高级开关 (含 IPv4 优先)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️  系统高级开关 (输入 y 开启, n 关闭)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        [[ "$ipv6_status" == "0" ]] && str_ipv6="${GREEN}开启中${PLAIN}" || str_ipv6="${RED}已禁用${PLAIN}"
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then str_ipv4_first="${GREEN}已优先${PLAIN}"; else str_ipv4_first="${RED}默认(IPv6优先)${PLAIN}"; fi
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        [[ "$ping_status" == "0" ]] && str_ping="${GREEN}允许被Ping${PLAIN}" || str_ping="${RED}禁Ping中${PLAIN}"
        
        echo -e "${GREEN}  1. 管理 IPv6 网络状态${PLAIN}    当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. IPv4 出站优先级增强${PLAIN}   当前: [ $str_ipv4_first ]"
        echo -e "${GREEN}  3. 管理 被人Ping状态${PLAIN}     当前: [ $str_ping ]"
        echo -e "${GREEN}  4. 彻底清理系统垃圾${PLAIN}      (日志/缓存/无用包)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 选择: " tweak_choice
        case $tweak_choice in
            1) read -p "❓ 开启 IPv6？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then rm -f /etc/sysctl.d/99-disable-ipv6.conf; sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1; echo -e "${GREEN}已开启${PLAIN}"; else echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf; sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1; echo -e "${RED}已禁用${PLAIN}"; fi; sleep 1 ;;
            2) read -p "❓ IPv4 优先？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf; echo -e "${GREEN}已设为 IPv4 优先${PLAIN}"; else sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf; echo -e "${BLUE}已恢复默认${PLAIN}"; fi; sleep 1 ;;
            3) read -p "❓ 允许被 Ping？(y/n): " yn; if [[ "$yn" =~ ^[Yy]$ ]]; then rm -f /etc/sysctl.d/99-disable-ping.conf; sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1; echo -e "${GREEN}已允许${PLAIN}"; else echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf; sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1; echo -e "${RED}已禁Ping${PLAIN}"; fi; sleep 1 ;;
            4) if [[ "$OS" =~ debian|ubuntu ]]; then apt autoremove --purge -y; apt clean; else yum autoremove -y; yum clean all; fi; journalctl --vacuum-time=1d > /dev/null 2>&1; echo -e "${GREEN}清理完成${PLAIN}"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# ---------------------------------------------------------
# 3. 常用环境及软件 (Caddy 反代加固)
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
        echo -e "${CYAN} 13. 一键配置 Caddy 反向代理 ${YELLOW}(域名+全自动HTTPS)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 选择: " env_choice
        case $env_choice in
            1) bash <(curl -sL 'https://get.docker.com') ;;
            2) curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh ;;
            3) [[ "$OS" =~ debian|ubuntu ]] && apt install iperf3 -y || yum install iperf3 -y ;;
            4) bash <(curl -L https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh) -i ;;
            5) wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh && chmod +x gost.sh && ./gost.sh ;;
            6) bash <(curl -fsSL https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh) ;;
            7) curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh ;;
            8) wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
            9) wget -N git.io/aria2.sh && chmod +x aria2.sh && ./aria2.sh ;;
            10) wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh && sudo bash install.sh ;;
            11) bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh) ;;
            12) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
            13)
                if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y debian-keyring debian-archive-keyring apt-transport-https -qq && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && apt update && apt install caddy -y; else yum install -y yum-utils && yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo && yum install caddy -y; fi
                read -p "域名: " domain; read -p "端口: " port
                echo -e "$domain {\n    reverse_proxy localhost:$port\n}" > /etc/caddy/Caddyfile
                systemctl restart caddy && echo -e "${GREEN}✅ 反代成功：https://$domain${PLAIN}" ;;
            0) break ;;
        esac
    done
}

# ---------------------------------------------------------
# 19. DNS 流媒体分流解锁 (Alice DNS)
# ---------------------------------------------------------
func_dns_unlock() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔓 DNS 流媒体分流解锁 (Alice DNS)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：${PLAIN}"
    echo -e " 1. 通过修改 DNS 实现 Netflix, Disney+, YouTube 等区域解锁。"
    echo -e " 2. 支持自定义分流，不影响普通上网速度。"
    echo -e " 3. 项目地址：${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}⚠️  注意：执行脚本会修改您的 /etc/resolv.conf，请知悉。${PLAIN}"
    read -p "❓ 确认现在运行该脚本吗？(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        wget https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh && bash dns-unlock.sh
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 4. SSH / 5. Docker / 6. BBR (ylx2016 tcpx.sh)
# ---------------------------------------------------------
func_docker_manage() {
    if ! command -v docker >/dev/null 2>&1; then echo -e "${RED}❌ 未安装 Docker${PLAIN}"; sleep 1; return; fi
    while true; do
        clear; echo -e "${CYAN}🐳 Docker 管理\n1. 开启本地防穿透\n2. 解除防穿透\n0. 返回${PLAIN}"
        read -p "👉 选择: " c
        case $c in
            1) mkdir -p /etc/docker; echo -e '{\n "ip": "127.0.0.1",\n "log-driver": "json-file",\n "log-opts": {"max-size": "50m", "max-file": "3"}\n}' > /etc/docker/daemon.json; systemctl restart docker; echo -e "${GREEN}已开启${PLAIN}" ;;
            2) rm -f /etc/docker/daemon.json; systemctl restart docker; echo -e "${GREEN}已解除${PLAIN}" ;;
            0) break ;;
        esac; sleep 1
    done
}

# ---------------------------------------------------------
# 11. 极速硬件探针 / 12. 测试合集
# ---------------------------------------------------------
func_system_info() {
    clear; os_name=$(cat /etc/os-release | grep -w "PRETTY_NAME" | cut -d= -f2 | sed 's/"//g')
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}OS  :${PLAIN} $os_name | 内核: $(uname -r)\n${YELLOW}CPU :${PLAIN} $(nproc) 核心 | $(lscpu | grep 'Model name:' | sed 's/Model name:\s*//')\n${YELLOW}RAM :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')\n${YELLOW}IPv4:${PLAIN} $(curl -s4 icanhazip.com)\n${YELLOW}IPv6:${PLAIN} $(curl -s6 icanhazip.com || echo '无')\n${CYAN}================================================${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

func_test_scripts() {
    while true; do
        clear; echo -e "${CYAN}📊 综合测试\n1. YABS  2. 融合怪  3. SuperBench  4. bench.sh  5. 解锁  6. 路由  7. IP质量  0. 返回${PLAIN}"
        read -p "👉 选择: " t
        case $t in
            1) wget -qO- yabs.sh | bash ;;
            2) curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && bash ecs.sh ;;
            3) wget -qO- about.superbench.pro | bash ;;
            4) wget -qO- bench.sh | bash ;;
            5) bash <(curl -L -s check.unlock.media) ;;
            6) curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh ;;
            7) bash <(curl -Ls IP.Check.Place) ;;
            0) break ;;
        esac; echo ""; read -n 1 -s -r -p "继续..."
    done
}

# ---------------------------------------------------------
# 17. 热更新 / 18. 救砖
# ---------------------------------------------------------
func_update_script() {
    clear; echo -e "${CYAN}👉 获取最新版...${PLAIN}"
    if curl -sL "$UPDATE_URL" -o /tmp/cy_new.sh; then
        mv /tmp/cy_new.sh "$0"; chmod +x "$0"; cp "$0" /usr/local/bin/cy
        echo -e "${GREEN}✅ 更新完成！${PLAIN}"; sleep 1; exec bash "$0"
    else
        echo -e "${RED}❌ 更新失败！${PLAIN}"; read -n 1 -s -r -p "返回..."
    fi
}

func_rescue_panel() {
    clear; echo -e "${RED}⚠️ 重置面板 SSL 为 HTTP？${PLAIN}"; read -p "(y/n): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        db_path=""; [[ -f "/etc/x-ui/x-ui.db" ]] && db_path="/etc/x-ui/x-ui.db"; [[ -f "/etc/x-panel/x-panel.db" ]] && db_path="/etc/x-panel/x-panel.db"
        if [[ -n "$db_path" ]]; then sqlite3 "$db_path" "update settings set value='' where key='webCertFile';" "update settings set value='' where key='webKeyFile';"; fi
        systemctl restart x-ui x-panel >/dev/null 2>&1; echo -e "${GREEN}✅ 已重置${PLAIN}"
    fi; read -n 1 -s -r -p "返回..."
}

# ---------------------------------------------------------
# 主菜单
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}🚀 VPS 终极全能控制面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}${BLUE}▶ 基础与系统环境${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 基础环境初始化   ${YELLOW}(必备工具/激活BBR)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 系统高级开关     ${YELLOW}(IPv4优先/禁Ping/清理)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 常用环境与软件   ${YELLOW}(宝塔/Caddy/哪吒/WARP等)${PLAIN}"
        echo -e " ${BOLD}${BLUE}▶ 安全与网络优化${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} SSH 安全加固     ${YELLOW}(修改端口/自动放行防火墙)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} Docker 深度管理  ${YELLOW}(本地防穿透保护机制)${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} BBR 增强管理     ${YELLOW}(调用 ylx2016 终极脚本)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} 动态 TCP 调优    ${YELLOW}(联动 Omnitt 极致参数)${PLAIN}"
        echo -e " ${BOLD}${BLUE}▶ 内核与内存榨取${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 智能内存调优     ${YELLOW}(ZRAM压缩+Swap 详尽分级)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 换装 Cloud内核   ${YELLOW}(释放驱动冗余，KVM 专属)${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 卸载冗余旧内核   ${YELLOW}(释放磁盘空间，需谨慎)${PLAIN}"
        echo -e " ${BOLD}${BLUE}▶ 探针与节点建站${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} 极速硬件探针     ${YELLOW}(查看本机配置与实时负载)${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 综合测试合集     ${YELLOW}(融合怪/流媒体/IP质量/路由)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口流量监控     ${YELLOW}(拉取运行 Port Traffic Dog)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 安装 x-panel     ${YELLOW}(多协议面板官方一键脚本)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 安装 Sing-box    ${YELLOW}(勇哥四合一官方一键脚本)${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} ${CYAN}${BOLD}DNS流媒体解锁${PLAIN}    ${YELLOW}(Alice DNS 分流解锁脚本)${PLAIN}"
        echo -e " ${GREEN}18.${PLAIN} ${RED}${BOLD}面板救砖/重置SSL${PLAIN} ${YELLOW}(无法访问面板应急手段)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${YELLOW}17.${PLAIN} ${BOLD}一键更新脚本${PLAIN}     ${RED}16.${PLAIN} 重启服务器  ${RED}0.${PLAIN} 退出"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 选择: " choice
        case $choice in
            1) func_base_init ;; 2) func_system_tweaks ;; 3) func_env_install ;;
            4) func_security ;; 5) func_docker_manage ;; 6) func_bbr_manage ;;
            7) func_tcp_tune ;; 8) func_zram_swap ;; 9) func_install_kernel ;;
            10) func_clean_kernel ;; 11) func_system_info ;; 12) func_test_scripts ;;
            13) wget -qO t.sh https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh && bash t.sh ;;
            14) bash <(curl -Ls https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh) ;;
            15) bash <(curl -fsSL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh) ;;
            19) func_dns_unlock ;; 18) func_rescue_panel ;; 17) func_update_script ;;
            16) reboot ;; 0) exit 0 ;;
            *) echo -e "${RED}无效输入！${PLAIN}"; sleep 1 ;;
        esac
    done
}

main_menu
