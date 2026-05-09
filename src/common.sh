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
