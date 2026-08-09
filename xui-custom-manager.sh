#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PROFILE="${CONFIG_PROFILE:-/etc/xui-custom-manager.conf}"
CONFIG_FILE="${CONFIG_FILE:-/etc/xui-custom-reset.json}"
BACKUP_DIR="${BACKUP_DIR:-/root/x-ui-backups}"
XUI_DB="${XUI_DB:-/etc/x-ui/x-ui.db}"
XUI_ETC_DIR="${XUI_ETC_DIR:-/etc/x-ui}"
XUI_PROGRAM_DIR="${XUI_PROGRAM_DIR:-/usr/local/x-ui}"
XUI_SUPPORTED_VERSION_RANGES="${XUI_SUPPORTED_VERSION_RANGES:-2.9.x 3.x}"
LOG_FILE="${LOG_FILE:-/var/log/xui-custom-manager.log}"
RESET_STATE="${RESET_STATE:-/var/lib/xui-custom-manager/reset-state.json}"
RESET_SERVICE="${RESET_SERVICE:-/etc/systemd/system/xui-custom-reset.service}"
RESET_TIMER="${RESET_TIMER:-/etc/systemd/system/xui-custom-reset.timer}"
LOCAL_RUNNER="/usr/local/bin/xui-custom-manager.sh"
XCM_PATH="/usr/local/bin/xcm"

RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
PLAIN='\033[0m'

RUN_CHECK=0
DRY_RUN=0
SELF_TEST=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --reset-check)
            RUN_CHECK=1
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --self-test)
            SELF_TEST=1
            ;;
        -h|--help)
            echo "用法：$0 [--reset-check] [--dry-run] [--self-test]"
            exit 0
            ;;
        *)
            echo "未知参数：$1"
            exit 1
            ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ] && [ "$SELF_TEST" -ne 1 ]; then
    echo "请用 root 用户运行。"
    exit 1
fi

if [ -f "$CONFIG_PROFILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_PROFILE"
fi

LOCAL_RUNNER="/usr/local/bin/xui-custom-manager.sh"
XCM_PATH="/usr/local/bin/xcm"

if [ "$SELF_TEST" -ne 1 ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
fi

if { [ "$RUN_CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; } && [ "$SELF_TEST" -ne 1 ] && [ ! -t 1 ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "===== $(date '+%F %T') reset-check 执行 ====="
fi

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033c'
    fi
}

pause() {
    echo
    # EOF（Ctrl+D）时不因 set -e 直接退出整个脚本
    read -rp "按回车返回..." || true
}

confirm_yes() {
    local message="$1"
    local answer
    echo
    echo -e "${YELLOW}${message}${PLAIN}"
    read -rp "继续？[Y/n]: " answer
    answer="${answer:-yes}"
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

need_tty() {
    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        echo "错误：该功能需要交互式终端。"
        return 1
    fi
}

require_interactive_menu() {
    if [ -t 0 ]; then
        return 0
    fi
    if [ -r /dev/tty ]; then
        exec </dev/tty
        return 0
    fi
    echo "错误：管理菜单需要交互式终端，当前没有可读取的 stdin。"
    echo "请在 SSH 终端中直接运行：bash $LOCAL_RUNNER"
    echo "非交互环境请使用：bash $LOCAL_RUNNER --reset-check --dry-run"
    return 1
}

read_menu_choice() {
    local __var_name="$1"
    local __prompt="${2:-请选择：}"
    local __value
    # EOF（Ctrl+D）按“返回上级”处理，避免 set -e 直接退出整个脚本
    read -rp "$__prompt" __value || { echo; __value="q"; }
    printf -v "$__var_name" '%s' "$__value"
}

ensure_dirs() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$RESET_STATE")"
    chmod 700 "$BACKUP_DIR"
    chmod 700 "$(dirname "$RESET_STATE")"
}

detect_xui_version() {
    local command_line output version
    local -a parts
    local commands=(
        "x-ui version"
        "x-ui -v"
        "/usr/local/x-ui/x-ui version"
        "/usr/local/x-ui/x-ui -v"
    )

    for command_line in "${commands[@]}"; do
        read -r -a parts <<< "$command_line"
        output="$("${parts[@]}" 2>&1 || true)"
        version="$(printf '%s\n' "$output" | grep -Eo 'v?[0-9]+([.][0-9]+){2,3}' | head -n 1 | sed 's/^v//')"
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    done

    echo "unknown"
}

format_supported_version_ranges() {
    local output
    output="${XUI_SUPPORTED_VERSION_RANGES// /, }"
    echo "$output"
}

xui_version_is_supported() {
    local detected_version="${1:-}"
    local range
    detected_version="${detected_version:-$(detect_xui_version)}"
    for range in $XUI_SUPPORTED_VERSION_RANGES; do
        case "$range" in
            2.9.x)
                [[ "$detected_version" == 2.9.* ]] && return 0
                ;;
            3.x)
                [[ "$detected_version" == 3.* ]] && return 0
                ;;
            *)
                [[ "$detected_version" == "$range" ]] && return 0
                ;;
        esac
    done
    return 1
}

print_xui_version_warning() {
    local detected_version="${1:-}"
    local supported_ranges
    detected_version="${detected_version:-$(detect_xui_version)}"
    supported_ranges="$(format_supported_version_ranges)"
    if xui_version_is_supported "$detected_version"; then
        echo -e "${GREEN}兼容性：当前 3x-ui v${detected_version} 在支持范围内，写库前仍会校验数据库表/字段关键字。${PLAIN}"
    else
        echo -e "${YELLOW}兼容性提示：当前 3x-ui v${detected_version} 不在支持范围内。${PLAIN}"
        echo -e "${YELLOW}支持范围：${supported_ranges}。其它版本只允许备份、查看、预览和自检，不允许写库或启用自动重置。${PLAIN}"
    fi
}

check_xui_db_schema_readonly() {
    if [ ! -f "$XUI_DB" ]; then
        echo "数据库不存在：$XUI_DB" >&2
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "缺少 python3，无法执行只读 schema 兼容检查。" >&2
        return 1
    fi

    XUI_DB="$XUI_DB" python3 <<'PY'
import os
import sqlite3
import sys

db_path = os.environ["XUI_DB"]
required = {
    "inbounds": {"id", "remark", "port", "up", "down", "total", "traffic_reset", "last_traffic_reset_time"},
    "client_traffics": {"id", "inbound_id", "email", "up", "down", "total", "enable"},
}
optional_relation = {
    "clients": {"id", "email"},
    "client_inbounds": {"client_id", "inbound_id"},
}

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
except Exception as exc:
    print(f"只读打开数据库失败：{exc}", file=sys.stderr)
    sys.exit(1)

try:
    missing = []
    def table_columns(table):
        rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
        return {row[1] for row in rows}

    for table, columns in required.items():
        existing = table_columns(table)
        if not existing:
            missing.append(f"{table}.*")
            continue
        for column in sorted(columns - existing):
            missing.append(f"{table}.{column}")
    relation_tables_found = any(table_columns(table) for table in optional_relation)
    if relation_tables_found:
        for table, columns in optional_relation.items():
            existing = table_columns(table)
            if not existing:
                missing.append(f"{table}.*")
                continue
            for column in sorted(columns - existing):
                missing.append(f"{table}.{column}")
    if missing:
        print("数据库字段兼容检查失败，缺少：" + ", ".join(missing), file=sys.stderr)
        sys.exit(1)
finally:
    conn.close()
PY
}

require_verified_xui_for_write() {
    local detected_version
    detected_version="$(detect_xui_version)"
    if ! xui_version_is_supported "$detected_version"; then
        print_xui_version_warning "$detected_version"
        echo -e "${RED}错误：当前 3x-ui 版本不在支持范围内，已禁止写库/启用 timer。${PLAIN}"
        return 1
    fi
    if ! check_xui_db_schema_readonly; then
        print_xui_version_warning "$detected_version"
        echo -e "${RED}错误：无法确认数据库字段兼容，已禁止写库/启用 timer。${PLAIN}"
        return 1
    fi
}

install_runtime_deps() {
    local missing=()

    command -v sqlite3 >/dev/null 2>&1 || missing+=("sqlite3")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi

    local apt_log_dir apt_log
    if [ -d /var/log ] && [ -w /var/log ]; then
        apt_log_dir="/var/log"
    else
        apt_log_dir="/tmp"
    fi
    apt_log="$(mktemp "${apt_log_dir}/xui-custom-manager-apt-XXXXXX.log")"

    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        if ! apt-get update -qq >"$apt_log" 2>&1 || ! apt-get install -y "${missing[@]}" >>"$apt_log" 2>&1; then
            unset DEBIAN_FRONTEND
            echo "错误：自动安装依赖失败，日志：$apt_log"
            echo "最后 20 行："
            tail -n 20 "$apt_log" 2>/dev/null || true
            return 1
        fi
        unset DEBIAN_FRONTEND
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        # RHEL 系（Rocky/Alma 等）：sqlite3 命令由 sqlite 包提供
        local rhel_pkg_cmd="dnf" rhel_pkgs=() tool
        command -v dnf >/dev/null 2>&1 || rhel_pkg_cmd="yum"
        for tool in "${missing[@]}"; do
            case "$tool" in
                sqlite3) rhel_pkgs+=("sqlite") ;;
                *) rhel_pkgs+=("$tool") ;;
            esac
        done
        if ! "$rhel_pkg_cmd" install -y "${rhel_pkgs[@]}" >"$apt_log" 2>&1; then
            echo "错误：自动安装依赖失败，日志：$apt_log"
            echo "最后 20 行："
            tail -n 20 "$apt_log" 2>/dev/null || true
            return 1
        fi
    else
        rm -f "$apt_log"
        echo "错误：缺少依赖：${missing[*]}，且未找到 apt-get/dnf/yum，请手动安装后重试。"
        return 1
    fi
    rm -f "$apt_log"
}

timer_active_status() {
    if systemctl is-active --quiet xui-custom-reset.timer 2>/dev/null; then
        echo "已启用"
    else
        echo "未启用"
    fi
}

