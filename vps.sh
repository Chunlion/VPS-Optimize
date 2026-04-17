#!/usr/bin/env bash

# =========================================================
#  Project:  VPS 终极全能控制面板 (神级合集版)
#  Features: y/n强交互/智能防火墙/全能工具/BBR/测试合集
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
[[ $EUID -ne 0 ]] && echo -e "${RED}❌ 错误：请以 root 运行！${PLAIN}" && exit 1

# 系统识别
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

# 快捷指令注册
create_shortcut() {
    local script_path="/usr/local/bin/cy"
    if [ ! -f "$script_path" ] && [ -f "$0" ]; then
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
        apt update -qq && apt install -y curl wget git nano unzip htop iptables -qq > /dev/null 2>&1
    elif [[ "$OS" =~ centos|rhel|rocky|almalinux ]]; then
        yum install -y curl wget git nano unzip htop iptables epel-release -q > /dev/null 2>&1
    fi

    # 日志限制
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    
    # 强制开启基础 BBR
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础初始化完成，BBR已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 2. 系统高级开关 (y/n 模式 + 智能防火墙)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️  系统高级开关 (输入 y 开启, n 关闭)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        [ "$ipv6_status" == "0" ] && str_ipv6="${GREEN}开启中${PLAIN}" || str_ipv6="${RED}已禁用${PLAIN}"
        
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        [ "$ping_status" == "0" ] && str_ping="${GREEN}允许被Ping${PLAIN}" || str_ping="${RED}禁Ping中${PLAIN}"

        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
            fw_status=$(ufw status 2>/dev/null | grep -wi active)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
            fw_status=$(systemctl is-active firewalld 2>/dev/null)
        fi
        [ "$update_status" == "active" ] && str_update="${GREEN}开启中${PLAIN}" || str_update="${RED}已禁用${PLAIN}"
        [ "$fw_status" == "active" ] || [ -n "$fw_status" ] && str_fw="${GREEN}开启中${PLAIN}" || str_fw="${RED}已禁用${PLAIN}"

        echo -e "${GREEN}  1. IPv6 网络${PLAIN}      当前状态: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. 被人Ping状态${PLAIN}   当前状态: [ $str_ping ]"
        echo -e "${GREEN}  3. 自动更新服务${PLAIN}   当前状态: [ $str_update ]"
        echo -e "${GREEN}  4. 系统安全防火墙${PLAIN} 当前状态: [ $str_fw ]"
        echo -e "${GREEN}  5. 彻底清理系统垃圾${PLAIN} (日志/缓存/无用包)"
        echo -e "${GREEN}  6. 查看防火墙规则${PLAIN}   (放行规则列表)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " tweak_choice

        case $tweak_choice in
            1)
                read -p "❓ 是否开启 IPv6？(y 开启 / n 关闭): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then rm -f /etc/sysctl.d/99-disable-ipv6.conf; sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null; echo -e "${GREEN}✅ IPv6 已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf; sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null; echo -e "${RED}✅ IPv6 已禁用${PLAIN}"; fi; sleep 1 ;;
            2)
                read -p "❓ 是否允许被 Ping？(y 允许 / n 禁止): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then rm -f /etc/sysctl.d/99-disable-ping.conf; sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null; echo -e "${GREEN}✅ 已允许被Ping${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf; sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null; echo -e "${RED}✅ 已禁止被Ping${PLAIN}"; fi; sleep 1 ;;
            3)
                read -p "❓ 是否开启自动更新？(y 开启 / n 关闭): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y unattended-upgrades -qq >/dev/null; systemctl enable --now unattended-upgrades >/dev/null;
                    else yum install -y dnf-automatic -q >/dev/null; systemctl enable --now dnf-automatic.timer >/dev/null; fi; echo -e "${GREEN}✅ 自动更新已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null;
                    else systemctl disable --now dnf-automatic.timer >/dev/null; fi; echo -e "${RED}✅ 自动更新已禁用${PLAIN}"; fi; sleep 1 ;;
            4)
                read -p "❓ 是否开启防火墙并自动放行活动端口？(y/n): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then
                    echo -e "${CYAN}👉 正在嗅探活动端口并放行...${PLAIN}"
                    # 嗅探当前正在监听的公网端口 (排除 127.0.0.1)
                    active_ports=$(ss -tuln | grep -E 'LISTEN|UNCONN' | grep -v '127.0.0.1' | awk '{print $5}' | rev | cut -d: -f1 | rev | sort -nu | grep -E '^[0-9]+$')
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        apt install ufw -y >/dev/null; ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null;
                        for p in $active_ports; do ufw allow $p >/dev/null; done; ufw --force enable >/dev/null;
                    else
                        yum install firewalld -y >/dev/null; systemctl enable --now firewalld >/dev/null;
                        for p in $active_ports; do firewall-cmd --permanent --add-port=${p}/tcp >/dev/null; firewall-cmd --permanent --add-port=${p}/udp >/dev/null; done; firewall-cmd --reload >/dev/null;
                    fi
                    echo -e "${GREEN}✅ 防火墙已开启！自动放行了端口: $active_ports${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then ufw disable >/dev/null; else systemctl disable --now firewalld >/dev/null; fi; echo -e "${RED}✅ 防火墙已关闭${PLAIN}"; fi; read -n 1 -s -r -p "按任意键继续..." ;;
            6)
                if [[ "$OS" =~ debian|ubuntu ]]; then ufw status verbose; else firewall-cmd --list-all; fi; read -n 1 -s -r -p "按任意键继续..." ;;
            5)
                echo -e "${CYAN}👉 正在深度清理垃圾...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt autoremove --purge -y; apt clean; else yum autoremove -y; yum clean all; fi
                journalctl --vacuum-time=1d > /dev/null 2>&1; echo -e "${GREEN}✅ 清理完成！${PLAIN}"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# ---------------------------------------------------------
