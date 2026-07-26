#!/usr/bin/env bash

# Repository bootstrap.
# Compatibility fallback is handled below when local files are incomplete.
# Compatibility marker for legacy updater: VPS 全能控制面板

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -z "$SCRIPT_DIR" ]]; then
    echo "无法确定脚本所在目录。" >&2
    exit 1
fi
RELEASE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh"
MODULE_LIST="$SCRIPT_DIR/scripts/modules.list"
MODULES=()

download_release_script() {
    local output_file="$1"
    local local_file
    if [[ "$RELEASE_URL" == file://* ]]; then
        local_file="${RELEASE_URL#file://}"
        [[ -f "$local_file" ]] && cp "$local_file" "$output_file" 2>/dev/null
        return $?
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 90 --retry 2 --retry-delay 1 --retry-connrefused "$RELEASE_URL" -o "$output_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 --tries=3 -O "$output_file" "$RELEASE_URL"
    else
        echo "缺少 curl/wget，无法下载脚本。" >&2
        return 1
    fi
    [[ -s "$output_file" ]]
}

switch_to_release_script() {
    local tmp_file self_path
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/vps-optimize-release.XXXXXX.sh") || {
        echo "创建临时脚本失败。" >&2
        return 1
    }

    echo "检测到本地文件不完整，正在下载完整脚本..." >&2
    if ! download_release_script "$tmp_file"; then
        rm -f "$tmp_file"
        echo "下载脚本失败：$RELEASE_URL" >&2
        return 1
    fi
    if ! bash -n "$tmp_file" >/dev/null 2>&1; then
        rm -f "$tmp_file"
        echo "下载的脚本未通过语法检查。" >&2
        return 1
    fi
    if ! grep -q 'func_sni_stack_quick_menu' "$tmp_file" || ! grep -q 'main_menu' "$tmp_file"; then
        rm -f "$tmp_file"
        echo "下载的脚本内容不完整。" >&2
        return 1
    fi

    chmod +x "$tmp_file" 2>/dev/null || true
    self_path="$0"
    # 覆盖自身需要目录可写（mv 替换文件依赖父目录权限，而非文件本身）。
    # 若替换失败，回退到直接运行已下载的完整脚本，避免反复下载造成死循环。
    if [[ -f "$self_path" && -w "$self_path" ]] && mv "$tmp_file" "$self_path" 2>/dev/null; then
        chmod +x "$self_path" 2>/dev/null || true
        exec bash "$self_path" "$@"
    fi

    exec bash "$tmp_file" "$@"
}

load_source_modules() {
    local raw module
    MODULES=()
    [[ -f "$MODULE_LIST" ]] || {
        echo "缺少模块列表文件：scripts/modules.list" >&2
        return 1
    }
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        module="${raw%%#*}"
        module="${module#"${module%%[![:space:]]*}"}"
        module="${module%"${module##*[![:space:]]}"}"
        [[ -n "$module" ]] || continue
        if [[ "$module" == *.sh ]]; then
            echo "模块列表条目不应包含 .sh 后缀：${module}" >&2
            return 1
        fi
        MODULES+=("$module")
    done < "$MODULE_LIST"
    [[ ${#MODULES[@]} -gt 0 ]] || {
        echo "模块列表为空：scripts/modules.list" >&2
        return 1
    }
}

missing_module=0
if ! load_source_modules; then
    missing_module=1
fi
for module in "${MODULES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/src/${module}.sh" ]]; then
        echo "缺少源码模块：src/${module}.sh" >&2
        missing_module=1
    fi
done

if [[ "$missing_module" -ne 0 ]]; then
    switch_to_release_script "$@"
    exit 1
fi

for module in "${MODULES[@]}"; do
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/src/${module}.sh"
done
