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

print_action_summary() {
    local level="$1"
    local title="$2"
    local impact="$3"
    local rollback="$4"
    local advice="${5:-}"
    local snapshot_advice="${6:-}"

    if [[ -z "$snapshot_advice" ]]; then
        if [[ "$level" == "danger" ]]; then
            snapshot_advice="$(localized_text \
                "建议先创建 VPS 快照，或确认云厂商快照/救援控制台可用。" \
                "Create a VPS snapshot first, or confirm that snapshot or rescue-console access is available." \
                "Сначала создайте снимок VPS или убедитесь, что доступны снимок либо аварийная консоль.")"
        else
            snapshot_advice="$(localized_text \
                "确认上方参数无误。" \
                "Verify the values above." \
                "Проверьте указанные выше значения.")"
        fi
    fi

    if [[ "$level" == "danger" ]]; then
        echo -e "$(localized_text "${RED}⚠️ 高风险操作：${title}${PLAIN}" "${RED}⚠️ High-risk operation: ${title}${PLAIN}" "${RED}⚠️ Операция высокого риска: ${title}${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 操作确认：${title}${PLAIN}" "${YELLOW}⚠️ Confirm operation: ${title}${PLAIN}" "${YELLOW}⚠️ Подтвердите операцию: ${title}${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}将修改：${PLAIN}${impact}" "${YELLOW}Changes:${PLAIN} ${impact}" "${YELLOW}Изменения:${PLAIN} ${impact}")"
    echo -e "$(localized_text "${BLUE}恢复方式：${PLAIN}${rollback}" "${BLUE}Recovery:${PLAIN} ${rollback}" "${BLUE}Восстановление:${PLAIN} ${rollback}")"
    echo -e "$(localized_text "${CYAN}操作前：${PLAIN}${snapshot_advice}" "${CYAN}Before continuing:${PLAIN} ${snapshot_advice}" "${CYAN}Перед продолжением:${PLAIN} ${snapshot_advice}")"
    [[ -n "$advice" ]] && echo -e "$(localized_text "${CYAN}注意：${PLAIN}${advice}" "${CYAN}Note:${PLAIN} ${advice}" "${CYAN}Важно:${PLAIN} ${advice}")"
}

confirm_default_yes() {
    local confirm
    while true; do
        read_trimmed confirm "$(localized_text "确认执行？(Y/n，默认 Y): " "Proceed? (Y/n, default Y): " "Продолжить? (Y/n, по умолчанию Y): ")" || return 1
        case "$(trim_input "$confirm" | tr '[:upper:]' '[:lower:]')" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *)
                echo -e "$(localized_text "${YELLOW}请输入 Y 或 n。${PLAIN}" "${YELLOW}Enter Y or n.${PLAIN}" "${YELLOW}Введите Y или n.${PLAIN}")"
                ;;
        esac
    done
}

confirm_default_no() {
    local prompt="${1:-$(localized_text "确认继续？(y/N): " "Continue? (y/N): " "Продолжить? (y/N): ")}"
    local confirm
    while true; do
        read_trimmed confirm "$prompt" || return 1
        case "$(trim_input "$confirm" | tr '[:upper:]' '[:lower:]')" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            "")
                echo -e "$(localized_text "${GREEN}尚未执行；已填写参数仍保留。输入 y 继续，输入 n 取消。${PLAIN}" "${GREEN}Not executed; entered values are preserved. Enter y to continue or n to cancel.${PLAIN}" "${GREEN}Операция не запущена; введённые значения сохранены. Введите y для продолжения или n для отмены.${PLAIN}")"
                ;;
            *)
                echo -e "$(localized_text "${YELLOW}请输入 y 或 N。${PLAIN}" "${YELLOW}Enter y or N.${PLAIN}" "${YELLOW}Введите y или N.${PLAIN}")"
                ;;
        esac
    done
}

confirm_danger() {
    local title="$1"
    local impact="$2"
    local rollback="$3"
    local advice="${4:-}"
    local snapshot_advice="${5:-}"
    local confirm confirm_word

    print_action_summary "danger" "$title" "$impact" "$rollback" "$advice" "$snapshot_advice"
    echo -e "$(localized_text \
        "${BOLD}${GREEN}默认 N：${PLAIN}直接回车仅停留在本页，已填写参数不会丢失。" \
        "${BOLD}${GREEN}Default N:${PLAIN} Enter keeps this page open and preserves the values you entered." \
        "${BOLD}${GREEN}По умолчанию N:${PLAIN} Enter оставляет эту страницу открытой и сохраняет введённые значения.")"

    while true; do
        read_trimmed confirm "$(localized_text "继续执行？(y/N): " "Continue? (y/N): " "Продолжить? (y/N): ")" || return 1
        case "$(trim_input "$confirm" | tr '[:upper:]' '[:lower:]')" in
            "")
                echo -e "$(localized_text "${GREEN}尚未执行；参数已保留。输入 y 继续，输入 n 取消。${PLAIN}" "${GREEN}Not executed; values are preserved. Enter y to continue or n to cancel.${PLAIN}" "${GREEN}Операция не запущена; значения сохранены. Введите y для продолжения или n для отмены.${PLAIN}")"
                ;;
            n|no) return 1 ;;
            y|yes)
                while true; do
                    read_trimmed confirm_word "$(localized_text "再次确认：输入 YES 执行，直接回车返回上一步: " "Final confirmation: enter YES to proceed, or press Enter to go back: " "Повторное подтверждение: введите YES для запуска или нажмите Enter, чтобы вернуться: ")" || return 1
                    case "$(trim_input "$confirm_word" | tr '[:lower:]' '[:upper:]')" in
                        YES) return 0 ;;
                        "")
                            echo -e "$(localized_text "${GREEN}已返回上一步；参数仍保留。${PLAIN}" "${GREEN}Back to the previous confirmation; values are still preserved.${PLAIN}" "${GREEN}Возврат к предыдущему подтверждению; значения сохранены.${PLAIN}")"
                            break
                            ;;
                        *)
                            echo -e "$(localized_text "${YELLOW}确认词不匹配，操作尚未执行。请输入 YES，或直接回车返回上一步。${PLAIN}" "${YELLOW}Confirmation did not match; nothing was executed. Enter YES, or press Enter to go back.${PLAIN}" "${YELLOW}Подтверждение не совпало; операция не запущена. Введите YES или нажмите Enter, чтобы вернуться.${PLAIN}")"
                            ;;
                    esac
                done
                ;;
            *)
                echo -e "$(localized_text "${YELLOW}请输入 y 或 N。${PLAIN}" "${YELLOW}Enter y or N.${PLAIN}" "${YELLOW}Введите y или N.${PLAIN}")"
                ;;
        esac
    done

}

