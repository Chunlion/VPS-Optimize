# shellcheck shell=bash
# 443 single-entry collection, installation, rendering, certificates, and runtime apply flows.

collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}443 单入口共享配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}公网 443 将由你选择的入口模式监听；Web 域名、Caddy 后端、证书和白名单为三种模式共享。${PLAIN}"
    echo -e "${YELLOW}Caddy/Xray/3x-ui 本地后端默认绑定 127.0.0.1。${PLAIN}"
    echo -e "------------------------------------------------"

    local default_panel_addr="127.0.0.1"
    local default_panel_port="40000"
    local default_panel_path="/panel/"
    local default_sub_addr="127.0.0.1"
    local default_sub_port="2096"
    local default_sub_path="/sub/"
    local default_clash_path="/clash/"
    detect_xui_single_443_defaults
    if [[ -n "${XUI_DETECTED_BIN:-}" || -n "${XUI_DETECTED_DB:-}" ]]; then
        default_panel_addr="${XUI_DETECTED_PANEL_ADDR:-127.0.0.1}"
        default_panel_port="${XUI_DETECTED_WEB_PORT:-40000}"
        default_panel_path="${XUI_DETECTED_WEB_BASE_PATH:-/panel/}"
        default_sub_addr="${XUI_DETECTED_SUB_ADDR:-127.0.0.1}"
        default_sub_port="${XUI_DETECTED_SUB_PORT:-2096}"
        default_sub_path="${XUI_DETECTED_SUB_PATH:-/sub/}"
        default_clash_path="${XUI_DETECTED_SUB_CLASH_PATH:-/clash/}"
    fi
    print_xui_single_443_detected_defaults
    echo -e "------------------------------------------------"

    read_trimmed PANEL_DOMAIN "面板域名（必填，例如 panel.example.com）: "
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()
    TCP_ROUTE_SNIS=()
    TCP_ROUTE_ADDRS=()
    TCP_ROUTE_PORTS=()
    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()
    local site_domains_input
    site_domains_input=$(ask_with_default "网站/反代域名（可选，多个用英文逗号分隔，例如 site1.example.com,site2.example.com）" "")
    split_csv_to_array "$site_domains_input" SITE_DOMAINS
    echo -e "${YELLOW}REALITY 伪装 SNI 请填写外部真实 HTTPS 站点域名，不要填写面板域名或节点域名。${PLAIN}"
    echo -e "${YELLOW}模板示例：your-reality-sni.example.com（请替换成你自己选择的真实站点）${PLAIN}"
    read_trimmed REALITY_SNI "REALITY 伪装 SNI（必填）: "
    NGINX_LISTEN_ADDR=$(ask_with_default "Nginx 公网监听地址" "0.0.0.0")
    NGINX_LISTEN_PORT=$(ask_with_default "Nginx 公网监听端口" "443")

    local advanced_mode
    read_trimmed advanced_mode "是否进入高级模式并允许修改本地服务监听地址？(y/n，默认 n): "
    if is_yes "$advanced_mode"; then
        CADDY_LISTEN_ADDR=$(ask_with_default "Caddy 本地监听地址" "127.0.0.1")
        XRAY_LISTEN_ADDR=$(ask_with_default "Xray REALITY 本地监听地址" "127.0.0.1")
        PANEL_LISTEN_ADDR=$(ask_with_default "3x-ui 面板监听地址" "$default_panel_addr")
        SUB_LISTEN_ADDR=$(ask_with_default "3x-ui 订阅服务监听地址" "$default_sub_addr")
    else
        CADDY_LISTEN_ADDR="127.0.0.1"
        XRAY_LISTEN_ADDR="127.0.0.1"
        PANEL_LISTEN_ADDR="$default_panel_addr"
        SUB_LISTEN_ADDR="$default_sub_addr"
        echo -e "${GREEN}普通模式：Caddy/Xray/3x-ui/订阅/网站后端均使用 127.0.0.1。${PLAIN}"
    fi

    CADDY_LISTEN_PORT=$(ask_with_default "Caddy 本地监听端口" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "Xray REALITY 本地监听端口" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "3x-ui 面板端口" "$default_panel_port")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 面板公网路径 / webBasePath（必须和面板 url 根路径一致）" "$default_panel_path")")
    SUB_LISTEN_PORT=$(ask_with_default "3x-ui 订阅服务端口（可自定义）" "$default_sub_port")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 普通订阅路径前缀（不带端口和客户端 Subscription，建议写 /sub/）" "$default_sub_path")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "$default_clash_path")")
    local panel_whitelist_enabled panel_whitelist_input panel_whitelist_ranges current_client_ip
    local -a panel_whitelist_array=()
    read_trimmed panel_whitelist_enabled "是否为面板域名启用 IP 白名单？(y/n，默认 n): "
    if is_yes "$panel_whitelist_enabled"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed panel_whitelist_input "请输入允许访问面板域名的 IP/CIDR（多个用空格或英文逗号分隔）: "
        normalize_ip_whitelist_input "$panel_whitelist_input" panel_whitelist_array || return 1
        append_vps_public_ips_to_whitelist panel_whitelist_array
        panel_whitelist_ranges=$(join_array_by_space "${panel_whitelist_array[@]}")
    fi
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i default_site_port
        default_site_port=3000
        for i in "${!SITE_DOMAINS[@]}"; do
            if [[ -z "${SITE_DOMAINS[$i]}" ]]; then
                continue
            fi
            if is_yes "$advanced_mode"; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端监听地址" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端端口" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    echo -e "${YELLOW}443 单入口需要 3x-ui 面板/订阅后端使用 HTTP，由 Caddy 统一托管公网证书。${PLAIN}"
    echo -e "${YELLOW}本向导会让 Caddy 通过 HTTP 连接 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} 和 ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}。${PLAIN}"
    echo -e "${CYAN}证书处理分两种情况：${PLAIN}"
    echo -e "  3x-ui 3.x 新安装：在官方安装器里选择 Skip SSL / 不申请 SSL，本步骤只做兜底检查。"
    echo -e "  3x-ui 2.x、升级旧配置、或曾经启用过 3x-ui SSL：继续按旧流程清空面板/订阅证书路径。"
    local cert_clear_confirm
    read_trimmed cert_clear_confirm "是否现在兜底清空 2.x/旧配置中的 3x-ui 面板/订阅证书路径？(Y/n，默认 yes): "
    cert_clear_confirm="${cert_clear_confirm:-yes}"
    if is_yes "$cert_clear_confirm"; then
        if ! clear_xui_cert_settings_for_single_443; then
            read_trimmed cert_clear_confirm "未能自动确认清空，是否已经手动清空面板证书和订阅证书路径？(y/n，默认 n): "
            is_yes "$cert_clear_confirm" || { echo -e "${YELLOW}请先回 3x-ui 清空证书路径并保存重启，再运行本向导。${PLAIN}"; return 1; }
        fi
    else
        read_trimmed cert_clear_confirm "确认已经手动清空面板证书和订阅证书路径？(y/n，默认 n): "
        is_yes "$cert_clear_confirm" || { echo -e "${YELLOW}请先回 3x-ui 清空证书路径并保存重启，再运行本向导。${PLAIN}"; return 1; }
    fi

    echo -e "${CYAN}请输入 Cloudflare API Token（需 Zone.DNS.Edit + Zone.Zone.Read）${PLAIN}"
    read_secret_trimmed CF_TOKEN "CF Token: "

    PANEL_DOMAIN=$(normalize_domain_input "$PANEL_DOMAIN")
    REALITY_SNI=$(normalize_domain_input "$REALITY_SNI")
    local site_idx
    for site_idx in "${!SITE_DOMAINS[@]}"; do
        SITE_DOMAINS[$site_idx]=$(normalize_domain_input "${SITE_DOMAINS[$site_idx]}")
    done

    if ! is_valid_domain "$PANEL_DOMAIN"; then echo -e "${RED}❌ 面板域名无效。${PLAIN}"; return 1; fi
    if ! is_valid_domain "$REALITY_SNI"; then echo -e "${RED}❌ REALITY SNI 无效。${PLAIN}"; return 1; fi
    check_domain_dns_sanity "$PANEL_DOMAIN" "面板域名" "prompt" || return 1
    check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "prompt" || return 1
    local site_domain seen_domains
    seen_domains=" ${PANEL_DOMAIN} ${REALITY_SNI} "
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ -z "$site_domain" ]] && continue
        if ! is_valid_domain "$site_domain"; then echo -e "${RED}❌ 网站/反代域名无效：${site_domain}${PLAIN}"; return 1; fi
        if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" || "$seen_domains" == *" ${site_domain} "* ]]; then
            echo -e "${RED}❌ 面板域名、网站/反代域名、REALITY SNI 不能相同：${site_domain}${PLAIN}"
            return 1
        fi
        check_domain_dns_sanity "$site_domain" "网站/反代域名" "prompt" || return 1
        seen_domains+=" ${site_domain} "
    done

    local p a
    for p in "$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}"; do
        is_valid_port "$p" || { echo -e "${RED}❌ 端口无效：${p}${PLAIN}"; return 1; }
    done
    for a in "$NGINX_LISTEN_ADDR" "$CADDY_LISTEN_ADDR" "$XRAY_LISTEN_ADDR" "$PANEL_LISTEN_ADDR" "$SUB_LISTEN_ADDR" "${SITE_BACKEND_ADDRS[@]}"; do
        is_valid_listen_addr "$a" || { echo -e "${RED}❌ 监听地址无效：${a}${PLAIN}"; return 1; }
    done
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "${RED}❌ 面板公网路径无效：${PANEL_WEB_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "${RED}❌ 普通订阅路径前缀无效：${SUB_URI_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "${RED}❌ Clash/Mihomo 订阅路径前缀无效：${CLASH_URI_PATH}${PLAIN}"; return 1; }
    if [[ "$PANEL_WEB_PATH" == "$SUB_URI_PATH" || "$PANEL_WEB_PATH" == "$CLASH_URI_PATH" || "$SUB_URI_PATH" == "$CLASH_URI_PATH" ]]; then
        echo -e "${RED}❌ 面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。${PLAIN}"
        return 1
    fi
    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
    if [[ -n "${panel_whitelist_ranges:-}" ]]; then
        set_sni_ip_whitelist_for_domain "$PANEL_DOMAIN" "$panel_whitelist_ranges"
    fi
    [[ "$NGINX_LISTEN_PORT" != "443" ]] && echo -e "${YELLOW}⚠️  Nginx 公网端口不是 443，不推荐。${PLAIN}"

    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 面板" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 订阅服务" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then echo -e "${RED}❌ Cloudflare Token 长度异常。${PLAIN}"; return 1; fi
    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
    verify_cf_token_online "$CF_TOKEN"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
    else
        echo -e "${RED}❌ Cloudflare Token 校验失败。${PLAIN}"
        return 1
    fi
}

