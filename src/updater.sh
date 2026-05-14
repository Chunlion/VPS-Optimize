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
    local message="$3"
    local cache_dir
    cache_dir=$(dirname "$SCRIPT_UPDATE_CACHE")
    mkdir -p "$cache_dir" 2>/dev/null || return 0
    {
        echo "status=${status}"
        echo "latest=${latest}"
        echo "message=${message}"
        echo "checked_at=$(date -Is 2>/dev/null || date)"
    } > "$SCRIPT_UPDATE_CACHE" 2>/dev/null || true
}

check_script_update_status() {
    local mode="${1:-auto}"
    local status latest message
    if [[ "$mode" != "force" ]] && script_update_cache_is_fresh; then
        status=$(read_script_update_cache_field status)
        latest=$(read_script_update_cache_field latest)
        if [[ -n "$latest" && "$latest" != "unknown" ]]; then
            if version_is_newer "$latest" "$SCRIPT_VERSION"; then
                status="available"
            else
                status="current"
            fi
        fi
        printf '%s|%s\n' "${status:-unknown}" "${latest:-unknown}"
        return 0
    fi

    if latest=$(fetch_latest_script_version); then
        if version_is_newer "$latest" "$SCRIPT_VERSION"; then
            status="available"
            message="发现新版本 ${latest}"
        else
            status="current"
            message="当前已是最新版本"
        fi
        write_script_update_cache "$status" "$latest" "$message"
        printf '%s|%s\n' "$status" "$latest"
        return 0
    fi

    write_script_update_cache "error" "unknown" "无法检查更新"
    printf 'error|unknown\n'
}

print_auto_update_notice() {
    local result status latest
    result=$(check_script_update_status "auto" 2>/dev/null || true)
    status="${result%%|*}"
    latest="${result#*|}"
    case "$status" in
        available)
            echo -e " ${BOLD}${YELLOW}更新提示:${PLAIN} 检测到 ${CYAN}${latest}${PLAIN}，输入 ${YELLOW}u${PLAIN} 可无缝更新发布版。"
            ;;
        current)
            echo -e " ${BLUE}更新状态:${PLAIN} 当前 ${SCRIPT_VERSION}，未发现更高的发布版。"
            ;;
    esac
}

func_update_script() {
    clear
    local tmp_file sha_file
    tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh) || {
        echo -e "${RED}❌ 临时文件创建失败，更新已取消。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    }
    sha_file=$(mktemp /tmp/cy_update.XXXXXX.sha256) || {
        rm -f "$tmp_file"
        echo -e "${RED}❌ 临时校验文件创建失败，更新已取消。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return 1
    }
    echo -e "${CYAN}👉 正在从 GitHub 源地址拉取最新版本...${PLAIN}"
    if download_remote_script "$UPDATE_URL" "$tmp_file" \
        && bash -n "$tmp_file" \
        && download_remote_script "$UPDATE_SHA256_URL" "$sha_file" \
        && verify_file_sha256 "$tmp_file" "$sha_file" \
        && grep -q "func_sni_stack_quick_menu" "$tmp_file" 2>/dev/null \
        && grep -q "main_menu" "$tmp_file" 2>/dev/null \
        && ! grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*src/' "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" /usr/local/bin/cy
        chmod +x /usr/local/bin/cy
        rm -f "$sha_file"
        echo -e "${GREEN}✅ 更新下载并覆盖完成！正在重启面板...${PLAIN}"
        sleep 1
        exec bash /usr/local/bin/cy
    else
        rm -f "$tmp_file" "$sha_file"
        echo -e "${RED}❌ 更新失败！请检查您的网络连通性或 GitHub 地址是否正确。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
    fi
}

# ---------------------------------------------------------
# 20. 一键运维预检
# ---------------------------------------------------------
