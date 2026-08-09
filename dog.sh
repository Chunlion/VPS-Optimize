#!/bin/bash
#原项目https://github.com/zywe03/realm-xwPF/blob/main/port-traffic-dog.sh
set -euo pipefail

readonly SCRIPT_VERSION="1.2.7-TG通知版"
readonly SCRIPT_NAME="端口流量狗"
readonly SCRIPT_PATH="$(realpath "$0")"
readonly CONFIG_DIR="/etc/port-traffic-dog"
readonly CONFIG_FILE="$CONFIG_DIR/config.json"
readonly LOG_FILE="$CONFIG_DIR/logs/traffic.log"
readonly TRAFFIC_DATA_FILE="$CONFIG_DIR/traffic_data.json"
readonly DAILY_USAGE_FILE="$CONFIG_DIR/daily_usage.json"
readonly DAILY_SNAPSHOT_STATE_FILE="$CONFIG_DIR/daily_snapshot_state.json"

NFT_COUNTER_SNAPSHOT=""
UI_LANGUAGE="${VPSO_LANG:-${DOG_LANGUAGE:-zh}}"
REQUESTED_UI_LANGUAGE=""

readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

normalize_ui_language() {
    case "${1,,}" in
        zh|zh_cn|zh-cn|chinese|中文) printf 'zh' ;;
        en|en_us|en-us|english) printf 'en' ;;
        ru|ru_ru|ru-ru|russian|русский) printf 'ru' ;;
        *) return 1 ;;
    esac
}

ui_text() {
    local zh="$1" en="$2" ru="$3"
    case "$UI_LANGUAGE" in
        en) printf '%s' "$en" ;;
        ru) printf '%s' "$ru" ;;
        *) printf '%s' "$zh" ;;
    esac
}

load_ui_language() {
    local saved=""
    if [[ -z "${VPSO_LANG:-}" && -z "${DOG_LANGUAGE:-}" && -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        saved=$(jq -r '.global.ui_language // empty' "$CONFIG_FILE" 2>/dev/null || true)
    fi
    UI_LANGUAGE=$(normalize_ui_language "${VPSO_LANG:-${DOG_LANGUAGE:-${REQUESTED_UI_LANGUAGE:-$saved}}}" 2>/dev/null || printf 'zh')
}

save_ui_language() {
    local language="$1"
    language=$(normalize_ui_language "$language") || return 1
    update_config ".global.ui_language = \"${language}\"" || return 1
    UI_LANGUAGE="$language"
}

select_ui_language() {
    local choice target
    echo -e "${BLUE}$(ui_text '=== 界面语言 ===' '=== Interface language ===' '=== Язык интерфейса ===')${NC}"
    echo "  1. English"
    echo "  2. 简体中文"
    echo "  3. Русский"
    echo "  0. $(ui_text '返回主菜单' 'Back to main menu' 'Назад в главное меню')"
    read_trimmed choice "$(ui_text '请选择 [0-3]: ' 'Select [0-3]: ' 'Выберите [0-3]: ')"
    case "${choice,,}" in
        1|en|english) target="en" ;;
        2|zh|chinese|中文) target="zh" ;;
        3|ru|russian|русский) target="ru" ;;
        0|q|quit|back) return 0 ;;
        *) echo -e "${RED}$(ui_text '无效选择。' 'Invalid selection.' 'Неверный выбор.')${NC}"; return 1 ;;
    esac
    save_ui_language "$target" || { echo -e "${RED}$(ui_text '语言设置保存失败。' 'Failed to save language setting.' 'Не удалось сохранить язык интерфейса.')${NC}"; return 1; }
    echo -e "${GREEN}$(ui_text '界面语言已更新。' 'Interface language updated.' 'Язык интерфейса обновлён.')${NC}"
}

trim_input() {
    local value="$*"
    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

read_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local input
    # 输入流关闭（Ctrl+D）时优雅退出，避免 set -e 直接崩溃
    if ! read -r -p "$prompt" input; then
        echo
        exit 0
    fi
    if [[ -z "$(trim_input "$input")" ]]; then
        case "$prompt" in
            *"(Y/n"*|*"[Y/n]"*|*"直接回车继续"*) input="y" ;;
        esac
    fi
    printf -v "$__target" '%s' "$(trim_input "$input")"
}

read_secret_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local input
    if ! read -r -s -p "$prompt" input; then
        echo
        exit 0
    fi
    echo ""
    printf -v "$__target" '%s' "$(trim_input "$input")"
}

quarantine_path() {
    local target="$1"
    local quarantine_root="${2:-/root/port-traffic-dog-quarantine}"
    local resolved base dest

    if [[ -z "$target" || "$target" == *"*"* || "$target" == *"?"* ]]; then
        echo -e "${RED}拒绝隔离空路径或通配符路径: ${target}${NC}"
        return 1
    fi

    [[ -e "$target" || -L "$target" ]] || return 0

    resolved=$(readlink -f -- "$target" 2>/dev/null || realpath -m -- "$target" 2>/dev/null || printf '%s' "$target")
    case "$resolved" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
            echo -e "${RED}拒绝隔离系统根级目录: ${resolved}${NC}"
            return 1
            ;;
    esac

    mkdir -p "$quarantine_root" || return 1
    base=$(basename "$resolved")
    dest="${quarantine_root%/}/$(date +%Y%m%d_%H%M%S)_${base}"
    while [[ -e "$dest" ]]; do
        dest="${dest}_$RANDOM"
    done

    mv -- "$target" "$dest"
    echo -e "${YELLOW}已隔离: ${resolved} -> ${dest}${NC}"
}

normalize_main_choice() {
    local choice
    choice="$(trim_input "$1")"
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
        q|quit|exit|0|退出) echo "0" ;;
        add|port|端口) echo "1" ;;
        limit|quota|限额|限速) echo "2" ;;
        reset|重置) echo "3" ;;
        config|配置) echo "4" ;;
        update|upd|u|更新) echo "5" ;;
        uninstall|remove|卸载) echo "6" ;;
        tg|telegram|通知) echo "7" ;;
        report|trend|日报|趋势) echo "8" ;;
        detail|details|d|明细|详细) echo "detail" ;;
        health|check|diag|diagnose|h|诊断|健康检查) echo "health" ;;
        lang|language|l|语言|язык) echo "language" ;;
        *) echo "$choice" ;;
    esac
}

# 网络超时设置
readonly SHORT_CONNECT_TIMEOUT=5
readonly SHORT_MAX_TIMEOUT=7
readonly SCRIPT_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/refs/heads/main/dog.sh"
readonly SHORTCUT_COMMAND="dog"

download_notification_modules() {
    return 0
}
detect_system() {
    if [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release 2>/dev/null; then
        echo "ubuntu"
        return
    fi
    if [ -f /etc/debian_version ]; then
        echo "debian"
        return
    fi
    if [ -f /etc/redhat-release ]; then
        echo "rhel"
        return
    fi
    echo "unknown"
}

install_missing_tools() {
    local missing_tools=("$@")
    local system_type=$(detect_system)
    local pkg_cmd
    local packages=()
    local tool pkg
    case $system_type in
        "ubuntu"|"debian") pkg_cmd="apt-get" ;;
        "rhel")
            if command -v dnf >/dev/null 2>&1; then pkg_cmd="dnf"; else pkg_cmd="yum"; fi
            ;;
        *)
            echo -e "${RED}不支持的系统类型: $system_type${NC}"
            exit 1
            ;;
    esac

    echo -e "${YELLOW}检测到缺少工具: ${missing_tools[*]}${NC}"
    for tool in "${missing_tools[@]}"; do
        if [ "$system_type" = "rhel" ]; then
            case $tool in
                "nft") pkg="nftables" ;;
                "tc"|"ss") pkg="iproute" ;;
                "awk") pkg="gawk" ;;
                "cron") pkg="cronie" ;;
                "conntrack") pkg="conntrack-tools" ;;
                *) pkg="$tool" ;;
            esac
        else
            case $tool in
                "nft") pkg="nftables" ;;
                "tc"|"ss") pkg="iproute2" ;;
                "awk") pkg="gawk" ;;
                *) pkg="$tool" ;;
            esac
        fi
        [[ " ${packages[*]} " == *" $pkg "* ]] || packages+=("$pkg")
    done

    if [ "$system_type" = "rhel" ]; then
        $pkg_cmd install -y "${packages[@]}"
    else
        export DEBIAN_FRONTEND=noninteractive
        $pkg_cmd update -qq
        $pkg_cmd install -y "${packages[@]}"
        unset DEBIAN_FRONTEND
    fi

    if [[ " ${missing_tools[*]} " == *" cron "* ]]; then
        # Debian 系服务名为 cron，RHEL 系为 crond
        systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
        systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true
    fi
    echo -e "${GREEN}依赖工具安装完成${NC}"
}

check_dependencies() {
    local silent_mode=${1:-false}
    local missing_tools=()
    local required_tools=("nft" "tc" "ss" "jq" "awk" "bc" "unzip" "cron" "curl" "conntrack")

    for tool in "${required_tools[@]}"; do
        # RHEL 系的 cron 守护进程二进制名为 crond，二者任一存在即视为满足
        if [ "$tool" = "cron" ]; then
            if ! command -v cron >/dev/null 2>&1 && ! command -v crond >/dev/null 2>&1; then
                missing_tools+=("cron")
            fi
            continue
        fi
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        install_missing_tools "${missing_tools[@]}"
        local still_missing=()
        for tool in "${missing_tools[@]}"; do
            if ! command -v "$tool" >/dev/null 2>&1; then
                still_missing+=("$tool")
            fi
        done
        if [ ${#still_missing[@]} -gt 0 ]; then
            echo -e "${RED}安装失败，仍缺少工具: ${still_missing[*]}${NC}"
            exit 1
        fi
    fi

    if [ "$silent_mode" != "true" ]; then
        echo -e "${GREEN}依赖检查通过${NC}"
    fi

    setup_script_permissions
    setup_cron_environment
    local active_ports=($(get_active_ports 2>/dev/null || true))
    for port in "${active_ports[@]}"; do
        setup_port_auto_reset_cron "$port" >/dev/null 2>&1 || true
    done
}

setup_script_permissions() {
    if [ -f "$SCRIPT_PATH" ]; then chmod +x "$SCRIPT_PATH" 2>/dev/null || true; fi
    if [ -f "/usr/local/bin/port-traffic-dog.sh" ]; then chmod +x "/usr/local/bin/port-traffic-dog.sh" 2>/dev/null || true; fi
}

ensure_local_script_copy() {
    local local_script="/usr/local/bin/port-traffic-dog.sh"
    if [ "$SCRIPT_PATH" != "$local_script" ]; then
        install -m 700 "$SCRIPT_PATH" "$local_script" || return 1
    else
        chmod 700 "$local_script" 2>/dev/null || true
    fi
    printf '%s' "$local_script"
}

confirm_danger() {
    local title="$1"
    local impact="$2"
    local rollback="${3:-取消后不会改动当前配置；继续前建议先导出配置。}"
    local confirm
    echo -e "${RED}高风险操作: ${title}${NC}"
    echo -e "${YELLOW}影响: ${impact}${NC}"
    echo -e "${BLUE}回退: ${rollback}${NC}"
    read_trimmed confirm "确认继续？[Y/n]: "
    [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]
}

setup_cron_environment() {
    local runtime_script
    runtime_script=$(ensure_local_script_copy) || runtime_script="$SCRIPT_PATH"
    local current_cron=$(crontab -l 2>/dev/null || true)
    if ! echo "$current_cron" | grep -q "^PATH=.*sbin"; then
        local temp_cron=$(mktemp /tmp/port-traffic-dog-cron.XXXXXX)
        echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" > "$temp_cron"
        echo "$current_cron" | grep -v "^PATH=" >> "$temp_cron" || true
        crontab "$temp_cron" 2>/dev/null || true
        rm -f "$temp_cron"
    fi
    
    # 修复：强行注册开机自启任务，确保重启后恢复逻辑被执行
    # 兼容旧版未加引号的条目：只要 @reboot 行里含本脚本路径就视为已注册
    if ! crontab -l 2>/dev/null | grep -F "$runtime_script" | grep -Fq "@reboot"; then
        local temp_cron2=$(mktemp)
        crontab -l 2>/dev/null > "$temp_cron2" || true
        echo "@reboot /bin/bash \"$runtime_script\" >/dev/null 2>&1" >> "$temp_cron2"
        crontab "$temp_cron2" 2>/dev/null || true
        rm -f "$temp_cron2"
    fi
    # 修复：注入高频持久化任务，防止意外死机导致的流量数据蒸发
    if ! crontab -l 2>/dev/null | grep -F "$runtime_script" | grep -Fq -- "--save-data"; then
        local temp_cron3=$(mktemp)
        crontab -l 2>/dev/null | grep -vF -- "--save-data" > "$temp_cron3" || true
        # 每小时第 15 分钟触发一次后台数据存档
        echo "15 * * * * /bin/bash \"$runtime_script\" --save-data >/dev/null 2>&1" >> "$temp_cron3"
        crontab "$temp_cron3" 2>/dev/null || true
        rm -f "$temp_cron3"
    fi

    # 每小时增量采集一次日报快照数据（用于昨日/近7日趋势）
    if ! crontab -l 2>/dev/null | grep -F "$runtime_script" | grep -Fq -- "--daily-snapshot"; then
        local temp_cron4=$(mktemp)
        crontab -l 2>/dev/null | grep -vF -- "--daily-snapshot" > "$temp_cron4" || true
        echo "10 * * * * /bin/bash \"$runtime_script\" --daily-snapshot >/dev/null 2>&1" >> "$temp_cron4"
        crontab "$temp_cron4" 2>/dev/null || true
        rm -f "$temp_cron4"
    fi

    sync_telegram_notification_cron
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}$(ui_text '错误：此脚本需要 root 权限运行。' 'Error: run this script as root.' 'Ошибка: запустите сценарий от root.')${NC}"
        exit 1
    fi
}

init_config() {
    mkdir -p "$CONFIG_DIR" "$(dirname "$LOG_FILE")"
    chmod 700 "$CONFIG_DIR" 2>/dev/null || true
    download_notification_modules >/dev/null 2>&1 || true

    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "global": {
  },
  "ports": {},
  "nftables": {
    "table_name": "port_traffic_monitor",
    "family": "inet"
  },
  "notifications": {
    "telegram": {
      "enabled": false,
      "bot_token": "",
      "chat_id": "",
      "server_name": "",
      "template": "<b>🐶 {server_name} 端口流量通知</b>\n{report}",
      "status_notifications": {
        "enabled": false,
        "interval": "1h",
        "daily_hour": 9
      }
    },
    "email": {
      "enabled": false,
      "status": "coming_soon"
    },
    "wecom": {
      "enabled": false,
      "webhook_url": "",
      "server_name": "",
      "status_notifications": {
        "enabled": false,
        "interval": "1h"
      }
    }
  }
}
EOF
    fi
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    ensure_global_defaults
    ensure_notification_defaults
    sanitize_nftables_config
    ensure_daily_usage_files
    init_nftables
    setup_exit_hooks
    # 修复：移除残缺的 restore_monitoring_if_needed，改为调用全量恢复函数
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -gt 0 ]; then
        # 1. 注入关机前保存的流量数据，防止进度丢失
        restore_traffic_data_from_backup
        # 2. 恢复所有的 nftables、TC限速 以及 cron 重置任务
        restore_all_monitoring_rules
    fi
}

sanitize_nftables_config() {
    local family
    local table_name
    family=$(jq -r '.nftables.family // "inet"' "$CONFIG_FILE" 2>/dev/null || echo "inet")
    table_name=$(jq -r '.nftables.table_name // "port_traffic_monitor"' "$CONFIG_FILE" 2>/dev/null || echo "port_traffic_monitor")

    case "$family" in
        ip|ip6|inet|arp|bridge|netdev) ;;
        *)
            echo -e "${YELLOW}检测到异常 nftables family，已恢复为 inet。${NC}"
            update_config '.nftables.family = "inet"'
            ;;
    esac

    if ! [[ "$table_name" =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]]; then
        echo -e "${YELLOW}检测到异常 nftables table_name，已恢复为 port_traffic_monitor。${NC}"
        update_config '.nftables.table_name = "port_traffic_monitor"'
    fi
}

init_nftables() {
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    nft add table "$family" "$table_name" 2>/dev/null || true
    nft add chain "$family" "$table_name" input { type filter hook input priority 0\; } 2>/dev/null || true
    nft add chain "$family" "$table_name" output { type filter hook output priority 0\; } 2>/dev/null || true
    nft add chain "$family" "$table_name" forward { type filter hook forward priority 0\; } 2>/dev/null || true
}

get_network_interfaces() {
    local interfaces=()
    while IFS= read -r interface; do
        if [[ "$interface" != "lo" ]] && [[ "$interface" != "" ]]; then
            interfaces+=("$interface")
        fi
    done < <(ip link show | grep "state UP" | awk -F': ' '{print $2}' | cut -d'@' -f1)
    printf '%s\n' "${interfaces[@]}"
}

