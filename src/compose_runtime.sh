# shellcheck shell=bash
# Docker Compose runtime helpers and generic compose project management.

install_docker_compose_standalone() {
    local compose_url tmp_file
    compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    tmp_file=$(mktemp /tmp/docker-compose.XXXXXX) || { echo -e "$(localized_text "${RED}❌ 临时文件创建失败。${PLAIN}" "${RED}❌ Temporary file creation failed.${PLAIN}" "${RED}❌ Не удалось создать временный файл.${PLAIN}")"; return 1; }

    if ! download_remote_script "$compose_url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "$(localized_text "${RED}❌ Docker Compose 下载失败，请检查网络或 GitHub 访问。${PLAIN}" "${RED}❌ Docker Compose download failed, please check the network or GitHub access.${PLAIN}" "${RED}❌ Загрузка Docker Compose не удалась, проверьте сеть или доступ к GitHub.${PLAIN}")"
        return 1
    fi

    if [[ ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file"
        echo -e "$(localized_text "${RED}❌ Docker Compose 下载文件为空，已取消安装。${PLAIN}" "${RED}❌ Docker Compose The download file is empty and the installation has been cancelled.${PLAIN}" "${RED}❌ Docker Compose Файл загрузки пуст, и установка отменена.${PLAIN}")"
        return 1
    fi

    if ! mv "$tmp_file" /usr/local/bin/docker-compose; then
        rm -f "$tmp_file"
        echo -e "$(localized_text "${RED}❌ Docker Compose 写入 /usr/local/bin 失败。${PLAIN}" "${RED}❌ Docker Compose Failed to write /usr/local/bin.${PLAIN}" "${RED}❌ Docker Compose Не удалось записать /usr/local/bin.${PLAIN}")"
        return 1
    fi
    chmod +x /usr/local/bin/docker-compose || return 1
}

ensure_docker_engine_ready() {
    if command -v docker >/dev/null 2>&1; then
        systemctl enable --now docker >/dev/null 2>&1 || true
        return 0
    fi

    echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 Docker，正在自动安装 Docker 引擎...${PLAIN}" "${YELLOW}⚠️ Docker not detected, automatically installing Docker engine...${PLAIN}" "${YELLOW}⚠️ Docker не обнаружен, автоматическая установка двигателя Docker...${PLAIN}")"
    if ! run_remote_script "$(localized_text "安装 Docker 引擎" "Install Docker engine" "Установите двигатель Docker.")" "https://get.docker.com"; then
        echo -e "$(localized_text "${RED}❌ Docker 自动安装失败，请检查网络或软件源。${PLAIN}" "${RED}❌ Docker Automatic installation failed, please check the network or software source.${PLAIN}" "${RED}❌ Docker Не удалось выполнить автоматическую установку. Проверьте сеть или источник программного обеспечения.${PLAIN}")"
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ Docker 安装后仍不可用，请检查安装日志。${PLAIN}" "${RED}❌ Docker is still not available after installation, please check the installation log.${PLAIN}" "${RED}❌ Docker по-прежнему недоступен после установки, проверьте журнал установки.${PLAIN}")"
        return 1
    fi

    systemctl enable --now docker >/dev/null 2>&1 || true
    echo -e "$(localized_text "${GREEN}✅ Docker 引擎已安装。${PLAIN}" "${GREEN}✅ Docker engine has been installed.${PLAIN}" "${GREEN}Установлен двигатель ✅ Docker.${PLAIN}")"
}

ensure_docker_compose_ready() {
    DOCKER_COMPOSE_CMD=""
    ensure_docker_engine_ready || return 1

    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您安装...${PLAIN}" "${YELLOW}⚠️ Docker Compose plug-in not detected, installing for you...${PLAIN}" "${YELLOW}⚠️ Плагин Docker Compose не обнаружен, установка для вас...${PLAIN}")"
        install_docker_compose_standalone || return 1
        DOCKER_COMPOSE_CMD="docker-compose"
        echo -e "$(localized_text "${GREEN}✅ Docker Compose 安装完成。${PLAIN}" "${GREEN}✅ Docker Compose installation completed.${PLAIN}" "${GREEN}✅ Установка Docker Compose завершена.${PLAIN}")"
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
        echo -e "$(localized_text "${BOLD}🧭 ${project_name} 管理${PLAIN}" "${BOLD}🧭 Manage ${project_name}${PLAIN}" "${BOLD}🧭 Управление ${project_name}${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}部署目录：${CYAN}${project_dir}${PLAIN}" "${YELLOW}Deployment directory: ${project_dir}${PLAIN}" "${YELLOW}Каталог развертывания : ${project_dir}.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}数据说明：${CYAN}${data_hint}${PLAIN}" "${YELLOW}Data: ${data_hint}${PLAIN}" "${YELLOW}Данные: ${data_hint}${PLAIN}")"
        echo -e "------------------------------------------------"

        if [[ ! -d "$project_dir" ]] || ! compose_file=$(find_compose_file "$project_dir"); then
            echo -e "$(localized_text "${YELLOW}未检测到 ${project_name} 的 Compose 部署。请返回上级菜单先安装。${PLAIN}" "${YELLOW}No Compose deployment was found for ${project_name}. Return to the previous menu to install it.${PLAIN}" "${YELLOW}Развёртывание Compose для ${project_name} не найдено. Вернитесь в предыдущее меню и выполните установку.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi

        echo -e "$(localized_text "${GREEN}  1. 查看运行状态${PLAIN}" "${GREEN}1. Check the running status${PLAIN}" "${GREEN}1. Проверьте рабочее состояние.${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  2. 查看/编辑 Compose 配置${PLAIN} ${YELLOW}(备份、校验，可选择 up -d)${PLAIN}" "${CYAN}2. View/edit Compose configuration (backup, verification, optional up -d)${PLAIN}" "${CYAN}2. Просмотр/редактирование конфигурации Compose (резервное копирование, проверка, опциональный up -d)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 重启服务${PLAIN}" "${GREEN}3. Restart the service${PLAIN}" "${GREEN}3. Перезапустите службу.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 更新镜像并重建${PLAIN}" "${GREEN}4. Update the image and rebuild${PLAIN}" "${GREEN}4. Обновите образ и пересоберите.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  5. 停止并移除容器（保留目录数据）${PLAIN}" "${YELLOW}5. Stop and remove the container (keep directory data)${PLAIN}" "${YELLOW}5. Остановить и удалить контейнер (сохранить данные каталога)${PLAIN}")"
        echo -e "$(localized_text "${RED}  6. 归档部署目录（停止容器并隔离配置/数据）${PLAIN}" "${RED}6. Archive deployment directory (stop container and isolate configuration/data)${PLAIN}" "${RED}6. Архивировать каталог развертывания (остановить контейнер и изолировать конфигурацию/данные)${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回上级菜单 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" ps)
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                ;;
            2)
                edit_applied_config_file "$compose_file" "compose" "$(localized_text "${project_name} Compose 配置" "${project_name} Compose configuration" "Конфигурация ${project_name} Compose")"
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                ;;
            3)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" restart)
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                ;;
            4)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" pull && $DOCKER_COMPOSE_CMD -f "$compose_file" up -d)
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                ;;
            5)
                if confirm_risk_action "$(localized_text "停止并移除 ${project_name} 容器" "Stop and remove the ${project_name} container" "Остановите и удалите контейнер ${project_name}.")" \
                    "$(localized_text "Docker Compose 容器运行状态" "Docker Compose container running status" "Статус работы контейнера Docker Compose")" \
                    "$(localized_text "在 ${project_dir} 中重新执行 compose up -d，或回到管理菜单重建" "Re-execute compose up -d in ${project_dir}, or return to the management menu to rebuild" "Перезапустите compose up -d в ${project_dir} или вернитесь в меню управления для пересборки.")" \
                    "$(localized_text "目录数据会保留，但服务会立即中断。" "Directory data is preserved, but service is immediately interrupted." "Данные каталога сохраняются, но обслуживание немедленно прерывается.")"; then
                    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }
                    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down)
                    echo -e "$(localized_text "${GREEN}✅ 已停止并移除容器，部署目录仍保留：${project_dir}${PLAIN}" "${GREEN}✅ The container has been stopped and removed, but the deployment directory remains: ${project_dir}${PLAIN}" "${GREEN}. Контейнер остановлен и удален, но каталог развертывания остался: ${project_dir}.${PLAIN}")"
                else
                    echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
                fi
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                ;;
            6)
                echo -e "$(localized_text "${RED}⚠️  高风险：这会停止容器并把 ${project_dir} 移入隔离目录，配置、数据库或本地数据不再原地可用。${PLAIN}" "${RED}⚠️ High Risk: This will stop the container and move ${project_dir} into the quarantine directory, and the configuration, database, or local data will no longer be available in place.${PLAIN}" "${RED}⚠️ Высокий риск: это остановит контейнер и переместит ${project_dir} в каталог карантина, при этом конфигурация, база данных или локальные данные больше не будут доступны.${PLAIN}")"
                echo -e "$(localized_text "${YELLOW}隔离后如需彻底清理，请确认无误后手动处理隔离目录。${PLAIN}" "${YELLOW}If needs to be thoroughly cleaned after isolation, please confirm that it is correct and then manually process the isolation directory.${PLAIN}" "${YELLOW}Если необходимо тщательно очистить после изоляции, убедитесь, что это правильно, а затем вручную обработайте каталог изоляции.${PLAIN}")"
                if confirm_risk_action "$(localized_text "归档 ${project_name} 部署目录" "Archive ${project_name} deployment directory" "Архив каталога развертывания ${project_name}")" \
                    "$(localized_text "Docker Compose 容器、部署目录、配置和本地数据位置" "Docker Compose container, deployment directory, configuration and local data location" "Контейнер Docker Compose, каталог развертывания, конфигурация и расположение локальных данных.")" \
                    "$(localized_text "从 /opt/.vps-optimize-quarantine 手动移回原路径后重新启动" "Manually move back to the original path from /opt/.vps-optimize-quarantine and then restart" "Вручную вернитесь к исходному пути из /opt/.vps-optimize-quarantine, а затем перезапустите.")" \
                    "$(localized_text "确认已经备份数据库和配置，且服务可以中断。" "Confirm that the database and configuration have been backed up and that service can be interrupted." "Убедитесь, что резервная копия базы данных и конфигурации выполнена и что обслуживание можно прервать.")"; then
                    if ! is_managed_compose_dir "$project_dir"; then
                        echo -e "$(localized_text "${RED}❌ 安全检查未通过，拒绝归档非脚本托管目录：${project_dir}${PLAIN}" "${RED}❌ The security check failed and the archive of the non-script hosting directory was refused: ${project_dir}${PLAIN}" "${RED}❌ Проверка безопасности не удалась, и в архиве каталога хостинга без скриптов было отказано: ${project_dir}${PLAIN}")"
                    else
                        ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }
                        (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down -v)
                        if quarantine_path "$project_dir" "/opt/.vps-optimize-quarantine"; then
                            echo -e "$(localized_text "${GREEN}✅ 已归档 ${project_name} 部署目录。${PLAIN}" "${GREEN}✅ Archived ${project_name} deployment directory.${PLAIN}" "${GREEN}✅ Архивированный каталог развертывания ${project_name}.${PLAIN}")"
                        else
                            echo -e "$(localized_text "${RED}❌ 归档失败，请手动检查目录：${project_dir}${PLAIN}" "${RED}❌ Archiving failed, please check the directory manually: ${project_dir}${PLAIN}" "${RED}❌ Не удалось архивировать, проверьте каталог вручную: ${project_dir}.${PLAIN}")"
                        fi
                    fi
                else
                    echo -e "$(localized_text "${BLUE}已取消归档。${PLAIN}" "${BLUE}Has been unarchived.${PLAIN}" "${BLUE}разархивирован.${PLAIN}")"
                fi
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                ;;
            0|q|Q) return ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}
