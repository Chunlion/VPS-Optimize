#!/bin/bash
#原项目https://github.com/zywe03/realm-xwPF/blob/main/port-traffic-dog.sh
set -euo pipefail

readonly SCRIPT_VERSION="1.2.6-TG优化版"
readonly SCRIPT_NAME="端口流量狗"
readonly SCRIPT_PATH="$(realpath "$0")"
readonly CONFIG_DIR="/etc/port-traffic-dog"
readonly CONFIG_FILE="$CONFIG_DIR/config.json"
readonly LOG_FILE="$CONFIG_DIR/logs/traffic.log"
readonly TRAFFIC_DATA_FILE="$CONFIG_DIR/traffic_data.json"
readonly DAILY_USAGE_FILE="$CONFIG_DIR/daily_usage.json"
readonly DAILY_SNAPSHOT_STATE_FILE="$CONFIG_DIR/daily_snapshot_state.json"

readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

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
    read -r -p "$prompt" input
    printf -v "$__target" '%s' "$(trim_input "$input")"
}

read_secret_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local input
    read -r -s -p "$prompt" input
    echo ""
    printf -v "$__target" '%s' "$(trim_input "$input")"
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
    echo "unknown"
}

install_missing_tools() {
    local missing_tools=("$@")
    local system_type=$(detect_system)
    local pkg_cmd
    case $system_type in
        "ubuntu") pkg_cmd="apt" ;;
        "debian") pkg_cmd="apt-get" ;;
        *)
            echo -e "${RED}不支持的系统类型: $system_type${NC}"
            exit 1
            ;;
    esac

    echo -e "${YELLOW}检测到缺少工具: ${missing_tools[*]}${NC}"
    $pkg_cmd update -qq
    for tool in "${missing_tools[@]}"; do
        case $tool in
            "nft") $pkg_cmd install -y nftables ;;
            "tc"|"ss") $pkg_cmd install -y iproute2 ;;
            "jq") $pkg_cmd install -y jq ;;
            "awk") $pkg_cmd install -y gawk ;;
            "bc") $pkg_cmd install -y bc ;;
            "curl") $pkg_cmd install -y curl ;;
            "cron")
                $pkg_cmd install -y cron
                systemctl enable cron 2>/dev/null || true
                systemctl start cron 2>/dev/null || true
                ;;
            *) $pkg_cmd install -y "$tool" ;;
        esac
    done
    echo -e "${GREEN}依赖工具安装完成${NC}"
}

