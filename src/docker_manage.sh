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
    print_breadcrumb "$(localized_text "Docker 管理 > 项目容器状态" "Docker Management > Project Container Status" "Docker > Статус контейнеров проекта")"
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
    print_breadcrumb "$(localized_text "Docker 管理 > 443 暴露审计" "Docker Management > 443 Exposure Audit" "Docker > Аудит публикации порта 443")"
    echo -e "$(localized_text "${BOLD}🔎 Docker 端口暴露审计${PLAIN}" "${BOLD}🔎 Docker Port exposure audit${PLAIN}" "${BOLD}🔎 Docker Аудит воздействия порта${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}目标：启用 443端口复用后，订阅工具和管理面板应尽量只绑定 127.0.0.1，再由 Caddy/Nginx 对外。${PLAIN}" "${YELLOW}Goal: After enabling the Port 443 Reuse, the subscription tool and management panel should only be bound to 127.0.0.1, and then Caddy/Nginx should be externalized.${PLAIN}" "${YELLOW}Назначение: после включения повторного использования порта 443 инструмент подписки и панель управления должны быть привязаны только к 127.0.0.1, а затем Caddy/Nginx должны быть экспортированы.${PLAIN}")"
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

docker_manage_pause() {
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

docker_require_running() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}Docker 未安装，请先选择 [1]。${PLAIN}" "${YELLOW}Docker is not installed. Select [1] first.${PLAIN}" "${YELLOW}Docker не установлен. Сначала выберите [1].${PLAIN}")"
        return 1
    fi
    if docker info >/dev/null 2>&1; then
        return 0
    fi
    systemctl start docker >/dev/null 2>&1 || true
    if ! docker info >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}Docker 服务不可用，请检查 systemctl status docker。${PLAIN}" "${RED}Docker is unavailable. Check systemctl status docker.${PLAIN}" "${RED}Docker недоступен. Проверьте systemctl status docker.${PLAIN}")"
        return 1
    fi
}

