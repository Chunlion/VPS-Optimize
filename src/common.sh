# shellcheck shell=bash
# Common constants, platform detection, package helpers, and remote script helpers.

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

SCRIPT_VERSION="v2.6"
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
    echo -e "$(localized_text "${RED}❌ 软件包${action}失败: $*${PLAIN}" "${RED}❌ Package ${action} failed: $*${PLAIN}" "${RED}❌ Ошибка пакета ${action}: $*${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}日志: ${log_file}${PLAIN}" "${YELLOW}Log: ${log_file}${PLAIN}" "${YELLOW}Журнал : ${log_file}${PLAIN}")"
    if [[ -s "$log_file" ]]; then
        echo -e "$(localized_text "${YELLOW}最近 20 行:${PLAIN}" "${YELLOW}Last 20 lines:${PLAIN}" "${YELLOW}Последние 20 строк:${PLAIN}")"
        tail -n 20 "$log_file" 2>/dev/null || true
    else
        echo -e "$(localized_text "${YELLOW}日志为空，可能是包管理器未能启动或当前系统不支持该操作。${PLAIN}" "${YELLOW}Log is empty. It may be that the package manager failed to start or the current system does not support this operation.${PLAIN}" "${YELLOW}Журнал пуст. Возможно, менеджер пакетов не запустился или текущая система не поддерживает эту операцию.${PLAIN}")"
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
        echo -e "$(localized_text "${RED}❌ 当前系统暂不支持自动安装软件包：OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}" "${RED}❌ The current system does not support automatic installation of software packages: OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}" "${RED}❌ Текущая система не поддерживает автоматическую установку пакетов программного обеспечения: OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}")"
        rm -f "$log_file"
        return 1
    fi
    if [[ "$rc" -eq 0 ]]; then
        rm -f "$log_file"
    else
        print_pkg_failure_log "$(localized_text "安装" "Installation" "Установка")" "$log_file" "${pkgs[@]}"
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
        echo -e "$(localized_text "${RED}❌ 当前系统暂不支持自动卸载软件包：OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}" "${RED}❌ The current system does not support automatic uninstallation of software packages: OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}" "${RED}❌ Текущая система не поддерживает автоматическое удаление пакетов программного обеспечения: OS=${OS:-unknown} ID_LIKE=${OS_LIKE:-unknown}${PLAIN}")"
        rm -f "$log_file"
        return 1
    fi
    if [[ "$rc" -eq 0 ]]; then
        rm -f "$log_file"
    else
        print_pkg_failure_log "$(localized_text "移除" "Remove" "Удалить")" "$log_file" "${pkgs[@]}"
    fi
    return "$rc"
}

