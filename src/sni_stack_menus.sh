# shellcheck shell=bash
# 443 single-entry secondary menus for sites, routes, and web whitelist controls.

manage_sni_stack_sites() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🌐 443 网站/反代域名管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：给已完成 443 单入口的机器新增、删除或查看网站/反代域名。${PLAIN}"
        echo -e "${YELLOW}后续新增网站不需要重跑首次配置，只需要填写域名和本机后端端口。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前网站/反代域名${PLAIN}"
        echo -e "${GREEN}  2. 新增网站/反代域名${PLAIN}"
        echo -e "${GREEN}  3. 修改网站/反代后端${PLAIN}"
        echo -e "${GREEN}  4. 删除网站/反代域名${PLAIN}"
        echo -e "${GREEN}  5. 管理域名 IP 白名单${PLAIN}       ${YELLOW}(只限制被选择的域名)${PLAIN}"
        echo -e "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}"
        echo -e "${GREEN}  7. 443 单入口链路体检${PLAIN}"
        echo -e "${GREEN}  8. 切换 Web 反代引擎${PLAIN}       ${YELLOW}(Caddy / Nginx 本地反代)${PLAIN}"
        echo -e "${GREEN}  9. 修改面板域名${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回上一级 / q/back/返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请输入菜单编号或 ?: "
        case "$choice" in
            1) list_sni_stack_sites ;;
            2) add_sni_stack_site ;;
            3) edit_sni_stack_site_backend ;;
            4) remove_sni_stack_site ;;
            5) manage_sni_stack_ip_whitelist ;;
            6) reapply_sni_stack_from_env ;;
            7) sni_stack_health_check ;;
            8) switch_sni_stack_web_proxy_engine ;;
            9) edit_sni_stack_panel_domain_profile ;;
            "?"|help) show_sni_help; pause_return; continue ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择，请输入菜单编号或 ?。${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}