check_dependencies() {
    local silent_mode=${1:-false}
    local missing_tools=()
    local required_tools=("nft" "tc" "ss" "jq" "awk" "bc" "unzip" "cron" "curl" "conntrack")

    for tool in "${required_tools[@]}"; do
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

confirm_danger() {
    local title="$1"
    local impact="$2"
    local confirm
    echo -e "${RED}高风险操作: ${title}${NC}"
    echo -e "${YELLOW}影响: ${impact}${NC}"
    read_trimmed confirm "确认继续请输入 YES: "
    [[ "$confirm" == "YES" ]]
}

setup_cron_environment() {
    local current_cron=$(crontab -l 2>/dev/null || true)
    if ! echo "$current_cron" | grep -q "^PATH=.*sbin"; then
        local temp_cron=$(mktemp /tmp/port-traffic-dog-cron.XXXXXX)
        echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" > "$temp_cron"
        echo "$current_cron" | grep -v "^PATH=" >> "$temp_cron" || true
        crontab "$temp_cron" 2>/dev/null || true
        rm -f "$temp_cron"
    fi
    
    # 修复：强行注册开机自启任务，确保重启后恢复逻辑被执行
    if ! crontab -l 2>/dev/null | grep -Fq "@reboot /bin/bash $SCRIPT_PATH"; then
        local temp_cron2=$(mktemp)
        crontab -l 2>/dev/null > "$temp_cron2" || true
        echo "@reboot /bin/bash $SCRIPT_PATH >/dev/null 2>&1" >> "$temp_cron2"
        crontab "$temp_cron2" 2>/dev/null || true
        rm -f "$temp_cron2"
    fi
    # 修复：注入高频持久化任务，防止意外死机导致的流量数据蒸发
    if ! crontab -l 2>/dev/null | grep -Fq -- "--save-data"; then
        local temp_cron3=$(mktemp)
        crontab -l 2>/dev/null > "$temp_cron3" || true
        # 每小时第 15 分钟触发一次后台数据存档
        echo "15 * * * * /bin/bash \"$SCRIPT_PATH\" --save-data >/dev/null 2>&1" >> "$temp_cron3"
        crontab "$temp_cron3" 2>/dev/null || true
        rm -f "$temp_cron3"
    fi

    # 每小时增量采集一次日报快照数据（用于昨日/近7日趋势）
    if ! crontab -l 2>/dev/null | grep -Fq -- "--daily-snapshot"; then
        local temp_cron4=$(mktemp)
        crontab -l 2>/dev/null > "$temp_cron4" || true
        echo "10 * * * * /bin/bash \"$SCRIPT_PATH\" --daily-snapshot >/dev/null 2>&1" >> "$temp_cron4"
        crontab "$temp_cron4" 2>/dev/null || true
        rm -f "$temp_cron4"
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：此脚本需要root权限运行${NC}"
        exit 1
    fi
}

init_config() {
    mkdir -p "$CONFIG_DIR" "$(dirname "$LOG_FILE")"
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
      "status_notifications": {
        "enabled": false,
        "interval": "1h"
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
    ensure_global_defaults
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

init_nftables() {
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    nft add table $family $table_name 2>/dev/null || true
    nft add chain $family $table_name input { type filter hook input priority 0\; } 2>/dev/null || true
    nft add chain $family $table_name output { type filter hook output priority 0\; } 2>/dev/null || true
    nft add chain $family $table_name forward { type filter hook forward priority 0\; } 2>/dev/null || true
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
    local bytes=$1
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then bytes=0; fi
    if [ $bytes -ge 1073741824 ]; then
        local gb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1073741824}")
        echo "${gb}GB"
    elif [ $bytes -ge 1048576 ]; then
        local mb=$(echo "scale=2; $bytes / 1048576" | bc)
        echo "${mb}MB"
    elif [ $bytes -ge 1024 ]; then
        local kb=$(echo "scale=2; $bytes / 1024" | bc)
        echo "${kb}KB"
    else
        echo "${bytes}B"
    fi
}

get_beijing_time() { TZ='Asia/Shanghai' date "$@"; }

# 优化1：增加文件锁，防止高并发导致配置脏读/损坏
update_config() {
    local jq_expression="$1"
    (
        flock -w 5 9 || { echo -e "${RED}配置文件正忙，稍后重试${NC}"; return 1; }
        jq "$jq_expression" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    ) 9> "${CONFIG_DIR}/.config.lock"
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

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        input_bytes=$(nft list counter $family $table_name "port_${port_safe}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
        output_bytes=$(nft list counter $family $table_name "port_${port_safe}_out" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
    else
        input_bytes=$(nft list counter $family $table_name "port_${port}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
        output_bytes=$(nft list counter $family $table_name "port_${port}_out" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
    fi
    input_bytes=${input_bytes:-0}
    output_bytes=${output_bytes:-0}
    echo "$input_bytes $output_bytes"
}

save_traffic_data() {
    local temp_file=$(mktemp /tmp/port-traffic-dog-data.XXXXXX)
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -eq 0 ]; then return 0; fi
    echo '{}' > "$temp_file"

    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
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

# 优化2：兜底清理临时文件，防止产生大量 /tmp 垃圾文件
setup_exit_hooks() {
    trap 'save_traffic_data_on_exit; rm -f /tmp/port-traffic-dog-*' EXIT
    trap 'save_traffic_data_on_exit; rm -f /tmp/port-traffic-dog-*; exit 1' INT TERM
}

save_traffic_data_on_exit() { save_traffic_data >/dev/null 2>&1; }

restore_monitoring_if_needed() {
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -eq 0 ]; then return 0; fi
    
    for port in "${active_ports[@]}"; do
        local p_safe=$(echo "$port" | tr '-' '_')
        # 如果内核里找不到这个端口的计数器，说明规则丢了，自动重新下发
        if ! nft list counter inet port_traffic_monitor "port_${p_safe}_out" >/dev/null 2>&1; then
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
        nft add counter $family $table_name "port_${port_safe}_in" { packets 0 bytes $target_input } 2>/dev/null || true
        nft add counter $family $table_name "port_${port_safe}_out" { packets 0 bytes $target_output } 2>/dev/null || true
    else
        nft add counter $family $table_name "port_${port}_in" { packets 0 bytes $target_input } 2>/dev/null || true
        nft add counter $family $table_name "port_${port}_out" { packets 0 bytes $target_output } 2>/dev/null || true
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

calculate_single_traffic() {
    local input_bytes=$1
    local output_bytes=$2
    # 单向口径按 VPS 出站计算，更接近用户本地实际使用的节点流量。
    echo "$output_bytes"
}

normalize_billing_mode() {
    local mode="${1:-dual}"
    case "$mode" in
        single|out|output|单向) echo "single" ;;
        dual|both|total|双向|"") echo "dual" ;;
        *) echo "dual" ;;
    esac
}

get_port_billing_mode() {
    local port=$1
    local mode=$(jq -r ".ports.\"$port\".quota.billing_mode // \"dual\"" "$CONFIG_FILE" 2>/dev/null || echo "dual")
    normalize_billing_mode "$mode"
}

get_billing_mode_label() {
    local mode=$(normalize_billing_mode "${1:-dual}")
    if [ "$mode" = "single" ]; then
        echo "单向计费(只算出站)"
    else
        echo "双向计费(入站+出站)"
    fi
}

choose_billing_mode() {
    local default_mode=$(normalize_billing_mode "${1:-dual}")
    local default_choice="2"
    if [ "$default_mode" = "single" ]; then default_choice="1"; fi

    echo >&2
    echo -e "${BLUE}请选择流量配额统计口径：${NC}" >&2
    echo "1. 单向计费：只计算 VPS 出站流量，接近用户本地实际使用量" >&2
    echo "2. 双向计费：计算入站 + 出站，接近 VPS 商家后台统计口径" >&2
    read_trimmed billing_choice "请选择 [1/2，回车默认${default_choice}]: "
    billing_choice="${billing_choice:-$default_choice}"

    case "$billing_choice" in
        1) echo "single" ;;
        2) echo "dual" ;;
        *)
            echo -e "${YELLOW}选择无效，已使用默认口径：$(get_billing_mode_label "$default_mode")${NC}" >&2
            echo "$default_mode"
            ;;
    esac
}

get_port_usage_by_mode() {
    local port=$1
    local mode=$(normalize_billing_mode "${2:-dual}")
    local traffic_data=($(get_nftables_counter_data "$port"))
    local input_bytes=${traffic_data[0]:-0}
    local output_bytes=${traffic_data[1]:-0}

    if [ "$mode" = "single" ]; then
        calculate_single_traffic "$input_bytes" "$output_bytes"
    else
        calculate_total_traffic "$input_bytes" "$output_bytes"
    fi
}

get_vps_provider_traffic_since_boot() {
    if [ ! -r /proc/net/dev ]; then
        echo "0 0 0"
        return
    fi

    awk -F'[: ]+' '
        NR > 2 && $2 != "lo" && $2 != "" {
            rx += $3
            tx += $11
        }
        END {
            printf "%.0f %.0f %.0f\n", rx, tx, rx + tx
        }
    ' /proc/net/dev
}

