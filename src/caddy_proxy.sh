# shellcheck shell=bash
# Ordinary Caddy/Nginx reverse proxy workflows outside the Port 443 Reuse stack.

write_caddy_reverse_proxy_conf() {
    local domain="$1"
    local backend_addr="$2"
    local port="$3"
    local is_https="$4"
    local conf_file="$5"
    local ip_whitelist_ranges="${6:-}"
    local backend_hostport
    backend_hostport=$(format_hostport "$backend_addr" "$port")

    if is_yes "$is_https"; then
        cat <<EOF > "$conf_file"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy https://${backend_hostport} {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
    else
        cat <<EOF > "$conf_file"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy ${backend_hostport}
}
EOF
    fi
}

validate_caddy_config_with_log() {
    local log_file="$1"
    caddy validate --config /etc/caddy/Caddyfile >"$log_file" 2>&1
}

print_caddy_validate_failure() {
    local title="$1"
    local log_file="$2"
    local generated_conf="${3:-}"

    echo -e "${RED}❌ ${title}${PLAIN}"
    if [[ -s "$log_file" ]]; then
        echo -e "$(localized_text "${YELLOW}Caddy 校验错误：${PLAIN}" "${YELLOW}Caddy Verification error:${PLAIN}" "${YELLOW}Caddy Ошибка проверки:${PLAIN}")"
        tail -n 40 "$log_file" 2>/dev/null || true
        echo -e "$(localized_text "${YELLOW}完整日志：${log_file}${PLAIN}" "${YELLOW}Complete log: ${log_file}${PLAIN}" "${YELLOW}полный журнал: ${log_file}${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}Caddy 未返回详细错误，请手动执行：caddy validate --config /etc/caddy/Caddyfile${PLAIN}" "${YELLOW}Caddy does not return detailed errors, please execute manually: caddy validate --config /etc/caddy/Caddyfile${PLAIN}" "${YELLOW}Caddy не возвращает подробные ошибки, выполните вручную: caddy validate --config /etc/caddy/Caddyfile${PLAIN}")"
    fi
    if [[ -n "$generated_conf" && -f "$generated_conf" ]]; then
        echo -e "$(localized_text "${YELLOW}本次新增配置：${generated_conf}${PLAIN}" "${YELLOW}This new configuration: ${generated_conf}${PLAIN}" "${YELLOW}Эта новая конфигурация: ${generated_conf}.${PLAIN}")"
        sed -n '1,80p' "$generated_conf" 2>/dev/null || true
    fi
}

