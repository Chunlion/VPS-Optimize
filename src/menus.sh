# shellcheck shell=bash
# Help text plus top-level and second-level menu wiring.

show_main_help() {
    echo -e "${CYAN}VPS-Optimize > 主菜单 > 帮助${PLAIN}"
    echo "1/2 适合新机器先体检和初始化。"
    echo "3   基础组件与常用服务；安装 Docker、Python、WARP 和常用工具。"
    echo "4   反代（Caddy/Nginx）；适合未接入 443 单入口的网站/面板反代。"
    echo "5   管理 3x-ui、Sing-box、Xray 和订阅工具。"
    echo "6   SSH 安全中心；管理端口、公钥和用户密钥登录模式。"
    echo "8   管理系统防火墙；改 SSH、防火墙前先确认云安全组。"
    echo "10  网络/内核优化；涉及 BBR、TCP、ZRAM 和内核清理。"
    echo "15  健康总览和反馈诊断信息，用于排错或提交 Issue。"
    echo "16  备份与回滚，高风险操作前建议先跑。"
    echo "19  443 单入口管理中心，面板/订阅/REALITY 共用公网 443。"
    echo "10 -> 7  流量达量关机保护，按账单周期防刷流量和超额账单。"
    echo "xcm/外置  直达 3x-ui 外置增强管理；也可走 5 -> 16。"
    echo "? 查看帮助，0/q 退出。"
}

