# shellcheck shell=bash
# Validation and normalization helpers.

normalize_domain_input() {
    local domain
    domain="$(trim_input "$1")"
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain=$(echo "$domain" | tr -d '[:space:]')
    printf '%s' "$domain"
}

is_valid_hostname() {
    local name="$1"
    local label
    [[ -n "$name" && ${#name} -le 253 ]] || return 1
    [[ "$name" != .* && "$name" != *. ]] || return 1
    [[ "$name" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    IFS='.' read -ra labels <<< "$name"
    for label in "${labels[@]}"; do
        [[ -n "$label" && ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
    return 0
}

is_valid_domain() {
    local domain="$1"
    echo "$domain" | grep -Eq '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
}

print_domain_validation_error() {
    local label="${1:-域名}"
    local raw="${2:-}"
    local normalized="${3:-}"
    local trimmed display_value

    [[ -z "$normalized" && -n "$raw" ]] && normalized=$(normalize_domain_input "$raw")
    display_value="${normalized:-（空）}"
    echo -e "${RED}❌ ${label}格式无效：${display_value}${PLAIN}"
    echo -e "${YELLOW}提示：请只粘贴纯域名，例如 panel.example.com；不要带协议、路径、端口或中文/全角标点。${PLAIN}"

    if [[ -z "$raw" ]]; then
        echo -e "${YELLOW}脚本规范化后用于校验的值：${display_value}${PLAIN}"
        return 0
    fi

    trimmed=$(trim_input "$raw")
    if [[ "$trimmed" != "$raw" || "$raw" =~ [[:space:]] ]]; then
        echo -e "${YELLOW}检测到空白字符：请确认没有复制到换行、制表符、不可见空格或多余空格。${PLAIN}"
    fi
    if [[ "$trimmed" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// || "$trimmed" == *"://"* || "$trimmed" == */* || "$trimmed" == *\?* || "$trimmed" == *#* || "$trimmed" == *:* ]]; then
        echo -e "${YELLOW}检测到类似 URL 的内容：请去掉 http(s)://、路径、查询参数、#片段或 :端口。${PLAIN}"
    fi
    if printf '%s' "$trimmed" | grep -q '[：，。／、；？＃＠　]'; then
        echo -e "${YELLOW}检测到中文/全角标点：请改成英文半角的 . , / : 等字符；域名里的点必须是英文句点。${PLAIN}"
    fi
    if printf '%s' "$trimmed" | LC_ALL=C grep -q '[^ -~]'; then
        echo -e "${YELLOW}检测到非 ASCII 字符：可能包含零宽空格、全角字符或复制来源带入的隐藏字符。${PLAIN}"
    fi
    echo -e "${YELLOW}脚本规范化后用于校验的值：${display_value}${PLAIN}"
}

normalize_path_prefix() {
    local path
    path="$(trim_input "$1")"
    if [[ "$path" =~ ^https?://[^/]+(/.*)?$ ]]; then
        path="${BASH_REMATCH[1]:-/}"
    fi
    path="${path%%\?*}"
    path="${path%%#*}"
    [[ -z "$path" ]] && path="/sub/"
    [[ "$path" != /* ]] && path="/${path}"
    [[ "$path" != */ ]] && path="${path}/"
    printf '%s' "$path"
}

is_valid_path_prefix() {
    local path="$1"
    [[ "$path" != "/" && "$path" != *".."* ]] && echo "$path" | grep -Eq '^/[A-Za-z0-9._~/-]+/$'
}

caddy_path_match_tokens() {
    local path
    local exact
    local seen=" "
    local tokens=""
    for path in "$@"; do
        path=$(normalize_path_prefix "$path")
        exact="${path%/}"
        if [[ "$seen" == *" ${exact} "* ]]; then
            continue
        fi
        tokens+="${exact} ${exact}/* "
        seen+=" ${exact} "
    done
    printf '%s' "${tokens% }"
}

is_yes() {
    local value
    value="$(trim_input "$1")"
    [[ "$value" =~ ^[Yy]([Ee][Ss])?$ ]]
}

is_no() {
    local value
    value="$(trim_input "$1")"
    [[ "$value" =~ ^[Nn]([Oo])?$ ]]
}

is_suspicious_public_ipv4() {
    local ip="$1"
    local a b c d

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r a b c d <<< "$ip"
    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]+$ ]] && ((10#$octet <= 255)) || return 1
    done

    # Public panel domains should not resolve to private, loopback, test, multicast,
    # or benchmark/fake-ip ranges. Run this on the VPS side; local proxy fake-ip
    # mode may intentionally return 198.18.0.0/15 on the user's own computer.
    ((10#$a == 0 || 10#$a == 10 || 10#$a == 127 || 10#$a >= 224)) && return 0
    ((10#$a == 100 && 10#$b >= 64 && 10#$b <= 127)) && return 0
    ((10#$a == 169 && 10#$b == 254)) && return 0
    ((10#$a == 172 && 10#$b >= 16 && 10#$b <= 31)) && return 0
    ((10#$a == 192 && 10#$b == 168)) && return 0
    ((10#$a == 198 && (10#$b == 18 || 10#$b == 19))) && return 0
    ((10#$a == 192 && 10#$b == 0 && 10#$c == 2)) && return 0
    ((10#$a == 198 && 10#$b == 51 && 10#$c == 100)) && return 0
    ((10#$a == 203 && 10#$b == 0 && 10#$c == 113)) && return 0
    return 1
}

resolve_domain_a_records() {
    local domain="$1"
    if command -v dig >/dev/null 2>&1; then
        dig +short A "$domain" @1.1.1.1 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup -type=A "$domain" 1.1.1.1 2>/dev/null | awk '/^Address: / {print $2}' | grep -Ev '^1\.1\.1\.1$' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u
    elif command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u
    fi
}

check_domain_dns_sanity() {
    local domain="$1"
    local label="${2:-域名}"
    local mode="${3:-warn}"
    local ips ip suspect=0 confirm

    ips=$(resolve_domain_a_records "$domain")
    if [[ -z "$ips" ]]; then
        echo -e "${YELLOW}⚠️ ${label} ${domain} 未解析到 A 记录；如果只配置了 IPv6/AAAA，请确认客户端和 VPS 都支持 IPv6。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ ${label} ${domain} 当前 A 记录: $(echo "$ips" | tr '\n' ' ')${PLAIN}"
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if is_suspicious_public_ipv4 "$ip"; then
            echo -e "${RED}❌ ${label} ${domain} 解析到可疑地址 ${ip}，这不是正常公网 VPS 地址。${PLAIN}"
            suspect=1
        fi
    done <<< "$ips"

    if [[ "$suspect" -eq 1 ]]; then
        echo -e "${YELLOW}请在 VPS 上复查 DNS。若只在本地电脑开启了 fake-ip，198.18.x.x 可能只是本地代理映射；若 VPS/公共 DNS 也看到此地址，请把 A 记录改成真实 VPS 公网 IP。${PLAIN}"
        echo -e "${YELLOW}如果使用 Cloudflare 小云朵，公共 DNS 应看到 Cloudflare 边缘 IP，而不是 198.18/10/127/192.168 等地址。${PLAIN}"
        if [[ "$mode" == "prompt" ]]; then
            read_trimmed confirm "仍要继续请输入 yes（不推荐，大小写均可）: "
            is_yes "$confirm" || return 1
        else
            return 1
        fi
    fi

    return 0
}

is_valid_ipv4_cidr() {
    local value="$1"
    local ip prefix a b c d octet
    ip="${value%%/*}"
    prefix=""
    [[ "$value" == */* ]] && prefix="${value##*/}"

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r a b c d <<< "$ip"
    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
    done
    if [[ -n "$prefix" ]]; then
        [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
        (( 10#$prefix >= 0 && 10#$prefix <= 32 )) || return 1
    fi
}

is_valid_ipv6_cidr() {
    local value="$1"
    local ip prefix
    ip="${value%%/*}"
    prefix=""
    [[ "$value" == */* ]] && prefix="${value##*/}"

    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    if [[ -n "$prefix" ]]; then
        [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
        (( 10#$prefix >= 0 && 10#$prefix <= 128 )) || return 1
    fi
}

is_valid_ip_cidr() {
    local value="$1"
    [[ -n "$value" && "$value" != *";"* && "$value" != *"{"* && "$value" != *"}"* ]] || return 1
    is_valid_ipv4_cidr "$value" || is_valid_ipv6_cidr "$value"
}

normalize_ip_whitelist_input() {
    local input="$1"
    local -n out_array=$2
    local item normalized seen
    input="${input//，/,}"
    input="${input//;/ }"
    input="${input//,/ }"
    input="${input//$'\r'/ }"
    input="${input//$'\n'/ }"
    out_array=()
    seen=" "
    for item in $input; do
        normalized=$(echo "$(trim_input "$item")" | tr '[:upper:]' '[:lower:]')
        [[ -z "$normalized" ]] && continue
        if ! is_valid_ip_cidr "$normalized"; then
            echo -e "${RED}❌ IP/CIDR 格式无效：${normalized}${PLAIN}"
            return 1
        fi
        if [[ "$seen" != *" ${normalized} "* ]]; then
            out_array+=("$normalized")
            seen+=" ${normalized} "
        fi
    done
    [[ ${#out_array[@]} -gt 0 ]]
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))
}

is_valid_listen_addr() {
    local addr="$1"
    if [[ "$addr" == "127.0.0.1" || "$addr" == "localhost" || "$addr" == "0.0.0.0" || "$addr" == "::1" || "$addr" == "::" ]]; then
        return 0
    fi
    if [[ "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS=.
        local -a octets=($addr)
        local octet
        for octet in "${octets[@]}"; do
            [[ "$octet" =~ ^[0-9]+$ ]] || return 1
            (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
        done
        return 0
    fi
    return 1
}

is_loopback_listen_addr() {
    local addr="$1"
    [[ "$addr" == "127.0.0.1" || "$addr" == "localhost" || "$addr" == "::1" ]]
}

normalize_loopback_addr() {
    local addr="$1"
    [[ "$addr" == "localhost" ]] && addr="127.0.0.1"
    printf '%s' "$addr"
}

normalize_port_rule_input() {
    local value="$1"
    value="${value//，/,}"
    value="${value//：/:}"
    value="${value//－/-}"
    value="${value//—/-}"
    value=$(echo "$value" | tr -d '[:space:]')

    local item start end extra
    local items=()
    local normalized=()
    IFS=',' read -ra items <<< "$value"
    for item in "${items[@]}"; do
        item="${item//:/-}"
        if [[ "$item" == *-* ]]; then
            IFS='-' read -r start end extra <<< "$item"
            if [[ -z "$extra" && "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]]; then
                normalized+=("$((10#$start))-$((10#$end))")
            else
                normalized+=("$item")
            fi
        elif [[ "$item" =~ ^[0-9]+$ ]]; then
            normalized+=("$((10#$item))")
        else
            normalized+=("$item")
        fi
    done

    (IFS=','; printf '%s' "${normalized[*]}")
}

is_valid_port_rule_input() {
    local input
    input=$(normalize_port_rule_input "$1")
    [[ -n "$input" ]] || return 1

    local item range_start range_end extra
    local items=()
    IFS=',' read -ra items <<< "$input"
    for item in "${items[@]}"; do
        [[ -n "$item" ]] || return 1
        item="${item//:/-}"
        if [[ "$item" == *-* ]]; then
            IFS='-' read -r range_start range_end extra <<< "$item"
            [[ -z "$extra" ]] || return 1
            is_valid_port "$range_start" && is_valid_port "$range_end" || return 1
            (( 10#$range_start <= 10#$range_end )) || return 1
        else
            is_valid_port "$item" || return 1
        fi
    done
    return 0
}

warn_if_public_bind() {
    local service_name="$1"
    local listen_addr="$2"
    local listen_port="$3"
    local confirm
    if [[ "$listen_addr" == "0.0.0.0" || "$listen_addr" == "::" ]]; then
        confirm_risk_action "${service_name} 监听公网 ${listen_addr}:${listen_port}" \
            "${service_name} 监听地址将从本地模型改为公网可访问" \
            "改回 127.0.0.1 后重新应用配置并重启相关服务" \
            "仅在你明确需要公网直连该服务时继续。" || return 1
    fi
    return 0
}

format_hostport() {
    local addr="$1"
    local port="$2"
    if [[ "$addr" == *:* && "$addr" != \[*\] ]]; then
        echo "[${addr}]:${port}"
    else
        echo "${addr}:${port}"
    fi
}

nginx_stream_listen_directives() {
    local addr="$1"
    local port="$2"

    if [[ "$addr" == *:* && "$addr" != \[*\] ]]; then
        printf '    listen [%s]:%s;\n' "$addr" "$port"
        return 0
    fi

    printf '    listen %s:%s;\n' "$addr" "$port"
    if [[ "$addr" == "0.0.0.0" ]]; then
        printf '    listen [::]:%s;\n' "$port"
    fi
}

xui_cert_setting_key_sql_list() {
    printf '%s' "'webcertfile','webkeyfile','webcert','webcertkey','webcertkeyfile','certfile','keyfile','cert','key','subcertfile','subkeyfile','subcert','subkey','subcertkey','subcertkeyfile'"
}

dns_is_valid_ipv4() {
    local ip="$1"
    local octet
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
    done
    return 0
}

dns_is_valid_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    [[ "$ip" != *:::* ]]
}

dns_normalize_servers() {
    local family="$1"
    local raw="$2"
    local item
    local items=()
    local result=()

    raw="${raw//，/,}"
    raw="${raw//;/,}"
    raw="${raw// /,}"
    raw="${raw//$'\t'/,}"
    IFS=',' read -ra items <<< "$raw"

    for item in "${items[@]}"; do
        item="$(trim_input "$item")"
        [[ -z "$item" ]] && continue
        if [[ "$family" == "4" ]]; then
            dns_is_valid_ipv4 "$item" || return 1
        else
            dns_is_valid_ipv6 "$item" || return 1
        fi
        result+=("$item")
    done

    [[ ${#result[@]} -gt 0 ]] || return 1
    (IFS=' '; printf '%s' "${result[*]}")
}
