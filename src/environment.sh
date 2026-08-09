# shellcheck shell=bash
# Common runtime environment and dependency installation workflows.

func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "基础组件与常用服务" "Basic components and common services" "Базовые компоненты и общие услуги")"
        echo -e "$(localized_text "${BOLD}📦 基础组件与常用服务${PLAIN}" "${BOLD}📦 Basic components and common services${PLAIN}" "${BOLD}📦 Базовые компоненты и общие службы${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：安装基础组件、转发隧道和常用服务。Caddy/Nginx 反代走主菜单 [4]，443端口复用只走主菜单 [19]。${PLAIN}" "${YELLOW}Purpose: Install basic components, forwarding tunnels and common services. Caddy/Nginx reverse proxy goes to the main menu [4], Port 443 Reuse only goes to the main menu [19].${PLAIN}" "${YELLOW}Назначение: Установка основных компонентов, туннелей пересылки и общих служб. Caddy/Nginx наоборот использует главное меню [4], а повторное использование порта 443 использует только главное меню [19].${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 基础运行环境${PLAIN}" "${BOLD}▶ Basic operating environment${PLAIN}" "${BOLD}▶ Базовая операционная среда${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  1. Docker 引擎        ${YELLOW}  2. Python 环境        ${GREEN}  3. iperf3 测速工具${PLAIN}" "${GREEN}1. Docker engine 2. Python environment 3. iperf3 speed measurement tool${PLAIN}" "${GREEN}1. Двигатель Docker 2. Python Окружающая среда 3. iperf3 Инструмент измерения скорости${PLAIN}")"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 转发、隧道与常用服务${PLAIN}" "${BOLD}▶ Forwarding, tunneling and common services${PLAIN}" "${BOLD}▶ Пересылка, туннелирование и общие услуги${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. WARP 解锁/网络     ${YELLOW}  5. Realm 端口转发     ${GREEN}  6. Gost 隧道${PLAIN}" "${GREEN}4. WARP Unlock/Network 5. Realm port forwarding 6. Gost Tunnel${PLAIN}" "${GREEN}4. WARP Разблокировка/Сеть 5. маршрутизация портов области 6. Gost Туннель${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. Forwardx 转发面板  ${YELLOW}  8. Argox 节点         ${GREEN}  9. 极光面板${PLAIN}" "${GREEN}7. Forwardx forwarding panel 8. Argox node 9. Aurora panel${PLAIN}" "${GREEN}7. Панель пересылки Forwardx 8. Узел Argox 9. Панель Aurora${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 10. nftables NAT 转发  ${YELLOW} 11. Aria2 下载         ${GREEN} 12. PVE 虚拟化工具${PLAIN}" "${GREEN}10. nftables NAT forwarding 11. Aria2 download 12. PVE virtualization tool${PLAIN}" "${GREEN}10. nftables маршрутизация NAT 11. Загрузка Aria2 12. Инструмент виртуализации PVE${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 13. FLVX 哆啦转发面板  ${YELLOW} 14. EasyTier 组网       ${GREEN} 15. Tailscale 组网${PLAIN}" "${GREEN}13. FLVX Doraemon forwarding panel 14. EasyTier networking 15. Tailscale networking${PLAIN}" "${GREEN}13. Панель пересылки FLVX Doraemon 14. Сеть EasyTier 15. Сеть Tailscale${PLAIN}")"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Return to the main menu / q Return to the previous level${PLAIN}" "${RED}0. Возврат в главное меню / q Возврат на предыдущий уровень${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local env_choice
        read_trimmed env_choice "$(localized_text "👉 选择: " "👉 Choose:" "👉 Выбирайте:")"
        
        case $env_choice in
            1) 
                echo -e "$(localized_text "${CYAN}▶ 正在拉取 Docker 引擎...${PLAIN}" "${CYAN}▶ Pulling Docker engine...${PLAIN}" "${CYAN}▶ Извлечение двигателя Docker...${PLAIN}")"
                run_remote_script "$(localized_text "安装 Docker 引擎" "Install Docker engine" "Установите двигатель Docker.")" "https://get.docker.com" || echo -e "$(localized_text "${RED}❌ Docker 安装失败，请检查网络！${PLAIN}" "${RED}❌ Docker Installation failed, please check the network!${PLAIN}" "${RED}❌ Docker Установка не удалась, проверьте сеть!${PLAIN}")"
                ;;
            2) run_remote_script "$(localized_text "安装 Python 环境" "Install Python environment" "Установите среду Python.")" "https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh" ;;
            3) run_safe "$(localized_text "安装 iperf3" "Install iperf3" "Установить iperf3")" install_pkg iperf3 ;;
            4) run_remote_script "$(localized_text "安装 WARP 解锁/网络工具" "Install WARP Unlock/Network Tool" "Установите инструмент разблокировки/сети WARP.")" "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" ;;
            5) run_remote_script "$(localized_text "安装 Realm 端口转发" "Install Realm port forwarding" "Установите переадресацию портов Realm")" "https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh" install ;;
            6) run_remote_script "$(localized_text "安装 Gost 隧道" "Install Gost tunnel" "Установите туннель Gost.")" "https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh" ;;
            7) run_remote_script "$(localized_text "安装 Forwardx 转发面板" "Install Forwardx forwarding panel" "Установить панель маршрутизация Forwardx")" "https://raw.githubusercontent.com/poouo/Forwardx/main/scripts/install-panel-local.sh" install ;;
            8) run_remote_script "$(localized_text "安装 Argox 节点" "Install Argox node" "Установите узел Argox.")" "https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh" ;;
            9) run_remote_script "$(localized_text "安装极光面板" "Install Aurora Panel" "Установить панель Аврора")" "https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh" ;;
            10) run_remote_script "$(localized_text "安装 nftables NAT 转发工具" "Install nftables NAT forwarding tool" "Установите инструмент маршрутизация NAT nftables.")" "https://us.arloor.dev/https://github.com/arloor/nftables-nat-rust/releases/download/v2.0.0/setup.sh" toml ;;
            11) run_remote_script "$(localized_text "安装 Aria2 下载工具" "Install the Aria2 download tool" "Установите инструмент загрузки Aria2.")" "https://git.io/aria2.sh" ;;
            12) run_remote_script "$(localized_text "安装 PVE 虚拟化工具" "Install PVE virtualization tools" "Установите инструменты виртуализации PVE")" "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh" ;;
            13) run_remote_script "$(localized_text "安装 FLVX 哆啦转发面板" "Install FLVX Doraemon forwarding panel" "Установите панель маршрутизация FLVX Doraemon.")" "https://raw.githubusercontent.com/Sagit-chu/flvx/main/panel_install.sh" ;;
            14) run_remote_script "$(localized_text "安装 EasyTier 组网" "Install EasyTier networking" "Установите сеть EasyTier")" "https://raw.githubusercontent.com/EasyTier/EasyTier/main/script/install.sh" install ;;
            15)
                if run_remote_script "$(localized_text "安装 Tailscale 组网" "Install Tailscale networking" "Установите сеть Tailscale")" "https://tailscale.com/install.sh"; then
                    echo -e "$(localized_text "${GREEN}✅ 安装完成后运行 tailscale up，按提示登录并加入网络。${PLAIN}" "${GREEN}✅ After the installation is complete, run tailscale up, follow the prompts to log in and join the network.${PLAIN}" "${GREEN}. После завершения установки запустите Tailscale Up, следуйте инструкциям, чтобы войти в систему и присоединиться к сети.${PLAIN}")"
                fi
                ;;
            "?"|help) echo "$(localized_text "基础组件菜单只安装 Docker、Python、WARP、转发隧道和常用服务。Caddy/Nginx 反代走主菜单 [4]；443端口复用走主菜单 [19]。" "The basic component menu only installs Docker, Python, WARP, forwarding tunnel and common services. Caddy/Nginx reverse proxy goes to the main menu [4]; Port 443 Reuse goes to the main menu [19]." "Меню базового компонента устанавливает только Docker, Python, WARP, туннель пересылки и общие службы. Caddy/Nginx осуществляет обратный доступ к главному меню [4]; 443 повторного использования порта 443 обеспечивает доступ к главному меню [19].")"; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效的输入！${PLAIN}" "${RED}❌ Invalid input!${PLAIN}" "${RED}❌ Неверный ввод!${PLAIN}")" ;;
        esac
        echo ""
        pause_after_external_script "$(localized_text "按回车键继续..." "Press Enter to continue..." "Нажмите Enter, чтобы продолжить...")"
    done
}

# ---------------------------------------------------------
# 旧版 Reality+CF 向导已禁用，菜单 [19] 使用下方新的 SNI stack 向导。
# ---------------------------------------------------------
