#!/usr/bin/env bash
set -euo pipefail
trap 'echo "dog-limits failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR
cd "$(dirname "$0")/.."

# Load functions without installing dog or accessing its production configuration.
source <(sed -n '/^normalize_ui_language()/,/^main()/p' dog.sh | sed '$d')
RED='' GREEN='' YELLOW='' BLUE='' NC='' UI_LANGUAGE=zh NFT_COUNTER_SNAPSHOT=''
test_dir=$(mktemp -d /tmp/dog-limits.XXXXXX)
CONFIG_DIR="$test_dir"
CONFIG_FILE="$test_dir/config.json"
DAILY_USAGE_FILE="$test_dir/daily.json"
DAILY_SNAPSHOT_STATE_FILE="$test_dir/state.json"
TRAFFIC_DATA_FILE="$test_dir/traffic.json"
cleanup() {
    rm -f -- "$CONFIG_FILE" "$DAILY_USAGE_FILE" "$DAILY_SNAPSHOT_STATE_FILE" "$TRAFFIC_DATA_FILE" "$test_dir/.config.lock"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cat > "$CONFIG_FILE" <<'JSON'
{"ports":{"54558":{"quota":{"enabled":true,"monthly_limit":"50g"},"bandwidth_limit":{"enabled":false}},"54559":{"quota":{"enabled":true,"monthly_limit":"unlimited"},"bandwidth_limit":{"enabled":false}},"65535":{},"1000-1002":{},"80":{},"1080":{}},"nftables":{"family":"inet","table_name":"dog_test"}}
JSON
printf '{}\n' > "$DAILY_USAGE_FILE"
printf '{}\n' > "$DAILY_SNAPSHOT_STATE_FILE"

[[ "$(parse_size_to_bytes 50g)" == 53687091200 ]]
[[ "$(parse_size_to_bytes 08GB)" == 8589934592 ]]
[[ "$(parse_tc_rate_to_kbps 08mbit)" == 8000 ]]
validate_bandwidth 50Mbps
if validate_bandwidth 0Mbps || validate_quota 0GB || validate_quota 999999999999T || validate_quota 9999999T; then exit 1; fi
choices=()
parse_multi_choice_input '1,1,2' 3 choices
[[ "${choices[*]}" == '1 2' ]]
if parse_multi_choice_input '1,54558' 3 choices >/dev/null; then exit 1; fi
[[ ${#choices[@]} == 0 ]]
if parse_port_range_input '443,' choices >/dev/null || parse_port_range_input '999999999999-65535' choices >/dev/null || parse_comma_separated_input '50G,' choices >/dev/null; then exit 1; fi
ports_overlap 54558 54000-55000
if ports_overlap 443 444-445; then exit 1; fi
problems=0
print_json_file_health valid "$DAILY_USAGE_FILE" problems >/dev/null
print_json_file_health missing "$test_dir/missing.json" problems >/dev/null
[[ "$problems" == 1 ]]
class_id=$(generate_tc_class_id 65535)
[[ "$class_id" =~ ^1:([a-f0-9]{1,4})$ ]]
(( 16#${BASH_REMATCH[1]} > 1 ))

# A mistyped rate must never remove the previous limit or update configuration.
(
    show_port_list() { :; }
    get_active_ports() { echo 54558; }
    remove_tc_limit() { echo 'unexpected removal' >&2; exit 1; }
    apply_tc_limit() { echo 'unexpected application' >&2; exit 1; }
    update_config() { echo 'unexpected config write' >&2; exit 1; }
    set_port_bandwidth_limit <<< $'1\nbad-rate\nq' >/dev/null
)
echo 'PASS: selection, units, health variable scope and invalid-rate preservation'

(
    FUNCNEST=12
    show_main_menu() { echo 'unexpected parent menu call' >&2; exit 1; }
    menu_input=$(printf 'invalid\n%.0s' {1..40}; printf '0\n')
    for menu in manage_port_monitoring manage_traffic_limits manage_traffic_reset manage_configuration manage_notifications manage_daily_usage_reports manage_telegram_schedule manage_telegram_template select_ui_language; do
        "$menu" <<< "$menu_input" >/dev/null
    done
    actions=''
    add_port_monitoring() { actions+='add '; }
    remove_port_monitoring() { actions+='remove '; }
    manage_port_monitoring <<< $'1\n2\n0' >/dev/null
    [[ "$actions" == 'add remove ' ]]
)
(
    show_port_list() { :; }
    get_active_ports() { printf '%s\n' 54558 54559; }
    selected=()
    select_monitored_ports selected <<< $'54558\n1,1,2' >/dev/null
    [[ "${selected[*]}" == '54558 54559' ]]
    select_monitored_ports selected <<< 'all' >/dev/null
    [[ "${selected[*]}" == '54558 54559' ]]
    if select_monitored_ports selected <<< 'q' >/dev/null; then exit 1; fi
    [[ ${#selected[@]} == 0 ]]
    apply_tc_limit() { echo 'unexpected partial update' >&2; exit 1; }
    set_port_bandwidth_limit <<< $'all\n10Mbps,bad-rate\nq' >/dev/null
    expr=''
    update_config() { expr="$1"; }
    setup_port_auto_reset_cron() { :; }
    set_reset_day <<< $'1\ninvalid\n08' >/dev/null
    [[ "$expr" == '.ports."54558".quota.reset_day = 8' ]]
    if confirm_danger reset irreversible <<< '' >/dev/null; then exit 1; fi
    confirm_danger reset irreversible <<< 'yes' >/dev/null
    update_telegram_template() { echo 'unexpected template save' >&2; exit 1; }
    manage_telegram_template <<< $'1\n{report}\nq' >/dev/null
)
echo 'PASS: menu return depth, in-place retries, batch selection and cancellation'

if [[ "${1:-}" != '--network' ]]; then
    if [[ "$EUID" == 0 ]] && command -v nft >/dev/null && command -v tc >/dev/null && unshare -n true 2>/dev/null; then
        unshare -n bash tests/dog-limits.sh --network
    else
        echo 'SKIPPED: isolated kernel checks require root, nft, tc and network namespaces'
    fi
    exit 0
fi

ip link set lo up
ip link add dog0 type veth peer name dog1
ip addr add 192.0.2.1/24 dev dog0
ip -6 addr add fd00:d09::1/64 dev dog0 nodad
ip link set dog0 up
ip link set dog1 up
ip route add default dev dog0
peer_mac=$(ip -j link show dog1 | jq -r '.[0].address')
ip neigh add 192.0.2.2 lladdr "$peer_mac" dev dog0 nud permanent
ip -6 neigh add fd00:d09::2 lladdr "$peer_mac" dev dog0 nud permanent

nft add table inet dog_test
for chain in input output forward; do
    nft add chain inet dog_test "$chain" "{ type filter hook $chain priority 0; }"
done
nft add counter inet dog_test port_54558_in '{ packets 1 bytes 1073741824; }'
for port in 54558 54559 65535 1000-1002 80 1080; do add_nftables_rules "$port"; done
apply_nftables_quota 54558 50g
nft insert rule inet dog_test output tcp sport 54558 quota name port_54558_quota drop
[[ "$(show_statistics_health_check)" == *'配额上限或规则异常'* ]]
apply_nftables_quota 54558 50g
nft -j list quota inet dog_test port_54558_quota | jq -e 'any(.nftables[]; .quota.bytes? == 53687091200 and .quota.used == 1073741824)' >/dev/null
for i in 1 2 3; do apply_nftables_quota 54558 50g; done
[[ "$(nft -j list table inet dog_test | jq '[.nftables[] | .rule? // empty | select(any(.expr[]?; .quota? == "port_54558_quota"))] | length')" == 8 ]]

# Reconcile a stale 1G kernel quota even when all eight references still exist.
apply_nftables_quota 54558 1G true
apply_nftables_quota 54558 50g
nft -j list quota inet dog_test port_54558_quota | jq -e 'any(.nftables[]; .quota.bytes? == 53687091200)' >/dev/null
health_output=$(show_statistics_health_check)
[[ "$health_output" == *'内核上限=53687091200 bytes'* ]]
[[ "$health_output" == *'未发现明显异常'* ]]

before=$(nft -j list table inet dog_test)
(
    nft() {
        if [[ "$1" == '-f' ]]; then
            { cat; printf '\nthis-is-invalid\n'; } | command nft -f - 2>/dev/null
        else command nft "$@"; fi
    }
    if apply_nftables_quota 54558 60G true 2>/dev/null; then exit 1; fi
)
[[ "$(nft -j list table inet dog_test)" == "$before" ]]
echo 'PASS: 50G after 1G used, stale quota repair, idempotence and atomic failure'

for port in 54558 54559 65535 1000-1002 80 1080; do apply_tc_limit "$port" 4mbit; done
# Old ports 80 and 1080 share u32 preference 81; remove only the selected handle.
tc filter add dev dog0 protocol ip parent 1: prio 81 u32 match ip sport 80 0xffff flowid "$(legacy_tc_class_id 80)"
tc filter add dev dog0 protocol ip parent 1: prio 81 u32 match ip sport 1080 0xffff flowid "$(legacy_tc_class_id 1080)"
apply_tc_limit 80 4mbit
tc -j filter show dev dog0 parent 1: | jq -e 'any(.[]; .kind == "u32" and .options.flowid? == "1:1438")' >/dev/null
apply_tc_limit 1080 4mbit
update_config '.ports["54559"].bandwidth_limit.enabled = true | .ports["54559"].bandwidth_limit.rate = "4Mbps"'
(
    tc() {
        if [[ "$1 ${2:-}" == 'filter replace' && "$*" == *'protocol ipv6'* ]]; then return 1; fi
        command tc "$@"
    }
    if apply_tc_limit 54559 8mbit 2>/dev/null; then exit 1; fi
)
tc -j class show dev dog0 | jq -e 'any(.[]; .handle == "1:e51f" and .rate == 500000)' >/dev/null
tc -j filter show dev dog0 parent 1: | jq -e '[.[] | select(.kind == "flower" and .options.classid != null)] | length == 48' >/dev/null
# Applying repeatedly must replace filters, not add duplicate references.
apply_tc_limit 54558 4mbit
tc -j filter show dev dog0 parent 1: | jq -e '[.[] | select(.kind == "flower" and .options.classid != null)] | length == 48' >/dev/null

python3 - <<'PY'
import socket
for family, local, remote in [(socket.AF_INET, '192.0.2.1', '192.0.2.2'), (socket.AF_INET6, 'fd00:d09::1', 'fd00:d09::2')]:
    with socket.socket(family, socket.SOCK_DGRAM) as sock:
        sock.bind((local, 54558))
        for _ in range(20):
            sock.sendto(b'x' * 1000, (remote, 54559))
PY
sleep 1
tc -s -j filter show dev dog0 parent 1: | jq -e '
    [.[] | select(.kind == "flower" and .options.keys.ip_proto? == "udp") |
     select(.options.keys.src_port? == 54558) | .options.in_hw // false] | length == 2
' >/dev/null
class_id=$(jq -r '.ports["54558"].bandwidth_limit.class_id' "$CONFIG_FILE")
class_stats=$(tc -s -j class show dev dog0)
jq -e --arg id "$class_id" 'any(.[]; .handle == $id and .rate == 500000 and (.stats.bytes // .bytes) > 40000)' <<< "$class_stats" >/dev/null || {
    jq --arg id "$class_id" '.[] | select(.handle == $id or .classid == $id)' <<< "$class_stats" >&2
    exit 1
}
nft -j list counter inet dog_test port_54558_out | jq -e 'any(.nftables[]; .counter.bytes? > 40000)' >/dev/null

# The same traffic must stop when the quota is actually exhausted.
apply_nftables_quota 54558 1G true
before_bytes=$(nft -j list counter inet dog_test port_54558_out | jq '[.nftables[] | .counter.bytes? // empty][0]')
python3 - <<'PY'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(('192.0.2.1', 54558))
    try:
        sock.sendto(b'blocked', ('192.0.2.2', 54559))
    except PermissionError:
        pass
    else:
        raise AssertionError('exhausted quota must reject the packet')
PY
[[ "$(nft -j list counter inet dog_test port_54558_out | jq '[.nftables[] | .counter.bytes? // empty][0]')" == "$before_bytes" ]]
apply_nftables_quota 54558 50g true
refresh_nftables_counter_snapshot
[[ "$(get_port_monthly_usage 54558)" -gt 1073741824 ]]
selected_index=$(get_active_ports | awk '$0 == "54558" {print NR}')
immediate_reset <<< "$selected_index"$'\ny' >/dev/null
[[ "$(get_port_monthly_usage 54558)" == 0 ]]
nft -j list quota inet dog_test port_54558_quota | jq -e 'any(.nftables[]; .quota.used? == 0)' >/dev/null

remove_tc_limit 54558
tc -j filter show dev dog0 parent 1: | jq -e '[.[] | select(.kind == "flower" and .options.classid != null)] | length == 40' >/dev/null
apply_tc_limit 54559 8mbit
remove_nftables_quota 54558
remove_nftables_rules 54558
nft list counter inet dog_test port_54559_in >/dev/null
if nft list counter inet dog_test port_54558_in >/dev/null 2>&1; then exit 1; fi
echo 'PASS: IPv4/IPv6 packet classification, ranges/high ports and independent removal'
