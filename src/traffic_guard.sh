# shellcheck shell=bash
# Traffic quota accounting, guard checker installation, and quota protection menus.

traffic_guard_human_bytes() {
    local bytes="${1:-0}"
    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB PB", u, " ");
        i=1;
        while (b >= 1024 && i < 6) { b=b/1024; i++ }
        if (i == 1) printf "%.0f%s", b, u[i]; else printf "%.2f%s", b, u[i]
    }'
}

traffic_guard_gb_to_bytes() {
    local gb="$1"
    gb="${gb//，/.}"
    gb="${gb//,/}"
    awk -v gb="$gb" 'BEGIN {
        if (gb !~ /^[0-9]+([.][0-9]+)?$/ || gb <= 0) exit 1;
        printf "%.0f", gb * 1024 * 1024 * 1024
    }'
}

traffic_guard_gb_to_bytes_zero_ok() {
    local gb="$1"
    gb="${gb//，/.}"
    gb="${gb//,/}"
    awk -v gb="$gb" 'BEGIN {
        if (gb !~ /^[0-9]+([.][0-9]+)?$/) exit 1;
        printf "%.0f", gb * 1024 * 1024 * 1024
    }'
}

traffic_guard_bytes_to_gb() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    awk -v b="$bytes" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'
}

traffic_guard_sys_class_net() {
    printf '%s' "${VPSO_TRAFFIC_GUARD_SYS_CLASS_NET:-${TRAFFIC_GUARD_SYS_CLASS_NET:-/sys/class/net}}"
}

traffic_guard_iface_is_physical_candidate() {
    local iface="$1"
    case "$iface" in
        lo|docker*|br-*|veth*|tailscale*|wg*|tun*|tap*|zt*|virbr*|vmnet*|cni*|flannel*|kube*|dummy*|ifb*)
            return 1
            ;;
    esac
    return 0
}

traffic_guard_best_active_iface() {
    local sys_net path iface oper rx tx score best_iface="" best_score=-1
    sys_net=$(traffic_guard_sys_class_net)
    for path in "${sys_net}"/*; do
        [[ -e "$path" ]] || continue
        iface="${path##*/}"
        traffic_guard_valid_iface "$iface" || continue
        traffic_guard_iface_is_physical_candidate "$iface" || continue
        oper=$(cat "${path}/operstate" 2>/dev/null || echo "unknown")
        [[ "$oper" == "down" ]] && continue
        rx=$(cat "${path}/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "${path}/statistics/tx_bytes" 2>/dev/null || echo 0)
        [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
        [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
        score=$(( rx + tx ))
        if (( score > best_score )); then
            best_score="$score"
            best_iface="$iface"
        fi
    done
    printf '%s' "$best_iface"
}

traffic_guard_detect_iface() {
    local iface
    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if traffic_guard_valid_iface "$iface" && traffic_guard_iface_is_physical_candidate "$iface"; then
        printf '%s' "$iface"
        return 0
    fi
    iface=$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')
    if traffic_guard_valid_iface "$iface" && traffic_guard_iface_is_physical_candidate "$iface"; then
        printf '%s' "$iface"
        return 0
    fi
    iface=$(ip -o -6 route show default 2>/dev/null | awk '{print $5; exit}')
    if traffic_guard_valid_iface "$iface" && traffic_guard_iface_is_physical_candidate "$iface"; then
        printf '%s' "$iface"
        return 0
    fi
    iface=$(traffic_guard_best_active_iface)
    printf '%s' "$iface"
}

traffic_guard_valid_iface() {
    local iface="$1"
    local sys_net
    [[ -n "$iface" && "$iface" != *"/"* && "$iface" != *".."* ]] || return 1
    sys_net=$(traffic_guard_sys_class_net)
    [[ -r "${sys_net}/${iface}/statistics/rx_bytes" && -r "${sys_net}/${iface}/statistics/tx_bytes" ]]
}

traffic_guard_mode_label() {
    case "$1" in
        tx) echo "$(localized_text "出站 TX 计费" "Outbound TX billing" "Биллинг за исходящую передачу")" ;;
        rx) echo "$(localized_text "入站 RX 计费" "Inbound RX billing" "Биллинг входящего приема")" ;;
        total) echo "$(localized_text "出入总量 RX+TX" "Total amount of incoming and outgoing RX+TX" "Общий объем входящих и исходящих RX+TX")" ;;
        max) echo "$(localized_text "任一方向达量" "Amount in any direction" "Сумма в любом направлении")" ;;
        *) echo "$1" ;;
    esac
}

traffic_guard_action_label() {
    case "$1" in
        poweroff) echo "$(localized_text "立即关机" "Shut down immediately" "Немедленно выключить")" ;;
        ssh-only) echo "$(localized_text "仅保留 SSH，封锁其余公网业务流量" "Only retain SSH and block other public business traffic." "Сохраните только SSH и заблокируйте другой бизнес-трафик публичной сети.")" ;;
        log) echo "$(localized_text "只写日志" "Just write a log" "Просто напишите журнал")" ;;
        *) echo "$1" ;;
    esac
}

traffic_guard_select_ssh_port() {
    local current_port="${1:-}" candidate
    shift || true
    if [[ "$current_port" =~ ^[0-9]+$ ]] && (( current_port >= 1 && current_port <= 65535 )); then
        for candidate in "$@"; do
            if [[ "$candidate" == "$current_port" ]]; then
                printf '%s' "$current_port"
                return 0
            fi
        done
    fi
    if (( $# == 1 )) && [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); then
        printf '%s' "$1"
        return 0
    fi
    return 1
}

traffic_guard_detect_ssh_port() {
    local _client_addr _client_port _server_addr current_port _extra sshd_bin
    local -a ssh_ports=()
    read -r _client_addr _client_port _server_addr current_port _extra <<< "${SSH_CONNECTION:-}"
    [[ -z "${_extra:-}" ]] || current_port=""

    mapfile -t ssh_ports < <(ss -tlnp 2>/dev/null | awk '/sshd/ {addr=$4; sub(/^.*:/, "", addr); if (addr ~ /^[0-9]+$/) print addr}' | sort -nu)
    if (( ${#ssh_ports[@]} > 0 )); then
        traffic_guard_select_ssh_port "$current_port" "${ssh_ports[@]}"
        return $?
    fi

    sshd_bin=$(command -v sshd 2>/dev/null || true)
    if [[ -n "$sshd_bin" ]]; then
        mapfile -t ssh_ports < <("$sshd_bin" -T 2>/dev/null | awk '$1 == "port" && $2 ~ /^[0-9]+$/ {print $2}' | sort -nu)
    fi
    traffic_guard_select_ssh_port "$current_port" "${ssh_ports[@]}"
}

traffic_guard_ssh_only_firewall_supported() {
    command -v iptables >/dev/null 2>&1 || return 1
    [[ ! -s /proc/net/if_inet6 ]] || command -v ip6tables >/dev/null 2>&1
}

traffic_guard_normalize_cycle_day() {
    local cycle_day="${1:-1}"
    [[ "$cycle_day" =~ ^[0-9]+$ ]] || cycle_day=1
    cycle_day=$((10#$cycle_day))
    (( cycle_day >= 1 && cycle_day <= 31 )) || cycle_day=1
    printf '%s' "$cycle_day"
}

traffic_guard_cycle_date_for_month() {
    local year_month="$1"
    local cycle_day
    local last_day effective_day
    cycle_day=$(traffic_guard_normalize_cycle_day "${2:-1}")
    last_day=$(date -d "${year_month}-01 +1 month -1 day" +%d 2>/dev/null || echo 31)
    last_day=$((10#$last_day))
    effective_day="$cycle_day"
    (( effective_day > last_day )) && effective_day="$last_day"
    printf '%s-%02d' "$year_month" "$effective_day"
}

traffic_guard_current_cycle_key() {
    local cycle_day="${1:-1}"
    local current_month previous_month current_day reset_date reset_day
    cycle_day=$(traffic_guard_normalize_cycle_day "$cycle_day")
    current_month=$(date +%Y-%m)
    reset_date=$(traffic_guard_cycle_date_for_month "$current_month" "$cycle_day")
    reset_day="${reset_date##*-}"
    current_day=$(date +%d)
    if (( 10#$current_day >= 10#$reset_day )); then
        printf '%s' "$reset_date"
    else
        previous_month=$(date -d "${current_month}-01 -1 month" +%Y-%m)
        traffic_guard_cycle_date_for_month "$previous_month" "$cycle_day"
    fi
}

traffic_guard_boot_started_after_cycle_start() {
    local cycle_key="$1"
    local proc_uptime="${VPSO_TRAFFIC_GUARD_PROC_UPTIME:-/proc/uptime}"
    local cycle_epoch now_epoch uptime_raw uptime_seconds boot_epoch
    cycle_epoch=$(date -d "${cycle_key} 00:00:00" +%s 2>/dev/null) || return 1
    read -r uptime_raw _ < "$proc_uptime" 2>/dev/null || return 1
    uptime_seconds="${uptime_raw%%.*}"
    [[ "$uptime_seconds" =~ ^[0-9]+$ ]] || return 1
    now_epoch=$(date +%s 2>/dev/null) || return 1
    boot_epoch=$(( now_epoch - uptime_seconds ))
    (( boot_epoch >= cycle_epoch ))
}

traffic_guard_read_stats() {
    local iface="$1"
    local sys_net
    sys_net=$(traffic_guard_sys_class_net)
    cat "${sys_net}/${iface}/statistics/rx_bytes" "${sys_net}/${iface}/statistics/tx_bytes" 2>/dev/null
}

traffic_guard_mode_usage_bytes() {
    local mode="$1"
    local rx="${2:-0}"
    local tx="${3:-0}"
    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    case "$mode" in
        rx) printf '%s' "$rx" ;;
        total) printf '%s' "$(( rx + tx ))" ;;
        max)
            if (( rx > tx )); then printf '%s' "$rx"; else printf '%s' "$tx"; fi
            ;;
        tx|*) printf '%s' "$tx" ;;
    esac
}

traffic_guard_scale_offset_bytes() {
    local total="${1:-0}"
    local part="${2:-0}"
    local whole="${3:-0}"
    awk -v total="$total" -v part="$part" -v whole="$whole" 'BEGIN {
        if (total !~ /^[0-9]+$/ || part !~ /^[0-9]+$/ || whole !~ /^[0-9]+$/ || whole <= 0) {
            print 0;
            exit;
        }
        printf "%.0f", total * part / whole;
    }'
}

traffic_guard_baseline_direction_offsets() {
    local mode="$1"
    local rx="${2:-0}"
    local tx="${3:-0}"
    local initial="${4:-0}"
    local rx_offset=0 tx_offset=0 current_total

    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    [[ "$initial" =~ ^[0-9]+$ ]] || initial=0

    case "$mode" in
        rx)
            rx_offset="$initial"
            ;;
        total)
            current_total=$(( rx + tx ))
            if (( current_total > 0 )); then
                rx_offset=$(traffic_guard_scale_offset_bytes "$initial" "$rx" "$current_total")
                tx_offset=$(awk -v total="$initial" -v rx_offset="$rx_offset" 'BEGIN {
                    v = total - rx_offset;
                    if (v < 0) v = 0;
                    printf "%.0f", v;
                }')
            else
                rx_offset="$initial"
            fi
            ;;
        max)
            if (( rx >= tx && rx > 0 )); then
                rx_offset="$initial"
                tx_offset=$(traffic_guard_scale_offset_bytes "$initial" "$tx" "$rx")
            elif (( tx > 0 )); then
                tx_offset="$initial"
                rx_offset=$(traffic_guard_scale_offset_bytes "$initial" "$rx" "$tx")
            else
                rx_offset="$initial"
                tx_offset="$initial"
            fi
            ;;
        tx|*)
            tx_offset="$initial"
            ;;
    esac

    printf '%s\n%s\n' "$rx_offset" "$tx_offset"
}

traffic_guard_existing_state_usage() {
    local iface="$1"
    local mode="$2"
    local cycle_day="${3:-}"
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    [[ -r "$TRAFFIC_GUARD_CONFIG" && -r "$state_file" ]] || return 1
    (
        local expected_cycle
        # shellcheck disable=SC1090
        . "$TRAFFIC_GUARD_CONFIG"
        # shellcheck disable=SC1090
        . "$state_file"
        [[ "${IFACE:-}" == "$iface" && "${MODE:-}" == "$mode" ]] || exit 1
        expected_cycle=$(traffic_guard_current_cycle_key "${cycle_day:-${CYCLE_DAY:-1}}")
        [[ "${CYCLE_KEY:-}" == "$expected_cycle" ]] || exit 1
        [[ "${LAST_USAGE:-}" =~ ^[0-9]+$ ]] || exit 1
        printf '%s' "$LAST_USAGE"
    )
}

traffic_guard_detect_initial_used_bytes() {
    local iface="$1"
    local mode="$2"
    local current_stats current_rx current_tx
    mapfile -t current_stats < <(traffic_guard_read_stats "$iface")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    traffic_guard_mode_usage_bytes "$mode" "$current_rx" "$current_tx"
}

traffic_guard_write_state_baseline() {
    local iface="$1"
    local cycle_day="$2"
    local initial_used_bytes="${3:-0}"
    local mode="${4:-${MODE:-tx}}"
    local current_stats current_rx current_tx cycle_key state_file offset_stats offset_rx offset_tx offset_bytes

    [[ "$initial_used_bytes" =~ ^[0-9]+$ ]] || initial_used_bytes=0
    traffic_guard_valid_iface "$iface" || return 1
    mapfile -t current_stats < <(traffic_guard_read_stats "$iface")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    mapfile -t offset_stats < <(traffic_guard_baseline_direction_offsets "$mode" "$current_rx" "$current_tx" "$initial_used_bytes")
    offset_rx="${offset_stats[0]:-0}"
    offset_tx="${offset_stats[1]:-0}"
    offset_bytes=$(traffic_guard_mode_usage_bytes "$mode" "$offset_rx" "$offset_tx")
    cycle_key=$(traffic_guard_current_cycle_key "$cycle_day")
    mkdir -p "$TRAFFIC_GUARD_STATE_DIR" || return 1
    chmod 700 "$TRAFFIC_GUARD_STATE_DIR" 2>/dev/null || true
    state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    {
        echo "CYCLE_KEY='${cycle_key}'"
        echo "STATE_IFACE='${iface}'"
        echo "STATE_MODE='${mode}'"
        echo "BASE_RX='${current_rx}'"
        echo "BASE_TX='${current_tx}'"
        echo "OFFSET_RX_BYTES='${offset_rx}'"
        echo "OFFSET_TX_BYTES='${offset_tx}'"
        echo "OFFSET_BYTES='${offset_bytes}'"
        echo "WARN_SENT='0'"
        echo "TRIPPED='0'"
        echo "LAST_RX='${current_rx}'"
        echo "LAST_TX='${current_tx}'"
        echo "LAST_USAGE='${offset_bytes}'"
        echo "LAST_CHECKED_AT='$(date -Is 2>/dev/null || date)'"
    } > "$state_file"
    chmod 600 "$state_file" 2>/dev/null || true
}

traffic_guard_admin_log() {
    local msg="$1"
    mkdir -p "$(dirname "$TRAFFIC_GUARD_LOG")" 2>/dev/null || true
    printf '%s %s\n' "$(date -Is 2>/dev/null || date)" "$msg" >> "$TRAFFIC_GUARD_LOG" 2>/dev/null || true
    logger -t vps-traffic-guard "$msg" 2>/dev/null || true
}

traffic_guard_checker_first_line_hex() {
    local file="$1"
    [[ -r "$file" ]] || return 1
    head -n 1 "$file" 2>/dev/null | LC_ALL=C od -An -tx1 | awk '{$1=$1; print}'
}

traffic_guard_normalize_generated_checker() {
    local file="$1"
    local tmp
    tmp=$(mktemp "${file}.normalize.XXXXXX") || return 1
    if ! LC_ALL=C sed '1s/^\xef\xbb\xbf//' "$file" | tr -d '\r' > "$tmp"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
    if ! cmp -s "$file" "$tmp"; then
        cat "$tmp" > "$file" || {
            rm -f "$tmp" 2>/dev/null || true
            return 1
        }
        traffic_guard_admin_log "normalized generated checker header/line endings: ${file}"
    fi
    rm -f "$tmp" 2>/dev/null || true
}

traffic_guard_report_checker_install_failure() {
    local reason="$1"
    local file="${2:-$TRAFFIC_GUARD_CHECKER}"
    local first_line_hex
    first_line_hex=$(traffic_guard_checker_first_line_hex "$file" 2>/dev/null || echo "unreadable")
    echo -e "$(localized_text "${RED}❌ Traffic Guard 检查器写入失败：${reason}${PLAIN}" "${RED}❌ Traffic Guard checker write failure: ${reason}${PLAIN}" "${RED}❌ Ошибка записи средства проверки трафика: ${reason}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}检查器路径：${TRAFFIC_GUARD_CHECKER}${PLAIN}" "${YELLOW}Inspector path: ${TRAFFIC_GUARD_CHECKER}${PLAIN}" "${YELLOW}Путь инспектора : ${TRAFFIC_GUARD_CHECKER}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}待检查文件：${file}${PLAIN}" "${YELLOW}Files to be inspected: ${file}${PLAIN}" "${YELLOW}Файлы для проверки: ${file}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}首行实际字节：${first_line_hex:-empty}${PLAIN}" "${YELLOW}Actual bytes in the first row of : ${first_line_hex:-empty}${PLAIN}" "${YELLOW}Фактические байты в первой строке : ${first_line_hex:-empty}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}日志路径：${TRAFFIC_GUARD_LOG}${PLAIN}" "${YELLOW}Log path: ${TRAFFIC_GUARD_LOG}${PLAIN}" "${YELLOW}Путь журнала : ${TRAFFIC_GUARD_LOG}${PLAIN}")"
    traffic_guard_admin_log "checker install failed: ${reason}; file=${file}; first_line_hex=${first_line_hex:-empty}"
}

