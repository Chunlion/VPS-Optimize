# shellcheck shell=bash
# Managed subscription-tool update workflow.

update_compose_project() {
    local name="$1"
    local dir="$2"

    if [[ ! -d "$dir" || ! -f "$dir/docker-compose.yml" ]]; then
        echo -e "${YELLOW}⚠️ 未找到 ${name} 的 Compose 配置：${dir}/docker-compose.yml，已跳过。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在更新 ${name}...${PLAIN}"
    (
        cd "$dir" || exit 1
        $DOCKER_COMPOSE_CMD pull
        $DOCKER_COMPOSE_CMD up -d
    )
}

func_update_subscription_tools() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}${YELLOW}UPD 更新订阅管理工具 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}这个菜单只更新订阅管理工具容器，不会更新 3x-ui / Sing-box / Xray。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${BOLD}${YELLOW}  1. UPD 更新 SublinkPro${PLAIN}       ${CYAN}(/opt/sublinkpro)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  2. UPD 更新 妙妙屋订阅管理${PLAIN}     ${CYAN}(/opt/miaomiaowu)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  3. UPD 更新 Sub-Store${PLAIN}        ${CYAN}(/opt/sub-store)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  4. UPD 全部更新${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice
    read_trimmed choice "请选择要更新的项目: "
    [[ "$choice" == "0" ]] && return

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    case "$choice" in
        1) update_compose_project "SublinkPro" "/opt/sublinkpro" ;;
        2) update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" ;;
        3) update_compose_project "Sub-Store" "/opt/sub-store" ;;
        4)
            update_compose_project "SublinkPro" "/opt/sublinkpro" || true
            update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" || true
            update_compose_project "Sub-Store" "/opt/sub-store" || true
            ;;
        *)
            echo -e "${RED}❌ 无效选择！${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
            ;;
    esac

    echo -e "------------------------------------------------"
    echo -e "${GREEN}✅ 更新流程已执行完成。${PLAIN}"
    local prune_confirm
    read_trimmed prune_confirm "是否清理无标签旧镜像以释放磁盘空间？(y/n，默认 n): "
    if [[ "$prune_confirm" =~ ^[Yy]$ ]]; then
        docker image prune -f
    fi
    read -n 1 -s -r -p "按任意键返回..."
}
