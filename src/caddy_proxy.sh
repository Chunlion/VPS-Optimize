# shellcheck shell=bash
# Ordinary Caddy/Nginx reverse proxy workflows outside the 443 single-entry stack.

func_caddy_add_reverse_proxy() {
    echo -e "${CYAN}▶ 正在检查并安装 Caddy...${PLAIN}"
    if ! install_caddy_if_needed; then
        echo -e "${RED}❌ Caddy 安装失败，请检查软件源、网络或系统版本。${PLAIN}"
        return 1
    fi
    if ! ensure_caddy_module_layout; then
        echo -e "${RED}❌ Caddy 配置目录初始化失败，请检查 /etc/caddy 权限。${PLAIN}"
        return 1
    fi

    local domain domain_input port is_https
    read_trimmed domain_input "请输入解析后的域名 (如 panel.site.com): "
    read_trimmed port "请输入面板本地映射端口 (如 40000): "
    domain=$(normalize_domain_input "$domain_input")

    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "域名" "$domain_input" "$domain"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。${PLAIN}"
        return 1
    fi

    local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
    if grep -q "^[[:space:]]*$domain" /etc/caddy/Caddyfile 2>/dev/null || [[ -e "$domain_conf" ]]; then
        echo -e "${RED}❌ 错误：已存在该域名的配置块！请先清理或更换域名后再添加。${PLAIN}"
        return 1
    fi

    read_trimmed is_https "❓ 后端面板是否开启了自带的 SSL 证书？(y/n): "

    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed enable_ip_whitelist "❓ 是否只允许指定 IP/CIDR 访问该域名？(y/n，默认 n): "
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单，避免把自己挡在外面。${PLAIN}"
        read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "${RED}❌ 白名单为空或格式错误，已取消本次反代配置。${PLAIN}"
            return 1
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi

    local backup_file="/etc/caddy/Caddyfile.bak_$(date +%s)"
    [[ -f /etc/caddy/Caddyfile ]] && cp -p /etc/caddy/Caddyfile "$backup_file"

    if is_yes "$is_https"; then
        cat <<EOF > "$domain_conf"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
    else
        cat <<EOF > "$domain_conf"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy localhost:$port
}
EOF
    fi

    echo -e "${CYAN}▶ 正在校验 Caddy 配置文件...${PLAIN}"
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Caddy 反代配置已追加并生效！请访问 https://$domain${PLAIN}"
            [[ -n "$ip_whitelist_ranges" ]] && echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
            echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
        else
            echo -e "${RED}❌ Caddy 配置校验通过，但服务重载失败，正在回滚...${PLAIN}"
            [[ -f "$backup_file" ]] && mv "$backup_file" /etc/caddy/Caddyfile
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
            return 1
        fi
    else
        echo -e "${RED}❌ 致命错误：生成的配置存在语法异常！正在自动回滚...${PLAIN}"
        [[ -f "$backup_file" ]] && mv "$backup_file" /etc/caddy/Caddyfile
        quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
        return 1
    fi
}

nginx_proxy_conf_path() {
    local domain="$1"
    echo "/etc/nginx/conf.d/vps_proxy_${domain}.conf"
}

install_nginx_http_if_needed() {
    command -v nginx >/dev/null 2>&1 && return 0
    echo -e "${CYAN}▶ 未检测到 Nginx，正在安装...${PLAIN}"
    if is_debian || is_redhat; then
        install_pkg nginx || return 1
    else
        echo -e "${RED}❌ 当前系统暂不支持自动安装 Nginx。${PLAIN}"
        return 1
    fi
    command -v nginx >/dev/null 2>&1
}

ensure_nginx_http_conf_d() {
    local nginx_conf="/etc/nginx/nginx.conf"
    mkdir -p /etc/nginx/conf.d || return 1
    [[ -f "$nginx_conf" ]] || { echo -e "${RED}❌ 未找到 ${nginx_conf}。${PLAIN}"; return 1; }
    if grep -q '/etc/nginx/conf.d/\*.conf' "$nginx_conf" 2>/dev/null; then
        return 0
    fi
    if grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$nginx_conf" 2>/dev/null; then
        cp -p "$nginx_conf" "${nginx_conf}.bak_$(date +%s)" 2>/dev/null || true
        sed -i '/^[[:space:]]*http[[:space:]]*{/a\    include /etc/nginx/conf.d/*.conf;' "$nginx_conf"
        return 0
    fi
    echo -e "${RED}❌ nginx.conf 中未找到 http {}，无法安全追加 conf.d include。${PLAIN}"
    return 1
}