traffic_guard_mark_checker_install_failure() {
    local kind="$1"
    local reason="$2"
    local file="${3:-$TRAFFIC_GUARD_CHECKER}"
    TRAFFIC_GUARD_CHECKER_INSTALL_FAILURE_KIND="$kind"
    TRAFFIC_GUARD_CHECKER_INSTALL_FAILURE_FILE="$file"
    traffic_guard_report_checker_install_failure "$reason" "$file"
}

traffic_guard_checker_install_failure_is_generated() {
    [[ "${TRAFFIC_GUARD_CHECKER_INSTALL_FAILURE_KIND:-}" == "generated-content" ]]
}

traffic_guard_install_checker_once() {
    local first_line write_rc tmp_checker
    mkdir -p "$(dirname "$TRAFFIC_GUARD_CHECKER")" "$TRAFFIC_GUARD_STATE_DIR" "$(dirname "$TRAFFIC_GUARD_CONFIG")" || return 1
    tmp_checker=$(mktemp "${TRAFFIC_GUARD_CHECKER}.tmp.XXXXXX") || {
        traffic_guard_mark_checker_install_failure "io" "$(localized_text "无法创建临时检查器文件" "Unable to create temporary checker file" "Невозможно создать временный файл проверки")" "$TRAFFIC_GUARD_CHECKER"
        return 1
    }
    cat > "$tmp_checker" <<'GUARD_SCRIPT'
#!/usr/bin/env bash
set -u

CONFIG="${VPSO_TRAFFIC_GUARD_CONFIG:-/etc/vps-optimize/traffic-guard.conf}"
STATE_DIR="${VPSO_TRAFFIC_GUARD_STATE_DIR:-/var/lib/vps-optimize/traffic-guard}"
STATE_FILE="${STATE_DIR}/state"
LOG_FILE="${VPSO_TRAFFIC_GUARD_LOG:-/var/log/vps-traffic-guard.log}"
SYS_CLASS_NET="${VPSO_TRAFFIC_GUARD_SYS_CLASS_NET:-/sys/class/net}"
PROC_UPTIME="${VPSO_TRAFFIC_GUARD_PROC_UPTIME:-/proc/uptime}"
LOG_MAX_BYTES="${VPSO_TRAFFIC_GUARD_LOG_MAX_BYTES:-5242880}"
LOG_ROTATE_KEEP="${VPSO_TRAFFIC_GUARD_LOG_ROTATE_KEEP:-3}"

log_file_size_bytes() {
    local size
    [[ -f "$LOG_FILE" ]] || { echo 0; return 0; }
    size=$(wc -c < "$LOG_FILE" 2>/dev/null | awk '{print $1}')
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    echo "$size"
}

traffic_guard_rotate_log_file() {
    local size i old_path new_path
    [[ "$LOG_MAX_BYTES" =~ ^[0-9]+$ ]] || LOG_MAX_BYTES=5242880
    [[ "$LOG_ROTATE_KEEP" =~ ^[0-9]+$ ]] || LOG_ROTATE_KEEP=3
    (( LOG_MAX_BYTES > 0 && LOG_ROTATE_KEEP > 0 )) || return 0
    [[ -f "$LOG_FILE" ]] || return 0

    size=$(log_file_size_bytes)
    (( size >= LOG_MAX_BYTES )) || return 0

    rm -f "${LOG_FILE}.${LOG_ROTATE_KEEP}" 2>/dev/null || true
    for ((i = LOG_ROTATE_KEEP - 1; i >= 1; i--)); do
        old_path="${LOG_FILE}.${i}"
        new_path="${LOG_FILE}.$((i + 1))"
        [[ -e "$old_path" ]] && mv -f "$old_path" "$new_path" 2>/dev/null || true
    done
    mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
}

log_msg() {
    local msg="$1"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    traffic_guard_rotate_log_file
    printf '%s %s\n' "$(date -Is 2>/dev/null || date)" "$msg" >> "$LOG_FILE" 2>/dev/null || true
    logger -t vps-traffic-guard "$msg" 2>/dev/null || true
}

SSH_ONLY_FIREWALL_TAG="VPSO-TRAFFIC-GUARD-SSH-ONLY"
SSH_ONLY_ICMPV6_TYPES="1 2 3 4 130 131 132 133 134 135 136 137 141 142 143"

firewall_delete_rule_all() {
    local bin="$1"
    shift
    while "$bin" -C "$@" >/dev/null 2>&1; do
        "$bin" -D "$@" >/dev/null 2>&1 || return 1
    done
}

clear_ssh_only_firewall() {
    local bin chain icmp_type
    local rc=0
    for bin in iptables ip6tables; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            if [[ "$bin" == "iptables" || -s /proc/net/if_inet6 ]]; then
                rc=1
            fi
            continue
        fi
        firewall_delete_rule_all "$bin" INPUT -p tcp --dport "${SSH_PORT:-0}" -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
        firewall_delete_rule_all "$bin" OUTPUT -p tcp --sport "${SSH_PORT:-0}" -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
        firewall_delete_rule_all "$bin" INPUT -i lo -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
        firewall_delete_rule_all "$bin" OUTPUT -o lo -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
        if [[ "$bin" == "ip6tables" ]]; then
            firewall_delete_rule_all "$bin" INPUT -p udp --sport 547 --dport 546 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
            firewall_delete_rule_all "$bin" OUTPUT -p udp --sport 546 --dport 547 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
            for chain in INPUT OUTPUT; do
                for icmp_type in $SSH_ONLY_ICMPV6_TYPES; do
                    firewall_delete_rule_all "$bin" "$chain" -p ipv6-icmp --icmpv6-type "$icmp_type" -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
                done
            done
        else
            firewall_delete_rule_all "$bin" INPUT -p udp --sport 67 --dport 68 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
            firewall_delete_rule_all "$bin" OUTPUT -p udp --sport 68 --dport 67 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || rc=1
        fi
        firewall_delete_rule_all "$bin" INPUT -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j DROP || rc=1
        firewall_delete_rule_all "$bin" OUTPUT -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j DROP || rc=1
        firewall_delete_rule_all "$bin" FORWARD -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j DROP || rc=1
    done
    return "$rc"
}

ensure_ssh_only_rule() {
    local bin="$1"
    local chain="$2"
    shift 2
    "$bin" -C "$chain" "$@" >/dev/null 2>&1 || "$bin" -I "$chain" 1 "$@" >/dev/null 2>&1
}

apply_ssh_only_firewall_for_bin() {
    local bin="$1" chain icmp_type
    ensure_ssh_only_rule "$bin" INPUT -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j DROP || return 1
    ensure_ssh_only_rule "$bin" OUTPUT -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j DROP || return 1
    ensure_ssh_only_rule "$bin" FORWARD -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j DROP || return 1
    ensure_ssh_only_rule "$bin" INPUT -i lo -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
    ensure_ssh_only_rule "$bin" OUTPUT -o lo -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
    if [[ "$bin" == "ip6tables" ]]; then
        ensure_ssh_only_rule "$bin" INPUT -p udp --sport 547 --dport 546 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
        ensure_ssh_only_rule "$bin" OUTPUT -p udp --sport 546 --dport 547 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
        for chain in INPUT OUTPUT; do
            for icmp_type in $SSH_ONLY_ICMPV6_TYPES; do
                ensure_ssh_only_rule "$bin" "$chain" -p ipv6-icmp --icmpv6-type "$icmp_type" -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
            done
        done
    else
        ensure_ssh_only_rule "$bin" INPUT -p udp --sport 67 --dport 68 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
        ensure_ssh_only_rule "$bin" OUTPUT -p udp --sport 68 --dport 67 -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
    fi
    ensure_ssh_only_rule "$bin" INPUT -p tcp --dport "$SSH_PORT" -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
    ensure_ssh_only_rule "$bin" OUTPUT -p tcp --sport "$SSH_PORT" -m comment --comment "$SSH_ONLY_FIREWALL_TAG" -j ACCEPT || return 1
}

apply_ssh_only_firewall() {
    [[ "${SSH_PORT:-}" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || {
        log_msg "ssh-only action skipped: invalid SSH_PORT=${SSH_PORT:-empty}"
        return 1
    }
    command -v iptables >/dev/null 2>&1 || {
        log_msg "ssh-only action skipped: iptables is unavailable"
        return 1
    }
    if [[ -s /proc/net/if_inet6 ]] && ! command -v ip6tables >/dev/null 2>&1; then
        log_msg "ssh-only action skipped: IPv6 is enabled but ip6tables is unavailable"
        return 1
    fi

    if ! apply_ssh_only_firewall_for_bin iptables || { [[ -s /proc/net/if_inet6 ]] && ! apply_ssh_only_firewall_for_bin ip6tables; }; then
        clear_ssh_only_firewall >/dev/null 2>&1 || true
        log_msg "ssh-only action failed: unable to install managed firewall rules"
        return 1
    fi
    log_msg "ssh-only firewall enabled on TCP port ${SSH_PORT}"
}

if [[ "${1:-}" == "--restore-ssh-only-firewall" ]]; then
    if [[ -r "$CONFIG" ]]; then
        # shellcheck disable=SC1090
        . "$CONFIG"
    fi
    if clear_ssh_only_firewall; then
        log_msg "ssh-only firewall restored"
        exit 0
    fi
    log_msg "ssh-only firewall restore failed"
    exit 1
fi

guard_exit() {
    local rc=$?
    if [[ "$rc" -ne 0 ]]; then
        log_msg "checker exited unexpectedly rc=${rc}; keep timer healthy and retry next run"
        exit 0
    fi
}
trap guard_exit EXIT

normalize_cycle_day() {
    local cycle_day="${1:-1}"
    [[ "$cycle_day" =~ ^[0-9]+$ ]] || cycle_day=1
    cycle_day=$((10#$cycle_day))
    (( cycle_day >= 1 && cycle_day <= 31 )) || cycle_day=1
    printf '%s' "$cycle_day"
}

cycle_date_for_month() {
    local year_month="$1"
    local cycle_day
    local last_day effective_day
    cycle_day=$(normalize_cycle_day "${2:-1}")
    last_day=$(date -d "${year_month}-01 +1 month -1 day" +%d 2>/dev/null || echo 31)
    last_day=$((10#$last_day))
    effective_day="$cycle_day"
    (( effective_day > last_day )) && effective_day="$last_day"
    printf '%s-%02d' "$year_month" "$effective_day"
}

current_cycle_key() {
    local cycle_day="${1:-1}"
    local current_month previous_month current_day reset_date reset_day
    cycle_day=$(normalize_cycle_day "$cycle_day")
    current_month=$(date +%Y-%m)
    reset_date=$(cycle_date_for_month "$current_month" "$cycle_day")
    reset_day="${reset_date##*-}"
    current_day=$(date +%d)
    if (( 10#$current_day >= 10#$reset_day )); then
        printf '%s' "$reset_date"
    else
        previous_month=$(date -d "${current_month}-01 -1 month" +%Y-%m)
        cycle_date_for_month "$previous_month" "$cycle_day"
    fi
}

mode_usage_bytes() {
    local mode="$1"
    local rx="${2:-0}"
    local tx="${3:-0}"
    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    case "$mode" in
        rx) printf '%s' "$rx" ;;
        total) printf '%s' "$(( rx + tx ))" ;;
        max)
            if (( rx > tx )); then printf '%s' "$rx"; else printf '%s' "$tx"; fi
            ;;
        tx|*) printf '%s' "$tx" ;;
    esac
}

scale_offset_bytes() {
    local total="${1:-0}"
    local part="${2:-0}"
    local whole="${3:-0}"
    awk -v total="$total" -v part="$part" -v whole="$whole" 'BEGIN {
        if (total !~ /^[0-9]+$/ || part !~ /^[0-9]+$/ || whole !~ /^[0-9]+$/ || whole <= 0) {
            print 0;
            exit;
        }
        printf "%.0f", total * part / whole;
    }'
}

baseline_direction_offsets() {
    local mode="$1"
    local rx="${2:-0}"
    local tx="${3:-0}"
    local initial="${4:-0}"
    local rx_offset=0 tx_offset=0 current_total

    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
    [[ "$initial" =~ ^[0-9]+$ ]] || initial=0

    case "$mode" in
        rx)
            rx_offset="$initial"
            ;;
        total)
            current_total=$(( rx + tx ))
            if (( current_total > 0 )); then
                rx_offset=$(scale_offset_bytes "$initial" "$rx" "$current_total")
                tx_offset=$(awk -v total="$initial" -v rx_offset="$rx_offset" 'BEGIN {
                    v = total - rx_offset;
                    if (v < 0) v = 0;
                    printf "%.0f", v;
                }')
            else
                rx_offset="$initial"
            fi
            ;;
        max)
            if (( rx >= tx && rx > 0 )); then
                rx_offset="$initial"
                tx_offset=$(scale_offset_bytes "$initial" "$tx" "$rx")
            elif (( tx > 0 )); then
                tx_offset="$initial"
                rx_offset=$(scale_offset_bytes "$initial" "$rx" "$tx")
            else
                rx_offset="$initial"
                tx_offset="$initial"
            fi
            ;;
        tx|*)
            tx_offset="$initial"
            ;;
    esac

    printf '%s\n%s\n' "$rx_offset" "$tx_offset"
}