timer_enabled_status() {
    if systemctl is-enabled --quiet xui-custom-reset.timer 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

runner_status() {
    if [ -x "$LOCAL_RUNNER" ]; then
        echo "已安装"
    else
        echo "未安装"
    fi
}

register_xcm_shortcut() {
    local need_write=0

    mkdir -p "$(dirname "$XCM_PATH")"

    if [ ! -f "$XCM_PATH" ]; then
        need_write=1
    elif ! grep -q "CACHE_FILE=.*xui-custom-manager.sh" "$XCM_PATH" 2>/dev/null; then
        need_write=1
    elif ! grep -q "wget" "$XCM_PATH" 2>/dev/null; then
        need_write=1
    fi

    if [ "$need_write" -eq 1 ]; then
        cat > "$XCM_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh"
CACHE_DIR="/usr/local/lib/xui-custom-manager"
CACHE_FILE="$CACHE_DIR/xui-custom-manager.sh"
TMP_FILE="$(mktemp)"

mkdir -p "$CACHE_DIR"

validate_downloaded_manager() {
    if ! bash -n "$TMP_FILE"; then
        echo "警告：新下载的 xui-custom-manager.sh 语法检查失败，保留旧缓存。"
        return 1
    fi
    if ! grep -Eq 'xui-custom-manager|CONFIG_PROFILE' "$TMP_FILE"; then
        echo "警告：新下载的 xui-custom-manager.sh 缺少关键标识，保留旧缓存。"
        return 1
    fi
}

if command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 10 --retry 2 "$URL" -o "$TMP_FILE" && validate_downloaded_manager; then
    install -m 755 "$TMP_FILE" "$CACHE_FILE"
    rm -f "$TMP_FILE"
    exec bash "$CACHE_FILE" "$@"
fi

if command -v wget >/dev/null 2>&1 && wget -qO "$TMP_FILE" --timeout=10 --tries=2 "$URL" && validate_downloaded_manager; then
    install -m 755 "$TMP_FILE" "$CACHE_FILE"
    rm -f "$TMP_FILE"
    exec bash "$CACHE_FILE" "$@"
fi

rm -f "$TMP_FILE"

if [ -f "$CACHE_FILE" ]; then
    echo "警告：拉取最新版失败，使用本地缓存版本。"
    exec bash "$CACHE_FILE" "$@"
fi

echo "错误：无法拉取最新版，也没有本地缓存。"
exit 1
EOF
    fi

    chmod 755 "$XCM_PATH"
}

validate_manager_script_source() {
    local source_file="$1"
    local first_line

    if [ ! -r "$source_file" ]; then
        echo "错误：源脚本不可读：$source_file"
        return 1
    fi
    IFS= read -r first_line < "$source_file" || first_line=""
    if [ "$first_line" != "#!/usr/bin/env bash" ]; then
        echo "错误：拒绝安装本地 runner，源脚本首行必须是 #!/usr/bin/env bash。"
        return 1
    fi
    if ! bash -n "$source_file"; then
        echo "错误：拒绝安装本地 runner，源脚本 bash -n 未通过。"
        return 1
    fi
    if ! grep -Eq 'xui-custom-manager|CONFIG_PROFILE' "$source_file"; then
        echo "错误：拒绝安装本地 runner，源脚本缺少 xui-custom-manager 关键标识。"
        return 1
    fi
}

install_local_runner() {
    local self_path
    self_path="$(readlink -f "${BASH_SOURCE[0]}")"

    mkdir -p "$(dirname "$LOCAL_RUNNER")"

    if [ "$self_path" = "$LOCAL_RUNNER" ] && [ -x "$LOCAL_RUNNER" ]; then
        return 0
    fi

    validate_manager_script_source "$self_path" || return 1
    install -m 755 "$self_path" "$LOCAL_RUNNER"
}

ensure_reset_timer_installed() {
    require_verified_xui_for_write || return 1
    # 本地 runner 安装失败时必须中止，否则 timer 会指向不存在的执行器
    install_local_runner || return 1

    # TimeoutStartSec 需覆盖首次运行时的依赖安装与大数据库备份；
    # ExecStopPost 兜底：即使运行中途被杀，也会把 x-ui 拉起来
    cat > "$RESET_SERVICE" <<EOF
[Unit]
Description=x-ui custom reset check
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $LOCAL_RUNNER --reset-check
ExecStopPost=-/usr/bin/systemctl start x-ui
TimeoutStartSec=900
StandardOutput=journal
StandardError=journal
EOF

    cat > "$RESET_TIMER" <<'EOF'
[Unit]
Description=Run x-ui custom reset check daily

[Timer]
OnCalendar=*-*-* 00:10:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now xui-custom-reset.timer
}

disable_reset_timer() {
    systemctl disable --now xui-custom-reset.timer >/dev/null 2>&1 || true
}

backup_database() {
    ensure_dirs

    if [ ! -f "$XUI_DB" ]; then
        # 错误信息走 stderr：调用方用 $(…) 捕获 stdout，否则用户看不到报错
        echo "错误：数据库不存在：$XUI_DB" >&2
        return 1
    fi

    local ts backup_file
    ts="$(date +%F_%H%M%S)"
    backup_file="$BACKUP_DIR/x-ui.db.$ts.bak"

    # 先写临时文件再原子改名，避免中断产生的半截备份混入恢复列表
    if sqlite3 "$XUI_DB" ".backup '$backup_file.tmp'"; then
        chmod 600 "$backup_file.tmp"
        mv "$backup_file.tmp" "$backup_file"
        echo "$backup_file"
        return 0
    fi

    rm -f "$backup_file.tmp"
    echo "错误：数据库备份失败，已取消写库。" >&2
    return 1
}

backup_all() {
    ensure_dirs
    install_runtime_deps

    echo "正在备份..."

    if [ -f "$XUI_DB" ]; then
        local db_backup
        db_backup="$(backup_database)" || return 1
        echo "数据库备份：$db_backup"
    else
        echo "数据库不存在，跳过：$XUI_DB"
    fi

    local ts
    ts="$(date +%F_%H%M%S)"

    # 压缩包同样先写 .tmp 再原子改名，防止半截包被恢复列表当成有效备份
    if [ -d "$XUI_ETC_DIR" ]; then
        local etc_tar="$BACKUP_DIR/x-ui-etc.$ts.tar.gz"
        if tar -czf "$etc_tar.tmp" -C "$(dirname "$XUI_ETC_DIR")" "$(basename "$XUI_ETC_DIR")"; then
            chmod 600 "$etc_tar.tmp"
            mv "$etc_tar.tmp" "$etc_tar"
            echo "配置目录备份：$etc_tar"
        else
            rm -f "$etc_tar.tmp"
            echo "错误：配置目录备份失败。" >&2
            return 1
        fi
    else
        echo "配置目录不存在，跳过：$XUI_ETC_DIR"
    fi

    if [ -d "$XUI_PROGRAM_DIR" ]; then
        local program_tar="$BACKUP_DIR/x-ui-program.$ts.tar.gz"
        if tar -czf "$program_tar.tmp" -C "$(dirname "$XUI_PROGRAM_DIR")" "$(basename "$XUI_PROGRAM_DIR")"; then
            chmod 600 "$program_tar.tmp"
            mv "$program_tar.tmp" "$program_tar"
            echo "程序目录备份：$program_tar"
        else
            rm -f "$program_tar.tmp"
            echo "错误：程序目录备份失败。" >&2
            return 1
        fi
    else
        echo "程序目录不存在，跳过：$XUI_PROGRAM_DIR"
    fi
}

restore_backup() {
    local kind="$1"
    local pattern label target_dir

    ensure_dirs
    install_runtime_deps

    case "$kind" in
        db)
            pattern="x-ui.db.*.bak"
            label="数据库"
            ;;
        program)
            pattern="x-ui-program.*.tar.gz"
            label="程序目录"
            target_dir="$(dirname "$XUI_PROGRAM_DIR")"
            ;;
        etc)
            pattern="x-ui-etc.*.tar.gz"
            label="配置目录"
            target_dir="$(dirname "$XUI_ETC_DIR")"
            ;;
        *)
            echo "未知恢复类型：$kind"
            return 1
            ;;
    esac

    while true; do
        clear_screen
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}x-ui 增强套件 - 恢复$label${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local files=()
        mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$pattern" | sort -r)

        if [ "${#files[@]}" -eq 0 ]; then
            echo "未找到 $label 备份。"
            pause
            return 0
        fi

        local i
        for i in "${!files[@]}"; do
            echo " $((i + 1)). ${files[$i]}"
        done
        echo "------------------------------------------------"
        echo -e "${RED}  0/q. 返回备份与恢复${PLAIN}"
        echo "================================================"

        local choice
        read_menu_choice choice "请选择备份文件 [0-${#files[@]}]："
        if [[ "$choice" =~ ^(0|q|Q)$ ]]; then
            return 0
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#files[@]}" ]; then
            echo -e "${RED}输入无效，请输入 0-${#files[@]}。${PLAIN}"
            sleep 1
            continue
        fi

        local selected="${files[$((choice - 1))]}"
        confirm_yes "恢复会覆盖当前 $label。恢复前会先备份当前状态。" || {
            echo "已取消。"
            return 0
        }

        # 恢复是灾难修复入口：不再要求当前安装状态健康（当前损坏时正是最需要恢复的时候），
        # 改为校验所选备份文件本身的完整性
        if [ "$kind" = "db" ]; then
            if command -v sqlite3 >/dev/null 2>&1 && ! sqlite3 "$selected" "PRAGMA integrity_check;" 2>/dev/null | grep -qx "ok"; then
                echo -e "${RED}错误：所选数据库备份未通过完整性校验，已取消恢复。${PLAIN}"
                pause
                continue
            fi
        else
            if ! tar -tzf "$selected" >/dev/null 2>&1; then
                echo -e "${RED}错误：所选备份压缩包已损坏，已取消恢复。${PLAIN}"
                pause
                continue
            fi
        fi

        echo "恢复前备份当前状态..."
        if ! backup_all; then
            echo -e "${YELLOW}警告：恢复前备份失败（当前安装可能已损坏）。${PLAIN}"
            confirm_yes "仍要继续恢复吗？继续后当前状态将无法回退。" || {
                echo "已取消。"
                return 0
            }
        fi

        echo "停止 x-ui..."
        systemctl stop x-ui || true

        # 恢复动作必须受控失败：中途出错也要把 x-ui 拉起来并明确告知，不能让脚本静默退出
        local restore_failed=0
        if [ "$kind" = "db" ]; then
            mkdir -p "$(dirname "$XUI_DB")" 2>/dev/null || true
            if cp -a "$selected" "$XUI_DB"; then
                chmod 600 "$XUI_DB"
            else
                restore_failed=1
            fi
        else
            tar -xzf "$selected" -C "$target_dir" || restore_failed=1
        fi

        echo "启动 x-ui..."
        systemctl start x-ui || true
        if [ "$restore_failed" -ne 0 ]; then
            echo -e "${RED}错误：恢复过程中出现失败，目标可能处于不完整状态；可重试或改用其他备份。${PLAIN}"
            pause
            return 1
        fi
        echo
        print_health_report
        return 0
    done
}

cleanup_backups() {
    clear_screen
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}x-ui 增强套件 - 清理旧备份${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    ensure_dirs

    local patterns=("x-ui.db.*.bak" "x-ui-etc.*.tar.gz" "x-ui-program.*.tar.gz")
    local labels=("数据库" "配置目录" "程序目录")
    local i

    for i in "${!patterns[@]}"; do
        local files=()
        mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${patterns[$i]}" | sort -r)

        if [ "${#files[@]}" -le 10 ]; then
            echo "${labels[$i]}：当前 ${#files[@]} 个，不需要清理。"
            continue
        fi

        echo
        echo "${labels[$i]}：保留最新 10 个，可选择删除一个旧备份。"
        local idx
        for idx in "${!files[@]}"; do
            if [ "$idx" -ge 10 ]; then
                echo " $((idx + 1)). ${files[$idx]}"
            fi
        done
        echo -e "${RED}  0/q. 跳过此类备份${PLAIN}"

        local choice
        read_menu_choice choice "请选择要删除的备份编号："
        if [[ "$choice" =~ ^(0|q|Q)$ ]]; then
            continue
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 11 ] && [ "$choice" -le "${#files[@]}" ]; then
            local selected="${files[$((choice - 1))]}"
            confirm_yes "确认删除文件：$selected" && rm -f -- "$selected" && echo "已删除：$selected"
        else
            echo "无效选择，已跳过。"
        fi
    done

    echo
    echo "清理完成。"
}

