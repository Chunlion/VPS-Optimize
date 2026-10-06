# shellcheck shell=bash
# Rollback and quarantine helpers.

quarantine_path() {
    local target="$1"
    local quarantine_root="${2:-/root/vps-optimize-quarantine}"
    local resolved base dest

    if [[ -z "$target" || "$target" == *"*"* || "$target" == *"?"* ]]; then
        echo -e "$(localized_text "${RED}❌ 拒绝隔离空路径或通配符路径：${target}${PLAIN}" "${RED}❌ Deny quarantine of empty or wildcard paths: ${target}${PLAIN}" "${RED}❌ Запретить карантин пустых путей или путей с подстановочными знаками: ${target}.${PLAIN}")"
        return 1
    fi

    [[ -e "$target" || -L "$target" ]] || return 0

    resolved=$(readlink -f -- "$target" 2>/dev/null || realpath -m -- "$target" 2>/dev/null || printf '%s' "$target")
    case "$resolved" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
            echo -e "$(localized_text "${RED}❌ 拒绝隔离系统根级目录：${resolved}${PLAIN}" "${RED}❌ Refuse to isolate the system root directory: ${resolved}${PLAIN}" "${RED}❌ Отказаться от изоляции корневого каталога системы: ${resolved}${PLAIN}")"
            return 1
            ;;
    esac

    mkdir -p "$quarantine_root" || return 1
    chmod 700 "$quarantine_root" 2>/dev/null || true
    base=$(basename "$resolved")
    dest="${quarantine_root%/}/$(date +%Y%m%d_%H%M%S)_${base}"
    while [[ -e "$dest" ]]; do
        dest="${dest}_$RANDOM"
    done

    mv -- "$target" "$dest" || return 1
    echo -e "$(localized_text "${YELLOW}已隔离：${resolved} -> ${dest}${PLAIN}" "${YELLOW}Has been isolated: ${resolved} -> ${dest}${PLAIN}" "${YELLOW}изолирован: ${resolved} -> ${dest}${PLAIN}")"
}

restore_sni_stack_backup_files() {
    local backup_dir="$1"
    local domain conf_file snapshot
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || return 1

    mkdir -p /etc/nginx/stream.d /etc/nginx/conf.d /etc/caddy/conf.d /etc/vps-optimize /etc/systemd/system /usr/local/bin || return 1
    while IFS='|' read -r conf_file snapshot; do
        if [[ -e "$backup_dir/$snapshot" || -L "$backup_dir/$snapshot" ]]; then
            mkdir -p "$(dirname "$conf_file")" || return 1
            cp -a "$backup_dir/$snapshot" "$conf_file" || return 1
        elif [[ -f "$backup_dir/absent-files" ]] && grep -Fxq "$conf_file" "$backup_dir/absent-files"; then
            quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/sni-stack" >/dev/null 2>&1 || return 1
        fi
    done <<'EOF'
/etc/nginx/nginx.conf|nginx.conf
/etc/caddy/Caddyfile|Caddyfile
/etc/nginx/conf.d/00-vps-proxy-map.conf|nginx_conf.d/00-vps-proxy-map.conf
/etc/nginx/sites-available/default|nginx_default_sites/available-default
/etc/nginx/sites-enabled/default|nginx_default_sites/enabled-default
/etc/nginx/conf.d/default.conf|nginx_default_sites/default.conf
/etc/nginx/conf.d/00-vps-default-drop.conf|nginx_default_sites/00-vps-default-drop.conf
/etc/vps-optimize/sni-stack.env|vps-optimize/sni-stack.env
/etc/vps-optimize/xray-sni-routes.conf|vps-optimize/xray-sni-routes.conf
/etc/vps-optimize/443-engine.conf|vps-optimize/443-engine.conf
/etc/vps-optimize/vpso-mux.yaml|vps-optimize/vpso-mux.yaml
/etc/systemd/system/vpso-mux.service|systemd/vpso-mux.service
/usr/local/bin/vpso-mux|usr-local-bin/vpso-mux
EOF

    while IFS= read -r conf_file; do
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-sni" >/dev/null 2>&1 || return 1
    done < <(find /etc/nginx/stream.d -maxdepth 1 -type f -name 'vps_sni_*.conf' 2>/dev/null | sort)
    for conf_file in "$backup_dir/nginx_stream.d/"*.conf; do
        [[ -e "$conf_file" || -L "$conf_file" ]] || continue
        cp -a "$conf_file" /etc/nginx/stream.d/ || return 1
    done

    while IFS= read -r conf_file; do
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-conf-d" >/dev/null 2>&1 || return 1
    done < <(find /etc/nginx/conf.d -maxdepth 1 \( -name 'vps_sni_web_*.conf' -o -name 'vps_proxy_*.conf' \) 2>/dev/null | sort)
    for conf_file in "$backup_dir/nginx_conf.d/"*.conf; do
        [[ -e "$conf_file" || -L "$conf_file" ]] || continue
        cp -a "$conf_file" /etc/nginx/conf.d/ || return 1
    done

    for domain in "$PANEL_DOMAIN" "${SITE_DOMAINS[@]}"; do
        [[ -n "$domain" ]] || continue
        conf_file="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -e "$conf_file" || -L "$conf_file" ]]; then
            quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-sni" >/dev/null 2>&1 || return 1
        fi
    done
    for conf_file in "$backup_dir/caddy_conf.d/"*.caddy; do
        [[ -e "$conf_file" || -L "$conf_file" ]] || continue
        cp -a "$conf_file" /etc/caddy/conf.d/ || return 1
    done
    return 0
}

