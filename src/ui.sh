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
    local snapshot_advice="${5:-建议先创建 VPS 快照，或确认云厂商快照/救援控制台可用。}"
    local confirm
    echo -e "${RED}⚠️ 高风险操作：${title}${PLAIN}"
    echo ""
    echo -e "${YELLOW}操作名称：${PLAIN}${title}"
    echo -e "${YELLOW}将修改的内容：${PLAIN}"
    echo -e "- ${impact}"
    echo ""
    echo -e "${YELLOW}可能风险：${PLAIN}"
    echo "- 操作失败可能导致 SSH、面板、反代、证书、容器或网络服务短暂不可用。"
    echo "- 如果云厂商安全组、防火墙、监听地址或证书配置不匹配，可能导致远程访问中断。"
    echo ""
    echo -e "${BLUE}出错恢复方式：${PLAIN}"
    echo -e "- ${rollback}"
    echo "- 使用当前未断开的 SSH 会话恢复配置。"
    echo "- 使用云厂商控制台、VNC 或救援模式恢复。"
    echo "- 使用备份与回滚入口恢复已纳入备份的配置。"
    echo ""
    echo -e "${CYAN}是否建议先做快照：${PLAIN}${snapshot_advice}"
    echo -e "${CYAN}建议：${PLAIN}"
    echo "- 已创建 VPS 快照。"
    echo "- 已确认云厂商安全组和系统防火墙规则。"
    echo "- 当前 SSH 会话不要断开。"
    [[ -n "$advice" ]] && echo -e "- ${advice}"
    echo ""
    read_trimmed confirm "直接回车继续，输入 n 取消（大小写均可）: "
    is_yes "$confirm"
}

confirm_risk_action() {
    confirm_danger "$@"
}

render_menu() {
    local items_name="$1"
    local -n menu_items="$items_name"
    local item number title description handler risk

    for item in "${menu_items[@]}"; do
        IFS='|' read -r number title description handler risk <<< "$item"
        echo -e "${GREEN}  ${number}. ${title}${PLAIN}   ${YELLOW}(${description})${PLAIN}"
    done
}

dispatch_menu_choice() {
    local choice="$1"
    local items_name="$2"
    local -n menu_items="$items_name"
    local item number title description handler risk

    for item in "${menu_items[@]}"; do
        IFS='|' read -r number title description handler risk <<< "$item"
        if [[ "$choice" == "$number" ]]; then
            if [[ -n "$risk" ]] && declare -F confirm_menu_risk >/dev/null; then
                confirm_menu_risk "$risk" || return 0
            fi
            "$handler"
            return 0
        fi
    done
    return 1
}