run_custom_reset_ui() {
    install_runtime_deps
    need_tty || return 1

    local xui_write_allowed=0
    local detected_version
    detected_version="$(detect_xui_version)"
    if xui_version_is_supported "$detected_version" && check_xui_db_schema_readonly >/dev/null 2>&1; then
        xui_write_allowed=1
    fi

    local tmp_py
    tmp_py="$(mktemp --suffix=.py)"
    trap 'rm -f "$tmp_py"' RETURN

    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

db_path = os.environ.get("XUI_DB", "/etc/x-ui/x-ui.db")
config_path = Path(os.environ.get("CONFIG_FILE", "/etc/xui-custom-reset.json"))
write_allowed = os.environ.get("XUI_WRITE_ALLOWED") == "1"
supported_ranges = os.environ.get("XUI_SUPPORTED_VERSION_RANGES", "2.9.x 3.x")
detected_version = os.environ.get("XUI_DETECTED_VERSION", "unknown")

ANSI = {
    "red": "\033[0;31m",
    "green": "\033[1;32m",
    "yellow": "\033[1;33m",
    "blue": "\033[1;34m",
    "magenta": "\033[1;35m",
    "cyan": "\033[1;36m",
    "white": "\033[1;37m",
    "bold": "\033[1m",
    "plain": "\033[0m",
}

def paint(text, color):
    return f"{ANSI[color]}{text}{ANSI['plain']}"

def title(text):
    print(paint("================================================", "cyan"))
    print(paint(text, "bold"))
    print(paint("================================================", "cyan"))

def separator():
    print(paint("------------------------------------------------", "blue"))

def menu_line(number, label, hint=""):
    line = f" {paint(str(number) + '.', 'cyan')} {paint(label, 'green')}"
    if hint:
        line += f" {paint(hint, 'yellow')}"
    print(line)

def status_value(enabled, enabled_text="开启", disabled_text="关闭"):
    return paint(enabled_text, "green") if enabled else paint(disabled_text, "red")

def clear_screen():
    print("\033c", end="")

def pause():
    input("\n按回车返回...")

def print_write_blocked():
    print(paint(f"错误：当前 3x-ui v{detected_version} 不在支持范围内，或数据库表/字段关键字未通过检查。", "red"))
    print(paint(f"支持范围：{', '.join(supported_ranges.split())}。", "yellow"))
    print(paint("不满足条件时只允许备份、查看、预览和自检，不允许修改配置、写库或启用自动重置。", "yellow"))

def require_config_write():
    if write_allowed:
        return True
    print_write_blocked()
    pause()
    return False

def valid_day(value):
    try:
        day = int(value)
    except Exception:
        return None
    return day if 1 <= day <= 31 else None

def default_config():
    return {"enabled": False, "default_day": 1, "inbounds": {}}

def normalize_config(data):
    if not isinstance(data, dict):
        raise ValueError("配置根节点不是对象")
    data.setdefault("enabled", False)
    data["enabled"] = bool(data.get("enabled"))
    day = valid_day(data.get("default_day", 1))
    data["default_day"] = day or 1
    if not isinstance(data.get("inbounds"), dict):
        data["inbounds"] = {}
    for iid, cfg in list(data["inbounds"].items()):
        if not isinstance(cfg, dict):
            data["inbounds"].pop(iid, None)
            continue
        cfg["enabled"] = bool(cfg.get("enabled", False))
        cfg["day"] = valid_day(cfg.get("day", data["default_day"])) or data["default_day"]
        cfg["reset_inbound"] = bool(cfg.get("reset_inbound", True))
        cfg["reset_clients_without_custom_day"] = bool(cfg.get("reset_clients_without_custom_day", False))
        if not isinstance(cfg.get("clients"), dict):
            cfg["clients"] = {}
        for email, ccfg in list(cfg["clients"].items()):
            if not isinstance(ccfg, dict):
                cfg["clients"].pop(email, None)
                continue
            cday = valid_day(ccfg.get("day", 0))
            if not cday:
                cfg["clients"].pop(email, None)
                continue
            ccfg["enabled"] = bool(ccfg.get("enabled", True))
            ccfg["day"] = cday
    return data

def load_config():
    if not config_path.exists():
        return default_config()
    try:
        with config_path.open("r", encoding="utf-8") as f:
            return normalize_config(json.load(f))
    except Exception as exc:
        print(f"错误：读取配置失败：{config_path}")
        print(f"原因：{exc}")
        print("请先手动检查配置文件，或从备份恢复。")
        sys.exit(1)

def save_config(data):
    if not write_allowed:
        print_write_blocked()
        return False
    data = normalize_config(data)
    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = config_path.with_name(config_path.name + f".tmp.{os.getpid()}")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp_path, config_path)
    os.chmod(config_path, 0o600)
    return True

def input_choice(prompt, valid_choices):
    while True:
        try:
            choice = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        if choice in valid_choices:
            return choice
        print("无效选择，请重新输入。")

def ask_day(prompt, allow_zero=False):
    while True:
        try:
            raw = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        try:
            day = int(raw)
        except Exception:
            print("请输入数字。")
            continue
        if allow_zero and day == 0:
            return 0
        if 1 <= day <= 31:
            return day
        print("日期范围只能是 1-31。")

def trunc(text, limit=20):
    text = text or "无备注"
    return text if len(text) <= limit else text[:limit] + "..."

def timer_status():
    return subprocess.run(["systemctl", "is-active", "--quiet", "xui-custom-reset.timer"]).returncode == 0

def load_db():
    try:
        # 只读模式打开：数据库缺失时报错而不是悄悄创建一个空的 x-ui.db
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        try:
            inbounds = conn.execute("SELECT id, remark, port, traffic_reset FROM inbounds ORDER BY id").fetchall()
        except sqlite3.OperationalError:
            inbounds = conn.execute("SELECT id, remark, port, 'unknown' AS traffic_reset FROM inbounds ORDER BY id").fetchall()
        clients = load_clients(conn)
        conn.close()
        return inbounds, clients
    except Exception as exc:
        print(paint(f"数据库读取失败：{exc}", "red"))
        sys.exit(1)

