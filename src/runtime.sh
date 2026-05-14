# shellcheck shell=bash
# Runtime privilege guard shared by source and generated release scripts.

# --- Runtime guard ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 错误：请以 root 用户身份运行本脚本！${PLAIN}"
    exit 1
fi