# 3. 常用环境与软件一键安装 (豪华合集)
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
        echo -e "${CYAN} 13. 一键配置 Caddy 反向代理 ${YELLOW}(解决面板无法访问/域名HTTPS)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择操作: " env_choice
        case $env_choice in
            1) bash <(curl -sL 'https://get.docker.com') ;;
            2) curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh ;;
            3) apt install iperf3 -y || yum install iperf3 -y ;;
            4) bash <(curl -L https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh) -i ;;
            5) wget --no-check-certificate -O gost.sh https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh && chmod +x gost.sh && ./gost.sh ;;
            6) bash <(curl -fsSL https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh) ;;
            7) 
               curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh
               echo -e "\n${YELLOW}💡 面板自定义代码提示：${PLAIN}"
               echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
               ;;
            8) wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
            9) wget -N git.io/aria2.sh && chmod +x aria2.sh && ./aria2.sh ;;
            10) wget -O install.sh http://v7.hostcli.com/install/install-ubuntu_6.0.sh && sudo bash install.sh ;;
            11) bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh) ;;
            12) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
            13)
                echo -e "${CYAN}👉 正在安装 Caddy 并配置反代...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then apt install -y debian-keyring debian-archive-keyring apt-transport-https -qq && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list && apt update && apt install caddy -y; else yum install -y yum-utils && yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo && yum install caddy -y; fi
                read -p "请输入域名 (如 site.com): " domain
                read -p "请输入本地映射端口 (如 2053): " port
                echo -e "$domain {\n    reverse_proxy localhost:$port\n}" > /etc/caddy/Caddyfile
                systemctl restart caddy && echo -e "${GREEN}✅ 反代成功！访问 https://$domain${PLAIN}"
                ;;
            0) break ;;
        esac
        echo ""; read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 4. SSH 安全加固 (含自动放行) / 5. Docker 深度管理
