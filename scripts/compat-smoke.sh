#!/usr/bin/env bash
set -euo pipefail
trap 'echo "compat-smoke failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local message="${3:-${file} is missing required content: ${needle}}"
    if ! grep -Fq -- "$needle" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local message="${3:-${file} contains forbidden content: ${needle}}"
    if grep -Fq -- "$needle" "$file"; then
        echo "$message" >&2
        exit 1
    fi
}

compat_tmp_dir=$(mktemp -d /tmp/vps-compat-smoke.XXXXXX)
trap 'rm -rf -- "$compat_tmp_dir"' EXIT

source src/common.sh
VPSO_LANGUAGE_CONFIG="$compat_tmp_dir/language.conf"
source src/language.sh
source src/ui.sh
source src/input.sh
source src/validate.sh
source src/kernel_tuning.sh
source src/system_core.sh
source src/dns_optimize.sh

(
    OS=debian
    OS_LIKE=""
    APT_UPDATED=0
    update_rc=100
    install_rc=0
    pkg_log_file() { printf '%s\n' "$compat_tmp_dir/pkg-install.log"; }
    apt-get() {
        printf '%s\n' "$1" >> "$compat_tmp_dir/apt-calls"
        case "$1" in
            update)
                if [[ "$update_rc" -ne 0 ]]; then
                    echo 'E: Could not get lock /var/lib/apt/lists/lock. It is held by process 3814 (apt)' >&2
                fi
                return "$update_rc"
                ;;
            install) return "$install_rc" ;;
        esac
    }

    if install_pkg sqlite3 > "$compat_tmp_dir/pkg-output" 2>&1; then
        echo "install_pkg must fail when apt update fails." >&2
        exit 1
    else
        [[ "$?" -eq 100 ]]
    fi
    [[ "$(cat "$compat_tmp_dir/apt-calls")" == update ]]
    [[ "$APT_UPDATED" == 0 ]]
    [[ -z "${DEBIAN_FRONTEND+x}" ]]
    grep -Fq 'held by process 3814 (apt)' "$compat_tmp_dir/pkg-install.log"
    grep -Fq 'held by process 3814 (apt)' "$compat_tmp_dir/pkg-output"

    update_rc=0
    : > "$compat_tmp_dir/apt-calls"
    install_pkg sqlite3 > "$compat_tmp_dir/pkg-output" 2>&1
    [[ "$(cat "$compat_tmp_dir/apt-calls")" == $'update\ninstall' ]]
    [[ "$APT_UPDATED" == 1 ]]
    [[ ! -e "$compat_tmp_dir/pkg-install.log" ]]

    : > "$compat_tmp_dir/apt-calls"
    install_rc=42
    if install_pkg sqlite3 > "$compat_tmp_dir/pkg-output" 2>&1; then
        echo "install_pkg must preserve apt install failures." >&2
        exit 1
    else
        [[ "$?" -eq 42 ]]
    fi
    [[ "$(cat "$compat_tmp_dir/apt-calls")" == install ]]
)

[[ "$(localized_text "中文" "English")" == "中文" ]]
save_ui_language en
[[ "$VPSO_LANGUAGE" == "en" ]]
[[ "$(localized_text "中文" "English")" == "English" ]]
[[ "$(cat "$VPSO_LANGUAGE_CONFIG")" == "LANGUAGE=en" ]]
VPSO_LANGUAGE="zh"
load_ui_language
[[ "$VPSO_LANGUAGE" == "en" ]]
select_ui_language initial <<<"3" >/dev/null
[[ "$VPSO_LANGUAGE" == "ru" ]]
[[ "$(localized_text "中文" "English" "Русский")" == "Русский" ]]
[[ "$(cat "$VPSO_LANGUAGE_CONFIG")" == "LANGUAGE=ru" ]]

tailscale() {
    return 1
}
printf '%s\n' 'nameserver 100.100.100.100' > "$compat_tmp_dir/tailscale-resolv.conf"
dns_disable_tailscale_dns "$compat_tmp_dir/tailscale-resolv.conf" >/dev/null
unset -f tailscale

