# shellcheck shell=bash
# Common constants, platform detection, package helpers, and remote script helpers.

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

SCRIPT_VERSION="v2.3"
UPDATE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh"
UPDATE_SHA256_URL="${UPDATE_URL}.sha256"
SCRIPT_UPDATE_CACHE="/etc/vps-optimize/update-check.cache"
TRAFFIC_GUARD_CONFIG="/etc/vps-optimize/traffic-guard.conf"
TRAFFIC_GUARD_CHECKER="/usr/local/bin/vps-traffic-guard-check"
TRAFFIC_GUARD_STATE_DIR="/var/lib/vps-optimize/traffic-guard"
TRAFFIC_GUARD_LOG="/var/log/vps-traffic-guard.log"
DNS_OPTIMIZE_BACKUP_DIR="/etc/vps-optimize/backups/dns"
DNS_OPTIMIZE_RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf"
VPSO_DEFAULT_LOG_MAX_BYTES=$((5 * 1024 * 1024))
VPSO_DEFAULT_LOG_ROTATE_KEEP=3

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

file_size_bytes() {
    local file="$1"
    local size
    [[ -e "$file" ]] || { echo 0; return 0; }
    size=$(wc -c < "$file" 2>/dev/null | awk '{print $1}')
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    echo "$size"
}

format_bytes() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ")
        i = 1
        while (b >= 1024 && i < 5) { b = b / 1024; i++ }
        if (i == 1) printf "%d %s", b, u[i]
        else printf "%.2f %s", b, u[i]
    }'
}

# Lightweight path-based rotation for logs that shell helpers append by name.
# It intentionally does not create a fresh file after mv; daemons that keep an
# open fd need journald, a reload/restart, or log code that can reopen files.
rotate_log_file() {
    local log_file="$1"
    local max_bytes="${2:-$VPSO_DEFAULT_LOG_MAX_BYTES}"
    local keep="${3:-$VPSO_DEFAULT_LOG_ROTATE_KEEP}"
    local size i old_path new_path

    [[ -n "$log_file" && -f "$log_file" ]] || return 0
    [[ "$max_bytes" =~ ^[0-9]+$ ]] || max_bytes="$VPSO_DEFAULT_LOG_MAX_BYTES"
    [[ "$keep" =~ ^[0-9]+$ ]] || keep="$VPSO_DEFAULT_LOG_ROTATE_KEEP"
    (( max_bytes > 0 && keep > 0 )) || return 0

    size=$(file_size_bytes "$log_file")
    (( size >= max_bytes )) || return 0

    rm -f "${log_file}.${keep}" 2>/dev/null || true
    for ((i = keep - 1; i >= 1; i--)); do
        old_path="${log_file}.${i}"
        new_path="${log_file}.$((i + 1))"
        [[ -e "$old_path" ]] && mv -f "$old_path" "$new_path" 2>/dev/null || true
    done
    mv -f "$log_file" "${log_file}.1" 2>/dev/null || true
}

pkg_log_file() {
    local action="${1:-pkg}"
    local log_dir="/var/log/vps-optimize"

    if mkdir -p "$log_dir" 2>/dev/null && [[ -w "$log_dir" ]]; then
        mktemp "${log_dir}/pkg-${action}.XXXXXX.log"
    else
        mktemp "/tmp/vps-optimize-pkg-${action}.XXXXXX.log"
    fi
}

print_pkg_failure_log() {
    local action="$1"
    local log_file="$2"
    shift 2
    echo -e "${RED}❌ 软件包${action}失败: $*${PLAIN}"
    echo -e "${YELLOW}日志: ${log_file}${PLAIN}"
    if [[ -s "$log_file" ]]; then
        echo -e "${YELLOW}最近 20 行:${PLAIN}"
        tail -n 20 "$log_file" 2>/dev/null || true
    else
        echo -e "${YELLOW}日志为空，可能是包管理器未能启动或当前系统不支持该操作。${PLAIN}"
    fi
}

install_pkg() {
    local pkgs=("$@")
    local rc=0 log_file
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_file=$(pkg_log_file install) || return 1
    if is_debian; then
        # 使用 apt-get 代替 apt，消除 "stable CLI interface" 警告 
        export DEBIAN_FRONTEND=noninteractive
        apt_update_once >>"$log_file" 2>&1 || true
        apt-get install -y -qq "${pkgs[@]}" >>"$log_file" 2>&1
        rc=$?
        unset DEBIAN_FRONTEND
    elif is_redhat; then
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y -q "${pkgs[@]}" >>"$log_file" 2>&1
        else
            yum install -y -q "${pkgs[@]}" >>"$log_file" 2>&1
        fi
        rc=$?
    else
        echo -e "${RED}❌ 当前系统暂不支持自动安装软件包：OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}"
        rm -f "$log_file"
        return 1
    fi
    if [[ "$rc" -eq 0 ]]; then
        rm -f "$log_file"
    else
        print_pkg_failure_log "安装" "$log_file" "${pkgs[@]}"
    fi
    return "$rc"
}

