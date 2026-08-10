# shellcheck shell=bash
# Validation and normalization helpers.

normalize_domain_input() {
    local domain
    domain="$(trim_input "$1")"
    if declare -F normalize_ascii_digits >/dev/null 2>&1; then
        domain="$(normalize_ascii_digits "$domain")"
    fi
    domain="${domain//。/.}"
    domain="${domain//．/.}"
    domain="${domain//｡/.}"
    domain="${domain//：/:}"
    domain=$(printf '%s' "$domain" | sed 's#／#/#g')
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%\?*}"
    domain="${domain%%？*}"
    domain="${domain%%#*}"
    domain="${domain%%＃*}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain=$(echo "$domain" | tr -d '[:space:]')
    while [[ "$domain" == *. ]]; do
        domain="${domain%.}"
    done
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
    local label="$(localized_text "${1:-域名}" "${1:-域名}" "${1:-域名}")"
    local raw="${2:-}"
    local normalized="${3:-}"
    local trimmed display_value

    [[ -z "$normalized" && -n "$raw" ]] && normalized=$(normalize_domain_input "$raw")
    display_value="$(localized_text "${normalized:-（空）}" "${normalized:-（空）}" "${normalized:-（空）}")"
    echo -e "$(localized_text "${RED}❌ ${label}格式无效：${display_value}${PLAIN}" "${RED}❌ ${label} Invalid format: ${display_value}${PLAIN}" "${RED}❌ ${label} Неверный формат: ${display_value}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}提示：请只粘贴纯域名，例如 panel.example.com；不要带协议、路径、端口或中文/全角标点。${PLAIN}" "${YELLOW}Tip: Please paste only the pure domain, such as panel.example.com; do not include the protocol, path, port or Chinese/full-width punctuation.${PLAIN}" "${YELLOW}Совет. Вставьте только чистое доменное имя, например Panel.example.com; не включайте протокол, путь, порт или знаки препинания на китайском языке или во всю ширину.${PLAIN}")"

    if [[ -z "$raw" ]]; then
        echo -e "$(localized_text "${YELLOW}脚本规范化后用于校验的值：${display_value}${PLAIN}" "${YELLOW}The value used for verification after the script is normalized: ${display_value}${PLAIN}" "${YELLOW}Значение, используемое для проверки после нормализации сценария : ${display_value}.${PLAIN}")"
        return 0
    fi

    trimmed=$(trim_input "$raw")
    if [[ "$trimmed" != "$raw" || "$raw" =~ [[:space:]] ]]; then
        echo -e "$(localized_text "${YELLOW}检测到空白字符：请确认没有复制到换行、制表符、不可见空格或多余空格。${PLAIN}" "${YELLOW}Whitespace characters detected: Please confirm that no newlines, tabs, invisible spaces, or extra spaces are copied.${PLAIN}" "${YELLOW}Обнаружены пробельные символы: убедитесь, что не копируются символы новой строки, табуляции, невидимые пробелы или дополнительные пробелы.${PLAIN}")"
    fi
    if [[ "$trimmed" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// || "$trimmed" == *"://"* || "$trimmed" == */* || "$trimmed" == *\?* || "$trimmed" == *#* || "$trimmed" == *:* ]]; then
        echo -e "$(localized_text "${YELLOW}检测到类似 URL 的内容：请去掉 http(s)://、路径、查询参数、#片段或 :端口。${PLAIN}" "${YELLOW}Detected URL-like content: Please remove http(s)://, path, query parameters, # fragment or :port.${PLAIN}" "${YELLOW}обнаружил содержимое, похожее на URL-адрес: удалите http(s)://, путь, параметры запроса, # фрагмент или :port.${PLAIN}")"
    fi
    if printf '%s' "$trimmed" | grep -q '[：，。／、；？＃＠　]'; then
        echo -e "$(localized_text "${YELLOW}检测到中文/全角标点：请改成英文半角的 . , / : 等字符；域名里的点必须是英文句点。${PLAIN}" "${YELLOW}Detected Chinese/full-width punctuation: please change it to English half-width . , / : and other characters; the dots in the domain must be English periods.${PLAIN}" "${YELLOW}обнаружил китайскую/полноширинную пунктуацию: измените ее на английскую половинную ширину. , / : и другие символы; точки в доменном имени должны быть английскими точками.${PLAIN}")"
    fi
    if printf '%s' "$trimmed" | LC_ALL=C grep -q '[^ -~]'; then
        echo -e "$(localized_text "${YELLOW}检测到非 ASCII 字符：可能包含零宽空格、全角字符或复制来源带入的隐藏字符。${PLAIN}" "${YELLOW}Non-ASCII characters detected: may contain zero-width spaces, full-width characters, or hidden characters brought in from the copy source.${PLAIN}" "${YELLOW}Обнаружены символы, отличные от ASCII: могут содержать пробелы нулевой ширины, символы полной ширины или скрытые символы, полученные из источника копирования.${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}脚本规范化后用于校验的值：${display_value}${PLAIN}" "${YELLOW}The value used for verification after the script is normalized: ${display_value}${PLAIN}" "${YELLOW}Значение, используемое для проверки после нормализации сценария : ${display_value}.${PLAIN}")"
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
    local label="$(localized_text "${2:-域名}" "${2:-域名}" "${2:-域名}")"
    local mode="${3:-warn}"
    local ips ip suspect=0

    ips=$(resolve_domain_a_records "$domain")
    if [[ -z "$ips" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${label} ${domain} 未解析到 A 记录；如果只配置了 IPv6/AAAA，请确认客户端和 VPS 都支持 IPv6。${PLAIN}" "${YELLOW}⚠️ ${label} ${domain} is not resolved to the A record; if only IPv6/AAAA is configured, please confirm that both the client and VPS support IPv6.${PLAIN}" "${YELLOW}⚠️ ${label} ${domain} не разрешается в запись A; если настроен только IPv6/AAAA, убедитесь, что и клиент, и VPS поддерживают IPv6.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ ${label} ${domain} 当前 A 记录: $(echo "$ips" | tr '\n' ' ')${PLAIN}" "${CYAN}▶ ${label} ${domain} Current A record: $(echo \"$ips\" | tr '\n' ' ')${PLAIN}" "${CYAN}▶ ${label} ${domain} Текущая запись A: $(echo \"$ips\" | tr '\n' ' ')${PLAIN}")"
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if is_suspicious_public_ipv4 "$ip"; then
            echo -e "$(localized_text "${RED}❌ ${label} ${domain} 解析到可疑地址 ${ip}，这不是正常公网 VPS 地址。${PLAIN}" "${RED}❌ ${label} ${domain} resolves to the suspicious address ${ip}, which is not a normal public VPS address.${PLAIN}" "${RED}❌ ${label} ${domain} разрешается в подозрительный адрес ${ip}, который не является обычным VPS-адресом публичной сети.${PLAIN}")"
            suspect=1
        fi
    done <<< "$ips"

    if [[ "$suspect" -eq 1 ]]; then
        echo -e "$(localized_text "${YELLOW}请在 VPS 上复查 DNS。若只在本地电脑开启了 fake-ip，198.18.x.x 可能只是本地代理映射；若 VPS/公共 DNS 也看到此地址，请把 A 记录改成真实 VPS 公网 IP。${PLAIN}" "${YELLOW}Please review DNS on VPS. If fake-ip is only enabled on the local computer, 198.18.x.x may only be local proxy mapping; if VPS/public DNS also sees this address, please change the A record to the real VPS public IP.${PLAIN}" "${YELLOW}Пожалуйста, просмотрите DNS на VPS. Если поддельный IP-адрес включен только на локальном компьютере, 198.18.x.x может быть сопоставлением только локального прокси-сервера; если VPS/public DNS также видит этот адрес, измените запись A на реальный IP-адрес VPS в Интернете.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}如果使用 Cloudflare 小云朵，公共 DNS 应看到 Cloudflare 边缘 IP，而不是 198.18/10/127/192.168 等地址。${PLAIN}" "${YELLOW}If using the Cloudflare cloudlet, the public DNS should see the Cloudflare edge IP instead of 198.18/10/127/192.168 etc. addresses.${PLAIN}" "${YELLOW}При использовании облака Cloudflare общедоступный DNS должен видеть граничный IP-адрес Cloudflare вместо адресов 198.18/10/127/192.168 и т. д.${PLAIN}")"
        if [[ "$mode" == "prompt" ]]; then
            confirm_default_no "$(localized_text "仍要继续？(y/N，不推荐): " "Continue anyway? (y/N, not recommended): " "Всё равно продолжить? (y/N, не рекомендуется): ")" || return 1
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
    if [[ "$value" == */* ]]; then
        prefix="${value##*/}"
        [[ -n "$prefix" ]] || return 1
    fi

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
    local ip prefix remainder double_colon_count segment_count segment
    local -a ipv6_segments
    [[ -n "$value" ]] || return 1
    ip="${value%%/*}"
    prefix=""
    if [[ "$value" == */* ]]; then
        prefix="${value##*/}"
        [[ -n "$prefix" ]] || return 1
    fi

    [[ -n "$ip" ]] || return 1
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    remainder="$ip"
    double_colon_count=0
    while [[ "$remainder" == *"::"* ]]; do
        ((double_colon_count += 1))
        remainder="${remainder#*::}"
    done
    (( double_colon_count <= 1 )) || return 1

    segment_count=0
    IFS=':' read -ra ipv6_segments <<< "$ip"
    for segment in "${ipv6_segments[@]}"; do
        [[ -z "$segment" ]] && continue
        ((segment_count += 1))
        ((${#segment} <= 4)) || return 1
    done
    if (( double_colon_count == 0 )); then
        (( segment_count == 8 )) || return 1
    else
        (( segment_count < 8 )) || return 1
    fi
    if [[ -n "$prefix" ]]; then
        [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
        (( 10#$prefix >= 0 && 10#$prefix <= 128 )) || return 1
    fi
}

validate_ip_cidr_python() {
    local value="$1"
    python3 - "$value" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_network(sys.argv[1], strict=False)
except ValueError:
    sys.exit(1)
PY
}

is_valid_ip_cidr() {
    local value="$1"
    [[ -n "$value" && "$value" != *";"* && "$value" != *"{"* && "$value" != *"}"* ]] || return 1
    if command -v python3 >/dev/null 2>&1; then
        validate_ip_cidr_python "$value" && return 0
    fi
    is_valid_ipv4_cidr "$value" || is_valid_ipv6_cidr "$value"
}

normalize_ip_input() {
    local value
    value="$(trim_input "$1")"
    if declare -F normalize_ascii_digits >/dev/null 2>&1; then
        value="$(normalize_ascii_digits "$value")"
    fi
    value="${value//。/.}"
    value="${value//．/.}"
    value="${value//｡/.}"
    value="${value//：/:}"
    value=$(printf '%s' "$value" | sed 's#／#/#g')
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    value="${value#http://}"
    value="${value#https://}"
    value="${value%%\?*}"
    value="${value%%？*}"
    value="${value%%#*}"
    value="${value%%＃*}"
    value="${value%%/*}"
    value=$(echo "$value" | tr -d '[:space:]')
    if [[ "$value" =~ ^\[(.+)\](:[0-9]+)?$ ]]; then
        value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^(([0-9]{1,3}\.){3}[0-9]{1,3}):[0-9]+$ ]]; then
        value="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$value"
}

normalize_backend_addr_input() {
    local value
    value="$(normalize_ip_input "$1")"
    value="$(normalize_loopback_addr "$value")"
    if [[ "$value" =~ ^([^:]+):[0-9]+$ ]]; then
        value="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$value"
}

normalize_ip_whitelist_input() {
    local input="$1"
    local -n out_array=$2
    local item normalized seen
    if declare -F normalize_ascii_digits >/dev/null 2>&1; then
        input="$(normalize_ascii_digits "$input")"
    fi
    input="${input//。/.}"
    input="${input//．/.}"
    input="${input//｡/.}"
    input="${input//：/:}"
    input=$(printf '%s' "$input" | sed 's#／#/#g')
    input="${input//，/ }"
    input="${input//、/ }"
    input="${input//；/ }"
    input="${input//;/ }"
    input="${input//|/ }"
    input="${input//,/ }"
    input="${input//$'\r'/ }"
    input="${input//$'\n'/ }"
    input="${input//$'\t'/ }"
    out_array=()
    seen=" "
    for item in $input; do
        normalized=$(echo "$(trim_input "$item")" | tr '[:upper:]' '[:lower:]')
        if [[ "$normalized" =~ ^\[(.+)\](/.+)?$ ]]; then
            normalized="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        fi
        [[ -z "$normalized" ]] && continue
        if ! is_valid_ip_cidr "$normalized"; then
            echo -e "$(localized_text "${RED}❌ IP/CIDR 格式无效：${normalized}${PLAIN}" "${RED}❌ Invalid IP/CIDR format: ${normalized}${PLAIN}" "${RED}❌ Неверный формат IP/CIDR: ${normalized}.${PLAIN}")"
            return 1
        fi
        if [[ "$seen" != *" ${normalized} "* ]]; then
            out_array+=("$normalized")
            seen+=" ${normalized} "
        fi
    done
    [[ ${#out_array[@]} -gt 0 ]]
}

normalize_port_input() {
    local value port_candidate
    value="$(trim_input "$1")"
    if declare -F normalize_ascii_digits >/dev/null 2>&1; then
        value="$(normalize_ascii_digits "$value")"
    fi
    value="${value//：/:}"
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    value="${value#http://}"
    value="${value#https://}"
    value="${value%%\?*}"
    value="${value%%？*}"
    value="${value%%#*}"
    value="${value%%＃*}"
    value="${value%%/*}"
    value=$(echo "$value" | tr -d '[:space:]')
    value="${value%)}"
    value="${value%）}"
    value="${value%.}"
    value="${value%．}"
    value="${value%,}"
    value="${value%，}"
    value="${value%;}"
    value="${value%；}"
    if [[ "$value" == *:* ]]; then
        port_candidate="${value##*:}"
        [[ "$port_candidate" =~ ^[0-9]+$ ]] && value="$port_candidate"
    fi
    printf '%s' "$value"
}

is_valid_port() {
    local port
    port="$(normalize_port_input "$1")"
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

is_valid_backend_addr() {
    local addr="$1"
    [[ -n "$addr" ]] || return 1
    is_valid_listen_addr "$addr" || is_valid_hostname "$addr"
}

backend_addr_resolution_status() {
    local addr="$1"

    addr="${addr#[}"
    addr="${addr%]}"
    if is_valid_listen_addr "$addr"; then
        return 0
    fi
    if command -v getent >/dev/null 2>&1; then
        getent ahosts "$addr" >/dev/null 2>&1
        return $?
    fi
    return 2
}

tcp_target_reachable() {
    local host="$1"
    local port="$2"
    local attempted=0

    is_valid_port "$port" || return 1
    if command -v nc >/dev/null 2>&1; then
        attempted=1
        nc -z -w 3 "$host" "$port" >/dev/null 2>&1 && return 0
    fi
    if command -v timeout >/dev/null 2>&1; then
        attempted=1
        timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        attempted=1
        curl -fsS --connect-timeout 3 --max-time 5 "telnet://$(format_hostport "$host" "$port")" </dev/null >/dev/null 2>&1 && return 0
    fi
    [[ "$attempted" -eq 1 ]] && return 1
    return 2
}

probe_backend_target() {
    local label="$1"
    local addr="$2"
    local port="$3"
    local probe_rc

    if ! is_valid_backend_addr "$addr" || ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}❌ ${label}：后端地址或端口无效（$(format_hostport "$addr" "$port")）${PLAIN}" "${RED}❌ ${label}: Invalid backend address or port ($(format_hostport \"$addr\" \"$port\"))${PLAIN}" "${RED}❌ ${label}: Неверный внутренний адрес или порт ($(format_hostport \"$addr\" \"$port\"))${PLAIN}")"
        return 1
    fi

    if backend_addr_resolution_status "$addr"; then
        :
    else
        probe_rc=$?
        if [[ "$probe_rc" -eq 2 ]]; then
            echo -e "$(localized_text "${YELLOW}⚠️ ${label}：缺少地址解析工具，未检查 $(format_hostport "$addr" "$port")${PLAIN}" "${YELLOW}⚠️ ${label}: Missing address resolution tool, not checked $(format_hostport \"$addr\" \"$port\")${PLAIN}" "${YELLOW}⚠️ ${label}: Отсутствует инструмент разрешения адресов, не отмечен $(format_hostport \"$addr\" \"$port\")${PLAIN}")"
            return 2
        fi
        echo -e "$(localized_text "${RED}❌ ${label}：无法解析后端地址 ${addr}${PLAIN}" "${RED}❌ ${label}: Unable to resolve backend address ${addr}${PLAIN}" "${RED}❌ ${label}: невозможно разрешить внутренний адрес ${addr}${PLAIN}")"
        return 1
    fi

    if tcp_target_reachable "$addr" "$port"; then
        echo -e "$(localized_text "${GREEN}✅ ${label}：$(format_hostport "$addr" "$port") 可连接${PLAIN}" "${GREEN}✅ ${label}: $(format_hostport \"$addr\" \"$port\") is reachable${PLAIN}" "${GREEN}✅ ${label}: $(format_hostport \"$addr\" \"$port\") доступен${PLAIN}")"
        return 0
    fi
    probe_rc=$?
    if [[ "$probe_rc" -eq 2 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${label}：缺少 nc、timeout 或 curl，未检查 $(format_hostport "$addr" "$port")${PLAIN}" "${YELLOW}⚠️ ${label}: missing nc, timeout or curl, not checked $(format_hostport \"$addr\" \"$port\")${PLAIN}" "${YELLOW}⚠️ ${label}: отсутствует NC, тайм-аут или curl, не проверено $(format_hostport \"$addr\" \"$port\")${PLAIN}")"
        return 2
    fi
    echo -e "$(localized_text "${RED}❌ ${label}：$(format_hostport "$addr" "$port") 当前不可连接${PLAIN}" "${RED}❌ ${label}: $(format_hostport \"$addr\" \"$port\") is unreachable${PLAIN}" "${RED}❌ ${label}: $(format_hostport \"$addr\" \"$port\") недоступен${PLAIN}")"
    return 1
}

confirm_backend_target_or_continue() {
    local label="$1"
    local addr="$2"
    local port="$3"
    local probe_rc

    if probe_backend_target "$label" "$addr" "$port"; then
        return 0
    fi
    probe_rc=$?
    [[ "$probe_rc" -eq 2 ]] && return 0

    if confirm_default_no "$(localized_text "后端当前不可连接，仍要继续保存吗？(y/N，默认 N): " "The backend is unreachable. Save anyway? (y/N, default N): " "Бэкенд недоступен. Всё равно сохранить? (y/N, по умолчанию N): ")"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已选择继续；保存后请检查后端服务、地址和端口。${PLAIN}" "${YELLOW}⚠️ Selected to continue; please check the backend service, address and port after saving.${PLAIN}" "${YELLOW}⚠️ Выбрано для продолжения; пожалуйста, проверьте серверную службу, адрес и порт после сохранения.${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${BLUE}已取消保存。${PLAIN}" "${BLUE}Save canceled.${PLAIN}" "${BLUE}Сохранение отменено.${PLAIN}")"
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
    if declare -F normalize_ascii_digits >/dev/null 2>&1; then
        value="$(normalize_ascii_digits "$value")"
    fi
    value="${value//，/,}"
    value="${value//、/,}"
    value="${value//；/,}"
    value="${value//;/,}"
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
        confirm_risk_action "$(localized_text "${service_name} 监听公网 ${listen_addr}:${listen_port}" "${service_name} listens on the public ${listen_addr}:${listen_port}" "${service_name} прослушивает публичную сеть ${listen_addr}:${listen_port}")" \
            "$(localized_text "${service_name} 监听地址将从本地模型改为公网可访问" "${service_name} listening address will be changed from local model to public accessible" "Адрес прослушивания ${service_name} будет изменен с локальной модели на доступную публичную сеть.")" \
            "$(localized_text "改回 127.0.0.1 后重新应用配置并重启相关服务" "Change back to 127.0.0.1 and then reapply the configuration and restart related services." "Вернитесь к 127.0.0.1, затем повторно примените конфигурацию и перезапустите соответствующие службы.")" \
            "$(localized_text "仅在你明确需要公网直连该服务时继续。" "Only continue if you clearly need a direct public connection to the service." "Продолжайте только в том случае, если вам явно необходимо прямое подключение к службе через публичную сеть.")" || return 1
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

    if declare -F normalize_ascii_digits >/dev/null 2>&1; then
        raw="$(normalize_ascii_digits "$raw")"
    fi
    raw="${raw//。/.}"
    raw="${raw//．/.}"
    raw="${raw//｡/.}"
    raw="${raw//：/:}"
    raw=$(printf '%s' "$raw" | sed 's#／#/#g')
    raw="${raw//，/,}"
    raw="${raw//、/,}"
    raw="${raw//；/,}"
    raw="${raw//;/,}"
    raw="${raw//$'\r'/,}"
    raw="${raw//$'\n'/,}"
    raw="${raw// /,}"
    raw="${raw//$'\t'/,}"
    IFS=',' read -ra items <<< "$raw"

    for item in "${items[@]}"; do
        item="$(trim_input "$item")"
        if [[ "$item" =~ ^\[(.+)\]$ ]]; then
            item="${BASH_REMATCH[1]}"
        fi
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
