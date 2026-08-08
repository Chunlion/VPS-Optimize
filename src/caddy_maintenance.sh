# shellcheck shell=bash
# Cloudflare/Caddy certificate maintenance, Caddy config repair, whitelist, and cleanup tools.

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

func_caddy_cf_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🩺 CF DNS 一键体检${PLAIN}" "${BOLD}🩺 CF DNS One-click health check${PLAIN}" "${BOLD}🩺 CF DNS проверка состояния в один клик${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"

    echo -e "$(localized_text "${YELLOW}▶ [1/5] 检查 Cloudflare Token ...${PLAIN}" "${YELLOW}▶ [1/5] Check Cloudflare Token ...${PLAIN}" "${YELLOW}▶ [1/5] Проверить токен Cloudflare ...${PLAIN}")"
    if [[ -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            if command -v curl >/dev/null 2>&1; then
                local verify_resp
                verify_resp=$(curl -s --max-time 8 -H "Authorization: Bearer ${CF_Token}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
                if echo "$verify_resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
                    echo -e "$(localized_text "${GREEN}✅ Cloudflare Token 校验通过${PLAIN}" "${GREEN}✅ Cloudflare Token verification passed${PLAIN}" "${GREEN}✅ Cloudflare Проверка токена пройдена${PLAIN}")"
                    ((ok_count++))
                else
                    echo -e "$(localized_text "${YELLOW}⚠️ Token 文件存在，但在线校验失败（可能权限不足/网络异常）${PLAIN}" "${YELLOW}⚠️ The Token file exists, but the online verification failed (maybe insufficient permissions/network abnormality)${PLAIN}" "${YELLOW}⚠️ Файл токена существует, но онлайн-проверка не удалась (возможно, недостаточные разрешения/неисправность сети)${PLAIN}")"
                    ((warn_count++))
                fi
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}" "${YELLOW}⚠️ curl is not installed, skip online verification.${PLAIN}" "${YELLOW}⚠️ curl не установлен, пропустите онлайн-проверку.${PLAIN}")"
                ((warn_count++))
            fi
        else
            echo -e "$(localized_text "${RED}❌ Token 文件为空，请在维护菜单 [2] 重新写入。${PLAIN}" "${RED}❌ Token file is empty, please rewrite it in the maintenance menu [2].${PLAIN}" "${RED}❌ Файл токена пуст, перезапишите его в меню обслуживания [2].${PLAIN}")"
            ((err_count++))
        fi
    else
        echo -e "$(localized_text "${RED}❌ 未找到 Token 文件: ${cf_env_file}${PLAIN}" "${RED}❌ Token file not found: ${cf_env_file}${PLAIN}" "${RED}❌ Файл токена не найден: ${cf_env_file}${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [2/5] 检查 Caddy 服务状态...${PLAIN}" "${YELLOW}▶ [2/5] Check Caddy service status...${PLAIN}" "${YELLOW}▶ [2/5] Проверьте статус службы Caddy...${PLAIN}")"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            echo -e "$(localized_text "${GREEN}✅ Caddy 服务运行中${PLAIN}" "${GREEN}✅ Caddy service is running${PLAIN}" "${GREEN}✅ Служба Caddy запущена${PLAIN}")"
            ((ok_count++))
        else
            echo -e "$(localized_text "${YELLOW}⚠️ Caddy 已安装但未运行${PLAIN}" "${YELLOW}⚠️ Caddy is installed but not running${PLAIN}" "${YELLOW}⚠️ Caddy установлен, но не работает${PLAIN}")"
            ((warn_count++))
        fi
    else
        echo -e "$(localized_text "${RED}❌ 未安装 Caddy${PLAIN}" "${RED}❌ Not installed Caddy${PLAIN}" "${RED}❌ Не установлено Caddy${PLAIN}")"
        ((err_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [3/5] 检查域名配置、证书与软链接...${PLAIN}" "${YELLOW}▶ [3/5] Check domain configuration, certificate and symlink...${PLAIN}" "${YELLOW}▶ [3/5] Проверьте конфигурацию доменного имени, сертификат и программную ссылку...${PLAIN}")"
    local domain_count=0
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            local domain
            local listen_addr
            local listen_port
            local listen_target
            local backend
            local backend_addr
            local backend_port
            local cert_file
            local key_file
            local cert_end
            local cert_ts
            local now_ts
            local days_left

            domain=$(basename "$conf_file" .caddy)
            cert_file="/etc/caddy/certs/${domain}.crt"
            key_file="/etc/caddy/certs/${domain}.key"

            if ! head -n1 "$conf_file" | grep -q '^https://'; then
                continue
            fi
            ((domain_count++))

            listen_addr=$(caddy_conf_site_bind_addr "$conf_file")
            listen_port=$(caddy_conf_site_listen_port "$conf_file")
            listen_target=$(caddy_conf_site_listen_target "$conf_file")
            backend=$(caddy_conf_first_reverse_proxy_target "$conf_file")
            backend_addr=$(caddy_reverse_proxy_target_host "$backend")
            backend_port=$(caddy_reverse_proxy_target_port "$backend")

            echo -e "$(localized_text "${CYAN}  - 域名: ${domain}${PLAIN}" "${CYAN}- domain: ${domain}${PLAIN}" "${CYAN}— Доменное имя: ${domain}.${PLAIN}")"

            if [[ -f "$cert_file" && -f "$key_file" ]]; then
                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -n "$cert_end" && "$days_left" -gt 15 ]]; then
                    echo -e "$(localized_text "    ${GREEN}证书状态: 正常 (剩余约 ${days_left} 天)${PLAIN}" "${GREEN}Certificate status: Normal (approximately ${days_left} days remaining)${PLAIN}" "${GREEN}Статус сертификата: Нормальный (осталось примерно ${days_left} дней)${PLAIN}")"
                    ((ok_count++))
                elif [[ -n "$cert_end" ]]; then
                    echo -e "$(localized_text "    ${YELLOW}证书状态: 即将到期 (剩余约 ${days_left} 天)${PLAIN}" "${YELLOW}Certificate status: About to expire (approximately ${days_left} days remaining)${PLAIN}" "Статус сертификата ${YELLOW}: Срок действия истекает (осталось примерно ${days_left} дней)${PLAIN}")"
                    ((warn_count++))
                else
                    echo -e "$(localized_text "    ${RED}证书状态: 无法读取有效期${PLAIN}" "${RED}Certificate status: Unable to read validity period${PLAIN}" "${RED}Статус сертификата: Невозможно прочитать срок действия${PLAIN}")"
                    ((err_count++))
                fi
            else
                echo -e "$(localized_text "    ${RED}证书状态: 缺失 /etc/caddy/certs/${domain}.crt|.key${PLAIN}" "${RED}Certificate status: missing /etc/caddy/certs/${domain}.crt|.key${PLAIN}" "Статус сертификата ${RED}: отсутствует /etc/caddy/certs/${domain}.crt|.key${PLAIN}")"
                ((err_count++))
            fi

            if [[ -L "/root/cert/${domain}.crt" && -e "/root/cert/${domain}.crt" && -L "/root/cert/${domain}.key" && -e "/root/cert/${domain}.key" ]]; then
                echo -e "$(localized_text "    ${GREEN}软链接状态: /root/cert 已正确挂载${PLAIN}" "${GREEN}Symlink status: /root/cert has correctly mounted${PLAIN}" "Состояние программной ссылки ${GREEN}: /root/cert правильно смонтировал${PLAIN}.")"
                ((ok_count++))
            else
                echo -e "$(localized_text "    ${YELLOW}软链接状态: 缺失或失效，建议执行维护菜单 [10] 重建软链接${PLAIN}" "${YELLOW}Symlink status: missing or invalid, it is recommended to execute the maintenance menu [10] to rebuild the symlink${PLAIN}" "Состояние мягкой ссылки ${YELLOW}: отсутствует или недействителен, рекомендуется выполнить меню обслуживания [10] для восстановления мягкой ссылки${PLAIN}")"
                ((warn_count++))
            fi

            [[ -z "$listen_target" ]] && listen_target="$(localized_text "未知" "unknown" "неизвестно")"
            if [[ -n "$listen_port" ]] && caddy_listen_addr_port_is_visible "$listen_addr" "$listen_port"; then
                echo -e "$(localized_text "    ${GREEN}监听状态: Caddy 本地端口 ${listen_target} 可见${PLAIN}" "${GREEN}Listening status: Caddy local port ${listen_target} visible${PLAIN}" "Статус прослушивания ${GREEN}: локальный порт Caddy, ${listen_target} виден${PLAIN}")"
                ((ok_count++))
            else
                echo -e "$(localized_text "    ${YELLOW}监听状态: 未检测到 ${listen_target} 在监听${PLAIN}" "    ${YELLOW}Listener: nothing is listening on ${listen_target}${PLAIN}" "    ${YELLOW}Прослушивание: на ${listen_target} служба не обнаружена${PLAIN}")"
                ((warn_count++))
            fi

            [[ -z "$backend" ]] && backend="$(localized_text "未知" "unknown" "неизвестно")"
            if [[ -z "$backend_addr" || -z "$backend_port" ]]; then
                echo -e "$(localized_text "    ${YELLOW}⚠️ 后端状态：无法从配置读取后端地址${PLAIN}" "${YELLOW}⚠️ Backend status: Unable to read backend address${PLAIN} from configuration" "${YELLOW}⚠️ Статус серверной части: невозможно прочитать адрес внутренней части${PLAIN} из конфигурации.")"
                ((warn_count++))
            elif probe_backend_target "$(localized_text "    后端状态" "    Backend status" "    Состояние бэкенда")" "$backend_addr" "$backend_port"; then
                ((ok_count++))
            else
                ((warn_count++))
            fi
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi

    if [[ "$domain_count" -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到本功能托管的域名配置（https://域名:端口）。${PLAIN}" "${YELLOW}⚠️ The domain configuration hosted by this function was not detected (https://域名:端口）。${PLAIN}" "${YELLOW}⚠️ Конфигурация доменного имени, размещенная с помощью этой функции, не обнаружена (https://域名:端口）。${PLAIN}")"
        ((warn_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [4/5] 检查清单文件...${PLAIN}" "${YELLOW}▶ [4/5] Checklist file...${PLAIN}" "${YELLOW}▶ [4/5] Файл контрольного списка...${PLAIN}")"
    if [[ -f /root/cert/caddy_cf_manifest.txt ]]; then
        echo -e "$(localized_text "${GREEN}✅ 清单文件存在: /root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ Manifest file exists: /root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ Существует файл манифеста: /root/cert/caddy_cf_manifest.txt.${PLAIN}")"
        ((ok_count++))
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 清单文件不存在，建议执行维护菜单 [11] 重建。${PLAIN}" "${YELLOW}⚠️ The manifest file does not exist, it is recommended to perform maintenance menu [11] to rebuild.${PLAIN}" "${YELLOW}⚠️ Файл манифеста не существует, рекомендуется выполнить меню обслуживания [11] для восстановления.${PLAIN}")"
        ((warn_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [5/5] 总结...${PLAIN}" "${YELLOW}▶ [5/5] Summary...${PLAIN}" "${YELLOW}▶ [5/5] Краткое описание...${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${CYAN}体检结果: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}" "${CYAN}Health check results: ${ok_count} Normal / ${warn_count} Warning / ${err_count} Abnormal${PLAIN}" "${CYAN}Результаты медицинского осмотра: ${ok_count} Норма / ${warn_count} Предупреждение / ${err_count} Отклонение от нормы${PLAIN}")"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "$(localized_text "${RED}建议优先修复异常项，再继续业务切流。${PLAIN}" "${RED}It is recommended to fix the abnormal items first before continuing the business flow cutoff.${PLAIN}" "${RED}Рекомендуется сначала устранить аномальные элементы, прежде чем продолжать отключение бизнес-потока.${PLAIN}")"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}当前可继续运行，但建议处理警告项提高稳定性。${PLAIN}" "${YELLOW}Can currently continue to run, but it is recommended to handle the warning items to improve stability.${PLAIN}" "${YELLOW}в настоящее время может продолжать работать, но рекомендуется обработать элементы предупреждений для повышения стабильности.${PLAIN}")"
    else
        echo -e "$(localized_text "${GREEN}检查未发现异常。${PLAIN}" "${GREEN}Check found no abnormality.${PLAIN}" "${GREEN}Проверка не выявила отклонений.${PLAIN}")"
    fi
}

func_caddy_cf_auto_fix() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧰 CF DNS 一键自动修复${PLAIN}" "${BOLD}🧰 CF DNS One-click automatic repair${PLAIN}" "${BOLD}🧰 CF DNS Автоматическое восстановление в один клик${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local fixed_count=0
    local warn_count=0
    local fail_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    local acme_bin="/root/.acme.sh/acme.sh"

    echo -e "$(localized_text "${YELLOW}▶ [1/7] 修复基础目录与主配置...${PLAIN}" "${YELLOW}▶ [1/7] Repair the basic directory and main configuration...${PLAIN}" "${YELLOW}▶ [1/7] Восстановление базового каталога и основной конфигурации...${PLAIN}")"
    mkdir -p /root/cert /etc/caddy/certs /etc/caddy/conf.d /root/.config/vps-panel
    chmod 700 /root/.config/vps-panel >/dev/null 2>&1

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
        ((fixed_count++))
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
        ((fixed_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [1.5/7] 隔离旧式站点配置（避免抢占 443）...${PLAIN}" "${YELLOW}▶ [1.5/7] Isolating legacy site configurations (avoiding preemption 443)...${PLAIN}" "${YELLOW}▶ [1.5/7] Изолирование устаревших конфигураций сайта (избежание приоритетного вытеснения 443)...${PLAIN}")"
    quarantine_legacy_caddy_443_configs

    echo -e "$(localized_text "${YELLOW}▶ [2/7] 修复证书权限...${PLAIN}" "${YELLOW}▶ [2/7] Repair certificate permissions...${PLAIN}" "${YELLOW}▶ [2/7] Разрешения на ремонт сертификата...${PLAIN}")"
    if [[ -d /etc/caddy/certs ]]; then
        if id caddy >/dev/null 2>&1; then
            chown root:caddy /etc/caddy/certs/* 2>/dev/null
            chmod 640 /etc/caddy/certs/* 2>/dev/null
        else
            chmod 600 /etc/caddy/certs/* 2>/dev/null
        fi
        ((fixed_count++))
    else
        ((warn_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [3/7] 全量重建 /root/cert 软链接...${PLAIN}" "${YELLOW}▶ [3/7] Full reconstruction /root/cert symlink...${PLAIN}" "${YELLOW}▶ [3/7] Полная реконструкция /root/cert символическая ссылка...${PLAIN}")"
    local relink_count=0
    if [[ -d /etc/caddy/certs ]]; then
        while IFS= read -r cert_path; do
            local domain
            domain=$(basename "$cert_path" .crt)
            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                ((relink_count++))
            fi
        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
    fi
    echo -e "$(localized_text "${GREEN}✅ 已重建 ${relink_count} 组软链接。${PLAIN}" "${GREEN}✅ The ${relink_count} group symlink has been rebuilt.${PLAIN}" "${GREEN}✅ символическая ссылка группы ${relink_count} была перестроена.${PLAIN}")"
    ((fixed_count++))

    echo -e "$(localized_text "${YELLOW}▶ [4/7] 近效期证书自动续签...${PLAIN}" "${YELLOW}▶ [4/7] Automatic renewal of recent validity certificate...${PLAIN}" "${YELLOW}▶ [4/7] Автоматическое продление последнего сертификата действия...${PLAIN}")"
    local renew_count=0
    local renew_fail=0
    if [[ -x "$acme_bin" && -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            while IFS= read -r conf_file; do
                local domain
                local cert_file
                local cert_end
                local cert_ts
                local now_ts
                local days_left

                domain=$(basename "$conf_file" .caddy)
                cert_file="/etc/caddy/certs/${domain}.crt"

                if ! head -n1 "$conf_file" | grep -q '^https://'; then
                    continue
                fi
                if [[ ! -f "$cert_file" ]]; then
                    continue
                fi

                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -z "$cert_end" || "$days_left" -le 15 ]]; then
                    if issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                        "$acme_bin" --install-cert -d "$domain" --ecc \
                            --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                            --key-file "/etc/caddy/certs/${domain}.key" \
                            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1
                        ((renew_count++))
                    else
                        ((renew_fail++))
                    fi
                fi
            done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)

            if [[ "$renew_fail" -gt 0 ]]; then
                ((warn_count+=renew_fail))
            fi
            echo -e "$(localized_text "${GREEN}✅ 自动续签完成，成功 ${renew_count} 个，失败 ${renew_fail} 个。${PLAIN}" "${GREEN}✅ Automatic renewal completed, ${renew_count} successful and ${renew_fail} failed.${PLAIN}" "${GREEN}✅ Автоматическое продление завершено, ${renew_count} успешно, ${renew_fail} не удалось.${PLAIN}")"
            ((fixed_count++))
        else
            echo -e "$(localized_text "${YELLOW}⚠️ Token 为空，跳过自动续签。${PLAIN}" "${YELLOW}⚠️ Token is empty, skip automatic renewal.${PLAIN}" "${YELLOW}⚠️ Токен пуст, пропустите автоматическое продление.${PLAIN}")"
            ((warn_count++))
        fi
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 acme.sh 或 Token 文件，跳过自动续签。${PLAIN}" "${YELLOW}⚠️ No acme.sh or Token file detected, skipping automatic renewal.${PLAIN}" "${YELLOW}⚠️ acme.sh или файл токена не обнаружены, автоматическое продление отсутствует.${PLAIN}")"
        ((warn_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [5/7] 校验并重载 Caddy...${PLAIN}" "${YELLOW}▶ [5/7] Verify and reload Caddy...${PLAIN}" "${YELLOW}▶ [5/7] Проверьте и перезагрузите Caddy...${PLAIN}")"
    if command -v caddy >/dev/null 2>&1; then
        if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            systemctl enable caddy >/dev/null 2>&1
            if systemctl restart caddy >/dev/null 2>&1; then
                echo -e "$(localized_text "${GREEN}✅ Caddy 配置校验通过并重启成功。${PLAIN}" "${GREEN}✅ Caddy configuration validation passed and restarted successfully.${PLAIN}" "${GREEN}✅ Caddy Проверка конфигурации пройдена и успешно перезапущена.${PLAIN}")"
                ((fixed_count++))
            else
                echo -e "$(localized_text "${RED}❌ Caddy 重启失败，请手动检查日志。${PLAIN}" "${RED}❌ Caddy Restart failed, please check the log manually.${PLAIN}" "${RED}❌ Caddy Не удалось перезапустить, проверьте журнал вручную.${PLAIN}")"
                ((fail_count++))
            fi
        else
            echo -e "$(localized_text "${RED}❌ Caddy 配置校验失败，未执行重启。${PLAIN}" "${RED}❌ Caddy configuration validation failed and restart was not performed.${PLAIN}" "${RED}❌ Caddy Проверка конфигурации не удалась, и перезапуск не был выполнен.${PLAIN}")"
            ((fail_count++))
        fi
    else
        echo -e "$(localized_text "${RED}❌ 未安装 Caddy，无法执行重载。${PLAIN}" "${RED}❌ Caddy is not installed and reloading cannot be performed.${PLAIN}" "${RED}❌ Caddy не установлен и перезагрузка невозможна.${PLAIN}")"
        ((fail_count++))
    fi

    echo -e "$(localized_text "${YELLOW}▶ [6/7] 重建清单文件...${PLAIN}" "${YELLOW}▶ [6/7] Rebuild the manifest file...${PLAIN}" "${YELLOW}▶ [6/7] Пересобрать файл манифеста...${PLAIN}")"
    generate_caddy_cf_manifest
    ((fixed_count++))
    echo -e "$(localized_text "${GREEN}✅ 清单已重建: /root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ List has been rebuilt: /root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ Список был перестроен: /root/cert/caddy_cf_manifest.txt${PLAIN}")"

    echo -e "$(localized_text "${YELLOW}▶ [7/7] 补全 acme 自动续签任务...${PLAIN}" "${YELLOW}▶ [7/7] Complete acme automatic renewal task...${PLAIN}" "${YELLOW}▶ [7/7] Выполните задачу автоматического продления acme...${PLAIN}")"
    if [[ -x "$acme_bin" ]]; then
        if "$acme_bin" --install-cronjob >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ acme.sh 自动续签任务已确认。${PLAIN}" "${GREEN}✅ acme.sh The automatic renewal task has been confirmed.${PLAIN}" "${GREEN}✅ acme.sh Задача на автоматическое продление подтверждена.${PLAIN}")"
            ((fixed_count++))
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 无法确认 acme.sh 续签任务，请手动检查 crontab。${PLAIN}" "${YELLOW}⚠️ Unable to confirm acme.sh renewal task, please check crontab manually.${PLAIN}" "${YELLOW}⚠️ Невозможно подтвердить задачу обновления acme.sh, проверьте crontab вручную.${PLAIN}")"
            ((warn_count++))
        fi
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 acme.sh，跳过续签任务补全。${PLAIN}" "${YELLOW}⚠️ acme.sh is not installed and the renewal task completion is skipped.${PLAIN}" "${YELLOW}⚠️ acme.sh не установлен и выполнение задачи обновления пропускается.${PLAIN}")"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${CYAN}自动修复结果: ${GREEN}${fixed_count} 已修复${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${fail_count} 失败${PLAIN}" "${CYAN}Automatic repair results: ${fixed_count} Fixed / ${warn_count} Warning / ${fail_count} Failed${PLAIN}" "${CYAN}Результаты автоматического ремонта : ${fixed_count} Исправлено / ${warn_count} Предупреждение / ${fail_count} Ошибка${PLAIN}")"
    if [[ "$fail_count" -gt 0 ]]; then
        echo -e "$(localized_text "${RED}存在失败项，建议先执行维护菜单 [13] 体检复查并查看 caddy 日志。${PLAIN}" "${RED}There are failed items in . It is recommended to perform health check review in the maintenance menu [13] and check the caddy log.${PLAIN}" "${RED}В есть неудачные элементы. Рекомендуется выполнить проверка состояния в меню обслуживания [13] и проверить журнал caddy.${PLAIN}")"
    else
        echo -e "$(localized_text "${GREEN}自动修复流程完成，可执行维护菜单 [13] 复检确认。${PLAIN}" "${GREEN}Automatic repair process is completed, and the maintenance menu [13] can be executed for re-inspection and confirmation.${PLAIN}" "${GREEN}Процесс автоматического ремонта завершен, и можно запустить меню обслуживания [13] для повторной проверки и подтверждения.${PLAIN}")"
    fi
}

func_caddy_cf_maintenance_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🛠️ 443 / Caddy / Cloudflare 维护中心${PLAIN}" "${BOLD}🛠️ 443 / Caddy / Cloudflare Maintenance Center${PLAIN}" "${BOLD}🛠️ 443 / Caddy / Cloudflare Центр технического обслуживания${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：排查 443 链路、重签证书、修复软链接、隔离旧配置和回滚。${PLAIN}" "${YELLOW}Purpose: troubleshooting 443 links, re-signing certificates, repairing symlinks, isolating old configurations and rolling back.${PLAIN}" "${YELLOW}Назначение: устранение неполадок 443 ссылок, переподписка сертификатов, восстановление программных ссылок, изоляция старых конфигураций и откат.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}建议顺序：先 [1] 体检，再按异常选择证书或 Caddy 修复项。${PLAIN}" "${YELLOW}Recommended order: [1] health check first, then select the certificate or Caddy repair item according to the abnormality.${PLAIN}" "${YELLOW}Рекомендуемый порядок: [1] Сначала проверка состояния, затем выберите сертификат или элемент ремонта Caddy в соответствии с неисправностью.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 443 单入口常用${PLAIN}" "${BOLD}▶ 443 shared entry commonly used${PLAIN}" "${BOLD}▶ 443 Обычно используется с одним входом${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  1. 443 链路与安全体检${PLAIN}       ${YELLOW}(Nginx/Caddy/REALITY/面板/版本隐藏)${PLAIN}" "${GREEN}1. 443 Link and security health check (Nginx/Caddy/REALITY/panel/version hidden)${PLAIN}" "${GREEN}1. 443 проверка состояния канала и безопасности (Nginx/Caddy/REALITY/панель/версия скрыта)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 管理 443 网站/反代域名${PLAIN}    ${YELLOW}(新增/删除/查看，最常用)${PLAIN}" "${GREEN}2. Management 443 website/reverse domain (add/delete/view, most commonly used)${PLAIN}" "${GREEN}2. Веб-сайт Management 443/обратное доменное имя (добавление/удаление/просмотр, наиболее часто используемый)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改 443 分流参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}" "${GREEN}3. Modify 443 routing parameters   (Panel/Subscription/REALITY/Entry Port and Path)${PLAIN}" "${GREEN}3. Измените 443 параметра маршрутизации   (Панель/Подписка/REALITY/Входной порт и путь)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 重新应用上次 443 配置${PLAIN}     ${YELLOW}(读取 sni-stack.env 重建配置)${PLAIN}" "${GREEN}4. Reapply the last 443 configuration (read sni-stack.env and rebuild the configuration)${PLAIN}" "${GREEN}4. Повторно примените последнюю конфигурацию 443 (прочитайте sni-stack.env и перестройте конфигурацию)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}" "${GREEN}5. Subscription link / External Proxy prompt (check whether the node link outputs public port 443)${PLAIN}" "${GREEN}5. Ссылка на подписку/запрос внешнего прокси (проверьте, выводит ли ссылка узла публичный порт 443)${PLAIN}")"
        echo -e "$(localized_text "${RED}  6. 回滚 443 单入口配置${PLAIN}       ${YELLOW}(从最近备份恢复)${PLAIN}" "${RED}6. Rollback 443 Shared entry configuration   (restore from recent backup)${PLAIN}" "${RED}6. Откат 443 Конфигурация с общей точкой входа (восстановление из последней резервной копии)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 证书与 Cloudflare${PLAIN}" "${BOLD}▶ Certificate and Cloudflare${PLAIN}" "${BOLD}▶ Сертификат и Cloudflare${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 查看已管理域名 / 证书路径${PLAIN}" "${GREEN}7. View the managed domain/certificate path${PLAIN}" "${GREEN}7. Просмотрите имя управляемого домена/путь сертификата.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  8. 更新 Cloudflare API Token${PLAIN}" "${GREEN}8. Update Cloudflare API Token${PLAIN}" "${GREEN}8. Обновите Cloudflare API-токен${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  9. 重新签发某个域名证书${PLAIN}" "${GREEN}9. Reissue a domain certificate${PLAIN}" "${GREEN}9. Перевыпустите сертификат доменного имени.${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 10. 重建 /root/cert 证书软链接${PLAIN}" "${GREEN}10. Rebuild /root/cert certificate symlink${PLAIN}" "${GREEN}10. Перестройте программную ссылку сертификата /root/cert.${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 11. 重建证书清单文件${PLAIN}" "${GREEN}11. Rebuild the certificate list file${PLAIN}" "${GREEN}11. Перестройте файл списка сертификатов.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ Caddy 修复与清理${PLAIN}" "${BOLD}▶ Caddy Repair and Cleanup${PLAIN}" "${BOLD}▶ Caddy Ремонт и очистка${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 12. 校验并重载 Caddy${PLAIN}" "${GREEN}12. Verify and reload Caddy${PLAIN}" "${GREEN}12. Проверьте и перезагрузите Caddy.${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 13. Caddy/证书一键体检${PLAIN}       ${YELLOW}(Token/证书/监听/后端)${PLAIN}" "${GREEN}13. Caddy/certificate one-click health check (Token/certificate/listening/backend)${PLAIN}" "${GREEN}13. Caddy/сертификат, проверка состояния в один клик (токен/сертификат/прослушивание/бэкенд)${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 14. 一键自动修复常见问题${PLAIN}" "${GREEN}14. One-click automatic repair of common problems${PLAIN}" "${GREEN}14. Автоматическое устранение распространенных проблем в один клик${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 15. 隔离旧 Caddy 配置${PLAIN}        ${YELLOW}(避免抢占 443)${PLAIN}" "${GREEN}15. Isolate the old Caddy and configure (avoid preemption 443)${PLAIN}" "${GREEN}15. Изолируйте старый Caddy и настройте (избегайте вытеснения 443)${PLAIN}")"
        echo -e "$(localized_text "${RED} 16. 隔离某个域名的 Caddy 配置与证书${PLAIN}" "${RED}16. Isolate a domain Caddy configuration and certificate${PLAIN}" "${RED}16. Изолируйте конфигурацию доменного имени Caddy и сертификат.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local m_choice
        read_trimmed m_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"

        case "$m_choice" in
            1) m_choice=11 ;;
            2) m_choice=15 ;;
            3) m_choice=16 ;;
            4) m_choice=12 ;;
            5) m_choice=13 ;;
            6) m_choice=14 ;;
            7) m_choice=1 ;;
            8) m_choice=2 ;;
            9) m_choice=3 ;;
            10) m_choice=4 ;;
            11) m_choice=7 ;;
            12) m_choice=6 ;;
            13) m_choice=8 ;;
            14) m_choice=9 ;;
            15) m_choice=10 ;;
            16) m_choice=5 ;;
        esac

        case $m_choice in
            16)
                edit_sni_stack_runtime_profile
                ;;

            1)
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${CYAN}👇 当前清单内容：${PLAIN}" "${CYAN}👇 Current list content:${PLAIN}" "${CYAN}👇 Текущее содержимое списка:${PLAIN}")"
                cat /root/cert/caddy_cf_manifest.txt 2>/dev/null
                ;;

            2)
                local new_token escaped_token
                mkdir -p /root/.config/vps-panel
                chmod 700 /root/.config/vps-panel
                echo -e "$(localized_text "${CYAN}👇 请输入新的 Cloudflare API Token${PLAIN}" "${CYAN}👇 Please enter the new Cloudflare API Token${PLAIN}" "${CYAN}👇 Введите новый токен API Cloudflare.${PLAIN}")"
                read_secret_trimmed new_token "CF Token: "
                if [[ -z "$new_token" || ${#new_token} -lt 20 ]]; then
                    echo -e "$(localized_text "${RED}❌ Token 长度异常，更新取消。${PLAIN}" "${RED}❌ Token length is abnormal and the update is cancelled.${PLAIN}" "${RED}❌ Неверная длина токена, обновление отменено.${PLAIN}")"
                else
                    echo -e "$(localized_text "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}" "${CYAN}▶ Verifying online Cloudflare Token...${PLAIN}" "${CYAN}▶ Проверка токена Cloudflare онлайн...${PLAIN}")"
                    verify_cf_token_online "$new_token"
                    local verify_rc=$?
                    if [[ "$verify_rc" -eq 1 ]]; then
                        echo -e "$(localized_text "${RED}❌ Token 在线校验失败，未写入。${PLAIN}" "${RED}❌ Token failed online verification and was not written.${PLAIN}" "${RED}❌ Токен не прошел онлайн-проверку и не был записан.${PLAIN}")"
                        echo -e "$(localized_text "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}" "${YELLOW}Requires permissions: Zone.DNS.Edit + Zone.Zone.Read${PLAIN}" "${YELLOW}требуются разрешения: Zone.DNS.Edit + Zone.Zone.Read.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    elif [[ "$verify_rc" -eq 2 ]]; then
                        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，跳过在线校验，继续写入。${PLAIN}" "${YELLOW}⚠️ curl is not installed, skip online verification and continue writing.${PLAIN}" "${YELLOW}⚠️ curl не установлен, пропустите онлайн-проверку и продолжайте писать.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${GREEN}✅ Token 校验通过。${PLAIN}" "${GREEN}✅ Token verification passed.${PLAIN}" "${GREEN}✅ Проверка токена пройдена.${PLAIN}")"
                    fi

                    escaped_token=${new_token//\'/\'"\'"\'}
                    printf "CF_Token='%s'\n" "$escaped_token" > /root/.config/vps-panel/cloudflare.env
                    chmod 600 /root/.config/vps-panel/cloudflare.env
                    echo -e "$(localized_text "${GREEN}✅ Cloudflare Token 已更新。${PLAIN}" "${GREEN}✅ Cloudflare Token has been updated.${PLAIN}" "${GREEN}✅ Cloudflare Токен обновлен.${PLAIN}")"
                fi
                ;;

            3)
                local domain domain_input
                local acme_bin="/root/.acme.sh/acme.sh"
                local cf_env_file="/root/.config/vps-panel/cloudflare.env"

                read_trimmed domain_input "$(localized_text "👉 请输入要重签的域名: " "👉 Please enter the domain you want to re-sign:" "👉 Пожалуйста, введите доменное имя, которое вы хотите переподписать:")"
                domain=$(normalize_domain_input "$domain_input")
                if ! is_valid_domain "$domain"; then
                    print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "$(localized_text "${RED}❌ 未检测到 acme.sh，请先运行主菜单 [19] -> [2] 首次配置 443 单入口。${PLAIN}" "${RED}❌ acme.sh is not detected, please run the main menu [19] -> [2] first to configure 443 shared entry.${PLAIN}" "${RED}❌ acme.sh не обнаружен, запустите главное меню [19] -> [2], чтобы настроить общую запись 443 в первый раз.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi
                if [[ ! -f "$cf_env_file" ]]; then
                    echo -e "$(localized_text "${RED}❌ 未检测到 Cloudflare Token，请先执行本菜单 [2]。${PLAIN}" "${RED}❌ Cloudflare Token is not detected, please execute this menu [2] first.${PLAIN}" "${RED}❌ Cloudflare Токен не обнаружен, сначала откройте это меню [2].${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                # shellcheck disable=SC1090
                source "$cf_env_file"
                confirm_risk_action "$(localized_text "重签并安装 ${domain} 的证书" "Re-sign and install the certificate of ${domain}" "Переподпишите и установите сертификат ${domain}.")" \
                    "$(localized_text "acme.sh 证书缓存、/etc/caddy/certs 和 /root/cert 软链接" "acme.sh certificate cache, /etc/caddy/certs and /root/cert symlinks" "Кэш сертификатов acme.sh, символическая ссылка /etc/caddy/certs и /root/cert")" \
                    "$(localized_text "使用现有 Caddy/证书备份恢复，或重新运行证书维护菜单签发" "Use the existing Caddy/certificate backup to restore, or re-run the certificate maintenance menu to issue" "Используйте существующую резервную копию Caddy/сертификата для восстановления или повторно запустите меню обслуживания сертификата для выдачи.")" \
                    "$(localized_text "确认域名 DNS 已解析，Cloudflare Token 权限正确。" "Confirm that the domain DNS has been resolved and the Cloudflare Token permissions are correct." "Убедитесь, что доменное имя DNS разрешено и разрешения токена Cloudflare верны.")" || {
                    echo -e "$(localized_text "${BLUE}已取消证书重签。${PLAIN}" "${BLUE}Certificate re-signing has been canceled.${PLAIN}" "${BLUE}Переподписка сертификата отменена.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                }
                echo -e "$(localized_text "${CYAN}▶ 正在重签证书: ${domain}${PLAIN}" "${CYAN}▶ Re-issuing certificate: ${domain}${PLAIN}" "${CYAN}▶ Перевыпуск сертификата: ${domain}${PLAIN}")"

                if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                    echo -e "$(localized_text "${RED}❌ 证书签发失败：${domain}${PLAIN}" "${RED}❌ Certificate issuance failed: ${domain}${PLAIN}" "${RED}❌ Не удалось выдать сертификат: ${domain}.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}   提示：建议先执行本菜单 [14] 自动修复再重试。${PLAIN}" "${YELLOW}Tip: It is recommended to perform automatic repair in this menu [14] and then try again.${PLAIN}" "${YELLOW}Совет: рекомендуется выполнить автоматическое восстановление в этом меню [14], а затем повторить попытку.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                mkdir -p /etc/caddy/certs /root/cert
                if ! "$acme_bin" --install-cert -d "$domain" --ecc \
                    --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                    --key-file "/etc/caddy/certs/${domain}.key" \
                    --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
                    echo -e "$(localized_text "${RED}❌ 证书安装失败：${domain}${PLAIN}" "${RED}❌ Certificate installation failed: ${domain}${PLAIN}" "${RED}❌ Не удалось установить сертификат: ${domain}.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if id caddy >/dev/null 2>&1; then
                    chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
                    chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                else
                    chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                fi

                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${GREEN}✅ 重签完成并已更新 /root/cert 软链接。${PLAIN}" "${GREEN}✅ The re-signing is completed and the /root/cert symlink has been updated.${PLAIN}" "${GREEN}✅ Переподписка завершена, символическая ссылка /root/cert обновлена.${PLAIN}")"
                ;;

            4)
                local link_mode domain domain_input
                mkdir -p /root/cert
                read_trimmed link_mode "$(localized_text "❓ 重建全部链接还是单域名？(all/one): " "❓ Rebuild all links or a single domain? (all/one):" "❓Перестроить все ссылки или одно доменное имя? (все/один):")"

                if [[ "$link_mode" == "all" ]]; then
                    local relink_count=0
                    if [[ -d /etc/caddy/certs ]]; then
                        while IFS= read -r cert_path; do
                            domain=$(basename "$cert_path" .crt)
                            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                                ((relink_count++))
                            fi
                        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
                    fi
                    generate_caddy_cf_manifest
                    echo -e "$(localized_text "${GREEN}✅ 已重建 ${relink_count} 个域名的证书软链接。${PLAIN}" "${GREEN}✅ The certificate symlinks of ${relink_count} domains have been rebuilt.${PLAIN}" "${GREEN}✅ символическая ссылка сертификатов доменных имен ${relink_count} были перестроены.${PLAIN}")"
                else
                    read_trimmed domain_input "$(localized_text "👉 请输入域名: " "👉 Please enter domain:" "👉 Пожалуйста, введите доменное имя:")"
                    domain=$(normalize_domain_input "$domain_input")
                    if ! is_valid_domain "$domain"; then
                        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    fi
                    if [[ -f "/etc/caddy/certs/${domain}.crt" && -f "/etc/caddy/certs/${domain}.key" ]]; then
                        ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                        ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                        generate_caddy_cf_manifest
                        echo -e "$(localized_text "${GREEN}✅ 软链接已重建：/root/cert/${domain}.crt 与 /root/cert/${domain}.key${PLAIN}" "${GREEN}✅ symlink has been rebuilt: /root/cert/${domain}.crt and /root/cert/${domain}.key${PLAIN}" "${GREEN}✅ символическая ссылка была перестроена: /root/cert/${domain}.crt и /root/cert/${domain}.key.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ 未找到该域名证书文件。${PLAIN}" "${RED}❌ The domain certificate file was not found.${PLAIN}" "${RED}❌ Файл сертификата доменного имени не найден.${PLAIN}")"
                    fi
                fi
                ;;

            5)
                local domain domain_input purge_acme
                read_trimmed domain_input "$(localized_text "👉 请输入要隔离的域名: " "👉 Please enter the domain to be isolated:" "👉 Пожалуйста, введите доменное имя, которое необходимо изолировать:")"
                domain=$(normalize_domain_input "$domain_input")
                if ! is_valid_domain "$domain"; then
                    print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if ! confirm_risk_action "$(localized_text "隔离 ${domain} 的配置与证书" "Isolate the configuration and certificate of ${domain}" "Изолируйте конфигурацию и сертификат ${domain}.")" \
                    "$(localized_text "Caddy 配置、证书文件和可选 acme.sh 历史记录" "Caddy configuration, certificate files, and optional acme.sh history" "Конфигурация Caddy, файлы сертификатов и дополнительная история acme.sh.")" \
                    "$(localized_text "从隔离目录手动移回，或重新签发证书并恢复 Caddy 配置" "Manually move back from the quarantine directory, or reissue the certificate and restore the Caddy configuration" "Вручную вернитесь из каталога карантина или перевыпустите сертификат и восстановите конфигурацию Caddy.")" \
                    "$(localized_text "确认该域名不再承载线上服务，或已经准备好重新签发。" "Confirm that the domain no longer hosts online services or is ready for re-issuance." "Подтвердите, что доменное имя больше не размещает онлайн-сервисы или готово к перевыпуску.")"; then
                    echo -e "$(localized_text "${BLUE}已取消隔离。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                local domain_quarantine_dir="/etc/vps-optimize/quarantine/caddy-domain-${domain}-$(date +%s)"
                mkdir -p "$domain_quarantine_dir"
                quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true

                read_trimmed purge_acme "$(localized_text "❓ 是否同时删除 acme.sh 历史记录？(Y/n，默认 y，建议保留): " "❓ Do you want to delete the acme.sh history at the same time? (Y/n, default y, recommended to keep):" "❓ Хотите одновременно удалить историю acme.sh? (Да/нет, по умолчанию y, рекомендуется сохранить):")"
                if is_yes "$purge_acme"; then
                    /root/.acme.sh/acme.sh --remove -d "$domain" --ecc >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                fi

                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                fi
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${GREEN}✅ ${domain} 的 Caddy 配置与证书已隔离到：${domain_quarantine_dir}${PLAIN}" "${GREEN}✅ Caddy configuration and certificate of ${domain} have been isolated to: ${domain_quarantine_dir}${PLAIN}" "${GREEN}✅ Конфигурация Caddy и сертификат ${domain} изолированы от: ${domain_quarantine_dir}.${PLAIN}")"
                ;;

            6)
                caddy_format_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ Caddy 配置已格式化，校验通过并重启生效。${PLAIN}" "${GREEN}✅ Caddy configuration has been formatted, passed verification and will take effect after restarting.${PLAIN}" "${GREEN}✅ Конфигурация Caddy отформатирована, прошла проверку и вступит в силу после перезагрузки.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Caddy 配置校验失败，请检查 /etc/caddy/conf.d/*.caddy${PLAIN}" "${RED}❌ Caddy configuration validation failed, please check /etc/caddy/conf.d/*.caddy${PLAIN}" "${RED}❌ Caddy Проверка конфигурации не удалась, проверьте /etc/caddy/conf.d/*.caddy${PLAIN}")"
                fi
                ;;

            7)
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${GREEN}✅ 清单已重建：/root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ List has been rebuilt: /root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ Список был перестроен: /root/cert/caddy_cf_manifest.txt${PLAIN}")"
                ;;

            8)
                func_caddy_cf_health_check
                ;;

            9)
                func_caddy_cf_auto_fix
                ;;

            10)
                quarantine_legacy_caddy_443_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ 隔离完成，Caddy 已重载。${PLAIN}" "${GREEN}✅ Isolation completed, Caddy has been reloaded.${PLAIN}" "${GREEN}. Изоляция завершена, Caddy перезагружен.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ 当前 Caddy 配置校验失败，请先修复语法错误。${PLAIN}" "${RED}❌ The current Caddy configuration validation failed, please fix the syntax error first.${PLAIN}" "${RED}❌ Текущая проверка конфигурации Caddy не удалась, сначала исправьте синтаксическую ошибку.${PLAIN}")"
                fi
                ;;

            11)
                sni_stack_health_check
                ;;

            12)
                reapply_sni_stack_from_env
                ;;

            13)
                check_sni_stack_subscription_hint
                ;;

            14)
                rollback_sni_stack_config
                ;;

            15)
                manage_sni_stack_sites
                ;;

            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")" ;;
        esac

        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

# ---------------------------------------------------------
# 新增功能：查看 Caddy 已申请证书路径
# ---------------------------------------------------------
func_view_caddy_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔑 Caddy 已申请证书路径查询${PLAIN}" "${BOLD}🔑 Caddy Applied certificate path query${PLAIN}" "${BOLD}🔑 Caddy Запрос пути примененного сертификата${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    if [[ ! -f "/etc/caddy/Caddyfile" ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 /etc/caddy/Caddyfile，请先配置反代！${PLAIN}" "${RED}❌ /etc/caddy/Caddyfile is not detected, please configure reverse proxy first!${PLAIN}" "${RED}❌ /etc/caddy/Caddyfile не обнаружен, сначала настройте обратный прокси-сервер!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    
    # 提取 Caddyfile 与 conf.d 中的域名 (排除注释，简单匹配)
    local domains
    domains=$(cat /etc/caddy/Caddyfile /etc/caddy/conf.d/*.caddy 2>/dev/null | grep -vE '^[[:space:]]*#' | grep '{' | awk '{print $1}' | tr -d '{')
    
    if [[ -z "$domains" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ Caddyfile 中没有配置明确的域名。${PLAIN}" "${YELLOW}⚠️ There is no clear domain configured in Caddyfile.${PLAIN}" "${YELLOW}⚠️ В файле Caddy нет четкого доменного имени.${PLAIN}")"
    else
        # Caddy 默认的证书存储根路径
        local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
        [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"
        
        for domain in $domains; do
            # 过滤掉本地回环等无意义的块
            if [[ "$domain" == ":80" || "$domain" == "localhost" ]]; then continue; fi
            
            echo -e "$(localized_text "${BLUE}🌐 域名: ${BOLD}${domain}${PLAIN}" "${BLUE}🌐 domain: ${domain}${PLAIN}" "${BLUE}🌐 Доменное имя: ${domain}${PLAIN}")"
            
            local found=false
            if [[ -d "$cert_root" ]]; then
                # 递归查找对应的 .crt 和 .key 文件
                local cert_file
                local key_file
                cert_file=$(find "$cert_root" -name "${domain}.crt" -print -quit 2>/dev/null)
                key_file=$(find "$cert_root" -name "${domain}.key" -print -quit 2>/dev/null)
                
                if [[ -n "$cert_file" && -n "$key_file" ]]; then
                    echo -e "$(localized_text "   ${GREEN}📄 公钥 (CRT):${PLAIN} ${cert_file}" "${GREEN}📄 Public key (CRT):${PLAIN} ${cert_file}" "${GREEN}📄 Открытый ключ (CRT):${PLAIN} ${cert_file}")"
                    echo -e "$(localized_text "   ${YELLOW}🔑 密钥 (KEY):${PLAIN} ${key_file}" "${YELLOW}🔑 Key (KEY):${PLAIN} ${key_file}" "${YELLOW}🔑 Ключ (KEY):${PLAIN} ${key_file}")"
                    found=true
                fi
            fi
            
            if ! $found; then
                echo -e "$(localized_text "   ${RED}❌ 未找到证书，可能尚未签发成功或路径异常。${PLAIN}" "${RED}❌ The certificate was not found. It may not have been successfully issued or the path may be abnormal.${PLAIN}" "${RED}❌ Сертификат не найден. Возможно, он не был успешно выдан или путь может быть ненормальным.${PLAIN}")"
            fi
            echo -e "------------------------------------------------"
        done
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

# ---------------------------------------------------------
# 新增功能：清空 Caddy 配置文件 (适配模块化安全架构)
# ---------------------------------------------------------
func_caddy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧹 清空 Caddy 配置文件 (模块化版本)${PLAIN}" "${BOLD}🧹 Clear Caddy configuration file (modular version)${PLAIN}" "${BOLD}🧹 Очистить файл конфигурации Caddy (модульная версия)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 检查主文件与模块化目录是否存在
    if [[ -f /etc/caddy/Caddyfile ]] || [[ -d /etc/caddy/conf.d ]]; then
        echo -e "$(localized_text "${YELLOW}将清空 /etc/caddy/conf.d/*.caddy，并重置 /etc/caddy/Caddyfile 为模块化初始状态。${PLAIN}" "${YELLOW}Will clear /etc/caddy/conf.d/*.caddy and reset /etc/caddy/Caddyfile to the modular initial state.${PLAIN}" "${YELLOW}очистит /etc/caddy/conf.d/*.caddy и сбросит /etc/caddy/Caddyfile в модульное исходное состояние.${PLAIN}")"
        if confirm_danger "$(localized_text "清空 Caddy 反代配置" "Clear Caddy reverse proxy configuration" "Очистить конфигурацию обратного прокси-сервера Caddy.")" "$(localized_text "所有独立 Caddy 反代配置会失效，相关网站/面板可能暂时打不开。" "All independent Caddy reverse proxy configurations will become invalid, and related websites/panels may not be opened temporarily." "Все независимые конфигурации обратный прокси Caddy станут недействительными, а соответствующие веб-сайты/панели могут быть временно недоступны.")" "$(localized_text "脚本会备份 Caddyfile 和 conf.d 目录，可按备份路径手动恢复。" "The script will back up the Caddyfile and conf.d directories, which can be restored manually according to the backup path." "Скрипт создаст резервную копию каталогов Caddyfile и conf.d, которые можно восстановить вручную в соответствии с путем резервной копии.")"; then
            
            # 1. 备份现有的模块化配置目录
            if [[ -d /etc/caddy/conf.d ]]; then
                local backup_dir="/etc/caddy/conf.d_bak_$(date +%s)"
                cp -r /etc/caddy/conf.d "$backup_dir" 2>/dev/null
                echo -e "$(localized_text "${BLUE}已备份原配置目录为 $backup_dir${PLAIN}" "${BLUE}Has backed up the original configuration directory to $backup_dir${PLAIN}" "${BLUE}создал резервную копию исходного каталога конфигурации в $backup_dir.${PLAIN}")"
                
                # 精准隔离所有 .caddy 配置文件，避免不可逆删除。
                while IFS= read -r caddy_conf; do
                    mv "$caddy_conf" "$backup_dir/" 2>/dev/null || true
                done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name '*.caddy' 2>/dev/null | sort)
            fi
            
            # 2. 守护主文件架构，重置为极简模式并注入模块化指令
            cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null
            echo "# Caddyfile Cleared and Reset to Modular Architecture" > /etc/caddy/Caddyfile
            echo "import conf.d/*" >> /etc/caddy/Caddyfile
            
            # 3. 重启生效
            systemctl restart caddy >/dev/null 2>&1
            echo -e "$(localized_text "${GREEN}✅ 所有反代配置已清空并成功重载！系统已恢复纯净的模块化初始状态。${PLAIN}" "${GREEN}✅ All reverse proxy configurations have been cleared and reloaded successfully! The system has been restored to its pristine, modular initial state.${PLAIN}" "${GREEN}✅ Все конфигурации обратный прокси очищены и успешно перезагружены! Система была восстановлена ​​в первозданном, модульном исходном состоянии.${PLAIN}")"
        else
            echo -e "$(localized_text "${BLUE}已取消清空操作。${PLAIN}" "${BLUE}The clearing operation has been canceled.${PLAIN}" "${BLUE}Операция очистки была отменена.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "${RED}❌ 未检测到 Caddy 配置文件或模块化目录！${PLAIN}" "${RED}❌ No Caddy configuration file or modular directory detected!${PLAIN}" "${RED}❌ Файл конфигурации или модульный каталог Caddy не обнаружен!${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

strip_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local tmp_file
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    awk '
        /# vps-optimize-ip-whitelist-start/ {skip=1; next}
        /# vps-optimize-ip-whitelist-end/ {skip=0; next}
        !skip {print}
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

insert_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local ranges="$2"
    local tmp_file block
    strip_caddy_ip_whitelist_block "$conf_file" || return 1
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    block=$(caddy_ip_whitelist_block "$ranges")
    awk -v block="$block" '
        inserted == 0 && /^[[:space:]]*[^#[:space:]].*\{[[:space:]]*$/ {
            print
            printf "%s", block
            inserted=1
            next
        }
        {print}
        END { if (inserted == 0) exit 1 }
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

func_caddy_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔐 Caddy 域名 IP 白名单${PLAIN}" "${BOLD}🔐 Caddy domain IP whitelist${PLAIN}" "${BOLD}🔐 Caddy доменное имя Белый список IP-адресов${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}适用于未启用 443 单入口、由 Caddy 直接对外服务的域名。${PLAIN}" "${YELLOW}Suitable for domains that do not enable the 443 shared entry and are directly served externally by Caddy.${PLAIN}" "${YELLOW}подходит для доменных имен, которые не поддерживают общий вход 443 и обслуживаются напрямую извне Caddy.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果该域名已接入 443 单入口，请用主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]，不要在 Caddy 层限制。${PLAIN}" "${YELLOW}If the domain has been connected to 443 shared entry, please use the main menu [19 443 shared entry management center] -> [8 Manage Web domain/reverse proxy] -> [5 Manage domain IP whitelist], do not limit it at the Caddy layer.${PLAIN}" "${YELLOW}Если доменное имя подключено к 443 единому входу, используйте главное меню [19 443 центр управления общим входом] -> [8 Управление именем веб-домена/обратным прокси-сервером] -> [5 Управление белым списком IP-адресов доменного имени], не ограничивайте его на уровне Caddy.${PLAIN}")"
    echo -e "------------------------------------------------"

    if ! command -v caddy >/dev/null 2>&1 || [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 Caddy 或 /etc/caddy/Caddyfile，请先配置 Caddy 反代。${PLAIN}" "${RED}❌ Caddy or /etc/caddy/Caddyfile is not detected, please configure Caddy reverse proxy first.${PLAIN}" "${RED}❌ Caddy или /etc/caddy/Caddyfile не обнаружен, сначала настройте обратный прокси-сервер Caddy.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    local domain domain_input conf_file first_site_line action backup_file
    read_trimmed domain_input "$(localized_text "请输入要管理的域名 (如 panel.example.com): " "Please enter the domain you want to manage (eg panel.example.com):" "Пожалуйста, введите доменное имя, которым вы хотите управлять (например, Panel.example.com):")"
    domain=$(normalize_domain_input "$domain_input")
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    conf_file="/etc/caddy/conf.d/${domain}.caddy"
    if [[ ! -f "$conf_file" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 ${conf_file}。该入口只管理脚本创建的模块化 Caddy 域名配置。${PLAIN}" "${RED}❌ ${conf_file} not found. This entry only manages the modular Caddy domain configuration created by the script.${PLAIN}" "${RED}❌ ${conf_file} не найден. Эта запись управляет только модульной конфигурацией доменного имени Caddy, созданной сценарием.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    first_site_line=$(grep -m1 -E '^[[:space:]]*[^#[:space:]].*\{' "$conf_file" 2>/dev/null | sed 's/^[[:space:]]*//')
    if [[ "$first_site_line" != "$domain "* && "$first_site_line" != "$domain{"* && "$first_site_line" != "https://${domain}"* ]]; then
        echo -e "$(localized_text "${RED}❌ ${conf_file} 的首个站点块不是 ${domain}，为避免误改已取消。${PLAIN}" "${RED}❌ The first site block of ${conf_file} is not ${domain}, and has been canceled to avoid mistaken modification.${PLAIN}" "${RED}❌ Первый блок сайта ${conf_file} — это не ${domain}, и он был отменен во избежание ошибочной модификации.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi
    if [[ "$first_site_line" =~ ^https://[^[:space:]]+:[0-9]+[[:space:]]*\{ ]]; then
        echo -e "$(localized_text "${RED}❌ 这个配置看起来属于 443 单入口本地 Caddy TLS 站点。请改用主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]。${PLAIN}" "${RED}❌ This configuration appears to belong to the 443 shared entry local Caddy TLS site. Please use the main menu instead [19 443 shared entry Management Center] -> [8 Manage Web domain/Reverse Proxy] -> [5 Manage domain IP Whitelist].${PLAIN}" "${RED}❌ Похоже, эта конфигурация принадлежит локальному сайту Caddy TLS с общей точкой входа 443. Вместо этого используйте главное меню [19 443 Центр управления общим входом] -> [8 Управление именем веб-домена/обратным прокси-сервером] -> [5 Управление белым списком IP-адресов доменных имен].${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    echo -e "$(localized_text "当前配置文件：${conf_file}" "Current configuration file: ${conf_file}" "Текущий файл конфигурации: ${conf_file}.")"
    if grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
        echo -e "$(localized_text "${YELLOW}当前状态：已启用脚本管理的 IP 白名单。${PLAIN}" "${YELLOW}Current status: IP whitelist for script management is enabled.${PLAIN}" "${YELLOW}Текущее состояние: белый список IP-адресов для управления сценариями включен.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}当前状态：未启用脚本管理的 IP 白名单。${PLAIN}" "${BLUE}Current status: IP whitelist for script management is not enabled.${PLAIN}" "${BLUE}Текущий статус: Белый список IP-адресов для управления сценариями не включен.${PLAIN}")"
    fi
    echo -e "$(localized_text "1. 设置/覆盖白名单" "1. Set/override whitelist" "1. Установить/переопределить белый список")"
    echo -e "$(localized_text "2. 清除白名单" "2. Clear the whitelist" "2. Очистите белый список")"
    echo -e "$(localized_text "0/q. 取消" "0/q. Cancel" "0/кв. Отмена")"
    read_trimmed action "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"

    backup_file="${conf_file}.bak_$(date +%s)"
    case "$action" in
        1)
            local ip_whitelist_input ip_whitelist_ranges current_client_ip
            local -a ip_whitelist_array=()
            current_client_ip=$(detect_ssh_client_ip)
            [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
            read_trimmed ip_whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
            if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
                echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format, and the operation has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат, и операция отменена.${PLAIN}")"
                read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                return
            fi
            append_vps_public_ips_to_whitelist ip_whitelist_array
            ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
            cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"; return; }
            if insert_caddy_ip_whitelist_block "$conf_file" "$ip_whitelist_ranges" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
                    echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
                    echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Caddy 重载失败，正在回滚...${PLAIN}" "${RED}❌ Caddy Reload failed, rolling back...${PLAIN}" "${RED}❌ Caddy Ошибка перезагрузки, откат...${PLAIN}")"
                    mv "$backup_file" "$conf_file"
                    systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                fi
            else
                echo -e "$(localized_text "${RED}❌ 写入后 Caddy 校验失败，正在回滚...${PLAIN}" "${RED}❌ After writing Caddy verification failed, rolling back...${PLAIN}" "${RED}❌ После записи Caddy проверка не удалась, откат...${PLAIN}")"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        2)
            if ! grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
                echo -e "$(localized_text "${BLUE}该域名没有脚本管理的白名单块，无需清除。${PLAIN}" "${BLUE}This domain does not have a script-managed whitelist block and does not need to be cleared.${PLAIN}" "${BLUE}Это доменное имя не имеет блока белого списка, управляемого сценарием, и его не нужно очищать.${PLAIN}")"
                read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                return
            fi
            cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"; return; }
            if strip_caddy_ip_whitelist_block "$conf_file" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ 已清除 ${domain} 的 IP 白名单。${PLAIN}" "${GREEN}✅ The IP whitelist of ${domain} has been cleared.${PLAIN}" "${GREEN}✅ Белый список IP-адресов ${domain} очищен.${PLAIN}")"
                echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
            else
                echo -e "$(localized_text "${RED}❌ 清除后 Caddy 校验失败，正在回滚...${PLAIN}" "${RED}❌ After clearing Caddy Verification failed, rolling back...${PLAIN}" "${RED}❌ После очистки Caddy проверка не удалась, откат...${PLAIN}")"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        0|q|Q|"")
            echo -e "$(localized_text "${BLUE}已取消。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 无效操作。${PLAIN}" "${RED}❌ Invalid operation.${PLAIN}" "${RED}❌ Недопустимая операция.${PLAIN}")"
            ;;
    esac

    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 清理域名证书、配置与端口占用
# ---------------------------------------------------------
sync_sni_stack_state_after_caddy_domain_delete() {
    local domain="$1"
    local env_file="/etc/vps-optimize/sni-stack.env"
    local i removed=0
    local -a new_domains=()
    local -a new_addrs=()
    local -a new_ports=()

    [[ -f "$env_file" ]] || return 0
    load_sni_stack_env >/dev/null 2>&1 || return 0

    if [[ "$domain" == "${PANEL_DOMAIN:-}" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${domain} 是当前 443 单入口面板域名，保存状态仍会引用它；重新应用前必须重新签发证书或更换面板域名。${PLAIN}" "${YELLOW}⚠️ ${domain} is the current 443 shared entry panel domain, and the saved state will still refer to it; the certificate must be re-issued or the panel domain must be changed before re-applying.${PLAIN}" "${YELLOW}⚠️ ${domain} — это текущее доменное имя панели с единым вводом 443, и сохраненное состояние по-прежнему будет ссылаться на него; сертификат необходимо перевыпустить или изменить доменное имя панели перед повторной подачей заявки.${PLAIN}")"
        return 0
    fi

    for i in "${!SITE_DOMAINS[@]}"; do
        if [[ "$domain" == "${SITE_DOMAINS[$i]}" ]]; then
            removed=1
            continue
        fi
        new_domains+=("${SITE_DOMAINS[$i]}")
        new_addrs+=("${SITE_BACKEND_ADDRS[$i]}")
        new_ports+=("${SITE_BACKEND_PORTS[$i]}")
    done

    [[ "$removed" -eq 1 ]] || return 0
    SITE_DOMAINS=("${new_domains[@]}")
    SITE_BACKEND_ADDRS=("${new_addrs[@]}")
    SITE_BACKEND_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$domain"
    save_sni_stack_env
    echo -e "$(localized_text "${GREEN}✅ 已同步移除 443 单入口保存状态中的 Web 域名：${domain}${PLAIN}" "${GREEN}✅ The web domain in the saved status of 443 shared entries has been removed simultaneously: ${domain}${PLAIN}" "${GREEN}. Имя веб-домена в сохраненном состоянии 443 с общей точкой входа было одновременно удалено: ${domain}.${PLAIN}")"
}

func_caddy_delete_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}清理域名证书与配置${PLAIN}" "${BOLD}Clean up domain certificate and configuration${PLAIN}" "${BOLD}Очистка сертификата и конфигурации доменного имени${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}将隔离指定域名的证书和配置，并清理 acme.sh 残留。${PLAIN}" "${YELLOW}Will isolate the certificate and configuration of the specified domain and clean up the residue of acme.sh.${PLAIN}" "${YELLOW}изолирует сертификат и конфигурацию указанного доменного имени и очистит остатки acme.sh.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    local domain domain_input
    read_trimmed domain_input "$(localized_text "👉 请输入要清理的域名（例如 panel.site.com）: " "👉 Please enter the domain to be cleaned (for example panel.site.com):" "👉 Введите имя домена, который необходимо очистить (например, Panel.site.com):")"
    domain=$(normalize_domain_input "$domain_input")
    if [[ -z "$domain" ]]; then
        echo -e "$(localized_text "${RED}❌ 域名不能为空！${PLAIN}" "${RED}❌ The domain cannot be empty!${PLAIN}" "${RED}❌ Доменное имя не может быть пустым!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        echo -e "$(localized_text "${RED}❌ 已取消清理。${PLAIN}" "${RED}❌ Cleanup canceled.${PLAIN}" "${RED}❌ Очистка отменена.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "\n${CYAN}▶ 正在清理域名证书与配置...${PLAIN}" "\n${CYAN}▶ Cleaning up domain certificate and configuration...${PLAIN}" "\n${CYAN}▶ Очистка сертификата и конфигурации доменного имени...${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}此操作会移走该域名的证书与配置，相关网站会暂时不可用。${PLAIN}" "${YELLOW}This operation will remove the certificate and configuration of the domain, and the related website will be temporarily unavailable.${PLAIN}" "${YELLOW}Эта операция приведет к удалению сертификата и конфигурации доменного имени, а соответствующий веб-сайт будет временно недоступен.${PLAIN}")"
    echo -e "$(localized_text "请确认操作...${PLAIN}" "Please confirm the operation...${PLAIN}" "Пожалуйста, подтвердите операцию...${PLAIN}")"
    if confirm_danger "$(localized_text "清理 ${domain} 的证书与配置" "Clean up the certificate and configuration of ${domain}" "Очистите сертификат и конфигурацию ${domain}.")" "$(localized_text "会停止 Caddy，隔离该域名的 Caddy/Nginx 配置、共享证书文件和 acme.sh 残留，再启动/重载相关服务。" "Caddy will be stopped, the Caddy/Nginx configuration, shared certificate file and acme.sh residue of the domain will be isolated, and then related services will be started/reloaded." "Caddy будет остановлен, конфигурация Caddy/Nginx, файл общего сертификата и остаток acme.sh доменного имени будут изолированы, а затем соответствующие службы будут запущены/перезагружены.")" "$(localized_text "请先确认已有系统快照或反代配置备份；清理后的证书需要重新签发。" "Please first confirm that you have a system snapshot or reverse configuration backup; the cleaned certificate needs to be re-issued." "Сначала подтвердите, что у вас есть снимок системы или резервная копия обратной конфигурации; очищенный сертификат необходимо перевыпустить.")"; then
        # 1. 停止 Caddy，强制释放 80/443 端口
        systemctl stop caddy >/dev/null 2>&1
        echo -e "$(localized_text "${GREEN}✅ [1/4] 已强制停止 Caddy 服务，释放网络端口。${PLAIN}" "${GREEN}✅ [1/4] The Caddy service has been forcibly stopped and the network port has been released.${PLAIN}" "${GREEN}✅ [1/4] Служба Caddy была принудительно остановлена, а сетевой порт освобожден.${PLAIN}")"
        
        # 2. 深度清理 Caddy 底层证书缓存
        local caddy_paths=("/var/lib/caddy/.local/share/caddy/certificates" "/root/.local/share/caddy/certificates")
        local caddy_found=false
        for cp in "${caddy_paths[@]}"; do
            if [[ -d "$cp" ]]; then
                local target=$(find "$cp" -type d -name "${domain}" -print -quit 2>/dev/null)
                if [[ -n "$target" ]]; then
                    quarantine_path "$target" "/root/vps-optimize-quarantine/caddy-certs" >/dev/null 2>&1 || true
                    caddy_found=true
                fi
            fi
        done
        if $caddy_found; then
            echo -e "$(localized_text "${GREEN}✅ [2/4] Caddy 引擎中关于 ${domain} 的密钥与证书已抹除。${PLAIN}" "${GREEN}✅ [2/4] The key and certificate related to ${domain} in the Caddy engine have been erased.${PLAIN}" "${GREEN}✅ [2/4] Ключ и сертификат, относящиеся к ${domain} в движке Caddy, были стерты.${PLAIN}")"
        else
            echo -e "$(localized_text "${BLUE}ℹ️ [2/4] 未在 Caddy 引擎中发现该域名的证书。${PLAIN}" "${BLUE}ℹ️ [2/4] The certificate for this domain was not found in the Caddy engine.${PLAIN}" "${BLUE}ℹ️ [2/4] Сертификат для этого доменного имени не найден в движке Caddy.${PLAIN}")"
        fi
        
        # 3. 清理 acme.sh 残留
        if [[ -d "/root/.acme.sh" ]]; then
            local acme_target=$(find "/root/.acme.sh" -type d -name "*${domain}*" -print -quit 2>/dev/null)
            if [[ -n "$acme_target" ]]; then
                quarantine_path "$acme_target" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ [3/4] 面板底层 (~/.acme.sh) 关于 ${domain} 的残留已抹除。${PLAIN}" "${GREEN}✅ [3/4] The remnants of ${domain} on the bottom layer of the panel (~/.acme.sh) have been erased.${PLAIN}" "${GREEN}✅ [3/4] Остатки ${domain} на нижнем слое панели (~/.acme.sh) стерты.${PLAIN}")"
            else
                echo -e "$(localized_text "${BLUE}ℹ️ [3/4] 未在 acme.sh 引擎中发现残留。${PLAIN}" "${BLUE}ℹ️ [3/4] No residue found in acme.sh engine.${PLAIN}" "${BLUE}ℹ️ [3/4] В двигателе acme.sh остатков не обнаружено.${PLAIN}")"
            fi
        else
            echo -e "$(localized_text "${BLUE}ℹ️ [3/4] 系统未安装独立 acme.sh 环境，已跳过。${PLAIN}" "${BLUE}ℹ️ [3/4] The independent acme.sh environment is not installed on the system and has been skipped.${PLAIN}" "${BLUE}ℹ️ [3/4] Независимая среда acme.sh не установлена в системе и пропущена.${PLAIN}")"
        fi
        
        # 4. 外科手术：模块化安全删除 Caddy/Nginx 域名配置
        local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$domain_conf" ]]; then
            echo -e "$(localized_text "${YELLOW}⏳ [4/5] 检测到 Caddy 专属配置文件，正在隔离...${PLAIN}" "${YELLOW}⏳ [4/5] Detected Caddy exclusive configuration file, isolating...${PLAIN}" "${YELLOW}⏳ [4/5] Обнаружен эксклюзивный файл конфигурации Caddy, изолирующий...${PLAIN}")"
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ [4/5] Caddy 专属配置文件 ($domain_conf) 已隔离！${PLAIN}" "${GREEN}✅ [4/5] Caddy exclusive profile ($domain_conf) has been quarantined!${PLAIN}" "${GREEN}✅ [4/5] Эксклюзивный профиль Caddy ($domain_conf) помещен на карантин!${PLAIN}")"
        else
            echo -e "$(localized_text "${GREEN}✅ [4/5] 未发现该域名的 Caddy 专属配置文件。${PLAIN}" "${GREEN}✅ [4/5] No Caddy exclusive configuration file was found for this domain.${PLAIN}" "${GREEN}✅ [4/5] Для этого доменного имени не найден эксклюзивный файл конфигурации Caddy.${PLAIN}")"
        fi
        local nginx_domain_conf
        nginx_domain_conf=$(nginx_proxy_conf_path "$domain" 2>/dev/null || echo "/etc/nginx/conf.d/vps_proxy_${domain}.conf")
        if [[ -f "$nginx_domain_conf" ]]; then
            quarantine_path "$nginx_domain_conf" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ 已隔离 Nginx 反代配置：${nginx_domain_conf}${PLAIN}" "${GREEN}✅ Isolated Nginx Reverse configuration: ${nginx_domain_conf}${PLAIN}" "${GREEN}✅ Изолированный Nginx Обратная конфигурация: ${nginx_domain_conf}${PLAIN}")"
        fi

        # 5. 隔离共享证书安装路径，Nginx 反代也复用这些证书。
        local shared_cert_file
        echo -e "$(localized_text "${YELLOW}⏳ [5/5] 正在隔离共享证书安装路径...${PLAIN}" "${YELLOW}⏳ [5/5] Isolating the shared certificate installation path...${PLAIN}" "${YELLOW}⏳ [5/5] Изолирование пути установки общего сертификата...${PLAIN}")"
        for shared_cert_file in "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.crt" "/root/cert/${domain}.key"; do
            if [[ -e "$shared_cert_file" || -L "$shared_cert_file" ]]; then
                quarantine_path "$shared_cert_file" "/etc/vps-optimize/quarantine/shared-certs" >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ 已隔离共享证书路径：${shared_cert_file}${PLAIN}" "${GREEN}✅ Isolated shared certificate path: ${shared_cert_file}${PLAIN}" "${GREEN}✅ Путь к изолированному общему сертификату: ${shared_cert_file}${PLAIN}")"
            fi
        done

        # 重启 Caddy 以加载干净的配置
        systemctl start caddy >/dev/null 2>&1
        if command -v nginx >/dev/null 2>&1; then
            nginx -t >/dev/null 2>&1 && { systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true; }
        fi
        sync_sni_stack_state_after_caddy_domain_delete "$domain" || true
        generate_caddy_cf_manifest 2>/dev/null || true

        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}✅ 清理完成；相关配置和证书已移入隔离目录。${PLAIN}" "${GREEN}✅ Cleanup completed; related configurations and certificates have been moved to the isolation directory.${PLAIN}" "${GREEN}✅ Очистка завершена; связанные конфигурации и сертификаты были перемещены в каталог изоляции.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}操作已取消。${PLAIN}" "${BLUE}Operation has been cancelled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

# ---------------------------------------------------------
# 新增功能：独立追加 Caddy 跳过不安全证书反代块 (模块化版)
# ---------------------------------------------------------
func_caddy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🛡️ 独立配置：追加 Caddy 跳过证书验证反代${PLAIN}" "${BOLD}🛡️ Independent configuration: append Caddy to skip certificate verification and replace with${PLAIN}" "${BOLD}🛡️ Независимая конфигурация: добавьте Caddy, чтобы пропустить проверку сертификата, и замените на.${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 Caddy 配置文件，请先运行 [13] 安装 Caddy！${PLAIN}" "${RED}❌ The Caddy configuration file is not detected, please run [13] to install Caddy first!${PLAIN}" "${RED}❌ Файл конфигурации Caddy не обнаружен, пожалуйста, запустите [13], чтобы сначала установить Caddy!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    
    local domain domain_input
    local backend_addr port
    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed domain_input "$(localized_text "👉 请输入解析后的域名 (如 panel.site.com): " "👉 Please enter the resolved domain (such as panel.site.com):" "👉 Введите разрешенное доменное имя (например, Panel.site.com):")"
    read_trimmed port "$(localized_text "👉 请输入面板 HTTPS 本地映射端口 (如 40000): " "👉 Please enter the panel HTTPS local mapping port (such as 40000):" "👉 Введите локальный порт сопоставления панели HTTPS (например, 40000):")"
    backend_addr=$(ask_with_default "$(localized_text "后端地址" "Backend address" "Внутренний адрес")" "127.0.0.1")
    backend_addr=$(normalize_backend_addr_input "$backend_addr")
    if ! is_valid_backend_addr "$backend_addr"; then
        echo -e "$(localized_text "${RED}❌ 后端地址无效：${backend_addr}${PLAIN}" "${RED}❌ Invalid backend address: ${backend_addr}${PLAIN}" "${RED}❌ Неверный внутренний адрес: ${backend_addr}.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi
    domain=$(normalize_domain_input "$domain_input")
    
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi
    if ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。已取消操作。${PLAIN}" "${RED}❌ Port format error: ${port}, the port must be 1-65535. Operation canceled.${PLAIN}" "${RED}❌ Ошибка формата порта: ${port}, порт должен быть 1-65535. Операция отменена.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi

    read_trimmed enable_ip_whitelist "$(localized_text "❓ 是否只允许指定 IP/CIDR 访问该域名？(Y/n，默认 y): " "❓ Are only the specified IP/CIDR allowed to access the domain? (Y/n, default y):" "❓ Разрешен ли только указанный IP/CIDR доступ к доменному имени? (Да/нет, по умолчанию y):")"
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
        read_trimmed ip_whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format, and the operation has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат, и операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
            return
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi
    
    # 确保主文件包含模块化目录
    grep -q "import conf.d/\*" /etc/caddy/Caddyfile || echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    
    mkdir -p /etc/caddy/conf.d
    local conf_file="/etc/caddy/conf.d/${domain}.caddy"
    local backup_file=""
    if [[ -f "$conf_file" ]]; then
        backup_file="${conf_file}.bak_$(date +%s)"
        if ! cp -p "$conf_file" "$backup_file"; then
            echo -e "$(localized_text "${RED}❌ 现有配置备份失败，已取消操作。${PLAIN}" "${RED}❌ The existing configuration backup failed and the operation has been cancelled.${PLAIN}" "${RED}❌ Не удалось выполнить резервное копирование существующей конфигурации, и операция была отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
            return
        fi
    fi
    
    write_caddy_reverse_proxy_conf "$domain" "$backend_addr" "$port" "y" "$conf_file" "$ip_whitelist_ranges"
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl reload caddy >/dev/null 2>&1
        echo -e "$(localized_text "${GREEN}✅ 独立跳过验证配置已成功建立并生效！${PLAIN}" "${GREEN}✅ The independent skip verification configuration has been successfully established and takes effect!${PLAIN}" "${GREEN}✅ Конфигурация независимой проверки пропуска успешно установлена и вступила в силу!${PLAIN}")"
        [[ -n "$ip_whitelist_ranges" ]] && echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 新配置语法错误，正在回滚...${PLAIN}" "${RED}❌ New configuration syntax error, rolling back...${PLAIN}" "${RED}❌ Синтаксическая ошибка новой конфигурации, откат...${PLAIN}")"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
        [[ -n "$backup_file" && -f "$backup_file" ]] && mv "$backup_file" "$conf_file"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 4. SSH 安全加固 (终极完美版：防截断、防覆盖、防 Socket 冲突)
# ---------------------------------------------------------