get_default_interface() {
    local default_interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -n "$default_interface" ]; then echo "$default_interface"; return; fi
    local interfaces=($(get_network_interfaces))
    if [ ${#interfaces[@]} -gt 0 ]; then echo "${interfaces[0]}"; else echo "eth0"; fi
}

format_bytes() {
    local bytes=${1:-0}
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then bytes=0; fi
    if ((bytes >= 1073741824)); then
        local gb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1073741824}")
        echo "${gb}GB"
    elif ((bytes >= 1048576)); then
        local mb=$(echo "scale=2; $bytes / 1048576" | bc)
        echo "${mb}MB"
    elif ((bytes >= 1024)); then
        local kb=$(echo "scale=2; $bytes / 1024" | bc)
        echo "${kb}KB"
    else
        echo "${bytes}B"
    fi
}

get_beijing_time() { TZ='Asia/Shanghai' date "$@"; }

print_traffic_scope_notice() {
    echo -e "${YELLOW}$(ui_text '统计口径：当前统计来自 nftables counter。' 'Source: nftables counters.' 'Источник: счётчики nftables.')${NC}"
    echo -e "${YELLOW}$(ui_text '范围：受监控端口的 TCP/UDP input/output/forward 流量，不等同于 VPS 商家账单。' 'Scope: TCP/UDP input/output/forward traffic for monitored ports; not a VPS provider bill.' 'Охват: TCP/UDP input/output/forward для отслеживаемых портов; это не счёт провайдера VPS.')${NC}"
    echo -e "${YELLOW}$(ui_text '日报按定时快照增量统计，跨日可能有小时级误差。' 'Daily reports use scheduled snapshot deltas and may have hour-level cross-day variance.' 'Дневные отчёты используют приращения снимков; на границе суток возможна погрешность до часа.')${NC}"
}

print_daily_snapshot_notice() {
    echo -e "${YELLOW}提示：日报由定时快照增量计算，跨日边界可能存在快照间隔误差。${NC}"
}

# 优化1：增加文件锁，防止高并发导致配置脏读/损坏
update_config() {
    local jq_expression="$1"
    local temp_file
    (
        flock -w 5 9 || { echo -e "${RED}配置文件正忙，稍后重试${NC}"; return 1; }
        temp_file=$(mktemp "${CONFIG_DIR}/config.XXXXXX.tmp") || return 1
        if jq "$jq_expression" "$CONFIG_FILE" > "$temp_file"; then
            mv "$temp_file" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        else
            rm -f "$temp_file"
            echo -e "${RED}配置更新失败，已保留原配置。${NC}"
            return 1
        fi
    ) 9> "${CONFIG_DIR}/.config.lock"
}

update_telegram_config() {
    local bot_token="$1"
    local chat_id="$2"
    local temp_file
    (
        flock -w 5 9 || { echo -e "${RED}配置文件正忙，稍后重试${NC}"; return 1; }
        temp_file=$(mktemp "${CONFIG_DIR}/config.XXXXXX.tmp") || return 1
        if jq --arg bot_token "$bot_token" --arg chat_id "$chat_id" \
            '.notifications.telegram.bot_token = $bot_token | .notifications.telegram.chat_id = $chat_id | .notifications.telegram.enabled = true' \
            "$CONFIG_FILE" > "$temp_file"; then
            mv "$temp_file" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        else
            rm -f "$temp_file"
            echo -e "${RED}Telegram 配置写入失败，已保留原配置。${NC}"
            return 1
        fi
    ) 9> "${CONFIG_DIR}/.config.lock"
}

ensure_notification_defaults() {
    if jq -e '
        . as $root |
        ($root.notifications.telegram.template | type == "string" and contains("{report}")) and
        (["1h", "6h", "12h", "daily"] | index($root.notifications.telegram.status_notifications.interval) != null) and
        ($root.notifications.telegram.status_notifications.daily_hour | type == "number" and . >= 0 and . <= 23)
    ' "$CONFIG_FILE" >/dev/null 2>&1; then
        return 0
    fi

    update_config '
        .notifications //= {} |
        .notifications.telegram //= {} |
        .notifications.telegram.enabled //= false |
        .notifications.telegram.bot_token //= "" |
        .notifications.telegram.chat_id //= "" |
        .notifications.telegram.server_name //= "" |
        .notifications.telegram.template //= "<b>🐶 {server_name} 端口流量通知</b>\n{report}" |
        .notifications.telegram.status_notifications //= {} |
        .notifications.telegram.status_notifications.enabled //= false |
        .notifications.telegram.status_notifications.interval //= "1h" |
        .notifications.telegram.status_notifications.daily_hour //= 9 |
        .notifications.telegram.template |= if type == "string" and contains("{report}") then . else "<b>🐶 {server_name} 端口流量通知</b>\n{report}" end |
        .notifications.telegram.status_notifications.interval |= if . == "1h" or . == "6h" or . == "12h" or . == "daily" then . else "1h" end |
        .notifications.telegram.status_notifications.daily_hour |= if type == "number" and . >= 0 and . <= 23 then . else 9 end
    ' >/dev/null
}

render_notification_template() {
    local template="$1"
    local server_name="$2"
    local report="$3"
    local generated_at="$4"

    jq -nr \
        --arg template "$template" \
        --arg server_name "$server_name" \
        --arg report "$report" \
        --arg generated_at "$generated_at" \
        '$template
         | split("{server_name}") | join($server_name)
         | split("{report}") | join($report)
         | split("{time}") | join($generated_at)'
}