write_nginx_proxy_map_conf() {
    mkdir -p /etc/nginx/conf.d || return 1
    cat <<'EOF' > /etc/nginx/conf.d/00-vps-proxy-map.conf
map $http_upgrade $vps_proxy_connection_upgrade {
    default upgrade;
    '' close;
}
EOF
}

nginx_ip_whitelist_block() {
    local ranges="$1"
    [[ -z "$ranges" ]] && return 0
    {
        echo "    # vps-optimize-ip-whitelist-start"
        local range
        for range in $ranges; do
            echo "    allow ${range};"
        done
        echo "    deny all;"
        echo "    # vps-optimize-ip-whitelist-end"
    }
}

strip_nginx_ip_whitelist_block() {
    local conf_file="$1"
    local tmp_file
    tmp_file=$(mktemp /tmp/nginx-ipwl.XXXXXX) || return 1
    awk '
        /# vps-optimize-ip-whitelist-start/ {skip=1; next}
        /# vps-optimize-ip-whitelist-end/ {skip=0; next}
        !skip {print}
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

insert_nginx_ip_whitelist_block() {
    local conf_file="$1"
    local ranges="$2"
    local tmp_file block
    strip_nginx_ip_whitelist_block "$conf_file" || return 1
    tmp_file=$(mktemp /tmp/nginx-ipwl.XXXXXX) || return 1
    block=$(nginx_ip_whitelist_block "$ranges")
    awk -v block="$block" '
        inserted == 0 && /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/ {
            printf "%s\n", block
            print
            inserted=1
            next
        }
        {print}
        END { if (inserted == 0) exit 1 }
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

nginx_proxy_whitelist_ranges_from_conf() {
    local conf_file="$1"
    awk '
        /# vps-optimize-ip-whitelist-start/ {in_block=1; next}
        /# vps-optimize-ip-whitelist-end/ {in_block=0; next}
        in_block && /^[[:space:]]*allow[[:space:]]+/ {
            gsub(/^[[:space:]]*allow[[:space:]]+/, "", $0)
            gsub(/[;[:space:]]+$/, "", $0)
            if ($0 != "") print $0
        }
    ' "$conf_file" | paste -sd' ' -
}

nginx_proxy_domain_exists() {
    local domain="$1"
    [[ -e "$(nginx_proxy_conf_path "$domain")" ]] && return 0
    grep -RqsE "server_name[[:space:]].*\\b${domain}\\b" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null
}

nginx_proxy_warn_if_single_entry_enabled() {
    if [[ -f /etc/vps-optimize/sni-stack.env || -f /etc/vps-optimize/443-engine.conf ]]; then
        echo -e "${RED}❌ 已检测到 443 单入口配置。Nginx HTTPS 反代会抢占公网 443，已拒绝继续。${PLAIN}"
        echo -e "${YELLOW}请改用：主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]。${PLAIN}"
        return 1
    fi
    return 0
}

quarantine_legacy_nginx_https_proxy_configs() {
    local conf_file moved=0
    for conf_file in /etc/nginx/conf.d/vps_proxy_*.conf; do
        [[ -e "$conf_file" ]] || continue
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy-to-443-entry" >/dev/null 2>&1 || true
        moved=$((moved + 1))
    done
    if [[ "$moved" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已隔离 ${moved} 个旧 Nginx HTTPS 反代配置，避免抢占公网 443。${PLAIN}"
    fi
}

nginx_proxy_ensure_certificate() {
    local domain="$1"
    local cert_file="/etc/caddy/certs/${domain}.crt"
    local key_file="/etc/caddy/certs/${domain}.key"
    local reuse_cert CF_TOKEN verify_rc

    if [[ -s "$cert_file" && -s "$key_file" ]]; then
        read_trimmed reuse_cert "检测到已有证书 ${cert_file}，是否复用？(Y/n，默认 yes): "
        if ! is_no "$reuse_cert"; then
            echo -e "${GREEN}✅ 已复用现有证书：${cert_file}${PLAIN}"
            return 0
        fi
    fi

    echo -e "${YELLOW}Nginx 反代证书继续使用现有 acme.sh + Cloudflare DNS API 流程。${PLAIN}"
    echo -e "${YELLOW}证书将安装到 /etc/caddy/certs/${domain}.crt|key，并软链到 /root/cert/。${PLAIN}"
    read_secret_trimmed CF_TOKEN "请输入 Cloudflare API Token（需有该域名 DNS 编辑权限）: "
    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then
        echo -e "${RED}❌ Cloudflare Token 长度异常。${PLAIN}"
        return 1
    fi
    verify_cf_token_online "$CF_TOKEN"
    verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
    else
        echo -e "${RED}❌ Cloudflare Token 在线校验失败。${PLAIN}"
        return 1
    fi
    issue_and_install_cert_for_domain "$domain" "$CF_TOKEN" || return 1
    [[ -s "$cert_file" && -s "$key_file" ]] || { echo -e "${RED}❌ 证书安装后仍缺失：${cert_file}|${key_file}${PLAIN}"; return 1; }
}

write_nginx_reverse_proxy_conf() {
    local domain="$1"
    local port="$2"
    local is_https="$3"
    local conf_file="$4"
    local ip_whitelist_ranges="${5:-}"
    local backend_scheme="http"
    local proxy_ssl_block=""
    local ip_whitelist_block=""
    local listen_80_ipv6=""
    local listen_443_ipv6=""

    if is_yes "$is_https"; then
        backend_scheme="https"
        proxy_ssl_block="    proxy_ssl_server_name on;
    proxy_ssl_verify off;"
    fi
    ip_whitelist_block=$(nginx_ip_whitelist_block "$ip_whitelist_ranges")
    if [[ -s /proc/net/if_inet6 && "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" != "1" ]]; then
        listen_80_ipv6="    listen [::]:80;"
        listen_443_ipv6="    listen [::]:443 ssl http2;"
    fi

    cat <<EOF > "$conf_file"
server {
    listen 80;
${listen_80_ipv6}
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
${listen_443_ipv6}
    server_name ${domain};

    ssl_certificate /etc/caddy/certs/${domain}.crt;
    ssl_certificate_key /etc/caddy/certs/${domain}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    location / {
${ip_whitelist_block}
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$vps_proxy_connection_upgrade;
${proxy_ssl_block}
        proxy_pass ${backend_scheme}://127.0.0.1:${port};
    }
}
EOF
}

func_nginx_add_reverse_proxy() {
    echo -e "${CYAN}▶ 正在配置 Nginx HTTPS 反代...${PLAIN}"
    nginx_proxy_warn_if_single_entry_enabled || return 1
    local domain domain_input port is_https conf_file enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed domain_input "请输入解析后的域名 (如 panel.example.com): "
    read_trimmed port "请输入本地后端端口 (如 40000): "
    domain=$(normalize_domain_input "$domain_input")

    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "域名" "$domain_input" "$domain"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。${PLAIN}"
        return 1
    fi

    conf_file=$(nginx_proxy_conf_path "$domain")
    if nginx_proxy_domain_exists "$domain"; then
        echo -e "${RED}❌ Nginx 中已存在该域名配置，请先清理或更换域名后再添加。${PLAIN}"
        return 1
    fi
    if [[ -e "/etc/caddy/conf.d/${domain}.caddy" ]] || grep -q "^[[:space:]]*$domain" /etc/caddy/Caddyfile 2>/dev/null; then
        echo -e "${RED}❌ Caddy 中已存在该域名配置，请避免同一域名同时由 Caddy 和 Nginx 接管。${PLAIN}"
        return 1
    fi

    read_trimmed is_https "后端是否是自带证书的 HTTPS 服务？(y/n，默认 n): "
    read_trimmed enable_ip_whitelist "是否只允许指定 IP/CIDR 访问该 Nginx 域名？(y/n，默认 n): "
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单，避免把自己挡在外面。${PLAIN}"
        read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "${RED}❌ 白名单为空或格式错误，已取消本次反代配置。${PLAIN}"
            return 1
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi
    nginx_proxy_ensure_certificate "$domain" || return 1
    install_nginx_http_if_needed || { echo -e "${RED}❌ Nginx 安装失败，请检查软件源、网络或系统版本。${PLAIN}"; return 1; }
    ensure_nginx_http_conf_d || return 1
    harden_nginx_public_errors
    write_nginx_proxy_map_conf || return 1
    write_nginx_reverse_proxy_conf "$domain" "$port" "$is_https" "$conf_file" "$ip_whitelist_ranges" || return 1

    echo -e "${CYAN}▶ 正在校验 Nginx 配置...${PLAIN}"
    if ! nginx -t >/dev/null 2>&1; then
        echo -e "${RED}❌ Nginx 配置校验失败，已隔离新增配置。${PLAIN}"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1 || true
        nginx -t
        return 1
    fi

    systemctl enable nginx >/dev/null 2>&1 || true
    if systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Nginx 反代已生效：https://${domain}${PLAIN}"
        echo -e "${GREEN}✅ 后端：127.0.0.1:${port}${PLAIN}"
        [[ -n "$ip_whitelist_ranges" ]] && echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
        echo -e "${CYAN}配置文件：${conf_file}${PLAIN}"
        echo -e "${CYAN}证书路径：/etc/caddy/certs/${domain}.crt 和 /etc/caddy/certs/${domain}.key${PLAIN}"
    else
        echo -e "${RED}❌ Nginx 配置校验通过，但 reload/restart 失败。可能是 Caddy、443 单入口或其他服务占用了 80/443。${PLAIN}"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1 || true
        return 1
    fi
}

func_nginx_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ Nginx 后端 HTTPS 跳过证书校验${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    nginx_proxy_warn_if_single_entry_enabled || return 1

    local domain domain_input port conf_file backup_file ip_whitelist_ranges
    read_trimmed domain_input "请输入要设置的域名 (如 panel.example.com): "
    read_trimmed port "请输入 HTTPS 后端本地端口 (如 40000): "
    domain=$(normalize_domain_input "$domain_input")
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "域名" "$domain_input" "$domain"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。${PLAIN}"
        return 1
    fi

    nginx_proxy_ensure_certificate "$domain" || return 1
    install_nginx_http_if_needed || return 1
    ensure_nginx_http_conf_d || return 1
    harden_nginx_public_errors
    write_nginx_proxy_map_conf || return 1

    conf_file=$(nginx_proxy_conf_path "$domain")
    if [[ -f "$conf_file" ]]; then
        backup_file="${conf_file}.bak_$(date +%s)"
        cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; return 1; }
        ip_whitelist_ranges=$(nginx_proxy_whitelist_ranges_from_conf "$conf_file")
        echo -e "${CYAN}已备份现有配置：${backup_file}${PLAIN}"
    else
        ip_whitelist_ranges=""
    fi

    write_nginx_reverse_proxy_conf "$domain" "$port" "y" "$conf_file" "$ip_whitelist_ranges" || return 1
    if nginx -t >/dev/null 2>&1; then
        if systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Nginx 已设置为 HTTPS 后端并跳过后端证书校验：${domain} -> https://127.0.0.1:${port}${PLAIN}"
            [[ -n "$ip_whitelist_ranges" ]] && echo -e "${GREEN}✅ 已保留 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
        else
            echo -e "${RED}❌ Nginx 校验通过，但 reload/restart 失败。${PLAIN}"
            [[ -n "$backup_file" && -f "$backup_file" ]] && cp -p "$backup_file" "$conf_file"
            return 1
        fi
    else
        echo -e "${RED}❌ Nginx 配置校验失败，正在回滚。${PLAIN}"
        [[ -n "$backup_file" && -f "$backup_file" ]] && cp -p "$backup_file" "$conf_file"
        nginx -t
        return 1
    fi
}

func_proxy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 后端 HTTPS 跳过证书校验${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Caddy 跳过后端证书校验${PLAIN}"
    echo -e "${GREEN}  2. Nginx 跳过后端证书校验${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    local choice
    read_trimmed choice "请选择操作: "
    case "$choice" in
        1) func_caddy_add_insecure ;;
        2) func_nginx_add_insecure ;;
        0|q|Q|"") echo -e "${BLUE}已取消。${PLAIN}" ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
    esac
}