show_beginner_help() {
    echo -e "${CYAN}VPS-Optimize > 新手向导 > 帮助${PLAIN}"
    echo "1 新机器初始化：按安全顺序引导预检、初始化、SSH、公钥、Fail2ban、防火墙、备份。"
    echo "2 安装面板/节点：进入面板、节点与订阅工具菜单。"
    echo "3 配置 443 单入口：进入 443 管理中心，适合面板、订阅和 REALITY 共用 443。"
    echo "4 健康检查：查看服务、端口、证书，并可生成反馈诊断信息。"
    echo "5 备份/回滚：创建备份或从已有备份恢复。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_panel_help() {
    echo -e "${CYAN}VPS-Optimize > 面板、节点与订阅工具 > 帮助${PLAIN}"
    echo "1 管理 3x-ui / x-ui，适合安装、进入官方菜单、修复面板。"
    echo "3/4 分别管理 Sing-box 和 Xray。"
    echo "5/6/7 管理订阅工具，部署后建议用 Caddy 或 443 单入口对外访问。"
    echo "11 面板救砖 / SSL 清理，适合 443 接入前清空面板证书路径。"
    echo "14 端口实际流量监控，只看已监控端口实际跑过的流量。"
    echo "16 3x-ui 外置增强管理，适合自定义重置日期、校准已用流量、备份恢复和查看日志。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_sni_help() {
    echo -e "${CYAN}VPS-Optimize > 443 单入口管理中心 > 帮助${PLAIN}"
    echo "1 查看当前入口状态 / 监听详情：显示公网 443、Caddy、Xray 和服务状态。"
    echo "2 首次配置 / 安装：建立共享 Web 域名、Caddy、证书和默认 Nginx Stream 入口。"
    echo "3/4/5 入口模式切换：在 Nginx Stream 模式、Xray Fallback 模式、TCP Peek + Splice 模式之间切换。"
    echo "6 重新应用：按当前 ENTRY_MODE 重新生成并启动入口配置。"
    echo "7 回滚：恢复上一次入口模式切换前的备份。"
    echo "8 管理 Web 域名/反代：后续新增或删除网站，不需要重跑首次配置。"
    echo "9 Web 域名 IP 白名单：只限制 Web/Caddy 域名，不影响 Xray 节点。"
    echo "10 Xray 入站管理：记录 SNI -> 本地地址:端口，不编辑 3x-ui/Xray 入站。"
    echo "11 链路体检：排查 ENTRY_MODE、监听、证书、Web 和 Xray 分流。"
    echo "12 网络访问测试：检查 DNS、TCP、TLS SNI、面板和订阅路径响应。"
    echo "13/14/15 维护项：证书、共享参数和订阅 External Proxy 提示。"
    echo "16 查看 TCP Peek + Splice 状态 / 8444 预检：展示 status.json 统计；预检只监听 8444，不改公网 443。"
    echo "17 TCP Peek 分流规则校验：只检查配置，不重启入口。"
    echo "18 查看 TCP Peek + Splice 日志：查看 vpso-mux 分流器日志。"
    echo "Caddy 未接入 443 单入口时，用主菜单 [4 反代] -> [5] 管理域名 IP 白名单。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_backup_help() {
    echo -e "${CYAN}VPS-Optimize > 备份与回滚 > 帮助${PLAIN}"
    echo "1 创建备份：高风险操作前先用。"
    echo "2 查看备份：确认可用备份和时间。"
    echo "3 回滚：会覆盖当前配置，必须输入 yes 确认，大小写均可。"
    echo "4 隔离旧备份：只移动到隔离目录，不直接删除。"
    echo "5 查看/编辑脚本已应用配置：先备份，再按配置类型校验，可选择 reload/restart。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_net_kernel_help() {
    echo -e "${CYAN}VPS-Optimize > 网络/内核优化 > 帮助${PLAIN}"
    echo "1 BBR / 拥塞控制：调用外部调优脚本，执行前建议备份。"
    echo "2 TCP 参数：修改 sysctl，适合有明确参数需求的用户。"
    echo "3 ZRAM / Swap：适合小内存 VPS。"
    echo "4 安装/切换内核：高风险，必须确认快照和救援控制台可用。"
    echo "5 清理旧内核：不要删除当前内核和云厂商定制内核。"
    echo "6 DNS 更改优化：国内/国外默认 DNS，也支持自定义 IPv4 和 IPv6。"
    echo "7 流量达量关机保护：按网卡流量和账单周期自动关机，防止超额账单。"
    echo "8 网卡管理工具：查看网卡、路由、DNS，临时调整 MTU 或刷新 DHCP。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_health_help() {
    echo -e "${CYAN}VPS-Optimize > 诊断/健康检查 > 帮助${PLAIN}"
    echo "健康总览会检查关键服务、监听端口和证书摘要。"
    echo "系统硬件探针会附带 443、Caddy、3x-ui、订阅工具和 Docker 场景概览。"
    echo "生成反馈诊断信息用于提交 GitHub Issue，会尽量避免输出 Token、私钥和敏感密钥。"
}


