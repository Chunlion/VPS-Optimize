#!/bin/bash
#原项目https://github.com/zywe03/realm-xwPF/blob/main/port-traffic-dog.sh
set -euo pipefail

readonly SCRIPT_VERSION="1.2.6-TG增强版(优化版)"
readonly SCRIPT_NAME="端口流量狗"
readonly SCRIPT_PATH="$(realpath "$0")"
readonly CONFIG_DIR="/etc/port-traffic-dog"
readonly CONFIG_FILE="$CONFIG_DIR/config.json"
readonly LOG_FILE="$CONFIG_DIR/logs/traffic.log"
readonly TRAFFIC_DATA_FILE="$CONFIG_DIR/traffic_data.json"

readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

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
    if ! crontab -l 2>/dev/null | grep -q "@reboot.*port-traffic-dog"; then
        local temp_cron2=$(mktemp)
        crontab -l 2>/dev/null > "$temp_cron2" || true
        echo "@reboot /bin/bash $SCRIPT_PATH >/dev/null 2>&1" >> "$temp_cron2"
        crontab "$temp_cron2" 2>/dev/null || true
        rm -f "$temp_cron2"
    fi
    # 修复：注入高频持久化任务，防止意外死机导致的流量数据蒸发
    if ! crontab -l 2>/dev/null | grep -q "port-traffic-dog.*--save-data"; then
        local temp_cron3=$(mktemp)
        crontab -l 2>/dev/null > "$temp_cron3" || true
        # 每小时第 15 分钟触发一次后台数据存档
        echo "15 * * * * /bin/bash \"$SCRIPT_PATH\" --save-data >/dev/null 2>&1" >> "$temp_cron3"
        crontab "$temp_cron3" 2>/dev/null || true
        rm -f "$temp_cron3"
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
    "billing_mode": "double"
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
        local gb=$(echo "scale=2; $bytes / 1073741824" | bc)
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

parse_multi_choice_input() {
    local input="$1"
    local max_choice="$2"
    local -n result_array=$3
    IFS=',' read -ra CHOICES <<< "$input"
    result_array=()
    for choice in "${CHOICES[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max_choice" ]; then
            result_array+=("$choice")
        else
            echo -e "${RED}无效选择: $choice${NC}"
        fi
    done
}

parse_comma_separated_input() {
    local input="$1"
    local -n result_array=$2
    IFS=',' read -ra result_array <<< "$input"
    for i in "${!result_array[@]}"; do
        result_array[$i]=$(echo "${result_array[$i]}" | tr -d ' ')
    done
}