func_nginx_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔐 Nginx 域名 IP 白名单${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适用于未启用 443 单入口、由 Nginx HTTPS 反代直接对外服务的域名。${PLAIN}"
    echo -e "${YELLOW}如果该域名已接入 443 单入口，请用 [19] -> [9]，不要在 Nginx HTTP 层限制。${PLAIN}"
    echo -e "------------------------------------------------"

    local domain domain_input conf_file action backup_file
    read_trimmed domain_input "请输入要管理的域名 (如 panel.example.com): "
    domain=$(normalize_domain_input "$domain_input")
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "域名" "$domain_input" "$domain"
        return 1
    fi
    conf_file=$(nginx_proxy_conf_path "$domain")
    if [[ ! -f "$conf_file" ]]; then
        echo -e "${RED}❌ 未找到 ${conf_file}。该入口只管理脚本创建的 Nginx HTTPS 反代配置。${PLAIN}"
        return 1
    fi

    echo -e "当前配置文件：${conf_file}"
    if grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
        echo -e "${YELLOW}当前状态：已启用脚本管理的 IP 白名单。${PLAIN}"
        echo -e "当前白名单：$(nginx_proxy_whitelist_ranges_from_conf "$conf_file")"
    else
        echo -e "${BLUE}当前状态：未启用脚本管理的 IP 白名单。${PLAIN}"
    fi
    echo -e "1. 设置/覆盖白名单"
    echo -e "2. 清除白名单"
    echo -e "0/q. 取消"
    read_trimmed action "请选择操作: "

    backup_file="${conf_file}.bak_$(date +%s)"
    case "$action" in
        1)
            local ip_whitelist_input ip_whitelist_ranges current_client_ip
            local -a ip_whitelist_array=()
            current_client_ip=$(detect_ssh_client_ip)
            [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
            read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
            if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
                echo -e "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}"
                return 1
            fi
            append_vps_public_ips_to_whitelist ip_whitelist_array
            ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
            cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; return 1; }
            if insert_nginx_ip_whitelist_block "$conf_file" "$ip_whitelist_ranges" && nginx -t >/dev/null 2>&1; then
                if systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ 已为 ${domain} 启用 Nginx IP 白名单：${ip_whitelist_ranges}${PLAIN}"
                    echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
                else
                    echo -e "${RED}❌ Nginx 重载失败，正在回滚...${PLAIN}"
                    cp -p "$backup_file" "$conf_file"
                    systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
                    return 1
                fi
            else
                echo -e "${RED}❌ 写入后 Nginx 校验失败，正在回滚...${PLAIN}"
                cp -p "$backup_file" "$conf_file"
                nginx -t
                return 1
            fi
            ;;
        2)
            if ! grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
                echo -e "${BLUE}该域名没有脚本管理的白名单块，无需清除。${PLAIN}"
                return 0
            fi
            cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; return 1; }
            if strip_nginx_ip_whitelist_block "$conf_file" && nginx -t >/dev/null 2>&1; then
                systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ 已清除 ${domain} 的 Nginx IP 白名单。${PLAIN}"
                echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
            else
                echo -e "${RED}❌ 清除后 Nginx 校验失败，正在回滚...${PLAIN}"
                cp -p "$backup_file" "$conf_file"
                return 1
            fi
            ;;
        0|q|Q|"")
            echo -e "${BLUE}已取消。${PLAIN}"
            ;;
        *)
            echo -e "${RED}❌ 无效操作。${PLAIN}"
            ;;
    esac
}

