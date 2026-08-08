# shellcheck shell=bash
# Docker exposure audit, managed project status, and Docker safety workflows.

docker_port_line_is_public() {
    local line="$1"
    case "$line" in
        *"0.0.0.0:"*|*":::"*|*"[::]:"*|*"[0:0:0:0:0:0:0:0]:"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_managed_container_status() {
    local title="$1"
    local container="$2"
    local dir="$3"
    local state health ports compose_file

    if docker inspect "$container" >/dev/null 2>&1; then
        state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container" 2>/dev/null || true)
        ports=$(docker port "$container" 2>/dev/null | tr '\n' '; ')
        [[ -z "$ports" ]] && ports="$(localized_text "未暴露 Docker 端口或使用 host 网络" "The Docker port is not exposed or the host network is used" "Порт Docker не открыт или используется хост-сеть.")"
        [[ -z "$health" ]] && health="$(localized_text "无 healthcheck" "No healthcheck" "Нет проверки здоровья")"
        echo -e "${GREEN}${title}${PLAIN}: ${state} / ${health}"
        echo -e "$(localized_text "  端口: ${ports}" "Port: ${ports}" "Порт: ${ports}")"
    else
        echo -e "$(localized_text "${YELLOW}${title}${PLAIN}: 未检测到容器 ${container}" "${YELLOW}${title}${PLAIN}: Container ${container} not detected" "${YELLOW}${title}${PLAIN}: Контейнер ${container} не обнаружен")"
    fi

    compose_file=$(find_compose_file "$dir" 2>/dev/null || true)
    if [[ -n "$compose_file" ]]; then
        echo -e "  Compose: ${CYAN}${compose_file}${PLAIN}"
    else
        echo -e "$(localized_text "  Compose: ${BLUE}未检测到 ${dir} 部署目录${PLAIN}" "Compose: ${BLUE}Not detected ${dir} deployment directory${PLAIN}" "Compose: ${BLUE}не обнаружен Каталог развертывания ${dir}${PLAIN}")"
    fi
}

print_subscription_compose_status() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}未安装 Docker，跳过订阅工具容器状态。${PLAIN}" "${YELLOW}Is not installed. Docker skips the subscription tool container status.${PLAIN}" "${YELLOW}не установлен. Docker пропускает состояние контейнера средства подписки.${PLAIN}")"
        return 0
    fi
    print_managed_container_status "SublinkPro" "sublinkpro" "/opt/sublinkpro"
    print_managed_container_status "$(localized_text "妙妙屋订阅管理" "Miaomiaowu Subscription Management" "Управление подпиской Miaomiaowu")" "miaomiaowu" "/opt/miaomiaowu"
    print_managed_container_status "Sub-Store" "sub-store" "/opt/sub-store"
    print_managed_container_status "Dockge" "dockge" "/opt/dockge"
    print_managed_container_status "Komari" "komari" "/opt/komari"
}