parse_port_range_input() {
    local input="$1"
    local -n result_array=$2
    IFS=',' read -ra PARTS <<< "$input"
    result_array=()
    for part in "${PARTS[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        if is_port_range "$part"; then
            local start_port=$(echo "$part" | cut -d'-' -f1)
            local end_port=$(echo "$part" | cut -d'-' -f2)
            if [ "$start_port" -gt "$end_port" ]; then
                echo -e "${RED}错误：端口段 $part 起始端口大于结束端口${NC}"
                return 1
            fi
            if [ "$start_port" -lt 1 ] || [ "$start_port" -gt 65535 ] || [ "$end_port" -lt 1 ] || [ "$end_port" -gt 65535 ]; then
                echo -e "${RED}错误：端口段 $part 包含无效端口${NC}"
                return 1
            fi
            result_array+=("$part")
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            if [ "$part" -ge 1 ] && [ "$part" -le 65535 ]; then
                result_array+=("$part")
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
    local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
    local input_bytes=0
    local output_bytes=0

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        if [ "$billing_mode" = "double" ]; then
            input_bytes=$(nft list counter $family $table_name "port_${port_safe}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
        fi
        output_bytes=$(nft list counter $family $table_name "port_${port_safe}_out" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
    else
        if [ "$billing_mode" = "double" ]; then
            input_bytes=$(nft list counter $family $table_name "port_${port}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || true)
        fi
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
    local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        if [ "$billing_mode" = "double" ]; then
            nft add counter $family $table_name "port_${port_safe}_in" { packets 0 bytes $target_input } 2>/dev/null || true
        fi
        nft add counter $family $table_name "port_${port_safe}_out" { packets 0 bytes $target_output } 2>/dev/null || true
    else
        if [ "$billing_mode" = "double" ]; then
            nft add counter $family $table_name "port_${port}_in" { packets 0 bytes $target_input } 2>/dev/null || true
        fi
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
    local billing_mode=${3:-"double"}
    case $billing_mode in
        "double") echo $((input_bytes + output_bytes)) ;;
        "single"|*) echo $output_bytes ;;
    esac
}

get_port_status_label() {
    local port=$1
    local port_config=$(jq -r ".ports.\"$port\"" "$CONFIG_FILE" 2>/dev/null)
    local remark=$(echo "$port_config" | jq -r '.remark // ""')
    local billing_mode=$(echo "$port_config" | jq -r '.billing_mode // "single"')
    local limit_enabled=$(echo "$port_config" | jq -r '.bandwidth_limit.enabled // false')
    local rate_limit=$(echo "$port_config" | jq -r '.bandwidth_limit.rate // "unlimited"')
    local quota_enabled=$(echo "$port_config" | jq -r '.quota.enabled // true')
    local monthly_limit=$(echo "$port_config" | jq -r '.quota.monthly_limit // "unlimited"')
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
            if [ "$billing_mode" = "double" ]; then
                status_tags+=("[双向${quota_display}]")
            else
                status_tags+=("[单向${quota_display}]")
            fi
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
            if [ "$billing_mode" = "double" ]; then status_tags+=("[双向无限制]"); else status_tags+=("[单向无限制]"); fi
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
    local traffic_data=($(get_nftables_counter_data "$port"))
    local input_bytes=${traffic_data[0]}
    local output_bytes=${traffic_data[1]}
    local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
    calculate_total_traffic "$input_bytes" "$output_bytes" "$billing_mode"
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
        local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
        local port_total=$(calculate_total_traffic "$input_bytes" "$output_bytes" "$billing_mode")
        total_bytes=$(( total_bytes + port_total ))
    done
    format_bytes $total_bytes
}

format_port_list() {
    local format_type="$1"
    local active_ports=($(get_active_ports))
    local result=""
    for port in "${active_ports[@]}"; do
        local traffic_data=($(get_nftables_counter_data "$port"))
        local input_bytes=${traffic_data[0]}
        local output_bytes=${traffic_data[1]}
        local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
        local total_bytes=$(calculate_total_traffic "$input_bytes" "$output_bytes" "$billing_mode")
        local total_formatted=$(format_bytes $total_bytes)
        local output_formatted=$(format_bytes $output_bytes)
        local status_label=$(get_port_status_label "$port")
        local input_formatted=$(format_bytes $input_bytes)

        if [ "$format_type" = "display" ]; then
            echo -e "端口:${GREEN}$port${NC} | 总流量:${GREEN}$total_formatted${NC} | 上行(入站): ${GREEN}$input_formatted${NC} | 下行(出站):${GREEN}$output_formatted${NC} | ${YELLOW}$status_label${NC}"
        elif [ "$format_type" = "markdown" ]; then
            result+="> 端口:**${port}** | 总流量:**${total_formatted}** | 上行:**${input_formatted}** | 下行:**${output_formatted}** | ${status_label}\n"
        else
            result+="\n端口:${port} | 总流量:${total_formatted} | 上行(入站): ${input_formatted} | 下行(出站):${output_formatted} | ${status_label}"
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
    local daily_total=$(get_daily_total_traffic)

    echo -e "${BLUE}=== 端口流量狗 v$SCRIPT_VERSION ===${NC}"
    echo -e "${GREEN}介绍主页:${NC}https://zywe.de | ${GREEN}原项目:${NC}https://github.com/zywe03/realm-xwPF"
    echo -e "${GREEN}项目地址：https://github.com/Chunlion/VPS-Optimize 作者修改了部分代码 | 快捷命令: dog${NC}"
    echo
    echo -e "${GREEN}状态: 监控中${NC} | ${BLUE}守护端口: ${port_count}个${NC} | ${YELLOW}端口总流量: $daily_total${NC}"
    echo "────────────────────────────────────────────────────────"

    if [ $port_count -gt 0 ]; then
        format_port_list "display"
    else
        echo -e "${YELLOW}暂无监控端口${NC}"
    fi

    echo "────────────────────────────────────────────────────────"
    echo -e "${BLUE}1.${NC} 添加/删除端口监控     ${BLUE}2.${NC} 端口限制设置管理"
    echo -e "${BLUE}3.${NC} 流量重置管理          ${BLUE}4.${NC} 一键导出/导入配置"
    echo -e "${BLUE}5.${NC} 检查并自动热更新脚本    ${BLUE}6.${NC} 卸载脚本"
    echo -e "${BLUE}7.${NC} 通知管理 (含交互式TG机器人)"
    echo -e "${BLUE}0.${NC} 退出"
    echo
    read -p "请选择操作 [0-7]: " choice

    case $choice in
        1) manage_port_monitoring ;;
        2) manage_traffic_limits ;;
        3) manage_traffic_reset ;;
        4) manage_configuration ;;
        5) install_update_script ;;
        6) uninstall_script ;;
        7) manage_notifications ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择，请输入0-7${NC}"; sleep 1; show_main_menu ;;
    esac
}

