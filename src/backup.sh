# shellcheck shell=bash
# Backup helpers and backup center entrypoint.

sni_stack_backup_dir() {
    echo "/etc/vps-optimize/backups/sni-stack_$(date +%Y%m%d_%H%M%S)"
}

create_sni_stack_backup() {
    local backup_dir
    backup_dir="${1:-$(sni_stack_backup_dir)}"
    mkdir -p "$backup_dir/nginx_stream.d" "$backup_dir/nginx_conf.d" "$backup_dir/caddy_conf.d" "$backup_dir/vps-optimize" "$backup_dir/systemd" "$backup_dir/usr-local-bin" "$backup_dir/x-ui"
    [[ -f /etc/nginx/nginx.conf ]] && cp -a /etc/nginx/nginx.conf "$backup_dir/nginx.conf" 2>/dev/null || true
    [[ -d /etc/nginx/stream.d ]] && cp -a /etc/nginx/stream.d/vps_sni_*.conf "$backup_dir/nginx_stream.d/" 2>/dev/null || true
    [[ -d /etc/nginx/conf.d ]] && cp -a /etc/nginx/conf.d/vps_sni_web_*.conf "$backup_dir/nginx_conf.d/" 2>/dev/null || true
    [[ -d /etc/nginx/conf.d ]] && cp -a /etc/nginx/conf.d/vps_proxy_*.conf "$backup_dir/nginx_conf.d/" 2>/dev/null || true
    [[ -f /etc/nginx/conf.d/00-vps-proxy-map.conf ]] && cp -a /etc/nginx/conf.d/00-vps-proxy-map.conf "$backup_dir/nginx_conf.d/" 2>/dev/null || true
    [[ -f /etc/caddy/Caddyfile ]] && cp -a /etc/caddy/Caddyfile "$backup_dir/Caddyfile" 2>/dev/null || true
    [[ -d /etc/caddy/conf.d ]] && cp -a /etc/caddy/conf.d/*.caddy "$backup_dir/caddy_conf.d/" 2>/dev/null || true
    [[ -f /etc/vps-optimize/sni-stack.env ]] && cp -a /etc/vps-optimize/sni-stack.env "$backup_dir/vps-optimize/sni-stack.env" 2>/dev/null || true
    [[ -f /etc/vps-optimize/xray-sni-routes.conf ]] && cp -a /etc/vps-optimize/xray-sni-routes.conf "$backup_dir/vps-optimize/xray-sni-routes.conf" 2>/dev/null || true
    [[ -f /etc/vps-optimize/443-engine.conf ]] && cp -a /etc/vps-optimize/443-engine.conf "$backup_dir/vps-optimize/443-engine.conf" 2>/dev/null || true
    [[ -f /etc/vps-optimize/vpso-mux.yaml ]] && cp -a /etc/vps-optimize/vpso-mux.yaml "$backup_dir/vps-optimize/vpso-mux.yaml" 2>/dev/null || true
    [[ -f /etc/systemd/system/vpso-mux.service ]] && cp -a /etc/systemd/system/vpso-mux.service "$backup_dir/systemd/vpso-mux.service" 2>/dev/null || true
    [[ -f /usr/local/bin/vpso-mux ]] && cp -a /usr/local/bin/vpso-mux "$backup_dir/usr-local-bin/vpso-mux" 2>/dev/null || true
    [[ -d /etc/x-ui ]] && cp -a /etc/x-ui "$backup_dir/x-ui/etc-x-ui" 2>/dev/null || true
    [[ -f /usr/local/x-ui/bin/config.json ]] && cp -a /usr/local/x-ui/bin/config.json "$backup_dir/x-ui/config.json" 2>/dev/null || true
    echo "$backup_dir" > /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true
    echo -e "${GREEN}✅ 已创建配置备份：${backup_dir}${PLAIN}"
}

make_secure_temp_dir() {
    local prefix="$1"
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXX") || return 1
    chmod 700 "$tmp_dir" 2>/dev/null || true
    printf '%s' "$tmp_dir"
}

backup_copy_path() {
    local src="$1"
    local dest_rel="$2"
    local manifest_file="$3"
    local work_dir="$4"
    local dest_dir

    [[ -e "$src" || -L "$src" ]] || return 1
    dest_dir=$(dirname "$dest_rel")
    mkdir -p "$work_dir/$dest_dir" || return 1

    if cp -a -- "$src" "$work_dir/$dest_rel" 2>/dev/null; then
        echo " - $src" >> "$manifest_file"
        return 0
    fi
    return 1
}

backup_copy_xui_databases() {
    local manifest_file="$1"
    local work_dir="$2"
    local copied=1
    local db suffix src
    local db_paths=(
        "/etc/x-ui/x-ui.db"
        "/usr/local/x-ui/x-ui.db"
        "/usr/local/x-ui/bin/x-ui.db"
    )

    for db in "${db_paths[@]}"; do
        for suffix in "" "-wal" "-shm"; do
            src="${db}${suffix}"
            if backup_copy_path "$src" "${src#/}" "$manifest_file" "$work_dir"; then
                copied=0
            fi
        done
    done
    return "$copied"
}

redact_sensitive_output() {
    sed -E \
        -e 's/(authorization:[[:space:]]*(bearer|basic)[[:space:]]+)[^[:space:]]+/\1***REDACTED***/gI' \
        -e 's/((^|[^[:alnum:]_])(token|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|CF_Token|CF_Key)[[:space:]]*[=:][[:space:]]*)[^[:space:],;"'\''}]+/\1***REDACTED***/gI' \
        -e 's/("(token|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|CF_Token|CF_Key)"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/gI' \
        -e 's/([?&](token|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret)=)[^&[:space:]]+/\1***REDACTED***/gI' \
        -e 's#(https?://)[^/@[:space:]]+@#\1***REDACTED***@#g'
}

dns_backup_current_config() {
    local ts backup_dir
    ts=$(date +%Y%m%d_%H%M%S)
    backup_dir="${DNS_OPTIMIZE_BACKUP_DIR}/${ts}"
    mkdir -p "$backup_dir"
    chmod 700 "$DNS_OPTIMIZE_BACKUP_DIR" "$backup_dir" 2>/dev/null || true
    [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]] && cp -a /etc/resolv.conf "$backup_dir/resolv.conf" 2>/dev/null || true
    [[ -f "$DNS_OPTIMIZE_RESOLVED_DROPIN" ]] && cp -a "$DNS_OPTIMIZE_RESOLVED_DROPIN" "$backup_dir/99-vps-optimize-dns.conf" 2>/dev/null || true
    echo "$backup_dir" > "${DNS_OPTIMIZE_BACKUP_DIR}/last" 2>/dev/null || true
    echo "$backup_dir"
}