ensure_direction_offsets() {
    local legacy_offset offset_stats
    if [[ "${OFFSET_RX_BYTES:-}" =~ ^[0-9]+$ && "${OFFSET_TX_BYTES:-}" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    legacy_offset="${OFFSET_BYTES:-${LAST_USAGE:-0}}"
    [[ "$legacy_offset" =~ ^[0-9]+$ ]] || legacy_offset=0
    mapfile -t offset_stats < <(baseline_direction_offsets "$MODE" "${BASE_RX:-0}" "${BASE_TX:-0}" "$legacy_offset")
    OFFSET_RX_BYTES="${offset_stats[0]:-0}"
    OFFSET_TX_BYTES="${offset_stats[1]:-0}"
    OFFSET_BYTES=$(mode_usage_bytes "$MODE" "$OFFSET_RX_BYTES" "$OFFSET_TX_BYTES")
    log_msg "migrated legacy scalar offset on ${IFACE}, mode=${MODE}, offset_rx=${OFFSET_RX_BYTES}, offset_tx=${OFFSET_TX_BYTES}"
}

direction_usage_at_last_check() {
    local last_rx="${LAST_RX:-${BASE_RX:-0}}"
    local last_tx="${LAST_TX:-${BASE_TX:-0}}"
    local delta_rx=0 delta_tx=0 usage_rx usage_tx
    [[ "$last_rx" =~ ^[0-9]+$ ]] || last_rx="${BASE_RX:-0}"
    [[ "$last_tx" =~ ^[0-9]+$ ]] || last_tx="${BASE_TX:-0}"
    if [[ "${BASE_RX:-0}" =~ ^[0-9]+$ ]] && (( last_rx >= BASE_RX )); then
        delta_rx=$(( last_rx - BASE_RX ))
    fi
    if [[ "${BASE_TX:-0}" =~ ^[0-9]+$ ]] && (( last_tx >= BASE_TX )); then
        delta_tx=$(( last_tx - BASE_TX ))
    fi
    usage_rx=$(( ${OFFSET_RX_BYTES:-0} + delta_rx ))
    usage_tx=$(( ${OFFSET_TX_BYTES:-0} + delta_tx ))
    printf '%s\n%s\n' "$usage_rx" "$usage_tx"
}

boot_started_after_cycle_start() {
    local cycle_epoch now_epoch uptime_raw uptime_seconds boot_epoch
    cycle_epoch=$(date -d "${CYCLE_KEY} 00:00:00" +%s 2>/dev/null) || return 1
    read -r uptime_raw _ < "$PROC_UPTIME" 2>/dev/null || return 1
    uptime_seconds="${uptime_raw%%.*}"
    [[ "$uptime_seconds" =~ ^[0-9]+$ ]] || return 1
    now_epoch=$(date +%s 2>/dev/null) || return 1
    boot_epoch=$(( now_epoch - uptime_seconds ))
    (( boot_epoch >= cycle_epoch ))
}

save_state() {
    mkdir -p "$STATE_DIR" || exit 1
    chmod 700 "$STATE_DIR" 2>/dev/null || true
    {
        echo "CYCLE_KEY='${CYCLE_KEY:-}'"
        echo "STATE_IFACE='${IFACE:-}'"
        echo "STATE_MODE='${MODE:-tx}'"
        echo "BASE_RX='${BASE_RX:-0}'"
        echo "BASE_TX='${BASE_TX:-0}'"
        echo "OFFSET_RX_BYTES='${OFFSET_RX_BYTES:-0}'"
        echo "OFFSET_TX_BYTES='${OFFSET_TX_BYTES:-0}'"
        echo "OFFSET_BYTES='${OFFSET_BYTES:-0}'"
        echo "WARN_SENT='${WARN_SENT:-0}'"
        echo "TRIPPED='${TRIPPED:-0}'"
        echo "LAST_RX='${CURRENT_RX:-0}'"
        echo "LAST_TX='${CURRENT_TX:-0}'"
        echo "LAST_USAGE='${USAGE_BYTES:-0}'"
        echo "LAST_CHECKED_AT='$(date -Is 2>/dev/null || date)'"
    } > "$STATE_FILE"
    chmod 600 "$STATE_FILE" 2>/dev/null || true
}

[[ -r "$CONFIG" ]] || exit 0
# shellcheck disable=SC1090
. "$CONFIG"

[[ "${ENABLED:-0}" == "1" ]] || exit 0
IFACE="${IFACE:-}"
MODE="${MODE:-tx}"
LIMIT_BYTES="${LIMIT_BYTES:-0}"
CYCLE_DAY="${CYCLE_DAY:-1}"
WARN_PERCENT="${WARN_PERCENT:-90}"
ACTION="${ACTION:-poweroff}"
SSH_PORT="${SSH_PORT:-}"
INITIAL_USED_BYTES="${INITIAL_USED_BYTES:-0}"

[[ -n "$IFACE" && -r "${SYS_CLASS_NET}/${IFACE}/statistics/rx_bytes" && -r "${SYS_CLASS_NET}/${IFACE}/statistics/tx_bytes" ]] || {
    log_msg "interface ${IFACE:-empty} is not readable, skip"
    exit 0
}
[[ "$LIMIT_BYTES" =~ ^[0-9]+$ && "$LIMIT_BYTES" -gt 0 ]] || exit 0
[[ "$WARN_PERCENT" =~ ^[0-9]+$ ]] || WARN_PERCENT=90
(( WARN_PERCENT >= 1 && WARN_PERCENT <= 99 )) || WARN_PERCENT=90

CURRENT_RX=$(cat "${SYS_CLASS_NET}/${IFACE}/statistics/rx_bytes" 2>/dev/null || echo 0)
CURRENT_TX=$(cat "${SYS_CLASS_NET}/${IFACE}/statistics/tx_bytes" 2>/dev/null || echo 0)
[[ "$CURRENT_RX" =~ ^[0-9]+$ ]] || CURRENT_RX=0
[[ "$CURRENT_TX" =~ ^[0-9]+$ ]] || CURRENT_TX=0
CYCLE_NOW=$(current_cycle_key "$CYCLE_DAY")

STATE_EXISTS=0
if [[ -r "$STATE_FILE" ]]; then
    STATE_EXISTS=1
    # shellcheck disable=SC1090
    . "$STATE_FILE"
fi

if [[ "$STATE_EXISTS" -eq 1 ]]; then
    if [[ -n "${STATE_IFACE:-}" && "${STATE_IFACE:-}" != "$IFACE" ]]; then
        log_msg "state interface ${STATE_IFACE} does not match ${IFACE}; reinitialize baseline"
        STATE_EXISTS=0
        CYCLE_KEY=""
    elif [[ -n "${STATE_MODE:-}" && "${STATE_MODE:-}" != "$MODE" ]]; then
        log_msg "state mode ${STATE_MODE} does not match ${MODE}; reinitialize baseline"
        STATE_EXISTS=0
        CYCLE_KEY=""
    fi
fi

if [[ "${CYCLE_KEY:-}" != "$CYCLE_NOW" ]]; then
    if [[ "$ACTION" == "ssh-only" ]] && ! clear_ssh_only_firewall; then
        log_msg "new cycle ${CYCLE_NOW} detected but ssh-only firewall restore failed; will retry"
        exit 0
    fi
    offset_stats=()
    CYCLE_KEY="$CYCLE_NOW"
    BASE_RX="$CURRENT_RX"
    BASE_TX="$CURRENT_TX"
    if [[ "$STATE_EXISTS" -eq 0 ]]; then
        mapfile -t offset_stats < <(baseline_direction_offsets "$MODE" "$CURRENT_RX" "$CURRENT_TX" "${INITIAL_USED_BYTES:-0}")
        OFFSET_RX_BYTES="${offset_stats[0]:-0}"
        OFFSET_TX_BYTES="${offset_stats[1]:-0}"
    else
        OFFSET_RX_BYTES=0
        OFFSET_TX_BYTES=0
    fi
    OFFSET_BYTES=$(mode_usage_bytes "$MODE" "$OFFSET_RX_BYTES" "$OFFSET_TX_BYTES")
    if boot_started_after_cycle_start; then
        if (( CURRENT_RX > OFFSET_RX_BYTES )); then
            OFFSET_RX_BYTES="$CURRENT_RX"
        fi
        if (( CURRENT_TX > OFFSET_TX_BYTES )); then
            OFFSET_TX_BYTES="$CURRENT_TX"
        fi
        OFFSET_BYTES=$(mode_usage_bytes "$MODE" "$OFFSET_RX_BYTES" "$OFFSET_TX_BYTES")
        log_msg "cycle floor applied on ${IFACE}, boot is inside ${CYCLE_KEY}, usage=${OFFSET_BYTES}, rx=${OFFSET_RX_BYTES}, tx=${OFFSET_TX_BYTES}"
    fi
    WARN_SENT=0
    TRIPPED=0
    USAGE_BYTES="$OFFSET_BYTES"
    save_state
    log_msg "new cycle ${CYCLE_KEY}, baseline reset on ${IFACE}, initial used ${OFFSET_BYTES} bytes, offset_rx=${OFFSET_RX_BYTES}, offset_tx=${OFFSET_TX_BYTES}"
    exit 0
fi

BASE_RX="${BASE_RX:-$CURRENT_RX}"
BASE_TX="${BASE_TX:-$CURRENT_TX}"
[[ "$BASE_RX" =~ ^[0-9]+$ ]] || BASE_RX="$CURRENT_RX"
[[ "$BASE_TX" =~ ^[0-9]+$ ]] || BASE_TX="$CURRENT_TX"
WARN_SENT="${WARN_SENT:-0}"
TRIPPED="${TRIPPED:-0}"
ensure_direction_offsets

if (( CURRENT_RX < BASE_RX || CURRENT_TX < BASE_TX )); then
    mapfile -t previous_direction_usage < <(direction_usage_at_last_check)
    OFFSET_RX_BYTES=$(( ${previous_direction_usage[0]:-0} + CURRENT_RX ))
    OFFSET_TX_BYTES=$(( ${previous_direction_usage[1]:-0} + CURRENT_TX ))
    OFFSET_BYTES=$(mode_usage_bytes "$MODE" "$OFFSET_RX_BYTES" "$OFFSET_TX_BYTES")
    BASE_RX="$CURRENT_RX"
    BASE_TX="$CURRENT_TX"
    WARN_SENT=0
    TRIPPED=0
    USAGE_BYTES="$OFFSET_BYTES"
    save_state
    log_msg "counter reset detected on ${IFACE}, baseline reset and preserved current counters, usage=${OFFSET_BYTES}, offset_rx=${OFFSET_RX_BYTES}, offset_tx=${OFFSET_TX_BYTES}"
    exit 0
fi

DELTA_RX=$(( CURRENT_RX - BASE_RX ))
DELTA_TX=$(( CURRENT_TX - BASE_TX ))
USAGE_RX_BYTES=$(( OFFSET_RX_BYTES + DELTA_RX ))
USAGE_TX_BYTES=$(( OFFSET_TX_BYTES + DELTA_TX ))
OFFSET_BYTES=$(mode_usage_bytes "$MODE" "$OFFSET_RX_BYTES" "$OFFSET_TX_BYTES")
USAGE_BYTES=$(mode_usage_bytes "$MODE" "$USAGE_RX_BYTES" "$USAGE_TX_BYTES")

if [[ "$TRIPPED" != "1" ]] && (( USAGE_BYTES * 100 >= LIMIT_BYTES * WARN_PERCENT )) && (( USAGE_BYTES < LIMIT_BYTES )) && [[ "$WARN_SENT" != "1" ]]; then
    WARN_SENT=1
    save_state
    log_msg "warning ${USAGE_BYTES}/${LIMIT_BYTES} bytes (${WARN_PERCENT}%) on ${IFACE}, mode=${MODE}"
    exit 0
fi

if (( USAGE_BYTES >= LIMIT_BYTES )); then
    TRIPPED=1
    save_state
    log_msg "quota reached ${USAGE_BYTES}/${LIMIT_BYTES} bytes on ${IFACE}, mode=${MODE}, action=${ACTION}"
    case "$ACTION" in
        log)
            exit 0
            ;;
        ssh-only)
            if ! apply_ssh_only_firewall; then
                TRIPPED=0
                save_state
                log_msg "ssh-only firewall action failed; will retry on next timer run"
            fi
            ;;
        poweroff|*)
            sync
            if systemctl poweroff >/dev/null 2>&1 || poweroff >/dev/null 2>&1 || shutdown -h now >/dev/null 2>&1; then
                log_msg "poweroff command accepted"
            else
                TRIPPED=0
                save_state
                log_msg "poweroff command failed; will retry on next timer run"
            fi
            ;;
    esac
fi

save_state
exit 0
GUARD_SCRIPT
    write_rc=$?
    if (( write_rc != 0 )); then
        traffic_guard_mark_checker_install_failure "io" "$(localized_text "无法写入临时检查器文件" "Unable to write to temporary checker file" "Невозможно записать во временный файл проверки")" "$tmp_checker"
        rm -f "$tmp_checker" 2>/dev/null || true
        return 1
    fi
    if ! traffic_guard_normalize_generated_checker "$tmp_checker"; then
        traffic_guard_mark_checker_install_failure "generated-content" "$(localized_text "无法规范化检查器换行或文件头" "Unable to normalize checker newlines or file headers" "Невозможно нормализовать новую строку или заголовки файлов проверки.")" "$tmp_checker"
        return 1
    fi
    IFS= read -r first_line < "$tmp_checker" || first_line=""
    if [[ "${first_line%$'\r'}" != "#!/usr/bin/env bash" ]]; then
        traffic_guard_mark_checker_install_failure "generated-content" "$(localized_text "首行必须是 #!/usr/bin/env bash" "The first line must be #!/usr/bin/env bash" "Первая строка должна быть #!/usr/bin/env bash.")" "$tmp_checker"
        return 1
    fi
    if LC_ALL=C grep -q $'\r' "$tmp_checker"; then
        traffic_guard_mark_checker_install_failure "generated-content" "$(localized_text "检测到 CRLF/回车字符" "CRLF/carriage return character detected" "Обнаружен символ CRLF/возврата каретки")" "$tmp_checker"
        return 1
    fi
    if ! bash -n "$tmp_checker"; then
        traffic_guard_mark_checker_install_failure "generated-content" "$(localized_text "Bash 语法检查未通过" "Bash syntax check failed" "Проверка синтаксиса Bash не удалась")" "$tmp_checker"
        return 1
    fi
    if ! chmod 700 "$tmp_checker"; then
        traffic_guard_mark_checker_install_failure "io" "$(localized_text "权限设置失败：无法 chmod 700" "Permissions setup failed: Unable to chmod 700" "Не удалось настроить разрешения: невозможно выполнить chmod 700.")" "$tmp_checker"
        return 1
    fi
    if ! mv -f "$tmp_checker" "$TRAFFIC_GUARD_CHECKER"; then
        traffic_guard_mark_checker_install_failure "io" "$(localized_text "无法替换 ${TRAFFIC_GUARD_CHECKER}" "Unable to replace ${TRAFFIC_GUARD_CHECKER}" "Невозможно заменить ${TRAFFIC_GUARD_CHECKER}.")" "$tmp_checker"
        return 1
    fi
    traffic_guard_admin_log "checker installed: ${TRAFFIC_GUARD_CHECKER}"
}

install_traffic_guard_checker() {
    local attempt
    for attempt in 1 2; do
        TRAFFIC_GUARD_CHECKER_INSTALL_FAILURE_KIND=""
        TRAFFIC_GUARD_CHECKER_INSTALL_FAILURE_FILE=""
        if traffic_guard_install_checker_once; then
            return 0
        fi
        if [[ "$attempt" == "1" ]] && traffic_guard_checker_install_failure_is_generated; then
            echo -e "$(localized_text "${YELLOW}⚠️ 检查器生成内容异常，正在安全重装一次...${PLAIN}" "${YELLOW}⚠️ The content generated by the checker is abnormal, reinstalling safely...${PLAIN}" "${YELLOW}⚠️ Содержимое, сгенерированное программой проверки, является ненормальным, безопасная переустановка...${PLAIN}")"
            traffic_guard_admin_log "retry checker install once after generated content validation failure"
            continue
        fi
        return 1
    done
    return 1
}

reset_traffic_guard_failed_state() {
    systemctl reset-failed vps-traffic-guard.service vps-traffic-guard.timer >/dev/null 2>&1 || true
}

traffic_guard_state_epoch() {
    local checked_at
    checked_at=$(traffic_guard_state_last_checked_at 2>/dev/null) || { echo 0; return 0; }
    date -d "$checked_at" +%s 2>/dev/null || echo 0
}