remove_pkg() {
    local pkgs=("$@")
    local rc=0 log_file
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_file=$(pkg_log_file remove) || return 1
    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y -qq "${pkgs[@]}" >>"$log_file" 2>&1
        rc=$?
        unset DEBIAN_FRONTEND
    elif is_redhat; then
        if command -v dnf >/dev/null 2>&1; then
            dnf remove -y -q "${pkgs[@]}" >>"$log_file" 2>&1
        else
            yum remove -y -q "${pkgs[@]}" >>"$log_file" 2>&1
        fi
        rc=$?
    else
        echo -e "${RED}❌ 当前系统暂不支持自动卸载软件包：OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}"
        rm -f "$log_file"
        return 1
    fi
    if [[ "$rc" -eq 0 ]]; then
        rm -f "$log_file"
    else
        print_pkg_failure_log "移除" "$log_file" "${pkgs[@]}"
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

is_vps_optimize_generated_script() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    grep -Fq "Project:  VPS Optimize" "$file" || return 1
    grep -Fq "Generated: scripts/build.sh" "$file" || return 1
    grep -Fq "VPS 全能控制面板" "$file" || return 1
    grep -Fq "main_menu" "$file" || return 1
}

copy_shortcut_candidate() {
    local source_file="$1"
    local target_file="$2"
    local label="$3"

    if ! is_vps_optimize_generated_script "$source_file"; then
        echo -e "${YELLOW}⚠️ ${label} 未通过 VPS-Optimize 脚本标识校验，已拒绝注册快捷指令。${PLAIN}"
        return 1
    fi
    cp "$source_file" "$target_file" 2>/dev/null
}

create_shortcut() {
    local script_path="/usr/local/bin/cy"
    local release_path
    if [[ ! -f "$script_path" ]]; then
        # 优先尝试从远端直接拉取
        if ! download_remote_script "$UPDATE_URL" "$script_path" 2>/dev/null; then
            release_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/dist/vps.sh"
            if [[ -f "$release_path" ]]; then
                copy_shortcut_candidate "$release_path" "$script_path" "本地脚本" || {
                    echo -e "${YELLOW}⚠️ 快捷指令本地注册失败，请稍后在主菜单 [17] 更新脚本完成注册。${PLAIN}"
                    return
                }
            # 若远端拉取失败，且检测到 $0 确实是本地存在的物理文件，才允许复制
            elif [[ -f "$0" ]]; then
                copy_shortcut_candidate "$(readlink -f "$0")" "$script_path" "当前脚本 \$0" || {
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

is_trusted_remote_script_url() {
    local url="$1"
    case "$url" in
        "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh"|\
        "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh")
            echo "VPS-Optimize 项目维护脚本"
            return 0
            ;;
        "https://get.docker.com")
            echo "Docker 官方安装脚本"
            return 0
            ;;
        "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"|\
        "https://raw.githubusercontent.com/mhsanaei/3x-ui/v2.9.4/install.sh")
            echo "3x-ui 官方安装脚本"
            return 0
            ;;
        "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh")
            echo "S-UI 官方安装脚本"
            return 0
            ;;
        "https://github.com/233boy/sing-box/raw/main/install.sh"|\
        "https://github.com/233boy/Xray/raw/main/install.sh")
            echo "233boy 官方安装脚本"
            return 0
            ;;
        "https://yabs.sh"|\
        "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh"|\
        "https://about.superbench.pro"|\
        "https://bench.sh"|\
        "https://check.unlock.media"|\
        "https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh"|\
        "https://IP.Check.Place"|\
        "https://run.NodeQuality.com"|\
        "https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh"|\
        "https://raw.githubusercontent.com/zhouh047/realm-oneclick-install/main/realm.sh"|\
        "https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh"|\
        "https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh"|\
        "https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh"|\
        "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"|\
        "https://git.io/aria2.sh"|\
        "http://v7.hostcli.com/install/install-ubuntu_6.0.sh"|\
        "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh"|\
        "https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh"|\
        "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"|\
        "https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh"|\
        "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh")
            echo "项目内置硬编码外部脚本源"
            return 0
            ;;
    esac
    return 1
}

run_remote_script() {
    local desc="$1"
    local url="$2"
    shift 2
    local tmp_file rc confirm trusted_source
    echo -e "${CYAN}▶ ${desc}${PLAIN}"
    echo -e "${YELLOW}脚本来源：${url}${PLAIN}"
    if trusted_source=$(is_trusted_remote_script_url "$url"); then
        echo -e "${GREEN}内置已知来源：${trusted_source}${PLAIN}"
    else
        trusted_source=""
        echo -e "${RED}⚠️ 非内置已知来源：该 URL 不在 VPS-Optimize 内置远程脚本白名单内。${PLAIN}"
    fi
    if [[ "$url" != https://* ]]; then
        echo -e "${YELLOW}⚠️ 该来源不是 HTTPS，将按脚本内置地址继续下载执行。${PLAIN}"
    fi

    if [[ -z "$trusted_source" || "${VPSO_REMOTE_SCRIPT_CONFIRM:-1}" != "0" ]]; then
        if declare -F confirm_risk_action >/dev/null 2>&1; then
            confirm_risk_action "$desc" \
                "下载并执行远程脚本：${url}" \
                "取消执行，或根据远程脚本自身备份/卸载方式恢复；必要时使用 VPS 快照或救援模式回滚" \
                "确认脚本来源可信，并保持当前 SSH 会话不要断开。" || return 1
        else
            read -r -p "继续请输入 yes，直接回车取消（大小写均可）: " confirm
            [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]] || return 1
        fi
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