func_docker_project_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "Docker 安全管理 > 项目容器状态" "Docker Security Management > Project Container Status" "Docker Управление безопасностью > Статус контейнера проекта")"
    echo -e "$(localized_text "${BOLD}🐳 443 / 订阅工具相关容器状态${PLAIN}" "${BOLD}🐳 443 / Subscription tool related container status${PLAIN}" "${BOLD}🐳 443 / Статус контейнера, связанного с инструментом подписки${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}这里只看本项目场景相关容器：SublinkPro、妙妙屋、Sub-Store、Dockge、Komari。${PLAIN}" "${YELLOW}Here we only look at the containers related to this project scenario: SublinkPro, Miaomiaowu, Sub-Store, Dockge, Komari.${PLAIN}" "${YELLOW}Здесь мы рассматриваем только контейнеры, относящиеся к этому сценарию проекта: SublinkPro, Miaomiaowu, Sub-Store, Dockge, Komari.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}3x-ui、Caddy、Nginx 通常是 systemd 服务，状态请看 [15] 或 [19] 体检。${PLAIN}" "${YELLOW}3x-ui, Caddy, Nginx are usually systemd services, please see [15] or [19] for health check status.${PLAIN}" "${YELLOW}3x-ui, Caddy, Nginx обычно представляют собой услуги systemd, информацию о статусе медицинского осмотра см. в [15] или [19].${PLAIN}")"
    echo -e "------------------------------------------------"
    print_subscription_compose_status
    echo -e "------------------------------------------------"
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_docker_443_exposure_audit() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "Docker 安全管理 > 443 暴露审计" "Docker Security Management > 443 Exposure Audit" "Docker Управление безопасностью > 443 Аудит воздействия")"
    echo -e "$(localized_text "${BOLD}🔎 Docker 端口暴露审计${PLAIN}" "${BOLD}🔎 Docker Port exposure audit${PLAIN}" "${BOLD}🔎 Docker Аудит воздействия порта${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}目标：启用 443 单入口后，订阅工具和管理面板应尽量只绑定 127.0.0.1，再由 Caddy/Nginx 对外。${PLAIN}" "${YELLOW}Goal: After enabling the 443 shared entry, the subscription tool and management panel should only be bound to 127.0.0.1, and then Caddy/Nginx should be externalized.${PLAIN}" "${YELLOW}Назначение: после включения общего входа 443 инструмент подписки и панель управления должны быть привязаны только к 127.0.0.1, а затем Caddy/Nginx должны быть экспортированы.${PLAIN}")"
    echo -e "------------------------------------------------"

    local found_public=false
    local line name ports
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        ports=$(docker port "$name" 2>/dev/null || true)
        [[ -z "$ports" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if docker_port_line_is_public "$line"; then
                found_public=true
                echo -e "${YELLOW}⚠️ ${name}: ${line}${PLAIN}"
            fi
        done <<< "$ports"
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)

    if $found_public; then
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${YELLOW}建议：订阅工具、Dockge、Komari 用 127.0.0.1 绑定，公网访问走 [19] -> [8] 添加 443 反代域名。${PLAIN}" "${YELLOW}Recommends: Use 127.0.0.1 to bind subscription tools, Dockge, and Komari, and use [19] -> [8] to access the public by adding a 443 reverse proxy domain.${PLAIN}" "${YELLOW}рекомендует: используйте 127.0.0.1 для привязки инструментов подписки, Dockge и Komari, и используйте [19] -> [8] для доступа к публичной сети, добавив доменное имя обратного прокси 443.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}如确实需要公网直连，请确认云安全组、系统防火墙和访问密码都已收紧。${PLAIN}" "${YELLOW}If you really need to connect directly to the public, please confirm that the cloud security group, system firewall and access password have been tightened.${PLAIN}" "${YELLOW}Если вам действительно необходимо подключиться напрямую к публичной сети, убедитесь, что группа безопасности облака, системный брандмауэр и пароль доступа ужесточены.${PLAIN}")"
    else
        echo -e "$(localized_text "${GREEN}✅ 未发现 Docker 容器通过 0.0.0.0 / :: 直接暴露端口。${PLAIN}" "${GREEN}✅ No direct exposed ports found for the Docker container via 0.0.0.0/::.${PLAIN}" "${GREEN}для контейнера Docker через 0.0.0.0/:: не обнаружено прямых открытых портов.${PLAIN}")"
    fi

    echo -e "------------------------------------------------"
    print_subscription_compose_status
    echo -e "------------------------------------------------"
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_docker_manage() {
    if declare -F ensure_docker_engine_ready >/dev/null 2>&1; then
        ensure_docker_engine_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }
    elif ! command -v docker >/dev/null 2>&1; then
        clear
        echo -e "$(localized_text "${RED}❌ 未检测到 Docker 引擎，且当前运行环境缺少自动安装组件。${PLAIN}" "${RED}❌ The Docker engine is not detected, and the current running environment lacks automatic installation components.${PLAIN}" "${RED}❌ Модуль Docker не обнаружен, а в текущей рабочей среде отсутствуют компоненты автоматической установки.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    
    # 确保依赖工具存在 (使用我们抽象的 install_pkg)
    if ! command -v jq >/dev/null 2>&1; then install_pkg jq; fi

    while true; do
        clear
        local docker_ver
        docker_ver=$(docker -v | awk '{print $3}' | tr -d ',')
        
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "Docker 安全管理" "Docker Security Management" "Docker Управление безопасностью")"
        echo -e "$(localized_text "${BOLD}🐳 Docker 安全管理 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}" "${BOLD}🐳 Docker Security Management (Version: ${docker_ver})${PLAIN}" "${BOLD}🐳 Docker Управление безопасностью (Версия: ${docker_ver})${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${GREEN}  1. 查看 443 / 订阅工具容器状态${PLAIN}" "${GREEN}1. View 443 / Subscription tool container status${PLAIN}" "${GREEN}1. Просмотр 443 / Статус контейнера инструментов подписки${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. Docker 端口暴露审计${PLAIN} ${YELLOW}(检查是否绕过 443 单入口)${PLAIN}" "${GREEN}2. Docker Port exposure audit   (check whether the 443 shared entry is bypassed)${PLAIN}" "${GREEN}2. Docker Аудит воздействия порта   (проверьте, не обходит ли общая запись 443)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 开启 Docker 本地防穿透${PLAIN} ${YELLOW}(限制映射端口仅 127.0.0.1 访问)${PLAIN}" "${GREEN}3. Enable Docker local exposure protection (limit mapped port access to only 127.0.0.1)${PLAIN}" "${GREEN}3. Включить локальную защиту от проникновения Docker (ограничить доступ к сопоставленному порту только 127.0.0.1)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 解除 Docker 本地防穿透${PLAIN} ${YELLOW}(恢复全网可访，不破坏原配置)${PLAIN}" "${GREEN}4. Release Docker local exposure protection (restore full network accessibility without destroying the original configuration)${PLAIN}" "${GREEN}4. Выпуск Docker локальной защиты от проникновения (восстановление полной доступности сети без разрушения исходной конфигурации)${PLAIN}")"
        echo -e "$(localized_text "${BOLD}${YELLOW}  5. UPD 更新订阅工具容器${PLAIN} ${CYAN}(SublinkPro / 妙妙屋 / Sub-Store)${PLAIN}" "${BOLD}5. UPD update subscription tool container (SublinkPro / Miaomiaowu / Sub-Store)${PLAIN}" "${BOLD}5. Контейнер инструментов подписки на обновление UPD (SublinkPro / Miaomiaowu / Sub-Store)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        
        local c
        read_trimmed c "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
        case $c in
            1) func_docker_project_status ;;
            2) func_docker_443_exposure_audit ;;
            3)
                confirm_risk_action "$(localized_text "开启 Docker 本地防穿透" "Enable Docker local exposure protection" "Включить локальную защиту от проникновения Docker")" \
                    "$(localized_text "Docker daemon.json 和 Docker 服务重启" "Docker daemon.json and Docker services restart" "Демон Docker. Службы json и Docker перезапускаются.")" \
                    "$(localized_text "使用自动备份的 daemon.json 恢复并重启 Docker" "Use the automatically backed up daemon.json to restore and restart Docker" "Используйте автоматически резервный демон.json для восстановления и перезапуска Docker.")" \
                    "$(localized_text "确认现有容器不依赖公网直连映射端口。" "Confirm that existing containers do not rely on public direct mapping ports." "Убедитесь, что существующие контейнеры не используют порты прямого сопоставления публичной сети.")" || { echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"; sleep 1; continue; }
                echo -e "$(localized_text "${CYAN}▶ 正在配置 Docker 安全策略...${PLAIN}" "${CYAN}▶ Configuring Docker security policy...${PLAIN}" "${CYAN}▶ Настройка политики безопасности Docker...${PLAIN}")"
                mkdir -p /etc/docker
                local conf_file="/etc/docker/daemon.json"
                local backup_file="${conf_file}.bak_$(date +%s)"
                local tmp_json
                tmp_json=$(mktemp /tmp/docker-daemon.XXXXXX) || { echo -e "$(localized_text "${RED}❌ 临时文件创建失败，已取消操作。${PLAIN}" "${RED}❌ Temporary file creation failed and the operation has been cancelled.${PLAIN}" "${RED}❌ Не удалось создать временный файл, операция была отменена.${PLAIN}")"; sleep 1; continue; }
                
                # 检查并备份
                if [[ -f "$conf_file" ]]; then
                    if ! cp -p "$conf_file" "$backup_file"; then
                        echo -e "$(localized_text "${RED}❌ Docker 配置备份失败，已取消操作。${PLAIN}" "${RED}❌ Docker Configuration backup failed and the operation has been cancelled.${PLAIN}" "${RED}❌ Docker Не удалось выполнить резервное копирование конфигурации, и операция была отменена.${PLAIN}")"
                        rm -f "$tmp_json"
                        sleep 1
                        continue
                    fi
                    echo -e "$(localized_text "${YELLOW}⚠️ 已备份原有配置至 $backup_file${PLAIN}" "${YELLOW}⚠️ The original configuration has been backed up to $backup_file${PLAIN}" "${YELLOW}⚠️ Исходная конфигурация сохранена в $backup_file.${PLAIN}")"
                    
                    # 使用 jq 进行非破坏性合并，保留用户原有配置
                    if ! jq '. + {"ip": "127.0.0.1", "log-driver": "json-file", "log-opts": {"max-size": "50m", "max-file": "3"}}' "$conf_file" > "$tmp_json" 2>/dev/null; then
                        echo -e "$(localized_text "${RED}❌ 原 daemon.json 格式损坏，合并失败！操作中止。${PLAIN}" "${RED}❌ The original daemon.json format is damaged and the merge failed! Operation aborted.${PLAIN}" "${RED}❌ Исходный формат daemon.json поврежден, и слияние не удалось! Операция прервана.${PLAIN}")"
                        rm -f "$tmp_json"
                        echo -e "$(localized_text "${YELLOW}备份已保留：$backup_file${PLAIN}" "${YELLOW}Backup has been retained: $backup_file${PLAIN}" "${YELLOW}Резервная копия сохранена: $backup_file.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    fi
                    mv "$tmp_json" "$conf_file"
                else
                    # 文件不存在时初始生成
                    cat <<EOF > "$conf_file"
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
                fi
                
                # 防宕机重启机制：如果新配置导致引擎崩溃，立刻回滚！
                if systemctl restart docker >/dev/null 2>&1; then
                    echo -e "$(localized_text "${GREEN}✅ 已开启安全保护，Docker 容器端口仅限本地反代访问！${PLAIN}" "${GREEN}✅ Security protection has been turned on, and the Docker container port is only accessible to local reverse proxy!${PLAIN}" "${GREEN}✅ Защита безопасности включена, а порт контейнера Docker доступен только через локальный обратный прокси!${PLAIN}")"
                    [[ -f "$backup_file" ]] && echo -e "$(localized_text "${CYAN}Docker 配置备份已保留：$backup_file${PLAIN}" "${CYAN}Docker Configuration backup has been retained: $backup_file${PLAIN}" "${CYAN}Docker Резервная копия конфигурации сохранена: $backup_file${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ 致命错误：新配置导致 Docker 引擎无法启动！正在自动回滚...${PLAIN}" "${RED}❌ Fatal error: New configuration causes Docker engine to fail to start! Automatically rolling back...${PLAIN}" "${RED}❌ Неустранимая ошибка: новая конфигурация приводит к тому, что двигатель Docker не запускается! Автоматический откат...${PLAIN}")"
                    if [[ -f "$backup_file" ]]; then
                        mv "$backup_file" "$conf_file"
                    else
                        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/docker" >/dev/null 2>&1 || true
                    fi
                    systemctl restart docker >/dev/null 2>&1
                fi
                sleep 2
                ;;
            4)
                local conf_file="/etc/docker/daemon.json"
                if [[ -f "$conf_file" ]]; then
                    confirm_risk_action "$(localized_text "解除 Docker 本地防穿透" "Release Docker local exposure protection" "Выпуск локальной защиты от проникновения Docker")" \
                        "$(localized_text "Docker daemon.json 和 Docker 服务重启" "Docker daemon.json and Docker services restart" "Демон Docker. Службы json и Docker перезапускаются.")" \
                        "$(localized_text "使用自动备份的 daemon.json 恢复并重启 Docker" "Use the automatically backed up daemon.json to restore and restart Docker" "Используйте автоматически резервный демон.json для восстановления и перезапуска Docker.")" \
                        "$(localized_text "解除后容器映射端口可能重新公网可达，请确认防火墙和云安全组。" "After being released, the container mapping port may be reachable from the public again. Please confirm the firewall and cloud security group." "После освобождения порт сопоставления контейнера снова может быть доступен из публичной сети. Пожалуйста, подтвердите брандмауэр и группу безопасности облака.")" || { echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"; sleep 1; continue; }
                    echo -e "$(localized_text "${CYAN}▶ 正在安全移除 Docker 端口限制...${PLAIN}" "${CYAN}▶ Safely removing Docker port restriction...${PLAIN}" "${CYAN}▶ Безопасное снятие ограничения порта Docker...${PLAIN}")"
                    local backup_file="${conf_file}.bak_$(date +%s)"
                    local tmp_json
                    tmp_json=$(mktemp /tmp/docker-daemon.XXXXXX) || { echo -e "$(localized_text "${RED}❌ 临时文件创建失败，已取消操作。${PLAIN}" "${RED}❌ Temporary file creation failed and the operation has been cancelled.${PLAIN}" "${RED}❌ Не удалось создать временный файл, операция была отменена.${PLAIN}")"; sleep 1; continue; }
                    if ! cp -p "$conf_file" "$backup_file"; then
                        echo -e "$(localized_text "${RED}❌ Docker 配置备份失败，已取消操作。${PLAIN}" "${RED}❌ Docker Configuration backup failed and the operation has been cancelled.${PLAIN}" "${RED}❌ Docker Не удалось выполнить резервное копирование конфигурации, и операция была отменена.${PLAIN}")"
                        rm -f "$tmp_json"
                        sleep 1
                        continue
                    fi

                    # 核心修复：只精准删除 ip 限制，绝不误删国内镜像源等其他配置！
                    if ! jq 'del(.ip)' "$conf_file" > "$tmp_json" 2>/dev/null; then
                        echo -e "$(localized_text "${RED}❌ JSON 解析失败，操作中止。${PLAIN}" "${RED}❌ JSON Parsing failed and the operation was aborted.${PLAIN}" "${RED}❌ JSON Не удалось выполнить синтаксический анализ, и операция была прервана.${PLAIN}")"
                        rm -f "$tmp_json"
                        echo -e "$(localized_text "${YELLOW}备份已保留：$backup_file${PLAIN}" "${YELLOW}Backup has been retained: $backup_file${PLAIN}" "${YELLOW}Резервная копия сохранена: $backup_file.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    fi
                    mv "$tmp_json" "$conf_file"

                    if systemctl restart docker >/dev/null 2>&1; then
                        echo -e "$(localized_text "${GREEN}✅ 已解除限制，容器端口恢复公网可访状态！${PLAIN}" "${GREEN}✅ The restriction has been lifted and the container port is restored to the public accessible state!${PLAIN}" "${GREEN}✅ Ограничение снято и контейнерный порт восстановлен до состояния доступности публичной сети!${PLAIN}")"
                        echo -e "$(localized_text "${CYAN}Docker 配置备份已保留：$backup_file${PLAIN}" "${CYAN}Docker Configuration backup has been retained: $backup_file${PLAIN}" "${CYAN}Docker Резервная копия конфигурации сохранена: $backup_file${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ 卸载异常：导致引擎无法启动！正在回滚...${PLAIN}" "${RED}❌ Unloading exception: causing the engine to fail to start! Rolling back...${PLAIN}" "${RED}❌ Исключение при разгрузке: двигатель не запускается! Откат...${PLAIN}")"
                        mv "$backup_file" "$conf_file"
                        systemctl restart docker >/dev/null 2>&1
                    fi
                else
                    echo -e "$(localized_text "${BLUE}未检测到限制配置文件，当前已是全网开放状态。${PLAIN}" "${BLUE}No restricted configuration file was detected, and the entire network is currently open.${PLAIN}" "${BLUE}Файл конфигурации с ограниченным доступом не обнаружен, и вся сеть в настоящее время открыта.${PLAIN}")"
                fi
                sleep 2
                ;;
            5) func_update_subscription_tools ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效的输入！${PLAIN}" "${RED}❌ Invalid input!${PLAIN}" "${RED}❌ Неверный ввод!${PLAIN}")"; sleep 1 ;;
        esac
    done
}
# ---------------------------------------------------------
# 6. BBR 增强管理
# ---------------------------------------------------------