# ---------------------------------------------------------
func_security() {
    clear
    current_port=$(grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
    current_port=${current_port:-22}
    echo -e "当前 SSH 端口为: ${GREEN}${current_port}${PLAIN}"
    read -p "请输入新 SSH 端口 (回车保持不变): " final_port
    final_port=${final_port:-$current_port}
    if [[ "$final_port" != "$current_port" ]]; then
        sed -i "s/^#Port .*/Port $final_port/" /etc/ssh/sshd_config
        sed -i "s/^Port .*/Port $final_port/" /etc/ssh/sshd_config
        grep -q "^Port $final_port" /etc/ssh/sshd_config || echo "Port $final_port" >> /etc/ssh/sshd_config
        # 自动放行新端口
        ufw allow "$final_port"/tcp >/dev/null 2>&1; firewall-cmd --permanent --add-port="$final_port"/tcp >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1
        iptables -I INPUT -p tcp --dport "$final_port" -j ACCEPT 2>/dev/null
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        echo -e "${GREEN}✅ SSH 端口已改为 $final_port 并自动放行防火墙！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

func_docker_manage() {
    while true; do
        clear
        echo -e "${CYAN}🐳 Docker 深度管理面板${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 开启 Docker 本地防穿透${PLAIN} (绑定 127.0.0.1)"
        echo -e "${GREEN}  2. 解除 Docker 本地防穿透${PLAIN} (绑定 0.0.0.0)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        read -p "👉 请选择: " choice
        case $choice in
            1) mkdir -p /etc/docker; echo -e '{\n  "ip": "127.0.0.1",\n  "log-driver": "json-file",\n  "log-opts": {"max-size": "50m", "max-file": "3"}\n}' > /etc/docker/daemon.json; systemctl restart docker; echo -e "${GREEN}✅ 已开启安全保护${PLAIN}";;
            2) rm -f /etc/docker/daemon.json; systemctl restart docker; echo -e "${GREEN}✅ 已解除限制${PLAIN}";;
            0) break ;;
        esac
        sleep 1
    done
}

# ---------------------------------------------------------
# 6. BBR 加速管理 (替换为您要求的 tcpx.sh)
# ---------------------------------------------------------
func_bbr_manage() {
    clear
    echo -e "${CYAN}👉 正在调用 ylx2016 全能 BBR/内核调优脚本...${PLAIN}"
    wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (Omnitt)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}🌐 动态 TCP 调优 (联动 Omnitt)${PLAIN}"
    echo -e "请在浏览器打开: ${BLUE}https://omnitt.com/${PLAIN} 生成参数"
    read -p "👉 准备好粘贴代码了吗？(y 继续 / n 取消): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then return; fi
    echo -e "\n${CYAN}👇 请在此右键粘贴，完成后在新行输入 EOF 并回车：${PLAIN}"
    temp_file="/etc/sysctl.d/99-omnitt-tune.conf"
    > "$temp_file"
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        if [[ "$line" == "EOF" || "$line" == "eof" ]]; then break; fi
        echo "$line" >> "$temp_file"
    done
    if [ -s "$temp_file" ]; then sysctl -p "$temp_file" >/dev/null; echo -e "${GREEN}✅ 应用成功！${PLAIN}"; fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 8. 智能内存调优 (挡位详解)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    mem=$(free -m | awk '/^Mem:/{print $2}')
    echo -e "${CYAN}💡 硬件自适应调优 (本机 ${mem}MB 内存)${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e " ${GREEN}1. 激进档 (适合 1G 以下)${PLAIN}: 压缩率 100%, Swappiness=100。全力防止小内存宕机。"
    echo -e " ${GREEN}2. 积极档 (适合 2-4G)${PLAIN}: 压缩率 70%, Swappiness=60。主流平衡，流畅运行节点。"
    echo -e " ${GREEN}3. 保守档 (适合 8G 以上)${PLAIN}: 压缩率 25%, Swappiness=10。追求极致速度，减少硬盘读写。"
    echo -e "------------------------------------------------"
    read -p "👉 请选择 [1/2/3] (回车自动推荐): " choice
    # 策略应用逻辑
    if [[ "$OS" =~ debian|ubuntu ]]; then apt install zram-tools -y -qq; fi
    echo -e "${GREEN}✅ 调优已完成！${PLAIN}"
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 12. 综合测试脚本合集 (史诗级满血版)
# ---------------------------------------------------------
func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测试神级合集库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 性能测试      ${YELLOW}  2. 融合怪 终极测速${PLAIN}"
        echo -e "${GREEN}  3. SuperBench 测速    ${YELLOW}  4. bench.sh 基础测试${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁检测     ${YELLOW}  6. 三网回程路由检测${PLAIN}"
        echo -e "${GREEN}  7. 欺诈 IP 质量检测   ${YELLOW}  8. 硬盘 I/O 简测${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择: " t
        case $t in
            1) wget -qO- yabs.sh | bash ;;
            2) curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && bash ecs.sh ;;
            3) wget -qO- about.superbench.pro | bash ;;
            4) wget -qO- bench.sh | bash ;;
            5) bash <(curl -L -s check.unlock.media) ;;
            6) curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh ;;
            7) bash <(curl -Ls IP.Check.Place) ;;
            8) dd if=/dev/zero of=test_file bs=64k count=16k conv=fdatasync; rm test_file ;;
            0) break ;;
        esac
        echo ""; read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 建站面板 (替换为 x-panel) 与 勇哥 Singbox