traffic_guard_print_timer_failure_context() {
    echo -e "$(localized_text "${YELLOW}▶ Traffic Guard 检查器/Timer 诊断上下文${PLAIN}" "${YELLOW}▶ Traffic Guard Inspector/Timer Diagnostic Context${PLAIN}" "${YELLOW}▶ Контекст диагностики инспектора трафика/таймера${PLAIN}")"
    echo -e "checker : ${TRAFFIC_GUARD_CHECKER}"
    ls -l "$TRAFFIC_GUARD_CHECKER" 2>/dev/null || true
    echo -e "config  : ${TRAFFIC_GUARD_CONFIG}"
    ls -l "$TRAFFIC_GUARD_CONFIG" 2>/dev/null || true
    echo -e "state   : ${TRAFFIC_GUARD_STATE_DIR}/state"
    ls -l "${TRAFFIC_GUARD_STATE_DIR}/state" 2>/dev/null || true
    echo -e "${YELLOW}▶ systemd timer:${PLAIN}"
    systemctl status vps-traffic-guard.timer --no-pager -l 2>/dev/null || true
    systemctl list-timers --all vps-traffic-guard.timer --no-pager 2>/dev/null || true
    echo -e "${YELLOW}▶ systemd service:${PLAIN}"
    systemctl status vps-traffic-guard.service --no-pager -l 2>/dev/null || true
    echo -e "$(localized_text "${YELLOW}▶ 最近 journal:${PLAIN}" "${YELLOW}▶ Recent journal:${PLAIN}" "${YELLOW}▶ Последний журнал:${PLAIN}")"
    journalctl -u vps-traffic-guard.service -u vps-traffic-guard.timer -n 80 --no-pager 2>/dev/null || true
    echo -e "$(localized_text "${YELLOW}▶ 最近脚本日志:${PLAIN}" "${YELLOW}▶ Recent script log:${PLAIN}" "${YELLOW}▶ Журнал последних сценариев:${PLAIN}")"
    traffic_guard_recent_log_summary 20
}

traffic_guard_install_checker_or_report() {
    install_traffic_guard_checker && return 0
    echo -e "$(localized_text "${RED}❌ 安装检查脚本失败。下面是可直接排查的上下文：${PLAIN}" "${RED}❌ The installation check script failed. The following is the context that can be directly investigated:${PLAIN}" "${RED}❌ Не удалось выполнить сценарий проверки установки. Ниже приводится контекст, который можно непосредственно исследовать:.${PLAIN}")"
    traffic_guard_print_timer_failure_context
    return 1
}