def table_columns(conn, table):
    try:
        return {row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    except sqlite3.OperationalError:
        return set()

def has_normalized_clients(conn):
    return (
        {"id", "email"} <= table_columns(conn, "clients")
        and {"client_id", "inbound_id"} <= table_columns(conn, "client_inbounds")
    )

def load_clients(conn):
    if has_normalized_clients(conn):
        rows = conn.execute(
            """
            SELECT COALESCE(ct.id, 0) AS id,
                   ci.inbound_id AS inbound_id,
                   c.email AS email
            FROM client_inbounds ci
            JOIN clients c ON c.id = ci.client_id
            LEFT JOIN client_traffics ct ON ct.email = c.email
            WHERE COALESCE(c.email, '') <> ''
            ORDER BY ci.inbound_id, c.id
            """
        ).fetchall()
        return [dict(row) for row in rows]
    try:
        return conn.execute("SELECT id, inbound_id, email FROM client_traffics ORDER BY id").fetchall()
    except sqlite3.OperationalError:
        return []

config = load_config()
inbounds, clients = load_db()
clients_by_inbound = {}
for client in clients:
    clients_by_inbound.setdefault(str(client["inbound_id"]), []).append(client)

def show_config():
    clear_screen()
    title("x-ui 增强套件 - 自定义重置配置")
    print(json.dumps(config, ensure_ascii=False, indent=2))
    pause()

def manage_clients(inbound_id, inbound_cfg):
    clients_for_inbound = clients_by_inbound.get(str(inbound_id), [])
    while True:
        clear_screen()
        title("x-ui 增强套件 - 设置客户端重置日")
        print(f"{paint('入站 ID：', 'cyan')}{paint(inbound_id, 'white')}")
        print(paint("未单独设置的客户端使用入站规则。", "yellow"))
        separator()

        if not clients_for_inbound:
            print(paint("当前入站没有客户端。", "yellow"))
        for idx, client in enumerate(clients_for_inbound, start=1):
            email = client["email"] or "无邮箱"
            ccfg = inbound_cfg.get("clients", {}).get(email, {})
            if ccfg.get("enabled") and ccfg.get("day"):
                status = paint(f"每月 {ccfg['day']} 号", "green")
            else:
                status = paint("使用入站规则", "yellow")
            print(f" {paint(str(idx) + '.', 'cyan')} {paint(email, 'white')}")
            print(f"    {status}")

        separator()
        print(f" {paint('0/q.', 'red')} 返回入站设置")
        print(paint("================================================", "cyan"))

        valid = {"0", "q", "Q"} | {str(i) for i in range(1, len(clients_for_inbound) + 1)}
        choice = input_choice(f"请选择客户端 [0-{len(clients_for_inbound)}]：", valid)
        if choice in {"0", "q", "Q"}:
            return

        email = clients_for_inbound[int(choice) - 1]["email"] or ""
        if not require_config_write():
            continue
        day = ask_day("设置重置日 [1-31]，输入 0 使用入站规则：", allow_zero=True)
        inbound_cfg.setdefault("clients", {})
        if day == 0:
            inbound_cfg["clients"].pop(email, None)
            print("已改为使用入站规则。")
        else:
            inbound_cfg["clients"][email] = {"enabled": True, "day": day}
            print(f"已设置为每月 {day} 号。")
        save_config(config)
        pause()

def manage_inbound(inbound):
    iid = str(inbound["id"])
    config.setdefault("inbounds", {})
    cfg = config["inbounds"].setdefault(iid, {})
    cfg.setdefault("enabled", False)
    cfg.setdefault("day", config.get("default_day", 1))
    cfg.setdefault("reset_inbound", True)
    cfg.setdefault("reset_clients_without_custom_day", False)
    cfg.setdefault("clients", {})
    if write_allowed:
        save_config(config)

    while True:
        clear_screen()
        title("x-ui 增强套件 - 入站重置设置")
        print(f"{paint('ID：', 'cyan')}{paint(iid, 'white')}")
        print(f"{paint('端口：', 'cyan')}{paint(str(inbound['port']), 'white')}")
        print(f"{paint('备注：', 'cyan')}{paint(inbound['remark'] or '无备注', 'white')}")
        print()
        print(f"{paint('自定义重置：', 'cyan')}{status_value(cfg.get('enabled'), '启用', '停用')}")
        print(f"{paint('重置日：', 'cyan')}{paint('每月 ' + str(cfg.get('day', config.get('default_day', 1))) + ' 号', 'white')}")
        print(f"{paint('入站自身流量：', 'cyan')}{paint('重置 up/down', 'green') if cfg.get('reset_inbound', True) else paint('不重置', 'yellow')}")
        print(f"{paint('未单独设置日的客户端：', 'cyan')}{paint('跟随入站重置', 'green') if cfg.get('reset_clients_without_custom_day', False) else paint('不跟随入站', 'yellow')}")
        if inbound["traffic_reset"] == "monthly":
            print()
            print(paint("提醒：面板原生 monthly 仍启用，请在 3x-ui 面板中改为 never/不重置。", "yellow"))
        separator()
        menu_line(1, "停用该入站自定义重置" if cfg.get("enabled") else "启用该入站自定义重置")
        menu_line(2, "修改入站重置日")
        menu_line(3, "不重置入站自身 up/down" if cfg.get("reset_inbound", True) else "重置入站自身 up/down")
        menu_line(4, "未单独设置日的客户端不跟随入站" if cfg.get("reset_clients_without_custom_day", False) else "未单独设置日的客户端跟随入站")
        menu_line(5, "设置客户端单独重置日")
        separator()
        print(f" {paint('0/q.', 'red')} 返回入站列表")
        print(paint("================================================", "cyan"))

        choice = input_choice("请选择 [0-5]：", {"0", "q", "Q", "1", "2", "3", "4", "5"})
        if choice in {"0", "q", "Q"}:
            return
        if choice in {"1", "2", "3", "4"} and not require_config_write():
            continue
        if choice == "1":
            cfg["enabled"] = not cfg.get("enabled", False)
        elif choice == "2":
            cfg["day"] = ask_day("设置入站重置日 [1-31]：")
        elif choice == "3":
            cfg["reset_inbound"] = not cfg.get("reset_inbound", True)
        elif choice == "4":
            cfg["reset_clients_without_custom_day"] = not cfg.get("reset_clients_without_custom_day", False)
        elif choice == "5":
            # 客户端子菜单在其内部已按需保存；此处跳过保存，
            # 避免只读模式下反复弹出“禁止写入”的提示
            manage_clients(iid, cfg)
            continue
        save_config(config)

def choose_inbound():
    while True:
        clear_screen()
        title("x-ui 增强套件 - 配置入站重置规则")

        if not inbounds:
            print(paint("未读取到入站。", "yellow"))
        for idx, inbound in enumerate(inbounds, start=1):
            iid = str(inbound["id"])
            cfg = config.get("inbounds", {}).get(iid, {})
            enabled = status_value(cfg.get("enabled"))
            day = cfg.get("day", config.get("default_day", 1))
            print(f" {paint(str(idx) + '.', 'cyan')} ID={paint(iid, 'white')}  端口={paint(str(inbound['port']), 'white')}  备注={paint(trunc(inbound['remark']), 'white')}")
            print(f"    自定义重置：{enabled}  重置日：{paint('每月 ' + str(day) + ' 号', 'green')}")
            if inbound["traffic_reset"] == "monthly":
                print(f"    面板原生：{paint('monthly', 'red')}  {paint('警告：请在面板中改为 never/不重置', 'yellow')}")
            else:
                print(f"    面板原生：{paint(inbound['traffic_reset'] or 'unknown', 'white')}")
            print()

        separator()
        print(f" {paint('0/q.', 'red')} 返回自定义重置")
        print(paint("================================================", "cyan"))

        valid = {"0", "q", "Q"} | {str(i) for i in range(1, len(inbounds) + 1)}
        choice = input_choice(f"请选择入站 [0-{len(inbounds)}]：", valid)
        if choice in {"0", "q", "Q"}:
            return
        manage_inbound(inbounds[int(choice) - 1])

while True:
    clear_screen()
    title("x-ui 增强套件 - 自定义流量重置")
    print(f"{paint('自动重置：', 'cyan')}{status_value(config.get('enabled'), '启用', '停用')}")
    print(f"{paint('默认重置日：', 'cyan')}{paint('每月 ' + str(config.get('default_day', 1)) + ' 号', 'white')}")
    print(f"{paint('自动检查：', 'cyan')}{status_value(timer_status(), '已启用', '未启用')}")
    print()
    if not write_allowed:
        print(paint(f"兼容性：当前 3x-ui v{detected_version} 不在支持范围内，或数据库表/字段关键字未通过检查。", "yellow"))
        print(paint("当前只允许查看配置和预览，不允许修改配置或启用自动重置。", "yellow"))
        print()
    print(paint("使用前请在 3x-ui 面板中将对应入站的原生 monthly 改为 never/不重置。", "yellow"))
    print(paint("首次使用先选 [4] 预览；预览后输入 n 可取消执行。", "yellow"))
    separator()
    menu_line(1, "停用自动重置" if config.get("enabled") else "启用自动重置")
    menu_line(2, "修改默认重置日", f"当前：每月 {config.get('default_day', 1)} 号")
    menu_line(3, "配置入站和客户端")
    menu_line(4, "预览本次重置", "预览后可确认执行")
    menu_line(5, "查看配置 JSON")
    separator()
    print(f" {paint('0/q.', 'red')} 返回主菜单")
    print(paint("================================================", "cyan"))

    choice = input_choice("请选择 [0-5]：", {"0", "q", "Q", "1", "2", "3", "4", "5"})
    if choice in {"0", "q", "Q"}:
        sys.exit(0)
    if choice == "1":
        if not require_config_write():
            continue
        action = "关闭" if config.get("enabled", False) else "开启"
        try:
            answer = input(f"确认{action}自动重置？将同步{'停用' if action == '关闭' else '安装并启动'}检查 timer。[Y/n]: ").strip().lower() or "y"
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            continue
        if answer not in {"y", "yes"}:
            continue
        config["enabled"] = not config.get("enabled", False)
        save_config(config)
        sys.exit(200 if config["enabled"] else 201)
    if choice == "2":
        if not require_config_write():
            continue
        config["default_day"] = ask_day("设置默认重置日 [1-31]：")
        save_config(config)
    elif choice == "3":
        choose_inbound()
    elif choice == "4":
        sys.exit(202)
    elif choice == "5":
        show_config()
PY

    set +e
    XUI_DB="$XUI_DB" CONFIG_FILE="$CONFIG_FILE" XUI_WRITE_ALLOWED="$xui_write_allowed" XUI_SUPPORTED_VERSION_RANGES="$XUI_SUPPORTED_VERSION_RANGES" XUI_DETECTED_VERSION="$detected_version" python3 "$tmp_py" </dev/tty
    local ret=$?
    rm -f "$tmp_py"
    trap - RETURN
    set -e

    case "$ret" in
        0|100)
            return 0
            ;;
        200)
            if ensure_reset_timer_installed; then
                echo "自定义重置已启用，自动检查已安装并启动。"
                echo "timer 状态：$(timer_active_status)"
            else
                echo "错误：自定义重置已启用，但自动检查安装或启动失败。"
                echo "你仍然可以使用“预览并手动执行一次重置检查”手动执行。"
            fi
            pause
            ;;
        201)
            disable_reset_timer
            echo "自定义重置已禁用，自动检查 timer 已停用。"
            echo "配置文件未删除：$CONFIG_FILE"
            pause
            ;;
        202)
            run_reset_check_interactive
            ;;
        *)
            echo "自定义重置菜单异常退出，状态码：$ret"
            pause
            ;;
    esac
}