manage_port_monitoring() {
    echo -e "${BLUE}=== 端口监控管理 ===${NC}"
    echo "1. 添加端口监控"
    echo "2. 删除端口监控"
    echo "0. 返回主菜单"
    read -p "请选择操作 [0-2]: " choice
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
    read -p "请输入要监控的端口号（多端口使用逗号,分隔,端口段使用-分隔）: " port_input

    local PORTS=()
    parse_port_range_input "$port_input" PORTS
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
    echo "请选择统计模式:"
    echo "1. 双向流量统计 (总流量 = in*2 + out*2)"
    echo "2. 单向流量统计 (仅统计出站)"
    read -p "请选择(回车默认1) [1-2]: " billing_choice

    local billing_mode="double"
    case $billing_choice in
        1|"") billing_mode="double" ;;
        2) billing_mode="single" ;;
        *) billing_mode="double" ;;
    esac

    echo
    local port_list=$(IFS=','; echo "${valid_ports[*]}")
    while true; do
        echo "请输入配额值（0为无限制）（要带单位MB/GB/T）:"
        read -p "流量配额(回车默认0): " quota_input
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
    read -p "请输入当前规则备注(可选，直接回车跳过): " remark_input
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
               --arg billing "$billing_mode" \
               --arg remark "$remark" \
               --arg created "$(get_beijing_time -Iseconds)" \
               --argjson quota_conf "$quota_config" \
               '.ports[$port] = {
                   name: ("端口" + $port),
                   enabled: true,
                   billing_mode: $billing,
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

    read -p "请选择要删除的端口（多端口使用逗号,分隔）: " choice_input
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

    read -p "确认删除这些端口的监控? [y/N]: " confirm
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
    local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
    local batch_cmds=""
    
    local port_safe=$(echo "$port" | tr '-' '_')
    if nft list chain $family $table_name output 2>/dev/null | grep -q "port_${port_safe}_out"; then
        return 0
    fi
    
    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        local mark_id=$(generate_port_range_mark "$port")
        if [ "$billing_mode" = "double" ]; then
            nft list counter $family $table_name "port_${port_safe}_in" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port_safe}_in\n"
            nft list counter $family $table_name "port_${port_safe}_out" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port_safe}_out\n"
            
            batch_cmds+="add rule $family $table_name input tcp dport $port meta mark set $mark_id counter name \"port_${port_safe}_in\"\n"
            batch_cmds+="add rule $family $table_name input udp dport $port meta mark set $mark_id counter name \"port_${port_safe}_in\"\n"
            batch_cmds+="add rule $family $table_name forward tcp dport $port meta mark set $mark_id counter name \"port_${port_safe}_in\"\n"
            batch_cmds+="add rule $family $table_name forward udp dport $port meta mark set $mark_id counter name \"port_${port_safe}_in\"\n"
            
            batch_cmds+="add rule $family $table_name output tcp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
            batch_cmds+="add rule $family $table_name output udp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
            batch_cmds+="add rule $family $table_name forward tcp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
            batch_cmds+="add rule $family $table_name forward udp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
        else
            nft list counter $family $table_name "port_${port_safe}_out" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port_safe}_out\n"
            batch_cmds+="add rule $family $table_name output tcp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
            batch_cmds+="add rule $family $table_name output udp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
            batch_cmds+="add rule $family $table_name forward tcp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
            batch_cmds+="add rule $family $table_name forward udp sport $port meta mark set $mark_id counter name \"port_${port_safe}_out\"\n"
        fi
    else
        if [ "$billing_mode" = "double" ]; then
            nft list counter $family $table_name "port_${port}_in" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port}_in\n"
            nft list counter $family $table_name "port_${port}_out" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port}_out\n"
            
            batch_cmds+="add rule $family $table_name input tcp dport $port counter name \"port_${port}_in\"\n"
            batch_cmds+="add rule $family $table_name input udp dport $port counter name \"port_${port}_in\"\n"
            batch_cmds+="add rule $family $table_name forward tcp dport $port counter name \"port_${port}_in\"\n"
            batch_cmds+="add rule $family $table_name forward udp dport $port counter name \"port_${port}_in\"\n"
            
            batch_cmds+="add rule $family $table_name output tcp sport $port counter name \"port_${port}_out\"\n"
            batch_cmds+="add rule $family $table_name output udp sport $port counter name \"port_${port}_out\"\n"
            batch_cmds+="add rule $family $table_name forward tcp sport $port counter name \"port_${port}_out\"\n"
            batch_cmds+="add rule $family $table_name forward udp sport $port counter name \"port_${port}_out\"\n"
        else
            nft list counter $family $table_name "port_${port}_out" >/dev/null 2>&1 || batch_cmds+="add counter $family $table_name port_${port}_out\n"
            batch_cmds+="add rule $family $table_name output tcp sport $port counter name \"port_${port}_out\"\n"
            batch_cmds+="add rule $family $table_name output udp sport $port counter name \"port_${port}_out\"\n"
            batch_cmds+="add rule $family $table_name forward tcp sport $port counter name \"port_${port}_out\"\n"
            batch_cmds+="add rule $family $table_name forward udp sport $port counter name \"port_${port}_out\"\n"
        fi
    fi

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

    read -p "请选择要限制的端口（多端口使用逗号,分隔） [1-${#active_ports[@]}]: " choice_input
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
    read -p "带宽限制: " limit_input

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
    read -p "请选择要设置配额的端口（多端口使用逗号,分隔） [1-${#active_ports[@]}]: " choice_input

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
        read -p "流量配额(回车默认0): " quota_input
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
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"unlimited\" | del(.ports.\"$port\".quota.reset_day)"
            remove_port_auto_reset_cron "$port"
            success_count=$((success_count + 1))
            continue
        fi

        remove_nftables_quota "$port"
        apply_nftables_quota "$port" "$quota"
        local current_monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE")
        
        if [ "$current_monthly_limit" = "unlimited" ]; then
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"$quota\" | .ports.\"$port\".quota.reset_day = 1"
        else
            update_config ".ports.\"$port\".quota.enabled = true | .ports.\"$port\".quota.monthly_limit = \"$quota\""
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
    echo "3. 修改端口统计方式（双向/单向）"
    echo "0. 返回主菜单"
    read -p "请选择操作 [0-3]: " choice
    case $choice in
        1) set_port_bandwidth_limit ;;
        2) set_port_quota_limit ;;
        3) change_port_billing_mode ;;
        0) show_main_menu ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; manage_traffic_limits ;;
    esac
}