docker_install_or_update() {
    if ! command -v docker >/dev/null 2>&1; then
        ensure_docker_compose_ready
        return
    fi

    local -a packages=()
    local pkg manager=""
    if command -v apt-get >/dev/null 2>&1; then
        manager="apt"
        for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker.io docker-compose-v2; do
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' && packages+=("$pkg")
        done
        if [[ ${#packages[@]} -gt 0 ]]; then
            apt-get update && apt-get install --only-upgrade -y "${packages[@]}"
        fi
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        manager=$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)
        for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; do
            rpm -q "$pkg" >/dev/null 2>&1 && packages+=("$pkg")
        done
        [[ ${#packages[@]} -gt 0 ]] && "$manager" upgrade -y "${packages[@]}"
    elif command -v apk >/dev/null 2>&1; then
        manager="apk"
        for pkg in docker docker-cli-compose; do
            apk info -e "$pkg" >/dev/null 2>&1 && packages+=("$pkg")
        done
        [[ ${#packages[@]} -gt 0 ]] && apk upgrade "${packages[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        manager="pacman"
        for pkg in docker docker-compose; do
            pacman -Q "$pkg" >/dev/null 2>&1 && packages+=("$pkg")
        done
        [[ ${#packages[@]} -gt 0 ]] && pacman -Syu --noconfirm "${packages[@]}"
    fi

    if [[ -z "$manager" || ${#packages[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未识别到包管理器安装记录，未自动覆盖当前 Docker。${PLAIN}" "${YELLOW}No package-managed Docker installation was found; the current installation was not overwritten.${PLAIN}" "${YELLOW}Установка Docker через менеджер пакетов не найдена; текущая установка не перезаписана.${PLAIN}")"
    fi
    ensure_docker_compose_ready || return 1
    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
}

docker_global_status() {
    docker_require_running || return
    local total running images networks volumes
    total=$(docker ps -aq | wc -l | tr -d ' ')
    running=$(docker ps -q | wc -l | tr -d ' ')
    images=$(docker image ls -q | sort -u | wc -l | tr -d ' ')
    networks=$(docker network ls -q | wc -l | tr -d ' ')
    volumes=$(docker volume ls -q | wc -l | tr -d ' ')
    echo -e "$(localized_text "${BOLD}Docker 全局状态${PLAIN}" "${BOLD}Docker overview${PLAIN}" "${BOLD}Обзор Docker${PLAIN}")"
    echo -e "$(localized_text "版本" "Version" "Версия"): $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    echo -e "$(localized_text "容器" "Containers" "Контейнеры"): ${running}/${total}  |  $(localized_text "镜像" "Images" "Образы"): ${images}  |  $(localized_text "网络" "Networks" "Сети"): ${networks}  |  $(localized_text "卷" "Volumes" "Тома"): ${volumes}"
    echo "------------------------------------------------"
    docker system df
    echo "------------------------------------------------"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

docker_container_manage() {
    docker_require_running || return
    local choice target
    while true; do
        clear
        print_breadcrumb "$(localized_text "Docker 管理 > 容器" "Docker Management > Containers" "Docker > Контейнеры")"
        docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
        echo "------------------------------------------------"
        echo -e "${GREEN}  1. $(localized_text "启动" "Start" "Запустить")${PLAIN}"
        echo -e "${GREEN}  2. $(localized_text "停止" "Stop" "Остановить")${PLAIN}"
        echo -e "${GREEN}  3. $(localized_text "重启" "Restart" "Перезапустить")${PLAIN}"
        echo -e "${GREEN}  4. $(localized_text "查看日志" "View logs" "Журнал")${PLAIN}"
        echo -e "${GREEN}  5. $(localized_text "进入容器" "Open shell" "Открыть shell")${PLAIN}"
        echo -e "${RED}  6. $(localized_text "删除容器" "Remove container" "Удалить контейнер")${PLAIN}"
        echo -e "${RED}  0. $(localized_text "返回" "Back" "Назад")${PLAIN}"
        read_trimmed choice "$(localized_text "请选择: " "Select: " "Выберите: ")"
        [[ "$choice" == "0" ]] && return
        read_trimmed target "$(localized_text "容器名称: " "Container name: " "Имя контейнера: ")"
        docker inspect "$target" >/dev/null 2>&1 || { echo -e "${RED}$(localized_text "容器不存在。" "Container not found." "Контейнер не найден.")${PLAIN}"; sleep 1; continue; }
        case "$choice" in
            1) docker start "$target" ;;
            2) docker stop "$target" ;;
            3) docker restart "$target" ;;
            4) echo -e "${YELLOW}Ctrl+C $(localized_text "返回" "to return" "для возврата")${PLAIN}"; docker logs --tail 200 -f "$target" ;;
            5) docker exec -it "$target" sh -lc 'if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi' ;;
            6) confirm_risk_action "$(localized_text "删除容器 ${target}" "Remove container ${target}" "Удалить контейнер ${target}")" "$(localized_text "容器会停止并删除" "The container will be stopped and removed" "Контейнер будет остановлен и удален")" "$(localized_text "可用原 Compose 配置重新创建" "Recreate it from the original Compose configuration" "Повторно создайте из исходной конфигурации Compose")" || continue; docker rm -f "$target" ;;
            *) echo -e "${RED}$(localized_text "无效选择。" "Invalid choice." "Неверный выбор.")${PLAIN}" ;;
        esac
        docker_manage_pause
    done
}

docker_image_manage() {
    docker_require_running || return
    local choice target
    while true; do
        clear
        print_breadcrumb "$(localized_text "Docker 管理 > 镜像" "Docker Management > Images" "Docker > Образы")"
        docker image ls
        echo "------------------------------------------------"
        echo -e "${GREEN}  1. $(localized_text "拉取 / 更新镜像" "Pull / update image" "Загрузить / обновить образ")${PLAIN}"
        echo -e "${RED}  2. $(localized_text "删除镜像" "Remove image" "Удалить образ")${PLAIN}"
        echo -e "${RED}  3. $(localized_text "清理未使用镜像" "Prune unused images" "Очистить неиспользуемые образы")${PLAIN}"
        echo -e "${RED}  0. $(localized_text "返回" "Back" "Назад")${PLAIN}"
        read_trimmed choice "$(localized_text "请选择: " "Select: " "Выберите: ")"
        case "$choice" in
            0) return ;;
            1) read_trimmed target "$(localized_text "镜像名称: " "Image name: " "Имя образа: ")"; [[ -n "$target" ]] && docker pull "$target" ;;
            2) read_trimmed target "$(localized_text "镜像 ID 或名称: " "Image ID or name: " "ID или имя образа: ")"; confirm_risk_action "$(localized_text "删除镜像 ${target}" "Remove image ${target}" "Удалить образ ${target}")" "$(localized_text "依赖该镜像的新容器无法创建" "New containers depending on it cannot be created" "Новые контейнеры на его основе не будут созданы")" "$(localized_text "可重新拉取镜像" "Pull the image again" "Повторно загрузите образ")" || continue; docker image rm "$target" ;;
            3) confirm_risk_action "$(localized_text "清理未使用镜像" "Prune unused images" "Очистить неиспользуемые образы")" "$(localized_text "删除未被容器使用的镜像" "Remove images unused by containers" "Удалить образы, не используемые контейнерами")" "$(localized_text "需要时重新拉取" "Pull them again when needed" "Загрузите их снова при необходимости")" || continue; docker image prune -af ;;
            *) echo -e "${RED}$(localized_text "无效选择。" "Invalid choice." "Неверный выбор.")${PLAIN}" ;;
        esac
        docker_manage_pause
    done
}

docker_network_manage() {
    docker_require_running || return
    local choice network container
    while true; do
        clear
        print_breadcrumb "$(localized_text "Docker 管理 > 网络" "Docker Management > Networks" "Docker > Сети")"
        docker network ls
        echo "------------------------------------------------"
        echo -e "${GREEN}  1. $(localized_text "查看网络详情" "Inspect network" "Сведения о сети")${PLAIN}"
        echo -e "${GREEN}  2. $(localized_text "创建网络" "Create network" "Создать сеть")${PLAIN}"
        echo -e "${GREEN}  3. $(localized_text "连接容器" "Connect container" "Подключить контейнер")${PLAIN}"
        echo -e "${GREEN}  4. $(localized_text "断开容器" "Disconnect container" "Отключить контейнер")${PLAIN}"
        echo -e "${RED}  5. $(localized_text "删除网络" "Remove network" "Удалить сеть")${PLAIN}"
        echo -e "${RED}  0. $(localized_text "返回" "Back" "Назад")${PLAIN}"
        read_trimmed choice "$(localized_text "请选择: " "Select: " "Выберите: ")"
        [[ "$choice" == "0" ]] && return
        read_trimmed network "$(localized_text "网络名称: " "Network name: " "Имя сети: ")"
        case "$choice" in
            1) docker network inspect "$network" ;;
            2) docker network create "$network" ;;
            3) read_trimmed container "$(localized_text "容器名称: " "Container name: " "Имя контейнера: ")"; docker network connect "$network" "$container" ;;
            4) read_trimmed container "$(localized_text "容器名称: " "Container name: " "Имя контейнера: ")"; docker network disconnect "$network" "$container" ;;
            5) confirm_risk_action "$(localized_text "删除网络 ${network}" "Remove network ${network}" "Удалить сеть ${network}")" "$(localized_text "使用中的网络不能删除" "Networks in use cannot be removed" "Используемую сеть удалить нельзя")" "$(localized_text "可按原名称重新创建" "Recreate it with the same name" "Создайте ее снова с тем же именем")" || continue; docker network rm "$network" ;;
            *) echo -e "${RED}$(localized_text "无效选择。" "Invalid choice." "Неверный выбор.")${PLAIN}" ;;
        esac
        docker_manage_pause
    done
}

