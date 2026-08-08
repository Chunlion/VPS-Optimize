# shellcheck shell=bash
# Cloudflare/Caddy certificate health checks and auto-fix workflows.

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
