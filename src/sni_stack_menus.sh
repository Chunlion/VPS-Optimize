# shellcheck shell=bash
# 443 single entry point secondary menus for sites, routes, and web whitelist controls.

manage_sni_stack_sites() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🌐 443 网站/反代域名管理${PLAIN}" "${BOLD}🌐 443 Website/reverse domain management${PLAIN}" "${BOLD}🌐 443 Управление веб-сайтом/обратным доменным именем${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：给已完成 443 单入口的机器新增、删除或查看网站/反代域名。${PLAIN}" "${YELLOW}Purpose: Add, delete or view websites/reverse domains for machines that have completed 443 single entries.${PLAIN}" "${YELLOW}Назначение: добавление, удаление или просмотр веб-сайтов/обратных доменных имен для компьютеров, которые выполнили 443 отдельные записи.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}后续新增网站不需要重跑首次配置，只需要填写域名和本机后端端口。${PLAIN}" "${YELLOW}Subsequent new websites do not need to re-run the first configuration. You only need to fill in the domain and local back-end port.${PLAIN}" "${YELLOW}Последующие новые веб-сайты не требуют повторного запуска первой конфигурации. Вам нужно только указать имя домена и локальный внутренний порт.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 查看当前网站/反代域名${PLAIN}" "${GREEN}1. View the current website/reverse domain${PLAIN}" "${GREEN}1. Просмотрите текущий веб-сайт/обратное доменное имя.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 新增网站/反代域名${PLAIN}" "${GREEN}2. Add new website/reverse domain${PLAIN}" "${GREEN}2. Добавьте новый веб-сайт/обратное доменное имя.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改网站/反代后端${PLAIN}" "${GREEN}3. Modify website/reverse backend${PLAIN}" "${GREEN}3. Измените веб-сайт/обратный сервер.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 删除网站/反代域名${PLAIN}" "${GREEN}4. Delete website/reverse domain${PLAIN}" "${GREEN}4. Удалить веб-сайт/обратное доменное имя.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 管理域名 IP 白名单${PLAIN}       ${YELLOW}(只限制被选择的域名)${PLAIN}" "${GREEN}5. Manage domain IP whitelist (limit only selected domains)${PLAIN}" "${GREEN}5. Управление белым списком IP-адресов доменных имен (ограничить только выбранные доменные имена)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}" "${GREEN}6. Reapply and restart Nginx/Caddy${PLAIN}" "${GREEN}6. Повторно примените и перезапустите Nginx/Caddy.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 443 单入口链路体检${PLAIN}" "${GREEN}7. 443 shared entry link health check${PLAIN}" "${GREEN}7. 443 проверка состояния с одним входом${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  8. 切换 Web 反代引擎${PLAIN}       ${YELLOW}(Caddy / Nginx 本地反代)${PLAIN}" "${GREEN}8. Switch the Web reverse proxy engine (Caddy / Nginx local reverse proxy)${PLAIN}" "${GREEN}8. Переключите механизм обратного веб-прокси   (локальный обратный прокси-сервер Caddy / Nginx)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  9. 修改面板域名${PLAIN}" "${GREEN}9. Modify the panel domain${PLAIN}" "${GREEN}9. Измените доменное имя панели.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q/back/返回${PLAIN}" "${RED}0. Return to the previous level / q/back/return to${PLAIN}" "${RED}0. Возврат на предыдущий уровень /q/назад/возврат в${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "👉 请输入菜单编号或 ?: " "👉 Please enter menu number or ?:" "👉 Пожалуйста, введите номер меню или ?:")"
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