func_proxy_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔐 域名 IP 白名单（Caddy / Nginx）${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Caddy 域名 IP 白名单${PLAIN}"
    echo -e "${GREEN}  2. Nginx 域名 IP 白名单${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    local choice
    read_trimmed choice "请选择操作: "
    case "$choice" in
        1) func_caddy_manage_ip_whitelist ;;
        2) func_nginx_manage_ip_whitelist ;;
        0|q|Q|"") echo -e "${BLUE}已取消。${PLAIN}" ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
    esac
}

func_nginx_clear_proxy_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清空 Nginx HTTPS 反代配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}只隔离 VPS-Optimize 创建的 /etc/nginx/conf.d/vps_proxy_*.conf 和 00-vps-proxy-map.conf。${PLAIN}"
    echo -e "${YELLOW}不会清理 /etc/nginx/stream.d，也不会影响 443 单入口配置。${PLAIN}"
    echo -e "------------------------------------------------"

    local -a files=()
    local conf_file backup_dir moved=0
    for conf_file in /etc/nginx/conf.d/vps_proxy_*.conf /etc/nginx/conf.d/00-vps-proxy-map.conf; do
        [[ -f "$conf_file" ]] && files+=("$conf_file")
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${BLUE}未检测到脚本创建的 Nginx HTTPS 反代配置。${PLAIN}"
        return 0
    fi
    printf '  - %s\n' "${files[@]}"
    if ! confirm_danger "清空 Nginx HTTPS 反代配置" \
        "上述 Nginx HTTPS 反代配置会被移入隔离目录，相关域名将不再由 Nginx 反代访问。" \
        "从隔离目录 /etc/vps-optimize/quarantine/nginx-proxy 手动移回对应文件后执行 nginx -t && systemctl reload nginx。"; then
        echo -e "${BLUE}已取消清空操作。${PLAIN}"
        return 0
    fi

    backup_dir="/etc/vps-optimize/backups/nginx-proxy-clear_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    for conf_file in "${files[@]}"; do
        cp -p "$conf_file" "$backup_dir/$(basename "$conf_file")" 2>/dev/null || true
        if quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1; then
            moved=$((moved + 1))
        else
            echo -e "${YELLOW}⚠️ 隔离失败：${conf_file}${PLAIN}"
        fi
    done
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ 已隔离 ${moved} 个 Nginx HTTPS 反代配置。${PLAIN}"
        echo -e "${CYAN}备份目录：${backup_dir}${PLAIN}"
    else
        echo -e "${RED}❌ 清理后 Nginx 校验失败，请检查 nginx -t 输出。${PLAIN}"
        nginx -t
        return 1
    fi
}