compat_menu_handler_called=0
compat_menu_handler() {
    compat_menu_handler_called=1
}
COMPAT_MENU_ITEMS=(
    "1|Compat check|No-op handler|compat_menu_handler|"
)
render_output=$(render_menu COMPAT_MENU_ITEMS)
[[ "$render_output" == *"Compat check"* ]]
if dispatch_menu_choice "invalid" COMPAT_MENU_ITEMS; then
    echo "dispatch_menu_choice must reject invalid input without dispatching." >&2
    exit 1
fi
[[ "$compat_menu_handler_called" == "0" ]]

rotate_log_file "$compat_tmp_dir/missing.log" 1 3
touch "$compat_tmp_dir/empty.log"
rotate_log_file "$compat_tmp_dir/empty.log" 1 3
[[ -f "$compat_tmp_dir/empty.log" ]]
[[ ! -e "$compat_tmp_dir/empty.log.1" ]]

printf 'abc' > "$compat_tmp_dir/small.log"
rotate_log_file "$compat_tmp_dir/small.log" 10 3
[[ -f "$compat_tmp_dir/small.log" ]]
[[ ! -e "$compat_tmp_dir/small.log.1" ]]

printf 'abcdef' > "$compat_tmp_dir/large.log"
rotate_log_file "$compat_tmp_dir/large.log" 4 3
[[ ! -e "$compat_tmp_dir/large.log" ]]
[[ -f "$compat_tmp_dir/large.log.1" ]]