telegram_notification_due() {
    local interval="$1"
    local daily_hour="$2"
    local current_hour="$3"

    [[ "$current_hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || return 1
    case "$interval" in
        1h) return 0 ;;
        6h) ((10#$current_hour % 6 == 0)) ;;
        12h) ((10#$current_hour % 12 == 0)) ;;
        daily)
            [[ "$daily_hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || return 1
            ((10#$current_hour == 10#$daily_hour))
            ;;
        *) return 1 ;;
    esac
}

parse_nft_counter_snapshot() {
    jq -ce '
        reduce (
            .nftables[]?
            | select(.counter.name? != null)
            | .counter
        ) as $counter ({}; .[$counter.name] = ($counter.bytes // 0))
    '
}

show_port_list() {
    local active_ports=($(get_active_ports))
    if [ ${#active_ports[@]} -eq 0 ]; then
        echo "暂无监控端口"
        return 1
    fi
    echo "当前监控的端口:"
    for i in "${!active_ports[@]}"; do
        local port=${active_ports[$i]}
        local status_label=$(get_port_status_label "$port")
        echo "$((i+1)). 端口 $port $status_label"
    done
    return 0
}

is_valid_port_number() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 ))
}

parse_multi_choice_input() {
    local input="$1"
    local max_choice="$2"
    local -n result_array=$3
    input="${input//，/,}"
    IFS=',' read -ra CHOICES <<< "$input"
    result_array=()
    for choice in "${CHOICES[@]}"; do
        choice=$(trim_input "$choice")
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= max_choice )); then
            result_array+=("$((10#$choice))")
        else
            echo -e "${RED}无效选择: $choice${NC}"
        fi
    done
}

parse_comma_separated_input() {
    local input="$1"
    local -n result_array=$2
    input="${input//，/,}"
    IFS=',' read -ra result_array <<< "$input"
    for i in "${!result_array[@]}"; do
        result_array[$i]=$(trim_input "${result_array[$i]}")
    done
}

parse_port_range_input() {
    local input="$1"
    local -n result_array=$2
    input="${input//，/,}"
    input="${input//：/:}"
    input="${input//－/-}"
    input="${input//—/-}"
    IFS=',' read -ra PARTS <<< "$input"
    result_array=()
    for part in "${PARTS[@]}"; do
        part=$(trim_input "$part")
        part="${part//:/-}"
        if is_port_range "$part"; then
            local start_port=$(echo "$part" | cut -d'-' -f1)
            local end_port=$(echo "$part" | cut -d'-' -f2)
            if (( 10#$start_port > 10#$end_port )); then
                echo -e "${RED}错误：端口段 $part 起始端口大于结束端口${NC}"
                return 1
            fi
            if ! is_valid_port_number "$start_port" || ! is_valid_port_number "$end_port"; then
                echo -e "${RED}错误：端口段 $part 包含无效端口${NC}"
                return 1
            fi
            result_array+=("$((10#$start_port))-$((10#$end_port))")
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            if is_valid_port_number "$part"; then
                result_array+=("$((10#$part))")
            else
                echo -e "${RED}错误：端口号 $part 无效${NC}"
                return 1
            fi
        else
            echo -e "${RED}错误：无效的端口格式 $part${NC}"
            return 1
        fi
    done
    return 0
}

expand_single_value_to_array() {
    local -n source_array=$1
    local target_size=$2
    if [ ${#source_array[@]} -eq 1 ]; then
        local single_value="${source_array[0]}"
        source_array=()
        for ((i=0; i<target_size; i++)); do
            source_array+=("$single_value")
        done
    fi
}

get_beijing_month_year() {
    local current_day=$(TZ='Asia/Shanghai' date +%d | sed 's/^0//')
    local current_month=$(TZ='Asia/Shanghai' date +%m | sed 's/^0//')
    local current_year=$(TZ='Asia/Shanghai' date +%Y)
    echo "$current_day $current_month $current_year"
}

get_nftables_counter_data() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    local input_bytes=0
    local output_bytes=0
    local port_safe=$(echo "$port" | tr '-' '_')

    if [ -n "$NFT_COUNTER_SNAPSHOT" ]; then
        if get_nftables_counter_data_from_snapshot "$port"; then
            return 0
        fi
        echo "0 0"
        return 0
    fi

    if is_port_range "$port"; then
        input_bytes=$(nft list counter "$family" "$table_name" "port_${port_safe}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
        output_bytes=$(nft list counter "$family" "$table_name" "port_${port_safe}_out" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
    else
        input_bytes=$(nft list counter "$family" "$table_name" "port_${port}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
        output_bytes=$(nft list counter "$family" "$table_name" "port_${port}_out" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
    fi
    input_bytes=${input_bytes:-0}
    output_bytes=${output_bytes:-0}
    echo "$input_bytes $output_bytes"
}

refresh_nftables_counter_snapshot() {
    local table_name
    local family
    local nft_json
    local parsed

    table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    NFT_COUNTER_SNAPSHOT=""

    nft_json=$(nft -j list table "$family" "$table_name" 2>/dev/null) || return 1
    parsed=$(printf '%s' "$nft_json" | parse_nft_counter_snapshot) || return 1
    NFT_COUNTER_SNAPSHOT="$parsed"
}

get_nftables_counter_data_from_snapshot() {
    local port="$1"
    local port_safe
    local counter_in
    local counter_out

    [ -n "$NFT_COUNTER_SNAPSHOT" ] || return 1
    port_safe=$(echo "$port" | tr '-' '_')
    counter_in="port_${port_safe}_in"
    counter_out="port_${port_safe}_out"

    jq -er --arg counter_in "$counter_in" --arg counter_out "$counter_out" '
        if has($counter_in)
           and has($counter_out)
           and (.[$counter_in] | type) == "number"
           and (.[$counter_out] | type) == "number"
        then "\(.[$counter_in]) \(.[$counter_out])"
        else empty
        end
    ' <<< "$NFT_COUNTER_SNAPSHOT"
}

validate_traffic_counter_snapshot() {
    local active_ports=()
    local port
    local table_name
    local family
    local input_chain
    local output_chain
    local forward_chain

    mapfile -t active_ports < <(get_active_ports 2>/dev/null || true)
    refresh_nftables_counter_snapshot || return 1
    table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    input_chain=$(nft list chain "$family" "$table_name" input 2>/dev/null) || return 1
    output_chain=$(nft list chain "$family" "$table_name" output 2>/dev/null) || return 1
    forward_chain=$(nft list chain "$family" "$table_name" forward 2>/dev/null) || return 1
    for port in "${active_ports[@]}"; do
        get_nftables_counter_data_from_snapshot "$port" >/dev/null || return 1
        port_nftables_rules_are_exact "$port" "$input_chain" "$output_chain" "$forward_chain" || return 1
    done
}

save_traffic_data() {
    local temp_file=$(mktemp /tmp/port-traffic-dog-data.XXXXXX)
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -eq 0 ]; then
        rm -f "$temp_file"
        return 0
    fi
    if ! validate_traffic_counter_snapshot; then
        rm -f "$temp_file"
        echo "$(get_beijing_time -Iseconds) 实时计数保存失败：nftables counter 快照不完整" >> "$LOG_FILE"
        return 1
    fi
    echo '{}' > "$temp_file"

    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data_from_snapshot "$port"))
        local current_input=${traffic_data[0]}
        local current_output=${traffic_data[1]}
        if [ $current_input -gt 0 ] || [ $current_output -gt 0 ]; then
            jq ".\"$port\" = {\"input\": $current_input, \"output\": $current_output, \"backup_time\": \"$(get_beijing_time -Iseconds)\"}" "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
        fi
    done
    if [ -s "$temp_file" ] && [ "$(jq 'keys | length' "$temp_file" 2>/dev/null)" != "0" ]; then
        mv "$temp_file" "$TRAFFIC_DATA_FILE"
    else
        rm -f "$temp_file"
    fi
}

# 退出时只保存计数数据；临时文件在创建点按明确路径清理。
setup_exit_hooks() {
    trap 'save_traffic_data_on_exit' EXIT
    trap 'save_traffic_data_on_exit; exit 1' INT TERM
}

save_traffic_data_on_exit() { save_traffic_data >/dev/null 2>&1 || true; }

restore_monitoring_if_needed() {
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -eq 0 ]; then return 0; fi
    local table_name
    local family
    table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    
    for port in "${active_ports[@]}"; do
        local p_safe=$(echo "$port" | tr '-' '_')
        # 如果内核里找不到这个端口的计数器，说明规则丢了，自动重新下发
        if ! nft list counter "$family" "$table_name" "port_${p_safe}_out" >/dev/null 2>&1; then
            echo -e "${YELLOW}检测到规则丢失，正在为端口 $port 重新下发监控规则...${NC}"
            add_nftables_rules "$port"
            
            # 如果有流量限制，也一并恢复
            local monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE")
            if [ "$monthly_limit" != "unlimited" ]; then
                apply_nftables_quota "$port" "$monthly_limit"
            fi
        fi
    done
}

restore_traffic_data_from_backup() {
    if [ ! -f "$TRAFFIC_DATA_FILE" ]; then return 0; fi
    local backup_ports=($(jq -r 'keys[]' "$TRAFFIC_DATA_FILE" 2>/dev/null || true))
    for port in "${backup_ports[@]}"; do
        local backup_input=$(jq -r ".\"$port\".input // 0" "$TRAFFIC_DATA_FILE" 2>/dev/null || echo "0")
        local backup_output=$(jq -r ".\"$port\".output // 0" "$TRAFFIC_DATA_FILE" 2>/dev/null || echo "0")
        if [ $backup_input -gt 0 ] || [ $backup_output -gt 0 ]; then
            restore_counter_value "$port" "$backup_input" "$backup_output"
        fi
    done
    rm -f "$TRAFFIC_DATA_FILE"
}

restore_counter_value() {
    local port=$1
    local target_input=$2
    local target_output=$3
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        nft add counter "$family" "$table_name" "port_${port_safe}_in" { packets 0 bytes "$target_input" } 2>/dev/null || true
        nft add counter "$family" "$table_name" "port_${port_safe}_out" { packets 0 bytes "$target_output" } 2>/dev/null || true
    else
        nft add counter "$family" "$table_name" "port_${port}_in" { packets 0 bytes "$target_input" } 2>/dev/null || true
        nft add counter "$family" "$table_name" "port_${port}_out" { packets 0 bytes "$target_output" } 2>/dev/null || true
    fi
}

restore_all_monitoring_rules() {
    local active_ports=($(get_active_ports))
    for port in "${active_ports[@]}"; do
        add_nftables_rules "$port"
        local quota_enabled=$(jq -r ".ports.\"$port\".quota.enabled // false" "$CONFIG_FILE")
        local monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE")
        if [ "$quota_enabled" = "true" ] && [ "$monthly_limit" != "unlimited" ]; then
            apply_nftables_quota "$port" "$monthly_limit"
        fi
        local limit_enabled=$(jq -r ".ports.\"$port\".bandwidth_limit.enabled // false" "$CONFIG_FILE")
        local rate_limit=$(jq -r ".ports.\"$port\".bandwidth_limit.rate // \"unlimited\"" "$CONFIG_FILE")
        if [ "$limit_enabled" = "true" ] && [ "$rate_limit" != "unlimited" ]; then
            local tc_limit=$(convert_bandwidth_to_tc "$rate_limit")
            if [ -n "$tc_limit" ]; then apply_tc_limit "$port" "$tc_limit"; fi
        fi
        setup_port_auto_reset_cron "$port"
    done
}

calculate_total_traffic() {
    local input_bytes=$1
    local output_bytes=$2
    echo $((input_bytes + output_bytes))
}

get_port_actual_usage() {
    local port=$1
    local traffic_data=($(get_nftables_counter_data "$port"))
    local input_bytes=${traffic_data[0]:-0}
    local output_bytes=${traffic_data[1]:-0}
    calculate_total_traffic "$input_bytes" "$output_bytes"
}

print_json_file_health() {
    local label="$1"
    local file="$2"
    local __problems_var="$3"
    local problems

    problems=${!__problems_var}
    if [ ! -f "$file" ]; then
        echo -e "  ${RED}${label}: 缺失：$file${NC}"
        problems=$((problems + 1))
    elif jq -e '.' "$file" >/dev/null 2>&1; then
        echo -e "  ${GREEN}${label}: JSON 有效：$file${NC}"
    else
        echo -e "  ${RED}${label}: JSON 无效：$file${NC}"
        problems=$((problems + 1))
    fi
    printf -v "$__problems_var" '%s' "$problems"
}

show_statistics_health_check() {
    local problems=0
    local table_name
    local family
    local active_ports=()

    echo -e "${BLUE}=== 统计健康检查 ===${NC}"
    print_traffic_scope_notice
    echo

    if ! command -v nft >/dev/null 2>&1; then
        echo -e "${RED}nft 命令不存在，无法检查 nftables counter 和规则。${NC}"
        problems=$((problems + 1))
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}jq 命令不存在，无法检查 JSON 状态文件。${NC}"
        problems=$((problems + 1))
    fi

    table_name=$(jq -r '.nftables.table_name // "port_traffic_monitor"' "$CONFIG_FILE" 2>/dev/null || echo "port_traffic_monitor")
    family=$(jq -r '.nftables.family // "inet"' "$CONFIG_FILE" 2>/dev/null || echo "inet")

    mapfile -t active_ports < <(get_active_ports 2>/dev/null || true)
    echo "nftables: family=$family table=$table_name"
    if [ ${#active_ports[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}暂无监控端口。${NC}"
    elif command -v nft >/dev/null 2>&1; then
        local input_chain output_chain forward_chain
        input_chain=$(nft list chain "$family" "$table_name" input 2>/dev/null || true)
        output_chain=$(nft list chain "$family" "$table_name" output 2>/dev/null || true)
        forward_chain=$(nft list chain "$family" "$table_name" forward 2>/dev/null || true)

        for port in "${active_ports[@]}"; do
            local port_safe counter_in counter_out
            port_safe=$(echo "$port" | tr '-' '_')
            counter_in="port_${port_safe}_in"
            counter_out="port_${port_safe}_out"
            echo "端口 $port:"

            if nft list counter "$family" "$table_name" "$counter_in" >/dev/null 2>&1; then
                echo -e "  ${GREEN}counter $counter_in: 存在${NC}"
            else
                echo -e "  ${RED}counter $counter_in: 缺失${NC}"
                problems=$((problems + 1))
            fi
            if nft list counter "$family" "$table_name" "$counter_out" >/dev/null 2>&1; then
                echo -e "  ${GREEN}counter $counter_out: 存在${NC}"
            else
                echo -e "  ${RED}counter $counter_out: 缺失${NC}"
                problems=$((problems + 1))
            fi

            if grep -Fq "counter name \"$counter_in\"" <<< "$input_chain"; then
                echo -e "  ${GREEN}input 链 $counter_in 规则: 存在${NC}"
            else
                echo -e "  ${RED}input 链 $counter_in 规则: 缺失${NC}"
                problems=$((problems + 1))
            fi
            if grep -Fq "counter name \"$counter_out\"" <<< "$output_chain"; then
                echo -e "  ${GREEN}output 链 $counter_out 规则: 存在${NC}"
            else
                echo -e "  ${RED}output 链 $counter_out 规则: 缺失${NC}"
                problems=$((problems + 1))
            fi
            if grep -Fq "counter name \"$counter_in\"" <<< "$forward_chain" && grep -Fq "counter name \"$counter_out\"" <<< "$forward_chain"; then
                echo -e "  ${GREEN}forward 链 $counter_in/$counter_out 规则: 存在${NC}"
            else
                echo -e "  ${RED}forward 链 $counter_in/$counter_out 规则: 缺失${NC}"
                problems=$((problems + 1))
            fi
            if port_nftables_rules_are_exact "$port" "$input_chain" "$output_chain" "$forward_chain"; then
                echo -e "  ${GREEN}计数规则数量: 正常${NC}"
            else
                echo -e "  ${RED}计数规则数量: 缺失或重复${NC}"
                problems=$((problems + 1))
            fi
        done
    fi

    echo
    echo "日报状态文件:"
    print_json_file_health "DAILY_USAGE_FILE" "$DAILY_USAGE_FILE" problems
    print_json_file_health "DAILY_SNAPSHOT_STATE_FILE" "$DAILY_SNAPSHOT_STATE_FILE" problems

    echo
    echo "实时计数备份:"
    if [ -f "$TRAFFIC_DATA_FILE" ]; then
        if jq -e '.' "$TRAFFIC_DATA_FILE" >/dev/null 2>&1; then
            local last_backup
            last_backup=$(jq -r '[.. | objects | .backup_time? // empty] | max // empty' "$TRAFFIC_DATA_FILE" 2>/dev/null || true)
            [ -z "$last_backup" ] && last_backup=$(stat -c '%y' "$TRAFFIC_DATA_FILE" 2>/dev/null | cut -d'.' -f1 || true)
            echo -e "  ${GREEN}TRAFFIC_DATA_FILE: 存在，最后保存时间：${last_backup:-未知}${NC}"
        else
            echo -e "  ${RED}TRAFFIC_DATA_FILE: 存在但 JSON 无效：$TRAFFIC_DATA_FILE${NC}"
            problems=$((problems + 1))
        fi
    else
        echo -e "  ${YELLOW}TRAFFIC_DATA_FILE: 不存在，通常表示当前没有待恢复的退出快照。${NC}"
    fi

    echo
    if [ "$problems" -eq 0 ]; then
        echo -e "${GREEN}统计健康检查完成，未发现明显异常。${NC}"
    else
        echo -e "${YELLOW}统计健康检查发现 $problems 项异常；本检查不会自动修复。${NC}"
        echo -e "${YELLOW}如需修复 nftables counter 或链规则，请重新应用监控规则。${NC}"
    fi
}

get_port_status_label() {
    local port=$1
    local port_config=$(jq -r ".ports.\"$port\"" "$CONFIG_FILE" 2>/dev/null)
    local remark=$(echo "$port_config" | jq -r '.remark // ""')
    local limit_enabled=$(echo "$port_config" | jq -r '.bandwidth_limit.enabled // false')
    local rate_limit=$(echo "$port_config" | jq -r '.bandwidth_limit.rate // "unlimited"')
    local quota_enabled=$(echo "$port_config" | jq -r '.quota.enabled // false')
    local monthly_limit=$(echo "$port_config" | jq -r '.quota.monthly_limit // "unlimited"')
    local reset_day_raw=$(echo "$port_config" | jq -r '.quota.reset_day')

    # 预生成重置日标签：按目标月的实际天数收敛显示（31 号在 2 月显示为月末日），
    # 与 check_and_run_daily_resets 的"月末补偿"行为保持一致
    local reset_tag=""
    if [ "$reset_day_raw" != "null" ] && [[ "$reset_day_raw" =~ ^[0-9]+$ ]]; then
        local time_info=($(get_beijing_month_year))
        local current_day=${time_info[0]}
        local target_month=${time_info[1]}
        local target_year=${time_info[2]}
        if [ "$current_day" -ge "$reset_day_raw" ]; then
            target_month=$((target_month + 1))
            if [ $target_month -gt 12 ]; then target_month=1; target_year=$((target_year + 1)); fi
        fi
        local target_last=$(date -d "$(printf '%04d-%02d-01' "$target_year" "$target_month") +1 month -1 day" +%d 2>/dev/null | sed 's/^0//')
        local display_day=$reset_day_raw
        if [ -n "$target_last" ] && [ "$display_day" -gt "$target_last" ]; then
            display_day=$target_last
        fi
        reset_tag="[${target_month}月${display_day}日重置]"
    fi

    local status_tags=()
    if [ -n "$remark" ] && [ "$remark" != "null" ] && [ "$remark" != "" ]; then
        status_tags+=("[备注:$remark]")
    fi
    if [ "$quota_enabled" = "true" ]; then
        if [ "$monthly_limit" != "unlimited" ]; then
            local current_usage=$(get_port_monthly_usage "$port")
            local limit_bytes=$(parse_size_to_bytes "$monthly_limit")
            local usage_percent=0
            if [ "$limit_bytes" -gt 0 ]; then
                usage_percent=$((current_usage * 100 / limit_bytes))
            fi
            local quota_display="$monthly_limit"
            status_tags+=("[配额:${quota_display}]")
            if [ -n "$reset_tag" ]; then
                status_tags+=("$reset_tag")
            fi
            if [ $usage_percent -ge 100 ]; then status_tags+=("[已超限]"); fi
        else
            status_tags+=("[无限制]")
            if [ -n "$reset_tag" ]; then
                status_tags+=("$reset_tag")
            fi
        fi
    fi
    if [ "$limit_enabled" = "true" ] && [ "$rate_limit" != "unlimited" ]; then
        status_tags+=("[限制带宽${rate_limit}]")
    fi
    if [ ${#status_tags[@]} -gt 0 ]; then
        printf '%s' "${status_tags[@]}"
        echo
    fi
}

get_port_monthly_usage() {
    local port=$1
    get_port_actual_usage "$port"
}

validate_bandwidth() {
    local input="$1"
    local lower_input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    if [[ "$input" == "0" ]]; then return 0
    elif [[ "$lower_input" =~ ^[0-9]+kbps$ ]] || [[ "$lower_input" =~ ^[0-9]+mbps$ ]] || [[ "$lower_input" =~ ^[0-9]+gbps$ ]]; then return 0
    else return 1; fi
}

validate_quota() {
    local input="$1"
    local lower_input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    if [[ "$input" == "0" ]]; then return 0
    elif [[ "$lower_input" =~ ^[0-9]+(mb|gb|tb|m|g|t)$ ]]; then return 0
    else return 1; fi
}

parse_size_to_bytes() {
    local size_str=$1
    local number=$(echo "$size_str" | grep -o '^[0-9]\+')
    local unit=$(echo "$size_str" | grep -o '[A-Za-z]\+$' | tr '[:lower:]' '[:upper:]')
    [ -z "$number" ] && echo "0" && return 1
    case $unit in
        "MB"|"M") echo $((number * 1048576)) ;;
        "GB"|"G") echo $((number * 1073741824)) ;;
        "TB"|"T") echo $((number * 1099511627776)) ;;
        *) echo "0" ;;
    esac
}

get_active_ports() { jq -r '.ports | keys[]' "$CONFIG_FILE" 2>/dev/null | sort -n; }

is_port_range() { local port=$1; [[ "$port" =~ ^[0-9]+-[0-9]+$ ]]; }

generate_port_range_mark() {
    local port_range=$1
    echo "$port_range" | cksum | awk '{print ($1 % 65535) + 1}'
}

calculate_tc_burst() {
    local base_rate=$1
    local rate_bytes_per_sec=$((base_rate * 1000 / 8))
    local burst_by_formula=$((rate_bytes_per_sec / 20))
    local min_burst=$((2 * 1500))
    if [ $burst_by_formula -gt $min_burst ]; then echo $burst_by_formula; else echo $min_burst; fi
}

format_tc_burst() {
    local burst_bytes=$1
    if [ $burst_bytes -lt 1024 ]; then echo "${burst_bytes}"
    elif [ $burst_bytes -lt 1048576 ]; then echo "$((burst_bytes / 1024))k"
    else echo "$((burst_bytes / 1048576))m"; fi
}

get_global_display_mode() {
    echo "raw"
}

ensure_global_defaults() {
    :
}

ensure_daily_usage_files() {
        if [ ! -f "$DAILY_USAGE_FILE" ] || ! jq -e '.' "$DAILY_USAGE_FILE" >/dev/null 2>&1; then
                cat > "$DAILY_USAGE_FILE" << 'EOF'
{
    "days": {},
    "meta": {
        "last_snapshot": ""
    }
}
EOF
        fi

        if [ ! -f "$DAILY_SNAPSHOT_STATE_FILE" ] || ! jq -e '.' "$DAILY_SNAPSHOT_STATE_FILE" >/dev/null 2>&1; then
                cat > "$DAILY_SNAPSHOT_STATE_FILE" << 'EOF'
{
    "ports": {},
    "updated_at": ""
}
EOF
        fi
}

parse_tc_rate_to_kbps() {
    local total_limit=$1
    if [[ "$total_limit" =~ gbit$ ]]; then
        local rate=$(echo "$total_limit" | sed 's/gbit$//')
        echo $((rate * 1000000))
    elif [[ "$total_limit" =~ mbit$ ]]; then
        local rate=$(echo "$total_limit" | sed 's/mbit$//')
        echo $((rate * 1000))
    else
        echo $(echo "$total_limit" | sed 's/kbit$//')
    fi
}

convert_bandwidth_to_tc() {
    local rate="$1"
    local lower=$(echo "$rate" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" =~ kbps$ ]]; then echo "${lower/%kbps/kbit}"
    elif [[ "$lower" =~ mbps$ ]]; then echo "${lower/%mbps/mbit}"
    elif [[ "$lower" =~ gbps$ ]]; then echo "${lower/%gbps/gbit}"
    fi
}

generate_tc_class_id() {
    local port=$1
    if is_port_range "$port"; then
        local mark_id=$(generate_port_range_mark "$port")
        echo "1:$(printf '%x' $((0x2000 + mark_id)))"
    else
        echo "1:$(printf '%x' $((0x1000 + port)))"
    fi
}

get_daily_total_traffic() {
    local total_bytes=0
    local ports=($(get_active_ports))
    for port in "${ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
        local input_bytes=${traffic_data[0]}
        local output_bytes=${traffic_data[1]}
        local port_total=$((input_bytes + output_bytes))
        total_bytes=$(( total_bytes + port_total ))
    done
    format_bytes $total_bytes
}

collect_daily_usage_snapshot() {
    local silent_mode=${1:-"false"}
    (
        if ! flock -w 30 9; then
            [ "$silent_mode" = "true" ] || echo -e "${RED}日报快照任务正忙，请稍后重试。${NC}"
            return 1
        fi
        collect_daily_usage_snapshot_locked "$silent_mode"
    ) 9> "${CONFIG_DIR}/.daily-snapshot.lock"
}

collect_daily_usage_snapshot_locked() {
    local silent_mode=${1:-"false"}
    ensure_daily_usage_files

    if ! validate_traffic_counter_snapshot; then
        echo "$(get_beijing_time -Iseconds) 日报快照失败：nftables counter 快照不完整" >> "$LOG_FILE"
        [ "$silent_mode" = "true" ] || echo -e "${RED}nftables counter 不完整，未写入日报。请运行 health 检查。${NC}"
        return 1
    fi

    local day_key=$(get_beijing_time +%F)
    local snapshot_time=$(get_beijing_time -Iseconds)
    local usage_tmp=$(mktemp /tmp/port-traffic-dog-daily-usage.XXXXXX)
    local state_tmp=$(mktemp /tmp/port-traffic-dog-daily-state.XXXXXX)
    cp "$DAILY_USAGE_FILE" "$usage_tmp"
    cp "$DAILY_SNAPSHOT_STATE_FILE" "$state_tmp"

    local active_ports=($(get_active_ports 2>/dev/null || true))
    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data_from_snapshot "$port"))
        local input_bytes=${traffic_data[0]:-0}
        local output_bytes=${traffic_data[1]:-0}
        local actual_total=$((input_bytes + output_bytes))

        local prev_actual=0
        if jq -e --arg port "$port" '.ports[$port]' "$state_tmp" >/dev/null 2>&1; then
            prev_actual=$(jq -r --arg port "$port" '.ports[$port].raw // .ports[$port].actual // 0' "$state_tmp" 2>/dev/null || echo "0")
        else
            prev_actual=$actual_total
        fi

        local delta_actual=$((actual_total - prev_actual))
        if [ "$delta_actual" -lt 0 ]; then
            local backup_actual=0
            if [ -f "$TRAFFIC_DATA_FILE" ]; then
                local backup_input=$(jq -r ".\"$port\".input // 0" "$TRAFFIC_DATA_FILE" 2>/dev/null || echo "0")
                local backup_output=$(jq -r ".\"$port\".output // 0" "$TRAFFIC_DATA_FILE" 2>/dev/null || echo "0")
                backup_actual=$((backup_input + backup_output))
            fi
            if [ "$backup_actual" -gt 0 ] && [ "$backup_actual" -gt "$prev_actual" ]; then
                delta_actual=$((actual_total - backup_actual))
                if [ "$delta_actual" -lt 0 ]; then
                    delta_actual=$actual_total
                    prev_actual=0
                else
                    prev_actual=$backup_actual
                fi
            else
                delta_actual=$actual_total
                prev_actual=0
            fi
        fi

        jq --arg day "$day_key" \
           --arg port "$port" \
           --arg ts "$snapshot_time" \
           --argjson delta_actual "$delta_actual" \
           '(.days[$day].ports[$port] // 0) as $old |
            .days[$day].ports[$port] = {
                raw: ((if ($old | type) == "object" then ($old.raw // $old.actual // 0) else $old end) + $delta_actual)
            } |
            .days[$day].total_raw = ((.days[$day].total_raw // .days[$day].total_actual // 0) + $delta_actual) |
            .days[$day].updated_at = $ts |
            .meta.last_snapshot = $ts' "$usage_tmp" > "${usage_tmp}.new" && mv "${usage_tmp}.new" "$usage_tmp"

        jq --arg port "$port" \
           --arg ts "$snapshot_time" \
           --argjson actual "$actual_total" \
           '.ports[$port] = {raw: $actual} |
            .updated_at = $ts' "$state_tmp" > "${state_tmp}.new" && mv "${state_tmp}.new" "$state_tmp"
    done

    jq --arg ts "$snapshot_time" '.meta.last_snapshot = $ts' "$usage_tmp" > "${usage_tmp}.new" && mv "${usage_tmp}.new" "$usage_tmp"
    jq --arg ts "$snapshot_time" '.updated_at = $ts' "$state_tmp" > "${state_tmp}.new" && mv "${state_tmp}.new" "$state_tmp"

    mv "$usage_tmp" "$DAILY_USAGE_FILE"
    mv "$state_tmp" "$DAILY_SNAPSHOT_STATE_FILE"

    if [ "$silent_mode" != "true" ]; then
        echo -e "${GREEN}✓ 日报快照采集完成：$day_key${NC}"
    fi
}

show_daily_report_for_day() {
    local day_key="$1"
    ensure_daily_usage_files

    if ! jq -e --arg day "$day_key" '.days[$day]' "$DAILY_USAGE_FILE" >/dev/null 2>&1; then
        echo -e "${YELLOW}$day_key 暂无日报数据${NC}"
        return 1
    fi

    local total_actual=$(jq -r --arg day "$day_key" '.days[$day].total_raw // .days[$day].total_actual // 0' "$DAILY_USAGE_FILE")

    echo -e "${BLUE}=== $day_key 日报 ===${NC}"
    print_daily_snapshot_notice
    echo -e "实际端口流量: ${GREEN}$(format_bytes "$total_actual")${NC}"
    echo "────────────────────────────────────────────────────────"

    local ports=($(jq -r --arg day "$day_key" '.days[$day].ports | keys[]?' "$DAILY_USAGE_FILE" 2>/dev/null | sort -n))
    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "${YELLOW}该日暂无端口明细${NC}"
        return 0
    fi

    for port in "${ports[@]}"; do
        local actual=$(jq -r --arg day "$day_key" --arg port "$port" '.days[$day].ports[$port] | if type == "object" then .raw // .actual // 0 else . // 0 end' "$DAILY_USAGE_FILE")
        echo -e "端口 ${GREEN}$port${NC} | 实际流量: ${GREEN}$(format_bytes "$actual")${NC}"
    done
}

show_recent_7_days_trend() {
    ensure_daily_usage_files
    local sum_actual=0

    echo -e "${BLUE}=== 近7日趋势报表 ===${NC}"
    print_daily_snapshot_notice
    echo "日期 | 实际端口流量"
    echo "────────────────────────────────────────────────────────"

    for ((i=6; i>=0; i--)); do
        local day_key=$(get_beijing_time -d "-$i day" +%F)
        local day_actual=$(jq -r --arg day "$day_key" '.days[$day].total_raw // .days[$day].total_actual // 0' "$DAILY_USAGE_FILE" 2>/dev/null || echo "0")
        sum_actual=$((sum_actual + day_actual))
        echo "$day_key | $(format_bytes "$day_actual")"
    done

    echo "────────────────────────────────────────────────────────"
    echo -e "7日合计: ${GREEN}$(format_bytes "$sum_actual")${NC}"
}

manage_daily_usage_reports() {
    echo -e "${BLUE}=== 流量日报与趋势报表 ===${NC}"
    print_traffic_scope_notice
    echo "────────────────────────────────────────────────────────"
    echo "1. 立即采集快照"
    echo "2. 查看昨日报表"
    echo "3. 查看近7日趋势"
    echo "4. 查看指定日期报表"
    echo "0. 返回主菜单"
    read_trimmed choice "请选择 [0-4]: "

    case $choice in
        1)
            collect_daily_usage_snapshot
            echo
            read -r -p "按回车返回..." || true
            manage_daily_usage_reports
            ;;
        2)
            local day_key=$(get_beijing_time -d "yesterday" +%F)
            show_daily_report_for_day "$day_key"
            echo
            read -r -p "按回车返回..."
            manage_daily_usage_reports
            ;;
        3)
            show_recent_7_days_trend
            echo
            read -r -p "按回车返回..."
            manage_daily_usage_reports
            ;;
        4)
            read_trimmed day_input "请输入日期 (YYYY-MM-DD): "
            if [[ ! "$day_input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                echo -e "${RED}日期格式错误${NC}"
                sleep 1
                manage_daily_usage_reports
                return
            fi
            if ! get_beijing_time -d "$day_input" +%F >/dev/null 2>&1; then
                echo -e "${RED}无效日期${NC}"
                sleep 1
                manage_daily_usage_reports
                return
            fi
            show_daily_report_for_day "$day_input"
            echo
            read -r -p "按回车返回..."
            manage_daily_usage_reports
            ;;
        0)
            show_main_menu
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            sleep 1
            manage_daily_usage_reports
            ;;
    esac
}

format_port_list() {
    local format_type="$1"
    local active_ports=($(get_active_ports))
    local result=""
    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
        local input_bytes=${traffic_data[0]}
        local output_bytes=${traffic_data[1]}
        local total_bytes=$((input_bytes + output_bytes))
        local total_formatted=$(format_bytes $total_bytes)
        local status_label=$(get_port_status_label "$port")

        if [ "$format_type" = "display" ]; then
            echo -e "端口:${GREEN}$port${NC} | 实际流量:${GREEN}$total_formatted${NC} | ${YELLOW}$status_label${NC}"
        elif [ "$format_type" = "display_detail" ]; then
            echo -e "端口:${GREEN}$port${NC} | input:${GREEN}$(format_bytes "$input_bytes")${NC} | output:${GREEN}$(format_bytes "$output_bytes")${NC} | total:${GREEN}$total_formatted${NC} | ${YELLOW}$status_label${NC}"
        elif [ "$format_type" = "markdown" ]; then
            result+="> 端口:**${port}** | 实际流量:**${total_formatted}** | ${status_label}\n"
        else
            result+="\n端口:${port} | 实际流量:${total_formatted} | ${status_label}"
        fi
    done
    if [ "$format_type" = "message" ] || [ "$format_type" = "markdown" ]; then
        echo -e "$result"
    fi
}

show_detailed_port_usage() {
    clear
    local active_ports=($(get_active_ports))
    local counter_snapshot_ok=true
    if ! validate_traffic_counter_snapshot; then
        counter_snapshot_ok=false
        NFT_COUNTER_SNAPSHOT=""
    fi

    echo -e "${BLUE}=== 端口流量详细视图 ===${NC}"
    print_traffic_scope_notice
    echo "────────────────────────────────────────────────────────"
    if [ "$counter_snapshot_ok" != "true" ]; then
        echo -e "${RED}nftables counter 不完整，未显示流量数字。请运行 health 检查。${NC}"
    elif [ ${#active_ports[@]} -gt 0 ]; then
        format_port_list "display_detail"
    else
        echo -e "${YELLOW}暂无监控端口${NC}"
    fi
    echo "────────────────────────────────────────────────────────"
    read -r -p "按回车返回主菜单..."
    show_main_menu
}

show_main_menu() {
    clear
    local active_ports=($(get_active_ports))
    local port_count=${#active_ports[@]}
    local counter_snapshot_ok=true
    local port_actual_total
    port_actual_total="$(ui_text '统计不可用' 'Unavailable' 'Недоступно')"
    if validate_traffic_counter_snapshot; then
        port_actual_total=$(get_daily_total_traffic)
    else
        counter_snapshot_ok=false
        NFT_COUNTER_SNAPSHOT=""
    fi

    echo -e "${BLUE}=== $(ui_text '端口流量狗' 'Port Traffic Dog' 'Монитор трафика портов') v$SCRIPT_VERSION ===${NC}"
    echo -e "${GREEN}$(ui_text '原项目' 'Original project' 'Исходный проект'):${NC}https://github.com/zywe03/realm-xwPF"
    echo -e "${GREEN}VPS-Optimize: https://github.com/Chunlion/VPS-Optimize | $(ui_text '快捷命令' 'Command' 'Команда'): dog${NC}"
    echo -e "${YELLOW}$(ui_text '按端口统计流量、设置配额/限速、查看日报趋势和 Telegram 报告。' 'Monitor traffic by port, manage quotas/rate limits, and view daily trends or Telegram reports.' 'Контролируйте трафик по портам, квоты/лимиты скорости, дневные отчёты и Telegram-уведомления.')${NC}"
    echo -e "${YELLOW}$(ui_text '快捷输入：add、limit、tg、report、detail、health、lang、u、q。' 'Shortcuts: add, limit, tg, report, detail, health, lang, u, q.' 'Быстрые команды: add, limit, tg, report, detail, health, lang, u, q.')${NC}"
    echo
    echo -e "${GREEN}$(ui_text '状态：监控中' 'Status: monitoring' 'Статус: мониторинг')${NC} | ${BLUE}$(ui_text '监控端口' 'Monitored ports' 'Отслеживаемые порты'): ${port_count}${NC}"
    echo -e "${YELLOW}$(ui_text '实际端口总流量' 'Actual monitored-port traffic' 'Фактический трафик отслеживаемых портов'): $port_actual_total${NC}"
    echo "────────────────────────────────────────────────────────"

    if [ "$counter_snapshot_ok" != "true" ]; then
        echo -e "${RED}$(ui_text 'nftables counter 不完整，未显示流量数字。请使用 health 检查。' 'nftables counters are incomplete; traffic values are hidden. Run health.' 'Счётчики nftables неполные; значения трафика скрыты. Запустите health.')${NC}"
    elif [ $port_count -gt 0 ]; then
        format_port_list "display"
    else
        echo -e "${YELLOW}$(ui_text '暂无监控端口' 'No monitored ports.' 'Нет отслеживаемых портов.')${NC}"
    fi

    echo "────────────────────────────────────────────────────────"
    echo -e "${BLUE}1.${NC} $(ui_text '端口监控' 'Port monitoring' 'Мониторинг портов')       ${BLUE}2.${NC} $(ui_text '配额与限速' 'Quotas and rate limits' 'Квоты и лимиты скорости')"
    echo -e "${BLUE}3.${NC} $(ui_text '流量重置' 'Traffic reset' 'Сброс трафика')         ${BLUE}4.${NC} $(ui_text '导出/导入配置' 'Export/import config' 'Экспорт/импорт конфигурации')"
    echo -e "${BLUE}5.${NC} $(ui_text '更新脚本' 'Update script' 'Обновить сценарий')        ${BLUE}6.${NC} $(ui_text '卸载' 'Uninstall' 'Удалить')"
    echo -e "${BLUE}7.${NC} $(ui_text 'Telegram 通知' 'Telegram notifications' 'Уведомления Telegram')  ${BLUE}8.${NC} $(ui_text '日报与趋势' 'Daily reports and trends' 'Дневные отчёты и тренды')"
    echo -e "${BLUE}l.${NC} $(ui_text '界面语言' 'Interface language' 'Язык интерфейса')        ${BLUE}0.${NC} $(ui_text '退出' 'Exit' 'Выход')"
    echo
    read_trimmed choice "$(ui_text '请选择 [0-8 或快捷词]: ' 'Select [0-8 or shortcut]: ' 'Выберите [0-8 или команду]: ')"
    choice=$(normalize_main_choice "$choice")

    case $choice in
        1) manage_port_monitoring ;;
        2) manage_traffic_limits ;;
        3) manage_traffic_reset ;;
        4) manage_configuration ;;
        5) install_update_script ;;
        6) uninstall_script ;;
        7) manage_notifications ;;
        8) manage_daily_usage_reports ;;
        detail) show_detailed_port_usage ;;
        health)
            show_statistics_health_check
            echo
            read -r -p "$(ui_text '按回车返回主菜单...' 'Press Enter to return to the main menu...' 'Нажмите Enter для возврата в главное меню...')"
            show_main_menu
            ;;
        language) select_ui_language; sleep 1; show_main_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}$(ui_text '无效选择，请输入 0-8 或快捷词。' 'Invalid selection. Enter 0-8 or a shortcut.' 'Неверный выбор. Введите 0-8 или команду.')${NC}"; sleep 1; show_main_menu ;;
    esac
}