run_traffic_ui() {
    install_runtime_deps
    need_tty || return 1

    local writes_file tmp_py
    writes_file="$(mktemp)"
    tmp_py="$(mktemp --suffix=.py)"
    trap 'rm -f "$tmp_py" "$writes_file"' RETURN

    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

db_path = os.environ.get("XUI_DB", "/etc/x-ui/x-ui.db")
writes_file = os.environ["WRITES_FILE"]
GIB = Decimal(1024) ** 3

ANSI = {
    "red": "\033[0;31m",
    "green": "\033[1;32m",
    "yellow": "\033[1;33m",
    "blue": "\033[1;34m",
    "cyan": "\033[1;36m",
    "white": "\033[1;37m",
    "bold": "\033[1m",
    "plain": "\033[0m",
}

def paint(text, color):
    return f"{ANSI[color]}{text}{ANSI['plain']}"

def title(text):
    print(paint("================================================", "cyan"))
    print(paint(text, "bold"))
    print(paint("================================================", "cyan"))

def separator():
    print(paint("------------------------------------------------", "blue"))

def menu_line(number, label, hint=""):
    line = f" {paint(str(number) + '.', 'cyan')} {paint(label, 'green')}"
    if hint:
        line += f" {paint(hint, 'yellow')}"
    print(line)

def clear_screen():
    print("\033c", end="")

def format_gib(value):
    try:
        amount = Decimal(int(value or 0)) / GIB
    except Exception:
        amount = Decimal(0)
    return f"{amount.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)} GiB"

def parse_gib(raw):
    try:
        value = Decimal(raw.strip())
    except (InvalidOperation, AttributeError):
        raise ValueError("请输入有效数字")
    if value < 0:
        raise ValueError("流量不能为负数")
    return int((value * GIB).to_integral_value(rounding=ROUND_HALF_UP))

def input_choice(prompt, valid_choices):
    while True:
        try:
            choice = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        if choice in valid_choices:
            return choice
        print("无效选择，请重新输入。")

def ask_gib(prompt):
    while True:
        try:
            return parse_gib(input(prompt))
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        except ValueError as exc:
            print(f"输入无效：{exc}")

def trunc(text, limit=20):
    text = text or "无备注"
    return text if len(text) <= limit else text[:limit] + "..."

def table_columns(conn, table):
    try:
        return {row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    except sqlite3.OperationalError:
        return set()

def has_normalized_clients(conn):
    return (
        {"id", "email"} <= table_columns(conn, "clients")
        and {"client_id", "inbound_id"} <= table_columns(conn, "client_inbounds")
    )

def load_clients_for_inbound(conn, inbound_id):
    if has_normalized_clients(conn):
        return conn.execute(
            """
            SELECT ct.id AS id,
                   c.email AS email,
                   COALESCE(ct.up, 0) AS up,
                   COALESCE(ct.down, 0) AS down,
                   COALESCE(ct.total, 0) AS total
            FROM client_inbounds ci
            JOIN clients c ON c.id = ci.client_id
            JOIN client_traffics ct ON ct.email = c.email
            WHERE ci.inbound_id = ?
              AND COALESCE(c.email, '') <> ''
            ORDER BY c.id
            """,
            (inbound_id,),
        ).fetchall()
    try:
        return conn.execute(
            "SELECT id, email, up, down, total FROM client_traffics WHERE inbound_id=? ORDER BY id",
            (inbound_id,),
        ).fetchall()
    except sqlite3.OperationalError:
        return []

def load_rows():
    # 只读模式打开：校准界面只读展示，写库由后续独立连接完成
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    inbounds = conn.execute("SELECT id, remark, port, up, down, total FROM inbounds ORDER BY id").fetchall()
    return conn, inbounds

try:
    conn, inbounds = load_rows()
except Exception as exc:
    print(f"数据库读取失败：{exc}")
    sys.exit(1)

def build_write(target, up, down):
    before_up = int(target["up"] or 0)
    before_down = int(target["down"] or 0)
    return {
        "table": target["table"],
        "id": target["id"],
        "label": target["label"],
        "before_up": before_up,
        "before_down": before_down,
        "after_up": int(up),
        "after_down": int(down),
    }

def calibrate_target(target):
    clear_screen()
    title("x-ui 增强套件 - 设置已用流量")
    print(f"{paint('对象：', 'cyan')}{paint(target['label'], 'white')}")
    print(f"{paint('当前已用：', 'cyan')}{paint(format_gib((target['up'] or 0) + (target['down'] or 0)), 'green')}")
    print()
    print(paint("选择流量分配方式：", "yellow"))
    menu_line(1, "设置总已用流量", "全部计入 down")
    menu_line(2, "设置总已用流量", "沿用当前比例；当前为 0 时计入 down")
    menu_line(3, "分别设置 up 和 down")
    separator()
    print(f" {paint('0/q.', 'red')} 返回校准对象")
    print(paint("================================================", "cyan"))
    mode = input_choice("请选择 [0-3]：", {"0", "q", "Q", "1", "2", "3"})
    if mode in {"0", "q", "Q"}:
        return None

    cur_up = int(target["up"] or 0)
    cur_down = int(target["down"] or 0)
    cur_total = cur_up + cur_down

    if mode in ("1", "2"):
        total = ask_gib("总已用流量 [GiB]：")
        if mode == "1" or cur_total <= 0:
            new_up, new_down = 0, total
        else:
            new_up = int(Decimal(total) * Decimal(cur_up) / Decimal(cur_total))
            new_down = total - new_up
    else:
        new_up = ask_gib("上传流量 up [GiB]：")
        new_down = ask_gib("下载流量 down [GiB]：")

    return build_write(target, new_up, new_down)

while True:
    clear_screen()
    title("x-ui 增强套件 - 校准已用流量")
    print(paint("只修改已用流量 up/down，不修改流量上限 total。单位：GiB。", "yellow"))
    separator()

    if not inbounds:
        print(paint("当前没有入站。", "yellow"))
    for idx, inbound in enumerate(inbounds, start=1):
        used = int(inbound["up"] or 0) + int(inbound["down"] or 0)
        total = int(inbound["total"] or 0)
        total_text = format_gib(total) if total > 0 else "不限量"
        print(f" {paint(str(idx) + '.', 'cyan')} ID={paint(str(inbound['id']), 'white')}  端口={paint(str(inbound['port']), 'white')}  备注={paint(trunc(inbound['remark']), 'white')}")
        print(f"    已用：{paint(format_gib(used), 'green')} / 上限：{paint(total_text, 'yellow' if total <= 0 else 'white')}")
        print()

    separator()
    print(f" {paint('0/q.', 'red')} 返回主菜单")
    print(paint("================================================", "cyan"))

    valid_inbounds = {"0", "q", "Q"} | {str(i) for i in range(1, len(inbounds) + 1)}
    choice = input_choice(f"请选择入站 [0-{len(inbounds)}]：", valid_inbounds)
    if choice in {"0", "q", "Q"}:
        sys.exit(100)

    inbound = inbounds[int(choice) - 1]
    inbound_id = inbound["id"]

    clients = load_clients_for_inbound(conn, inbound_id)

    while True:
        clear_screen()
        title("x-ui 增强套件 - 选择校准对象")
        print(f"{paint('入站 ID：', 'cyan')}{paint(str(inbound_id), 'white')}")
        print(f"{paint('端口：', 'cyan')}{paint(str(inbound['port']), 'white')}")
        print(f"{paint('备注：', 'cyan')}{paint(inbound['remark'] or '无备注', 'white')}")
        separator()

        inbound_used = int(inbound["up"] or 0) + int(inbound["down"] or 0)
        menu_line(1, "入站自身")
        print(f"    已用：{paint(format_gib(inbound_used), 'green')}")
        print()

        for idx, client in enumerate(clients, start=2):
            used = int(client["up"] or 0) + int(client["down"] or 0)
            total = int(client["total"] or 0)
            total_text = format_gib(total) if total > 0 else "不限量"
            print(f" {paint(str(idx) + '.', 'cyan')} {paint(client['email'] or '无邮箱', 'white')}")
            print(f"    已用：{paint(format_gib(used), 'green')} / 上限：{paint(total_text, 'yellow' if total <= 0 else 'white')}")
            print()

        all_clients_choice = str(len(clients) + 2)
        if clients:
            menu_line(all_clients_choice, "逐个校准全部客户端")
        separator()
        print(f" {paint('0/q.', 'red')} 返回入站列表")
        print(paint("================================================", "cyan"))

        valid_objects = {"0", "q", "Q", "1"} | {str(i) for i in range(2, len(clients) + 2)}
        if clients:
            valid_objects.add(all_clients_choice)

        obj_choice = input_choice(f"请选择对象 [0-{all_clients_choice if clients else len(clients) + 1}]：", valid_objects)
        if obj_choice in {"0", "q", "Q"}:
            break

        targets = []
        if obj_choice == "1":
            targets.append({
                "table": "inbounds",
                "id": inbound_id,
                "label": f"入站 ID={inbound_id}",
                "up": inbound["up"],
                "down": inbound["down"],
            })
        elif clients and obj_choice == all_clients_choice:
            for client in clients:
                targets.append({
                    "table": "client_traffics",
                    "id": client["id"],
                    "label": client["email"] or f"客户端 ID={client['id']}",
                    "up": client["up"],
                    "down": client["down"],
                })
        else:
            client = clients[int(obj_choice) - 2]
            targets.append({
                "table": "client_traffics",
                "id": client["id"],
                "label": client["email"] or f"客户端 ID={client['id']}",
                "up": client["up"],
                "down": client["down"],
            })

        writes = []
        for target in targets:
            write = calibrate_target(target)
            if write is None:
                writes = []
                break
            writes.append(write)

        if not writes:
            continue

        clear_screen()
        title("x-ui 增强套件 - 确认流量校准")
        print(paint("以下操作只会修改 up/down，不会修改 total。", "yellow"))
        print(paint("写库前会自动备份数据库，并重启 x-ui。", "yellow"))
        separator()
        for write in writes:
            before_total = write["before_up"] + write["before_down"]
            after_total = write["after_up"] + write["after_down"]
            print(f"{paint('对象：', 'cyan')}{paint(write['label'], 'white')}")
            print(f"  修改前：up {paint(format_gib(write['before_up']), 'yellow')} / down {paint(format_gib(write['before_down']), 'yellow')} / 合计 {paint(format_gib(before_total), 'yellow')}")
            print(f"  修改后：up {paint(format_gib(write['after_up']), 'green')} / down {paint(format_gib(write['after_down']), 'green')} / 合计 {paint(format_gib(after_total), 'green')}")
            print()
        try:
            answer = input("确认写入数据库？[Y/n]: ").strip().lower() or "y"
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        if answer not in {"y", "yes"}:
            print("已取消，没有写入数据库。")
            sys.exit(100)

        with open(writes_file, "w", encoding="utf-8") as f:
            json.dump(writes, f, ensure_ascii=False)
        sys.exit(200)
PY

    set +e
    XUI_DB="$XUI_DB" WRITES_FILE="$writes_file" python3 "$tmp_py" </dev/tty
    local ret=$?
    rm -f "$tmp_py"
    set -e

    if [ "$ret" -eq 100 ]; then
        rm -f "$writes_file"
        trap - RETURN
        return 0
    fi
    if [ "$ret" -ne 200 ]; then
        rm -f "$writes_file"
        echo "流量校准已取消或失败。"
        pause
        trap - RETURN
        return 0
    fi

    require_verified_xui_for_write || {
        rm -f "$writes_file"
        pause
        trap - RETURN
        return 1
    }

    echo "正在备份数据库..."
    local db_backup
    db_backup="$(backup_database)" || {
        rm -f "$writes_file"
        pause
        trap - RETURN
        return 1
    }
    echo "数据库备份：$db_backup"

    echo "停止 x-ui..."
    systemctl stop x-ui || true

    set +e
    XUI_DB="$XUI_DB" WRITES_FILE="$writes_file" python3 <<'PY'
import json
import os
import sqlite3
import sys

db_path = os.environ["XUI_DB"]
writes_file = os.environ["WRITES_FILE"]

try:
    with open(writes_file, "r", encoding="utf-8") as f:
        writes = json.load(f)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("BEGIN")
    for write in writes:
        table = write["table"]
        if table not in {"inbounds", "client_traffics"}:
            raise ValueError(f"非法表名：{table}")
        cur.execute(f"UPDATE {table} SET up=?, down=? WHERE id=?", (write["after_up"], write["after_down"], write["id"]))
        if cur.rowcount <= 0:
            raise RuntimeError(f"未找到对象：{write['label']}")
    conn.commit()
    print("写入成功。")
except Exception as exc:
    try:
        conn.rollback()
    except Exception:
        pass
    print(f"写入失败：{exc}")
    sys.exit(1)
finally:
    try:
        conn.close()
    except Exception:
        pass
PY
    local write_ret=$?
    set -e

    rm -f "$writes_file"
    trap - RETURN
    echo "启动 x-ui..."
    systemctl start x-ui || true

    if [ "$write_ret" -eq 0 ]; then
        echo "流量校准完成。"
    else
        echo "流量校准失败，数据库已保留写入前备份：$db_backup"
    fi
    pause
}

run_reset_engine() {
    install_runtime_deps
    ensure_dirs
    if [ "$DRY_RUN" -ne 1 ]; then
        require_verified_xui_for_write || return 1
    fi

    XUI_DB="$XUI_DB" \
    CONFIG_FILE="$CONFIG_FILE" \
    RESET_STATE="$RESET_STATE" \
    BACKUP_DIR="$BACKUP_DIR" \
    DRY_RUN="$DRY_RUN" \
    PLAN_COUNT_FILE="${PLAN_COUNT_FILE:-}" \
    python3 <<'PY'
import calendar
import json
import os
import sqlite3
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

db_path = Path(os.environ["XUI_DB"])
config_path = Path(os.environ["CONFIG_FILE"])
state_path = Path(os.environ["RESET_STATE"])
backup_dir = Path(os.environ["BACKUP_DIR"])
dry_run = os.environ.get("DRY_RUN") == "1"
plan_count_file = os.environ.get("PLAN_COUNT_FILE")

today = date.today()
current_month = today.strftime("%Y-%m")

def write_plan_count(count):
    if not plan_count_file:
        return
    try:
        Path(plan_count_file).write_text(str(count), encoding="utf-8")
    except Exception:
        pass

def non_negative_int(value, default=0):
    try:
        parsed = int(value or default)
    except Exception:
        parsed = default
    return max(parsed, 0)

def load_config():
    if not config_path.exists():
        return {"enabled": False, "default_day": 1, "inbounds": {}}
    try:
        with config_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        print(f"错误：读取配置失败：{config_path}")
        print(f"原因：{exc}")
        return None
    if not isinstance(data, dict):
        print(f"错误：配置格式无效：{config_path}")
        return None
    data.setdefault("enabled", False)
    data.setdefault("default_day", 1)
    data.setdefault("inbounds", {})
    if not isinstance(data["inbounds"], dict):
        data["inbounds"] = {}
    return data

def load_state():
    if not state_path.exists():
        return {"schema_version": 2, "inbounds": {}, "clients": {}}
    try:
        with state_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        print(f"错误：读取状态文件失败：{state_path}")
        print(f"原因：{exc}")
        print("为避免重复重置，脚本不会覆盖损坏的状态文件。请手动检查或恢复备份。")
        return None
    if not isinstance(data, dict):
        print(f"错误：状态文件格式无效：{state_path}")
        return None
    if "schema_version" not in data:
        data = {
            "schema_version": 2,
            "inbounds": data.get("inbounds", {}) if isinstance(data.get("inbounds"), dict) else {},
            "clients": data.get("clients", {}) if isinstance(data.get("clients"), dict) else {},
        }
    data["schema_version"] = max(non_negative_int(data.get("schema_version", 1), 1), 2)
    data.setdefault("inbounds", {})
    data.setdefault("clients", {})
    if not isinstance(data["inbounds"], dict):
        data["inbounds"] = {}
    if not isinstance(data["clients"], dict):
        data["clients"] = {}
    for records in (data["inbounds"], data["clients"]):
        for key, record in list(records.items()):
            if not isinstance(record, dict):
                records[key] = {"traffic_totals": {"up": 0, "down": 0, "total": 0}}
                continue
            totals = record.get("traffic_totals")
            if not isinstance(totals, dict):
                totals = {}
            totals["up"] = non_negative_int(totals.get("up", 0))
            totals["down"] = non_negative_int(totals.get("down", 0))
            totals["total"] = totals["up"] + totals["down"]
            record["traffic_totals"] = totals
    return data

def save_state(data):
    state_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = state_path.with_name(state_path.name + f".tmp.{os.getpid()}")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp_path, state_path)
    os.chmod(state_path, 0o600)

def safe_day(value, fallback=1):
    try:
        day = int(value)
    except Exception:
        day = fallback
    if day < 1:
        day = fallback
    if day > 31:
        day = 31
    return day

def effective_day(configured_day):
    last_day = calendar.monthrange(today.year, today.month)[1]
    return min(safe_day(configured_day), last_day)

def should_reset(configured_day, state_record):
    day = safe_day(configured_day)
    eff = effective_day(day)
    if today.day < eff:
        return False, f"未到本月重置日：每月 {day} 号，本月有效日 {eff} 号"
    if state_record.get("last_reset_month") == current_month:
        reset_date = state_record.get("last_reset_date", "未知日期")
        return False, f"本月已在 {reset_date} 重置过"
    return True, f"每月 {day} 号，本月有效日 {eff} 号，本月尚未重置"

def truncate(text, limit=20):
    text = text or "无备注"
    return text if len(text) <= limit else text[:limit] + "..."

def connect_db():
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn

def table_columns(conn, table):
    try:
        return {row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    except sqlite3.OperationalError:
        return set()

def has_normalized_clients(conn):
    return (
        {"id", "email"} <= table_columns(conn, "clients")
        and {"client_id", "inbound_id"} <= table_columns(conn, "client_inbounds")
    )

def load_client_links(conn):
    if has_normalized_clients(conn):
        rows = conn.execute(
            """
            SELECT ci.inbound_id AS inbound_id,
                   c.email AS email
            FROM client_inbounds ci
            JOIN clients c ON c.id = ci.client_id
            WHERE COALESCE(c.email, '') <> ''
            ORDER BY ci.inbound_id, c.id
            """
        ).fetchall()
        return [dict(row) for row in rows]
    try:
        return conn.execute("SELECT inbound_id, email FROM client_traffics ORDER BY id").fetchall()
    except sqlite3.OperationalError:
        return []

def load_db_rows(conn):
    try:
        inbounds = conn.execute("SELECT id, remark, port, traffic_reset FROM inbounds ORDER BY id").fetchall()
    except sqlite3.OperationalError:
        inbounds = conn.execute("SELECT id, remark, port, 'unknown' AS traffic_reset FROM inbounds ORDER BY id").fetchall()
    clients = load_client_links(conn)
    return inbounds, clients

def build_plan(config, state, inbounds, clients):
    inbound_map = {str(row["id"]): row for row in inbounds}
    clients_by_inbound = {}
    client_lookup = set()
    for client in clients:
        iid = str(client["inbound_id"])
        email = client["email"] or ""
        clients_by_inbound.setdefault(iid, []).append(client)
        client_lookup.add((iid, email))

    plan_inbounds = []
    plan_clients = []
    skipped = []
    warnings = []
    planned_client_emails = set()
    planned_client_by_email = {}
    default_day = safe_day(config.get("default_day", 1))

    def add_client_plan(item):
        email = item.get("email") or ""
        if not email:
            skipped.append((item["label"], "客户端 email 为空，跳过"))
            return
        if email in planned_client_emails:
            skipped.append((item["label"], "同一 email 已在本次计划中处理，3x-ui 客户端流量按 email 共享"))
            # 记录被去重项的状态键：执行成功后需一并盖章，
            # 否则下次运行会因该键缺少本月记录而把共享流量再次清零
            planned = planned_client_by_email.get(email)
            if planned is not None and item.get("key") and item["key"] != planned.get("key"):
                planned.setdefault("alias_keys", []).append(item["key"])
            return
        planned_client_emails.add(email)
        planned_client_by_email[email] = item
        plan_clients.append(item)

    for iid, cfg in sorted(config.get("inbounds", {}).items(), key=lambda item: int(item[0]) if str(item[0]).isdigit() else str(item[0])):
        if not isinstance(cfg, dict) or not cfg.get("enabled", False):
            continue

        inbound = inbound_map.get(str(iid))
        if inbound is None:
            skipped.append((f"入站 ID={iid}", "入站已不存在，跳过"))
            continue

        if inbound["traffic_reset"] == "monthly":
            warnings.append(f"入站 ID={iid} 仍启用面板原生 monthly。")
            warnings.append("使用外置自定义重置日期时，请在 3x-ui 面板中改为 never/不重置。")

        inbound_day = safe_day(cfg.get("day", default_day), default_day)
        inbound_due, inbound_reason = should_reset(inbound_day, state["inbounds"].get(str(iid), {}))
        inbound_label = f"入站 ID={iid}，端口={inbound['port']}，备注={truncate(inbound['remark'])}"

        if cfg.get("reset_inbound", True):
            if inbound_due:
                plan_inbounds.append({"id": str(iid), "label": inbound_label, "reason": inbound_reason})
            else:
                skipped.append((f"入站 ID={iid}", inbound_reason))
        else:
            skipped.append((f"入站 ID={iid}", "入站自身 up/down 已设置为不重置"))

        client_rules = cfg.get("clients", {}) if isinstance(cfg.get("clients"), dict) else {}

        if cfg.get("reset_clients_without_custom_day", False):
            for client in clients_by_inbound.get(str(iid), []):
                email = client["email"] or ""
                custom_rule = client_rules.get(email, {})
                if isinstance(custom_rule, dict) and custom_rule.get("enabled") and safe_day(custom_rule.get("day", 0), 0) > 0:
                    continue
                key = f"{iid}|{email}"
                due, reason = should_reset(inbound_day, state["clients"].get(key, {}))
                label = f"客户端 {email or '无邮箱'}，入站 ID={iid}"
                if due:
                    add_client_plan({"inbound_id": str(iid), "email": email, "key": key, "label": label, "reason": f"跟随入站，{reason}", "reset_scope": "inbound"})
                else:
                    skipped.append((label, reason))

        for email, ccfg in sorted(client_rules.items()):
            if not isinstance(ccfg, dict) or not ccfg.get("enabled", True):
                continue
            cday = safe_day(ccfg.get("day", 0), 0)
            if cday <= 0:
                continue
            key_tuple = (str(iid), email)
            label = f"客户端 {email or '无邮箱'}，入站 ID={iid}"
            if key_tuple not in client_lookup:
                skipped.append((label, "客户端已不存在，跳过"))
                continue
            key = f"{iid}|{email}"
            due, reason = should_reset(cday, state["clients"].get(key, {}))
            if due:
                add_client_plan({"inbound_id": str(iid), "email": email, "key": key, "label": label, "reason": f"客户端单独日期，{reason}", "reset_scope": "client"})
            else:
                skipped.append((label, reason))

    return plan_inbounds, plan_clients, skipped, warnings

def print_preview(plan_inbounds, plan_clients, skipped, warnings):
    print("================================================")
    print("本次重置预览")
    print("================================================")
    print(f"日期：{today.isoformat()}")
    print("模式：预览模式，只预览，不写数据库")
    print("说明：真实执行时只重置本月 up/down；客户端会按官方逻辑重新启用；不修改 all_time 和 total")
    print()
    if not plan_inbounds and not plan_clients:
        print("本次没有需要重置的入站或客户端。")
    else:
        print("将重置：")
        for item in plan_inbounds:
            print(f"  {item['label']}")
            print(f"    原因：{item['reason']}")
            print()
        for item in plan_clients:
            print(f"  {item['label']}")
            print(f"    原因：{item['reason']}")
            print()
    print("不会重置：")
    if not skipped:
        print("  无")
    else:
        for label, reason in skipped:
            print(f"  {label}")
            print(f"    原因：{reason}")
    if warnings:
        print()
        print("提醒：")
        seen = set()
        for warning in warnings:
            if warning in seen:
                continue
            seen.add(warning)
            print(f"  {warning}")
    print("================================================")

def backup_database():
    backup_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(backup_dir, 0o700)
    backup_path = backup_dir / f"x-ui.db.{time.strftime('%Y-%m-%d_%H%M%S')}.bak"
    src = sqlite3.connect(db_path)
    dst = sqlite3.connect(backup_path)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    os.chmod(backup_path, 0o600)
    return backup_path

def quick_health():
    print()
    print("简短健康检查：")
    active = subprocess.run(["systemctl", "is-active", "--quiet", "x-ui"]).returncode == 0
    print(f"  x-ui 服务：{'运行中' if active else '未运行'}")
    try:
        conn = sqlite3.connect(db_path)
        result = conn.execute("PRAGMA integrity_check;").fetchone()[0]
        conn.close()
        print(f"  数据库完整性：{result}")
    except Exception as exc:
        print(f"  数据库完整性：检查失败：{exc}")

def add_preserved_traffic(state_record, up, down):
    totals = state_record.setdefault("traffic_totals", {})
    previous_up = non_negative_int(totals.get("up", 0))
    previous_down = non_negative_int(totals.get("down", 0))
    up = non_negative_int(up)
    down = non_negative_int(down)
    totals["up"] = previous_up + up
    totals["down"] = previous_down + down
    totals["total"] = totals["up"] + totals["down"]
    return totals

def get_table_columns(cur, table):
    try:
        return {row[1] for row in cur.execute(f"PRAGMA table_info({table})").fetchall()}
    except Exception:
        return set()

def execute_plan(plan_inbounds, plan_clients, state):
    print("准备执行自定义重置...")
    backup_path = backup_database()
    print(f"数据库备份：{backup_path}")

    service_stopped = False
    conn = None
    updated_inbounds = []
    updated_clients = []
    skipped_write = []

    try:
        subprocess.run(["systemctl", "stop", "x-ui"], check=False)
        service_stopped = True

        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("BEGIN")
        inbound_columns = get_table_columns(cur, "inbounds")
        client_columns = get_table_columns(cur, "client_traffics")
        reset_time_ms = int(time.time() * 1000)
        inbounds_to_mark = set()
        reset_client_emails = set()

        for item in plan_inbounds:
            row = cur.execute("SELECT up, down FROM inbounds WHERE id=?", (item["id"],)).fetchone()
            if row is None:
                skipped_write.append((item["label"], "写入时入站已不存在"))
                continue
            cur.execute("UPDATE inbounds SET up=0, down=0 WHERE id=?", (item["id"],))
            if cur.rowcount > 0:
                item["preserved_totals"] = add_preserved_traffic(
                    state["inbounds"].setdefault(item["id"], {}),
                    row[0],
                    row[1],
                )
                updated_inbounds.append(item)
                inbounds_to_mark.add(item["id"])
            else:
                skipped_write.append((item["label"], "写入时入站已不存在"))

        for item in plan_clients:
            if item["email"] in reset_client_emails:
                skipped_write.append((item["label"], "同一 email 已在本次执行中重置"))
                continue
            row = cur.execute("SELECT up, down FROM client_traffics WHERE email=?", (item["email"],)).fetchone()
            if row is None:
                skipped_write.append((item["label"], "写入时客户端已不存在"))
                continue
            if "enable" in client_columns:
                cur.execute(
                    "UPDATE client_traffics SET enable=1, up=0, down=0 WHERE email=?",
                    (item["email"],),
                )
            else:
                cur.execute(
                    "UPDATE client_traffics SET up=0, down=0 WHERE email=?",
                    (item["email"],),
                )
            if cur.rowcount > 0:
                reset_client_emails.add(item["email"])
                item["preserved_totals"] = add_preserved_traffic(
                    state["clients"].setdefault(item["key"], {}),
                    row[0],
                    row[1],
                )
                updated_clients.append(item)
                if item.get("reset_scope") == "inbound":
                    inbounds_to_mark.add(item["inbound_id"])
            else:
                skipped_write.append((item["label"], "写入时客户端已不存在"))

        if "last_traffic_reset_time" in inbound_columns:
            for inbound_id in sorted(inbounds_to_mark, key=lambda value: int(value) if str(value).isdigit() else str(value)):
                cur.execute(
                    "UPDATE inbounds SET last_traffic_reset_time=? WHERE id=?",
                    (reset_time_ms, inbound_id),
                )

        conn.commit()

        for item in updated_inbounds:
            state["inbounds"].setdefault(item["id"], {}).update({"last_reset_month": current_month, "last_reset_date": today.isoformat()})
        for item in updated_clients:
            state["clients"].setdefault(item["key"], {}).update({"last_reset_month": current_month, "last_reset_date": today.isoformat()})
            # 同一 email 在其他入站下的状态键一并盖章，防止次日重复重置共享流量
            for alias_key in item.get("alias_keys", []):
                state["clients"].setdefault(alias_key, {}).update({"last_reset_month": current_month, "last_reset_date": today.isoformat()})
        save_state(state)

        if updated_inbounds or updated_clients:
            print("重置完成：")
            for item in updated_inbounds:
                print(f"  {item['label']}，累计历史总流量已保留 {item['preserved_totals']['total']} bytes")
            for item in updated_clients:
                print(f"  {item['label']}，累计历史总流量已保留 {item['preserved_totals']['total']} bytes")
        else:
            print("没有对象被写入，状态文件未新增记录。")
        for label, reason in skipped_write:
            print(f"跳过：{label}，{reason}")
        return 0
    except Exception as exc:
        if conn is not None:
            try:
                conn.rollback()
            except Exception:
                pass
        print(f"执行失败：{exc}")
        return 1
    finally:
        if conn is not None:
            conn.close()
        if service_stopped:
            subprocess.run(["systemctl", "start", "x-ui"], check=False)
        quick_health()

def main():
    config = load_config()
    if config is None:
        write_plan_count(0)
        return 1

    if not config.get("enabled", False):
        if dry_run:
            print("================================================")
            print("本次重置预览")
            print("================================================")
            print(f"日期：{today.isoformat()}")
            print("模式：预览模式，只预览，不写数据库")
            print("说明：真实执行时只重置本月 up/down；客户端会按官方逻辑重新启用；不修改 all_time 和 total")
            print()
            print("自定义重置已禁用，跳过。")
            print("================================================")
        else:
            print("自定义重置已禁用，跳过。")
        write_plan_count(0)
        return 0

    state = load_state()
    if state is None:
        write_plan_count(0)
        return 1

    if not db_path.exists():
        print(f"错误：数据库不存在：{db_path}")
        write_plan_count(0)
        return 1

    try:
        conn = connect_db()
        inbounds, clients = load_db_rows(conn)
        conn.close()
    except Exception as exc:
        print(f"数据库读取失败：{exc}")
        write_plan_count(0)
        return 1

    plan_inbounds, plan_clients, skipped, warnings = build_plan(config, state, inbounds, clients)
    plan_count = len(plan_inbounds) + len(plan_clients)
    write_plan_count(plan_count)

    if dry_run:
        print_preview(plan_inbounds, plan_clients, skipped, warnings)
        return 0

    for warning in warnings:
        print(f"提醒：{warning}")

    if plan_count == 0:
        print("本次没有需要重置的对象。")
        return 0

    return execute_plan(plan_inbounds, plan_clients, state)

try:
    sys.exit(main())
except KeyboardInterrupt:
    print("已取消。")
    sys.exit(100)
except Exception as exc:
    print(f"执行异常：{exc}")
    sys.exit(1)
PY
}

run_reset_check_interactive() {
    clear_screen

    local count_file count
    count_file="$(mktemp)"

    set +e
    PLAN_COUNT_FILE="$count_file" DRY_RUN=1 run_reset_engine
    local dry_ret=$?
    set -e

    count="0"
    if [ -f "$count_file" ]; then
        count="$(tr -cd '0-9' < "$count_file")"
    fi
    rm -f "$count_file"
    count="${count:-0}"

    if [ "$dry_ret" -ne 0 ]; then
        echo
        echo "预览失败，未执行任何写库操作。"
        pause
        return 0
    fi

    if [ "$count" -eq 0 ]; then
        pause
        return 0
    fi

    echo
    local answer
    read -rp "确认按以上计划执行重置？[Y/n]: " answer || answer=""
    answer="${answer:-yes}"
    if [[ ! "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "已取消，没有写入数据库。"
        pause
        return 0
    fi

    echo
    DRY_RUN=0 run_reset_engine || true
    pause
}

collect_db_ports() {
    if [ ! -f "$XUI_DB" ]; then
        return 0
    fi

    XUI_DB="$XUI_DB" python3 <<'PY' 2>/dev/null || true
import os
import sqlite3

db_path = os.environ["XUI_DB"]
conn = sqlite3.connect(db_path)
cols = [row[1] for row in conn.execute("PRAGMA table_info(inbounds)").fetchall()]
if "port" not in cols:
    raise SystemExit(0)
if "enable" in cols:
    rows = conn.execute("SELECT port FROM inbounds WHERE enable=1").fetchall()
else:
    rows = conn.execute("SELECT port FROM inbounds").fetchall()
for (port,) in rows:
    try:
        port = int(port)
    except Exception:
        continue
    if port > 0:
        print(port)
conn.close()
PY
}

collect_process_ports() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnpH 2>/dev/null \
            | awk '/x-ui|3x-ui/ {print $4}' \
            | awk -F: '{print $NF}' \
            | grep -E '^[0-9]+$' || true
    fi
}

port_is_listening() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    fi

    return 2
}

print_monthly_conflicts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$XUI_DB" ]; then
        echo "monthly 冲突：未发现"
        return 0
    fi

    XUI_DB="$XUI_DB" CONFIG_FILE="$CONFIG_FILE" python3 <<'PY' 2>/dev/null || true
import json
import os
import sqlite3

db_path = os.environ["XUI_DB"]
config_path = os.environ["CONFIG_FILE"]

try:
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
except Exception:
    print("monthly 冲突：配置读取失败")
    raise SystemExit(0)

enabled_ids = [str(k) for k, v in config.get("inbounds", {}).items() if isinstance(v, dict) and v.get("enabled")]
if not enabled_ids:
    print("monthly 冲突：未发现")
    raise SystemExit(0)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
try:
    rows = conn.execute("SELECT id, remark, traffic_reset FROM inbounds").fetchall()
except sqlite3.OperationalError:
    rows = []
conflicts = [row for row in rows if str(row["id"]) in enabled_ids and row["traffic_reset"] == "monthly"]
conn.close()

if not conflicts:
    print("monthly 冲突：未发现")
else:
    print("monthly 冲突：发现提醒")
    for row in conflicts:
        remark = row["remark"] or "无备注"
        if len(remark) > 20:
            remark = remark[:20] + "..."
        print(f"  入站 ID={row['id']} 备注={remark}")
    print("  建议：请在 3x-ui 面板中关闭原生 monthly，改为 never/不重置。")
PY
}