get_port_status_label() {
    local port=$1
    local port_config=$(jq -r ".ports.\"$port\"" "$CONFIG_FILE" 2>/dev/null)
    local remark=$(echo "$port_config" | jq -r '.remark // ""')
    local limit_enabled=$(echo "$port_config" | jq -r '.bandwidth_limit.enabled // false')
    local rate_limit=$(echo "$port_config" | jq -r '.bandwidth_limit.rate // "unlimited"')
    local quota_enabled=$(echo "$port_config" | jq -r '.quota.enabled // true')
    local monthly_limit=$(echo "$port_config" | jq -r '.quota.monthly_limit // "unlimited"')
    local billing_mode=$(normalize_billing_mode "$(echo "$port_config" | jq -r '.quota.billing_mode // "dual"')")
    local billing_tag="双向"
    if [ "$billing_mode" = "single" ]; then billing_tag="单向"; fi
    local reset_day_raw=$(echo "$port_config" | jq -r '.quota.reset_day')
    local reset_day="null"
    
    if [ "$monthly_limit" != "unlimited" ] && [ "$reset_day_raw" != "null" ]; then
        reset_day="${reset_day_raw:-1}"
    fi

    local status_tags=()
    if [ -n "$remark" ] && [ "$remark" != "null" ] && [ "$remark" != "" ]; then
        status_tags+=("[备注:$remark]")
    fi
    if [ "$quota_enabled" = "true" ]; then
        if [ "$monthly_limit" != "unlimited" ]; then
            local current_usage=$(get_port_monthly_usage "$port")
            local limit_bytes=$(parse_size_to_bytes "$monthly_limit")
            local usage_percent=$((current_usage * 100 / limit_bytes))
            local quota_display="$monthly_limit"
            status_tags+=("[${quota_display}/${billing_tag}]")
            if [ "$reset_day" != "null" ]; then
                local time_info=($(get_beijing_month_year))
                local current_day=${time_info[0]}
                local current_month=${time_info[1]}
                local next_month=$current_month
                if [ $current_day -ge $reset_day ]; then
                    next_month=$((current_month + 1))
                    if [ $next_month -gt 12 ]; then next_month=1; fi
                fi
                status_tags+=("[${next_month}月${reset_day}日重置]")
            fi
            if [ $usage_percent -ge 100 ]; then status_tags+=("[已超限]"); fi
        else
            status_tags+=("[无限制]")
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
    local billing_mode=$(get_port_billing_mode "$port")
    get_port_usage_by_mode "$port" "$billing_mode"
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

get_daily_single_traffic() {
    local total_bytes=0
    local ports=($(get_active_ports))
    for port in "${ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
        local output_bytes=${traffic_data[1]:-0}
        total_bytes=$(( total_bytes + output_bytes ))
    done
    format_bytes $total_bytes
}

collect_daily_usage_snapshot() {
    local silent_mode=${1:-"false"}
    ensure_daily_usage_files

    local day_key=$(get_beijing_time +%F)
    local snapshot_time=$(get_beijing_time -Iseconds)
    local usage_tmp=$(mktemp /tmp/port-traffic-dog-daily-usage.XXXXXX)
    local state_tmp=$(mktemp /tmp/port-traffic-dog-daily-state.XXXXXX)
    cp "$DAILY_USAGE_FILE" "$usage_tmp"
    cp "$DAILY_SNAPSHOT_STATE_FILE" "$state_tmp"

    local active_ports=($(get_active_ports 2>/dev/null || true))
    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
        local input_bytes=${traffic_data[0]:-0}
        local output_bytes=${traffic_data[1]:-0}
        local raw_total=$((input_bytes + output_bytes))
        local single_total=$output_bytes

        local prev_raw=0
        local prev_single=0
        if jq -e --arg port "$port" '.ports[$port]' "$state_tmp" >/dev/null 2>&1; then
            prev_raw=$(jq -r --arg port "$port" '.ports[$port].raw // 0' "$state_tmp" 2>/dev/null || echo "0")
            local prev_single_raw=$(jq -r --arg port "$port" '.ports[$port].single // "missing"' "$state_tmp" 2>/dev/null || echo "missing")
            if [ "$prev_single_raw" = "missing" ]; then
                prev_single=$single_total
            else
                prev_single=$prev_single_raw
            fi
        else
            prev_raw=$raw_total
            prev_single=$single_total
        fi

        local delta_raw=$((raw_total - prev_raw))
        local delta_single=$((single_total - prev_single))
        if [ "$delta_raw" -lt 0 ]; then
            local backup_raw=0
            local backup_single=0
            if [ -f "$TRAFFIC_DATA_FILE" ]; then
                local backup_input=$(jq -r ".\"$port\".input // 0" "$TRAFFIC_DATA_FILE" 2>/dev/null || echo "0")
                local backup_output=$(jq -r ".\"$port\".output // 0" "$TRAFFIC_DATA_FILE" 2>/dev/null || echo "0")
                backup_raw=$((backup_input + backup_output))
                backup_single=$backup_output
            fi
            if [ "$backup_raw" -gt 0 ] && [ "$backup_raw" -gt "$prev_raw" ]; then
                delta_raw=$((raw_total - backup_raw))
                delta_single=$((single_total - backup_single))
                if [ "$delta_raw" -lt 0 ]; then
                    delta_raw=$raw_total
                    delta_single=$single_total
                    prev_raw=0
                    prev_single=0
                else
                    prev_raw=$backup_raw
                    prev_single=$backup_single
                fi
            else
                delta_raw=$raw_total
                delta_single=$single_total
                prev_raw=0
                prev_single=0
            fi
        fi
        if [ "$delta_single" -lt 0 ]; then
            delta_single=$single_total
        fi

        jq --arg day "$day_key" \
           --arg port "$port" \
           --arg ts "$snapshot_time" \
           --argjson delta_raw "$delta_raw" \
           --argjson delta_single "$delta_single" \
           '(.days[$day].ports[$port] // 0) as $old |
            .days[$day].ports[$port] = {
                raw: ((if ($old | type) == "object" then ($old.raw // 0) else $old end) + $delta_raw),
                single: ((if ($old | type) == "object" then ($old.single // 0) else 0 end) + $delta_single)
            } |
            .days[$day].total_raw = ((.days[$day].total_raw // 0) + $delta_raw) |
            .days[$day].total_single = ((.days[$day].total_single // 0) + $delta_single) |
            .days[$day].updated_at = $ts |
            .meta.last_snapshot = $ts' "$usage_tmp" > "${usage_tmp}.new" && mv "${usage_tmp}.new" "$usage_tmp"

        jq --arg port "$port" \
           --arg ts "$snapshot_time" \
           --argjson raw "$raw_total" \
           --argjson single "$single_total" \
           '.ports[$port] = {raw: $raw, single: $single} |
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

    local total_raw=$(jq -r --arg day "$day_key" '.days[$day].total_raw // 0' "$DAILY_USAGE_FILE")
    local total_single=$(jq -r --arg day "$day_key" '.days[$day].total_single // 0' "$DAILY_USAGE_FILE")

    echo -e "${BLUE}=== $day_key 日报 ===${NC}"
    echo -e "用户单向(出站): ${GREEN}$(format_bytes "$total_single")${NC} | 端口双向: ${GREEN}$(format_bytes "$total_raw")${NC}"
    echo "────────────────────────────────────────────────────────"

    local ports=($(jq -r --arg day "$day_key" '.days[$day].ports | keys[]?' "$DAILY_USAGE_FILE" 2>/dev/null | sort -n))
    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "${YELLOW}该日暂无端口明细${NC}"
        return 0
    fi

    for port in "${ports[@]}"; do
        local raw=$(jq -r --arg day "$day_key" --arg port "$port" '.days[$day].ports[$port] | if type == "object" then .raw // 0 else . // 0 end' "$DAILY_USAGE_FILE")
        local single=$(jq -r --arg day "$day_key" --arg port "$port" '.days[$day].ports[$port] | if type == "object" then .single // 0 else 0 end' "$DAILY_USAGE_FILE")
        echo -e "端口 ${GREEN}$port${NC} | 单向: ${GREEN}$(format_bytes "$single")${NC} | 双向: ${GREEN}$(format_bytes "$raw")${NC}"
    done
}

show_recent_7_days_trend() {
    ensure_daily_usage_files
    local sum_raw=0
    local sum_single=0

    echo -e "${BLUE}=== 近7日趋势报表 ===${NC}"
    echo "日期 | 单向出站 | 端口双向"
    echo "────────────────────────────────────────────────────────"

    for ((i=6; i>=0; i--)); do
        local day_key=$(get_beijing_time -d "-$i day" +%F)
        local day_raw=$(jq -r --arg day "$day_key" '.days[$day].total_raw // 0' "$DAILY_USAGE_FILE" 2>/dev/null || echo "0")
        local day_single=$(jq -r --arg day "$day_key" '.days[$day].total_single // 0' "$DAILY_USAGE_FILE" 2>/dev/null || echo "0")
        sum_raw=$((sum_raw + day_raw))
        sum_single=$((sum_single + day_single))
        echo "$day_key | $(format_bytes "$day_single") | $(format_bytes "$day_raw")"
    done

    echo "────────────────────────────────────────────────────────"
    echo -e "7日合计 单向: ${GREEN}$(format_bytes "$sum_single")${NC} | 双向: ${GREEN}$(format_bytes "$sum_raw")${NC}"
}

manage_daily_usage_reports() {
    echo -e "${BLUE}=== 流量日报与趋势报表 ===${NC}"
    echo "1. 立即采集快照"
    echo "2. 查看昨日报表"
    echo "3. 查看近7日趋势"
    echo "4. 查看指定日期报表"
    echo "0. 返回主菜单"
    read_trimmed choice "请选择 [0-4]: "

    case $choice in
        1)
            collect_daily_usage_snapshot
            sleep 1
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
        local input_formatted=$(format_bytes $input_bytes)
        local output_formatted=$(format_bytes $output_bytes)
        local single_formatted=$(format_bytes $output_bytes)
        local total_formatted=$(format_bytes $total_bytes)
        local status_label=$(get_port_status_label "$port")

        if [ "$format_type" = "display" ]; then
            echo -e "端口:${GREEN}$port${NC} | 用户单向(出站):${GREEN}$single_formatted${NC} | 端口双向:${GREEN}$total_formatted${NC} | 入站:${GREEN}$input_formatted${NC} | 出站:${GREEN}$output_formatted${NC} | ${YELLOW}$status_label${NC}"
        elif [ "$format_type" = "markdown" ]; then
            result+="> 端口:**${port}** | 用户单向(出站):**${single_formatted}** | 端口双向:**${total_formatted}** | 入站:**${input_formatted}** | 出站:**${output_formatted}** | ${status_label}\n"
        else
            result+="\n端口:${port} | 用户单向(出站):${single_formatted} | 端口双向:${total_formatted} | 入站:${input_formatted} | 出站:${output_formatted} | ${status_label}"
        fi
    done
    if [ "$format_type" = "message" ] || [ "$format_type" = "markdown" ]; then
        echo -e "$result"
    fi
}

show_main_menu() {
    clear
    local active_ports=($(get_active_ports))
    local port_count=${#active_ports[@]}
    local port_single_total=$(get_daily_single_traffic)
    local port_dual_total=$(get_daily_total_traffic)
    local provider_traffic=($(get_vps_provider_traffic_since_boot))
    local provider_rx=$(format_bytes "${provider_traffic[0]:-0}")
    local provider_tx=$(format_bytes "${provider_traffic[1]:-0}")
    local provider_total=$(format_bytes "${provider_traffic[2]:-0}")

    echo -e "${BLUE}=== 端口流量狗 v$SCRIPT_VERSION ===${NC}"
    echo -e "${GREEN}介绍主页:${NC}https://zywe.de | ${GREEN}原项目:${NC}https://github.com/zywe03/realm-xwPF"
    echo -e "${GREEN}项目地址：https://github.com/Chunlion/VPS-Optimize 作者修改了部分代码 | 快捷命令: dog${NC}"
    echo -e "${YELLOW}用途：按端口统计流量、设置配额/限速、日报趋势和 Telegram 查询。${NC}"
    echo
    echo -e "${GREEN}状态: 监控中${NC} | ${BLUE}守护端口: ${port_count}个${NC}"
    echo -e "${YELLOW}端口单向(用户实际/出站): $port_single_total${NC} | ${YELLOW}端口双向(入站+出站): $port_dual_total${NC}"
    echo -e "${BLUE}VPS商家口径(整机自启动): 入站 $provider_rx | 出站 $provider_tx | 合计 $provider_total${NC}"
    echo -e "${YELLOW}提示: 商家后台通常按整台机器入站+出站计费，端口双向只是被监控端口的近似贡献。${NC}"
    echo "────────────────────────────────────────────────────────"

    if [ $port_count -gt 0 ]; then
        format_port_list "display"
    else
        echo -e "${YELLOW}暂无监控端口${NC}"
    fi

    echo "────────────────────────────────────────────────────────"
    echo -e "${BLUE}1.${NC} 添加/删除端口监控       ${BLUE}2.${NC} 配额/限速管理"
    echo -e "${BLUE}3.${NC} 每月/立即重置流量       ${BLUE}4.${NC} 导出/导入配置"
    echo -e "${BLUE}5.${NC} 检查并热更新脚本        ${BLUE}6.${NC} 卸载脚本"
    echo -e "${BLUE}7.${NC} 通知管理 (Telegram 查询)"
    echo -e "${BLUE}8.${NC} 流量口径说明            ${BLUE}9.${NC} 日报与趋势报表"
    echo -e "${BLUE}0.${NC} 退出"
    echo
    read_trimmed choice "请选择操作 [0-9]: "

    case $choice in
        1) manage_port_monitoring ;;
        2) manage_traffic_limits ;;
        3) manage_traffic_reset ;;
        4) manage_configuration ;;
        5) install_update_script ;;
        6) uninstall_script ;;
        7) manage_notifications ;;
        8) manage_display_mode ;;
        9) manage_daily_usage_reports ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择，请输入0-9${NC}"; sleep 1; show_main_menu ;;
    esac
}

manage_port_monitoring() {
    echo -e "${BLUE}=== 端口监控管理 ===${NC}"
    echo "1. 添加端口监控"
    echo "2. 删除端口监控"
    echo "0. 返回主菜单"
    read_trimmed choice "请选择操作 [0-2]: "
    case $choice in
        1) add_port_monitoring ;;
        2) remove_port_monitoring ;;
        0) show_main_menu ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; manage_port_monitoring ;;
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

    local billing_mode
    billing_mode=$(choose_billing_mode "dual")

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
            quota_config="{\"enabled\": $quota_enabled, \"monthly_limit\": \"$monthly_limit\", \"reset_day\": 1, \"billing_mode\": \"$billing_mode\"}"
        else
            quota_config="{\"enabled\": $quota_enabled, \"monthly_limit\": \"$monthly_limit\", \"billing_mode\": \"$billing_mode\"}"
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

    read_trimmed confirm "确认删除这些端口的监控? [y/N]: "
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