manage_port_monitoring() {
    echo -e "${BLUE}=== $(ui_text '端口监控' 'Port monitoring' 'Мониторинг портов') ===${NC}"
    echo "1. $(ui_text '添加端口监控' 'Add port monitoring' 'Добавить мониторинг порта')"
    echo "2. $(ui_text '删除端口监控' 'Remove port monitoring' 'Удалить мониторинг порта')"
    echo "0. $(ui_text '返回主菜单' 'Back to main menu' 'Назад в главное меню')"
    read_trimmed choice "$(ui_text '请选择 [0-2]: ' 'Select [0-2]: ' 'Выберите [0-2]: ')"
    case $choice in
        1) add_port_monitoring ;;
        2) remove_port_monitoring ;;
        0) show_main_menu ;;
        *) echo -e "${RED}$(ui_text '无效选择。' 'Invalid selection.' 'Неверный выбор.')${NC}"; sleep 1; manage_port_monitoring ;;
    esac
}

add_port_monitoring() {
    echo -e "${BLUE}=== 添加端口监控 ===${NC}"
    echo
    echo -e "${GREEN}当前系统端口使用情况:${NC}"
    printf "%-15s %-9s\n" "程序名" "端口"
    echo "────────────────────────────────────────────────────────"

    declare -A program_ports
    while read -r line; do # 修复: 加入 -r 防止反斜杠丢失
        if [[ "$line" =~ LISTEN|UNCONN ]]; then
            # 修复: 加入 local 限定作用域，防止全局污染
            local local_addr=$(echo "$line" | awk '{print $5}')
            local port=$(echo "$local_addr" | grep -o ':[0-9]*$' | cut -d':' -f2)
            local program=$(echo "$line" | awk '{print $7}' | cut -d'"' -f2 2>/dev/null || echo "")
            if [ -n "$port" ] && [ -n "$program" ] && [ "$program" != "-" ]; then
               if [ -z "${program_ports[$program]:-}" ]; then
                    program_ports[$program]="$port"
                else
                    if [[ ! "${program_ports[$program]}" =~ (^|.*\|)$port(\||$) ]]; then
                        program_ports[$program]="${program_ports[$program]}|$port"
                    fi
                fi
            fi
        fi
    done < <(ss -tulnp 2>/dev/null || true)

    if [ ${#program_ports[@]} -gt 0 ]; then
        for program in $(printf '%s\n' "${!program_ports[@]}" | sort); do
            local ports="${program_ports[$program]}" # 修复: 声明为 local
            printf "%-10s | %-9s\n" "$program" "$ports"
        done
    else
        echo "无活跃端口"
    fi

    echo "────────────────────────────────────────────────────────"
    read_trimmed port_input "请输入要监控的端口号（多端口使用逗号,分隔,端口段使用-分隔）: "
    if [ -z "$port_input" ] || [ "$port_input" = "0" ]; then
        echo -e "${YELLOW}已取消添加端口监控${NC}"
        sleep 1
        manage_port_monitoring
        return
    fi

    local PORTS=()
    if ! parse_port_range_input "$port_input" PORTS; then
        sleep 2
        manage_port_monitoring
        return
    fi
    local valid_ports=()

    for port in "${PORTS[@]}"; do
        if jq -e ".ports.\"$port\"" "$CONFIG_FILE" >/dev/null 2>&1; then
            echo -e "${YELLOW}端口 $port 已在监控列表中，跳过${NC}"
            continue
        fi
        valid_ports+=("$port")
    done

    if [ ${#valid_ports[@]} -eq 0 ]; then
        echo -e "${RED}没有有效的端口可添加${NC}"
        sleep 2
        manage_port_monitoring
        return
    fi

    echo
    local port_list=$(IFS=','; echo "${valid_ports[*]}")
    while true; do
        echo "请输入配额值（0为无限制）（要带单位MB/GB/T）:"
        read_trimmed quota_input "流量配额(回车默认0): "
        if [ -z "$quota_input" ]; then quota_input="0"; fi

        local QUOTAS=()
        parse_comma_separated_input "$quota_input" QUOTAS

        local all_valid=true
        for quota in "${QUOTAS[@]}"; do
            if [ "$quota" != "0" ] && ! validate_quota "$quota"; then
                echo -e "${RED}配额格式错误: $quota${NC}"
                all_valid=false
                break
            fi
        done

        if [ "$all_valid" = false ]; then continue; fi

        expand_single_value_to_array QUOTAS ${#valid_ports[@]}
        if [ ${#QUOTAS[@]} -ne ${#valid_ports[@]} ]; then
            echo -e "${RED}配额值数量与端口数量不匹配${NC}"
            continue
        fi
        break
    done

    echo
    read_trimmed remark_input "请输入当前规则备注(可选，直接回车跳过): "
    local REMARKS=()
    if [ -n "$remark_input" ]; then
        parse_comma_separated_input "$remark_input" REMARKS
        expand_single_value_to_array REMARKS ${#valid_ports[@]}
        if [ ${#REMARKS[@]} -ne ${#valid_ports[@]} ]; then
            echo -e "${RED}备注数量与端口数量不匹配${NC}"
            sleep 2
            add_port_monitoring
            return
        fi
    fi

    local added_count=0
    for i in "${!valid_ports[@]}"; do
        local port="${valid_ports[$i]}"
        local quota=$(echo "${QUOTAS[$i]}" | tr -d ' ')
        local remark=""
        if [ ${#REMARKS[@]} -gt $i ]; then remark=$(echo "${REMARKS[$i]}" | tr -d ' '); fi

        local quota_enabled="true"
        local monthly_limit="unlimited"
        if [ "$quota" != "0" ] && [ -n "$quota" ]; then monthly_limit="$quota"; fi

        local quota_config
        if [ "$monthly_limit" != "unlimited" ]; then
            quota_config="{\"enabled\": $quota_enabled, \"monthly_limit\": \"$monthly_limit\", \"reset_day\": 1}"
        else
            quota_config="{\"enabled\": $quota_enabled, \"monthly_limit\": \"$monthly_limit\"}"
        fi

        # 优化3：修复 JSON 注入问题，采用 jq 参数安全传递数据
        (
            flock -w 5 9 || exit 1
            jq --arg port "$port" \
               --arg remark "$remark" \
               --arg created "$(get_beijing_time -Iseconds)" \
               --argjson quota_conf "$quota_config" \
               '.ports[$port] = {
                   name: ("端口" + $port),
                   enabled: true,
                   bandwidth_limit: {enabled: false, rate: "unlimited"},
                   quota: $quota_conf,
                   remark: $remark,
                   created_at: $created
                }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        ) 9> "${CONFIG_DIR}/.config.lock" || { echo -e "${RED}配置文件正忙，跳过 $port${NC}"; continue; }

        add_nftables_rules "$port"
        if [ "$monthly_limit" != "unlimited" ]; then apply_nftables_quota "$port" "$quota"; fi
        setup_port_auto_reset_cron "$port"
        added_count=$((added_count + 1))
    done

    echo -e "${GREEN}成功添加 $added_count 个端口监控${NC}"
    sleep 2
    manage_port_monitoring
}

remove_port_monitoring() {
    echo -e "${BLUE}=== 删除端口监控 ===${NC}"
    local active_ports=($(get_active_ports))
    if ! show_port_list; then sleep 2; manage_port_monitoring; return; fi
    echo

    read_trimmed choice_input "请选择要删除的端口（多端口使用逗号,分隔）: "
    if [ -z "$choice_input" ] || [ "$choice_input" = "0" ]; then
        echo -e "${YELLOW}已取消删除端口监控${NC}"
        sleep 1
        manage_port_monitoring
        return
    fi
    local valid_choices=()
    local ports_to_delete=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices

    for choice in "${valid_choices[@]}"; do
        ports_to_delete+=("${active_ports[$((choice-1))]}")
    done

    if [ ${#ports_to_delete[@]} -eq 0 ]; then
        echo -e "${RED}没有有效的端口可删除${NC}"
        sleep 2; remove_port_monitoring; return
    fi

    read_trimmed confirm "确认删除这些端口的监控? [Y/n]: "
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local deleted_count=0
        for port in "${ports_to_delete[@]}"; do
            remove_nftables_rules "$port"
            remove_nftables_quota "$port"
            remove_tc_limit "$port"
            update_config "del(.ports.\"$port\")"

            local history_file="$CONFIG_DIR/reset_history.log"
            if [ -f "$history_file" ]; then
                grep -v "|$port|" "$history_file" > "${history_file}.tmp" 2>/dev/null || true
                mv "${history_file}.tmp" "$history_file" 2>/dev/null || true
            fi
            remove_port_auto_reset_cron "$port"
            deleted_count=$((deleted_count + 1))
        done
        echo -e "${GREEN}成功删除 $deleted_count 个端口监控${NC}"
        echo "正在清理网络状态..."
        for port in "${ports_to_delete[@]}"; do
            if is_port_range "$port"; then
                local start_port=$(echo "$port" | cut -d'-' -f1)
                local end_port=$(echo "$port" | cut -d'-' -f2)
                for ((p=start_port; p<=end_port; p++)); do
                    conntrack -D -p tcp --dport $p 2>/dev/null || true
                    conntrack -D -p udp --dport $p 2>/dev/null || true
                done
            else
                conntrack -D -p tcp --dport $port 2>/dev/null || true
                conntrack -D -p udp --dport $port 2>/dev/null || true
            fi
        done
        echo -e "${GREEN}网络状态已清理，现有连接的限制应该已解除${NC}"
    fi
    sleep 2
    manage_port_monitoring
}

port_nftables_rules_are_exact() {
    local port="$1"
    local input_chain="${2:-}"
    local output_chain="${3:-}"
    local forward_chain="${4:-}"
    local port_safe
    local counter_in
    local counter_out
    local input_count
    local output_count
    local forward_in_count
    local forward_out_count

    port_safe=$(echo "$port" | tr '-' '_')
    counter_in="port_${port_safe}_in"
    counter_out="port_${port_safe}_out"
    input_count=$(grep -Fc "counter name \"$counter_in\"" <<< "$input_chain" || true)
    output_count=$(grep -Fc "counter name \"$counter_out\"" <<< "$output_chain" || true)
    forward_in_count=$(grep -Fc "counter name \"$counter_in\"" <<< "$forward_chain" || true)
    forward_out_count=$(grep -Fc "counter name \"$counter_out\"" <<< "$forward_chain" || true)

    [ "$input_count" -eq 2 ] && [ "$output_count" -eq 2 ] && \
        [ "$forward_in_count" -eq 2 ] && [ "$forward_out_count" -eq 2 ]
}

# 原子修复并应用 nftables 计数规则，避免缺失或重复规则造成漏算、重复计数。
add_nftables_rules() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    local batch_cmds=""
    local port_safe=$(echo "$port" | tr '-' '_')
    local counter_in="port_${port_safe}_in"
    local counter_out="port_${port_safe}_out"
    local input_chain
    local output_chain
    local forward_chain
    local chain
    local chain_rules
    local handle

    input_chain=$(nft -a list chain "$family" "$table_name" input 2>/dev/null || true)
    output_chain=$(nft -a list chain "$family" "$table_name" output 2>/dev/null || true)
    forward_chain=$(nft -a list chain "$family" "$table_name" forward 2>/dev/null || true)
    if port_nftables_rules_are_exact "$port" "$input_chain" "$output_chain" "$forward_chain"; then
        return 0
    fi

    for chain in input output forward; do
        case "$chain" in
            input) chain_rules="$input_chain" ;;
            output) chain_rules="$output_chain" ;;
            forward) chain_rules="$forward_chain" ;;
        esac
        while IFS= read -r handle; do
            [ -n "$handle" ] && batch_cmds+="delete rule $family $table_name $chain handle $handle\n"
        done < <(
            grep -F -e "counter name \"$counter_in\"" -e "counter name \"$counter_out\"" <<< "$chain_rules" \
                | sed -n 's/.*# handle \([0-9]\+\)$/\1/p'
        )
    done

    # 智能处理匹配表达式（兼容单端口和端口段）
    local match_expr="dport $port"
    local sport_expr="sport $port"
    if is_port_range "$port"; then
        local mark_id=$(generate_port_range_mark "$port")
        match_expr="dport $port meta mark set $mark_id"
        sport_expr="sport $port meta mark set $mark_id"
    fi

    # 1. 注入响应方向计数规则
    nft list counter "$family" "$table_name" "$counter_out" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name $counter_out\n"
    for proto in tcp udp; do
        batch_cmds+="add rule $family $table_name output $proto $sport_expr counter name \"$counter_out\"\n"
        batch_cmds+="add rule $family $table_name forward $proto $sport_expr counter name \"$counter_out\"\n"
    done

    # 2. 注入请求方向计数规则
    nft list counter "$family" "$table_name" "$counter_in" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name $counter_in\n"
    for proto in tcp udp; do
        batch_cmds+="add rule $family $table_name input $proto $match_expr counter name \"$counter_in\"\n"
        batch_cmds+="add rule $family $table_name forward $proto $match_expr counter name \"$counter_in\"\n"
    done

    if [ -n "$batch_cmds" ]; then
        if ! printf '%b' "$batch_cmds" | nft -f - 2>/dev/null; then
            echo -e "${RED}端口 $port 的 nftables 计数规则应用失败。${NC}" >&2
            return 1
        fi
    fi
}

remove_nftables_rules() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")

    # 锚定到计数器全名（含 in/out 后缀和收尾引号），防止把
    # 端口段规则误删（例如删除端口 80 时波及 80-90 的 port_80_90_in）
    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        local search_pattern="port_${port_safe}_(in|out)\""
    else
        local search_pattern="port_${port}_(in|out)\""
    fi

    local deleted_count=0
    while true; do
        local handle=$(nft -a list table "$family" "$table_name" 2>/dev/null | grep -E "(tcp|udp).*(dport|sport).*$search_pattern" | head -n1 | sed -n 's/.*# handle \([0-9]\+\)$/\1/p')
        if [ -z "$handle" ]; then break; fi
        for chain in input output forward; do
            if nft delete rule "$family" "$table_name" "$chain" handle "$handle" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                break
            fi
        done
        if [ $deleted_count -ge 150 ]; then break; fi
    done

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        nft delete counter "$family" "$table_name" "port_${port_safe}_in" 2>/dev/null || true
        nft delete counter "$family" "$table_name" "port_${port_safe}_out" 2>/dev/null || true
    else
        nft delete counter "$family" "$table_name" "port_${port}_in" 2>/dev/null || true
        nft delete counter "$family" "$table_name" "port_${port}_out" 2>/dev/null || true
    fi
}

set_port_bandwidth_limit() {
    echo -e "${BLUE}设置端口带宽限制${NC}"
    local active_ports=($(get_active_ports))
    if ! show_port_list; then sleep 2; manage_traffic_limits; return; fi

    read_trimmed choice_input "请选择要限制的端口（多端口使用逗号,分隔） [1-${#active_ports[@]}]: "
    if [ -z "$choice_input" ] || [ "$choice_input" = "0" ]; then
        echo -e "${YELLOW}已取消设置带宽限制${NC}"
        sleep 1
        manage_traffic_limits
        return
    fi
    local valid_choices=()
    local ports_to_limit=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices

    for choice in "${valid_choices[@]}"; do
        ports_to_limit+=("${active_ports[$((choice-1))]}")
    done

    if [ ${#ports_to_limit[@]} -eq 0 ]; then
        echo -e "${RED}没有有效的端口可设置限制${NC}"
        sleep 2; set_port_bandwidth_limit; return
    fi

    local port_list=$(IFS=','; echo "${ports_to_limit[*]}")
    echo "请输入限制值（0为无限制）（要带单位Kbps/Mbps/Gbps）:"
    read_trimmed limit_input "带宽限制(回车取消): "
    if [ -z "$limit_input" ]; then
        echo -e "${YELLOW}已取消设置带宽限制${NC}"
        sleep 1
        manage_traffic_limits
        return
    fi

    local LIMITS=()
    parse_comma_separated_input "$limit_input" LIMITS
    expand_single_value_to_array LIMITS ${#ports_to_limit[@]}
    if [ ${#LIMITS[@]} -ne ${#ports_to_limit[@]} ]; then
        echo -e "${RED}限制值数量与端口数量不匹配${NC}"
        sleep 2; set_port_bandwidth_limit; return
    fi

    local success_count=0
    for i in "${!ports_to_limit[@]}"; do
        local port="${ports_to_limit[$i]}"
        local limit=$(echo "${LIMITS[$i]}" | tr -d ' ')

        if [ "$limit" = "0" ] || [ -z "$limit" ]; then
            remove_tc_limit "$port"
            update_config ".ports.\"$port\".bandwidth_limit.enabled = false | .ports.\"$port\".bandwidth_limit.rate = \"unlimited\""
            echo -e "${GREEN}端口 $port 带宽限制已移除${NC}"
            success_count=$((success_count + 1))
            continue
        fi

        remove_tc_limit "$port"
     
        if ! validate_bandwidth "$limit"; then
            echo -e "${RED}端口 $port 格式错误${NC}"
            continue
        fi

        local tc_limit=$(convert_bandwidth_to_tc "$limit")
        apply_tc_limit "$port" "$tc_limit"
        update_config ".ports.\"$port\".bandwidth_limit.enabled = true | .ports.\"$port\".bandwidth_limit.rate = \"$limit\""
        success_count=$((success_count + 1))
    done
    echo -e "${GREEN}成功设置 $success_count 个端口的带宽限制${NC}"
    sleep 3; manage_traffic_limits
}

set_port_quota_limit() {
    echo -e "${BLUE}=== 设置端口流量配额 ===${NC}"
    local active_ports=($(get_active_ports))
    if ! show_port_list; then sleep 2; manage_traffic_limits; return; fi
    read_trimmed choice_input "请选择要设置配额的端口（多端口使用逗号,分隔） [1-${#active_ports[@]}]: "
    if [ -z "$choice_input" ] || [ "$choice_input" = "0" ]; then
        echo -e "${YELLOW}已取消设置流量配额${NC}"
        sleep 1
        manage_traffic_limits
        return
    fi

    local valid_choices=()
    local ports_to_quota=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices

    for choice in "${valid_choices[@]}"; do
        ports_to_quota+=("${active_ports[$((choice-1))]}")
    done

    if [ ${#ports_to_quota[@]} -eq 0 ]; then
        echo -e "${RED}没有有效的端口可设置配额${NC}"
        sleep 2; set_port_quota_limit; return
    fi

    while true; do
        echo "请输入配额值（0为无限制）（要带单位MB/GB/T）:"
        read_trimmed quota_input "流量配额(回车默认0): "
        if [ -z "$quota_input" ]; then quota_input="0"; fi

        local QUOTAS=()
        parse_comma_separated_input "$quota_input" QUOTAS

        local all_valid=true
        for quota in "${QUOTAS[@]}"; do
            if [ "$quota" != "0" ] && ! validate_quota "$quota"; then
                echo -e "${RED}配额格式错误: $quota${NC}"
                all_valid=false; break
            fi
        done
        if [ "$all_valid" = false ]; then continue; fi
        expand_single_value_to_array QUOTAS ${#ports_to_quota[@]}
        if [ ${#QUOTAS[@]} -ne ${#ports_to_quota[@]} ]; then
            echo -e "${RED}配额值数量与端口数量不匹配${NC}"
            continue
        fi
        break
    done

    local success_count=0
    for i in "${!ports_to_quota[@]}"; do
        local port="${ports_to_quota[$i]}"
        local quota=$(echo "${QUOTAS[$i]}" | tr -d ' ')

        if [ "$quota" = "0" ] || [ -z "$quota" ]; then
            remove_nftables_quota "$port"
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"unlimited\" | del(.ports.\"$port\".quota.reset_day) | del(.ports.\"$port\".quota.billing_mode)"
            remove_port_auto_reset_cron "$port"
            success_count=$((success_count + 1))
            continue
        fi

        remove_nftables_quota "$port"
        apply_nftables_quota "$port" "$quota"
        local current_monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE")
        
        if [ "$current_monthly_limit" = "unlimited" ]; then
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"$quota\" | .ports.\"$port\".quota.reset_day = 1 | del(.ports.\"$port\".quota.billing_mode)"
        else
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"$quota\" | del(.ports.\"$port\".quota.billing_mode)"
        fi
        
        setup_port_auto_reset_cron "$port"
        success_count=$((success_count + 1))
    done
    echo -e "${GREEN}成功设置 $success_count 个端口的流量配额${NC}"
    sleep 3; manage_traffic_limits
}

manage_traffic_limits() {
    echo -e "${BLUE}=== $(ui_text '配额与限速' 'Quotas and rate limits' 'Квоты и лимиты скорости') ===${NC}"
    echo "1. $(ui_text '设置端口带宽限制（速率控制）' 'Set port bandwidth limit (rate control)' 'Ограничить скорость порта')"
    echo "2. $(ui_text '设置端口流量配额（总量控制）' 'Set port traffic quota (volume control)' 'Задать квоту трафика порта')"
    echo "0. $(ui_text '返回主菜单' 'Back to main menu' 'Назад в главное меню')"
    read_trimmed choice "$(ui_text '请选择 [0-2]: ' 'Select [0-2]: ' 'Выберите [0-2]: ')"
    case $choice in
        1) set_port_bandwidth_limit ;;
        2) set_port_quota_limit ;;
        0) show_main_menu ;;
        *) echo -e "${RED}$(ui_text '无效选择。' 'Invalid selection.' 'Неверный выбор.')${NC}"; sleep 1; manage_traffic_limits ;;
    esac
}

# 优化5：批量应用 nftables 配额限制规则
apply_nftables_quota() {
    local port=$1
    local quota_limit=$2
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    local quota_bytes=$(parse_size_to_bytes "$quota_limit")

    local current_traffic=($(get_nftables_counter_data "$port"))
    local current_actual_total=$(( ${current_traffic[0]} + ${current_traffic[1]} ))
    local effective_quota_bytes=$quota_bytes
    local effective_used_bytes=$current_actual_total
    local batch_cmds=""

    local port_safe=$(echo "$port" | tr '-' '_')
    local quota_name="port_${port_safe}_quota"

    # 恢复路径会在每次运行时反复调用本函数：若内核中已有引用该配额的规则，
    # 直接跳过，防止 drop 规则不断叠加导致同一数据包被多条规则重复计入配额
    if nft list table "$family" "$table_name" 2>/dev/null | grep -Fq "quota name \"$quota_name\""; then
        return 0
    fi

    nft delete quota "$family" "$table_name" "$quota_name" 2>/dev/null || true
    nft add quota "$family" "$table_name" "$quota_name" { over "$effective_quota_bytes" bytes used "$effective_used_bytes" bytes } 2>/dev/null || true

    # 配额按被监控端口的实际流量累计。
    for proto in tcp udp; do
        batch_cmds+="insert rule $family $table_name output $proto sport $port quota name \"$quota_name\" drop\n"
        batch_cmds+="insert rule $family $table_name forward $proto sport $port quota name \"$quota_name\" drop\n"
        batch_cmds+="insert rule $family $table_name input $proto dport $port quota name \"$quota_name\" drop\n"
        batch_cmds+="insert rule $family $table_name forward $proto dport $port quota name \"$quota_name\" drop\n"
    done

    if [ -n "$batch_cmds" ]; then
        echo -e "$batch_cmds" | nft -f - 2>/dev/null || true
    fi
}

remove_nftables_quota() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        local quota_name="port_${port_safe}_quota"
    else
        local quota_name="port_${port}_quota"
    fi

    local deleted_count=0
    while true; do
        local handle=$(nft -a list table "$family" "$table_name" 2>/dev/null | grep "quota name \"$quota_name\"" | head -n1 | sed -n 's/.*# handle \([0-9]\+\)$/\1/p')
        if [ -z "$handle" ]; then break; fi
        for chain in input output forward; do
            if nft delete rule "$family" "$table_name" "$chain" handle "$handle" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                break
            fi
        done
        if [ $deleted_count -ge 150 ]; then break; fi
    done
    nft delete quota "$family" "$table_name" "$quota_name" 2>/dev/null || true
}

apply_tc_limit() {
    local port=$1
    local total_limit=$2
    local interface=$(get_default_interface)

    tc qdisc add dev $interface root handle 1: htb default 30 2>/dev/null || true
    # [修复]: 将写死的 1Gbps 根节点上限提升为 100Gbps，防止误伤万兆网卡
    tc class add dev $interface parent 1: classid 1:1 htb rate 100000mbit 2>/dev/null || true

    local class_id=$(generate_tc_class_id "$port")
    tc class del dev $interface classid $class_id 2>/dev/null || true

    local base_rate=$(parse_tc_rate_to_kbps "$total_limit")
    local burst_bytes=$(calculate_tc_burst "$base_rate")
    local burst_size=$(format_tc_burst "$burst_bytes")

    # 创建失败时给出警告但不中断脚本（set -e 下裸命令失败会导致整个脚本
    # 在启动恢复阶段直接退出，例如根 qdisc 已被其他工具占用时）
    if ! tc class add dev $interface parent 1:1 classid $class_id htb rate $total_limit ceil $total_limit burst $burst_size 2>/dev/null; then
        echo -e "${YELLOW}警告：在网卡 $interface 上创建限速类失败，端口 $port 的带宽限制未生效。${NC}" >&2
        return 0
    fi

    if is_port_range "$port"; then
        local mark_id=$(generate_port_range_mark "$port")
        tc filter add dev $interface protocol ip parent 1:0 prio 1 handle $mark_id fw flowid $class_id 2>/dev/null || true
    else
        local filter_prio=$((port % 1000 + 1))
        tc filter add dev $interface protocol ip parent 1:0 prio $filter_prio u32 match ip protocol 6 0xff match ip sport $port 0xffff flowid $class_id 2>/dev/null || true
        tc filter add dev $interface protocol ip parent 1:0 prio $filter_prio u32 match ip protocol 6 0xff match ip dport $port 0xffff flowid $class_id 2>/dev/null || true
        tc filter add dev $interface protocol ip parent 1:0 prio $((filter_prio + 1000)) u32 match ip protocol 17 0xff match ip sport $port 0xffff flowid $class_id 2>/dev/null || true
        tc filter add dev $interface protocol ip parent 1:0 prio $((filter_prio + 1000)) u32 match ip protocol 17 0xff match ip dport $port 0xffff flowid $class_id 2>/dev/null || true
    fi
}

remove_tc_limit() {
    local port=$1
    local interface=$(get_default_interface)
    local class_id=$(generate_tc_class_id "$port")

    if is_port_range "$port"; then
        local mark_id=$(generate_port_range_mark "$port")
        local mark_hex=$(printf '0x%x' "$mark_id")
        tc filter del dev $interface protocol ip parent 1:0 prio 1 handle $mark_hex fw 2>/dev/null || true
        tc filter del dev $interface protocol ip parent 1:0 prio 1 handle $mark_id fw 2>/dev/null || true
    else
        local filter_prio=$((port % 1000 + 1))
        tc filter del dev $interface protocol ip parent 1:0 prio $filter_prio u32 match ip protocol 6 0xff match ip sport $port 0xffff 2>/dev/null || true
        tc filter del dev $interface protocol ip parent 1:0 prio $filter_prio u32 match ip protocol 6 0xff match ip dport $port 0xffff 2>/dev/null || true
        tc filter del dev $interface protocol ip parent 1:0 prio $((filter_prio + 1000)) u32 match ip protocol 17 0xff match ip sport $port 0xffff 2>/dev/null || true
        tc filter del dev $interface protocol ip parent 1:0 prio $((filter_prio + 1000)) u32 match ip protocol 17 0xff match ip dport $port 0xffff 2>/dev/null || true
    fi
    tc class del dev $interface classid $class_id 2>/dev/null || true
}

manage_traffic_reset() {
    echo -e "${BLUE}$(ui_text '流量重置' 'Traffic reset' 'Сброс трафика')${NC}"
    echo "1. $(ui_text '每月流量重置日设置' 'Monthly reset day' 'День ежемесячного сброса')"
    echo "2. $(ui_text '立即重置' 'Reset now' 'Сбросить сейчас')"
    echo "0. $(ui_text '返回主菜单' 'Back to main menu' 'Назад в главное меню')"
    read_trimmed choice "$(ui_text '请选择 [0-2]: ' 'Select [0-2]: ' 'Выберите [0-2]: ')"
    case $choice in
        1) set_reset_day ;;
        2) immediate_reset ;;
        0) show_main_menu ;;
        *) echo -e "${RED}$(ui_text '无效选择。' 'Invalid selection.' 'Неверный выбор.')${NC}"; sleep 1; manage_traffic_reset ;;
    esac
}

set_reset_day() {
    echo -e "${BLUE}=== 设置端口每月重置日 ===${NC}"
    local active_ports=($(get_active_ports))
    if ! show_port_list; then sleep 2; manage_traffic_reset; return; fi
    
    read_trimmed choice_input "请选择要设置重置日期的端口序号（多端口逗号分隔）: "
    if [ -z "$choice_input" ] || [ "$choice_input" = "0" ]; then
        echo -e "${YELLOW}已取消设置重置日期${NC}"
        sleep 1
        manage_traffic_reset
        return
    fi
    local valid_choices=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices
    
    if [ ${#valid_choices[@]} -eq 0 ]; then
        echo -e "${RED}❌ 未选择有效端口，操作取消。${NC}"
        sleep 2
        manage_traffic_reset
        return
    fi
    
    read_trimmed reset_day "请输入每月的重置日期 (输入1-31，输入0代表取消自动重置): "
    
    if ! [[ "$reset_day" =~ ^[0-9]+$ ]] || [ "$reset_day" -lt 0 ] || [ "$reset_day" -gt 31 ]; then
        echo -e "${RED}❌ 输入无效，请输入 0-31 之间的数字！${NC}"
        sleep 2
        manage_traffic_reset
        return
    fi
    
    for choice in "${valid_choices[@]}"; do
        local port=${active_ports[$((choice-1))]}
        
        if [ "$reset_day" = "0" ]; then
            update_config "del(.ports.\"$port\".quota.reset_day)"
            remove_port_auto_reset_cron "$port"
        else
            update_config ".ports.\"$port\".quota.reset_day = $reset_day"
            setup_port_auto_reset_cron "$port"
        fi
    done
    
    echo -e "${GREEN}✅ 重置日期设置成功！${NC}"
    sleep 2
    manage_traffic_reset
}

immediate_reset() {
    echo -e "${BLUE}=== 立即重置端口流量 ===${NC}"
    local active_ports=($(get_active_ports))
    if ! show_port_list; then sleep 2; manage_traffic_reset; return; fi
    
    read_trimmed choice_input "请选择要立即重置的端口序号（多端口逗号分隔）: "
    if [ -z "$choice_input" ] || [ "$choice_input" = "0" ]; then
        echo -e "${YELLOW}已取消立即重置${NC}"
        sleep 1
        manage_traffic_reset
        return
    fi
    local valid_choices=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices
    
    if [ ${#valid_choices[@]} -eq 0 ]; then
        echo -e "${RED}❌ 未选择有效端口！${NC}"
        sleep 2; manage_traffic_reset; return
    fi

    if confirm_danger "立即清零端口流量" "选定端口的当前 nftables 计数和配额计数会被重置，历史实时统计不可恢复。"; then
        for choice in "${valid_choices[@]}"; do
            local port=${active_ports[$((choice-1))]}
            auto_reset_port "$port"
            echo -e "${GREEN}✅ 端口 $port 已清零！${NC}"
        done
    fi
    sleep 2
    manage_traffic_reset
}

auto_reset_port() {
    local port="$1"
    reset_port_nftables_counters "$port"
    echo "端口 $port 自动重置完成"
}
check_and_run_daily_resets() {
    # 获取今天日期，去掉前导 0 防止 Bash 当成八进制报错 (比如 08, 09)
    local today=$(TZ='Asia/Shanghai' date +%d | sed 's/^0//')
    local current_ym=$(TZ='Asia/Shanghai' date +%Y-%m)
    # 利用 GNU date 推算下个月第一天的前一天，完美获取当月最后一天
    local last_day=$(TZ='Asia/Shanghai' date -d "$current_ym-01 +1 month -1 day" +%d | sed 's/^0//')
    
    # 优化点：单次 jq 提取所有端口的核心配置项，极大降低系统开销
    local all_port_configs=$(jq -r '.ports | to_entries[] | "\(.key) \(.value.quota.enabled // false) \(.value.quota.monthly_limit // "unlimited") \(.value.quota.reset_day // "null")"' "$CONFIG_FILE" 2>/dev/null || true)
    
    if [ -z "$all_port_configs" ]; then return 0; fi

    echo "$all_port_configs" | while read -r port quota_enabled monthly_limit reset_day; do
        # 只要设置了重置日就生效——不再要求端口必须配置配额，
        # 保证"设置重置日期"菜单的承诺对无配额端口同样兑现
        if [ "$quota_enabled" = "true" ] && [ "$reset_day" != "null" ]; then
            local should_reset=false
            
            # 规则 1：今天刚好等于用户设定的重置日
            if [ "$today" -eq "$reset_day" ]; then
                should_reset=true
            # 规则 2：今天是本月最后一天，且用户设定的日期比今天大（完美补偿 31号 陷阱）
            elif [ "$today" -eq "$last_day" ] && [ "$reset_day" -gt "$last_day" ]; then
                should_reset=true
            fi
            
            if [ "$should_reset" = true ]; then
                auto_reset_port "$port"
            fi
        fi
    done
}

reset_port_nftables_counters() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        nft reset counter "$family" "$table_name" "port_${port_safe}_in" >/dev/null 2>&1 || true
        nft reset counter "$family" "$table_name" "port_${port_safe}_out" >/dev/null 2>&1 || true
        nft reset quota "$family" "$table_name" "port_${port_safe}_quota" >/dev/null 2>&1 || true
    else
        nft reset counter "$family" "$table_name" "port_${port}_in" >/dev/null 2>&1 || true
        nft reset counter "$family" "$table_name" "port_${port}_out" >/dev/null 2>&1 || true
        nft reset quota "$family" "$table_name" "port_${port}_quota" >/dev/null 2>&1 || true
    fi
}

manage_configuration() {
    echo -e "${BLUE}=== $(ui_text '配置导入与导出' 'Configuration import/export' 'Импорт/экспорт конфигурации') ===${NC}"
    echo "1. $(ui_text '导出配置包' 'Export configuration' 'Экспорт конфигурации')"
    echo "2. $(ui_text '导入配置包' 'Import configuration' 'Импорт конфигурации')"
    echo "0. $(ui_text '返回主菜单' 'Back to main menu' 'Назад в главное меню')"
    read_trimmed choice "$(ui_text '请选择 [0-2]: ' 'Select [0-2]: ' 'Выберите [0-2]: ')"
    case $choice in
        1) export_config ;;
        2) import_config ;;
        0) show_main_menu ;;
        *) echo -e "${RED}$(ui_text '无效选择。' 'Invalid selection.' 'Неверный выбор.')${NC}"; sleep 1; manage_configuration ;;
    esac
}

export_config() {
    local timestamp=$(get_beijing_time +%Y%m%d-%H%M%S)
    local backup_name="port-traffic-dog-config-${timestamp}.tar.gz"
    local backup_path="/root/${backup_name}"
    tar -czf "$backup_path" "$CONFIG_DIR" 2>/dev/null
    echo -e "${GREEN}配置包已导出到: $backup_path${NC}"
    sleep 2; manage_configuration
}

import_config() {
    read_trimmed package_path "配置包路径(回车取消): "
    if [ -z "$package_path" ]; then
        echo -e "${YELLOW}已取消导入${NC}"
    elif [ ! -f "$package_path" ]; then
        echo -e "${RED}文件不存在：$package_path${NC}"
    else
        if confirm_danger "导入配置包" "会把配置包内容解压到系统根目录，覆盖现有 Port Traffic Dog 配置。"; then
            if tar -tzf "$package_path" 2>/dev/null | awk '
                BEGIN { ok = 1; seen = 0 }
                /^\/|(^|\/)\.\.(\/|$)/ { ok = 0 }
                !/^etc\/port-traffic-dog(\/|$)/ && !/^\.\/etc\/port-traffic-dog(\/|$)/ { ok = 0 }
                /^etc\/port-traffic-dog(\/|$)/ || /^\.\/etc\/port-traffic-dog(\/|$)/ { seen = 1 }
                END { exit (ok && seen) ? 0 : 1 }
            '; then
                if tar -xzf "$package_path" -C / 2>/dev/null; then
                    echo -e "${GREEN}配置包已恢复，重启脚本生效。${NC}"
                else
                    echo -e "${RED}配置包解压失败，请检查文件是否完整。${NC}"
                fi
            else
                echo -e "${RED}配置包校验失败：仅允许导入 /etc/port-traffic-dog 内的相对路径。${NC}"
            fi
        fi
    fi
    sleep 2; manage_configuration
}

download_with_sources() {
    local url="$1"
    local output_file="$2"

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}错误：缺少 curl，无法下载远程脚本。${NC}"
        return 1
    fi

    if curl -fsSL --connect-timeout 5 --max-time 30 --retry 2 --retry-delay 1 --retry-connrefused "$url" -o "$output_file" 2>/dev/null; then
        if [ -s "$output_file" ]; then
            return 0
        fi
    fi
    return 1
}

install_update_script() {
    echo -e "${BLUE}=== 正在启动脚本热更新 ===${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "${YELLOW}正在从远程仓库获取最新版本...${NC}"

    local temp_file
    temp_file=$(mktemp /tmp/port-traffic-dog-update.XXXXXX.sh) || {
        echo -e "${RED}错误：临时文件创建失败，更新已取消。${NC}"
        read -r -p "按回车键返回菜单..."
        show_main_menu
        return
    }
    
    if download_with_sources "$SCRIPT_URL" "$temp_file"; then
        if [ -s "$temp_file" ] && grep -q "端口流量狗" "$temp_file" 2>/dev/null && bash -n "$temp_file" >/dev/null 2>&1; then
            # 先展示版本信息并确认，避免"检查"菜单项直接执行不可逆的替换重启
            local remote_version=$(grep -m1 '^readonly SCRIPT_VERSION=' "$temp_file" | cut -d'"' -f2)
            echo -e "当前版本: ${GREEN}${SCRIPT_VERSION}${NC}"
            echo -e "远程版本: ${GREEN}${remote_version:-未知}${NC}"
            if [ -n "$remote_version" ] && [ "$remote_version" = "$SCRIPT_VERSION" ]; then
                echo -e "${GREEN}当前已是最新版本。${NC}"
            fi
            read_trimmed update_confirm "确认更新并原地重启脚本？[Y/n]: "
            case "$update_confirm" in
                y|Y) ;;
                *)
                    rm -f "$temp_file"
                    echo -e "${YELLOW}已取消更新${NC}"
                    read -r -p "按回车键返回菜单..." || true
                    show_main_menu
                    return
                    ;;
            esac
            echo -e "${GREEN}下载成功，正在进行热替换...${NC}"

            mv "$temp_file" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            
            create_shortcut_command
            download_notification_modules >/dev/null 2>&1 || true

            echo -e "${GREEN}脚本更新完成！正在原地热重启...${NC}"
            echo "────────────────────────────────────────────────────────"
            sleep 1
            
            exec bash "$SCRIPT_PATH"
        else
            echo -e "${RED}错误：下载的文件验证失败或语法检查未通过，请检查网络或 URL。${NC}"
            rm -f "$temp_file"
        fi
    else
        echo -e "${RED}错误：下载失败，请检查服务器连接。${NC}"
        rm -f "$temp_file"
    fi

    read -r -p "按回车键返回菜单..."
    show_main_menu
}

uninstall_script() {
    echo -e "${BLUE}=== 卸载端口流量狗 ===${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "${YELLOW}将要执行以下操作:${NC}"
    echo "  1. 清除所有端口的流量监控规则 (nftables)" 
    echo "  2. 清除所有端口的带宽限制规则 (TC)"
    echo "  3. 删除本脚本注册的全部定时任务 (开机自启/数据存档/日报快照/自动重置)"
    echo "  4. 停止并隔离 TG 交互机器人后台服务 (Systemd)"
    echo "  5. 隔离快捷命令 dog"
    echo "  6. 隔离配置文件及日志 (/etc/port-traffic-dog)"
    echo "  7. 删除脚本本身" 
    echo
    echo -e "${RED}🔴 警告：此操作会移除当前 nftables/tc 运行规则，历史配置会尽量隔离保留。${NC}"
    if confirm_danger "卸载端口流量狗" "会删除 nftables/tc 运行规则、定时任务；机器人服务文件、快捷命令和配置目录会先隔离保留。" "隔离目录可用于手动恢复配置；重新运行脚本后可导入或比对旧配置。"; then
        echo -e "${YELLOW}正在全力卸载中...${NC}"

        local active_ports=($(get_active_ports 2>/dev/null || true))
        for port in "${active_ports[@]}"; do
            remove_nftables_rules "$port" 2>/dev/null || true
            remove_tc_limit "$port" 2>/dev/null || true
            remove_port_auto_reset_cron "$port" 2>/dev/null || true
        done

        local table_name
        local family
        table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE" 2>/dev/null || echo "port_traffic_monitor")
        family=$(jq -r '.nftables.family' "$CONFIG_FILE" 2>/dev/null || echo "inet")
        nft delete table "$family" "$table_name" >/dev/null 2>&1 || true

        systemctl stop port-tg-bot 2>/dev/null || true
        systemctl disable port-tg-bot 2>/dev/null || true
        quarantine_path /etc/systemd/system/port-tg-bot.service "/root/port-traffic-dog-quarantine/systemd" >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true

        # 清理本脚本注册的全部定时任务。
        local cleaned_cron
        cleaned_cron=$(crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH" | grep -vF "/usr/local/bin/port-traffic-dog.sh" || true)
        if [ -n "$cleaned_cron" ]; then
            printf '%s\n' "$cleaned_cron" | crontab - 2>/dev/null || true
        else
            crontab -r 2>/dev/null || true
        fi

        quarantine_path "$CONFIG_DIR" "/root/port-traffic-dog-quarantine" >/dev/null 2>&1 || true
        quarantine_path "/usr/local/bin/$SHORTCUT_COMMAND" "/root/port-traffic-dog-quarantine/bin" >/dev/null 2>&1 || true
        
        quarantine_path "/usr/local/bin/port-traffic-dog.sh" "/root/port-traffic-dog-quarantine/bin" >/dev/null 2>&1 || true
        if [ "$SCRIPT_PATH" != "/usr/local/bin/port-traffic-dog.sh" ]; then
            quarantine_path "$SCRIPT_PATH" "/root/port-traffic-dog-quarantine/bin" >/dev/null 2>&1 || true
        fi

        echo -e "${GREEN}✅ 卸载完成，旧配置目录和脚本文件已隔离到 /root/port-traffic-dog-quarantine。${NC}"
        echo -e "${YELLOW}感谢使用，江湖路远，有缘再见！👋${NC}"
        exit 0
    else
        echo "取消卸载，返回主菜单。"
        sleep 1
        show_main_menu
    fi
}

# ==========================================
# 交互式 Telegram 机器人功能核心区
# ==========================================

setup_interactive_tg() {
    echo -e "${BLUE}=== 部署 Telegram 交互式查询机器人 ===${NC}"
    read_secret_trimmed bot_token "请输入 Bot Token (去@BotFather获取): "
    read_trimmed chat_id "请输入允许查询的 Chat ID (个人的ID或群组ID): "

    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Token或Chat ID不能为空，操作取消。${NC}"
        sleep 2
        manage_notifications
        return
    fi

    if ! update_telegram_config "$bot_token" "$chat_id"; then
        sleep 2
        manage_notifications
        return
    fi

    echo -e "${YELLOW}正在部署 Systemd 守护进程...${NC}"
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${RED}未检测到 systemctl，无法部署后台机器人服务。${NC}"
        sleep 2
        manage_notifications
        return
    fi
    local runtime_script
    if ! runtime_script=$(ensure_local_script_copy); then
        echo -e "${RED}无法安装本地脚本到 /usr/local/bin/port-traffic-dog.sh。${NC}"
        sleep 2
        manage_notifications
        return
    fi
    
    cat > /etc/systemd/system/port-tg-bot.service << EOF
[Unit]
Description=Port Traffic Dog Interactive TG Bot
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash $runtime_script --run-listener
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable port-tg-bot 2>/dev/null || true
    if ! systemctl restart port-tg-bot; then
        echo -e "${RED}TG 后台服务启动失败，请查看：systemctl status port-tg-bot --no-pager${NC}"
        read -r -p "按回车键返回..."
        manage_notifications
        return
    fi

    echo -e "${GREEN}✅ 部署成功！机器人已在后台常驻运行。${NC}"
    echo -e "💡 提示: 请确保在 @BotFather 关闭了机器人的 Group Privacy (Turn OFF)"
    echo -e "现在可发送 ${YELLOW}/t 端口号${NC}、${YELLOW}/all${NC}、${YELLOW}/yday${NC}、${YELLOW}/trend${NC}、${YELLOW}/day YYYY-MM-DD${NC}"
    echo
    read -r -p "按回车键返回..."
    manage_notifications
}

stop_interactive_tg() {
    read_trimmed stop_confirm "确认停止并隔离 Telegram 交互机器人服务？[Y/n]: "
    case "$stop_confirm" in
        y|Y) ;;
        *)
            echo -e "${YELLOW}已取消${NC}"
            sleep 1
            manage_notifications
            return
            ;;
    esac
    echo -e "${YELLOW}正在停止并隔离 Telegram 交互机器人服务...${NC}"
    systemctl stop port-tg-bot 2>/dev/null || true
    systemctl disable port-tg-bot 2>/dev/null || true
    quarantine_path /etc/systemd/system/port-tg-bot.service "/root/port-traffic-dog-quarantine/systemd" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    echo -e "${GREEN}✅ 交互式机器人服务已停止，服务文件已隔离。${NC}"
    sleep 2
    manage_notifications
}

manage_display_mode() {
    echo -e "${BLUE}=== 实际端口流量说明 ===${NC}"
    echo -e "${GREEN}实际端口流量：${NC}只统计已添加监控的端口实际跑过的流量。"
    echo
    echo -e "${YELLOW}未添加到监控列表的端口不会计入这里。${NC}"
    echo "0. 返回主菜单"
    read_trimmed mode_choice "请选择 [0]: "

    case $mode_choice in
        0)
            show_main_menu
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            sleep 1
            manage_display_mode
            return
            ;;
    esac

    sleep 2
    show_main_menu
}

tg_send_message_checked() {
    local token="$1"
    local chat_id="$2"
    local text="$3"
    local parse_mode="${4:-HTML}"

    if [ -n "$parse_mode" ]; then
        curl -fsS --connect-timeout 10 --max-time 20 --retry 1 --retry-delay 1 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=${parse_mode}" >/dev/null 2>&1
    else
        curl -fsS --connect-timeout 10 --max-time 20 --retry 1 --retry-delay 1 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" >/dev/null 2>&1
    fi
}

tg_send_message() {
    tg_send_message_checked "$@" || true
}

html_escape_text() {
    jq -nr --arg value "$1" '$value
        | split("&") | join("&amp;")
        | split("<") | join("&lt;")
        | split(">") | join("&gt;")'
}

get_telegram_server_name() {
    local server_name
    server_name=$(jq -r '.notifications.telegram.server_name // ""' "$CONFIG_FILE" 2>/dev/null || true)
    if [ -z "$server_name" ] || [ "$server_name" = "null" ]; then
        server_name=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "VPS")
    fi
    html_escape_text "$server_name"
}

build_telegram_status_notification() {
    local template
    local report
    local server_name
    local generated_at

    template=$(jq -r '.notifications.telegram.template // "<b>🐶 {server_name} 端口流量通知</b>\n{report}"' "$CONFIG_FILE")
    [[ "$template" == *"{report}"* ]] || return 1
    report=$(build_tg_all_ports_report)
    [[ "$report" != "❌"* ]] || return 1
    server_name=$(get_telegram_server_name)
    generated_at=$(get_beijing_time '+%Y-%m-%d %H:%M:%S')
    render_notification_template "$template" "$server_name" "$report" "$generated_at"
}

send_telegram_status_notification() {
    local source="${1:-manual}"
    local token
    local chat_id
    local message

    token=$(jq -r '.notifications.telegram.bot_token // ""' "$CONFIG_FILE" 2>/dev/null || true)
    chat_id=$(jq -r '.notifications.telegram.chat_id // ""' "$CONFIG_FILE" 2>/dev/null || true)
    if [ -z "$token" ] || [ "$token" = "null" ] || [ -z "$chat_id" ] || [ "$chat_id" = "null" ]; then
        echo "Telegram Bot Token 或 Chat ID 未配置。" >&2
        return 1
    fi
    if ! validate_traffic_counter_snapshot; then
        echo "nftables counter 不完整，已取消通知。" >&2
        return 1
    fi

    if ! message=$(build_telegram_status_notification); then
        echo "无法生成通知，请检查模板和统计健康状态。" >&2
        return 1
    fi
    if [ ${#message} -gt 4000 ]; then
        echo "通知内容超过 4000 字符，请缩短模板或减少监控端口。" >&2
        return 1
    fi
    if tg_send_message_checked "$token" "$chat_id" "$message"; then
        echo "$(get_beijing_time -Iseconds) Telegram ${source}通知发送成功" >> "$LOG_FILE"
        return 0
    fi
    echo "$(get_beijing_time -Iseconds) Telegram ${source}通知发送失败" >> "$LOG_FILE"
    return 1
}

send_manual_telegram_notification() {
    echo -e "${BLUE}=== 立即查询并发送 ===${NC}"
    if send_telegram_status_notification "手动"; then
        echo -e "${GREEN}实时流量报告已发送。${NC}"
    else
        echo -e "${RED}发送失败，请检查 Telegram 配置、网络和统计健康状态。${NC}"
    fi
    read -r -p "按回车返回通知管理..."
    manage_notifications
}

sync_telegram_notification_cron() {
    command -v crontab >/dev/null 2>&1 || return 0
    [ -f "$CONFIG_FILE" ] || return 0

    local enabled
    local temp_cron
    local runtime_script
    runtime_script=$(ensure_local_script_copy) || return 1
    enabled=$(jq -r '.notifications.telegram.status_notifications.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    temp_cron=$(mktemp /tmp/port-traffic-dog-notify-cron.XXXXXX) || return 1
    crontab -l 2>/dev/null | grep -vF -- "--scheduled-notify" > "$temp_cron" || true
    if [ "$enabled" = "true" ]; then
        echo "20 * * * * /bin/bash \"$runtime_script\" --scheduled-notify >/dev/null 2>&1  # 端口流量狗 Telegram 定时通知" >> "$temp_cron"
    fi
    crontab "$temp_cron"
    rm -f "$temp_cron"
}

run_scheduled_telegram_notification() {
    local enabled
    local interval
    local daily_hour
    local current_hour

    enabled=$(jq -r '.notifications.telegram.status_notifications.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    [ "$enabled" = "true" ] || return 0
    interval=$(jq -r '.notifications.telegram.status_notifications.interval // "1h"' "$CONFIG_FILE")
    daily_hour=$(jq -r '.notifications.telegram.status_notifications.daily_hour // 9' "$CONFIG_FILE")
    current_hour=$(get_beijing_time +%-H)
    telegram_notification_due "$interval" "$daily_hour" "$current_hour" || return 0

    (
        flock -n 9 || exit 0
        send_telegram_status_notification "定时"
    ) 9> "${CONFIG_DIR}/.telegram-notification.lock"
}

update_telegram_schedule_config() {
    local interval="$1"
    local daily_hour="$2"
    local enabled="$3"
    local temp_file
    (
        flock -w 5 9 || return 1
        temp_file=$(mktemp "${CONFIG_DIR}/config.XXXXXX.tmp") || return 1
        if jq --arg interval "$interval" --argjson daily_hour "$daily_hour" --argjson enabled "$enabled" '
            .notifications.telegram.status_notifications.enabled = $enabled |
            .notifications.telegram.status_notifications.interval = $interval |
            .notifications.telegram.status_notifications.daily_hour = $daily_hour
        ' "$CONFIG_FILE" > "$temp_file"; then
            mv "$temp_file" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        else
            rm -f "$temp_file"
            return 1
        fi
    ) 9> "${CONFIG_DIR}/.config.lock"
}

manage_telegram_schedule() {
    local current_enabled
    local current_interval
    local current_daily_hour
    local choice
    local interval="1h"
    local daily_hour=9
    local token
    local chat_id

    current_enabled=$(jq -r '.notifications.telegram.status_notifications.enabled // false' "$CONFIG_FILE")
    current_interval=$(jq -r '.notifications.telegram.status_notifications.interval // "1h"' "$CONFIG_FILE")
    current_daily_hour=$(jq -r '.notifications.telegram.status_notifications.daily_hour // 9' "$CONFIG_FILE")
    echo -e "${BLUE}=== Telegram 定时通知 ===${NC}"
    echo "当前状态: enabled=$current_enabled interval=$current_interval daily_hour=$current_daily_hour"
    echo "1. 每小时"
    echo "2. 每 6 小时"
    echo "3. 每 12 小时"
    echo "4. 每天指定小时（北京时间）"
    echo "5. 停用定时通知"
    echo "0. 返回"
    read_trimmed choice "请选择 [0-5]: "

    case "$choice" in
        1) interval="1h" ;;
        2) interval="6h" ;;
        3) interval="12h" ;;
        4)
            interval="daily"
            read_trimmed daily_hour "请输入通知小时 [0-23，默认9]: "
            daily_hour=${daily_hour:-9}
            if ! [[ "$daily_hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
                echo -e "${RED}小时必须是 0-23。${NC}"
                sleep 1
                manage_telegram_schedule
                return
            fi
            ;;
        5)
            if update_telegram_schedule_config "$current_interval" "$current_daily_hour" false && sync_telegram_notification_cron; then
                echo -e "${GREEN}定时通知已停用。${NC}"
            else
                echo -e "${RED}定时通知停用失败。${NC}"
            fi
            sleep 1
            manage_notifications
            return
            ;;
        0) manage_notifications; return ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; manage_telegram_schedule; return ;;
    esac

    token=$(jq -r '.notifications.telegram.bot_token // ""' "$CONFIG_FILE" 2>/dev/null || true)
    chat_id=$(jq -r '.notifications.telegram.chat_id // ""' "$CONFIG_FILE" 2>/dev/null || true)
    if [ -z "$token" ] || [ "$token" = "null" ] || [ -z "$chat_id" ] || [ "$chat_id" = "null" ]; then
        echo -e "${RED}请先部署 Telegram 机器人并配置 Bot Token、Chat ID。${NC}"
        sleep 1
        manage_notifications
        return
    fi

    if update_telegram_schedule_config "$interval" "$daily_hour" true && sync_telegram_notification_cron; then
        echo -e "${GREEN}定时通知已启用：$interval。${NC}"
    else
        echo -e "${RED}定时通知配置失败。${NC}"
    fi
    sleep 1
    manage_notifications
}

update_telegram_template() {
    local template="$1"
    local temp_file
    (
        flock -w 5 9 || return 1
        temp_file=$(mktemp "${CONFIG_DIR}/config.XXXXXX.tmp") || return 1
        if jq --arg template "$template" '.notifications.telegram.template = $template' "$CONFIG_FILE" > "$temp_file"; then
            mv "$temp_file" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        else
            rm -f "$temp_file"
            return 1
        fi
    ) 9> "${CONFIG_DIR}/.config.lock"
}

manage_telegram_template() {
    local choice
    local line
    local template=""
    local default_template=$'<b>🐶 {server_name} 端口流量通知</b>\n{report}'

    echo -e "${BLUE}=== Telegram 通知模板 ===${NC}"
    echo "可用变量: {server_name} {report} {time}"
    echo "1. 自定义模板"
    echo "2. 恢复默认模板"
    echo "0. 返回"
    read_trimmed choice "请选择 [0-2]: "
    case "$choice" in
        1)
            echo "逐行输入模板，单独输入 . 保存；模板必须包含 {report}。"
            while IFS= read -r line; do
                [ "$line" = "." ] && break
                template+="${template:+$'\n'}${line}"
            done
            if [[ "$template" != *"{report}"* ]]; then
                echo -e "${RED}模板缺少 {report}，未保存。${NC}"
            elif [ ${#template} -gt 2000 ]; then
                echo -e "${RED}模板不能超过 2000 字符。${NC}"
            elif update_telegram_template "$template"; then
                echo -e "${GREEN}通知模板已保存。${NC}"
            else
                echo -e "${RED}通知模板保存失败。${NC}"
            fi
            ;;
        2)
            if update_telegram_template "$default_template"; then
                echo -e "${GREEN}已恢复默认通知模板。${NC}"
            else
                echo -e "${RED}默认模板恢复失败。${NC}"
            fi
            ;;
        0) manage_notifications; return ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
    sleep 1
    manage_notifications
}

build_tg_help_message() {
    cat <<'EOF'
<b>端口流量狗 TG 指令</b>
/t 端口           查询单端口实时流量
/all              查询全部端口实时汇总
/yday             查询昨日日报
/trend            查询近7日趋势
/day YYYY-MM-DD   查询指定日期日报
/help             查看帮助
EOF
}

build_tg_port_report() {
    local port="$1"

    if ! jq -e ".ports.\"$port\"" "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "❌ 未找到端口 ${port} 的监控数据"
        return 0
    fi

    if ! refresh_nftables_counter_snapshot; then
        echo "❌ 无法读取 nftables counter，请运行 dog 后使用 health 检查"
        return 0
    fi
    local counter_data
    if ! counter_data=$(get_nftables_counter_data_from_snapshot "$port"); then
        echo "❌ 端口 ${port} 的 counter 不完整，请运行 dog 后使用 health 检查"
        return 0
    fi
    local traffic_data=($counter_data)
    local in_b=${traffic_data[0]:-0}
    local out_b=${traffic_data[1]:-0}
    local actual_total=$((in_b + out_b))
    local monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE" 2>/dev/null)

    echo "<b>端口流量实时报告</b>"
    echo "监听端口: <code>${port}</code>"
    echo "实际端口流量: <b>$(format_bytes "$actual_total")</b>"
    # 仅在端口设置了配额时展示配额用量，避免无配额端口出现误导性数字
    if [ "$monthly_limit" != "unlimited" ] && [ -n "$monthly_limit" ]; then
        echo "配额已用: <b>$(format_bytes "$actual_total")</b> / ${monthly_limit}"
    fi
    echo "查询时间: $(get_beijing_time '+%Y-%m-%d %H:%M:%S')"
}

build_tg_all_ports_report() {
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -eq 0 ]; then
        echo "当前暂无监控端口"
        return 0
    fi

    if ! validate_traffic_counter_snapshot; then
        echo "❌ nftables counter 不完整，未生成流量汇总。请运行 dog 后使用 health 检查"
        return 0
    fi

    local total_actual=0
    local report="<b>全部端口实时流量汇总</b>"

    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data_from_snapshot "$port"))
        local in_b=${traffic_data[0]:-0}
        local out_b=${traffic_data[1]:-0}
        local actual_total=$((in_b + out_b))

        total_actual=$((total_actual + actual_total))
        report+=$'\n'
        report+="端口 <code>${port}</code> | 实际流量: $(format_bytes "$actual_total")"
    done

    report+=$'\n'
    report+="实际端口总流量: <b>$(format_bytes "$total_actual")</b>"
    report+=$'\n'
    report+="查询时间: $(get_beijing_time '+%Y-%m-%d %H:%M:%S')"
    echo "$report"
}

