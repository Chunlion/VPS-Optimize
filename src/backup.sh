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
    echo -e "$(localized_text "${GREEN}✅ 已创建配置备份：${backup_dir}${PLAIN}" "${GREEN}✅ Configuration backup created: ${backup_dir}${PLAIN}" "${GREEN}✅ Создана резервная копия конфигурации: ${backup_dir}.${PLAIN}")"
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

    append_applied_config_file "$(localized_text "Caddy 主配置" "Caddy main configuration" "Основная конфигурация Caddy")" "/etc/caddy/Caddyfile" "caddy"
    for conf_file in /etc/caddy/conf.d/*.caddy; do
        [[ -f "$conf_file" ]] && append_applied_config_file "$(localized_text "Caddy 站点 $(basename "$conf_file")" "Caddy site $(basename \"$conf_file\")" "Caddy сайт $(basename \"$conf_file\")")" "$conf_file" "caddy"
    done
    append_applied_config_file "$(localized_text "Nginx 主配置" "Nginx main configuration" "Основная конфигурация Nginx")" "/etc/nginx/nginx.conf" "nginx"
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
    append_applied_config_file "$(localized_text "443 共享参数" "443 Shared parameters" "443 Общие параметры")" "/etc/vps-optimize/sni-stack.env" "entry-mode"
    append_applied_config_file "$(localized_text "443 引擎状态" "443 Engine status" "443 Статус двигателя")" "/etc/vps-optimize/443-engine.conf" "entry-mode"
    append_applied_config_file "$(localized_text "Xray SNI 分流记录" "Xray SNI routing record" "Xray SNI маршрутизирующая пластинка")" "/etc/vps-optimize/xray-sni-routes.conf" "xray-routes"
    append_applied_config_file "$(localized_text "TCP Peek vpso-mux 配置" "TCP Peek vpso-mux configuration" "Конфигурация TCP Peek vpso-mux")" "/etc/vps-optimize/vpso-mux.yaml" "vpso-mux"
    append_applied_config_file "vpso-mux systemd" "/etc/systemd/system/vpso-mux.service" "systemd"
    append_applied_config_file "$(localized_text "vpso-mux 8444 预检 systemd" "vpso-mux 8444 preflight check systemd" "vpso-mux 8444 Предварительная проверка systemd")" "/etc/systemd/system/vpso-mux-preflight.service" "systemd"
    append_applied_config_file "$(localized_text "Traffic Guard 配置" "Traffic Guard configuration" "Конфигурация Traffic Guard")" "$TRAFFIC_GUARD_CONFIG" "traffic-guard"
    append_applied_config_file "Traffic Guard service" "/etc/systemd/system/vps-traffic-guard.service" "systemd"
    append_applied_config_file "Traffic Guard timer" "/etc/systemd/system/vps-traffic-guard.timer" "systemd"
    append_applied_config_file "$(localized_text "Cloudflare DNS API 配置" "Cloudflare DNS API configuration" "Cloudflare DNS Конфигурация API")" "/root/.config/vps-panel/cloudflare.env" "env"
    append_applied_config_file "Docker daemon.json" "/etc/docker/daemon.json" "docker-json"
    append_applied_config_file "$(localized_text "SSH 主配置" "SSH main configuration" "Основная конфигурация SSH")" "/etc/ssh/sshd_config" "ssh"
    for conf_file in /etc/ssh/sshd_config.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "SSH drop-in $(basename "$conf_file")" "$conf_file" "ssh"
    done
    append_applied_config_file "$(localized_text "Hosts 文件" "Hosts file" "Файл хостов")" "/etc/hosts" "hosts"
    append_applied_config_file "$(localized_text "Hostname 文件" "Hostname file" "Файл имени хоста")" "/etc/hostname" "hostname"
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
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 jq/python3，已跳过 JSON 语法校验。${PLAIN}" "${YELLOW}⚠️ jq/python3 not detected, JSON syntax check skipped.${PLAIN}" "${YELLOW}⚠️ jq/python3 не обнаружен, проверка синтаксиса JSON пропущена.${PLAIN}")"
        return 0
    fi
}

load_docker_compose_runtime_helper() {
    local helper_path
    local -a helper_paths=()

    declare -F ensure_docker_compose_ready >/dev/null 2>&1 && return 0

    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        helper_paths+=("${SCRIPT_DIR}/src/compose_runtime.sh")
    fi
    helper_paths+=("$(dirname "${BASH_SOURCE[0]}")/compose_runtime.sh")

    for helper_path in "${helper_paths[@]}"; do
        [[ -f "$helper_path" ]] || continue
        # shellcheck source=/dev/null
        . "$helper_path"
        declare -F ensure_docker_compose_ready >/dev/null 2>&1 && return 0
    done

    return 1
}

run_applied_config_compose() {
    local target_file="$1"
    local project_dir
    shift

    if ! load_docker_compose_runtime_helper; then
        echo -e "$(localized_text "${RED}❌ 未加载 Docker Compose 自动安装/检测逻辑，无法应用 Compose 操作。${PLAIN}" "${RED}❌ The Docker Compose automatic installation/detection logic is not loaded and the Compose operation cannot be applied.${PLAIN}" "${RED}❌ Логика автоматической установки/обнаружения Docker Compose не загружена, и операцию Compose невозможно применить.${PLAIN}")"
        return 1
    fi

    ensure_docker_compose_ready || return 1
    project_dir=$(dirname "$target_file")
    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$target_file" "$@")
}

validate_applied_config_kind() {
    local kind="$1"
    local target_file="$2"

    case "$kind" in
        caddy)
            command -v caddy >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 caddy 命令，无法校验配置。${PLAIN}" "${RED}❌ The caddy command is not detected and the configuration cannot be verified.${PLAIN}" "${RED}❌ Команда caddy не обнаружена, и конфигурация не может быть проверена.${PLAIN}")"; return 1; }
            caddy validate --config /etc/caddy/Caddyfile
            ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 nginx 命令，无法校验配置。${PLAIN}" "${RED}❌ The nginx command is not detected and the configuration cannot be verified.${PLAIN}" "${RED}❌ Команда nginx не обнаружена, и конфигурация не может быть проверена.${PLAIN}")"; return 1; }
            nginx -t
            ;;
        systemd)
            if command -v systemd-analyze >/dev/null 2>&1; then
                systemd-analyze verify "$target_file"
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 systemd-analyze，已跳过 systemd unit 静态校验。${PLAIN}" "${YELLOW}⚠️ systemd-analyze is not detected and systemd unit static verification has been skipped.${PLAIN}" "${YELLOW}⚠️ systemd-анализ не обнаружен, а статическая проверка блока systemd пропущена.${PLAIN}")"
            fi
            ;;
        docker-json|xui-json)
            validate_json_file "$target_file"
            ;;
        compose)
            run_applied_config_compose "$target_file" config >/dev/null
            ;;
        ssh)
            command -v sshd >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 sshd 命令，无法校验 SSH 配置。${PLAIN}" "${RED}❌ The sshd command was not detected and the SSH configuration could not be verified.${PLAIN}" "${RED}❌ Команда sshd не обнаружена, и конфигурацию SSH проверить не удалось.${PLAIN}")"; return 1; }
            sshd -t
            ;;
        vpso-mux)
            if declare -F run_vpso_mux_config_check >/dev/null 2>&1; then
                run_vpso_mux_config_check "$target_file"
            elif [[ -x /usr/local/bin/vpso-mux ]]; then
                /usr/local/bin/vpso-mux -config "$target_file" -check
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 vpso-mux 二进制，已跳过运行时配置校验。${PLAIN}" "${YELLOW}⚠️ vpso-mux binary not detected, runtime configuration validation skipped.${PLAIN}" "${YELLOW}⚠️ Двоичный файл vpso-mux не обнаружен, проверка конфигурации во время выполнения пропущена.${PLAIN}")"
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
                echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 fail2ban-client，已跳过 Fail2ban 配置校验。${PLAIN}" "${YELLOW}⚠️ fail2ban-client is not detected and Fail2ban configuration validation has been skipped.${PLAIN}" "${YELLOW}⚠️ fail2ban-клиент не обнаружен и проверка конфигурации Fail2ban пропущена.${PLAIN}")"
            fi
            ;;
        *)
            echo -e "$(localized_text "${YELLOW}⚠️ 未知配置类型 ${kind}，仅保存备份，不执行额外校验。${PLAIN}" "${YELLOW}⚠️ Unknown configuration type ${kind}, only save backup and do not perform additional verification.${PLAIN}" "${YELLOW}⚠️ Неизвестный тип конфигурации ${kind}, сохраняйте только резервную копию и не выполняйте дополнительную проверку.${PLAIN}")"
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
    local previous_file="${3:-}"
    local confirm unit_name

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
            read_trimmed confirm "$(localized_text "systemd 已 daemon-reload，是否现在重启/重新加载 ${unit_name}？(Y/n，默认 y): " "systemd has been daemon-reloaded. Do you want to restart/reload ${unit_name} now? (Y/n, default y):" "systemd был перезагружен демоном. Вы хотите перезапустить/перезагрузить ${unit_name} сейчас? (Да/нет, по умолчанию y):")"
            if is_yes "$confirm"; then
                systemctl try-reload-or-restart "$unit_name" >/dev/null 2>&1 || systemctl restart "$unit_name" >/dev/null 2>&1
            else
                echo -e "$(localized_text "${BLUE}已保存 unit 修改，未重启 ${unit_name}。${PLAIN}" "${BLUE}Has saved the unit modification and has not restarted ${unit_name}.${PLAIN}" "${BLUE}сохранил модификацию устройства и не перезапустил ${unit_name}.${PLAIN}")"
            fi
            ;;
        docker-json)
            read_trimmed confirm "$(localized_text "Docker daemon.json 已校验，是否现在重启 Docker 使其生效？(Y/n，默认 y): " "Docker daemon.json has been verified. Do you want to restart Docker now to make it take effect? (Y/n, default y):" "Демон Docker.json проверен. Хотите перезапустить Docker сейчас, чтобы изменения вступили в силу? (Да/нет, по умолчанию y):")"
            if is_yes "$confirm"; then
                restart_named_service_if_available docker
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Docker 未重启，daemon.json 修改尚未生效。${PLAIN}" "${YELLOW}⚠️ Docker has not restarted, and the modification of daemon.json has not yet taken effect.${PLAIN}" "${YELLOW}⚠️ Docker не перезапустился, а модификация daemon.json еще не вступила в силу.${PLAIN}")"
            fi
            ;;
        compose)
            read_trimmed confirm "$(localized_text "Compose 配置已校验，是否现在执行 up -d 应用修改？(Y/n，默认 y): " "Compose The configuration has been verified. Do you want to execute up -d to apply the changes now? (Y/n, default y):" "Compose Конфигурация проверена. Вы хотите выполнить команду up -d, чтобы применить изменения сейчас? (Да/нет, по умолчанию y):")"
            if is_yes "$confirm"; then
                run_applied_config_compose "$target_file" up -d
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Compose 修改已保存，但容器尚未重建。${PLAIN}" "${YELLOW}⚠️ Compose The modifications have been saved, but the container has not been rebuilt.${PLAIN}" "${YELLOW}⚠️ Compose Модификации сохранены, но контейнер не пересобран.${PLAIN}")"
            fi
            ;;
        ssh)
            if confirm_risk_action "$(localized_text "重启 SSH 服务" "Restart SSH service" "Перезапустите службу SSH.")" \
                "$(localized_text "当前 SSH 服务运行状态" "Current SSH service running status" "Текущее состояние работы службы SSH")" \
                "$(localized_text "使用当前未断开的 SSH 会话恢复 ${target_file}.bak_*，或通过云厂商控制台恢复 SSH 配置" "Use the currently undisconnected SSH session to restore ${target_file}.bak_*, or restore the SSH configuration through the cloud vendor console" "Используйте текущий неотключенный сеанс SSH для восстановления ${target_file}.bak_* или восстановите конфигурацию SSH через консоль облачного поставщика.")" \
                "$(localized_text "确认新 SSH 配置已经通过 sshd -t 校验。" "Confirm that the new SSH configuration has passed sshd -t verification." "Убедитесь, что новая конфигурация SSH прошла проверку sshd -t.")"; then
                restart_service_if_available sshd >/dev/null 2>&1 || restart_service_if_available ssh >/dev/null 2>&1
            else
                echo -e "$(localized_text "${YELLOW}⚠️ SSH 未重启，修改可能尚未生效。${PLAIN}" "${YELLOW}⚠️ SSH has not been restarted, and the modification may not yet take effect.${PLAIN}" "${YELLOW}⚠️ SSH не был перезапущен, и модификация может еще не вступить в силу.${PLAIN}")"
            fi
            ;;
        vpso-mux)
            if confirm_risk_action "$(localized_text "重启 vpso-mux" "Restart vpso-mux" "Перезагрузите vpso-mux.")" \
                "$(localized_text "TCP Peek/vpso-mux 分流器运行进程" "TCP Peek/vpso-mux routing running process" "Процесс работы маршрутизации TCP Peek/vpso-mux")" \
                "$(localized_text "使用当前未断开的 SSH 会话恢复 ${target_file}.bak_*，或回到 443 单入口菜单重新应用/回滚入口模式" "Restore ${target_file}.bak_* using the currently undisconnected SSH session, or return to the 443 shared entry menu to reapply/rollback entry mode" "Восстановите ${target_file}.bak_*, используя текущий неотключенный сеанс SSH, или вернитесь в меню 443 с одним входом, чтобы повторно применить/откатить режим входа.")" \
                "$(localized_text "确认公网 443 当前入口模式和本机后端端口都正常。" "Confirm that the current entry mode of public port 443 and the local backend port are normal." "Убедитесь, что текущий режим входа в публичный порт 443 и локальный внутренний порт являются нормальными.")"; then
                restart_named_service_if_available vpso-mux
            else
                echo -e "$(localized_text "${YELLOW}⚠️ vpso-mux 未重启，修改尚未生效。${PLAIN}" "${YELLOW}⚠️ vpso-mux has not been restarted and the modification has not yet taken effect.${PLAIN}" "${YELLOW}⚠️ vpso-mux не был перезапущен и модификация еще не вступила в силу.${PLAIN}")"
            fi
            ;;
        entry-mode|xray-routes)
            if declare -F reapply_current_entry_mode >/dev/null 2>&1; then
                if confirm_risk_action "$(localized_text "重新应用当前 443 入口模式" "Reapply current 443 entry pattern" "Повторно применить текущий шаблон входа 443")" \
                    "$(localized_text "公网 443 入口配置、Caddy/Nginx/vpso-mux/Xray 相关路由" "public port 443 entry configuration, Caddy/Nginx/vpso-mux/Xray related routes" "Конфигурация входа в публичную сеть 443, маршруты, связанные с Caddy/Nginx/vpso-mux/Xray")" \
                    "$(localized_text "脚本会创建入口模式备份并在失败时回滚；也可从备份与回滚中心恢复" "Script creates entry mode backup and rolls back on failure; can also be restored from the Backup and Rollback Center" "Скрипт создает резервную копию в режим входа и выполняет откат в случае сбоя; также можно восстановить из Центра резервного копирования и отката.")" \
                    "$(localized_text "确认配置文件中的域名、端口和 ENTRY_MODE 值已经匹配。" "Confirm that the domain, port, and ENTRY_MODE value in the configuration file match." "Убедитесь, что имя домена, порт и значение ENTRY_MODE в файле конфигурации совпадают.")"; then
                    reapply_current_entry_mode
                else
                    echo -e "$(localized_text "${YELLOW}⚠️ 已保存配置，但未重新应用 443 入口模式。${PLAIN}" "${YELLOW}⚠️ Configuration saved, but 443 entry mode was not reapplied.${PLAIN}" "${YELLOW}⚠️ Конфигурация сохранена, но режим входа 443 не был применен повторно.${PLAIN}")"
                fi
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 已保存配置；请回到 443 单入口菜单重新应用当前入口模式。${PLAIN}" "${YELLOW}⚠️ The configuration has been saved; please return to the 443 shared entry menu to reapply the current entry mode.${PLAIN}" "${YELLOW}⚠️ Конфигурация сохранена; вернитесь в меню единого входа 443, чтобы повторно применить текущий режим ввода.${PLAIN}")"
            fi
            ;;
        traffic-guard)
            if [[ -n "$previous_file" ]] && declare -F traffic_guard_restore_ssh_only_firewall_from_config >/dev/null 2>&1; then
                traffic_guard_restore_ssh_only_firewall_from_config "$previous_file" || {
                    echo -e "$(localized_text "${RED}❌ 无法解除编辑前配置的仅保留 SSH 封锁规则，已取消应用。${PLAIN}" "${RED}❌ The keep-only SSH blocking rule configured before editing cannot be released and the application has been cancelled.${PLAIN}" "${RED}❌ Правило блокировки SSH «только сохранение», настроенное до редактирования, не может быть отменено, и приложение было отменено.${PLAIN}")"
                    return 1
                }
            fi
            if confirm_risk_action "$(localized_text "重启 Traffic Guard timer" "Restart Traffic Guard timer" "Перезапустить таймер Traffic Guard")" \
                "$(localized_text "vps-traffic-guard.timer 和流量阈值检查周期" "vps-traffic-guard.timer and traffic threshold check period" "vps-traffic-guard.timer и период проверки порога трафика")" \
                "$(localized_text "重新编辑 ${target_file} 或从 ${target_file}.bak_* 恢复；必要时停用 vps-traffic-guard.timer" "Re-edit ${target_file} or restore from ${target_file}.bak_*; disable vps-traffic-guard.timer if necessary" "Отредактируйте ${target_file} повторно или восстановите из ${target_file}.bak_*; при необходимости отключите vps-traffic-guard.timer")" \
                "$(localized_text "如果 ACTION=poweroff，请确认阈值、账单周期和云厂商救援方式。" "If ACTION=poweroff, confirm the threshold, billing cycle, and cloud vendor rescue method." "Если ACTION=poweroff, подтвердите пороговое значение, цикл выставления счетов и метод восстановления поставщика облачных услуг.")"; then
                systemctl daemon-reload >/dev/null 2>&1 || true
                systemctl restart vps-traffic-guard.timer >/dev/null 2>&1
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Traffic Guard timer 未重启，下一次运行前请确认配置已生效。${PLAIN}" "${YELLOW}⚠️ Traffic Guard timer has not been restarted. Please confirm that the configuration has taken effect before running it next time.${PLAIN}" "${YELLOW}⚠️ Таймер Traffic Guard не был перезапущен. Пожалуйста, подтвердите, что конфигурация вступила в силу, прежде чем запускать ее в следующий раз.${PLAIN}")"
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
            if confirm_risk_action "$(localized_text "重启 systemd-resolved" "Restart systemd-resolved" "Перезапуск systemd-решено")" \
                "$(localized_text "系统 DNS 解析服务和 resolved drop-in 配置" "System DNS resolution service and resolved drop-in configuration" "Служба разрешения проблем системы DNS и решенная прямая конфигурация")" \
                "$(localized_text "恢复 ${target_file}.bak_*，或重新进入 DNS 更改优化菜单切换回原配置" "Restore ${target_file}.bak_*, or re-enter DNS and change the optimization menu to switch back to the original configuration." "Восстановите ${target_file}.bak_* или повторно введите DNS и измените меню оптимизации, чтобы вернуться к исходной конфигурации.")" \
                "$(localized_text "确认当前 SSH 会话保持连接，必要时可用 IP 直连排障。" "Confirm that the current SSH session remains connected, and use IP direct connection to troubleshoot if necessary." "Убедитесь, что текущий сеанс SSH остается подключенным, и при необходимости используйте прямое IP-соединение для устранения неполадок.")"; then
                restart_named_service_if_available systemd-resolved
            else
                echo -e "$(localized_text "${BLUE}DNS 配置已保存，未重启 systemd-resolved。${PLAIN}" "${BLUE}DNS configuration saved, no restart systemd-resolved.${PLAIN}" "${BLUE}Конфигурация DNS сохранена, проблема с systemd решена без перезагрузки.${PLAIN}")"
            fi
            ;;
        sysctl)
            if confirm_risk_action "$(localized_text "应用 sysctl 配置" "Apply sysctl configuration" "Применить конфигурацию sysctl")" \
                "$(localized_text "当前内核运行中的 sysctl 参数" "sysctl parameters currently running in the kernel" "Параметры sysctl, работающие в настоящее время в ядре")" \
                "$(localized_text "恢复 ${target_file}.bak_* 后重新执行 sysctl --system，或手动回退异常参数" "Restore ${target_file}.bak_* and re-execute sysctl --system, or manually roll back the abnormal parameters" "Восстановите ${target_file}.bak_* и повторно выполните sysctl --system или вручную откатите ненормальные параметры.")" \
                "$(localized_text "确认参数来源可信；错误网络参数可能影响远程连接。" "Confirm that the source of the parameters is trustworthy; incorrect network parameters may affect remote connections." "Подтвердите, что источник параметров заслуживает доверия; неправильные параметры сети могут повлиять на удаленные подключения.")"; then
                sysctl --system >/dev/null
            else
                echo -e "$(localized_text "${YELLOW}⚠️ sysctl 修改尚未应用到当前内核。${PLAIN}" "${YELLOW}⚠️ The sysctl modification has not yet been applied to the current kernel.${PLAIN}" "${YELLOW}⚠️ Модификация sysctl пока не применена к текущему ядру.${PLAIN}")"
            fi
            ;;
        fail2ban)
            if confirm_risk_action "$(localized_text "重启 fail2ban" "Restart fail2ban" "Перезагрузите fail2ban.")" \
                "$(localized_text "Fail2ban 服务和登录防护规则" "Fail2ban Service and Login Protection Rules" "Fail2ban Правила защиты и защиты входа в систему")" \
                "$(localized_text "恢复 ${target_file}.bak_* 后重启 fail2ban，或临时停用异常 jail" "Restore ${target_file}.bak_* and then restart fail2ban, or temporarily disable the abnormal jail" "Восстановите ${target_file}.bak_*, а затем перезапустите fail2ban или временно отключите аварийный джейл.")" \
                "$(localized_text "确认当前 SSH 来源不会被新规则误封。" "Confirm that the current SSH source will not be accidentally blocked by the new rules." "Убедитесь, что текущий источник SSH не будет случайно заблокирован новыми правилами.")"; then
                restart_named_service_if_available fail2ban
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Fail2ban 未重启，修改尚未生效。${PLAIN}" "${YELLOW}⚠️ Fail2ban has not been restarted and the modification has not yet taken effect.${PLAIN}" "${YELLOW}⚠️ Fail2ban не был перезапущен и модификация еще не вступила в силу.${PLAIN}")"
            fi
            ;;
        xui-json)
            if confirm_risk_action "$(localized_text "重启 x-ui/3x-ui" "Restart x-ui/3x-ui" "Перезагрузите x-ui/3x-ui.")" \
                "$(localized_text "x-ui/3x-ui 面板进程和 config.json 运行配置" "x-ui/3x-ui panel process and config.json running configuration" "Процесс и конфигурация панели x-ui/3x-ui. Текущая конфигурация json")" \
                "$(localized_text "恢复 ${target_file}.bak_* 后重启面板，或用官方 x-ui/3x-ui 命令进入管理菜单修复" "Restore ${target_file}.bak_* and then restart the panel, or use the official x-ui/3x-ui command to enter the management menu to repair" "Восстановите ${target_file}.bak_*, а затем перезапустите панель или используйте официальную команду x-ui/3x-ui, чтобы войти в меню управления для восстановления.")" \
                "$(localized_text "确认面板端口、证书路径和 443 单入口设置匹配。" "Verify that the panel port, certificate path, and 443 share entry settings match." "Убедитесь, что порт панели, путь к сертификату и настройки записи общего ресурса 443 совпадают.")"; then
                restart_named_service_if_available x-ui
                restart_named_service_if_available 3x-ui
            else
                echo -e "$(localized_text "${YELLOW}⚠️ x-ui/3x-ui 未重启，修改可能尚未生效。${PLAIN}" "${YELLOW}⚠️ x-ui/3x-ui has not been restarted, and the modification may not yet take effect.${PLAIN}" "${YELLOW}⚠️ x-ui/3x-ui не был перезапущен, и модификация может еще не вступить в силу.${PLAIN}")"
            fi
            ;;
        env|hosts)
            echo -e "$(localized_text "${BLUE}配置已保存；该文件通常由系统或脚本后续读取，无需立即 reload。${PLAIN}" "${BLUE}Configuration has been saved; this file is usually read later by the system or script and does not need to be reloaded immediately.${PLAIN}" "${BLUE}Конфигурация сохранена; этот файл обычно читается позже системой или сценарием, и его не нужно перезагружать немедленно.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${BLUE}配置已保存；未为 ${kind} 定义自动 reload。${PLAIN}" "${BLUE}Configuration saved; no automatic reload is defined for ${kind}.${PLAIN}" "${BLUE}Конфигурация сохранена; для ${kind} автоматическая перезагрузка не определена.${PLAIN}")"
            ;;
    esac
}

edit_applied_config_file() {
    local target_file="$1"
    local target_kind="$2"
    local target_label="${3:-$1}"
    local backup_file editor confirm rollback_confirm

    [[ -e "$target_file" || -L "$target_file" ]] || { echo -e "$(localized_text "${RED}❌ 文件不存在：${target_file}${PLAIN}" "${RED}❌ File does not exist: ${target_file}${PLAIN}" "${RED}❌ Файл не существует: ${target_file}${PLAIN}")"; return 1; }
    [[ -f "$target_file" || -L "$target_file" ]] || { echo -e "$(localized_text "${RED}❌ 不是普通配置文件：${target_file}${PLAIN}" "${RED}❌ is not an ordinary configuration file: ${target_file}${PLAIN}" "${RED}❌ — это не обычный файл конфигурации: ${target_file}.${PLAIN}")"; return 1; }

    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    echo -e "$(localized_text "${BOLD}当前文件：${target_label}${PLAIN}" "${BOLD}Current file: ${target_label}${PLAIN}" "${BOLD}Текущий файл: ${target_label}${PLAIN}")"
    echo -e "${CYAN}${target_file}${PLAIN}"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    nl -ba "$target_file"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    read_trimmed confirm "$(localized_text "是否打开编辑器修改该文件？(Y/n，默认 y): " "Do you want to open an editor to modify the file? (Y/n, default y):" "Хотите открыть редактор и изменить файл? (Да/нет, по умолчанию y):")"
    is_yes "$confirm" || return 0

    editor=$(applied_config_editor_command) || {
        echo -e "$(localized_text "${RED}❌ 未找到可用编辑器。请先安装 nano/vim/vi，或设置 EDITOR。${PLAIN}" "${RED}❌ No available editor found. Please install nano/vim/vi first, or set up EDITOR.${PLAIN}" "${RED}❌ Доступный редактор не найден. Пожалуйста, сначала установите nano/vim/vi или настройте РЕДАКТОР.${PLAIN}")"
        return 1
    }
    backup_file="${target_file}.bak_$(date +%s)"
    cp -p "$target_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消编辑。${PLAIN}" "${RED}❌ Backup failed, editing canceled.${PLAIN}" "${RED}❌ Не удалось выполнить резервное копирование, редактирование отменено.${PLAIN}")"; return 1; }
    echo -e "$(localized_text "${CYAN}编辑前备份：${backup_file}${PLAIN}" "${CYAN}Backup before editing: ${backup_file}${PLAIN}" "${CYAN}Резервная копия перед редактированием: ${backup_file}${PLAIN}")"

    "$editor" "$target_file" || {
        echo -e "$(localized_text "${RED}❌ 编辑器异常退出，配置未重新加载。${PLAIN}" "${RED}❌ The editor exited abnormally and the configuration was not reloaded.${PLAIN}" "${RED}❌ Редактор завершился аварийно, и конфигурация не была перезагружена.${PLAIN}")"
        return 1
    }

    if cmp -s "$target_file" "$backup_file"; then
        echo -e "$(localized_text "${BLUE}配置未变化。${PLAIN}" "${BLUE}The configuration has not changed.${PLAIN}" "${BLUE}Конфигурация не изменилась.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在校验配置...${PLAIN}" "${CYAN}▶ Verifying configuration...${PLAIN}" "${CYAN}▶ Проверка конфигурации...${PLAIN}")"
    if ! validate_applied_config_kind "$target_kind" "$target_file"; then
        echo -e "$(localized_text "${RED}❌ 校验失败，服务不会 reload。${PLAIN}" "${RED}❌ The verification failed and the service will not reload.${PLAIN}" "${RED}❌ Проверка не удалась, и служба не перезагрузится.${PLAIN}")"
        read_trimmed rollback_confirm "$(localized_text "是否恢复编辑前备份？(Y/n，默认 yes): " "Restore pre-edit backup? (Y/n, default yes):" "Восстановить предварительно отредактированную резервную копию? (Да/нет, по умолчанию да):")"
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && echo -e "$(localized_text "${GREEN}✅ 已恢复：${target_file}${PLAIN}" "${GREEN}✅ Restored: ${target_file}${PLAIN}" "${GREEN}✅ Восстановлено: ${target_file}${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 已保留未通过校验的修改，请手动修正后再应用。${PLAIN}" "${YELLOW}⚠️ The modifications that failed the verification have been retained. Please correct them manually before applying them.${PLAIN}" "${YELLOW}⚠️ Модификации, не прошедшие проверку, сохранены. Пожалуйста, исправьте их вручную перед применением.${PLAIN}")"
        fi
        return 1
    fi

    if reload_applied_config_kind "$target_kind" "$target_file" "$backup_file"; then
        echo -e "$(localized_text "${GREEN}✅ 配置已保存并完成可执行的校验/应用步骤。${PLAIN}" "${GREEN}✅ Configuration saved and executable verification/application steps completed.${PLAIN}" "${GREEN}✅ Конфигурация сохранена, исполняемые этапы проверки/приложения выполнены.${PLAIN}")"
        echo -e "$(localized_text "${CYAN}备份文件：${backup_file}${PLAIN}" "${CYAN}Backup file: ${backup_file}${PLAIN}" "${CYAN}Файл резервной копии : ${backup_file}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 配置校验通过，但应用/reload 失败。${PLAIN}" "${RED}❌ configuration validation passed, but application/reload failed.${PLAIN}" "${RED}❌ Проверка конфигурации пройдена, но приложение/перезагрузка не удалась.${PLAIN}")"
        read_trimmed rollback_confirm "$(localized_text "是否恢复编辑前备份？(Y/n，默认 yes): " "Restore pre-edit backup? (Y/n, default yes):" "Восстановить предварительно отредактированную резервную копию? (Да/нет, по умолчанию да):")"
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && reload_applied_config_kind "$target_kind" "$target_file" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ 已尝试恢复编辑前配置。${PLAIN}" "${GREEN}✅ An attempt has been made to restore the pre-edit configuration.${PLAIN}" "${GREEN}✅ Предпринята попытка восстановить предредактированную конфигурацию.${PLAIN}")"
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
        echo -e "$(localized_text "${BOLD}📝 查看/编辑已应用反代配置${PLAIN}" "${BOLD}📝 View/edit applied reverse proxy configuration${PLAIN}" "${BOLD}📝 Просмотр/редактирование примененной конфигурации обратного прокси-сервера${PLAIN}")"
    else
        echo -e "$(localized_text "${BOLD}📝 查看/编辑脚本已应用配置${PLAIN}" "${BOLD}📝 View/edit script has applied configuration${PLAIN}" "${BOLD}📝 Скрипт просмотра/редактирования применил конфигурацию${PLAIN}")"
    fi
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#applied_config_paths[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到可编辑的已应用配置文件。${PLAIN}" "${YELLOW}No editable applied profile detected.${PLAIN}" "${YELLOW}Не обнаружен редактируемый прикладной профиль.${PLAIN}")"
        return 0
    fi

    local i
    for i in "${!applied_config_paths[@]}"; do
        printf '%b%3d. %s%b\n' "$GREEN" "$((i + 1))" "${applied_config_labels[$i]} -> ${applied_config_paths[$i]}" "$PLAIN"
    done
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice idx
    read_trimmed choice "$(localized_text "请选择要查看/编辑的配置文件: " "Please select a profile to view/edit:" "Пожалуйста, выберите профиль для просмотра/редактирования:")"
    [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "Q" ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#applied_config_paths[@]} )); then
        echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
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
        print_breadcrumb "$(localized_text "备份与回滚" "Backup and rollback" "Резервное копирование и откат")"
        echo -e "$(localized_text "${BOLD}🗂️ 配置备份与回滚中心${PLAIN}" "${BOLD}🗂️ Configure backup and rollback center${PLAIN}" "${BOLD}🗂️ Настройка центра резервного копирования и отката${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "当前备份目录: ${YELLOW}${backup_root}${PLAIN}" "Current backup directory: ${YELLOW}${backup_root}${PLAIN}" "Текущий каталог резервной копии: ${YELLOW}${backup_root}${PLAIN}.")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 创建全量配置备份${PLAIN}       ${YELLOW}(系统/面板/Caddy/脚本配置)${PLAIN}" "${GREEN}1. Create a full configuration backup (System/Panel/Caddy/Script Configuration)${PLAIN}" "${GREEN}1. Создайте полную резервную копию конфигурации (Система/Панель/Caddy/Конфигурация сценария)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 查看现有备份列表${PLAIN}" "${GREEN}2. View the existing backup list${PLAIN}" "${GREEN}2. Просмотрите существующий список резервных копий.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 从备份一键回滚${PLAIN}" "${GREEN}3. One-click rollback of from backup${PLAIN}" "${GREEN}3. Откат из резервной копии в один клик.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 隔离旧备份${PLAIN}             ${YELLOW}(仅保留最近 5 份，旧文件移入隔离区)${PLAIN}" "${GREEN}4. Isolate old backups (only the latest 5 copies are kept, and old files are moved to the quarantine area)${PLAIN}" "${GREEN}4. Изолировать старые резервные копии (сохраняются только последние 5 копий, а старые файлы перемещаются в зону карантина)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  5. 查看/编辑脚本已应用配置${PLAIN} ${YELLOW}(备份、校验，可选择 reload/restart)${PLAIN}" "${CYAN}5. View/edit script applied configuration (backup, verification, optional reload/restart)${PLAIN}" "${CYAN}5. Просмотр/редактирование примененной конфигурации сценария (резервное копирование, проверка, дополнительная перезагрузка/перезапуск)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Return to the main menu / q Return to the previous level${PLAIN}" "${RED}0. Возврат в главное меню / q Возврат на предыдущий уровень${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local b_choice
        read_trimmed b_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"

        case $b_choice in
            1)
                local ts
                ts=$(date +%Y%m%d_%H%M%S)
                local work_dir
                local tar_file="${backup_root}/backup_${ts}.tar.gz"
                local manifest_file
                local copied=0

                work_dir=$(make_secure_temp_dir "vps_backup_${ts}") || {
                    echo -e "$(localized_text "${RED}❌ 无法创建安全临时目录，备份已取消。${PLAIN}" "${RED}❌ Unable to create secure temporary directory, backup canceled.${PLAIN}" "${RED}❌ Невозможно создать безопасный временный каталог, резервное копирование отменено.${PLAIN}")"
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
                    echo -e "$(localized_text "${YELLOW}⚠️ 未检测到可备份配置文件，已取消创建。${PLAIN}" "${YELLOW}⚠️ The backupable configuration file was not detected and the creation has been cancelled.${PLAIN}" "${YELLOW}⚠️ Резервный файл конфигурации не обнаружен, и его создание отменено.${PLAIN}")"
                else
                    if ( umask 077 && tar -czf "$tar_file" -C "$work_dir" . ) >/dev/null 2>&1; then
                        chmod 600 "$tar_file" 2>/dev/null || true
                        echo -e "$(localized_text "${GREEN}✅ 备份创建成功: ${tar_file}${PLAIN}" "${GREEN}✅ Backup created successfully: ${tar_file}${PLAIN}" "${GREEN}. Резервная копия успешно создана: ${tar_file}.${PLAIN}")"
                        echo -e "$(localized_text "${YELLOW}⚠️ 备份包含证书私钥、面板数据库和 API Token 等敏感配置，请妥善保管。${PLAIN}" "${YELLOW}⚠️ The backup contains sensitive configurations such as certificate private key, panel database and API Token, please keep it properly.${PLAIN}" "${YELLOW}⚠️ Резервная копия содержит конфиденциальные конфигурации, такие как закрытый ключ сертификата, база данных панели и токен API, сохраняйте ее правильно.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ 备份打包失败，请检查磁盘空间与权限。${PLAIN}" "${RED}❌ Backup packaging failed, please check the disk space and permissions.${PLAIN}" "${RED}❌ Не удалось создать резервную копию, проверьте место на диске и разрешения.${PLAIN}")"
                    fi
                    quarantine_path "$work_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                fi
                ;;

            2)
                local backups
                backups=$(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ -z "$backups" ]]; then
                    echo -e "$(localized_text "${YELLOW}⚠️ 当前没有任何备份文件。${PLAIN}" "${YELLOW}⚠️ There are currently no backup files.${PLAIN}" "${YELLOW}⚠️ На данный момент файлов резервных копий нет.${PLAIN}")"
                else
                    echo -e "$(localized_text "${CYAN}👇 当前备份列表 (新 -> 旧)：${PLAIN}" "${CYAN}👇 Current backup list (new -> old):${PLAIN}" "${CYAN}👇 Текущий список резервных копий (новый -> старый):${PLAIN}")"
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
                    echo -e "$(localized_text "${YELLOW}⚠️ 没有可用备份，无法回滚。${PLAIN}" "${YELLOW}⚠️ No backup available, cannot roll back.${PLAIN}" "${YELLOW}⚠️ Резервная копия недоступна, невозможно выполнить откат.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                echo -e "$(localized_text "${CYAN}👇 可回滚备份如下：${PLAIN}" "${CYAN}👇 The rollback backup is as follows:${PLAIN}" "${CYAN}👇 Резервная копия для отката выглядит следующим образом:${PLAIN}")"
                for i in "${!backups[@]}"; do
                    echo -e "  ${GREEN}$((i+1)).${PLAIN} $(basename "${backups[$i]}")"
                done

                local r_choice
                read_trimmed r_choice "$(localized_text "👉 请输入要回滚的序号: " "👉 Please enter the serial number to be rolled back:" "👉 Пожалуйста, введите серийный номер для отката:")"
                if ! [[ "$r_choice" =~ ^[0-9]+$ ]] || [[ "$r_choice" -lt 1 ]] || [[ "$r_choice" -gt ${#backups[@]} ]]; then
                    echo -e "$(localized_text "${RED}❌ 无效序号，已取消回滚。${PLAIN}" "${RED}❌ Invalid sequence number, rollback canceled.${PLAIN}" "${RED}❌ Неверный порядковый номер, откат отменен.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                local target_file="${backups[$((r_choice-1))]}"
                confirm_danger "$(localized_text "从备份回滚系统配置" "Rolling back system configuration from backup" "Откат конфигурации системы из резервной копии")" "$(localized_text "会覆盖 SSH、Caddy、Docker、Fail2ban、sysctl 等已纳入备份的当前配置。" "It will overwrite the current configurations of SSH, Caddy, Docker, Fail2ban, sysctl, etc. that have been included in the backup." "Он перезапишет текущие конфигурации SSH, Caddy, Docker, Fail2ban, sysctl и т. д., которые были включены в резервную копию.")" "$(localized_text "回滚后脚本会尝试重启相关服务；请保持当前 SSH 会话并准备好云厂商救援控制台。" "After the rollback, the script will try to restart related services; please keep the current SSH session and prepare the cloud vendor rescue console." "После отката скрипт попытается перезапустить связанные службы; сохраните текущий сеанс SSH и подготовьте консоль восстановления облачного поставщика.")" || {
                    echo -e "$(localized_text "${BLUE}已取消回滚操作。${PLAIN}" "${BLUE}The rollback operation has been canceled.${PLAIN}" "${BLUE}Операция отката отменена.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                }

                local restore_dir
                local restore_failed=0
                local restore_quarantine="/etc/vps-optimize/quarantine/manual-restore"
                restore_dir=$(make_secure_temp_dir "vps_restore") || {
                    echo -e "$(localized_text "${RED}❌ 无法创建安全临时目录，回滚中止。${PLAIN}" "${RED}❌ Unable to create secure temporary directory, rollback aborted.${PLAIN}" "${RED}❌ Невозможно создать безопасный временный каталог, откат прерван.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                }

                if ! tar -tzf "$target_file" >/dev/null 2>&1; then
                    quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "$(localized_text "${RED}❌ 备份文件无法读取，回滚中止。${PLAIN}" "${RED}❌ The backup file cannot be read and the rollback is aborted.${PLAIN}" "${RED}❌ Файл резервной копии не может быть прочитан, и откат прерывается.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi
                if tar -tzf "$target_file" 2>/dev/null | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
                    quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "$(localized_text "${RED}❌ 备份文件包含不安全路径，回滚中止。${PLAIN}" "${RED}❌ The backup file contains an unsafe path and the rollback is aborted.${PLAIN}" "${RED}❌ Файл резервной копии содержит небезопасный путь, и откат прерывается.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if ! tar -xzf "$target_file" -C "$restore_dir" >/dev/null 2>&1; then
                    quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                    echo -e "$(localized_text "${RED}❌ 备份解压失败，回滚中止。${PLAIN}" "${RED}❌ Backup decompression failed and rollback aborted.${PLAIN}" "${RED}❌ Не удалось распаковать резервную копию, и откат прерван.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if [[ -f "$restore_dir/etc/vps-optimize/traffic-guard.conf" || -f "$restore_dir/usr/local/bin/vps-traffic-guard-check" ]]; then
                    if declare -F traffic_guard_restore_ssh_only_firewall >/dev/null 2>&1 && ! traffic_guard_restore_ssh_only_firewall; then
                        quarantine_path "$restore_dir" "/etc/vps-optimize/quarantine/manual-temp" >/dev/null 2>&1 || true
                        echo -e "$(localized_text "${RED}❌ 无法解除当前仅保留 SSH 封锁规则，回滚中止。${PLAIN}" "${RED}❌ Unable to unblock the current blocking rule of SSH, the rollback is aborted.${PLAIN}" "${RED}❌ Невозможно разблокировать текущее правило блокировки SSH, откат прерывается.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    fi
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
                    echo -e "$(localized_text "${GREEN}✅ 回滚完成！建议立即验证 SSH、反代和容器服务状态。${PLAIN}" "${GREEN}✅ Rollback completed! It is recommended to verify SSH, reverse proxy and container service status immediately.${PLAIN}" "${GREEN}✅ Откат завершен! Рекомендуется немедленно проверить статус SSH, обратный прокси и контейнерной службы.${PLAIN}")"
                elif [[ "$restore_failed" -ne 0 ]]; then
                    echo -e "$(localized_text "${YELLOW}⚠️ 部分备份文件恢复失败，请检查权限、磁盘空间和 ${restore_quarantine}。${PLAIN}" "${YELLOW}⚠️ Partial backup file recovery failed, please check permissions, disk space and ${restore_quarantine}.${PLAIN}" "${YELLOW}⚠️ Не удалось частично восстановить файл резервной копии. Проверьте разрешения, место на диске и ${restore_quarantine}.${PLAIN}")"
                else
                    echo -e "$(localized_text "${YELLOW}⚠️ 回滚文件已写入，但至少一个服务重启失败，请立即查看 systemctl status。${PLAIN}" "${YELLOW}⚠️ The rollback file has been written, but at least one service failed to restart. Please check systemctl status immediately.${PLAIN}" "${YELLOW}⚠️ Файл отката записан, но как минимум одну службу не удалось перезапустить. Пожалуйста, немедленно проверьте статус systemctl.${PLAIN}")"
                fi
                ;;

            4)
                mapfile -t backups < <(ls -1t "$backup_root"/backup_*.tar.gz 2>/dev/null)
                if [[ ${#backups[@]} -le 5 ]]; then
                    echo -e "$(localized_text "${BLUE}当前备份数量不超过 5 份，无需清理。${PLAIN}" "${BLUE}The current number of backups does not exceed 5 and no cleaning is required.${PLAIN}" "${BLUE}Текущее количество резервных копий не превышает 5 и очистка не требуется.${PLAIN}")"
                else
                    confirm_danger "$(localized_text "隔离旧备份" "Quarantine old backups" "Поместить старые резервные копии в карантин")" "$(localized_text "会把第 6 份及更早的备份移入隔离目录，不会直接删除。" "The 6th and earlier backups will be moved to the quarantine directory and will not be deleted directly." "Шестая и более ранние резервные копии будут перемещены в каталог карантина и не будут удалены напрямую.")" "$(localized_text "如需恢复，可到 /etc/vps-optimize/quarantine/manual-backups 手动查看。保留最近 5 份不动。" "If you need to restore, you can go to /etc/vps-optimize/quarantine/manual-backups to check manually. Leave the last 5 copies unchanged." "Если вам нужно восстановить, вы можете перейти к /etc/vps-optimize/quarantine/manual-backups и проверить вручную. Последние 5 копий оставьте без изменений.")" || {
                        echo -e "$(localized_text "${BLUE}已取消旧备份隔离。${PLAIN}" "${BLUE}The old backup has been dequarantined.${PLAIN}" "${BLUE}Старая резервная копия выведена из карантина.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    }
                    for i in "${!backups[@]}"; do
                        if [[ "$i" -ge 5 ]]; then
                            quarantine_path "${backups[$i]}" "/etc/vps-optimize/quarantine/manual-backups" >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}⚠️ 隔离失败: ${backups[$i]}${PLAIN}" "${YELLOW}⚠️ Isolation failed: ${backups[$i]}${PLAIN}" "${YELLOW}⚠️ Сбой изоляции: ${backups[$i]}${PLAIN}")"
                        fi
                    done
                    echo -e "$(localized_text "${GREEN}✅ 旧备份隔离完成，最近 5 份备份已保留。${PLAIN}" "${GREEN}✅ Old backup isolation completed, the last 5 backups have been retained.${PLAIN}" "${GREEN}✅ Изоляция старых резервных копий завершена, последние 5 резервных копий сохранены.${PLAIN}")"
                fi
                ;;

            5)
                func_edit_applied_config_center
                ;;

            "?"|help) show_backup_help ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")" ;;
        esac

        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}