applied_config_editor_command() {
    local editor="${EDITOR:-}"
    if [[ -n "$editor" && "$editor" != *" "* ]] && command -v "$editor" >/dev/null 2>&1; then
        printf '%s' "$editor"
        return 0
    fi

    local candidate
    for candidate in nano vim vi; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

append_applied_config_file() {
    local label="$1"
    local path="$2"
    local kind="$3"
    local existing

    [[ -e "$path" || -L "$path" ]] || return 0
    for existing in "${applied_config_paths[@]}"; do
        [[ "$existing" == "$path" ]] && return 0
    done

    applied_config_labels+=("$label")
    applied_config_paths+=("$path")
    applied_config_kinds+=("$kind")
}

collect_applied_config_files() {
    local scope="${1:-all}"
    local conf_file

    applied_config_labels=()
    applied_config_paths=()
    applied_config_kinds=()

    append_applied_config_file "Caddy 主配置" "/etc/caddy/Caddyfile" "caddy"
    for conf_file in /etc/caddy/conf.d/*.caddy; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Caddy 站点 $(basename "$conf_file")" "$conf_file" "caddy"
    done
    append_applied_config_file "Nginx 主配置" "/etc/nginx/nginx.conf" "nginx"
    for conf_file in /etc/nginx/conf.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Nginx conf.d $(basename "$conf_file")" "$conf_file" "nginx"
    done
    for conf_file in /etc/nginx/sites-enabled/*; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Nginx sites-enabled $(basename "$conf_file")" "$conf_file" "nginx"
    done

    [[ "$scope" == "proxy" ]] && return 0

    for conf_file in /etc/nginx/stream.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Nginx stream.d $(basename "$conf_file")" "$conf_file" "nginx"
    done
    append_applied_config_file "443 共享参数" "/etc/vps-optimize/sni-stack.env" "entry-mode"
    append_applied_config_file "443 引擎状态" "/etc/vps-optimize/443-engine.conf" "entry-mode"
    append_applied_config_file "Xray SNI 分流记录" "/etc/vps-optimize/xray-sni-routes.conf" "xray-routes"
    append_applied_config_file "TCP Peek vpso-mux 配置" "/etc/vps-optimize/vpso-mux.yaml" "vpso-mux"
    append_applied_config_file "vpso-mux systemd" "/etc/systemd/system/vpso-mux.service" "systemd"
    append_applied_config_file "vpso-mux 8444 预检 systemd" "/etc/systemd/system/vpso-mux-preflight.service" "systemd"
    append_applied_config_file "Traffic Guard 配置" "$TRAFFIC_GUARD_CONFIG" "traffic-guard"
    append_applied_config_file "Traffic Guard service" "/etc/systemd/system/vps-traffic-guard.service" "systemd"
    append_applied_config_file "Traffic Guard timer" "/etc/systemd/system/vps-traffic-guard.timer" "systemd"
    append_applied_config_file "Cloudflare DNS API 配置" "/root/.config/vps-panel/cloudflare.env" "env"
    append_applied_config_file "Docker daemon.json" "/etc/docker/daemon.json" "docker-json"
    append_applied_config_file "SSH 主配置" "/etc/ssh/sshd_config" "ssh"
    for conf_file in /etc/ssh/sshd_config.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "SSH drop-in $(basename "$conf_file")" "$conf_file" "ssh"
    done
    append_applied_config_file "Hosts 文件" "/etc/hosts" "hosts"
    append_applied_config_file "Hostname 文件" "/etc/hostname" "hostname"
    append_applied_config_file "DNS resolv.conf" "/etc/resolv.conf" "dns"
    append_applied_config_file "systemd-resolved DNS drop-in" "$DNS_OPTIMIZE_RESOLVED_DROPIN" "dns"
    append_applied_config_file "Fail2ban jail.local" "/etc/fail2ban/jail.local" "fail2ban"
    append_applied_config_file "x-ui config.json" "/usr/local/x-ui/bin/config.json" "xui-json"
    for conf_file in /etc/sysctl.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "sysctl.d $(basename "$conf_file")" "$conf_file" "sysctl"
    done
    for conf_file in /opt/sublinkpro/docker-compose.yml /opt/miaomiaowu/docker-compose.yml /opt/sub-store/docker-compose.yml /opt/dockge/docker-compose.yml /opt/komari/docker-compose.yml /opt/*/compose.yaml /opt/*/compose.yml /opt/*/docker-compose.yml /opt/*/docker-compose.yaml; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Compose $(basename "$(dirname "$conf_file")")/$(basename "$conf_file")" "$conf_file" "compose"
    done
}

validate_xray_routes_file() {
    local target_file="$1"
    awk -F'|' '
        /^[[:space:]]*($|#)/ { next }
        { for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
        NF != 3 { exit 1 }
        $1 == "" || $2 == "" || $3 !~ /^[0-9]+$/ || $3 < 1 || $3 > 65535 { exit 1 }
    ' "$target_file"
}

validate_hosts_file() {
    local target_file="$1"
    awk '
        /^[[:space:]]*($|#)/ { next }
        NF < 2 { exit 1 }
    ' "$target_file"
}

validate_hostname_file() {
    local target_file="$1"
    local hostname_value
    hostname_value=$(head -n1 "$target_file" 2>/dev/null | tr -d '[:space:]')
    [[ -n "$hostname_value" && "$hostname_value" != *"/"* ]]
}

validate_json_file() {
    local target_file="$1"
    if command -v jq >/dev/null 2>&1; then
        jq empty "$target_file"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m json.tool "$target_file" >/dev/null
    else
        echo -e "${YELLOW}⚠️ 未检测到 jq/python3，已跳过 JSON 语法校验。${PLAIN}"
        return 0
    fi
}

validate_applied_config_kind() {
    local kind="$1"
    local target_file="$2"
    local project_dir

    case "$kind" in
        caddy)
            command -v caddy >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 caddy 命令，无法校验配置。${PLAIN}"; return 1; }
            caddy validate --config /etc/caddy/Caddyfile
            ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 nginx 命令，无法校验配置。${PLAIN}"; return 1; }
            nginx -t
            ;;
        systemd)
            if command -v systemd-analyze >/dev/null 2>&1; then
                systemd-analyze verify "$target_file"
            else
                echo -e "${YELLOW}⚠️ 未检测到 systemd-analyze，已跳过 systemd unit 静态校验。${PLAIN}"
            fi
            ;;
        docker-json|xui-json)
            validate_json_file "$target_file"
            ;;
        compose)
            if declare -F ensure_docker_compose_ready >/dev/null 2>&1; then
                ensure_docker_compose_ready || return 1
                project_dir=$(dirname "$target_file")
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$target_file" config >/dev/null)
            elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
                project_dir=$(dirname "$target_file")
                (cd "$project_dir" && docker compose -f "$target_file" config >/dev/null)
            elif command -v docker-compose >/dev/null 2>&1; then
                project_dir=$(dirname "$target_file")
                (cd "$project_dir" && docker-compose -f "$target_file" config >/dev/null)
            else
                echo -e "${YELLOW}⚠️ 未检测到 Docker Compose，已跳过 Compose 语法校验。${PLAIN}"
            fi
            ;;
        ssh)
            command -v sshd >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 sshd 命令，无法校验 SSH 配置。${PLAIN}"; return 1; }
            sshd -t
            ;;
        vpso-mux)
            if declare -F run_vpso_mux_config_check >/dev/null 2>&1; then
                run_vpso_mux_config_check "$target_file"
            elif [[ -x /usr/local/bin/vpso-mux ]]; then
                /usr/local/bin/vpso-mux -config "$target_file" -check
            else
                echo -e "${YELLOW}⚠️ 未检测到 vpso-mux 二进制，已跳过运行时配置校验。${PLAIN}"
            fi
            ;;
        entry-mode|traffic-guard|env)
            bash -n "$target_file"
            ;;
        xray-routes)
            validate_xray_routes_file "$target_file"
            ;;
        hosts)
            validate_hosts_file "$target_file"
            ;;
        hostname)
            validate_hostname_file "$target_file"
            ;;
        dns|sysctl)
            return 0
            ;;
        fail2ban)
            if command -v fail2ban-client >/dev/null 2>&1; then
                fail2ban-client -t
            else
                echo -e "${YELLOW}⚠️ 未检测到 fail2ban-client，已跳过 Fail2ban 配置校验。${PLAIN}"
            fi
            ;;
        *)
            echo -e "${YELLOW}⚠️ 未知配置类型 ${kind}，仅保存备份，不执行额外校验。${PLAIN}"
            ;;
    esac
}

restart_named_service_if_available() {
    local service_name="$1"
    local rc
    restart_service_if_available "$service_name"
    rc=$?
    [[ "$rc" -eq 0 || "$rc" -eq 2 ]]
}

reload_applied_config_kind() {
    local kind="$1"
    local target_file="$2"
    local confirm unit_name project_dir

    case "$kind" in
        caddy)
            systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1
            ;;
        nginx)
            systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1
            ;;
        systemd)
            systemctl daemon-reload >/dev/null 2>&1 || return 1
            unit_name=$(basename "$target_file")
            read_trimmed confirm "systemd 已 daemon-reload，是否现在重启/重新加载 ${unit_name}？(y/n，默认 n): "
            if is_yes "$confirm"; then
                systemctl try-reload-or-restart "$unit_name" >/dev/null 2>&1 || systemctl restart "$unit_name" >/dev/null 2>&1
            else
                echo -e "${BLUE}已保存 unit 修改，未重启 ${unit_name}。${PLAIN}"
            fi
            ;;
        docker-json)
            read_trimmed confirm "Docker daemon.json 已校验，是否现在重启 Docker 使其生效？(y/n，默认 n): "
            if is_yes "$confirm"; then
                restart_named_service_if_available docker
            else
                echo -e "${YELLOW}⚠️ Docker 未重启，daemon.json 修改尚未生效。${PLAIN}"
            fi
            ;;
        compose)
            read_trimmed confirm "Compose 配置已校验，是否现在执行 up -d 应用修改？(y/n，默认 n): "
            if is_yes "$confirm"; then
                if declare -F ensure_docker_compose_ready >/dev/null 2>&1; then
                    ensure_docker_compose_ready || return 1
                    project_dir=$(dirname "$target_file")
                    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$target_file" up -d)
                elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
                    project_dir=$(dirname "$target_file")
                    (cd "$project_dir" && docker compose -f "$target_file" up -d)
                elif command -v docker-compose >/dev/null 2>&1; then
                    project_dir=$(dirname "$target_file")
                    (cd "$project_dir" && docker-compose -f "$target_file" up -d)
                else
                    echo -e "${RED}❌ 未检测到 Docker Compose，无法应用修改。${PLAIN}"
                    return 1
                fi
            else
                echo -e "${YELLOW}⚠️ Compose 修改已保存，但容器尚未重建。${PLAIN}"
            fi
            ;;
        ssh)
            if confirm_risk_action "重启 SSH 服务" \
                "当前 SSH 服务运行状态" \
                "使用当前未断开的 SSH 会话恢复 ${target_file}.bak_*，或通过云厂商控制台恢复 SSH 配置" \
                "确认新 SSH 配置已经通过 sshd -t 校验。"; then
                restart_service_if_available sshd >/dev/null 2>&1 || restart_service_if_available ssh >/dev/null 2>&1
            else
                echo -e "${YELLOW}⚠️ SSH 未重启，修改可能尚未生效。${PLAIN}"
            fi
            ;;
        vpso-mux)
            if confirm_risk_action "重启 vpso-mux" \
                "TCP Peek/vpso-mux 分流器运行进程" \
                "使用当前未断开的 SSH 会话恢复 ${target_file}.bak_*，或回到 443 单入口菜单重新应用/回滚入口模式" \
                "确认公网 443 当前入口模式和本机后端端口都正常。"; then
                restart_named_service_if_available vpso-mux
            else
                echo -e "${YELLOW}⚠️ vpso-mux 未重启，修改尚未生效。${PLAIN}"
            fi
            ;;
        entry-mode|xray-routes)
            if declare -F reapply_current_entry_mode >/dev/null 2>&1; then
                if confirm_risk_action "重新应用当前 443 入口模式" \
                    "公网 443 入口配置、Caddy/Nginx/vpso-mux/Xray 相关路由" \
                    "脚本会创建入口模式备份并在失败时回滚；也可从备份与回滚中心恢复" \
                    "确认配置文件中的域名、端口和 ENTRY_MODE 值已经匹配。"; then
                    reapply_current_entry_mode
                else
                    echo -e "${YELLOW}⚠️ 已保存配置，但未重新应用 443 入口模式。${PLAIN}"
                fi
            else
                echo -e "${YELLOW}⚠️ 已保存配置；请回到 443 单入口菜单重新应用当前入口模式。${PLAIN}"
            fi
            ;;
        traffic-guard)
            if confirm_risk_action "重启 Traffic Guard timer" \
                "vps-traffic-guard.timer 和流量阈值检查周期" \
                "重新编辑 ${target_file} 或从 ${target_file}.bak_* 恢复；必要时停用 vps-traffic-guard.timer" \
                "如果 ACTION=poweroff，请确认阈值、账单周期和云厂商救援方式。"; then
                systemctl daemon-reload >/dev/null 2>&1 || true
                systemctl restart vps-traffic-guard.timer >/dev/null 2>&1
            else
                echo -e "${YELLOW}⚠️ Traffic Guard timer 未重启，下一次运行前请确认配置已生效。${PLAIN}"
            fi
            ;;
        hostname)
            local hostname_value
            hostname_value=$(head -n1 "$target_file" 2>/dev/null | tr -d '[:space:]')
            if [[ -n "$hostname_value" ]]; then
                hostnamectl set-hostname "$hostname_value" >/dev/null 2>&1 || hostname "$hostname_value" 2>/dev/null || true
            fi
            ;;
        dns)
            if confirm_risk_action "重启 systemd-resolved" \
                "系统 DNS 解析服务和 resolved drop-in 配置" \
                "恢复 ${target_file}.bak_*，或重新进入 DNS 更改优化菜单切换回原配置" \
                "确认当前 SSH 会话保持连接，必要时可用 IP 直连排障。"; then
                restart_named_service_if_available systemd-resolved
            else
                echo -e "${BLUE}DNS 配置已保存，未重启 systemd-resolved。${PLAIN}"
            fi
            ;;
        sysctl)
            if confirm_risk_action "应用 sysctl 配置" \
                "当前内核运行中的 sysctl 参数" \
                "恢复 ${target_file}.bak_* 后重新执行 sysctl --system，或手动回退异常参数" \
                "确认参数来源可信；错误网络参数可能影响远程连接。"; then
                sysctl --system >/dev/null
            else
                echo -e "${YELLOW}⚠️ sysctl 修改尚未应用到当前内核。${PLAIN}"
            fi
            ;;
        fail2ban)
            if confirm_risk_action "重启 fail2ban" \
                "Fail2ban 服务和登录防护规则" \
                "恢复 ${target_file}.bak_* 后重启 fail2ban，或临时停用异常 jail" \
                "确认当前 SSH 来源不会被新规则误封。"; then
                restart_named_service_if_available fail2ban
            else
                echo -e "${YELLOW}⚠️ Fail2ban 未重启，修改尚未生效。${PLAIN}"
            fi
            ;;
        xui-json)
            if confirm_risk_action "重启 x-ui/3x-ui" \
                "x-ui/3x-ui 面板进程和 config.json 运行配置" \
                "恢复 ${target_file}.bak_* 后重启面板，或用官方 x-ui/3x-ui 命令进入管理菜单修复" \
                "确认面板端口、证书路径和 443 单入口设置匹配。"; then
                restart_named_service_if_available x-ui
                restart_named_service_if_available 3x-ui
            else
                echo -e "${YELLOW}⚠️ x-ui/3x-ui 未重启，修改可能尚未生效。${PLAIN}"
            fi
            ;;
        env|hosts)
            echo -e "${BLUE}配置已保存；该文件通常由系统或脚本后续读取，无需立即 reload。${PLAIN}"
            ;;
        *)
            echo -e "${BLUE}配置已保存；未为 ${kind} 定义自动 reload。${PLAIN}"
            ;;
    esac
}

edit_applied_config_file() {
    local target_file="$1"
    local target_kind="$2"
    local target_label="${3:-$1}"
    local backup_file editor confirm rollback_confirm

    [[ -e "$target_file" || -L "$target_file" ]] || { echo -e "${RED}❌ 文件不存在：${target_file}${PLAIN}"; return 1; }
    [[ -f "$target_file" || -L "$target_file" ]] || { echo -e "${RED}❌ 不是普通配置文件：${target_file}${PLAIN}"; return 1; }

    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    echo -e "${BOLD}当前文件：${target_label}${PLAIN}"
    echo -e "${CYAN}${target_file}${PLAIN}"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    nl -ba "$target_file"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    read_trimmed confirm "是否打开编辑器修改该文件？(y/n，默认 n): "
    is_yes "$confirm" || return 0

    editor=$(applied_config_editor_command) || {
        echo -e "${RED}❌ 未找到可用编辑器。请先安装 nano/vim/vi，或设置 EDITOR。${PLAIN}"
        return 1
    }
    backup_file="${target_file}.bak_$(date +%s)"
    cp -p "$target_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消编辑。${PLAIN}"; return 1; }
    echo -e "${CYAN}编辑前备份：${backup_file}${PLAIN}"

    "$editor" "$target_file" || {
        echo -e "${RED}❌ 编辑器异常退出，配置未重新加载。${PLAIN}"
        return 1
    }

    if cmp -s "$target_file" "$backup_file"; then
        echo -e "${BLUE}配置未变化。${PLAIN}"
        return 0
    fi

    echo -e "${CYAN}▶ 正在校验配置...${PLAIN}"
    if ! validate_applied_config_kind "$target_kind" "$target_file"; then
        echo -e "${RED}❌ 校验失败，服务不会 reload。${PLAIN}"
        read_trimmed rollback_confirm "是否恢复编辑前备份？(Y/n，默认 yes): "
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && echo -e "${GREEN}✅ 已恢复：${target_file}${PLAIN}"
        else
            echo -e "${YELLOW}⚠️ 已保留未通过校验的修改，请手动修正后再应用。${PLAIN}"
        fi
        return 1
    fi

    if reload_applied_config_kind "$target_kind" "$target_file"; then
        echo -e "${GREEN}✅ 配置已保存并完成可执行的校验/应用步骤。${PLAIN}"
        echo -e "${CYAN}备份文件：${backup_file}${PLAIN}"
    else
        echo -e "${RED}❌ 配置校验通过，但应用/reload 失败。${PLAIN}"
        read_trimmed rollback_confirm "是否恢复编辑前备份？(Y/n，默认 yes): "
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && reload_applied_config_kind "$target_kind" "$target_file" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ 已尝试恢复编辑前配置。${PLAIN}"
        fi
        return 1
    fi
}

func_edit_applied_config_center() {
    local scope="${1:-all}"
    local -a applied_config_labels=()
    local -a applied_config_paths=()
    local -a applied_config_kinds=()
    collect_applied_config_files "$scope"

    clear
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ "$scope" == "proxy" ]]; then
        echo -e "${BOLD}📝 查看/编辑已应用反代配置${PLAIN}"
    else
        echo -e "${BOLD}📝 查看/编辑脚本已应用配置${PLAIN}"
    fi
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#applied_config_paths[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未检测到可编辑的已应用配置文件。${PLAIN}"
        return 0
    fi

    local i
    for i in "${!applied_config_paths[@]}"; do
        printf '%b%3d. %s%b\n' "$GREEN" "$((i + 1))" "${applied_config_labels[$i]} -> ${applied_config_paths[$i]}" "$PLAIN"
    done
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice idx
    read_trimmed choice "请选择要查看/编辑的配置文件: "
    [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "Q" ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#applied_config_paths[@]} )); then
        echo -e "${RED}❌ 无效选择。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    edit_applied_config_file "${applied_config_paths[$idx]}" "${applied_config_kinds[$idx]}" "${applied_config_labels[$idx]}"
}

func_backup_center() {
    local backup_root="/etc/vps-optimize/backups/manual"
    mkdir -p "$backup_root"
    chmod 700 "$backup_root" 2>/dev/null || true

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "备份与回滚"
        echo -e "${BOLD}🗂️ 配置备份与回滚中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "当前备份目录: ${YELLOW}${backup_root}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 创建全量配置备份${PLAIN}       ${YELLOW}(系统/面板/Caddy/脚本配置)${PLAIN}"
        echo -e "${GREEN}  2. 查看现有备份列表${PLAIN}"
        echo -e "${GREEN}  3. 从备份一键回滚${PLAIN}"
        echo -e "${GREEN}  4. 隔离旧备份${PLAIN}             ${YELLOW}(仅保留最近 5 份，旧文件移入隔离区)${PLAIN}"
        echo -e "${CYAN}  5. 查看/编辑脚本已应用配置${PLAIN} ${YELLOW}(备份、校验，可选择 reload/restart)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local b_choice
        read_trimmed b_choice "👉 请选择操作: "

        case $b_choice in
            1)
                local ts
                ts=$(date +%Y%m%d_%H%M%S)
                local work_dir
                local tar_file="${backup_root}/backup_${ts}.tar.gz"
                local manifest_file
                local copied=0

                work_dir=$(make_secure_temp_dir "vps_backup_${ts}") || {
                    echo -e "${RED}❌ 无法创建安全临时目录，备份已取消。${PLAIN}"
                    sleep 2
                    continue
                }
                manifest_file="${work_dir}/manifest.txt"
                {
                    echo "VPS-Optimize backup manifest"
                    echo "Created: $(date -Is 2>/dev/null || date)"
                    echo "Backup file: ${tar_file}"
                    echo "Included paths:"
                } > "$manifest_file"

                backup_copy_path /etc/ssh/sshd_config etc/ssh/sshd_config "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/hostname etc/hostname "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/hosts etc/hosts "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/nginx/nginx.conf etc/nginx/nginx.conf "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/nginx/stream.d etc/nginx/stream.d "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/nginx/conf.d etc/nginx/conf.d "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/nginx/sites-available etc/nginx/sites-available "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/nginx/sites-enabled etc/nginx/sites-enabled "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/caddy/Caddyfile etc/caddy/Caddyfile "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/caddy/conf.d etc/caddy/conf.d "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/caddy/certs etc/caddy/certs "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /root/cert root/cert "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /root/.acme.sh root/.acme.sh "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /root/.config/vps-panel/cloudflare.env root/.config/vps-panel/cloudflare.env "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/vps-optimize/sni-stack.env etc/vps-optimize/sni-stack.env "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/vps-optimize/sni-stack.last-backup etc/vps-optimize/sni-stack.last-backup "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/vps-optimize/443-engine.conf etc/vps-optimize/443-engine.conf "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/vps-optimize/vpso-mux.yaml etc/vps-optimize/vpso-mux.yaml "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/systemd/system/vpso-mux.service etc/systemd/system/vpso-mux.service "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /usr/local/bin/vpso-mux usr/local/bin/vpso-mux "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/vps-optimize/traffic-guard.conf etc/vps-optimize/traffic-guard.conf "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /var/lib/vps-optimize/traffic-guard var/lib/vps-optimize/traffic-guard "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /usr/local/bin/vps-traffic-guard-check usr/local/bin/vps-traffic-guard-check "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/systemd/system/vps-traffic-guard.service etc/systemd/system/vps-traffic-guard.service "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/systemd/system/vps-traffic-guard.timer etc/systemd/system/vps-traffic-guard.timer "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/resolv.conf etc/resolv.conf "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/docker/daemon.json etc/docker/daemon.json "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/fail2ban/jail.local etc/fail2ban/jail.local "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/sysctl.d etc/sysctl.d "$manifest_file" "$work_dir" && copied=1
                backup_copy_path /etc/x-ui etc/x-ui "$manifest_file" "$work_dir" && copied=1
                backup_copy_xui_databases "$manifest_file" "$work_dir" && copied=1

                if [[ "$copied" -eq 0 ]]; then
                    quarantine_path "$work_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "${YELLOW}⚠️ 未检测到可备份配置文件，已取消创建。${PLAIN}"
                else
                    if ( umask 077 && tar -czf "$tar_file" -C "$work_dir" . ) >/dev/null 2>&1; then
                        chmod 600 "$tar_file" 2>/dev/null || true
                        echo -e "${GREEN}✅ 备份创建成功: ${tar_file}${PLAIN}"
                        echo -e "${YELLOW}⚠️ 备份包含证书私钥、面板数据库和 API Token 等敏感配置，请妥善保管。${PLAIN}"
                    else
                        echo -e "${RED}❌ 备份打包失败，请检查磁盘空间与权限。${PLAIN}"
                    fi
                    quarantine_path "$work_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                fi
                ;;

            2)
                local backups
                backups=$(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ -z "$backups" ]]; then
                    echo -e "${YELLOW}⚠️ 当前没有任何备份文件。${PLAIN}"
                else
                    echo -e "${CYAN}👇 当前备份列表 (新 -> 旧)：${PLAIN}"
                    local idx=1
                    while IFS= read -r f; do
                        echo -e "  ${GREEN}${idx}.${PLAIN} $(basename "$f")"
                        idx=$((idx+1))
                    done <<< "$backups"
                fi
                ;;

            3)
                mapfile -t backups < <(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    echo -e "${YELLOW}⚠️ 没有可用备份，无法回滚。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                echo -e "${CYAN}👇 可回滚备份如下：${PLAIN}"
                for i in "${!backups[@]}"; do
                    echo -e "  ${GREEN}$((i+1)).${PLAIN} $(basename "${backups[$i]}")"
                done

                local r_choice
                read_trimmed r_choice "👉 请输入要回滚的序号: "
                if ! [[ "$r_choice" =~ ^[0-9]+$ ]] || [[ "$r_choice" -lt 1 ]] || [[ "$r_choice" -gt ${#backups[@]} ]]; then
                    echo -e "${RED}❌ 无效序号，已取消回滚。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                local target_file="${backups[$((r_choice-1))]}"
                confirm_danger "从备份回滚系统配置" "会覆盖 SSH、Caddy、Docker、Fail2ban、sysctl 等已纳入备份的当前配置。" "回滚后脚本会尝试重启相关服务；请保持当前 SSH 会话并准备好云厂商救援控制台。" || {
                    echo -e "${BLUE}已取消回滚操作。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                }

                local restore_dir
                local restore_failed=0
                local restore_quarantine="/etc/vps-optimize/quarantine/manual-restore"
                restore_dir=$(make_secure_temp_dir "vps_restore") || {
                    echo -e "${RED}❌ 无法创建安全临时目录，回滚中止。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                }

                if ! tar -tzf "$target_file" >/dev/null 2>&1; then
                    quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "${RED}❌ 备份文件无法读取，回滚中止。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                if tar -tzf "$target_file" 2>/dev/null | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
                    quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "${RED}❌ 备份文件包含不安全路径，回滚中止。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if ! tar -xzf "$target_file" -C "$restore_dir" >/dev/null 2>&1; then
                    quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "${RED}❌ 备份解压失败，回滚中止。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                restore_backup_file "$restore_dir/etc/ssh/sshd_config" /etc/ssh/sshd_config || restore_failed=1
                restore_backup_file "$restore_dir/etc/hostname" /etc/hostname || restore_failed=1
                restore_backup_file "$restore_dir/etc/hosts" /etc/hosts || restore_failed=1
                restore_backup_file "$restore_dir/etc/nginx/nginx.conf" /etc/nginx/nginx.conf || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/stream.d" /etc/nginx/stream.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/conf.d" /etc/nginx/conf.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/sites-available" /etc/nginx/sites-available "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/sites-enabled" /etc/nginx/sites-enabled "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/etc/caddy/Caddyfile" /etc/caddy/Caddyfile || restore_failed=1
                restore_backup_dir "$restore_dir/etc/caddy/conf.d" /etc/caddy/conf.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/caddy/certs" /etc/caddy/certs "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/root/cert" /root/cert "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/root/.acme.sh" /root/.acme.sh "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/root/.config/vps-panel/cloudflare.env" /root/.config/vps-panel/cloudflare.env || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/sni-stack.env" /etc/vps-optimize/sni-stack.env || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/sni-stack.last-backup" /etc/vps-optimize/sni-stack.last-backup || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/443-engine.conf" /etc/vps-optimize/443-engine.conf || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/vpso-mux.yaml" /etc/vps-optimize/vpso-mux.yaml || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/system/vpso-mux.service" /etc/systemd/system/vpso-mux.service || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/bin/vpso-mux" /usr/local/bin/vpso-mux || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/traffic-guard.conf" /etc/vps-optimize/traffic-guard.conf || restore_failed=1
                restore_backup_dir "$restore_dir/var/lib/vps-optimize/traffic-guard" /var/lib/vps-optimize/traffic-guard "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/bin/vps-traffic-guard-check" /usr/local/bin/vps-traffic-guard-check || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/system/vps-traffic-guard.service" /etc/systemd/system/vps-traffic-guard.service || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/system/vps-traffic-guard.timer" /etc/systemd/system/vps-traffic-guard.timer || restore_failed=1
                restore_backup_file "$restore_dir/etc/resolv.conf" /etc/resolv.conf || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf" /etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf || restore_failed=1
                restore_backup_file "$restore_dir/etc/docker/daemon.json" /etc/docker/daemon.json || restore_failed=1
                restore_backup_file "$restore_dir/etc/fail2ban/jail.local" /etc/fail2ban/jail.local || restore_failed=1
                restore_backup_dir "$restore_dir/etc/sysctl.d" /etc/sysctl.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/x-ui" /etc/x-ui "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/x-ui.db" /usr/local/x-ui/x-ui.db || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/x-ui.db-wal" /usr/local/x-ui/x-ui.db-wal || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/x-ui.db-shm" /usr/local/x-ui/x-ui.db-shm || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/bin/x-ui.db" /usr/local/x-ui/bin/x-ui.db || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/bin/x-ui.db-wal" /usr/local/x-ui/bin/x-ui.db-wal || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/bin/x-ui.db-shm" /usr/local/x-ui/bin/x-ui.db-shm || restore_failed=1

                if [[ -d "$restore_dir/etc/sysctl.d" ]]; then
                    sysctl --system >/dev/null 2>&1
                fi
                if [[ -f "$restore_dir/etc/hostname" ]]; then
                    local restored_hostname
                    restored_hostname=$(cat /etc/hostname 2>/dev/null | head -n1)
                    restored_hostname="$(trim_input "$restored_hostname")"
                    if [[ -n "$restored_hostname" ]]; then
                        hostnamectl set-hostname "$restored_hostname" >/dev/null 2>&1 || hostname "$restored_hostname" 2>/dev/null || true
                    fi
                fi
                if [[ -f "$restore_dir/etc/systemd/system/vps-traffic-guard.timer" || -f "$restore_dir/etc/systemd/system/vps-traffic-guard.service" || -f "$restore_dir/etc/systemd/system/vpso-mux.service" ]]; then
                    systemctl daemon-reload >/dev/null 2>&1 || true
                fi

                local restart_failed=0
                local restart_rc=0
                restart_service_if_available sshd
                restart_rc=$?
                if [[ "$restart_rc" -eq 2 ]]; then
                    restart_service_if_available ssh
                    restart_rc=$?
                fi
                [[ "$restart_rc" -eq 1 ]] && restart_failed=1

                for svc in nginx caddy docker fail2ban systemd-resolved x-ui 3x-ui xray sing-box vpso-mux; do
                    restart_service_if_available "$svc"
                    restart_rc=$?
                    [[ "$restart_rc" -eq 1 ]] && restart_failed=1
                done

                quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                if [[ "$restore_failed" -eq 0 && "$restart_failed" -eq 0 ]]; then
                    echo -e "${GREEN}✅ 回滚完成！建议立即验证 SSH、反代和容器服务状态。${PLAIN}"
                elif [[ "$restore_failed" -ne 0 ]]; then
                    echo -e "${YELLOW}⚠️ 部分备份文件恢复失败，请检查权限、磁盘空间和 ${restore_quarantine}。${PLAIN}"
                else
                    echo -e "${YELLOW}⚠️ 回滚文件已写入，但至少一个服务重启失败，请立即查看 systemctl status。${PLAIN}"
                fi
                ;;

            4)
                mapfile -t backups < <(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ ${#backups[@]} -le 5 ]]; then
                    echo -e "${BLUE}当前备份数量不超过 5 份，无需清理。${PLAIN}"
                else
                    confirm_danger "隔离旧备份" "会把第 6 份及更早的备份移入隔离目录，不会直接删除。" "如需恢复，可到 /etc/vps-optimize/quarantine/manual-backups 手动查看。保留最近 5 份不动。" || {
                        echo -e "${BLUE}已取消旧备份隔离。${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    }
                    for i in "${!backups[@]}"; do
                        if [[ "$i" -ge 5 ]]; then
                            quarantine_path "${backups[$i]}" "/etc/vps-optimize/quarantine/manual-backups" >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ 隔离失败: ${backups[$i]}${PLAIN}"
                        fi
                    done
                    echo -e "${GREEN}✅ 旧备份隔离完成，最近 5 份备份已保留。${PLAIN}"
                fi
                ;;

            5)
                func_edit_applied_config_center
                ;;

            "?"|help) show_backup_help ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac

        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}