build_tg_day_report() {
    local day_key="$1"
    ensure_daily_usage_files

    if ! jq -e --arg day "$day_key" '.days[$day]' "$DAILY_USAGE_FILE" >/dev/null 2>&1; then
        echo "${day_key} 暂无日报数据"
        return 0
    fi

    local total_actual=$(jq -r --arg day "$day_key" '.days[$day].total_raw // .days[$day].total_actual // 0' "$DAILY_USAGE_FILE")
    local report="<b>${day_key} 日报</b>"
    report+=$'\n'
    report+="实际端口流量: <b>$(format_bytes "$total_actual")</b>"

    local ports=($(jq -r --arg day "$day_key" '.days[$day].ports | keys[]?' "$DAILY_USAGE_FILE" 2>/dev/null | sort -n))
    if [ ${#ports[@]} -gt 0 ]; then
        for port in "${ports[@]}"; do
            local actual=$(jq -r --arg day "$day_key" --arg port "$port" '.days[$day].ports[$port] | if type == "object" then .raw // .actual // 0 else . // 0 end' "$DAILY_USAGE_FILE")
            report+=$'\n'
            report+="端口 <code>${port}</code> | 实际流量: $(format_bytes "$actual")"
        done
    fi

    echo "$report"
}

build_tg_7days_report() {
    ensure_daily_usage_files
    local sum_actual=0
    local report="<b>近7日趋势报表</b>"

    for ((i=6; i>=0; i--)); do
        local day_key=$(get_beijing_time -d "-$i day" +%F)
        local day_actual=$(jq -r --arg day "$day_key" '.days[$day].total_raw // .days[$day].total_actual // 0' "$DAILY_USAGE_FILE" 2>/dev/null || echo "0")
        sum_actual=$((sum_actual + day_actual))
        report+=$'\n'
        report+="${day_key} | 实际流量: $(format_bytes "$day_actual")"
    done

    report+=$'\n'
    report+="7日合计: <b>$(format_bytes "$sum_actual")</b>"
    echo "$report"
}

# 优化6：TG后台守护进程数据容错，防止因为 API 返回错误而崩溃退出
run_tg_listener() {
    local token=$(jq -r '.notifications.telegram.bot_token' "$CONFIG_FILE")
    local allowed_chat=$(jq -r '.notifications.telegram.chat_id' "$CONFIG_FILE")
    
    if [[ -z "$token" || "$token" == "null" ]]; then
        echo "未配置 Bot Token，守护进程退出..."
        exit 1
    fi

    local offset=0
    echo "TG交互查询机器人正在后台守望..."

    while true; do
        local updates=$(curl -fsS --connect-timeout 10 --max-time 70 --retry 1 --retry-delay 1 "https://api.telegram.org/bot${token}/getUpdates?offset=${offset}&timeout=50" 2>/dev/null || true)
        local latest_id=$(echo "$updates" | jq -r '.result[-1].update_id // empty' 2>/dev/null || true)
        
        # 增加纯数字判断容错，防止非预期响应导致 bash 算数报错
        if [[ -n "$latest_id" && "$latest_id" =~ ^[0-9]+$ ]]; then
            offset=$((latest_id + 1))
            
            # 优化点：使用进程替换取代管道符，防止 while 陷在 subshell 内
            while read -r update; do
                local msg_text=$(echo "$update" | jq -r '.message.text // empty')
                local chat_id=$(echo "$update" | jq -r '.message.chat.id // empty')

                if [[ -n "$allowed_chat" && "$allowed_chat" != "null" && "$chat_id" != "$allowed_chat" ]]; then
                    continue
                fi
                
                if [[ "$msg_text" =~ ^/(start|help)(@[A-Za-z0-9_]+)?[[:space:]]*$ ]]; then
                    tg_send_message "$token" "$chat_id" "$(build_tg_help_message)"
                    continue
                fi

                if [[ "$msg_text" =~ ^/(traffic|t)(@[A-Za-z0-9_]+)?[[:space:]]+([0-9]+(-[0-9]+)?)[[:space:]]*$ ]]; then
                    local port="${BASH_REMATCH[3]}"
                    local reply
                    reply=$(build_tg_port_report "$port")
                    tg_send_message "$token" "$chat_id" "$reply"
                    continue
                fi

                if [[ "$msg_text" =~ ^/(all|ta|total|sum)(@[A-Za-z0-9_]+)?[[:space:]]*$ ]]; then
                    local reply
                    reply=$(build_tg_all_ports_report)
                    tg_send_message "$token" "$chat_id" "$reply"
                    continue
                fi

                if [[ "$msg_text" =~ ^/(yday|yesterday)(@[A-Za-z0-9_]+)?[[:space:]]*$ ]]; then
                    local day_key=$(get_beijing_time -d "yesterday" +%F)
                    local reply
                    reply=$(build_tg_day_report "$day_key")
                    tg_send_message "$token" "$chat_id" "$reply"
                    continue
                fi

                if [[ "$msg_text" =~ ^/(trend|seven)(@[A-Za-z0-9_]+)?[[:space:]]*$ ]]; then
                    local reply
                    reply=$(build_tg_7days_report)
                    tg_send_message "$token" "$chat_id" "$reply"
                    continue
                fi

                if [[ "$msg_text" =~ ^/day(@[A-Za-z0-9_]+)?[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]*$ ]]; then
                    local day_input="${BASH_REMATCH[2]}"
                    if ! get_beijing_time -d "$day_input" +%F >/dev/null 2>&1; then
                        tg_send_message "$token" "$chat_id" "❌ 日期格式无效，请使用 YYYY-MM-DD"
                        continue
                    fi
                    local reply
                    reply=$(build_tg_day_report "$day_input")
                    tg_send_message "$token" "$chat_id" "$reply"
                    continue
                fi

                if [[ "$msg_text" =~ ^/ ]]; then
                    tg_send_message "$token" "$chat_id" "未识别的命令，发送 /help 查看可用指令。" ""
                    continue
                fi
            done < <(echo "$updates" | jq -c '.result[]' 2>/dev/null || true)
        fi
        sleep 1
    done
}

manage_notifications() {
    echo -e "${BLUE}=== $(ui_text '通知管理' 'Notifications' 'Уведомления') ===${NC}"
    echo "1. $(ui_text '部署 Telegram 查询机器人（/t /all /yday /trend /day）' 'Deploy Telegram query bot (/t /all /yday /trend /day)' 'Развернуть Telegram-бота запросов (/t /all /yday /trend /day)')"
    echo "2. $(ui_text '停止并卸载 Telegram 查询机器人' 'Stop and uninstall Telegram query bot' 'Остановить и удалить Telegram-бота запросов')"
    echo "3. $(ui_text '企业微信机器人（保留接口）' 'WeCom bot (legacy interface)' 'Бот WeCom (устаревший интерфейс)')"
    echo "4. $(ui_text '立即发送实时报告' 'Send a real-time report now' 'Отправить отчёт сейчас')"
    echo "5. $(ui_text 'Telegram 定时通知' 'Scheduled Telegram notifications' 'Расписание уведомлений Telegram')"
    echo "6. $(ui_text 'Telegram 通知模板' 'Telegram notification template' 'Шаблон уведомлений Telegram')"
    echo "0. $(ui_text '返回主菜单' 'Back to main menu' 'Назад в главное меню')"
    echo
    read_trimmed choice "$(ui_text '请选择 [0-6]: ' 'Select [0-6]: ' 'Выберите [0-6]: ')"

    case $choice in
        1) setup_interactive_tg ;;
        2) stop_interactive_tg ;;
        3) echo -e "${YELLOW}$(ui_text '请使用旧版逻辑维护。' 'Use the legacy workflow for this item.' 'Используйте прежний сценарий для этого пункта.')${NC}"; sleep 2; manage_notifications ;;
        4) send_manual_telegram_notification ;;
        5) manage_telegram_schedule ;;
        6) manage_telegram_template ;;
        0) show_main_menu ;;
        *) echo -e "${RED}$(ui_text '无效选择。' 'Invalid selection.' 'Неверный выбор.')${NC}"; sleep 1; manage_notifications ;;
    esac
}