install_caddy_if_needed() {
    command -v caddy >/dev/null 2>&1 && return 0
    echo -e "${CYAN}▶ 未检测到 Caddy，正在安装...${PLAIN}"
    if is_debian; then
        local key_tmp repo_tmp
        install_pkg debian-keyring debian-archive-keyring apt-transport-https curl gpg || return 1
        command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ 缺少 curl，无法添加 Caddy 源。${PLAIN}"; return 1; }
        command -v gpg >/dev/null 2>&1 || { echo -e "${RED}❌ 缺少 gpg，无法校验 Caddy 源。${PLAIN}"; return 1; }
        key_tmp=$(mktemp /tmp/caddy-key.XXXXXX) || return 1
        repo_tmp=$(mktemp /tmp/caddy-repo.XXXXXX) || { rm -f "$key_tmp"; return 1; }
        if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o "$key_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "${RED}❌ Caddy GPG key 下载失败。${PLAIN}"
            return 1
        fi
        if ! gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg "$key_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "${RED}❌ Caddy GPG key 写入失败。${PLAIN}"
            return 1
        fi
        if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o "$repo_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "${RED}❌ Caddy APT 源配置下载失败。${PLAIN}"
            return 1
        fi
        if ! mv "$repo_tmp" /etc/apt/sources.list.d/caddy-stable.list; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "${RED}❌ Caddy APT 源配置写入失败。${PLAIN}"
            return 1
        fi
        rm -f "$key_tmp"
        install_pkg caddy || return 1
    elif is_redhat; then
        install_pkg yum-utils || true
        if command -v yum-config-manager >/dev/null 2>&1; then
            yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo >/dev/null 2>&1 || return 1
        else
            echo -e "${YELLOW}⚠️ 未检测到 yum-config-manager，将尝试直接从系统源安装 Caddy。${PLAIN}"
        fi
        install_pkg caddy || return 1
    else
        echo -e "${RED}❌ 暂不支持当前系统自动安装 Caddy。${PLAIN}"
        return 1
    fi
    command -v caddy >/dev/null 2>&1
}