func_net_kernel_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "网络/内核优化"
        echo -e "${BOLD}🚀 网络性能与内核管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：调整网络栈、内存压缩和内核；涉及内核安装/清理前建议先做快照。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. BBR / 拥塞控制管理${PLAIN}   ${YELLOW}(调用 ylx2016 多内核调优脚本)${PLAIN}"
        echo -e "${GREEN}  2. 动态 TCP 参数调优${PLAIN}    ${YELLOW}(粘贴 Omnitt 参数并自动校验)${PLAIN}"
        echo -e "${GREEN}  3. ZRAM / Swap 内存调优${PLAIN} ${YELLOW}(按内存分档优化小鸡)${PLAIN}"
        echo -e "${GREEN}  4. 安装/切换优化内核${PLAIN}   ${YELLOW}(Cloud/KVM 稳定推荐 / XanMod 高级可选)${PLAIN}"
        echo -e "${GREEN}  5. 清理旧内核${PLAIN}           ${YELLOW}(释放磁盘空间，谨慎操作)${PLAIN}"
        echo -e "${GREEN}  6. DNS 更改优化${PLAIN}         ${YELLOW}(国内/国外/自定义，IPv4+IPv6)${PLAIN}"
        echo -e "${GREEN}  7. 流量达量关机保护${PLAIN}     ${YELLOW}(防刷流量 / 防超额账单)${PLAIN}"
        echo -e "${GREEN}  8. 网卡管理工具${PLAIN}         ${YELLOW}(网卡/路由/DNS/MTU/DHCP)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local nk_choice
        read_trimmed nk_choice "👉 请选择操作: "
        case $nk_choice in
            1) confirm_risk_action "BBR / 拥塞控制管理" "内核网络模块、拥塞控制和 TCP 参数" "从快照恢复，或重新进入本菜单切换回原配置" "外部调优脚本可能安装/切换内核，请确认救援控制台可用。" && func_bbr_manage ;;
            2) confirm_risk_action "动态 TCP 参数调优" "sysctl TCP 参数和网络栈配置" "恢复 /etc/sysctl.d 中的备份配置，或手动回退参数" "确认参数来源可信，错误参数可能影响网络连接。" && func_tcp_tune ;;
            3) func_zram_swap ;;
            4) confirm_risk_action "安装/切换优化内核" "内核包、引导配置和 GRUB 菜单" "从云厂商控制台选择旧内核启动，或使用救援模式恢复" "确认已创建快照，且当前 VPS 不是 OpenVZ 老系统。" && func_install_kernel ;;
            5) func_clean_kernel ;;
            6) func_dns_optimize ;;
            7) func_traffic_guard_menu ;;
            8) func_network_interface_manage ;;
            "?"|help) show_net_kernel_help; pause_return ;;
            0|q|Q) break ;;
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
        print_breadcrumb "面板、节点与订阅工具"
        echo -e "${BOLD}🛰️ 面板、节点与订阅工具部署${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：管理 3x-ui、Sing-box、Xray、订阅工具、Dockge、Komari 和节点辅助工具。${PLAIN}"
        echo -e "${YELLOW}提示：面板或订阅工具对外访问，可用 Caddy 反代；已启用 443 单入口时用 [19] 统一管理。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 管理 3x-ui 面板${PLAIN}       ${YELLOW}(安装 / 官方菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  2. 管理 Sing-box${PLAIN}         ${YELLOW}(安装 / 管理菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  3. 管理 Xray${PLAIN}             ${YELLOW}(安装 / 官方菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  4. 管理 SublinkPro${PLAIN}       ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${GREEN}  5. 管理 妙妙屋订阅管理${PLAIN}     ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${GREEN}  6. 管理 Sub-Store${PLAIN}        ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${GREEN}  7. 管理 Dockge${PLAIN}           ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${BOLD}${YELLOW}  8. UPD 更新订阅管理工具${PLAIN}   ${CYAN}(SublinkPro / 妙妙屋 / Sub-Store)${PLAIN}"
        echo -e "${GREEN}  9. 迁移 Compose 到 Dockge${PLAIN} ${YELLOW}(Dockge 后安装时接管旧项目)${PLAIN}"
        echo -e "${GREEN} 10. 面板救砖 / SSL 清理${PLAIN}    ${YELLOW}(清空 3x-ui 证书路径，回到 HTTP 后端)${PLAIN}"
        echo -e "${GREEN} 11. DNS 流媒体解锁${PLAIN}        ${YELLOW}(Alice DNS 分流脚本)${PLAIN}"
        echo -e "${GREEN} 12. 防 IP 送中脚本${PLAIN}        ${YELLOW}(IP-Sentinel)${PLAIN}"
        echo -e "${GREEN} 13. 端口实际流量监控${PLAIN}      ${YELLOW}(只看已监控端口实际流量)${PLAIN}"
        echo -e "${GREEN} 14. 管理 Komari 探针监控${PLAIN}  ${YELLOW}(Docker Compose / 探针面板)${PLAIN}"
        echo -e "${GREEN} 15. 3x-ui 外置增强管理${PLAIN}    ${YELLOW}(快捷词 xcm / 重置日期 / 流量校准 / 备份恢复)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local pd_choice
        read_trimmed pd_choice "👉 请选择操作: "
        case $pd_choice in
            1) func_xpanel_menu ;;
            2) func_singbox_menu ;;
            3) func_xray_menu ;;
            4) func_sublinkpro_menu ;;
            5) func_miaomiaowu_menu ;;
            6) func_substore_menu ;;
            7) func_dockge_menu ;;
            8) func_update_subscription_tools ;;
            9) func_migrate_compose_to_dockge ;;
            10) func_rescue_panel ;;
            11) func_dns_unlock ;;
            12) func_ip_sentinel ;;
            13) func_port_dog ;;
            14) func_komari_menu ;;
            15) func_xui_custom_manager ;;
            xcm|XCM|xui-custom|外置|外置增强|外置管理) func_xui_custom_manager ;;
            "?"|help) show_panel_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_sni_stack_quick_menu() {
    while true; do
        clear
        show_current_entry_summary
        echo -e "------------------------------------------------"
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "443 单入口管理中心"
        echo -e "${BOLD}🧩 443 单入口管理中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：统一管理公网 443 的入口模式、Web 域名、Xray 入站分流和链路体检。${PLAIN}"
        echo -e "${YELLOW}首次部署先选 [2]；已有配置后用 [3]/[4]/[5] 在三种入口模式间切换。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 当前状态与入口模式${PLAIN}"
        echo -e "${GREEN}  1. 查看当前入口状态 / 监听详情${PLAIN} ${YELLOW}(公网 443、Caddy、Xray、服务状态)${PLAIN}"
        echo -e "${GREEN}  2. 首次配置 / 安装 443 单入口${PLAIN} ${YELLOW}(默认 Nginx Stream 模式，第一次部署用)${PLAIN}"
        echo -e "${GREEN}  3. 切换到 Nginx Stream 模式${PLAIN}  ${YELLOW}(默认稳定模式)${PLAIN}"
        echo -e "${GREEN}  4. 切换到 Xray Fallback 模式${PLAIN} ${YELLOW}(需已有 Xray/3x-ui 主入站)${PLAIN}"
        echo -e "${GREEN}  5. 切换到 TCP Peek + Splice 模式${PLAIN} ${YELLOW}(需先完成 8444 预检，切换时不自动编译)${PLAIN}"
        echo -e "${CYAN}  6. 重新应用当前入口模式${PLAIN}"
        echo -e "${YELLOW}  7. 回滚上一次入口模式切换${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 共享配置与体检${PLAIN}"
        echo -e "${GREEN}  8. 管理 Web 域名/反代${PLAIN}        ${YELLOW}(新增/删除/查看网站，最常用)${PLAIN}"
        echo -e "${CYAN}  9. 管理 Web 域名 IP 白名单${PLAIN}   ${YELLOW}(只限制 Web/Caddy 域名)${PLAIN}"
        echo -e "${CYAN} 10. Xray 入站管理${PLAIN}             ${YELLOW}(SNI -> 本地地址:端口 分流记录)${PLAIN}"
        echo -e "${GREEN} 11. 443 链路体检${PLAIN}              ${YELLOW}(ENTRY_MODE/监听/证书/Web/Xray 分流)${PLAIN}"
        echo -e "${CYAN} 12. 443 网络访问测试${PLAIN}          ${YELLOW}(DNS/TCP/TLS/面板/订阅路径)${PLAIN}"
        echo -e "${CYAN} 13. CF DNS / Caddy 证书维护${PLAIN}   ${YELLOW}(重签/软链/清理/修复/回滚)${PLAIN}"
        echo -e "${CYAN} 14. 修改 443 共享参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}"
        echo -e "${CYAN} 15. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}"
        echo -e "${CYAN} 16. 查看 TCP Peek + Splice 状态 / 8444 预检${PLAIN} ${YELLOW}(不改公网 443)${PLAIN}"
        echo -e "${CYAN} 17. TCP Peek 分流规则校验${PLAIN} ${YELLOW}(只检查配置，不重启入口)${PLAIN}"
        echo -e "${CYAN} 18. 查看 TCP Peek + Splice 日志${PLAIN} ${YELLOW}(vpso-mux 分流器日志)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}说明：三种 443 入口不是三套独立安装器；[2] 建立共享配置，[3]/[4]/[5] 负责检查依赖、生成目标配置并切换入口。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local sni_choice
        read_trimmed sni_choice "👉 请选择操作: "
        case "$sni_choice" in
            1) show_current_entry_status ;;
            2) func_caddy_cf_reality_wizard ;;
            3) switch_entry_mode "nginx-stream" ;;
            4) switch_entry_mode "xray-fallback" ;;
            5) switch_entry_mode "tcp-peek" ;;
            6) reapply_current_entry_mode ;;
            7) rollback_last_entry_mode ;;
            8) manage_sni_stack_sites; continue ;;
            9) manage_sni_stack_ip_whitelist; continue ;;
            10) manage_xray_inbound_routes; continue ;;
            11) sni_stack_health_check_enhanced ;;
            12) func_443_network_test; continue ;;
            13) func_caddy_cf_maintenance_menu; continue ;;
            14) edit_sni_stack_runtime_profile; continue ;;
            15) check_sni_stack_subscription_hint ;;
            16) start_tcp_peek_test_port ;;
            17) tcp_peek_dry_run_config ;;
            18) view_vpso_mux_logs ;;
            "?"|help) show_sni_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

