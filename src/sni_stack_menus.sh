# shellcheck shell=bash
# Port 443 Reuse secondary menus for sites, routes, and web whitelist controls.

manage_sni_stack_sites() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🌐 443 网站/反代域名管理${PLAIN}" "${BOLD}🌐 443 Web domain and reverse-proxy management${PLAIN}" "${BOLD}🌐 443 Управление Web-доменами и обратным прокси${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}管理已配置 443端口复用的网站和反代域名。${PLAIN}" "${YELLOW}Manage Web domains and reverse proxies after Port 443 Reuse is configured.${PLAIN}" "${YELLOW}Управляйте Web-доменами и обратными прокси после настройки повторного использования порта 443.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}新增网站只需填写域名和本机后端端口，无需重跑首次配置。${PLAIN}" "${YELLOW}To add a site, enter its domain and local backend port; do not rerun initial setup.${PLAIN}" "${YELLOW}Для нового сайта укажите домен и локальный порт бэкенда; первоначальная настройка не нужна.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看当前网站/反代域名${PLAIN}" "${GREEN}1. View current Web domains/reverse proxies${PLAIN}" "${GREEN}1. Показать текущие Web-домены и обратные прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 新增网站/反代域名${PLAIN}" "${GREEN}2. Add a Web domain/reverse proxy${PLAIN}" "${GREEN}2. Добавить Web-домен и обратный прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改网站/反代后端${PLAIN}" "${GREEN}3. Edit a Web/reverse-proxy backend${PLAIN}" "${GREEN}3. Изменить бэкенд Web-сайта или обратного прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 删除网站/反代域名${PLAIN}" "${GREEN}4. Remove a Web domain/reverse proxy${PLAIN}" "${GREEN}4. Удалить Web-домен и обратный прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 管理域名 IP 白名单${PLAIN}       ${YELLOW}(只限制被选择的域名)${PLAIN}" "${GREEN}5. Manage domain IP allowlists (selected domains only)${PLAIN}" "${GREEN}5. Управление IP-белым списком доменов (только выбранные домены)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}" "${GREEN}6. Reapply configuration and restart Nginx/Caddy${PLAIN}" "${GREEN}6. Повторно применить конфигурацию и перезапустить Nginx/Caddy${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 443端口复用链路体检${PLAIN}" "${GREEN}7. Port 443 Reuse diagnostics${PLAIN}" "${GREEN}7. Диагностика повторного использования порта 443${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  8. 切换 Web 反代引擎${PLAIN}       ${YELLOW}(Caddy / Nginx 本地反代)${PLAIN}" "${GREEN}8. Switch the Web reverse-proxy engine (local Caddy/Nginx)${PLAIN}" "${GREEN}8. Сменить Web-движок обратного прокси (локальный Caddy/Nginx)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  9. 修改面板域名${PLAIN}" "${GREEN}9. Change the panel domain${PLAIN}" "${GREEN}9. Изменить домен панели${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q/back/返回${PLAIN}" "${RED}0. Back / q/back/return${PLAIN}" "${RED}0. Назад / q/back/вернуться${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "请输入菜单编号或 ?: " "Select a menu number or ?:" "Выберите номер меню или ?:")"
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
            *) echo -e "$(localized_text "${RED}❌ 无效选择，请输入菜单编号或 ?。${PLAIN}" "${RED}❌ Invalid selection, please enter the menu number or ?.${PLAIN}" "${RED}❌ Неверный выбор, введите номер меню или ?.${PLAIN}")" ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}