# 优化4：批量应用 nftables 规则，提升并发性能
add_nftables_rules() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    local batch_cmds=""

    local port_safe=$(echo "$port" | tr '-' '_')
    if nft list chain $family $table_name output 2>/dev/null | grep -q "port_${port_safe}_out"; then
        return 0
    fi

    # 智能处理匹配表达式（兼容单端口和端口段）
    local match_expr="dport $port"
    local sport_expr="sport $port"
    if is_port_range "$port"; then
        local mark_id=$(generate_port_range_mark "$port")
        match_expr="dport $port meta mark set $mark_id"
        sport_expr="sport $port meta mark set $mark_id"
    fi

    # 1. 注入出站规则 (Out & Forward Out)
    nft list counter $family $table_name "port_${port_safe}_out" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port_safe}_out\n"
    for proto in tcp udp; do
        batch_cmds+="add rule $family $table_name output $proto $sport_expr counter name \"port_${port_safe}_out\"\n"
        batch_cmds+="add rule $family $table_name forward $proto $sport_expr counter name \"port_${port_safe}_out\"\n"
    done

    # 2. 注入入站规则 (In & Forward In)
    nft list counter $family $table_name "port_${port_safe}_in" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port_safe}_in\n"
    for proto in tcp udp; do
        batch_cmds+="add rule $family $table_name input $proto $match_expr counter name \"port_${port_safe}_in\"\n"
        batch_cmds+="add rule $family $table_name forward $proto $match_expr counter name \"port_${port_safe}_in\"\n"
    done

    if [ -n "$batch_cmds" ]; then
        echo -e "$batch_cmds" | nft -f - 2>/dev/null || true
    fi
}

