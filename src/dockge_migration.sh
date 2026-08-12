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
        echo -e "$(localized_text "${RED}❌ 未找到 Compose 配置：${source_dir}${PLAIN}" "${RED}❌ Not found Compose Configuration: ${source_dir}${PLAIN}" "${RED}❌ Не найден Compose Конфигурация: ${source_dir}${PLAIN}")"
        return 1
    }

    stack_name=$(ask_with_default "$(localized_text "Dockge stack 名称" "Dockge stack name" "Имя стека Dockge")" "$(basename "$source_dir")")
    if [[ ! "$stack_name" =~ ^[A-Za-z0-9_.-]+$ || "$stack_name" == "." || "$stack_name" == ".." ]]; then
        echo -e "$(localized_text "${RED}❌ stack 名称无效，只能使用字母、数字、点、下划线和短横线。${PLAIN}" "${RED}❌ The stack name is invalid. Only letters, numbers, dots, underscores and dashes can be used.${PLAIN}" "${RED}❌ Недопустимое имя стека. Можно использовать только буквы, цифры, точки, подчеркивания и тире.${PLAIN}")"
        return 1
    fi

    target_dir="${stacks_dir%/}/${stack_name}"
    if [[ "$source_dir" == "$target_dir" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${source_dir} 已经在 Dockge stacks 目录内，已跳过。${PLAIN}" "${YELLOW}⚠️ ${source_dir} is already in the Dockge stacks directory and has been skipped.${PLAIN}" "${YELLOW}⚠️ ${source_dir} уже находится в каталоге стеков Dockge и был пропущен.${PLAIN}")"
        return 0
    fi
    if [[ -e "$target_dir" ]]; then
        echo -e "$(localized_text "${RED}❌ 目标目录已存在：${target_dir}${PLAIN}" "${RED}❌ The target directory already exists: ${target_dir}${PLAIN}" "${RED}❌ Целевой каталог уже существует: ${target_dir}.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请先在 Dockge 中确认是否已有同名 stack，或换一个 stack 名称。${PLAIN}" "${YELLOW}Please first confirm whether there is a stack with the same name in Dockge, or change the stack name.${PLAIN}" "${YELLOW}Сначала проверьте, существует ли стек с таким же именем в Dockge, или измените имя стека.${PLAIN}")"
        return 1
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}将迁移：${CYAN}${source_dir}${PLAIN}" "${YELLOW}Will migrate: ${source_dir}${PLAIN}" "${YELLOW}будет перенесен: ${source_dir}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}迁移到：${CYAN}${target_dir}${PLAIN}" "${YELLOW}Migrated to: ${target_dir}${PLAIN}" "${YELLOW}перенесен в: ${target_dir}.${PLAIN}")"
    echo -e "${YELLOW}Compose：${CYAN}${source_compose}${PLAIN}"
    echo -e "$(localized_text "${YELLOW}说明：会移动整个项目目录，保留相对挂载的数据目录。${PLAIN}" "${YELLOW}Description: The entire project directory will be moved and the relatively mounted data directory will be retained.${PLAIN}" "${YELLOW}Описание: Весь каталог проекта будет перемещен, а связанный с ним каталог данных сохранится.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如果项目使用 Docker 命名卷，建议保持 stack 名称与原目录名一致。${PLAIN}" "${YELLOW}If the project uses Docker to name the volume, it is recommended to keep the stack name consistent with the original directory name.${PLAIN}" "${YELLOW}Если в проекте для имени тома используется Docker, рекомендуется сохранять имя стека в соответствии с исходным именем каталога.${PLAIN}")"
    confirm_risk_action "$(localized_text "迁移 Compose 项目到 Dockge" "Migrate the Compose project to Dockge" "Перенесите проект Compose в Dockge.")" \
        "$(localized_text "Compose 项目目录、容器停止/启动位置和 Dockge stack 路径" "Compose project directory, container stop/start location and Dockge stack path" "Каталог проекта Compose, местоположение остановки/начала контейнера и путь стека Dockge.")" \
        "$(localized_text "把 ${target_dir} 手动移回 ${source_dir}，并用原 compose 文件重新启动" "Manually move ${target_dir} back to ${source_dir} and restart with the original compose file" "Вручную переместите ${target_dir} обратно в ${source_dir} и перезапустите исходный файл compose.")" \
        "$(localized_text "确认项目没有绝对路径依赖，且已备份重要数据。" "Confirm that the project has no absolute path dependencies and that important data has been backed up." "Убедитесь, что проект не имеет абсолютных зависимостей пути и что важные данные были зарезервированы.")" || { echo -e "$(localized_text "${BLUE}已取消迁移 ${source_dir}。${PLAIN}" "${BLUE}Canceled the migration of ${source_dir}.${PLAIN}" "${BLUE}отменил миграцию ${source_dir}.${PLAIN}")"; return 0; }

    read_trimmed restart_confirm "$(localized_text "是否停止旧容器并在新目录重新启动？(y/N，默认 N): " "Stop the old containers and restart them from the new directory? (y/N, default N): " "Остановить старые контейнеры и перезапустить их из нового каталога? (y/N, по умолчанию N): ")"
    if ! is_yes "$restart_confirm"; then
        restart_stack="false"
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "$(localized_text "${CYAN}▶ 正在停止旧目录中的 Compose 项目...${PLAIN}" "${CYAN}▶ Stopping Compose project in old directory...${PLAIN}" "${CYAN}▶ Остановка проекта Compose в старом каталоге...${PLAIN}")"
        ( cd "$source_dir" && $DOCKER_COMPOSE_CMD down ) || {
            echo -e "$(localized_text "${RED}❌ 停止旧项目失败，已中止迁移。${PLAIN}" "${RED}❌ Failed to stop old project, migration aborted.${PLAIN}" "${RED}❌ Не удалось остановить старый проект, миграция прервана.${PLAIN}")"
            return 1
        }
    fi

    mkdir -p "$stacks_dir" || return 1
    mv "$source_dir" "$target_dir" || {
        echo -e "$(localized_text "${RED}❌ 移动目录失败：${source_dir} -> ${target_dir}${PLAIN}" "${RED}❌ Failed to move directory: ${source_dir} -> ${target_dir}${PLAIN}" "${RED}❌ Не удалось переместить каталог: ${source_dir} -> ${target_dir}.${PLAIN}")"
        return 1
    }

    compose_name=$(basename "$source_compose")
    if [[ "$compose_name" == docker-compose.y* && ! -f "${target_dir}/compose.yaml" ]]; then
        mv "${target_dir}/${compose_name}" "${target_dir}/compose.yaml" || {
            echo -e "$(localized_text "${RED}❌ 重命名 Compose 文件失败，请手动检查：${target_dir}${PLAIN}" "${RED}❌ Failed to rename Compose file, please check manually: ${target_dir}${PLAIN}" "${RED}❌ Не удалось переименовать файл Compose, проверьте вручную: ${target_dir}.${PLAIN}")"
            return 1
        }
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "$(localized_text "${CYAN}▶ 正在新目录中重新启动 Compose 项目...${PLAIN}" "${CYAN}▶ Restarting Compose project in new directory...${PLAIN}" "${CYAN}▶ Перезапуск проекта Compose в новом каталоге...${PLAIN}")"
        ( cd "$target_dir" && $DOCKER_COMPOSE_CMD up -d ) || {
            echo -e "$(localized_text "${RED}❌ 新目录启动失败，请手动检查：${target_dir}${PLAIN}" "${RED}❌ New directory startup failed, please check manually: ${target_dir}${PLAIN}" "${RED}❌ Не удалось запустить новый каталог, проверьте вручную: ${target_dir}${PLAIN}")"
            return 1
        }
    fi

    echo -e "$(localized_text "${GREEN}✅ 已迁移到 Dockge stacks：${target_dir}${PLAIN}" "${GREEN}✅ Migrated to Dockge stacks: ${target_dir}${PLAIN}" "${GREEN}вещество перенесено на стеки Dockge: ${target_dir}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请在 Dockge 页面里扫描/刷新 stacks 目录后接管。${PLAIN}" "${YELLOW}Please scan/refresh the stacks directory on the Dockge page and take over.${PLAIN}" "${YELLOW}Пожалуйста, просканируйте/обновите каталог stacks на странице Dockge и возьмите на себя управление.${PLAIN}")"
}