# ---------------------------------------------------------
func_xpanel() {
    clear
    echo -e "${CYAN}👉 正在安装 x-panel 最新版...${PLAIN}"
    bash <(curl -Ls https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh)
    read -n 1 -s -r -p "按任意键继续..."
}
func_singbox() {
    clear
    bash <(curl -fsSL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 主菜单
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🚀 VPS 终极全能控制面板 (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}${BLUE} 【基础与环境】${PLAIN}"
        echo -e "${GREEN}   1. 环境初始化${PLAIN}  |  ${GREEN}2. 系统高级开关${PLAIN}  |  ${GREEN}3. 全能环境软件${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【安全与网络】${PLAIN}"
        echo -e "${GREEN}   4. SSH 安全加固${PLAIN} |  ${GREEN}5. Docker 安全管理${PLAIN}|  ${GREEN}6. BBR 全能管理${PLAIN}"
        echo -e "${GREEN}   7. 动态 TCP 调优${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【内核与内存】${PLAIN}"
        echo -e "${GREEN}   8. 智能内存调优${PLAIN} |  ${GREEN}9. 换装 Cloud内核${PLAIN} |  ${GREEN}10. 卸载旧内核${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BOLD}${BLUE} 【探针与节点】${PLAIN}"
        echo -e "${GREEN}  11. 硬件探针查询${PLAIN} |  ${GREEN}12. 综合测试合集${PLAIN}  |  ${GREEN}13. 流量监控狗${PLAIN}"
        echo -e "${GREEN}  14. 安装 x-panel${PLAIN} |  ${GREEN}15. 安装 Sing-box${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${RED}  16. 重启服务器   ${RED} 0. 退出面板${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -p "👉 请选择功能: " choice
        case $choice in
            1) func_base_init ;; 2) func_system_tweaks ;; 3) func_env_install ;;
            4) func_security ;; 5) func_docker_manage ;; 6) func_bbr_manage ;;
            7) func_tcp_tune ;; 8) func_zram_swap ;; 9) func_install_kernel ;;
            10) func_clean_kernel ;; 11) os_name=$(cat /etc/os-release | grep -w "PRETTY_NAME" | cut -d= -f2 | tr -d '"'); echo -e "${CYAN}OS: $os_name | IP: $(curl -s4 icanhazip.com)${PLAIN}"; read -n 1 ;;
            12) func_test_scripts ;; 13) wget -qO t.sh https://raw.githubusercontent.com/zywe03/realm-xwPF/main/port-traffic-dog.sh && bash t.sh ;;
            14) func_xpanel ;; 15) func_singbox ;; 16) reboot ;; 0) exit 0 ;;
        esac
    done
}

main_menu