remove_nftables_rules() {
    local port=$1
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        local search_pattern="port_${port_safe}_"
    else
        local search_pattern="port_${port}_"
    fi

    local deleted_count=0
    while true; do
        local handle=$(nft -a list table $family $table_name 2>/dev/null | grep -E "(tcp|udp).*(dport|sport).*$search_pattern" | head -n1 | sed -n 's/.*# handle \([0-9]\+\)$/\1/p')
        if [ -z "$handle" ]; then break; fi
        for chain in input output forward; do
            if nft delete rule $family $table_name $chain handle $handle 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                break
            fi
        done
        if [ $deleted_count -ge 150 ]; then break; fi
    done

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        nft delete counter $family $table_name "port_${port_safe}_in" 2>/dev/null || true
        nft delete counter $family $table_name "port_${port_safe}_out" 2>/dev/null || true
    else
        nft delete counter $family $table_name "port_${port}_in" 2>/dev/null || true
        nft delete counter $family $table_name "port_${port}_out" 2>/dev/null || true
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
    read_trimmed limit_input "带宽限制: "

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

    local billing_mode
    local default_billing_mode=$(get_port_billing_mode "${ports_to_quota[0]}")
    billing_mode=$(choose_billing_mode "$default_billing_mode")

    local success_count=0
    for i in "${!ports_to_quota[@]}"; do
        local port="${ports_to_quota[$i]}"
        local quota=$(echo "${QUOTAS[$i]}" | tr -d ' ')

        if [ "$quota" = "0" ] || [ -z "$quota" ]; then
            remove_nftables_quota "$port"
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"unlimited\" | .ports.\"$port\".quota.billing_mode = \"$billing_mode\" | del(.ports.\"$port\".quota.reset_day)"
            remove_port_auto_reset_cron "$port"
            success_count=$((success_count + 1))
            continue
        fi

        remove_nftables_quota "$port"
        update_config ".ports.\"$port\".quota.billing_mode = \"$billing_mode\""
        apply_nftables_quota "$port" "$quota"
        local current_monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE")
        
        if [ "$current_monthly_limit" = "unlimited" ]; then
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"$quota\" | .ports.\"$port\".quota.reset_day = 1 | .ports.\"$port\".quota.billing_mode = \"$billing_mode\""
        else
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"$quota\" | .ports.\"$port\".quota.billing_mode = \"$billing_mode\""
        fi
        
        setup_port_auto_reset_cron "$port"
        success_count=$((success_count + 1))
    done
    echo -e "${GREEN}成功设置 $success_count 个端口的流量配额${NC}"
    sleep 3; manage_traffic_limits
}