setup_port_auto_reset_cron() {
    local temp_cron=$(mktemp /tmp/port-traffic-dog-cron.XXXXXX)
    local runtime_script
    runtime_script=$(ensure_local_script_copy) || runtime_script="$SCRIPT_PATH"
    # 顺手把之前可能生成的冗余独立端口规则清理掉
    crontab -l 2>/dev/null | grep -v -- "端口流量狗自动重置端口" | grep -v -- "--reset-port" | grep -v -- "--daily-reset-check" > "$temp_cron" || true
    
    # 注入唯一的“全局每日智能心跳检测”
    echo "5 0 * * * /bin/bash \"$runtime_script\" --daily-reset-check >/dev/null 2>&1  # 端口流量狗全局智能流量重置" >> "$temp_cron"
    
    crontab "$temp_cron"
    rm -f "$temp_cron"
}

remove_port_auto_reset_cron() {
    # 既然改为了全局每日心跳，这里不需要再单独删配置了，留空即可
    : 
}
create_shortcut_command() {
    local runtime_script
    runtime_script=$(ensure_local_script_copy) || runtime_script="$SCRIPT_PATH"
    if [ ! -f "/usr/local/bin/$SHORTCUT_COMMAND" ]; then
        cat > "/usr/local/bin/$SHORTCUT_COMMAND" << EOF
#!/bin/bash
exec bash "$runtime_script" "\$@"
EOF
        chmod +x "/usr/local/bin/$SHORTCUT_COMMAND" 2>/dev/null || true
    fi
}

