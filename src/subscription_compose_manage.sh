# shellcheck shell=bash
# Managed subscription-tool update workflow.

update_compose_project() {
    local name="$1"
    local dir="$2"

    if [[ ! -d "$dir" || ! -f "$dir/docker-compose.yml" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 ${name} 的 Compose 配置：${dir}/docker-compose.yml，已跳过。${PLAIN}" "${YELLOW}⚠️ The Compose configuration for ${name} was not found: ${dir}/docker-compose.yml, skipped.${PLAIN}" "${YELLOW}⚠️ Конфигурация Compose для ${name} не найдена: ${dir}/docker-compose.yml, пропущен.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在更新 ${name}...${PLAIN}" "${CYAN}▶Updating ${name}...${PLAIN}" "${CYAN}▶Обновление ${name}...${PLAIN}")"
    (
        cd "$dir" || exit 1
        $DOCKER_COMPOSE_CMD pull
        $DOCKER_COMPOSE_CMD up -d
    )
}

func_update_subscription_tools() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}${YELLOW}更新订阅工具（Docker Compose）${PLAIN}" "${BOLD}${YELLOW}Update subscription tools (Docker Compose)${PLAIN}" "${BOLD}${YELLOW}Обновление инструментов подписки (Docker Compose)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}这个菜单只更新订阅管理工具容器，不会更新 3x-ui / Sing-box / Xray。${PLAIN}" "${YELLOW}This menu only updates the subscription management tool container, and will not update 3x-ui / Sing-box / Xray.${PLAIN}" "${YELLOW}Это меню обновляет только контейнер средства управления подписками и не обновляет 3x-ui / Sing-box / Xray.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}${YELLOW}  1. 更新 SublinkPro${PLAIN} ${CYAN}(/opt/sublinkpro)${PLAIN}" "${BOLD}${YELLOW}  1. Update SublinkPro${PLAIN} ${CYAN}(/opt/sublinkpro)${PLAIN}" "${BOLD}${YELLOW}  1. Обновить SublinkPro${PLAIN} ${CYAN}(/opt/sublinkpro)${PLAIN}")"
    echo -e "$(localized_text "${BOLD}${YELLOW}  2. 更新妙妙屋订阅${PLAIN} ${CYAN}(/opt/miaomiaowu)${PLAIN}" "${BOLD}${YELLOW}  2. Update Miaomiaowu${PLAIN} ${CYAN}(/opt/miaomiaowu)${PLAIN}" "${BOLD}${YELLOW}  2. Обновить Miaomiaowu${PLAIN} ${CYAN}(/opt/miaomiaowu)${PLAIN}")"
    echo -e "$(localized_text "${BOLD}${YELLOW}  3. 更新 Sub-Store${PLAIN} ${CYAN}(/opt/sub-store)${PLAIN}" "${BOLD}${YELLOW}  3. Update Sub-Store${PLAIN} ${CYAN}(/opt/sub-store)${PLAIN}" "${BOLD}${YELLOW}  3. Обновить Sub-Store${PLAIN} ${CYAN}(/opt/sub-store)${PLAIN}")"
    echo -e "$(localized_text "${BOLD}${YELLOW}  4. 全部更新${PLAIN}" "${BOLD}${YELLOW}  4. Update all${PLAIN}" "${BOLD}${YELLOW}  4. Обновить всё${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice
    read_trimmed choice "$(localized_text "选择更新项目: " "Select projects to update: " "Выберите проекты для обновления: ")"
    [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "Q" ]] && return

    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    case "$choice" in
        1) update_compose_project "SublinkPro" "/opt/sublinkpro" ;;
        2) update_compose_project "$(localized_text "妙妙屋订阅管理" "Miaomiaowu Subscription Management" "Управление подпиской Miaomiaowu")" "/opt/miaomiaowu" ;;
        3) update_compose_project "Sub-Store" "/opt/sub-store" ;;
        4)
            update_compose_project "SublinkPro" "/opt/sublinkpro" || true
            update_compose_project "$(localized_text "妙妙屋订阅管理" "Miaomiaowu Subscription Management" "Управление подпиской Miaomiaowu")" "/opt/miaomiaowu" || true
            update_compose_project "Sub-Store" "/opt/sub-store" || true
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
            ;;
    esac

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${GREEN}✅ 更新流程已执行完成。${PLAIN}" "${GREEN}✅ The update process has been completed.${PLAIN}" "${GREEN}✅ Процесс обновления завершен.${PLAIN}")"
    local prune_confirm
    read_trimmed prune_confirm "$(localized_text "是否清理无标签旧镜像以释放磁盘空间？(y/N，默认 N): " "Remove dangling images to free disk space? (y/N, default N): " "Удалить неиспользуемые образы, чтобы освободить место? (y/N, по умолчанию N): ")"
    if is_yes "$prune_confirm"; then
        docker image prune -f
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}
