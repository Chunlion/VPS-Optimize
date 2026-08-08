# shellcheck shell=bash
# UI output and confirmation helpers.

print_breadcrumb() {
    echo -e "${CYAN}VPS-Optimize > $*${PLAIN}"
}

pause_return() {
    local default_prompt
    if declare -F localized_text >/dev/null 2>&1; then
        default_prompt="$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    else
        default_prompt="$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    fi
    local prompt="${1:-$default_prompt}"
    read -n 1 -s -r -p "$prompt"
    echo ""
}

confirm_danger() {
    local title="$1"
    local impact="$2"
    local rollback="$3"
    local advice="${4:-}"
    local snapshot_advice="$(localized_text "${5:-建议先创建 VPS 快照，或确认云厂商快照/救援控制台可用。}" "${5:-建议先创建 VPS 快照，或确认云厂商快照/救援控制台可用。}" "${5:-建议先创建 VPS 快照，或确认云厂商快照/救援控制台可用。}")"
    local confirm
    echo -e "$(localized_text "${RED}⚠️ 高风险操作：${title}${PLAIN}" "${RED}⚠️ High-risk operation: ${title}${PLAIN}" "${RED}⚠️ Операция высокого риска: ${title}${PLAIN}")"
    echo ""
    echo -e "$(localized_text "${YELLOW}操作名称：${PLAIN}${title}" "${YELLOW}Operation name:${PLAIN}${title}" "${YELLOW}Имя операции:${PLAIN}${title}")"
    echo -e "$(localized_text "${YELLOW}将修改的内容：${PLAIN}" "${YELLOW}Will modify the content:${PLAIN}" "${YELLOW}изменит содержимое:${PLAIN}")"
    echo -e "- ${impact}"
    echo ""
    echo -e "$(localized_text "${YELLOW}可能风险：${PLAIN}" "${YELLOW}Possible risks:${PLAIN}" "${YELLOW}Возможные риски:${PLAIN}")"
    echo "$(localized_text "- 操作失败可能导致 SSH、面板、反代、证书、容器或网络服务短暂不可用。" "- Operation failure may cause SSH, panel, reverse proxy, certificate, container or network service to be temporarily unavailable." "- Сбой в работе может привести к временной недоступности SSH, панели, обратный прокси, сертификата, контейнера или сетевой службы.")"
    echo "$(localized_text "- 如果云厂商安全组、防火墙、监听地址或证书配置不匹配，可能导致远程访问中断。" "- If the cloud vendor's security group, firewall, listening address, or certificate configurations do not match, remote access may be interrupted." "- Если конфигурация группы безопасности, брандмауэра, адреса прослушивания или сертификата поставщика облака не совпадает, удаленный доступ может быть прерван.")"
    echo ""
    echo -e "$(localized_text "${BLUE}出错恢复方式：${PLAIN}" "${BLUE}Error recovery method:${PLAIN}" "${BLUE}Метод восстановления ошибки :${PLAIN}")"
    echo -e "- ${rollback}"
    echo "$(localized_text "- 使用当前未断开的 SSH 会话恢复配置。" "- Restore the configuration using a currently undisconnected SSH session." "- Восстановите конфигурацию, используя в данный момент неотключенный сеанс SSH.")"
    echo "$(localized_text "- 使用云厂商控制台、VNC 或救援模式恢复。" "- Restore using cloud vendor console, VNC or rescue mode." "- Восстановление с помощью консоли облачного поставщика, VNC или режима восстановления.")"
    echo "$(localized_text "- 使用备份与回滚入口恢复已纳入备份的配置。" "- Use the backup and rollback menu to restore configurations that have been included in the backup." "- Используйте точка входа резервного копирования и отката для восстановления конфигураций, включенных в резервную копию.")"
    echo ""
    echo -e "$(localized_text "${CYAN}是否建议先做快照：${PLAIN}${snapshot_advice}" "${CYAN}Is it recommended to take a snapshot first:${PLAIN}${snapshot_advice}" "${CYAN}Рекомендуется ли сначала сделать снимок:${PLAIN}${snapshot_advice}")"
    echo -e "$(localized_text "${CYAN}建议：${PLAIN}" "${CYAN}Recommendation:${PLAIN}" "${CYAN}Рекомендация:${PLAIN}")"
    echo "$(localized_text "- 已创建 VPS 快照。" "- VPS snapshot created." "- Создан снимок VPS.")"
    echo "$(localized_text "- 已确认云厂商安全组和系统防火墙规则。" "- The cloud vendor security group and system firewall rules have been confirmed." "— Группа безопасности поставщика облака и правила системного брандмауэра подтверждены.")"
    echo "$(localized_text "- 当前 SSH 会话不要断开。" "- Do not disconnect the current SSH session." "- Не отключайте текущий сеанс SSH.")"
    [[ -n "$advice" ]] && echo -e "- ${advice}"
    echo ""
    read_trimmed confirm "$(localized_text "直接回车继续，输入 n 取消（大小写均可）: " "Just press Enter to continue, enter n to cancel (both uppercase and lowercase are acceptable):" "Просто нажмите Enter, чтобы продолжить, введите n для отмены (допускаются как прописные, так и строчные буквы):")"
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