docker_volume_manage() {
    docker_require_running || return
    local choice volume
    while true; do
        clear
        print_breadcrumb "$(localized_text "Docker 管理 > 数据卷" "Docker Management > Volumes" "Docker > Тома")"
        docker volume ls
        echo "------------------------------------------------"
        echo -e "${GREEN}  1. $(localized_text "查看卷详情" "Inspect volume" "Сведения о томе")${PLAIN}"
        echo -e "${GREEN}  2. $(localized_text "创建卷" "Create volume" "Создать том")${PLAIN}"
        echo -e "${RED}  3. $(localized_text "删除卷" "Remove volume" "Удалить том")${PLAIN}"
        echo -e "${RED}  4. $(localized_text "清理未使用卷" "Prune unused volumes" "Очистить неиспользуемые тома")${PLAIN}"
        echo -e "${RED}  0. $(localized_text "返回" "Back" "Назад")${PLAIN}"
        read_trimmed choice "$(localized_text "请选择: " "Select: " "Выберите: ")"
        case "$choice" in
            0) return ;;
            1) read_trimmed volume "$(localized_text "卷名称: " "Volume name: " "Имя тома: ")"; docker volume inspect "$volume" ;;
            2) read_trimmed volume "$(localized_text "卷名称: " "Volume name: " "Имя тома: ")"; docker volume create "$volume" ;;
            3) read_trimmed volume "$(localized_text "卷名称: " "Volume name: " "Имя тома: ")"; confirm_risk_action "$(localized_text "删除数据卷 ${volume}" "Remove volume ${volume}" "Удалить том ${volume}")" "$(localized_text "卷内数据会永久删除" "Data in the volume will be permanently removed" "Данные тома будут удалены безвозвратно")" "$(localized_text "请先完成数据备份" "Back up the data first" "Сначала создайте резервную копию")" || continue; docker volume rm "$volume" ;;
            4) confirm_risk_action "$(localized_text "清理未使用数据卷" "Prune unused volumes" "Очистить неиспользуемые тома")" "$(localized_text "未挂载卷内的数据会永久删除" "Data in unused volumes will be permanently removed" "Данные неиспользуемых томов будут удалены")" "$(localized_text "请先完成数据备份" "Back up the data first" "Сначала создайте резервную копию")" || continue; docker volume prune -af ;;
            *) echo -e "${RED}$(localized_text "无效选择。" "Invalid choice." "Неверный выбор.")${PLAIN}" ;;
        esac
        docker_manage_pause
    done
}