func_migrate_compose_to_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}迁移已有 Compose 项目到 Dockge${PLAIN}" "${BOLD}Migrates the existing Compose project to Dockge${PLAIN}" "${BOLD}переносит существующий проект Compose в Dockge.${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}适合 Dockge 后安装的场景：把已有 docker-compose.yml / compose.yaml 项目移动到 Dockge stacks 目录。${PLAIN}" "${YELLOW}Suitable for the post-installation scenario of Dockge: move the existing docker-compose.yml / compose.yaml project to the Dockge stacks directory.${PLAIN}" "${YELLOW}подходит для сценария после установки Dockge: переместите существующий проект docker-compose.yml/compose.yaml в каталог стеков Dockge.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}建议先确认相关服务可以短暂停机，并已做好重要数据备份。${PLAIN}" "${YELLOW}Recommends confirming that the relevant services can be shut down briefly and that important data has been backed up.${PLAIN}" "${YELLOW}рекомендует подтвердить, что соответствующие службы могут быть ненадолго отключены и что важные данные были сохранены.${PLAIN}")"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    local stacks_dir="/opt/stacks"
    local choice custom_dir i
    stacks_dir=$(ask_with_default "$(localized_text "Dockge stacks 目录" "Dockge stacks directory" "Каталог стеков Dockge")" "$stacks_dir")
    mkdir -p "$stacks_dir" || { echo -e "$(localized_text "${RED}❌ 无法创建 stacks 目录：${stacks_dir}${PLAIN}" "${RED}❌ Unable to create stacks directory: ${stacks_dir}${PLAIN}" "${RED}❌ Невозможно создать каталог стеков: ${stacks_dir}.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    discover_dockge_migration_candidates "$stacks_dir"

    if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -gt 0 ]]; then
        echo -e "$(localized_text "${GREEN}检测到以下可迁移 Compose 项目：${PLAIN}" "${GREEN}Detected the following migratable Compose items:${PLAIN}" "${GREEN}обнаружил следующие переносимые элементы Compose:${PLAIN}")"
        for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
            echo -e "${GREEN}  $((i + 1)). ${DOCKGE_MIGRATION_NAMES[$i]}${PLAIN} ${CYAN}(${DOCKGE_MIGRATION_DIRS[$i]})${PLAIN}"
        done
        echo -e "$(localized_text "${BOLD}${YELLOW}  a. 迁移全部检测到的项目${PLAIN}" "${BOLD}A. Migrate all detected items${PLAIN}" "${BOLD}а. Перенести все обнаруженные элементы${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未在 /opt 下检测到常见 Compose 项目。${PLAIN}" "${YELLOW}⚠️ The common Compose item was not detected under /opt.${PLAIN}" "${YELLOW}⚠️ Общий элемент Compose не был обнаружен в /opt.${PLAIN}")"
    fi
    echo -e "$(localized_text "${CYAN}  c. 手动输入项目目录${PLAIN}" "${CYAN}C. Manually enter the project directory${PLAIN}" "${CYAN}в. Вручную введите каталог проекта.${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 返回${PLAIN}" "${RED}0. Return${PLAIN}" "${RED}0. Возврат${PLAIN}")"
    echo -e "------------------------------------------------"

    read_trimmed choice "$(localized_text "选择要迁移的项目: " "Select projects to migrate: " "Выберите проекты для переноса: ")"
    case "$choice" in
        0) return ;;
        a|A)
            if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -eq 0 ]]; then
                echo -e "$(localized_text "${YELLOW}⚠️ 没有可自动迁移的项目。${PLAIN}" "${YELLOW}⚠️ There are no items that can be automatically migrated.${PLAIN}" "${YELLOW}⚠️ Нет элементов, которые можно перенести автоматически.${PLAIN}")"
            else
                for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
                    migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$i]}" "$stacks_dir" || true
                    echo -e "------------------------------------------------"
                done
            fi
            ;;
        c|C)
            read_trimmed custom_dir "$(localized_text "请输入已有 Compose 项目目录: " "Please enter the existing Compose project directory:" "Пожалуйста, введите существующий каталог проекта Compose:")"
            migrate_compose_project_to_dockge "$custom_dir" "$stacks_dir"
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DOCKGE_MIGRATION_DIRS[@]} )); then
                migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$((choice - 1))]}" "$stacks_dir"
            else
                echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"
            fi
            ;;
    esac

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}
# ---------------------------------------------------------
# 18. 面板救砖/重置 SSL (兼容新版 3x-ui 证书字段)
# ---------------------------------------------------------