minimal_compat_packages() {
    if is_debian; then
        printf '%s\n' \
            ca-certificates curl wget gnupg gpg lsb-release apt-transport-https debian-archive-keyring \
            sudo bash coreutils findutils grep sed gawk util-linux git nano htop lsof net-tools iputils-ping dnsutils \
            iproute2 iptables procps psmisc cron dbus chrony jq unzip tar gzip openssl
    elif is_redhat; then
        printf '%s\n' \
            ca-certificates curl wget gnupg2 redhat-lsb-core iproute iptables procps-ng psmisc cronie \
            sudo bash coreutils findutils grep sed gawk util-linux git nano htop lsof net-tools iputils bind-utils \
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
        echo -e "$(localized_text "${CYAN}▶ 正在补齐精简系统兼容组件...${PLAIN}" "${CYAN}▶ Completing the streamlined system compatible components...${PLAIN}" "${CYAN}▶ Комплектация оптимизированных компонентов, совместимых с системой...${PLAIN}")"
        if install_pkg "${pkgs[@]}"; then
            echo -e "$(localized_text "${GREEN}✅ 精简系统兼容组件已检查/补齐。${PLAIN}" "${GREEN}✅ The streamlined system compatible components have been checked/completed.${PLAIN}" "${GREEN}✅ Компоненты, совместимые с оптимизированной системой, проверены/доработаны.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 部分兼容组件安装失败，请检查软件源或网络。${PLAIN}" "${YELLOW}⚠️ The installation of some compatible components failed, please check the software source or network.${PLAIN}" "${YELLOW}⚠️ Не удалось установить некоторые совместимые компоненты, проверьте источник программного обеспечения или сеть.${PLAIN}")"
            echo -e "$(localized_text "${CYAN}▶ 正在降级为逐个组件补齐，尽量提高兼容性...${PLAIN}" "${CYAN}▶ We are downgrading to complete components one by one to improve compatibility as much as possible...${PLAIN}" "${CYAN}▶ Мы переводим компоненты на более раннюю версию один за другим, чтобы максимально улучшить совместимость...${PLAIN}")"
            for pkg in "${pkgs[@]}"; do
                install_pkg "$pkg" || echo -e "$(localized_text "${YELLOW}  - 跳过不可安装组件: ${pkg}${PLAIN}" "${YELLOW}- Skip uninstallable components: ${pkg}${PLAIN}" "${YELLOW}— пропустить неустанавливаемые компоненты: ${pkg}.${PLAIN}")"
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
    local target_dir tmp_file

    if ! is_vps_optimize_generated_script "$source_file" || ! bash -n "$source_file" >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${label} 未通过 VPS-Optimize 脚本标识校验，已拒绝注册快捷指令。${PLAIN}" "${YELLOW}⚠️ ${label} failed the VPS-Optimize script identification verification and has refused to register the shortcut command.${PLAIN}" "${YELLOW}⚠️ ${label} не прошел проверку идентификации сценария VPS-Optimize и отказался зарегистрировать команду быстрого доступа.${PLAIN}")"
        return 1
    fi
    target_dir=$(dirname "$target_file")
    mkdir -p "$target_dir" 2>/dev/null || return 1
    tmp_file=$(mktemp "${target_file}.XXXXXX") || return 1
    if ! cp "$source_file" "$tmp_file" 2>/dev/null \
        || ! chmod +x "$tmp_file" \
        || ! mv -f "$tmp_file" "$target_file"; then
        rm -f "$tmp_file"
        return 1
    fi
}

