# shellcheck shell=bash
# Disabled legacy Caddy + Reality wizard compatibility stub.

func_caddy_cf_reality_wizard_legacy_disabled() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧩 Reality 443 复用 + Cloudflare DNS 自动化向导${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}本向导会让 Caddy 仅监听本地端口，不占用公网 80/443。${PLAIN}"
    echo -e "${YELLOW}推荐用于：3x-ui Reality 已占用 443，同时 Web 服务需要同域名 HTTPS。${PLAIN}"
    echo -e "------------------------------------------------"

    read_trimmed reality_occupied "❓ 当前 443 端口是否已被 3x-ui VLESS-Reality 占用？(y/n): "
    if is_no "$reality_occupied"; then
        echo -e "${BLUE}ℹ️ 您选择了未占用 443，本向导仍将使用本地端口模式，避免与未来业务冲突。${PLAIN}"
    fi

    local listen_port
    read_trimmed listen_port "👉 请输入 Caddy 本地 TLS 监听端口 (默认 8443): "
    listen_port=${listen_port:-8443}
    if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [[ "$listen_port" -lt 1 || "$listen_port" -gt 65535 ]]; then
        echo -e "${RED}❌ 监听端口无效！必须是 1-65535 的纯数字。${PLAIN}"
        return
    fi
    if is_yes "$reality_occupied" && [[ "$listen_port" -eq 443 ]]; then
        echo -e "${RED}❌ 443 已用于 Reality，请改用本地高位端口 (如 8443/9443)。${PLAIN}"
        return
    fi

    local cf_token
    echo -e "${CYAN}👇 请输入 Cloudflare API Token（需 Zone.DNS 编辑权限）${PLAIN}"
    read_secret_trimmed cf_token "CF Token: "
    if [[ -z "$cf_token" || ${#cf_token} -lt 20 ]]; then
        echo -e "${RED}❌ Token 长度异常，已取消。${PLAIN}"
        return
    fi
    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
    verify_cf_token_online "$cf_token"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "${GREEN}✅ Token 校验通过。${PLAIN}"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
    else
        echo -e "${RED}❌ Token 在线校验失败：请检查权限或确认 Token 未填错。${PLAIN}"
        echo -e "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}"
        return
    fi

    if ! install_caddy_if_needed; then
        echo -e "${RED}❌ Caddy 安装失败，请检查网络后重试。${PLAIN}"
        return
    fi

    local acme_bin="/root/.acme.sh/acme.sh"
    local acme_email
    acme_email=$(get_acme_account_email)
    if [[ ! -x "$acme_bin" ]]; then
        if ! install_acme_sh "$acme_email"; then
            echo -e "${RED}❌ acme.sh 安装失败，请检查网络后重试。${PLAIN}"
            return
        fi
    fi
    if [[ ! -x "$acme_bin" ]]; then
        echo -e "${RED}❌ 未找到 acme.sh，可执行文件异常。${PLAIN}"
        return
    fi
    if ! prepare_acme_account "$acme_bin" "$acme_email"; then
        echo -e "${RED}❌ acme 账户初始化失败，请检查邮箱配置后重试。${PLAIN}"
        return
    fi

    local cf_env_dir="/root/.config/vps-panel"
    local cf_env_file="${cf_env_dir}/cloudflare.env"
    mkdir -p "$cf_env_dir"
    chmod 700 "$cf_env_dir"
    local escaped_token
    escaped_token=${cf_token//\'/\'"\'"\'}
    printf "CF_Token='%s'\n" "$escaped_token" > "$cf_env_file"
    chmod 600 "$cf_env_file"

    mkdir -p /etc/caddy/conf.d /etc/caddy/certs /root/cert

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    fi

    echo -e "${CYAN}▶ 正在扫描并隔离旧式 Caddy 配置（防止抢占 443）...${PLAIN}"
    quarantine_legacy_caddy_443_configs

    echo -e "${YELLOW}👇 开始添加域名反代规则（可连续添加多个）${PLAIN}"
    echo -e "${YELLOW}格式：域名 -> 本地端口，例如 panel.example.com -> 8000${PLAIN}"
    echo -e "------------------------------------------------"

    local success_count=0
    local fail_count=0
    local summary_file="/root/cert/caddy_cf_manifest.txt"

    while true; do
        local domain domain_input backend_port continue_add
        read_trimmed domain_input "👉 请输入域名 (回车结束添加): "
        domain=$(normalize_domain_input "$domain_input")
        if [[ -z "$domain" ]]; then
            break
        fi

        if ! is_valid_domain "$domain"; then
            print_domain_validation_error "域名" "$domain_input" "$domain"
            ((fail_count++))
            continue
        fi

        read_trimmed backend_port "👉 请输入该域名反代的本地端口: "
        if ! is_valid_port "$backend_port"; then
            echo -e "${RED}❌ 端口无效：$backend_port${PLAIN}"
            ((fail_count++))
            continue
        fi

        local conf_file="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$conf_file" ]]; then
            echo -e "${RED}❌ 已存在域名配置：$conf_file，请先删除后再添加。${PLAIN}"
            ((fail_count++))
            continue
        fi

        # shellcheck disable=SC1090
        source "$cf_env_file"
        echo -e "${CYAN}▶ 正在为 ${domain} 申请 DNS 证书...${PLAIN}"
        if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
            echo -e "${RED}❌ 证书申请失败：${domain}${PLAIN}"
            echo -e "${YELLOW}   提示：可进入主菜单 [19] -> [13] 一键自动修复后再重试。${PLAIN}"
            ((fail_count++))
            continue
        fi

        local cert_file="/etc/caddy/certs/${domain}.crt"
        local key_file="/etc/caddy/certs/${domain}.key"

        if ! "$acme_bin" --install-cert -d "$domain" --ecc \
            --fullchain-file "$cert_file" \
            --key-file "$key_file" \
            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
            echo -e "${RED}❌ 证书安装失败：${domain}${PLAIN}"
            ((fail_count++))
            continue
        fi

        if id caddy >/dev/null 2>&1; then
            chown root:caddy "$cert_file" "$key_file" >/dev/null 2>&1
            chmod 640 "$cert_file" "$key_file"
        else
            chmod 600 "$cert_file" "$key_file"
        fi

        ln -sfn "$cert_file" "/root/cert/${domain}.crt"
        ln -sfn "$key_file" "/root/cert/${domain}.key"

        cat <<EOF > "$conf_file"
https://${domain}:${listen_port} {
    bind 127.0.0.1
    tls ${cert_file} ${key_file}
    reverse_proxy 127.0.0.1:${backend_port}
}
EOF

        echo -e "${GREEN}✅ 域名 ${domain} 已完成：证书签发 + 反代配置 + 证书挂载。${PLAIN}"
        ((success_count++))

        read_trimmed continue_add "继续添加下一个域名？(y/n): "
        if ! is_yes "$continue_add"; then
            break
        fi
    done

    echo -e "${CYAN}▶ 正在校验并加载 Caddy 配置...${PLAIN}"
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl enable caddy >/dev/null 2>&1
        systemctl restart caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ Caddy 已成功重载，配置生效。${PLAIN}"
    else
        echo -e "${RED}❌ Caddy 配置校验失败！请检查 /etc/caddy/conf.d/ 下新增文件语法。${PLAIN}"
        echo -e "${YELLOW}已保留证书文件，您修正配置后可手动执行: systemctl restart caddy${PLAIN}"
    fi

    generate_caddy_cf_manifest

    echo -e "------------------------------------------------"
    echo -e "${GREEN}🎯 向导执行完成：成功 ${success_count} 个，失败 ${fail_count} 个。${PLAIN}"
    echo -e "${CYAN}证书软链接目录:${PLAIN} /root/cert"
    echo -e "${CYAN}清单文件路径:${PLAIN} ${summary_file}"
    echo -e "${YELLOW}💡 3x-ui 手动配置提示：${PLAIN}"
    echo -e "1) 在 Reality 节点里设置 fallback/dest 指向: 127.0.0.1:${listen_port}"
    echo -e "2) 每个回落域名需与本向导录入域名一致，SNI 才能命中对应证书和反代规则"
    echo -e "3) 如业务强依赖真实访客IP，请后续再单独启用 PROXY Protocol 高阶方案"
}

# ---------------------------------------------------------
# 新增功能：CF DNS 证书二次维护菜单
# ---------------------------------------------------------
