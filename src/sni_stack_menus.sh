# shellcheck shell=bash
# Port 443 Reuse secondary menus for sites, routes, and web whitelist controls.

manage_sni_stack_sites() {
    while true; do
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🌐 管理 Web 域名与反向代理${PLAIN}" "${BOLD}🌐 Manage Web domains and reverse proxies${PLAIN}" "${BOLD}🌐 Управление Web-доменами и обратным прокси${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}管理已配置 443端口复用的网站和反向代理域名。${PLAIN}" "${YELLOW}Manage Web domains and reverse proxies after Port 443 Reuse is configured.${PLAIN}" "${YELLOW}Управляйте Web-доменами и обратными прокси после настройки повторного использования порта 443.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}新增网站只需填写域名和本机后端端口，无需重跑首次配置。${PLAIN}" "${YELLOW}To add a site, enter its domain and local backend port; do not rerun initial setup.${PLAIN}" "${YELLOW}Для нового сайта укажите домен и локальный порт бэкенда; первоначальная настройка не нужна.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看 Web 域名与反向代理${PLAIN}" "${GREEN}1. View Web domains and reverse proxies${PLAIN}" "${GREEN}1. Показать Web-домены и обратные прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 新增 Web 域名与反向代理${PLAIN}" "${GREEN}2. Add a Web domain or reverse proxy${PLAIN}" "${GREEN}2. Добавить Web-домен или обратный прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改反向代理后端${PLAIN}" "${GREEN}3. Edit a reverse-proxy backend${PLAIN}" "${GREEN}3. Изменить бэкенд обратного прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 删除 Web 域名与反向代理${PLAIN}" "${GREEN}4. Remove a Web domain or reverse proxy${PLAIN}" "${GREEN}4. Удалить Web-домен или обратный прокси${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 管理域名 IP 白名单${PLAIN}       ${YELLOW}(只限制被选择的域名)${PLAIN}" "${GREEN}5. Manage domain IP allowlists (selected domains only)${PLAIN}" "${GREEN}5. Управление IP-белым списком доменов (только выбранные домены)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  6. 重新应用当前入口配置${PLAIN}" "${GREEN}6. Reapply current entry configuration${PLAIN}" "${GREEN}6. Повторно применить конфигурацию текущего входа${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 443端口复用链路体检${PLAIN}" "${GREEN}7. Port 443 Reuse diagnostics${PLAIN}" "${GREEN}7. Диагностика повторного использования порта 443${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  8. 切换 Web 反向代理引擎${PLAIN}       ${YELLOW}(Caddy / Nginx 本地反代)${PLAIN}" "${GREEN}8. Switch the Web reverse-proxy engine (local Caddy/Nginx)${PLAIN}" "${GREEN}8. Сменить Web-движок обратного прокси (локальный Caddy/Nginx)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  9. 修改面板域名${PLAIN}" "${GREEN}9. Change the panel domain${PLAIN}" "${GREEN}9. Изменить домен панели${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "输入菜单编号或 ?: " "Enter a menu number or ?: " "Введите номер пункта или ?: ")"
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
            "?") show_sni_help; pause_return; continue ;;
            0|q|Q|'') break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择，请输入菜单编号或 ?。${PLAIN}" "${RED}❌ Invalid selection, please enter the menu number or ?.${PLAIN}" "${RED}❌ Неверный выбор, введите номер меню или ?.${PLAIN}")"; continue ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}