print_health_report() {
    install_runtime_deps

    print_xui_version_warning

    echo "x-ui 服务："
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "  ${GREEN}运行中${PLAIN}"
    else
        echo -e "  ${RED}未运行${PLAIN}"
    fi

    echo "数据库文件："
    if [ -f "$XUI_DB" ]; then
        echo -e "  ${GREEN}存在：$XUI_DB${PLAIN}"
        local integrity
        integrity="$(sqlite3 "$XUI_DB" "PRAGMA integrity_check;" 2>&1 || true)"
        if [ "$integrity" = "ok" ]; then
            echo -e "  ${GREEN}完整性：ok${PLAIN}"
        else
            echo -e "  ${RED}完整性异常：$integrity${PLAIN}"
        fi
        local schema_result
        if schema_result="$(check_xui_db_schema_readonly 2>&1)"; then
            echo -e "  ${GREEN}字段兼容：ok${PLAIN}"
        else
            echo -e "  ${RED}字段兼容异常：$schema_result${PLAIN}"
        fi
    else
        echo -e "  ${RED}缺失：$XUI_DB${PLAIN}"
    fi

    echo "本地执行器："
    if [ -x "$LOCAL_RUNNER" ]; then
        echo -e "  ${GREEN}已安装：$LOCAL_RUNNER${PLAIN}"
    else
        echo -e "  ${YELLOW}未安装：$LOCAL_RUNNER${PLAIN}"
    fi

    echo "xcm："
    if [ -x "$XCM_PATH" ]; then
        echo -e "  ${GREEN}已注册：$XCM_PATH${PLAIN}"
    else
        echo -e "  ${YELLOW}未注册：$XCM_PATH${PLAIN}"
    fi

    echo "自动检查 timer："
    if [ -f "$RESET_TIMER" ]; then
        echo "  文件：存在"
    else
        echo "  文件：不存在"
    fi
    echo "  enabled：$(timer_enabled_status)"
    echo "  active：$(timer_active_status)"

    echo "端口监听："
    local ports=()
    mapfile -t ports < <({ collect_db_ports; collect_process_ports; } | sort -n | uniq)
    if [ "${#ports[@]}" -eq 0 ]; then
        echo "  未从数据库读取到入站端口。"
    else
        local port
        for port in "${ports[@]}"; do
            if port_is_listening "$port"; then
                echo -e "  ${GREEN}$port 已监听${PLAIN}"
            else
                echo -e "  ${YELLOW}$port 未监听，请检查 x-ui / xray 服务${PLAIN}"
            fi
        done
    fi

    print_monthly_conflicts

    echo "最近日志关键词："
    local log_hit=0
    if [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" | grep -Eiq "panic|error|failed|no such column"; then
        log_hit=1
    fi
    if journalctl -u x-ui -n 100 --no-pager 2>/dev/null | grep -Eiq "panic|error|failed|no such column"; then
        log_hit=1
    fi
    if [ "$log_hit" -eq 1 ]; then
        echo -e "  ${YELLOW}发现错误关键词，请进入 [5] 查看日志。${PLAIN}"
    else
        echo -e "  ${GREEN}未发现明显错误关键词。${PLAIN}"
    fi

    echo "预览入口："
    echo "  [1] 自定义流量重置 -> [4] 预览本次重置"
}

run_self_test() {
    local failures=0
    local self_path detected_version

    self_path="$(readlink -f "${BASH_SOURCE[0]}")"

    selftest_pass() {
        echo "PASS: $*"
    }
    selftest_fail() {
        echo "FAIL: $*"
        failures=$((failures + 1))
    }
    selftest_warn() {
        echo "WARN: $*"
    }

    echo "xui-custom-manager self-test"
    echo "========================================"

    if bash -n "$self_path"; then
        selftest_pass "当前脚本 bash -n 通过"
    else
        selftest_fail "当前脚本 bash -n 未通过"
    fi

    if command -v python3 >/dev/null 2>&1; then
        selftest_pass "python3 存在：$(command -v python3)"
    else
        selftest_fail "python3 不存在"
    fi

    if command -v sqlite3 >/dev/null 2>&1; then
        selftest_pass "sqlite3 存在：$(command -v sqlite3)"
    else
        selftest_fail "sqlite3 不存在"
    fi

    detected_version="$(detect_xui_version)"
    echo "检测到的 3x-ui 版本：$detected_version"
    echo "支持版本范围：$(format_supported_version_ranges)"
    if xui_version_is_supported "$detected_version"; then
        selftest_pass "3x-ui 版本在支持范围内"
    else
        selftest_fail "写库功能不可用：当前 3x-ui 版本不在支持范围内"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        if command -v python3 >/dev/null 2>&1 && CONFIG_FILE="$CONFIG_FILE" python3 <<'PY'
import json
import os

with open(os.environ["CONFIG_FILE"], "r", encoding="utf-8") as f:
    json.load(f)
PY
        then
            selftest_pass "配置文件 JSON 可解析：$CONFIG_FILE"
        else
            selftest_fail "配置文件 JSON 解析失败：$CONFIG_FILE"
        fi
    else
        selftest_warn "配置文件不存在，跳过 JSON 检查：$CONFIG_FILE"
    fi

    if [ -f "$XUI_DB" ]; then
        if command -v python3 >/dev/null 2>&1 && XUI_DB="$XUI_DB" python3 <<'PY'
import os
import sqlite3
import sys

db_path = os.environ["XUI_DB"]
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    result = conn.execute("PRAGMA integrity_check;").fetchone()[0]
    print(result)
    if result != "ok":
        sys.exit(1)
finally:
    conn.close()
PY
        then
            selftest_pass "数据库只读 integrity_check 可执行：$XUI_DB"
        else
            selftest_fail "数据库只读 integrity_check 失败：$XUI_DB"
        fi

        if check_xui_db_schema_readonly; then
            selftest_pass "数据库关键字段兼容"
        else
            selftest_fail "数据库关键字段不兼容"
        fi
    else
        selftest_warn "数据库不存在，跳过只读 integrity/schema 检查：$XUI_DB"
    fi

    if [ -e "$LOCAL_RUNNER" ]; then
        if [ -x "$LOCAL_RUNNER" ]; then
            selftest_pass "LOCAL_RUNNER 可执行：$LOCAL_RUNNER"
        else
            selftest_fail "LOCAL_RUNNER 存在但不可执行：$LOCAL_RUNNER"
        fi
        if bash -n "$LOCAL_RUNNER"; then
            selftest_pass "LOCAL_RUNNER bash -n 通过"
        else
            selftest_fail "LOCAL_RUNNER bash -n 未通过"
        fi
    else
        selftest_warn "LOCAL_RUNNER 不存在：$LOCAL_RUNNER"
    fi

    if [ -e "$XCM_PATH" ]; then
        if [ -x "$XCM_PATH" ]; then
            selftest_pass "XCM_PATH 可执行：$XCM_PATH"
        else
            selftest_fail "XCM_PATH 存在但不可执行：$XCM_PATH"
        fi
        if bash -n "$XCM_PATH"; then
            selftest_pass "XCM_PATH bash -n 通过"
        else
            selftest_fail "XCM_PATH bash -n 未通过"
        fi
    else
        selftest_warn "XCM_PATH 不存在：$XCM_PATH"
    fi

    echo "========================================"
    if [ "$failures" -eq 0 ]; then
        echo "PASS"
        return 0
    fi
    echo "FAIL: $failures 项失败"
    return 1
}

health_check() {
    clear_screen
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}x-ui 增强套件 - 健康检查${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    print_health_report
}

menu_logs() {
    while true; do
        clear_screen
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}x-ui 增强套件 - 日志${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}查看脚本、自动重置检查和 x-ui 服务日志。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 脚本日志${PLAIN}                  ${YELLOW}($LOG_FILE)${PLAIN}"
        echo -e "${GREEN}  2. 自动重置检查日志${PLAIN}          ${YELLOW}(仅 reset-check 记录)${PLAIN}"
        echo -e "${GREEN}  3. timer 服务日志${PLAIN}            ${YELLOW}(xui-custom-reset.service)${PLAIN}"
        echo -e "${GREEN}  4. x-ui 服务日志${PLAIN}             ${YELLOW}(x-ui.service)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0/q. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_menu_choice choice "请选择 [0-4]："

        case "$choice" in
            1)
                clear_screen
                echo "脚本日志：$LOG_FILE"
                echo "提示：这里包含历史记录，旧菜单或 read error 可能是以前版本留下的日志。"
                echo "------------------------------------------------"
                tail -n 100 "$LOG_FILE" || true
                pause
                ;;
            2)
                clear_screen
                echo "reset-check 日志：$LOG_FILE"
                echo "------------------------------------------------"
                if [ -f "$LOG_FILE" ]; then
                    local reset_log
                    reset_log="$(awk '
                        /^===== .*reset-check 执行 =====/ { printing=1; print; next }
                        /^===== / && printing { printing=0 }
                        printing { print }
                    ' "$LOG_FILE" | tail -n 120)"
                    if [ -n "$reset_log" ]; then
                        echo "$reset_log"
                    else
                        echo "暂无 reset-check 日志记录。"
                    fi
                else
                    echo "日志文件不存在。"
                fi
                pause
                ;;
            3)
                clear_screen
                echo "自动检查 timer 日志"
                echo "------------------------------------------------"
                journalctl -u xui-custom-reset.service -n 100 --no-pager || true
                pause
                ;;
            4)
                clear_screen
                echo "x-ui 服务日志"
                echo "------------------------------------------------"
                journalctl -u x-ui -n 100 --no-pager || true
                pause
                ;;
            0|q|Q)
                return 0
                ;;
            *)
                echo -e "${RED}输入无效，请输入 0-4。${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