func_caddy_add_reverse_proxy() {
    echo -e "$(localized_text "${CYAN}▶ 正在检查并安装 Caddy...${PLAIN}" "${CYAN}▶ Checking and installing Caddy...${PLAIN}" "${CYAN}▶ Проверка и установка Caddy...${PLAIN}")"
    if ! install_caddy_if_needed; then
        echo -e "$(localized_text "${RED}❌ Caddy 安装失败，请检查软件源、网络或系统版本。${PLAIN}" "${RED}❌ Caddy The installation failed, please check the software source, network or system version.${PLAIN}" "${RED}❌ Caddy Не удалось выполнить установку. Проверьте источник программного обеспечения, версию сети или системы.${PLAIN}")"
        return 1
    fi
    if ! ensure_caddy_module_layout; then
        echo -e "$(localized_text "${RED}❌ Caddy 配置目录初始化失败，请检查 /etc/caddy 权限。${PLAIN}" "${RED}❌ Caddy Configuration directory initialization failed, please check /etc/caddy permissions.${PLAIN}" "${RED}❌ Caddy Не удалось инициализировать каталог конфигурации, проверьте разрешения /etc/caddy.${PLAIN}")"
        return 1
    fi

    local validate_log
    validate_log=$(mktemp /tmp/vps-caddy-validate.XXXXXX.log) || return 1
    if ! validate_caddy_config_with_log "$validate_log"; then
        print_caddy_validate_failure "$(localized_text "当前 Caddy 配置校验失败，未写入新增反代。" "The current Caddy configuration validation failed and the new reverse proxy was not written." "Текущая проверка конфигурации Caddy не удалась, и новое обратный прокси не было записано.")" "$validate_log"
        echo -e "$(localized_text "${YELLOW}请先修复 /etc/caddy/Caddyfile 或 /etc/caddy/conf.d/*.caddy 后再添加域名。${PLAIN}" "${YELLOW}Please repair /etc/caddy/Caddyfile or /etc/caddy/conf.d/*.caddy first and then add the domain.${PLAIN}" "${YELLOW}Сначала исправьте /etc/caddy/Caddyfile или /etc/caddy/conf.d/*.caddy, а затем добавьте доменное имя.${PLAIN}")"
        return 1
    fi

    local domain domain_input backend_addr port is_https
    read_trimmed domain_input "$(localized_text "请输入解析后的域名 (如 panel.site.com): " "Please enter the resolved domain (such as panel.site.com):" "Введите разрешенное доменное имя (например, Panel.site.com):")"
    read_trimmed port "$(localized_text "请输入面板本地映射端口 (如 40000): " "Please enter the panel's local mapping port (such as 40000):" "Пожалуйста, введите локальный порт отображения панели (например, 40000):")"
    backend_addr=$(ask_with_default "$(localized_text "后端地址" "Backend address" "Внутренний адрес")" "127.0.0.1")
    backend_addr=$(normalize_backend_addr_input "$backend_addr")
    domain=$(normalize_domain_input "$domain_input")

    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。${PLAIN}" "${RED}❌ Port format error: ${port}, the port must be 1-65535.${PLAIN}" "${RED}❌ Ошибка формата порта: ${port}, порт должен быть 1-65535.${PLAIN}")"
        return 1
    fi

    if ! is_valid_backend_addr "$backend_addr"; then
        echo -e "$(localized_text "${RED}❌ 后端地址无效：${backend_addr}${PLAIN}" "${RED}❌ Invalid backend address: ${backend_addr}${PLAIN}" "${RED}❌ Неверный внутренний адрес: ${backend_addr}.${PLAIN}")"
        return 1
    fi

    local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
    if grep -q "^[[:space:]]*$domain" /etc/caddy/Caddyfile 2>/dev/null || [[ -e "$domain_conf" ]]; then
        echo -e "$(localized_text "${RED}❌ 错误：已存在该域名的配置块！请先清理或更换域名后再添加。${PLAIN}" "${RED}❌ Error: The configuration block for this domain already exists! Please clean or change the domain before adding it.${PLAIN}" "${RED}❌ Ошибка: блок конфигурации для этого доменного имени уже существует! Пожалуйста, очистите или измените доменное имя перед его добавлением.${PLAIN}")"
        return 1
    fi

    read_trimmed is_https "$(localized_text "❓ 后端面板是否开启了自带的 SSL 证书？(Y/n): " "❓ Is the built-in SSL certificate enabled on the backend panel? (Y/n):" "❓ Включен ли встроенный сертификат SSL на внутренней панели? (Да/Нет):")"

    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed enable_ip_whitelist "$(localized_text "❓ 是否只允许指定 IP/CIDR 访问该域名？(y/N，默认 N): " "❓ Restrict this domain to specified IP/CIDR ranges? (y/N, default N): " "❓ Ограничить доступ к домену указанными IP/CIDR? (y/N, по умолчанию N): ")"
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单，避免把自己挡在外面。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that you have joined the whitelist to avoid blocking yourself out.${PLAIN}" "${YELLOW}Текущий IP-адрес источника SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что вы присоединились к белому списку, чтобы не заблокировать себя.${PLAIN}")"
        read_trimmed ip_whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消本次反代配置。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format. This reverse proxy configuration has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат. Эта конфигурация обратного прокси-сервера была отменена.${PLAIN}")"
            return 1
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi

    local backup_file="/etc/caddy/Caddyfile.bak_$(date +%s)"
    [[ -f /etc/caddy/Caddyfile ]] && cp -p /etc/caddy/Caddyfile "$backup_file"

    write_caddy_reverse_proxy_conf "$domain" "$backend_addr" "$port" "$is_https" "$domain_conf" "$ip_whitelist_ranges"

    echo -e "$(localized_text "${CYAN}▶ 正在校验 Caddy 配置文件...${PLAIN}" "${CYAN}▶ Verifying Caddy configuration file...${PLAIN}" "${CYAN}▶ Проверка файла конфигурации Caddy...${PLAIN}")"
    if validate_caddy_config_with_log "$validate_log"; then
        if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ Caddy 反代配置已追加并生效！请访问 https://$domain${PLAIN}" "${GREEN}✅ Caddy reverse proxy configuration has been added and takes effect! Please visit https://$domain${PLAIN}" "${GREEN}✅ Конфигурация обратный прокси Caddy добавлена и вступила в силу! Пожалуйста, посетите https://$domain${PLAIN}")"
            [[ -n "$ip_whitelist_ranges" ]] && echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
            echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
        else
            echo -e "$(localized_text "${RED}❌ Caddy 配置校验通过，但服务重载失败，正在回滚...${PLAIN}" "${RED}❌ Caddy The configuration validation passed, but the service reload failed and is being rolled back...${PLAIN}" "${RED}❌ Caddy Проверка конфигурации прошла, но перезагрузка службы не удалась и выполняется откат...${PLAIN}")"
            [[ -f "$backup_file" ]] && mv "$backup_file" /etc/caddy/Caddyfile
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
            return 1
        fi
    else
        print_caddy_validate_failure "$(localized_text "写入新增反代后 Caddy 校验失败，正在自动回滚。" "After writing the new reverse proxy, Caddy verification failed and is being automatically rolled back." "После записи нового обратного прокси-сервера проверка Caddy не удалась, и выполняется автоматический откат.")" "$validate_log" "$domain_conf"
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
    echo -e "$(localized_text "${CYAN}▶ 未检测到 Nginx，正在安装...${PLAIN}" "${CYAN}▶ Nginx not detected, installing...${PLAIN}" "${CYAN}▶ Nginx не обнаружен, устанавливается...${PLAIN}")"
    if is_debian || is_redhat; then
        install_pkg nginx || return 1
    else
        echo -e "$(localized_text "${RED}❌ 当前系统暂不支持自动安装 Nginx。${PLAIN}" "${RED}❌ The current system does not support automatic installation of Nginx.${PLAIN}" "${RED}❌ Текущая система не поддерживает автоматическую установку Nginx.${PLAIN}")"
        return 1
    fi
    command -v nginx >/dev/null 2>&1
}

ensure_nginx_http_conf_d() {
    local nginx_conf="/etc/nginx/nginx.conf"
    mkdir -p /etc/nginx/conf.d || return 1
    [[ -f "$nginx_conf" ]] || { echo -e "$(localized_text "${RED}❌ 未找到 ${nginx_conf}。${PLAIN}" "${RED}❌ ${nginx_conf} not found.${PLAIN}" "${RED}❌ ${nginx_conf} не найден.${PLAIN}")"; return 1; }
    if grep -q '/etc/nginx/conf.d/\*.conf' "$nginx_conf" 2>/dev/null; then
        return 0
    fi
    if grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$nginx_conf" 2>/dev/null; then
        cp -p "$nginx_conf" "${nginx_conf}.bak_$(date +%s)" 2>/dev/null || true
        sed -i '/^[[:space:]]*http[[:space:]]*{/a\    include /etc/nginx/conf.d/*.conf;' "$nginx_conf"
        return 0
    fi
    echo -e "$(localized_text "${RED}❌ nginx.conf 中未找到 http {}，无法安全追加 conf.d include。${PLAIN}" "${RED}❌ http {} not found in nginx.conf, cannot safely append conf.d include.${PLAIN}" "${RED}❌ http {} не найден в nginx.conf, невозможно безопасно добавить включение conf.d.${PLAIN}")"
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

nginx_proxy_ipv6_enabled() {
    local if_inet6="${VPSO_PROC_NET_IF_INET6:-/proc/net/if_inet6}"
    local disable_ipv6="${VPSO_PROC_SYS_DISABLE_IPV6:-/proc/sys/net/ipv6/conf/all/disable_ipv6}"
    [[ -s "$if_inet6" && "$(cat "$disable_ipv6" 2>/dev/null || echo 1)" != "1" ]]
}

nginx_proxy_domain_exists() {
    local domain="$1"
    [[ -e "$(nginx_proxy_conf_path "$domain")" ]] && return 0
    grep -RqsE "server_name[[:space:]].*\\b${domain}\\b" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null
}

nginx_proxy_warn_if_single_entry_enabled() {
    if [[ -f /etc/vps-optimize/sni-stack.env || -f /etc/vps-optimize/443-engine.conf ]]; then
        echo -e "$(localized_text "${RED}❌ 已检测到 443端口复用配置。Nginx HTTPS 反代会抢占公网 443，已拒绝继续。${PLAIN}" "${RED}❌ Port 443 Reuse configuration detected. Nginx HTTPS The reverse proxy will seize public port 443 and has refused to continue.${PLAIN}" "${RED}❌ Обнаружена конфигурация повторного использования порта 443. Nginx HTTPS Обратный прокси-сервер задействует публичный порт 443 и отказывается продолжать работу.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请改用：主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代]。${PLAIN}" "${YELLOW}Please use: Main menu [19 Port 443 Reuse Manager] -> [8 Management Web domain/Reverse Proxy].${PLAIN}" "${YELLOW}Используйте: Главное меню [19 Управление повторным использованием порта 443] -> [8 Имя веб-домена управления/обратный прокси].${PLAIN}")"
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
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个旧 Nginx HTTPS 反代配置，避免抢占公网 443。${PLAIN}" "${YELLOW}⚠️ Already isolated ${moved} old Nginx HTTPS reverse proxy configuration to avoid seizing the public port 443.${PLAIN}" "${YELLOW}⚠️ Изолированный ${moved} старый Nginx HTTPS конфигурация обратного прокси-сервера, чтобы избежать захвата публичного порта 443.${PLAIN}")"
    fi
}

nginx_proxy_ensure_certificate() {
    local domain="$1"
    local cert_file="/etc/caddy/certs/${domain}.crt"
    local key_file="/etc/caddy/certs/${domain}.key"
    local reuse_cert CF_TOKEN verify_rc

    if [[ -s "$cert_file" && -s "$key_file" ]]; then
        read_trimmed reuse_cert "$(localized_text "检测到已有证书 ${cert_file}，是否复用？(Y/n，默认 yes): " "An existing certificate ${cert_file} has been detected. Do you want to reuse it? (Y/n, default yes):" "Обнаружен существующий сертификат ${cert_file}. Хотите ли вы использовать его повторно? (Да/нет, по умолчанию да):")"
        if ! is_no "$reuse_cert"; then
            echo -e "$(localized_text "${GREEN}✅ 已复用现有证书：${cert_file}${PLAIN}" "${GREEN}✅ Existing certificate has been reused: ${cert_file}${PLAIN}" "${GREEN}✅ Существующий сертификат был использован повторно: ${cert_file}.${PLAIN}")"
            return 0
        fi
    fi

    echo -e "$(localized_text "${YELLOW}Nginx 反代证书继续使用现有 acme.sh + Cloudflare DNS API 流程。${PLAIN}" "${YELLOW}The Nginx reverse certificate continues to use the existing acme.sh + Cloudflare DNS API process.${PLAIN}" "${YELLOW}Обратный сертификат Nginx продолжает использовать существующий процесс API acme.sh + Cloudflare DNS.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}证书将安装到 /etc/caddy/certs/${domain}.crt|key，并软链到 /root/cert/。${PLAIN}" "${YELLOW}The certificate will be installed to /etc/caddy/certs/${domain}.crt|key and symlinked to /root/cert/.${PLAIN}" "${YELLOW}Сертификат будет установлен в /etc/caddy/certs/${domain}.crt|key и программно связан с /root/cert/.${PLAIN}")"
    read_secret_trimmed CF_TOKEN "$(localized_text "请输入 Cloudflare API Token（需有该域名 DNS 编辑权限）: " "Please enter Cloudflare API Token (requires editing permission of the domain DNS):" "Пожалуйста, введите Cloudflare API Token (требуется разрешение на редактирование доменного имени DNS):")"
    if [[ -z "$CF_TOKEN" || ${#CF_TOKEN} -lt 20 ]]; then
        echo -e "$(localized_text "${RED}❌ Cloudflare Token 长度异常。${PLAIN}" "${RED}❌ Cloudflare Token length is abnormal.${PLAIN}" "${RED}❌ Cloudflare Неверная длина токена.${PLAIN}")"
        return 1
    fi
    verify_cf_token_online "$CF_TOKEN"
    verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ Cloudflare Token 校验通过。${PLAIN}" "${GREEN}✅ Cloudflare Token verification passed.${PLAIN}" "${GREEN}✅ Cloudflare Проверка токена пройдена.${PLAIN}")"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}" "${YELLOW}⚠️ curl is not installed, skip online verification.${PLAIN}" "${YELLOW}⚠️ curl не установлен, пропустите онлайн-проверку.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ Cloudflare Token 在线校验失败。${PLAIN}" "${RED}❌ Cloudflare Token online verification failed.${PLAIN}" "${RED}❌ Cloudflare Онлайн-проверка токена не удалась.${PLAIN}")"
        return 1
    fi
    issue_and_install_cert_for_domain "$domain" "$CF_TOKEN" || return 1
    [[ -s "$cert_file" && -s "$key_file" ]] || { echo -e "$(localized_text "${RED}❌ 证书安装后仍缺失：${cert_file}|${key_file}${PLAIN}" "${RED}❌ The certificate is still missing after installation: ${cert_file}|${key_file}${PLAIN}" "${RED}❌ Сертификат по-прежнему отсутствует после установки: ${cert_file}|${key_file}${PLAIN}")"; return 1; }
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
    if nginx_proxy_ipv6_enabled; then
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
    echo -e "$(localized_text "${CYAN}▶ 正在配置 Nginx HTTPS 反代...${PLAIN}" "${CYAN}▶ Configuring Nginx HTTPS reverse proxy...${PLAIN}" "${CYAN}▶ Настройка обратного прокси-сервера Nginx HTTPS...${PLAIN}")"
    nginx_proxy_warn_if_single_entry_enabled || return 1
    local domain domain_input port is_https conf_file enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed domain_input "$(localized_text "请输入解析后的域名 (如 panel.example.com): " "Please enter the resolved domain (such as panel.example.com):" "Введите разрешенное доменное имя (например, Panel.example.com):")"
    read_trimmed port "$(localized_text "请输入本地后端端口 (如 40000): " "Please enter the local backend port (e.g. 40000):" "Введите локальный внутренний порт (например, 40000):")"
    domain=$(normalize_domain_input "$domain_input")

    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。${PLAIN}" "${RED}❌ Port format error: ${port}, the port must be 1-65535.${PLAIN}" "${RED}❌ Ошибка формата порта: ${port}, порт должен быть 1-65535.${PLAIN}")"
        return 1
    fi

    conf_file=$(nginx_proxy_conf_path "$domain")
    if nginx_proxy_domain_exists "$domain"; then
        echo -e "$(localized_text "${RED}❌ Nginx 中已存在该域名配置，请先清理或更换域名后再添加。${PLAIN}" "${RED}The domain configuration already exists in ❌ Nginx. Please clean or change the domain before adding it.${PLAIN}" "${RED}Конфигурация доменного имени уже существует в ❌ Nginx. Пожалуйста, очистите или измените доменное имя перед его добавлением.${PLAIN}")"
        return 1
    fi
    if [[ -e "/etc/caddy/conf.d/${domain}.caddy" ]] || grep -q "^[[:space:]]*$domain" /etc/caddy/Caddyfile 2>/dev/null; then
        echo -e "$(localized_text "${RED}❌ Caddy 中已存在该域名配置，请避免同一域名同时由 Caddy 和 Nginx 接管。${PLAIN}" "${RED}❌ This domain configuration already exists in Caddy. Please avoid the same domain being taken over by Caddy and Nginx at the same time.${PLAIN}" "${RED}❌ Эта конфигурация доменного имени уже существует в Caddy. Пожалуйста, избегайте одновременного захвата одного и того же доменного имени Caddy и Nginx.${PLAIN}")"
        return 1
    fi

    read_trimmed is_https "$(localized_text "后端是否是自带证书的 HTTPS 服务？(Y/n，默认 y): " "Is the backend a HTTPS service with its own certificate? (Y/n, default y):" "Является ли бэкенд службой HTTPS с собственным сертификатом? (Да/нет, по умолчанию y):")"
    read_trimmed enable_ip_whitelist "$(localized_text "是否只允许指定 IP/CIDR 访问该 Nginx 域名？(y/N，默认 N): " "Restrict this Nginx domain to specified IP/CIDR ranges? (y/N, default N): " "Ограничить доступ к домену Nginx указанными IP/CIDR? (y/N, по умолчанию N): ")"
    if is_yes "$enable_ip_whitelist"; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单，避免把自己挡在外面。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that you have joined the whitelist to avoid blocking yourself out.${PLAIN}" "${YELLOW}Текущий IP-адрес источника SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что вы присоединились к белому списку, чтобы не заблокировать себя.${PLAIN}")"
        read_trimmed ip_whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消本次反代配置。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format. This reverse proxy configuration has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат. Эта конфигурация обратного прокси-сервера была отменена.${PLAIN}")"
            return 1
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi
    nginx_proxy_ensure_certificate "$domain" || return 1
    install_nginx_http_if_needed || { echo -e "$(localized_text "${RED}❌ Nginx 安装失败，请检查软件源、网络或系统版本。${PLAIN}" "${RED}❌ Nginx The installation failed, please check the software source, network or system version.${PLAIN}" "${RED}❌ Nginx Не удалось выполнить установку. Проверьте источник программного обеспечения, версию сети или системы.${PLAIN}")"; return 1; }
    ensure_nginx_http_conf_d || return 1
    harden_nginx_public_errors
    write_nginx_proxy_map_conf || return 1
    write_nginx_reverse_proxy_conf "$domain" "$port" "$is_https" "$conf_file" "$ip_whitelist_ranges" || return 1

    echo -e "$(localized_text "${CYAN}▶ 正在校验 Nginx 配置...${PLAIN}" "${CYAN}▶ Verifying Nginx configuration...${PLAIN}" "${CYAN}▶ Проверка конфигурации Nginx...${PLAIN}")"
    if ! nginx -t >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ Nginx 配置校验失败，已隔离新增配置。${PLAIN}" "${RED}❌ Nginx The configuration validation failed and the new configuration has been isolated.${PLAIN}" "${RED}❌ Nginx Проверка конфигурации не удалась, и новая конфигурация была изолирована.${PLAIN}")"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1 || true
        nginx -t
        return 1
    fi

    systemctl enable nginx >/dev/null 2>&1 || true
    if systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1; then
        echo -e "$(localized_text "${GREEN}✅ Nginx 反代已生效：https://${domain}${PLAIN}" "${GREEN}✅ Nginx reverse proxy has taken effect: https://${domain}${PLAIN}" "${GREEN}✅ Nginx обратный прокси вступила в силу: https://${domain}${PLAIN}")"
        echo -e "$(localized_text "${GREEN}✅ 后端：127.0.0.1:${port}${PLAIN}" "${GREEN}✅ Backend: 127.0.0.1:${port}${PLAIN}" "${GREEN}вещество: 127.0.0.1:${port}${PLAIN}")"
        [[ -n "$ip_whitelist_ranges" ]] && echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
        echo -e "$(localized_text "${CYAN}配置文件：${conf_file}${PLAIN}" "${CYAN}Configuration file: ${conf_file}${PLAIN}" "${CYAN}Файл конфигурации : ${conf_file}${PLAIN}")"
        echo -e "$(localized_text "${CYAN}证书路径：/etc/caddy/certs/${domain}.crt 和 /etc/caddy/certs/${domain}.key${PLAIN}" "${CYAN}Certificate path: /etc/caddy/certs/${domain}.crt and /etc/caddy/certs/${domain}.key${PLAIN}" "${CYAN}Путь сертификата : /etc/caddy/certs/${domain}.crt и /etc/caddy/certs/${domain}.key.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ Nginx 配置校验通过，但 reload/restart 失败。可能是 Caddy、443端口复用或其他服务占用了 80/443。${PLAIN}" "${RED}❌ Nginx configuration validation passed, but reload/restart failed. It may be that Caddy, Port 443 Reuse or other services occupy 80/443.${PLAIN}" "${RED}❌ Nginx Проверка конфигурации пройдена, но перезагрузка/перезапуск не удалось. Возможно, Caddy, повторное использование порта 443 или другие службы занимают 80/443.${PLAIN}")"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1 || true
        return 1
    fi
}

func_nginx_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🛡️ Nginx 后端 HTTPS 跳过证书校验${PLAIN}" "${BOLD}🛡️ Nginx backend HTTPS skip certificate verification${PLAIN}" "${BOLD}🛡️ Nginx бэкенд HTTPS пропустить проверку сертификата${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    nginx_proxy_warn_if_single_entry_enabled || return 1

    local domain domain_input port conf_file backup_file ip_whitelist_ranges
    read_trimmed domain_input "$(localized_text "请输入要设置的域名 (如 panel.example.com): " "Please enter the domain you want to set (such as panel.example.com):" "Введите доменное имя, которое вы хотите установить (например, Panel.example.com):")"
    read_trimmed port "$(localized_text "请输入 HTTPS 后端本地端口 (如 40000): " "Please enter the HTTPS backend local port (e.g. 40000):" "Пожалуйста, введите локальный порт HTTPS (например, 40000):")"
    domain=$(normalize_domain_input "$domain_input")
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        return 1
    fi
    if ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}❌ 端口格式错误：${port}，端口必须是 1-65535。${PLAIN}" "${RED}❌ Port format error: ${port}, the port must be 1-65535.${PLAIN}" "${RED}❌ Ошибка формата порта: ${port}, порт должен быть 1-65535.${PLAIN}")"
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
        cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; return 1; }
        ip_whitelist_ranges=$(nginx_proxy_whitelist_ranges_from_conf "$conf_file")
        echo -e "$(localized_text "${CYAN}已备份现有配置：${backup_file}${PLAIN}" "${CYAN}Has backed up the existing configuration: ${backup_file}${PLAIN}" "${CYAN}создал резервную копию существующей конфигурации: ${backup_file}.${PLAIN}")"
    else
        ip_whitelist_ranges=""
    fi

    write_nginx_reverse_proxy_conf "$domain" "$port" "y" "$conf_file" "$ip_whitelist_ranges" || return 1
    if nginx -t >/dev/null 2>&1; then
        if systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ Nginx 已设置为 HTTPS 后端并跳过后端证书校验：${domain} -> https://127.0.0.1:${port}${PLAIN}" "${GREEN}✅ Nginx has been set as HTTPS backend and skips backend certificate verification: ${domain} -> https://127.0.0.1:${port}${PLAIN}" "${GREEN}✅ Nginx установлен как бэкэнд HTTPS и пропускает проверку сертификата бэкенда: ${domain} -> https://127.0.0.1:${port}${PLAIN}")"
            [[ -n "$ip_whitelist_ranges" ]] && echo -e "$(localized_text "${GREEN}✅ 已保留 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Reserved IP whitelist: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список зарезервированных IP-адресов: ${ip_whitelist_ranges}${PLAIN}")"
        else
            echo -e "$(localized_text "${RED}❌ Nginx 校验通过，但 reload/restart 失败。${PLAIN}" "${RED}❌ Nginx The verification passed, but the reload/restart failed.${PLAIN}" "${RED}❌ Nginx Проверка пройдена, но перезагрузка/перезапуск не удались.${PLAIN}")"
            [[ -n "$backup_file" && -f "$backup_file" ]] && cp -p "$backup_file" "$conf_file"
            return 1
        fi
    else
        echo -e "$(localized_text "${RED}❌ Nginx 配置校验失败，正在回滚。${PLAIN}" "${RED}❌ Nginx configuration validation failed and is being rolled back.${PLAIN}" "${RED}❌ Nginx Проверка конфигурации не удалась, и выполняется откат.${PLAIN}")"
        [[ -n "$backup_file" && -f "$backup_file" ]] && cp -p "$backup_file" "$conf_file"
        nginx -t
        return 1
    fi
}

func_proxy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🛡️ 后端 HTTPS 跳过证书校验${PLAIN}" "${BOLD}🛡️ Backend HTTPS Skip certificate verification${PLAIN}" "${BOLD}🛡️ бэкенд HTTPS Пропустить проверку сертификата${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}  1. Caddy 跳过后端证书校验${PLAIN}" "${GREEN}1. Caddy skips back-end certificate verification${PLAIN}" "${GREEN}1. Caddy пропускает внутреннюю проверку сертификата${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. Nginx 跳过后端证书校验${PLAIN}" "${GREEN}2. Nginx skips back-end certificate verification${PLAIN}" "${GREEN}2. Nginx пропускает внутреннюю проверку сертификата${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    local choice
    read_trimmed choice "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"
    case "$choice" in
        1) func_caddy_add_insecure ;;
        2) func_nginx_add_insecure ;;
        0|q|Q|"") echo -e "$(localized_text "${BLUE}已取消。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")" ;;
        *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")" ;;
    esac
}

func_nginx_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔐 Nginx 域名 IP 白名单${PLAIN}" "${BOLD}🔐 Nginx domain IP whitelist${PLAIN}" "${BOLD}🔐 Nginx доменное имя Белый список IP-адресов${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}适用于未启用 443端口复用、由 Nginx HTTPS 反代直接对外服务的域名。${PLAIN}" "${YELLOW}Suitable for domains that do not enable the Port 443 Reuse and are directly served externally by the Nginx HTTPS reverse proxy.${PLAIN}" "${YELLOW}подходит для доменных имен, которые не поддерживают повторное использование порта 443 и обслуживаются непосредственно извне обратным прокси-сервером Nginx HTTPS.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果该域名已接入 443端口复用，请用主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]，不要在 Nginx HTTP 层限制。${PLAIN}" "${YELLOW}If the domain has been connected to Port 443 Reuse, please use the main menu [19 Port 443 Reuse Manager] -> [8 Manage Web domain/reverse proxy] -> [5 Manage domain IP whitelist], do not limit it at the Nginx HTTP layer.${PLAIN}" "${YELLOW}Если доменное имя подключено к повторном использовании порта 443, используйте главное меню [19 Управление повторным использованием порта 443] -> [8 Управление именем веб-домена/обратным прокси] -> [5 Управление белым списком IP-адресов доменного имени] и не ограничивайте его на уровне Nginx HTTP.${PLAIN}")"
    echo -e "------------------------------------------------"

    local domain domain_input conf_file action backup_file
    read_trimmed domain_input "$(localized_text "请输入要管理的域名 (如 panel.example.com): " "Please enter the domain you want to manage (eg panel.example.com):" "Пожалуйста, введите доменное имя, которым вы хотите управлять (например, Panel.example.com):")"
    domain=$(normalize_domain_input "$domain_input")
    if ! is_valid_domain "$domain"; then
        print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
        return 1
    fi
    conf_file=$(nginx_proxy_conf_path "$domain")
    if [[ ! -f "$conf_file" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 ${conf_file}。该入口只管理脚本创建的 Nginx HTTPS 反代配置。${PLAIN}" "${RED}❌ ${conf_file} not found. This entry only manages the Nginx HTTPS reverse proxy configuration created by the script.${PLAIN}" "${RED}❌ ${conf_file} не найден. Эта запись управляет только конфигурацией обратный прокси Nginx HTTPS, созданной сценарием.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "当前配置文件：${conf_file}" "Current configuration file: ${conf_file}" "Текущий файл конфигурации: ${conf_file}.")"
    if grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
        echo -e "$(localized_text "${YELLOW}当前状态：已启用脚本管理的 IP 白名单。${PLAIN}" "${YELLOW}Current status: IP whitelist for script management is enabled.${PLAIN}" "${YELLOW}Текущее состояние: белый список IP-адресов для управления сценариями включен.${PLAIN}")"
        echo -e "$(localized_text "当前白名单：$(nginx_proxy_whitelist_ranges_from_conf "$conf_file")" "Current whitelist: $(nginx_proxy_whitelist_ranges_from_conf \"$conf_file\")" "Текущий белый список: $(nginx_proxy_whitelist_ranges_from_conf \"$conf_file\").")"
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
                return 1
            fi
            append_vps_public_ips_to_whitelist ip_whitelist_array
            ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
            cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; return 1; }
            if insert_nginx_ip_whitelist_block "$conf_file" "$ip_whitelist_ranges" && nginx -t >/dev/null 2>&1; then
                if systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1; then
                    echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 Nginx IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Nginx IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Nginx Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
                    echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Nginx 重载失败，正在回滚...${PLAIN}" "${RED}❌ Nginx Reload failed, rolling back...${PLAIN}" "${RED}❌ Nginx Ошибка перезагрузки, откат...${PLAIN}")"
                    cp -p "$backup_file" "$conf_file"
                    systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
                    return 1
                fi
            else
                echo -e "$(localized_text "${RED}❌ 写入后 Nginx 校验失败，正在回滚...${PLAIN}" "${RED}❌ After writing Nginx verification failed, rolling back...${PLAIN}" "${RED}❌ После записи Nginx проверка не удалась, откат...${PLAIN}")"
                cp -p "$backup_file" "$conf_file"
                nginx -t
                return 1
            fi
            ;;
        2)
            if ! grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
                echo -e "$(localized_text "${BLUE}该域名没有脚本管理的白名单块，无需清除。${PLAIN}" "${BLUE}This domain does not have a script-managed whitelist block and does not need to be cleared.${PLAIN}" "${BLUE}Это доменное имя не имеет блока белого списка, управляемого сценарием, и его не нужно очищать.${PLAIN}")"
                return 0
            fi
            cp -p "$conf_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消。${PLAIN}" "${RED}❌ Backup failed and has been cancelled.${PLAIN}" "${RED}❌ Резервное копирование не выполнено и было отменено.${PLAIN}")"; return 1; }
            if strip_nginx_ip_whitelist_block "$conf_file" && nginx -t >/dev/null 2>&1; then
                systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ 已清除 ${domain} 的 Nginx IP 白名单。${PLAIN}" "${GREEN}✅ The Nginx IP whitelist of ${domain} has been cleared.${PLAIN}" "${GREEN}. Белый список IP-адресов Nginx для ${domain} очищен.${PLAIN}")"
                echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
            else
                echo -e "$(localized_text "${RED}❌ 清除后 Nginx 校验失败，正在回滚...${PLAIN}" "${RED}❌ After clearing Nginx Verification failed, rolling back...${PLAIN}" "${RED}❌ После очистки Nginx проверка не удалась, откат...${PLAIN}")"
                cp -p "$backup_file" "$conf_file"
                return 1
            fi
            ;;
        0|q|Q|"")
            echo -e "$(localized_text "${BLUE}已取消。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 无效操作。${PLAIN}" "${RED}❌ Invalid operation.${PLAIN}" "${RED}❌ Недопустимая операция.${PLAIN}")"
            ;;
    esac
}

func_proxy_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔐 域名 IP 白名单（Caddy / Nginx）${PLAIN}" "${BOLD}🔐 domain IP whitelist (Caddy / Nginx)${PLAIN}" "${BOLD}🔐 Белый список IP-адресов доменных имен (Caddy / Nginx)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}  1. Caddy 域名 IP 白名单${PLAIN}" "${GREEN}1. Caddy domain IP whitelist${PLAIN}" "${GREEN}1. Caddy доменное имя Белый список IP-адресов${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. Nginx 域名 IP 白名单${PLAIN}" "${GREEN}2. Nginx domain IP whitelist${PLAIN}" "${GREEN}2. Nginx доменное имя Белый список IP-адресов${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    local choice
    read_trimmed choice "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"
    case "$choice" in
        1) func_caddy_manage_ip_whitelist ;;
        2) func_nginx_manage_ip_whitelist ;;
        0|q|Q|"") echo -e "$(localized_text "${BLUE}已取消。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")" ;;
        *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")" ;;
    esac
}

func_nginx_clear_proxy_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧹 清空 Nginx HTTPS 反代配置${PLAIN}" "${BOLD}🧹 Clear Nginx HTTPS reverse proxy configuration${PLAIN}" "${BOLD}🧹 Очистить Nginx HTTPS Конфигурация обратного прокси${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}只隔离 VPS-Optimize 创建的 /etc/nginx/conf.d/vps_proxy_*.conf 和 00-vps-proxy-map.conf。${PLAIN}" "${YELLOW}Only isolates /etc/nginx/conf.d/vps_proxy_*.conf and 00-vps-proxy-map.conf created by VPS-Optimize.${PLAIN}" "${YELLOW}изолирует только /etc/nginx/conf.d/vps_proxy_*.conf и 00-vps-proxy-map.conf, созданные VPS-Optimize.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}不会清理 /etc/nginx/stream.d，也不会影响 443端口复用配置。${PLAIN}" "${YELLOW}Will not clean up /etc/nginx/stream.d, nor will it affect the Port 443 Reuse configuration.${PLAIN}" "${YELLOW}не очистит /etc/nginx/stream.d и не повлияет на конфигурацию с повторным использованием порта 443.${PLAIN}")"
    echo -e "------------------------------------------------"

    local -a files=()
    local conf_file backup_dir moved=0
    for conf_file in /etc/nginx/conf.d/vps_proxy_*.conf /etc/nginx/conf.d/00-vps-proxy-map.conf; do
        [[ -f "$conf_file" ]] && files+=("$conf_file")
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${BLUE}未检测到脚本创建的 Nginx HTTPS 反代配置。${PLAIN}" "${BLUE}Did not detect the Nginx HTTPS reverse proxy configuration created by the script.${PLAIN}" "${BLUE}не обнаружил конфигурацию обратный прокси Nginx HTTPS, созданную сценарием.${PLAIN}")"
        return 0
    fi
    printf '  - %s\n' "${files[@]}"
    if ! confirm_danger "$(localized_text "清空 Nginx HTTPS 反代配置" "Clear Nginx HTTPS reverse proxy configuration" "Очистить конфигурацию обратного прокси-сервера Nginx HTTPS.")" \
        "$(localized_text "上述 Nginx HTTPS 反代配置会被移入隔离目录，相关域名将不再由 Nginx 反代访问。" "The above Nginx HTTPS reverse proxy configuration will be moved to the isolation directory, and the related domains will no longer be accessed by Nginx reverse proxy." "Вышеупомянутая конфигурация обратный прокси Nginx HTTPS будет перемещена в каталог изоляции, и соответствующие доменные имена больше не будут доступны для обратный прокси Nginx.")" \
        "$(localized_text "从隔离目录 /etc/vps-optimize/quarantine/nginx-proxy 手动移回对应文件后执行 nginx -t && systemctl reload nginx。" "Manually move the corresponding files back from the isolation directory /etc/vps-optimize/quarantine/nginx-proxy and execute nginx -t && systemctl reload nginx." "Вручную переместите соответствующие файлы обратно из каталога изоляции /etc/vps-optimize/quarantine/nginx-proxy и выполните nginx -t && systemctl reload nginx.")"; then
        echo -e "$(localized_text "${BLUE}已取消清空操作。${PLAIN}" "${BLUE}The clearing operation has been canceled.${PLAIN}" "${BLUE}Операция очистки была отменена.${PLAIN}")"
        return 0
    fi

    backup_dir="/etc/vps-optimize/backups/nginx-proxy-clear_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    for conf_file in "${files[@]}"; do
        cp -p "$conf_file" "$backup_dir/$(basename "$conf_file")" 2>/dev/null || true
        if quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/nginx-proxy" >/dev/null 2>&1; then
            moved=$((moved + 1))
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 隔离失败：${conf_file}${PLAIN}" "${YELLOW}⚠️ Isolation failed: ${conf_file}${PLAIN}" "${YELLOW}⚠️ Сбой изоляции: ${conf_file}${PLAIN}")"
        fi
    done
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
        echo -e "$(localized_text "${GREEN}✅ 已隔离 ${moved} 个 Nginx HTTPS 反代配置。${PLAIN}" "${GREEN}✅ ${moved} Nginx HTTPS reverse proxy configurations have been isolated.${PLAIN}" "${GREEN}✅ ${moved} Nginx HTTPS Конфигурации обратный прокси изолированы.${PLAIN}")"
        echo -e "$(localized_text "${CYAN}备份目录：${backup_dir}${PLAIN}" "${CYAN}Backup directory: ${backup_dir}${PLAIN}" "${CYAN}Каталог резервной копии : ${backup_dir}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 清理后 Nginx 校验失败，请检查 nginx -t 输出。${PLAIN}" "${RED}❌ Nginx verification failed after cleaning, please check the nginx -t output.${PLAIN}" "${RED}❌ Проверка Nginx не удалась после очистки, проверьте вывод nginx -t.${PLAIN}")"
        nginx -t
        return 1
    fi
}

func_proxy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧹 清空反代配置（Caddy / Nginx）${PLAIN}" "${BOLD}🧹 Clear the reverse proxy configuration (Caddy / Nginx)${PLAIN}" "${BOLD}🧹 Очистить конфигурацию обратного прокси (Caddy / Nginx)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}  1. 清空 Caddy 反代配置${PLAIN}" "${GREEN}1. Clear Caddy and reverse proxy configuration${PLAIN}" "${GREEN}1. Очистите конфигурацию обратного прокси-сервера Caddy .${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. 清空 Nginx HTTPS 反代配置${PLAIN}" "${GREEN}2. Clear Nginx HTTPS and reverse proxy configuration${PLAIN}" "${GREEN}2. Очистите конфигурацию обратного прокси-сервера Nginx HTTPS .${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    local choice
    read_trimmed choice "$(localized_text "请选择操作: " "Please select an action:" "Пожалуйста, выберите действие:")"
    case "$choice" in
        1) func_caddy_clear_config ;;
        2) func_nginx_clear_proxy_config ;;
        0|q|Q|"") echo -e "$(localized_text "${BLUE}已取消。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")" ;;
        *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")" ;;
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

    append_editable_proxy_config_file "$(localized_text "Caddy 主配置" "Caddy main configuration" "Основная конфигурация Caddy")" "/etc/caddy/Caddyfile" "caddy"
    local conf_file
    for conf_file in /etc/caddy/conf.d/*.caddy; do
        [[ -f "$conf_file" ]] && append_editable_proxy_config_file "$(localized_text "Caddy 站点 $(basename "$conf_file")" "Caddy site $(basename \"$conf_file\")" "Caddy сайт $(basename \"$conf_file\")")" "$conf_file" "caddy"
    done
    append_editable_proxy_config_file "$(localized_text "Nginx 主配置" "Nginx main configuration" "Основная конфигурация Nginx")" "/etc/nginx/nginx.conf" "nginx"
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
            command -v caddy >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 caddy 命令，无法校验配置。${PLAIN}" "${RED}❌ The caddy command is not detected and the configuration cannot be verified.${PLAIN}" "${RED}❌ Команда caddy не обнаружена, и конфигурация не может быть проверена.${PLAIN}")"; return 1; }
            caddy validate --config /etc/caddy/Caddyfile
            ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 nginx 命令，无法校验配置。${PLAIN}" "${RED}❌ The nginx command is not detected and the configuration cannot be verified.${PLAIN}" "${RED}❌ Команда nginx не обнаружена, и конфигурация не может быть проверена.${PLAIN}")"; return 1; }
            nginx -t
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 未知配置类型：${kind}${PLAIN}" "${RED}❌ Unknown configuration type: ${kind}${PLAIN}" "${RED}❌ Неизвестный тип конфигурации: ${kind}.${PLAIN}")"
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
    echo -e "$(localized_text "${BOLD}📝 查看/编辑已应用配置文件${PLAIN}" "${BOLD}📝 View/edit applied profile${PLAIN}" "${BOLD}📝 Просмотр/редактирование примененного профиля${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#proxy_config_paths[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到可编辑的 Caddy/Nginx 配置文件。${PLAIN}" "${YELLOW}Did not detect the editable Caddy/Nginx configuration file.${PLAIN}" "${YELLOW}не обнаружил редактируемый файл конфигурации Caddy/Nginx.${PLAIN}")"
        return 0
    fi

    local i
    for i in "${!proxy_config_paths[@]}"; do
        printf '%b%3d. %s%b\n' "$GREEN" "$((i + 1))" "${proxy_config_labels[$i]} -> ${proxy_config_paths[$i]}" "$PLAIN"
    done
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice idx target_file target_kind backup_file editor confirm rollback_confirm
    read_trimmed choice "$(localized_text "请选择要查看/编辑的配置文件: " "Please select a profile to view/edit:" "Пожалуйста, выберите профиль для просмотра/редактирования:")"
    [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "Q" ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#proxy_config_paths[@]} )); then
        echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    target_file="${proxy_config_paths[$idx]}"
    target_kind="${proxy_config_kinds[$idx]}"
    [[ -f "$target_file" ]] || { echo -e "$(localized_text "${RED}❌ 文件不存在：${target_file}${PLAIN}" "${RED}❌ File does not exist: ${target_file}${PLAIN}" "${RED}❌ Файл не существует: ${target_file}${PLAIN}")"; return 1; }

    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    echo -e "$(localized_text "${BOLD}当前文件：${target_file}${PLAIN}" "${BOLD}Current file: ${target_file}${PLAIN}" "${BOLD}Текущий файл: ${target_file}${PLAIN}")"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    nl -ba "$target_file"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    read_trimmed confirm "$(localized_text "是否打开编辑器修改该文件？(Y/n，默认 y): " "Do you want to open an editor to modify the file? (Y/n, default y):" "Хотите открыть редактор и изменить файл? (Да/нет, по умолчанию y):")"
    is_yes "$confirm" || return 0

    editor=$(proxy_config_editor_command) || {
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
    if ! validate_proxy_config_kind "$target_kind"; then
        echo -e "$(localized_text "${RED}❌ 校验失败，服务不会 reload。${PLAIN}" "${RED}❌ The verification failed and the service will not reload.${PLAIN}" "${RED}❌ Проверка не удалась, и служба не перезагрузится.${PLAIN}")"
        read_trimmed rollback_confirm "$(localized_text "是否恢复编辑前备份？(Y/n，默认 yes): " "Restore pre-edit backup? (Y/n, default yes):" "Восстановить предварительно отредактированную резервную копию? (Да/нет, по умолчанию да):")"
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && echo -e "$(localized_text "${GREEN}✅ 已恢复：${target_file}${PLAIN}" "${GREEN}✅ Restored: ${target_file}${PLAIN}" "${GREEN}✅ Восстановлено: ${target_file}${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 已保留未通过校验的修改，请手动修正后再 reload。${PLAIN}" "${YELLOW}⚠️ Modifications that failed verification have been retained. Please correct them manually before reloading.${PLAIN}" "${YELLOW}⚠️ Модификации, не прошедшие проверку, сохранены. Пожалуйста, исправьте их вручную перед перезагрузкой.${PLAIN}")"
        fi
        return 1
    fi

    if reload_proxy_config_kind "$target_kind"; then
        echo -e "$(localized_text "${GREEN}✅ 配置已校验并重新加载。${PLAIN}" "${GREEN}✅ Configuration has been verified and reloaded.${PLAIN}" "${GREEN}✅ Конфигурация проверена и перезагружена.${PLAIN}")"
        echo -e "$(localized_text "${CYAN}备份文件：${backup_file}${PLAIN}" "${CYAN}Backup file: ${backup_file}${PLAIN}" "${CYAN}Файл резервной копии : ${backup_file}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 配置校验通过，但服务 reload/restart 失败。${PLAIN}" "${RED}❌ The configuration validation passed, but the service reload/restart failed.${PLAIN}" "${RED}❌ Проверка конфигурации прошла, но перезагрузка/перезапуск службы не удалась.${PLAIN}")"
        read_trimmed rollback_confirm "$(localized_text "是否恢复编辑前备份？(Y/n，默认 yes): " "Restore pre-edit backup? (Y/n, default yes):" "Восстановить предварительно отредактированную резервную копию? (Да/нет, по умолчанию да):")"
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && reload_proxy_config_kind "$target_kind" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ 已尝试恢复编辑前配置。${PLAIN}" "${GREEN}✅ An attempt has been made to restore the pre-edit configuration.${PLAIN}" "${GREEN}✅ Предпринята попытка восстановить предредактированную конфигурацию.${PLAIN}")"
        fi
        return 1
    fi
}

func_caddy_reverse_proxy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "反代" "reverse proxyal" "обратный прокси")"
        echo -e "$(localized_text "${BOLD}🌐 反代（Caddy / Nginx）${PLAIN}" "${BOLD}🌐 reverse proxy (Caddy / Nginx)${PLAIN}" "${BOLD}🌐 обратный прокси (Caddy / Nginx)${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：管理未接入 443端口复用的域名反代。443端口复用请只走主菜单 [19]。${PLAIN}" "${YELLOW}Purpose: Manage domain reverse proxy that is not connected to the Port 443 Reuse. 443 For Port 443 Reuse, please only go to the main menu [19].${PLAIN}" "${YELLOW}Назначение: Управление обратным прокси-сервером доменного имени, который не подключен к повторному использованию порта 443. 443 Для общего входа зайдите только в главное меню [19].${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 添加 Caddy 反代${PLAIN}" "${GREEN}1. Add Caddy to replace${PLAIN}" "${GREEN}1. Добавьте Caddy вместо.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 添加 Nginx HTTPS 反代${PLAIN} ${YELLOW}(复用 acme.sh + CF DNS 证书)${PLAIN}" "${GREEN}2. Add Nginx HTTPS to reverse proxy (reuse acme.sh + CF DNS certificate)${PLAIN}" "${GREEN}2. Добавьте Nginx HTTPS в обратный прокси (повторное использование сертификата acme.sh + CF DNS)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  3. 查看 Caddy/共享证书路径${PLAIN}" "${CYAN}3. View Caddy/shared certificate path${PLAIN}" "${CYAN}3. Просмотр Caddy/пути общего сертификата${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  4. 后端 HTTPS 跳过证书校验${PLAIN} ${YELLOW}(Caddy/Nginx，后端自签 HTTPS 时使用)${PLAIN}" "${CYAN}4. Backend HTTPS skips certificate verification (Caddy/Nginx, used when the backend self-signs HTTPS)${PLAIN}" "${CYAN}4. бэкенд HTTPS пропускает проверку сертификата (Caddy/Nginx, используется, когда бэкенд самостоятельно подписывает HTTPS)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  5. 域名 IP 白名单${PLAIN} ${YELLOW}(Caddy/Nginx)${PLAIN}" "${CYAN}5. domain IP whitelist (Caddy/Nginx)${PLAIN}" "${CYAN}5. Белый список IP-адресов доменных имен (Caddy/Nginx)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  6. 查看/编辑已应用配置文件${PLAIN} ${YELLOW}(Caddy/Nginx，校验后 reload)${PLAIN}" "${CYAN}6. View/edit the applied configuration file (Caddy/Nginx, reload after verification)${PLAIN}" "${CYAN}6. Просмотр/редактирование прикладного файла конфигурации (Caddy/Nginx, перезагрузка после проверки)${PLAIN}")"
        echo -e "$(localized_text "${RED}  7. 清空反代配置${PLAIN} ${YELLOW}(Caddy/Nginx)${PLAIN}" "${RED}7. Clear the reverse proxy configuration (Caddy/Nginx)${PLAIN}" "${RED}7. Очистите конфигурацию обратного прокси-сервера  (Caddy/Nginx)${PLAIN}")"
        echo -e "$(localized_text "${RED}  8. 删除底层 ACME 证书/域名配置${PLAIN} ${YELLOW}(会同时清理脚本创建的 Nginx 配置)${PLAIN}" "${RED}8. Delete the underlying ACME certificate/domain configuration (the Nginx configuration created by the script will also be cleaned up)${PLAIN}" "${RED}8. Удалите базовую конфигурацию сертификата ACME/доменного имени (конфигурация Nginx, созданная сценарием, также будет очищена)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local caddy_choice
        read_trimmed caddy_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
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
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
        echo ""
        pause_return "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}