rollback_sni_stack_after_failure() {
    local backup_dir="$1"
    local reason="$(localized_text "${2:-配置应用失败}" "${2:-配置应用失败}" "${2:-配置应用失败}")"
    echo -e "${RED}❌ ${reason}${PLAIN}"
    echo -e "$(localized_text "${YELLOW}▶ 正在从本次操作前备份回滚 Nginx/Caddy 配置...${PLAIN}" "${YELLOW}▶ Rolling back from the backup before this operation Nginx/Caddy configuration...${PLAIN}" "${YELLOW}▶ Откат из резервной копии перед этой операцией. Конфигурация Nginx/Caddy...${PLAIN}")"
    if restore_sni_stack_backup_files "$backup_dir"; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        if ! restore_sni_stack_web_services "$backup_dir"; then
            echo -e "$(localized_text "${RED}❌ 回滚文件已恢复，但 Web 配置校验或服务恢复失败，请检查备份：${backup_dir}${PLAIN}" "${RED}❌ Backup files restored, but Web validation or service recovery failed. Check: ${backup_dir}${PLAIN}" "${RED}❌ Файлы восстановлены, но проверка Web или восстановление служб завершились ошибкой. Проверьте: ${backup_dir}${PLAIN}")"
            return 1
        fi
        echo -e "$(localized_text "${YELLOW}已回滚到：${backup_dir}${PLAIN}" "${YELLOW}Has been rolled back to: ${backup_dir}${PLAIN}" "${YELLOW}откатился до: ${backup_dir}.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 自动回滚失败，请手动使用备份目录恢复：${backup_dir}${PLAIN}" "${RED}❌ Automatic rollback failed, please manually use the backup directory to restore: ${backup_dir}${PLAIN}" "${RED}❌ Не удалось выполнить автоматический откат. Для восстановления вручную используйте каталог резервной копии: ${backup_dir}.${PLAIN}")"
    fi
    return 1
}

rollback_sni_stack_config() {
    local backup_dir
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        backup_dir=$(find /etc/vps-optimize/backups -maxdepth 1 -type d -name 'sni-stack_*' 2>/dev/null | sort | tail -n1)
    fi
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到可回滚的 SNI stack 备份。${PLAIN}" "${RED}❌ No rollbackable SNI stack backup found.${PLAIN}" "${RED}❌ Не найдена резервная копия стека SNI, допускающая откат.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${YELLOW}即将回滚到备份：${backup_dir}${PLAIN}" "${YELLOW}Is about to be rolled back to backup: ${backup_dir}${PLAIN}" "${YELLOW}собирается вернуться к резервной копии: ${backup_dir}${PLAIN}")"
    confirm_risk_action "$(localized_text "回滚覆盖 Nginx/Caddy 443 配置" "Rollback coverage Nginx/Caddy 443 configuration" "Покрытие отката конфигурации Nginx/Caddy 443")" \
        "$(localized_text "当前 Nginx/Caddy/443端口复用相关配置" "Current Nginx/Caddy/Port 443 Reuse related configuration" "Текущая конфигурация, связанная повторного использования порта 443 Nginx/Caddy/443")" \
        "$(localized_text "如回滚后仍异常，请用云厂商控制台或手动恢复备份目录" "If the exception persists after rollback, please use the cloud provider console or manually restore the backup directory." "Если исключение сохраняется после отката, воспользуйтесь консолью облачного провайдера или вручную восстановите каталог резервной копии.")" \
        "$(localized_text "回滚会覆盖当前配置，请确认已选中正确备份。" "Rolling back will overwrite the current configuration, please confirm that correct backup is selected." "При откате текущая конфигурация будет перезаписана. Убедитесь, что выбрана правильная резервная копия.")" || return 1

    restore_sni_stack_backup_files "$backup_dir" || { echo -e "$(localized_text "${RED}❌ 回滚文件恢复失败。${PLAIN}" "${RED}❌ Rollback file recovery failed.${PLAIN}" "${RED}❌ Не удалось выполнить откат восстановления файла.${PLAIN}")"; return 1; }

    systemctl daemon-reload >/dev/null 2>&1 || true
    if restore_sni_stack_web_services "$backup_dir"; then
        echo -e "$(localized_text "${GREEN}✅ 回滚完成。${PLAIN}" "${GREEN}✅ Rollback completed.${PLAIN}" "${GREEN}✅ Откат завершен.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 回滚文件已恢复，但配置校验失败，请手动检查备份：${backup_dir}${PLAIN}" "${RED}❌ The rollback file has been restored, but the configuration validation failed. Please check the backup manually: ${backup_dir}${PLAIN}" "${RED}❌ Файл отката восстановлен, но проверка конфигурации не удалась. Пожалуйста, проверьте резервную копию вручную: ${backup_dir}.${PLAIN}")"
        return 1
    fi
}