script_version_from_file() {
    local file="$1"
    local line version
    line=$(grep -m1 '^SCRIPT_VERSION=' "$file" 2>/dev/null || true)
    version="${line#SCRIPT_VERSION=}"
    version="${version%\"}"
    version="${version#\"}"
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

download_verified_update_script() {
    local output_file="$1"
    local sha_file
    sha_file=$(mktemp /tmp/cy_update.XXXXXX.sha256) || return 1
    if download_remote_script "$UPDATE_URL" "$output_file" \
        && bash -n "$output_file" >/dev/null 2>&1 \
        && is_vps_optimize_generated_script "$output_file" \
        && download_remote_script "$UPDATE_SHA256_URL" "$sha_file" \
        && verify_file_sha256 "$output_file" "$sha_file" >/dev/null; then
        rm -f "$sha_file"
        return 0
    fi
    rm -f "$sha_file" "$output_file"
    return 1
}

sync_shortcut_from_newer_current_script() {
    local current_file="$1"
    local shortcut_file="$2"
    local current_version shortcut_version

    [[ -f "$current_file" && -f "$shortcut_file" ]] || return 1
    is_vps_optimize_generated_script "$current_file" || return 1
    current_version=$(script_version_from_file "$current_file" 2>/dev/null || true)
    shortcut_version=$(script_version_from_file "$shortcut_file" 2>/dev/null || true)
    [[ -n "$current_version" && -n "$shortcut_version" ]] || return 1
    declare -F version_is_newer >/dev/null 2>&1 || return 1
    version_is_newer "$current_version" "$shortcut_version" || return 1
    copy_shortcut_candidate "$current_file" "$shortcut_file" "$(localized_text "当前脚本" "current script" "текущий сценарий")"
}

create_shortcut() {
    local script_path="${VPSO_SHORTCUT_PATH:-/usr/local/bin/cy}"
    local release_path current_file candidate_file
    current_file="${VPSO_CURRENT_SCRIPT_PATH:-$(readlink -f "$0" 2>/dev/null || true)}"

    if [[ -f "$script_path" ]] \
        && is_vps_optimize_generated_script "$script_path" \
        && bash -n "$script_path" >/dev/null 2>&1; then
        if sync_shortcut_from_newer_current_script "$current_file" "$script_path"; then
            echo -e "$(localized_text "${GREEN}✅ 快捷指令 'cy' 已同步到当前较新版本。${PLAIN}" "${GREEN}✅ The shortcut command 'cy' has been synced to the current newer version.${PLAIN}" "${GREEN}✅ Команда быстрого доступа «cy» синхронизирована с текущей более новой версией.${PLAIN}")"
            sleep 1
        fi
        return 0
    fi

    if [[ -f "$script_path" ]]; then
        quarantine_path "$script_path" "/tmp/vps-optimize-quarantine" >/dev/null 2>&1 || return 1
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离无效的旧快捷指令，正在重新注册。${PLAIN}" "${YELLOW}⚠️ The invalid old shortcut command has been quarantined and is being re-registered.${PLAIN}" "${YELLOW}⚠️ Недействительная старая команда быстрого доступа помещена в карантин и перерегистрируется.${PLAIN}")"
    fi

    candidate_file=$(mktemp /tmp/cy_shortcut.XXXXXX.sh) || return 1
    if ! download_verified_update_script "$candidate_file" 2>/dev/null; then
        rm -f "$candidate_file"
        candidate_file=$(mktemp /tmp/cy_shortcut.XXXXXX.sh) || return 1
        if {
            release_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/dist/vps.sh"
            if [[ -f "$release_path" ]]; then
                cp "$release_path" "$candidate_file"
            elif [[ -f "$current_file" ]]; then
                cp "$current_file" "$candidate_file"
            else
                false
            fi
        }; then
            :
        else
            rm -f "$candidate_file"
            echo -e "$(localized_text "${YELLOW}⚠️ 快捷指令注册挂起，请稍后在主菜单 [17] 更新脚本完成注册。${PLAIN}" "${YELLOW}⚠️ Shortcut command registration is pending. Please update the script in the main menu [17] later to complete the registration.${PLAIN}" "${YELLOW}⚠️ Ожидается регистрация команды быстрого доступа. Пожалуйста, обновите скрипт в главном меню [17] позже, чтобы завершить регистрацию.${PLAIN}")"
            return 1
        fi
    fi

    if ! copy_shortcut_candidate "$candidate_file" "$script_path" "$(localized_text "快捷指令候选脚本" "Shortcut candidate script" "Сокращенный сценарий кандидата")"; then
        rm -f "$candidate_file"
        echo -e "$(localized_text "${YELLOW}⚠️ 快捷指令注册失败，请检查 /usr/local/bin 权限。${PLAIN}" "${YELLOW}⚠️ Shortcut command registration failed, please check /usr/local/bin permissions.${PLAIN}" "${YELLOW}⚠️ Не удалось зарегистрировать команду быстрого доступа, проверьте разрешения /usr/local/bin.${PLAIN}")"
        return 1
    fi
    rm -f "$candidate_file"
    echo -e "$(localized_text "${GREEN}✅ 快捷指令 'cy' 已全局注册！下次可直接输入 cy 唤出面板。${PLAIN}" "${GREEN}✅ The shortcut command 'cy' has been globally registered! Next time you can directly enter cy to call up the panel.${PLAIN}" "${GREEN}✅ Команда быстрого доступа «cy» зарегистрирована во всем мире! В следующий раз вы можете напрямую ввести cy для вызова панели.${PLAIN}")"
    sleep 1
}

run_safe() {
    local desc="$1"
    shift
    echo -e "$(localized_text "${CYAN}▶ 正在执行: ${desc}...${PLAIN}" "${CYAN}▶ Executing: ${desc}...${PLAIN}" "${CYAN}▶ Выполнение: ${desc}...${PLAIN}")"
    # 丢弃正常输出保留错误输出，若执行失败则阻断并告警
    if "$@" >/dev/null; then
        echo -e "$(localized_text "${GREEN}✅ ${desc} - 成功！${PLAIN}" "${GREEN}✅ ${desc} - Success!${PLAIN}" "${GREEN}✅ ${desc} - Успех!${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ ${desc} - 失败！请检查系统网络或依赖源。${PLAIN}" "${RED}❌ ${desc} - Failed! Please check the system network or dependency sources.${PLAIN}" "${RED}❌ ${desc} — Ошибка! Пожалуйста, проверьте системную сеть или источники зависимостей.${PLAIN}")"
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
    local local_file

    if [[ "$url" == file://* ]]; then
        local_file="${url#file://}"
        if [[ -f "$local_file" ]] && cp "$local_file" "$output_file" 2>/dev/null; then
            return 0
        fi
        echo -e "$(localized_text "${RED}❌ 本地脚本文件不可读：${local_file}${PLAIN}" "${RED}❌ The local script file is unreadable: ${local_file}${PLAIN}" "${RED}❌ Локальный файл сценария не читается: ${local_file}.${PLAIN}")"
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 缺少 curl/wget，正在尝试自动补齐下载工具...${PLAIN}" "${YELLOW}⚠️ Missing curl/wget, trying to automatically complete the download tool...${PLAIN}" "${YELLOW}⚠️ Отсутствует curl/wget, попытка автоматического завершения загрузки...${PLAIN}")"
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
        echo -e "$(localized_text "${RED}❌ 下载远程脚本失败，请检查网络、DNS 或 GitHub 连通性。${PLAIN}" "${RED}❌ Failed to download remote script, please check network, DNS or GitHub connectivity.${PLAIN}" "${RED}❌ Не удалось загрузить удаленный сценарий. Проверьте сеть, подключение DNS или GitHub.${PLAIN}")"
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
        echo -e "$(localized_text "${RED}❌ sha256 校验文件格式无效：${checksum_file}${PLAIN}" "${RED}❌ sha256 check file format is invalid: ${checksum_file}${PLAIN}" "${RED}❌ sha256 Формат файла проверки недействителен: ${checksum_file}${PLAIN}")"
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ 当前系统缺少 sha256sum，无法校验更新包。${PLAIN}" "${RED}❌ The current system lacks sha256sum and cannot verify the update package.${PLAIN}" "${RED}❌ В текущей системе отсутствует sha256sum, и она не может проверить пакет обновления.${PLAIN}")"
        return 1
    fi

    check_file=$(mktemp /tmp/cy_update_check.XXXXXX.sha256) || return 1
    printf '%s  %s\n' "$expected" "$file" > "$check_file"
    if ! sha256sum -c "$check_file" >/dev/null 2>&1; then
        rm -f "$check_file"
        echo -e "$(localized_text "${RED}❌ sha256 校验失败，已拒绝覆盖 /usr/local/bin/cy。${PLAIN}" "${RED}❌ sha256 verification failed and coverage of /usr/local/bin/cy has been refused.${PLAIN}" "${RED}Проверка ❌ sha256 не удалась, и в покрытии /usr/local/bin/cy было отказано.${PLAIN}")"
        return 1
    fi
    rm -f "$check_file"

    echo -e "$(localized_text "${GREEN}✅ sha256 校验通过。${PLAIN}" "${GREEN}✅ sha256 verification passed.${PLAIN}" "${GREEN}✅ Проверка sha256 пройдена.${PLAIN}")"
}

is_trusted_remote_script_url() {
    local url="$1"
    case "$url" in
        "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh"|\
        "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh")
            echo "$(localized_text "VPS-Optimize 项目维护脚本" "VPS-Optimize project maintenance script" "Сценарий обслуживания проекта VPS-Optimize")"
            return 0
            ;;
        "https://get.docker.com")
            echo "$(localized_text "Docker 官方安装脚本" "Docker official installation script" "Официальный скрипт установки Docker")"
            return 0
            ;;
        "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"|\
        "https://raw.githubusercontent.com/mhsanaei/3x-ui/v2.9.4/install.sh")
            echo "$(localized_text "3x-ui 官方安装脚本" "3x-ui official installation script" "Официальный скрипт установки 3x-ui")"
            return 0
            ;;
        "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh")
            echo "$(localized_text "S-UI 官方安装脚本" "S-UI official installation script" "Официальный скрипт установки S-UI")"
            return 0
            ;;
        "https://raw.githubusercontent.com/EasyTier/EasyTier/main/script/install.sh")
            echo "$(localized_text "EasyTier 官方安装脚本" "EasyTier official installation script" "Официальный скрипт установки EasyTier")"
            return 0
            ;;
        "https://tailscale.com/install.sh")
            echo "$(localized_text "Tailscale 官方安装脚本" "Tailscale official installation script" "Официальный скрипт установки Tailscale")"
            return 0
            ;;
        "https://github.com/233boy/sing-box/raw/main/install.sh"|\
        "https://github.com/233boy/Xray/raw/main/install.sh")
            echo "$(localized_text "233boy 官方安装脚本" "233boy official installation script" "Официальный скрипт установки 233boy")"
            return 0
            ;;
        "https://yabs.sh"|\
        "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh"|\
        "https://about.superbench.pro"|\
        "https://bench.sh"|\
        "https://check.unlock.media"|\
        "https://Check.Place"|\
        "https://raw.githubusercontent.com/Cd1s/network-latency-tester/main/latency.sh"|\
        "https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh"|\
        "https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh"|\
        "https://IP.Check.Place"|\
        "https://run.NodeQuality.com"|\
        "https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh"|\
        "https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh"|\
        "https://raw.githubusercontent.com/qqrrooty/EZgost/main/gost.sh"|\
        "https://raw.githubusercontent.com/Aurora-Admin-Panel/deploy/main/install.sh"|\
        "https://us.arloor.dev/https://github.com/arloor/nftables-nat-rust/releases/download/v2.0.0/setup.sh"|\
        "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"|\
        "https://git.io/aria2.sh"|\
        "http://v7.hostcli.com/install/install-ubuntu_6.0.sh"|\
        "https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh"|\
        "https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh"|\
        "https://raw.githubusercontent.com/poouo/Forwardx/main/scripts/install-panel-local.sh"|\
        "https://raw.githubusercontent.com/Sagit-chu/flvx/main/panel_install.sh"|\
        "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"|\
        "https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh"|\
        "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh")
            echo "$(localized_text "项目内置硬编码外部脚本源" "Project built-in hardcoded external script source" "Встроенный в проект жестко закодированный внешний источник сценария")"
            return 0
            ;;
    esac
    return 1
}