func_proxy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清空反代配置（Caddy / Nginx）${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. 清空 Caddy 反代配置${PLAIN}"
    echo -e "${GREEN}  2. 清空 Nginx HTTPS 反代配置${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    local choice
    read_trimmed choice "请选择操作: "
    case "$choice" in
        1) func_caddy_clear_config ;;
        2) func_nginx_clear_proxy_config ;;
        0|q|Q|"") echo -e "${BLUE}已取消。${PLAIN}" ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
    esac
}

append_editable_proxy_config_file() {
    local label="$1"
    local path="$2"
    local kind="$3"
    [[ -f "$path" ]] || return 0
    proxy_config_labels+=("$label")
    proxy_config_paths+=("$path")
    proxy_config_kinds+=("$kind")
}

collect_editable_proxy_config_files() {
    proxy_config_labels=()
    proxy_config_paths=()
    proxy_config_kinds=()

    append_editable_proxy_config_file "Caddy 主配置" "/etc/caddy/Caddyfile" "caddy"
    local conf_file
    for conf_file in /etc/caddy/conf.d/*.caddy; do
        [[ -f "$conf_file" ]] && append_editable_proxy_config_file "Caddy 站点 $(basename "$conf_file")" "$conf_file" "caddy"
    done
    append_editable_proxy_config_file "Nginx 主配置" "/etc/nginx/nginx.conf" "nginx"
    for conf_file in /etc/nginx/conf.d/*.conf; do
        [[ -f "$conf_file" ]] && append_editable_proxy_config_file "Nginx conf.d $(basename "$conf_file")" "$conf_file" "nginx"
    done
    for conf_file in /etc/nginx/sites-enabled/*; do
        [[ -f "$conf_file" ]] && append_editable_proxy_config_file "Nginx sites-enabled $(basename "$conf_file")" "$conf_file" "nginx"
    done
}

proxy_config_editor_command() {
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

validate_proxy_config_kind() {
    local kind="$1"
    case "$kind" in
        caddy)
            command -v caddy >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 caddy 命令，无法校验配置。${PLAIN}"; return 1; }
            caddy validate --config /etc/caddy/Caddyfile
            ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 nginx 命令，无法校验配置。${PLAIN}"; return 1; }
            nginx -t
            ;;
        *)
            echo -e "${RED}❌ 未知配置类型：${kind}${PLAIN}"
            return 1
            ;;
    esac
}

reload_proxy_config_kind() {
    local kind="$1"
    case "$kind" in
        caddy) systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 ;;
        nginx) systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

func_edit_applied_proxy_config() {
    local -a proxy_config_labels=()
    local -a proxy_config_paths=()
    local -a proxy_config_kinds=()
    collect_editable_proxy_config_files

    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}📝 查看/编辑已应用配置文件${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#proxy_config_paths[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未检测到可编辑的 Caddy/Nginx 配置文件。${PLAIN}"
        return 0
    fi

    local i
    for i in "${!proxy_config_paths[@]}"; do
        printf '%b%3d. %s%b\n' "$GREEN" "$((i + 1))" "${proxy_config_labels[$i]} -> ${proxy_config_paths[$i]}" "$PLAIN"
    done
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice idx target_file target_kind backup_file editor confirm rollback_confirm
    read_trimmed choice "请选择要查看/编辑的配置文件: "
    [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "Q" ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#proxy_config_paths[@]} )); then
        echo -e "${RED}❌ 无效选择。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    target_file="${proxy_config_paths[$idx]}"
    target_kind="${proxy_config_kinds[$idx]}"
    [[ -f "$target_file" ]] || { echo -e "${RED}❌ 文件不存在：${target_file}${PLAIN}"; return 1; }

    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    echo -e "${BOLD}当前文件：${target_file}${PLAIN}"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    nl -ba "$target_file"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    read_trimmed confirm "是否打开编辑器修改该文件？(y/n，默认 n): "
    is_yes "$confirm" || return 0

    editor=$(proxy_config_editor_command) || {
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
    if ! validate_proxy_config_kind "$target_kind"; then
        echo -e "${RED}❌ 校验失败，服务不会 reload。${PLAIN}"
        read_trimmed rollback_confirm "是否恢复编辑前备份？(Y/n，默认 yes): "
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && echo -e "${GREEN}✅ 已恢复：${target_file}${PLAIN}"
        else
            echo -e "${YELLOW}⚠️ 已保留未通过校验的修改，请手动修正后再 reload。${PLAIN}"
        fi
        return 1
    fi

    if reload_proxy_config_kind "$target_kind"; then
        echo -e "${GREEN}✅ 配置已校验并重新加载。${PLAIN}"
        echo -e "${CYAN}备份文件：${backup_file}${PLAIN}"
    else
        echo -e "${RED}❌ 配置校验通过，但服务 reload/restart 失败。${PLAIN}"
        read_trimmed rollback_confirm "是否恢复编辑前备份？(Y/n，默认 yes): "
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && reload_proxy_config_kind "$target_kind" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ 已尝试恢复编辑前配置。${PLAIN}"
        fi
        return 1
    fi
}

func_caddy_reverse_proxy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "反代"
        echo -e "${BOLD}🌐 反代（Caddy / Nginx）${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：管理未接入 443 单入口的域名反代。443 单入口请只走主菜单 [19]。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 添加 Caddy 反代${PLAIN}"
        echo -e "${GREEN}  2. 添加 Nginx HTTPS 反代${PLAIN} ${YELLOW}(复用 acme.sh + CF DNS 证书)${PLAIN}"
        echo -e "${CYAN}  3. 查看 Caddy/共享证书路径${PLAIN}"
        echo -e "${CYAN}  4. 后端 HTTPS 跳过证书校验${PLAIN} ${YELLOW}(Caddy/Nginx，后端自签 HTTPS 时使用)${PLAIN}"
        echo -e "${CYAN}  5. 域名 IP 白名单${PLAIN} ${YELLOW}(Caddy/Nginx)${PLAIN}"
        echo -e "${CYAN}  6. 查看/编辑已应用配置文件${PLAIN} ${YELLOW}(Caddy/Nginx，校验后 reload)${PLAIN}"
        echo -e "${RED}  7. 清空反代配置${PLAIN} ${YELLOW}(Caddy/Nginx)${PLAIN}"
        echo -e "${RED}  8. 删除底层 ACME 证书/域名配置${PLAIN} ${YELLOW}(会同时清理脚本创建的 Nginx 配置)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local caddy_choice
        read_trimmed caddy_choice "👉 请选择操作: "
        case "$caddy_choice" in
            1) func_caddy_add_reverse_proxy ;;
            2) func_nginx_add_reverse_proxy ;;
            3) func_view_caddy_cert ;;
            4) func_proxy_add_insecure ;;
            5) func_proxy_manage_ip_whitelist ;;
            6) func_edit_applied_proxy_config ;;
            7) func_proxy_clear_config ;;
            8) func_caddy_delete_cert ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        pause_return "按任意键继续..."
    done
}