docker_prune_unused() {
    docker_require_running || return
    docker system df
    confirm_risk_action "$(localized_text "清理 Docker 未使用资源" "Prune unused Docker resources" "Очистить неиспользуемые ресурсы Docker")" "$(localized_text "删除已停止容器、未使用镜像、网络、卷和构建缓存" "Remove stopped containers, unused images, networks, volumes and build cache" "Удалить остановленные контейнеры, образы, сети, тома и кэш сборки")" "$(localized_text "重要数据卷请先备份" "Back up important volumes first" "Сначала создайте резервную копию важных томов")" || return
    docker system prune -af --volumes
}

docker_daemon_apply_jq() {
    local label="$1"
    shift
    local conf_file="/etc/docker/daemon.json" source_file tmp_file backup_file=""
    command -v jq >/dev/null 2>&1 || install_pkg jq || return 1
    mkdir -p /etc/docker || return 1
    source_file=$(mktemp /tmp/docker-daemon-source.XXXXXX) || return 1
    tmp_file=$(mktemp /tmp/docker-daemon-new.XXXXXX) || { rm -f "$source_file"; return 1; }
    if [[ -f "$conf_file" ]]; then
        cp -p "$conf_file" "$source_file" || { rm -f "$source_file" "$tmp_file"; return 1; }
        backup_file="${conf_file}.bak_$(date +%s)"
        cp -p "$conf_file" "$backup_file" || { rm -f "$source_file" "$tmp_file"; return 1; }
    else
        printf '{}\n' > "$source_file"
    fi
    if ! jq "$@" "$source_file" > "$tmp_file" 2>/dev/null; then
        echo -e "$(localized_text "${RED}daemon.json 格式无效，未修改。${PLAIN}" "${RED}daemon.json is invalid and was not changed.${PLAIN}" "${RED}daemon.json недействителен и не изменен.${PLAIN}")"
        rm -f "$source_file" "$tmp_file"
        return 1
    fi
    install -m 600 "$tmp_file" "$conf_file" || { rm -f "$source_file" "$tmp_file"; return 1; }
    rm -f "$source_file" "$tmp_file"
    if systemctl restart docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ ${label}${PLAIN}"
        [[ -n "$backup_file" ]] && echo -e "$(localized_text "${CYAN}备份：${backup_file}${PLAIN}" "${CYAN}Backup: ${backup_file}${PLAIN}" "${CYAN}Резервная копия: ${backup_file}${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${RED}Docker 重启失败，正在恢复原配置。${PLAIN}" "${RED}Docker failed to restart; restoring the previous configuration.${PLAIN}" "${RED}Не удалось перезапустить Docker; восстанавливается прежняя конфигурация.${PLAIN}")"
    if [[ -n "$backup_file" ]]; then
        cp -p "$backup_file" "$conf_file"
    else
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/docker" >/dev/null 2>&1 || true
    fi
    systemctl restart docker >/dev/null 2>&1 || true
    return 1
}

docker_configure_mirror() {
    docker_require_running || return
    local mirror
    read_trimmed mirror "$(localized_text "镜像源 URL（留空恢复默认）: " "Registry mirror URL (blank restores default): " "URL зеркала (пусто — по умолчанию): ")"
    if [[ -z "$mirror" ]]; then
        docker_daemon_apply_jq "$(localized_text "已恢复默认镜像源。" "Default registry source restored." "Источник реестра по умолчанию восстановлен.")" 'del(.["registry-mirrors"])'
    elif [[ "$mirror" =~ ^https?://[^[:space:]]+$ ]]; then
        docker_daemon_apply_jq "$(localized_text "镜像源已更新。" "Registry mirror updated." "Зеркало реестра обновлено.")" --arg mirror "${mirror%/}" '.["registry-mirrors"] = [$mirror]'
    else
        echo -e "$(localized_text "${RED}请输入有效的 http(s) URL。${PLAIN}" "${RED}Enter a valid http(s) URL.${PLAIN}" "${RED}Введите допустимый URL http(s).${PLAIN}")"
    fi
}

docker_edit_daemon_json() {
    docker_require_running || return
    command -v jq >/dev/null 2>&1 || install_pkg jq || return
    mkdir -p /etc/docker
    [[ -f /etc/docker/daemon.json ]] || printf '{}\n' > /etc/docker/daemon.json
    edit_applied_config_file /etc/docker/daemon.json docker-json "Docker daemon.json"
}

docker_local_protection_state() {
    if [[ -f /etc/docker/daemon.json ]] && command -v jq >/dev/null 2>&1 && [[ "$(jq -r '.ip // ""' /etc/docker/daemon.json 2>/dev/null)" == "127.0.0.1" ]]; then
        localized_text "已开启" "On" "Включено"
    else
        localized_text "未开启" "Off" "Выключено"
    fi
}

docker_toggle_local_protection() {
    docker_require_running || return
    if [[ -f /etc/docker/daemon.json ]] && command -v jq >/dev/null 2>&1 && [[ "$(jq -r '.ip // ""' /etc/docker/daemon.json 2>/dev/null)" == "127.0.0.1" ]]; then
        confirm_risk_action "$(localized_text "关闭 Docker 本地防穿透" "Disable Docker local exposure protection" "Отключить локальную защиту Docker")" "$(localized_text "映射端口可能恢复公网访问" "Mapped ports may become publicly reachable" "Опубликованные порты могут стать общедоступными")" "$(localized_text "确认防火墙与云安全组规则" "Check firewall and cloud security group rules" "Проверьте брандмауэр и облачную группу безопасности")" || return
        docker_daemon_apply_jq "$(localized_text "本地防穿透已关闭。" "Local exposure protection disabled." "Локальная защита отключена.")" 'del(.ip)'
    else
        confirm_risk_action "$(localized_text "开启 Docker 本地防穿透" "Enable Docker local exposure protection" "Включить локальную защиту Docker")" "$(localized_text "Docker 将重启，默认映射地址改为 127.0.0.1" "Docker will restart and default published address becomes 127.0.0.1" "Docker перезапустится; адрес публикации станет 127.0.0.1")" "$(localized_text "可再次进入本项关闭" "Run this option again to disable it" "Запустите этот пункт снова для отключения")" || return
        docker_daemon_apply_jq "$(localized_text "本地防穿透已开启。" "Local exposure protection enabled." "Локальная защита включена.")" '.ip = "127.0.0.1" | .["log-driver"] = "json-file" | .["log-opts"] = ((.["log-opts"] // {}) + {"max-size":"50m","max-file":"3"})'
    fi
}

docker_enable_ipv6() {
    docker_require_running || return
    local cidr
    cidr=$(ask_with_default "$(localized_text "Docker IPv6 网段" "Docker IPv6 subnet" "Подсеть Docker IPv6")" "fd00:dead:beef::/64")
    is_valid_ipv6_cidr "$cidr" || { echo -e "${RED}$(localized_text "IPv6 网段格式无效。" "Invalid IPv6 subnet." "Недопустимая подсеть IPv6.")${PLAIN}"; return; }
    docker_daemon_apply_jq "$(localized_text "Docker IPv6 已开启。" "Docker IPv6 enabled." "Docker IPv6 включен.")" --arg cidr "$cidr" '. + {"ipv6":true,"fixed-cidr-v6":$cidr}'
}

docker_disable_ipv6() {
    docker_require_running || return
    confirm_risk_action "$(localized_text "关闭 Docker IPv6" "Disable Docker IPv6" "Отключить Docker IPv6")" "$(localized_text "依赖 IPv6 的容器网络会中断" "IPv6-dependent container networks will be interrupted" "Сети контейнеров, зависящие от IPv6, будут прерваны")" "$(localized_text "可重新开启并使用原网段" "Re-enable it with the previous subnet" "Включите снова с прежней подсетью")" || return
    docker_daemon_apply_jq "$(localized_text "Docker IPv6 已关闭。" "Docker IPv6 disabled." "Docker IPv6 отключен.")" 'del(.ipv6, .["fixed-cidr-v6"])'
}

docker_backup_migration_menu() {
    local choice
    while true; do
        clear
        print_breadcrumb "$(localized_text "Docker 管理 > 备份与迁移" "Docker Management > Backup and Migration" "Docker > Резервное копирование и перенос")"
        echo -e "$(localized_text "${YELLOW}配置备份可还原 daemon.json；不包含镜像和数据卷。${PLAIN}" "${YELLOW}Configuration backups include daemon.json, not images or volumes.${PLAIN}" "${YELLOW}Резервная копия включает daemon.json, но не образы и тома.${PLAIN}")"
        echo -e "${GREEN}  1. $(localized_text "配置备份 / 还原" "Configuration backup / restore" "Резервная копия / восстановление")${PLAIN}"
        echo -e "${GREEN}  2. $(localized_text "迁移 Compose 项目到 Dockge" "Migrate Compose project to Dockge" "Перенести Compose в Dockge")${PLAIN}"
        echo -e "${RED}  0. $(localized_text "返回" "Back" "Назад")${PLAIN}"
        read_trimmed choice "$(localized_text "请选择: " "Select: " "Выберите: ")"
        case "$choice" in
            1) func_backup_center ;;
            2) func_migrate_compose_to_dockge ;;
            0) return ;;
            *) echo -e "${RED}$(localized_text "无效选择。" "Invalid choice." "Неверный выбор.")${PLAIN}"; sleep 1 ;;
        esac
    done
}