restore_sni_stack_web_services() {
    local backup_dir="${1:-}" svc failed=0
    for svc in nginx caddy; do
        if [[ -f "$backup_dir/web-services" ]]; then
            if grep -Fxq "$svc|enabled" "$backup_dir/web-services"; then
                systemctl enable "$svc" || failed=1
            elif grep -Fxq "$svc|disabled" "$backup_dir/web-services"; then
                systemctl disable "$svc" || failed=1
            fi
        fi
        if [[ -f "$backup_dir/web-services" ]] && grep -Fxq "$svc|inactive" "$backup_dir/web-services"; then
            if systemctl is-active --quiet "$svc" && ! systemctl stop "$svc"; then
                failed=1
            fi
        fi
    done
    [[ "$failed" == 0 ]] || return 1
    for svc in nginx caddy; do
        if [[ -f "$backup_dir/web-services" ]] && grep -Fxq "$svc|inactive" "$backup_dir/web-services"; then
            continue
        fi
        case "$svc" in
            nginx)
                [[ -f /etc/nginx/nginx.conf ]] || continue
                nginx -t || { failed=1; continue; }
                ;;
            caddy)
                [[ -f /etc/caddy/Caddyfile ]] || continue
                caddy validate --config /etc/caddy/Caddyfile || { failed=1; continue; }
                ;;
        esac
        if ! restart_service_if_available "$svc"; then
            failed=1
        fi
    done
    return "$failed"
}

restore_backup_file() {
    local snapshot="$1"
    local target="$2"

    [[ -f "$snapshot" || -L "$snapshot" ]] || return 0
    mkdir -p "$(dirname "$target")" || return 1
    cp -af -- "$snapshot" "$target"
}

restore_backup_dir() {
    local snapshot="$1"
    local target="$2"
    local quarantine_root="$3"

    [[ -d "$snapshot" ]] || return 0
    mkdir -p "$(dirname "$target")" || return 1
    if [[ -e "$target" || -L "$target" ]]; then
        quarantine_path "$target" "$quarantine_root" >/dev/null 2>&1 || return 1
    fi
    cp -a -- "$snapshot" "$target"
}

dns_restore_latest_backup() {
    local backup_dir
    backup_dir=$(cat "${DNS_OPTIMIZE_BACKUP_DIR}/last" 2>/dev/null || true)
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到最近一次 DNS 备份。${PLAIN}" "${YELLOW}⚠️ The most recent DNS backup was not found.${PLAIN}" "${YELLOW}⚠️ Самая последняя резервная копия DNS не найдена.${PLAIN}")"
        return 1
    fi

    confirm_risk_action "$(localized_text "恢复最近一次 DNS 备份" "Restore the most recent DNS backup" "Восстановите самую последнюю резервную копию DNS.")" \
        "$(localized_text "/etc/resolv.conf 和 VPS-Optimize 写入的 systemd-resolved DNS 配置" "systemd-resolved DNS configuration written by /etc/resolv.conf and VPS-Optimize" "Конфигурация DNS с разрешением systemd, написанная /etc/resolv.conf и VPS-Optimize")" \
        "$(localized_text "重新进入 DNS 优化菜单选择国内/国外/自定义 DNS" "Re-enter DNS optimization menu and select domestic/foreign/customized DNS" "Снова войдите в меню оптимизации DNS и выберите отечественный/иностранный/индивидуальный DNS.")" \
        "$(localized_text "恢复后如果解析异常，请重新选择一个 DNS 配置。" "If the parsing is abnormal after recovery, please select a DNS configuration again." "Если после восстановления анализ происходит ненормально, выберите конфигурацию DNS еще раз.")" || return 1

    if [[ -e "$backup_dir/resolv.conf" || -L "$backup_dir/resolv.conf" ]]; then
        [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]] && quarantine_path /etc/resolv.conf "/etc/vps-optimize/quarantine/dns" >/dev/null 2>&1 || true
        cp -a "$backup_dir/resolv.conf" /etc/resolv.conf
    fi

    if [[ -f "$DNS_OPTIMIZE_RESOLVED_DROPIN" ]]; then
        quarantine_path "$DNS_OPTIMIZE_RESOLVED_DROPIN" "/etc/vps-optimize/quarantine/dns" >/dev/null 2>&1 || true
    fi
    if [[ -f "$backup_dir/99-vps-optimize-dns.conf" ]]; then
        mkdir -p /etc/systemd/resolved.conf.d
        cp -a "$backup_dir/99-vps-optimize-dns.conf" "$DNS_OPTIMIZE_RESOLVED_DROPIN"
    fi

    systemctl restart systemd-resolved >/dev/null 2>&1 || true
    echo -e "$(localized_text "${GREEN}✅ 已恢复 DNS 备份：${backup_dir}${PLAIN}" "${GREEN}✅ Restored DNS Backup: ${backup_dir}${PLAIN}" "${GREEN}✅ Восстановлена резервная копия DNS: ${backup_dir}${PLAIN}")"
}
