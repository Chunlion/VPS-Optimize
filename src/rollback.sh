# shellcheck shell=bash
# Rollback and quarantine helpers.

quarantine_path() {
    local target="$1"
    local quarantine_root="${2:-/root/vps-optimize-quarantine}"
    local resolved base dest

    if [[ -z "$target" || "$target" == *"*"* || "$target" == *"?"* ]]; then
        echo -e "${RED}❌ 拒绝隔离空路径或通配符路径：${target}${PLAIN}"
        return 1
    fi

    [[ -e "$target" || -L "$target" ]] || return 0

    resolved=$(readlink -f -- "$target" 2>/dev/null || realpath -m -- "$target" 2>/dev/null || printf '%s' "$target")
    case "$resolved" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
            echo -e "${RED}❌ 拒绝隔离系统根级目录：${resolved}${PLAIN}"
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

    mv -- "$target" "$dest"
    echo -e "${YELLOW}已隔离：${resolved} -> ${dest}${PLAIN}"
}

restore_sni_stack_backup_files() {
    local backup_dir="$1"
    local domain conf_file
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || return 1

    mkdir -p /etc/nginx/stream.d /etc/nginx/conf.d /etc/caddy/conf.d /etc/vps-optimize /etc/systemd/system /usr/local/bin
    [[ -f "$backup_dir/nginx.conf" ]] && cp -a "$backup_dir/nginx.conf" /etc/nginx/nginx.conf
    [[ -f "$backup_dir/Caddyfile" ]] && cp -a "$backup_dir/Caddyfile" /etc/caddy/Caddyfile
    [[ -f "$backup_dir/vps-optimize/sni-stack.env" ]] && cp -a "$backup_dir/vps-optimize/sni-stack.env" /etc/vps-optimize/sni-stack.env
    [[ -f "$backup_dir/vps-optimize/xray-sni-routes.conf" ]] && cp -a "$backup_dir/vps-optimize/xray-sni-routes.conf" /etc/vps-optimize/xray-sni-routes.conf
    [[ -f "$backup_dir/vps-optimize/443-engine.conf" ]] && cp -a "$backup_dir/vps-optimize/443-engine.conf" /etc/vps-optimize/443-engine.conf
    [[ -f "$backup_dir/vps-optimize/vpso-mux.yaml" ]] && cp -a "$backup_dir/vps-optimize/vpso-mux.yaml" /etc/vps-optimize/vpso-mux.yaml
    [[ -f "$backup_dir/systemd/vpso-mux.service" ]] && cp -a "$backup_dir/systemd/vpso-mux.service" /etc/systemd/system/vpso-mux.service
    [[ -f "$backup_dir/usr-local-bin/vpso-mux" ]] && cp -a "$backup_dir/usr-local-bin/vpso-mux" /usr/local/bin/vpso-mux

    while IFS= read -r conf_file; do
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-sni" >/dev/null 2>&1 || true
    done < <(find /etc/nginx/stream.d -maxdepth 1 -type f -name 'vps_sni_*.conf' 2>/dev/null | sort)
    cp -a "$backup_dir/nginx_stream.d/"*.conf /etc/nginx/stream.d/ 2>/dev/null || true

    while IFS= read -r conf_file; do
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-conf-d" >/dev/null 2>&1 || true
    done < <(find /etc/nginx/conf.d -maxdepth 1 \( -name 'vps_sni_web_*.conf' -o -name 'vps_proxy_*.conf' \) 2>/dev/null | sort)
    cp -a "$backup_dir/nginx_conf.d/"*.conf /etc/nginx/conf.d/ 2>/dev/null || true

    for domain in "$PANEL_DOMAIN" "${SITE_DOMAINS[@]}"; do
        [[ -n "$domain" ]] || continue
        conf_file="/etc/caddy/conf.d/${domain}.caddy"
        [[ -e "$conf_file" ]] && quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-sni" >/dev/null 2>&1 || true
    done
    cp -a "$backup_dir/caddy_conf.d/"*.caddy /etc/caddy/conf.d/ 2>/dev/null || true
}

rollback_sni_stack_after_failure() {
    local backup_dir="$1"
    local reason="${2:-配置应用失败}"
    echo -e "${RED}❌ ${reason}${PLAIN}"
    echo -e "${YELLOW}▶ 正在从本次操作前备份回滚 Nginx/Caddy 配置...${PLAIN}"
    if restore_sni_stack_backup_files "$backup_dir"; then
        nginx -t >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ Nginx 回滚后语法检查仍未通过，请手动检查 /etc/nginx/nginx.conf。${PLAIN}"
        caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ Caddy 回滚后配置检查仍未通过，请手动检查 /etc/caddy/Caddyfile。${PLAIN}"
        restart_service_if_available nginx >/dev/null 2>&1 || true
        restart_service_if_available caddy >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        echo -e "${YELLOW}已回滚到：${backup_dir}${PLAIN}"
    else
        echo -e "${RED}❌ 自动回滚失败，请手动使用备份目录恢复：${backup_dir}${PLAIN}"
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
        echo -e "${RED}❌ 未找到可回滚的 SNI stack 备份。${PLAIN}"
        return 1
    fi
    echo -e "${YELLOW}即将回滚到备份：${backup_dir}${PLAIN}"
    confirm_risk_action "回滚覆盖 Nginx/Caddy 443 配置" \
        "当前 Nginx/Caddy/443 单入口相关配置" \
        "如回滚后仍异常，请用云厂商控制台或手动恢复备份目录" \
        "回滚会覆盖当前配置，请确认已选中正确备份。" || return 1

    restore_sni_stack_backup_files "$backup_dir" || { echo -e "${RED}❌ 回滚文件恢复失败。${PLAIN}"; return 1; }

    if nginx -t && caddy validate --config /etc/caddy/Caddyfile; then
        restart_service_if_available nginx >/dev/null 2>&1 || true
        restart_service_if_available caddy >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ 回滚完成。${PLAIN}"
    else
        echo -e "${RED}❌ 回滚文件已恢复，但配置校验失败，请手动检查备份：${backup_dir}${PLAIN}"
        return 1
    fi
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
        echo -e "${YELLOW}⚠️ 未找到最近一次 DNS 备份。${PLAIN}"
        return 1
    fi

    confirm_risk_action "恢复最近一次 DNS 备份" \
        "/etc/resolv.conf 和 VPS-Optimize 写入的 systemd-resolved DNS 配置" \
        "重新进入 DNS 优化菜单选择国内/国外/自定义 DNS" \
        "恢复后如果解析异常，请重新选择一个 DNS 配置。" || return 1

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
    echo -e "${GREEN}✅ 已恢复 DNS 备份：${backup_dir}${PLAIN}"
}