main() {
    if [[ "${1:-}" == "--lang" ]]; then
        REQUESTED_UI_LANGUAGE="${2:-}"
        if ! normalize_ui_language "$REQUESTED_UI_LANGUAGE" >/dev/null; then
            echo -e "${RED}--lang $(ui_text '仅支持 zh、en 或 ru。' 'accepts only zh, en, or ru.' 'поддерживает только zh, en или ru.')${NC}" >&2
            exit 1
        fi
        UI_LANGUAGE=$(normalize_ui_language "$REQUESTED_UI_LANGUAGE")
        shift 2
    fi
    # 1. 基础环境校验
    check_root
    
    # 2. 👉 【核心大招】：把配置初始化和恢复规则提到了最前面！
    # 这样无论是开机自启还是手动运行，它都会先默默检查并补齐丢失的监控规则
    init_config  
    load_ui_language
    if [[ -n "$REQUESTED_UI_LANGUAGE" ]]; then
        save_ui_language "$REQUESTED_UI_LANGUAGE" || exit 1
    fi

    # 3. 拦截后台机器人的启动参数
    if [ "${1:-}" == "--run-listener" ]; then
        run_tg_listener
        exit 0
    fi
    
    # 4. 拦截自动重置的参数
    if [ "${1:-}" == "--reset-port" ]; then
        if [ -z "${2:-}" ]; then
            echo -e "${RED}错误：--reset-port 需要指定端口参数${NC}" >&2
            exit 1
        fi
        auto_reset_port "$2"
        exit 0
    fi
    # 拦截智能每日检测参数
    if [ "${1:-}" == "--daily-reset-check" ]; then
        check_and_run_daily_resets
        exit 0
    fi
    # 拦截后台自动保存数据
    if [ "${1:-}" == "--save-data" ]; then
        save_traffic_data
        exit 0
    fi
    # 拦截日报快照采集参数
    if [ "${1:-}" == "--daily-snapshot" ]; then
        collect_daily_usage_snapshot "true"
        exit 0
    fi
    if [ "${1:-}" == "--scheduled-notify" ]; then
        run_scheduled_telegram_notification
        exit 0
    fi
    # 5. 常规的前台菜单逻辑
    check_dependencies
    create_shortcut_command
    show_main_menu
}

main "$@"
