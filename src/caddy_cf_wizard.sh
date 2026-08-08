# shellcheck shell=bash
# Current 443 stack handoff for the old Caddy/Cloudflare wizard entry.

func_caddy_cf_reality_wizard() {
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}检测到已有 443 单入口配置${PLAIN}" "${BOLD}Detects that there are already 443 shared entry configurations${PLAIN}" "${BOLD}обнаружил, что существует 443 конфигурации с общей точкой входа.${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}如果只是新增网站或反代域名，请返回并选择 [8] 管理 Web 域名/反代。${PLAIN}" "${YELLOW}If you are just adding a new website or reverse proxy domain, please go back and select [8] Manage Web domain/Reverse proxy.${PLAIN}" "${YELLOW}Если вы просто добавляете новый веб-сайт или доменное имя обратного прокси, вернитесь назад и выберите [8] Управление именем веб-домена/обратным прокси.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}继续首次配置会重写 443 入口、Web 反代引擎和 Xray 分流相关核心配置。${PLAIN}" "${YELLOW}Continuing initial setup will rewrite the port 443 entry, Web reverse proxy, and Xray routing configuration.${PLAIN}" "${YELLOW}Продолжение первоначальной настройки перезапишет конфигурацию входа 443, веб-прокси и маршрутизации Xray.${PLAIN}")"
        echo -e "------------------------------------------------"
        grep -E '^(PANEL_DOMAIN|PANEL_WEB_PATH|REALITY_SNI|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_PORT|XRAY_LISTEN_PORT|SUB_URI_PATH|CLASH_URI_PATH)=' /etc/vps-optimize/sni-stack.env 2>/dev/null || true
        echo -e "------------------------------------------------"
        confirm_danger "$(localized_text "重新执行 443 首次配置" "Re-execute 443 initial setup" "Повторно выполнить конфигурацию 443 при первом запуске.")" "$(localized_text "将基于新输入重写 443 单入口核心配置，并重启入口服务/Caddy。" "The 443 shared-entry core configuration will be rewritten based on the new input and the entry service/Caddy will be restarted." "Конфигурация ядра общей точки входа 443 будет переписана на основе новых входных данных, а служба входа/Caddy будет перезапущена.")" "$(localized_text "脚本会先创建备份，可从 443 维护菜单或备份目录回滚。" "The script will first create a backup, which can be rolled back from the 443 maintenance menu or the backup directory." "Скрипт сначала создаст резервную копию, откат которой можно выполнить из меню обслуживания 443 или каталога резервных копий.")" || return 1
    fi
    select_initial_entry_mode || return 1
    collect_sni_stack_config || return 1
    probe_reality_sni "$REALITY_SNI" || return 1
    print_sni_stack_preview || return 1
    guard_current_ssh_not_on_entry_port "$(localized_text "首次配置 443 单入口" "Initial shared 443 entry setup" "Первоначальная настройка общей точки входа 443")" || return 1
    local cf_env_dir="/root/.config/vps-panel"
    local cf_env_file="${cf_env_dir}/cloudflare.env"
    local escaped_token
    mkdir -p "$cf_env_dir"
    chmod 700 "$cf_env_dir"
    escaped_token=${CF_TOKEN//\'/\'"\'"\'}
    printf "CF_Token='%s'\n" "$escaped_token" > "$cf_env_file"
    chmod 600 "$cf_env_file"

    local backup_dir
    backup_dir=$(backup_entry_mode_config) || return 1
    prepare_initial_entry_mode_dependencies "$ENTRY_MODE" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式依赖检查失败" "Entry mode dependency check failed" "Проверка зависимости режима входа не удалась")"; return 1; }
    quarantine_legacy_caddy_443_configs
    quarantine_legacy_nginx_https_proxy_configs
    issue_and_install_cert_for_domain "$PANEL_DOMAIN" "$CF_TOKEN" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "面板域名证书签发/安装失败" "Panel domain certificate issuance/installation failed" "Не удалось выдать/установить сертификат доменного имени панели.")"; return 1; }
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local site_domain
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -z "$site_domain" ]] && continue
            issue_and_install_cert_for_domain "$site_domain" "$CF_TOKEN" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "站点域名 ${site_domain} 证书签发/安装失败" "Site domain ${site_domain} certificate issuance/installation failed" "Доменное имя сайта ${site_domain} не удалось выдать/установить сертификат")"; return 1; }
        done
    fi
    preflight_entry_mode_before_cutover "$ENTRY_MODE" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式 ${ENTRY_MODE} 预检失败，公网 443 未切换" "entry mode ${ENTRY_MODE} preflight failed, public port 443 not switched" "Режим входа в предполетный режим ${ENTRY_MODE} не выполнен, публичный порт 443 не переключена")"; return 1; }
    stop_public_443_entry_services_for_target "$ENTRY_MODE" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "停止旧公网 443 入口服务失败" "Stop the old public port 443 entry service failed" "Остановить старую публичную сеть 443, служба входа не удалась")"; return 1; }
    apply_entry_mode_by_name "$ENTRY_MODE" "$backup_dir" || { rollback_sni_stack_after_failure "$backup_dir" "$(localized_text "入口模式 ${ENTRY_MODE} 应用失败" "Entry mode ${ENTRY_MODE} application failed" "Режим входа в приложение ${ENTRY_MODE} не выполнен.")"; return 1; }
    save_sni_stack_env
    harden_single_443_firewall
    generate_caddy_cf_manifest
    print_sni_stack_result
}