docker_uninstall_engine() {
    command -v docker >/dev/null 2>&1 || { echo -e "${YELLOW}$(localized_text "Docker 未安装。" "Docker is not installed." "Docker не установлен.")${PLAIN}"; return; }
    confirm_risk_action "$(localized_text "卸载 Docker 环境" "Uninstall Docker" "Удалить Docker")" "$(localized_text "Docker 服务会停止，软件包会卸载" "Docker will stop and its packages will be removed" "Docker будет остановлен, пакеты будут удалены")" "$(localized_text "容器数据与配置会保留，可重新安装恢复" "Container data and configuration are kept for reinstallation" "Данные и конфигурация сохранятся для переустановки")" || return
    local -a packages=()
    local pkg manager=""
    systemctl disable --now docker docker.socket >/dev/null 2>&1 || true
    if command -v apt-get >/dev/null 2>&1; then
        manager="apt"
        for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker.io docker-compose-v2; do
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' && packages+=("$pkg")
        done
        [[ ${#packages[@]} -gt 0 ]] && apt-get remove -y "${packages[@]}"
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        manager=$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)
        for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; do rpm -q "$pkg" >/dev/null 2>&1 && packages+=("$pkg"); done
        [[ ${#packages[@]} -gt 0 ]] && "$manager" remove -y "${packages[@]}"
    elif command -v apk >/dev/null 2>&1; then
        manager="apk"
        for pkg in docker docker-cli-compose; do apk info -e "$pkg" >/dev/null 2>&1 && packages+=("$pkg"); done
        [[ ${#packages[@]} -gt 0 ]] && apk del "${packages[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        manager="pacman"
        for pkg in docker docker-compose; do pacman -Q "$pkg" >/dev/null 2>&1 && packages+=("$pkg"); done
        [[ ${#packages[@]} -gt 0 ]] && pacman -Rns --noconfirm "${packages[@]}"
    fi
    if [[ -z "$manager" || ${#packages[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未找到可卸载的软件包，请按原安装方式处理。${PLAIN}" "${YELLOW}No removable package was found; use the original installation method.${PLAIN}" "${YELLOW}Удаляемые пакеты не найдены; используйте исходный способ установки.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}Docker 软件包已卸载；/var/lib/docker 与 /etc/docker 已保留。${PLAIN}" "${GREEN}Docker packages removed; /var/lib/docker and /etc/docker were kept.${PLAIN}" "${GREEN}Пакеты Docker удалены; /var/lib/docker и /etc/docker сохранены.${PLAIN}")"
}

func_docker_manage() {
    local choice docker_ver protection_state
    while true; do
        clear
        docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        [[ -z "$docker_ver" ]] && docker_ver="$(localized_text "未安装" "Not installed" "Не установлен")"
        protection_state=$(docker_local_protection_state)
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "Docker 管理" "Docker Management" "Управление Docker")"
        echo -e "$(localized_text "${BOLD}🐳 Docker 管理${PLAIN}  ${CYAN}${docker_ver}${PLAIN}" "${BOLD}🐳 Docker Management${PLAIN}  ${CYAN}${docker_ver}${PLAIN}" "${BOLD}🐳 Управление Docker${PLAIN}  ${CYAN}${docker_ver}${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. $(localized_text "安装 / 更新 Docker" "Install / update Docker" "Установить / обновить Docker")${PLAIN}"
        echo -e "${GREEN}  2. $(localized_text "查看 Docker 全局状态" "View Docker overview" "Обзор Docker")${PLAIN}"
        echo "------------------------------------------------"
        echo -e "${GREEN}  3. $(localized_text "容器管理" "Container management" "Контейнеры")${PLAIN}"
        echo -e "${GREEN}  4. $(localized_text "镜像管理" "Image management" "Образы")${PLAIN}"
        echo -e "${GREEN}  5. $(localized_text "网络管理" "Network management" "Сети")${PLAIN}"
        echo -e "${GREEN}  6. $(localized_text "数据卷管理" "Volume management" "Тома")${PLAIN}"
        echo "------------------------------------------------"
        echo -e "${YELLOW}  7. $(localized_text "清理未使用资源" "Prune unused resources" "Очистить неиспользуемые ресурсы")${PLAIN}"
        echo -e "${GREEN}  8. $(localized_text "配置 Docker 镜像源" "Configure registry mirror" "Настроить зеркало реестра")${PLAIN}"
        echo -e "${GREEN}  9. $(localized_text "编辑 daemon.json" "Edit daemon.json" "Изменить daemon.json")${PLAIN}"
        echo -e "${GREEN} 10. $(localized_text "Docker 本地防穿透" "Docker local exposure protection" "Локальная защита Docker")${PLAIN}  ${CYAN}[${protection_state}]${PLAIN}"
        echo "------------------------------------------------"
        echo -e "${GREEN} 11. $(localized_text "开启 Docker IPv6" "Enable Docker IPv6" "Включить Docker IPv6")${PLAIN}"
        echo -e "${GREEN} 12. $(localized_text "关闭 Docker IPv6" "Disable Docker IPv6" "Отключить Docker IPv6")${PLAIN}"
        echo "------------------------------------------------"
        echo -e "${GREEN} 19. $(localized_text "备份 / 迁移 / 还原 Docker 配置" "Backup / migrate / restore Docker configuration" "Резервное копирование / перенос / восстановление")${PLAIN}"
        echo -e "${RED} 20. $(localized_text "卸载 Docker 环境" "Uninstall Docker" "Удалить Docker")${PLAIN}"
        echo "------------------------------------------------"
        echo -e "${RED}  0. $(localized_text "返回主菜单" "Main menu" "Главное меню") / q $(localized_text "返回" "Back" "Назад")${PLAIN}"
        read_trimmed choice "$(localized_text "请选择: " "Select: " "Выберите: ")"
        case "$choice" in
            1) docker_install_or_update; docker_manage_pause ;;
            2) docker_global_status; docker_manage_pause ;;
            3) docker_container_manage ;;
            4) docker_image_manage ;;
            5) docker_network_manage ;;
            6) docker_volume_manage ;;
            7) docker_prune_unused; docker_manage_pause ;;
            8) docker_configure_mirror; docker_manage_pause ;;
            9) docker_edit_daemon_json; docker_manage_pause ;;
            10) docker_toggle_local_protection; docker_manage_pause ;;
            11) docker_enable_ipv6; docker_manage_pause ;;
            12) docker_disable_ipv6; docker_manage_pause ;;
            19) docker_backup_migration_menu ;;
            20) docker_uninstall_engine; docker_manage_pause ;;
            0|q|Q) return ;;
            *) echo -e "${RED}$(localized_text "无效选择。" "Invalid choice." "Неверный выбор.")${PLAIN}"; sleep 1 ;;
        esac
    done
}
# ---------------------------------------------------------
# 6. BBR 增强管理
# ---------------------------------------------------------