traffic_guard_run_checker_once() {
    local before_epoch after_epoch age rc=0 runner
    before_epoch=$(traffic_guard_state_epoch)
    runner="direct"

    if [[ ! -x "$TRAFFIC_GUARD_CHECKER" ]]; then
        echo -e "$(localized_text "${RED}❌ 检查器不存在或不可执行：${TRAFFIC_GUARD_CHECKER}${PLAIN}" "${RED}❌ Checker does not exist or is not executable: ${TRAFFIC_GUARD_CHECKER}${PLAIN}" "${RED}❌ Программа проверки не существует или не является исполняемой: ${TRAFFIC_GUARD_CHECKER}${PLAIN}")"
        return 1
    fi

    reset_traffic_guard_failed_state
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files vps-traffic-guard.service --no-legend >/dev/null 2>&1; then
        runner="systemd"
        systemctl start vps-traffic-guard.service >/dev/null 2>&1 || rc=$?
    else
        /usr/bin/env bash "$TRAFFIC_GUARD_CHECKER" >/dev/null 2>&1 || rc=$?
    fi
    reset_traffic_guard_failed_state

    if (( rc != 0 )); then
        echo -e "$(localized_text "${RED}❌ 已尝试通过 ${runner} 运行检查器，但执行失败 rc=${rc}。${PLAIN}" "${RED}❌ An attempt was made to run the checker with ${runner}, but execution failed with rc=${rc}.${PLAIN}" "${RED}❌ Была предпринята попытка запустить программу проверки с помощью ${runner}, но выполнение не удалось с rc=${rc}.${PLAIN}")"
        return 1
    fi

    after_epoch=$(traffic_guard_state_epoch)
    age=$(traffic_guard_state_age_seconds 2>/dev/null || echo "")
    if [[ "$age" =~ ^[0-9]+$ && "$age" -le 120 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 检查器已立即运行，状态文件已刷新。${PLAIN}" "${GREEN}✅ The checker has been run immediately and the status file has been refreshed.${PLAIN}" "${GREEN}✅ Проверка была запущена немедленно, и файл состояния был обновлен.${PLAIN}")"
        return 0
    fi
    if [[ "$after_epoch" =~ ^[0-9]+$ && "$before_epoch" =~ ^[0-9]+$ && "$after_epoch" -gt "$before_epoch" ]]; then
        echo -e "$(localized_text "${GREEN}✅ 检查器已立即运行，状态时间已推进。${PLAIN}" "${GREEN}✅ The checker has been run immediately and the status time has been advanced.${PLAIN}" "${GREEN}. Проверка была запущена немедленно, а время статуса было увеличено.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${RED}❌ 检查器执行结束但状态文件没有刷新。${PLAIN}" "${RED}❌ Checker execution ended but the status file was not refreshed.${PLAIN}" "${RED}❌ Выполнение средства проверки завершилось, но файл состояния не был обновлен.${PLAIN}")"
    return 1
}

install_traffic_guard_units() {
    local interval="$1"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=60
    (( interval >= 30 )) || interval=30

    cat > /etc/systemd/system/vps-traffic-guard.service <<EOF
[Unit]
Description=VPS-Optimize traffic quota guard
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/env bash ${TRAFFIC_GUARD_CHECKER}
TimeoutStartSec=30
StandardOutput=journal
StandardError=journal
EOF

    cat > /etc/systemd/system/vps-traffic-guard.timer <<EOF
[Unit]
Description=Run VPS-Optimize traffic quota guard periodically

[Timer]
OnBootSec=1min
OnActiveSec=${interval}s
OnUnitActiveSec=${interval}s
AccuracySec=10s
Persistent=true
Unit=vps-traffic-guard.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || return 1
    reset_traffic_guard_failed_state
    systemctl enable --now vps-traffic-guard.timer >/dev/null 2>&1 || return 1
    reset_traffic_guard_failed_state
}

write_traffic_guard_config() {
    local iface="$1"
    local mode="$2"
    local limit_gb="$3"
    local limit_bytes="$4"
    local cycle_day="$5"
    local warn_percent="$6"
    local action="$7"
    local initial_used_gb="$8"
    local initial_used_bytes="$9"
    local interval="${10}"
    local ssh_port="${11:-}"

    mkdir -p "$(dirname "$TRAFFIC_GUARD_CONFIG")" || return 1
    cat > "$TRAFFIC_GUARD_CONFIG" <<EOF
# VPS-Optimize traffic quota guard
# Generated: $(date -Is 2>/dev/null || date)
ENABLED=1
IFACE='${iface}'
MODE='${mode}'
LIMIT_GB='${limit_gb}'
LIMIT_BYTES='${limit_bytes}'
CYCLE_DAY='${cycle_day}'
WARN_PERCENT='${warn_percent}'
ACTION='${action}'
SSH_PORT='${ssh_port}'
INITIAL_USED_GB='${initial_used_gb}'
INITIAL_USED_BYTES='${initial_used_bytes}'
CHECK_INTERVAL='${interval}'
EOF
    chmod 600 "$TRAFFIC_GUARD_CONFIG" 2>/dev/null || true
}

load_traffic_guard_config() {
    [[ -r "$TRAFFIC_GUARD_CONFIG" ]] || return 1
    # shellcheck disable=SC1090
    . "$TRAFFIC_GUARD_CONFIG"
}

traffic_guard_restore_ssh_only_firewall_from_config() {
    local config_path="${1:-$TRAFFIC_GUARD_CONFIG}"
    local configured_action
    [[ -r "$config_path" ]] || return 0
    configured_action=$(
        unset ACTION
        # shellcheck disable=SC1090
        . "$config_path" || exit 1
        printf '%s' "${ACTION:-poweroff}"
    ) || return 1
    [[ "$configured_action" == "ssh-only" ]] || return 0
    [[ -x "$TRAFFIC_GUARD_CHECKER" ]] || return 1
    VPSO_TRAFFIC_GUARD_CONFIG="$config_path" \
    VPSO_TRAFFIC_GUARD_STATE_DIR="$TRAFFIC_GUARD_STATE_DIR" \
    VPSO_TRAFFIC_GUARD_LOG="$TRAFFIC_GUARD_LOG" \
        /usr/bin/env bash "$TRAFFIC_GUARD_CHECKER" --restore-ssh-only-firewall
}

traffic_guard_restore_ssh_only_firewall() {
    traffic_guard_restore_ssh_only_firewall_from_config "$TRAFFIC_GUARD_CONFIG"
}

traffic_guard_usage_from_state() {
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    [[ -r "$state_file" ]] || return 1
    # shellcheck disable=SC1090
    . "$state_file"
    printf '%s' "${LAST_USAGE:-0}"
}

traffic_guard_direction_usage_from_state() {
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    local base_rx base_tx last_rx last_tx offset_rx offset_tx delta_rx=0 delta_tx=0
    [[ -r "$state_file" ]] || return 1
    # shellcheck disable=SC1090
    . "$state_file"
    base_rx="${BASE_RX:-0}"
    base_tx="${BASE_TX:-0}"
    last_rx="${LAST_RX:-$base_rx}"
    last_tx="${LAST_TX:-$base_tx}"
    offset_rx="${OFFSET_RX_BYTES:-}"
    offset_tx="${OFFSET_TX_BYTES:-}"
    [[ "$base_rx" =~ ^[0-9]+$ && "$base_tx" =~ ^[0-9]+$ ]] || return 1
    [[ "$last_rx" =~ ^[0-9]+$ && "$last_tx" =~ ^[0-9]+$ ]] || return 1
    [[ "$offset_rx" =~ ^[0-9]+$ && "$offset_tx" =~ ^[0-9]+$ ]] || return 1
    if (( last_rx >= base_rx )); then
        delta_rx=$(( last_rx - base_rx ))
    fi
    if (( last_tx >= base_tx )); then
        delta_tx=$(( last_tx - base_tx ))
    fi
    printf '%s %s\n' "$(( offset_rx + delta_rx ))" "$(( offset_tx + delta_tx ))"
}

traffic_guard_state_last_checked_at() {
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    [[ -r "$state_file" ]] || return 1
    grep -m1 '^LAST_CHECKED_AT=' "$state_file" | cut -d= -f2- | sed "s/^'//;s/'$//"
}

traffic_guard_state_age_seconds() {
    local checked_at checked_epoch now_epoch
    checked_at=$(traffic_guard_state_last_checked_at) || return 1
    checked_epoch=$(date -d "$checked_at" +%s 2>/dev/null) || return 1
    now_epoch=$(date +%s 2>/dev/null) || return 1
    (( now_epoch >= checked_epoch )) || return 1
    printf '%s' "$(( now_epoch - checked_epoch ))"
}

traffic_guard_stale_threshold_seconds() {
    local interval="${CHECK_INTERVAL:-60}"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=60
    (( interval >= 30 )) || interval=60
    local threshold=$(( interval * 3 ))
    (( threshold < 300 )) && threshold=300
    printf '%s' "$threshold"
}

traffic_guard_live_usage_from_state() {
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    local current_stats current_rx current_tx base_rx base_tx offset_rx offset_tx
    local last_rx last_tx delta_rx=0 delta_tx=0 usage_rx usage_tx usage mode cycle_now
    mode="${MODE:-tx}"
    traffic_guard_valid_iface "${IFACE:-}" || return 1
    mapfile -t current_stats < <(traffic_guard_read_stats "$IFACE")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    [[ "$current_rx" =~ ^[0-9]+$ ]] || current_rx=0
    [[ "$current_tx" =~ ^[0-9]+$ ]] || current_tx=0

    if [[ ! -r "$state_file" ]]; then
        usage=$(traffic_guard_mode_usage_bytes "$mode" "$current_rx" "$current_tx")
        printf '%s %s %s\n' "$usage" "$current_rx" "$current_tx"
        return 0
    fi

    # shellcheck disable=SC1090
    . "$state_file"
    cycle_now=$(traffic_guard_current_cycle_key "${CYCLE_DAY:-1}")
    if [[ "${STATE_IFACE:-$IFACE}" != "$IFACE" || "${STATE_MODE:-$mode}" != "$mode" ]]; then
        usage=$(traffic_guard_mode_usage_bytes "$mode" "$current_rx" "$current_tx")
        printf '%s %s %s\n' "$usage" "$current_rx" "$current_tx"
        return 0
    fi
    if [[ "${CYCLE_KEY:-}" != "$cycle_now" ]]; then
        if traffic_guard_boot_started_after_cycle_start "$cycle_now"; then
            usage=$(traffic_guard_mode_usage_bytes "$mode" "$current_rx" "$current_tx")
            printf '%s %s %s\n' "$usage" "$current_rx" "$current_tx"
        else
            printf '0 0 0\n'
        fi
        return 0
    fi

    base_rx="${BASE_RX:-$current_rx}"
    base_tx="${BASE_TX:-$current_tx}"
    offset_rx="${OFFSET_RX_BYTES:-}"
    offset_tx="${OFFSET_TX_BYTES:-}"
    if [[ ! "$offset_rx" =~ ^[0-9]+$ || ! "$offset_tx" =~ ^[0-9]+$ ]]; then
        local legacy_offset offset_stats
        legacy_offset="${OFFSET_BYTES:-${LAST_USAGE:-0}}"
        [[ "$legacy_offset" =~ ^[0-9]+$ ]] || legacy_offset=0
        mapfile -t offset_stats < <(traffic_guard_baseline_direction_offsets "$mode" "$base_rx" "$base_tx" "$legacy_offset")
        offset_rx="${offset_stats[0]:-0}"
        offset_tx="${offset_stats[1]:-0}"
    fi

    if [[ "$base_rx" =~ ^[0-9]+$ && "$base_tx" =~ ^[0-9]+$ ]] && (( current_rx >= base_rx && current_tx >= base_tx )); then
        delta_rx=$(( current_rx - base_rx ))
        delta_tx=$(( current_tx - base_tx ))
        usage_rx=$(( offset_rx + delta_rx ))
        usage_tx=$(( offset_tx + delta_tx ))
    else
        last_rx="${LAST_RX:-$base_rx}"
        last_tx="${LAST_TX:-$base_tx}"
        [[ "$last_rx" =~ ^[0-9]+$ ]] || last_rx="$base_rx"
        [[ "$last_tx" =~ ^[0-9]+$ ]] || last_tx="$base_tx"
        if [[ "$base_rx" =~ ^[0-9]+$ && "$last_rx" =~ ^[0-9]+$ ]] && (( last_rx >= base_rx )); then
            delta_rx=$(( last_rx - base_rx ))
        fi
        if [[ "$base_tx" =~ ^[0-9]+$ && "$last_tx" =~ ^[0-9]+$ ]] && (( last_tx >= base_tx )); then
            delta_tx=$(( last_tx - base_tx ))
        fi
        usage_rx=$(( offset_rx + delta_rx + current_rx ))
        usage_tx=$(( offset_tx + delta_tx + current_tx ))
    fi

    usage=$(traffic_guard_mode_usage_bytes "$mode" "$usage_rx" "$usage_tx")
    printf '%s %s %s\n' "$usage" "$usage_rx" "$usage_tx"
}

traffic_guard_recent_log_summary() {
    local lines="${1:-5}"

    [[ "$lines" =~ ^[0-9]+$ ]] || lines=5
    (( lines > 0 )) || lines=5

    if [[ ! -r "$TRAFFIC_GUARD_LOG" ]]; then
        echo "$(localized_text "暂无日志" "No logs yet" "Журналов пока нет")"
        return 0
    fi

    if declare -F redact_sensitive_output >/dev/null; then
        tail -n "$lines" "$TRAFFIC_GUARD_LOG" 2>/dev/null | redact_sensitive_output
    else
        tail -n "$lines" "$TRAFFIC_GUARD_LOG" 2>/dev/null
    fi
}

print_traffic_guard_diagnostic_summary() {
    local log_lines="${1:-5}"
    local show_unconfigured="${2:-yes}"
    local state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    local timer_active timer_enabled has_config has_state has_log usage source_usage live_rx live_tx
    local limit pct mode_label state_age stale_threshold last_checked state_status config_status log_status
    local ENABLED IFACE MODE LIMIT_GB LIMIT_BYTES CYCLE_DAY WARN_PERCENT ACTION INITIAL_USED_GB INITIAL_USED_BYTES CHECK_INTERVAL

    [[ "$log_lines" =~ ^[0-9]+$ ]] || log_lines=5
    (( log_lines >= 0 )) || log_lines=5

    timer_active=$(systemctl is-active vps-traffic-guard.timer 2>/dev/null || true)
    timer_enabled=$(systemctl is-enabled vps-traffic-guard.timer 2>/dev/null || true)
    timer_active=${timer_active:-inactive}
    timer_enabled=${timer_enabled:-disabled}
    [[ -r "$TRAFFIC_GUARD_CONFIG" ]] && has_config="yes" || has_config="no"
    [[ -r "$state_file" ]] && has_state="yes" || has_state="no"
    [[ -r "$TRAFFIC_GUARD_LOG" ]] && has_log="yes" || has_log="no"

    if [[ "$has_config" == "no" && "$has_state" == "no" && "$has_log" == "no" && "$timer_active" != "active" && "$timer_enabled" == "disabled" ]]; then
        [[ "$show_unconfigured" == "yes" ]] && echo "$(localized_text "流量限额保护摘要：未配置" "Traffic quota protection: not configured" "Защита лимита трафика: не настроена")"
        return 0
    fi

    echo "$(localized_text "流量限额保护摘要：" "Traffic quota protection:" "Защита лимита трафика:")"
    echo "- timer: vps-traffic-guard.timer active=${timer_active}; enabled=${timer_enabled}"
    config_status="$(localized_text "不可读或不存在" "Unreadable or does not exist" "Нечитабельно или не существует")"
    state_status="$(localized_text "不可读或不存在" "Unreadable or does not exist" "Нечитабельно или не существует")"
    log_status="$(localized_text "不可读或不存在" "Unreadable or does not exist" "Нечитабельно или не существует")"
    [[ "$has_config" == "yes" ]] && config_status="$(localized_text "存在" "exist" "существовать")"
    [[ "$has_state" == "yes" ]] && state_status="$(localized_text "存在" "exist" "существовать")"
    [[ "$has_log" == "yes" ]] && log_status="$(localized_text "存在" "exist" "существовать")"
    echo "$(localized_text "- 配置文件: ${TRAFFIC_GUARD_CONFIG} (${config_status})" "- Configuration file: ${TRAFFIC_GUARD_CONFIG} (${config_status})" "- Файл конфигурации: ${TRAFFIC_GUARD_CONFIG} (${config_status})")"
    echo "$(localized_text "- 状态文件: ${state_file} (${state_status})" "- Status file: ${state_file} (${state_status})" "- Файл состояния: ${state_file} (${state_status})")"
    echo "$(localized_text "- 日志文件: ${TRAFFIC_GUARD_LOG} (${log_status})" "- Log file: ${TRAFFIC_GUARD_LOG} (${log_status})" "- Файл журнала: ${TRAFFIC_GUARD_LOG} (${log_status})")"

    if [[ "$has_config" != "yes" ]]; then
        echo "$(localized_text "- 当前配置: 未配置或不可读" "- Current configuration: Not configured or unreadable" "- Текущая конфигурация: не настроена или нечитаема.")"
    else
        # shellcheck disable=SC1090
        . "$TRAFFIC_GUARD_CONFIG"
        limit="${LIMIT_BYTES:-0}"
        if read -r usage live_rx live_tx < <(traffic_guard_live_usage_from_state 2>/dev/null); then
            source_usage="$(localized_text "实时估算" "Real-time estimation" "Оценка в реальном времени")"
        else
            usage=$(traffic_guard_usage_from_state 2>/dev/null || echo 0)
            live_rx=""
            live_tx=""
            source_usage="$(localized_text "上次状态" "last status" "последний статус")"
        fi
        [[ "$usage" =~ ^[0-9]+$ ]] || usage=0
        [[ "$limit" =~ ^[0-9]+$ ]] || limit=0
        if (( limit > 0 )); then
            pct=$(awk -v u="$usage" -v l="$limit" 'BEGIN { printf "%.2f", (u/l)*100 }')
            mode_label=$(traffic_guard_mode_label "${MODE:-tx}")
            echo "$(localized_text "- 当前配置: ENABLED=${ENABLED:-0}; 模式=${mode_label}; 动作=$(traffic_guard_action_label "${ACTION:-poweroff}"); 检查间隔=${CHECK_INTERVAL:-60}s" "- Current configuration: ENABLED=${ENABLED:-0}; mode=${mode_label}; action=$(traffic_guard_action_label \"${ACTION:-poweroff}\"); check interval=${CHECK_INTERVAL:-60}s" "- Текущая конфигурация: ENABLED=${ENABLED:-0}; режим = ${mode_label}; действие = $(traffic_guard_action_label \"${ACTION:-poweroff}\"); интервал проверки = ${CHECK_INTERVAL:-60}s")"
            echo "- ${source_usage}: $(traffic_guard_human_bytes "$usage") / $(traffic_guard_human_bytes "$limit") (${pct}%)"
        else
            echo "$(localized_text "- 当前配置: ENABLED=${ENABLED:-0}; 模式=$(traffic_guard_mode_label "${MODE:-tx}"); 阈值未设置或无效" "- Current configuration: ENABLED=${ENABLED:-0}; Mode=$(traffic_guard_mode_label \"${MODE:-tx}\"); Threshold not set or invalid" "- Текущая конфигурация: ENABLED=${ENABLED:-0}; Режим = $(traffic_guard_mode_label \"${MODE:-tx}\"); Порог не установлен или недействителен.")"
        fi
        if [[ "$live_rx" =~ ^[0-9]+$ && "$live_tx" =~ ^[0-9]+$ ]]; then
            echo "$(localized_text "- 方向估算: RX $(traffic_guard_human_bytes "$live_rx") / TX $(traffic_guard_human_bytes "$live_tx")" "- Direction estimation: RX $(traffic_guard_human_bytes \"$live_rx\") / TX $(traffic_guard_human_bytes \"$live_tx\")" "- Оценка направления: RX $(traffic_guard_human_bytes \"$live_rx\") / TX $(traffic_guard_human_bytes \"$live_tx\").")"
        fi
    fi

    if [[ "$has_state" == "yes" ]]; then
        last_checked=$(traffic_guard_state_last_checked_at 2>/dev/null || echo "$(localized_text "未知" "unknown" "неизвестно")")
        state_age=$(traffic_guard_state_age_seconds 2>/dev/null || echo "")
        stale_threshold=$(traffic_guard_stale_threshold_seconds)
        if [[ "$state_age" =~ ^[0-9]+$ ]]; then
            echo "$(localized_text "- 最近检查: ${last_checked} (${state_age}s 前; 超时阈值 ${stale_threshold}s)" "- Last checked: ${last_checked} (${state_age}s ago; timeout threshold ${stale_threshold}s)" "- Последняя проверка: ${last_checked} (${state_age}s назад; порог тайм-аута ${stale_threshold}s)")"
            if (( state_age > stale_threshold )); then
                if [[ "$timer_active" == "active" ]]; then
                    echo "$(localized_text "- 异常提示: 最近检查超时，timer active 但状态文件已超过 ${state_age}s 未刷新，请查看日志或使用菜单 [10] -> [5] -> [6] 修复 timer" "- Exception prompt: The latest check timed out, timer active but the status file has exceeded ${state_age}s and has not been refreshed, please check the log or use the menu [10] -> [5] -> [6] to repair the timer" "- Подсказка об исключении: время последней проверки истекло, таймер активен, но файл состояния превысил ${state_age} и не был обновлен. Проверьте журнал или воспользуйтесь меню [10] -> [5] -> [6] для восстановления таймера.")"
                else
                    echo "$(localized_text "- 异常提示: 最近检查超时，状态文件已超过 ${state_age}s 未刷新，timer 当前为 ${timer_active}" "- Exception prompt: The latest check has timed out, the status file has exceeded ${state_age}s and has not been refreshed, and the timer is currently ${timer_active}" "- Подсказка об исключении: время последней проверки истекло, файл состояния превысил ${state_age} и не был обновлен, а таймер в настоящее время равен ${timer_active}.")"
                fi
            fi
        else
            echo "$(localized_text "- 最近检查: ${last_checked}" "- Last checked: ${last_checked}" "- Последняя проверка: ${last_checked}.")"
        fi
    else
        echo "$(localized_text "- 最近检查: 状态文件尚未生成" "- Last checked: status file has not been generated yet" "- Последняя проверка: файл состояния еще не создан.")"
    fi

    if (( log_lines > 0 )); then
        echo "$(localized_text "- 最近 vps-traffic-guard 日志:" "- Recent vps-traffic-guard logs:" "- Последние журналы vps-traffic-guard:")"
        traffic_guard_recent_log_summary "$log_lines" | sed 's/^/  /'
    fi
}

show_traffic_guard_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "网络/内核优化 > 流量限额保护" "Network/Kernel Optimization > Traffic quota protection" "Оптимизация сети/ядра > Защита лимита трафика")"
    echo -e "$(localized_text "${BOLD}🧯 流量限额保护状态${PLAIN}" "${BOLD}🧯 Traffic quota protection status${PLAIN}" "${BOLD}🧯 Состояние защиты лимита трафика${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    if ! load_traffic_guard_config; then
        echo -e "$(localized_text "${YELLOW}尚未配置流量限额保护。${PLAIN}" "${YELLOW}Traffic quota protection is not configured.${PLAIN}" "${YELLOW}Защита лимита трафика не настроена.${PLAIN}")"
        echo -e "$(localized_text "${BLUE}选择 [1] 设置流量阈值和达到阈值后的保护动作。${PLAIN}" "${BLUE}Select [1] to set the quota and the action taken when it is reached.${PLAIN}" "${BLUE}Выберите [1], чтобы задать лимит и действие при его достижении.${PLAIN}")"
        return 0
    fi

    local timer_state service_state usage limit pct cycle_key state_file current_stats current_rx current_tx
    local live_usage live_rx live_tx state_usage state_age stale_threshold last_checked
    timer_state=$(systemctl is-active vps-traffic-guard.timer 2>/dev/null || echo "inactive")
    service_state=$(systemctl is-enabled vps-traffic-guard.timer 2>/dev/null || echo "disabled")
    state_usage=$(traffic_guard_usage_from_state 2>/dev/null || echo 0)
    if read -r live_usage live_rx live_tx < <(traffic_guard_live_usage_from_state 2>/dev/null); then
        usage="$live_usage"
    else
        usage="$state_usage"
        live_rx=""
        live_tx=""
    fi
    limit="${LIMIT_BYTES:-0}"
    if [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]]; then
        pct=$(awk -v u="$usage" -v l="$limit" 'BEGIN { printf "%.2f", (u/l)*100 }')
    else
        pct="0.00"
    fi
    cycle_key=$(traffic_guard_current_cycle_key "${CYCLE_DAY:-1}")

    echo -e "$(localized_text "开关状态 : ${GREEN}${ENABLED:-0}${PLAIN}  timer: ${timer_state}/${service_state}" "Switch status: ${GREEN}${ENABLED:-0}${PLAIN} timer: ${timer_state}/${service_state}" "Статус переключателя: ${GREEN}${ENABLED:-0}${PLAIN}, таймер: ${timer_state}/${service_state}")"
    echo -e "$(localized_text "监控网卡 : ${CYAN}${IFACE:-未知}${PLAIN}" "Monitored interface: ${CYAN}${IFACE:-未知}${PLAIN}" "Контролируемый сетевой интерфейс: ${CYAN}${IFACE:-未知}${PLAIN}")"
    echo -e "$(localized_text "计费模式 : ${CYAN}$(traffic_guard_mode_label "${MODE:-tx}")${PLAIN}" "Billing mode: ${CYAN}$(traffic_guard_mode_label \"${MODE:-tx}\")${PLAIN}" "Режим выставления счетов: ${CYAN}$(traffic_guard_mode_label \"${MODE:-tx}\")${PLAIN}")"
    echo -e "$(localized_text "本周期   : ${CYAN}${cycle_key}${PLAIN} 起，配置为每月 ${CYCLE_DAY:-1} 日重置（短月份按最后一天）" "This cycle: Starting from ${CYAN}${cycle_key}${PLAIN}, it is configured to be reset on ${CYCLE_DAY:-1} every month (short months are reset on the last day)" "Этот цикл: Начиная с ${CYAN}${cycle_key}${PLAIN}, он настроен на сброс в ${CYCLE_DAY:-1} каждый месяц (короткие месяцы сбрасываются в последний день).")"
    echo -e "$(localized_text "阈值     : ${YELLOW}${LIMIT_GB:-未知}GB${PLAIN} ($(traffic_guard_human_bytes "$limit"))" "Threshold: ${YELLOW}${LIMIT_GB:-未知}GB${PLAIN} ($(traffic_guard_human_bytes \"$limit\"))" "Порог: ${YELLOW}${LIMIT_GB:-未知}GB${PLAIN} ($(traffic_guard_human_bytes \"$limit\"))")"
    echo -e "$(localized_text "达量动作 : ${RED}$(traffic_guard_action_label "${ACTION:-poweroff}")${PLAIN}" "Limit action: ${RED}$(traffic_guard_action_label \"${ACTION:-poweroff}\")${PLAIN}" "Действие при достижении лимита: ${RED}$(traffic_guard_action_label \"${ACTION:-poweroff}\")${PLAIN}")"
    if [[ "${ACTION:-}" == "ssh-only" ]]; then
        echo -e "$(localized_text "保留 SSH : ${CYAN}${SSH_PORT:-未知}/tcp${PLAIN}；下个重置周期会自动移除临时封锁规则" "Reserved SSH: ${CYAN}${SSH_PORT:-未知}/tcp${PLAIN}; the temporary blocking rule will be automatically removed in the next reset cycle" "Зарезервировано SSH: ${CYAN}${SSH_PORT:-未知}/tcp${PLAIN}; правило временной блокировки будет автоматически удалено при следующем цикле сброса")"
    fi
    echo -e "$(localized_text "本周期已用 : ${GREEN}$(traffic_guard_human_bytes "$usage")${PLAIN} / ${pct}%（按基线和初始已用实时估算）" "Used this billing cycle: ${GREEN}$(traffic_guard_human_bytes \"$usage\")${PLAIN} / ${pct}% (estimated from the baseline and initial usage)" "Использовано за расчётный период: ${GREEN}$(traffic_guard_human_bytes \"$usage\")${PLAIN} / ${pct}% (оценка по базовому и начальному значениям)")"
    if [[ "$state_usage" =~ ^[0-9]+$ && "$state_usage" != "$usage" ]]; then
        echo -e "$(localized_text "状态记录 : ${YELLOW}$(traffic_guard_human_bytes "$state_usage")${PLAIN}（上次检查写入）" "Status record: ${YELLOW}$(traffic_guard_human_bytes \"$state_usage\")${PLAIN} (last check write)" "Запись состояния: ${YELLOW}$(traffic_guard_human_bytes \"$state_usage\")${PLAIN} (последняя проверка записи)")"
    fi
    if [[ "$live_rx" =~ ^[0-9]+$ && "$live_tx" =~ ^[0-9]+$ ]]; then
        echo -e "$(localized_text "本周期方向 : RX ${CYAN}$(traffic_guard_human_bytes "$live_rx")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes "$live_tx")${PLAIN}（已减基线并包含初始已用）" "Direction of this cycle: RX ${CYAN}$(traffic_guard_human_bytes \"$live_rx\")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes \"$live_tx\")${PLAIN} (baseline reduced and includes initial used)" "Направление этого цикла: RX ${CYAN}$(traffic_guard_human_bytes \"$live_rx\")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes \"$live_tx\")${PLAIN} (базовый уровень уменьшен и включает первоначально использованный)")"
    fi
    echo -e "$(localized_text "预警线   : ${WARN_PERCENT:-90}%  动作: ${ACTION:-poweroff}" "Warning line: ${WARN_PERCENT:-90}% Action: ${ACTION:-poweroff}" "Строка предупреждения: ${WARN_PERCENT:-90}% Действие: ${ACTION:-poweroff}")"
    if traffic_guard_valid_iface "${IFACE:-}"; then
        mapfile -t current_stats < <(traffic_guard_read_stats "$IFACE")
        current_rx="${current_stats[0]:-0}"
        current_tx="${current_stats[1]:-0}"
        echo -e "$(localized_text "网卡原始计数 : RX ${CYAN}$(traffic_guard_human_bytes "$current_rx")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes "$current_tx")${PLAIN}（自开机累计，不等于本周期已用）" "Raw interface counters: RX ${CYAN}$(traffic_guard_human_bytes \"$current_rx\")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes \"$current_tx\")${PLAIN} (since boot; not billing-cycle usage)" "Исходные счётчики интерфейса: RX ${CYAN}$(traffic_guard_human_bytes \"$current_rx\")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes \"$current_tx\")${PLAIN} (с момента загрузки; это не расход за расчётный период)")"
        echo -e "$(localized_text "${BLUE}说明：保护触发只看“本周期已用”；原始计数只用于计算差量，开机久时可能明显更大。${PLAIN}" "${BLUE}The protection threshold uses only the current billing-cycle usage. Raw counters are used only to calculate deltas and may be much larger after a long uptime.${PLAIN}" "${BLUE}Порог защиты учитывает только трафик за текущий расчётный период. Исходные счётчики нужны лишь для расчёта разницы и могут быть значительно больше после длительной работы.${PLAIN}")"
    fi
    echo -e "$(localized_text "配置文件 : ${CYAN}${TRAFFIC_GUARD_CONFIG}${PLAIN}" "Configuration file: ${CYAN}${TRAFFIC_GUARD_CONFIG}${PLAIN}" "Файл конфигурации: ${CYAN}${TRAFFIC_GUARD_CONFIG}${PLAIN}")"
    echo -e "$(localized_text "日志文件 : ${CYAN}${TRAFFIC_GUARD_LOG}${PLAIN}" "Log file: ${CYAN}${TRAFFIC_GUARD_LOG}${PLAIN}" "Файл журнала: ${CYAN}${TRAFFIC_GUARD_LOG}${PLAIN}")"

    state_file="${TRAFFIC_GUARD_STATE_DIR}/state"
    if [[ -r "$state_file" ]]; then
        last_checked=$(traffic_guard_state_last_checked_at 2>/dev/null || echo "$(localized_text "未知" "unknown" "неизвестно")")
        echo -e "$(localized_text "最近检查 : ${CYAN}${last_checked}${PLAIN}" "Last checked: ${CYAN}${last_checked}${PLAIN}" "Последняя проверка: ${CYAN}${last_checked}${PLAIN}")"
        state_age=$(traffic_guard_state_age_seconds 2>/dev/null || echo "")
        stale_threshold=$(traffic_guard_stale_threshold_seconds)
        if [[ "$state_age" =~ ^[0-9]+$ && "$state_age" -gt "$stale_threshold" ]]; then
            echo -e "$(localized_text "${RED}异常提示 : 最近检查已超过 ${state_age}s，timer 显示 active 也不能代表检查器真的在刷新。请用本菜单 [7] 立即同步/验证；如失败再用 [6] 重装 timer。${PLAIN}" "${RED}Exception prompt: The recent check has exceeded ${state_age}s, and the timer showing active does not mean that the checker is really refreshing. Please use this menu [7] to synchronize/verify immediately; if it fails, use [6] to reinstall the timer.${PLAIN}" "${RED}Подсказка об исключении : недавняя проверка превысила значение ${state_age}, и активный таймер не означает, что программа проверки действительно обновляется. Используйте это меню [7] для немедленной синхронизации/проверки; если это не помогло, используйте [6], чтобы переустановить таймер.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "${YELLOW}尚未生成状态文件，timer 首次运行后会自动初始化基线。${PLAIN}" "${YELLOW}Has not generated a status file, and the timer will automatically initialize the baseline after running it for the first time.${PLAIN}" "${YELLOW}не создал файл состояния, и таймер автоматически инициализирует базовые показатели после первого запуска.${PLAIN}")"
    fi
}