change_port_billing_mode() {
    local active_ports=$(jq -r '.ports | keys[]' "$CONFIG_FILE" 2>/dev/null | sort -n)
    if [ -z "$active_ports" ]; then sleep 2; manage_traffic_limits; return; fi
    
    local port_list=()
    local idx=1
    for port in $active_ports; do
        local current_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
        local mode_display=$([ "$current_mode" = "double" ] && echo "双向" || echo "单向")
        echo -e "  $idx. 端口 $port - 当前模式: ${BLUE}${mode_display}${NC}"
        port_list+=("$port")
        ((idx++))
    done
    echo "  0. 返回上级菜单"
    
    read -p "请选择要修改的端口 [0-$((idx-1))]: " port_choice
    if [ "$port_choice" = "0" ]; then manage_traffic_limits; return; fi
    if ! [[ "$port_choice" =~ ^[0-9]+$ ]] || [ "$port_choice" -lt 1 ] || [ "$port_choice" -gt ${#port_list[@]} ]; then
        change_port_billing_mode; return
    fi
    
    local target_port="${port_list[$((port_choice-1))]}"
    echo "1. 双向流量统计"
    echo "2. 单向流量统计"
    echo "0. 取消"
    read -p "请选择统计模式 [0-2]: " mode_choice
    
    local new_mode=""
    case $mode_choice in
        1) new_mode="double" ;;
        2) new_mode="single" ;;
        0|"") change_port_billing_mode; return ;;
        *) change_port_billing_mode; return ;;
    esac
    
    local traffic_data=($(get_nftables_counter_data "$target_port"))
    local saved_input=${traffic_data[0]:-0}
    local saved_output=${traffic_data[1]:-0}
    
    remove_nftables_rules "$target_port"
    update_config ".ports.\"$target_port\".billing_mode = \"$new_mode\""
    
    restore_counter_value "$target_port" "$saved_input" "$saved_output"
    add_nftables_rules "$target_port"
    
    local quota_enabled=$(jq -r ".ports.\"$target_port\".quota.enabled // false" "$CONFIG_FILE")
    local quota_limit=$(jq -r ".ports.\"$target_port\".quota.monthly_limit // \"\"" "$CONFIG_FILE")
    if [ "$quota_enabled" = "true" ] && [ -n "$quota_limit" ] && [ "$quota_limit" != "null" ] && [ "$quota_limit" != "unlimited" ]; then
        apply_nftables_quota "$target_port" "$quota_limit"
    fi
    echo -e "${GREEN}✓ 统计方式已更新${NC}"
    sleep 2; change_port_billing_mode
}

