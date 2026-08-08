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