sync_traffic_guard_now() {
    load_traffic_guard_config || {
        echo -e "$(localized_text "${YELLOW}尚未配置流量限额保护。${PLAIN}" "${YELLOW}Traffic quota protection is not configured.${PLAIN}" "${YELLOW}Защита лимита трафика не настроена.${PLAIN}")"
        pause_return
        return 1
    }

    if [[ "${ACTION:-poweroff}" == "poweroff" ]]; then
        confirm_danger "$(localized_text "立即运行一次流量保护检查器" "Run a traffic protection checker now" "Запустите проверку защиты трафика прямо сейчас")" \
            "$(localized_text "会立刻读取 ${IFACE:-当前网卡} 流量并刷新 ${TRAFFIC_GUARD_STATE_DIR}/state；如果已经超过阈值，会按当前配置执行 poweroff。" "${IFACE:-当前网卡} traffic will be read immediately and ${TRAFFIC_GUARD_STATE_DIR}/state will be refreshed; if the threshold has been exceeded, poweroff will be performed according to the current configuration." "Трафик ${IFACE:-当前网卡} будет прочитан немедленно, а ${TRAFFIC_GUARD_STATE_DIR}/state будет обновлен; если порог превышен, выключение будет выполнено в соответствии с текущей конфигурацией.")" \
            "$(localized_text "如只是 timer 未刷新，可在同步失败后查看诊断上下文并重新修复 timer；如阈值配置错误，请先停用或重设基线。" "If only the timer is not refreshed, you can check the diagnostic context and repair the timer after the synchronization fails; if the threshold is configured incorrectly, please disable or reset the baseline first." "Если не обновляется только таймер, вы можете проверить диагностический контекст и восстановить таймер после сбоя синхронизации; Если порог настроен неправильно, сначала отключите или сбросьте базовый уровень.")" \
            "$(localized_text "当前低于阈值时这是最直接的同步方式；接近阈值时请先确认云厂商后台流量。" "When the current value is lower than the threshold, this is the most direct synchronization method; when it is close to the threshold, please first confirm the background traffic of the cloud provider." "Когда текущее значение ниже порогового значения, это самый прямой метод синхронизации; когда оно приближается к пороговому значению, сначала подтвердите фоновый трафик облачного провайдера.")" || return 1
    else
        confirm_risk_action "$(localized_text "立即运行一次流量保护检查器" "Run a traffic protection checker now" "Запустите проверку защиты трафика прямо сейчас")" \
            "$(localized_text "会立刻读取 ${IFACE:-当前网卡} 流量并刷新 ${TRAFFIC_GUARD_STATE_DIR}/state。" "The ${IFACE:-当前网卡} traffic will be read immediately and ${TRAFFIC_GUARD_STATE_DIR}/state will be refreshed." "Трафик ${IFACE:-当前网卡} будет прочитан немедленно, а ${TRAFFIC_GUARD_STATE_DIR}/state будет обновлен.")" \
            "$(localized_text "同步失败时查看诊断上下文，或重新修复 timer。" "Check the diagnostic context when synchronization fails, or repair the timer again." "Проверьте диагностический контекст в случае сбоя синхронизации или снова восстановите таймер.")" \
            "$(localized_text "当前 ACTION=${ACTION:-log}，达到阈值时只按配置动作执行。" "Currently ACTION=${ACTION:-log}, when the threshold is reached, only the configured action will be executed." "В настоящее время ACTION=${ACTION:-log}, при достижении порога будет выполнено только настроенное действие.")" || return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在立即运行 vps-traffic-guard-check 并验证状态刷新...${PLAIN}" "${CYAN}▶ Running vps-traffic-guard-check now and verifying status refresh...${PLAIN}" "${CYAN}▶ Запускаем vps-traffic-guard-check и проверяем обновление статуса...${PLAIN}")"
    if traffic_guard_run_checker_once; then
        show_traffic_guard_status
        return 0
    fi
    traffic_guard_print_timer_failure_context
    return 1
}

