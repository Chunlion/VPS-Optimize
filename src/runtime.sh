# shellcheck shell=bash
# Runtime privilege guard used before starting the menu.

# --- Runtime guard ---
ensure_runtime_root() {
    if [[ $EUID -ne 0 ]]; then
        localized_echo \
            "${RED}❌ 错误：请以 root 用户身份运行本脚本！${PLAIN}" \
            "${RED}❌ Error: run this script as root.${PLAIN}" \
            "${RED}❌ Ошибка: запустите этот скрипт от имени пользователя root.${PLAIN}"
        exit 1
    fi
}

acquire_vpso_session_lock() {
    local lock_dir="/run/lock"
    local lock_file="${lock_dir}/vps-optimize.lock"
    local owner=""

    command -v flock >/dev/null 2>&1 || {
        localized_echo \
            "${RED}❌ 缺少 flock，无法防止多个会话同时修改配置。${PLAIN}" \
            "${RED}❌ flock is required to prevent concurrent configuration changes.${PLAIN}" \
            "${RED}❌ Для защиты от одновременного изменения конфигурации требуется flock.${PLAIN}"
        exit 1
    }
    mkdir -p "$lock_dir" || exit 1
    exec {VPSO_SESSION_LOCK_FD}>>"$lock_file" || exit 1
    if ! flock -n "$VPSO_SESSION_LOCK_FD"; then
        owner=$(head -n 1 "$lock_file" 2>/dev/null || true)
        localized_echo \
            "${YELLOW}⚠️ 另一个 VPS-Optimize 会话正在运行：${owner:-状态未知}${PLAIN}" \
            "${YELLOW}⚠️ Another VPS-Optimize session is running: ${owner:-unknown}${PLAIN}" \
            "${YELLOW}⚠️ Уже запущен другой сеанс VPS-Optimize: ${owner:-неизвестно}${PLAIN}"
        exit 1
    fi
    : > "$lock_file"
    printf 'pid=%s started=%s\n' "$$" "$(date -Is 2>/dev/null || date)" >&"$VPSO_SESSION_LOCK_FD"
    trap release_vpso_session_lock EXIT
}

release_vpso_session_lock() {
    if [[ -n "${VPSO_SESSION_LOCK_FD:-}" ]]; then
        flock -u "$VPSO_SESSION_LOCK_FD" 2>/dev/null || true
        exec {VPSO_SESSION_LOCK_FD}>&-
        VPSO_SESSION_LOCK_FD=""
    fi
}
