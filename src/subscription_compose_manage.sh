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
    echo -e "$(localized_text "${BOLD}${YELLOW}UPD 更新订阅管理工具 (Docker Compose)${PLAIN}" "${BOLD}UPD Update Subscription Management Tool (Docker Compose)${PLAIN}" "${BOLD}UPD Средство управления подпиской на обновления (Docker Compose)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}这个菜单只更新订阅管理工具容器，不会更新 3x-ui / Sing-box / Xray。${PLAIN}" "${YELLOW}This menu only updates the subscription management tool container, and will not update 3x-ui / Sing-box / Xray.${PLAIN}" "${YELLOW}Это меню обновляет только контейнер средства управления подписками и не обновляет 3x-ui / Sing-box / Xray.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${BOLD}${YELLOW}  1. UPD 更新 SublinkPro${PLAIN}       ${CYAN}(/opt/sublinkpro)${PLAIN}" "${BOLD}1. UPD update SublinkPro (/opt/sublinkpro)${PLAIN}" "${BOLD}1. Обновление UPD SublinkPro (/opt/sublinkpro)${PLAIN}")"
    echo -e "$(localized_text "${BOLD}${YELLOW}  2. UPD 更新 妙妙屋订阅管理${PLAIN}     ${CYAN}(/opt/miaomiaowu)${PLAIN}" "${BOLD}2. UPD update Miaomiaowu Subscription Management (/opt/miaomiaowu)${PLAIN}" "${BOLD}2. Обновление UPD Управление подписками Miaomiaowu (/opt/miaomiaowu)${PLAIN}")"
    echo -e "$(localized_text "${BOLD}${YELLOW}  3. UPD 更新 Sub-Store${PLAIN}        ${CYAN}(/opt/sub-store)${PLAIN}" "${BOLD}3. UPD update Sub-Store (/opt/sub-store)${PLAIN}" "${BOLD}3. Дополнительный магазин обновления UPD (/opt/sub-store)${PLAIN}")"
    echo -e "$(localized_text "${BOLD}${YELLOW}  4. UPD 全部更新${PLAIN}" "${BOLD}4. UPD all updated${PLAIN}" "${BOLD}4. UPD все обновлено${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Return / q Return${PLAIN}" "${RED}0. Возврат / q Возврат${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice
    read_trimmed choice "$(localized_text "请选择要更新的项目: " "Please select items to update:" "Пожалуйста, выберите элементы для обновления:")"
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
    read_trimmed prune_confirm "$(localized_text "是否清理无标签旧镜像以释放磁盘空间？(Y/n，默认 y): " "Clean old unlabeled images to free up disk space? (Y/n, default y):" "Очистить старые немаркированные изображения, чтобы освободить место на диске? (Да/нет, по умолчанию y):")"
    if is_yes "$prune_confirm"; then
        docker image prune -f
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}
