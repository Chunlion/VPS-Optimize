# shellcheck shell=bash
# Docker Compose runtime helpers and generic compose project management.

install_docker_compose_standalone() {
    local compose_url tmp_file
    compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    tmp_file=$(mktemp /tmp/docker-compose.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败。${PLAIN}"; return 1; }

    if ! download_remote_script "$compose_url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 下载失败，请检查网络或 GitHub 访问。${PLAIN}"
        return 1
    fi

    if [[ ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 下载文件为空，已取消安装。${PLAIN}"
        return 1
    fi

    if ! mv "$tmp_file" /usr/local/bin/docker-compose; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 写入 /usr/local/bin 失败。${PLAIN}"
        return 1
    fi
    chmod +x /usr/local/bin/docker-compose || return 1
}

ensure_docker_compose_ready() {
    DOCKER_COMPOSE_CMD=""
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 基础组件与常用服务] 中安装 Docker。${PLAIN}"
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您安装...${PLAIN}"
        install_docker_compose_standalone || return 1
        DOCKER_COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi
}

find_compose_file() {
    local dir="$1"
    local file
    for file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        if [[ -f "${dir}/${file}" ]]; then
            echo "${dir}/${file}"
            return 0
        fi
    done
    return 1
}

is_managed_compose_dir() {
    local dir="${1%/}"
    case "$dir" in
        /opt/sublinkpro|/opt/miaomiaowu|/opt/sub-store|/opt/dockge|/opt/komari)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

manage_compose_project() {
    local project_name="$1"
    local project_dir="${2%/}"
    local data_hint="$3"
    local compose_file choice yn

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 ${project_name} 管理 / 卸载${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}部署目录：${CYAN}${project_dir}${PLAIN}"
        echo -e "${YELLOW}数据提示：${CYAN}${data_hint}${PLAIN}"
        echo -e "------------------------------------------------"

        if [[ ! -d "$project_dir" ]] || ! compose_file=$(find_compose_file "$project_dir"); then
            echo -e "${YELLOW}未检测到 ${project_name} 的 Compose 部署。${PLAIN}"
            echo -e "${BLUE}可以先返回上级菜单选择对应安装项。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${GREEN}  1. 查看运行状态${PLAIN}"
        echo -e "${GREEN}  2. 重启服务${PLAIN}"
        echo -e "${GREEN}  3. 更新镜像并重建${PLAIN}"
        echo -e "${CYAN}  4. 查看/编辑 Compose 配置${PLAIN} ${YELLOW}(备份、校验，可选择 up -d)${PLAIN}"
        echo -e "${YELLOW}  5. 停止并移除容器（保留目录数据）${PLAIN}"
        echo -e "${RED}  6. 归档部署目录（停止容器并隔离配置/数据）${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" ps)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            2)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" restart)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            3)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" pull && $DOCKER_COMPOSE_CMD -f "$compose_file" up -d)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            4)
                edit_applied_config_file "$compose_file" "compose" "${project_name} Compose 配置"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            5)
                if confirm_risk_action "停止并移除 ${project_name} 容器" \
                    "Docker Compose 容器运行状态" \
                    "在 ${project_dir} 中重新执行 compose up -d，或回到管理菜单重建" \
                    "目录数据会保留，但服务会立即中断。"; then
                    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down)
                    echo -e "${GREEN}✅ 已停止并移除容器，部署目录仍保留：${project_dir}${PLAIN}"
                else
                    echo -e "${BLUE}已取消操作。${PLAIN}"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            6)
                echo -e "${RED}⚠️  高风险：这会停止容器并把 ${project_dir} 移入隔离目录，配置、数据库或本地数据不再原地可用。${PLAIN}"
                echo -e "${YELLOW}隔离后如需彻底清理，请确认无误后手动处理隔离目录。${PLAIN}"
                if confirm_risk_action "归档 ${project_name} 部署目录" \
                    "Docker Compose 容器、部署目录、配置和本地数据位置" \
                    "从 /opt/.vps-optimize-quarantine 手动移回原路径后重新启动" \
                    "确认已经备份数据库和配置，且服务可以中断。"; then
                    if ! is_managed_compose_dir "$project_dir"; then
                        echo -e "${RED}❌ 安全检查未通过，拒绝归档非脚本托管目录：${project_dir}${PLAIN}"
                    else
                        ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                        (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down -v)
                        if quarantine_path "$project_dir" "/opt/.vps-optimize-quarantine"; then
                            echo -e "${GREEN}✅ 已归档 ${project_name} 部署目录。${PLAIN}"
                        else
                            echo -e "${RED}❌ 归档失败，请手动检查目录：${project_dir}${PLAIN}"
                        fi
                    fi
                else
                    echo -e "${BLUE}已取消归档。${PLAIN}"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            0) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}
