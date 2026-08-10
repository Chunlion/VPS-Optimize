# shellcheck shell=bash
# Script update cache, version comparison, notice, and hot-update workflows.

fetch_latest_script_version() {
    local line version
    if command -v curl >/dev/null 2>&1; then
        line=$(curl -fsSL --connect-timeout 4 --max-time 10 "$UPDATE_URL" 2>/dev/null | grep -m1 '^SCRIPT_VERSION=' || true)
    elif command -v wget >/dev/null 2>&1; then
        line=$(wget -q --timeout=10 --tries=1 -O - "$UPDATE_URL" 2>/dev/null | grep -m1 '^SCRIPT_VERSION=' || true)
    else
        return 1
    fi
    [[ -n "$line" ]] || return 1
    version="${line#SCRIPT_VERSION=}"
    version="${version%\"}"
    version="${version#\"}"
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

fetch_latest_script_sha256() {
    local checksum
    if command -v curl >/dev/null 2>&1; then
        checksum=$(curl -fsSL --connect-timeout 4 --max-time 10 "$UPDATE_SHA256_URL" 2>/dev/null | awk 'NR == 1 {print $1}' || true)
    elif command -v wget >/dev/null 2>&1; then
        checksum=$(wget -q --timeout=10 --tries=1 -O - "$UPDATE_SHA256_URL" 2>/dev/null | awk 'NR == 1 {print $1}' || true)
    else
        return 1
    fi
    checksum=$(printf '%s' "$checksum" | tr 'A-F' 'a-f')
    [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$checksum"
}

current_script_sha256() {
    local current_file
    current_file="${VPSO_CURRENT_SCRIPT_PATH:-$(readlink -f "$0" 2>/dev/null || true)}"
    if [[ ! -f "$current_file" ]] || ! is_vps_optimize_generated_script "$current_file"; then
        current_file="${VPSO_SHORTCUT_PATH:-/usr/local/bin/cy}"
    fi
    [[ -f "$current_file" ]] || return 1
    command -v sha256sum >/dev/null 2>&1 || return 1
    sha256sum "$current_file" 2>/dev/null | awk 'NR == 1 {print $1}'
}

version_is_newer() {
    local latest="${1#v}"
    local current="${2#v}"
    local l1=0 l2=0 l3=0 c1=0 c2=0 c3=0
    IFS='.' read -r l1 l2 l3 <<< "$latest"
    IFS='.' read -r c1 c2 c3 <<< "$current"
    l1=${l1:-0}; l2=${l2:-0}; l3=${l3:-0}
    c1=${c1:-0}; c2=${c2:-0}; c3=${c3:-0}
    [[ "$l1$l2$l3$c1$c2$c3" =~ ^[0-9]+$ ]] || return 1
    (( 10#$l1 > 10#$c1 )) && return 0
    (( 10#$l1 < 10#$c1 )) && return 1
    (( 10#$l2 > 10#$c2 )) && return 0
    (( 10#$l2 < 10#$c2 )) && return 1
    (( 10#$l3 > 10#$c3 ))
}

script_update_cache_is_fresh() {
    local now mtime
    [[ -f "$SCRIPT_UPDATE_CACHE" ]] || return 1
    now=$(date +%s 2>/dev/null || echo 0)
    mtime=$(stat -c %Y "$SCRIPT_UPDATE_CACHE" 2>/dev/null || echo 0)
    [[ "$now" =~ ^[0-9]+$ && "$mtime" =~ ^[0-9]+$ ]] || return 1
    (( now > mtime && now - mtime < 43200 ))
}

read_script_update_cache_field() {
    local key="$1"
    grep -m1 "^${key}=" "$SCRIPT_UPDATE_CACHE" 2>/dev/null | cut -d= -f2-
}

write_script_update_cache() {
    local status="$1"
    local latest="$2"
    local latest_sha256="$3"
    local message="$4"
    local cache_dir
    cache_dir=$(dirname "$SCRIPT_UPDATE_CACHE")
    mkdir -p "$cache_dir" 2>/dev/null || return 0
    {
        echo "status=${status}"
        echo "latest=${latest}"
        echo "latest_sha256=${latest_sha256}"
        echo "message=${message}"
        echo "checked_at=$(date -Is 2>/dev/null || date)"
    } > "$SCRIPT_UPDATE_CACHE" 2>/dev/null || true
}

check_script_update_status() {
    local mode="${1:-auto}"
    local status latest latest_sha256 current_sha256 message
    current_sha256=$(current_script_sha256 2>/dev/null || true)
    if [[ "$mode" != "force" ]] && script_update_cache_is_fresh; then
        status=$(read_script_update_cache_field status)
        latest=$(read_script_update_cache_field latest)
        latest_sha256=$(read_script_update_cache_field latest_sha256)
        if [[ "$latest_sha256" =~ ^[0-9a-f]{64}$ && -n "$latest" && "$latest" != "unknown" ]]; then
            if version_is_newer "$latest" "$SCRIPT_VERSION"; then
                status="available"
            elif [[ -n "$current_sha256" && -n "$latest_sha256" && "$current_sha256" != "$latest_sha256" ]]; then
                status="available"
            else
                status="current"
            fi
            printf '%s|%s\n' "${status:-unknown}" "${latest:-unknown}"
            return 0
        fi
    fi

    if latest=$(fetch_latest_script_version) && latest_sha256=$(fetch_latest_script_sha256); then
        if version_is_newer "$latest" "$SCRIPT_VERSION"; then
            status="available"
            message="$(localized_text "发现新版本 ${latest}" "Found new version ${latest}" "Нашёл новую версию ${latest}")"
        elif [[ -n "$current_sha256" && "$current_sha256" != "$latest_sha256" ]]; then
            status="available"
            message="$(localized_text "检测到同版本内容更新" "Content updates of the same version detected" "Обнаружены обновления контента той же версии")"
        else
            status="current"
            message="$(localized_text "当前脚本内容已是最新" "The current script content is up to date" "Текущее содержимое сценария актуально.")"
        fi
        write_script_update_cache "$status" "$latest" "$latest_sha256" "$message"
        printf '%s|%s\n' "$status" "$latest"
        return 0
    fi

    write_script_update_cache "error" "unknown" "unknown" "$(localized_text "无法检查更新" "Unable to check for updates" "Невозможно проверить наличие обновлений")"
    printf 'error|unknown\n'
}

print_auto_update_notice() {
    local result status latest
    result=$(check_script_update_status "auto" 2>/dev/null || true)
    status="${result%%|*}"
    latest="${result#*|}"
    case "$status" in
        available)
            if [[ "$VPSO_LANGUAGE" == "ru" && "$latest" == "$SCRIPT_VERSION" ]]; then
                echo -e " ${BOLD}${YELLOW}Обновление:${PLAIN} содержимое версии ${CYAN}${latest}${PLAIN} изменилось; введите ${YELLOW}u${PLAIN}, чтобы обновить скрипт."
            elif [[ "$VPSO_LANGUAGE" == "ru" ]]; then
                echo -e " ${BOLD}${YELLOW}Обновление:${PLAIN} доступна версия ${CYAN}${latest}${PLAIN}; введите ${YELLOW}u${PLAIN}, чтобы обновить скрипт."
            elif [[ "$VPSO_LANGUAGE" == "en" && "$latest" == "$SCRIPT_VERSION" ]]; then
                echo -e " ${BOLD}${YELLOW}Update:${PLAIN} Content changed for ${CYAN}${latest}${PLAIN}; enter ${YELLOW}u${PLAIN} to update."
            elif [[ "$VPSO_LANGUAGE" == "en" ]]; then
                echo -e " ${BOLD}${YELLOW}Update:${PLAIN} ${CYAN}${latest}${PLAIN} is available; enter ${YELLOW}u${PLAIN} to update."
            elif [[ "$latest" == "$SCRIPT_VERSION" ]]; then
                echo -e "$(localized_text " ${BOLD}${YELLOW}更新提示:${PLAIN} 检测到 ${CYAN}${latest}${PLAIN} 的内容更新，输入 ${YELLOW}u${PLAIN} 可更新当前脚本。" "${BOLD}${YELLOW}Update prompt:${PLAIN} detects the content update of ${CYAN}${latest}${PLAIN}. Enter ${YELLOW}U${PLAIN} to update the current script." "Запрос на обновление ${BOLD}${YELLOW}:${PLAIN} обнаруживает обновление содержимого ${CYAN}${latest}${PLAIN}. Введите ${YELLOW}u${PLAIN}, чтобы обновить текущий скрипт.")"
            else
                echo -e "$(localized_text " ${BOLD}${YELLOW}更新提示:${PLAIN} 检测到 ${CYAN}${latest}${PLAIN}，输入 ${YELLOW}u${PLAIN} 可更新当前脚本。" "${BOLD}${YELLOW}Update prompt:${PLAIN} detects ${CYAN}${latest}${PLAIN}. Enter ${YELLOW}U${PLAIN} to update the current script." "${BOLD}${YELLOW}Приглашение к обновлению:${PLAIN} обнаруживает ${CYAN}${latest}${PLAIN}. Введите ${YELLOW}u${PLAIN}, чтобы обновить текущий скрипт.")"
            fi
            ;;
        current)
            localized_echo \
                " ${BLUE}更新状态:${PLAIN} 当前 ${SCRIPT_VERSION}，脚本内容已是最新。" \
                " ${BLUE}Update status:${PLAIN} ${SCRIPT_VERSION} is current." \
                " ${BLUE}Статус обновления:${PLAIN} установлена актуальная версия ${SCRIPT_VERSION}."
            ;;
    esac
}

func_update_script() {
    clear
    local tmp_file
    tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh) || {
        echo -e "$(localized_text "${RED}❌ 临时文件创建失败，更新已取消。${PLAIN}" "${RED}❌ Temporary file creation failed, update canceled.${PLAIN}" "${RED}❌ Не удалось создать временный файл, обновление отменено.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return 1
    }
    echo -e "$(localized_text "${CYAN}👉 正在从 GitHub 源地址拉取最新版本...${PLAIN}" "${CYAN}👉 Pulling the latest version from the GitHub source address...${PLAIN}" "${CYAN}👉 Получение последней версии с исходного адреса GitHub...${PLAIN}")"
    if download_verified_update_script "$tmp_file" \
        && grep -q "func_sni_stack_quick_menu" "$tmp_file" 2>/dev/null \
        && grep -q "main_menu" "$tmp_file" 2>/dev/null \
        && ! grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*src/' "$tmp_file" 2>/dev/null \
        && copy_shortcut_candidate "$tmp_file" /usr/local/bin/cy "$(localized_text "已验证更新脚本" "Verified update script" "Проверенный скрипт обновления")"; then
        rm -f "$tmp_file" "$SCRIPT_UPDATE_CACHE"
        echo -e "$(localized_text "${GREEN}✅ 更新已安装，正在重新打开面板...${PLAIN}" "${GREEN}✅ Update installed. Reopening the panel...${PLAIN}" "${GREEN}✅ Обновление установлено. Панель запускается заново...${PLAIN}")"
        sleep 1
        release_vpso_session_lock
        exec bash /usr/local/bin/cy
    else
        rm -f "$tmp_file"
        echo -e "$(localized_text "${RED}❌ 更新失败：下载、脚本标识、语法或 sha256 校验未全部通过。${PLAIN}" "${RED}❌ Update failed: The download, script identifier, syntax, or sha256 check did not all pass.${PLAIN}" "${RED}❌ Обновление не выполнено: проверка загрузки, идентификатора сценария, синтаксиса или sha256 не прошла успешно.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
    fi
}

# ---------------------------------------------------------
# 20. 一键运维预检
# ---------------------------------------------------------
