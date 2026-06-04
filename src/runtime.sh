# shellcheck shell=bash
# Runtime privilege guard used before starting the menu.

# --- Runtime guard ---
ensure_runtime_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ 错误：请以 root 用户身份运行本脚本！${PLAIN}"
        exit 1
    fi
}
