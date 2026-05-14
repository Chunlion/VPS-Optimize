# shellcheck shell=bash
# acme.sh account preparation, Cloudflare DNS certificate issuance, and certificate manifests.

get_acme_account_email() {
    local account_conf="/root/.acme.sh/account.conf"
    if [[ -f "$account_conf" ]]; then
        local existing_email
        existing_email=$(grep '^ACCOUNT_EMAIL=' "$account_conf" 2>/dev/null | cut -d"'" -f2 | cut -d'"' -f2)
        if echo "$existing_email" | grep -Eq '^[a-zA-Z0-9._%+-]+@(gmail\.com|outlook\.com|yahoo\.com|hotmail\.com)$'; then
            echo "$existing_email"
            return
        fi
    fi

    local prefix
    prefix=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 12 2>/dev/null || echo "user$RANDOM$RANDOM")
    local domains=("gmail.com" "outlook.com" "yahoo.com" "hotmail.com")
    local domain="${domains[$((RANDOM % ${#domains[@]}))]}"
    echo "${prefix}@${domain}"
}

prepare_acme_account() {
    local acme_bin="$1"
    local acme_email="$2"
    local account_log="${3:-/tmp/vps_acme_account_$(date +%s).log}"
    local account_conf="/root/.acme.sh/account.conf"
    local le_ca_dir="/root/.acme.sh/ca/acme-v02.api.letsencrypt.org"

    if [[ ! -x "$acme_bin" ]]; then
        return 1
    fi

    mkdir -p /root/.acme.sh
    if [[ -f "$account_conf" ]]; then
        if grep -q '^ACCOUNT_EMAIL=' "$account_conf"; then
            sed -i "s|^ACCOUNT_EMAIL=.*|ACCOUNT_EMAIL='${acme_email}'|" "$account_conf"
        else
            printf "ACCOUNT_EMAIL='%s'\n" "$acme_email" >> "$account_conf"
        fi
    else
        printf "ACCOUNT_EMAIL='%s'\n" "$acme_email" > "$account_conf"
    fi

    export ACCOUNT_EMAIL="$acme_email"
    "$acme_bin" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

    if "$acme_bin" --register-account --server letsencrypt --accountemail "$acme_email" >"$account_log" 2>&1 || \
       "$acme_bin" --register-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt --accountemail "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1; then
        return 0
    fi

    # 若历史账户状态异常（例如旧邮箱残留），先隔离 LE 账户缓存后重试。
    quarantine_path "$le_ca_dir" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
    quarantine_path "/root/.acme.sh/ca/acme-staging-v02.api.letsencrypt.org" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
    if "$acme_bin" --register-account --server letsencrypt --accountemail "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --register-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt --accountemail "$acme_email" >>"$account_log" 2>&1 || \
       "$acme_bin" --update-account --server letsencrypt -m "$acme_email" >>"$account_log" 2>&1; then
        return 0
    fi

    return 1
}