menu_backup_restore() {
    while true; do
        clear_screen
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}x-ui 增强套件 - 备份与恢复${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}备份目录：$BACKUP_DIR${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 立即备份全部${PLAIN}              ${YELLOW}(数据库 / 配置 / 程序)${PLAIN}"
        echo -e "${GREEN}  2. 恢复数据库${PLAIN}                ${YELLOW}(覆盖当前 x-ui.db)${PLAIN}"
        echo -e "${GREEN}  3. 恢复程序目录${PLAIN}              ${YELLOW}(/usr/local/x-ui)${PLAIN}"
        echo -e "${GREEN}  4. 恢复配置目录${PLAIN}              ${YELLOW}(/etc/x-ui)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0/q. 返回主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_menu_choice choice "请选择 [0-4]："

        case "$choice" in
            1)
                clear_screen
                # 失败时函数内部已提示；|| true 防止 set -e 把整个菜单杀掉
                backup_all || true
                pause
                ;;
            2)
                restore_backup "db" || true
                pause
                ;;
            3)
                restore_backup "program" || true
                pause
                ;;
            4)
                restore_backup "etc" || true
                pause
                ;;
            0|q|Q)
                return 0
                ;;
            *)
                echo -e "${RED}输入无效，请输入 0-4。${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

show_quick_guide() {
    clear_screen
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}x-ui 增强套件 - 按目标选择${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo "  设置入站或客户端重置日       -> [1] 自定义流量重置"
    echo "  只预览今天的重置计划         -> [1] -> [4]，预览后输入 n"
    echo "  修正面板显示的已用流量       -> [2] 校准已用流量"
    echo "  备份数据或恢复旧状态         -> [3] 备份与恢复"
    echo "  检查服务、数据库和重置冲突   -> [4] 健康检查"
    echo "  排查自动重置或 x-ui 报错     -> [5] 日志"
    echo "  删除一个旧备份文件           -> [6] 清理旧备份"
    echo "------------------------------------------------"
    echo "命令行入口："
    echo "  xcm                                  打开本菜单"
    echo "  xui-custom-manager.sh --dry-run      只预览本次重置计划"
    echo "  xui-custom-manager.sh --reset-check  执行一次自动重置检查"
    echo "------------------------------------------------"
    echo -e "${YELLOW}写库和恢复前会显示影响范围并要求确认；确认提示默认 Yes，输入 n 取消。${PLAIN}"
}