configure_traffic_guard() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "网络/内核优化 > 配置流量限额保护" "Network/Kernel Optimization > Configure traffic quota protection" "Оптимизация сети/ядра > Настройка защиты лимита трафика")"
    echo -e "$(localized_text "${BOLD}🧯 配置流量限额保护${PLAIN}" "${BOLD}🧯 Configure traffic quota protection${PLAIN}" "${BOLD}🧯 Настройка защиты лимита трафика${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：定时读取网卡流量，达到阈值后自动关机，避免超额流量产生账单。${PLAIN}" "${YELLOW}Purpose: Read the network card traffic regularly and automatically shut down after reaching the threshold to avoid excessive traffic bills.${PLAIN}" "${YELLOW}Назначение: регулярно считывать трафик сетевой карты и автоматически отключаться после достижения порогового значения, чтобы избежать чрезмерных счетов за трафик.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}注意：脚本只能按本机网卡计数估算，云厂商后台统计可能有延迟或口径差异，请留安全余量。${PLAIN}" "${YELLOW}Note: The script can only be estimated based on the local network card count. The cloud vendor's background statistics may have delays or caliber differences, so please leave a safety margin.${PLAIN}" "${YELLOW}Примечание. Сценарий можно оценить только на основе количества локальных сетевых карт. Справочная статистика поставщика облачных услуг может иметь задержки или различия в калибре, поэтому оставляйте запас прочности.${PLAIN}")"
    echo -e "------------------------------------------------"

    local default_iface iface limit_gb limit_bytes initial_used_gb initial_used_bytes
    local cycle_day cycle_default_day warn_percent action_choice action mode_choice mode interval ssh_port=""
    local current_stats current_rx current_tx detected_used_bytes detected_used_gb existing_used_bytes
    default_iface=$(traffic_guard_detect_iface)
    iface=$(ask_with_default "$(localized_text "监控网卡（自动推荐活跃公网网卡）" "Network interface to monitor (active public interface is suggested automatically)" "Сетевой интерфейс для контроля (активный публичный интерфейс предлагается автоматически)")" "${default_iface:-eth0}")
    if ! traffic_guard_valid_iface "$iface"; then
        echo -e "$(localized_text "${RED}❌ 网卡 ${iface} 不存在或无法读取统计数据。${PLAIN}" "${RED}❌ Network card ${iface} does not exist or the statistics cannot be read.${PLAIN}" "${RED}❌ Сетевая карта ${iface} не существует или невозможно прочитать статистику.${PLAIN}")"
        pause_return
        return 1
    fi
    mapfile -t current_stats < <(traffic_guard_read_stats "$iface")
    current_rx="${current_stats[0]:-0}"
    current_tx="${current_stats[1]:-0}"
    echo -e "$(localized_text "${GREEN}✅ 已选择网卡：${iface}${PLAIN}" "${GREEN}✅ Network card selected: ${iface}${PLAIN}" "${GREEN}Выбрана сетевая карта: ${iface}${PLAIN}")"
    echo -e "$(localized_text "当前网卡原始计数（自开机累计，仅用于建立基线）：RX ${CYAN}$(traffic_guard_human_bytes "$current_rx")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes "$current_tx")${PLAIN}" "Current interface counters (since boot; used only to establish the baseline): RX ${CYAN}$(traffic_guard_human_bytes \"$current_rx\")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes \"$current_tx\")${PLAIN}" "Текущие счётчики интерфейса (с момента загрузки; только для создания базового уровня): RX ${CYAN}$(traffic_guard_human_bytes \"$current_rx\")${PLAIN} / TX ${CYAN}$(traffic_guard_human_bytes \"$current_tx\")${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}说明：系统只能读取本机网卡计数；配置后会从当前计数建立基线，云厂商账单口径可能不同，请优先参考云后台并留余量。${PLAIN}" "${YELLOW}Description: The system can only read the local network card count; after configuration, a baseline will be established from the current count. The billing caliber of cloud vendors may be different. Please refer to the cloud background first and leave a margin.${PLAIN}" "${YELLOW}Описание: Система может только считывать количество локальных сетевых карт; после настройки базовый уровень будет установлен на основе текущего количества. Уровень выставления счетов у поставщиков облачных услуг может быть разным. Пожалуйста, сначала обратитесь к фону облаков и оставьте запас.${PLAIN}")"

    while true; do
        limit_gb=$(ask_with_default "$(localized_text "本周期流量阈值 GB（建议填套餐的 80%-95%）" "Traffic threshold for this cycle GB (it is recommended to fill in 80%-95% of the package)" "Порог трафика для этого цикла ГБ (рекомендуется заполнить 80%-95% пакета)")" "900")
        if limit_bytes=$(traffic_guard_gb_to_bytes "$limit_gb" 2>/dev/null); then
            break
        fi
        echo -e "$(localized_text "${RED}❌ 阈值无效，请输入大于 0 的数字，例如 900 或 0.5。${PLAIN}" "${RED}❌ Invalid threshold, please enter a number greater than 0, such as 900 or 0.5.${PLAIN}" "${RED}❌ Неверный порог. Введите число больше 0, например 900 или 0,5.${PLAIN}")"
    done

    while true; do
        cycle_default_day=$(date +%d)
        cycle_default_day=$((10#$cycle_default_day))
        cycle_day=$(ask_with_default "$(localized_text "每月套餐/账单重置日 1-31（短月份自动按最后一天）" "Monthly package/bill reset date 1-31 (short months automatically reset to the last day)" "Дата сброса ежемесячного пакета/счета 1–31 (короткие месяцы автоматически сбрасываются до последнего дня)")" "$cycle_default_day")
        if [[ "$cycle_day" =~ ^[0-9]+$ ]] && (( 10#$cycle_day >= 1 && 10#$cycle_day <= 31 )); then
            break
        fi
        echo -e "$(localized_text "${RED}❌ 重置日只支持 1-31。${PLAIN}" "${RED}❌ The reset date only supports 1-31.${PLAIN}" "${RED}❌ Дата сброса поддерживается только в диапазоне от 1 до 31.${PLAIN}")"
    done

    echo -e "$(localized_text "计费模式：" "Billing model:" "Модель выставления счетов:")"
    echo -e "$(localized_text "  1. 出站 TX 计费" "1. Outbound TX billing" "1. Биллинг за исходящую передачу")"
    echo -e "$(localized_text "  2. 出入总量 RX+TX" "2. Total deposits and withdrawals RX+TX" "2. Общая сумма депозитов и снятий RX+TX")"
    echo -e "$(localized_text "  3. 任一方向达量" "3. Amount in any direction" "3. Сумма в любую сторону")"
    echo -e "$(localized_text "  4. 入站 RX 计费" "4. Inbound RX billing" "4. Биллинг входящего приема")"
    read_trimmed mode_choice "$(localized_text "选择流量统计模式 [1]: " "Select traffic accounting mode [1]: " "Выберите режим учёта трафика [1]: ")"
    case "${mode_choice:-1}" in
        2) mode="total" ;;
        3) mode="max" ;;
        4) mode="rx" ;;
        *) mode="tx" ;;
    esac

    detected_used_bytes=$(traffic_guard_detect_initial_used_bytes "$iface" "$mode" "$cycle_day")
    detected_used_gb=$(traffic_guard_bytes_to_gb "$detected_used_bytes")
    existing_used_bytes=$(traffic_guard_existing_state_usage "$iface" "$mode" "$cycle_day" 2>/dev/null || true)
    if [[ "$existing_used_bytes" =~ ^[0-9]+$ && "$existing_used_bytes" != "$detected_used_bytes" ]]; then
        echo -e "$(localized_text "检测到已有保护状态已用：${YELLOW}$(traffic_guard_human_bytes "$existing_used_bytes")${PLAIN}" "Detected that the existing protection status has been used: ${YELLOW}$(traffic_guard_human_bytes \"$existing_used_bytes\")${PLAIN}" "Обнаружено, что использован существующий статус защиты: ${YELLOW}$(traffic_guard_human_bytes \"$existing_used_bytes\")${PLAIN}.")"
        echo -e "$(localized_text "${YELLOW}本次重新配置默认按当前网卡原始计数估算，启用后会重置基线，避免旧状态误导。${PLAIN}" "${YELLOW}This reconfiguration defaults to the original count of the current network card. After being enabled, the baseline will be reset to avoid misleading the old status.${PLAIN}" "${YELLOW}При этой реконфигурации по умолчанию используется исходный счетчик текущей сетевой карты. После включения базовый уровень будет сброшен, чтобы не вводить в заблуждение старый статус.${PLAIN}")"
    fi
    echo -e "$(localized_text "默认初始已用按当前网卡原始计数和计费模式估算：${CYAN}$(traffic_guard_human_bytes "$detected_used_bytes")${PLAIN}（默认可直接回车）" "The default initial usage is estimated based on the original count and billing mode of the current network card: ${CYAN}$(traffic_guard_human_bytes \"$detected_used_bytes\")${PLAIN} (you can press Enter directly by default)" "Первоначальное использование по умолчанию оценивается на основе исходного количества и режима выставления счетов текущей сетевой карты: ${CYAN}$(traffic_guard_human_bytes \"$detected_used_bytes\")${PLAIN} (по умолчанию вы можете нажать Enter напрямую)")"
    echo -e "$(localized_text "${YELLOW}如果云厂商后台显示不同，请手动覆盖这里的 GB 数值。${PLAIN}" "${YELLOW}If the cloud provider background display is different, please manually overwrite the GB value here.${PLAIN}" "${YELLOW}Если фоновое отображение облачного провайдера отличается, вручную перезапишите здесь значение ГБ.${PLAIN}")"
    while true; do
        initial_used_gb=$(ask_with_default "$(localized_text "本周期已用流量 GB" "Traffic used in this cycle GB" "Трафик, использованный в этом цикле, ГБ")" "$detected_used_gb")
        if initial_used_bytes=$(traffic_guard_gb_to_bytes_zero_ok "$initial_used_gb" 2>/dev/null); then
            break
        fi
        echo -e "$(localized_text "${RED}❌ 已用流量无效，请输入不小于 0 的数字。${PLAIN}" "${RED}❌ The used traffic is invalid, please enter a number not less than 0.${PLAIN}" "${RED}❌ Использованный трафик недействителен, введите число не меньше 0.${PLAIN}")"
    done

    while true; do
        warn_percent=$(ask_with_default "$(localized_text "预警百分比 1-99" "Warning percentage 1-99" "Процент предупреждений 1-99")" "90")
        if [[ "$warn_percent" =~ ^[0-9]+$ ]] && (( 10#$warn_percent >= 1 && 10#$warn_percent <= 99 )); then
            break
        fi
        echo -e "$(localized_text "${RED}❌ 预警百分比无效。${PLAIN}" "${RED}❌ The warning percentage is invalid.${PLAIN}" "${RED}❌ Недопустимый процент предупреждения.${PLAIN}")"
    done

    interval=$(ask_with_default "$(localized_text "检查间隔秒数（最低 30，默认 60）" "Number of seconds between checks (minimum 30, default 60)" "Количество секунд между проверками (минимум 30, по умолчанию 60)")" "60")
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( 10#$interval < 30 )); then
        interval=60
    fi

    echo -e "$(localized_text "触发动作：" "Trigger action:" "Триггерное действие:")"
    echo -e "$(localized_text "  1. 立即关机 ${YELLOW}(防止继续产生流量费用)${PLAIN}" "1. Shut down immediately ${YELLOW}(to prevent continued traffic charges)${PLAIN}" "1. Немедленно выключите ${YELLOW}(во избежание продолжения оплаты трафика)${PLAIN}")"
    echo -e "$(localized_text "  2. 仅保留 SSH 端口 ${YELLOW}(封锁其他公网业务流量，到重置日自动恢复)${PLAIN}" "2. Only reserve SSH port ${YELLOW}(block other public business traffic and automatically restore on the reset date)${PLAIN}" "2. Зарезервируйте только порт SSH ${YELLOW}(блокируйте другой бизнес-трафик публичной сети и автоматически восстанавливайте его в дату сброса)${PLAIN}")"
    echo -e "$(localized_text "  3. 只写日志 ${YELLOW}(安全默认值；不关机、不封锁端口)${PLAIN}" "3. Log only ${YELLOW}(safe default; no shutdown or port blocking)${PLAIN}" "3. Только журнал ${YELLOW}(безопасный вариант по умолчанию; без выключения и блокировки портов)${PLAIN}")"
    while true; do
        read_trimmed action_choice "$(localized_text "请选择触发动作 (默认 3): " "Select a trigger action (default 3): " "Выберите действие (по умолчанию 3): ")"
        case "${action_choice:-3}" in
            1)
                action="poweroff"
                break
                ;;
            2)
                traffic_guard_ssh_only_firewall_supported || {
                    echo -e "$(localized_text "${RED}❌ 缺少 iptables，或启用 IPv6 时缺少 ip6tables，无法安全启用仅保留 SSH 模式。${PLAIN}" "${RED}❌ SSH-only mode requires iptables and, when IPv6 is enabled, ip6tables.${PLAIN}" "${RED}❌ Для режима «только SSH» требуется iptables, а при включённом IPv6 — также ip6tables.${PLAIN}")"
                    pause_return
                    return 1
                }
                ssh_port=$(traffic_guard_detect_ssh_port) || {
                    echo -e "$(localized_text "${RED}❌ 未检测到唯一可用的 SSH 监听端口，无法安全启用仅保留 SSH 模式。${PLAIN}" "${RED}❌ A single usable SSH listening port was not detected; SSH-only mode cannot be enabled safely.${PLAIN}" "${RED}❌ Не удалось определить единственный доступный порт SSH; безопасно включить режим «только SSH» невозможно.${PLAIN}")"
                    pause_return
                    return 1
                }
                action="ssh-only"
                break
                ;;
            3)
                action="log"
                break
                ;;
            *)
                echo -e "$(localized_text "${YELLOW}请输入 1、2 或 3；直接回车使用安全默认值 3。${PLAIN}" "${YELLOW}Enter 1, 2, or 3. Press Enter for the safe default, 3.${PLAIN}" "${YELLOW}Введите 1, 2 или 3. Нажмите Enter для безопасного варианта 3.${PLAIN}")"
                ;;
        esac
    done

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "网卡：${CYAN}${iface}${PLAIN}" "Network card: ${CYAN}${iface}${PLAIN}" "Сетевая карта: ${CYAN}${iface}${PLAIN}")"
    echo -e "$(localized_text "阈值：${YELLOW}${limit_gb}GB${PLAIN}，本周期初始已用：${initial_used_gb}GB" "Threshold: ${YELLOW}${limit_gb}GB${PLAIN}, initially used in this cycle: ${initial_used_gb}GB" "Порог: ${YELLOW}${limit_gb}GB${PLAIN}, первоначально используемый в этом цикле: ${initial_used_gb}GB")"
    echo -e "$(localized_text "模式：${CYAN}$(traffic_guard_mode_label "$mode")${PLAIN}" "Mode: ${CYAN}$(traffic_guard_mode_label \"$mode\")${PLAIN}" "Режим: ${CYAN}$(traffic_guard_mode_label \"$mode\")${PLAIN}")"
    echo -e "$(localized_text "周期：每月 ${cycle_day} 日重置（短月份按最后一天）；检查间隔：${interval}s；预警：${warn_percent}%" "Period: ${cycle_day} daily reset every month (short months are based on the last day); check interval: ${interval}s; early warning: ${warn_percent}%" "Период: ${cycle_day} ежедневно сбрасывается каждый месяц (короткие месяцы основаны на последнем дне); интервал проверки: ${interval}s; раннее предупреждение: ${warn_percent}%")"
    echo -e "$(localized_text "动作：${RED}$(traffic_guard_action_label "$action")${PLAIN}" "Action: ${RED}$(traffic_guard_action_label \"$action\")${PLAIN}" "Действие: ${RED}$(traffic_guard_action_label \"$action\")${PLAIN}")"
    [[ "$action" == "ssh-only" ]] && echo -e "$(localized_text "保留 SSH：${CYAN}${ssh_port}/tcp${PLAIN}；其余公网业务流量会被临时封锁，必要网络控制流量仍保留。" "Reserved SSH: ${CYAN}${ssh_port}/tcp${PLAIN}; other public business traffic will be temporarily blocked, and necessary network control traffic will still be retained." "Зарезервировано SSH: ${CYAN}${ssh_port}/tcp${PLAIN}; другой бизнес-трафик публичной сети будет временно заблокирован, а необходимый трафик управления сетью по-прежнему будет сохраняться.")"

    if [[ "$action" == "poweroff" ]]; then
        confirm_danger "$(localized_text "启用流量达量自动关机" "Enable automatic shutdown when traffic reaches high volume" "Включить автоматическое отключение, когда трафик достигает большого объема")" \
            "$(localized_text "安装 vps-traffic-guard systemd timer；达到阈值会执行 systemctl poweroff。" "Install vps-traffic-guard systemd timer; systemctl poweroff will be executed when the threshold is reached." "Установите таймер vps-traffic-guard systemd; systemctl poweroff будет выполнен при достижении порога.")" \
            "$(localized_text "从云厂商控制台手动开机；开机后进入本菜单调整阈值、重置基线或停用保护。" "Manually boot from the cloud vendor console; after booting, enter this menu to adjust the threshold, reset the baseline, or disable protection." "Загрузка вручную из консоли поставщика облака; после загрузки войдите в это меню, чтобы настроить пороговое значение, сбросить базовый уровень или отключить защиту.")" \
            "$(localized_text "建议阈值低于套餐上限，并确认云厂商后台流量口径。" "It is recommended that the threshold be lower than the upper limit of the package and confirm the backend traffic caliber of the cloud vendor." "Рекомендуется, чтобы порог был ниже верхнего предела пакета и подтверждал уровень внутреннего трафика поставщика облака.")" || return 1
    elif [[ "$action" == "ssh-only" ]]; then
        confirm_danger "$(localized_text "启用达量后仅保留 SSH" "After enabling the amount, only SSH will be retained." "После включения суммы сохранится только SSH.")" \
            "$(localized_text "达到阈值后，保留 ${ssh_port}/tcp 的 SSH 和必要网络控制流量；其他公网业务流量会被临时封锁。" "After reaching the threshold, SSH and necessary network control traffic of ${ssh_port}/tcp are retained; other public business traffic will be temporarily blocked." "После достижения порога SSH и необходимый трафик управления сетью ${ssh_port}/tcp сохраняются; другой бизнес-трафик публичной сети будет временно заблокирован.")" \
            "$(localized_text "下个账单重置日自动解除封锁；也可在本菜单重置基线或停用保护来立即解除。" "The block will be automatically unblocked on the next bill reset date; you can also reset the baseline or disable protection in this menu to unblock it immediately." "Блокировка будет автоматически разблокирована в следующую дату обнуления счета; вы также можете сбросить базовый уровень или отключить защиту в этом меню, чтобы немедленно разблокировать ее.")" \
            "$(localized_text "SSH 端口必须保持可用；云厂商安全组和 SSH 服务异常仍可能导致无法登录。" "The SSH port must remain available; abnormalities in the cloud vendor security group and SSH service may still result in the inability to log in." "Порт SSH должен оставаться доступным; отклонения в группе безопасности поставщика облака и службе SSH по-прежнему могут приводить к невозможности входа в систему.")" || return 1
    fi

    traffic_guard_restore_ssh_only_firewall || {
        echo -e "$(localized_text "${RED}❌ 无法解除上一周期的仅保留 SSH 封锁规则，已取消重新配置。${PLAIN}" "${RED}❌ Unable to unblock the previous cycle's keep-only SSH blocking rule, reconfiguration canceled.${PLAIN}" "${RED}❌ Невозможно разблокировать правило блокировки SSH предыдущего цикла только для сохранения, реконфигурация отменена.${PLAIN}")"
        pause_return
        return 1
    }

    write_traffic_guard_config "$iface" "$mode" "$limit_gb" "$limit_bytes" "$cycle_day" "$warn_percent" "$action" "$initial_used_gb" "$initial_used_bytes" "$interval" "$ssh_port" || {
        echo -e "$(localized_text "${RED}❌ 写入配置失败。${PLAIN}" "${RED}❌ Failed to write configuration.${PLAIN}" "${RED}❌ Не удалось записать конфигурацию.${PLAIN}")"
        pause_return
        return 1
    }
    traffic_guard_install_checker_or_report || {
        pause_return
        return 1
    }
    traffic_guard_write_state_baseline "$iface" "$cycle_day" "$initial_used_bytes" "$mode" || {
        echo -e "$(localized_text "${RED}❌ 写入流量保护基线失败。${PLAIN}" "${RED}❌ Failed to write traffic protection baseline.${PLAIN}" "${RED}❌ Не удалось записать базовый уровень защиты трафика.${PLAIN}")"
        pause_return
        return 1
    }
    install_traffic_guard_units "$interval" || {
        echo -e "$(localized_text "${RED}❌ 启用 systemd timer 失败，请检查 systemd 状态。${PLAIN}" "${RED}❌ Failed to enable systemd timer, please check systemd status.${PLAIN}" "${RED}❌ Не удалось включить таймер systemd, проверьте статус systemd.${PLAIN}")"
        pause_return
        return 1
    }

    local checker_rc=0
    /usr/bin/env bash "$TRAFFIC_GUARD_CHECKER" >/dev/null 2>&1 || checker_rc=$?
    if (( checker_rc == 0 )); then
        reset_traffic_guard_failed_state
        echo -e "$(localized_text "${GREEN}✅ 流量限额保护已启用，首次检查通过。${PLAIN}" "${GREEN}✅ Traffic quota protection is enabled; the first check passed.${PLAIN}" "${GREEN}✅ Защита лимита трафика включена; первая проверка пройдена.${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 流量限额保护已启用，但首次检查失败（rc=${checker_rc}）。请查看日志和菜单 [2] 的状态。${PLAIN}" "${YELLOW}⚠️ Traffic quota protection is enabled, but the first check failed (rc=${checker_rc}). Check the logs and menu [2].${PLAIN}" "${YELLOW}⚠️ Защита лимита трафика включена, но первая проверка завершилась ошибкой (rc=${checker_rc}). Проверьте журнал и пункт [2].${PLAIN}")"
    fi
    echo -e "$(localized_text "${YELLOW}状态可在本菜单 [2] 查看；日志：${TRAFFIC_GUARD_LOG}${PLAIN}" "${YELLOW}The status can be viewed in this menu [2]; log: ${TRAFFIC_GUARD_LOG}${PLAIN}" "${YELLOW}Статус можно просмотреть в этом меню [2]; журнал: ${TRAFFIC_GUARD_LOG}${PLAIN}")"
    pause_return
}