normalize_main_choice() {
    local choice
    choice="$(trim_input "$1")"
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
        q|quit|exit|0|退出) echo "0" ;;
        pre|preflight|check|预检) echo "1" ;;
        init|base|初始化) echo "2" ;;
        env|docker|组件) echo "3" ;;
        caddy|nginx|ngx|proxy|reverse|反代) echo "4" ;;
        xcm|xui-custom|外置|外置增强|外置管理) echo "xui-custom" ;;
        panel|node|nodes|面板|节点) echo "5" ;;
        ssh) echo "6" ;;
        fail2ban|f2b) echo "7" ;;
        fw|firewall|防火墙) echo "8" ;;
        tweak|system|系统) echo "9" ;;
        net|kernel|bbr|网络|内核) echo "10" ;;
        docker-safe|docker安全) echo "11" ;;
        test|speed|测速) echo "12" ;;
        port|端口) echo "13" ;;
        info|hardware|探针) echo "14" ;;
        h|health|健康|体检) echo "15" ;;
        b|backup|bak|备份) echo "16" ;;
        u|upd|update|更新) echo "17" ;;
        reboot|重启) echo "18" ;;
        sni|443|单入口) echo "19" ;;
        traffic|quota|bill|流量|达量|账单) echo "10" ;;
        *) echo "$choice" ;;
    esac
}

