# shellcheck shell=bash
# Common runtime environment and dependency installation workflows.

func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "基础组件与常用服务"
        echo -e "${BOLD}📦 基础组件与常用服务${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：安装基础组件、转发隧道和常用服务。Caddy/Nginx 反代走主菜单 [4]，443 单入口只走主菜单 [19]。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 基础运行环境${PLAIN}"
        echo -e "${GREEN}  1. Docker 引擎        ${YELLOW}  2. Python 环境        ${GREEN}  3. iperf3 测速工具${PLAIN}"
        echo -e "${BOLD}${BLUE}▶ 转发、隧道与常用服务${PLAIN}"
        echo -e "${GREEN}  4. Realm 端口转发     ${YELLOW}  5. Gost 隧道          ${GREEN}  6. 极光面板${PLAIN}"
        echo -e "${GREEN}  7. 哪吒监控           ${YELLOW}  8. WARP 解锁/网络     ${GREEN}  9. Aria2 下载${PLAIN}"
        echo -e "${GREEN} 10. Forwardx 转发面板  ${YELLOW} 11. PVE 虚拟化工具     ${GREEN} 12. Argox 节点${PLAIN}"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local env_choice
        read_trimmed env_choice "👉 选择: "
        
        case $env_choice in
            1) 
                echo -e "${CYAN}▶ 正在拉取 Docker 引擎...${PLAIN}"
                run_remote_script "安装 Docker 引擎" "https://get.docker.com" || echo -e "${RED}❌ Docker 安装失败，请检查网络！${PLAIN}"
                ;;
            2) run_remote_script "安装 Python 环境" "https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh" ;;
            3) run_safe "安装 iperf3" install_pkg iperf3 ;;
            4) run_remote_script "安装 Realm 端口转发" "https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh" install ;;
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
            10) ensure_docker_compose_ready && run_remote_script "安装 Forwardx 转发面板" "https://raw.githubusercontent.com/poouo/Forwardx/main/scripts/install-panel-docker.sh" install ;;
            11) run_remote_script "安装 PVE 虚拟化工具" "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh" ;;
            12) run_remote_script "安装 Argox 节点" "https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh" ;;
            "?"|help) echo "基础组件菜单只安装 Docker、Python、WARP、转发隧道和常用服务。Caddy/Nginx 反代走主菜单 [4]；443 单入口走主菜单 [19]。"; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}" ;;
        esac
        echo ""
        pause_after_external_script "按回车键继续..."
    done
}

# ---------------------------------------------------------
# 旧版 Reality+CF 向导已禁用，菜单 [19] 使用下方新的 SNI stack 向导。
# ---------------------------------------------------------
