#!/usr/bin/env bash

# =========================================================
#  Project:  VPS Optimize
#  Generated: scripts/build.sh
#  Source modules: src/*.sh
#  Compatibility marker: VPS 全能控制面板
# =========================================================

# ---------------------------------------------------------
# Module: common.sh
# ---------------------------------------------------------
# shellcheck shell=bash
# Common constants, platform detection, package helpers, and remote script helpers.

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

SCRIPT_VERSION="v1.9"
UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh"
UPDATE_SHA256_URL="${UPDATE_URL}.sha256"
SCRIPT_UPDATE_CACHE="/etc/vps-optimize/update-check.cache"
TRAFFIC_GUARD_CONFIG="/etc/vps-optimize/traffic-guard.conf"
TRAFFIC_GUARD_CHECKER="/usr/local/bin/vps-traffic-guard-check"
TRAFFIC_GUARD_STATE_DIR="/var/lib/vps-optimize/traffic-guard"
TRAFFIC_GUARD_LOG="/var/log/vps-traffic-guard.log"
DNS_OPTIMIZE_BACKUP_DIR="/etc/vps-optimize/backups/dns"
DNS_OPTIMIZE_RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf"

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS=$ID
    OS_LIKE=${ID_LIKE:-""}
else
    OS="unknown"
    OS_LIKE="unknown"
fi

APT_UPDATED=0

is_debian() {
    [[ "$OS" =~ debian|ubuntu ]] || [[ "$OS_LIKE" =~ debian|ubuntu ]]
}

is_redhat() {
    [[ "$OS" =~ centos|rhel|rocky|almalinux|fedora ]] || [[ "$OS_LIKE" =~ centos|rhel|fedora ]]
}

apt_update_once() {
    [[ "$APT_UPDATED" == "1" ]] && return 0
    apt-get update -qq >/dev/null 2>&1 && APT_UPDATED=1
}

install_pkg() {
    local pkgs=("$@")
    local rc=0
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    if is_debian; then
        # 使用 apt-get 代替 apt，消除 "stable CLI interface" 警告 
        export DEBIAN_FRONTEND=noninteractive
        apt_update_once || true
        apt-get install -y -qq "${pkgs[@]}" >/dev/null 2>&1
        rc=$?
        unset DEBIAN_FRONTEND
    elif is_redhat; then
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y -q "${pkgs[@]}" >/dev/null 2>&1
        else
            yum install -y -q "${pkgs[@]}" >/dev/null 2>&1
        fi
        rc=$?
    fi
    return "$rc"
}

remove_pkg() {
    local pkgs=("$@")
    local rc=0
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y -qq "${pkgs[@]}" >/dev/null 2>&1
        rc=$?
        unset DEBIAN_FRONTEND
    elif is_redhat; then
        if command -v dnf >/dev/null 2>&1; then
            dnf remove -y -q "${pkgs[@]}" >/dev/null 2>&1
        else
            yum remove -y -q "${pkgs[@]}" >/dev/null 2>&1
        fi
        rc=$?
    fi
    return "$rc"
}

minimal_compat_packages() {
    if is_debian; then
        printf '%s\n' \
            ca-certificates curl wget gnupg gpg lsb-release apt-transport-https debian-archive-keyring \
            iproute2 iptables procps psmisc cron dbus chrony jq unzip tar gzip openssl
    elif is_redhat; then
        printf '%s\n' \
            ca-certificates curl wget gnupg2 redhat-lsb-core iproute iptables procps-ng psmisc cronie \
            dbus chrony jq unzip tar gzip openssl
    fi
}

ensure_minimal_system_compat() {
    local pkgs=()
    local pkg

    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && pkgs+=("$pkg")
    done < <(minimal_compat_packages)

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        echo -e "${CYAN}▶ 正在补齐精简系统兼容组件...${PLAIN}"
        if install_pkg "${pkgs[@]}"; then
            echo -e "${GREEN}✅ 精简系统兼容组件已检查/补齐。${PLAIN}"
        else
            echo -e "${YELLOW}⚠️ 部分兼容组件安装失败，请检查软件源或网络。${PLAIN}"
            echo -e "${CYAN}▶ 正在降级为逐个组件补齐，尽量提高兼容性...${PLAIN}"
            for pkg in "${pkgs[@]}"; do
                install_pkg "$pkg" || echo -e "${YELLOW}  - 跳过不可安装组件: ${pkg}${PLAIN}"
            done
        fi
    fi

    systemctl enable --now cron >/dev/null 2>&1 || true
    systemctl enable --now crond >/dev/null 2>&1 || true
    systemctl enable --now dbus >/dev/null 2>&1 || true
    systemctl enable --now chrony >/dev/null 2>&1 || true
    systemctl enable --now chronyd >/dev/null 2>&1 || true
    update-ca-certificates >/dev/null 2>&1 || update-ca-trust >/dev/null 2>&1 || true
}

create_shortcut() {
    local script_path="/usr/local/bin/cy"
    local release_path
    if [[ ! -f "$script_path" ]]; then
        # 优先尝试从远端直接拉取
        if ! download_remote_script "$UPDATE_URL" "$script_path" 2>/dev/null; then
            release_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/dist/vps.sh"
            if [[ -f "$release_path" ]]; then
                cp "$release_path" "$script_path" 2>/dev/null || {
                    echo -e "${YELLOW}⚠️ 快捷指令本地注册失败，请稍后在主菜单 [17] 更新脚本完成注册。${PLAIN}"
                    return
                }
            # 若远端拉取失败，且检测到 $0 确实是本地存在的物理文件，才允许复制
            elif [[ -f "$0" ]]; then
                cp "$(readlink -f "$0")" "$script_path" 2>/dev/null || {
                    echo -e "${YELLOW}⚠️ 快捷指令本地注册失败，请稍后在主菜单 [17] 更新脚本完成注册。${PLAIN}"
                    return
                }
            else
                echo -e "${YELLOW}⚠️ 快捷指令本地注册挂起，请稍后在主菜单 [17] 更新脚本完成注册。${PLAIN}"
                return
            fi
        fi
        if ! bash -n "$script_path" >/dev/null 2>&1; then
            quarantine_path "$script_path" "/tmp/vps-optimize-quarantine" >/dev/null 2>&1 || true
            echo -e "${RED}❌ 快捷指令脚本未通过语法检查，已隔离异常文件。${PLAIN}"
            return
        fi
        chmod +x "$script_path" || {
            echo -e "${YELLOW}⚠️ 快捷指令授权失败，请检查 /usr/local/bin 权限。${PLAIN}"
            return
        }
        echo -e "${GREEN}✅ 快捷指令 'cy' 已全局注册！下次可直接输入 cy 唤出面板。${PLAIN}"
        sleep 1
    fi
}

run_safe() {
    local desc="$1"
    shift
    echo -e "${CYAN}▶ 正在执行: ${desc}...${PLAIN}"
    # 丢弃正常输出保留错误输出，若执行失败则阻断并告警
    if "$@" >/dev/null; then
        echo -e "${GREEN}✅ ${desc} - 成功！${PLAIN}"
    else
        echo -e "${RED}❌ ${desc} - 失败！请检查系统网络或依赖源。${PLAIN}"
        return 1
    fi
}

restart_service_if_available() {
    local svc="$1"
    command -v systemctl >/dev/null 2>&1 || return 2
    if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q . || systemctl list-units "${svc}.service" --no-legend 2>/dev/null | grep -q .; then
        systemctl restart "$svc" >/dev/null 2>&1
    else
        return 2
    fi
}

download_remote_script() {
    local url="$1"
    local output_file="$2"
    local downloaded=1

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 缺少 curl/wget，正在尝试自动补齐下载工具...${PLAIN}"
        install_pkg curl wget >/dev/null 2>&1 || true
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 10 --max-time 90 --retry 2 --retry-delay 1 --retry-connrefused "$url" -o "$output_file"; then
            downloaded=0
        fi
    fi
    if [[ "$downloaded" -ne 0 ]] && command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=15 --tries=3 -O "$output_file" "$url"; then
            downloaded=0
        fi
    fi

    if [[ "$downloaded" -ne 0 ]]; then
        echo -e "${RED}❌ 下载远程脚本失败，请检查网络、DNS 或 GitHub 连通性。${PLAIN}"
        return 1
    fi
    [[ -s "$output_file" ]]
}

verify_file_sha256() {
    local file="$1"
    local checksum_file="$2"
    local expected check_file

    expected=$(awk 'NR == 1 {print $1}' "$checksum_file" 2>/dev/null | tr 'A-F' 'a-f')
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        echo -e "${RED}❌ sha256 校验文件格式无效：${checksum_file}${PLAIN}"
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        echo -e "${RED}❌ 当前系统缺少 sha256sum，无法校验更新包。${PLAIN}"
        return 1
    fi

    check_file=$(mktemp /tmp/cy_update_check.XXXXXX.sha256) || return 1
    printf '%s  %s\n' "$expected" "$file" > "$check_file"
    if ! sha256sum -c "$check_file" >/dev/null 2>&1; then
        rm -f "$check_file"
        echo -e "${RED}❌ sha256 校验失败，已拒绝覆盖 /usr/local/bin/cy。${PLAIN}"
        return 1
    fi
    rm -f "$check_file"

    echo -e "${GREEN}✅ sha256 校验通过。${PLAIN}"
}

run_remote_script() {
    local desc="$1"
    local url="$2"
    shift 2
    local tmp_file rc
    echo -e "${CYAN}▶ ${desc}${PLAIN}"
    echo -e "${YELLOW}脚本来源：${url}${PLAIN}"
    if [[ "$url" != https://* ]]; then
        echo -e "${YELLOW}⚠️ 该来源不是 HTTPS，将按脚本内置地址继续下载执行。${PLAIN}"
    fi

    tmp_file=$(mktemp /tmp/vps-remote.XXXXXX.sh) || {
        echo -e "${RED}❌ 临时文件创建失败，已取消执行。${PLAIN}"
        return 1
    }
    if ! download_remote_script "$url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ 下载失败，请检查网络或脚本来源。${PLAIN}"
        return 1
    fi
    if ! bash -n "$tmp_file" >/dev/null 2>&1; then
        echo -e "${RED}❌ 远程脚本未通过 Bash 语法检查，已中止执行。${PLAIN}"
        echo -e "${YELLOW}已保留下载文件用于排查：${tmp_file}${PLAIN}"
        return 1
    fi

    chmod +x "$tmp_file"
    bash "$tmp_file" "$@"
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

pause_after_external_script() {
    local prompt="${1:-按回车键继续...}"
    local junk

    if [[ -r /dev/tty ]]; then
        while IFS= read -r -s -n 1 -t 0.05 junk < /dev/tty; do :; done
        read -r -p "$prompt" junk < /dev/tty
    else
        read -r -p "$prompt" junk
    fi
}

install_acme_sh() {
    local acme_email="$1"
    local tmp_file rc
    tmp_file=$(mktemp /tmp/vps-acme.XXXXXX.sh)
    echo -e "${CYAN}▶ 正在安装 acme.sh...${PLAIN}"
    if ! download_remote_script "https://get.acme.sh" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ acme.sh 安装脚本下载失败。${PLAIN}"
        return 1
    fi
    if ! sh -n "$tmp_file" >/dev/null 2>&1; then
        echo -e "${RED}❌ acme.sh 安装脚本未通过 sh 语法检查，已中止。${PLAIN}"
        echo -e "${YELLOW}已保留下载文件用于排查：${tmp_file}${PLAIN}"
        return 1
    fi
    sh "$tmp_file" "email=${acme_email}" >/dev/null 2>&1
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

# ---------------------------------------------------------
# Module: ui.sh
# ---------------------------------------------------------
# shellcheck shell=bash
# UI output and confirmation helpers.

print_breadcrumb() {
    echo -e "${CYAN}VPS-Optimize > $*${PLAIN}"
}

pause_return() {
    local prompt="${1:-按任意键继续...}"
    read -n 1 -s -r -p "$prompt"
    echo ""
}

confirm_danger() {
    local title="$1"
    local impact="$2"
    local rollback="$3"
    local advice="${4:-}"
    local confirm
    echo -e "${RED}⚠️ 高风险操作：${title}${PLAIN}"
    echo ""
    echo -e "${YELLOW}即将修改：${PLAIN}"
    echo -e "- ${impact}"
    echo ""
    echo -e "${YELLOW}可能风险：${PLAIN}"
    echo "- 操作失败可能导致 SSH、面板、反代、证书、容器或网络服务短暂不可用。"
    echo "- 如果云厂商安全组、防火墙、监听地址或证书配置不匹配，可能导致远程访问中断。"
    echo ""
    echo -e "${BLUE}回滚方式：${PLAIN}"
    echo -e "- ${rollback}"
    echo "- 使用当前未断开的 SSH 会话恢复配置。"
    echo "- 使用云厂商控制台、VNC 或救援模式恢复。"
    echo "- 使用备份与回滚入口恢复已纳入备份的配置。"
    echo ""
    echo -e "${CYAN}建议：${PLAIN}"
    echo "- 已创建 VPS 快照。"
    echo "- 已确认云厂商安全组和系统防火墙规则。"
    echo "- 当前 SSH 会话不要断开。"
    [[ -n "$advice" ]] && echo -e "- ${advice}"
    echo ""
    read_trimmed confirm "继续请输入 YES，直接回车取消: "
    [[ "$confirm" == "YES" ]]
}

confirm_risk_action() {
    confirm_danger "$@"
}

# ---------------------------------------------------------
# Module: input.sh
# ---------------------------------------------------------
# shellcheck shell=bash
# Input normalization and prompt helpers.

trim_input() {
    local value="$*"
    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

read_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local __raw_input
    read -r -p "$prompt" __raw_input
    printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
}

read_secret_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local __raw_input
    read -r -s -p "$prompt" __raw_input
    echo ""
    printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
}

ask_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input
    read_trimmed input "${prompt} (默认: ${default_value}): "
    echo "${input:-$default_value}"
}

split_csv_to_array() {
    local input="$1"
    local -n out_array=$2
    local idx cleaned
    input="${input//，/,}"
    out_array=()
    local raw_array=()
    IFS=',' read -ra raw_array <<< "$input"
    for idx in "${!raw_array[@]}"; do
        cleaned=$(echo "${raw_array[$idx]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        [[ -n "$cleaned" ]] && out_array+=("$cleaned")
    done
}

split_pipe_to_array() {
    local input="$1"
    local -n out_array=$2
    local item cleaned
    local raw_array=()
    out_array=()
    IFS='|' read -ra raw_array <<< "$input"
    for item in "${raw_array[@]}"; do
        cleaned=$(trim_input "$item")
        [[ -n "$cleaned" ]] && out_array+=("$cleaned")
    done
}

# ---------------------------------------------------------
# Module: validate.sh
# ---------------------------------------------------------
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
    if [[ "$addr" == "::" || "$addr" == "::1" ]]; then
        echo "[${addr}]:${port}"
    else
        echo "${addr}:${port}"
    fi
}

nginx_stream_listen_directives() {
    local addr="$1"
    local port="$2"

    if [[ "$addr" == "::" || "$addr" == "::1" ]]; then
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

# ---------------------------------------------------------
# Module: rollback.sh
# ---------------------------------------------------------
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

    mkdir -p /etc/nginx/stream.d /etc/caddy/conf.d /etc/vps-optimize /etc/systemd/system /usr/local/bin
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

# ---------------------------------------------------------
# Module: backup.sh
# ---------------------------------------------------------
# shellcheck shell=bash
# Backup helpers and backup center entrypoint.

sni_stack_backup_dir() {
    echo "/etc/vps-optimize/backups/sni-stack_$(date +%Y%m%d_%H%M%S)"
}

create_sni_stack_backup() {
    local backup_dir
    backup_dir=$(sni_stack_backup_dir)
    mkdir -p "$backup_dir/nginx_stream.d" "$backup_dir/caddy_conf.d" "$backup_dir/vps-optimize" "$backup_dir/systemd" "$backup_dir/usr-local-bin" "$backup_dir/x-ui"
    [[ -f /etc/nginx/nginx.conf ]] && cp -a /etc/nginx/nginx.conf "$backup_dir/nginx.conf" 2>/dev/null || true
    [[ -d /etc/nginx/stream.d ]] && cp -a /etc/nginx/stream.d/vps_sni_*.conf "$backup_dir/nginx_stream.d/" 2>/dev/null || true
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

            "?"|help) show_backup_help ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac

        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# Module: main.sh
# ---------------------------------------------------------
# shellcheck shell=bash
# Main feature implementation. Shared helpers live in src/*.sh.

# --- Runtime guard ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 错误：请以 root 用户身份运行本脚本！${PLAIN}"
    exit 1
fi

configure_system_timezone_for_init() {
    local current_tz choice custom_tz target_tz

    if ! command -v timedatectl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 timedatectl，已保持当前系统时区。${PLAIN}"
        return 0
    fi

    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    [[ -z "$current_tz" ]] && current_tz="未设置/未知"

    echo -e "${CYAN}当前系统时区：${current_tz}${PLAIN}"
    echo -e "${GREEN}  1. 保持当前时区${PLAIN} ${YELLOW}(默认)${PLAIN}"
    echo -e "${GREEN}  2. Asia/Shanghai${PLAIN}"
    echo -e "${GREEN}  3. Asia/Tokyo${PLAIN}"
    echo -e "${GREEN}  4. UTC${PLAIN}"
    echo -e "${GREEN}  5. 自定义时区${PLAIN}"
    read_trimmed choice "请选择基础初始化时区处理方式（默认 1）: "

    case "${choice:-1}" in
        1)
            echo -e "${BLUE}已保持当前时区：${current_tz}${PLAIN}"
            return 0
            ;;
        2) target_tz="Asia/Shanghai" ;;
        3) target_tz="Asia/Tokyo" ;;
        4) target_tz="UTC" ;;
        5)
            read_trimmed custom_tz "请输入 IANA 时区名称（例如 Europe/London）: "
            target_tz="$custom_tz"
            ;;
        *)
            echo -e "${YELLOW}⚠️ 未选择有效选项，已保持当前时区：${current_tz}${PLAIN}"
            return 0
            ;;
    esac

    if [[ -z "$target_tz" ]]; then
        echo -e "${YELLOW}⚠️ 自定义时区为空，已保持当前时区：${current_tz}${PLAIN}"
        return 0
    fi

    if timedatectl set-timezone "$target_tz" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 系统时区已设置为：${target_tz}${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 时区设置失败，已保持当前时区：${current_tz}${PLAIN}"
    fi
}

func_base_init() {
    clear
    echo -e "${CYAN}👉 正在更新系统软件包、安装基础工具、限制日志并开启基础 BBR...${PLAIN}"
    
    # 更新系统软件包并优雅调用全局安装函数
    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y && apt-get upgrade -y && APT_UPDATED=1
        unset DEBIAN_FRONTEND
        install_pkg curl wget git nano unzip htop iptables iproute2 sqlite3 jq
    elif is_redhat; then
        yum update -y
        install_pkg curl wget git nano unzip htop iptables iproute epel-release sqlite jq
    fi

    ensure_minimal_system_compat

    # 限制系统日志最大 100M
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/99-limit.conf <<EOF
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=100M
EOF
    systemctl restart systemd-journald > /dev/null 2>&1
    
    # 时区默认保持当前设置，必要时由用户选择
    configure_system_timezone_for_init
    
    # 强制激活基础 BBR
    modprobe tcp_bbr >/dev/null 2>&1 # 先主动唤醒/加载 BBR 内核模块
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr-init.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-bbr-init.conf
    sysctl -p /etc/sysctl.d/99-bbr-init.conf > /dev/null 2>&1
    
    echo -e "${GREEN}✅ 基础初始化完成，原生 BBR 已激活！${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# ★ 防火墙专属管理面板 (安全追加模式 + 批量多端口支持)
# ---------------------------------------------------------
func_firewall_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "防火墙规则管理"
        echo -e "${BOLD}🛡️ 防火墙规则管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local fw_status
        local str_fw
        if [[ "$OS" =~ debian|ubuntu ]]; then
            fw_status=$(ufw status 2>/dev/null | grep -wi active)
        else
            fw_status=$(systemctl is-active firewalld 2>/dev/null)
        fi
        
        if [[ "$fw_status" == *"active"* ]]; then 
            str_fw="${GREEN}运行中${PLAIN}"
        else 
            str_fw="${RED}已关闭 / 未配置${PLAIN}"
        fi

        echo -e "当前防火墙状态: [ $str_fw ]"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 启用防火墙 + 自动放行当前公网端口${PLAIN} ${YELLOW}(不覆盖原有规则)${PLAIN}"
        echo -e "${GREEN}  2. 手动放行端口${PLAIN} ${YELLOW}(支持 80,443 或 8000-9000)${PLAIN}"
        echo -e "${GREEN}  3. 删除已放行端口${PLAIN} ${YELLOW}(支持批量/范围)${PLAIN}"
        echo -e "${GREEN}  4. 查看防火墙放行列表${PLAIN}"
        echo -e "${RED}  5. 关闭防火墙${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${BLUE}  0. 返回上一级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local fw_choice
        read_trimmed fw_choice "👉 请选择操作: "
        
        case $fw_choice in
            1)
                echo -e "${CYAN}👉 正在嗅探活动端口并配置防火墙...${PLAIN}"
                local active_ports
                active_ports=$(ss -tuln 2>/dev/null | grep -E 'LISTEN|UNCONN' | awk '{print $5}' | grep -Ev '^(127\.0\.0\.1:|\[?::1\]?:)' | rev | cut -d: -f1 | rev | sort -nu | grep -E '^[0-9]+$' || true)

                local ssh_port
                ssh_port=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
                [[ -z "$ssh_port" ]] && ssh_port=$(grep -i '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
                ssh_port=${ssh_port:-22}
                if is_valid_port "$ssh_port" && ! printf '%s\n' "$active_ports" | grep -qx "$ssh_port"; then
                    active_ports=$(printf '%s\n%s\n' "$active_ports" "$ssh_port" | grep -E '^[0-9]+$' | sort -nu)
                fi

                if [[ -z "$active_ports" ]]; then
                    echo -e "${RED}❌ 未能识别到需要放行的监听端口，已取消启用防火墙，避免误锁 SSH。${PLAIN}"
                    echo -e "${YELLOW}请先确认 ss/iproute2 可用，或使用 [2] 手动添加 SSH 端口后再启用。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    install_pkg ufw
                    ufw default deny incoming >/dev/null 2>&1
                    ufw default allow outgoing >/dev/null 2>&1
                    
                    for p in $active_ports; do ufw allow "$p" >/dev/null 2>&1; done
                    ufw --force enable >/dev/null 2>&1
                else
                    install_pkg firewalld
                    systemctl enable --now firewalld >/dev/null 2>&1
                    
                    for p in $active_ports; do
                        firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1
                        firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1
                    done
                    firewall-cmd --reload >/dev/null 2>&1
                fi
                echo -e "${GREEN}✅ 防火墙已成功配置！已为您安全追加放行了以下端口: $(echo "$active_ports" | tr '\n' ' ')${PLAIN}"
                sleep 2
                ;;
            2)
                local add_p
                echo -e "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}"
                read_trimmed add_p "👉 请输入要放行的端口号: "
                add_p=$(normalize_port_rule_input "$add_p")
                if [[ -z "$add_p" || "$add_p" == "0" ]]; then
                    echo -e "${BLUE}已取消添加端口规则。${PLAIN}"
                    sleep 1
                    continue
                fi
                
                # 放宽正则，允许数字、逗号、冒号和减号
                if is_valid_port_rule_input "$add_p"; then
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg ufw
                        if ! command -v ufw >/dev/null 2>&1; then
                            echo -e "${RED}❌ 未检测到 ufw，无法写入规则。${PLAIN}"
                            sleep 2
                            continue
                        fi
                        if ! ufw status 2>/dev/null | grep -qi active; then
                            echo -e "${YELLOW}⚠️ UFW 当前未启用，本次只写入规则；需要启用时请回到 [1] 自动放行活动端口。${PLAIN}"
                        fi
                    elif ! systemctl is-active --quiet firewalld 2>/dev/null; then
                        echo -e "${RED}❌ Firewalld 未运行。为避免误关端口，请先使用 [1] 启用并自动放行当前活动端口。${PLAIN}"
                        sleep 2
                        continue
                    fi
                    # 将输入的逗号分隔符转换为数组，按个循环处理
                    IFS=',' read -ra PORT_ARRAY <<< "$add_p"
                    for p in "${PORT_ARRAY[@]}"; do
                        if [[ "$OS" =~ debian|ubuntu ]]; then
                            # UFW 语法转换：将减号强转为冒号
                            local p_ufw="${p//-/:}"
                            if [[ "$p_ufw" == *":"* ]]; then
                                ufw allow "$p_ufw/tcp" >/dev/null 2>&1
                                ufw allow "$p_ufw/udp" >/dev/null 2>&1
                            else
                                ufw allow "$p_ufw" >/dev/null 2>&1
                            fi
                        else
                            # Firewalld 语法转换：将冒号强转为减号
                            local p_fwd="${p//:/-}"
                            firewall-cmd --permanent --add-port="${p_fwd}/tcp" >/dev/null 2>&1
                            firewall-cmd --permanent --add-port="${p_fwd}/udp" >/dev/null 2>&1
                        fi
                    done
                    
                    if [[ ! "$OS" =~ debian|ubuntu ]]; then
                        firewall-cmd --reload >/dev/null 2>&1
                    fi
                    
                    echo -e "${GREEN}✅ 端口规则 [$add_p] 已成功添加至允许列表！${PLAIN}"
                else
                    echo -e "${RED}❌ 无效的端口格式！端口必须是 1-65535，范围起始值不能大于结束值。${PLAIN}"
                fi
                sleep 2
                ;;
            3)
                local del_p
                echo -e "${YELLOW}💡 支持格式：单端口(80)、多端口(80,443)、端口范围(8000:9000 或 8000-9000)${PLAIN}"
                read_trimmed del_p "👉 请输入要删除放行的端口号: "
                del_p=$(normalize_port_rule_input "$del_p")
                if [[ -z "$del_p" || "$del_p" == "0" ]]; then
                    echo -e "${BLUE}已取消删除端口规则。${PLAIN}"
                    sleep 1
                    continue
                fi
                
                if is_valid_port_rule_input "$del_p"; then
                    confirm_risk_action "删除防火墙放行规则 ${del_p}" \
                        "系统防火墙端口放行规则" \
                        "重新进入防火墙菜单手动放行端口，或通过云厂商控制台/VNC 修复" \
                        "确认不会删除当前 SSH 端口或业务必需端口。" || {
                        echo -e "${BLUE}已取消删除端口规则。${PLAIN}"
                        sleep 1
                        continue
                    }
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg ufw
                        if ! command -v ufw >/dev/null 2>&1; then
                            echo -e "${RED}❌ 未检测到 ufw，无法删除规则。${PLAIN}"
                            sleep 2
                            continue
                        fi
                    elif ! systemctl is-active --quiet firewalld 2>/dev/null; then
                        echo -e "${RED}❌ Firewalld 未运行，无法读取/删除运行时规则。${PLAIN}"
                        sleep 2
                        continue
                    fi
                    IFS=',' read -ra PORT_ARRAY <<< "$del_p"
                    for p in "${PORT_ARRAY[@]}"; do
                        if [[ "$OS" =~ debian|ubuntu ]]; then
                            # UFW 语法转换：将减号强转为冒号
                            local p_ufw="${p//-/:}"
                            if [[ "$p_ufw" == *":"* ]]; then
                                ufw delete allow "$p_ufw/tcp" >/dev/null 2>&1
                                ufw delete allow "$p_ufw/udp" >/dev/null 2>&1
                            else
                                ufw delete allow "$p_ufw" >/dev/null 2>&1
                            fi
                        else
                            # Firewalld 语法转换：将冒号强转为减号
                            local p_fwd="${p//:/-}"
                            firewall-cmd --permanent --remove-port="${p_fwd}/tcp" >/dev/null 2>&1
                            firewall-cmd --permanent --remove-port="${p_fwd}/udp" >/dev/null 2>&1
                        fi
                    done
                    
                    if [[ ! "$OS" =~ debian|ubuntu ]]; then
                        firewall-cmd --reload >/dev/null 2>&1
                    fi
                    
                    echo -e "${GREEN}✅ 端口规则 [$del_p] 已成功从允许列表中移除！${PLAIN}"
                else
                    echo -e "${RED}❌ 无效的端口格式！端口必须是 1-65535，范围起始值不能大于结束值。${PLAIN}"
                fi
                sleep 2
                ;;
            4)
                echo -e "${CYAN}👇 当前防火墙规则列表：${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    ufw status numbered
                else
                    firewall-cmd --list-ports
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            5)
                confirm_risk_action "关闭系统防火墙" \
                    "ufw/firewalld 服务状态和系统侧访问控制" \
                    "重新启用防火墙并恢复放行规则；必要时从云厂商安全组限制暴露面" \
                    "确认关闭后不会暴露数据库、面板或内部服务。" || {
                    echo -e "${BLUE}已取消关闭防火墙。${PLAIN}"
                    sleep 1
                    continue
                }
                echo -e "${RED}⚠️ 正在关闭防火墙...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then
                    ufw disable >/dev/null 2>&1
                else
                    systemctl disable --now firewalld >/dev/null 2>&1
                fi
                echo -e "${GREEN}✅ 防火墙已彻底禁用！${PLAIN}"
                sleep 2
                ;;
            "?"|help) echo "防火墙菜单用于放行、删除、查看或关闭系统防火墙规则。删除规则和关闭防火墙都必须输入 YES。"; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

update_hosts_hostname_entry() {
    local old_name="$1"
    local new_name="$2"
    local tmp_file

    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    awk -v old="$old_name" -v new="$new_name" '
        BEGIN { updated = 0 }
        $1 == "127.0.1.1" {
            print "127.0.1.1\t" new
            updated = 1
            next
        }
        {
            for (i = 2; i <= NF; i++) {
                if ($i == old) {
                    $i = new
                    updated = 1
                }
            }
            print
        }
        END {
            if (!updated) {
                print "127.0.1.1\t" new
            }
        }
    ' /etc/hosts > "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
    }
    cp "$tmp_file" /etc/hosts
    rm -f "$tmp_file"
}

func_change_hostname() {
    local current_name new_name ts
    current_name=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
    current_name="$(trim_input "$current_name")"
    current_name="${current_name:-localhost}"

    echo -e "当前主机名: ${CYAN}${current_name}${PLAIN}"
    echo -e "${YELLOW}主机名建议只使用字母、数字、连字符和点号；每段不能以连字符开头或结尾。${PLAIN}"
    read_trimmed new_name "请输入新的主机名（回车取消）: "
    [[ -z "$new_name" || "$new_name" == "0" ]] && { echo -e "${BLUE}已取消修改主机名。${PLAIN}"; return 0; }

    if ! is_valid_hostname "$new_name"; then
        echo -e "${RED}❌ 主机名格式无效。示例：vps01 或 node-1.example.com${PLAIN}"
        return 1
    fi

    if [[ "$new_name" == "$current_name" ]]; then
        echo -e "${BLUE}主机名未变化。${PLAIN}"
        return 0
    fi

    confirm_risk_action "修改主机名为 ${new_name}" \
        "/etc/hostname、/etc/hosts 和当前运行时 hostname" \
        "使用本功能改回 ${current_name}，或从 /etc/*.bak_时间戳 恢复" \
        "少数服务会在重启后才读取新主机名。" || return 1

    ts=$(date +%s)
    [[ -f /etc/hostname ]] && cp -p /etc/hostname "/etc/hostname.bak_${ts}" 2>/dev/null || true
    [[ -f /etc/hosts ]] && cp -p /etc/hosts "/etc/hosts.bak_${ts}" 2>/dev/null || true

    echo "$new_name" > /etc/hostname || {
        echo -e "${RED}❌ 写入 /etc/hostname 失败。${PLAIN}"
        return 1
    }

    if [[ -f /etc/hosts ]]; then
        update_hosts_hostname_entry "$current_name" "$new_name" || echo -e "${YELLOW}⚠️ /etc/hosts 更新失败，请稍后手动检查。${PLAIN}"
    else
        {
            echo "127.0.0.1	localhost"
            echo "127.0.1.1	$new_name"
        } > /etc/hosts
    fi

    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$new_name" >/dev/null 2>&1 || hostname "$new_name" 2>/dev/null || true
    else
        hostname "$new_name" 2>/dev/null || true
    fi

    echo -e "${GREEN}✅ 主机名已修改为：${new_name}${PLAIN}"
    echo -e "${YELLOW}如部分服务仍显示旧名称，重启对应服务或下次重启系统后会完全生效。${PLAIN}"
}

hosts_managed_marker() {
    printf '%s' '# VPS-Optimize local-hosts'
}

hosts_is_valid_ip() {
    local ip="$1"
    [[ "$ip" != */* ]] || return 1
    dns_is_valid_ipv4 "$ip" || dns_is_valid_ipv6 "$ip"
}

hosts_normalize_names() {
    local raw="$1"
    local -n out_array=$2
    local item normalized seen=" "
    raw="${raw//，/,}"
    raw="${raw//;/,}"
    raw="${raw//,/ }"
    out_array=()
    for item in $raw; do
        normalized=$(echo "$(trim_input "$item")" | tr '[:upper:]' '[:lower:]')
        [[ -z "$normalized" ]] && continue
        if ! is_valid_hostname "$normalized"; then
            echo -e "${RED}❌ 主机名/域名格式无效：${normalized}${PLAIN}"
            return 1
        fi
        case "$normalized" in
            localhost|localhost.localdomain|ip6-localhost|ip6-loopback)
                echo -e "${RED}❌ 为避免破坏系统解析，不能管理保留名称：${normalized}${PLAIN}"
                return 1
                ;;
        esac
        if [[ "$seen" != *" ${normalized} "* ]]; then
            out_array+=("$normalized")
            seen+=" ${normalized} "
        fi
    done
    [[ ${#out_array[@]} -gt 0 ]]
}

hosts_backup_current() {
    local backup_dir="/etc/vps-optimize/backups/hosts"
    local backup_file
    mkdir -p "$backup_dir" || return 1
    backup_file="${backup_dir}/hosts.$(date +%Y%m%d_%H%M%S).bak"
    if [[ -f /etc/hosts ]]; then
        cp -p /etc/hosts "$backup_file" || return 1
    else
        : > "$backup_file" || return 1
    fi
    printf '%s' "$backup_file"
}

hosts_remove_names_to_tmp() {
    local names_csv="$1"
    local tmp_file="$2"
    local hosts_file="/etc/hosts"
    [[ -f "$hosts_file" ]] || : > "$hosts_file"
    awk -v names_csv="$names_csv" '
        BEGIN {
            split(names_csv, names, ",")
            for (i in names) target[names[i]] = 1
        }
        /^[[:space:]]*#/ || NF == 0 { print; next }
        {
            keep = 0
            line = $1
            for (i = 2; i <= NF; i++) {
                if ($i == "#") break
                if (!($i in target)) {
                    line = line "\t" $i
                    keep = 1
                }
            }
            if (keep) print line
        }
    ' "$hosts_file" > "$tmp_file"
}

hosts_add_or_update_entry() {
    local ip names_input names_csv names_joined backup_file tmp_file
    local -a names=()
    read_trimmed ip "请输入解析 IP（IPv4/IPv6）: "
    if ! hosts_is_valid_ip "$ip"; then
        echo -e "${RED}❌ IP 格式无效。${PLAIN}"
        return 1
    fi
    read_trimmed names_input "请输入要绑定的域名/主机名（多个用空格或逗号分隔）: "
    if ! hosts_normalize_names "$names_input" names; then
        return 1
    fi
    names_csv=$(IFS=','; printf '%s' "${names[*]}")
    names_joined=$(IFS=' '; printf '%s' "${names[*]}")
    confirm_risk_action "写入本机 hosts 解析" \
        "/etc/hosts 本机解析表" \
        "从 /etc/vps-optimize/backups/hosts 恢复最近备份，或在本菜单删除对应条目" \
        "本功能只影响当前 VPS 本机解析，不会修改公网 DNS。" || return 1

    backup_file=$(hosts_backup_current) || {
        echo -e "${RED}❌ /etc/hosts 备份失败，已取消。${PLAIN}"
        return 1
    }
    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    if hosts_remove_names_to_tmp "$names_csv" "$tmp_file"; then
        printf '%s\t%s\t%s\n' "$ip" "$names_joined" "$(hosts_managed_marker)" >> "$tmp_file"
        cp "$tmp_file" /etc/hosts
        echo -e "${GREEN}✅ 已写入本机 hosts：${ip} -> ${names_joined}${PLAIN}"
        echo -e "${CYAN}备份已保留：${backup_file}${PLAIN}"
    else
        echo -e "${RED}❌ 生成 hosts 临时文件失败，已取消。${PLAIN}"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"
}

hosts_remove_entry() {
    local names_input names_csv names_joined backup_file tmp_file
    local -a names=()
    read_trimmed names_input "请输入要删除解析的域名/主机名（多个用空格或逗号分隔）: "
    if ! hosts_normalize_names "$names_input" names; then
        return 1
    fi
    names_csv=$(IFS=','; printf '%s' "${names[*]}")
    names_joined=$(IFS=' '; printf '%s' "${names[*]}")
    confirm_risk_action "删除本机 hosts 解析" \
        "/etc/hosts 中与 ${names_joined} 匹配的解析项" \
        "从 /etc/vps-optimize/backups/hosts 恢复最近备份" \
        "只删除匹配主机名，保留同一行其他别名。" || return 1

    backup_file=$(hosts_backup_current) || {
        echo -e "${RED}❌ /etc/hosts 备份失败，已取消。${PLAIN}"
        return 1
    }
    tmp_file=$(mktemp /tmp/vps-hosts.XXXXXX) || return 1
    if hosts_remove_names_to_tmp "$names_csv" "$tmp_file"; then
        cp "$tmp_file" /etc/hosts
        echo -e "${GREEN}✅ 已删除匹配的本机 hosts 解析：${names_joined}${PLAIN}"
        echo -e "${CYAN}备份已保留：${backup_file}${PLAIN}"
    else
        echo -e "${RED}❌ 生成 hosts 临时文件失败，已取消。${PLAIN}"
        rm -f "$tmp_file"
        return 1
    fi
    rm -f "$tmp_file"
}

hosts_restore_latest_backup() {
    local latest
    latest=$(find /etc/vps-optimize/backups/hosts -maxdepth 1 -type f -name 'hosts.*.bak' 2>/dev/null | sort -r | head -n1)
    if [[ -z "$latest" ]]; then
        echo -e "${YELLOW}未找到 hosts 备份。${PLAIN}"
        return 1
    fi
    confirm_risk_action "恢复最近 hosts 备份" \
        "/etc/hosts 将恢复为 ${latest}" \
        "重新进入本菜单添加/删除解析，或手动恢复更新前备份" \
        "恢复会覆盖当前本机 hosts 解析。" || return 1
    cp -p "$latest" /etc/hosts || {
        echo -e "${RED}❌ 恢复失败。${PLAIN}"
        return 1
    }
    echo -e "${GREEN}✅ 已恢复：${latest}${PLAIN}"
}

func_hosts_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "系统开关与清理 > 本机 hosts 解析"
        echo -e "${BOLD}🧭 本机 hosts 解析管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：修改当前 VPS 的 /etc/hosts，本地指定域名解析到某个 IP。不会影响公网 DNS。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前 hosts${PLAIN}"
        echo -e "${GREEN}  2. 添加 / 更新本机解析${PLAIN}"
        echo -e "${YELLOW}  3. 删除本机解析${PLAIN}"
        echo -e "${CYAN}  4. 恢复最近一次 hosts 备份${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                echo -e "${CYAN}--- /etc/hosts ---${PLAIN}"
                sed -n '1,120p' /etc/hosts 2>/dev/null || echo "未检测到 /etc/hosts"
                pause_return
                ;;
            2) hosts_add_or_update_entry; pause_return ;;
            3) hosts_remove_entry; pause_return ;;
            4) hosts_restore_latest_backup; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 2. 系统高级开关 (已修复显示丢失问题)
# ---------------------------------------------------------
func_system_tweaks() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}⚙️ 系统开关与清理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        # 状态获取
        local ipv6_status
        local str_ipv6
        ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
        if [[ "$ipv6_status" == "0" ]]; then str_ipv6="${GREEN}开启中${PLAIN}"; else str_ipv6="${RED}已禁用${PLAIN}"; fi
        
        local str_ipv4_first
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then 
            str_ipv4_first="${GREEN}已优先${PLAIN}"
        else 
            str_ipv4_first="${RED}默认(IPv6优先)${PLAIN}"
        fi
        
        local ping_status
        local str_ping
        ping_status=$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null)
        if [[ "$ping_status" == "0" ]]; then str_ping="${GREEN}允许被Ping${PLAIN}"; else str_ping="${RED}禁Ping中${PLAIN}"; fi
        
        local update_status
        local str_update
        if [[ "$OS" =~ debian|ubuntu ]]; then
            update_status=$(systemctl is-active unattended-upgrades 2>/dev/null)
        else
            update_status=$(systemctl is-active dnf-automatic.timer 2>/dev/null)
        fi
        if [[ "$update_status" == "active" ]]; then str_update="${GREEN}开启中${PLAIN}"; else str_update="${RED}已关闭${PLAIN}"; fi

        local current_hostname
        current_hostname=$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
        current_hostname="$(trim_input "$current_hostname")"
        current_hostname="${current_hostname:-未知}"

        # 完美修复：一字不落的菜单显示
        echo -e "${GREEN}  1. IPv6 开关${PLAIN}              当前: [ $str_ipv6 ]"
        echo -e "${GREEN}  2. IPv4 出站优先${PLAIN}          当前: [ $str_ipv4_first ]"
        echo -e "${GREEN}  3. Ping 响应开关${PLAIN}          当前: [ $str_ping ]"
        echo -e "${GREEN}  4. 自动安全更新开关${PLAIN}       当前: [ $str_update ]"
        echo -e "${GREEN}  5. 清理系统垃圾${PLAIN}           (日志/缓存/无用包)"
        echo -e "${GREEN}  6. 修改主机名${PLAIN}             当前: [ ${CYAN}${current_hostname}${PLAIN} ]"
        echo -e "${GREEN}  7. 本机 hosts 解析管理${PLAIN}    (/etc/hosts 本机域名解析)"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local tweak_choice
        read_trimmed tweak_choice "👉 请选择操作: "
        
        case $tweak_choice in
            1)
                read_trimmed yn "❓ 开启 IPv6？(y 开启 / n 关闭): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    quarantine_path /etc/sysctl.d/99-disable-ipv6.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ IPv6 已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/sysctl.d/99-disable-ipv6.conf ]] && cp -p /etc/sysctl.d/99-disable-ipv6.conf "/etc/sysctl.d/99-disable-ipv6.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.d/99-disable-ipv6.conf
                    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1
                    echo -e "${RED}✅ IPv6 已禁用${PLAIN}"
                fi; sleep 1 ;;
            2)
                read_trimmed yn "❓ 设置 IPv4 为最高出站优先级？(y 开启 / n 恢复默认): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -Ei '/^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+100\b.*?$/ {s/.+100\b([[:space:]]*#.*)?$/precedence ::ffff:0:0\/96  100\1/; :a;n;b a}; /^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+.*$/ {s/^.*precedence.+::ffff:0:0\/96[^0-9]+([0-9]+).*$/precedence ::ffff:0:0\/96  100\t#原值为 \1/; :a;n;ba;}; $aprecedence ::ffff:0:0\/96  100' /etc/gai.conf
                    echo -e "${GREEN}✅ 已设为 IPv4 优先${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/gai.conf ]] || touch /etc/gai.conf
                    cp -p /etc/gai.conf "/etc/gai.conf.bak_$(date +%s)" 2>/dev/null || true
                    sed -i '/precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
                    echo -e "${BLUE}已恢复系统默认${PLAIN}"
                fi; sleep 1 ;;
            3)
                read_trimmed yn "❓ 允许被 Ping？(y 允许 / n 禁止): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    quarantine_path /etc/sysctl.d/99-disable-ping.conf "/etc/vps-optimize/quarantine/sysctl" >/dev/null 2>&1 || true
                    sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
                    echo -e "${GREEN}✅ 已允许被 Ping${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    [[ -f /etc/sysctl.d/99-disable-ping.conf ]] && cp -p /etc/sysctl.d/99-disable-ping.conf "/etc/sysctl.d/99-disable-ping.conf.bak_$(date +%s)" 2>/dev/null || true
                    echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-ping.conf
                    sysctl -p /etc/sysctl.d/99-disable-ping.conf >/dev/null 2>&1
                    echo -e "${RED}✅ 已开启禁 Ping 保护${PLAIN}"
                fi; sleep 1 ;;
            4)
                read_trimmed yn "❓ 开启系统自动更新？(y 开启 / n 关闭): "
                if [[ "$yn" =~ ^[Yy]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then
                        install_pkg unattended-upgrades || { echo -e "${RED}❌ unattended-upgrades 安装失败。${PLAIN}"; sleep 1; continue; }
                        systemctl enable --now unattended-upgrades >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ unattended-upgrades 服务启用失败，请手动检查。${PLAIN}"
                    else
                        install_pkg dnf-automatic || { echo -e "${RED}❌ dnf-automatic 安装失败。${PLAIN}"; sleep 1; continue; }
                        systemctl enable --now dnf-automatic.timer >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ dnf-automatic.timer 启用失败，请手动检查。${PLAIN}"
                    fi
                    echo -e "${GREEN}✅ 自动更新已开启${PLAIN}"
                elif [[ "$yn" =~ ^[Nn]$ ]]; then 
                    if [[ "$OS" =~ debian|ubuntu ]]; then systemctl disable --now unattended-upgrades >/dev/null 2>&1
                    else systemctl disable --now dnf-automatic.timer >/dev/null 2>&1; fi
                    echo -e "${GREEN}✅ 自动更新已关闭${PLAIN}"
                fi; sleep 1 ;;
            5) 
                echo -e "${CYAN}👉 正在深度清理系统垃圾...${PLAIN}"
                if [[ "$OS" =~ debian|ubuntu ]]; then 
                    apt autoremove --purge -y >/dev/null 2>&1
                    apt clean >/dev/null 2>&1
                else 
                    yum autoremove -y >/dev/null 2>&1
                    yum clean all >/dev/null 2>&1
                fi
                journalctl --vacuum-time=1d > /dev/null 2>&1
                echo -e "${GREEN}✅ 清理完成！${PLAIN}"
                sleep 1 ;;
            6) func_change_hostname; sleep 1 ;;
            7) func_hosts_manage ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 统一包管理与执行守卫 (新增：请放在 func_env_install 函数上方)
# ---------------------------------------------------------














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

    local domain port is_https
    read_trimmed domain "请输入解析后的域名 (如 panel.site.com): "
    read_trimmed port "请输入面板本地映射端口 (如 40000): "
    domain=$(normalize_domain_input "$domain")

    if ! is_valid_domain "$domain" || ! is_valid_port "$port"; then
        echo -e "${RED}❌ 域名或端口格式错误！域名不要带 http(s)://、路径或端口，端口必须是 1-65535。${PLAIN}"
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
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
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

    if [[ "$is_https" =~ ^[Yy]$ ]]; then
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

func_caddy_reverse_proxy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "普通 Caddy 反代"
        echo -e "${BOLD}🌐 普通 Caddy 反代${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：管理未接入 443 单入口的普通 Caddy 域名反代。443 单入口请只走主菜单 [19]。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 添加普通 Caddy 反代${PLAIN}"
        echo -e "${CYAN}  2. 查看 Caddy 证书路径${PLAIN}"
        echo -e "${CYAN}  3. Caddy 跳过后端证书校验${PLAIN} ${YELLOW}(后端自签 HTTPS 时使用)${PLAIN}"
        echo -e "${CYAN}  4. 普通 Caddy 域名 IP 白名单${PLAIN}"
        echo -e "${RED}  5. 清空 Caddy 配置${PLAIN}"
        echo -e "${RED}  6. 删除底层 ACME 证书${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local caddy_choice
        read_trimmed caddy_choice "👉 请选择操作: "
        case "$caddy_choice" in
            1) func_caddy_add_reverse_proxy ;;
            2) func_view_caddy_cert ;;
            3) func_caddy_add_insecure ;;
            4) func_caddy_manage_ip_whitelist ;;
            5) func_caddy_clear_config ;;
            6) func_caddy_delete_cert ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        pause_return "按任意键继续..."
    done
}

func_env_install() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "基础组件与常用服务"
        echo -e "${BOLD}📦 基础组件与常用服务${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：安装基础组件、转发隧道和常用服务。普通 Caddy 反代走主菜单 [4]，443 单入口只走主菜单 [19]。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 基础运行环境${PLAIN}"
        echo -e "${GREEN}  1. Docker 引擎        ${YELLOW}  2. Python 环境        ${GREEN}  3. iperf3 测速工具${PLAIN}"
        echo -e "${BOLD}${BLUE}▶ 转发、隧道与常用服务${PLAIN}"
        echo -e "${GREEN}  4. Realm 端口转发     ${YELLOW}  5. Gost 隧道          ${GREEN}  6. 极光面板${PLAIN}"
        echo -e "${GREEN}  7. 哪吒监控           ${YELLOW}  8. WARP 解锁/网络     ${GREEN}  9. Aria2 下载${PLAIN}"
        echo -e "${GREEN} 10. 宝塔面板           ${YELLOW} 11. PVE 虚拟化工具     ${GREEN} 12. Argox 节点${PLAIN}"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local env_choice
        read_trimmed env_choice "👉 选择: "
        
        case $env_choice in
            1) 
                echo -e "${CYAN}▶ 正在拉取 Docker 引擎...${PLAIN}"
                run_remote_script "安装 Docker 引擎" "https://get.docker.com" || echo -e "${RED}❌ Docker 安装失败，请检查网络！${PLAIN}"
                ;;
            2) run_remote_script "安装 Python 环境" "https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh" ;;
            3) run_safe "安装 iperf3" install_pkg iperf3 ;;
            4) run_remote_script "安装 Realm 端口转发" "https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh" -i ;;
            5) run_remote_script "安装 Gost 隧道" "https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh" ;;
            6) run_remote_script "安装极光面板" "https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh" ;;
            7) 
                if run_remote_script "安装哪吒监控" "https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh"; then
                    echo -e "\n${YELLOW}💡 哪吒自定义代码提示 (去除动效并固定顶部)：${PLAIN}"
                    echo -e "${GREEN}<script>\nwindow.ShowNetTransfer = true;\nwindow.FixedTopServerName = true;\nwindow.DisableAnimatedMan = true;\n</script>${PLAIN}"
                fi
                ;;
            8) run_remote_script "安装 WARP 解锁/网络工具" "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" ;;
            9) run_remote_script "安装 Aria2 下载工具" "https://git.io/aria2.sh" ;;
            10) run_remote_script "安装宝塔面板" "http://v7.hostcli.com/install/install-ubuntu_6.0.sh" ;;
            11) run_remote_script "安装 PVE 虚拟化工具" "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh" ;;
            12) run_remote_script "安装 Argox 节点" "https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh" ;;
            "?"|help) echo "基础组件菜单只安装 Docker、Python、WARP、转发隧道和常用服务。普通 Caddy 反代走主菜单 [4]；443 单入口走主菜单 [19]。"; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}" ;;
        esac
        echo ""
        pause_after_external_script "按回车键继续..."
    done
}

# ---------------------------------------------------------
# 旧版 Reality+CF 向导已禁用，菜单 [19] 使用下方新的 SNI stack 向导。
# ---------------------------------------------------------
func_caddy_cf_reality_wizard_legacy_disabled() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧩 Reality 443 复用 + Cloudflare DNS 自动化向导${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}本向导会让 Caddy 仅监听本地端口，不占用公网 80/443。${PLAIN}"
    echo -e "${YELLOW}推荐用于：3x-ui Reality 已占用 443，同时 Web 服务需要同域名 HTTPS。${PLAIN}"
    echo -e "------------------------------------------------"

    read_trimmed reality_occupied "❓ 当前 443 端口是否已被 3x-ui VLESS-Reality 占用？(y/n): "
    if [[ "$reality_occupied" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}ℹ️ 您选择了未占用 443，本向导仍将使用本地端口模式，避免与未来业务冲突。${PLAIN}"
    fi

    local listen_port
    read_trimmed listen_port "👉 请输入 Caddy 本地 TLS 监听端口 (默认 8443): "
    listen_port=${listen_port:-8443}
    if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [[ "$listen_port" -lt 1 || "$listen_port" -gt 65535 ]]; then
        echo -e "${RED}❌ 监听端口无效！必须是 1-65535 的纯数字。${PLAIN}"
        return
    fi
    if [[ "$reality_occupied" =~ ^[Yy]$ ]] && [[ "$listen_port" -eq 443 ]]; then
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
        local domain backend_port continue_add
        read_trimmed domain "👉 请输入域名 (回车结束添加): "
        domain=$(normalize_domain_input "$domain")
        if [[ -z "$domain" ]]; then
            break
        fi

        if ! is_valid_domain "$domain"; then
            echo -e "${RED}❌ 域名格式无效：$domain${PLAIN}"
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
        if [[ ! "$continue_add" =~ ^[Yy]$ ]]; then
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







detect_vps_public_ip_by_family() {
    local family="$1"
    local curl_flag="-4"
    local endpoint ip
    local endpoints=()

    command -v curl >/dev/null 2>&1 || return 1

    if [[ "$family" == "6" ]]; then
        curl_flag="-6"
        endpoints=("https://api6.ipify.org" "https://ipv6.icanhazip.com")
    else
        endpoints=("https://api.ipify.org" "https://ipv4.icanhazip.com")
    fi

    for endpoint in "${endpoints[@]}"; do
        ip=$(curl "$curl_flag" -fsS --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
        ip=$(trim_input "$ip")
        if [[ "$family" == "6" ]]; then
            is_valid_ipv6_cidr "$ip" && { echo "$ip"; return 0; }
        else
            is_valid_ipv4_cidr "$ip" && ! is_suspicious_public_ipv4 "$ip" && { echo "$ip"; return 0; }
        fi
    done
    return 1
}

append_vps_public_ips_to_whitelist() {
    local -n out_array=$1
    local ip existing seen added=0
    seen=" "
    for existing in "${out_array[@]}"; do
        seen+=" ${existing} "
    done

    for ip in "$(detect_vps_public_ip_by_family 4 2>/dev/null)" "$(detect_vps_public_ip_by_family 6 2>/dev/null)"; do
        [[ -n "$ip" ]] || continue
        if [[ "$seen" != *" ${ip} "* ]]; then
            out_array+=("$ip")
            seen+=" ${ip} "
            echo -e "${GREEN}✅ 已自动加入 VPS 本机公网 IP：${ip}${PLAIN}"
            added=1
        fi
    done

    if [[ "$added" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ 未能自动获取 VPS 本机公网 IP；如需要本机自测访问，请手动加入 VPS 公网 IP。${PLAIN}"
    fi

    append_local_service_ips_to_whitelist "$1" seen
}

append_local_service_ips_to_whitelist() {
    local -n out_array=$1
    local -n seen_ref=$2
    local entry subnet local_added=0
    local -a local_ranges=("127.0.0.1/32" "::1/128")

    if command -v docker >/dev/null 2>&1; then
        while IFS= read -r subnet; do
            subnet=$(trim_input "$subnet")
            [[ -n "$subnet" ]] && local_ranges+=("$subnet")
        done < <(docker network inspect $(docker network ls -q 2>/dev/null) \
            --format '{{range .IPAM.Config}}{{if .Subnet}}{{.Subnet}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u)
    fi

    for entry in "${local_ranges[@]}"; do
        [[ -n "$entry" ]] || continue
        is_valid_ip_cidr "$entry" || continue
        if [[ "$seen_ref" != *" ${entry} "* ]]; then
            out_array+=("$entry")
            seen_ref+=" ${entry} "
            echo -e "${GREEN}✅ 已自动加入本机/容器访问来源：${entry}${PLAIN}"
            local_added=1
        fi
    done

    if [[ "$local_added" -eq 0 ]]; then
        echo -e "${BLUE}ℹ️ 本机/容器访问来源已在白名单中，无需重复加入。${PLAIN}"
    fi
}

join_array_by_space() {
    local IFS=' '
    echo "$*"
}

detect_ssh_client_ip() {
    local client_ip=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        client_ip="${SSH_CONNECTION%% *}"
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        client_ip="${SSH_CLIENT%% *}"
    fi
    echo "$client_ip"
}

caddy_ip_whitelist_block() {
    local ranges="$1"
    [[ -z "$ranges" ]] && return 0
    cat <<EOF
    # vps-optimize-ip-whitelist-start
    @vps_ip_denied not remote_ip ${ranges}
    abort @vps_ip_denied
    # vps-optimize-ip-whitelist-end

EOF
}













find_xui_database_candidates() {
    local db_path extra_db
    local seen_dbs=" "
    local db_candidates=(
        "/etc/x-ui/x-ui.db"
        "/usr/local/x-ui/x-ui.db"
        "/usr/local/x-ui/bin/x-ui.db"
        "/etc/x-panel/x-panel.db"
    )

    for db_path in "${db_candidates[@]}"; do
        [[ -f "$db_path" ]] || continue
        [[ "$seen_dbs" == *" ${db_path} "* ]] && continue
        seen_dbs+=" ${db_path} "
        echo "$db_path"
    done

    while IFS= read -r extra_db; do
        [[ -f "$extra_db" ]] || continue
        [[ "$seen_dbs" == *" ${extra_db} "* ]] && continue
        seen_dbs+=" ${extra_db} "
        echo "$extra_db"
    done < <(find /etc /usr/local/x-ui /opt -maxdepth 4 -type f \( -name "x-ui.db" -o -name "x-panel.db" \) 2>/dev/null | sort -u)
}

check_xui_cert_settings_for_single_443() {
    local cert_key_sql db_path rows key value
    local checked=0 found=0

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 sqlite3，跳过 3x-ui 证书路径数据库检查。${PLAIN}"
        return 2
    fi

    cert_key_sql=$(xui_cert_setting_key_sql_list)
    while IFS= read -r db_path; do
        [[ -n "$db_path" ]] || continue
        checked=1
        rows=$(sqlite3 -separator '|' "$db_path" "select key,value from settings where lower(key) in (${cert_key_sql}) and length(trim(coalesce(value,''))) > 0;" 2>/dev/null || true)
        [[ -n "$rows" ]] || continue

        found=1
        echo -e "${YELLOW}⚠️ ${db_path} 仍有 3x-ui 面板/订阅证书路径，443 单入口下建议清空：${PLAIN}"
        while IFS='|' read -r key value; do
            [[ -n "$key" ]] || continue
            echo -e "  ${key}=${value}"
        done <<< "$rows"
    done < <(find_xui_database_candidates)

    if [[ "$checked" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ 未找到 3x-ui 数据库，跳过证书路径检查。${PLAIN}"
        return 2
    fi

    if [[ "$found" -eq 1 ]]; then
        echo -e "${YELLOW}建议：进入 [5] -> [11] 面板救砖 / SSL 清理，或在 3x-ui 面板里清空证书路径并重启。${PLAIN}"
        return 1
    fi

    echo -e "${GREEN}✅ 3x-ui 面板/订阅证书路径未发现残留${PLAIN}"
    return 0
}





cleanup_old_nginx_sni_stream_configs() {
    mkdir -p /etc/nginx/stream.d
    local old_dir="/etc/nginx/stream.d/backup_vps_sni_$(date +%Y%m%d_%H%M%S)"
    local moved=0
    while IFS= read -r conf_file; do
        mkdir -p "$old_dir"
        mv "$conf_file" "$old_dir/" >/dev/null 2>&1 && ((moved++))
    done < <(find /etc/nginx/stream.d -maxdepth 1 -type f -name 'vps_sni_*.conf' 2>/dev/null | sort)
    if [[ "$moved" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ 已隔离 ${moved} 个旧 Nginx SNI 配置到：${old_dir}${PLAIN}"
    fi
}

probe_reality_sni() {
    local sni="$1"
    echo -e "${CYAN}▶ 正在检测 REALITY 伪装 SNI 连通性：${sni}:443${PLAIN}"
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 未检测到 openssl，跳过 SNI 连通性检测。${PLAIN}"
        return 0
    fi
    if timeout 12 openssl s_client -connect "${sni}:443" -servername "$sni" </dev/null 2>/tmp/vps_reality_sni_probe.log | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${GREEN}✅ REALITY SNI 可连通并返回证书。${PLAIN}"
        return 0
    fi
    echo -e "${RED}❌ REALITY SNI 检测失败：${sni}:443 未正常返回证书。${PLAIN}"
    echo -e "${YELLOW}请更换一个外部真实 HTTPS 站点域名，不要使用模板域名或自己的面板域名。${PLAIN}"
    return 1
}

print_sni_stack_preview() {
    local entry_mode entry_label
    entry_mode="${ENTRY_MODE:-nginx-stream}"
    entry_mode=$(normalize_entry_mode_name "$entry_mode" 2>/dev/null || echo "nginx-stream")
    case "$entry_mode" in
        "nginx-stream") entry_label="Nginx Stream 模式" ;;
        "xray-fallback") entry_label="Xray Fallback 模式" ;;
        "tcp-peek") entry_label="TCP Peek + Splice 模式 / vpso-mux 分流器" ;;
        *) entry_label="$entry_mode" ;;
    esac

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}即将写入的 443 单入口分流配置预览${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "配置模式 ENTRY_MODE：${entry_mode}"
    echo -e "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> ${entry_label}"
    echo -e "面板域名：${PANEL_DOMAIN} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "面板路径：https://${PANEL_DOMAIN}${PANEL_WEB_PATH:-/panel/}"
    echo -e "普通订阅路径：https://${PANEL_DOMAIN}${SUB_URI_PATH:-/sub/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
    echo -e "Clash/Mihomo 路径：https://${PANEL_DOMAIN}${CLASH_URI_PATH:-/clash/} -> http://${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            echo -e "网站/反代域名：${SITE_DOMAINS[$i]} -> ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "TCP/SNI 入站：${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "Xray 入站分流：${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}"
        done
    fi
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}域名 IP 白名单：${PLAIN}"
        local wl_i
        for wl_i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
            echo -e "  ${SNI_IP_WHITELIST_DOMAINS[$wl_i]} 仅允许 ${SNI_IP_WHITELIST_RANGES[$wl_i]}"
        done
    fi
    if [[ "$entry_mode" == "xray-fallback" ]]; then
        echo -e "Xray 主入站：公网 ${NGINX_LISTEN_PORT} 由 Xray 接管，普通 HTTPS fallback 到 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}"
        echo -e "提示：脚本不会创建或修改 3x-ui/Xray 入站内部配置。"
    else
        echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
        echo -e "默认/未知 SNI -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    fi
    echo -e ""
    echo -e "${YELLOW}确认后会备份现有配置，并按所选 ENTRY_MODE 生成入口配置。${PLAIN}"
    confirm_risk_action "写入 443 单入口共享配置" \
        "${entry_label}、Caddy 配置和 443 分流规则" \
        "使用本次自动备份目录恢复，或进入 443 维护菜单回滚" \
        "确认公网 443 没有其他服务需要直接占用。"
}

caddy_format_configs() {
    command -v caddy >/dev/null 2>&1 || return 0
    caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            caddy fmt --overwrite "$conf_file" >/dev/null 2>&1 || true
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi
}

get_entry_mode() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local mode=""

    if [[ ! -f "$env_file" ]]; then
        echo "not-configured"
        return 0
    fi

    mode=$(
        # shellcheck disable=SC1090
        source "$env_file" 2>/dev/null || true
        printf '%s' "${ENTRY_MODE:-}"
    )

    case "$mode" in
        ""|"nginx-stream"|"nginx_stream")
            echo "nginx-stream"
            ;;
        "xray-fallback"|"xray_fallback")
            echo "xray-fallback"
            ;;
        "tcp-peek"|"tcp_peek")
            echo "tcp-peek"
            ;;
        *)
            echo "invalid:${mode}"
            ;;
    esac
}

set_entry_mode() {
    local mode="$1"
    local env_file="/etc/vps-optimize/sni-stack.env"

    case "$mode" in
        "nginx_stream") mode="nginx-stream" ;;
        "xray_fallback") mode="xray-fallback" ;;
        "tcp_peek") mode="tcp-peek" ;;
    esac

    case "$mode" in
        "nginx-stream"|"xray-fallback"|"tcp-peek") ;;
        *)
            echo -e "${RED}Invalid ENTRY_MODE: ${mode}${PLAIN}"
            return 1
            ;;
    esac

    mkdir -p /etc/vps-optimize
    if [[ -f "$env_file" ]] && grep -q '^ENTRY_MODE=' "$env_file" 2>/dev/null; then
        sed -i "s|^ENTRY_MODE=.*|ENTRY_MODE='${mode}'|" "$env_file"
    else
        printf "ENTRY_MODE='%s'\n" "$mode" >> "$env_file"
    fi
    chmod 600 "$env_file" 2>/dev/null || true
}

listen_process_from_ss_line() {
    local line="$1"
    local proc
    proc=$(printf '%s\n' "$line" | awk -F'"' '/users:/ {print $2; exit}')
    printf '%s' "${proc:-unknown}"
}

normalize_entry_listener_process() {
    local proc="$1"
    case "$proc" in
        nginx*) echo "nginx" ;;
        xray*|x-ui*|3x-ui*) echo "xray" ;;
        vpso-mux*|tcppeek*|tcp-peek*) echo "tcppeek" ;;
        caddy*) echo "caddy" ;;
        unknown|"") echo "unknown" ;;
        *) echo "unknown:${proc}" ;;
    esac
}

entry_listener_display_name() {
    local listener="$1"
    case "$listener" in
        nginx) echo "Nginx Stream (nginx)" ;;
        xray) echo "Xray Fallback (xray/3x-ui/x-ui)" ;;
        tcppeek) echo "TCP Peek + Splice 模式 (vpso-mux 分流器)" ;;
        caddy) echo "Caddy（不应直接接管 443 单入口）" ;;
        none) echo "未监听" ;;
        multiple) echo "多个进程监听/匹配" ;;
        unknown) echo "已监听，但进程不可见" ;;
        unknown:*) echo "未知进程 ${listener#unknown:}" ;;
        *) echo "$listener" ;;
    esac
}

entry_mode_expected_listener() {
    local mode="$1"
    case "$mode" in
        "nginx-stream") echo "nginx" ;;
        "xray-fallback") echo "xray" ;;
        "tcp-peek") echo "tcppeek" ;;
        *) echo "" ;;
    esac
}

listen_line_status() {
    local addr="$1"
    local port="$2"
    local line="$3"
    local proc

    if [[ "$addr" == "not-configured" || "$port" == "not-configured" ]]; then
        echo "未配置"
        return 0
    fi
    if [[ -z "$line" || "$line" == "未监听" || "$line" == "not-configured" ]]; then
        echo "未监听"
        return 0
    fi

    proc=$(listen_process_from_ss_line "$line")
    if [[ "$proc" == "unknown" ]]; then
        echo "已监听（进程不可见）"
    else
        echo "已监听（${proc}）"
    fi
}

detect_443_listener() {
    local lines line proc normalized seen procs
    lines=$(ss -lntp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || true)

    if [[ -z "$lines" ]]; then
        echo "none|none"
        return 0
    fi

    seen=" "
    procs=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        proc=$(listen_process_from_ss_line "$line")
        normalized=$(normalize_entry_listener_process "$proc")
        if [[ "$seen" != *" ${normalized} "* ]]; then
            seen+="${normalized} "
            if [[ -z "$procs" ]]; then
                procs="$normalized"
            else
                procs="${procs},${normalized}"
            fi
        fi
    done <<< "$lines"

    if [[ "$procs" == *,* ]]; then
        echo "multiple|${procs}"
    else
        echo "${procs}|${procs}"
    fi
}

detect_current_entry_status() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local listener_info expected_listener xui_svc xui_status

    ENTRY_STATUS_MODE=$(get_entry_mode)
    ENTRY_STATUS_CADDY_ADDR="not-configured"
    ENTRY_STATUS_CADDY_PORT="not-configured"
    ENTRY_STATUS_XRAY_ADDR="not-configured"
    ENTRY_STATUS_XRAY_PORT="not-configured"

    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file" 2>/dev/null || true
        ENTRY_STATUS_CADDY_ADDR="${CADDY_LISTEN_ADDR:-not-configured}"
        ENTRY_STATUS_CADDY_PORT="${CADDY_LISTEN_PORT:-not-configured}"
        ENTRY_STATUS_XRAY_ADDR="${XRAY_LISTEN_ADDR:-not-configured}"
        ENTRY_STATUS_XRAY_PORT="${XRAY_LISTEN_PORT:-not-configured}"
    fi

    listener_info=$(detect_443_listener)
    ENTRY_STATUS_LISTENER="${listener_info%%|*}"
    ENTRY_STATUS_LISTENER_PROCESS="${listener_info#*|}"
    ENTRY_STATUS_LISTENER_DISPLAY=$(entry_listener_display_name "$ENTRY_STATUS_LISTENER")
    ENTRY_STATUS_NGINX_SERVICE=$(service_status_compact nginx)
    xui_status=$(xui_panel_status_compact)
    if xui_svc=$(xui_panel_service_name 2>/dev/null); then
        xui_status="${xui_svc}.service ${xui_status}"
    fi
    ENTRY_STATUS_XRAY_SERVICE="面板托管 Xray: ${xui_status} / 独立 xray.service: $(service_status_compact xray)"
    ENTRY_STATUS_TCPPEEK_SERVICE=$(service_status_compact vpso-mux)
    ENTRY_STATUS_CADDY_LISTEN_LINE="not-configured"
    ENTRY_STATUS_XRAY_LISTEN_LINE="not-configured"

    if is_valid_port "$ENTRY_STATUS_CADDY_PORT"; then
        ENTRY_STATUS_CADDY_LISTEN_LINE=$(get_listen_line_by_port "$ENTRY_STATUS_CADDY_PORT")
    fi
    if is_valid_port "$ENTRY_STATUS_XRAY_PORT"; then
        ENTRY_STATUS_XRAY_LISTEN_LINE=$(get_listen_line_by_port "$ENTRY_STATUS_XRAY_PORT")
    fi

    expected_listener=$(entry_mode_expected_listener "$ENTRY_STATUS_MODE")

    if [[ -n "$expected_listener" && "$ENTRY_STATUS_LISTENER" == "$expected_listener" ]]; then
        ENTRY_STATUS_CONSISTENT="yes"
    else
        ENTRY_STATUS_CONSISTENT="no"
    fi
}

show_current_entry_status() {
    detect_current_entry_status
    echo -e "${BOLD}当前 443 入口状态${PLAIN}"
    echo -e "配置模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}"
    echo -e "公网 443：${ENTRY_STATUS_LISTENER_DISPLAY}"
    echo -e "监听进程：${ENTRY_STATUS_LISTENER_PROCESS}"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "Xray 公网：${GREEN}公网 443 当前由 Xray/面板托管 Xray 监听${PLAIN}"
    else
        echo -e "Xray 公网：未检测到 Xray 监听公网 443"
    fi
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "一致性：${GREEN}配置模式与实际监听一致${PLAIN}"
    else
        echo -e "一致性：${YELLOW}配置模式与实际监听不一致${PLAIN}"
        echo -e "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    echo -e "${BOLD}本地监听${PLAIN}"
    echo -e "Caddy：${ENTRY_STATUS_CADDY_ADDR}:${ENTRY_STATUS_CADDY_PORT} - $(listen_line_status "$ENTRY_STATUS_CADDY_ADDR" "$ENTRY_STATUS_CADDY_PORT" "$ENTRY_STATUS_CADDY_LISTEN_LINE")"
    echo -e "Xray： ${ENTRY_STATUS_XRAY_ADDR}:${ENTRY_STATUS_XRAY_PORT} - $(listen_line_status "$ENTRY_STATUS_XRAY_ADDR" "$ENTRY_STATUS_XRAY_PORT" "$ENTRY_STATUS_XRAY_LISTEN_LINE")"
    echo -e "------------------------------------------------"
    echo -e "${BOLD}服务状态${PLAIN}"
    echo -e "nginx：${ENTRY_STATUS_NGINX_SERVICE}"
    echo -e "TCP Peek + Splice / vpso-mux 分流器：${ENTRY_STATUS_TCPPEEK_SERVICE}"
    echo -e "Xray/3x-ui/x-ui：${ENTRY_STATUS_XRAY_SERVICE}"
}

show_current_entry_summary() {
    detect_current_entry_status
    echo -e "${BOLD}当前入口模式：${CYAN}${ENTRY_STATUS_MODE}${PLAIN}"
    if [[ "$ENTRY_STATUS_CONSISTENT" != "yes" ]]; then
        echo -e "${YELLOW}⚠️ 配置模式与公网 443 实际监听不一致，详情看 [1]，建议确认后重新应用当前入口模式。${PLAIN}"
    fi
}

load_sni_stack_env() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED}❌ 未找到 ${env_file}，请先运行主菜单 [19] -> [2] 首次配置 443 单入口。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$env_file"
    ENTRY_MODE=$(get_entry_mode)
    PANEL_WEB_PATH=$(normalize_path_prefix "${PANEL_WEB_PATH:-/panel/}")
    SUB_URI_PATH=$(normalize_path_prefix "${SUB_URI_PATH:-/sub/}")
    CLASH_URI_PATH=$(normalize_path_prefix "${CLASH_URI_PATH:-/clash/}")
    normalize_site_stack_arrays
    normalize_tcp_route_arrays
    load_xray_sni_route_arrays
    normalize_sni_ip_whitelist_arrays
}

get_listen_line_by_port() {
    local port="$1"
    local line
    line=$(ss -lntp 2>/dev/null | grep ":${port}[[:space:]]" | head -n1 || true)
    echo "${line:-未监听}"
}

print_sni_stack_current_summary() {
    local env_file="/etc/vps-optimize/sni-stack.env"
    local caddy_conf="/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy"
    local nginx_conf="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"

    echo -e "${BOLD}当前保存的 443 分流配置${PLAIN} ${CYAN}(${env_file})${PLAIN}"
    echo -e "面板：      https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "普通订阅：  https://${PANEL_DOMAIN}${SUB_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
    echo -e "Clash 订阅：https://${PANEL_DOMAIN}${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
    echo -e "REALITY：   ${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "TCP/SNI：   ${TCP_ROUTE_SNIS[$tcp_i]} -> ${TCP_ROUTE_ADDRS[$tcp_i]}:${TCP_ROUTE_PORTS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "Xray 入站：  ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]} -> ${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}:${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}"
        done
    fi
    echo -e "公网入口：  ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Caddy ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}"
    echo -e "配置文件：  Nginx ${nginx_conf}"
    echo -e "           Caddy ${caddy_conf}"
    print_sni_ip_whitelist_summary
    echo -e "------------------------------------------------"
    echo -e "${BOLD}当前实际监听状态${PLAIN}"
    echo -e "Nginx 入口：  $(get_listen_line_by_port "$NGINX_LISTEN_PORT")"
    echo -e "Caddy 本地：  $(get_listen_line_by_port "$CADDY_LISTEN_PORT")"
    echo -e "面板后端：    $(get_listen_line_by_port "$PANEL_LISTEN_PORT")"
    echo -e "订阅后端：    $(get_listen_line_by_port "$SUB_LISTEN_PORT")"
    echo -e "REALITY 后端：$(get_listen_line_by_port "$XRAY_LISTEN_PORT")"
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            echo -e "TCP/SNI 后端 ${TCP_ROUTE_SNIS[$tcp_i]}：$(get_listen_line_by_port "${TCP_ROUTE_PORTS[$tcp_i]}")"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            echo -e "Xray 入站后端 ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}：$(get_listen_line_by_port "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}")"
        done
    fi
}

normalize_site_stack_arrays() {
    SITE_DOMAINS=()
    SITE_BACKEND_ADDRS=()
    SITE_BACKEND_PORTS=()

    if [[ -n "${SITE_DOMAINS_CSV:-}" ]]; then
        split_csv_to_array "$SITE_DOMAINS_CSV" SITE_DOMAINS
        split_csv_to_array "${SITE_BACKEND_ADDRS_CSV:-}" SITE_BACKEND_ADDRS
        split_csv_to_array "${SITE_BACKEND_PORTS_CSV:-}" SITE_BACKEND_PORTS
    elif [[ -n "${SITE_DOMAIN:-}" ]]; then
        SITE_DOMAINS=("$SITE_DOMAIN")
        SITE_BACKEND_ADDRS=("${SITE_BACKEND_ADDR:-127.0.0.1}")
        SITE_BACKEND_PORTS=("${SITE_BACKEND_PORT:-3000}")
    fi

    local i default_port
    default_port=3000
    for i in "${!SITE_DOMAINS[@]}"; do
        SITE_BACKEND_ADDRS[$i]="${SITE_BACKEND_ADDRS[$i]:-127.0.0.1}"
        if [[ -z "${SITE_BACKEND_PORTS[$i]:-}" ]]; then
            if [[ "$i" -eq 0 && -n "${SITE_BACKEND_PORT:-}" ]]; then
                SITE_BACKEND_PORTS[$i]="$SITE_BACKEND_PORT"
            else
                SITE_BACKEND_PORTS[$i]="$default_port"
            fi
        fi
        default_port=$((default_port + 1))
    done

    SITE_DOMAIN="${SITE_DOMAINS[0]:-}"
    SITE_BACKEND_ADDR="${SITE_BACKEND_ADDRS[0]:-127.0.0.1}"
    SITE_BACKEND_PORT="${SITE_BACKEND_PORTS[0]:-3000}"
}

normalize_tcp_route_arrays() {
    local -a raw_snis=()
    local -a raw_addrs=()
    local -a raw_ports=()
    local -a clean_snis=()
    local -a clean_addrs=()
    local -a clean_ports=()
    local i sni addr port

    if [[ -n "${TCP_ROUTE_SNIS_CSV:-}" ]]; then
        split_csv_to_array "$TCP_ROUTE_SNIS_CSV" raw_snis
        split_csv_to_array "${TCP_ROUTE_ADDRS_CSV:-}" raw_addrs
        split_csv_to_array "${TCP_ROUTE_PORTS_CSV:-}" raw_ports
    fi

    for i in "${!raw_snis[@]}"; do
        sni=$(normalize_domain_input "${raw_snis[$i]}")
        addr=$(normalize_loopback_addr "${raw_addrs[$i]:-127.0.0.1}")
        port="${raw_ports[$i]:-8443}"
        if is_valid_domain "$sni" && is_loopback_listen_addr "$addr" && is_valid_port "$port"; then
            clean_snis+=("$sni")
            clean_addrs+=("$addr")
            clean_ports+=("$port")
        fi
    done

    TCP_ROUTE_SNIS=("${clean_snis[@]}")
    TCP_ROUTE_ADDRS=("${clean_addrs[@]}")
    TCP_ROUTE_PORTS=("${clean_ports[@]}")
}

xray_sni_routes_path() {
    echo "/etc/vps-optimize/xray-sni-routes.conf"
}

load_xray_sni_route_arrays() {
    local route_file line sni addr port
    route_file=$(xray_sni_routes_path)
    XRAY_SNI_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_ADDRS=()
    XRAY_SNI_ROUTE_PORTS=()

    [[ -f "$route_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        [[ -n "$(trim_input "$line")" ]] || continue
        IFS='|' read -r sni addr port _ <<< "$line"
        sni=$(normalize_domain_input "$sni")
        addr=$(normalize_loopback_addr "${addr:-127.0.0.1}")
        port="$(trim_input "${port:-}")"
        if is_valid_domain "$sni" && is_loopback_listen_addr "$addr" && is_valid_port "$port"; then
            XRAY_SNI_ROUTE_SNIS+=("$sni")
            XRAY_SNI_ROUTE_ADDRS+=("$addr")
            XRAY_SNI_ROUTE_PORTS+=("$port")
        fi
    done < "$route_file"
}

save_xray_sni_route_arrays() {
    local route_file i
    route_file=$(xray_sni_routes_path)
    mkdir -p "$(dirname "$route_file")"
    : > "$route_file"
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ -n "${XRAY_SNI_ROUTE_SNIS[$i]:-}" ]] || continue
        printf '%s|%s|%s\n' "${XRAY_SNI_ROUTE_SNIS[$i]}" "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}" >> "$route_file"
    done
    chmod 600 "$route_file" 2>/dev/null || true
}

xray_sni_route_index() {
    local sni="$1"
    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$sni" == "${XRAY_SNI_ROUTE_SNIS[$i]}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

xray_fallback_main_route_index() {
    local i
    if [[ -n "${XRAY_FALLBACK_MAIN_SNI:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            [[ "$XRAY_FALLBACK_MAIN_SNI" == "${XRAY_SNI_ROUTE_SNIS[$i]}" ]] && { echo "$i"; return 0; }
        done
    fi
    if [[ -n "${XRAY_FALLBACK_MAIN_ADDR:-}" && -n "${XRAY_FALLBACK_MAIN_PORT:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            if [[ "$XRAY_FALLBACK_MAIN_ADDR" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$XRAY_FALLBACK_MAIN_PORT" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
                echo "$i"
                return 0
            fi
        done
    fi
    if [[ "$(get_entry_mode)" == "xray-fallback" && -n "${XRAY_LISTEN_ADDR:-}" && -n "${XRAY_LISTEN_PORT:-}" ]]; then
        for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            if [[ "$XRAY_LISTEN_ADDR" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$XRAY_LISTEN_PORT" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
                echo "$i"
                return 0
            fi
        done
    fi
    return 1
}

set_xray_fallback_main_route_from_index() {
    local idx="$1"
    [[ "$idx" =~ ^[0-9]+$ ]] || return 1
    (( idx >= 0 && idx < ${#XRAY_SNI_ROUTE_SNIS[@]} )) || return 1
    XRAY_FALLBACK_MAIN_SNI="${XRAY_SNI_ROUTE_SNIS[$idx]}"
    XRAY_FALLBACK_MAIN_ADDR="${XRAY_SNI_ROUTE_ADDRS[$idx]}"
    XRAY_FALLBACK_MAIN_PORT="${XRAY_SNI_ROUTE_PORTS[$idx]}"
}

print_xray_fallback_mode_explanation() {
    echo -e "${YELLOW}Xray 本身可以有多个入站。但在 xray-fallback 模式下，公网 443 默认由一个 Xray 主入站接管。脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。${PLAIN}"
    echo -e "${YELLOW}该模式只负责 Xray 主入站监听公网 443，并 fallback 普通 HTTPS 到 Caddy。${PLAIN}"
    echo -e "${YELLOW}如需多个本地 Xray 入站通过 443 按 SNI 分流，请使用 Nginx Stream 模式或 TCP Peek + Splice 模式。${PLAIN}"
    echo -e "${YELLOW}如果 Web 域名开启 CDN/WAF/源站保护/Cloudflare 回源限制/Caddy 白名单，403 或拒绝访问通常是 Web/CDN/白名单/SNI 策略阻断，不一定是证书或 Caddy 故障。${PLAIN}"
}

print_xray_fallback_main_route_summary() {
    local idx
    idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    if [[ -n "$idx" ]]; then
        echo -e "${GREEN}当前 xray-fallback 主入站：${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}${PLAIN}"
    elif [[ -n "${XRAY_FALLBACK_MAIN_SNI:-}" ]]; then
        echo -e "${YELLOW}当前 xray-fallback 主入站记录：${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR:-?}:${XRAY_FALLBACK_MAIN_PORT:-?}，但未匹配到现有规则。${PLAIN}"
    elif [[ "$(get_entry_mode)" == "xray-fallback" ]]; then
        echo -e "${YELLOW}当前未记录 xray-fallback 主入站；请确认 Xray 主入站已按当前模式监听公网 443。${PLAIN}"
    fi
}

select_xray_fallback_main_route_for_switch() {
    load_sni_stack_env || return 1
    local count choice idx
    count=${#XRAY_SNI_ROUTE_SNIS[@]}

    if [[ "$count" -eq 0 ]]; then
        echo -e "${YELLOW}未找到 $(xray_sni_routes_path) 中的 Xray 入站分流规则。${PLAIN}"
        echo -e "${YELLOW}切换到 xray-fallback 时，将由用户已配置的 Xray 主入站接管公网 443；脚本不会修改 3x-ui/Xray 入站内部配置。${PLAIN}"
        confirm_risk_action "继续切换到 xray-fallback" \
            "公网 443 将由 Xray 主入站接管，普通 HTTPS fallback 到 Caddy" \
            "取消切换，先在 Xray 入站管理中记录一个主入站候选" \
            "确认你已经在 3x-ui/Xray 中准备好将作为主入站的配置。" || return 1
        XRAY_FALLBACK_MAIN_SNI=""
        XRAY_FALLBACK_MAIN_ADDR=""
        XRAY_FALLBACK_MAIN_PORT=""
        return 0
    fi

    print_xray_fallback_mode_explanation
    echo -e "------------------------------------------------"
    if [[ "$count" -eq 1 ]]; then
        echo -e "${CYAN}检测到 1 条 Xray 入站分流规则，可作为 xray-fallback 主入站候选：${PLAIN}"
        echo -e "1. ${XRAY_SNI_ROUTE_SNIS[0]} -> ${XRAY_SNI_ROUTE_ADDRS[0]}:${XRAY_SNI_ROUTE_PORTS[0]}"
        confirm_risk_action "使用该规则作为 xray-fallback 主入站候选" \
            "该规则会被记录为 xray-fallback 主入站；其他模式下仍按 xray-sni-routes.conf 正常分流" \
            "取消切换，先确认 3x-ui/Xray 主入站配置" \
            "确认该本地入站就是你希望在 xray-fallback 模式下接管公网 443 的主入站。" || return 1
        set_xray_fallback_main_route_from_index 0
        return 0
    fi

    echo -e "${CYAN}检测到多条 Xray 入站分流规则，请选择其中一条作为 xray-fallback 主入站：${PLAIN}"
    for idx in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        echo -e "${GREEN}$((idx + 1)).${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$idx]} -> ${XRAY_SNI_ROUTE_ADDRS[$idx]}:${XRAY_SNI_ROUTE_PORTS[$idx]}"
    done
    echo -e "${RED}0. 取消切换${PLAIN}"
    read_trimmed choice "请选择 xray-fallback 主入站候选: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消切换到 xray-fallback。${PLAIN}"
        return 1
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
        echo -e "${RED}❌ 序号无效，已取消切换。${PLAIN}"
        return 1
    fi
    set_xray_fallback_main_route_from_index "$((choice - 1))" || return 1
    echo -e "${GREEN}✅ 已选择 xray-fallback 主入站候选：${XRAY_FALLBACK_MAIN_SNI} -> ${XRAY_FALLBACK_MAIN_ADDR}:${XRAY_FALLBACK_MAIN_PORT}${PLAIN}"
}

xray_sni_route_port_conflict() {
    local addr="$1"
    local port="$2"
    local skip_idx="${3:-}"
    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ -n "$skip_idx" && "$i" == "$skip_idx" ]] && continue
        if [[ "$addr" == "${XRAY_SNI_ROUTE_ADDRS[$i]}" && "$port" == "${XRAY_SNI_ROUTE_PORTS[$i]}" ]]; then
            echo "${XRAY_SNI_ROUTE_SNIS[$i]}"
            return 0
        fi
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        if [[ "$addr" == "${TCP_ROUTE_ADDRS[$i]}" && "$port" == "${TCP_ROUTE_PORTS[$i]}" ]]; then
            echo "旧 TCP/SNI:${TCP_ROUTE_SNIS[$i]}"
            return 0
        fi
    done
    return 1
}

xray_route_listen_line_by_addr_port() {
    local addr="$1"
    local port="$2"
    local host_regex
    case "$addr" in
        "127.0.0.1") host_regex='(127\.0\.0\.1|0\.0\.0\.0|\*)' ;;
        "::1") host_regex='(\[::1\]|\[::\]|\*)' ;;
        "localhost") host_regex='(127\.0\.0\.1|0\.0\.0\.0|\[::1\]|\[::\]|\*)' ;;
        *) host_regex=$(printf '%s' "$addr" | sed 's/[.[\*^$()+?{}|\\]/\\&/g') ;;
    esac
    ss -lntp 2>/dev/null | grep -E "${host_regex}:${port}[[:space:]]" | head -n1 || true
}

print_xray_route_port_status() {
    local sni="$1"
    local addr="$2"
    local port="$3"
    local line conflict

    echo -e "${CYAN}${sni}${PLAIN} -> ${addr}:${port}"
    if [[ "${CADDY_LISTEN_PORT:-}" == "$port" ]]; then
        echo -e "${RED}  ❌ 与 Caddy 本地端口 ${CADDY_LISTEN_PORT} 冲突，请换一个本地入站端口。${PLAIN}"
    fi

    conflict=$(xray_sni_route_port_conflict "$addr" "$port" "$(xray_sni_route_index "$sni" 2>/dev/null || true)" || true)
    [[ -n "$conflict" ]] && echo -e "${YELLOW}  ⚠️ 与规则 ${conflict} 使用了相同的 ${addr}:${port}，请确认是否故意复用。${PLAIN}"

    line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
    if [[ -n "$line" ]]; then
        echo -e "${GREEN}  ✅ 端口已监听：${line}${PLAIN}"
        if echo "$line" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\*|\[::\]):'"${port}"'[[:space:]]'; then
            echo -e "${YELLOW}  ⚠️ 检测到可能监听在 0.0.0.0/[::]，存在公网暴露风险，建议改为 127.0.0.1。${PLAIN}"
        fi
    else
        echo -e "${YELLOW}  ⚠️ 未检测到 ${addr}:${port} 监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}"
    fi
}

is_sni_stack_managed_domain() {
    local domain="$1"
    local site_domain
    [[ "$domain" == "$PANEL_DOMAIN" ]] && return 0
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    for site_domain in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    for site_domain in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    return 1
}

is_sni_stack_web_domain() {
    local domain="$1"
    local site_domain
    [[ "$domain" == "$PANEL_DOMAIN" ]] && return 0
    for site_domain in "${SITE_DOMAINS[@]}"; do
        [[ "$domain" == "$site_domain" ]] && return 0
    done
    return 1
}

nginx_var_suffix_for_domain() {
    local domain="$1"
    domain=$(echo "$domain" | tr '.-' '__' | tr -cd 'a-zA-Z0-9_')
    printf '%s' "$domain"
}

normalize_sni_ip_whitelist_arrays() {
    local domains_input="${SNI_IP_WHITELIST_DOMAINS_CSV:-}"
    local ranges_input="${SNI_IP_WHITELIST_RANGES_PIPE:-}"
    local -a raw_domains=()
    local -a raw_ranges=()
    local -a clean_domains=()
    local -a clean_ranges=()
    local -a range_array=()
    local i domain ranges

    SNI_IP_WHITELIST_DOMAINS=()
    SNI_IP_WHITELIST_RANGES=()

    [[ -n "$domains_input" ]] && split_csv_to_array "$domains_input" raw_domains
    [[ -n "$ranges_input" ]] && split_pipe_to_array "$ranges_input" raw_ranges

    for i in "${!raw_domains[@]}"; do
        domain=$(normalize_domain_input "${raw_domains[$i]}")
        ranges="${raw_ranges[$i]:-}"
        [[ -n "$domain" && -n "$ranges" ]] || continue
        is_valid_domain "$domain" || continue
        is_sni_stack_web_domain "$domain" || continue
        if normalize_ip_whitelist_input "$ranges" range_array; then
            clean_domains+=("$domain")
            clean_ranges+=("$(join_array_by_space "${range_array[@]}")")
        fi
    done

    SNI_IP_WHITELIST_DOMAINS=("${clean_domains[@]}")
    SNI_IP_WHITELIST_RANGES=("${clean_ranges[@]}")
}

sni_ip_whitelist_index() {
    local domain="$1"
    local i
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ "$domain" == "${SNI_IP_WHITELIST_DOMAINS[$i]}" ]] && { echo "$i"; return 0; }
    done
    return 1
}

sni_ip_whitelist_ranges_for_domain() {
    local domain="$1"
    local idx
    idx=$(sni_ip_whitelist_index "$domain" 2>/dev/null) || return 0
    echo "${SNI_IP_WHITELIST_RANGES[$idx]:-}"
}

set_sni_ip_whitelist_for_domain() {
    local domain="$1"
    local ranges="$2"
    local idx
    idx=$(sni_ip_whitelist_index "$domain" 2>/dev/null) || idx=""
    if [[ -n "$idx" ]]; then
        SNI_IP_WHITELIST_RANGES[$idx]="$ranges"
    else
        SNI_IP_WHITELIST_DOMAINS+=("$domain")
        SNI_IP_WHITELIST_RANGES+=("$ranges")
    fi
}

remove_sni_ip_whitelist_for_domain() {
    local domain="$1"
    local i
    local -a new_domains=()
    local -a new_ranges=()
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ "$domain" == "${SNI_IP_WHITELIST_DOMAINS[$i]}" ]] && continue
        new_domains+=("${SNI_IP_WHITELIST_DOMAINS[$i]}")
        new_ranges+=("${SNI_IP_WHITELIST_RANGES[$i]}")
    done
    SNI_IP_WHITELIST_DOMAINS=("${new_domains[@]}")
    SNI_IP_WHITELIST_RANGES=("${new_ranges[@]}")
}

rename_sni_ip_whitelist_domain() {
    local old_domain="$1"
    local new_domain="$2"
    local idx
    idx=$(sni_ip_whitelist_index "$old_domain" 2>/dev/null) || return 0
    SNI_IP_WHITELIST_DOMAINS[$idx]="$new_domain"
}

print_sni_ip_whitelist_summary() {
    if [[ ${#SNI_IP_WHITELIST_DOMAINS[@]} -eq 0 ]]; then
        echo -e "IP 白名单：  未启用"
        return 0
    fi

    local i
    echo -e "IP 白名单："
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        echo -e "  - ${SNI_IP_WHITELIST_DOMAINS[$i]} 仅允许：${SNI_IP_WHITELIST_RANGES[$i]}"
    done
}

sni_stack_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 443 单入口分流链路体检${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local ok=0 warn=0 fail=0
    check_listen() {
        local name="$1"
        local port="$2"
        local expect_addr="$3"
        if ss -lntp 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            local line
            line=$(ss -lntp 2>/dev/null | grep ":${port}[[:space:]]" | head -n1)
            echo -e "${GREEN}✅ ${name} 端口 ${port} 有监听：${line}${PLAIN}"
            if [[ -n "$expect_addr" ]] && ! echo "$line" | grep -q "$expect_addr"; then
                echo -e "${YELLOW}⚠️ ${name} 期望监听 ${expect_addr}:${port}，请确认是否被改成公网监听。${PLAIN}"
                ((warn++))
            else
                ((ok++))
            fi
        else
            echo -e "${RED}❌ ${name} 端口 ${port} 未监听。${PLAIN}"
            ((fail++))
        fi
    }

    check_listen "Nginx 公网入口" "$NGINX_LISTEN_PORT" ""
    check_listen "Caddy 本地 TLS" "$CADDY_LISTEN_PORT" "$CADDY_LISTEN_ADDR"
    check_listen "Xray/3x-ui REALITY" "$XRAY_LISTEN_PORT" "$XRAY_LISTEN_ADDR"
    check_listen "3x-ui 面板" "$PANEL_LISTEN_PORT" "$PANEL_LISTEN_ADDR"
    check_listen "3x-ui 订阅" "$SUB_LISTEN_PORT" "$SUB_LISTEN_ADDR"
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local i
        for i in "${!SITE_DOMAINS[@]}"; do
            check_listen "网站后端 ${SITE_DOMAINS[$i]}" "${SITE_BACKEND_PORTS[$i]}" "${SITE_BACKEND_ADDRS[$i]}"
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_i
        for tcp_i in "${!TCP_ROUTE_SNIS[@]}"; do
            check_listen "TCP/SNI 入站 ${TCP_ROUTE_SNIS[$tcp_i]}" "${TCP_ROUTE_PORTS[$tcp_i]}" "${TCP_ROUTE_ADDRS[$tcp_i]}"
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_i
        for xray_route_i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
            check_listen "Xray 入站 ${XRAY_SNI_ROUTE_SNIS[$xray_route_i]}" "${XRAY_SNI_ROUTE_PORTS[$xray_route_i]}" "${XRAY_SNI_ROUTE_ADDRS[$xray_route_i]}"
        done
    fi

    echo -e "------------------------------------------------"
    if check_xui_cert_settings_for_single_443; then
        ((ok++))
    else
        ((warn++))
    fi

    echo -e "------------------------------------------------"
    if check_domain_dns_sanity "$PANEL_DOMAIN" "面板域名" "warn"; then
        ((ok++))
    else
        ((warn++))
    fi
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local dns_site
        for dns_site in "${SITE_DOMAINS[@]}"; do
            [[ -z "$dns_site" ]] && continue
            if check_domain_dns_sanity "$dns_site" "网站/反代域名" "warn"; then
                ((ok++))
            else
                ((warn++))
            fi
        done
    fi
    if [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]]; then
        local tcp_sni
        for tcp_sni in "${TCP_ROUTE_SNIS[@]}"; do
            [[ -z "$tcp_sni" ]] && continue
            if check_domain_dns_sanity "$tcp_sni" "TCP/SNI 入站域名" "warn"; then
                ((ok++))
            else
                echo -e "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}"
                ((warn++))
            fi
        done
    fi
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]]; then
        local xray_route_sni
        for xray_route_sni in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
            [[ -z "$xray_route_sni" ]] && continue
            if check_domain_dns_sanity "$xray_route_sni" "Xray 入站域名" "warn"; then
                ((ok++))
            else
                echo -e "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}"
                ((warn++))
            fi
        done
    fi

    echo -e "------------------------------------------------"
    nginx -t >/dev/null 2>&1 && echo -e "${GREEN}✅ nginx -t 通过${PLAIN}" && ((ok++)) || { echo -e "${RED}❌ nginx -t 失败${PLAIN}"; ((fail++)); }
    caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && echo -e "${GREEN}✅ Caddy 配置校验通过${PLAIN}" && ((ok++)) || { echo -e "${RED}❌ Caddy 配置校验失败${PLAIN}"; ((fail++)); }
    if grep -Eq '^[[:space:]]*server_tokens[[:space:]]+off;' /etc/nginx/nginx.conf 2>/dev/null; then
        echo -e "${GREEN}✅ Nginx 已关闭版本号显示 server_tokens off${PLAIN}"
        ((ok++))
    else
        echo -e "${YELLOW}⚠️ 未确认 Nginx server_tokens off，错误页可能显示版本号。${PLAIN}"
        ((warn++))
    fi
    if [[ -f /etc/nginx/conf.d/00-vps-default-drop.conf ]]; then
        echo -e "${GREEN}✅ Nginx 80 默认站点已设置为丢弃连接${PLAIN}"
        ((ok++))
    else
        echo -e "${YELLOW}⚠️ 未找到 80 默认丢弃配置，错误域名可能命中默认页。${PLAIN}"
        ((warn++))
    fi

    if command -v openssl >/dev/null 2>&1; then
        if timeout 10 openssl s_client -connect "127.0.0.1:${NGINX_LISTEN_PORT}" -servername "$PANEL_DOMAIN" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
            echo -e "${GREEN}✅ 面板 SNI 可从 Nginx 命中 Caddy 证书链${PLAIN}"
            ((ok++))
        else
            echo -e "${YELLOW}⚠️ 面板 SNI 测试未拿到证书，请检查 Nginx stream 与 Caddy。${PLAIN}"
            ((warn++))
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "体检结果：${GREEN}通过 ${ok}${PLAIN} / ${YELLOW}警告 ${warn}${PLAIN} / ${RED}失败 ${fail}${PLAIN}"
}

vpso_mux_config_path() {
    echo "/etc/vps-optimize/vpso-mux.yaml"
}

vpso_mux_service_name() {
    echo "vpso-mux.service"
}

single_443_engine_state_path() {
    echo "/etc/vps-optimize/443-engine.conf"
}

yaml_quote() {
    local value="$1"
    value=$(printf '%s' "$value" | sed "s/'/''/g")
    printf "'%s'" "$value"
}

single_443_current_engine() {
    local state_file
    state_file=$(single_443_engine_state_path)
    if [[ -f "$state_file" ]]; then
        (
            # shellcheck disable=SC1090
            source "$state_file" 2>/dev/null || true
            printf '%s' "${engine:-nginx_stream}"
        )
        return 0
    fi
    printf 'nginx_stream'
}

sni_stack_route_name() {
    local prefix="$1"
    local sni="$2"
    sni=$(echo "$sni" | tr '.-' '__' | tr -cd 'a-zA-Z0-9_')
    printf '%s_%s' "$prefix" "$sni"
}

sni_stack_route_summary_for_state() {
    local caddy_backend xray_backend summary i domain
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    summary="panel:${PANEL_DOMAIN}->${caddy_backend},reality:${REALITY_SNI}->${xray_backend},default->${xray_backend}"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] && summary+=",site:${domain}->${caddy_backend}"
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] && summary+=",tcp:${domain}->$(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}")"
    done
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] && summary+=",xray:${domain}->$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}")"
    done
    printf '%s' "$summary"
}

sni_stack_whitelist_summary_for_state() {
    local summary="" i
    for i in "${!SNI_IP_WHITELIST_DOMAINS[@]}"; do
        [[ -n "${SNI_IP_WHITELIST_DOMAINS[$i]}" && -n "${SNI_IP_WHITELIST_RANGES[$i]}" ]] || continue
        [[ -n "$summary" ]] && summary+="|"
        summary+="${SNI_IP_WHITELIST_DOMAINS[$i]}:${SNI_IP_WHITELIST_RANGES[$i]}"
    done
    printf '%s' "$summary"
}

write_single_443_engine_state() {
    local selected_engine="$1"
    local backup_id="${2:-}"
    local state_file mux_config mux_service caddy_backend xray_backend routes whitelist_rules
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    mux_service=$(vpso_mux_service_name)
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    routes=$(sni_stack_route_summary_for_state)
    whitelist_rules=$(sni_stack_whitelist_summary_for_state)
    [[ -z "$backup_id" ]] && backup_id=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true)

    mkdir -p /etc/vps-optimize
    cat <<EOF > "$state_file"
engine='${selected_engine}'
listen_addr='${NGINX_LISTEN_ADDR}'
listen_port='${NGINX_LISTEN_PORT}'
caddy_backend='${caddy_backend}'
xray_backend='${xray_backend}'
default_backend='${xray_backend}'
routes='${routes}'
whitelist_rules='${whitelist_rules}'
last_backup_id='${backup_id}'
mux_config_path='${mux_config}'
mux_systemd_service_name='${mux_service}'
EOF
    chmod 600 "$state_file" 2>/dev/null || true
}

show_single_443_engine_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔎 当前 443 入口状态 / 单入口引擎${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    local engine state_file mux_config
    engine=$(single_443_current_engine)
    state_file=$(single_443_engine_state_path)
    mux_config=$(vpso_mux_config_path)
    show_current_entry_status
    echo -e "------------------------------------------------"
    echo -e "当前 engine：${GREEN}${engine}${PLAIN}"
    echo -e "状态文件：${state_file}"
    echo -e "mux 配置：${mux_config}"
    echo -e "------------------------------------------------"
    echo -e "${GREEN}Nginx Stream 模式是默认稳定模式。${PLAIN}"
    echo -e "${YELLOW}TCP Peek + Splice 模式适合需要四层 SNI 分流和 splice 转发优化的进阶用户。${PLAIN}"
    echo -e "${YELLOW}首次建议先监听 8444 测试，不要直接接管 443。${PLAIN}"
    echo -e "${YELLOW}切换前会自动备份，可回滚。${PLAIN}"
    echo -e "------------------------------------------------"
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        load_sni_stack_env >/dev/null 2>&1 && print_sni_stack_current_summary
    else
        echo -e "${YELLOW}未检测到 sni-stack.env，尚未完成 443 单入口初始化。${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    echo -e "公网 443 监听："
    ss -lntup 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "未监听或当前用户无权限查看进程"
}

show_tcp_peek_splice_info() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Caddy 或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。${PLAIN}"
    echo -e "它只在 TCP 层读取 TLS ClientHello 的 SNI，不终止 TLS，不管理证书，不替换 Caddy，也不是 Xray 直占 443。"
    echo -e "推荐流程："
    echo -e "  1. 先生成 TCP Peek + Splice 分流规则：/etc/vps-optimize/vpso-mux.yaml"
    echo -e "  2. 校验配置和后端端口"
    echo -e "  3. 使用 TCP Peek + Splice 测试入口监听 8444"
    echo -e "  4. 确认后再事务式切换公网 443"
    echo -e "  5. 异常时从菜单回滚到 Nginx Stream 模式"
}

append_vpso_mux_route_yaml() {
    local file="$1"
    local name="$2"
    local sni="$3"
    local backend="$4"
    local whitelist="$5"
    {
        echo "  - name: $(yaml_quote "$name")"
        echo "    sni:"
        echo "      - $(yaml_quote "$sni")"
        echo "    backend: $(yaml_quote "$backend")"
        if [[ -n "$whitelist" ]]; then
            echo "    whitelist:"
            local range
            for range in $whitelist; do
                echo "      - $(yaml_quote "$range")"
            done
        fi
    } >> "$file"
}

write_vpso_mux_config_from_sni_stack() {
    local listen_port="${1:-$NGINX_LISTEN_PORT}"
    local output_file="${2:-$(vpso_mux_config_path)}"
    local caddy_backend xray_backend listen_addr route_name ranges i domain backend
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    mkdir -p "$(dirname "$output_file")"

    {
        echo "listen:"
        echo "  tcp:"
        if [[ "$NGINX_LISTEN_ADDR" == "0.0.0.0" ]]; then
            echo "    - $(yaml_quote "0.0.0.0:${listen_port}")"
            echo "    - $(yaml_quote "[::]:${listen_port}")"
        elif [[ "$NGINX_LISTEN_ADDR" == "::" ]]; then
            echo "    - $(yaml_quote "[::]:${listen_port}")"
        else
            listen_addr=$(format_hostport "$NGINX_LISTEN_ADDR" "$listen_port")
            echo "    - $(yaml_quote "$listen_addr")"
        fi
        echo ""
        echo "timeouts:"
        echo "  peek: $(yaml_quote "3s")"
        echo "  dial: $(yaml_quote "5s")"
        echo "  idle: $(yaml_quote "300s")"
        echo "  shutdown: $(yaml_quote "10s")"
        echo ""
        echo "splice:"
        echo "  enabled: true"
        echo "  pipe_size: 1048576"
        echo "  fallback_to_copy: true"
        echo ""
        echo "default_backend: $(yaml_quote "$xray_backend")"
        echo ""
        echo "routes:"
    } > "$output_file"

    ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    append_vpso_mux_route_yaml "$output_file" "panel" "$PANEL_DOMAIN" "$caddy_backend" "$ranges"
    if [[ -z "$ranges" ]]; then
        echo -e "${YELLOW}⚠️ 面板域名 ${PANEL_DOMAIN} 当前未配置 IP 白名单；切换前请确认这是你想要的行为。${PLAIN}"
    fi

    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "site" "$domain")
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$caddy_backend" "$ranges"
    done

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "tcp" "$domain")
        backend=$(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}")
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$backend" "$ranges"
    done

    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        route_name=$(sni_stack_route_name "xray" "$domain")
        backend=$(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}")
        append_vpso_mux_route_yaml "$output_file" "$route_name" "$domain" "$backend" ""
    done

    append_vpso_mux_route_yaml "$output_file" "reality" "$REALITY_SNI" "$xray_backend" ""

    cat <<EOF >> "$output_file"

logging:
  level: $(yaml_quote "info")
  format: $(yaml_quote "json")
EOF
    chmod 600 "$output_file" 2>/dev/null || true
}

generate_tcp_peek_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}重新应用 TCP Peek + Splice 配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}只生成 TCP Peek + Splice 分流规则，不改服务，不改端口，不接管 443。${PLAIN}"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$(vpso_mux_config_path)" || return 1
    echo -e "${GREEN}✅ 已生成：$(vpso_mux_config_path)${PLAIN}"
    echo -e "默认后端：$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")"
    echo -e "Caddy 后端：$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")"
    echo -e "${YELLOW}下一步建议先校验配置，再使用 TCP Peek + Splice 测试入口监听 8444。${PLAIN}"
}

install_vpso_mux_binary() {
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        return 0
    fi
    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if command -v go >/dev/null 2>&1 && [[ -d "$source_dir/cmd/vpso-mux" ]]; then
        echo -e "${CYAN}▶ 正在从当前源码构建 vpso-mux...${PLAIN}"
        (cd "$source_dir" && go build -o /usr/local/bin/vpso-mux ./cmd/vpso-mux) || return 1
        chmod 755 /usr/local/bin/vpso-mux
        return 0
    fi
    if command -v go >/dev/null 2>&1; then
        echo -e "${CYAN}▶ 正在通过 go install 安装 vpso-mux...${PLAIN}"
        GOBIN=/usr/local/bin go install github.com/Chunlion/VPS-Optimize/cmd/vpso-mux@latest || return 1
        chmod 755 /usr/local/bin/vpso-mux 2>/dev/null || true
        return 0
    fi
    echo -e "${RED}❌ 未找到 /usr/local/bin/vpso-mux，且当前系统未安装 Go，无法构建 vpso-mux 分流器。${PLAIN}"
    echo -e "${YELLOW}请先安装发布版 vpso-mux 二进制，或在源码目录安装 Go 后重试。${PLAIN}"
    return 1
}

write_vpso_mux_systemd_service() {
    cat <<'EOF' > /etc/systemd/system/vpso-mux.service
[Unit]
Description=VPS-Optimize TCP Peek + Splice vpso-mux router
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/vpso-mux.service
    systemctl daemon-reload >/dev/null 2>&1 || true
}

run_vpso_mux_config_check() {
    local config_file="${1:-$(vpso_mux_config_path)}"
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        /usr/local/bin/vpso-mux -config "$config_file" -check
        return $?
    fi
    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if command -v go >/dev/null 2>&1 && [[ -d "$source_dir/cmd/vpso-mux" ]]; then
        (cd "$source_dir" && go run ./cmd/vpso-mux -config "$config_file" -check)
        return $?
    fi
    echo -e "${RED}❌ 缺少 vpso-mux 二进制或 Go 工具链，无法执行完整配置校验。${PLAIN}"
    return 1
}

tcp_peek_dry_run_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 分流规则校验${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    local config_file
    config_file=$(vpso_mux_config_path)
    [[ -f "$config_file" ]] || { echo -e "${YELLOW}未找到 ${config_file}，正在先生成配置。${PLAIN}"; write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$config_file" || return 1; }
    echo -e "${CYAN}▶ 校验 YAML、SNI、backend、whitelist 和重复 SNI...${PLAIN}"
    run_vpso_mux_config_check "$config_file" || return 1
    echo -e "${CYAN}▶ 检查本地后端端口...${PLAIN}"
    tcp_probe_host "Caddy 127.0.0.1:${CADDY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "Xray/REALITY 127.0.0.1:${XRAY_LISTEN_PORT}" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true
    print_sni_ip_whitelist_summary
    echo -e "${GREEN}✅ 配置校验完成。请先使用 TCP Peek + Splice 测试入口验证，不要直接接管 443。${PLAIN}"
}

start_tcp_peek_test_port() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}TCP Peek + Splice 测试入口${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ "$(single_443_current_engine)" == "tcp_peek" ]]; then
        echo -e "${RED}❌ 当前入口已经是 TCP Peek + Splice 模式。为避免误停公网 443，本入口不覆盖运行中的 443 配置。${PLAIN}"
        return 1
    fi
    echo -e "${YELLOW}vpso-mux 分流器只监听 8444，Nginx Stream 模式继续负责公网 443。${PLAIN}"
    write_vpso_mux_config_from_sni_stack "8444" "$(vpso_mux_config_path)" || return 1
    install_vpso_mux_binary || return 1
    run_vpso_mux_config_check "$(vpso_mux_config_path)" || return 1
    write_vpso_mux_systemd_service
    systemctl enable vpso-mux >/dev/null 2>&1 || true
    systemctl restart vpso-mux || { echo -e "${RED}❌ vpso-mux 启动失败，请查看日志。${PLAIN}"; return 1; }
    echo -e "${GREEN}✅ vpso-mux 已启动在测试端口 8444。${PLAIN}"
    echo -e "测试命令："
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:8444 -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:8444 -servername random.example.com"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  curl -vk --resolve ${SITE_DOMAINS[0]}:8444:SERVER_IP https://${SITE_DOMAINS[0]}:8444/"
}

switch_public_443_to_tcp_peek() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}切换公网 443 到 TCP Peek + Splice 模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}TCP Peek + Splice 模式会备份配置、停止 Nginx Stream 对 ${NGINX_LISTEN_PORT} 的监听，并启动 vpso-mux 分流器监听公网 ${NGINX_LISTEN_PORT}。${PLAIN}"
    if [[ -z "$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")" ]]; then
        echo -e "${RED}⚠️ 面板/订阅域名 ${PANEL_DOMAIN} 当前没有 IP 白名单；切换后该 SNI route 将公开到 Caddy。${PLAIN}"
    fi
    confirm_risk_action "切换公网 443 到 TCP Peek + Splice 模式" \
        "Nginx Stream 443 监听关系、vpso-mux 分流器配置和 systemd 服务" \
        "菜单 [19] -> [7] 可回滚到 Nginx Stream 模式；失败时脚本会自动恢复本次备份" \
        "已完成 8444 测试，并确认面板白名单、Caddy、Xray 后端都正常。" || return 1

    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    local tmp_config backup_dir nginx_conf
    tmp_config="/etc/vps-optimize/vpso-mux.yaml.tmp.$$"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    install_vpso_mux_binary || { quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true; rollback_sni_stack_after_failure "$backup_dir" "vpso-mux 二进制安装失败"; return 1; }
    run_vpso_mux_config_check "$tmp_config" || { quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true; rollback_sni_stack_after_failure "$backup_dir" "vpso-mux 配置校验失败"; return 1; }
    write_vpso_mux_systemd_service
    mv "$tmp_config" "$(vpso_mux_config_path)" || { rollback_sni_stack_after_failure "$backup_dir" "vpso-mux 配置替换失败"; return 1; }
    nginx_conf="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    [[ -e "$nginx_conf" ]] && quarantine_path "$nginx_conf" "/etc/vps-optimize/quarantine/nginx-sni" >/dev/null 2>&1 || true
    if ! nginx -t >/dev/null 2>&1; then
        rollback_sni_stack_after_failure "$backup_dir" "禁用 Nginx stream 443 后 nginx -t 失败"
        return 1
    fi
    systemctl restart nginx || { rollback_sni_stack_after_failure "$backup_dir" "Nginx 重启失败"; return 1; }
    systemctl enable vpso-mux >/dev/null 2>&1 || true
    if ! systemctl restart vpso-mux; then
        rollback_sni_stack_after_failure "$backup_dir" "vpso-mux 重启失败"
        return 1
    fi
    if ! ss -lntup 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' | grep -q 'vpso-mux'; then
        systemctl stop vpso-mux >/dev/null 2>&1 || true
        rollback_sni_stack_after_failure "$backup_dir" "公网 443 未由 vpso-mux 监听"
        return 1
    fi
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || { systemctl stop vpso-mux >/dev/null 2>&1 || true; rollback_sni_stack_after_failure "$backup_dir" "Caddy 后端不可达"; return 1; }
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || { systemctl stop vpso-mux >/dev/null 2>&1 || true; rollback_sni_stack_after_failure "$backup_dir" "Xray 后端不可达"; return 1; }
    write_single_443_engine_state "tcp_peek" "$backup_dir"
    echo -e "${GREEN}✅ 公网 443 已切换到 TCP Peek + Splice 模式。${PLAIN}"
    sni_stack_health_check_enhanced
}

rollback_tcp_peek_to_nginx_stream() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}从 TCP Peek + Splice 模式回滚到 Nginx Stream 模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    confirm_risk_action "回滚 443 到 Nginx Stream 稳定模式" \
        "vpso-mux 分流器服务和 Nginx Stream 443 监听关系" \
        "如 Nginx 回滚失败，请用最近的 /etc/vps-optimize/backups/sni-stack_* 手动恢复" \
        "Nginx Stream 是默认稳定模式，回滚后会重新运行链路体检。" || return 1
    systemctl stop vpso-mux >/dev/null 2>&1 || true
    systemctl disable vpso-mux >/dev/null 2>&1 || true
    reapply_sni_stack_from_env --yes || return 1
    write_single_443_engine_state "nginx_stream"
    echo -e "${GREEN}✅ 已回滚到 Nginx Stream 模式。${PLAIN}"
    sni_stack_health_check
}

normalize_entry_mode_name() {
    local mode="$1"
    case "$mode" in
        "nginx_stream"|"nginx-stream") echo "nginx-stream" ;;
        "xray_fallback"|"xray-fallback") echo "xray-fallback" ;;
        "tcp_peek"|"tcp-peek") echo "tcp-peek" ;;
        *) return 1 ;;
    esac
}

entry_mode_engine_name() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || return 1
    case "$mode" in
        "nginx-stream") echo "nginx_stream" ;;
        "xray-fallback") echo "xray_fallback" ;;
        "tcp-peek") echo "tcp_peek" ;;
    esac
}

entry_mode_expected_listener() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || return 1
    case "$mode" in
        "nginx-stream") echo "nginx" ;;
        "xray-fallback") echo "xray" ;;
        "tcp-peek") echo "tcppeek" ;;
    esac
}

systemd_unit_exists() {
    local unit="$1"
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || systemctl status "$unit" >/dev/null 2>&1
}

xray_entry_service_name() {
    local svc
    for svc in xray.service x-ui.service 3x-ui.service; do
        if systemd_unit_exists "$svc"; then
            echo "${svc%.service}"
            return 0
        fi
    done
    return 1
}

restart_xray_entry_service() {
    local svc
    svc=$(xray_entry_service_name) || { echo -e "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务。${PLAIN}"; return 1; }
    systemctl enable "$svc" >/dev/null 2>&1 || true
    systemctl restart "$svc" || { echo -e "${RED}❌ ${svc} 重启失败。${PLAIN}"; return 1; }
}

stop_xray_entry_service_if_public_443() {
    local listener svc
    listener=$(detect_443_listener)
    [[ "${listener%%|*}" == "xray" ]] || return 0
    svc=$(xray_entry_service_name) || return 0
    systemctl stop "$svc" >/dev/null 2>&1 || true
}

disable_nginx_stream_public_443() {
    local nginx_conf="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
    [[ -e "$nginx_conf" ]] && quarantine_path "$nginx_conf" "/etc/vps-optimize/quarantine/nginx-sni" >/dev/null 2>&1 || true
    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/dev/null 2>&1 || return 1
        restart_service_if_available nginx >/dev/null 2>&1 || true
    fi
}

stop_public_443_entry_services_for_target() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1

    if [[ "$target_mode" != "nginx-stream" ]]; then
        disable_nginx_stream_public_443 || return 1
    fi
    if [[ "$target_mode" != "tcp-peek" ]]; then
        systemctl stop vpso-mux >/dev/null 2>&1 || true
    fi
    if [[ "$target_mode" != "xray-fallback" ]]; then
        stop_xray_entry_service_if_public_443
    fi
}

verify_public_443_listener_for_mode() {
    local mode="$1"
    local expected listener
    mode=$(normalize_entry_mode_name "$mode") || return 1
    expected=$(entry_mode_expected_listener "$mode") || return 1
    listener=$(detect_443_listener)
    if [[ "${listener%%|*}" == "$expected" ]]; then
        return 0
    fi
    echo -e "${RED}❌ 公网 443 监听不符合 ${mode}：期望 ${expected}，实际 ${listener#*|}${PLAIN}"
    return 1
}

check_entry_mode_dependencies() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode") || { echo -e "${RED}❌ 目标入口模式无效：${mode}${PLAIN}"; return 1; }

    case "$mode" in
        "nginx-stream")
            command -v nginx >/dev/null 2>&1 || echo -e "${YELLOW}未检测到 Nginx，切换时会沿用现有 Nginx stream 安装逻辑。${PLAIN}"
            command -v caddy >/dev/null 2>&1 || echo -e "${YELLOW}未检测到 Caddy，切换时会沿用现有 Caddy 安装逻辑。${PLAIN}"
            ;;
        "tcp-peek")
            [[ -x /usr/local/bin/vpso-mux ]] || { echo -e "${RED}❌ vpso-mux 分流器不存在：缺少 /usr/local/bin/vpso-mux，拒绝切换到 TCP Peek + Splice 模式。${PLAIN}"; return 1; }
            command -v caddy >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 Caddy，TCP Peek + Splice 模式无法转发 Web 流量。${PLAIN}"; return 1; }
            ;;
        "xray-fallback")
            xray_entry_service_name >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务，拒绝切换。${PLAIN}"; return 1; }
            command -v caddy >/dev/null 2>&1 || { echo -e "${RED}❌ 未检测到 Caddy，xray-fallback 无法 fallback 普通 HTTPS 到 Caddy。${PLAIN}"; return 1; }
            ;;
    esac
}

backup_entry_mode_config() {
    local backup_dir service_path svc listener_info
    create_sni_stack_backup >/dev/null
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || { echo -e "${RED}❌ 入口模式切换备份失败。${PLAIN}"; return 1; }

    mkdir -p "$backup_dir/systemd" "$backup_dir/xray" "$backup_dir/vps-optimize"
    for svc in nginx.service caddy.service xray.service x-ui.service 3x-ui.service vpso-mux.service; do
        for service_path in "/etc/systemd/system/$svc" "/lib/systemd/system/$svc" "/usr/lib/systemd/system/$svc"; do
            [[ -f "$service_path" ]] && cp -a "$service_path" "$backup_dir/systemd/${service_path//\//_}" 2>/dev/null || true
        done
    done
    [[ -f /etc/xray/config.json ]] && cp -a /etc/xray/config.json "$backup_dir/xray/etc-xray-config.json" 2>/dev/null || true
    [[ -f /usr/local/etc/xray/config.json ]] && cp -a /usr/local/etc/xray/config.json "$backup_dir/xray/usr-local-etc-xray-config.json" 2>/dev/null || true
    [[ -f /etc/vps-optimize/xray-sni-routes.conf ]] && cp -a /etc/vps-optimize/xray-sni-routes.conf "$backup_dir/vps-optimize/xray-sni-routes.conf" 2>/dev/null || true
    listener_info=$(detect_443_listener)
    {
        echo "created_at=$(date -Is 2>/dev/null || date)"
        echo "entry_mode=$(get_entry_mode)"
        echo "listener=${listener_info}"
        echo "ss_443:"
        ss -lntp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "none"
    } > "$backup_dir/vps-optimize/443-listener-state.txt"
    echo "$backup_dir"
}

rollback_last_entry_mode() {
    local backup_dir="${1:-}"
    local manual=0
    local old_mode=""
    if [[ -z "$backup_dir" ]]; then
        manual=1
        backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    fi
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        echo -e "${RED}❌ 未找到可回滚的入口模式备份。${PLAIN}"
        return 1
    fi
    if [[ -f "$backup_dir/vps-optimize/sni-stack.env" ]]; then
        old_mode=$(
            # shellcheck disable=SC1090
            source "$backup_dir/vps-optimize/sni-stack.env" 2>/dev/null || true
            printf '%s' "${ENTRY_MODE:-nginx-stream}"
        )
        old_mode=$(normalize_entry_mode_name "$old_mode" 2>/dev/null || echo "nginx-stream")
    fi

    if [[ "$manual" -eq 1 ]]; then
        confirm_risk_action "回滚上一次 443 入口模式切换" \
            "Nginx/Caddy/Xray/vpso-mux 入口相关配置和服务状态" \
            "再次切换入口模式，或用备份目录手动恢复" \
            "将使用备份目录 ${backup_dir} 覆盖当前入口配置。" || return 1
    fi

    echo -e "${YELLOW}▶ 正在回滚上一次入口模式切换：${backup_dir}${PLAIN}"
    restore_sni_stack_backup_files "$backup_dir" || { echo -e "${RED}❌ 回滚文件恢复失败。${PLAIN}"; return 1; }
    systemctl daemon-reload >/dev/null 2>&1 || true
    load_sni_stack_env >/dev/null 2>&1 || true
    old_mode=${old_mode:-$(get_entry_mode)}

    case "$old_mode" in
        "nginx-stream")
            systemctl stop vpso-mux >/dev/null 2>&1 || true
            restart_service_if_available caddy >/dev/null 2>&1 || true
            restart_service_if_available nginx >/dev/null 2>&1 || true
            ;;
        "tcp-peek")
            restart_service_if_available caddy >/dev/null 2>&1 || true
            restart_service_if_available nginx >/dev/null 2>&1 || true
            systemctl enable vpso-mux >/dev/null 2>&1 || true
            systemctl restart vpso-mux >/dev/null 2>&1 || true
            ;;
        "xray-fallback")
            systemctl stop vpso-mux >/dev/null 2>&1 || true
            disable_nginx_stream_public_443 >/dev/null 2>&1 || true
            restart_service_if_available caddy >/dev/null 2>&1 || true
            restart_xray_entry_service >/dev/null 2>&1 || true
            ;;
    esac
    set_entry_mode "$old_mode" >/dev/null 2>&1 || true
    write_single_443_engine_state "$(entry_mode_engine_name "$old_mode" 2>/dev/null || echo nginx_stream)" "$backup_dir"
    echo -e "${GREEN}✅ 已回滚到上一次入口模式：${old_mode}${PLAIN}"
}

apply_nginx_stream_mode() {
    local backup_dir="${1:-}"
    install_nginx_stream_stack || return 1
    harden_nginx_public_errors
    ensure_caddy_local_base_config || return 1
    cleanup_old_nginx_sni_stream_configs
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    write_nginx_sni_stream_config || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx || return 1
    verify_public_443_listener_for_mode "nginx-stream" || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || return 1
    write_single_443_engine_state "nginx_stream" "$backup_dir"
}

apply_tcppeek_mode() {
    local backup_dir="${1:-}"
    local tmp_config
    install_vpso_mux_binary || return 1
    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    tmp_config="/etc/vps-optimize/vpso-mux.yaml.tmp.$$"
    write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
    run_vpso_mux_config_check "$tmp_config" || { quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true; return 1; }
    write_vpso_mux_systemd_service
    mv "$tmp_config" "$(vpso_mux_config_path)" || return 1
    systemctl enable vpso-mux >/dev/null 2>&1 || true
    systemctl restart vpso-mux || return 1
    verify_public_443_listener_for_mode "tcp-peek" || return 1
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    tcp_probe_host "Xray/REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || return 1
    write_single_443_engine_state "tcp_peek" "$backup_dir"
}

apply_xray_fallback_mode() {
    local backup_dir="${1:-}"
    ensure_caddy_local_base_config || return 1
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || return 1
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || return 1
    restart_xray_entry_service || return 1
    verify_public_443_listener_for_mode "xray-fallback" || return 1
    tcp_probe_host "Caddy fallback 后端" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || return 1
    write_single_443_engine_state "xray_fallback" "$backup_dir"
}

apply_entry_mode_by_name() {
    local target_mode="$1"
    local backup_dir="${2:-}"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "nginx-stream") apply_nginx_stream_mode "$backup_dir" ;;
        "xray-fallback") apply_xray_fallback_mode "$backup_dir" ;;
        "tcp-peek") apply_tcppeek_mode "$backup_dir" ;;
    esac
}

select_initial_entry_mode() {
    local choice
    ENTRY_MODE="nginx-stream"

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}选择本次首次配置使用的 443 入口模式${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Nginx Stream 模式${PLAIN}       ${YELLOW}(默认稳定模式，适合大多数用户)${PLAIN}"
    echo -e "${GREEN}  2. Xray Fallback 模式${PLAIN}      ${YELLOW}(需你已在 Xray/3x-ui 准备好公网 443 主入站)${PLAIN}"
    echo -e "${GREEN}  3. TCP Peek + Splice 模式${PLAIN}  ${YELLOW}(vpso-mux 分流器接管公网 443，进阶模式)${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    read_trimmed choice "请选择入口模式（默认 1）: "
    case "${choice:-1}" in
        1) ENTRY_MODE="nginx-stream" ;;
        2) ENTRY_MODE="xray-fallback" ;;
        3) ENTRY_MODE="tcp-peek" ;;
        0) echo -e "${BLUE}已取消首次配置。${PLAIN}"; return 1 ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}"; return 1 ;;
    esac
    echo -e "${GREEN}✅ 已选择 443 入口模式：${ENTRY_MODE}${PLAIN}"
}

prepare_initial_entry_mode_dependencies() {
    local target_mode="$1"
    target_mode=$(normalize_entry_mode_name "$target_mode") || return 1
    case "$target_mode" in
        "tcp-peek")
            install_vpso_mux_binary || return 1
            ;;
        "xray-fallback")
            xray_entry_service_name >/dev/null 2>&1 || {
                echo -e "${RED}❌ 未检测到 xray/x-ui/3x-ui systemd 服务，无法首次配置为 xray-fallback。${PLAIN}"
                echo -e "${YELLOW}请先在 [4 面板、节点与订阅工具] 中安装并配置 Xray/3x-ui 主入站，或改选 Nginx Stream 模式 / TCP Peek + Splice 模式。${PLAIN}"
                return 1
            }
            print_xray_fallback_mode_explanation
            confirm_risk_action "首次配置使用 Xray Fallback 模式" \
                "公网 443 将由已有 Xray 主入站接管，普通 HTTPS fallback 到 Caddy" \
                "返回首次配置并选择 Nginx Stream 模式或 TCP Peek + Splice 模式" \
                "确认你已经在 Xray/3x-ui 中准备好公网 443 主入站；脚本不会创建或修改 3x-ui/Xray 入站内部配置。" || return 1
            ;;
    esac
}

switch_entry_mode() {
    local target_mode="$1"
    local current_mode backup_dir yn
    load_sni_stack_env || return 1
    target_mode=$(normalize_entry_mode_name "$target_mode") || { echo -e "${RED}❌ 目标入口模式无效：${target_mode}${PLAIN}"; return 1; }
    current_mode=$(get_entry_mode)

    if [[ "$target_mode" == "$current_mode" ]]; then
        read_trimmed yn "当前已经是 ${target_mode}，是否重新应用当前模式？(y/n，默认 n): "
        [[ "$yn" =~ ^[Yy]$ ]] && reapply_current_entry_mode
        return $?
    fi

    echo -e "${CYAN}准备切换 443 入口模式：${current_mode} -> ${target_mode}${PLAIN}"
    check_entry_mode_dependencies "$target_mode" || return 1
    backup_dir=$(backup_entry_mode_config) || return 1
    if [[ "$target_mode" == "xray-fallback" ]]; then
        select_xray_fallback_main_route_for_switch || return 1
    fi

    if ! stop_public_443_entry_services_for_target "$target_mode"; then
        echo -e "${RED}❌ 停止当前公网 443 入口服务失败，正在回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi

    if ! apply_entry_mode_by_name "$target_mode" "$backup_dir"; then
        echo -e "${RED}❌ 入口模式 ${target_mode} 应用失败，正在自动回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi

    ENTRY_MODE="$target_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$target_mode")" "$backup_dir"
    echo -e "${GREEN}✅ 443 入口模式已切换为：${target_mode}${PLAIN}"
    show_current_entry_status
}

reapply_current_entry_mode() {
    local current_mode backup_dir
    load_sni_stack_env || return 1
    current_mode=$(get_entry_mode)
    current_mode=$(normalize_entry_mode_name "$current_mode") || { echo -e "${RED}❌ 当前 ENTRY_MODE 无效：${current_mode}${PLAIN}"; return 1; }
    echo -e "${CYAN}正在重新应用当前 443 入口模式：${current_mode}${PLAIN}"
    check_entry_mode_dependencies "$current_mode" || return 1
    backup_dir=$(backup_entry_mode_config) || return 1
    if [[ "$current_mode" == "xray-fallback" ]]; then
        select_xray_fallback_main_route_for_switch || return 1
    fi
    if ! stop_public_443_entry_services_for_target "$current_mode"; then
        echo -e "${RED}❌ 停止当前公网 443 入口服务失败，正在回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi
    if ! apply_entry_mode_by_name "$current_mode" "$backup_dir"; then
        echo -e "${RED}❌ 当前入口模式重新应用失败，正在自动回滚。${PLAIN}"
        rollback_last_entry_mode "$backup_dir"
        return 1
    fi
    ENTRY_MODE="$current_mode"
    save_sni_stack_env
    write_single_443_engine_state "$(entry_mode_engine_name "$current_mode")" "$backup_dir"
    echo -e "${GREEN}✅ 当前入口模式已重新应用：${current_mode}${PLAIN}"
    show_current_entry_status
}

view_vpso_mux_logs() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}📜 vpso-mux 日志${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    journalctl -u vpso-mux -n 120 --no-pager 2>/dev/null || echo "未读取到 vpso-mux 日志。"
}

entry_mode_supports_xray_sni_routes() {
    local mode="$1"
    mode=$(normalize_entry_mode_name "$mode" 2>/dev/null) || return 1
    [[ "$mode" == "nginx-stream" || "$mode" == "tcp-peek" ]]
}

print_443_health_status_code_hints() {
    echo -e "${BOLD}状态码提示${PLAIN}"
    echo -e "  - 403/401：可能是 Web 白名单、CDN/WAF、源站保护、Host/SNI 策略或后端鉴权。"
    echo -e "  - 502：可能是 Caddy 到后端端口不通。"
    echo -e "  - 525/526：可能是 CDN 到源站 TLS 或证书校验失败。"
    echo -e "  - 超时：可能是 443 监听、防火墙、安全组、入口服务异常。"
}

print_443_health_reality_notes() {
    echo -e "${BOLD}REALITY 检查提示${PLAIN}"
    echo -e "  - 不要要求 REALITY serverName/dest 加入 Caddy。"
    echo -e "  - 不要要求本机证书覆盖 REALITY serverName。"
    echo -e "  - REALITY 应检查外部目标站点是否真实可访问、TLS 特征是否稳定。"
    echo -e "  - 普通 TLS 节点和 REALITY 节点的 SNI/serverName 检查逻辑必须区分。"
}

print_web_domain_http_status() {
    local label="$1"
    local domain="$2"
    local path="${3:-/}"
    local url code

    [[ -n "$domain" ]] || return 0
    path=$(normalize_path_prefix "$path")
    url="https://${domain}${path}"

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${label}：${url} -> ${YELLOW}未检测，curl 未安装${PLAIN}"
        return 0
    fi

    code=$(curl -k -L -o /dev/null -sS --connect-timeout 6 --max-time 12 -w '%{http_code}' "$url" 2>/dev/null) || code="timeout"
    [[ -z "$code" || "$code" == "000" ]] && code="timeout"
    echo -e "${label}：${url} -> ${code}"
}

print_domain_cert_file_status() {
    local domain="$1"
    local cert key root_cert root_key

    [[ -n "$domain" ]] || return 0
    cert="/etc/caddy/certs/${domain}.crt"
    key="/etc/caddy/certs/${domain}.key"
    root_cert="/root/cert/${domain}.crt"
    root_key="/root/cert/${domain}.key"

    echo -e "${CYAN}${domain}${PLAIN}"
    [[ -s "$cert" ]] && echo -e "  ${GREEN}✅ 证书文件存在：${cert}${PLAIN}" || echo -e "  ${YELLOW}⚠️ 证书文件不存在或为空：${cert}${PLAIN}"
    [[ -s "$key" ]] && echo -e "  ${GREEN}✅ 私钥文件存在：${key}${PLAIN}" || echo -e "  ${YELLOW}⚠️ 私钥文件不存在或为空：${key}${PLAIN}"

    if [[ -L "$root_cert" && "$(readlink "$root_cert" 2>/dev/null)" == "$cert" && -e "$root_cert" ]]; then
        echo -e "  ${GREEN}✅ /root/cert 证书软链接正常：${root_cert} -> ${cert}${PLAIN}"
    else
        echo -e "  ${YELLOW}⚠️ /root/cert 证书软链接异常或不存在：${root_cert}${PLAIN}"
    fi

    if [[ -L "$root_key" && "$(readlink "$root_key" 2>/dev/null)" == "$key" && -e "$root_key" ]]; then
        echo -e "  ${GREEN}✅ /root/cert 私钥软链接正常：${root_key} -> ${key}${PLAIN}"
    else
        echo -e "  ${YELLOW}⚠️ /root/cert 私钥软链接异常或不存在：${root_key}${PLAIN}"
    fi
}

print_xray_route_health_list() {
    local mode="$1"
    local i sni addr port line main_idx status

    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未配置 Xray 入站分流规则：$(xray_sni_routes_path)${PLAIN}"
        return 0
    fi

    main_idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        sni="${XRAY_SNI_ROUTE_SNIS[$i]}"
        addr="${XRAY_SNI_ROUTE_ADDRS[$i]}"
        port="${XRAY_SNI_ROUTE_PORTS[$i]}"
        [[ -n "$sni" ]] || continue

        if [[ "$mode" == "xray-fallback" ]]; then
            if [[ -n "$main_idx" && "$i" == "$main_idx" ]]; then
                status="xray-fallback 主入站，当前模式生效"
            else
                status="已保留，当前 xray-fallback 模式下不生效"
            fi
        else
            status="当前模式支持按 SNI 分流"
        fi

        echo -e "${CYAN}${sni}${PLAIN} -> ${addr}:${port}（${status}）"
        if [[ "${CADDY_LISTEN_PORT:-}" == "$port" ]]; then
            echo -e "${RED}  ❌ 与 Caddy 本地端口 ${CADDY_LISTEN_PORT} 冲突。${PLAIN}"
        fi
        line=$(xray_route_listen_line_by_addr_port "$addr" "$port")
        if [[ -n "$line" ]]; then
            echo -e "${GREEN}  ✅ 端口已监听：${line}${PLAIN}"
            if echo "$line" | grep -Eq '(^|[[:space:]])(0\.0\.0\.0|\*|\[::\]):'"${port}"'[[:space:]]'; then
                echo -e "${YELLOW}  ⚠️ 检测到可能监听在 0.0.0.0/[::]，存在公网暴露风险，建议改为 127.0.0.1。${PLAIN}"
            fi
        else
            echo -e "${YELLOW}  ⚠️ 未检测到 ${addr}:${port} 监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}"
        fi
    done
}

sni_stack_health_check_enhanced() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 443 链路体检增强${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    detect_current_entry_status

    local mode caddy_backend xray_backend panel_backend sub_backend site_backend route_count ranges i domain public_443_lines mux_config mux_service
    mode="$ENTRY_STATUS_MODE"
    caddy_backend=$(format_hostport "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT")
    xray_backend=$(format_hostport "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT")
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    mux_config=$(vpso_mux_config_path)
    mux_service="/etc/systemd/system/$(vpso_mux_service_name)"
    route_count=$((2 + ${#SITE_DOMAINS[@]} + ${#TCP_ROUTE_SNIS[@]} + ${#XRAY_SNI_ROUTE_SNIS[@]}))

    echo -e "${BOLD}入口状态${PLAIN}"
    echo -e "当前 ENTRY_MODE：${GREEN}${mode}${PLAIN}"
    echo -e "实际公网 443 监听服务：${ENTRY_STATUS_LISTENER_PROCESS}"
    public_443_lines=$(ss -lntp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || true)
    echo -e "${public_443_lines:-未监听或当前用户无权限查看进程}"
    if [[ "$ENTRY_STATUS_CONSISTENT" == "yes" ]]; then
        echo -e "配置模式与实际监听：${GREEN}一致${PLAIN}"
    else
        echo -e "配置模式与实际监听：${YELLOW}不一致${PLAIN}"
        echo -e "${YELLOW}配置模式与实际监听不一致，建议重新应用当前入口模式。${PLAIN}"
    fi
    echo -e "nginx 状态：${ENTRY_STATUS_NGINX_SERVICE}"
    echo -e "Xray/3x-ui 状态：${ENTRY_STATUS_XRAY_SERVICE}"
    echo -e "TCP Peek + Splice 状态：${ENTRY_STATUS_TCPPEEK_SERVICE}"
    echo -e "caddy 状态：$(service_status_compact caddy)"
    if [[ -f "$mux_config" ]]; then
        echo -e "TCP Peek + Splice 分流规则：${GREEN}存在 ${mux_config}${PLAIN}"
    else
        echo -e "TCP Peek + Splice 分流规则：${YELLOW}未找到 ${mux_config}${PLAIN}"
    fi
    if [[ -f "$mux_service" ]]; then
        echo -e "vpso-mux 分流器 systemd：${GREEN}存在 ${mux_service}${PLAIN}"
    else
        echo -e "vpso-mux 分流器 systemd：${YELLOW}未找到 ${mux_service}${PLAIN}"
    fi

    echo -e "------------------------------------------------"
    echo -e "${BOLD}本地监听${PLAIN}"
    echo -e "Caddy 本地监听端口：${caddy_backend}"
    get_listen_line_by_port "$CADDY_LISTEN_PORT" | grep -q "$CADDY_LISTEN_ADDR" && echo -e "${GREEN}✅ Caddy 期望监听 ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}${PLAIN}" || echo -e "${YELLOW}⚠️ Caddy 监听地址需确认：$(get_listen_line_by_port "$CADDY_LISTEN_PORT")${PLAIN}"
    echo -e "Xray 本地监听端口：${xray_backend}"
    get_listen_line_by_port "$XRAY_LISTEN_PORT" | grep -q "$XRAY_LISTEN_ADDR" && echo -e "${GREEN}✅ Xray 期望监听 ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}" || echo -e "${YELLOW}⚠️ Xray 监听地址需确认：$(get_listen_line_by_port "$XRAY_LISTEN_PORT")${PLAIN}"
    if [[ "$ENTRY_STATUS_LISTENER" == "xray" ]]; then
        echo -e "Xray 公网监听端口：${GREEN}公网 443 当前由 Xray 监听${PLAIN}"
    else
        echo -e "Xray 公网监听端口：未检测到 Xray 监听公网 443"
    fi

    echo -e "------------------------------------------------"
    echo -e "${BOLD}Xray 入站分流规则${PLAIN}"
    if entry_mode_supports_xray_sni_routes "$mode"; then
        echo -e "当前入口模式是否支持 Xray 入站分流规则：${GREEN}支持${PLAIN}"
    else
        echo -e "当前入口模式是否支持 Xray 入站分流规则：${YELLOW}不支持/当前不生效${PLAIN}"
    fi
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "${YELLOW}当前为 Xray Fallback 模式，Xray 入站管理中的多 SNI 分流规则不生效。${PLAIN}"
        echo -e "${YELLOW}如需多个本地 Xray 入站，请切换到 Nginx Stream 模式或 TCP Peek + Splice 模式。${PLAIN}"
        echo -e "${YELLOW}普通 HTTPS 流量会先进入 Xray，再 fallback 到 Caddy；403/拒绝访问通常优先排查 Web 白名单、CDN/WAF、源站保护、Cloudflare 回源限制或 Host/SNI 策略。${PLAIN}"
        print_xray_fallback_main_route_summary
    fi
    print_xray_route_health_list "$mode"

    echo -e "------------------------------------------------"
    echo -e "${BOLD}Web 域名白名单状态${PLAIN}"
    print_sni_ip_whitelist_summary
    echo -e "Xray 节点白名单：不支持/不启用"

    echo -e "------------------------------------------------"
    echo -e "${BOLD}证书文件与 /root/cert 软链接${PLAIN}"
    print_domain_cert_file_status "$PANEL_DOMAIN"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        print_domain_cert_file_status "$domain"
    done

    echo -e "------------------------------------------------"
    echo -e "${BOLD}Web 域名访问 HTTP 状态码${PLAIN}"
    print_web_domain_http_status "面板路径" "$PANEL_DOMAIN" "$PANEL_WEB_PATH"
    print_web_domain_http_status "普通订阅路径" "$PANEL_DOMAIN" "$SUB_URI_PATH"
    print_web_domain_http_status "Clash/Mihomo 路径" "$PANEL_DOMAIN" "$CLASH_URI_PATH"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        print_web_domain_http_status "网站域名" "$domain" "/"
    done
    print_443_health_status_code_hints

    echo -e "------------------------------------------------"
    echo -e "${BOLD}路由摘要${PLAIN}"
    echo -e "default_backend 当前指向：${xray_backend}"
    echo -e "routes 数量：${route_count}"
    echo -e "unknown SNI 策略：default_backend -> ${xray_backend}"
    ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    echo -e "web panel: ${PANEL_DOMAIN}${PANEL_WEB_PATH} -> Caddy ${caddy_backend} -> 面板后端 ${panel_backend}"
    echo -e "web subscription: ${PANEL_DOMAIN}${SUB_URI_PATH} -> Caddy ${caddy_backend} -> 订阅后端 ${sub_backend}"
    echo -e "web clash/mihomo: ${PANEL_DOMAIN}${CLASH_URI_PATH} -> Caddy ${caddy_backend} -> 订阅后端 ${sub_backend}"
    echo -e "route panel: ${PANEL_DOMAIN} -> ${caddy_backend} whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    for i in "${!SITE_DOMAINS[@]}"; do
        domain="${SITE_DOMAINS[$i]}"
        [[ -n "$domain" ]] || continue
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        echo -e "web site: ${domain}/ -> Caddy ${caddy_backend} -> 网站后端 ${site_backend}"
        echo -e "route site: ${domain} -> ${caddy_backend} whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        domain="${TCP_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        echo -e "route tcp: ${domain} -> $(format_hostport "${TCP_ROUTE_ADDRS[$i]}" "${TCP_ROUTE_PORTS[$i]}") whitelist=$([[ -n "$ranges" ]] && echo yes || echo no)"
    done
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        domain="${XRAY_SNI_ROUTE_SNIS[$i]}"
        [[ -n "$domain" ]] || continue
        echo -e "route xray: ${domain} -> $(format_hostport "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}") whitelist=no"
    done
    echo -e "route reality: ${REALITY_SNI} -> ${xray_backend} whitelist=no"
    print_443_health_reality_notes

    echo -e "------------------------------------------------"
    echo -e "最近 20 行 vpso-mux 日志："
    journalctl -u vpso-mux -n 20 --no-pager 2>/dev/null || echo "未读取到 vpso-mux 日志。"
    echo -e "------------------------------------------------"
    echo -e "测试命令："
    echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername ${PANEL_DOMAIN}"
    [[ ${#SITE_DOMAINS[@]} -gt 0 ]] && echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername ${SITE_DOMAINS[0]}"
    echo -e "  openssl s_client -connect SERVER_IP:${NGINX_LISTEN_PORT} -servername random.example.com"
}

check_sni_stack_subscription_hint() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔎 订阅链接与 External Proxy 检查提示${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "请在 3x-ui 的 REALITY 入站里开启 External Proxy，并确保："
    echo -e "  类型：相同"
    echo -e "  地址：你的节点域名或服务器 IP"
    echo -e "  端口：${NGINX_LISTEN_PORT}"
    echo -e "${YELLOW}提示：本教程推荐 Cloudflare 灰云 / DNS only。REALITY 节点地址必须直连 VPS，可填灰云节点域名或服务器公网 IP。${PLAIN}"
    echo -e ""
    echo -e "复制节点链接后应该看到："
    echo -e "  vless://...@节点地址:${NGINX_LISTEN_PORT}?security=reality&sni=${REALITY_SNI}&..."
    echo -e ""
    echo -e "订阅公网入口应为："
    echo -e "  普通订阅：      https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo：  https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "${YELLOW}不要把公网订阅地址写成 :${SUB_LISTEN_PORT}，该端口只给 Caddy 在本机访问。${PLAIN}"
    echo -e ""
    echo -e "${YELLOW}如果链接里还是 :${XRAY_LISTEN_PORT}，说明 3x-ui 订阅仍在输出本地入站端口，请回到入站设置检查 External Proxy。${PLAIN}"
}

save_and_offer_reapply_sni_stack() {
    local yn env_file env_backup
    env_file="/etc/vps-optimize/sni-stack.env"
    env_backup=""
    if [[ -f "$env_file" ]]; then
        env_backup="${env_file}.pre_reapply_$(date +%Y%m%d_%H%M%S)"
        cp -p "$env_file" "$env_backup" 2>/dev/null || env_backup=""
    fi
    save_sni_stack_env
    echo -e "${GREEN}✅ 已保存新的 443 单入口运行参数。${PLAIN}"
    echo -e "${YELLOW}提示：保存后需要重新应用，Nginx/Caddy 才会使用新的端口或路径。${PLAIN}"
    read_trimmed yn "是否现在重新应用并重启 Nginx/Caddy？输入 YES 继续，直接回车取消: "
    if [[ "$yn" == "YES" ]]; then
        if ! reapply_sni_stack_from_env --yes; then
            if [[ -n "$env_backup" && -f "$env_backup" ]]; then
                cp -p "$env_backup" "$env_file" 2>/dev/null || true
                echo -e "${YELLOW}⚠️ 已恢复重新应用前的参数文件：${env_backup}${PLAIN}"
            fi
            return 1
        fi
    else
        echo -e "${YELLOW}稍后可执行 [19] -> [6] 重新应用上次配置。${PLAIN}"
        [[ -n "$env_backup" ]] && echo -e "${CYAN}参数修改前备份已保留：${env_backup}${PLAIN}"
    fi
}

edit_sni_stack_panel_subscription_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 3x-ui 面板 / 订阅端口与路径${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}适用于：你在 3x-ui 里修改了面板端口、订阅端口、普通订阅路径或 Clash/Mihomo 路径。${PLAIN}"
    echo -e "${YELLOW}注意：3x-ui 面板设置 -> 常规 -> 证书、订阅设置 -> 证书 路径必须清空，Caddy 才能按 HTTP 反代。${PLAIN}"
    echo -e "${YELLOW}修改前请先在 3x-ui 面板里保存对应设置，再来这里同步脚本。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "当前面板后端：${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "当前面板公网路径：${PANEL_WEB_PATH}"
    echo -e "当前订阅后端：${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
    echo -e "当前普通订阅路径：${SUB_URI_PATH}"
    echo -e "当前 Clash/Mihomo 路径：${CLASH_URI_PATH}"
    echo -e "------------------------------------------------"

    PANEL_LISTEN_ADDR=$(ask_with_default "3x-ui 面板监听地址" "$PANEL_LISTEN_ADDR")
    PANEL_LISTEN_PORT=$(ask_with_default "3x-ui 面板端口" "$PANEL_LISTEN_PORT")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 面板公网路径 / webBasePath" "$PANEL_WEB_PATH")")
    SUB_LISTEN_ADDR=$(ask_with_default "3x-ui 订阅服务监听地址" "$SUB_LISTEN_ADDR")
    SUB_LISTEN_PORT=$(ask_with_default "3x-ui 订阅服务端口" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "普通订阅路径前缀（不带客户端 Subscription，建议写 /sub/）" "$SUB_URI_PATH")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "$CLASH_URI_PATH")")

    is_valid_listen_addr "$PANEL_LISTEN_ADDR" || { echo -e "${RED}❌ 面板监听地址无效：${PANEL_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_listen_addr "$SUB_LISTEN_ADDR" || { echo -e "${RED}❌ 订阅监听地址无效：${SUB_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_port "$PANEL_LISTEN_PORT" || { echo -e "${RED}❌ 面板端口无效：${PANEL_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_port "$SUB_LISTEN_PORT" || { echo -e "${RED}❌ 订阅端口无效：${SUB_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_path_prefix "$PANEL_WEB_PATH" || { echo -e "${RED}❌ 面板公网路径无效：${PANEL_WEB_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$SUB_URI_PATH" || { echo -e "${RED}❌ 普通订阅路径无效：${SUB_URI_PATH}${PLAIN}"; return 1; }
    is_valid_path_prefix "$CLASH_URI_PATH" || { echo -e "${RED}❌ Clash/Mihomo 路径无效：${CLASH_URI_PATH}${PLAIN}"; return 1; }
    if [[ "$PANEL_WEB_PATH" == "$SUB_URI_PATH" || "$PANEL_WEB_PATH" == "$CLASH_URI_PATH" || "$SUB_URI_PATH" == "$CLASH_URI_PATH" ]]; then
        echo -e "${RED}❌ 面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。${PLAIN}"
        return 1
    fi
    warn_if_public_bind "3x-ui 面板" "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT" || return 1
    warn_if_public_bind "3x-ui 订阅服务" "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT" || return 1

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_reality_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 REALITY 本地监听与伪装 SNI${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}适用于：你在 3x-ui REALITY 入站里修改了监听端口、监听地址，或更换了伪装 SNI。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "当前 REALITY：${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "当前 REALITY SNI：${REALITY_SNI}"
    echo -e "------------------------------------------------"

    XRAY_LISTEN_ADDR=$(ask_with_default "Xray/3x-ui REALITY 本地监听地址" "$XRAY_LISTEN_ADDR")
    XRAY_LISTEN_PORT=$(ask_with_default "Xray/3x-ui REALITY 本地监听端口" "$XRAY_LISTEN_PORT")
    REALITY_SNI=$(normalize_domain_input "$(ask_with_default "REALITY 伪装 SNI" "$REALITY_SNI")")

    is_valid_listen_addr "$XRAY_LISTEN_ADDR" || { echo -e "${RED}❌ REALITY 监听地址无效：${XRAY_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_port "$XRAY_LISTEN_PORT" || { echo -e "${RED}❌ REALITY 端口无效：${XRAY_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_domain "$REALITY_SNI" || { echo -e "${RED}❌ REALITY SNI 无效：${REALITY_SNI}${PLAIN}"; return 1; }
    [[ "$REALITY_SNI" == "$PANEL_DOMAIN" ]] && { echo -e "${RED}❌ REALITY SNI 不能写面板域名。${PLAIN}"; return 1; }
    local existing
    for existing in "${SITE_DOMAINS[@]}" "${TCP_ROUTE_SNIS[@]}" "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$REALITY_SNI" == "$existing" ]] && { echo -e "${RED}❌ REALITY SNI 不能和其他 443 分流域名相同：${existing}${PLAIN}"; return 1; }
    done
    warn_if_public_bind "Xray REALITY" "$XRAY_LISTEN_ADDR" "$XRAY_LISTEN_PORT" || return 1
    probe_reality_sni "$REALITY_SNI" || return 1

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_entry_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 Nginx / Caddy 单入口监听${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}适用于：你要调整公网入口端口、Caddy 本地 TLS 端口，或修正监听地址。普通用户建议保持默认。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "当前公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}"
    echo -e "当前 Caddy 本地 TLS：${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT}"
    echo -e "------------------------------------------------"

    NGINX_LISTEN_ADDR=$(ask_with_default "Nginx 公网监听地址" "$NGINX_LISTEN_ADDR")
    NGINX_LISTEN_PORT=$(ask_with_default "Nginx 公网监听端口" "$NGINX_LISTEN_PORT")
    CADDY_LISTEN_ADDR=$(ask_with_default "Caddy 本地监听地址" "$CADDY_LISTEN_ADDR")
    CADDY_LISTEN_PORT=$(ask_with_default "Caddy 本地监听端口" "$CADDY_LISTEN_PORT")

    is_valid_listen_addr "$NGINX_LISTEN_ADDR" || { echo -e "${RED}❌ Nginx 监听地址无效：${NGINX_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_listen_addr "$CADDY_LISTEN_ADDR" || { echo -e "${RED}❌ Caddy 监听地址无效：${CADDY_LISTEN_ADDR}${PLAIN}"; return 1; }
    is_valid_port "$NGINX_LISTEN_PORT" || { echo -e "${RED}❌ Nginx 端口无效：${NGINX_LISTEN_PORT}${PLAIN}"; return 1; }
    is_valid_port "$CADDY_LISTEN_PORT" || { echo -e "${RED}❌ Caddy 端口无效：${CADDY_LISTEN_PORT}${PLAIN}"; return 1; }
    warn_if_public_bind "Caddy" "$CADDY_LISTEN_ADDR" "$CADDY_LISTEN_PORT" || return 1
    if [[ "$NGINX_LISTEN_PORT" != "443" ]]; then
        echo -e "${YELLOW}⚠️  Nginx 公网入口不是 443。请确认云安全组、防火墙和客户端地址都同步改了。${PLAIN}"
    fi

    save_and_offer_reapply_sni_stack
}

edit_sni_stack_panel_domain_profile() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改面板域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "${RED}❌ 未找到 Cloudflare Token，请先到证书维护菜单更新 Token。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "${RED}❌ Cloudflare Token 为空，请先到证书维护菜单更新。${PLAIN}"
        return 1
    fi

    local old_domain new_domain existing confirm old_conf
    old_domain="$PANEL_DOMAIN"
    echo -e "当前面板域名：${old_domain}"
    echo -e "${YELLOW}修改前请先把新域名解析到当前 VPS，并确认 Cloudflare Token 有该 zone 权限。${PLAIN}"
    new_domain=$(normalize_domain_input "$(ask_with_default "新的面板域名" "$PANEL_DOMAIN")")
    [[ "$new_domain" == "$old_domain" ]] && { echo -e "${BLUE}面板域名未变化。${PLAIN}"; return 0; }
    is_valid_domain "$new_domain" || { echo -e "${RED}❌ 面板域名无效：${new_domain}${PLAIN}"; return 1; }
    [[ "$new_domain" == "$REALITY_SNI" ]] && { echo -e "${RED}❌ 面板域名不能和 REALITY SNI 相同。${PLAIN}"; return 1; }
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "${RED}❌ 面板域名不能和网站/反代域名相同。${PLAIN}"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "${RED}❌ 面板域名不能和 TCP/SNI 入站域名相同。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$new_domain" == "$existing" ]] && { echo -e "${RED}❌ 面板域名不能和 Xray 入站域名相同。${PLAIN}"; return 1; }
    done
    check_domain_dns_sanity "$new_domain" "新的面板域名" "prompt" || return 1
    confirm_risk_action "替换 443 面板域名为 ${new_domain}" \
        "面板域名、证书和 Caddy/Nginx 相关配置" \
        "使用 443 单入口备份恢复旧域名配置" \
        "确认新域名 DNS 已解析到当前 VPS，且 Token 有该 zone 权限。" || return 1

    issue_and_install_cert_for_domain "$new_domain" "$CF_Token" || return 1
    old_conf="/etc/caddy/conf.d/${old_domain}.caddy"
    [[ -f "$old_conf" ]] && quarantine_path "$old_conf" "/etc/caddy/conf.d_quarantine" >/dev/null 2>&1 || true
    PANEL_DOMAIN="$new_domain"
    rename_sni_ip_whitelist_domain "$old_domain" "$new_domain"
    save_and_offer_reapply_sni_stack
}

edit_sni_stack_runtime_profile() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 修改 443 分流参数${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：后续修改面板端口/路径、订阅端口/路径、REALITY SNI、入口端口时使用。${PLAIN}"
        echo -e "${YELLOW}新增网站请走 [19] -> [8]，不用重跑首次配置。${PLAIN}"
        echo -e "------------------------------------------------"
        if load_sni_stack_env >/dev/null 2>&1; then
            print_sni_stack_current_summary
        else
            echo -e "${RED}未找到 443 配置，请先运行 [19] -> [2]。${PLAIN}"
            return 1
        fi
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 修改面板/订阅端口与路径${PLAIN}"
        echo -e "${GREEN}  2. 修改 REALITY 本地监听 / 伪装 SNI${PLAIN}"
        echo -e "${GREEN}  3. 修改 Nginx 公网入口 / Caddy 本地 TLS${PLAIN}"
        echo -e "${GREEN}  4. 修改面板域名${PLAIN}"
        echo -e "${GREEN}  5. 重新应用当前保存的配置${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请选择要修改的配置: "
        case "$choice" in
            1) edit_sni_stack_panel_subscription_profile ;;
            2) edit_sni_stack_reality_profile ;;
            3) edit_sni_stack_entry_profile ;;
            4) edit_sni_stack_panel_domain_profile ;;
            5) reapply_sni_stack_from_env ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择。${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

reapply_sni_stack_from_env() {
    load_sni_stack_env || return 1
    local backup_dir
    if [[ "${1:-}" != "--yes" ]]; then
        print_sni_stack_preview || return 1
    fi
    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    install_nginx_stream_stack || { rollback_sni_stack_after_failure "$backup_dir" "Nginx stream 组件检查/配置失败"; return 1; }
    harden_nginx_public_errors
    ensure_caddy_local_base_config || { rollback_sni_stack_after_failure "$backup_dir" "Caddy 基础配置初始化失败"; return 1; }
    cleanup_old_nginx_sni_stream_configs
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || { rollback_sni_stack_after_failure "$backup_dir" "Caddy 配置校验失败"; return 1; }
    write_nginx_sni_stream_config || { rollback_sni_stack_after_failure "$backup_dir" "Nginx stream 配置校验失败"; return 1; }
    systemctl restart caddy || { rollback_sni_stack_after_failure "$backup_dir" "Caddy 服务重启失败"; return 1; }
    systemctl restart nginx || { rollback_sni_stack_after_failure "$backup_dir" "Nginx 服务重启失败"; return 1; }
    write_single_443_engine_state "nginx_stream" "$backup_dir"
    print_sni_stack_result
}


collect_sni_stack_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}443 单入口共享配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}公网 443 将由你选择的入口模式监听；Web 域名、Caddy 后端、证书和白名单为三种模式共享。${PLAIN}"
    echo -e "${YELLOW}Caddy/Xray/3x-ui 本地后端默认绑定 127.0.0.1。${PLAIN}"
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
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        CADDY_LISTEN_ADDR=$(ask_with_default "Caddy 本地监听地址" "127.0.0.1")
        XRAY_LISTEN_ADDR=$(ask_with_default "Xray REALITY 本地监听地址" "127.0.0.1")
        PANEL_LISTEN_ADDR=$(ask_with_default "3x-ui 面板监听地址" "127.0.0.1")
        SUB_LISTEN_ADDR=$(ask_with_default "3x-ui 订阅服务监听地址" "127.0.0.1")
    else
        CADDY_LISTEN_ADDR="127.0.0.1"
        XRAY_LISTEN_ADDR="127.0.0.1"
        PANEL_LISTEN_ADDR="127.0.0.1"
        SUB_LISTEN_ADDR="127.0.0.1"
        echo -e "${GREEN}普通模式：Caddy/Xray/3x-ui/订阅/网站后端均使用 127.0.0.1。${PLAIN}"
    fi

    CADDY_LISTEN_PORT=$(ask_with_default "Caddy 本地监听端口" "8443")
    XRAY_LISTEN_PORT=$(ask_with_default "Xray REALITY 本地监听端口" "1443")
    PANEL_LISTEN_PORT=$(ask_with_default "3x-ui 面板端口" "40000")
    PANEL_WEB_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 面板公网路径 / webBasePath（必须和面板 url 根路径一致）" "/panel/")")
    SUB_LISTEN_PORT=$(ask_with_default "3x-ui 订阅服务端口（可自定义）" "2096")
    SUB_URI_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui 普通订阅路径前缀（不带端口和客户端 Subscription，建议写 /sub/）" "/sub/")")
    CLASH_URI_PATH=$(normalize_path_prefix "$(ask_with_default "3x-ui Clash/Mihomo 订阅路径前缀（不带客户端 Subscription，建议写 /clash/）" "/clash/")")
    local panel_whitelist_enabled panel_whitelist_input panel_whitelist_ranges current_client_ip
    local -a panel_whitelist_array=()
    read_trimmed panel_whitelist_enabled "是否为面板域名启用 IP 白名单？(y/n，默认 n): "
    if [[ "$panel_whitelist_enabled" =~ ^[Yy]$ ]]; then
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
            if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
                SITE_BACKEND_ADDRS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端监听地址" "127.0.0.1")
            else
                SITE_BACKEND_ADDRS[$i]="127.0.0.1"
            fi
            SITE_BACKEND_PORTS[$i]=$(ask_with_default "网站 ${SITE_DOMAINS[$i]} 的后端端口" "$default_site_port")
            default_site_port=$((default_site_port + 1))
        done
    fi

    echo -e "${YELLOW}请确认 3x-ui 面板设置 -> 常规 -> 证书、订阅设置 -> 证书 路径已经清空。${PLAIN}"
    echo -e "${YELLOW}本向导会让 Caddy 通过 HTTP 连接 ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT} 和 ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}。${PLAIN}"
    local cert_clear_confirm
    read_trimmed cert_clear_confirm "确认已经清空面板证书和订阅证书路径？(y/n): "
    is_yes "$cert_clear_confirm" || { echo -e "${YELLOW}请先回 3x-ui 清空证书路径并保存重启，再运行本向导。${PLAIN}"; return 1; }

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
    local conf_file="/etc/nginx/stream.d/vps_sni_${NGINX_LISTEN_PORT}.conf"
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
    nginx -t
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
    local panel_backend
    local sub_backend
    local sub_match_paths
    panel_backend=$(format_hostport "$PANEL_LISTEN_ADDR" "$PANEL_LISTEN_PORT")
    sub_backend=$(format_hostport "$SUB_LISTEN_ADDR" "$SUB_LISTEN_PORT")
    SUB_URI_PATH=$(normalize_path_prefix "${SUB_URI_PATH:-/sub/}")
    CLASH_URI_PATH=$(normalize_path_prefix "${CLASH_URI_PATH:-/clash/}")
    sub_match_paths=$(caddy_path_match_tokens "$SUB_URI_PATH" "$CLASH_URI_PATH")
    cat <<EOF > "/etc/caddy/conf.d/${PANEL_DOMAIN}.caddy"
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
    local i site_domain site_backend
    for i in "${!SITE_DOMAINS[@]}"; do
        site_domain="${SITE_DOMAINS[$i]}"
        [[ -z "$site_domain" ]] && continue
        site_backend=$(format_hostport "${SITE_BACKEND_ADDRS[$i]}" "${SITE_BACKEND_PORTS[$i]}")
        cat <<EOF > "/etc/caddy/conf.d/${site_domain}.caddy"
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
        --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1 || return 1
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
    [[ "$yn" =~ ^[Yy]$ ]] || return 0
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
    echo -e "  面板证书路径/私钥路径：清空"
    echo -e "  Caddy 后端连接：http://${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    echo -e "  Panel URL / Public URL / External URL：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "  Subscription URI Path：${SUB_URI_PATH}"
    echo -e "  Subscription External URL：https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "  Clash/Mihomo URI Path：${CLASH_URI_PATH}"
    echo -e "  Clash/Mihomo External URL：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "${YELLOW}  不建议使用 webBasePath=/，随机面板路径能降低被批量扫描命中的概率。${PLAIN}"
    echo -e "  订阅证书路径/私钥路径：清空"
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
    echo -e "  ERR_TOO_MANY_REDIRECTS：通常是 3x-ui 面板或订阅证书路径没清空，或外部地址/路径配置不一致"
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
    echo -e "${RED}绝对不要做：Caddy 监听公网 443；Xray 监听公网 443；3x-ui 面板或新增 TCP/SNI 入站暴露公网；3x-ui 证书路径未清空就跑 443；把 REALITY dest/serverNames 写成面板域名。${PLAIN}"
}

apply_sni_stack_runtime_config() {
    local backup_dir
    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    install_nginx_stream_stack || { rollback_sni_stack_after_failure "$backup_dir" "Nginx stream 组件检查/配置失败"; return 1; }
    harden_nginx_public_errors
    ensure_caddy_local_base_config || { rollback_sni_stack_after_failure "$backup_dir" "Caddy 基础配置初始化失败"; return 1; }
    cleanup_old_nginx_sni_stream_configs
    write_caddy_panel_config
    write_caddy_site_config
    caddy_format_configs
    caddy validate --config /etc/caddy/Caddyfile || { rollback_sni_stack_after_failure "$backup_dir" "Caddy 配置校验失败"; return 1; }
    write_nginx_sni_stream_config || { rollback_sni_stack_after_failure "$backup_dir" "Nginx stream 配置校验失败"; return 1; }
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy || { rollback_sni_stack_after_failure "$backup_dir" "Caddy 服务重启失败"; return 1; }
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx || { rollback_sni_stack_after_failure "$backup_dir" "Nginx 服务重启失败"; return 1; }
    save_sni_stack_env
    write_single_443_engine_state "nginx_stream" "$backup_dir"
    generate_caddy_cf_manifest
}

list_sni_stack_sites() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}当前 443 单入口网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "面板域名：${PANEL_DOMAIN} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
    local panel_ranges
    panel_ranges=$(sni_ip_whitelist_ranges_for_domain "$PANEL_DOMAIN")
    [[ -n "$panel_ranges" ]] && echo -e "${YELLOW}面板域名 IP 白名单：${panel_ranges}${PLAIN}"
    echo -e "REALITY SNI：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    [[ ${#TCP_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "${CYAN}另有 ${#TCP_ROUTE_SNIS[@]} 个旧 TCP/SNI 入站。${PLAIN}"
        [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -gt 0 ]] && echo -e "${CYAN}另有 ${#XRAY_SNI_ROUTE_SNIS[@]} 个 Xray 入站，请在 [19] -> [10] 查看。${PLAIN}"
    echo -e "------------------------------------------------"
    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有额外的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} https://${SITE_DOMAINS[$i]}/ -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
        local site_ranges
        site_ranges=$(sni_ip_whitelist_ranges_for_domain "${SITE_DOMAINS[$i]}")
        [[ -n "$site_ranges" ]] && echo -e "   ${YELLOW}IP 白名单：${site_ranges}${PLAIN}"
    done
}

add_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}添加 443 网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    if [[ ! -f "$cf_env_file" ]]; then
        echo -e "${RED}❌ 未找到 Cloudflare Token，请先进入维护菜单 [2] 写入 Token。${PLAIN}"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$cf_env_file"
    if [[ -z "${CF_Token:-}" ]]; then
        echo -e "${RED}❌ Cloudflare Token 为空，请先进入维护菜单 [2] 更新。${PLAIN}"
        return 1
    fi

    echo -e "这个入口适合后续新增网站，例如 SublinkPro、Dockge、博客、订阅管理工具等。"
    echo -e "${YELLOW}新增域名会走：公网 ${NGINX_LISTEN_PORT} -> Nginx SNI -> Caddy -> 本地后端。${PLAIN}"
    echo -e ""

    local site_domain site_addr site_port advanced_mode existing idx confirm
    local enable_ip_whitelist whitelist_input whitelist_ranges current_client_ip
    local -a whitelist_array=()
    read_trimmed site_domain "请输入新网站/反代域名（例如 sub.example.com）: "
    site_domain=$(normalize_domain_input "$site_domain")
    if [[ -z "$site_domain" || "$site_domain" == "0" ]]; then
        echo -e "${BLUE}已取消新增网站/反代域名。${PLAIN}"
        return 0
    fi

    if ! is_valid_domain "$site_domain"; then
        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
        return 1
    fi
    if [[ "$site_domain" == "$PANEL_DOMAIN" || "$site_domain" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ 新域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经在 443 分流列表中。${PLAIN}"
            return 1
        fi
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经作为 TCP/SNI 入站使用。${PLAIN}"
            return 1
        fi
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        if [[ "$site_domain" == "$existing" ]]; then
            echo -e "${RED}❌ 该域名已经作为 Xray 入站使用。${PLAIN}"
            return 1
        fi
    done

    read_trimmed advanced_mode "是否进入高级模式并允许修改后端监听地址？(y/n，默认 n): "
    if [[ "$advanced_mode" =~ ^[Yy]$ ]]; then
        site_addr=$(ask_with_default "后端监听地址" "127.0.0.1")
    else
        site_addr="127.0.0.1"
        echo -e "${GREEN}普通模式：后端地址使用 127.0.0.1。${PLAIN}"
    fi
    site_port=$(ask_with_default "后端端口" "$((3000 + ${#SITE_DOMAINS[@]}))")

    is_valid_listen_addr "$site_addr" || { echo -e "${RED}❌ 后端监听地址无效：${site_addr}${PLAIN}"; return 1; }
    is_valid_port "$site_port" || { echo -e "${RED}❌ 后端端口无效：${site_port}${PLAIN}"; return 1; }
    warn_if_public_bind "网站/反代后端 ${site_domain}" "$site_addr" "$site_port" || return 1

    read_trimmed enable_ip_whitelist "是否为 ${site_domain} 启用 IP 白名单？(y/n，默认 n): "
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed whitelist_input "请输入允许访问 ${site_domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        normalize_ip_whitelist_input "$whitelist_input" whitelist_array || return 1
        append_vps_public_ips_to_whitelist whitelist_array
        whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
    fi

    echo -e ""
    echo -e "${CYAN}即将添加：${site_domain} -> ${site_addr}:${site_port}${PLAIN}"
    [[ -n "${whitelist_ranges:-}" ]] && echo -e "${YELLOW}IP 白名单：${whitelist_ranges}${PLAIN}"
    confirm_risk_action "新增 443 网站/反代域名 ${site_domain}" \
        "证书、Caddy 站点配置和 Nginx SNI 分流配置" \
        "使用 443 单入口备份恢复，或从网站管理菜单删除该域名" \
        "确认域名已解析到当前 VPS，后端端口可从本机访问。" || return 1

    idx=${#SITE_DOMAINS[@]}
    SITE_DOMAINS[$idx]="$site_domain"
    SITE_BACKEND_ADDRS[$idx]="$site_addr"
    SITE_BACKEND_PORTS[$idx]="$site_port"
    [[ -n "${whitelist_ranges:-}" ]] && set_sni_ip_whitelist_for_domain "$site_domain" "$whitelist_ranges"

    issue_and_install_cert_for_domain "$site_domain" "$CF_Token" || return 1
    apply_sni_stack_runtime_config || return 1
    echo -e "${GREEN}✅ 已添加网站入口：https://${site_domain}/${PLAIN}"
    echo -e "${YELLOW}提醒：后端服务需要监听 ${site_addr}:${site_port}，浏览器只访问 https://${site_domain}/。${PLAIN}"
    echo -e "${CYAN}当前 Caddy 后端：reverse_proxy ${site_addr}:${site_port}${PLAIN}"
}

edit_sni_stack_site_backend() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 443 网站/反代后端${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可修改的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num choice idx domain new_addr new_port confirm
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要修改的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消修改。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    new_addr=$(ask_with_default "后端监听地址" "${SITE_BACKEND_ADDRS[$idx]}")
    new_port=$(ask_with_default "后端端口" "${SITE_BACKEND_PORTS[$idx]}")

    is_valid_listen_addr "$new_addr" || { echo -e "${RED}❌ 后端监听地址无效：${new_addr}${PLAIN}"; return 1; }
    is_valid_port "$new_port" || { echo -e "${RED}❌ 后端端口无效：${new_port}${PLAIN}"; return 1; }
    warn_if_public_bind "网站/反代后端 ${domain}" "$new_addr" "$new_port" || return 1

    echo -e ""
    echo -e "${CYAN}即将修改：${domain} -> ${new_addr}:${new_port}${PLAIN}"
    confirm_risk_action "修改 443 网站/反代后端" \
        "Caddy 反代后端和 Nginx SNI 分流配置" \
        "使用 443 单入口备份恢复修改前配置" \
        "确认新后端地址和端口已经在本机监听。" || return 1

    SITE_BACKEND_ADDRS[$idx]="$new_addr"
    SITE_BACKEND_PORTS[$idx]="$new_port"
    apply_sni_stack_runtime_config || return 1
    echo -e "${GREEN}✅ 已更新网站后端：https://${domain}/ -> ${new_addr}:${new_port}${PLAIN}"
    echo -e "${CYAN}当前 Caddy 后端：reverse_proxy ${new_addr}:${new_port}${PLAIN}"
}

remove_sni_stack_site() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 443 网站/反代域名${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1

    if [[ ${#SITE_DOMAINS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的网站/反代域名。${PLAIN}"
        return 0
    fi

    local i num choice idx domain confirm delete_cert new_domains new_addrs new_ports
    for i in "${!SITE_DOMAINS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${SITE_DOMAINS[$i]} -> ${SITE_BACKEND_ADDRS[$i]}:${SITE_BACKEND_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要删除的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消删除。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#SITE_DOMAINS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    domain="${SITE_DOMAINS[$idx]}"
    confirm_risk_action "从 443 分流中移除 ${domain}" \
        "该域名的 Caddy 站点和 Nginx SNI 分流规则" \
        "使用 443 单入口备份恢复，或重新新增该网站/反代域名" \
        "确认该域名不再承载线上面板、订阅或网站。" || return 1

    new_domains=()
    new_addrs=()
    new_ports=()
    for i in "${!SITE_DOMAINS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_domains+=("${SITE_DOMAINS[$i]}")
        new_addrs+=("${SITE_BACKEND_ADDRS[$i]}")
        new_ports+=("${SITE_BACKEND_PORTS[$i]}")
    done
    SITE_DOMAINS=("${new_domains[@]}")
    SITE_BACKEND_ADDRS=("${new_addrs[@]}")
    SITE_BACKEND_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$domain"
    quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "/etc/vps-optimize/quarantine/caddy-sni" >/dev/null 2>&1 || true

    apply_sni_stack_runtime_config || return 1

    read_trimmed delete_cert "是否同时隔离 ${domain} 的 Caddy 证书文件？(y/n，默认 n): "
    if [[ "$delete_cert" =~ ^[Yy]$ ]]; then
        quarantine_path "/etc/caddy/certs/${domain}.crt" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/etc/caddy/certs/${domain}.key" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/root/cert/${domain}.crt" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        quarantine_path "/root/cert/${domain}.key" "/etc/vps-optimize/quarantine/caddy-certs" >/dev/null 2>&1 || true
        generate_caddy_cf_manifest
        echo -e "${GREEN}✅ 已移除 ${domain} 的配置，并隔离本地证书文件。${PLAIN}"
    else
        echo -e "${GREEN}✅ 已删除 ${domain} 的分流配置，证书文件已保留。${PLAIN}"
    fi
}

list_sni_stack_tcp_routes() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}当前 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "公网入口：${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT}"
    echo -e "REALITY 默认后端：${REALITY_SNI} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "------------------------------------------------"
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有额外 TCP/SNI 入站分流。${PLAIN}"
        return 0
    fi

    local i num route_ranges
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
        route_ranges=$(sni_ip_whitelist_ranges_for_domain "${TCP_ROUTE_SNIS[$i]}")
        [[ -n "$route_ranges" ]] && echo -e "   ${YELLOW}IP 白名单：${route_ranges}${PLAIN}"
    done
}

add_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}新增 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}用途：你已在 3x-ui 新增本地入站，本功能只把某个 SNI 通过公网 ${NGINX_LISTEN_PORT} 分流到该本地端口。${PLAIN}"
    echo -e "${YELLOW}要求：协议必须是 TCP 且客户端握手能带 SNI；UDP/QUIC/Hysteria2/TUIC 或无 SNI 的裸协议不适用。${PLAIN}"
    echo -e "${YELLOW}安全边界：后端只允许 127.0.0.1/localhost/::1，不会开放新公网端口。${PLAIN}"
    echo -e "------------------------------------------------"

    local route_sni route_addr route_port existing idx enable_ip_whitelist whitelist_input whitelist_ranges current_client_ip
    local -a whitelist_array=()
    read_trimmed route_sni "请输入用于分流的新 SNI/域名（例如 relay.example.com）: "
    route_sni=$(normalize_domain_input "$route_sni")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "${BLUE}已取消新增 TCP/SNI 入站。${PLAIN}"
        return 0
    fi
    is_valid_domain "$route_sni" || { echo -e "${RED}❌ SNI/域名格式无效。${PLAIN}"; return 1; }
    if [[ "$route_sni" == "$PANEL_DOMAIN" || "$route_sni" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ TCP/SNI 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为网站/反代域名使用。${PLAIN}"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该 TCP/SNI 入站已经存在。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为 Xray 入站使用。${PLAIN}"; return 1; }
    done

    check_domain_dns_sanity "$route_sni" "TCP/SNI 入站域名" "warn" || echo -e "${YELLOW}⚠️ 如果客户端使用服务器 IP 连接并手动指定 SNI，可忽略该 DNS 警告。${PLAIN}"
    route_addr=$(ask_with_default "3x-ui 新入站本地监听地址（只允许本地）" "127.0.0.1")
    route_addr=$(normalize_loopback_addr "$route_addr")
    route_port=$(ask_with_default "3x-ui 新入站本地监听端口" "8443")
    is_loopback_listen_addr "$route_addr" || { echo -e "${RED}❌ 为保证安全，TCP/SNI 入站后端只允许 127.0.0.1、localhost 或 ::1。${PLAIN}"; return 1; }
    is_valid_port "$route_port" || { echo -e "${RED}❌ 入站端口无效：${route_port}${PLAIN}"; return 1; }
    if [[ "$route_port" == "$NGINX_LISTEN_PORT" || "$route_port" == "$CADDY_LISTEN_PORT" || "$route_port" == "$PANEL_LISTEN_PORT" || "$route_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 入站端口不能复用公网入口、Caddy、面板或订阅服务端口。${PLAIN}"
        return 1
    fi

    read_trimmed enable_ip_whitelist "是否为 ${route_sni} 启用 IP 白名单？(y/n，默认 n): "
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed whitelist_input "请输入允许访问 ${route_sni} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        normalize_ip_whitelist_input "$whitelist_input" whitelist_array || return 1
        append_vps_public_ips_to_whitelist whitelist_array
        whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
    fi

    echo -e ""
    echo -e "${CYAN}即将添加 TCP/SNI 分流：${route_sni}:${NGINX_LISTEN_PORT} -> ${route_addr}:${route_port}${PLAIN}"
    echo -e "${YELLOW}请确认 3x-ui 入站已监听 ${route_addr}:${route_port}，且客户端连接端口使用 ${NGINX_LISTEN_PORT}。${PLAIN}"
    [[ -n "${whitelist_ranges:-}" ]] && echo -e "${YELLOW}IP 白名单：${whitelist_ranges}${PLAIN}"
    confirm_risk_action "新增 443 TCP/SNI 入站 ${route_sni}" \
        "Nginx stream SNI 分流规则，会把该 SNI 直通到本地 3x-ui 入站" \
        "使用 443 单入口备份恢复，或从 TCP/SNI 入站管理菜单删除该分流" \
        "确认后端只监听本地地址，不要在安全组或防火墙开放 ${route_port}。" || return 1

    idx=${#TCP_ROUTE_SNIS[@]}
    TCP_ROUTE_SNIS[$idx]="$route_sni"
    TCP_ROUTE_ADDRS[$idx]="$route_addr"
    TCP_ROUTE_PORTS[$idx]="$route_port"
    [[ -n "${whitelist_ranges:-}" ]] && set_sni_ip_whitelist_for_domain "$route_sni" "$whitelist_ranges"
    save_and_offer_reapply_sni_stack
}

edit_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}修改 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可修改的 TCP/SNI 入站分流。${PLAIN}"
        return 0
    fi

    local i num choice idx old_sni new_sni new_addr new_port existing
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要修改的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消修改。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#TCP_ROUTE_SNIS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    old_sni="${TCP_ROUTE_SNIS[$idx]}"
    new_sni=$(normalize_domain_input "$(ask_with_default "SNI/域名" "$old_sni")")
    new_addr=$(ask_with_default "本地监听地址（只允许本地）" "${TCP_ROUTE_ADDRS[$idx]}")
    new_addr=$(normalize_loopback_addr "$new_addr")
    new_port=$(ask_with_default "本地监听端口" "${TCP_ROUTE_PORTS[$idx]}")

    is_valid_domain "$new_sni" || { echo -e "${RED}❌ SNI/域名格式无效。${PLAIN}"; return 1; }
    if [[ "$new_sni" == "$PANEL_DOMAIN" || "$new_sni" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ TCP/SNI 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$new_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为网站/反代域名使用。${PLAIN}"; return 1; }
    done
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        [[ "$new_sni" == "${TCP_ROUTE_SNIS[$i]}" ]] && { echo -e "${RED}❌ 该 TCP/SNI 入站已经存在。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$new_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为 Xray 入站使用。${PLAIN}"; return 1; }
    done
    is_loopback_listen_addr "$new_addr" || { echo -e "${RED}❌ 为保证安全，TCP/SNI 入站后端只允许 127.0.0.1、localhost 或 ::1。${PLAIN}"; return 1; }
    is_valid_port "$new_port" || { echo -e "${RED}❌ 入站端口无效：${new_port}${PLAIN}"; return 1; }
    if [[ "$new_port" == "$NGINX_LISTEN_PORT" || "$new_port" == "$CADDY_LISTEN_PORT" || "$new_port" == "$PANEL_LISTEN_PORT" || "$new_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 入站端口不能复用公网入口、Caddy、面板或订阅服务端口。${PLAIN}"
        return 1
    fi

    echo -e ""
    echo -e "${CYAN}即将修改：${old_sni}:${NGINX_LISTEN_PORT} -> ${new_sni}:${NGINX_LISTEN_PORT} -> ${new_addr}:${new_port}${PLAIN}"
    confirm_risk_action "修改 443 TCP/SNI 入站 ${old_sni}" \
        "Nginx stream SNI 分流规则和本地后端端口" \
        "使用 443 单入口备份恢复修改前配置" \
        "确认 3x-ui 入站已按新地址和端口监听，且未开放该内部端口。" || return 1

    TCP_ROUTE_SNIS[$idx]="$new_sni"
    TCP_ROUTE_ADDRS[$idx]="$new_addr"
    TCP_ROUTE_PORTS[$idx]="$new_port"
    if [[ "$old_sni" != "$new_sni" ]]; then
        rename_sni_ip_whitelist_domain "$old_sni" "$new_sni"
    fi
    save_and_offer_reapply_sni_stack
}

remove_sni_stack_tcp_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 443 TCP/SNI 本地入站分流${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#TCP_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的 TCP/SNI 入站分流。${PLAIN}"
        return 0
    fi

    local i num choice idx route_sni
    local -a new_snis=()
    local -a new_addrs=()
    local -a new_ports=()
    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${TCP_ROUTE_SNIS[$i]}:${NGINX_LISTEN_PORT} -> ${TCP_ROUTE_ADDRS[$i]}:${TCP_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要删除的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消删除。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#TCP_ROUTE_SNIS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    route_sni="${TCP_ROUTE_SNIS[$idx]}"
    confirm_risk_action "从 443 分流中移除 TCP/SNI 入站 ${route_sni}" \
        "该 SNI 的 Nginx stream 直通规则" \
        "使用 443 单入口备份恢复，或重新新增该 TCP/SNI 入站" \
        "确认没有客户端仍依赖该 SNI 连接。" || return 1

    for i in "${!TCP_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_snis+=("${TCP_ROUTE_SNIS[$i]}")
        new_addrs+=("${TCP_ROUTE_ADDRS[$i]}")
        new_ports+=("${TCP_ROUTE_PORTS[$i]}")
    done
    TCP_ROUTE_SNIS=("${new_snis[@]}")
    TCP_ROUTE_ADDRS=("${new_addrs[@]}")
    TCP_ROUTE_PORTS=("${new_ports[@]}")
    remove_sni_ip_whitelist_for_domain "$route_sni"
    save_and_offer_reapply_sni_stack
}

xray_sni_routes_fallback_notice() {
    echo -e "${YELLOW}当前为 Xray Fallback 模式。${PLAIN}"
    print_xray_fallback_mode_explanation
}

list_xray_sni_routes() {
    load_sni_stack_env || return 1
    local mode fallback_idx
    mode=$(get_entry_mode)
    fallback_idx=$(xray_fallback_main_route_index 2>/dev/null || true)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Xray 入站分流规则${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "配置文件：$(xray_sni_routes_path)"
    echo -e "规则格式：SNI|ADDR|PORT"
    if [[ "$mode" == "xray-fallback" ]]; then
        echo -e "------------------------------------------------"
        xray_sni_routes_fallback_notice
        print_xray_fallback_main_route_summary
    fi
    echo -e "------------------------------------------------"
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有 Xray 入站分流规则。${PLAIN}"
        if [[ -n "${XRAY_LISTEN_PORT:-}" ]]; then
            echo -e "${CYAN}旧默认 Xray/REALITY 后端仍是：${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}${PLAIN}"
            echo -e "${CYAN}如需多个本地 Xray 入站，可按 SNI 添加新的本地端口分流记录。${PLAIN}"
        fi
        return 0
    fi

    local i num
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        if [[ "$mode" == "xray-fallback" && -n "$fallback_idx" && "$i" == "$fallback_idx" ]]; then
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} ${GREEN}[xray-fallback 主入站，当前模式生效]${PLAIN}"
        elif [[ "$mode" == "xray-fallback" ]]; then
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]} ${YELLOW}[已保留，当前 xray-fallback 模式下不生效]${PLAIN}"
        else
            echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]}"
        fi
    done
}

add_xray_sni_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}添加 Xray 入站分流规则${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    echo -e "${YELLOW}本菜单只记录 SNI -> 本地地址:端口，不会创建、删除或修改 3x-ui/Xray 入站。${PLAIN}"
    echo -e "------------------------------------------------"

    local route_sni route_addr route_port existing idx
    read_trimmed route_sni "SNI/域名: "
    route_sni=$(normalize_domain_input "$route_sni")
    if [[ -z "$route_sni" || "$route_sni" == "0" ]]; then
        echo -e "${BLUE}已取消添加。${PLAIN}"
        return 0
    fi
    is_valid_domain "$route_sni" || { echo -e "${RED}❌ SNI/域名格式无效。${PLAIN}"; return 1; }
    if [[ "$route_sni" == "$PANEL_DOMAIN" || "$route_sni" == "$REALITY_SNI" ]]; then
        echo -e "${RED}❌ Xray 入站域名不能和面板域名或 REALITY SNI 相同。${PLAIN}"
        return 1
    fi
    for existing in "${SITE_DOMAINS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已作为 Web/Caddy 域名使用，Xray 入站规则必须和 Web 域名分开。${PLAIN}"; return 1; }
    done
    for existing in "${TCP_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该域名已存在于旧 TCP/SNI 本地入站规则中。${PLAIN}"; return 1; }
    done
    for existing in "${XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$route_sni" == "$existing" ]] && { echo -e "${RED}❌ 该 Xray 入站分流规则已经存在。${PLAIN}"; return 1; }
    done

    route_addr=$(ask_with_default "本地监听地址" "127.0.0.1")
    route_addr=$(normalize_loopback_addr "$route_addr")
    route_port=$(ask_with_default "本地监听端口" "${XRAY_LISTEN_PORT:-1443}")
    is_loopback_listen_addr "$route_addr" || { echo -e "${RED}❌ 为避免公网暴露，本地监听地址只允许 127.0.0.1、localhost 或 ::1。${PLAIN}"; return 1; }
    is_valid_port "$route_port" || { echo -e "${RED}❌ 本地监听端口无效：${route_port}${PLAIN}"; return 1; }
    if [[ "$route_port" == "$CADDY_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 该端口与 Caddy 本地端口 ${CADDY_LISTEN_PORT} 冲突。${PLAIN}"
        return 1
    fi
    if [[ "$route_port" == "$NGINX_LISTEN_PORT" || "$route_port" == "$PANEL_LISTEN_PORT" || "$route_port" == "$SUB_LISTEN_PORT" ]]; then
        echo -e "${RED}❌ 入站端口不能复用公网入口、面板或订阅服务端口。${PLAIN}"
        return 1
    fi
    existing=$(xray_sni_route_port_conflict "$route_addr" "$route_port" || true)
    if [[ -n "$existing" ]]; then
        echo -e "${RED}❌ ${route_addr}:${route_port} 已被规则 ${existing} 使用。${PLAIN}"
        return 1
    fi

    print_xray_route_port_status "$route_sni" "$route_addr" "$route_port"
    if [[ -z "$(xray_route_listen_line_by_addr_port "$route_addr" "$route_port")" ]]; then
        echo -e "${RED}❌ 端口未监听，请先去 3x-ui 创建并启用对应入站。${PLAIN}"
        return 1
    fi

    idx=${#XRAY_SNI_ROUTE_SNIS[@]}
    XRAY_SNI_ROUTE_SNIS[$idx]="$route_sni"
    XRAY_SNI_ROUTE_ADDRS[$idx]="$route_addr"
    XRAY_SNI_ROUTE_PORTS[$idx]="$route_port"
    save_xray_sni_route_arrays
    echo -e "${GREEN}✅ 已保存 Xray 入站分流规则：${route_sni} -> ${route_addr}:${route_port}${PLAIN}"
    echo -e "${YELLOW}提示：保存后需要执行“同步到当前入口模式”或重新应用当前入口模式，公网 443 才会使用新规则。${PLAIN}"
}

remove_xray_sni_route() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}删除 Xray 入站分流规则${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    load_sni_stack_env || return 1
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有可删除的 Xray 入站分流规则。${PLAIN}"
        return 0
    fi

    local i num choice idx route_sni
    local -a new_snis=() new_addrs=() new_ports=()
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        num=$((i + 1))
        echo -e "${GREEN}${num}.${PLAIN} ${XRAY_SNI_ROUTE_SNIS[$i]} -> ${XRAY_SNI_ROUTE_ADDRS[$i]}:${XRAY_SNI_ROUTE_PORTS[$i]}"
    done
    echo -e "------------------------------------------------"
    read_trimmed choice "请输入要删除的序号: "
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo -e "${BLUE}已取消删除。${PLAIN}"
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#XRAY_SNI_ROUTE_SNIS[@]} )); then
        echo -e "${RED}❌ 序号无效。${PLAIN}"
        return 1
    fi

    idx=$((choice - 1))
    route_sni="${XRAY_SNI_ROUTE_SNIS[$idx]}"
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        [[ "$i" -eq "$idx" ]] && continue
        new_snis+=("${XRAY_SNI_ROUTE_SNIS[$i]}")
        new_addrs+=("${XRAY_SNI_ROUTE_ADDRS[$i]}")
        new_ports+=("${XRAY_SNI_ROUTE_PORTS[$i]}")
    done
    XRAY_SNI_ROUTE_SNIS=("${new_snis[@]}")
    XRAY_SNI_ROUTE_ADDRS=("${new_addrs[@]}")
    XRAY_SNI_ROUTE_PORTS=("${new_ports[@]}")
    save_xray_sni_route_arrays
    echo -e "${GREEN}✅ 已删除 Xray 入站分流规则：${route_sni}${PLAIN}"
    echo -e "${YELLOW}提示：删除后需要执行“同步到当前入口模式”或重新应用当前入口模式。${PLAIN}"
}

check_xray_sni_route_ports() {
    load_sni_stack_env || return 1
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}检查 Xray 入站端口状态${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#XRAY_SNI_ROUTE_SNIS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}当前没有 Xray 入站分流规则。${PLAIN}"
        return 0
    fi

    local i
    for i in "${!XRAY_SNI_ROUTE_SNIS[@]}"; do
        print_xray_route_port_status "${XRAY_SNI_ROUTE_SNIS[$i]}" "${XRAY_SNI_ROUTE_ADDRS[$i]}" "${XRAY_SNI_ROUTE_PORTS[$i]}"
        echo -e "------------------------------------------------"
    done
}

sync_xray_sni_routes_to_entry_mode() {
    load_sni_stack_env || return 1
    local mode
    mode=$(get_entry_mode)
    case "$mode" in
        "nginx-stream")
            echo -e "${CYAN}正在同步 Xray 入站分流规则到 Nginx Stream 配置...${PLAIN}"
            reapply_sni_stack_from_env --yes
            ;;
        "tcp-peek")
            local tmp_config target_config
            echo -e "${CYAN}正在同步 Xray 入站分流规则到 TCP Peek + Splice 配置...${PLAIN}"
            target_config=$(vpso_mux_config_path)
            tmp_config="${target_config}.tmp.$$"
            write_vpso_mux_config_from_sni_stack "$NGINX_LISTEN_PORT" "$tmp_config" || return 1
            if ! run_vpso_mux_config_check "$tmp_config"; then
                quarantine_path "$tmp_config" "/etc/vps-optimize/quarantine/vpso-mux" >/dev/null 2>&1 || true
                return 1
            fi
            mv "$tmp_config" "$target_config" || { echo -e "${RED}❌ TCP Peek + Splice 配置替换失败：${target_config}${PLAIN}"; return 1; }
            if systemctl is-active --quiet vpso-mux 2>/dev/null; then
                systemctl restart vpso-mux || { echo -e "${RED}❌ vpso-mux 重启失败，请查看日志。${PLAIN}"; return 1; }
            else
                echo -e "${YELLOW}vpso-mux 分流器当前未运行，已仅生成并校验配置文件。${PLAIN}"
            fi
            echo -e "${GREEN}✅ 已同步到 TCP Peek + Splice 配置：${target_config}${PLAIN}"
            ;;
        "xray-fallback")
            xray_sni_routes_fallback_notice
            return 1
            ;;
        *)
            echo -e "${RED}❌ 当前 ENTRY_MODE 无效或未配置：${mode}${PLAIN}"
            return 1
            ;;
    esac
}

manage_xray_inbound_routes() {
    load_sni_stack_env || return 1
    if [[ "$(get_entry_mode)" == "xray-fallback" ]]; then
        while true; do
            clear
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e "${BOLD}Xray 入站管理${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            xray_sni_routes_fallback_notice
            print_xray_fallback_main_route_summary
            echo -e "------------------------------------------------"
            echo -e "${GREEN}  1. 查看入站分流规则${PLAIN}"
            echo -e "${YELLOW}  2. 添加入站分流规则（当前模式不可用）${PLAIN}"
            echo -e "${YELLOW}  3. 删除入站分流规则（当前模式不可用）${PLAIN}"
            echo -e "${YELLOW}  4. 同步规则到当前入口模式（当前模式不可用）${PLAIN}"
            echo -e "------------------------------------------------"
            echo -e "${RED}  0. 返回${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"

            local fallback_choice
            read_trimmed fallback_choice "请选择操作: "
            case "$fallback_choice" in
                1) list_xray_sni_routes ;;
                2|3|4)
                    echo -e "${YELLOW}当前为 xray-fallback 模式，Xray 入站管理默认不可新增、删除或同步规则。${PLAIN}"
                    echo -e "${YELLOW}如需多个本地 Xray 入站通过 443 按 SNI 分流，请切换到 nginx-stream 或 tcp-peek。${PLAIN}"
                    ;;
                0) break ;;
                *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
            esac
            echo ""
            read -n 1 -s -r -p "按任意键继续..."
        done
        return 0
    fi

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}Xray 入站管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}只管理 SNI -> 本地地址:端口 分流记录，不编辑 3x-ui/Xray 入站内部配置。${PLAIN}"
        echo -e "配置文件：$(xray_sni_routes_path)"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看入站分流规则${PLAIN}"
        echo -e "${GREEN}  2. 添加入站分流规则${PLAIN}"
        echo -e "${GREEN}  3. 删除入站分流规则${PLAIN}"
        echo -e "${GREEN}  4. 检查入站端口状态${PLAIN}"
        echo -e "${GREEN}  5. 同步到当前入口模式${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "请选择操作: "
        case "$choice" in
            1) list_xray_sni_routes ;;
            2) add_xray_sni_route ;;
            3) remove_xray_sni_route ;;
            4) check_xray_sni_route_ports ;;
            5) sync_xray_sni_routes_to_entry_mode ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择。${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

manage_sni_stack_tcp_routes() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🔀 443 TCP/SNI 本地入站管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：把你已在 3x-ui 配好的本地 TCP 入站，通过不同 SNI 统一接入公网 ${NGINX_LISTEN_PORT}。${PLAIN}"
        echo -e "${YELLOW}本功能不开放新端口，不改 3x-ui 协议；只写 Nginx stream SNI -> 本地端口规则。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  2. 新增 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  3. 修改 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  4. 删除 TCP/SNI 入站${PLAIN}"
        echo -e "${GREEN}  5. 管理域名 IP 白名单${PLAIN}       ${YELLOW}(可限制某个 TCP/SNI 入站来源 IP)${PLAIN}"
        echo -e "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}"
        echo -e "${GREEN}  7. 443 单入口链路体检${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) list_sni_stack_tcp_routes ;;
            2) add_sni_stack_tcp_route ;;
            3) edit_sni_stack_tcp_route ;;
            4) remove_sni_stack_tcp_route ;;
            5) manage_sni_stack_ip_whitelist ;;
            6) reapply_sni_stack_from_env ;;
            7) sni_stack_health_check ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

manage_sni_stack_ip_whitelist() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🔐 443 域名 IP 白名单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        load_sni_stack_env || return 1
        echo -e "${YELLOW}只限制你选择的 Web 域名；支持面板、订阅、网站/反代，Xray 入站、REALITY SNI 与未知 SNI 不受 Web 白名单影响。${PLAIN}"
        echo -e "${YELLOW}443 单入口会在 Nginx stream 层按 SNI + 源 IP 拦截，避免影响同入口其他服务。${PLAIN}"
        echo -e "------------------------------------------------"

        local -a domains=("$PANEL_DOMAIN")
        local -a labels=("面板/订阅")
        local site_domain i num domain current_ranges
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -z "$site_domain" ]] && continue
            domains+=("$site_domain")
            labels+=("网站/反代")
        done
        for i in "${!domains[@]}"; do
            num=$((i + 1))
            current_ranges=$(sni_ip_whitelist_ranges_for_domain "${domains[$i]}")
            if [[ -n "$current_ranges" ]]; then
                echo -e "${GREEN}${num}.${PLAIN} [${labels[$i]}] ${domains[$i]}  ${YELLOW}仅允许：${current_ranges}${PLAIN}"
            else
                echo -e "${GREEN}${num}.${PLAIN} [${labels[$i]}] ${domains[$i]}  ${BLUE}未启用${PLAIN}"
            fi
        done
        echo -e "------------------------------------------------"
        echo -e "${RED}0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice idx action whitelist_input whitelist_ranges current_client_ip
        local -a whitelist_array=()
        read_trimmed choice "请输入要管理的域名序号: "
        [[ "$choice" == "0" || -z "$choice" ]] && break
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#domains[@]} )); then
            echo -e "${RED}❌ 序号无效。${PLAIN}"
            pause_return
            continue
        fi

        idx=$((choice - 1))
        domain="${domains[$idx]}"
        current_ranges=$(sni_ip_whitelist_ranges_for_domain "$domain")
        echo -e "当前域名：${domain}"
        echo -e "当前白名单：${current_ranges:-未启用}"
        echo -e "1. 设置/覆盖白名单"
        echo -e "2. 清除白名单"
        echo -e "0. 取消"
        read_trimmed action "请选择操作: "
        case "$action" in
            1)
                current_client_ip=$(detect_ssh_client_ip)
                [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
                read_trimmed whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
                if ! normalize_ip_whitelist_input "$whitelist_input" whitelist_array; then
                    echo -e "${RED}❌ 白名单为空或格式错误，已取消。${PLAIN}"
                    pause_return
                    continue
                fi
                append_vps_public_ips_to_whitelist whitelist_array
                whitelist_ranges=$(join_array_by_space "${whitelist_array[@]}")
                confirm_risk_action "为 ${domain} 启用 IP 白名单" \
                    "Nginx stream 会仅对该 SNI 做源 IP 限制" \
                    "使用 443 单入口自动备份回滚，或清除该域名白名单后重新应用" \
                    "确认你的管理 IP 已包含在白名单中，且该域名不是 Cloudflare 橙云代理访问。" || continue
                set_sni_ip_whitelist_for_domain "$domain" "$whitelist_ranges"
                save_and_offer_reapply_sni_stack
                ;;
            2)
                if [[ -z "$current_ranges" ]]; then
                    echo -e "${BLUE}该域名未启用白名单。${PLAIN}"
                    pause_return
                    continue
                fi
                confirm_risk_action "清除 ${domain} 的 IP 白名单" \
                    "该域名会恢复为普通 443 分流访问" \
                    "重新设置该域名白名单" \
                    "确认这是你想要的公网访问策略。" || continue
                remove_sni_ip_whitelist_for_domain "$domain"
                save_and_offer_reapply_sni_stack
                ;;
            0|"")
                ;;
            *)
                echo -e "${RED}❌ 无效操作。${PLAIN}"
                pause_return
                ;;
        esac
    done
}

show_main_help() {
    echo -e "${CYAN}VPS-Optimize > 主菜单 > 帮助${PLAIN}"
    echo "1/2 适合新机器先体检和初始化。"
    echo "3   基础组件与常用服务；安装 Docker、Python、WARP 和常用工具。"
    echo "4   普通 Caddy 反代；适合未接入 443 单入口的普通网站/面板反代。"
    echo "5   管理 3x-ui、S-UI、Sing-box、Xray 和订阅工具。"
    echo "6   SSH 安全中心；管理端口、公钥和用户密钥登录模式。"
    echo "8   管理系统防火墙；改 SSH、防火墙前先确认云安全组。"
    echo "10  网络/内核优化；涉及 BBR、TCP、ZRAM 和内核清理。"
    echo "15  健康总览和反馈诊断信息，用于排错或提交 Issue。"
    echo "16  备份与回滚，高风险操作前建议先跑。"
    echo "19  443 单入口管理中心，面板/订阅/REALITY 共用公网 443。"
    echo "10 -> 7  流量达量关机保护，按账单周期防刷流量和超额账单。"
    echo "? 查看帮助，0/q 退出。"
}

show_beginner_help() {
    echo -e "${CYAN}VPS-Optimize > 新手向导 > 帮助${PLAIN}"
    echo "1 新机器初始化：按安全顺序引导预检、初始化、SSH、公钥、Fail2ban、防火墙、备份。"
    echo "2 安装面板/节点：进入面板、节点与订阅工具菜单。"
    echo "3 配置 443 单入口：进入 443 管理中心，适合面板、订阅和 REALITY 共用 443。"
    echo "4 健康检查：查看服务、端口、证书，并可生成反馈诊断信息。"
    echo "5 备份/回滚：创建备份或从已有备份恢复。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_panel_help() {
    echo -e "${CYAN}VPS-Optimize > 面板、节点与订阅工具 > 帮助${PLAIN}"
    echo "1 管理 3x-ui / x-ui，适合安装、进入官方菜单、修复面板。"
    echo "3/4 分别管理 Sing-box 和 Xray。"
    echo "5/6/7 管理订阅工具，部署后建议用 Caddy 或 443 单入口对外访问。"
    echo "11 面板救砖 / SSL 清理，适合 443 接入前清空面板证书路径。"
    echo "14 端口流量监控，单独管理 Port Traffic Dog。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_sni_help() {
    echo -e "${CYAN}VPS-Optimize > 443 单入口管理中心 > 帮助${PLAIN}"
    echo "1 查看当前入口状态 / 监听详情：显示公网 443、Caddy、Xray 和服务状态。"
    echo "2 首次配置 / 安装：建立共享 Web 域名、Caddy、证书和默认 Nginx Stream 入口。"
    echo "3/4/5 入口模式切换：在 Nginx Stream 模式、Xray Fallback 模式、TCP Peek + Splice 模式之间切换。"
    echo "6 重新应用：按当前 ENTRY_MODE 重新生成并启动入口配置。"
    echo "7 回滚：恢复上一次入口模式切换前的备份。"
    echo "8 管理 Web 域名/反代：后续新增或删除网站，不需要重跑首次配置。"
    echo "9 Web 域名 IP 白名单：只限制 Web/Caddy 域名，不影响 Xray 节点。"
    echo "10 Xray 入站管理：记录 SNI -> 本地地址:端口，不编辑 3x-ui/Xray 入站。"
    echo "11 链路体检：排查 ENTRY_MODE、监听、证书、Web 和 Xray 分流。"
    echo "12 网络访问测试：检查 DNS、TCP、TLS SNI、面板和订阅路径响应。"
    echo "13/14/15 维护项：证书、共享参数和订阅 External Proxy 提示。"
    echo "16 查看 TCP Peek + Splice 状态：查看 vpso-mux 分流器日志。"
    echo "普通 Caddy 未接入 443 单入口时，用主菜单 [4 普通 Caddy 反代] -> [4] 管理域名 IP 白名单。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_backup_help() {
    echo -e "${CYAN}VPS-Optimize > 备份与回滚 > 帮助${PLAIN}"
    echo "1 创建备份：高风险操作前先用。"
    echo "2 查看备份：确认可用备份和时间。"
    echo "3 回滚：会覆盖当前配置，必须输入 YES。"
    echo "4 隔离旧备份：只移动到隔离目录，不直接删除。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_net_kernel_help() {
    echo -e "${CYAN}VPS-Optimize > 网络/内核优化 > 帮助${PLAIN}"
    echo "1 BBR / 拥塞控制：调用外部调优脚本，执行前建议备份。"
    echo "2 TCP 参数：修改 sysctl，适合有明确参数需求的用户。"
    echo "3 ZRAM / Swap：适合小内存 VPS。"
    echo "4 安装/切换内核：高风险，必须确认快照和救援控制台可用。"
    echo "5 清理旧内核：不要删除当前内核和云厂商定制内核。"
    echo "6 DNS 更改优化：国内/国外默认 DNS，也支持自定义 IPv4 和 IPv6。"
    echo "7 流量达量关机保护：按网卡流量和账单周期自动关机，防止超额账单。"
    echo "8 网卡管理工具：查看网卡、路由、DNS，临时调整 MTU 或刷新 DHCP。"
    echo "? 查看帮助，0/q 返回主菜单。"
}

show_health_help() {
    echo -e "${CYAN}VPS-Optimize > 诊断/健康检查 > 帮助${PLAIN}"
    echo "健康总览会检查关键服务、监听端口和证书摘要。"
    echo "系统硬件探针会附带 443、Caddy、3x-ui、订阅工具和 Docker 场景概览。"
    echo "生成反馈诊断信息用于提交 GitHub Issue，会尽量避免输出 Token、私钥和敏感密钥。"
}

manage_sni_stack_sites() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🌐 443 网站/反代域名管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：给已完成 443 单入口的机器新增、删除或查看网站/反代域名。${PLAIN}"
        echo -e "${YELLOW}后续新增网站不需要重跑首次配置，只需要填写域名和本机后端端口。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看当前网站/反代域名${PLAIN}"
        echo -e "${GREEN}  2. 新增网站/反代域名${PLAIN}"
        echo -e "${GREEN}  3. 修改网站/反代后端端口${PLAIN}"
        echo -e "${GREEN}  4. 删除网站/反代域名${PLAIN}"
        echo -e "${GREEN}  5. 管理域名 IP 白名单${PLAIN}       ${YELLOW}(只限制被选择的域名)${PLAIN}"
        echo -e "${GREEN}  6. 重新应用并重启 Nginx/Caddy${PLAIN}"
        echo -e "${GREEN}  7. 443 单入口链路体检${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) list_sni_stack_sites ;;
            2) add_sni_stack_site ;;
            3) edit_sni_stack_site_backend ;;
            4) remove_sni_stack_site ;;
            5) manage_sni_stack_ip_whitelist ;;
            6) reapply_sni_stack_from_env ;;
            7) sni_stack_health_check ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

func_caddy_cf_reality_wizard() {
    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}检测到已有 443 单入口配置${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}如果只是新增网站或反代域名，请返回并选择 [8] 管理 Web 域名/反代。${PLAIN}"
        echo -e "${YELLOW}继续首次配置会重写 443 入口、Caddy/Web 和 Xray 分流相关核心配置。${PLAIN}"
        echo -e "------------------------------------------------"
        grep -E '^(PANEL_DOMAIN|PANEL_WEB_PATH|REALITY_SNI|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_PORT|XRAY_LISTEN_PORT|SUB_URI_PATH|CLASH_URI_PATH)=' /etc/vps-optimize/sni-stack.env 2>/dev/null || true
        echo -e "------------------------------------------------"
        confirm_danger "重新执行 443 首次配置" "将基于新输入重写 443 单入口核心配置，并重启入口服务/Caddy。" "脚本会先创建备份，可从 443 维护菜单或备份目录回滚。" || return 1
    fi
    select_initial_entry_mode || return 1
    collect_sni_stack_config || return 1
    probe_reality_sni "$REALITY_SNI" || return 1
    print_sni_stack_preview || return 1
    local cf_env_dir="/root/.config/vps-panel"
    local cf_env_file="${cf_env_dir}/cloudflare.env"
    local escaped_token
    mkdir -p "$cf_env_dir"
    chmod 700 "$cf_env_dir"
    escaped_token=${CF_TOKEN//\'/\'"\'"\'}
    printf "CF_Token='%s'\n" "$escaped_token" > "$cf_env_file"
    chmod 600 "$cf_env_file"

    local backup_dir
    create_sni_stack_backup
    backup_dir=$(cat /etc/vps-optimize/sni-stack.last-backup 2>/dev/null)
    prepare_initial_entry_mode_dependencies "$ENTRY_MODE" || { rollback_sni_stack_after_failure "$backup_dir" "入口模式依赖检查失败"; return 1; }
    quarantine_legacy_caddy_443_configs
    issue_and_install_cert_for_domain "$PANEL_DOMAIN" "$CF_TOKEN" || return 1
    if [[ ${#SITE_DOMAINS[@]} -gt 0 ]]; then
        local site_domain
        for site_domain in "${SITE_DOMAINS[@]}"; do
            [[ -z "$site_domain" ]] && continue
            issue_and_install_cert_for_domain "$site_domain" "$CF_TOKEN" || return 1
        done
    fi
    stop_public_443_entry_services_for_target "$ENTRY_MODE" || { rollback_sni_stack_after_failure "$backup_dir" "停止旧公网 443 入口服务失败"; return 1; }
    apply_entry_mode_by_name "$ENTRY_MODE" "$backup_dir" || { rollback_sni_stack_after_failure "$backup_dir" "入口模式 ${ENTRY_MODE} 应用失败"; return 1; }
    save_sni_stack_env
    harden_single_443_firewall
    generate_caddy_cf_manifest
    print_sni_stack_result
}

func_caddy_cf_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🩺 CF DNS 一键体检${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"

    echo -e "${YELLOW}▶ [1/5] 检查 Cloudflare Token ...${PLAIN}"
    if [[ -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            if command -v curl >/dev/null 2>&1; then
                local verify_resp
                verify_resp=$(curl -s --max-time 8 -H "Authorization: Bearer ${CF_Token}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
                if echo "$verify_resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
                    echo -e "${GREEN}✅ Cloudflare Token 校验通过${PLAIN}"
                    ((ok_count++))
                else
                    echo -e "${YELLOW}⚠️ Token 文件存在，但在线校验失败（可能权限不足/网络异常）${PLAIN}"
                    ((warn_count++))
                fi
            else
                echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
                ((warn_count++))
            fi
        else
            echo -e "${RED}❌ Token 文件为空，请在维护菜单 [2] 重新写入。${PLAIN}"
            ((err_count++))
        fi
    else
        echo -e "${RED}❌ 未找到 Token 文件: ${cf_env_file}${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [2/5] 检查 Caddy 服务状态...${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            echo -e "${GREEN}✅ Caddy 服务运行中${PLAIN}"
            ((ok_count++))
        else
            echo -e "${YELLOW}⚠️ Caddy 已安装但未运行${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${RED}❌ 未安装 Caddy${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [3/5] 检查域名配置、证书与软链接...${PLAIN}"
    local domain_count=0
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            local domain
            local listen_port
            local backend
            local backend_port
            local cert_file
            local key_file
            local cert_end
            local cert_ts
            local now_ts
            local days_left

            domain=$(basename "$conf_file" .caddy)
            cert_file="/etc/caddy/certs/${domain}.crt"
            key_file="/etc/caddy/certs/${domain}.key"

            if ! head -n1 "$conf_file" | grep -q '^https://'; then
                continue
            fi
            ((domain_count++))

            listen_port=$(sed -n '1{s@^https://[^:]*:\([0-9]\+\)[[:space:]]*{.*$@\1@p;q}' "$conf_file")
            backend=$(grep -E '^[[:space:]]*reverse_proxy[[:space:]]+127.0.0.1:[0-9]+' "$conf_file" | awk '{print $2}' | head -n1)
            backend_port=$(echo "$backend" | awk -F: '{print $2}')

            echo -e "${CYAN}  - 域名: ${domain}${PLAIN}"

            if [[ -f "$cert_file" && -f "$key_file" ]]; then
                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -n "$cert_end" && "$days_left" -gt 15 ]]; then
                    echo -e "    ${GREEN}证书状态: 正常 (剩余约 ${days_left} 天)${PLAIN}"
                    ((ok_count++))
                elif [[ -n "$cert_end" ]]; then
                    echo -e "    ${YELLOW}证书状态: 即将到期 (剩余约 ${days_left} 天)${PLAIN}"
                    ((warn_count++))
                else
                    echo -e "    ${RED}证书状态: 无法读取有效期${PLAIN}"
                    ((err_count++))
                fi
            else
                echo -e "    ${RED}证书状态: 缺失 /etc/caddy/certs/${domain}.crt|.key${PLAIN}"
                ((err_count++))
            fi

            if [[ -L "/root/cert/${domain}.crt" && -e "/root/cert/${domain}.crt" && -L "/root/cert/${domain}.key" && -e "/root/cert/${domain}.key" ]]; then
                echo -e "    ${GREEN}软链接状态: /root/cert 已正确挂载${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}软链接状态: 缺失或失效，建议执行维护菜单 [9] 重建软链接${PLAIN}"
                ((warn_count++))
            fi

            if [[ -n "$listen_port" ]] && ss -lnt 2>/dev/null | awk '{print $4}' | grep -q "127.0.0.1:${listen_port}$"; then
                echo -e "    ${GREEN}监听状态: Caddy 本地端口 127.0.0.1:${listen_port} 可见${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}监听状态: 未检测到 127.0.0.1:${listen_port} 在监听${PLAIN}"
                ((warn_count++))
            fi

            if [[ -n "$backend_port" ]] && ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ":${backend_port}$"; then
                echo -e "    ${GREEN}后端状态: 127.0.0.1:${backend_port} 有服务监听${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}后端状态: 127.0.0.1:${backend_port} 未检测到监听${PLAIN}"
                ((warn_count++))
            fi
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi

    if [[ "$domain_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ 未检测到本功能托管的域名配置（https://域名:端口）。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [4/5] 检查清单文件...${PLAIN}"
    if [[ -f /root/cert/caddy_cf_manifest.txt ]]; then
        echo -e "${GREEN}✅ 清单文件存在: /root/cert/caddy_cf_manifest.txt${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 清单文件不存在，建议执行维护菜单 [10] 重建。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/5] 总结...${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${CYAN}体检结果: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "${RED}建议优先修复异常项，再继续业务切流。${PLAIN}"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "${YELLOW}当前可继续运行，但建议处理警告项提高稳定性。${PLAIN}"
    else
        echo -e "${GREEN}环境健康，可放心使用 Reality 回落 + Caddy 反代链路。${PLAIN}"
    fi
}

func_caddy_cf_auto_fix() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧰 CF DNS 一键自动修复${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local fixed_count=0
    local warn_count=0
    local fail_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    local acme_bin="/root/.acme.sh/acme.sh"

    echo -e "${YELLOW}▶ [1/7] 修复基础目录与主配置...${PLAIN}"
    mkdir -p /root/cert /etc/caddy/certs /etc/caddy/conf.d /root/.config/vps-panel
    chmod 700 /root/.config/vps-panel >/dev/null 2>&1

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
        ((fixed_count++))
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
        ((fixed_count++))
    fi

    echo -e "${YELLOW}▶ [1.5/7] 隔离旧式站点配置（避免抢占 443）...${PLAIN}"
    quarantine_legacy_caddy_443_configs

    echo -e "${YELLOW}▶ [2/7] 修复证书权限...${PLAIN}"
    if [[ -d /etc/caddy/certs ]]; then
        if id caddy >/dev/null 2>&1; then
            chown root:caddy /etc/caddy/certs/* 2>/dev/null
            chmod 640 /etc/caddy/certs/* 2>/dev/null
        else
            chmod 600 /etc/caddy/certs/* 2>/dev/null
        fi
        ((fixed_count++))
    else
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [3/7] 全量重建 /root/cert 软链接...${PLAIN}"
    local relink_count=0
    if [[ -d /etc/caddy/certs ]]; then
        while IFS= read -r cert_path; do
            local domain
            domain=$(basename "$cert_path" .crt)
            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                ((relink_count++))
            fi
        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
    fi
    echo -e "${GREEN}✅ 已重建 ${relink_count} 组软链接。${PLAIN}"
    ((fixed_count++))

    echo -e "${YELLOW}▶ [4/7] 近效期证书自动续签...${PLAIN}"
    local renew_count=0
    local renew_fail=0
    if [[ -x "$acme_bin" && -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            while IFS= read -r conf_file; do
                local domain
                local cert_file
                local cert_end
                local cert_ts
                local now_ts
                local days_left

                domain=$(basename "$conf_file" .caddy)
                cert_file="/etc/caddy/certs/${domain}.crt"

                if ! head -n1 "$conf_file" | grep -q '^https://'; then
                    continue
                fi
                if [[ ! -f "$cert_file" ]]; then
                    continue
                fi

                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -z "$cert_end" || "$days_left" -le 15 ]]; then
                    if issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                        "$acme_bin" --install-cert -d "$domain" --ecc \
                            --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                            --key-file "/etc/caddy/certs/${domain}.key" \
                            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1
                        ((renew_count++))
                    else
                        ((renew_fail++))
                    fi
                fi
            done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)

            if [[ "$renew_fail" -gt 0 ]]; then
                ((warn_count+=renew_fail))
            fi
            echo -e "${GREEN}✅ 自动续签完成，成功 ${renew_count} 个，失败 ${renew_fail} 个。${PLAIN}"
            ((fixed_count++))
        else
            echo -e "${YELLOW}⚠️ Token 为空，跳过自动续签。${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${YELLOW}⚠️ 未检测到 acme.sh 或 Token 文件，跳过自动续签。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/7] 校验并重载 Caddy...${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            systemctl enable caddy >/dev/null 2>&1
            if systemctl restart caddy >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Caddy 配置校验通过并重启成功。${PLAIN}"
                ((fixed_count++))
            else
                echo -e "${RED}❌ Caddy 重启失败，请手动检查日志。${PLAIN}"
                ((fail_count++))
            fi
        else
            echo -e "${RED}❌ Caddy 配置校验失败，未执行重启。${PLAIN}"
            ((fail_count++))
        fi
    else
        echo -e "${RED}❌ 未安装 Caddy，无法执行重载。${PLAIN}"
        ((fail_count++))
    fi

    echo -e "${YELLOW}▶ [6/7] 重建清单文件...${PLAIN}"
    generate_caddy_cf_manifest
    ((fixed_count++))
    echo -e "${GREEN}✅ 清单已重建: /root/cert/caddy_cf_manifest.txt${PLAIN}"

    echo -e "${YELLOW}▶ [7/7] 补全 acme 自动续签任务...${PLAIN}"
    if [[ -x "$acme_bin" ]]; then
        if "$acme_bin" --install-cronjob >/dev/null 2>&1; then
            echo -e "${GREEN}✅ acme.sh 自动续签任务已确认。${PLAIN}"
            ((fixed_count++))
        else
            echo -e "${YELLOW}⚠️ 无法确认 acme.sh 续签任务，请手动检查 crontab。${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${YELLOW}⚠️ 未安装 acme.sh，跳过续签任务补全。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "${CYAN}自动修复结果: ${GREEN}${fixed_count} 已修复${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${fail_count} 失败${PLAIN}"
    if [[ "$fail_count" -gt 0 ]]; then
        echo -e "${RED}存在失败项，建议先执行维护菜单 [12] 体检复查并查看 caddy 日志。${PLAIN}"
    else
        echo -e "${GREEN}自动修复流程完成，可执行维护菜单 [12] 复检确认。${PLAIN}"
    fi
}

func_caddy_cf_maintenance_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🛠️ 443 / Caddy / Cloudflare 维护中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：排查 443 链路、重签证书、修复软链接、隔离旧配置和回滚。${PLAIN}"
        echo -e "${YELLOW}建议顺序：先 [1] 体检，再按异常选择证书或 Caddy 修复项。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 443 单入口常用${PLAIN}"
        echo -e "${GREEN}  1. 443 链路与安全体检${PLAIN}       ${YELLOW}(Nginx/Caddy/REALITY/面板/版本隐藏)${PLAIN}"
        echo -e "${GREEN}  2. 管理 443 网站/反代域名${PLAIN}    ${YELLOW}(新增/删除/查看，最常用)${PLAIN}"
        echo -e "${GREEN}  3. 修改 443 分流参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}"
        echo -e "${GREEN}  4. 重新应用上次 443 配置${PLAIN}     ${YELLOW}(读取 sni-stack.env 重建配置)${PLAIN}"
        echo -e "${GREEN}  5. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}"
        echo -e "${RED}  6. 回滚 443 单入口配置${PLAIN}       ${YELLOW}(从最近备份恢复)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 证书与 Cloudflare${PLAIN}"
        echo -e "${GREEN}  7. 查看已管理域名 / 证书路径${PLAIN}"
        echo -e "${GREEN}  8. 更新 Cloudflare API Token${PLAIN}"
        echo -e "${GREEN}  9. 重新签发某个域名证书${PLAIN}"
        echo -e "${GREEN} 10. 重建 /root/cert 证书软链接${PLAIN}"
        echo -e "${GREEN} 11. 重建证书清单文件${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ Caddy 修复与清理${PLAIN}"
        echo -e "${GREEN} 12. 校验并重载 Caddy${PLAIN}"
        echo -e "${GREEN} 13. Caddy/证书一键体检${PLAIN}       ${YELLOW}(Token/证书/监听/后端)${PLAIN}"
        echo -e "${GREEN} 14. 一键自动修复常见问题${PLAIN}"
        echo -e "${GREEN} 15. 隔离旧 Caddy 配置${PLAIN}        ${YELLOW}(避免抢占 443)${PLAIN}"
        echo -e "${RED} 16. 隔离某个域名的 Caddy 配置与证书${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local m_choice
        read_trimmed m_choice "👉 请选择操作: "

        case "$m_choice" in
            1) m_choice=11 ;;
            2) m_choice=15 ;;
            3) m_choice=16 ;;
            4) m_choice=12 ;;
            5) m_choice=13 ;;
            6) m_choice=14 ;;
            7) m_choice=1 ;;
            8) m_choice=2 ;;
            9) m_choice=3 ;;
            10) m_choice=4 ;;
            11) m_choice=7 ;;
            12) m_choice=6 ;;
            13) m_choice=8 ;;
            14) m_choice=9 ;;
            15) m_choice=10 ;;
            16) m_choice=5 ;;
        esac

        case $m_choice in
            16)
                edit_sni_stack_runtime_profile
                ;;

            1)
                generate_caddy_cf_manifest
                echo -e "${CYAN}👇 当前清单内容：${PLAIN}"
                cat /root/cert/caddy_cf_manifest.txt 2>/dev/null
                ;;

            2)
                local new_token escaped_token
                mkdir -p /root/.config/vps-panel
                chmod 700 /root/.config/vps-panel
                echo -e "${CYAN}👇 请输入新的 Cloudflare API Token${PLAIN}"
                read_secret_trimmed new_token "CF Token: "
                if [[ -z "$new_token" || ${#new_token} -lt 20 ]]; then
                    echo -e "${RED}❌ Token 长度异常，更新取消。${PLAIN}"
                else
                    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
                    verify_cf_token_online "$new_token"
                    local verify_rc=$?
                    if [[ "$verify_rc" -eq 1 ]]; then
                        echo -e "${RED}❌ Token 在线校验失败，未写入。${PLAIN}"
                        echo -e "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    elif [[ "$verify_rc" -eq 2 ]]; then
                        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验，继续写入。${PLAIN}"
                    else
                        echo -e "${GREEN}✅ Token 校验通过。${PLAIN}"
                    fi

                    escaped_token=${new_token//\'/\'"\'"\'}
                    printf "CF_Token='%s'\n" "$escaped_token" > /root/.config/vps-panel/cloudflare.env
                    chmod 600 /root/.config/vps-panel/cloudflare.env
                    echo -e "${GREEN}✅ Cloudflare Token 已更新。${PLAIN}"
                fi
                ;;

            3)
                local domain
                local acme_bin="/root/.acme.sh/acme.sh"
                local cf_env_file="/root/.config/vps-panel/cloudflare.env"

                read_trimmed domain "👉 请输入要重签的域名: "
                domain=$(normalize_domain_input "$domain")
                if ! is_valid_domain "$domain"; then
                    echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "${RED}❌ 未检测到 acme.sh，请先运行主菜单 [19] -> [2] 首次配置 443 单入口。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                if [[ ! -f "$cf_env_file" ]]; then
                    echo -e "${RED}❌ 未检测到 Cloudflare Token，请先执行本菜单 [2]。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                # shellcheck disable=SC1090
                source "$cf_env_file"
                confirm_risk_action "重签并安装 ${domain} 的证书" \
                    "acme.sh 证书缓存、/etc/caddy/certs 和 /root/cert 软链接" \
                    "使用现有 Caddy/证书备份恢复，或重新运行证书维护菜单签发" \
                    "确认域名 DNS 已解析，Cloudflare Token 权限正确。" || {
                    echo -e "${BLUE}已取消证书重签。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                }
                echo -e "${CYAN}▶ 正在重签证书: ${domain}${PLAIN}"

                if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                    echo -e "${RED}❌ 证书签发失败：${domain}${PLAIN}"
                    echo -e "${YELLOW}   提示：建议先执行本菜单 [13] 自动修复再重试。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                mkdir -p /etc/caddy/certs /root/cert
                if ! "$acme_bin" --install-cert -d "$domain" --ecc \
                    --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                    --key-file "/etc/caddy/certs/${domain}.key" \
                    --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
                    echo -e "${RED}❌ 证书安装失败：${domain}${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if id caddy >/dev/null 2>&1; then
                    chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
                    chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                else
                    chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                fi

                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ 重签完成并已更新 /root/cert 软链接。${PLAIN}"
                ;;

            4)
                local link_mode domain
                mkdir -p /root/cert
                read_trimmed link_mode "❓ 重建全部链接还是单域名？(all/one): "

                if [[ "$link_mode" == "all" ]]; then
                    local relink_count=0
                    if [[ -d /etc/caddy/certs ]]; then
                        while IFS= read -r cert_path; do
                            domain=$(basename "$cert_path" .crt)
                            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                                ((relink_count++))
                            fi
                        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
                    fi
                    generate_caddy_cf_manifest
                    echo -e "${GREEN}✅ 已重建 ${relink_count} 个域名的证书软链接。${PLAIN}"
                else
                    read_trimmed domain "👉 请输入域名: "
                    domain=$(normalize_domain_input "$domain")
                    if ! is_valid_domain "$domain"; then
                        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    if [[ -f "/etc/caddy/certs/${domain}.crt" && -f "/etc/caddy/certs/${domain}.key" ]]; then
                        ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                        ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                        generate_caddy_cf_manifest
                        echo -e "${GREEN}✅ 软链接已重建：/root/cert/${domain}.crt 与 /root/cert/${domain}.key${PLAIN}"
                    else
                        echo -e "${RED}❌ 未找到该域名证书文件。${PLAIN}"
                    fi
                fi
                ;;

            5)
                local domain purge_acme
                read_trimmed domain "👉 请输入要隔离的域名: "
                domain=$(normalize_domain_input "$domain")
                if ! is_valid_domain "$domain"; then
                    echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if ! confirm_risk_action "隔离 ${domain} 的配置与证书" \
                    "Caddy 配置、证书文件和可选 acme.sh 历史记录" \
                    "从隔离目录手动移回，或重新签发证书并恢复 Caddy 配置" \
                    "确认该域名不再承载线上服务，或已经准备好重新签发。"; then
                    echo -e "${BLUE}已取消隔离。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                local domain_quarantine_dir="/etc/vps-optimize/quarantine/caddy-domain-${domain}-$(date +%s)"
                mkdir -p "$domain_quarantine_dir"
                quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true

                read_trimmed purge_acme "❓ 是否同时删除 acme.sh 历史记录？(y/n，默认n，建议保留): "
                if is_yes "$purge_acme"; then
                    /root/.acme.sh/acme.sh --remove -d "$domain" --ecc >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                fi

                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                fi
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ ${domain} 的 Caddy 配置与证书已隔离到：${domain_quarantine_dir}${PLAIN}"
                ;;

            6)
                caddy_format_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "${GREEN}✅ Caddy 配置已格式化，校验通过并重启生效。${PLAIN}"
                else
                    echo -e "${RED}❌ Caddy 配置校验失败，请检查 /etc/caddy/conf.d/*.caddy${PLAIN}"
                fi
                ;;

            7)
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ 清单已重建：/root/cert/caddy_cf_manifest.txt${PLAIN}"
                ;;

            8)
                func_caddy_cf_health_check
                ;;

            9)
                func_caddy_cf_auto_fix
                ;;

            10)
                quarantine_legacy_caddy_443_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "${GREEN}✅ 隔离完成，Caddy 已重载。${PLAIN}"
                else
                    echo -e "${RED}❌ 当前 Caddy 配置校验失败，请先修复语法错误。${PLAIN}"
                fi
                ;;

            11)
                sni_stack_health_check
                ;;

            12)
                reapply_sni_stack_from_env
                ;;

            13)
                check_sni_stack_subscription_hint
                ;;

            14)
                rollback_sni_stack_config
                ;;

            15)
                manage_sni_stack_sites
                ;;

            0) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac

        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 新增功能：查看 Caddy 已申请证书路径
# ---------------------------------------------------------
func_view_caddy_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 Caddy 已申请证书路径查询${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    if [[ ! -f "/etc/caddy/Caddyfile" ]]; then
        echo -e "${RED}❌ 未检测到 /etc/caddy/Caddyfile，请先配置反代！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 提取 Caddyfile 与 conf.d 中的域名 (排除注释，简单匹配)
    local domains
    domains=$(cat /etc/caddy/Caddyfile /etc/caddy/conf.d/*.caddy 2>/dev/null | grep -vE '^[[:space:]]*#' | grep '{' | awk '{print $1}' | tr -d '{')
    
    if [[ -z "$domains" ]]; then
        echo -e "${YELLOW}⚠️ Caddyfile 中没有配置明确的域名。${PLAIN}"
    else
        # Caddy 默认的证书存储根路径
        local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
        [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"
        
        for domain in $domains; do
            # 过滤掉本地回环等无意义的块
            if [[ "$domain" == ":80" || "$domain" == "localhost" ]]; then continue; fi
            
            echo -e "${BLUE}🌐 域名: ${BOLD}${domain}${PLAIN}"
            
            local found=false
            if [[ -d "$cert_root" ]]; then
                # 递归查找对应的 .crt 和 .key 文件
                local cert_file
                local key_file
                cert_file=$(find "$cert_root" -name "${domain}.crt" -print -quit 2>/dev/null)
                key_file=$(find "$cert_root" -name "${domain}.key" -print -quit 2>/dev/null)
                
                if [[ -n "$cert_file" && -n "$key_file" ]]; then
                    echo -e "   ${GREEN}📄 公钥 (CRT):${PLAIN} ${cert_file}"
                    echo -e "   ${YELLOW}🔑 密钥 (KEY):${PLAIN} ${key_file}"
                    found=true
                fi
            fi
            
            if ! $found; then
                echo -e "   ${RED}❌ 未找到证书，可能尚未签发成功或路径异常。${PLAIN}"
            fi
            echo -e "------------------------------------------------"
        done
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：清空 Caddy 配置文件 (适配模块化安全架构)
# ---------------------------------------------------------
func_caddy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清空 Caddy 配置文件 (模块化版本)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 检查主文件与模块化目录是否存在
    if [[ -f /etc/caddy/Caddyfile ]] || [[ -d /etc/caddy/conf.d ]]; then
        echo -e "${YELLOW}将清空 /etc/caddy/conf.d/*.caddy，并重置 /etc/caddy/Caddyfile 为模块化初始状态。${PLAIN}"
        if confirm_danger "清空 Caddy 反代配置" "所有独立 Caddy 反代配置会失效，相关网站/面板可能暂时打不开。" "脚本会备份 Caddyfile 和 conf.d 目录，可按备份路径手动恢复。"; then
            
            # 1. 备份现有的模块化配置目录
            if [[ -d /etc/caddy/conf.d ]]; then
                local backup_dir="/etc/caddy/conf.d_bak_$(date +%s)"
                cp -r /etc/caddy/conf.d "$backup_dir" 2>/dev/null
                echo -e "${BLUE}已备份原配置目录为 $backup_dir${PLAIN}"
                
                # 精准隔离所有 .caddy 配置文件，避免不可逆删除。
                while IFS= read -r caddy_conf; do
                    mv "$caddy_conf" "$backup_dir/" 2>/dev/null || true
                done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name '*.caddy' 2>/dev/null | sort)
            fi
            
            # 2. 守护主文件架构，重置为极简模式并注入模块化指令
            cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null
            echo "# Caddyfile Cleared and Reset to Modular Architecture" > /etc/caddy/Caddyfile
            echo "import conf.d/*" >> /etc/caddy/Caddyfile
            
            # 3. 重启生效
            systemctl restart caddy >/dev/null 2>&1
            echo -e "${GREEN}✅ 所有反代配置已清空并成功重载！系统已恢复纯净的模块化初始状态。${PLAIN}"
        else
            echo -e "${BLUE}已取消清空操作。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 未检测到 Caddy 配置文件或模块化目录！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

strip_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local tmp_file
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    awk '
        /# vps-optimize-ip-whitelist-start/ {skip=1; next}
        /# vps-optimize-ip-whitelist-end/ {skip=0; next}
        !skip {print}
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

insert_caddy_ip_whitelist_block() {
    local conf_file="$1"
    local ranges="$2"
    local tmp_file block
    strip_caddy_ip_whitelist_block "$conf_file" || return 1
    tmp_file=$(mktemp /tmp/caddy-ipwl.XXXXXX) || return 1
    block=$(caddy_ip_whitelist_block "$ranges")
    awk -v block="$block" '
        inserted == 0 && /^[[:space:]]*[^#[:space:]].*\{[[:space:]]*$/ {
            print
            printf "%s", block
            inserted=1
            next
        }
        {print}
        END { if (inserted == 0) exit 1 }
    ' "$conf_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv "$tmp_file" "$conf_file"
}

func_caddy_manage_ip_whitelist() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔐 普通 Caddy 域名 IP 白名单${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适用于未启用 443 单入口、由 Caddy 直接对外服务的域名。${PLAIN}"
    echo -e "${YELLOW}如果该域名已接入 443 单入口，请用 [19] -> [9]，不要在 Caddy 层限制。${PLAIN}"
    echo -e "------------------------------------------------"

    if ! command -v caddy >/dev/null 2>&1 || [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "${RED}❌ 未检测到 Caddy 或 /etc/caddy/Caddyfile，请先配置普通 Caddy 反代。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    local domain conf_file first_site_line action backup_file
    read_trimmed domain "请输入要管理的域名 (如 panel.example.com): "
    domain=$(normalize_domain_input "$domain")
    if ! is_valid_domain "$domain"; then
        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    conf_file="/etc/caddy/conf.d/${domain}.caddy"
    if [[ ! -f "$conf_file" ]]; then
        echo -e "${RED}❌ 未找到 ${conf_file}。该入口只管理脚本创建的模块化 Caddy 域名配置。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    first_site_line=$(grep -m1 -E '^[[:space:]]*[^#[:space:]].*\{' "$conf_file" 2>/dev/null | sed 's/^[[:space:]]*//')
    if [[ "$first_site_line" != "$domain "* && "$first_site_line" != "$domain{"* && "$first_site_line" != "https://${domain}"* ]]; then
        echo -e "${RED}❌ ${conf_file} 的首个站点块不是 ${domain}，为避免误改已取消。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    if [[ "$first_site_line" =~ ^https://[^[:space:]]+:[0-9]+[[:space:]]*\{ ]]; then
        echo -e "${RED}❌ 这个配置看起来属于 443 单入口本地 Caddy TLS 站点。请改用 [19] -> [9] 管理白名单。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    echo -e "当前配置文件：${conf_file}"
    if grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
        echo -e "${YELLOW}当前状态：已启用脚本管理的 IP 白名单。${PLAIN}"
    else
        echo -e "${BLUE}当前状态：未启用脚本管理的 IP 白名单。${PLAIN}"
    fi
    echo -e "1. 设置/覆盖白名单"
    echo -e "2. 清除白名单"
    echo -e "0. 取消"
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
                read -n 1 -s -r -p "按任意键继续..."
                return
            fi
            append_vps_public_ips_to_whitelist ip_whitelist_array
            ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
            cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; read -n 1 -s -r -p "按任意键继续..."; return; }
            if insert_caddy_ip_whitelist_block "$conf_file" "$ip_whitelist_ranges" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                if systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
                    echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
                else
                    echo -e "${RED}❌ Caddy 重载失败，正在回滚...${PLAIN}"
                    mv "$backup_file" "$conf_file"
                    systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                fi
            else
                echo -e "${RED}❌ 写入后 Caddy 校验失败，正在回滚...${PLAIN}"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        2)
            if ! grep -q '# vps-optimize-ip-whitelist-start' "$conf_file" 2>/dev/null; then
                echo -e "${BLUE}该域名没有脚本管理的白名单块，无需清除。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                return
            fi
            cp -p "$conf_file" "$backup_file" || { echo -e "${RED}❌ 备份失败，已取消。${PLAIN}"; read -n 1 -s -r -p "按任意键继续..."; return; }
            if strip_caddy_ip_whitelist_block "$conf_file" && caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ 已清除 ${domain} 的 IP 白名单。${PLAIN}"
                echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
            else
                echo -e "${RED}❌ 清除后 Caddy 校验失败，正在回滚...${PLAIN}"
                mv "$backup_file" "$conf_file"
            fi
            ;;
        0|"")
            echo -e "${BLUE}已取消。${PLAIN}"
            ;;
        *)
            echo -e "${RED}❌ 无效操作。${PLAIN}"
            ;;
    esac

    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 优化重构：核弹级域名证书清理与解除端口占用 (模块化安全版)
# ---------------------------------------------------------
func_caddy_delete_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}☢️ 核弹级：彻底清理域名证书与配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：该脚本将彻底清理指定域名的证书与配置，确保服务器环境干净。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read_trimmed domain "👉 请输入要强杀清理的精准域名 (如 panel.site.com): "
    domain=$(normalize_domain_input "$domain")
    if [[ -z "$domain" ]]; then
        echo -e "${RED}❌ 域名不能为空！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    if ! is_valid_domain "$domain"; then
        echo -e "${RED}❌ 域名格式无效，已取消清理。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "\n${CYAN}▶ 正在执行核弹级清理流程...${PLAIN}"
    echo -e "${YELLOW}此操作将永久删除该域名的证书与配置，无法恢复！${PLAIN}"
    echo -e "请确认操作...${PLAIN}"
    if confirm_danger "彻底清理 ${domain} 的证书与配置" "会停止 Caddy，删除该域名证书、acme.sh 残留和 Caddy 配置，再启动 Caddy。" "请先确认已有系统快照或 Caddy 备份；删除后的证书需要重新签发。"; then
        # 1. 停止 Caddy，强制释放 80/443 端口
        systemctl stop caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ [1/4] 已强制停止 Caddy 服务，释放网络端口。${PLAIN}"
        
        # 2. 深度清理 Caddy 底层证书缓存
        local caddy_paths=("/var/lib/caddy/.local/share/caddy/certificates" "/root/.local/share/caddy/certificates")
        local caddy_found=false
        for cp in "${caddy_paths[@]}"; do
            if [[ -d "$cp" ]]; then
                local target=$(find "$cp" -type d -name "${domain}" -print -quit 2>/dev/null)
                if [[ -n "$target" ]]; then
                    quarantine_path "$target" "/root/vps-optimize-quarantine/caddy-certs" >/dev/null 2>&1 || true
                    caddy_found=true
                fi
            fi
        done
        if $caddy_found; then
            echo -e "${GREEN}✅ [2/4] Caddy 引擎中关于 ${domain} 的密钥与证书已抹除。${PLAIN}"
        else
            echo -e "${BLUE}ℹ️ [2/4] 未在 Caddy 引擎中发现该域名的证书。${PLAIN}"
        fi
        
        # 3. 清理 acme.sh 残留
        if [[ -d "/root/.acme.sh" ]]; then
            local acme_target=$(find "/root/.acme.sh" -type d -name "*${domain}*" -print -quit 2>/dev/null)
            if [[ -n "$acme_target" ]]; then
                quarantine_path "$acme_target" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ [3/4] 面板底层 (~/.acme.sh) 关于 ${domain} 的残留已抹除。${PLAIN}"
            else
                echo -e "${BLUE}ℹ️ [3/4] 未在 acme.sh 引擎中发现残留。${PLAIN}"
            fi
        else
            echo -e "${BLUE}ℹ️ [3/4] 系统未安装独立 acme.sh 环境，已跳过。${PLAIN}"
        fi
        
        # 4. 外科手术：模块化安全删除
        local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$domain_conf" ]]; then
            echo -e "${YELLOW}⏳ [4/4] 检测到专属配置文件，正在隔离...${PLAIN}"
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ [4/4] 专属配置文件 ($domain_conf) 已隔离！${PLAIN}"
        else
            echo -e "${GREEN}✅ [4/4] 未发现该域名的专属配置文件。${PLAIN}"
        fi

        # 重启 Caddy 以加载干净的配置
        systemctl start caddy >/dev/null 2>&1

        echo -e "------------------------------------------------"
        echo -e "${GREEN}🎉 清理彻底完成！当前域名环境已处于出厂真空状态。${PLAIN}"
    else
        echo -e "${BLUE}操作已取消。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：独立追加 Caddy 跳过不安全证书反代块 (模块化版)
# ---------------------------------------------------------
func_caddy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 独立配置：追加 Caddy 跳过证书验证反代${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "${RED}❌ 未检测到 Caddy 配置文件，请先运行 [13] 安装 Caddy！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    local domain
    local port
    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed domain "👉 请输入解析后的域名 (如 panel.site.com): "
    read_trimmed port "👉 请输入面板 HTTPS 本地映射端口 (如 40000): "
    domain=$(normalize_domain_input "$domain")
    
    if ! is_valid_domain "$domain" || ! is_valid_port "$port"; then
        echo -e "${RED}❌ 域名为空或端口格式错误！已取消操作。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    read_trimmed enable_ip_whitelist "❓ 是否只允许指定 IP/CIDR 访问该域名？(y/n，默认 n): "
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键继续..."
            return
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi
    
    # 确保主文件包含模块化目录
    grep -q "import conf.d/\*" /etc/caddy/Caddyfile || echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    
    mkdir -p /etc/caddy/conf.d
    local conf_file="/etc/caddy/conf.d/${domain}.caddy"
    local backup_file=""
    if [[ -f "$conf_file" ]]; then
        backup_file="${conf_file}.bak_$(date +%s)"
        if ! cp -p "$conf_file" "$backup_file"; then
            echo -e "${RED}❌ 现有配置备份失败，已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键继续..."
            return
        fi
    fi
    
    cat <<EOF > "$conf_file"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy https://127.0.0.1:$port {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl reload caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ 独立跳过验证配置已成功建立并生效！${PLAIN}"
        [[ -n "$ip_whitelist_ranges" ]] && echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
    else
        echo -e "${RED}❌ 致命错误：追加的配置导致语法错误！正在回滚...${PLAIN}"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
        [[ -n "$backup_file" && -f "$backup_file" ]] && mv "$backup_file" "$conf_file"
    fi

    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 4. SSH 安全加固 (终极完美版：防截断、防覆盖、防 Socket 冲突)
# ---------------------------------------------------------
ssh_service_restart() {
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
}

ssh_prepare_runtime_dir() {
    if [[ ! -d /run/sshd ]]; then
        mkdir -p /run/sshd 2>/dev/null || return 1
    fi
    chmod 755 /run/sshd 2>/dev/null || true
}

ssh_socket_unit_exists() {
    local unit="$1"
    local active_state enabled_state
    active_state=$(systemctl is-active "$unit" 2>/dev/null || true)
    enabled_state=$(systemctl is-enabled "$unit" 2>/dev/null || true)
    [[ "$active_state" == "active" ]] && return 0
    [[ "$enabled_state" == "enabled" || "$enabled_state" == "enabled-runtime" ]]
}

ssh_socket_units_for_host() {
    local unit
    for unit in ssh.socket sshd.socket; do
        if ssh_socket_unit_exists "$unit"; then
            echo "$unit"
        fi
    done
}

ssh_write_socket_port_dropins() {
    local port="$1"
    local unit dir found=false
    while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        found=true
        dir="/etc/systemd/system/${unit}.d"
        mkdir -p "$dir" || return 1
        cat > "${dir}/10-vps-optimize-port.conf" <<EOF
[Socket]
ListenStream=
ListenStream=${port}
EOF
    done < <(ssh_socket_units_for_host)
    $found
}

ssh_restart_socket_units() {
    local unit found=false ok=true
    systemctl daemon-reload >/dev/null 2>&1 || true
    while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        found=true
        systemctl restart "$unit" >/dev/null 2>&1 || ok=false
    done < <(ssh_socket_units_for_host)
    $found && $ok
}

ssh_restart_runtime() {
    local restarted=false
    if ssh_restart_socket_units; then
        restarted=true
    fi
    if ssh_service_restart; then
        restarted=true
    fi
    $restarted
}

ssh_write_sshd_port_dropin() {
    local port="$1"
    mkdir -p /etc/ssh/sshd_config.d 2>/dev/null || return 1
    cat > /etc/ssh/sshd_config.d/00-vps-optimize-port.conf <<EOF
# VPS-Optimize SSH port mirror
Port ${port}
EOF
}

ssh_write_auth_dropin() {
    local mode="$1"
    local interactive_key="$2"
    case "$mode" in
        key_only|key_preferred|password) ;;
        *) return 1 ;;
    esac
    mkdir -p /etc/ssh/sshd_config.d 2>/dev/null || return 1
    {
        echo "# VPS-Optimize SSH auth mode mirror"
        echo "PubkeyAuthentication yes"
        case "$mode" in
            key_only)
                echo "PasswordAuthentication no"
                echo "${interactive_key} no"
                ;;
            key_preferred|password)
                echo "PasswordAuthentication yes"
                echo "${interactive_key} yes"
                ;;
        esac
    } > /etc/ssh/sshd_config.d/00-vps-optimize-auth.conf
}

ssh_restore_auth_dropin() {
    local dropin="$1"
    local backup="$2"
    if [[ -n "$backup" && -f "$backup" ]]; then
        cp -p "$backup" "$dropin" 2>/dev/null || true
    else
        mkdir -p "$(dirname "$dropin")" 2>/dev/null || return 0
        cat > "$dropin" <<EOF
# VPS-Optimize SSH auth mode mirror disabled after rollback
EOF
    fi
}

ssh_reconcile_cloud_auth_dropins() {
    local mode="$1"
    local state_file="$2"
    local timestamp="$3"
    local dir="/etc/ssh/sshd_config.d"
    local conf tmp backup current_auth_dropin

    : > "$state_file" || return 1
    [[ -d "$dir" ]] || return 0
    current_auth_dropin="/etc/ssh/sshd_config.d/00-vps-optimize-auth.conf"

    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == "$current_auth_dropin" ]] && continue
        tmp=$(mktemp /tmp/vps-sshd-dropin.XXXXXX) || return 1
        if ! awk -v mode="$mode" '
            function desired_for(key, lkey) {
                lkey = tolower(key)
                if (lkey == "pubkeyauthentication") return "yes"
                if (lkey == "passwordauthentication") return mode == "key_only" ? "no" : "yes"
                if (lkey == "kbdinteractiveauthentication") return mode == "key_only" ? "no" : "yes"
                if (lkey == "challengeresponseauthentication") return mode == "key_only" ? "no" : "yes"
                return ""
            }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
            /^[[:space:]]*Match[[:space:]]+/ { in_match = 1; print; next }
            in_match { print; next }
            {
                desired = desired_for($1)
                if (desired != "") {
                    if (tolower($2) == desired) {
                        print
                    } else {
                        print $1 " " desired " # VPS-Optimize reconciled cloud image setting"
                    }
                    next
                }
                print
            }
        ' "$conf" > "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
        if ! cmp -s "$conf" "$tmp"; then
            backup="${conf}.bak_auth_${timestamp}"
            if ! cp -p "$conf" "$backup"; then
                rm -f "$tmp"
                return 1
            fi
            if ! cp "$tmp" "$conf"; then
                cp -p "$backup" "$conf" 2>/dev/null || true
                rm -f "$tmp"
                return 1
            fi
            printf '%s\t%s\n' "$conf" "$backup" >> "$state_file"
        fi
        rm -f "$tmp"
    done
}

ssh_restore_cloud_auth_dropins() {
    local state_file="$1"
    local conf backup
    [[ -f "$state_file" ]] || return 0
    while IFS=$'\t' read -r conf backup; do
        [[ -n "$conf" && -n "$backup" && -f "$backup" ]] || continue
        cp -p "$backup" "$conf" 2>/dev/null || true
    done < "$state_file"
}

ssh_assert_auth_mode_effective() {
    local mode="$1"
    local expected effective
    expected="yes"
    [[ "$mode" == "key_only" ]] && expected="no"
    effective=$(ssh_effective_setting PasswordAuthentication)
    [[ -z "$effective" ]] && return 0
    if [[ "$effective" != "$expected" ]]; then
        echo -e "${RED}❌ SSH 最终生效值仍为 PasswordAuthentication ${effective}，可能有更早的云镜像子配置覆盖。${PLAIN}"
        return 1
    fi
}

ssh_rollback_port_change() {
    local backup_file="$1"
    local current_port="$2"
    local socket_managed="${3:-false}"
    cp -p "$backup_file" /etc/ssh/sshd_config 2>/dev/null || true
    ssh_write_sshd_port_dropin "$current_port" >/dev/null 2>&1 || true
    if $socket_managed; then
        ssh_write_socket_port_dropins "$current_port" >/dev/null 2>&1 || true
        ssh_restart_socket_units >/dev/null 2>&1 || true
    fi
    ssh_service_restart >/dev/null 2>&1 || true
}

ssh_effective_setting() {
    local key="$1"
    local sshd_bin value
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    if [[ -n "$sshd_bin" ]]; then
        ssh_prepare_runtime_dir >/dev/null 2>&1 || true
        value=$("$sshd_bin" -T 2>/dev/null | awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" '$1 == k {print $2; exit}')
        [[ -n "$value" ]] || return 1
        printf '%s' "$value"
        return 0
    fi
    return 1
}

ssh_public_key_is_valid() {
    local key="$1"
    [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]]
}

ssh_user_home() {
    local user="$1"
    getent passwd "$user" 2>/dev/null | awk -F: '{print $6; exit}'
}

ssh_authorized_keys_path() {
    local user="$1"
    local home_dir
    home_dir=$(ssh_user_home "$user")
    [[ -n "$home_dir" ]] || return 1
    printf '%s/.ssh/authorized_keys' "$home_dir"
}

ssh_authorized_key_count() {
    local user="$1"
    local key_file
    key_file=$(ssh_authorized_keys_path "$user" 2>/dev/null) || { echo 0; return 0; }
    [[ -r "$key_file" ]] || { echo 0; return 0; }
    grep -E '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-|sk-)' "$key_file" 2>/dev/null | wc -l | awk '{print $1}'
}

ssh_choose_user() {
    local default_user user
    default_user="${SUDO_USER:-root}"
    [[ "$default_user" == "root" || -n "$(getent passwd "$default_user" 2>/dev/null)" ]] || default_user="root"
    user=$(ask_with_default "目标 Linux 用户" "$default_user")
    if ! getent passwd "$user" >/dev/null 2>&1; then
        echo -e "${RED}❌ 用户 ${user} 不存在。${PLAIN}" >&2
        return 1
    fi
    printf '%s' "$user"
}

ssh_add_public_key_for_user() {
    local user="$1"
    local ssh_key key_file ssh_dir home_dir
    home_dir=$(ssh_user_home "$user")
    [[ -n "$home_dir" ]] || return 1
    key_file="${home_dir}/.ssh/authorized_keys"
    ssh_dir="${home_dir}/.ssh"
    echo -e "👇 ${CYAN}请粘贴 ${user} 的 SSH 公钥，粘贴后按回车：${PLAIN}"
    read -r ssh_key
    if [[ -z "$ssh_key" ]]; then
        echo -e "${RED}❌ 输入为空，已取消。${PLAIN}"
        return 1
    fi
    if ! ssh_public_key_is_valid "$ssh_key"; then
        echo -e "${RED}❌ 公钥格式无效。支持 ssh-rsa、ssh-ed25519、ecdsa、FIDO2 sk-*。${PLAIN}"
        return 1
    fi
    mkdir -p "$ssh_dir" || return 1
    touch "$key_file" || return 1
    chmod 700 "$ssh_dir"
    chmod 600 "$key_file"
    if [[ "$user" != "root" ]]; then
        chown -R "$user:$user" "$ssh_dir" 2>/dev/null || true
    fi
    if grep -q -F -x "$ssh_key" "$key_file"; then
        echo -e "${YELLOW}⚠️ 该公钥已存在，无需重复添加。${PLAIN}"
        return 0
    fi
    printf '%s\n' "$ssh_key" >> "$key_file"
    echo -e "${GREEN}✅ 已为 ${user} 添加 SSH 公钥。${PLAIN}"
}

ssh_apply_auth_mode() {
    local mode="$1"
    local label backup_file tmp_file sshd_bin interactive_key auth_dropin auth_dropin_backup auth_reconcile_state timestamp reconciled_count
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    [[ -n "$sshd_bin" && -f /etc/ssh/sshd_config ]] || {
        echo -e "${RED}❌ 未找到 sshd 或 /etc/ssh/sshd_config，已取消。${PLAIN}"
        return 1
    }
    if ! ssh_prepare_runtime_dir; then
        echo -e "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}"
        return 1
    fi
    case "$mode" in
        key_only) label="仅密钥登录（禁用密码）" ;;
        key_preferred) label="密钥优先（保留密码）" ;;
        password) label="恢复密码登录" ;;
        *) return 1 ;;
    esac
    confirm_risk_action "切换 SSH 登录模式：${label}" \
        "/etc/ssh/sshd_config 与 /etc/ssh/sshd_config.d 登录认证配置" \
        "使用本菜单恢复密码登录，或从自动备份恢复 /etc/ssh/sshd_config 与对应子配置备份" \
        "会同步处理 50-cloud-init.conf 等云镜像子配置；切到仅密钥登录前，必须先确认新 SSH 窗口能用私钥登录。" || return 1

    timestamp=$(date +%s)
    interactive_key="KbdInteractiveAuthentication"
    if ! "$sshd_bin" -T 2>/dev/null | grep -qi '^kbdinteractiveauthentication '; then
        interactive_key="ChallengeResponseAuthentication"
    fi
    auth_dropin="/etc/ssh/sshd_config.d/00-vps-optimize-auth.conf"
    auth_dropin_backup=""
    auth_reconcile_state=$(mktemp /tmp/vps-sshd-reconcile.XXXXXX) || return 1
    backup_file="/etc/ssh/sshd_config.bak_auth_${timestamp}"
    cp -p /etc/ssh/sshd_config "$backup_file" || {
        echo -e "${RED}❌ SSH 配置备份失败，已取消。${PLAIN}"
        rm -f "$auth_reconcile_state"
        return 1
    }
    if [[ -f "$auth_dropin" ]]; then
        auth_dropin_backup="${auth_dropin}.bak_auth_${timestamp}"
        cp -p "$auth_dropin" "$auth_dropin_backup" || {
            echo -e "${RED}❌ SSH drop-in 配置备份失败，已取消。${PLAIN}"
            rm -f "$auth_reconcile_state"
            return 1
        }
    fi
    tmp_file=$(mktemp /tmp/vps-sshd.XXXXXX) || { rm -f "$auth_reconcile_state"; return 1; }
    awk '
        /^# VPS-Optimize SSH auth mode begin$/ {skip=1; next}
        /^# VPS-Optimize SSH auth mode end$/ {skip=0; next}
        skip != 1 {print}
    ' /etc/ssh/sshd_config > "$tmp_file" || {
        rm -f "$tmp_file"
        rm -f "$auth_reconcile_state"
        return 1
    }
    {
        echo "# VPS-Optimize SSH auth mode begin"
        echo "PubkeyAuthentication yes"
        case "$mode" in
            key_only)
                echo "PasswordAuthentication no"
                echo "${interactive_key} no"
                ;;
            key_preferred|password)
                echo "PasswordAuthentication yes"
                echo "${interactive_key} yes"
                ;;
        esac
        echo "# VPS-Optimize SSH auth mode end"
        cat "$tmp_file"
    } > /etc/ssh/sshd_config
    rm -f "$tmp_file"

    if ! ssh_write_auth_dropin "$mode" "$interactive_key"; then
        echo -e "${RED}❌ 写入 SSH drop-in 登录配置失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        rm -f "$auth_reconcile_state"
        return 1
    fi

    if ! ssh_reconcile_cloud_auth_dropins "$mode" "$auth_reconcile_state" "$timestamp"; then
        echo -e "${RED}❌ 处理云镜像 SSH 子配置失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi

    if ! "$sshd_bin" -t; then
        echo -e "${RED}❌ SSH 配置语法检查失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi
    if ! ssh_assert_auth_mode_effective "$mode"; then
        echo -e "${RED}❌ SSH 登录模式未真正生效，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi
    if ! ssh_restart_runtime; then
        echo -e "${RED}❌ SSH 服务重启失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        ssh_restart_runtime >/dev/null 2>&1 || true
        rm -f "$auth_reconcile_state"
        return 1
    fi
    echo -e "${GREEN}✅ SSH 登录模式已切换为：${label}${PLAIN}"
    echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
    reconciled_count=$(wc -l < "$auth_reconcile_state" 2>/dev/null | awk '{print $1}')
    if [[ "$reconciled_count" =~ ^[0-9]+$ && "$reconciled_count" -gt 0 ]]; then
        echo -e "${CYAN}已同步 ${reconciled_count} 个云镜像 SSH 子配置，例如 50-cloud-init.conf。${PLAIN}"
    fi
    rm -f "$auth_reconcile_state"
}

func_ssh_login_mode_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "SSH 安全中心 > 用户密钥登录模式"
        echo -e "${BOLD}🔐 用户密钥登录模式${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "PubkeyAuthentication      : ${CYAN}$(ssh_effective_setting PubkeyAuthentication || echo 未知)${PLAIN}"
        echo -e "PasswordAuthentication    : ${CYAN}$(ssh_effective_setting PasswordAuthentication || echo 未知)${PLAIN}"
        echo -e "KbdInteractiveAuthentication: ${CYAN}$(ssh_effective_setting KbdInteractiveAuthentication || echo 未知)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 为用户添加 SSH 公钥${PLAIN}"
        echo -e "${GREEN}  2. 密钥优先，保留密码登录${PLAIN}"
        echo -e "${RED}  3. 仅密钥登录，禁用密码登录${PLAIN}"
        echo -e "${YELLOW}  4. 恢复密码登录${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice user key_count
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                user=$(ssh_choose_user) || { pause_return; continue; }
                ssh_add_public_key_for_user "$user"
                pause_return
                ;;
            2) ssh_apply_auth_mode key_preferred; pause_return ;;
            3)
                user=$(ssh_choose_user) || { pause_return; continue; }
                key_count=$(ssh_authorized_key_count "$user")
                if [[ "$key_count" -eq 0 ]]; then
                    echo -e "${RED}❌ 用户 ${user} 还没有 authorized_keys，不能切到仅密钥登录。${PLAIN}"
                    echo -e "${YELLOW}请先用本菜单 [1] 添加公钥，并用新 SSH 窗口测试成功。${PLAIN}"
                    pause_return
                    continue
                fi
                echo -e "${YELLOW}检测到 ${user} 已有 ${key_count} 条公钥。切换后密码登录会被禁用。${PLAIN}"
                ssh_apply_auth_mode key_only
                pause_return
                ;;
            4) ssh_apply_auth_mode password; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_ssh_security_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "SSH 安全中心"
        echo -e "${BOLD}🛡️ SSH 安全中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 修改 SSH 端口${PLAIN}             ${YELLOW}(防失联校验和回滚)${PLAIN}"
        echo -e "${GREEN}  2. 用户密钥登录模式${PLAIN}         ${YELLOW}(添加公钥 / 禁用或恢复密码登录)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) func_security ;;
            2) func_ssh_login_mode_menu ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_security() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ SSH 安全加固 (端口修改与防失联)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：该脚本将修改 SSH 端口并配置防失联机制，确保服务稳定。${PLAIN}"
    echo -e "------------------------------------------------"
    
    # 1. 极致精准：读取内存和进程，获取当前真实生效的 SSH 端口
    local current_p sshd_bin
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    if [[ -z "$current_p" && -n "$sshd_bin" ]]; then
        ssh_prepare_runtime_dir >/dev/null 2>&1 || true
        current_p=$("$sshd_bin" -T 2>/dev/null | grep -i "^port " | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}

    local final_p
    # 交互提示优化：引导用户使用高位端口避开特权冲突
    read_trimmed final_p "👉 当前生效的 SSH 端口为 $current_p, 请输入新端口 [10000-65535] (回车保持不变): "
    final_p=${final_p:-$current_p}

    if [[ "$final_p" != "$current_p" ]]; then
        if [[ -z "$sshd_bin" ]]; then
            echo -e "${RED}❌ 未找到 sshd 命令，无法安全校验 SSH 配置，已取消。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! command -v systemctl >/dev/null 2>&1; then
            echo -e "${RED}❌ 未检测到 systemctl，无法安全重启 SSH 服务，已取消。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! ssh_prepare_runtime_dir; then
            echo -e "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        # [严格检验] 端口合法性
        if ! [[ "$final_p" =~ ^[0-9]+$ ]] || (( 10#$final_p < 10000 || 10#$final_p > 65535 )); then
            echo -e "${RED}❌ 错误：无效的端口号！必须是 10000-65535 之间的纯数字。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${YELLOW}即将修改：/etc/ssh/sshd_config、/etc/ssh/sshd_config.d、SSH systemd socket/服务、系统防火墙放行规则。${PLAIN}"
        echo -e "${YELLOW}请先确认云厂商安全组已经放行 ${final_p}/tcp，并保留当前 SSH 会话。${PLAIN}"
        confirm_danger "修改 SSH 端口为 ${final_p}" "新端口未放行会导致后续无法重新连接 SSH。" "脚本会先备份 sshd_config，校验语法失败或服务重启失败时自动回滚。" || {
            echo -e "${BLUE}已取消 SSH 端口修改。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        }

        echo -e "${CYAN}▶ 正在备份原生 SSH 配置文件...${PLAIN}"
        local backup_file="/etc/ssh/sshd_config.bak_$(date +%s)"
        if ! cp -p /etc/ssh/sshd_config "$backup_file"; then
            echo -e "${RED}❌ SSH 配置备份失败，已取消修改。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 2. 核心黑科技：安全的置顶替换
        # - 先安全删除所有带 Port 的行 (忽略注释符和空格)
        # - 然后在文件绝对第一行 (1i) 插入新端口，秒杀所有 include 配置覆盖！
        if ! sed -i '/^[[:space:]]*#\?Port /d' /etc/ssh/sshd_config || ! sed -i "1i Port $final_p" /etc/ssh/sshd_config; then
            echo -e "${RED}❌ 写入 SSH 配置失败，正在恢复备份。${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! ssh_write_sshd_port_dropin "$final_p"; then
            echo -e "${RED}❌ 写入 SSH drop-in 端口配置失败，正在恢复备份。${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 3. [CentOS 专属] SELinux 放行
        if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
            echo -e "${YELLOW}检测到 SELinux 开启，正在配置底层端口安全策略...${PLAIN}"
            if command -v semanage >/dev/null 2>&1; then
                semanage port -a -t ssh_port_t -p tcp "$final_p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$final_p" 2>/dev/null
            else
                echo -e "${RED}❌ 致命错误：缺少 semanage 工具！已触发安全回滚。${PLAIN}"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi

        # 4. 防失联核心：验证新配置语法
        if ! "$sshd_bin" -t; then
            echo -e "${RED}❌ 致命错误：SSH 配置存在语法异常！正在全盘恢复...${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        
        # 5. 放行全栈防火墙
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_p"/tcp >/dev/null 2>&1; fi
        if command -v firewall-cmd >/dev/null 2>&1; then 
            firewall-cmd --permanent --add-port="$final_p"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT -p tcp --dport "$final_p" -j ACCEPT 2>/dev/null || true
        fi
        
        # 6. systemd Socket 端口接管：兼容 Ubuntu/Debian 云镜像的 ssh.socket 与 sshd.socket
        local socket_managed=false socket_units
        socket_units=$(ssh_socket_units_for_host | tr '\n' ' ')
        if [[ -n "$socket_units" ]]; then
            echo -e "${YELLOW}检测到 SSH socket (${socket_units})，正在同步底层监听端口...${PLAIN}"
            if ssh_write_socket_port_dropins "$final_p"; then
                socket_managed=true
                systemctl daemon-reload >/dev/null 2>&1 || true
            else
                echo -e "${RED}❌ 写入 SSH socket drop-in 失败，正在回滚。${PLAIN}"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi
        
        # 7. 严格隔离的服务重启逻辑
        echo -e "${CYAN}▶ 正在重启底层 SSH 引擎...${PLAIN}"
        local restart_ok=false
        if $socket_managed; then
            if ssh_restart_socket_units; then
                restart_ok=true
                ssh_service_restart >/dev/null 2>&1 || true
            fi
        else
            ssh_service_restart && restart_ok=true
        fi
        
        if $restart_ok; then
            echo -e "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行！${PLAIN}"
            echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
        else
            echo -e "${RED}❌ 致命错误：重启 SSH 服务失败！正在回滚至原端口...${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" "$socket_managed"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
        echo -e "${YELLOW}⚠️ 终极保命提示：${PLAIN}"
        echo -e "现在的这扇 SSH 窗口【千万不要关闭】！"
        echo -e "请立刻使用新端口 $final_p 新建一个连接进行测试。"
        echo -e "如果云平台有【安全组】，请确保也已放行 $final_p 端口！"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
    else
        echo -e "${BLUE}端口未做更改。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增：Fail2ban 防爆破系统管理 (抽象精简版)
# ---------------------------------------------------------
func_fail2ban() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Fail2ban 防爆破系统管理${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -z "$current_p" ]]; then
        current_p=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}
    
    echo -e "${YELLOW}👉 当前系统检测到的 SSH 端口为: ${GREEN}$current_p${PLAIN}"
    echo -e "------------------------------------------------"
    
    local f2b_status="${RED}未安装${PLAIN}"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_status="${GREEN}已运行${PLAIN}"
        else
            f2b_status="${YELLOW}已停止${PLAIN}"
        fi
    fi
    
    echo -e "当前 Fail2ban 状态: [ $f2b_status ]"
    echo -e "  ${GREEN}1.${PLAIN} 一键安装并配置 Fail2ban ${YELLOW}(自动绑定当前 SSH 端口)${PLAIN}"
    echo -e "  ${BLUE}2.${PLAIN} 更新防护端口 ${YELLOW}(如果您刚改了 SSH 端口，选此项重载)${PLAIN}"
    echo -e "  ${RED}3.${PLAIN} 彻底卸载 Fail2ban"
    echo -e "  ${RED}0.${PLAIN} 返回主菜单"
    echo -e "------------------------------------------------"
    
    local f_choice
    read_trimmed f_choice "👉 请选择操作: "
    
    case $f_choice in
        1|2)
            if [[ "$f_choice" == "1" ]]; then
                echo -e "${CYAN}正在安装 Fail2ban...${PLAIN}"
                if is_debian; then
                    install_pkg fail2ban python3-systemd
                else
                    install_pkg fail2ban
                fi
            fi
            
            if command -v fail2ban-server >/dev/null 2>&1; then
                echo -e "${CYAN}正在写入配置并绑定端口 $current_p ...${PLAIN}"
                local f2b_backend="auto"
                if command -v journalctl >/dev/null 2>&1; then
                    f2b_backend="systemd"
                fi
                cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = $current_p
backend = $f2b_backend
EOF
                systemctl enable fail2ban >/dev/null 2>&1
                systemctl restart fail2ban >/dev/null 2>&1
                if systemctl is-active --quiet fail2ban; then
                    echo -e "${GREEN}✅ Fail2ban 配置完成并已启动！(保护端口: $current_p，日志后端: $f2b_backend)${PLAIN}"
                    echo -e "${YELLOW}💡 规则：10分钟内密码错误5次，自动封禁该IP 24小时。${PLAIN}"
                else
                    echo -e "${RED}❌ Fail2ban 启动失败，正在显示关键日志：${PLAIN}"
                    fail2ban-client -t 2>/dev/null || true
                    journalctl -u fail2ban -n 20 --no-pager 2>/dev/null || true
                fi
            else
                echo -e "${RED}❌ Fail2ban 安装或检测失败，请检查网络源。${PLAIN}"
            fi
            ;;
        3)
            echo -e "${CYAN}正在卸载 Fail2ban...${PLAIN}"
            remove_pkg fail2ban # <--- 核心修改：一句话极简卸载
            quarantine_path /etc/fail2ban "/etc/vps-optimize/quarantine" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ Fail2ban 已卸载，旧配置已隔离到 /etc/vps-optimize/quarantine。${PLAIN}"
            ;;
        0) return ;;
        *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
    esac
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增功能：添加 SSH 公钥登录
# ---------------------------------------------------------
func_add_ssh_key() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 添加 SSH 公钥登录 (免密安全认证)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}使用 SSH 密钥登录不仅免去输密码的烦恼，更能彻底免疫密码爆破！${PLAIN}"
    echo -e "请准备好您的公钥 (通常以 ssh-rsa, ssh-ed25519、ecdsa 或 sk-* 开头)。"
    echo -e "------------------------------------------------"
    local user enable_mode
    user=$(ssh_choose_user) || { read -n 1 -s -r -p "按任意键继续..."; return; }
    if ssh_add_public_key_for_user "$user"; then
        echo -e "${GREEN}✅ 公钥添加完成。请立刻新开一个 SSH 窗口测试私钥登录。${PLAIN}"
        read_trimmed enable_mode "是否同时写入“密钥优先，保留密码登录”模式？(y/N): "
        if [[ "$enable_mode" =~ ^[Yy]$ ]]; then
            ssh_apply_auth_mode key_preferred || true
        fi
        echo -e "${YELLOW}确认私钥登录 100% 成功后，可进入 [5 SSH 安全中心] -> [2 用户密钥登录模式] 禁用密码登录。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 5. Docker 深度管理 (重构版：非破坏性修改与防宕机回滚)
# ---------------------------------------------------------
docker_port_line_is_public() {
    local line="$1"
    case "$line" in
        *"0.0.0.0:"*|*":::"*|*"[::]:"*|*"[0:0:0:0:0:0:0:0]:"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_managed_container_status() {
    local title="$1"
    local container="$2"
    local dir="$3"
    local state health ports compose_file

    if docker inspect "$container" >/dev/null 2>&1; then
        state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container" 2>/dev/null || true)
        ports=$(docker port "$container" 2>/dev/null | tr '\n' '; ')
        [[ -z "$ports" ]] && ports="未暴露 Docker 端口或使用 host 网络"
        [[ -z "$health" ]] && health="无 healthcheck"
        echo -e "${GREEN}${title}${PLAIN}: ${state} / ${health}"
        echo -e "  端口: ${ports}"
    else
        echo -e "${YELLOW}${title}${PLAIN}: 未检测到容器 ${container}"
    fi

    compose_file=$(find_compose_file "$dir" 2>/dev/null || true)
    if [[ -n "$compose_file" ]]; then
        echo -e "  Compose: ${CYAN}${compose_file}${PLAIN}"
    else
        echo -e "  Compose: ${BLUE}未检测到 ${dir} 部署目录${PLAIN}"
    fi
}

print_subscription_compose_status() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}未安装 Docker，跳过订阅工具容器状态。${PLAIN}"
        return 0
    fi
    print_managed_container_status "SublinkPro" "sublinkpro" "/opt/sublinkpro"
    print_managed_container_status "妙妙屋订阅管理" "miaomiaowu" "/opt/miaomiaowu"
    print_managed_container_status "Sub-Store" "sub-store" "/opt/sub-store"
    print_managed_container_status "Dockge" "dockge" "/opt/dockge"
    print_managed_container_status "Komari" "komari" "/opt/komari"
}

func_docker_project_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "Docker 安全管理 > 项目容器状态"
    echo -e "${BOLD}🐳 443 / 订阅工具相关容器状态${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}这里只看本项目场景相关容器：SublinkPro、妙妙屋、Sub-Store、Dockge、Komari。${PLAIN}"
    echo -e "${YELLOW}3x-ui、Caddy、Nginx 通常是 systemd 服务，状态请看 [15] 或 [19] 体检。${PLAIN}"
    echo -e "------------------------------------------------"
    print_subscription_compose_status
    echo -e "------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回..."
}

func_docker_443_exposure_audit() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "Docker 安全管理 > 443 暴露审计"
    echo -e "${BOLD}🔎 Docker 端口暴露审计${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}目标：启用 443 单入口后，订阅工具和管理面板应尽量只绑定 127.0.0.1，再由 Caddy/Nginx 对外。${PLAIN}"
    echo -e "------------------------------------------------"

    local found_public=false
    local line name ports
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        ports=$(docker port "$name" 2>/dev/null || true)
        [[ -z "$ports" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if docker_port_line_is_public "$line"; then
                found_public=true
                echo -e "${YELLOW}⚠️ ${name}: ${line}${PLAIN}"
            fi
        done <<< "$ports"
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)

    if $found_public; then
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}建议：订阅工具、Dockge、Komari 用 127.0.0.1 绑定，公网访问走 [19] -> [8] 添加 443 反代域名。${PLAIN}"
        echo -e "${YELLOW}如确实需要公网直连，请确认云安全组、系统防火墙和访问密码都已收紧。${PLAIN}"
    else
        echo -e "${GREEN}✅ 未发现 Docker 容器通过 0.0.0.0 / :: 直接暴露端口。${PLAIN}"
    fi

    echo -e "------------------------------------------------"
    print_subscription_compose_status
    echo -e "------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回..."
}

func_docker_manage() {
    if ! command -v docker >/dev/null 2>&1; then 
        clear
        echo -e "${RED}❌ 错误：检测到系统尚未安装 Docker 引擎！${PLAIN}"
        echo -e "${YELLOW}💡 请先在主菜单进入 [3 基础组件与常用服务] 安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 确保依赖工具存在 (使用我们抽象的 install_pkg)
    if ! command -v jq >/dev/null 2>&1; then install_pkg jq; fi

    while true; do
        clear
        local docker_ver
        docker_ver=$(docker -v | awk '{print $3}' | tr -d ',')
        
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "Docker 安全管理"
        echo -e "${BOLD}🐳 Docker 安全管理 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 开启 Docker 本地防穿透${PLAIN} ${YELLOW}(限制映射端口仅 127.0.0.1 访问)${PLAIN}"
        echo -e "${GREEN}  2. 解除 Docker 本地防穿透${PLAIN} ${YELLOW}(恢复全网可访，不破坏原配置)${PLAIN}"
        echo -e "${GREEN}  3. 查看 443 / 订阅工具容器状态${PLAIN}"
        echo -e "${GREEN}  4. Docker 端口暴露审计${PLAIN} ${YELLOW}(检查是否绕过 443 单入口)${PLAIN}"
        echo -e "${BOLD}${YELLOW}  5. UPD 更新订阅工具容器${PLAIN} ${CYAN}(SublinkPro / 妙妙屋 / Sub-Store)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        
        local c
        read_trimmed c "👉 请选择操作: "
        case $c in
            1) 
                confirm_risk_action "开启 Docker 本地防穿透" \
                    "Docker daemon.json 和 Docker 服务重启" \
                    "使用自动备份的 daemon.json 恢复并重启 Docker" \
                    "确认现有容器不依赖公网直连映射端口。" || { echo -e "${BLUE}已取消操作。${PLAIN}"; sleep 1; continue; }
                echo -e "${CYAN}▶ 正在配置 Docker 安全策略...${PLAIN}"
                mkdir -p /etc/docker
                local conf_file="/etc/docker/daemon.json"
                local backup_file="${conf_file}.bak_$(date +%s)"
                local tmp_json
                tmp_json=$(mktemp /tmp/docker-daemon.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败，已取消操作。${PLAIN}"; sleep 1; continue; }
                
                # 检查并备份
                if [[ -f "$conf_file" ]]; then
                    if ! cp -p "$conf_file" "$backup_file"; then
                        echo -e "${RED}❌ Docker 配置备份失败，已取消操作。${PLAIN}"
                        rm -f "$tmp_json"
                        sleep 1
                        continue
                    fi
                    echo -e "${YELLOW}⚠️ 已备份原有配置至 $backup_file${PLAIN}"
                    
                    # 使用 jq 进行非破坏性合并，保留用户原有配置
                    if ! jq '. + {"ip": "127.0.0.1", "log-driver": "json-file", "log-opts": {"max-size": "50m", "max-file": "3"}}' "$conf_file" > "$tmp_json" 2>/dev/null; then
                        echo -e "${RED}❌ 原 daemon.json 格式损坏，合并失败！操作中止。${PLAIN}"
                        rm -f "$tmp_json"
                        echo -e "${YELLOW}备份已保留：$backup_file${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    mv "$tmp_json" "$conf_file"
                else
                    # 文件不存在时初始生成
                    cat <<EOF > "$conf_file"
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
                fi
                
                # 防宕机重启机制：如果新配置导致引擎崩溃，立刻回滚！
                if systemctl restart docker >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ 已开启安全保护，Docker 容器端口仅限本地反代访问！${PLAIN}"
                    [[ -f "$backup_file" ]] && echo -e "${CYAN}Docker 配置备份已保留：$backup_file${PLAIN}"
                else
                    echo -e "${RED}❌ 致命错误：新配置导致 Docker 引擎无法启动！正在自动回滚...${PLAIN}"
                    if [[ -f "$backup_file" ]]; then
                        mv "$backup_file" "$conf_file"
                    else
                        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/docker" >/dev/null 2>&1 || true
                    fi
                    systemctl restart docker >/dev/null 2>&1
                fi
                sleep 2
                ;;
            2) 
                local conf_file="/etc/docker/daemon.json"
                if [[ -f "$conf_file" ]]; then
                    confirm_risk_action "解除 Docker 本地防穿透" \
                        "Docker daemon.json 和 Docker 服务重启" \
                        "使用自动备份的 daemon.json 恢复并重启 Docker" \
                        "解除后容器映射端口可能重新公网可达，请确认防火墙和云安全组。" || { echo -e "${BLUE}已取消操作。${PLAIN}"; sleep 1; continue; }
                    echo -e "${CYAN}▶ 正在安全移除 Docker 端口限制...${PLAIN}"
                    local backup_file="${conf_file}.bak_$(date +%s)"
                    local tmp_json
                    tmp_json=$(mktemp /tmp/docker-daemon.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败，已取消操作。${PLAIN}"; sleep 1; continue; }
                    if ! cp -p "$conf_file" "$backup_file"; then
                        echo -e "${RED}❌ Docker 配置备份失败，已取消操作。${PLAIN}"
                        rm -f "$tmp_json"
                        sleep 1
                        continue
                    fi

                    # 核心修复：只精准删除 ip 限制，绝不误删国内镜像源等其他配置！
                    if ! jq 'del(.ip)' "$conf_file" > "$tmp_json" 2>/dev/null; then
                        echo -e "${RED}❌ JSON 解析失败，操作中止。${PLAIN}"
                        rm -f "$tmp_json"
                        echo -e "${YELLOW}备份已保留：$backup_file${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    mv "$tmp_json" "$conf_file"

                    if systemctl restart docker >/dev/null 2>&1; then
                        echo -e "${GREEN}✅ 已解除限制，容器端口恢复公网可访状态！${PLAIN}"
                        echo -e "${CYAN}Docker 配置备份已保留：$backup_file${PLAIN}"
                    else
                        echo -e "${RED}❌ 卸载异常：导致引擎无法启动！正在回滚...${PLAIN}"
                        mv "$backup_file" "$conf_file"
                        systemctl restart docker >/dev/null 2>&1
                    fi
                else
                    echo -e "${BLUE}未检测到限制配置文件，当前已是全网开放状态。${PLAIN}"
                fi
                sleep 2
                ;;
            3) func_docker_project_status ;;
            4) func_docker_443_exposure_audit ;;
            5) func_update_subscription_tools ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
        esac
    done
}
# ---------------------------------------------------------
# 6. BBR 增强管理
# ---------------------------------------------------------
func_bbr_manage() {
    clear
    echo -e "${CYAN}👉 正在调用 ylx2016 网络极速脚本...${PLAIN}"
    run_remote_script "运行 ylx2016 网络极速脚本" "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (修复版：放宽正则以兼容多值与特殊符号)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚀 动态 TCP 极致调优 (Omnitt)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "👉 推荐浏览器访问: ${BLUE}https://omnitt.com/${PLAIN} 获取针对您网络的定制参数"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "❓ 准备好粘贴参数了吗？(y 继续 / n 取消): "
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then return; fi
    
    local temp_f="/etc/sysctl.d/99-omnitt-tune.conf"
    local backup_f="${temp_f}.bak_$(date +%s)"
    
    # 事务起点：备份原配置
    if [[ -f "$temp_f" ]]; then
        cp "$temp_f" "$backup_f"
    fi
    
    > "$temp_f"
    echo -e "\n${YELLOW}👇 请在下方直接【右键粘贴】代码。${PLAIN}"
    echo -e "${YELLOW}💡 粘贴完成后，请按下【回车键】，然后输入 ${RED}EOF${YELLOW} 并再次回车保存：${PLAIN}"
    
    local has_content=false
    while IFS= read -r line; do
        # 极简清洗：去除回车符和前后多余空格
        line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        
        # 结束符匹配（忽略大小写）
        if [[ "${line,,}" == "eof" ]]; then
            break
        fi
        
        # 【核心修复】：放宽等号右侧的值校验，允许包含空格(如 tcp_rmem) 和特殊符号(如 %)
        if [[ -z "$line" || "$line" =~ ^# || "$line" =~ ^[a-zA-Z0-9_.-]+[[:space:]]*=[[:space:]]*.+$ ]]; then
            echo "$line" >> "$temp_f"
            # 标记确实写入了有效参数，而不是只敲了几个回车
            [[ -n "$line" && ! "$line" =~ ^# ]] && has_content=true
        else
            echo -e "${RED}⚠️ 已自动过滤非法参数行: $line${PLAIN}"
        fi
    done
    
    if $has_content; then
        echo -e "${CYAN}▶ 正在校验并应用新 TCP 参数...${PLAIN}"
        # 验证新配置是否被内核完全接受
        if sysctl -p "$temp_f" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 动态 TCP 调优参数应用成功！网络吞吐量已提升。${PLAIN}"
            rm -f "$backup_f" # 成功则删除备份
        else
            echo -e "${RED}❌ 致命错误：您粘贴的部分参数当前内核不支持或语法错误！${PLAIN}"
            echo -e "${YELLOW}正在触发安全回滚...${PLAIN}"
            if [[ -f "$backup_f" ]]; then
                mv "$backup_f" "$temp_f"
                sysctl -p "$temp_f" >/dev/null 2>&1
            else
                rm -f "$temp_f"
            fi
            echo -e "${BLUE}✅ 已恢复系统原 TCP 状态，未造成任何破坏。${PLAIN}"
        fi
    else
        echo -e "${YELLOW}⚠️ 未检测到有效的 TCP 调优参数，操作已取消。${PLAIN}"
        if [[ -f "$backup_f" ]]; then mv "$backup_f" "$temp_f"; else rm -f "$temp_f"; fi
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 8. 智能内存调优 (重构版：安全接管与 DRY 化)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    local mem
    mem=$(free -m | awk '/^Mem:/{print $2}')
    echo -e "${CYAN}💡 硬件自适应调优 (检测到本机 ${mem}MB 物理内存)${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e " ${GREEN}1. 激进档 (适合 1G 以下小鸡)${PLAIN}"
    echo -e "    - ZRAM 100% 压缩, Swappiness=100。全力防止宕机。"
    echo -e " ${GREEN}2. 积极档 (适合 2-4G 主流机型)${PLAIN}"
    echo -e "    - ZRAM 70% 压缩, Swappiness=60。平衡性能与空间。"
    echo -e " ${GREEN}3. 保守档 (适合 8G 以上性能怪兽)${PLAIN}"
    echo -e "    - ZRAM 25% 压缩, Swappiness=10。追求极致响应速度。"
    echo -e "------------------------------------------------"
    
    local choice
    read_trimmed choice "👉 请选择您的调优挡位 [1/2/3] (直接回车按内存自动匹配): "
    
    if [[ -z "$choice" ]]; then
        if [[ "$mem" -lt 1024 ]]; then choice=1
        elif [[ "$mem" -le 4096 ]]; then choice=2
        else choice=3
        fi
        echo -e "${YELLOW}💡 系统已根据本机内存 (${mem}MB) 自动选择：[ 挡位 $choice ]${PLAIN}"
        sleep 1.5
    fi
    
    # 提早阻断，避免非 Debian 机器运行破坏性 Swap 卸载指令
    if ! is_debian; then
        echo -e "${RED}❌ 抱歉，当前系统并非 Debian/Ubuntu 衍生系，暂不支持自动化 ZRAM 调优。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${CYAN}▶ 正在进行第一阶段：整理底层磁盘 Swap (保留 512M 保底防假死)...${PLAIN}"
    
    swapoff -a >/dev/null 2>&1
    local old_swap
    for old_swap in /swapfile /swap.img /var/swap /var/swapfile; do
        quarantine_path "$old_swap" "/root/vps-optimize-quarantine/swap" >/dev/null 2>&1 || true
    done
    
    dd if=/dev/zero of=/swapfile bs=1M count=512 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1
    
    sed -i -E 's/^([^#].*[[:space:]]swap[[:space:]].*)/#\1/' /etc/fstab
    sed -i '\@^/swapfile@d' /etc/fstab
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo -e "${GREEN}✅ 已建立 512M 极小磁盘 Swap 作为系统崩溃的最后防线！${PLAIN}"
    
    echo -e "${CYAN}▶ 正在进行第二阶段：配置 ZRAM 内存压缩引擎...${PLAIN}"
    
    # 核心修改：使用全局包安装器
    install_pkg zram-tools
    modprobe zram >/dev/null 2>&1
    
    local zram_conf="/etc/default/zramswap"
    local percent=70
    local swap_val=60
    
    case $choice in
        1) percent=100; swap_val=100 ;;
        2) percent=70; swap_val=60 ;;
        3) percent=25; swap_val=10 ;;
        *) percent=70; swap_val=60 ;;
    esac
    
    cat <<EOF > "$zram_conf"
ALGO=zstd
PERCENT=$percent
PRIORITY=100
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1
    systemctl restart zramswap >/dev/null 2>&1
    
    if ! grep -q zram /proc/swaps; then
        if command -v zramswap >/dev/null 2>&1; then
            zramswap start >/dev/null 2>&1
        elif [[ -x /usr/sbin/zramswap ]]; then
            /usr/sbin/zramswap start >/dev/null 2>&1
        fi
    fi
    
    echo "vm.swappiness = $swap_val" > /etc/sysctl.d/99-zram-swappiness.conf
    sysctl -p /etc/sysctl.d/99-zram-swappiness.conf >/dev/null 2>&1
    
if grep -q zram /proc/swaps; then
        echo -e "${GREEN}✅ ZRAM 调优落地完成！(已设置: ${percent}% 压缩比, ${swap_val} 交换倾向)${PLAIN}"
    else
        echo -e "${RED}❌ 警告：内核拒绝挂载 ZRAM (常见于 LXC/OpenVZ 架构)。${PLAIN}"
        echo -e "${CYAN}▶ 正在启动降级优化方案：传统 Swap 扩容与内核防假死调优...${PLAIN}"
        
        # 1. 扩容保底 Swap：从 512M 升级至 1024M (1GB)
        swapoff /swapfile >/dev/null 2>&1
        quarantine_path /swapfile "/root/vps-optimize-quarantine/swap" >/dev/null 2>&1 || true
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        
        # 2. 注入降级专属的内核内存管理参数
        # swappiness=30 : 只有内存比较吃紧时才使用较慢的磁盘 Swap
        # vfs_cache_pressure=50 : 降低系统回收目录/文件系统缓存的频率，提高小鸡流畅度
        # overcommit_memory=1 : 允许内核分配超过物理内存的空间，防止 Redis/数据库 等服务在启动时被直接 Kill
        cat <<EOF > /etc/sysctl.d/99-fallback-mem.conf
vm.swappiness = 30
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
EOF
        sysctl -p /etc/sysctl.d/99-fallback-mem.conf >/dev/null 2>&1
        
        echo -e "${GREEN}✅ 降级优化落地：已动态扩充 1GB 磁盘 Swap，并激活保守内存回收策略！${PLAIN}"
    fi
    
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 9. 安装/切换优化内核 (Cloud/KVM 稳定优先 + XanMod 高级可选)
# ---------------------------------------------------------
normalize_kernel_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "unknown" ;;
    esac
}

apt_pkg_available() {
    local pkg="$1"
    apt-cache show "$pkg" >/dev/null 2>&1
}

set_grub_default_kernel_by_keyword() {
    local kernel_keyword="$1"
    local target_v menu_1 menu_2

    if ! command -v dpkg >/dev/null 2>&1 || [[ ! -f /etc/default/grub ]]; then
        echo -e "${YELLOW}⚠️ 未检测到 dpkg/GRUB 配置，已跳过自动接管引导。${PLAIN}"
        return 0
    fi

    target_v=$(dpkg -l | awk '/^ii[[:space:]]+linux-image-[0-9]/ && /'"$kernel_keyword"'/ {print $2}' | sed 's/linux-image-//' | sort -V | tail -n 1)
    if [[ -z "$target_v" ]]; then
        echo -e "${RED}❌ 错误：未找到已安装的 ${kernel_keyword} 内核包，请检查安装日志。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在接管 GRUB 底层引导，锁定启动内核为: $target_v ...${PLAIN}"
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    else
        echo "GRUB_DEFAULT=saved" >> /etc/default/grub
    fi
    grep -q "^GRUB_SAVEDEFAULT=true" /etc/default/grub || echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
    if command -v update-grub >/dev/null 2>&1; then
        update-grub >/dev/null 2>&1
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    fi

    local grub_cfg="/boot/grub/grub.cfg"
    [[ -f "$grub_cfg" ]] || grub_cfg="/boot/grub2/grub.cfg"
    if [[ ! -f "$grub_cfg" ]]; then
        echo -e "${YELLOW}⚠️ 未找到 grub.cfg，新内核已安装，但请重启后手动确认默认启动项。${PLAIN}"
        return 0
    fi

    menu_1=$(grep -i "submenu 'Advanced options for" "$grub_cfg" | cut -d"'" -f2 | head -n 1)
    menu_2=$(grep -i "menuentry '.*$target_v.*'" "$grub_cfg" | grep -iv "recovery" | cut -d"'" -f2 | head -n 1)

    if [[ -n "$menu_1" && -n "$menu_2" ]]; then
        grub-set-default "$menu_1>$menu_2" 2>/dev/null || grub2-set-default "$menu_1>$menu_2" 2>/dev/null || true
        echo -e "${GREEN}✅ GRUB 引导接管成功！重启后将优先进入：$target_v${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}⚠️ 警告：GRUB 菜单寻址失败。系统可能仍以最高版本号内核启动。${PLAIN}"
    return 1
}

install_cloud_kvm_kernel() {
    local arch kernel_keyword="" pkg
    local candidates=()

    if uname -r | grep -qE "kvm|cloud|virtual"; then
        echo -e "${GREEN}✅ 系统当前已运行 KVM/Cloud/Virtual 优化内核 ($(uname -r))，无需重复安装！${PLAIN}"
        return 0
    fi

    arch=$(normalize_kernel_arch)
    if [[ "$arch" == "unknown" ]]; then
        echo -e "${RED}❌ 当前架构 $(uname -m) 暂不支持自动切换精简内核。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在安装发行版官方 Cloud/KVM/Virtual 精简内核...${PLAIN}"
    ensure_minimal_system_compat

    if [[ "$OS" == "debian" ]]; then
        if [[ "$arch" == "amd64" ]]; then
            candidates=("linux-image-cloud-amd64" "linux-image-amd64")
        else
            candidates=("linux-image-cloud-arm64" "linux-image-arm64")
        fi
        kernel_keyword="cloud|${arch}"
    elif [[ "$OS" == "ubuntu" ]]; then
        if [[ "$arch" == "amd64" ]]; then
            candidates=("linux-kvm" "linux-virtual" "linux-generic")
        else
            candidates=("linux-virtual" "linux-generic")
        fi
        kernel_keyword="kvm|virtual|generic"
    else
        echo -e "${RED}❌ Cloud/KVM/Virtual 内核功能目前仅支持 Debian 和 Ubuntu。${PLAIN}"
        return 1
    fi

    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt_update_once || true
        unset DEBIAN_FRONTEND
    fi

    for pkg in "${candidates[@]}"; do
        if ! apt_pkg_available "$pkg"; then
            echo -e "${YELLOW}  - 当前源未提供 ${pkg}，尝试下一个候选...${PLAIN}"
            continue
        fi
        echo -e "${CYAN}▶ 尝试安装内核包: ${pkg}${PLAIN}"
        if install_pkg "$pkg"; then
            echo -e "${GREEN}✅ 已安装内核包: ${pkg}${PLAIN}"
            set_grub_default_kernel_by_keyword "$kernel_keyword"
            return $?
        fi
        echo -e "${YELLOW}  - ${pkg} 安装失败，尝试下一个候选...${PLAIN}"
    done

    echo -e "${RED}❌ 未能安装可用的官方精简内核，请检查系统版本、架构和软件源。${PLAIN}"
    return 1
}

xanmod_cpu_level() {
    local flags level="x64v1"
    flags=$(awk -F: '/flags/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
    if [[ "$flags" =~ avx2 ]] && [[ "$flags" =~ bmi2 ]] && [[ "$flags" =~ fma ]] && [[ "$flags" =~ movbe ]]; then
        level="x64v3"
    fi
    if [[ "$flags" =~ avx512f ]] && [[ "$flags" =~ avx512bw ]] && [[ "$flags" =~ avx512vl ]]; then
        level="x64v4"
    fi
    if [[ "$flags" =~ cx16 ]] && [[ "$flags" =~ lahf_lm ]] && [[ "$flags" =~ popcnt ]] && [[ "$flags" =~ sse4_2 ]]; then
        [[ "$level" == "x64v1" ]] && level="x64v2"
    fi
    echo "$level"
}

xanmod_candidate_packages() {
    local level="${1:-x64v1}"
    case "$level" in
        x64v4) printf '%s\n' linux-xanmod-lts-x64v4 linux-xanmod-x64v4 linux-xanmod-lts-x64v3 linux-xanmod-x64v3 linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        x64v3) printf '%s\n' linux-xanmod-lts-x64v3 linux-xanmod-x64v3 linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        x64v2) printf '%s\n' linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        *) printf '%s\n' linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
    esac
}

xanmod_supported_codename() {
    case "$1" in
        bookworm|trixie|forky|sid|jammy|noble|plucky) return 0 ;;
        *) return 1 ;;
    esac
}

add_xanmod_repo() {
    local codename="$1"
    local key_tmp
    mkdir -p /etc/apt/keyrings
    quarantine_path /etc/apt/keyrings/xanmod-archive-keyring.gpg "/etc/vps-optimize/quarantine/apt-keyrings" >/dev/null 2>&1 || true
    key_tmp=$(mktemp /tmp/xanmod-key.XXXXXX) || return 1
    if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 https://dl.xanmod.org/archive.key -o "$key_tmp"; then
        rm -f "$key_tmp"
        echo -e "${RED}❌ XanMod GPG key 下载失败。${PLAIN}"
        return 1
    fi
    if ! gpg --batch --yes --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg "$key_tmp"; then
        rm -f "$key_tmp"
        echo -e "${RED}❌ XanMod GPG key 下载或写入失败。${PLAIN}"
        return 1
    fi
    rm -f "$key_tmp"
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${codename} main" > /etc/apt/sources.list.d/xanmod-release.list
    apt-get update -qq && APT_UPDATED=1
}

install_xanmod_kernel_package() {
    local preferred_level="$1"
    local pkg
    while IFS= read -r pkg; do
        apt_pkg_available "$pkg" || continue
        echo -e "${CYAN}▶ 尝试安装 XanMod 包: ${pkg}${PLAIN}"
        if install_pkg "$pkg"; then
            echo -e "${GREEN}✅ 已安装 XanMod 内核包: ${pkg}${PLAIN}"
            return 0
        fi
        echo -e "${YELLOW}  - ${pkg} 安装失败，尝试更保守候选...${PLAIN}"
    done < <(xanmod_candidate_packages "$preferred_level")

    return 1
}

install_xanmod_kernel() {
    local codename confirm arch cpu_level

    if uname -r | grep -qi "xanmod"; then
        echo -e "${GREEN}✅ 系统当前已运行 XanMod 内核 ($(uname -r))，无需重复安装！${PLAIN}"
        return 0
    fi

    if ! is_debian; then
        echo -e "${RED}❌ XanMod 自动安装目前仅支持 Debian/Ubuntu 衍生系统。${PLAIN}"
        return 1
    fi

    arch=$(normalize_kernel_arch)
    if [[ "$arch" != "amd64" ]]; then
        echo -e "${RED}❌ XanMod 官方 x64v 内核仅支持 x86_64/amd64，本机为 $(uname -m)。${PLAIN}"
        echo -e "${YELLOW}建议改用官方 Cloud/Virtual 内核。${PLAIN}"
        return 1
    fi

    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi
    if [[ -z "$codename" ]]; then
        echo -e "${RED}❌ 无法识别系统代号，无法安全添加 XanMod 源。${PLAIN}"
        return 1
    fi
    if ! xanmod_supported_codename "$codename"; then
        echo -e "${YELLOW}⚠️ 当前系统代号 ${codename} 可能不在脚本内置 XanMod 兼容列表中。${PLAIN}"
        echo -e "${YELLOW}脚本仍会尝试添加源；若 apt update 失败，请改用官方 Cloud/Virtual 内核。${PLAIN}"
    fi

    cpu_level=$(xanmod_cpu_level)

    echo -e "${RED}⚠️  XanMod 是第三方性能内核，可能影响 DKMS/驱动/部分云厂商兼容性。${PLAIN}"
    echo -e "${YELLOW}检测到 CPU 兼容级别：${cpu_level}，将从对应 XanMod LTS 包开始尝试，并自动向下兜底。${PLAIN}"
    echo -e "${YELLOW}建议先确认有快照、救援控制台，且知道如何从 GRUB 切回旧内核。${PLAIN}"
    confirm_risk_action "安装 XanMod 内核" \
        "内核包、引导配置和 GRUB 菜单" \
        "使用当前可启动内核或云厂商救援模式恢复" \
        "建议先创建 VPS 快照，并确认不是 OpenVZ 老系统。" || { echo -e "${BLUE}已取消 XanMod 安装。${PLAIN}"; return 1; }

    echo -e "${CYAN}▶ 正在添加 XanMod 官方 APT 源并安装兼容内核...${PLAIN}"
    ensure_minimal_system_compat
    install_pkg ca-certificates curl gpg gnupg || return 1
    add_xanmod_repo "$codename" || return 1

    if ! install_xanmod_kernel_package "$cpu_level"; then
        echo -e "${RED}❌ XanMod 内核安装失败，可能是当前系统代号/软件源/CPU 级别暂不兼容。${PLAIN}"
        return 1
    fi

    set_grub_default_kernel_by_keyword "xanmod"
}

func_install_kernel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}☁️  安装/切换优化内核${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${GREEN}  1. Cloud/KVM/Virtual 官方云内核${PLAIN} ${YELLOW}(推荐：稳定、轻量、云厂商兼容更好)${PLAIN}"
    echo -e "     Debian/Ubuntu 会按架构自动尝试 cloud/kvm/virtual/generic 候选。"
    echo -e "${GREEN}  2. XanMod 性能内核${PLAIN} ${YELLOW}(高级：自动匹配 x64v1-v4 并向下兜底)${PLAIN}"
    echo -e "     适合：愿意折腾、追求低延迟/新特性；仅 amd64，建议有快照或救援控制台。"
    echo -e "------------------------------------------------"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local kernel_choice virt
    read_trimmed kernel_choice "👉 请选择要安装的内核类型 [推荐 1]: "
    kernel_choice="${kernel_choice:-1}"
    [[ "$kernel_choice" == "0" ]] && return

    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    if [[ "$virt" =~ lxc|openvz ]]; then
        echo -e "${RED}❌ 致命错误：检测到当前 VPS 为 $virt 容器架构！${PLAIN}"
        echo -e "${YELLOW}💡 容器与母机共享内核，无法更改内核。操作已安全中止。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    local arch
    arch=$(normalize_kernel_arch)
    if [[ "$arch" == "unknown" ]]; then
        echo -e "${RED}❌ 致命错误：当前架构暂不支持自动切换内核，本机为 $(uname -m)！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    if [[ "$kernel_choice" == "2" && "$arch" != "amd64" ]]; then
        echo -e "${RED}❌ XanMod x64v 内核仅支持 x86_64/amd64，本机为 $(uname -m)。${PLAIN}"
        echo -e "${YELLOW}建议选择 [1] 官方 Cloud/KVM/Virtual 内核。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    local install_rc=0
    case "$kernel_choice" in
        1) install_cloud_kvm_kernel ;;
        2) install_xanmod_kernel ;;
        *) echo -e "${RED}❌ 无效选择。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return ;;
    esac
    install_rc=$?
    if [[ "$install_rc" -ne 0 ]]; then
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}⚠️ 内核安装/切换未完成，未继续提示重启。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}⚠️ 核心生效指引：${PLAIN}"
    echo -e "1. 新内核引导已配置完毕，请先选择主菜单的 ${RED}[17] 重启服务器${PLAIN}。"
    echo -e "2. 重启后请运行 ${GREEN}uname -r${PLAIN} 确认实际进入的新内核。"
    echo -e "3. 确认稳定后，再进入本菜单选择 ${GREEN}[5] 清理旧内核${PLAIN}。"

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 10. 清理冗余旧内核 (数组菜单驱动 + 核心防砖拦截版)
# ---------------------------------------------------------
func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    local current_k
    current_k=$(uname -r)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清理冗余旧内核${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "当前正在运行的内核为: ${GREEN}${current_k}${PLAIN}"
    echo -e "${RED}⚠️ 系统已自动为您屏蔽正在运行的内核以及常用云/虚拟化/性能内核。${PLAIN}"
    echo -e "------------------------------------------------"
    
    # 自动提取所有非当前的内核包存入数组 (排除元包，采用高可用字段匹配)
    mapfile -t old_kernels < <(dpkg -l | awk '$1 == "ii" && $2 ~ /^linux-image-[0-9]/ {print $2}' | grep -v "$current_k" | grep -Ev "cloud|kvm|virtual|generic|xanmod")

    if [[ ${#old_kernels[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 系统非常干净，没有发现需要清理的冗余旧内核。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${YELLOW}扫描到以下冗余内核可供清理：${PLAIN}"
    for i in "${!old_kernels[@]}"; do
        echo -e " [${CYAN}$((i+1))${PLAIN}] ${old_kernels[$i]}"
    done
    echo -e " [${RED}0${PLAIN}] 取消并返回"
    echo -e "------------------------------------------------"

    local k_choice
    read_trimmed k_choice "👉 请输入要卸载的序号: "

    if [[ "$k_choice" == "0" ]]; then
        echo -e "${BLUE}已取消卸载操作。${PLAIN}"
    elif [[ "$k_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$k_choice" -le "${#old_kernels[@]}" ]]; then
        local target_k="${old_kernels[$((k_choice-1))]}"
        confirm_danger "卸载旧内核 ${target_k}" "会删除内核包并刷新 GRUB，引导异常时可能影响下次启动。" "建议先创建 VPS 快照；当前运行内核已自动排除，如失败请从快照或救援模式恢复。" || {
            echo -e "${BLUE}已取消卸载操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        }
        echo -e "${CYAN}正在静默卸载 $target_k 并刷新引导...${PLAIN}"
        export DEBIAN_FRONTEND=noninteractive
        if apt-get purge -yq "$target_k" && update-grub >/dev/null 2>&1 && apt-get autoremove --purge -yq >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 旧内核 [$target_k] 清理完成！磁盘空间已释放。${PLAIN}"
        else
            echo -e "${RED}❌ 清理失败！存在依赖问题或执行被中断。${PLAIN}"
        fi
        unset DEBIAN_FRONTEND
    else
        echo -e "${RED}❌ 无效的选择！${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 11. 极速硬件探针
# ---------------------------------------------------------
service_status_compact() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            printf '%b' "${GREEN}运行中${PLAIN}"
        else
            printf '%b' "${YELLOW}未运行${PLAIN}"
        fi
    else
        printf '%b' "${BLUE}未安装${PLAIN}"
    fi
}

service_unit_exists() {
    local svc="$1"
    local units
    units=$(systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null || true)
    [[ -n "$units" ]] && return 0
    systemctl status "$svc" >/dev/null 2>&1
}

xui_panel_installed_by_files() {
    command -v 3x-ui >/dev/null 2>&1 && return 0
    command -v x-ui >/dev/null 2>&1 && return 0
    [[ -x /usr/local/x-ui/x-ui ]] && return 0
    [[ -f /etc/x-ui/x-ui.db || -f /usr/local/x-ui/x-ui.db || -f /usr/local/x-ui/bin/x-ui.db ]] && return 0
    return 1
}

xui_panel_service_name() {
    local svc
    for svc in 3x-ui x-ui x-panel; do
        if service_unit_exists "$svc"; then
            printf '%s' "$svc"
            return 0
        fi
    done
    return 1
}

xui_panel_status_compact() {
    local svc
    if svc=$(xui_panel_service_name); then
        if systemctl is-active --quiet "$svc"; then
            printf '%b' "${GREEN}运行中${PLAIN}"
        else
            printf '%b' "${YELLOW}未运行${PLAIN}"
        fi
    elif xui_panel_installed_by_files; then
        printf '%b' "${YELLOW}已安装/未运行${PLAIN}"
    else
        printf '%b' "${BLUE}未安装${PLAIN}"
    fi
}

xui_panel_state_for_issue() {
    local svc
    if svc=$(xui_panel_service_name); then
        if systemctl is-active --quiet "$svc"; then
            echo "运行中 (${svc}.service)"
        else
            echo "已安装/未运行 (${svc}.service)"
        fi
    elif xui_panel_installed_by_files; then
        echo "已安装/未检测到 systemd 服务"
    else
        echo "未检测到"
    fi
}

docker_public_binding_count() {
    local count=0
    local name line ports
    command -v docker >/dev/null 2>&1 || { echo "0"; return 0; }
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        ports=$(docker port "$name" 2>/dev/null || true)
        [[ -z "$ports" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            docker_port_line_is_public "$line" && count=$((count + 1))
        done <<< "$ports"
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)
    echo "$count"
}

print_project_runtime_overview() {
    echo -e "${CYAN}🧩 VPS-Optimize 场景概览${PLAIN}"
    echo -e "脚本版本 : ${GREEN}${SCRIPT_VERSION}${PLAIN}"
    echo -e "关键服务 : nginx[$(service_status_compact nginx)] caddy[$(service_status_compact caddy)] docker[$(service_status_compact docker)] 3x-ui面板[$(xui_panel_status_compact)] Xray内核[$(service_status_compact xray)]"

    if [[ -f /etc/vps-optimize/sni-stack.env ]]; then
        if load_sni_stack_env >/dev/null 2>&1; then
            echo -e "443 入口 : ${NGINX_LISTEN_ADDR}:${NGINX_LISTEN_PORT} -> Caddy ${CADDY_LISTEN_ADDR}:${CADDY_LISTEN_PORT} / REALITY ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
            echo -e "3x-ui   : 面板 https://${PANEL_DOMAIN}${PANEL_WEB_PATH} -> ${PANEL_LISTEN_ADDR}:${PANEL_LISTEN_PORT}"
            echo -e "订阅路径 : 普通 ${SUB_URI_PATH} / Clash-Mihomo ${CLASH_URI_PATH} -> ${SUB_LISTEN_ADDR}:${SUB_LISTEN_PORT}"
            echo -e "扩展分流 : 网站/反代 ${#SITE_DOMAINS[@]} 个，TCP/SNI 入站 ${#TCP_ROUTE_SNIS[@]} 个"
        else
        echo -e "443 入口 : ${YELLOW}检测到配置文件，但读取失败，请运行 [19] -> [11] 体检。${PLAIN}"
        fi
    else
        echo -e "443 入口 : ${BLUE}尚未配置；需要面板/订阅/REALITY 共用 443 时进入 [19]。${PLAIN}"
    fi

    if command -v docker >/dev/null 2>&1; then
        local running_containers public_binds
        running_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d '[:space:]')
        public_binds=$(docker_public_binding_count)
        echo -e "Docker   : 运行容器 ${running_containers:-0} 个，公网映射 ${public_binds:-0} 条"
    fi

    if [[ -r "$TRAFFIC_GUARD_CONFIG" ]]; then
        local guard_usage guard_limit guard_timer guard_pct
        # shellcheck disable=SC1090
        . "$TRAFFIC_GUARD_CONFIG"
        guard_usage=$(traffic_guard_usage_from_state 2>/dev/null || echo 0)
        guard_limit="${LIMIT_BYTES:-0}"
        guard_timer=$(systemctl is-active vps-traffic-guard.timer 2>/dev/null || echo "inactive")
        if [[ "$guard_limit" =~ ^[0-9]+$ && "$guard_limit" -gt 0 ]]; then
            guard_pct=$(awk -v u="$guard_usage" -v l="$guard_limit" 'BEGIN { printf "%.2f", (u/l)*100 }')
            echo -e "流量保护 : timer ${guard_timer}，$(traffic_guard_mode_label "${MODE:-tx}") 已用 $(traffic_guard_human_bytes "$guard_usage") / $(traffic_guard_human_bytes "$guard_limit") (${guard_pct}%)"
        else
            echo -e "流量保护 : timer ${guard_timer}，配置需检查"
        fi
    fi
}

func_system_info() {
    clear
    local os_name
    os_name=$(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🖥️  本机详细硬件与网络信息大屏${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}系统 OS  :${PLAIN} $os_name ($(uname -m))"
    echo -e "${YELLOW}内核版本 :${PLAIN} $(uname -r)"
    echo -e "${YELLOW}虚拟架构 :${PLAIN} $(systemd-detect-virt 2>/dev/null || echo "未知")"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}CPU 型号 :${PLAIN} $(lscpu | grep "Model name:" | sed 's/Model name:\s*//')"
    echo -e "${YELLOW}CPU 核心 :${PLAIN} $(nproc) 核心"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}物理内存 :${PLAIN} $(free -h | awk '/^Mem:/ {print $3}') / $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "${YELLOW}交换内存 :${PLAIN} $(free -h | awk '/^Swap:/ {print $3}') / $(free -h | awk '/^Swap:/ {print $2}')"
    echo -e "${YELLOW}硬盘空间 :${PLAIN} $(df -h / | awk 'NR==2 {print $3}') / $(df -h / | awk 'NR==2 {print $2}')"
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}IPv4 地址:${PLAIN} $(curl -s4 --max-time 3 icanhazip.com || echo "无公网IPv4")"
    echo -e "${YELLOW}IPv6 地址:${PLAIN} $(curl -s6 --max-time 3 icanhazip.com || echo "无公网IPv6")"
    echo -e "${YELLOW}运行时间 :${PLAIN} $(uptime -p | sed 's/up //')"
    echo -e "------------------------------------------------"
    print_project_runtime_overview
    echo -e "${CYAN}================================================${PLAIN}"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# ---------------------------------------------------------
# 12. 综合测试合集
# ---------------------------------------------------------
probe_host_for_listen_addr() {
    local addr="$1"
    case "$addr" in
        ""|"0.0.0.0"|"::"|"[::]") echo "127.0.0.1" ;;
        *:*) echo "localhost" ;;
        *) echo "$addr" ;;
    esac
}

tcp_probe_host() {
    local label="$1"
    local host="$2"
    local port="$3"
    if ! command -v timeout >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ ${label}: 缺少 timeout，跳过 TCP 探测。${PLAIN}"
        return 1
    fi
    if timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null; then
        echo -e "${GREEN}✅ ${label}: ${host}:${port} 可连接${PLAIN}"
        return 0
    fi
    echo -e "${RED}❌ ${label}: ${host}:${port} 连接失败${PLAIN}"
    return 1
}

https_url_for_port() {
    local host="$1"
    local port="$2"
    local path="$3"
    if [[ "$port" == "443" ]]; then
        printf 'https://%s%s' "$host" "$path"
    else
        printf 'https://%s:%s%s' "$host" "$port" "$path"
    fi
}

curl_sni_path_probe() {
    local label="$1"
    local domain="$2"
    local port="$3"
    local path="$4"
    local url code curl_rc
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ ${label}: 缺少 curl，跳过 HTTPS 路径探测。${PLAIN}"
        return 1
    fi
    url=$(https_url_for_port "$domain" "$port" "$path")
    code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 12 --resolve "${domain}:${port}:127.0.0.1" "$url" 2>/dev/null)
    curl_rc=$?
    if [[ "$curl_rc" -ne 0 || ! "$code" =~ ^[0-9]{3}$ || "$code" == "000" ]]; then
        echo -e "${RED}❌ ${label}: ${url} 无响应或 TLS/SNI 失败（curl exit ${curl_rc}, HTTP ${code:-000}）${PLAIN}"
        return 1
    fi
    case "$code" in
        404)
            echo -e "${YELLOW}⚠️ ${label}: ${url} HTTP ${code}，443/SNI 已到达，但路径或后端可能不匹配。${PLAIN}"
            return 0
            ;;
        *)
            echo -e "${GREEN}✅ ${label}: ${url} HTTP ${code}${PLAIN}"
            return 0
            ;;
    esac
}

tls_sni_probe_local() {
    local label="$1"
    local sni="$2"
    local port="$3"
    if ! command -v openssl >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ ${label}: 缺少 openssl/timeout，跳过 TLS SNI 探测。${PLAIN}"
        return 1
    fi
    if timeout 10 openssl s_client -connect "127.0.0.1:${port}" -servername "$sni" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${GREEN}✅ ${label}: Nginx 入口能按 ${sni} 命中 TLS 证书链${PLAIN}"
        return 0
    fi
    echo -e "${YELLOW}⚠️ ${label}: 未拿到证书链，请检查 Nginx stream、Caddy 证书或 SNI。${PLAIN}"
    return 1
}

func_443_network_test() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "测速与质量检测 > 443 单入口测试"
    echo -e "${BOLD}🧪 443 单入口网络访问测试${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    if [[ ! -f /etc/vps-optimize/sni-stack.env ]]; then
        echo -e "${YELLOW}未检测到 443 单入口配置。请先进入 [19] -> [2] 完成首次配置。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    load_sni_stack_env || { read -n 1 -s -r -p "按任意键返回..."; return; }

    echo -e "面板入口：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "订阅入口：https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "Clash/Mihomo：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "REALITY SNI：${REALITY_SNI}:${NGINX_LISTEN_PORT} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "------------------------------------------------"

    check_domain_dns_sanity "$PANEL_DOMAIN" "面板域名" "warn" || true
    [[ "$PANEL_DOMAIN" != "$REALITY_SNI" ]] && check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "warn" || true

    echo -e "------------------------------------------------"
    tcp_probe_host "公网入口 TCP" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" || true
    tcp_probe_host "本机 Nginx 入口" "127.0.0.1" "$NGINX_LISTEN_PORT" || true
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "3x-ui 面板后端" "$(probe_host_for_listen_addr "$PANEL_LISTEN_ADDR")" "$PANEL_LISTEN_PORT" || true
    tcp_probe_host "3x-ui 订阅后端" "$(probe_host_for_listen_addr "$SUB_LISTEN_ADDR")" "$SUB_LISTEN_PORT" || true
    tcp_probe_host "REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true

    echo -e "------------------------------------------------"
    tls_sni_probe_local "面板 SNI TLS" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" || true
    curl_sni_path_probe "面板路径" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$PANEL_WEB_PATH" || true
    curl_sni_path_probe "普通订阅路径" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$SUB_URI_PATH" || true
    curl_sni_path_probe "Clash/Mihomo 路径" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$CLASH_URI_PATH" || true

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}说明：HTTP 401/403/302 通常表示链路已到达后端；404 多数是路径或 3x-ui 订阅设置不一致。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测速与质量检验合集库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 硬件性能测试      ${YELLOW}  2. 融合怪详细测速${PLAIN}"
        echo -e "${GREEN}  3. SuperBench 综合测速    ${YELLOW}  4. bench.sh 基础测试${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁检测         ${YELLOW}  6. 三网回程路由测试${PLAIN}"
        echo -e "${GREEN}  7. IP 质量 / 欺诈度检测   ${YELLOW}  8. NodeSeek 综合测试${PLAIN}"
        echo -e "${GREEN}  9. 443 单入口链路测试      ${YELLOW}(面板/订阅/Caddy/REALITY 本地链路)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local t
        local ran_test=false
        read_trimmed t "👉 请输入对应序号选择: "
        case $t in
            1) ran_test=true; run_remote_script "运行 YABS 硬件性能测试" "https://yabs.sh" ;;
            2) ran_test=true; run_remote_script "运行融合怪详细测速" "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh" ;;
            3) ran_test=true; run_remote_script "运行 SuperBench 综合测速" "https://about.superbench.pro" ;;
            4) ran_test=true; run_remote_script "运行 bench.sh 基础测试" "https://bench.sh" ;;
            5) ran_test=true; run_remote_script "运行流媒体解锁检测" "https://check.unlock.media" ;;
            6) ran_test=true; run_remote_script "运行三网回程路由测试" "https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh" ;;
            7) ran_test=true; run_remote_script "运行 IP 质量 / 欺诈度检测" "https://IP.Check.Place" ;;
            8) ran_test=true; run_remote_script "运行 NodeSeek 综合测试" "https://run.NodeQuality.com" ;;
            9) func_443_network_test; continue ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1; continue ;;
        esac
        echo ""
        if [[ "$ran_test" == "true" ]]; then
            pause_after_external_script "操作结束，按回车键返回测试菜单..."
        fi
    done
}
# ---------------------------------------------------------
# 13, 14, 15 面板与流量狗快速部署
# ---------------------------------------------------------
func_port_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取并执行 Port Traffic Dog 监控狗...${PLAIN}"
    run_remote_script "安装 Port Traffic Dog 监控狗" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xpanel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 3x-ui / x-ui 面板${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}账号密码说明：本入口会运行 3x-ui 官方安装器。${PLAIN}"
    echo -e "${YELLOW}管理员账号、密码和面板路径通常由官方安装器交互设置或在安装结束时输出。${PLAIN}"
    echo -e "${YELLOW}请留意安装结束输出并及时保存；后续也可通过 x-ui / 3x-ui 官方菜单修改。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${CYAN}👉 正在拉取 mhsanaei 的官方 x-panel 一键脚本...${PLAIN}"
    run_remote_script "安装 3x-ui / x-ui 面板" "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xpanel_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 3x-ui / x-ui 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入官方管理菜单，执行配置查看、账号管理、更新或卸载等操作。${PLAIN}"
    echo -e "------------------------------------------------"

    local panel_cmd=""
    if command -v x-ui >/dev/null 2>&1; then
        panel_cmd="x-ui"
    elif command -v 3x-ui >/dev/null 2>&1; then
        panel_cmd="3x-ui"
    fi

    if [[ -z "$panel_cmd" ]]; then
        echo -e "${YELLOW}未检测到 x-ui / 3x-ui 命令，当前机器可能尚未安装 3x-ui 面板。${PLAIN}"
        local yn
        read_trimmed yn "是否现在安装 3x-ui 面板？(y/n): "
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            func_xpanel
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
        fi
        return
    fi

    echo -e "${GREEN}即将打开 ${panel_cmd} 官方管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    "$panel_cmd"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xui_custom_manager() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 3x-ui 外置增强管理${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：补充 3x-ui 面板内没有的维护能力，例如自定义流量重置、数据库流量校准、备份恢复和健康检查。${PLAIN}"
    echo -e "${YELLOW}建议：修改数据库或恢复备份前，先做快照或通过脚本备份 x-ui 数据。${PLAIN}"
    echo -e "------------------------------------------------"
    run_remote_script "运行 3x-ui 外置增强管理脚本" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_sui_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 S-UI 面板${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}账号密码说明：本入口会运行 S-UI 官方安装器。${PLAIN}"
    echo -e "${YELLOW}管理员账号、密码和面板访问参数由官方安装器设置或在安装结束时输出。${PLAIN}"
    echo -e "${YELLOW}请留意安装结束输出并及时保存；后续也可通过 s-ui 官方菜单修改。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${CYAN}👉 正在拉取 alireza0 的 S-UI 官方安装脚本...${PLAIN}"
    run_remote_script "安装 S-UI 面板" "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_sui_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 S-UI 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入 S-UI 官方管理菜单，执行配置查看、账号管理、更新或卸载等操作。${PLAIN}"
    echo -e "------------------------------------------------"

    if ! command -v s-ui >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 s-ui 命令，当前机器可能尚未安装 S-UI。${PLAIN}"
        local yn
        read_trimmed yn "是否现在安装 S-UI？(y/n): "
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            func_sui_panel
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
        fi
        return
    fi

    echo -e "${GREEN}即将打开 S-UI 官方管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    s-ui
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox() {
    clear
    echo -e "${CYAN}👉 正在拉取甬哥的 Sing-box 四合一脚本...${PLAIN}"
    run_remote_script "安装 Sing-box 甬哥四合一脚本" "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox_233boy() {
    clear
    echo -e "${CYAN}👉 正在拉取 233boy 的 Sing-box 一键脚本...${PLAIN}"
    echo -e "${YELLOW}脚本来源：https://github.com/233boy/sing-box${PLAIN}"
    echo -e "${YELLOW}使用文档：https://233boy.com/sing-box/sing-box-script/${PLAIN}"
    echo -e "${GREEN}安装完成后通常可使用 sing-box 或 sb 命令进入管理面板。${PLAIN}"
    run_remote_script "安装 Sing-box 233boy 一键脚本" "https://github.com/233boy/sing-box/raw/main/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 Sing-box 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入已安装 Sing-box 一键脚本的管理菜单。${PLAIN}"
    echo -e "------------------------------------------------"

    local sb_cmd=""
    if command -v sb >/dev/null 2>&1; then
        sb_cmd="sb"
    elif command -v sing-box >/dev/null 2>&1; then
        sb_cmd="sing-box"
    fi

    if [[ -z "$sb_cmd" ]]; then
        echo -e "${YELLOW}未检测到 sb / sing-box 管理命令。${PLAIN}"
        echo -e "${BLUE}如果是首次部署，请先选择对应的 Sing-box 安装项。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${GREEN}即将打开 ${sb_cmd} 管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在脚本菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    "$sb_cmd"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xray_233boy() {
    clear
    echo -e "${CYAN}👉 正在拉取 233boy 的 Xray 一键脚本...${PLAIN}"
    echo -e "${YELLOW}脚本来源：https://github.com/233boy/Xray${PLAIN}"
    echo -e "${YELLOW}使用文档：https://233boy.com/xray/xray-script/${PLAIN}"
    echo -e "${GREEN}安装完成后通常可使用 xray 命令进入管理面板。${PLAIN}"
    run_remote_script "安装 Xray 233boy 一键脚本" "https://github.com/233boy/Xray/raw/main/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xray_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 Xray 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入 233boy Xray 官方管理菜单。${PLAIN}"
    echo -e "------------------------------------------------"

    if ! command -v xray >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 xray 管理命令，当前机器可能尚未安装 233boy Xray 脚本。${PLAIN}"
        local yn
        read_trimmed yn "是否现在安装 Xray？(y/n): "
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            func_xray_233boy
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
        fi
        return
    fi

    echo -e "${GREEN}即将打开 xray 管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    xray
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 17. DNS 流媒体分流解锁 (Alice DNS)
# ---------------------------------------------------------
func_dns_unlock() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔓 DNS 流媒体分流解锁 (DNS-Alice-Unlock)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍与使用说明：${PLAIN}"
    echo -e " 1. 该脚本通过修改本地 DNS 解析，实现 Netflix, Disney+ 等特定区域流媒体的解锁。"
    echo -e " 2. ${GREEN}仅对流媒体域名进行分流${PLAIN}，不影响您的原生 IP 和普通上网速度。"
    echo -e " 3. 项目地址：${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}⚠️  风险提示：运行此脚本会修改您服务器的 /etc/resolv.conf 配置。${PLAIN}"
    echo -e "    如果您不懂如何自行配置解锁机的 DNS 记录，请务必先查阅项目文档！"
    echo -e "------------------------------------------------"
    
    local yn
    read_trimmed yn "❓ 确认现在运行 Alice DNS 解锁脚本吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        run_remote_script "运行 Alice DNS 解锁脚本" "https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh"
    else
        echo -e "${BLUE}已安全取消操作。${PLAIN}"
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}
# ---------------------------------------------------------
# 新增功能：安装 IP Sentinel (防止 IP 送中)
# ---------------------------------------------------------
func_ip_sentinel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 安装 IP Sentinel (防止 IP 送中)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}该脚本将持续监控并修正路由，防止服务器 IP 被错误定位至中国大陆。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "❓ 确定要安装并配置 IP Sentinel(公共网关) 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        run_remote_script "安装并配置 IP Sentinel" "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 新增功能：安装 SublinkPro (强大的订阅转换与管理面板)
# ---------------------------------------------------------
install_docker_compose_standalone() {
    local compose_url tmp_file
    compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    tmp_file=$(mktemp /tmp/docker-compose.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败。${PLAIN}"; return 1; }

    if ! download_remote_script "$compose_url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 下载失败，请检查网络或 GitHub 访问。${PLAIN}"
        return 1
    fi

    if [[ ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 下载文件为空，已取消安装。${PLAIN}"
        return 1
    fi

    if ! mv "$tmp_file" /usr/local/bin/docker-compose; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 写入 /usr/local/bin 失败。${PLAIN}"
        return 1
    fi
    chmod +x /usr/local/bin/docker-compose || return 1
}

ensure_docker_compose_ready() {
    DOCKER_COMPOSE_CMD=""
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 基础组件与常用服务] 中安装 Docker。${PLAIN}"
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您安装...${PLAIN}"
        install_docker_compose_standalone || return 1
        DOCKER_COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi
}

generate_random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        echo "secret_$(date +%s)_$RANDOM$RANDOM"
    fi
}

func_sublinkpro() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔗 安装 SublinkPro (节点订阅转换与管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 1. 检查 Docker 引擎
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 基础组件与常用服务] 中安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 2. 检查并兼容 Docker Compose
    local compose_cmd=""
    if docker compose version >/dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您静默安装...${PLAIN}"
        install_docker_compose_standalone || {
            read -n 1 -s -r -p "按任意键返回..."
            return
        }
        compose_cmd="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi

    # 3. 部署目录初始化
    local install_dir="/opt/sublinkpro"
    local sublink_bind_addr="127.0.0.1"
    local sublink_port="8000"
    sublink_bind_addr=$(ask_with_default "请输入 SublinkPro 监听地址" "$sublink_bind_addr")
    is_valid_listen_addr "$sublink_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        sublink_port=$(ask_with_default "请输入 SublinkPro 对外访问端口" "$sublink_port")
        if is_valid_port "$sublink_port"; then
            break
        fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "SublinkPro" "$sublink_bind_addr" "$sublink_port" || return 1

    echo -e "${YELLOW}💡 SublinkPro 将被安全部署在: ${CYAN}$install_dir${PLAIN}"
    echo -e "${YELLOW}💡 SublinkPro 监听地址将使用: ${CYAN}${sublink_bind_addr}:${sublink_port}${PLAIN}"
    echo -e "${YELLOW}💡 需要公网 HTTPS 访问时，建议部署后走 [19] -> [8] 添加 443 单入口反代域名。${PLAIN}"
    echo -e "${YELLOW}账号密码说明：当前安装流程不提供自定义后台账号密码。${PLAIN}"
    echo -e "${YELLOW}默认后台账号：${CYAN}admin${PLAIN} / 默认后台密码：${CYAN}123456${PLAIN}"
    echo -e "${YELLOW}部署完成后请尽快登录后台修改默认密码。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "❓ 确认现在开始一键安装吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir"
        cd "$install_dir" || return

        # 生成 docker-compose.yml 文件
        cat <<EOF > docker-compose.yml
services:
  sublinkpro:
    image: zerodeng/sublink-pro
    container_name: sublinkpro
    ports:
      - "${sublink_bind_addr}:${sublink_port}:8000"
    volumes:
      - "./db:/app/db"
      - "./template:/app/template"
      - "./logs:/app/logs"
    restart: unless-stopped
EOF
        
        echo -e "${CYAN}▶ 正在拉取镜像并启动 SublinkPro 容器...${PLAIN}"
        $compose_cmd up -d
        
        local access_host
        access_host="$sublink_bind_addr"
        [[ "$sublink_bind_addr" == "0.0.0.0" || "$sublink_bind_addr" == "::" ]] && access_host=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null || echo "您的服务器IP")
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}🎉 SublinkPro 部署并启动成功！${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "🌐 ${BOLD}本地访问地址:${PLAIN} http://${access_host}:${sublink_port}"
        echo -e "👤 ${BOLD}默认后台账号:${PLAIN} admin"
        echo -e "🔑 ${BOLD}默认后台密码:${PLAIN} 123456"
        echo -e "${YELLOW}⚠️ 当前安装流程未提供自定义账号密码，请登录后尽快修改默认密码。${PLAIN}"
        echo -e "${YELLOW}公网访问建议：主菜单 [19] -> [8] 为该本地端口添加 443 反代域名。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}⚠️ 核心防丢提示：${PLAIN}"
        echo -e "系统产生的数据库、模板和日志都已持久化映射在 ${CYAN}$install_dir${PLAIN} 下。"
        echo -e "如果您日后需要升级容器或重装 VPS，请务必提前打包备份该目录下的 ${GREEN}./db${PLAIN} 和 ${GREEN}./template${PLAIN} 文件夹！"
        echo -e "------------------------------------------------"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_miaomiaowu() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 妙妙屋订阅管理 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/miaomiaowu"
    local mmw_bind_addr="127.0.0.1"
    local mmw_port="8080"
    local jwt_secret

    mmw_bind_addr=$(ask_with_default "妙妙屋监听地址" "$mmw_bind_addr")
    is_valid_listen_addr "$mmw_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        mmw_port=$(ask_with_default "请输入 妙妙屋 对外访问端口" "$mmw_port")
        if is_valid_port "$mmw_port"; then
            break
        fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "妙妙屋订阅管理" "$mmw_bind_addr" "$mmw_port" || return 1

    jwt_secret=$(ask_with_default "JWT_SECRET（回车自动生成随机密钥）" "")
    if [[ -z "$jwt_secret" ]]; then
        jwt_secret=$(generate_random_secret)
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${mmw_bind_addr}:${mmw_port}${PLAIN}"
    echo -e "${YELLOW}数据目录：${CYAN}${install_dir}/data、subscribes、rule_templates${PLAIN}"
    echo -e "${YELLOW}公网 HTTPS 访问建议走 [19] -> [8]，不要直接开放容器端口。${PLAIN}"
    echo -e "${YELLOW}账号密码说明：当前安装流程不预设账号密码。${PLAIN}"
    echo -e "${YELLOW}首次打开面板会进入初始化页，请在页面中创建管理员账号和密码。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "确认现在部署 妙妙屋订阅管理 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir"/{data,subscribes,rule_templates}
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'

services:
  miaomiaowu:
    image: ghcr.io/iluobei/miaomiaowu:latest
    container_name: miaomiaowu
    restart: unless-stopped
    user: root
    environment:
      PORT: "${mmw_port}"
      DATABASE_PATH: /app/data/traffic.db
      LOG_LEVEL: info
      JWT_SECRET: "${jwt_secret}"
    ports:
      - "${mmw_bind_addr}:${mmw_port}:${mmw_port}"
    volumes:
      - ./data:/app/data
      - ./subscribes:/app/subscribes
      - ./rule_templates:/app/rule_templates
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:${mmw_port}/"]
      interval: 30s
      timeout: 3s
      start_period: 5s
      retries: 3
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 妙妙屋 容器...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        local access_host
        access_host="$mmw_bind_addr"
        [[ "$mmw_bind_addr" == "0.0.0.0" || "$mmw_bind_addr" == "::" ]] && access_host=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null || echo "您的服务器IP")
        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ 妙妙屋订阅管理部署完成！${PLAIN}"
        echo -e "本地访问地址：${BOLD}http://${access_host}:${mmw_port}${PLAIN}"
        echo -e "账号密码：${YELLOW}无默认账号密码，首次打开页面创建管理员账号。${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        echo -e "${YELLOW}公网访问建议：主菜单 [19] -> [8] 为该本地端口添加 443 反代域名。${PLAIN}"
        echo -e "${YELLOW}请定期备份 ${install_dir}/data、subscribes、rule_templates。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

func_substore() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Sub-Store (Docker Compose / HTTP-META)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/sub-store"
    local backend_port="3001"
    local meta_port="9876"
    local backend_path="/$(generate_random_secret | cut -c1-48)"

    while true; do
        backend_port=$(ask_with_default "Sub-Store 后端 API 端口" "$backend_port")
        if is_valid_port "$backend_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    while true; do
        meta_port=$(ask_with_default "HTTP-META 本地端口" "$meta_port")
        if is_valid_port "$meta_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    backend_path=$(ask_with_default "前端访问后端路径（建议保留随机路径）" "$backend_path")
    if [[ "$backend_path" != /* ]]; then
        backend_path="/${backend_path}"
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}Sub-Store 后端：${CYAN}127.0.0.1:${backend_port}${PLAIN}"
    echo -e "${YELLOW}HTTP-META：${CYAN}127.0.0.1:${meta_port}${PLAIN}"
    echo -e "${YELLOW}前端后端路径：${CYAN}${backend_path}${PLAIN}"
    echo -e "${YELLOW}默认使用 host 网络并绑定 127.0.0.1，如需公网访问建议再接 Caddy/Nginx 反代。${PLAIN}"
    echo -e "${YELLOW}账号密码说明：当前 Sub-Store 部署不使用登录账号密码。${PLAIN}"
    echo -e "${YELLOW}请保存随机后端路径；公网访问建议通过反代额外加认证。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "确认现在部署 Sub-Store 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir/data"
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'

services:
  sub-store:
    image: xream/sub-store:http-meta
    container_name: sub-store
    restart: always
    network_mode: host
    environment:
      SUB_STORE_BACKEND_API_HOST: "127.0.0.1"
      SUB_STORE_BACKEND_API_PORT: "${backend_port}"
      SUB_STORE_BACKEND_MERGE: "true"
      SUB_STORE_FRONTEND_BACKEND_PATH: "${backend_path}"
      PORT: "${meta_port}"
      HOST: "127.0.0.1"
    volumes:
      - ./data:/opt/app/data
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Sub-Store 容器...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Sub-Store 部署完成！${PLAIN}"
        echo -e "本地后端地址：${BOLD}http://127.0.0.1:${backend_port}${backend_path}${PLAIN}"
        echo -e "HTTP-META 地址：${BOLD}http://127.0.0.1:${meta_port}${PLAIN}"
        echo -e "账号密码：${YELLOW}无默认登录账号密码，请妥善保存上面的随机后端路径。${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        echo -e "${YELLOW}请定期备份 ${install_dir}/data。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

update_compose_project() {
    local name="$1"
    local dir="$2"

    if [[ ! -d "$dir" || ! -f "$dir/docker-compose.yml" ]]; then
        echo -e "${YELLOW}⚠️ 未找到 ${name} 的 Compose 配置：${dir}/docker-compose.yml，已跳过。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在更新 ${name}...${PLAIN}"
    (
        cd "$dir" || exit 1
        $DOCKER_COMPOSE_CMD pull
        $DOCKER_COMPOSE_CMD up -d
    )
}

func_update_subscription_tools() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}${YELLOW}UPD 更新订阅管理工具 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}这个菜单只更新订阅管理工具容器，不会更新 3x-ui / Sing-box / Xray。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${BOLD}${YELLOW}  1. UPD 更新 SublinkPro${PLAIN}       ${CYAN}(/opt/sublinkpro)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  2. UPD 更新 妙妙屋订阅管理${PLAIN}     ${CYAN}(/opt/miaomiaowu)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  3. UPD 更新 Sub-Store${PLAIN}        ${CYAN}(/opt/sub-store)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  4. UPD 全部更新${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice
    read_trimmed choice "请选择要更新的项目: "
    [[ "$choice" == "0" ]] && return

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    case "$choice" in
        1) update_compose_project "SublinkPro" "/opt/sublinkpro" ;;
        2) update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" ;;
        3) update_compose_project "Sub-Store" "/opt/sub-store" ;;
        4)
            update_compose_project "SublinkPro" "/opt/sublinkpro" || true
            update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" || true
            update_compose_project "Sub-Store" "/opt/sub-store" || true
            ;;
        *)
            echo -e "${RED}❌ 无效选择！${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
            ;;
    esac

    echo -e "------------------------------------------------"
    echo -e "${GREEN}✅ 更新流程已执行完成。${PLAIN}"
    local prune_confirm
    read_trimmed prune_confirm "是否清理无标签旧镜像以释放磁盘空间？(y/n，默认 n): "
    if [[ "$prune_confirm" =~ ^[Yy]$ ]]; then
        docker image prune -f
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Dockge (Docker Compose 管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}Dockge 用来管理 compose.yaml stack，可创建、编辑、启动、停止、重启和更新镜像。${PLAIN}"
    echo -e "${YELLOW}注意：Dockge 会挂载 Docker socket，建议只监听本地地址，再通过 Caddy/Nginx 反代访问。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/dockge"
    local stacks_dir="/opt/stacks"
    local dockge_bind_addr="127.0.0.1"
    local dockge_port="5001"

    dockge_bind_addr=$(ask_with_default "Dockge 监听地址" "$dockge_bind_addr")
    is_valid_listen_addr "$dockge_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        dockge_port=$(ask_with_default "Dockge 访问端口" "$dockge_port")
        if is_valid_port "$dockge_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "Dockge 管理面板" "$dockge_bind_addr" "$dockge_port" || return 1
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")

    echo -e "${YELLOW}Dockge 目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}Stacks 目录：${CYAN}${stacks_dir}${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${dockge_bind_addr}:${dockge_port}${PLAIN}"
    echo -e "${YELLOW}账号密码说明：Dockge 不预设默认账号密码。${PLAIN}"
    echo -e "${YELLOW}首次打开面板会进入初始化页，请在页面中创建管理员账号和密码。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "确认现在部署 Dockge 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir" "$stacks_dir"
        cd "$install_dir" || return

        cat <<EOF > compose.yaml
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - "${dockge_bind_addr}:${dockge_port}:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - ${stacks_dir}:${stacks_dir}
    environment:
      DOCKGE_STACKS_DIR: "${stacks_dir}"
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Dockge...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Dockge 部署完成！${PLAIN}"
        echo -e "访问地址：${BOLD}http://${dockge_bind_addr}:${dockge_port}${PLAIN}"
        echo -e "Stacks 目录：${CYAN}${stacks_dir}${PLAIN}"
        echo -e "账号密码：${YELLOW}无默认账号密码，首次打开页面创建管理员账号。${PLAIN}"
        echo -e "${YELLOW}已有 compose 项目可返回部署菜单选择 [10] 迁移到 Dockge 后，在 Dockge 里扫描 stacks 目录。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

func_komari() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Komari 探针监控面板 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}Komari 用于服务器探针监控。默认只监听本地地址；公网 HTTPS 可走普通 Caddy 反代，已启用 443 单入口时走 [19] -> [8]。${PLAIN}"
    echo -e "${YELLOW}如果探针客户端需要直连端口，可把监听地址改为 0.0.0.0，并确认云安全组已放行。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/komari"
    local komari_bind_addr="127.0.0.1"
    local komari_port="25774"
    local custom_admin="n"
    local admin_username=""
    local admin_password=""
    local yn

    komari_bind_addr=$(ask_with_default "Komari 监听地址" "$komari_bind_addr")
    is_valid_listen_addr "$komari_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        komari_port=$(ask_with_default "Komari 访问端口" "$komari_port")
        if is_valid_port "$komari_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "Komari 探针监控面板" "$komari_bind_addr" "$komari_port" || return 1

    read_trimmed custom_admin "是否自定义初始管理员账号和密码？(y/n，默认 n): "
    if [[ "$custom_admin" =~ ^[Yy]$ ]]; then
        while true; do
            read_trimmed admin_username "管理员用户名（默认 admin）: "
            admin_username="${admin_username:-admin}"
            if [[ "$admin_username" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
                break
            fi
            echo -e "${RED}❌ 用户名只能包含字母、数字、点、下划线和短横线，长度 3-32。${PLAIN}"
        done

        while true; do
            read_secret_trimmed admin_password "管理员密码（至少 8 位，留空自动生成）: "
            if [[ -z "$admin_password" ]]; then
                admin_password=$(generate_random_secret | cut -c1-24)
                echo -e "${YELLOW}已自动生成管理员密码，部署完成后会显示一次，请及时保存。${PLAIN}"
                break
            fi
            if [[ ${#admin_password} -ge 8 ]]; then
                break
            fi
            echo -e "${RED}❌ 密码至少需要 8 位。${PLAIN}"
        done
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}数据目录：${CYAN}${install_dir}/data${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${komari_bind_addr}:${komari_port}${PLAIN}"
    if [[ -n "$admin_username" ]]; then
        echo -e "${YELLOW}初始管理员：${CYAN}${admin_username}${PLAIN}"
    else
        echo -e "${YELLOW}账号密码说明：未自定义时 Komari 会生成默认管理员账号。${PLAIN}"
        echo -e "${YELLOW}初始管理员：${CYAN}使用 Komari 默认生成账号，请安装后查看容器日志${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    read_trimmed yn "确认现在部署 Komari 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        mkdir -p "$install_dir/data"
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'
services:
  komari:
    image: ghcr.io/komari-monitor/komari:latest
    container_name: komari
    ports:
      - "${komari_bind_addr}:${komari_port}:25774"
    volumes:
      - ./data:/app/data
    environment:
EOF

        if [[ -n "$admin_username" ]]; then
            cat <<EOF >> docker-compose.yml
      ADMIN_USERNAME: "${admin_username}"
      ADMIN_PASSWORD: "${admin_password}"
EOF
        else
            cat <<'EOF' >> docker-compose.yml
      # 可选：如需自定义初始管理员账号，请停止容器后取消注释并填写。
      # ADMIN_USERNAME: admin
      # ADMIN_PASSWORD: yourpassword
EOF
        fi

        cat <<EOF >> docker-compose.yml
    restart: unless-stopped
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Komari...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Komari 部署完成！${PLAIN}"
        echo -e "访问地址：${BOLD}http://${komari_bind_addr}:${komari_port}${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        if [[ -n "$admin_username" ]]; then
            echo -e "管理员账号：${BOLD}${admin_username}${PLAIN}"
            echo -e "管理员密码：${BOLD}${admin_password}${PLAIN}"
            echo -e "${YELLOW}请及时保存密码，后续也可在 ${install_dir}/docker-compose.yml 中查看或修改。${PLAIN}"
        else
            echo -e "${YELLOW}默认管理员账号请查看日志：${CYAN}$DOCKER_COMPOSE_CMD logs komari${PLAIN}"
        fi
        echo -e "${YELLOW}如需公网 HTTPS 访问：未启用 443 单入口可用 [4] -> [1] 普通 Caddy 反代；已启用 443 单入口请用 [19] -> [8] 添加反代域名。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

find_compose_file() {
    local dir="$1"
    local file
    for file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        if [[ -f "${dir}/${file}" ]]; then
            echo "${dir}/${file}"
            return 0
        fi
    done
    return 1
}

is_managed_compose_dir() {
    local dir="${1%/}"
    case "$dir" in
        /opt/sublinkpro|/opt/miaomiaowu|/opt/sub-store|/opt/dockge|/opt/komari)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

manage_compose_project() {
    local project_name="$1"
    local project_dir="${2%/}"
    local data_hint="$3"
    local compose_file choice yn

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 ${project_name} 管理 / 卸载${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}部署目录：${CYAN}${project_dir}${PLAIN}"
        echo -e "${YELLOW}数据提示：${CYAN}${data_hint}${PLAIN}"
        echo -e "------------------------------------------------"

        if [[ ! -d "$project_dir" ]] || ! compose_file=$(find_compose_file "$project_dir"); then
            echo -e "${YELLOW}未检测到 ${project_name} 的 Compose 部署。${PLAIN}"
            echo -e "${BLUE}可以先返回上级菜单选择对应安装项。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${GREEN}  1. 查看运行状态${PLAIN}"
        echo -e "${GREEN}  2. 重启服务${PLAIN}"
        echo -e "${GREEN}  3. 更新镜像并重建${PLAIN}"
        echo -e "${YELLOW}  4. 停止并移除容器（保留目录数据）${PLAIN}"
        echo -e "${RED}  5. 归档部署目录（停止容器并隔离配置/数据）${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" ps)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            2)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" restart)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            3)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" pull && $DOCKER_COMPOSE_CMD -f "$compose_file" up -d)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            4)
                if confirm_risk_action "停止并移除 ${project_name} 容器" \
                    "Docker Compose 容器运行状态" \
                    "在 ${project_dir} 中重新执行 compose up -d，或回到管理菜单重建" \
                    "目录数据会保留，但服务会立即中断。"; then
                    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down)
                    echo -e "${GREEN}✅ 已停止并移除容器，部署目录仍保留：${project_dir}${PLAIN}"
                else
                    echo -e "${BLUE}已取消操作。${PLAIN}"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            5)
                echo -e "${RED}⚠️  高风险：这会停止容器并把 ${project_dir} 移入隔离目录，配置、数据库或本地数据不再原地可用。${PLAIN}"
                echo -e "${YELLOW}隔离后如需彻底清理，请确认无误后手动处理隔离目录。${PLAIN}"
                if confirm_risk_action "归档 ${project_name} 部署目录" \
                    "Docker Compose 容器、部署目录、配置和本地数据位置" \
                    "从 /opt/.vps-optimize-quarantine 手动移回原路径后重新启动" \
                    "确认已经备份数据库和配置，且服务可以中断。"; then
                    if ! is_managed_compose_dir "$project_dir"; then
                        echo -e "${RED}❌ 安全检查未通过，拒绝归档非脚本托管目录：${project_dir}${PLAIN}"
                    else
                        ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                        (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down -v)
                        if quarantine_path "$project_dir" "/opt/.vps-optimize-quarantine"; then
                            echo -e "${GREEN}✅ 已归档 ${project_name} 部署目录。${PLAIN}"
                        else
                            echo -e "${RED}❌ 归档失败，请手动检查目录：${project_dir}${PLAIN}"
                        fi
                    fi
                else
                    echo -e "${BLUE}已取消归档。${PLAIN}"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            0) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_manage_sublinkpro() {
    manage_compose_project "SublinkPro" "/opt/sublinkpro" "db / template / logs 会保存在部署目录中"
}

func_manage_miaomiaowu() {
    manage_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" "data / subscribes / rule_templates 会保存在部署目录中"
}

func_manage_substore() {
    manage_compose_project "Sub-Store" "/opt/sub-store" "data 会保存在部署目录中"
}

func_manage_dockge() {
    manage_compose_project "Dockge" "/opt/dockge" "Dockge 数据在 /opt/dockge/data；Stacks 默认在 /opt/stacks，不会随 Dockge 目录删除"
}

func_manage_komari() {
    manage_compose_project "Komari" "/opt/komari" "Komari 数据会保存在 /opt/komari/data"
}

func_service_action_menu() {
    local title="$1"
    local usage="$2"
    local install_label="$3"
    local install_func="$4"
    local manage_label="$5"
    local manage_func="$6"
    local choice

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "面板、节点与订阅工具 > ${title}"
        echo -e "${BOLD}🧭 ${title}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}${usage}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. ${install_label}${PLAIN}"
        echo -e "${GREEN}  2. ${manage_label}${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "👉 请选择操作: "

        case "$choice" in
            1) "$install_func" ;;
            2) "$manage_func" ;;
            0|q|Q) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_xpanel_menu() {
    func_service_action_menu "3x-ui / x-ui 面板" "安装或进入官方菜单进行配置、更新、重置、卸载。" "安装 3x-ui 面板" func_xpanel "管理 / 卸载 3x-ui 面板" func_xpanel_manage
}

func_sui_menu() {
    func_service_action_menu "S-UI 面板" "安装或进入 S-UI 官方菜单进行配置、更新、卸载。" "安装 S-UI 面板" func_sui_panel "管理 / 卸载 S-UI 面板" func_sui_manage
}

func_singbox_menu() {
    local choice

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 Sing-box 管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}可选择不同一键脚本安装，也可进入已安装脚本的管理菜单。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 安装 Sing-box（甬哥四合一脚本）${PLAIN}"
        echo -e "${GREEN}  2. 安装 Sing-box（233boy 一键脚本）${PLAIN}"
        echo -e "${GREEN}  3. 管理 / 卸载 Sing-box${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "👉 请选择操作: "

        case "$choice" in
            1) func_singbox ;;
            2) func_singbox_233boy ;;
            3) func_singbox_manage ;;
            0) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_xray_menu() {
    func_service_action_menu "Xray 管理" "安装或进入 233boy Xray 官方菜单进行配置、更新、卸载。" "安装 Xray（233boy 一键脚本）" func_xray_233boy "管理 / 卸载 Xray" func_xray_manage
}

func_sublinkpro_menu() {
    func_service_action_menu "SublinkPro 管理" "安装或管理 Docker Compose 部署的 SublinkPro。" "安装 SublinkPro" func_sublinkpro "管理 / 卸载 SublinkPro" func_manage_sublinkpro
}

func_miaomiaowu_menu() {
    func_service_action_menu "妙妙屋订阅管理" "安装或管理 Docker Compose 部署的妙妙屋订阅管理。" "安装 妙妙屋订阅管理" func_miaomiaowu "管理 / 卸载 妙妙屋" func_manage_miaomiaowu
}

func_substore_menu() {
    func_service_action_menu "Sub-Store 管理" "安装或管理 Docker Compose 部署的 Sub-Store。" "安装 Sub-Store" func_substore "管理 / 卸载 Sub-Store" func_manage_substore
}

func_dockge_menu() {
    func_service_action_menu "Dockge 管理" "安装或管理 Docker Compose 部署的 Dockge。" "安装 Dockge" func_dockge "管理 / 卸载 Dockge" func_manage_dockge
}

func_komari_menu() {
    func_service_action_menu "Komari 探针监控" "安装或管理 Docker Compose 部署的 Komari 探针监控面板。" "安装 Komari" func_komari "管理 / 卸载 Komari" func_manage_komari
}

is_dockge_migration_seen() {
    local needle="$1"
    local item
    for item in "${DOCKGE_MIGRATION_DIRS[@]}"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

add_dockge_migration_candidate() {
    local dir="$1"
    local stacks_dir="$2"
    local name

    dir="${dir%/}"
    [[ -d "$dir" ]] || return 0
    [[ "$dir" == "/opt/dockge" ]] && return 0
    [[ "$dir" == "$stacks_dir" || "$dir" == "$stacks_dir"/* ]] && return 0
    find_compose_file "$dir" >/dev/null 2>&1 || return 0
    is_dockge_migration_seen "$dir" && return 0

    name=$(basename "$dir")
    DOCKGE_MIGRATION_NAMES+=("$name")
    DOCKGE_MIGRATION_DIRS+=("$dir")
}

discover_dockge_migration_candidates() {
    local stacks_dir="$1"
    local dir file
    DOCKGE_MIGRATION_NAMES=()
    DOCKGE_MIGRATION_DIRS=()

    for dir in /opt/sublinkpro /opt/miaomiaowu /opt/sub-store; do
        add_dockge_migration_candidate "$dir" "$stacks_dir"
    done

    for file in /opt/*/compose.yaml /opt/*/compose.yml /opt/*/docker-compose.yml /opt/*/docker-compose.yaml; do
        [[ -e "$file" ]] || continue
        add_dockge_migration_candidate "$(dirname "$file")" "$stacks_dir"
    done
}

migrate_compose_project_to_dockge() {
    local source_dir="$1"
    local stacks_dir="$2"
    local source_compose stack_name target_dir compose_name restart_confirm
    local restart_stack="true"

    source_dir="${source_dir%/}"
    source_compose=$(find_compose_file "$source_dir") || {
        echo -e "${RED}❌ 未找到 Compose 配置：${source_dir}${PLAIN}"
        return 1
    }

    stack_name=$(ask_with_default "Dockge stack 名称" "$(basename "$source_dir")")
    if [[ ! "$stack_name" =~ ^[A-Za-z0-9_.-]+$ || "$stack_name" == "." || "$stack_name" == ".." ]]; then
        echo -e "${RED}❌ stack 名称无效，只能使用字母、数字、点、下划线和短横线。${PLAIN}"
        return 1
    fi

    target_dir="${stacks_dir%/}/${stack_name}"
    if [[ "$source_dir" == "$target_dir" ]]; then
        echo -e "${YELLOW}⚠️ ${source_dir} 已经在 Dockge stacks 目录内，已跳过。${PLAIN}"
        return 0
    fi
    if [[ -e "$target_dir" ]]; then
        echo -e "${RED}❌ 目标目录已存在：${target_dir}${PLAIN}"
        echo -e "${YELLOW}请先在 Dockge 中确认是否已有同名 stack，或换一个 stack 名称。${PLAIN}"
        return 1
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}将迁移：${CYAN}${source_dir}${PLAIN}"
    echo -e "${YELLOW}迁移到：${CYAN}${target_dir}${PLAIN}"
    echo -e "${YELLOW}Compose：${CYAN}${source_compose}${PLAIN}"
    echo -e "${YELLOW}说明：会移动整个项目目录，保留相对挂载的数据目录。${PLAIN}"
    echo -e "${YELLOW}如果项目使用 Docker 命名卷，建议保持 stack 名称与原目录名一致。${PLAIN}"
    confirm_risk_action "迁移 Compose 项目到 Dockge" \
        "Compose 项目目录、容器停止/启动位置和 Dockge stack 路径" \
        "把 ${target_dir} 手动移回 ${source_dir}，并用原 compose 文件重新启动" \
        "确认项目没有绝对路径依赖，且已备份重要数据。" || { echo -e "${BLUE}已取消迁移 ${source_dir}。${PLAIN}"; return 0; }

    read_trimmed restart_confirm "是否先停止旧容器并在新目录重新启动？(Y/n): "
    if [[ "$restart_confirm" =~ ^[Nn]$ ]]; then
        restart_stack="false"
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在停止旧目录中的 Compose 项目...${PLAIN}"
        ( cd "$source_dir" && $DOCKER_COMPOSE_CMD down ) || {
            echo -e "${RED}❌ 停止旧项目失败，已中止迁移。${PLAIN}"
            return 1
        }
    fi

    mkdir -p "$stacks_dir" || return 1
    mv "$source_dir" "$target_dir" || {
        echo -e "${RED}❌ 移动目录失败：${source_dir} -> ${target_dir}${PLAIN}"
        return 1
    }

    compose_name=$(basename "$source_compose")
    if [[ "$compose_name" == docker-compose.y* && ! -f "${target_dir}/compose.yaml" ]]; then
        mv "${target_dir}/${compose_name}" "${target_dir}/compose.yaml" || {
            echo -e "${RED}❌ 重命名 Compose 文件失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在新目录中重新启动 Compose 项目...${PLAIN}"
        ( cd "$target_dir" && $DOCKER_COMPOSE_CMD up -d ) || {
            echo -e "${RED}❌ 新目录启动失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    echo -e "${GREEN}✅ 已迁移到 Dockge stacks：${target_dir}${PLAIN}"
    echo -e "${YELLOW}请在 Dockge 页面里扫描/刷新 stacks 目录后接管。${PLAIN}"
}

func_migrate_compose_to_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}迁移已有 Compose 项目到 Dockge${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适合 Dockge 后安装的场景：把已有 docker-compose.yml / compose.yaml 项目移动到 Dockge stacks 目录。${PLAIN}"
    echo -e "${YELLOW}建议先确认相关服务可以短暂停机，并已做好重要数据备份。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local stacks_dir="/opt/stacks"
    local choice custom_dir i
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")
    mkdir -p "$stacks_dir" || { echo -e "${RED}❌ 无法创建 stacks 目录：${stacks_dir}${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    discover_dockge_migration_candidates "$stacks_dir"

    if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -gt 0 ]]; then
        echo -e "${GREEN}检测到以下可迁移 Compose 项目：${PLAIN}"
        for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
            echo -e "${GREEN}  $((i + 1)). ${DOCKGE_MIGRATION_NAMES[$i]}${PLAIN} ${CYAN}(${DOCKGE_MIGRATION_DIRS[$i]})${PLAIN}"
        done
        echo -e "${BOLD}${YELLOW}  a. 迁移全部检测到的项目${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 未在 /opt 下检测到常见 Compose 项目。${PLAIN}"
    fi
    echo -e "${CYAN}  c. 手动输入项目目录${PLAIN}"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "------------------------------------------------"

    read_trimmed choice "请选择要迁移的项目: "
    case "$choice" in
        0) return ;;
        a|A)
            if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -eq 0 ]]; then
                echo -e "${YELLOW}⚠️ 没有可自动迁移的项目。${PLAIN}"
            else
                for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
                    migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$i]}" "$stacks_dir" || true
                    echo -e "------------------------------------------------"
                done
            fi
            ;;
        c|C)
            read_trimmed custom_dir "请输入已有 Compose 项目目录: "
            migrate_compose_project_to_dockge "$custom_dir" "$stacks_dir"
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DOCKGE_MIGRATION_DIRS[@]} )); then
                migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$((choice - 1))]}" "$stacks_dir"
            else
                echo -e "${RED}❌ 无效选择！${PLAIN}"
            fi
            ;;
    esac

    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 18. 面板救砖/重置 SSL (兼容新版 3x-ui 证书字段)
# ---------------------------------------------------------
func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚑 面板紧急救砖 / SSL 清理工具${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：清空 3x-ui 面板证书路径，让 Caddy 可以按 HTTP 反代本机面板。${PLAIN}"
    echo -e "更推荐在 3x-ui 面板里手动进入：面板设置 -> 常规 -> 证书，把证书路径和私钥路径清空后保存重启。"
    echo -e "本功能只作为打不开面板时的救急方案，会尝试清空常见证书字段：webCertFile/webKeyFile/CertFile/KeyFile 等。"
    echo -e "------------------------------------------------"
    
    local yn
    read_trimmed yn "❓ 确定要清空面板证书路径并尝试退回 HTTP 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        
        # 核心修改：使用我们的全局极简包管理器！兼容了包名差异。
        if ! command -v sqlite3 >/dev/null 2>&1; then
            echo -e "${CYAN}▶ 正在安装 sqlite3 数据库工具...${PLAIN}"
            install_pkg sqlite3 sqlite
        fi
        
        local xui_bin=""
        if [[ -x /usr/local/x-ui/x-ui ]]; then
            xui_bin="/usr/local/x-ui/x-ui"
        elif command -v x-ui >/dev/null 2>&1; then
            xui_bin="$(command -v x-ui)"
        elif command -v 3x-ui >/dev/null 2>&1; then
            xui_bin="$(command -v 3x-ui)"
        fi
        if [[ -n "$xui_bin" ]]; then
            echo -e "${CYAN}当前 3x-ui 证书状态：${PLAIN}"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi

        # 停服务
        systemctl stop x-ui >/dev/null 2>&1
        systemctl stop 3x-ui >/dev/null 2>&1
        systemctl stop x-panel >/dev/null 2>&1
        
        local cert_cmd_done=false
        if [[ -n "$xui_bin" ]]; then
            if "$xui_bin" cert -webCert "" -webCertKey "" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ 已通过 3x-ui 官方 cert 命令清空面板与订阅证书路径。${PLAIN}"
                cert_cmd_done=true
            else
                echo -e "${YELLOW}⚠️ 官方 cert 命令清理失败，将继续尝试直接修正数据库。${PLAIN}"
            fi
        fi

        # 新版/旧版字段名不完全一致，所以按 key 的小写形式兼容面板和订阅证书字段。
        local db_found=false
        local cert_key_sql
        local db_path
        cert_key_sql=$(xui_cert_setting_key_sql_list)
        while IFS= read -r db_path; do
            if [[ -f "$db_path" ]]; then
                if sqlite3 "$db_path" "update settings set value='' where lower(key) in (${cert_key_sql});" 2>/dev/null; then
                    echo -e "${GREEN}✅ 已清空常见 SSL 证书字段：${db_path}${PLAIN}"
                    db_found=true
                else
                    echo -e "${YELLOW}⚠️ 数据库存在但更新失败：${db_path}${PLAIN}"
                fi
            fi
        done < <(find_xui_database_candidates)
        
        if ! $db_found && ! $cert_cmd_done; then
            echo -e "${RED}❌ 未检测到常见面板的数据库文件！您可能没有安装 x-ui 或 x-panel。${PLAIN}"
        elif ! $db_found; then
            echo -e "${YELLOW}⚠️ 未在常见路径找到数据库，已依赖官方 cert 命令处理。${PLAIN}"
        fi
        
        # 重启服务
        systemctl restart x-ui >/dev/null 2>&1 || systemctl start x-ui >/dev/null 2>&1
        systemctl restart 3x-ui >/dev/null 2>&1 || systemctl start 3x-ui >/dev/null 2>&1
        systemctl start x-panel >/dev/null 2>&1
        
        echo -e "------------------------------------------------"
        if [[ -n "$xui_bin" ]]; then
            echo -e "${CYAN}清理后的 3x-ui 证书状态：${PLAIN}"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi
        echo -e "${GREEN}✅ 已尝试清空证书路径。${PLAIN}"
        echo -e "${YELLOW}请用本机测试确认协议：curl -I http://127.0.0.1:面板端口/你的面板路径/${PLAIN}"
        echo -e "${YELLOW}如果 HTTP 仍不通，请先进入 3x-ui 官方菜单或面板设置确认常规证书、订阅证书路径都已清空并重启面板。${PLAIN}"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 新增功能：网络端口占用可视化排查与进程查杀 (底层调用优化版)
# ---------------------------------------------------------
func_port_kill() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🔍 网络端口占用排查与进程释放${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}当前系统中正在监听的活动端口列表：${PLAIN}"
        echo -e "------------------------------------------------"
        printf "%-10s %-15s %-20s\n" "协议" "端口" "关联进程 (PID)"
        
        ss -tulnp | grep -E 'LISTEN|UNCONN' | while read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local port=$(echo "$line" | awk '{print $5}' | awk -F: '{print $NF}')
            local pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
            local proc=$(echo "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
            
            local proc_info=""
            if [[ -z "$proc" || -z "$pid" ]]; then
                proc_info="系统底层 / 无权限读取"
            else
                proc_info="$proc (PID: $pid)"
            fi
            printf "%-10s %-15s %-20s\n" "$proto" "$port" "$proc_info"
        done | sort -n -k2 | uniq
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}👉 指南：找到您想释放的冲突端口，输入它即可强杀对应进程。${PLAIN}"
        echo -e "${RED}⚠️ 高危：请勿随意终止 sshd (通常为 22) 的端口，否则会断网失联！${PLAIN}"
        echo -e "------------------------------------------------"
        
        local p_choice
        read_trimmed p_choice "❓ 请输入要强杀释放的端口号 (输入 0 返回主菜单): "
        
        if [[ "$p_choice" == "0" ]]; then break; fi
        
        if is_valid_port "$p_choice"; then
            local ssh_match
            ssh_match=$(ss -tulnp 2>/dev/null | awk -v port="$p_choice" '$5 ~ ":" port "$" && $0 ~ /(sshd|ssh)/ {print}')
            if [[ -n "$ssh_match" || "$p_choice" == "22" ]]; then
                echo -e "${RED}❌ 检测到你选择的是 SSH 相关端口或默认 SSH 端口，为避免失联，已拒绝强杀。${PLAIN}"
                sleep 2
                continue
            fi
            confirm_danger "强杀占用端口 ${p_choice} 的进程" "会对 TCP/UDP ${p_choice} 占用进程发送 SIGKILL，相关服务会立即中断。" "如果杀错服务，需要手动重启对应 systemd 服务或容器。" || {
                echo -e "${BLUE}已取消强杀操作。${PLAIN}"
                sleep 1
                continue
            }
            echo -e "${CYAN}▶ 正在调用底层系统命令强杀端口 $p_choice ...${PLAIN}"
            
            # [依赖前置检查]: 确保存在 fuser 工具
            if ! command -v fuser >/dev/null 2>&1; then
                install_pkg psmisc
            fi
            
            # [极简实现]: 一行代码杀掉占用该 TCP/UDP 端口的所有进程
            if fuser -k -9 -n tcp "$p_choice" >/dev/null 2>&1 || fuser -k -9 -n udp "$p_choice" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ 目标进程已被系统底层强制回收 (SIGKILL)。端口已释放！${PLAIN}"
            else
                echo -e "${BLUE}ℹ️ 未发现任何可被终止的进程占用该端口，或权限不足。${PLAIN}"
            fi
            sleep 2
        else
            echo -e "${RED}❌ 输入无效！请输入纯数字端口号。${PLAIN}"
            sleep 1
        fi
    done
}

func_reboot_server() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔁 重启服务器${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    confirm_danger "立即重启服务器" "当前 SSH 会话会断开，所有运行中的服务会短暂中断。" "请确认云厂商控制台可用，并确保关键配置已经保存。" || {
        echo -e "${BLUE}已取消重启操作。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    }
    reboot
}
# ---------------------------------------------------------
# 19. 脚本热更新
# ---------------------------------------------------------
fetch_latest_script_version() {
    local line version
    if command -v curl >/dev/null 2>&1; then
        line=$(curl -fsSL --connect-timeout 4 --max-time 10 "$UPDATE_URL" 2>/dev/null | grep -m1 '^SCRIPT_VERSION=' || true)
    elif command -v wget >/dev/null 2>&1; then
        line=$(wget -q --timeout=10 --tries=1 -O - "$UPDATE_URL" 2>/dev/null | grep -m1 '^SCRIPT_VERSION=' || true)
    else
        return 1
    fi
    [[ -n "$line" ]] || return 1
    version="${line#SCRIPT_VERSION=}"
    version="${version%\"}"
    version="${version#\"}"
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

version_is_newer() {
    local latest="${1#v}"
    local current="${2#v}"
    local l1=0 l2=0 l3=0 c1=0 c2=0 c3=0
    IFS='.' read -r l1 l2 l3 <<< "$latest"
    IFS='.' read -r c1 c2 c3 <<< "$current"
    l1=${l1:-0}; l2=${l2:-0}; l3=${l3:-0}
    c1=${c1:-0}; c2=${c2:-0}; c3=${c3:-0}
    [[ "$l1$l2$l3$c1$c2$c3" =~ ^[0-9]+$ ]] || return 1
    (( 10#$l1 > 10#$c1 )) && return 0
    (( 10#$l1 < 10#$c1 )) && return 1
    (( 10#$l2 > 10#$c2 )) && return 0
    (( 10#$l2 < 10#$c2 )) && return 1
    (( 10#$l3 > 10#$c3 ))
}

script_update_cache_is_fresh() {
    local now mtime
    [[ -f "$SCRIPT_UPDATE_CACHE" ]] || return 1
    now=$(date +%s 2>/dev/null || echo 0)
    mtime=$(stat -c %Y "$SCRIPT_UPDATE_CACHE" 2>/dev/null || echo 0)
    [[ "$now" =~ ^[0-9]+$ && "$mtime" =~ ^[0-9]+$ ]] || return 1
    (( now > mtime && now - mtime < 43200 ))
}

read_script_update_cache_field() {
    local key="$1"
    grep -m1 "^${key}=" "$SCRIPT_UPDATE_CACHE" 2>/dev/null | cut -d= -f2-
}

write_script_update_cache() {
    local status="$1"
    local latest="$2"
    local message="$3"
    local cache_dir
    cache_dir=$(dirname "$SCRIPT_UPDATE_CACHE")
    mkdir -p "$cache_dir" 2>/dev/null || return 0
    {
        echo "status=${status}"
        echo "latest=${latest}"
        echo "message=${message}"
        echo "checked_at=$(date -Is 2>/dev/null || date)"
    } > "$SCRIPT_UPDATE_CACHE" 2>/dev/null || true
}

check_script_update_status() {
    local mode="${1:-auto}"
    local status latest message
    if [[ "$mode" != "force" ]] && script_update_cache_is_fresh; then
        status=$(read_script_update_cache_field status)
        latest=$(read_script_update_cache_field latest)
        if [[ -n "$latest" && "$latest" != "unknown" ]]; then
            if version_is_newer "$latest" "$SCRIPT_VERSION"; then
                status="available"
            else
                status="current"
            fi
        fi
        printf '%s|%s\n' "${status:-unknown}" "${latest:-unknown}"
        return 0
    fi

    if latest=$(fetch_latest_script_version); then
        if version_is_newer "$latest" "$SCRIPT_VERSION"; then
            status="available"
            message="发现新版本 ${latest}"
        else
            status="current"
            message="当前已是最新版本"
        fi
        write_script_update_cache "$status" "$latest" "$message"
        printf '%s|%s\n' "$status" "$latest"
        return 0
    fi

    write_script_update_cache "error" "unknown" "无法检查更新"
    printf 'error|unknown\n'
}

print_auto_update_notice() {
    local result status latest
    result=$(check_script_update_status "auto" 2>/dev/null || true)
    status="${result%%|*}"
    latest="${result#*|}"
    case "$status" in
        available)
            echo -e " ${BOLD}${YELLOW}更新提示:${PLAIN} 检测到 ${CYAN}${latest}${PLAIN}，输入 ${YELLOW}u${PLAIN} 可无缝更新发布版。"
            ;;
        current)
            echo -e " ${BLUE}更新状态:${PLAIN} 当前 ${SCRIPT_VERSION}，未发现更高的发布版。"
            ;;
    esac
}

func_update_script() {
    clear
    local tmp_file sha_file
    tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh) || {
        echo -e "${RED}❌ 临时文件创建失败，更新已取消。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    }
    sha_file=$(mktemp /tmp/cy_update.XXXXXX.sha256) || {
        rm -f "$tmp_file"
        echo -e "${RED}❌ 临时校验文件创建失败，更新已取消。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    }
    echo -e "${CYAN}👉 正在从 GitHub 源地址拉取最新版本...${PLAIN}"
    if download_remote_script "$UPDATE_URL" "$tmp_file" \
        && bash -n "$tmp_file" \
        && download_remote_script "$UPDATE_SHA256_URL" "$sha_file" \
        && verify_file_sha256 "$tmp_file" "$sha_file" \
        && grep -q "func_sni_stack_quick_menu" "$tmp_file" 2>/dev/null \
        && grep -q "main_menu" "$tmp_file" 2>/dev/null \
        && ! grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*src/' "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" /usr/local/bin/cy
        chmod +x /usr/local/bin/cy
        rm -f "$sha_file"
        echo -e "${GREEN}✅ 更新下载并覆盖完成！正在重启面板...${PLAIN}"
        sleep 1
        exec bash /usr/local/bin/cy
    else
        rm -f "$tmp_file" "$sha_file"
        echo -e "${RED}❌ 更新失败！请检查您的网络连通性或 GitHub 地址是否正确。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# ---------------------------------------------------------
# 20. 一键运维预检
# ---------------------------------------------------------
preflight_install_missing_commands() {
    local missing=("$@")
    local pkgs=()
    local cmd

    for cmd in "${missing[@]}"; do
        case "$cmd" in
            curl) pkgs+=("curl") ;;
            wget) pkgs+=("wget") ;;
            ss)
                if is_debian; then
                    pkgs+=("iproute2")
                elif is_redhat; then
                    pkgs+=("iproute")
                fi
                ;;
        esac
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "${CYAN}▶ 正在安装缺失基础命令: ${missing[*]}${PLAIN}"
    install_pkg "${pkgs[@]}"
}

preflight_missing_minimal_compat_items() {
    local missing=()
    local cmd svc
    local commands=(curl wget ss ip getent tar gzip openssl jq awk sed grep pgrep journalctl timedatectl)
    local services=()

    for cmd in "${commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("cmd:$cmd")
    done

    if is_debian; then
        services=(cron dbus chrony)
    elif is_redhat; then
        services=(crond dbus chronyd)
    fi

    for svc in "${services[@]}"; do
        systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | awk 'NF {found=1} END {exit found ? 0 : 1}' || missing+=("svc:$svc")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '%s\n' "${missing[@]}"
    fi
}

preflight_enable_ntp() {
    local ntp_sync
    echo -e "${CYAN}▶ 正在尝试开启系统 NTP 时间同步...${PLAIN}"

    if is_debian; then
        install_pkg chrony
    elif is_redhat; then
        install_pkg chrony
    fi

    timedatectl set-ntp true >/dev/null 2>&1 || true
    systemctl enable --now chrony >/dev/null 2>&1 || true
    systemctl enable --now chronyd >/dev/null 2>&1 || true

    if command -v chronyc >/dev/null 2>&1; then
        chronyc -a 'burst 4/4' >/dev/null 2>&1 || true
        chronyc -a makestep >/dev/null 2>&1 || true
    else
        systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
    fi

    sleep 2
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "${GREEN}✅ NTP 时间同步已恢复。${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ NTP 仍未同步，下面是诊断信息：${PLAIN}"
        timedatectl status 2>/dev/null || true
        chronyc tracking 2>/dev/null || true
        chronyc sources -v 2>/dev/null || true
        journalctl -u chrony -u chronyd -u systemd-timesyncd -n 20 --no-pager 2>/dev/null || true
    fi
}

func_preflight_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧪 一键运维预检 (网络/系统/资源/包管理/精简系统兼容)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0

    echo -e "${YELLOW}▶ [1/8] 检查系统运行状态...${PLAIN}"
    local sys_state
    sys_state=$(systemctl is-system-running 2>/dev/null)
    sys_state=${sys_state:-unknown}
    if [[ "$sys_state" == "running" ]]; then
        echo -e "${GREEN}✅ systemd 状态正常: $sys_state${PLAIN}"
        ((ok_count++))
    elif [[ "$sys_state" == "degraded" ]]; then
        echo -e "${YELLOW}⚠️ systemd 状态降级: $sys_state${PLAIN}"
        systemctl --failed --no-legend --no-pager 2>/dev/null | awk 'NF {print "   - " $1 " (" $2 ")"}' | head -n 8
        ((warn_count++))
    else
        echo -e "${RED}❌ systemd 状态异常: $sys_state${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [2/8] 检查公网连通性...${PLAIN}"
    local ipv4
    ipv4=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null)
    if [[ -n "$ipv4" ]]; then
        echo -e "${GREEN}✅ IPv4 连通正常: ${ipv4}${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 未检测到公网 IPv4，可能为纯 IPv6 或网络受限${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [3/8] 检查 DNS 解析能力...${PLAIN}"
    if getent ahosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${GREEN}✅ DNS 解析正常 (raw.githubusercontent.com)${PLAIN}"
        ((ok_count++))
    else
        echo -e "${RED}❌ DNS 解析失败，后续远程脚本可能无法下载${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [4/8] 检查时间同步状态...${PLAIN}"
    local ntp_sync
    local can_fix_ntp=false
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [[ "$ntp_sync" == "yes" ]]; then
        echo -e "${GREEN}✅ NTP 时间同步正常${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ NTP 未同步，可能影响证书签发与仓库校验${PLAIN}"
        can_fix_ntp=true
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/8] 检查磁盘空间...${PLAIN}"
    local root_use
    root_use=$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')
    if [[ -n "$root_use" && "$root_use" -lt 80 ]]; then
        echo -e "${GREEN}✅ 根分区使用率健康: ${root_use}%${PLAIN}"
        ((ok_count++))
    elif [[ -n "$root_use" && "$root_use" -lt 90 ]]; then
        echo -e "${YELLOW}⚠️ 根分区使用率偏高: ${root_use}%${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ 根分区使用率危险: ${root_use:-未知}%${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [6/8] 检查可用内存...${PLAIN}"
    local mem_avail
    mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
    [[ -z "$mem_avail" ]] && mem_avail=$(free -m | awk '/^Mem:/ {print $4}')
    if [[ -n "$mem_avail" && "$mem_avail" -ge 300 ]]; then
        echo -e "${GREEN}✅ 可用内存充足: ${mem_avail}MB${PLAIN}"
        ((ok_count++))
    elif [[ -n "$mem_avail" && "$mem_avail" -ge 150 ]]; then
        echo -e "${YELLOW}⚠️ 可用内存偏低: ${mem_avail}MB${PLAIN}"
        ((warn_count++))
    else
        echo -e "${RED}❌ 可用内存过低: ${mem_avail:-未知}MB${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [7/8] 检查包管理器占用...${PLAIN}"
    local pkg_busy=false
    if is_debian; then
        pgrep -x apt >/dev/null 2>&1 && pkg_busy=true
        pgrep -x apt-get >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dpkg >/dev/null 2>&1 && pkg_busy=true
    elif is_redhat; then
        pgrep -x yum >/dev/null 2>&1 && pkg_busy=true
        pgrep -x dnf >/dev/null 2>&1 && pkg_busy=true
        pgrep -x rpm >/dev/null 2>&1 && pkg_busy=true
    fi

    if $pkg_busy; then
        echo -e "${YELLOW}⚠️ 检测到包管理器正在运行，建议稍后再安装软件${PLAIN}"
        ((warn_count++))
    else
        echo -e "${GREEN}✅ 包管理器空闲，可安全执行安装任务${PLAIN}"
        ((ok_count++))
    fi

    echo -e "${YELLOW}▶ [8/9] 检查关键命令可用性...${PLAIN}"
    local cmd_miss=()
    command -v curl >/dev/null 2>&1 || cmd_miss+=("curl")
    command -v wget >/dev/null 2>&1 || cmd_miss+=("wget")
    command -v ss >/dev/null 2>&1 || cmd_miss+=("ss")
    if [[ ${#cmd_miss[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 关键命令齐全${PLAIN}"
        ((ok_count++))
    else
        echo -e "${RED}❌ 缺少关键命令: ${cmd_miss[*]}${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [9/9] 检查精简系统兼容组件...${PLAIN}"
    local minimal_miss=()
    mapfile -t minimal_miss < <(preflight_missing_minimal_compat_items)
    if [[ ${#minimal_miss[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 精简系统兼容组件齐全${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 检测到精简系统缺少组件/服务:${PLAIN}"
        printf '  - %s\n' "${minimal_miss[@]}"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "${CYAN}📌 预检汇总: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "${RED}⚠️ 建议先修复异常项，再进行环境部署和系统改造。${PLAIN}"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "${YELLOW}💡 当前可继续操作，但建议先处理警告项以提升稳定性。${PLAIN}"
    else
        echo -e "${GREEN}🎉 当前环境健康，可直接进行后续部署。${PLAIN}"
    fi

    if ! $pkg_busy && { $can_fix_ntp || [[ ${#cmd_miss[@]} -gt 0 ]] || [[ ${#minimal_miss[@]} -gt 0 ]]; }; then
        local fix_confirm rerun_confirm
        echo -e "------------------------------------------------"
        echo -e "${CYAN}🛠️ 可自动处理的简单问题:${PLAIN}"
        $can_fix_ntp && echo -e "  - 开启 NTP 时间同步"
        [[ ${#cmd_miss[@]} -gt 0 ]] && echo -e "  - 安装缺失基础命令: ${cmd_miss[*]}"
        [[ ${#minimal_miss[@]} -gt 0 ]] && echo -e "  - 补齐精简系统兼容组件"
        read_trimmed fix_confirm "是否现在自动修复这些简单问题？(y/N): "
        if [[ "$fix_confirm" =~ ^[Yy]$ ]]; then
            [[ ${#minimal_miss[@]} -gt 0 ]] && ensure_minimal_system_compat
            $can_fix_ntp && preflight_enable_ntp
            [[ ${#cmd_miss[@]} -gt 0 ]] && preflight_install_missing_commands "${cmd_miss[@]}"
            echo -e "${GREEN}✅ 简单修复已执行。${PLAIN}"
            read_trimmed rerun_confirm "是否立即重新体检？(y/N): "
            if [[ "$rerun_confirm" =~ ^[Yy]$ ]]; then
                func_preflight_check
                return
            fi
        fi
    elif $pkg_busy; then
        echo -e "${YELLOW}ℹ️ 包管理器正在运行，本次跳过自动安装类修复。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

# ---------------------------------------------------------
# 21. 配置备份与回滚中心
# ---------------------------------------------------------







# ---------------------------------------------------------
# 22. 服务健康总览
# ---------------------------------------------------------
service_state_for_issue() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            echo "运行中"
        else
            echo "已安装/未运行"
        fi
    else
        echo "未检测到"
    fi
}

recent_journal_for_issue() {
    local svc="$1"
    if service_unit_exists "$svc"; then
        journalctl -u "$svc" -n 8 --no-pager 2>/dev/null | redact_sensitive_output
    else
        echo "未检测到 ${svc} 服务"
    fi
}

generate_issue_diagnostics() {
    local os_desc kernel arch now script_path firewall_status latest_backups log_path
    os_desc="未知"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_desc="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}"
    fi
    kernel=$(uname -r 2>/dev/null || echo "未知")
    arch=$(uname -m 2>/dev/null || echo "未知")
    now=$(date -Is 2>/dev/null || date)
    script_path=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")

    if command -v ufw >/dev/null 2>&1; then
        firewall_status=$(ufw status 2>/dev/null | head -n 5 | tr '\n' '; ')
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall_status=$(firewall-cmd --state 2>/dev/null || echo "firewalld 未运行")
    else
        firewall_status="未检测到 ufw/firewalld"
    fi

    latest_backups=$(find /etc/vps-optimize/backups -maxdepth 3 -type f -o -type d 2>/dev/null | sort -r | head -n 10)
    [[ -z "$latest_backups" ]] && latest_backups="未检测到"

    log_path=$(find /var/log /tmp /etc/vps-optimize -maxdepth 3 -type f \( -iname '*vps*optimize*.log' -o -iname '*cy*.log' \) 2>/dev/null | sort -r | head -n 5)
    [[ -z "$log_path" ]] && log_path="未检测到"

    echo ""
    echo "===== VPS-Optimize 反馈诊断信息 ====="
    echo "系统版本: ${os_desc}"
    echo "内核版本: ${kernel}"
    echo "CPU 架构: ${arch}"
    echo "脚本版本: ${SCRIPT_VERSION}"
    echo "脚本路径: ${script_path}"
    echo "当前时间: ${now}"
    echo ""
    echo "关键服务状态:"
    for svc in nginx caddy docker xray sing-box; do
        echo "- ${svc}: $(service_state_for_issue "$svc")"
    done
    echo "- 3x-ui 面板: $(xui_panel_state_for_issue)"
    echo ""
    echo "监听端口摘要:"
    ss -tulnp 2>/dev/null | sed -E 's/users:\(\("[^"]+",pid=[0-9]+,fd=[0-9]+\)\)/users:(process-redacted)/g' | head -n 30 || echo "未检测到 ss 输出"
    echo ""
    echo "443 占用情况:"
    ss -tulnp 2>/dev/null | grep -E '(:443[[:space:]]|:443$)' || echo "未检测到 443 监听"
    echo ""
    echo "防火墙状态:"
    echo "${firewall_status}"
    echo ""
    echo "最近 Nginx 错误日志摘要:"
    recent_journal_for_issue nginx
    echo ""
    echo "最近 Caddy 错误日志摘要:"
    recent_journal_for_issue caddy
    echo ""
    echo "最近脚本日志路径:"
    echo "${log_path}"
    echo ""
    echo "最近备份列表:"
    echo "${latest_backups}"
    echo "===== 诊断信息结束，请提交前再次检查是否有敏感信息 ====="
}

func_health_dashboard() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "诊断/健康检查"
    echo -e "${BOLD}📈 服务健康总览${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ssh_state="${RED}未运行${PLAIN}"
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
        ssh_state="${GREEN}运行中${PLAIN}"
    fi

    local caddy_state="${RED}未安装/未运行${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            caddy_state="${GREEN}运行中${PLAIN}"
        else
            caddy_state="${YELLOW}已安装但未运行${PLAIN}"
        fi
    fi

    local docker_state="${RED}未安装/未运行${PLAIN}"
    if command -v docker >/dev/null 2>&1; then
        if systemctl is-active --quiet docker; then
            docker_state="${GREEN}运行中${PLAIN}"
        else
            docker_state="${YELLOW}已安装但未运行${PLAIN}"
        fi
    fi

    local f2b_state="${RED}未安装${PLAIN}"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_state="${GREEN}运行中${PLAIN}"
        else
            f2b_state="${YELLOW}已安装但未运行${PLAIN}"
        fi
    fi

    local fw_state="${RED}未启用${PLAIN}"
    if is_debian; then
        if ufw status 2>/dev/null | grep -qwi active; then
            fw_state="${GREEN}UFW 运行中${PLAIN}"
        else
            fw_state="${YELLOW}UFW 未启用${PLAIN}"
        fi
    else
        if systemctl is-active --quiet firewalld; then
            fw_state="${GREEN}Firewalld 运行中${PLAIN}"
        else
            fw_state="${YELLOW}Firewalld 未启用${PLAIN}"
        fi
    fi

    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    [[ -z "$current_p" ]] && current_p=$(grep -i '^Port' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    current_p=${current_p:-22}

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | grep -c .)

    echo -e "SSH 服务状态       : [ $ssh_state ]  监听端口: ${CYAN}${current_p}${PLAIN}"
    echo -e "Caddy 服务状态     : [ $caddy_state ]"
    echo -e "Docker 服务状态    : [ $docker_state ]"
    echo -e "Fail2ban 服务状态  : [ $f2b_state ]"
    echo -e "防火墙服务状态      : [ $fw_state ]"
    echo -e "失败 systemd 单元数 : ${YELLOW}${failed_units}${PLAIN}"
    echo -e "------------------------------------------------"
    print_project_runtime_overview
    echo -e "------------------------------------------------"

    echo -e "${CYAN}🔌 当前监听端口 Top 12${PLAIN}"
    ss -tuln 2>/dev/null | grep -E 'LISTEN|UNCONN' | awk '{print $5}' | awk -F: '{print $NF}' | grep -E '^[0-9]+$' | sort -nu | head -n 12 | tr '\n' ' '
    echo ""

    local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
    [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"

    if [[ -d "$cert_root" ]]; then
        local cert_total=0
        local cert_warn=0
        while IFS= read -r crt; do
            local end_date ts_left days_left
            end_date=$(openssl x509 -enddate -noout -in "$crt" 2>/dev/null | cut -d= -f2-)
            if [[ -n "$end_date" ]]; then
                ts_left=$(( $(date -d "$end_date" +%s 2>/dev/null) - $(date +%s) ))
                days_left=$(( ts_left / 86400 ))
                cert_total=$((cert_total+1))
                if [[ "$days_left" -le 15 ]]; then
                    cert_warn=$((cert_warn+1))
                fi
            fi
        done < <(find "$cert_root" -type f -name "*.crt" 2>/dev/null)

        echo -e "${CYAN}🔐 证书健康摘要${PLAIN}"
        if [[ "$cert_total" -eq 0 ]]; then
            echo -e "${BLUE}ℹ️ 未检索到可分析证书文件。${PLAIN}"
        else
            echo -e "证书总数: ${GREEN}${cert_total}${PLAIN} | 15天内到期: ${YELLOW}${cert_warn}${PLAIN}"
        fi
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}💡 若失败单元 > 0，可执行: systemctl --failed 查看详情。${PLAIN}"
    echo -e "${CYAN}输入 d 生成反馈诊断信息，输入 ? 查看帮助，其他任意键返回。${PLAIN}"
    local health_choice
    read -n 1 -s -r health_choice
    echo ""
    case "$health_choice" in
        d|D) generate_issue_diagnostics; pause_return ;;
        "?") show_health_help; pause_return ;;
    esac
}





dns_write_static_resolv_conf() {
    local v4_servers="$1"
    local v6_servers="$2"
    local server

    if [[ -L /etc/resolv.conf ]]; then
        quarantine_path /etc/resolv.conf "/etc/vps-optimize/quarantine/dns" >/dev/null 2>&1 || return 1
    fi

    {
        echo "# Generated by VPS-Optimize DNS optimization"
        echo "# Updated: $(date -Is 2>/dev/null || date)"
        for server in $v4_servers; do
            echo "nameserver $server"
        done
        for server in $v6_servers; do
            echo "nameserver $server"
        done
        echo "options timeout:2 attempts:3 rotate"
    } > /etc/resolv.conf
}

dns_apply_profile() {
    local profile_name="$1"
    local v4_servers="$2"
    local v6_servers="$3"
    local backup_dir all_servers resolved_active resolv_target

    confirm_risk_action "更改系统 DNS 为 ${profile_name}" \
        "/etc/resolv.conf 和 systemd-resolved DNS 配置" \
        "进入本菜单选择 [5] 恢复最近一次 DNS 备份，或手动恢复 ${DNS_OPTIMIZE_BACKUP_DIR}" \
        "DNS 写错会导致域名解析失败；当前 SSH 连接通常不会立即断开。" || return 1

    backup_dir=$(dns_backup_current_config)
    all_servers="${v4_servers} ${v6_servers}"

    resolved_active=0
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        resolved_active=1
    fi

    if [[ "$resolved_active" -eq 1 ]]; then
        mkdir -p /etc/systemd/resolved.conf.d
        {
            echo "[Resolve]"
            echo "DNS=${all_servers}"
            echo "FallbackDNS="
        } > "$DNS_OPTIMIZE_RESOLVED_DROPIN"
        systemctl restart systemd-resolved >/dev/null 2>&1 || echo -e "${YELLOW}⚠️ systemd-resolved 重启失败，已继续写入静态 resolv.conf。${PLAIN}"

        resolv_target=$(readlink -f /etc/resolv.conf 2>/dev/null || true)
        if [[ "$resolv_target" != /run/systemd/resolve/* ]]; then
            dns_write_static_resolv_conf "$v4_servers" "$v6_servers" || return 1
        fi
    else
        dns_write_static_resolv_conf "$v4_servers" "$v6_servers" || return 1
    fi

    echo -e "${GREEN}✅ DNS 已切换为 ${profile_name}${PLAIN}"
    echo -e "IPv4 DNS: ${CYAN}${v4_servers}${PLAIN}"
    echo -e "IPv6 DNS: ${CYAN}${v6_servers}${PLAIN}"
    echo -e "${YELLOW}已备份旧配置：${backup_dir}${PLAIN}"

    if getent hosts raw.githubusercontent.com >/dev/null 2>&1; then
        echo -e "${GREEN}✅ DNS 解析测试通过。${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ DNS 解析测试未通过，请检查网络、IPv6 可用性或 DNS 服务器连通性。${PLAIN}"
    fi
}


func_dns_optimize() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "网络/内核优化 > DNS 更改优化"
        echo -e "${BOLD}DNS 更改优化${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}国内默认：IPv4 223.5.5.5 / 119.29.29.29，IPv6 2400:3200::1 / 2402:4e00::${PLAIN}"
        echo -e "${YELLOW}国外默认：IPv4 1.1.1.1 / 8.8.8.8，IPv6 2606:4700:4700::1111 / 2001:4860:4860::8888${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 使用国内 DNS${PLAIN}       ${YELLOW}(阿里 DNS + DNSPod)${PLAIN}"
        echo -e "${GREEN}  2. 使用国外 DNS${PLAIN}       ${YELLOW}(Cloudflare + Google)${PLAIN}"
        echo -e "${GREEN}  3. 自定义 DNS${PLAIN}         ${YELLOW}(分别输入 IPv4 / IPv6)${PLAIN}"
        echo -e "${GREEN}  4. 查看当前 DNS${PLAIN}"
        echo -e "${GREEN}  5. 恢复最近一次 DNS 备份${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  0. 返回上一级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice v4_servers v6_servers raw_v4 raw_v6
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                dns_apply_profile "国内 DNS" "223.5.5.5 119.29.29.29" "2400:3200::1 2402:4e00::"
                pause_return
                ;;
            2)
                dns_apply_profile "国外 DNS" "1.1.1.1 8.8.8.8" "2606:4700:4700::1111 2001:4860:4860::8888"
                pause_return
                ;;
            3)
                read_trimmed raw_v4 "请输入 IPv4 DNS（用逗号或空格分隔）: "
                read_trimmed raw_v6 "请输入 IPv6 DNS（用逗号或空格分隔）: "
                v4_servers=$(dns_normalize_servers 4 "$raw_v4") || {
                    echo -e "${RED}❌ IPv4 DNS 格式无效。${PLAIN}"
                    pause_return
                    continue
                }
                v6_servers=$(dns_normalize_servers 6 "$raw_v6") || {
                    echo -e "${RED}❌ IPv6 DNS 格式无效。${PLAIN}"
                    pause_return
                    continue
                }
                dns_apply_profile "自定义 DNS" "$v4_servers" "$v6_servers"
                pause_return
                ;;
            4)
                echo -e "${CYAN}--- /etc/resolv.conf ---${PLAIN}"
                sed -n '1,80p' /etc/resolv.conf 2>/dev/null || true
                if command -v resolvectl >/dev/null 2>&1; then
                    echo -e "\n${CYAN}--- resolvectl dns ---${PLAIN}"
                    resolvectl dns 2>/dev/null || true
                fi
                pause_return
                ;;
            5) dns_restore_latest_backup; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 23. 流量达量关机保护
# ---------------------------------------------------------
traffic_guard_human_bytes() {
    local bytes="${1:-0}"
    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB PB", u, " ");
        i=1;
        while (b >= 1024 && i < 6) { b=b/1024; i++ }
        if (i == 1) printf "%.0f%s", b, u[i]; else printf "%.2f%s", b, u[i]
    }'
}

traffic_guard_gb_to_bytes() {
    local gb="$1"
    gb="${gb//，/.}"
    gb="${gb//,/}"
    awk -v gb="$gb" 'BEGIN {
        if (gb !~ /^[0-9]+([.][0-9]+)?$/ || gb <= 0) exit 1;
        printf "%.0f", gb * 1024 * 1024 * 1024
    }'
}

traffic_guard_gb_to_bytes_zero_ok() {
    local gb="$1"
    gb="${gb//，/.}"
    gb="${gb//,/}"
    awk -v gb="$gb" 'BEGIN {
        if (gb !~ /^[0-9]+([.][0-9]+)?$/) exit 1;
        printf "%.0f", gb * 1024 * 1024 * 1024
    }'
}

traffic_guard_bytes_to_gb() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    awk -v b="$bytes" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'
}

traffic_guard_iface_is_physical_candidate() {
    local iface="$1"
    case "$iface" in
        lo|docker*|br-*|veth*|tailscale*|wg*|tun*|tap*|zt*|virbr*|vmnet*|cni*|flannel*|kube*|dummy*|ifb*)
            return 1
            ;;
    esac
    return 0
}

traffic_guard_best_active_iface() {
    local path iface oper rx tx score best_iface="" best_score=-1
    for path in /sys/class/net/*; do
        [[ -e "$path" ]] || continue
        iface="${path##*/}"
        traffic_guard_valid_iface "$iface" || continue
        traffic_guard_iface_is_physical_candidate "$iface" || continue
        oper=$(cat "${path}/operstate" 2>/dev/null || echo "unknown")
        [[ "$oper" == "down" ]] && continue
        rx=$(cat "${path}/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "${path}/statistics/tx_bytes" 2>/dev/null || echo 0)
        [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
        [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
        score=$(( rx + tx ))
        if (( score > best_score )); then
            best_score="$score"
            best_iface="$iface"
        fi
    done
    printf '%s' "$best_iface"
}

traffic_guard_detect_iface() {
    local iface
    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if traffic_guard_valid_iface "$iface" && traffic_guard_iface_is_physical_candidate "$iface"; then
        printf '%s' "$iface"
        return 0
    fi
    iface=$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')
    if traffic_guard_valid_iface "$iface" && traffic_guard_iface_is_physical_candidate "$iface"; then
        printf '%s' "$iface"
        return 0
    fi
    iface=$(ip -o -6 route show default 2>/dev/null | awk '{print $5; exit}')
    if traffic_guard_valid_iface "$iface" && traffic_guard_iface_is_physical_candidate "$iface"; then
        printf '%s' "$iface"
        return 0
    fi
    iface=$(traffic_guard_best_active_iface)
    printf '%s' "$iface"
}

traffic_guard_valid_iface() {
    local iface="$1"
    [[ -n "$iface" && "$iface" != *"/"* && "$iface" != *".."* ]] || return 1
    [[ -r "/sys/class/net/${iface}/statistics/rx_bytes" && -r "/sys/class/net/${iface}/statistics/tx_bytes" ]]
}

traffic_guard_mode_label() {
    case "$1" in
        tx) echo "出站 TX 计费" ;;
        rx) echo "入站 RX 计费" ;;
        total) echo "出入总量 RX+TX" ;;
        max) echo "任一方向达量" ;;
        *) echo "$1" ;;
    esac
}

traffic_guard_normalize_cycle_day() {
    local cycle_day="${1:-1}"
    [[ "$cycle_day" =~ ^[0-9]+$ ]] || cycle_day=1
    cycle_day=$((10#$cycle_day))
    (( cycle_day >= 1 && cycle_day <= 31 )) || cycle_day=1
    printf '%s' "$cycle_day"
}

traffic_guard_cycle_date_for_month() {
    local year_month="$1"
    local cycle_day
    local last_day effective_day
    cycle_day=$(traffic_guard_normalize_cycle_day "${2:-1}")
    last_day=$(date -d "${year_month}-01 +1 month -1 day" +%d 2>/dev/null || echo 31)
    last_day=$((10#$last_day))
    effective_day="$cycle_day"
    (( effective_day > last_day )) && effective_day="$last_day"
    printf '%s-%02d' "$year_month" "$effective_day"
}

traffic_guard_current_cycle_key() {
    local cycle_day="${1:-1}"
    local current_month previous_month current_day reset_date reset_day
    cycle_day=$(traffic_guard_normalize_cycle_day "$cycle_day")
    current_month=$(date +%Y-%m)
    reset_date=$(traffic_guard_cycle_date_for_month "$current_month" "$cycle_day")
    reset_day="${reset_date##*-}"
    current_day=$(date +%d)
    if (( 10#$current_day >= 10#$reset_day )); then
        printf '%s' "$reset_date"
    else
        previous_month=$(date -d "${current_month}-01 -1 month" +%Y-%m)
        traffic_guard_cycle_date_for_month "$previous_month" "$cycle_day"
    fi
}

traffic_guard_read_stats() {
    local iface="$1"
    cat "/sys/class/net/${iface}/statistics/rx_bytes" "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null
}

traffic_guard_mode_usage_bytes() {
    local mode="$1"
    local rx="${2:-0}"
    local tx="${3:-0}"
    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    case "$mode" in
        rx) printf '%s' "$rx" ;;
        total) printf '%s' "$(( rx + tx ))" ;;
        max)
            if (( rx > tx )); then printf '%s' "$rx"; else printf '%s' "$tx"; fi
            ;;
        tx|*) printf '%s' "$tx" ;;
    esac
}

traffic_guard_existing_state_usage() {
    local iface="$1"
    local mode="$2"
    local cycle_day="${3:-}"
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    [[ -r "$TRAFFIC_GUARD_CONFIG" && -r "$state_file" ]] || return 1
    (
        local expected_cycle
        # shellcheck disable=SC1090
        . "$TRAFFIC_GUARD_CONFIG"
        # shellcheck disable=SC1090
        . "$state_file"
        [[ "${IFACE:-}" == "$iface" && "${MODE:-}" == "$mode" ]] || exit 1
        expected_cycle=$(traffic_guard_current_cycle_key "${cycle_day:-${CYCLE_DAY:-1}}")
        [[ "${CYCLE_KEY:-}" == "$expected_cycle" ]] || exit 1
        [[ "${LAST_USAGE:-}" =~ ^[0-9]+$ ]] || exit 1
        printf '%s' "$LAST_USAGE"
    )
}

traffic_guard_detect_initial_used_bytes() {
    local iface="$1"
    local mode="$2"
    local current_stats current_rx current_tx
    mapfile -t current_stats < <(traffic_guard_read_stats "$iface")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    traffic_guard_mode_usage_bytes "$mode" "$current_rx" "$current_tx"
}

traffic_guard_write_state_baseline() {
    local iface="$1"
    local cycle_day="$2"
    local initial_used_bytes="${3:-0}"
    local current_stats current_rx current_tx cycle_key state_file

    [[ "$initial_used_bytes" =~ ^[0-9]+$ ]] || initial_used_bytes=0
    traffic_guard_valid_iface "$iface" || return 1
    mapfile -t current_stats < <(traffic_guard_read_stats "$iface")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    cycle_key=$(traffic_guard_current_cycle_key "$cycle_day")
    mkdir -p "$TRAFFIC_GUARD_STATE_DIR" || return 1
    chmod 700 "$TRAFFIC_GUARD_STATE_DIR" 2>/dev/null || true
    state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    {
        echo "CYCLE_KEY='${cycle_key}'"
        echo "BASE_RX='${current_rx}'"
        echo "BASE_TX='${current_tx}'"
        echo "OFFSET_BYTES='${initial_used_bytes}'"
        echo "WARN_SENT='0'"
        echo "TRIPPED='0'"
        echo "LAST_RX='${current_rx}'"
        echo "LAST_TX='${current_tx}'"
        echo "LAST_USAGE='${initial_used_bytes}'"
        echo "LAST_CHECKED_AT='$(date -Is 2>/dev/null || date)'"
    } > "$state_file"
    chmod 600 "$state_file" 2>/dev/null || true
}

install_traffic_guard_checker() {
    mkdir -p "$(dirname "$TRAFFIC_GUARD_CHECKER")" "$TRAFFIC_GUARD_STATE_DIR" "$(dirname "$TRAFFIC_GUARD_CONFIG")" || return 1
    cat > "$TRAFFIC_GUARD_CHECKER" <<'GUARD_SCRIPT'
set -u

CONFIG="/etc/vps-optimize/traffic-guard.conf"
STATE_DIR="/var/lib/vps-optimize/traffic-guard"
STATE_FILE="${STATE_DIR}/state"
LOG_FILE="/var/log/vps-traffic-guard.log"

log_msg() {
    local msg="$1"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s %s\n' "$(date -Is 2>/dev/null || date)" "$msg" >> "$LOG_FILE" 2>/dev/null || true
    logger -t vps-traffic-guard "$msg" 2>/dev/null || true
}

guard_exit() {
    local rc=$?
    if [[ "$rc" -ne 0 ]]; then
        log_msg "checker exited unexpectedly rc=${rc}; keep timer healthy and retry next run"
        exit 0
    fi
}
trap guard_exit EXIT

normalize_cycle_day() {
    local cycle_day="${1:-1}"
    [[ "$cycle_day" =~ ^[0-9]+$ ]] || cycle_day=1
    cycle_day=$((10#$cycle_day))
    (( cycle_day >= 1 && cycle_day <= 31 )) || cycle_day=1
    printf '%s' "$cycle_day"
}

cycle_date_for_month() {
    local year_month="$1"
    local cycle_day
    local last_day effective_day
    cycle_day=$(normalize_cycle_day "${2:-1}")
    last_day=$(date -d "${year_month}-01 +1 month -1 day" +%d 2>/dev/null || echo 31)
    last_day=$((10#$last_day))
    effective_day="$cycle_day"
    (( effective_day > last_day )) && effective_day="$last_day"
    printf '%s-%02d' "$year_month" "$effective_day"
}

current_cycle_key() {
    local cycle_day="${1:-1}"
    local current_month previous_month current_day reset_date reset_day
    cycle_day=$(normalize_cycle_day "$cycle_day")
    current_month=$(date +%Y-%m)
    reset_date=$(cycle_date_for_month "$current_month" "$cycle_day")
    reset_day="${reset_date##*-}"
    current_day=$(date +%d)
    if (( 10#$current_day >= 10#$reset_day )); then
        printf '%s' "$reset_date"
    else
        previous_month=$(date -d "${current_month}-01 -1 month" +%Y-%m)
        cycle_date_for_month "$previous_month" "$cycle_day"
    fi
}

save_state() {
    mkdir -p "$STATE_DIR" || exit 1
    chmod 700 "$STATE_DIR" 2>/dev/null || true
    {
        echo "CYCLE_KEY='${CYCLE_KEY:-}'"
        echo "BASE_RX='${BASE_RX:-0}'"
        echo "BASE_TX='${BASE_TX:-0}'"
        echo "OFFSET_BYTES='${OFFSET_BYTES:-0}'"
        echo "WARN_SENT='${WARN_SENT:-0}'"
        echo "TRIPPED='${TRIPPED:-0}'"
        echo "LAST_RX='${CURRENT_RX:-0}'"
        echo "LAST_TX='${CURRENT_TX:-0}'"
        echo "LAST_USAGE='${USAGE_BYTES:-0}'"
        echo "LAST_CHECKED_AT='$(date -Is 2>/dev/null || date)'"
    } > "$STATE_FILE"
    chmod 600 "$STATE_FILE" 2>/dev/null || true
}

[[ -r "$CONFIG" ]] || exit 0
# shellcheck disable=SC1090
. "$CONFIG"

[[ "${ENABLED:-0}" == "1" ]] || exit 0
IFACE="${IFACE:-}"
MODE="${MODE:-tx}"
LIMIT_BYTES="${LIMIT_BYTES:-0}"
CYCLE_DAY="${CYCLE_DAY:-1}"
WARN_PERCENT="${WARN_PERCENT:-90}"
ACTION="${ACTION:-poweroff}"
INITIAL_USED_BYTES="${INITIAL_USED_BYTES:-0}"

[[ -n "$IFACE" && -r "/sys/class/net/${IFACE}/statistics/rx_bytes" && -r "/sys/class/net/${IFACE}/statistics/tx_bytes" ]] || {
    log_msg "interface ${IFACE:-empty} is not readable, skip"
    exit 0
}
[[ "$LIMIT_BYTES" =~ ^[0-9]+$ && "$LIMIT_BYTES" -gt 0 ]] || exit 0
[[ "$WARN_PERCENT" =~ ^[0-9]+$ ]] || WARN_PERCENT=90
(( WARN_PERCENT >= 1 && WARN_PERCENT <= 99 )) || WARN_PERCENT=90

CURRENT_RX=$(cat "/sys/class/net/${IFACE}/statistics/rx_bytes" 2>/dev/null || echo 0)
CURRENT_TX=$(cat "/sys/class/net/${IFACE}/statistics/tx_bytes" 2>/dev/null || echo 0)
CYCLE_NOW=$(current_cycle_key "$CYCLE_DAY")

STATE_EXISTS=0
if [[ -r "$STATE_FILE" ]]; then
    STATE_EXISTS=1
    # shellcheck disable=SC1090
    . "$STATE_FILE"
fi

if [[ "${CYCLE_KEY:-}" != "$CYCLE_NOW" ]]; then
    CYCLE_KEY="$CYCLE_NOW"
    BASE_RX="$CURRENT_RX"
    BASE_TX="$CURRENT_TX"
    if [[ "$STATE_EXISTS" -eq 0 ]]; then
        OFFSET_BYTES="${INITIAL_USED_BYTES:-0}"
    else
        OFFSET_BYTES=0
    fi
    WARN_SENT=0
    TRIPPED=0
    USAGE_BYTES="$OFFSET_BYTES"
    save_state
    log_msg "new cycle ${CYCLE_KEY}, baseline reset on ${IFACE}, initial used ${OFFSET_BYTES} bytes"
    exit 0
fi

BASE_RX="${BASE_RX:-$CURRENT_RX}"
BASE_TX="${BASE_TX:-$CURRENT_TX}"
OFFSET_BYTES="${OFFSET_BYTES:-0}"
WARN_SENT="${WARN_SENT:-0}"
TRIPPED="${TRIPPED:-0}"

if (( CURRENT_RX < BASE_RX || CURRENT_TX < BASE_TX )); then
    PREVIOUS_USAGE="${LAST_USAGE:-${OFFSET_BYTES:-0}}"
    [[ "$PREVIOUS_USAGE" =~ ^[0-9]+$ ]] || PREVIOUS_USAGE=0
    BASE_RX="$CURRENT_RX"
    BASE_TX="$CURRENT_TX"
    OFFSET_BYTES="$PREVIOUS_USAGE"
    WARN_SENT=0
    TRIPPED=0
    USAGE_BYTES="$OFFSET_BYTES"
    save_state
    log_msg "counter reset detected on ${IFACE}, baseline reset and preserved ${OFFSET_BYTES} bytes"
    exit 0
fi

DELTA_RX=$(( CURRENT_RX - BASE_RX ))
DELTA_TX=$(( CURRENT_TX - BASE_TX ))
case "$MODE" in
    rx) USAGE_BYTES="$DELTA_RX" ;;
    total) USAGE_BYTES=$(( DELTA_RX + DELTA_TX )) ;;
    max)
        if (( DELTA_RX > DELTA_TX )); then USAGE_BYTES="$DELTA_RX"; else USAGE_BYTES="$DELTA_TX"; fi
        ;;
    tx|*) USAGE_BYTES="$DELTA_TX" ;;
esac
USAGE_BYTES=$(( USAGE_BYTES + OFFSET_BYTES ))

if [[ "$TRIPPED" != "1" ]] && (( USAGE_BYTES * 100 >= LIMIT_BYTES * WARN_PERCENT )) && (( USAGE_BYTES < LIMIT_BYTES )) && [[ "$WARN_SENT" != "1" ]]; then
    WARN_SENT=1
    save_state
    log_msg "warning ${USAGE_BYTES}/${LIMIT_BYTES} bytes (${WARN_PERCENT}%) on ${IFACE}, mode=${MODE}"
    exit 0
fi

if (( USAGE_BYTES >= LIMIT_BYTES )); then
    TRIPPED=1
    save_state
    log_msg "quota reached ${USAGE_BYTES}/${LIMIT_BYTES} bytes on ${IFACE}, mode=${MODE}, action=${ACTION}"
    case "$ACTION" in
        log)
            exit 0
            ;;
        poweroff|*)
            sync
            systemctl poweroff >/dev/null 2>&1 || poweroff >/dev/null 2>&1 || shutdown -h now >/dev/null 2>&1 || log_msg "poweroff command failed; will retry on next timer run"
            ;;
    esac
fi

save_state
exit 0
GUARD_SCRIPT
    chmod 700 "$TRAFFIC_GUARD_CHECKER" || return 1
}

reset_traffic_guard_failed_state() {
    systemctl reset-failed vps-traffic-guard.service vps-traffic-guard.timer >/dev/null 2>&1 || true
}

install_traffic_guard_units() {
    local interval="$1"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=60
    (( interval >= 30 )) || interval=30

    cat > /etc/systemd/system/vps-traffic-guard.service <<EOF
[Unit]
Description=VPS-Optimize traffic quota guard
After=network-online.target

[Service]
Type=oneshot
ExecStart=${TRAFFIC_GUARD_CHECKER}
EOF

    cat > /etc/systemd/system/vps-traffic-guard.timer <<EOF
[Unit]
Description=Run VPS-Optimize traffic quota guard periodically

[Timer]
OnBootSec=1min
OnUnitActiveSec=${interval}s
AccuracySec=10s
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || return 1
    reset_traffic_guard_failed_state
    systemctl enable --now vps-traffic-guard.timer >/dev/null 2>&1 || return 1
    reset_traffic_guard_failed_state
}

write_traffic_guard_config() {
    local iface="$1"
    local mode="$2"
    local limit_gb="$3"
    local limit_bytes="$4"
    local cycle_day="$5"
    local warn_percent="$6"
    local action="$7"
    local initial_used_gb="$8"
    local initial_used_bytes="$9"
    local interval="${10}"

    mkdir -p "$(dirname "$TRAFFIC_GUARD_CONFIG")" || return 1
    cat > "$TRAFFIC_GUARD_CONFIG" <<EOF
# VPS-Optimize traffic quota guard
# Generated: $(date -Is 2>/dev/null || date)
ENABLED=1
IFACE='${iface}'
MODE='${mode}'
LIMIT_GB='${limit_gb}'
LIMIT_BYTES='${limit_bytes}'
CYCLE_DAY='${cycle_day}'
WARN_PERCENT='${warn_percent}'
ACTION='${action}'
INITIAL_USED_GB='${initial_used_gb}'
INITIAL_USED_BYTES='${initial_used_bytes}'
CHECK_INTERVAL='${interval}'
EOF
    chmod 600 "$TRAFFIC_GUARD_CONFIG" 2>/dev/null || true
}

load_traffic_guard_config() {
    [[ -r "$TRAFFIC_GUARD_CONFIG" ]] || return 1
    # shellcheck disable=SC1090
    . "$TRAFFIC_GUARD_CONFIG"
}

traffic_guard_usage_from_state() {
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    [[ -r "$state_file" ]] || return 1
    # shellcheck disable=SC1090
    . "$state_file"
    printf '%s' "${LAST_USAGE:-0}"
}

show_traffic_guard_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "网络/内核优化 > 流量达量关机保护"
    echo -e "${BOLD}🧯 流量达量关机保护状态${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    if ! load_traffic_guard_config; then
        echo -e "${YELLOW}当前未配置流量达量关机保护。${PLAIN}"
        echo -e "${BLUE}建议先选择 [1] 配置，避免 VPS 被刷流量产生超额账单。${PLAIN}"
        return 0
    fi

    local timer_state service_state usage limit pct cycle_key state_file current_stats current_rx current_tx
    timer_state=$(systemctl is-active vps-traffic-guard.timer 2>/dev/null || echo "inactive")
    service_state=$(systemctl is-enabled vps-traffic-guard.timer 2>/dev/null || echo "disabled")
    usage=$(traffic_guard_usage_from_state 2>/dev/null || echo 0)
    limit="${LIMIT_BYTES:-0}"
    if [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]]; then
        pct=$(awk -v u="$usage" -v l="$limit" 'BEGIN { printf "%.2f", (u/l)*100 }')
    else
        pct="0.00"
    fi
    cycle_key=$(traffic_guard_current_cycle_key "${CYCLE_DAY:-1}")

    echo -e "开关状态 : ${GREEN}${ENABLED:-0}${PLAIN}  timer: ${timer_state}/${service_state}"
    echo -e "监控网卡 : ${CYAN}${IFACE:-未知}${PLAIN}"
    echo -e "计费模式 : ${CYAN}$(traffic_guard_mode_label "${MODE:-tx}")${PLAIN}"
    echo -e "本周期   : ${CYAN}${cycle_key}${PLAIN} 起，配置为每月 ${CYCLE_DAY:-1} 日重置（短月份按最后一天）"
    echo -e "阈值     : ${YELLOW}${LIMIT_GB:-未知}GB${PLAIN} ($(traffic_guard_human_bytes "$limit"))"
    echo -e "已用     : ${GREEN}$(traffic_guard_human_bytes "$usage")${PLAIN} / ${pct}%"
    echo -e "预警线   : ${WARN_PERCENT:-90}%  动作: ${ACTION:-poweroff}"
    if traffic_guard_valid_iface "${IFACE:-}"; then
        mapfile -t current_stats < <(traffic_guard_read_stats "$IFACE")
        current_rx="${current_stats[0]:-0}"
        current_tx="${current_stats[1]:-0}"
        echo -e "网卡计数 : RX ${CYAN}$(traffic_guard_human_bytes "$current_rx")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes "$current_tx")${PLAIN}（自开机累计）"
    fi
    echo -e "配置文件 : ${CYAN}${TRAFFIC_GUARD_CONFIG}${PLAIN}"
    echo -e "日志文件 : ${CYAN}${TRAFFIC_GUARD_LOG}${PLAIN}"

    state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    if [[ -r "$state_file" ]]; then
        local last_checked
        last_checked=$(grep -m1 '^LAST_CHECKED_AT=' "$state_file" | cut -d= -f2- | sed "s/^'//;s/'$//")
        echo -e "最近检查 : ${CYAN}${last_checked}${PLAIN}"
    else
        echo -e "${YELLOW}尚未生成状态文件，timer 首次运行后会自动初始化基线。${PLAIN}"
    fi
}

configure_traffic_guard() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "网络/内核优化 > 配置流量达量关机保护"
    echo -e "${BOLD}🧯 配置流量达量关机保护${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：定时读取网卡流量，达到阈值后自动关机，避免超额流量产生账单。${PLAIN}"
    echo -e "${YELLOW}注意：脚本只能按本机网卡计数估算，云厂商后台统计可能有延迟或口径差异，请留安全余量。${PLAIN}"
    echo -e "------------------------------------------------"

    local default_iface iface limit_gb limit_bytes initial_used_gb initial_used_bytes
    local cycle_day cycle_default_day warn_percent action_choice action mode_choice mode interval
    local current_stats current_rx current_tx detected_used_bytes detected_used_gb existing_used_bytes
    default_iface=$(traffic_guard_detect_iface)
    iface=$(ask_with_default "监控网卡（自动推荐活跃公网网卡）" "${default_iface:-eth0}")
    if ! traffic_guard_valid_iface "$iface"; then
        echo -e "${RED}❌ 网卡 ${iface} 不存在或无法读取统计数据。${PLAIN}"
        pause_return
        return 1
    fi
    mapfile -t current_stats < <(traffic_guard_read_stats "$iface")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    echo -e "${GREEN}✅ 已选择网卡：${iface}${PLAIN}"
    echo -e "当前网卡自开机累计：RX ${CYAN}$(traffic_guard_human_bytes "$current_rx")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes "$current_tx")${PLAIN}"
    echo -e "${YELLOW}说明：系统只能读取本机网卡计数；云厂商账单口径可能不同，请优先参考云后台并留余量。${PLAIN}"

    while true; do
        limit_gb=$(ask_with_default "本周期流量阈值 GB（建议填套餐的 80%-95%）" "900")
        if limit_bytes=$(traffic_guard_gb_to_bytes "$limit_gb" 2>/dev/null); then
            break
        fi
        echo -e "${RED}❌ 阈值无效，请输入大于 0 的数字，例如 900 或 0.5。${PLAIN}"
    done

    while true; do
        cycle_default_day=$(date +%d)
        cycle_default_day=$((10#$cycle_default_day))
        cycle_day=$(ask_with_default "每月套餐/账单重置日 1-31（短月份自动按最后一天）" "$cycle_default_day")
        if [[ "$cycle_day" =~ ^[0-9]+$ ]] && (( 10#$cycle_day >= 1 && 10#$cycle_day <= 31 )); then
            break
        fi
        echo -e "${RED}❌ 重置日只支持 1-31。${PLAIN}"
    done

    echo -e "计费模式："
    echo -e "  1. 出站 TX 计费"
    echo -e "  2. 出入总量 RX+TX"
    echo -e "  3. 任一方向达量"
    echo -e "  4. 入站 RX 计费"
    read_trimmed mode_choice "请选择计费模式 (默认 1): "
    case "${mode_choice:-1}" in
        2) mode="total" ;;
        3) mode="max" ;;
        4) mode="rx" ;;
        *) mode="tx" ;;
    esac

    detected_used_bytes=$(traffic_guard_detect_initial_used_bytes "$iface" "$mode" "$cycle_day")
    detected_used_gb=$(traffic_guard_bytes_to_gb "$detected_used_bytes")
    existing_used_bytes=$(traffic_guard_existing_state_usage "$iface" "$mode" "$cycle_day" 2>/dev/null || true)
    if [[ "$existing_used_bytes" =~ ^[0-9]+$ && "$existing_used_bytes" != "$detected_used_bytes" ]]; then
        echo -e "检测到已有保护状态已用：${YELLOW}$(traffic_guard_human_bytes "$existing_used_bytes")${PLAIN}"
        echo -e "${YELLOW}本次重新配置默认按当前网卡累计估算，启用后会重置基线，避免旧状态误导。${PLAIN}"
    fi
    echo -e "按当前网卡自开机累计和计费模式估算已用：${CYAN}$(traffic_guard_human_bytes "$detected_used_bytes")${PLAIN}（默认可直接回车）"
    echo -e "${YELLOW}如果云厂商后台显示不同，请手动覆盖这里的 GB 数值。${PLAIN}"
    while true; do
        initial_used_gb=$(ask_with_default "本周期已用流量 GB" "$detected_used_gb")
        if initial_used_bytes=$(traffic_guard_gb_to_bytes_zero_ok "$initial_used_gb" 2>/dev/null); then
            break
        fi
        echo -e "${RED}❌ 已用流量无效，请输入不小于 0 的数字。${PLAIN}"
    done

    while true; do
        warn_percent=$(ask_with_default "预警百分比 1-99" "90")
        if [[ "$warn_percent" =~ ^[0-9]+$ ]] && (( 10#$warn_percent >= 1 && 10#$warn_percent <= 99 )); then
            break
        fi
        echo -e "${RED}❌ 预警百分比无效。${PLAIN}"
    done

    interval=$(ask_with_default "检查间隔秒数（最低 30，默认 60）" "60")
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( 10#$interval < 30 )); then
        interval=60
    fi

    echo -e "触发动作："
    echo -e "  1. 立即关机 ${YELLOW}(防止继续产生流量费用)${PLAIN}"
    echo -e "  2. 只写日志 ${YELLOW}(测试配置，不关机)${PLAIN}"
    read_trimmed action_choice "请选择触发动作 (默认 1): "
    if [[ "${action_choice:-1}" == "2" ]]; then
        action="log"
    else
        action="poweroff"
    fi

    echo -e "------------------------------------------------"
    echo -e "网卡：${CYAN}${iface}${PLAIN}"
    echo -e "阈值：${YELLOW}${limit_gb}GB${PLAIN}，本周期已用抵扣：${initial_used_gb}GB"
    echo -e "模式：${CYAN}$(traffic_guard_mode_label "$mode")${PLAIN}"
    echo -e "周期：每月 ${cycle_day} 日重置（短月份按最后一天）；检查间隔：${interval}s；预警：${warn_percent}%"
    echo -e "动作：${RED}${action}${PLAIN}"

    if [[ "$action" == "poweroff" ]]; then
        confirm_danger "启用流量达量自动关机" \
            "安装 vps-traffic-guard systemd timer；达到阈值会执行 systemctl poweroff。" \
            "从云厂商控制台手动开机；开机后进入本菜单调整阈值、重置基线或停用保护。" \
            "建议阈值低于套餐上限，并确认云厂商后台流量口径。" || return 1
    fi

    write_traffic_guard_config "$iface" "$mode" "$limit_gb" "$limit_bytes" "$cycle_day" "$warn_percent" "$action" "$initial_used_gb" "$initial_used_bytes" "$interval" || {
        echo -e "${RED}❌ 写入配置失败。${PLAIN}"
        pause_return
        return 1
    }
    install_traffic_guard_checker || {
        echo -e "${RED}❌ 安装检查脚本失败。${PLAIN}"
        pause_return
        return 1
    }
    traffic_guard_write_state_baseline "$iface" "$cycle_day" "$initial_used_bytes" || {
        echo -e "${RED}❌ 写入流量保护基线失败。${PLAIN}"
        pause_return
        return 1
    }
    install_traffic_guard_units "$interval" || {
        echo -e "${RED}❌ 启用 systemd timer 失败，请检查 systemd 状态。${PLAIN}"
        pause_return
        return 1
    }

    "$TRAFFIC_GUARD_CHECKER" >/dev/null 2>&1 || true
    reset_traffic_guard_failed_state
    echo -e "${GREEN}✅ 流量达量关机保护已启用。${PLAIN}"
    echo -e "${YELLOW}状态可在本菜单 [2] 查看；日志：${TRAFFIC_GUARD_LOG}${PLAIN}"
    pause_return
}

reset_traffic_guard_baseline() {
    local iface mode cycle_day initial_used_gb initial_used_bytes
    local detected_used_bytes detected_used_gb
    load_traffic_guard_config || {
        echo -e "${YELLOW}尚未配置流量达量关机保护。${PLAIN}"
        pause_return
        return 1
    }
    iface="${IFACE:-}"
    mode="${MODE:-tx}"
    cycle_day="${CYCLE_DAY:-1}"
    traffic_guard_valid_iface "$iface" || {
        echo -e "${RED}❌ 当前配置的网卡 ${iface} 不可读。${PLAIN}"
        pause_return
        return 1
    }
    detected_used_bytes=$(traffic_guard_detect_initial_used_bytes "$iface" "$mode" "$cycle_day")
    detected_used_gb=$(traffic_guard_bytes_to_gb "$detected_used_bytes")
    echo -e "按当前网卡和计费模式估算已用：${CYAN}$(traffic_guard_human_bytes "$detected_used_bytes")${PLAIN}"
    initial_used_gb=$(ask_with_default "重置后本周期已用流量 GB" "$detected_used_gb")
    if ! initial_used_bytes=$(traffic_guard_gb_to_bytes_zero_ok "$initial_used_gb" 2>/dev/null); then
        echo -e "${RED}❌ 已用流量无效。${PLAIN}"
        pause_return
        return 1
    fi
    confirm_risk_action "重置流量保护基线" \
        "本周期统计会从当前网卡计数重新开始，已用抵扣设置为 ${initial_used_gb}GB。" \
        "重新进入本菜单再次重置基线，或参考云厂商后台手动修正已用流量。" \
        "请只在账单周期开始、刚配置完成或确认云厂商统计后执行。" || return 1

    traffic_guard_write_state_baseline "$iface" "$cycle_day" "$initial_used_bytes" || {
        echo -e "${RED}❌ 写入流量保护基线失败。${PLAIN}"
        pause_return
        return 1
    }
    echo -e "${GREEN}✅ 已重置 ${iface} 的流量统计基线。${PLAIN}"
    echo -e "当前模式：${CYAN}$(traffic_guard_mode_label "$mode")${PLAIN}；本周期已用：$(traffic_guard_human_bytes "$initial_used_bytes")"
    pause_return
}

disable_traffic_guard() {
    if ! systemctl list-unit-files vps-traffic-guard.timer >/dev/null 2>&1 && [[ ! -f "$TRAFFIC_GUARD_CONFIG" ]]; then
        echo -e "${YELLOW}未检测到流量保护配置。${PLAIN}"
        pause_return
        return 0
    fi
    confirm_risk_action "停用流量达量关机保护" \
        "vps-traffic-guard.timer 会停止，达到流量阈值后不再自动关机。" \
        "重新进入本菜单选择 [1] 启用保护。" \
        "停用后请自行监控云厂商流量，避免超额账单。" || return 1
    systemctl disable --now vps-traffic-guard.timer >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    reset_traffic_guard_failed_state
    if [[ -f "$TRAFFIC_GUARD_CONFIG" ]]; then
        sed -i 's/^ENABLED=.*/ENABLED=0/' "$TRAFFIC_GUARD_CONFIG" 2>/dev/null || true
    fi
    echo -e "${GREEN}✅ 已停用流量达量关机保护，配置文件仍保留：${TRAFFIC_GUARD_CONFIG}${PLAIN}"
    pause_return
}

func_traffic_guard_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "网络/内核优化 > 流量达量关机保护"
        echo -e "${BOLD}🧯 流量达量关机保护${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}达到套餐安全阈值后自动关机，优先防止刷流量造成天价账单。${PLAIN}"
        echo -e "${YELLOW}推荐阈值低于云厂商套餐上限，并按出站 TX 或总量模式保守配置。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 配置 / 启用保护${PLAIN}"
        echo -e "${GREEN}  2. 查看状态与已用量${PLAIN}"
        echo -e "${GREEN}  3. 重置本周期统计基线${PLAIN}"
        echo -e "${YELLOW}  4. 停用保护${PLAIN}"
        echo -e "${GREEN}  5. 查看最近日志${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) configure_traffic_guard ;;
            2) show_traffic_guard_status; pause_return ;;
            3) reset_traffic_guard_baseline ;;
            4) disable_traffic_guard ;;
            5)
                echo -e "${CYAN}--- ${TRAFFIC_GUARD_LOG} ---${PLAIN}"
                tail -n 30 "$TRAFFIC_GUARD_LOG" 2>/dev/null || echo "暂无日志"
                pause_return
                ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

network_iface_exists() {
    local iface="$1"
    [[ -n "$iface" && "$iface" != *"/"* && "$iface" != *".."* && -d "/sys/class/net/${iface}" ]]
}

network_default_ifaces() {
    {
        ip -o route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}'
        ip -o -6 route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}'
    } | sort -u
}

network_iface_is_default_route() {
    local iface="$1"
    network_default_ifaces | grep -Fxq "$iface"
}

network_choose_iface() {
    local default_iface iface
    default_iface=$(traffic_guard_detect_iface)
    iface=$(ask_with_default "网卡名称" "${default_iface:-eth0}")
    if ! network_iface_exists "$iface"; then
        echo -e "${RED}❌ 网卡 ${iface} 不存在。${PLAIN}" >&2
        return 1
    fi
    printf '%s' "$iface"
}

network_show_overview() {
    echo -e "${CYAN}--- 网卡地址 ---${PLAIN}"
    ip -br addr 2>/dev/null || ip addr
    echo ""
    echo -e "${CYAN}--- 默认路由 ---${PLAIN}"
    ip route show default 2>/dev/null || true
    ip -6 route show default 2>/dev/null || true
    echo ""
    echo -e "${CYAN}--- DNS ---${PLAIN}"
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl dns 2>/dev/null || cat /etc/resolv.conf 2>/dev/null
    else
        cat /etc/resolv.conf 2>/dev/null || true
    fi
}

network_show_iface_detail() {
    local iface
    iface=$(network_choose_iface) || return 1
    echo -e "${CYAN}--- ${iface} 链路详情 ---${PLAIN}"
    ip -d link show dev "$iface" 2>/dev/null || ip link show dev "$iface"
    echo ""
    echo -e "${CYAN}--- ${iface} 流量统计 ---${PLAIN}"
    ip -s link show dev "$iface" 2>/dev/null || true
    if command -v ethtool >/dev/null 2>&1; then
        echo ""
        echo -e "${CYAN}--- ${iface} 驱动/速率 ---${PLAIN}"
        ethtool "$iface" 2>/dev/null | sed -n '1,40p' || true
    fi
}

network_set_iface_state() {
    local state="$1"
    local iface
    iface=$(network_choose_iface) || return 1
    if [[ "$state" == "down" ]]; then
        local default_hint=""
        if network_iface_is_default_route "$iface"; then
            default_hint="当前网卡承载默认路由，关闭后 SSH 大概率会断开。"
        else
            default_hint="关闭网卡会影响该网卡上的所有连接。"
        fi
        confirm_danger "关闭网卡 ${iface}" \
            "网卡 ${iface} 链路状态" \
            "通过云厂商控制台或本菜单重新启用网卡" \
            "${default_hint}" || return 1
    fi
    ip link set dev "$iface" "$state" || {
        echo -e "${RED}❌ 设置 ${iface} ${state} 失败。${PLAIN}"
        return 1
    }
    echo -e "${GREEN}✅ 已设置 ${iface}: ${state}${PLAIN}"
}

network_set_iface_mtu() {
    local iface mtu
    iface=$(network_choose_iface) || return 1
    read_trimmed mtu "请输入临时 MTU（576-9000，重启后可能恢复）: "
    if ! [[ "$mtu" =~ ^[0-9]+$ ]] || (( 10#$mtu < 576 || 10#$mtu > 9000 )); then
        echo -e "${RED}❌ MTU 无效。${PLAIN}"
        return 1
    fi
    confirm_risk_action "设置 ${iface} MTU 为 ${mtu}" \
        "网卡 ${iface} 的运行时 MTU" \
        "重新设置原 MTU，或重启网络/系统恢复云厂商默认值" \
        "错误 MTU 可能导致部分网站或隧道访问异常。" || return 1
    ip link set dev "$iface" mtu "$mtu" || {
        echo -e "${RED}❌ 设置 MTU 失败。${PLAIN}"
        return 1
    }
    echo -e "${GREEN}✅ ${iface} MTU 已临时设置为 ${mtu}${PLAIN}"
}

network_renew_dhcp() {
    local iface
    iface=$(network_choose_iface) || return 1
    confirm_danger "刷新 ${iface} DHCP 租约" \
        "网卡 ${iface} 的地址租约/网络连接" \
        "通过云厂商控制台重连，或重启系统恢复网络" \
        "如果这是当前 SSH 使用的公网网卡，刷新租约可能短暂断开连接。" || return 1
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$iface" >/dev/null 2>&1 || true
        dhclient "$iface" || return 1
    elif command -v networkctl >/dev/null 2>&1; then
        networkctl renew "$iface" || return 1
    elif command -v nmcli >/dev/null 2>&1; then
        nmcli device reapply "$iface" || nmcli device connect "$iface" || return 1
    else
        echo -e "${YELLOW}⚠️ 未检测到 dhclient/networkctl/nmcli，无法自动刷新 DHCP。${PLAIN}"
        return 1
    fi
    echo -e "${GREEN}✅ 已尝试刷新 ${iface} 的 DHCP/网络连接。${PLAIN}"
}

func_network_interface_manage() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "网络/内核优化 > 网卡管理工具"
        echo -e "${BOLD}🧰 网卡管理工具${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：查看网卡、路由、DNS 和链路状态；危险操作会要求确认。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 查看网卡 / 路由 / DNS 概览${PLAIN}"
        echo -e "${GREEN}  2. 查看指定网卡详情与流量统计${PLAIN}"
        echo -e "${GREEN}  3. 启用指定网卡${PLAIN}"
        echo -e "${RED}  4. 关闭指定网卡${PLAIN}"
        echo -e "${YELLOW}  5. 临时设置网卡 MTU${PLAIN}"
        echo -e "${YELLOW}  6. 刷新 DHCP/网络连接${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) network_show_overview; pause_return ;;
            2) network_show_iface_detail; pause_return ;;
            3) network_set_iface_state up; pause_return ;;
            4) network_set_iface_state down; pause_return ;;
            5) network_set_iface_mtu; pause_return ;;
            6) network_renew_dhcp; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 24. 网络加速与内核优化菜单 (二级直达)
# ---------------------------------------------------------
func_net_kernel_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "网络/内核优化"
        echo -e "${BOLD}🚀 网络性能与内核管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：调整网络栈、内存压缩和内核；涉及内核安装/清理前建议先做快照。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. BBR / 拥塞控制管理${PLAIN}   ${YELLOW}(调用 ylx2016 多内核调优脚本)${PLAIN}"
        echo -e "${GREEN}  2. 动态 TCP 参数调优${PLAIN}    ${YELLOW}(粘贴 Omnitt 参数并自动校验)${PLAIN}"
        echo -e "${GREEN}  3. ZRAM / Swap 内存调优${PLAIN} ${YELLOW}(按内存分档优化小鸡)${PLAIN}"
        echo -e "${GREEN}  4. 安装/切换优化内核${PLAIN}   ${YELLOW}(Cloud/KVM 稳定推荐 / XanMod 高级可选)${PLAIN}"
        echo -e "${GREEN}  5. 清理旧内核${PLAIN}           ${YELLOW}(释放磁盘空间，谨慎操作)${PLAIN}"
        echo -e "${GREEN}  6. DNS 更改优化${PLAIN}         ${YELLOW}(国内/国外/自定义，IPv4+IPv6)${PLAIN}"
        echo -e "${GREEN}  7. 流量达量关机保护${PLAIN}     ${YELLOW}(防刷流量 / 防超额账单)${PLAIN}"
        echo -e "${GREEN}  8. 网卡管理工具${PLAIN}         ${YELLOW}(网卡/路由/DNS/MTU/DHCP)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local nk_choice
        read_trimmed nk_choice "👉 请选择操作: "
        case $nk_choice in
            1) confirm_risk_action "BBR / 拥塞控制管理" "内核网络模块、拥塞控制和 TCP 参数" "从快照恢复，或重新进入本菜单切换回原配置" "外部调优脚本可能安装/切换内核，请确认救援控制台可用。" && func_bbr_manage ;;
            2) confirm_risk_action "动态 TCP 参数调优" "sysctl TCP 参数和网络栈配置" "恢复 /etc/sysctl.d 中的备份配置，或手动回退参数" "确认参数来源可信，错误参数可能影响网络连接。" && func_tcp_tune ;;
            3) func_zram_swap ;;
            4) confirm_risk_action "安装/切换优化内核" "内核包、引导配置和 GRUB 菜单" "从云厂商控制台选择旧内核启动，或使用救援模式恢复" "确认已创建快照，且当前 VPS 不是 OpenVZ 老系统。" && func_install_kernel ;;
            5) func_clean_kernel ;;
            6) func_dns_optimize ;;
            7) func_traffic_guard_menu ;;
            8) func_network_interface_manage ;;
            "?"|help) show_net_kernel_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 24. 面板与节点部署菜单 (二级直达)
# ---------------------------------------------------------
func_panel_deploy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "面板、节点与订阅工具"
        echo -e "${BOLD}🛰️ 面板、节点与订阅工具部署${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：管理 3x-ui、S-UI、Sing-box、Xray、订阅工具、Dockge、Komari 和节点辅助工具。${PLAIN}"
        echo -e "${YELLOW}提示：面板或订阅工具对外访问，可用普通 Caddy 反代；已启用 443 单入口时用 [19] 统一管理。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 管理 3x-ui 面板${PLAIN}       ${YELLOW}(安装 / 官方菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  2. 管理 S-UI 面板${PLAIN}        ${YELLOW}(安装 / 官方菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  3. 管理 Sing-box${PLAIN}         ${YELLOW}(安装 / 管理菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  4. 管理 Xray${PLAIN}             ${YELLOW}(安装 / 官方菜单 / 卸载)${PLAIN}"
        echo -e "${GREEN}  5. 管理 SublinkPro${PLAIN}       ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${GREEN}  6. 管理 妙妙屋订阅管理${PLAIN}     ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${GREEN}  7. 管理 Sub-Store${PLAIN}        ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${GREEN}  8. 管理 Dockge${PLAIN}           ${YELLOW}(安装 / 状态 / 更新 / 卸载)${PLAIN}"
        echo -e "${BOLD}${YELLOW}  9. UPD 更新订阅管理工具${PLAIN}   ${CYAN}(SublinkPro / 妙妙屋 / Sub-Store)${PLAIN}"
        echo -e "${GREEN} 10. 迁移 Compose 到 Dockge${PLAIN} ${YELLOW}(Dockge 后安装时接管旧项目)${PLAIN}"
        echo -e "${GREEN} 11. 面板救砖 / SSL 清理${PLAIN}    ${YELLOW}(清空 3x-ui 证书路径，回到 HTTP 后端)${PLAIN}"
        echo -e "${GREEN} 12. DNS 流媒体解锁${PLAIN}        ${YELLOW}(Alice DNS 分流脚本)${PLAIN}"
        echo -e "${GREEN} 13. 防 IP 送中脚本${PLAIN}        ${YELLOW}(IP-Sentinel)${PLAIN}"
        echo -e "${GREEN} 14. 端口流量监控${PLAIN}          ${YELLOW}(Port Traffic Dog)${PLAIN}"
        echo -e "${GREEN} 15. 管理 Komari 探针监控${PLAIN}  ${YELLOW}(Docker Compose / 探针面板)${PLAIN}"
        echo -e "${GREEN} 16. 3x-ui 外置增强管理${PLAIN}    ${YELLOW}(面板缺失功能 / 流量重置 / 备份恢复)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local pd_choice
        read_trimmed pd_choice "👉 请选择操作: "
        case $pd_choice in
            1) func_xpanel_menu ;;
            2) func_sui_menu ;;
            3) func_singbox_menu ;;
            4) func_xray_menu ;;
            5) func_sublinkpro_menu ;;
            6) func_miaomiaowu_menu ;;
            7) func_substore_menu ;;
            8) func_dockge_menu ;;
            9) func_update_subscription_tools ;;
            10) func_migrate_compose_to_dockge ;;
            11) func_rescue_panel ;;
            12) func_dns_unlock ;;
            13) func_ip_sentinel ;;
            14) func_port_dog ;;
            15) func_komari_menu ;;
            16) func_xui_custom_manager ;;
            "?"|help) show_panel_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_sni_stack_quick_menu() {
    while true; do
        clear
        show_current_entry_summary
        echo -e "------------------------------------------------"
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "443 单入口管理中心"
        echo -e "${BOLD}🧩 443 单入口管理中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：统一管理公网 443 的入口模式、Web 域名、Xray 入站分流和链路体检。${PLAIN}"
        echo -e "${YELLOW}首次部署先选 [2]；已有配置后用 [3]/[4]/[5] 在三种入口模式间切换。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 当前状态与入口模式${PLAIN}"
        echo -e "${GREEN}  1. 查看当前入口状态 / 监听详情${PLAIN} ${YELLOW}(公网 443、Caddy、Xray、服务状态)${PLAIN}"
        echo -e "${GREEN}  2. 首次配置 / 安装 443 单入口${PLAIN} ${YELLOW}(默认 Nginx Stream 模式，第一次部署用)${PLAIN}"
        echo -e "${GREEN}  3. 切换到 Nginx Stream 模式${PLAIN}  ${YELLOW}(默认稳定模式)${PLAIN}"
        echo -e "${GREEN}  4. 切换到 Xray Fallback 模式${PLAIN} ${YELLOW}(需已有 Xray/3x-ui 主入站)${PLAIN}"
        echo -e "${GREEN}  5. 切换到 TCP Peek + Splice 模式${PLAIN} ${YELLOW}(自动生成/安装 vpso-mux 分流器，进阶模式)${PLAIN}"
        echo -e "${CYAN}  6. 重新应用当前入口模式${PLAIN}"
        echo -e "${YELLOW}  7. 回滚上一次入口模式切换${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 共享配置与体检${PLAIN}"
        echo -e "${GREEN}  8. 管理 Web 域名/反代${PLAIN}        ${YELLOW}(新增/删除/查看网站，最常用)${PLAIN}"
        echo -e "${CYAN}  9. 管理 Web 域名 IP 白名单${PLAIN}   ${YELLOW}(只限制 Web/Caddy 域名)${PLAIN}"
        echo -e "${CYAN} 10. Xray 入站管理${PLAIN}             ${YELLOW}(SNI -> 本地地址:端口 分流记录)${PLAIN}"
        echo -e "${GREEN} 11. 443 链路体检${PLAIN}              ${YELLOW}(ENTRY_MODE/监听/证书/Web/Xray 分流)${PLAIN}"
        echo -e "${CYAN} 12. 443 网络访问测试${PLAIN}          ${YELLOW}(DNS/TCP/TLS/面板/订阅路径)${PLAIN}"
        echo -e "${CYAN} 13. CF DNS / Caddy 证书维护${PLAIN}   ${YELLOW}(重签/软链/清理/修复/回滚)${PLAIN}"
        echo -e "${CYAN} 14. 修改 443 共享参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}"
        echo -e "${CYAN} 15. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}"
        echo -e "${CYAN} 16. 查看 TCP Peek + Splice 状态${PLAIN} ${YELLOW}(vpso-mux 分流器日志)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}说明：三种 443 入口不是三套独立安装器；[2] 建立共享配置，[3]/[4]/[5] 负责检查依赖、生成目标配置并切换入口。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local sni_choice
        read_trimmed sni_choice "👉 请选择操作: "
        case "$sni_choice" in
            1) show_current_entry_status ;;
            2) func_caddy_cf_reality_wizard ;;
            3) switch_entry_mode "nginx-stream" ;;
            4) switch_entry_mode "xray-fallback" ;;
            5) switch_entry_mode "tcp-peek" ;;
            6) reapply_current_entry_mode ;;
            7) rollback_last_entry_mode ;;
            8) manage_sni_stack_sites; continue ;;
            9) manage_sni_stack_ip_whitelist; continue ;;
            10) manage_xray_inbound_routes; continue ;;
            11) sni_stack_health_check_enhanced ;;
            12) func_443_network_test; continue ;;
            13) func_caddy_cf_maintenance_menu; continue ;;
            14) edit_sni_stack_runtime_profile; continue ;;
            15) check_sni_stack_subscription_hint ;;
            16) view_vpso_mux_logs ;;
            "?"|help) show_sni_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

normalize_main_choice() {
    local choice
    choice="$(trim_input "$1")"
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
        q|quit|exit|0|退出) echo "0" ;;
        pre|preflight|check|预检) echo "1" ;;
        init|base|初始化) echo "2" ;;
        env|docker|组件) echo "3" ;;
        caddy|proxy|reverse|反代|普通反代) echo "4" ;;
        panel|node|nodes|面板|节点) echo "5" ;;
        ssh) echo "6" ;;
        fail2ban|f2b) echo "7" ;;
        fw|firewall|防火墙) echo "8" ;;
        tweak|system|系统) echo "9" ;;
        net|kernel|bbr|网络|内核) echo "10" ;;
        docker-safe|docker安全) echo "11" ;;
        test|speed|测速) echo "12" ;;
        port|端口) echo "13" ;;
        info|hardware|探针) echo "14" ;;
        h|health|健康|体检) echo "15" ;;
        b|backup|bak|备份) echo "16" ;;
        u|upd|update|更新) echo "17" ;;
        reboot|重启) echo "18" ;;
        sni|443|单入口) echo "19" ;;
        traffic|quota|bill|流量|达量|账单) echo "10" ;;
        *) echo "$choice" ;;
    esac
}

func_beginner_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "新手向导"
        echo -e "${BOLD}VPS-Optimize ${SCRIPT_VERSION}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}这是简化入口，只保留第一次部署最常用的路径；老用户可返回完整菜单。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 新机器初始化${PLAIN}       ${YELLOW}(预检 -> 初始化 -> SSH/公钥/Fail2ban/防火墙 -> 备份)${PLAIN}"
        echo -e "${GREEN}  2. 安装面板/节点${PLAIN}     ${YELLOW}(进入面板、节点与订阅工具菜单)${PLAIN}"
        echo -e "${GREEN}  3. 配置 443 单入口${PLAIN}   ${YELLOW}(面板/订阅/REALITY 共用公网 443)${PLAIN}"
        echo -e "${GREEN}  4. 健康检查${PLAIN}          ${YELLOW}(服务状态、端口、证书、反馈诊断)${PLAIN}"
        echo -e "${GREEN}  5. 备份/回滚${PLAIN}         ${YELLOW}(创建备份或恢复配置)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BLUE}  ?. 查看帮助${PLAIN}"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local beginner_choice
        read_trimmed beginner_choice "👉 请选择操作: "
        case "$beginner_choice" in
            1)
                func_preflight_check
                func_base_init
                func_security
                func_add_ssh_key
                func_fail2ban
                func_firewall_manage
                func_backup_center
                ;;
            2) func_panel_deploy_menu ;;
            3) func_sni_stack_quick_menu ;;
            4) func_health_dashboard ;;
            5) func_backup_center ;;
            "?"|help|h) show_beginner_help; echo ""; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 界面主循环 (新增 IP 防送中 & SublinkPro)
# ---------------------------------------------------------
main_menu() {
    create_shortcut
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "主菜单"
        echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${YELLOW}快捷输入：443 直达单入口，h 看健康，b 做备份，u 更新，q 退出。${PLAIN}"
        echo -e " ${YELLOW}高风险操作必须输入大写 YES；不确定时先做 [16] 备份。${PLAIN}"
        print_auto_update_notice
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${BOLD}${BLUE}▶ 模式入口${PLAIN}"
        echo -e "  ${GREEN}n.${PLAIN} 新手向导              ${YELLOW}(只显示核心路径)${PLAIN}"
        echo -e "  ${GREEN}?.${PLAIN} 当前菜单帮助          ${YELLOW}(解释关键入口)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        echo -e " ${BOLD}${BLUE}▶ ① 推荐流程：新机器先跑这里${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 运维预检与风险扫描    ${YELLOW}(部署前先看端口/系统/服务状态)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 基础环境初始化        ${YELLOW}(工具/时区/系统更新/基础 BBR)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 基础组件与常用服务    ${YELLOW}(Docker/Python/WARP/常用工具)${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} 普通 Caddy 反代       ${YELLOW}(未接入 443 单入口的网站/面板反代)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} 面板、节点与订阅工具  ${YELLOW}(3x-ui/Sing-box/订阅管理/Dockge)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ② 安全与访问控制${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} SSH 安全中心          ${YELLOW}(端口/公钥/密钥登录模式)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} Fail2ban 防爆破       ${YELLOW}(自动封禁 SSH 爆破 IP)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 防火墙规则管理        ${YELLOW}(放行/删除/查看/关闭)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 系统开关与清理        ${YELLOW}(IPv6/IPv4优先/Ping/主机名/清理)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ③ 网络性能与容器${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 网络与内核优化        ${YELLOW}(BBR/TCP/ZRAM/DNS/轻量内核)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} Docker 安全管理       ${YELLOW}(本地防穿透/恢复访问)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ④ 诊断、备份与维护${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 测速与质量检测        ${YELLOW}(YABS/流媒体/回程/IP质量)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口排查与释放        ${YELLOW}(查看占用并强杀进程)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 系统硬件探针          ${YELLOW}(CPU/内存/磁盘/网络实时信息)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 服务健康总览          ${YELLOW}(服务状态/证书摘要/端口概览)${PLAIN}"
        echo -e " ${GREEN}16.${PLAIN} 配置备份与回滚        ${YELLOW}(备份/列表/恢复/清理)${PLAIN}"
        echo -e " ${BOLD}${YELLOW}17.${PLAIN} 更新脚本              ${CYAN}(快捷词：u / update / upd)${PLAIN}"
        echo -e " ${RED}18.${PLAIN} 重启服务器"
        echo -e ""
        echo -e " ${BOLD}${BLUE}▶ ⑤ 高频直达${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} 443 单入口管理中心    ${YELLOW}(初始化/加网站/体检/证书修复)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local choice
        read_trimmed choice "👉 请输入数字或快捷词选择功能: "
        choice=$(normalize_main_choice "$choice")
        
        case $choice in
            n|N|newbie|guide|新手|向导) func_beginner_menu ;;
            "?"|help|帮助) show_main_help; echo ""; pause_return ;;
            1) func_preflight_check ;;
            2) func_base_init ;;
            3) func_env_install ;;
            4) func_caddy_reverse_proxy_menu ;;
            5) func_panel_deploy_menu ;;
            6) func_ssh_security_menu ;;
            7) func_fail2ban ;;
            8) func_firewall_manage ;;
            9) func_system_tweaks ;;
            10) func_net_kernel_menu ;;
            11) func_docker_manage ;;
            12) func_test_scripts ;;
            13) func_port_kill ;;
            14) func_system_info ;;
            15) func_health_dashboard ;;
            16) func_backup_center ;;
            17) func_update_script ;;
            18) func_reboot_server ;;
            19) func_sni_stack_quick_menu ;;
            0) exit 0 ;;
            *) 
                echo -e "${RED}❌ 无效的输入，请输入菜单中存在的数字！${PLAIN}"
                sleep 1 
                ;;
        esac
    done
}

# --- 启动面板 ---
main_menu