# 优化5：批量应用 nftables 配额限制规则
apply_nftables_quota() {
    local port=$1
    local quota_limit=$2
    local table_name=$(jq -r '.nftables.table_name' "$CONFIG_FILE")
    local family=$(jq -r '.nftables.family' "$CONFIG_FILE")
    local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
    local quota_bytes=$(parse_size_to_bytes "$quota_limit")
    local current_traffic=($(get_nftables_counter_data "$port"))
    local current_input=${current_traffic[0]}
    local current_output=${current_traffic[1]}
    local current_total=$(calculate_total_traffic "$current_input" "$current_output" "$billing_mode")
    local batch_cmds=""

    if is_port_range "$port"; then
        local port_safe=$(echo "$port" | tr '-' '_')
        local quota_name="port_${port_safe}_quota"
        nft delete quota $family $table_name $quota_name 2>/dev/null || true
        nft add quota $family $table_name $quota_name { over $quota_bytes bytes used $current_total bytes } 2>/dev/null || true

        if [ "$billing_mode" = "double" ]; then
            batch_cmds+="insert rule $family $table_name input tcp dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name input udp dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward tcp dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward udp dport $port quota name \"$quota_name\" drop\n"
            
            batch_cmds+="insert rule $family $table_name output tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name output udp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward udp sport $port quota name \"$quota_name\" drop\n"
        else
            batch_cmds+="insert rule $family $table_name output tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name output udp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward udp sport $port quota name \"$quota_name\" drop\n"
        fi
    else
        local quota_name="port_${port}_quota"
        nft delete quota $family $table_name $quota_name 2>/dev/null || true
        nft add quota $family $table_name $quota_name { over $quota_bytes bytes used $current_total bytes } 2>/dev/null || true

        if [ "$billing_mode" = "double" ]; then
            batch_cmds+="insert rule $family $table_name input tcp dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name input udp dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward tcp dport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward udp dport $port quota name \"$quota_name\" drop\n"
            
            batch_cmds+="insert rule $family $table_name output tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name output udp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward udp sport $port quota name \"$quota_name\" drop\n"
        else
            batch_cmds+="insert rule $family $table_name output tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name output udp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward tcp sport $port quota name \"$quota_name\" drop\n"
            batch_cmds+="insert rule $family $table_name forward udp sport $port quota name \"$quota_name\" drop\n"
        fi
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
    tc class add dev $interface parent 1: classid 1:1 htb rate 1000mbit 2>/dev/null || true

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
    read -p "请选择操作 [0-2]: " choice
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
    
    read -p "请选择要设置重置日期的端口序号（多端口逗号分隔）: " choice_input
    local valid_choices=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices
    
    if [ ${#valid_choices[@]} -eq 0 ]; then
        echo -e "${RED}❌ 未选择有效端口，操作取消。${NC}"
        sleep 2
        manage_traffic_reset
        return
    fi
    
    read -p "请输入每月的重置日期 (输入1-31，输入0代表取消自动重置): " reset_day
    
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
    
    read -p "请选择要立即重置的端口序号（多端口逗号分隔）: " choice_input
    local valid_choices=()
    parse_multi_choice_input "$choice_input" "${#active_ports[@]}" valid_choices
    
    if [ ${#valid_choices[@]} -eq 0 ]; then
        echo -e "${RED}❌ 未选择有效端口！${NC}"
        sleep 2; manage_traffic_reset; return
    fi

    read -p "确认立即清零选定端口的流量吗? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
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
    
    local active_ports=($(get_active_ports 2>/dev/null || true))
    for port in "${active_ports[@]}"; do
        local quota_enabled=$(jq -r ".ports.\"$port\".quota.enabled // false" "$CONFIG_FILE")
        local monthly_limit=$(jq -r ".ports.\"$port\".quota.monthly_limit // \"unlimited\"" "$CONFIG_FILE")
        local reset_day=$(jq -r ".ports.\"$port\".quota.reset_day // null" "$CONFIG_FILE")
        
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
    read -p "请输入选择 [0-2]: " choice
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
    read -p "配置包路径: " package_path
    if [ -f "$package_path" ]; then
        tar -xzf "$package_path" -C / 2>/dev/null
        echo -e "${GREEN}配置包已恢复，重启脚本生效。${NC}"
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

    read -p "按回车键返回菜单..."
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
    read -p "确认卸载? [y/N]: " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
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
    read -p "请输入 Bot Token (去@BotFather获取): " bot_token
    read -p "请输入允许查询的 Chat ID (个人的ID或群组ID): " chat_id

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
    echo -e "现在可以在 TG 群聊发送 ${YELLOW}/t 端口号${NC} 试试看！"
    echo
    read -p "按回车键返回..."
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
            
            echo "$updates" | jq -c '.result[]' | while read -r update; do
                local msg_text=$(echo "$update" | jq -r '.message.text // empty')
                local chat_id=$(echo "$update" | jq -r '.message.chat.id // empty')
                
                if [[ "$msg_text" =~ ^/(traffic|t)[[:space:]]+([0-9]+(-[0-9]+)?)$ ]]; then
                    local port="${BASH_REMATCH[2]}"
                    
                    if jq -e ".ports.\"$port\"" "$CONFIG_FILE" >/dev/null 2>&1; then
                        local billing_mode=$(jq -r ".ports.\"$port\".billing_mode // \"double\"" "$CONFIG_FILE")
                        local port_safe=$(echo "$port" | tr '-' '_')
                        
                        local in_b=$(nft list counter inet port_traffic_monitor "port_${port_safe}_in" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || echo 0)
                        local out_b=$(nft list counter inet port_traffic_monitor "port_${port_safe}_out" 2>/dev/null | grep -o 'bytes [0-9]*' | awk '{print $2}' || echo 0)
   
                        local total=$((out_b))
                        [[ "$billing_mode" == "double" ]] && total=$((in_b + out_b))
                      
                        local reply="🛰️ <b>端口流量实时报告</b>%0A"
                        reply+="────────────────%0A"
                        reply+="🔌 <b>监听端口</b>：<code>${port}</code>%0A"
                        reply+="📈 <b>上行流量</b>：<code>$(format_bytes $in_b)</code> (入口)%0A"
                        reply+="📉 <b>下行流量</b>：<code>$(format_bytes $out_b)</code> (出口)%0A"
                        reply+="────────────────%0A"
                        reply+="💰 <b>合计使用</b>：<b>$(format_bytes $total)</b>%0A"
                        reply+="⚙️ <b>计费逻辑</b>：<code>$([[ "$billing_mode" == "double" ]] && echo "双向计费" || echo "单向计费")</code>%0A"
                        reply+="⏰ <b>查询时间</b>：$(get_beijing_time '+%Y-%m-%d %H:%M:%S')"

                        curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" -d "chat_id=${chat_id}" -d "text=${reply}" -d "parse_mode=HTML" > /dev/null
                    else
                        curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
                            -d "chat_id=${chat_id}" -d "text=❌ 未找到端口 ${port} 的监控数据" > /dev/null
                    fi
                fi
            done
        fi
        sleep 1
    done
}

manage_notifications() {
    echo -e "${BLUE}=== 通知管理 ===${NC}"
    echo "1. 部署 Telegram 交互式查询机器人 (支持在群里 /t 查流量)"
    echo "2. 停止并卸载 Telegram 交互式机器人"
    echo "3. 原版企业 wx 机器人通知配置 (保留接口)"
    echo "0. 返回主菜单"
    echo
    read -p "请选择操作 [0-3]: " choice

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
    crontab -l 2>/dev/null | grep -v "端口流量狗自动重置端口" | grep -v "port-traffic-dog.*--reset-port" | grep -v "--daily-reset-check" > "$temp_cron" || true
    
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
    # 5. 常规的前台菜单逻辑
    check_dependencies
    create_shortcut_command
    show_main_menu
}

main "$@"