main_menu() {
    register_xcm_shortcut

    while true; do
        clear_screen
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}${WHITE}x-ui 增强套件 - 主菜单${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}管理 3x-ui 自定义重置、已用流量、备份和诊断。${PLAIN}"
        print_xui_version_warning
        echo -e "${CYAN}自动重置：${GREEN}$(timer_active_status)${PLAIN} ${DIM}|${PLAIN} ${CYAN}本地执行器：${GREEN}$(runner_status)${PLAIN} ${DIM}|${PLAIN} ${CYAN}快捷命令：${WHITE}xcm${PLAIN}"
        echo -e "${BLUE}------------------------------------------------${PLAIN}"
        echo -e "  ${CYAN}1.${PLAIN} ${GREEN}自定义流量重置${PLAIN}            ${YELLOW}(设置入站 / 客户端重置日)${PLAIN}"
        echo -e "  ${CYAN}2.${PLAIN} ${GREEN}校准已用流量${PLAIN}              ${YELLOW}(只改 up/down，不改 total)${PLAIN}"
        echo -e "  ${CYAN}3.${PLAIN} ${GREEN}备份与恢复${PLAIN}                ${YELLOW}(数据库 / 配置 / 程序)${PLAIN}"
        echo -e "  ${CYAN}4.${PLAIN} ${GREEN}健康检查${PLAIN}                  ${YELLOW}(服务 / 数据库 / timer / 冲突)${PLAIN}"
        echo -e "  ${CYAN}5.${PLAIN} ${GREEN}日志${PLAIN}                      ${YELLOW}(脚本 / reset-check / systemd)${PLAIN}"
        echo -e "  ${CYAN}6.${PLAIN} ${GREEN}清理旧备份${PLAIN}                ${YELLOW}(每次只删一个明确备份文件)${PLAIN}"
        echo -e "${BLUE}------------------------------------------------${PLAIN}"
        echo -e "  ${BLUE}?.${PLAIN} ${WHITE}按目标选择${PLAIN}"
        echo -e "${RED}  0/q. 退出${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_menu_choice choice "请选择 [0-6/?]："

        case "$choice" in
            "?"|help|HELP|帮助)
                show_quick_guide
                pause
                ;;
            1)
                # 各入口失败时内部已提示；|| true 防止 set -e 结束整个交互会话
                run_custom_reset_ui || true
                ;;
            2)
                run_traffic_ui || true
                ;;
            3)
                menu_backup_restore
                ;;
            4)
                health_check || true
                pause
                ;;
            5)
                menu_logs
                ;;
            6)
                cleanup_backups
                pause
                ;;
            0|q|Q)
                clear_screen
                exit 0
                ;;
            *)
                echo -e "${RED}输入无效，请输入 0-6 或 ?。${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

if [ "$SELF_TEST" -eq 1 ]; then
    run_self_test
elif [ "$RUN_CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    run_reset_engine
else
    require_interactive_menu || exit 1
    main_menu
fi