quarantine_legacy_caddy_443_configs() {
    local conf_dir="/etc/caddy/conf.d"
    local quarantine_dir="/etc/caddy/conf.d_quarantine_443_$(date +%s)"
    local moved_count=0

    if [[ ! -d "$conf_dir" ]]; then
        return 0
    fi

    while IFS= read -r conf_file; do
        local first_site_line
        first_site_line=$(grep -m1 -E '^[[:space:]]*[^#[:space:]].*\{' "$conf_file" 2>/dev/null | sed 's/^[[:space:]]*//')

        [[ -z "$first_site_line" ]] && continue

        # Reality+CF 向导的新规范：https://domain:port { + bind 127.0.0.1
        if [[ "$first_site_line" =~ ^https://[^[:space:]]+:[0-9]+[[:space:]]*\{ ]]; then
            continue
        fi

        mkdir -p "$quarantine_dir"
        mv "$conf_file" "$quarantine_dir/" >/dev/null 2>&1
        ((moved_count++))
    done < <(find "$conf_dir" -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)

    if [[ "$moved_count" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已自动隔离 ${moved_count} 个旧站点配置（可能抢占 443）到：${quarantine_dir}${PLAIN}"
    fi
}

issue_cf_dns_cert_with_retry() {
    local domain="$1"
    local cf_token_raw="$2"
    local acme_bin="$3"
    local cf_token
    local acme_log
    local acme_email

    cf_token=$(echo "$cf_token_raw" | tr -d '\r\n')
    if [[ -z "$cf_token" || ! -x "$acme_bin" || -z "$domain" ]]; then
        return 1
    fi

    acme_log="/tmp/vps_acme_${domain}_$(date +%s).log"
    acme_email=$(get_acme_account_email)

    # 强制使用 Let's Encrypt，避免 ZeroSSL 触发 EAB 依赖导致签发失败。
    if ! prepare_acme_account "$acme_bin" "$acme_email" "$acme_log"; then
        mkdir -p /root/cert
        cp -f "$acme_log" /root/cert/acme_last_error.log >/dev/null 2>&1 || true
        echo -e "${RED}❌ acme 账户初始化失败：${domain}${PLAIN}"
        echo -e "${YELLOW}   最近错误日志: /root/cert/acme_last_error.log${PLAIN}"
        local account_hint
        account_hint=$(grep -Ei 'error|invalid|unauthorized|forbidden|failed|contact|account' "$acme_log" | tail -n 12)
        if [[ -n "$account_hint" ]]; then
            echo -e "${YELLOW}   关键报错如下：${PLAIN}"
            echo "$account_hint"
        fi
        return 1
    fi

    if CF_Token="$cf_token" "$acme_bin" --issue --server letsencrypt --dns dns_cf -d "$domain" --keylength ec-256 >"$acme_log" 2>&1; then
        return 0
    fi

    # 旧残留常导致“删除后重签失败”，先隔离历史状态再强制签发。
    "$acme_bin" --remove -d "$domain" --ecc >/dev/null 2>&1 || true
    quarantine_path "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
    quarantine_path "/root/.acme.sh/${domain}" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true

    if CF_Token="$cf_token" "$acme_bin" --issue --server letsencrypt --dns dns_cf -d "$domain" --keylength ec-256 --force >>"$acme_log" 2>&1; then
        return 0
    fi

    if CF_Token="$cf_token" "$acme_bin" --renew --server letsencrypt -d "$domain" --force --ecc >>"$acme_log" 2>&1; then
        return 0
    fi

    mkdir -p /root/cert
    cp -f "$acme_log" /root/cert/acme_last_error.log >/dev/null 2>&1 || true
    echo -e "${RED}❌ acme.sh 最终失败：${domain}${PLAIN}"
    echo -e "${YELLOW}   最近错误日志: /root/cert/acme_last_error.log${PLAIN}"

    local acme_hint
    acme_hint=$(grep -Ei 'error|invalid|unauthorized|forbidden|failed|timeout|SERVFAIL|NXDOMAIN|permission' "$acme_log" | tail -n 12)
    if [[ -n "$acme_hint" ]]; then
        echo -e "${YELLOW}   关键报错如下：${PLAIN}"
        echo "$acme_hint"
    else
        echo -e "${YELLOW}   未提取到关键错误，展示日志尾部：${PLAIN}"
        tail -n 12 "$acme_log"
    fi

    return 1
}

verify_cf_token_online() {
    local cf_token_raw="$1"
    local cf_token
    local verify_resp

    cf_token=$(echo "$cf_token_raw" | tr -d '\r\n')
    if [[ -z "$cf_token" ]]; then
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        return 2
    fi

    verify_resp=$(curl -s --max-time 10 -H "Authorization: Bearer ${cf_token}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
    if echo "$verify_resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
        return 0
    fi
    return 1
}

generate_caddy_cf_manifest() {
    local summary_file="/root/cert/caddy_cf_manifest.txt"
    mkdir -p /root/cert
    : > "$summary_file"
    echo "Caddy CF DNS 自动化清单 - $(date '+%F %T')" >> "$summary_file"
    echo "------------------------------------------------" >> "$summary_file"

    local found=false
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            local domain
            local listen_port
            local backend
            domain=$(basename "$conf_file" .caddy)

            if [[ ! -f "/etc/caddy/certs/${domain}.crt" || ! -f "/etc/caddy/certs/${domain}.key" ]]; then
                continue
            fi

            listen_port=$(sed -n '1{s@^https://[^:]*:\([0-9]\+\)[[:space:]]*{.*$@\1@p;q}' "$conf_file")
            backend=$(grep -E '^[[:space:]]*reverse_proxy[[:space:]]+127.0.0.1:[0-9]+' "$conf_file" | awk '{print $2}' | head -n1)

            [[ -z "$listen_port" ]] && listen_port="未知"
            [[ -z "$backend" ]] && backend="未知"

            echo "域名: ${domain}" >> "$summary_file"
            echo "  后端: ${backend}" >> "$summary_file"
            echo "  Caddy监听: 127.0.0.1:${listen_port}" >> "$summary_file"
            echo "  证书CRT: /root/cert/${domain}.crt" >> "$summary_file"
            echo "  证书KEY: /root/cert/${domain}.key" >> "$summary_file"
            echo "  配置文件: ${conf_file}" >> "$summary_file"
            echo "------------------------------------------------" >> "$summary_file"
            found=true
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi

    if ! $found; then
        echo "当前未检测到可管理的 CF DNS 站点配置。" >> "$summary_file"
        echo "------------------------------------------------" >> "$summary_file"
    fi
}

# ---------------------------------------------------------
# 3. 常用环境及软件 (重构版：防覆盖、严格容错、剔除静默失败)
# ---------------------------------------------------------
