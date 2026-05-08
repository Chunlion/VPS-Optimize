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