reset_traffic_guard_baseline() {
    local iface mode cycle_day initial_used_gb initial_used_bytes
    local detected_used_bytes detected_used_gb
    load_traffic_guard_config || {
        echo -e "$(localized_text "${YELLOW}尚未配置流量限额保护。${PLAIN}" "${YELLOW}Traffic quota protection is not configured.${PLAIN}" "${YELLOW}Защита лимита трафика не настроена.${PLAIN}")"
        pause_return
        return 1
    }
    iface="${IFACE:-}"
    mode="${MODE:-tx}"
    cycle_day="${CYCLE_DAY:-1}"
    traffic_guard_valid_iface "$iface" || {
        echo -e "$(localized_text "${RED}❌ 当前配置的网卡 ${iface} 不可读。${PLAIN}" "${RED}❌ The currently configured network card ${iface} is unreadable.${PLAIN}" "${RED}❌ Текущая настроенная сетевая карта ${iface} не читается.${PLAIN}")"
        pause_return
        return 1
    }
    detected_used_bytes=$(traffic_guard_detect_initial_used_bytes "$iface" "$mode" "$cycle_day")
    detected_used_gb=$(traffic_guard_bytes_to_gb "$detected_used_bytes")
    echo -e "$(localized_text "默认初始已用按当前网卡原始计数和计费模式估算：${CYAN}$(traffic_guard_human_bytes "$detected_used_bytes")${PLAIN}" "The default initial usage is estimated based on the original count and billing mode of the current network card: ${CYAN}$(traffic_guard_human_bytes \"$detected_used_bytes\")${PLAIN}" "Первоначальное использование по умолчанию оценивается на основе исходного счетчика и режима выставления счетов текущей сетевой карты: ${CYAN}$(traffic_guard_human_bytes \"$detected_used_bytes\")${PLAIN}.")"
    initial_used_gb=$(ask_with_default "$(localized_text "重置后本周期已用流量 GB" "Used traffic GB in this cycle after reset" "Использовано ГБ трафика в этом цикле после сброса")" "$detected_used_gb")
    if ! initial_used_bytes=$(traffic_guard_gb_to_bytes_zero_ok "$initial_used_gb" 2>/dev/null); then
        echo -e "$(localized_text "${RED}❌ 已用流量无效。${PLAIN}" "${RED}❌ The used traffic is invalid.${PLAIN}" "${RED}❌ Используемый трафик недействителен.${PLAIN}")"
        pause_return
        return 1
    fi
    confirm_risk_action "$(localized_text "重置流量保护基线" "Reset traffic protection baseline" "Сбросить базовый уровень защиты трафика")" \
        "$(localized_text "本周期统计会从当前网卡计数重新开始，初始已用设置为 ${initial_used_gb}GB。" "Statistics for this cycle will restart from the current network card count, and the initial used setting is ${initial_used_gb}GB." "Статистика для этого цикла будет перезапущена с текущего количества сетевых карт, а исходная используемая настройка — ${initial_used_gb}GB.")" \
        "$(localized_text "重新进入本菜单再次重置基线，或参考云厂商后台手动修正已用流量。" "Re-enter this menu to reset the baseline again, or refer to the cloud provider's backend to manually correct the used traffic." "Повторно войдите в это меню, чтобы снова сбросить базовый уровень, или обратитесь к серверной части поставщика облачных услуг, чтобы вручную скорректировать использованный трафик.")" \
        "$(localized_text "请只在账单周期开始、刚配置完成或确认云厂商统计后执行。" "Please only execute it at the beginning of the billing cycle, after the configuration has just been completed, or after confirming the cloud provider's statistics." "Пожалуйста, выполняйте его только в начале платежного цикла, после завершения настройки или после подтверждения статистики облачного провайдера.")" || return 1

    traffic_guard_restore_ssh_only_firewall || {
        echo -e "$(localized_text "${RED}❌ 无法解除仅保留 SSH 封锁规则，未重置统计基线。${PLAIN}" "${RED}❌ Unable to unblock only SSH blocking rule, the statistical baseline is not reset.${PLAIN}" "${RED}❌ Невозможно разблокировать только правило блокировки SSH, базовый статистический показатель не сбрасывается.${PLAIN}")"
        pause_return
        return 1
    }
    traffic_guard_write_state_baseline "$iface" "$cycle_day" "$initial_used_bytes" "$mode" || {
        echo -e "$(localized_text "${RED}❌ 写入流量保护基线失败。${PLAIN}" "${RED}❌ Failed to write traffic protection baseline.${PLAIN}" "${RED}❌ Не удалось записать базовый уровень защиты трафика.${PLAIN}")"
        pause_return
        return 1
    }
    echo -e "$(localized_text "${GREEN}✅ 已重置 ${iface} 的流量统计基线。${PLAIN}" "${GREEN}✅ The traffic statistics baseline of ${iface} has been reset.${PLAIN}" "${GREEN}✅ Базовая статистика трафика ${iface} была сброшена.${PLAIN}")"
    echo -e "$(localized_text "当前模式：${CYAN}$(traffic_guard_mode_label "$mode")${PLAIN}；本周期已用：$(traffic_guard_human_bytes "$initial_used_bytes")" "Current mode: ${CYAN}$(traffic_guard_mode_label \"$mode\")${PLAIN}; used in this cycle: $(traffic_guard_human_bytes \"$initial_used_bytes\")" "Текущий режим: ${CYAN}$(traffic_guard_mode_label \"$mode\")${PLAIN}; используется в этом цикле: $(traffic_guard_human_bytes \"$initial_used_bytes\")")"
    pause_return
}

repair_traffic_guard_timer() {
    local interval
    load_traffic_guard_config || {
        echo -e "$(localized_text "${YELLOW}尚未配置流量限额保护。${PLAIN}" "${YELLOW}Traffic quota protection is not configured.${PLAIN}" "${YELLOW}Защита лимита трафика не настроена.${PLAIN}")"
        pause_return
        return 1
    }
    interval="${CHECK_INTERVAL:-60}"
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || (( 10#$interval < 30 )); then
        interval=60
    fi

    if [[ "${ACTION:-poweroff}" == "poweroff" ]]; then
        confirm_danger "$(localized_text "修复流量保护自动检查 timer" "Fix traffic protection automatic check timer" "Исправить таймер автоматической проверки защиты трафика")" \
            "$(localized_text "会重新安装 vps-traffic-guard-check 和 systemd timer，恢复后会按 ${interval}s 周期检查。" "vps-traffic-guard-check and systemd timer will be reinstalled, and they will be checked at the ${interval}s period after recovery." "vps-traffic-guard-check и таймер systemd будут переустановлены, и после восстановления они будут проверены в период ${interval}s.")" \
            "$(localized_text "如果当前实时估算已经达到阈值，下一次检查可能会执行 systemctl poweroff。" "If the current live estimate has reached the threshold, the next check may perform a systemctl poweroff." "Если текущая оперативная оценка достигла порога, следующая проверка может выполнить отключение systemctl.")" \
            "$(localized_text "请先确认云厂商后台流量、阈值和当前 SSH/控制台救援方式。" "Please first confirm the cloud provider's background traffic, threshold and current SSH/console rescue method." "Сначала подтвердите фоновый трафик облачного провайдера, пороговое значение и текущий метод восстановления SSH/консоли.")" || return 1
    else
        confirm_risk_action "$(localized_text "修复流量保护自动检查 timer" "Fix traffic protection automatic check timer" "Исправить таймер автоматической проверки защиты трафика")" \
            "$(localized_text "会重新安装 vps-traffic-guard-check 和 systemd timer，恢复后会按 ${interval}s 周期检查。" "vps-traffic-guard-check and systemd timer will be reinstalled, and they will be checked at the ${interval}s period after recovery." "vps-traffic-guard-check и таймер systemd будут переустановлены, и после восстановления они будут проверены в период ${interval}s.")" \
            "$(localized_text "当前动作是 ${ACTION:-log}，达到阈值时只按配置动作执行。" "The current action is ${ACTION:-log}. When the threshold is reached, only the configured action will be executed." "Текущее действие — ${ACTION:-log}. При достижении порогового значения будет выполнено только настроенное действие.")" \
            "$(localized_text "修复后请回到状态页确认最近检查时间开始刷新。" "After repair, please return to the status page to confirm that the last check time has started to refresh." "После ремонта вернитесь на страницу состояния и убедитесь, что время последней проверки начало обновляться.")" || return 1
    fi

    traffic_guard_install_checker_or_report || {
        pause_return
        return 1
    }
    install_traffic_guard_units "$interval" || {
        echo -e "$(localized_text "${RED}❌ 启用 systemd timer 失败，请检查 systemd 状态。${PLAIN}" "${RED}❌ Failed to enable systemd timer, please check systemd status.${PLAIN}" "${RED}❌ Не удалось включить таймер systemd, проверьте статус systemd.${PLAIN}")"
        pause_return
        return 1
    }
    systemctl restart vps-traffic-guard.timer >/dev/null 2>&1 || true
    reset_traffic_guard_failed_state
    echo -e "$(localized_text "${GREEN}✅ 已重装并重启 vps-traffic-guard.timer。${PLAIN}" "${GREEN}✅ vps-traffic-guard.timer has been reinstalled and restarted.${PLAIN}" "${GREEN}вещество vps-traffic-guard.timer переустановлено и перезапущено.${PLAIN}")"
    echo -e "$(localized_text "${CYAN}▶ 正在立即运行一次检查器，验证状态文件是否刷新...${PLAIN}" "${CYAN}▶ Running a checker immediately to verify whether the status file is refreshed...${PLAIN}" "${CYAN}▶ Немедленный запуск проверки, чтобы проверить, обновлен ли файл состояния...${PLAIN}")"
    if traffic_guard_run_checker_once; then
        echo -e "$(localized_text "${GREEN}✅ 已重装 timer，并确认检查器可以刷新状态。${PLAIN}" "${GREEN}✅ Timer has been reinstalled and the checker has been confirmed to refresh the status.${PLAIN}" "${GREEN}✅ Таймер переустановлен и чекером подтверждено обновление статуса.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ timer 已重装，但检查器仍未刷新状态。下面是可直接排查的上下文：${PLAIN}" "${RED}❌ timer has been reinstalled, but the checker still has not refreshed status. The following is the context that can be directly investigated:${PLAIN}" "${RED}Таймер ❌ переустановлен, но статус чекера все еще не обновился. Ниже приводится контекст, который можно непосредственно исследовать:.${PLAIN}")"
        traffic_guard_print_timer_failure_context
        pause_return
        return 1
    fi
    echo -e "$(localized_text "${YELLOW}后续可回到 [2] 查看状态；如果再次过期，用 [7] 可立即验证检查器。${PLAIN}" "${YELLOW}Can return to [2] to check the status later; if it expires again, use [7] to verify the checker immediately.${PLAIN}" "${YELLOW}может вернуться к [2], чтобы позже проверить статус; если срок его действия снова истечет, используйте [7] для немедленной проверки чекера.${PLAIN}")"
    systemctl list-timers --all vps-traffic-guard.timer --no-pager 2>/dev/null || true
    pause_return
}

disable_traffic_guard() {
    if ! systemctl list-unit-files vps-traffic-guard.timer >/dev/null 2>&1 && [[ ! -f "$TRAFFIC_GUARD_CONFIG" ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到流量保护配置。${PLAIN}" "${YELLOW}No traffic protection configuration detected.${PLAIN}" "${YELLOW}Конфигурация защиты трафика не обнаружена.${PLAIN}")"
        pause_return
        return 0
    fi
    confirm_risk_action "$(localized_text "停用流量限额保护" "Disable traffic quota protection" "Отключить защиту лимита трафика")" \
        "$(localized_text "vps-traffic-guard.timer 会停止，达到流量阈值后不再执行配置的动作。" "vps-traffic-guard.timer will stop and will no longer perform configured actions after the traffic threshold is reached." "vps-traffic-guard.timer остановится и больше не будет выполнять настроенные действия после достижения порога трафика.")" \
        "$(localized_text "重新进入本菜单选择 [1] 启用保护。" "Re-enter this menu and select [1] to enable protection." "Снова войдите в это меню и выберите [1], чтобы включить защиту.")" \
        "$(localized_text "停用后请自行监控云厂商流量，避免超额账单。" "After deactivation, please monitor the cloud provider's traffic yourself to avoid excessive bills." "После деактивации следите за трафиком облачного провайдера самостоятельно, чтобы избежать чрезмерных счетов.")" || return 1
    traffic_guard_restore_ssh_only_firewall || {
        echo -e "$(localized_text "${RED}❌ 无法解除仅保留 SSH 封锁规则，未停用保护。${PLAIN}" "${RED}❌ Unable to unblock only SSH blocking rule, protection is not disabled.${PLAIN}" "${RED}❌ Невозможно разблокировать только правило блокировки SSH, защита не отключена.${PLAIN}")"
        pause_return
        return 1
    }
    systemctl disable --now vps-traffic-guard.timer >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    reset_traffic_guard_failed_state
    if [[ -f "$TRAFFIC_GUARD_CONFIG" ]]; then
        sed -i 's/^ENABLED=.*/ENABLED=0/' "$TRAFFIC_GUARD_CONFIG" 2>/dev/null || true
    fi
    echo -e "$(localized_text "${GREEN}✅ 已停用流量限额保护；配置文件保留在 ${TRAFFIC_GUARD_CONFIG}${PLAIN}" "${GREEN}✅ Traffic quota protection is disabled; the configuration remains at ${TRAFFIC_GUARD_CONFIG}.${PLAIN}" "${GREEN}✅ Защита лимита трафика отключена; конфигурация сохранена в ${TRAFFIC_GUARD_CONFIG}.${PLAIN}")"
    pause_return
}

func_traffic_guard_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "网络/内核优化 > 流量限额保护" "Network/Kernel Optimization > Traffic quota protection" "Оптимизация сети/ядра > Защита лимита трафика")"
        echo -e "$(localized_text "${BOLD}🧯 流量限额保护${PLAIN}" "${BOLD}🧯 Traffic quota protection${PLAIN}" "${BOLD}🧯 Защита лимита трафика${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}达到安全阈值后自动关机或仅保留 SSH，避免流量超额。阈值应低于云厂商套餐上限。${PLAIN}" "${YELLOW}Shut down automatically or keep only SSH at the safety threshold to prevent overages. Set the threshold below the provider quota.${PLAIN}" "${YELLOW}При достижении безопасного порога сервер выключается либо оставляет только SSH. Установите порог ниже лимита провайдера.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 配置 / 启用保护${PLAIN}" "${GREEN}1. Configure / enable protection${PLAIN}" "${GREEN}1. Настроить/включить защиту${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 查看状态与本周期用量${PLAIN}" "${GREEN}  2. View status and current-cycle usage${PLAIN}" "${GREEN}  2. Показать состояние и расход за текущий период${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 重置本周期统计起点${PLAIN}" "${GREEN}  3. Reset the current-cycle baseline${PLAIN}" "${GREEN}  3. Сбросить исходное значение текущего периода${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  4. 停用保护${PLAIN}" "${YELLOW}4. Disable protection${PLAIN}" "${YELLOW}4. Отключить защиту${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 查看最近日志${PLAIN}" "${GREEN}  5. View recent logs${PLAIN}" "${GREEN}  5. Показать последние журналы${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  6. 修复 / 重装自动检查定时器${PLAIN}" "${GREEN}  6. Repair or reinstall the check timer${PLAIN}" "${GREEN}  6. Исправить или переустановить таймер проверки${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 立即同步并验证检查器${PLAIN}" "${GREEN}  7. Sync and verify the checker now${PLAIN}" "${GREEN}  7. Синхронизировать и проверить обработчик сейчас${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local choice
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1) configure_traffic_guard ;;
            2) show_traffic_guard_status; pause_return ;;
            3) reset_traffic_guard_baseline ;;
            4) disable_traffic_guard ;;
            5)
                echo -e "${CYAN}--- ${TRAFFIC_GUARD_LOG} ---${PLAIN}"
                tail -n 30 "$TRAFFIC_GUARD_LOG" 2>/dev/null || echo "$(localized_text "暂无日志" "No logs yet" "Журналов пока нет")"
                pause_return
                ;;
            6) repair_traffic_guard_timer ;;
            7) sync_traffic_guard_now; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}