manage_traffic_limits() {
    echo -e "${BLUE}=== 端口限制设置管理 ===${NC}"
    echo "1. 设置端口带宽限制（速率控制）"
    echo "2. 设置端口流量配额（总量控制）"
    echo "0. 返回主菜单"
    read_trimmed choice "请选择操作 [0-2]: "
    case $choice in
        1) set_port_bandwidth_limit ;;
        2) set_port_quota_limit ;;
        0) show_main_menu ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; manage_traffic_limits ;;
    esac
}

# 优化5：批量应用 nftables 配额限制规则
apply_nftables_quota() {
    local port=$1
    local quota_limit=$2
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    local quota_bytes=$(parse_size_to_bytes "$quota_limit")
    local billing_mode=$(get_port_billing_mode "$port")
    
    local current_traffic=($(get_nftables_counter_data "$port"))
    local current_raw_total=$(( ${current_traffic[0]} + ${current_traffic[1]} ))
    local current_single_total=${current_traffic[1]:-0}
    local effective_quota_bytes=$quota_bytes
    local effective_used_bytes=$current_raw_total
    if [ "$billing_mode" = "single" ]; then
        effective_used_bytes=$current_single_total
    fi
    local batch_cmds=""

    local port_safe=$(echo "$port" | tr '-' '_')
    local quota_name="port_${port_safe}_quota"
    
    nft delete quota $family $table_name $quota_name 2>/dev/null || true
    nft add quota $family $table_name $quota_name { over $effective_quota_bytes bytes used $effective_used_bytes bytes } 2>/dev/null || true

    # 出站与转发过滤规则
    for proto in tcp udp; do
        batch_cmds+="insert rule $family $table_name output $proto sport $port quota name \"$quota_name\" drop\n"
        batch_cmds+="insert rule $family $table_name forward $proto sport $port quota name \"$quota_name\" drop\n"
    done

    if [ "$billing_mode" = "dual" ]; then
        # 双向配额才把入站也计入 quota；单向配额只限制出站。
        for proto in tcp udp; do
            batch_cmds+="insert rule $family $table_name input $proto dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward $proto dport $port quota name \"$quota_name\" drop\n"
        done
    fi

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
        local handle=$(nft -a list table $family $table_name 2>/dev/null | grep "quota name \"$quota_name\"" | head -n1 | sed -n 's/.*# handle \([0-9]\+\)$/\1/p')
        if [ -z "$handle" ]; then break; fi
        for chain in input output forward; do
            if nft delete rule $family $table_name $chain handle $handle 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                break
            fi
        done
        if [ $deleted_count -ge 150 ]; then break; fi
    done
    nft delete quota $family $table_name "$quota_name" 2>/dev/null || true
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

    tc class add dev $interface parent 1:1 classid $class_id htb rate $total_limit ceil $total_limit burst $burst_size

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
    echo -e "${BLUE}流量重置管理${NC}"
    echo "1. 每月流量重置日设置"
    echo "2. 立即重置"
    echo "0. 返回主菜单"
    read_trimmed choice "请选择操作 [0-2]: "
    case $choice in
        1) set_reset_day ;;
        2) immediate_reset ;;
        0) show_main_menu ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; manage_traffic_reset ;;
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
        if [ "$quota_enabled" = "true" ] && [ "$monthly_limit" != "unlimited" ] && [ "$reset_day" != "null" ]; then
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
        nft reset counter $family $table_name "port_${port_safe}_in" >/dev/null 2>&1 || true
        nft reset counter $family $table_name "port_${port_safe}_out" >/dev/null 2>&1 || true
        nft reset quota $family $table_name "port_${port_safe}_quota" >/dev/null 2>&1 || true
    else
        nft reset counter $family $table_name "port_${port}_in" >/dev/null 2>&1 || true
        nft reset counter $family $table_name "port_${port}_out" >/dev/null 2>&1 || true
        nft reset quota $family $table_name "port_${port}_quota" >/dev/null 2>&1 || true
    fi
}

manage_configuration() {
    echo -e "${BLUE}=== 配置文件管理 ===${NC}"
    echo "1. 导出配置包"
    echo "2. 导入配置包"
    echo "0. 返回上级菜单"
    read_trimmed choice "请输入选择 [0-2]: "
    case $choice in
        1) export_config ;;
        2) import_config ;;
        0) show_main_menu ;;
        *) manage_configuration ;;
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
    read_trimmed package_path "配置包路径: "
    if [ -f "$package_path" ]; then
        if confirm_danger "导入配置包" "会把配置包内容解压到系统根目录，覆盖现有 Port Traffic Dog 配置。"; then
            tar -xzf "$package_path" -C / 2>/dev/null
            echo -e "${GREEN}配置包已恢复，重启脚本生效。${NC}"
        fi
    fi
    sleep 2; manage_configuration
}