run_remote_script() {
    local desc="$1"
    local url="$2"
    shift 2
    local tmp_file rc trusted_source
    echo -e "${CYAN}▶ ${desc}${PLAIN}"
    echo -e "$(localized_text "${YELLOW}脚本来源：${url}${PLAIN}" "${YELLOW}Script source: ${url}${PLAIN}" "${YELLOW}Источник сценария : ${url}${PLAIN}")"
    if trusted_source=$(is_trusted_remote_script_url "$url"); then
        echo -e "$(localized_text "${GREEN}内置已知来源：${trusted_source}${PLAIN}" "${GREEN}Built-in Known source: ${trusted_source}${PLAIN}" "${GREEN}встроенный Известный источник: ${trusted_source}${PLAIN}")"
    else
        trusted_source=""
        echo -e "$(localized_text "${RED}⚠️ 非内置已知来源：该 URL 不在 VPS-Optimize 内置远程脚本白名单内。${PLAIN}" "${RED}⚠️ Non-built-in known sources: The URL is not in the VPS-Optimize built-in remote script whitelist.${PLAIN}" "${RED}⚠️ Невстроенные известные источники: URL-адрес отсутствует в белом списке встроенных удаленных сценариев VPS-Optimize.${PLAIN}")"
    fi
    if [[ "$url" != https://* && "$url" != file://* ]]; then
        echo -e "$(localized_text "${RED}❌ 该来源不是 HTTPS，已拒绝下载和执行。${PLAIN}" "${RED}❌ The source is not HTTPS and downloading and execution have been refused.${PLAIN}" "${RED}❌ Источник не HTTPS, загрузка и выполнение отклонены.${PLAIN}")"
        return 1
    fi

    tmp_file=$(mktemp /tmp/vps-remote.XXXXXX.sh) || {
        echo -e "$(localized_text "${RED}❌ 临时文件创建失败，已取消执行。${PLAIN}" "${RED}❌ Temporary file creation failed and execution has been cancelled.${PLAIN}" "${RED}❌ Не удалось создать временный файл, и выполнение было отменено.${PLAIN}")"
        return 1
    }
    if ! download_remote_script "$url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "$(localized_text "${RED}❌ 下载失败，请检查网络或脚本来源。${PLAIN}" "${RED}❌ Download failed, please check the network or script source.${PLAIN}" "${RED}❌ Не удалось загрузить, проверьте сеть или источник сценария.${PLAIN}")"
        return 1
    fi
    if ! bash -n "$tmp_file" >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ 远程脚本未通过 Bash 语法检查，已中止执行。${PLAIN}" "${RED}❌ The remote script failed the Bash syntax check and execution was aborted.${PLAIN}" "${RED}❌ Удаленный сценарий не прошел проверку синтаксиса Bash, и выполнение было прервано.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}已保留下载文件用于排查：${tmp_file}${PLAIN}" "${YELLOW}Has reserved the download file for troubleshooting: ${tmp_file}${PLAIN}" "${YELLOW}зарезервировал файл загрузки для устранения неполадок: ${tmp_file}.${PLAIN}")"
        return 1
    fi

    chmod +x "$tmp_file"
    bash "$tmp_file" "$@"
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

pause_after_external_script() {
    local prompt="$(localized_text "${1:-按回车键继续...}" "${1:-按回车键继续...}" "${1:-按回车键继续...}")"
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
    echo -e "$(localized_text "${CYAN}▶ 正在安装 acme.sh...${PLAIN}" "${CYAN}▶ Installing acme.sh...${PLAIN}" "${CYAN}▶ Установка acme.sh...${PLAIN}")"
    if ! download_remote_script "https://get.acme.sh" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "$(localized_text "${RED}❌ acme.sh 安装脚本下载失败。${PLAIN}" "${RED}❌ acme.sh The installation script download failed.${PLAIN}" "${RED}❌ acme.sh Не удалось загрузить сценарий установки.${PLAIN}")"
        return 1
    fi
    if ! sh -n "$tmp_file" >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ acme.sh 安装脚本未通过 sh 语法检查，已中止。${PLAIN}" "${RED}❌ acme.sh The installation script failed the sh syntax check and was aborted.${PLAIN}" "${RED}❌ acme.sh Сценарий установки не прошел проверку синтаксиса sh и был прерван.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}已保留下载文件用于排查：${tmp_file}${PLAIN}" "${YELLOW}Has reserved the download file for troubleshooting: ${tmp_file}${PLAIN}" "${YELLOW}зарезервировал файл загрузки для устранения неполадок: ${tmp_file}.${PLAIN}")"
        return 1
    fi
    sh "$tmp_file" "email=${acme_email}" >/dev/null 2>&1
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}