[[ -n "$(format_bytes 0)" ]]
[[ -n "$(format_bytes 1024)" ]]
[[ -n "$(format_bytes 1048576)" ]]
gai_test_file="$compat_tmp_dir/gai.conf"
printf '%s\n' '#precedence ::ffff:0:0/96  10' 'precedence ::ffff:0:0/96  50' 'precedence ::ffff:0:0/96  100' > "$gai_test_file"
configure_ipv4_preference "$gai_test_file"
ipv4_preference_is_enabled "$gai_test_file"
[[ "$(grep -Ec '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100$' "$gai_test_file")" == "1" ]]
assert_file_contains "$gai_test_file" '#precedence ::ffff:0:0/96  10'
assert_file_not_contains "$gai_test_file" 'precedence ::ffff:0:0/96  50'
configure_ipv4_preference "$gai_test_file"
[[ "$(grep -Ec '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100$' "$gai_test_file")" == "1" ]]
restore_default_ip_preference "$gai_test_file"
assert_file_not_contains "$gai_test_file" 'precedence ::ffff:0:0/96  100'
[[ "$(find "$compat_tmp_dir" -maxdepth 1 -type f -name 'gai.conf.bak_*' | wc -l)" == "2" ]]
[[ "$(bbr_direct_buffer_mb 100 near)" == "8" ]]
[[ "$(bbr_direct_buffer_mb 1000 near)" == "16" ]]
[[ "$(bbr_direct_buffer_mb 1000 long)" == "64" ]]
[[ "$(extract_speedtest_upload_mbps 'Upload: 123.45 Mbit/s')" == "123" ]]
[[ "$(extract_speedtest_upload_mbps 'Upload: 1.25 Gbit/s')" == "1250" ]]
[[ "$(extract_speedtest_download_mbps 'Download: 850.6 Mbps')" == "851" ]]
[[ "$(extract_speedtest_latency_ms 'Latency: 12.6 ms (0.8 ms jitter)')" == "13" ]]
(
    PATH="$compat_tmp_dir"
    MOCK_SPEEDTEST_VERSION='Speedtest by Ookla 1.2.0'
    speedtest() {
        if [[ "$1" == '--version' ]]; then
            printf '%s\n' "$MOCK_SPEEDTEST_VERSION"
        else
            printf 'speedtest %s\n' "$*"
            return "${MOCK_SPEEDTEST_RC:-0}"
        fi
    }
    speedtest-cli() { printf 'speedtest-cli %s\n' "$*"; }
    [[ "$(run_speedtest_client)" == 'speedtest --accept-license --accept-gdpr' ]]
    MOCK_SPEEDTEST_VERSION='speedtest-cli 2.1.3'
    [[ "$(run_speedtest_client)" == 'speedtest --secure' ]]
    MOCK_SPEEDTEST_RC=23
    if run_speedtest_client >/dev/null; then exit 1; else [[ "$?" == 23 ]]; fi
    unset -f speedtest
    [[ "$(run_speedtest_client)" == 'speedtest-cli --secure' ]]
    unset -f speedtest-cli
    if run_speedtest_client; then exit 1; else [[ "$?" == 127 ]]; fi
)
(
    source src/diagnostics_network.sh
    clear() { :; }
    print_breadcrumb() { :; }
    pause_return() { :; }
    ensure_speedtest_client() { return 0; }
    run_speedtest_client() { return "$MOCK_TEST_RC"; }
    MOCK_TEST_RC=23
    if func_server_bandwidth_test >/dev/null; then exit 1; else [[ "$?" == 23 ]]; fi
    MOCK_TEST_RC=0
    func_server_bandwidth_test >/dev/null

    iperf3() { IPERF_ARGS="$*"; return "$MOCK_TEST_RC"; }
    IPERF_ARGS=''
    func_iperf3_single_thread_test >/dev/null <<< $'[2001:db8::1]\n5201\n2\n08'
    [[ "$IPERF_ARGS" == '-c 2001:db8::1 -p 5201 -P 1 -t 8 -f m -R' ]]
    IPERF_ARGS=''
    if func_iperf3_single_thread_test >/dev/null <<< $'test.example.com\n5201\n1\n0301'; then
        exit 1
    fi
    [[ -z "$IPERF_ARGS" ]]
    MOCK_TEST_RC=17
    if func_iperf3_single_thread_test >/dev/null <<< $'test.example.com\n\n\n'; then
        exit 1
    else
        [[ "$?" == 17 ]]
    fi
    [[ "$IPERF_ARGS" == '-c test.example.com -p 5201 -P 1 -t 30 -f m' ]]
)
[[ "$(bbr_direct_buffer_mb_for_rtt 100 80)" == "8" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 1000 80)" == "20" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 1000 250)" == "60" ]]
[[ "$(bbr_direct_buffer_mb_for_rtt 10000 300)" == "64" ]]
[[ "$(bbr_direct_queue_values 100 80)" == "131072|2048|4096|5000|16384" ]]
[[ "$(bbr_direct_queue_values 2000 200)" == "524288|8192|16384|20000|65536" ]]
bbr_candidate="$compat_tmp_dir/bbr-direct.conf"
write_bbr_direct_candidate "$bbr_candidate" 2000 200 64
assert_file_contains "$bbr_candidate" 'net.core.rmem_default = 524288'
assert_file_contains "$bbr_candidate" 'net.ipv4.tcp_moderate_rcvbuf = 1'
assert_file_contains "$bbr_candidate" 'net.core.somaxconn = 8192'
assert_file_contains "$bbr_candidate" 'net.core.netdev_max_backlog = 20000'
assert_file_contains "$bbr_candidate" 'net.ipv4.tcp_notsent_lowat = 65536'
if bbr_direct_buffer_mb_for_rtt 100001 80 >/dev/null 2>&1; then
    echo "BBR buffer sizing must reject unreasonable bandwidth values." >&2
    exit 1
fi
bbr_verify="$compat_tmp_dir/bbr-verify.conf"
printf 'net.test.values = 1 2 3\n' > "$bbr_verify"
sysctl() {
    [[ "$1" == "-n" && "$2" == "net.test.values" ]] || return 1
    printf '1\t2  3\n'
}
sysctl_tune_verify_file "$bbr_verify"
unset -f sysctl
read_trimmed() {
    printf -v "$1" '%s' "${MOCK_TRIMMED_VALUE:-}"
}
ensure_speedtest_client() { return 0; }
run_speedtest_client() {
    printf '%s\n' 'Latency: 20.4 ms' 'Download: 900.2 Mbps' 'Upload: 1.25 Gbit/s'
}
MOCK_TRIMMED_VALUE=1
[[ "$(prompt_bbr_measurement 2>/dev/null)" == "1250|20|900" ]]
MOCK_TRIMMED_VALUE=4
[[ "$(prompt_bbr_rtt_ms 20 2>/dev/null)" == "20" ]]
unset MOCK_TRIMMED_VALUE

echo "Compatibility smoke passed."