func_beginner_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "新手向导"
        echo -e "${BOLD}VPS-Optimize ${SCRIPT_VERSION}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}这是简化入口，只保留第一次部署最常用的路径；老用户可返回完整菜单。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 新机器初始化${PLAIN}       ${YELLOW}(预检 -> 初始化 -> SSH/公钥/Fail2ban/防火墙 -> 备份)${PLAIN}"
        echo -e "${GREEN}  2. 安装面板/节点${PLAIN}     ${YELLOW}(进入面板、节点与订阅工具菜单)${PLAIN}"
        echo -e "${GREEN}  3. 配置 443 单入口${PLAIN}   ${YELLOW}(面板/订阅/REALITY 共用公网 443)${PLAIN}"
        echo -e "${GREEN}  4. 健康检查${PLAIN}          ${YELLOW}(服务状态、端口、证书、反馈诊断)${PLAIN}"
        echo -e "${GREEN}  5. 备份/回滚${PLAIN}         ${YELLOW}(创建备份或恢复配置)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local beginner_choice
        read_trimmed beginner_choice "👉 请选择操作: "
        case "$beginner_choice" in
            1)
                func_preflight_check
                func_base_init
                func_security
                func_add_ssh_key
                func_fail2ban
                func_firewall_manage
                func_backup_center
                ;;
            2) func_panel_deploy_menu ;;
            3) func_sni_stack_quick_menu ;;
            4) func_health_dashboard ;;
            5) func_backup_center ;;
            "?"|help|h) show_beginner_help; echo ""; pause_return ;;
            0|q|Q) break ;;
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
        print_breadcrumb "主菜单"
        echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${YELLOW}快捷输入：443 直达单入口，h 看健康，b 做备份，u 更新，q 退出。${PLAIN}"
        echo -e " ${YELLOW}高风险操作需要输入 yes 确认，大小写均可；不确定时先做 [16] 备份。${PLAIN}"
        print_auto_update_notice
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}${BLUE}▶ 模式入口${PLAIN}"
        echo -e "  ${GREEN}n.${PLAIN} 新手向导              ${YELLOW}(只显示核心路径)${PLAIN}"
        echo -e "  ${GREEN}?.${PLAIN} 当前菜单帮助          ${YELLOW}(解释关键入口)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ ① 推荐流程：新机器先跑这里${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 运维预检与风险扫描    ${YELLOW}(部署前先看端口/系统/服务状态)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 基础环境初始化        ${YELLOW}(工具/时区/系统更新/基础 BBR)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 基础组件与常用服务    ${YELLOW}(Docker/Python/WARP/常用工具)${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} 反代（Caddy/Nginx）   ${YELLOW}(未接入 443 单入口的网站/面板反代)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} 面板、节点与订阅工具  ${YELLOW}(3x-ui/Sing-box/订阅管理/Dockge)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ② 安全与访问控制${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} SSH 安全中心          ${YELLOW}(端口/公钥/密钥登录模式)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} Fail2ban 防爆破       ${YELLOW}(自动封禁 SSH 爆破 IP)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 防火墙规则管理        ${YELLOW}(放行/删除/查看/关闭)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 系统开关与清理        ${YELLOW}(IPv6/IPv4优先/Ping/主机名/清理)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ③ 网络性能与容器${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 网络与内核优化        ${YELLOW}(BBR/TCP/ZRAM/DNS/轻量内核)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} Docker 安全管理       ${YELLOW}(本地防穿透/恢复访问)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ④ 诊断、备份与维护${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 测速与质量检测        ${YELLOW}(YABS/流媒体/回程/IP质量)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口排查与释放        ${YELLOW}(查看占用并强杀进程)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 系统硬件探针          ${YELLOW}(CPU/内存/磁盘/网络实时信息)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 服务健康总览          ${YELLOW}(服务状态/证书摘要/端口概览)${PLAIN}"
        echo -e " ${GREEN}16.${PLAIN} 配置备份与回滚        ${YELLOW}(备份/列表/恢复/清理)${PLAIN}"
        echo -e " ${BOLD}${YELLOW}17.${PLAIN} 更新脚本              ${CYAN}(快捷词：u / update / upd)${PLAIN}"
        echo -e " ${RED}18.${PLAIN} 重启服务器"
        echo -e ""
        echo -e " ${BOLD}${BLUE}▶ ⑤ 高频直达${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} 443 单入口管理中心    ${YELLOW}(初始化/加网站/体检/证书修复)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local choice
        read_trimmed choice "👉 请输入数字或快捷词选择功能: "
        choice=$(normalize_main_choice "$choice")
        
        case $choice in
            n|N|newbie|guide|新手|向导) func_beginner_menu ;;
            "?"|help|帮助) show_main_help; echo ""; pause_return ;;
            xui-custom) func_xui_custom_manager ;;
            1) func_preflight_check ;;
            2) func_base_init ;;
            3) func_env_install ;;
            4) func_caddy_reverse_proxy_menu ;;
            5) func_panel_deploy_menu ;;
            6) func_ssh_security_menu ;;
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
