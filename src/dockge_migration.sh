# shellcheck shell=bash
# Dockge migration discovery and migration workflows.

is_dockge_migration_seen() {
    local needle="$1"
    local item
    for item in "${DOCKGE_MIGRATION_DIRS[@]}"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

add_dockge_migration_candidate() {
    local dir="$1"
    local stacks_dir="$2"
    local name

    dir="${dir%/}"
    [[ -d "$dir" ]] || return 0
    [[ "$dir" == "/opt/dockge" ]] && return 0
    [[ "$dir" == "$stacks_dir" || "$dir" == "$stacks_dir"/* ]] && return 0
    find_compose_file "$dir" >/dev/null 2>&1 || return 0
    is_dockge_migration_seen "$dir" && return 0

    name=$(basename "$dir")
    DOCKGE_MIGRATION_NAMES+=("$name")
    DOCKGE_MIGRATION_DIRS+=("$dir")
}

discover_dockge_migration_candidates() {
    local stacks_dir="$1"
    local dir file
    DOCKGE_MIGRATION_NAMES=()
    DOCKGE_MIGRATION_DIRS=()

    for dir in /opt/sublinkpro /opt/miaomiaowu /opt/sub-store; do
        add_dockge_migration_candidate "$dir" "$stacks_dir"
    done

    for file in /opt/*/compose.yaml /opt/*/compose.yml /opt/*/docker-compose.yml /opt/*/docker-compose.yaml; do
        [[ -e "$file" ]] || continue
        add_dockge_migration_candidate "$(dirname "$file")" "$stacks_dir"
    done
}

migrate_compose_project_to_dockge() {
    local source_dir="$1"
    local stacks_dir="$2"
    local source_compose stack_name target_dir compose_name restart_confirm
    local restart_stack="true"

    source_dir="${source_dir%/}"
    source_compose=$(find_compose_file "$source_dir") || {
        echo -e "${RED}❌ 未找到 Compose 配置：${source_dir}${PLAIN}"
        return 1
    }

    stack_name=$(ask_with_default "Dockge stack 名称" "$(basename "$source_dir")")
    if [[ ! "$stack_name" =~ ^[A-Za-z0-9_.-]+$ || "$stack_name" == "." || "$stack_name" == ".." ]]; then
        echo -e "${RED}❌ stack 名称无效，只能使用字母、数字、点、下划线和短横线。${PLAIN}"
        return 1
    fi

    target_dir="${stacks_dir%/}/${stack_name}"
    if [[ "$source_dir" == "$target_dir" ]]; then
        echo -e "${YELLOW}⚠️ ${source_dir} 已经在 Dockge stacks 目录内，已跳过。${PLAIN}"
        return 0
    fi
    if [[ -e "$target_dir" ]]; then
        echo -e "${RED}❌ 目标目录已存在：${target_dir}${PLAIN}"
        echo -e "${YELLOW}请先在 Dockge 中确认是否已有同名 stack，或换一个 stack 名称。${PLAIN}"
        return 1
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}将迁移：${CYAN}${source_dir}${PLAIN}"
    echo -e "${YELLOW}迁移到：${CYAN}${target_dir}${PLAIN}"
    echo -e "${YELLOW}Compose：${CYAN}${source_compose}${PLAIN}"
    echo -e "${YELLOW}说明：会移动整个项目目录，保留相对挂载的数据目录。${PLAIN}"
    echo -e "${YELLOW}如果项目使用 Docker 命名卷，建议保持 stack 名称与原目录名一致。${PLAIN}"
    confirm_risk_action "迁移 Compose 项目到 Dockge" \
        "Compose 项目目录、容器停止/启动位置和 Dockge stack 路径" \
        "把 ${target_dir} 手动移回 ${source_dir}，并用原 compose 文件重新启动" \
        "确认项目没有绝对路径依赖，且已备份重要数据。" || { echo -e "${BLUE}已取消迁移 ${source_dir}。${PLAIN}"; return 0; }

    read_trimmed restart_confirm "是否先停止旧容器并在新目录重新启动？(Y/n): "
    if is_no "$restart_confirm"; then
        restart_stack="false"
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在停止旧目录中的 Compose 项目...${PLAIN}"
        ( cd "$source_dir" && $DOCKER_COMPOSE_CMD down ) || {
            echo -e "${RED}❌ 停止旧项目失败，已中止迁移。${PLAIN}"
            return 1
        }
    fi

    mkdir -p "$stacks_dir" || return 1
    mv "$source_dir" "$target_dir" || {
        echo -e "${RED}❌ 移动目录失败：${source_dir} -> ${target_dir}${PLAIN}"
        return 1
    }

    compose_name=$(basename "$source_compose")
    if [[ "$compose_name" == docker-compose.y* && ! -f "${target_dir}/compose.yaml" ]]; then
        mv "${target_dir}/${compose_name}" "${target_dir}/compose.yaml" || {
            echo -e "${RED}❌ 重命名 Compose 文件失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在新目录中重新启动 Compose 项目...${PLAIN}"
        ( cd "$target_dir" && $DOCKER_COMPOSE_CMD up -d ) || {
            echo -e "${RED}❌ 新目录启动失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    echo -e "${GREEN}✅ 已迁移到 Dockge stacks：${target_dir}${PLAIN}"
    echo -e "${YELLOW}请在 Dockge 页面里扫描/刷新 stacks 目录后接管。${PLAIN}"
}

func_migrate_compose_to_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}迁移已有 Compose 项目到 Dockge${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适合 Dockge 后安装的场景：把已有 docker-compose.yml / compose.yaml 项目移动到 Dockge stacks 目录。${PLAIN}"
    echo -e "${YELLOW}建议先确认相关服务可以短暂停机，并已做好重要数据备份。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local stacks_dir="/opt/stacks"
    local choice custom_dir i
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")
    mkdir -p "$stacks_dir" || { echo -e "${RED}❌ 无法创建 stacks 目录：${stacks_dir}${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    discover_dockge_migration_candidates "$stacks_dir"

    if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -gt 0 ]]; then
        echo -e "${GREEN}检测到以下可迁移 Compose 项目：${PLAIN}"
        for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
            echo -e "${GREEN}  $((i + 1)). ${DOCKGE_MIGRATION_NAMES[$i]}${PLAIN} ${CYAN}(${DOCKGE_MIGRATION_DIRS[$i]})${PLAIN}"
        done
        echo -e "${BOLD}${YELLOW}  a. 迁移全部检测到的项目${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 未在 /opt 下检测到常见 Compose 项目。${PLAIN}"
    fi
    echo -e "${CYAN}  c. 手动输入项目目录${PLAIN}"
    echo -e "${RED}  0. 返回${PLAIN}"
    echo -e "------------------------------------------------"

    read_trimmed choice "请选择要迁移的项目: "
    case "$choice" in
        0) return ;;
        a|A)
            if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -eq 0 ]]; then
                echo -e "${YELLOW}⚠️ 没有可自动迁移的项目。${PLAIN}"
            else
                for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
                    migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$i]}" "$stacks_dir" || true
                    echo -e "------------------------------------------------"
                done
            fi
            ;;
        c|C)
            read_trimmed custom_dir "请输入已有 Compose 项目目录: "
            migrate_compose_project_to_dockge "$custom_dir" "$stacks_dir"
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DOCKGE_MIGRATION_DIRS[@]} )); then
                migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$((choice - 1))]}" "$stacks_dir"
            else
                echo -e "${RED}❌ 无效选择！${PLAIN}"
            fi
            ;;
    esac

    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 18. 面板救砖/重置 SSL (兼容新版 3x-ui 证书字段)
# ---------------------------------------------------------