download_with_sources() {
    local url=$1
    local output_file=$2

    if curl -sL --connect-timeout 5 --max-time 7 "$url" -o "$output_file" 2>/dev/null; then
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

    local temp_file=$(mktemp /tmp/port-traffic-dog-update.XXXXXX)
    
    if download_with_sources "$SCRIPT_URL" "$temp_file"; then
        if [ -s "$temp_file" ] && grep -q "端口流量狗" "$temp_file" 2>/dev/null; then
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
            echo -e "${RED}错误：下载的文件验证失败，请检查网络或 URL。${NC}"
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
    echo "  3. 删除 Telegram/企业微信/自动重置等定时任务"
    echo "  4. 停止并删除 TG 交互机器人后台服务 (Systemd)"
    echo "  5. 删除快捷命令 dog"
    echo "  6. 删除所有配置文件及日志 (/etc/port-traffic-dog)" 
    echo "  7. 删除脚本本身" 
    echo
    echo -e "${RED}🔴 警告：此操作不可逆，所有历史流量数据将永久丢失！${NC}" 
    if confirm_danger "卸载端口流量狗" "会删除 nftables/tc 规则、定时任务、机器人服务、快捷命令、配置和历史流量数据。"; then
        echo -e "${YELLOW}正在全力卸载中...${NC}"

        local active_ports=($(get_active_ports 2>/dev/null || true))
        for port in "${active_ports[@]}"; do
            remove_nftables_rules "$port" 2>/dev/null || true
            remove_tc_limit "$port" 2>/dev/null || true
            remove_port_auto_reset_cron "$port" 2>/dev/null || true
        done

        local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE" 2>/dev/null || echo "port_traffic_monitor")
        local family=$(jq -r '.nftables.family' "$CONFIG_FILE" 2>/dev/null || echo "inet")
        nft delete table $family $table_name >/dev/null 2>&1 || true

        systemctl stop port-tg-bot 2>/dev/null || true
        systemctl disable port-tg-bot 2>/dev/null || true
        rm -f /etc/systemd/system/port-tg-bot.service 2>/dev/null
        systemctl daemon-reload

        remove_telegram_notification_cron 2>/dev/null || true
        remove_wecom_notification_cron 2>/dev/null || true

        rm -rf "$CONFIG_DIR" 2>/dev/null || true 
        rm -f "/usr/local/bin/$SHORTCUT_COMMAND" 2>/dev/null || true
        
        echo -e "${GREEN}✅ 卸载完成！${NC}" 
        echo -e "${YELLOW}感谢使用，江湖路远，有缘再见！👋${NC}" 
        
        rm -f "$SCRIPT_PATH" 2>/dev/null || true 
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

    update_config ".notifications.telegram.bot_token = \"$bot_token\" | .notifications.telegram.chat_id = \"$chat_id\" | .notifications.telegram.enabled = true"

    echo -e "${YELLOW}正在部署 Systemd 守护进程...${NC}"
    
    cat > /etc/systemd/system/port-tg-bot.service << EOF
[Unit]
Description=Port Traffic Dog Interactive TG Bot
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash $SCRIPT_PATH --run-listener
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable port-tg-bot 2>/dev/null || true
    systemctl restart port-tg-bot

    echo -e "${GREEN}✅ 部署成功！机器人已在后台常驻运行。${NC}"
    echo -e "💡 提示: 请确保在 @BotFather 关闭了机器人的 Group Privacy (Turn OFF)"
    echo -e "现在可发送 ${YELLOW}/t 端口号${NC}、${YELLOW}/all${NC}、${YELLOW}/yday${NC}、${YELLOW}/trend${NC}、${YELLOW}/day YYYY-MM-DD${NC}"
    echo
    read -r -p "按回车键返回..."
    manage_notifications
}

stop_interactive_tg() {
    echo -e "${YELLOW}正在停止并卸载 Telegram 交互机器人服务...${NC}"
    systemctl stop port-tg-bot 2>/dev/null || true
    systemctl disable port-tg-bot 2>/dev/null || true
    rm -f /etc/systemd/system/port-tg-bot.service
    systemctl daemon-reload
    echo -e "${GREEN}✅ 交互式机器人服务已完全停止。${NC}"
    sleep 2
    manage_notifications
}

manage_display_mode() {
    echo -e "${BLUE}=== 流量口径说明 ===${NC}"
    echo -e "${GREEN}用户单向(出站)：${NC}只看 VPS 发给用户的数据，最接近用户本地实际消耗的节点流量。"
    echo -e "${GREEN}端口双向：${NC}监控端口的入站 + 出站，适合按“服务产生的双向流量”看单个端口贡献。"
    echo -e "${GREEN}VPS商家口径：${NC}整台机器所有网卡入站 + 出站，商家后台通常按这个逻辑计费。"
    echo
    echo -e "${YELLOW}注意：商家后台包含系统更新、Docker、面板、探针等所有流量，不只包含被 dog 监控的端口。${NC}"
    echo -e "${YELLOW}如果你要给用户看 Clash/订阅里的实际用量，一般看“用户单向(出站)”更直观。${NC}"
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

tg_send_message() {
    local token="$1"
    local chat_id="$2"
    local text="$3"
    local parse_mode="${4:-HTML}"

    if [ -n "$parse_mode" ]; then
        curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "parse_mode=${parse_mode}" >/dev/null 2>&1 || true
    else
        curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text}" >/dev/null 2>&1 || true
    fi
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

    local traffic_data=($(get_nftables_counter_data "$port"))
    local in_b=${traffic_data[0]:-0}
    local out_b=${traffic_data[1]:-0}
    local raw_total=$((in_b + out_b))
    local billing_mode=$(get_port_billing_mode "$port")
    local billing_usage=$(get_port_usage_by_mode "$port" "$billing_mode")

    cat <<EOF
<b>端口流量实时报告</b>
监听端口: <code>${port}</code>
用户单向(出站): <code>$(format_bytes "$out_b")</code>
端口双向(入站+出站): <b>$(format_bytes "$raw_total")</b>
入站流量: <code>$(format_bytes "$in_b")</code>
出站流量: <code>$(format_bytes "$out_b")</code>
当前配额口径: <code>$(get_billing_mode_label "$billing_mode")</code>
配额已用: <b>$(format_bytes "$billing_usage")</b>
查询时间: $(get_beijing_time '+%Y-%m-%d %H:%M:%S')
EOF
}