action_needs_safe_default() {
    local title
    local impact
    title=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
    impact=$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')

    case "$title" in
        *删除*|*清理*|*清空*|*隔离*|*卸载*|*重装*|*重启*|*关机*|*停机*|*恢复*|*回滚*|*停止*|*停用*|*关闭*|*覆盖*|*白名单*|*防火墙*|*监听公网*|*重置*|*切换*|*迁移*|*应用*|*重签*|*公网\ 443*|*delete*|*remove*|*prune*|*clean*|*clear*|*quarantine*|*isolate*|*uninstall*|*reinstall*|*restart*|*reboot*|*shutdown*|*poweroff*|*restore*|*rollback*|*stop*|*disable*|*overwrite*|*whitelist*|*allowlist*|*firewall*|*publicly*|*public\ port\ 443*|*reset*|*switch*|*migrate*|*apply*|*re-sign*|*удал*|*Удал*|*очист*|*Очист*|*карантин*|*Карантин*|*изолир*|*Изолир*|*переустанов*|*Переустанов*|*перезап*|*Перезап*|*перезагруз*|*Перезагруз*|*выключ*|*Выключ*|*восстанов*|*Восстанов*|*откат*|*Откат*|*останов*|*Останов*|*отключ*|*Отключ*|*сброс*|*Сброс*|*переключ*|*Переключ*|*мигр*|*Мигр*|*примен*|*Примен*|*переподп*|*Переподп*|*белый\ список*|*Белый\ список*|*список\ разреш*|*Список\ разреш*|*брандмауэр*|*Брандмауэр*|*публичн*443*|*Публичн*443*)
            return 0
            ;;
    esac
    case "$impact" in
        *删除*|*清空*|*关机*|*重启*|*覆盖*|*公网\ 443*|*erase*|*delete*|*shutdown*|*poweroff*|*restart*|*overwrite*|*public\ port\ 443*|*удал*|*Удал*|*очист*|*Очист*|*перезагруз*|*Перезагруз*|*выключ*|*Выключ*|*перезапис*|*Перезапис*|*публичн*443*|*Публичн*443*)
            return 0
            ;;
    esac
    return 1
}

confirm_risk_action() {
    if action_needs_safe_default "$1" "$2"; then
        confirm_danger "$@"
        return $?
    fi
    print_action_summary "risk" "$1" "$2" "$3" "${4:-}" "${5:-}"
    confirm_default_yes
}

terminal_text_width() {
    local text="$1"
    local width

    width=$(printf '%s\n' "$text" | LC_ALL=C.UTF-8 wc -L 2>/dev/null) \
        || width=$(printf '%s\n' "$text" | LC_ALL=C.utf8 wc -L 2>/dev/null) \
        || width=$(printf '%s\n' "$text" | wc -L 2>/dev/null) \
        || width=${#text}
    [[ "$width" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]] || width=${#text}
    printf '%d' "$width"
}

print_menu_item() {
    local number="$1"
    local title="$2"
    local description="$3"
    local title_column="${4:-28}"
    local number_color="${5:-$GREEN}"
    local description_color="${6:-$YELLOW}"
    local title_color="${7:-}"
    local title_width padding

    title_width=$(terminal_text_width "$title")
    padding=$((title_column - title_width + 2))
    (( padding < 2 )) && padding=2
    printf ' %b%2s.%b %b%s%b%*s%b(%s)%b\n' \
        "$number_color" "$number" "$PLAIN" "$title_color" "$title" "$PLAIN" \
        "$padding" '' "$description_color" "$description" "$PLAIN"
}

render_menu() {
    local items_name="$1"
    local -n menu_items="$items_name"
    local item number title description handler risk title_width
    local title_column=0

    for item in "${menu_items[@]}"; do
        IFS='|' read -r number title description handler risk <<< "$item"
        title_width=$(terminal_text_width "$title")
        (( title_width > title_column )) && title_column=$title_width
    done
    for item in "${menu_items[@]}"; do
        IFS='|' read -r number title description handler risk <<< "$item"
        print_menu_item "$number" "$title" "$description" "$title_column" "$GREEN" "$YELLOW" "$GREEN"
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