ensure_caddy_module_layout() {
    mkdir -p /etc/caddy/conf.d || return 1
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<'EOF' > /etc/caddy/Caddyfile
import conf.d/*
EOF
        return 0
    fi
    if ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        cp -p /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null || true
        printf '\nimport conf.d/*\n' >> /etc/caddy/Caddyfile
    fi
}

install_nginx_stream_stack() {
    echo -e "${CYAN}▶ 正在检查 Nginx stream 组件...${PLAIN}"
    local need_install=0
    local nginx_build
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 Nginx，正在安装基础组件...${PLAIN}"
        need_install=1
    else
        nginx_build=$(nginx -V 2>&1 || true)
    fi

    if [[ "$need_install" -eq 0 ]]; then
        if [[ "$nginx_build" == *"--with-stream=dynamic"* ]]; then
            if grep -Rqs 'load_module .*ngx_stream_module\.so' /etc/nginx/nginx.conf /etc/nginx/modules-enabled 2>/dev/null; then
                echo -e "${GREEN}✅ 已检测到 Nginx stream 动态模块加载配置，跳过安装步骤。${PLAIN}"
            else
                echo -e "${YELLOW}⚠️ Nginx 支持动态 stream 模块，但未确认模块已加载，正在尝试补齐模块...${PLAIN}"
                need_install=1
            fi
        elif [[ "$nginx_build" == *"--with-stream"* || "$nginx_build" == *"--with-stream_ssl_preread_module"* ]]; then
            echo -e "${GREEN}✅ 已检测到 Nginx stream 静态支持，跳过安装步骤。${PLAIN}"
        else
            echo -e "${YELLOW}⚠️ 未确认 Nginx stream 支持，正在尝试补齐模块...${PLAIN}"
            need_install=1
        fi
    fi

    if [[ "$need_install" -eq 1 ]]; then
        if is_debian; then
            install_pkg nginx libnginx-mod-stream
        elif is_redhat; then
            install_pkg nginx
            install_pkg nginx-mod-stream || echo -e "${YELLOW}⚠️ nginx-mod-stream 安装失败或仓库未提供，将继续检测 Nginx stream 支持。${PLAIN}"
        fi
    fi
    command -v nginx >/dev/null 2>&1 || { echo -e "${RED}❌ Nginx 安装失败。${PLAIN}"; return 1; }
    mkdir -p /etc/nginx/stream.d
    if ! grep -Eq '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        cat <<'EOF' >> /etc/nginx/nginx.conf

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF
    elif ! grep -q '/etc/nginx/stream.d/\*.conf' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        sed -i '/^[[:space:]]*stream[[:space:]]*{/a\    include /etc/nginx/stream.d/*.conf;' /etc/nginx/nginx.conf
    fi
}

harden_nginx_public_errors() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local drop_conf="/etc/nginx/conf.d/00-vps-default-drop.conf"
    local quarantine_dir="/etc/vps-optimize/nginx-default-sites-disabled_$(date +%s)"
    local moved=0
    local default_file

    command -v nginx >/dev/null 2>&1 || return 0
    mkdir -p /etc/nginx/conf.d /etc/vps-optimize

    if [[ -f "$nginx_conf" ]]; then
        if grep -Eq '^[#[:space:]]*server_tokens[[:space:]]+' "$nginx_conf"; then
            sed -i 's/^[#[:space:]]*server_tokens[[:space:]].*;/    server_tokens off;/' "$nginx_conf"
        elif grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$nginx_conf"; then
            sed -i '/^[[:space:]]*http[[:space:]]*{/a\    server_tokens off;' "$nginx_conf"
        fi
    fi

    for default_file in \
        /etc/nginx/sites-enabled/default \
        /etc/nginx/sites-available/default \
        /etc/nginx/conf.d/default.conf; do
        if [[ -e "$default_file" ]]; then
            mkdir -p "$quarantine_dir"
            mv "$default_file" "$quarantine_dir/" >/dev/null 2>&1 && ((moved++))
        fi
    done

    cat <<'EOF' > "$drop_conf"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
EOF

    if [[ "$moved" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已隔离 ${moved} 个 Nginx 默认站点配置到：${quarantine_dir}${PLAIN}"
    fi
    echo -e "${GREEN}✅ 已关闭 Nginx 版本号显示，并写入 80 端口默认丢弃规则。${PLAIN}"
}

write_nginx_sni_stream_config() {
    local conf_file="${1:-/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf}"
    local validate="${2:-yes}"
    local listen_directives
    local caddy_backend
    local xray_backend
    local guarded_backend_var="\$vps_sni_backend"
    local -a whitelist_block_vars=()
    listen_directives=$(nginx_stream_listen_directives "$NGINX_LISTEN_ADDR" "$NGINX_LISTEN_PORT")
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")

    : > "$conf_file"
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]]; then
        local i domain ranges suffix allow_var block_var range
        for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
            domain="${SNI_IP_WHITELIST_DOMAINS[$i]}"
            ranges="${SNI_IP_WHITELIST_RANGES[$i]}"
            [[ -n "$domain" && -n "$ranges" ]] || continue
            is_sni_stack_web_domain "$domain" || continue
            suffix=$(nginx_var_suffix_for_domain "$domain")
            allow_var="vps_ip_allow_${suffix}"
            block_var="vps_ip_block_${suffix}"
            whitelist_block_vars+=("\$${block_var}")
            cat <<EOF >> "$conf_file"
geo \$${allow_var} {
    default 0;
EOF
            for range in $ranges; do
                echo "    ${range} 1;" >> "$conf_file"
            done
            cat <<EOF >> "$conf_file"
}

map "\$ssl_preread_server_name:\$${allow_var}" \$${block_var} {
    default 0;
    "${domain}:0" 1;
}

EOF
        done
    fi

    cat <<EOF >> "$conf_file"
map \$ssl_preread_server_name \$vps_sni_backend {
    ${PANEL_DOMAIN} caddy_backend;
EOF
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local site_domain
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -n "$site_domain" ]] && echo "    ${site_domain} caddy_backend;" >> "$conf_file"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i tcp_sni
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            tcp_sni="${TCP_ROUTE_SNIS[$tcp_i]}"
            [[ -n "$tcp_sni" ]] && echo "    ${tcp_sni} vps_tcp_route_${tcp_i}_backend;" >> "$conf_file"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i xray_route_sni
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            xray_route_sni="${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}"
            [[ -n "$xray_route_sni" ]] && echo "    ${xray_route_sni} vps_xray_route_${xray_route_i}_backend;" >> "$conf_file"
        done
    fi
    cat <<EOF >> "$conf_file"
    ${REALITY_SNI} xray_backend;
    default xray_backend;
}

EOF
    if [[ ${#whitelist_block_vars[@]} -gt 0 ]]; then
        local whitelist_key
        whitelist_key=$(printf '%s' "${whitelist_block_vars[@]}")
        guarded_backend_var="\$vps_sni_guarded_backend"
        cat <<EOF >> "$conf_file"
map "${whitelist_key}" \$vps_sni_ip_blocked {
    default 0;
    ~1 1;
}

map \$vps_sni_ip_blocked \$vps_sni_guarded_backend {
    1 vps_ip_reject_backend;
    default \$vps_sni_backend;
}

EOF
    fi

    cat <<EOF >> "$conf_file"

upstream caddy_backend {
    server ${caddy_backend};
}

upstream xray_backend {
    server ${xray_backend};
}

EOF
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i tcp_sni tcp_backend
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            tcp_sni="${TCP_ROUTE_SNIS[$tcp_i]}"
            [[ -n "$tcp_sni" ]] || continue
            tcp_backend=$(format_hostport "${TCP_ROUTE_ADDRS[$tcp_i]}" "${TCP_ROUTE_PORTS[$tcp_i]}")
            cat <<EOF >> "$conf_file"
upstream vps_tcp_route_${tcp_i}_backend {
    server ${tcp_backend};
}

EOF
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i xray_route_sni xray_route_backend
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            xray_route_sni="${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}"
            [[ -n "$xray_route_sni" ]] || continue
            xray_route_backend=$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}" "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")
            cat <<EOF >> "$conf_file"
upstream vps_xray_route_${xray_route_i}_backend {
    server ${xray_route_backend};
}

EOF
        done
    fi
    if [[ ${#whitelist_block_vars[@]} -gt 0 ]]; then
        cat <<'EOF' >> "$conf_file"
upstream vps_ip_reject_backend {
    server 127.0.0.1:9;
}

EOF
    fi

    cat <<EOF >> "$conf_file"
server {
${listen_directives}
    ssl_preread on;
    proxy_pass ${guarded_backend_var};
    proxy_connect_timeout 10s;
    proxy_timeout 24h;
}
EOF
    if [[ "$validate" == "yes" ]]; then
        nginx -t
    fi
}

ensure_caddy_local_base_config() {
    install_caddy_if_needed || return 1
    mkdir -p /etc/caddy/conf.d /etc/caddy/certs
    cp -f /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null || true
    cat <<'EOF' > /etc/caddy/Caddyfile
{
    auto_https off
}

import conf.d/*
EOF
}

write_caddy_panel_config() {
    local output_file="${1:-/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy}"
    local panel_backend
    local sub_backend
    local sub_match_paths
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "${SUB_URI_PATH:-/sub/}")
    CLASH_URI_PATH=$(normalize_path_prefix "${CLASH_URI_PATH:-/clash/}")
    sub_match_paths=$(caddy_path_match_tokens "$SUB_URI_PATH" "$CLASH_URI_PATH")
    cat <<EOF > "$output_file"
https://${PANEL_DOMAIN}:${CADDY_LISTEN_PORT} {
    bind ${CADDY_LISTEN_ADDR}
    tls /etc/caddy/certs/${PANEL_DOMAIN}.crt /etc/caddy/certs/${PANEL_DOMAIN}.key
    encode gzip

    @sub path ${sub_match_paths}
    handle @sub {
        reverse_proxy ${sub_backend} {
            header_up Host {http.request.host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
            header_up X-Real-IP {remote_host}
            header_up Range {http.request.header.Range}
            header_up If-Range {http.request.header.If-Range}
        }
    }

    handle {
        reverse_proxy ${panel_backend} {
            header_up Host {http.request.host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
            header_up X-Real-IP {remote_host}
            header_up Range {http.request.header.Range}
            header_up If-Range {http.request.header.If-Range}
        }
    }
}
EOF
}

write_caddy_site_config() {
    [[ ${#SITE_DOMAINS[@]} -eq 0 ]] && return 0
    local output_dir="${1:-/etc/caddy/conf.d}"
    local i site_domain site_backend
    for i in "${!SITE_DOMAINS[@]}"; do
        site_domain="${SITE_DOMAINS[$i]}"
        [[ -z "$site_domain" ]] && continue
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        cat <<EOF > "${output_dir}/${site_domain}.caddy"
https://${site_domain}:${CADDY_LISTEN_PORT} {
    bind ${CADDY_LISTEN_ADDR}
    tls /etc/caddy/certs/${site_domain}.crt /etc/caddy/certs/${site_domain}.key
    encode gzip

    reverse_proxy ${site_backend} {
        header_up Host {http.request.host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Port ${NGINX_LISTEN_PORT}
        header_up X-Real-IP {remote_host}
    }
}
EOF
    done
}

stage_and_validate_caddy_configs_for_single_443() {
    local plan_dir plan_conf_dir validate_log
    install_caddy_if_needed || return 1
    plan_dir=$(mktemp -d /tmp/vpso-caddy-plan.XXXXXX) || return 1
    chmod 700 "$plan_dir" 2>/dev/null || true
    plan_conf_dir="${plan_dir}/conf.d"
    validate_log="${plan_dir}/caddy-validate.log"
    mkdir -p "$plan_conf_dir" || return 1

    cat <<EOF > "${plan_dir}/Caddyfile"
{
    auto_https off
}

import ${plan_conf_dir}/*
EOF
    write_caddy_panel_config "${plan_conf_dir}/${PANEL_DOMAIN}.caddy"
    write_caddy_site_config "$plan_conf_dir"

    echo -e "${CYAN}▶ 正在预校验 Caddy 计划配置，暂不改动 /etc/caddy...${PLAIN}"
    if caddy validate --config "${plan_dir}/Caddyfile" >"$validate_log" 2>&1; then
        echo -e "${GREEN}✅ Caddy 计划配置校验通过。${PLAIN}"
        return 0
    fi

    echo -e "${RED}❌ Caddy 计划配置校验失败，已停止写入和切换。${PLAIN}"
    echo -e "${YELLOW}预检目录：${plan_dir}${PLAIN}"
    echo -e "${YELLOW}最近校验输出：${PLAIN}"
    tail -n 80 "$validate_log" 2>/dev/null || true
    return 1
}

apply_caddy_configs_for_single_443() {
    stage_and_validate_caddy_configs_for_single_443 || return 1
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    if ! caddy validate --config /etc/caddy/Caddyfile; then
        echo -e "${RED}❌ Caddy 实际配置校验失败，拒绝继续。${PLAIN}"
        return 1
    fi
}

issue_and_install_cert_for_domain() {
    local domain="$1"
    local cf_token="$2"
    local acme_bin="/root/.acme.sh/acme.sh"
    local acme_email
    acme_email=$(get_acme_account_email)
    if [[ ! -x "$acme_bin" ]]; then
        install_acme_sh "$acme_email" || return 1
    fi
    prepare_acme_account "$acme_bin" "$acme_email" || return 1
    mkdir -p /etc/caddy/certs /root/cert
    echo -e "${CYAN}▶ 正在为 ${domain} 申请 Cloudflare DNS 证书...${PLAIN}"
    issue_cf_dns_cert_with_retry "$domain" "$cf_token" "$acme_bin" || return 1
    "$acme_bin" --install-cert -d "$domain" --ecc \
        --fullchain-file "/etc/caddy/certs/${domain}.crt" \
        --key-file "/etc/caddy/certs/${domain}.key" \
        --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true; systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true" >/dev/null 2>&1 || return 1
    if id caddy >/dev/null 2>&1; then
        chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
        chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
    else
        chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
    fi
    ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
    ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
}

save_sni_stack_env() {
    mkdir -p /etc/vps-optimize
    local entry_mode site_domains_csv site_backend_addrs_csv site_backend_ports_csv
    local tcp_route_snis_csv tcp_route_addrs_csv tcp_route_ports_csv
    local sni_ip_whitelist_domains_csv sni_ip_whitelist_ranges_pipe
    entry_mode="${ENTRY_MODE:-$(get_entry_mode)}"
    case "$entry_mode" in
        "nginx_stream") entry_mode="nginx-stream" ;;
        "xray_fallback") entry_mode="xray-fallback" ;;
        "tcp_peek") entry_mode="tcp-peek" ;;
    esac
    case "$entry_mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") ;;
        *) entry_mode="nginx-stream" ;;
    esac
    site_domains_csv=$(IFS=','; echo "${SITE_DOMAINS[*]}")
    site_backend_addrs_csv=$(IFS=','; echo "${SITE_BACKEND_ADDRS[*]}")
    site_backend_ports_csv=$(IFS=','; echo "${SITE_BACKEND_PORTS[*]}")
    tcp_route_snis_csv=$(IFS=','; echo "${TCP_ROUTE_SNIS[*]}")
    tcp_route_addrs_csv=$(IFS=','; echo "${TCP_ROUTE_ADDRS[*]}")
    tcp_route_ports_csv=$(IFS=','; echo "${TCP_ROUTE_PORTS[*]}")
    sni_ip_whitelist_domains_csv=$(IFS=','; echo "${SNI_IP_WHITELIST_DOMAINS[*]}")
    sni_ip_whitelist_ranges_pipe=$(IFS='|'; echo "${SNI_IP_WHITELIST_RANGES[*]}")
    cat <<EOF > /etc/vps-optimize/sni-stack.env
ENTRY_MODE='${entry_mode}'
PANEL_DOMAIN='${PANEL_DOMAIN}'
SITE_DOMAIN='${SITE_DOMAINS[0]:-}'
SITE_DOMAINS_CSV='${site_domains_csv}'
REALITY_SNI='${REALITY_SNI}'
NGINX_LISTEN_ADDR='${NGINX_LISTEN_ADDR}'
NGINX_LISTEN_PORT='${NGINX_LISTEN_PORT}'
CADDY_LISTEN_ADDR='${CADDY_LISTEN_ADDR}'
CADDY_LISTEN_PORT='${CADDY_LISTEN_PORT}'
XRAY_LISTEN_ADDR='${XRAY_LISTEN_ADDR}'
XRAY_LISTEN_PORT='${XRAY_LISTEN_PORT}'
XRAY_FALLBACK_MAIN_SNI='${XRAY_FALLBACK_MAIN_SNI:-}'
XRAY_FALLBACK_MAIN_ADDR='${XRAY_FALLBACK_MAIN_ADDR:-}'
XRAY_FALLBACK_MAIN_PORT='${XRAY_FALLBACK_MAIN_PORT:-}'
PANEL_LISTEN_ADDR='${PANEL_LISTEN_ADDR}'
PANEL_LISTEN_PORT='${PANEL_LISTEN_PORT}'
PANEL_WEB_PATH='${PANEL_WEB_PATH}'
SUB_LISTEN_ADDR='${SUB_LISTEN_ADDR}'
SUB_LISTEN_PORT='${SUB_LISTEN_PORT}'
SUB_URI_PATH='${SUB_URI_PATH}'
CLASH_URI_PATH='${CLASH_URI_PATH}'
SITE_BACKEND_ADDR='${SITE_BACKEND_ADDRS[0]:-127.0.0.1}'
SITE_BACKEND_PORT='${SITE_BACKEND_PORTS[0]:-3000}'
SITE_BACKEND_ADDRS_CSV='${site_backend_addrs_csv}'
SITE_BACKEND_PORTS_CSV='${site_backend_ports_csv}'
TCP_ROUTE_SNIS_CSV='${tcp_route_snis_csv}'
TCP_ROUTE_ADDRS_CSV='${tcp_route_addrs_csv}'
TCP_ROUTE_PORTS_CSV='${tcp_route_ports_csv}'
SNI_IP_WHITELIST_DOMAINS_CSV='${sni_ip_whitelist_domains_csv}'
SNI_IP_WHITELIST_RANGES_PIPE='${sni_ip_whitelist_ranges_pipe}'
EOF
    chmod 600 /etc/vps-optimize/sni-stack.env
}

harden_single_443_firewall() {
    local yn ssh_port remove_ports port
    echo -e "${YELLOW}可选：防火墙只保留 SSH 与 Nginx 公网入口端口。${PLAIN}"
    echo -e "${YELLOW}提醒：若 3x-ui 仍监听 0.0.0.0:${PANEL_LISTEN_PORT}，脚本的“自动追加当前活动端口”功能可能再次放行它。${PLAIN}"
    read_trimmed yn "是否现在收紧防火墙？(y/n，默认 n): "
    is_yes "$yn" || return 0
    ssh_port=$(ss -lntp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | head -n1)
    ssh_port=${ssh_port:-22}
    remove_ports=("$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}" "${TCP_ROUTE_PORTS[@]}" "${XRAY_SNI_ROUTE_PORTS[@]}" "40000" "8443" "1443" "2096" "3000")
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
        ufw allow "${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || true
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
            ufw delete allow "${port}/udp" >/dev/null 2>&1 || true
        done
    elif command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable --now firewalld >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${NGINX_LISTEN_PORT}/tcp" >/dev/null 2>&1 || true
        for port in "${remove_ports[@]}"; do
            [[ "$port" == "$ssh_port" || "$port" == "$NGINX_LISTEN_PORT" ]] && continue
            firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --permanent --remove-port="${port}/udp" >/dev/null 2>&1 || true
        done
        firewall-cmd --reload >/dev/null 2>&1 || true
    else
        echo -e "${YELLOW}⚠️ 未检测到 ufw/firewalld，跳过防火墙收紧。${PLAIN}"
    fi
}

print_sni_stack_result() {
    local check_ports=()
    local check_regex=""
    local p entry_mode entry_label entry_listener
    entry_mode="${ENTRY_MODE:-nginx-stream}"
    entry_mode=$(normalize_entry_mode_name "$entry_mode" 2>/dev/null || echo "nginx-stream")
    case "$entry_mode" in
        "nginx-stream") entry_label="Nginx Stream 模式"; entry_listener="nginx" ;;
        "xray-fallback") entry_label="Xray Fallback 模式"; entry_listener="xray/3x-ui 主入站" ;;
        "tcp-peek") entry_label="TCP Peek + Splice 模式"; entry_listener="vpso-mux 分流器" ;;
        *) entry_label="$entry_mode"; entry_listener="$entry_mode" ;;
    esac
    check_ports=("$NGINX_LISTEN_PORT" "$CADDY_LISTEN_PORT" "$XRAY_LISTEN_PORT" "$PANEL_LISTEN_PORT" "$SUB_LISTEN_PORT" "${SITE_BACKEND_PORTS[@]}" "${TCP_ROUTE_PORTS[@]}" "${XRAY_SNI_ROUTE_PORTS[@]}")
    mapfile -t check_ports < <(printf '%s\n' "${check_ports[@]}" | grep -E '^[0-9]+$' | awk '!seen[$0]++')
    for p in "${check_ports[@]}"; do
        if [[ -z "$check_regex" ]]; then
            check_regex=":${p}([[:space:]]|$)"
        else
            check_regex="${check_regex}|:${p}([[:space:]]|$)"
        fi
    done

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}✅ 443 单入口分流配置完成${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "当前入口模式：${entry_label} (${entry_mode})"
    echo -e "${BOLD}一、以后从外面只访问这些地址${PLAIN}"
    echo -e "  面板入口：      https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "  普通订阅入口：  https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo：  https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "  网站/反代入口： https://${SITE_DOMAINS[$i]}/"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "  TCP/SNI 入站：  ${TCP_ROUTE_SNIS[$tcp_i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "  Xray 入站：     ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}:${NGINX_LISTEN_PORT} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}"
        done
    fi
    echo -e "  REALITY 端口：  ${NGINX_LISTEN_PORT}"
    echo -e ""
    echo -e "${YELLOW}不要从公网访问这些内部端口：${CADDY_LISTEN_PORT}/${XRAY_LISTEN_PORT}/${PANEL_LISTEN_PORT}/${SUB_LISTEN_PORT}/${SITE_BACKEND_PORTS[*]} ${TCP_ROUTE_PORTS[*]} ${XRAY_SNI_ROUTE_PORTS[*]}${PLAIN}"
    echo -e "${YELLOW}它们应该只给本机内部服务互相连接，不是浏览器入口。${PLAIN}"
    echo -e ""
    echo -e "${BOLD}二、3x-ui 面板设置建议${PLAIN}"
    echo -e "  面板监听地址：${PANEL_LISTEN_ADDR}"
    echo -e "  面板端口：    ${PANEL_LISTEN_PORT}"
    echo -e "  webBasePath： ${PANEL_WEB_PATH}"
    echo -e "  3.x 新安装 SSL 选项：Skip SSL / 不申请 SSL"
    echo -e "  2.x/旧配置面板证书路径/私钥路径：清空"
    echo -e "  Caddy 后端连接：http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "  Panel URL / Public URL / External URL：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "  Subscription URI Path：${SUB_URI_PATH}"
    echo -e "  Subscription External URL：https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo URI Path：${CLASH_URI_PATH}"
    echo -e "  Clash/Mihomo External URL：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "${YELLOW}  不建议使用 webBasePath=/，随机面板路径能降低被批量扫描命中的概率。${PLAIN}"
    echo -e "  2.x/旧配置订阅证书路径/私钥路径：清空"
    echo -e ""
    echo -e "${BOLD}三、Xray / 3x-ui REALITY 入站这样填${PLAIN}"
    echo -e "  入站监听地址 listen：${XRAY_LISTEN_ADDR}"
    echo -e "  入站监听端口 port：  ${XRAY_LISTEN_PORT}"
    echo -e "  协议 protocol：      VLESS"
    echo -e "  传输 network：       tcp"
    echo -e "  安全 security：      reality"
    echo -e "  REALITY dest：       ${REALITY_SNI}:443"
    echo -e "  serverNames：        ${REALITY_SNI}"
    echo -e "  SpiderX：            /"
    echo -e "  客户端连接地址：     你的服务器 IP 或解析到服务器的域名"
    echo -e "  客户端连接端口：     ${NGINX_LISTEN_PORT}"
    echo -e "  客户端 SNI/serverName：${REALITY_SNI}"
    echo -e "${YELLOW}  注意：REALITY 的 dest/serverNames 必须是外部真实站点，不要写面板域名。${PLAIN}"
    echo -e ""
    echo -e "${BOLD}四、常见错误怎么判断${PLAIN}"
    echo -e "  ERR_SSL_PROTOCOL_ERROR：通常是访问了内部端口，外部只访问 https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "  ERR_TOO_MANY_REDIRECTS：通常是 3.x 误启用 3x-ui SSL、2.x/旧配置证书路径没清空，或外部地址/路径配置不一致"
    echo -e "  HTTP 404：先检查访问路径是否等于 3x-ui 的 webBasePath，再检查 Caddy 是否反代到 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "  502 Bad Gateway：通常是 3x-ui 没启动、端口不对，或 3x-ui 后端仍是 HTTPS"
    echo -e ""
    echo -e "${BOLD}五、监听状态应该长这样${PLAIN}"
    echo -e "  ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_listener}"
    echo -e "  ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> caddy"
    echo -e "  ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT} -> xray"
    echo -e "  ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} -> 3x-ui"
    echo -e "  ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT} -> 3x-ui subscription"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "  ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]} -> ${SITE_DOMAINS[$i]} 网站后端"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "  ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]} -> ${TCP_ROUTE_SNIS[$tcp_i]} TCP/SNI 入站"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "  ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} Xray 入站"
        done
    fi
    echo -e ""
    echo -e "${BOLD}六、检查命令${PLAIN}"
    if [[ -n "$check_regex" ]]; then
        echo -e "  ss -lntp | grep -E '${check_regex}'"
    else
        echo -e "  ss -lntp"
    fi
    echo -e "  nginx -t"
    echo -e "  caddy validate --config /etc/caddy/Caddyfile"
    echo -e "  curl -I http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}/"
    echo -e "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}"
    echo -e "  openssl s_client -connect 服务器IP:${NGINX_LISTEN_PORT} -servername ${REALITY_SNI}"
    echo -e "  journalctl -u caddy -n 80 --no-pager"
    echo -e "  journalctl -u x-ui -u 3x-ui -n 80 --no-pager"
    echo -e ""
    case "$entry_mode" in
        "xray-fallback")
            echo -e "${RED}绝对不要做：Caddy 直接监听公网 443；3x-ui 面板、订阅服务或额外本地入站暴露公网；3.x 安装时启用 3x-ui SSL 或 2.x/旧配置证书路径未清空就跑 Web fallback；把 REALITY dest/serverNames 写成面板域名。${PLAIN}"
            ;;
        *)
            echo -e "${RED}绝对不要做：Caddy 直接监听公网 443；Xray/3x-ui 主入站直接占用公网 443；3x-ui 面板或新增本地入站暴露公网；3.x 安装时启用 3x-ui SSL 或 2.x/旧配置证书路径未清空就跑 443；把 REALITY dest/serverNames 写成面板域名。${PLAIN}"
            ;;
    esac
}

apply_sni_stack_runtime_config() {
    local backup_dir current_mode
    current_mode="${ENTRY_MODE:-$(get_entry_mode)}"
    current_mode=$(normalize_entry_mode_name "$current_mode" 2>/dev/null || echo "nginx-stream")

    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    guard_current_ssh_not_on_entry_port "重新应用 443 单入口运行参数" || return 1
    check_entry_mode_dependencies "$current_mode" || { rollback_sni_stack_after_failure "$backup_dir" "入口模式依赖检查失败"; return 1; }
    preflight_entry_mode_before_cutover "$current_mode" || { echo -e "${RED}❌ 入口模式 ${current_mode} 预检失败，公网 443 未重新应用。${PLAIN}"; return 1; }
    stop_public_443_entry_services_for_target "$current_mode" || { rollback_sni_stack_after_failure "$backup_dir" "停止旧公网 443 入口服务失败"; return 1; }
    apply_entry_mode_by_name "$current_mode" "$backup_dir" || { rollback_sni_stack_after_failure "$backup_dir" "入口模式 ${current_mode} 应用失败"; return 1; }
    ENTRY_MODE="$current_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$current_mode")" "$backup_dir"
    generate_caddy_cf_manifest
}