build_tg_all_ports_report() {
    local active_ports=($(get_active_ports 2>/dev/null || true))
    if [ ${#active_ports[@]} -eq 0 ]; then
        echo "当前暂无监控端口"
        return 0
    fi

    local total_raw=0
    local total_single=0
    local provider_traffic=($(get_vps_provider_traffic_since_boot))
    local report="<b>全部端口实时流量汇总</b>"

    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
        local in_b=${traffic_data[0]:-0}
        local out_b=${traffic_data[1]:-0}
        local raw_total=$((in_b + out_b))

        total_raw=$((total_raw + raw_total))
        total_single=$((total_single + out_b))
        report+=$'\n'
        report+="端口 <code>${port}</code> | 单向: $(format_bytes "$out_b") | 双向: $(format_bytes "$raw_total")"
    done

    report+=$'\n'
    report+="用户单向合计: <b>$(format_bytes "$total_single")</b>"
    report+=$'\n'
    report+="端口双向合计: <b>$(format_bytes "$total_raw")</b>"
    report+=$'\n'
    report+="VPS商家口径(整机自启动): <b>$(format_bytes "${provider_traffic[2]:-0}")</b>"
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

    local total_raw=$(jq -r --arg day "$day_key" '.days[$day].total_raw // 0' "$DAILY_USAGE_FILE")
    local total_single=$(jq -r --arg day "$day_key" '.days[$day].total_single // 0' "$DAILY_USAGE_FILE")
    local report="<b>${day_key} 日报</b>"
    report+=$'\n'
    report+="用户单向(出站): <b>$(format_bytes "$total_single")</b>"
    report+=$'\n'
    report+="端口双向: <b>$(format_bytes "$total_raw")</b>"

    local ports=($(jq -r --arg day "$day_key" '.days[$day].ports | keys[]?' "$DAILY_USAGE_FILE" 2>/dev/null | sort -n))
    if [ ${#ports[@]} -gt 0 ]; then
        for port in "${ports[@]}"; do
            local raw=$(jq -r --arg day "$day_key" --arg port "$port" '.days[$day].ports[$port] | if type == "object" then .raw // 0 else . // 0 end' "$DAILY_USAGE_FILE")
            local single=$(jq -r --arg day "$day_key" --arg port "$port" '.days[$day].ports[$port] | if type == "object" then .single // 0 else 0 end' "$DAILY_USAGE_FILE")
            report+=$'\n'
            report+="端口 <code>${port}</code> | 单向: $(format_bytes "$single") | 双向: $(format_bytes "$raw")"
        done
    fi

    echo "$report"
}

build_tg_7days_report() {
    ensure_daily_usage_files
    local sum_raw=0
    local sum_single=0
    local report="<b>近7日趋势报表</b>"

    for ((i=6; i>=0; i--)); do
        local day_key=$(get_beijing_time -d "-$i day" +%F)
        local day_raw=$(jq -r --arg day "$day_key" '.days[$day].total_raw // 0' "$DAILY_USAGE_FILE" 2>/dev/null || echo "0")
        local day_single=$(jq -r --arg day "$day_key" '.days[$day].total_single // 0' "$DAILY_USAGE_FILE" 2>/dev/null || echo "0")
        sum_raw=$((sum_raw + day_raw))
        sum_single=$((sum_single + day_single))
        report+=$'\n'
        report+="${day_key} | 单向: $(format_bytes "$day_single") | 双向: $(format_bytes "$day_raw")"
    done

    report+=$'\n'
    report+="7日单向合计: <b>$(format_bytes "$sum_single")</b>"
    report+=$'\n'
    report+="7日双向合计: <b>$(format_bytes "$sum_raw")</b>"
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
        local updates=$(curl -s --max-time 60 "https://api.telegram.org/bot${token}/getUpdates?offset=${offset}&timeout=50")
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
    echo -e "${BLUE}=== 通知管理 ===${NC}"
    echo "1. 部署 Telegram 交互式查询机器人 (支持 /t /all /yday /trend /day)"
    echo "2. 停止并卸载 Telegram 交互式机器人"
    echo "3. 原版企业 wx 机器人通知配置 (保留接口)"
    echo "0. 返回主菜单"
    echo
    read_trimmed choice "请选择操作 [0-3]: "

    case $choice in
        1) setup_interactive_tg ;;
        2) stop_interactive_tg ;;
        3) echo -e "${YELLOW}请使用旧版逻辑维护${NC}"; sleep 2; manage_notifications ;;
        0) show_main_menu ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; manage_notifications ;;
    esac
}

setup_port_auto_reset_cron() {
    local temp_cron=$(mktemp /tmp/port-traffic-dog-cron.XXXXXX)
    # 顺手把之前可能生成的冗余独立端口规则清理掉
    crontab -l 2>/dev/null | grep -v -- "端口流量狗自动重置端口" | grep -v -- "--reset-port" | grep -v -- "--daily-reset-check" > "$temp_cron" || true
    
    # 注入唯一的“全局每日智能心跳检测”
    echo "5 0 * * * /bin/bash \"$SCRIPT_PATH\" --daily-reset-check >/dev/null 2>&1  # 端口流量狗全局智能流量重置" >> "$temp_cron"
    
    crontab "$temp_cron"
    rm -f "$temp_cron"
}

remove_port_auto_reset_cron() {
    # 既然改为了全局每日心跳，这里不需要再单独删配置了，留空即可
    : 
}
create_shortcut_command() {
    if [ ! -f "/usr/local/bin/$SHORTCUT_COMMAND" ]; then
        cat > "/usr/local/bin/$SHORTCUT_COMMAND" << EOF
#!/bin/bash
exec bash "$SCRIPT_PATH" "\$@"
EOF
        chmod +x "/usr/local/bin/$SHORTCUT_COMMAND" 2>/dev/null || true
    fi
}

main() {
    # 1. 基础环境校验
    check_root
    
    # 2. 👉 【核心大招】：把配置初始化和恢复规则提到了最前面！
    # 这样无论是开机自启还是手动运行，它都会先默默检查并补齐丢失的监控规则
    init_config  

    # 3. 拦截后台机器人的启动参数
    if [ "${1:-}" == "--run-listener" ]; then
        run_tg_listener
        exit 0
    fi
    
    # 4. 拦截自动重置的参数
    if [ "${1:-}" == "--reset-port" ]; then
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
    # 5. 常规的前台菜单逻辑
    check_dependencies
    create_shortcut_command
    show_main_menu
}

main "$@"
