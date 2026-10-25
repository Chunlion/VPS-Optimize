#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source src/input.sh
source src/validate.sh
source src/sni_stack_config.sh
source src/xhttp_path_routes.sh

fail() { echo "FAIL: $*" >&2; exit 1; }

# 菜单模块加载时只定义函数；确认依赖齐全时能完整加载并导出全部入口函数。
for vpso_fn in xhttp_path_mode_notice list_xhttp_path_routes add_xhttp_path_route remove_xhttp_path_route manage_xhttp_path_routes; do
    declare -F "$vpso_fn" >/dev/null || fail "xhttp_path_routes.sh did not define $vpso_fn"
done

PANEL_WEB_PATH=/panel/
SUB_URI_PATH=/sub/
CLASH_URI_PATH=/clash/

xhttp_paths_path() { echo "/tmp/vpso-xhttp-test.conf"; }

expect_path() {
    local input="$1" want="$2" got
    got=$(normalize_xhttp_path "$input" 2>/dev/null || true)
    [[ "$got" == "$want" ]] || fail "normalize '$input' => '$got', want '$want'"
}

expect_reject() {
    local input="$1" got
    got=$(normalize_xhttp_path "$input" 2>/dev/null || true)
    [[ -z "$got" ]] || fail "normalize '$input' should fail, got '$got'"
}

expect_path "/xhttp/" "/xhttp"
expect_path "xhttp" "/xhttp"
expect_path "/a/b" "/a/b"
expect_reject "/"
expect_reject "/a b"
expect_reject "/a?b"
expect_reject "/a#b"
expect_reject "/a/../b"

expect_conflict() {
    local candidate="$1" got
    got=$(xhttp_path_conflicts_with_web_paths "$candidate" || true)
    [[ -n "$got" ]] || fail "path '$candidate' should conflict"
}

expect_free() {
    local candidate="$1" got
    got=$(xhttp_path_conflicts_with_web_paths "$candidate" || true)
    [[ -z "$got" ]] || fail "path '$candidate' should not conflict, got '$got'"
}

expect_conflict "/panel"
expect_conflict "/panelx"
expect_conflict "/sub"
expect_conflict "/clash/abc"
expect_conflict "/p"
expect_free "/xhttp"
expect_free "/xhttpdl"

rm -f "$(xhttp_paths_path)"
XHTTP_PATH_DOMAINS=(panel.example.com site.example.com)
XHTTP_PATH_PATHS=(/xhttp /xhttpdl)
XHTTP_PATH_ADDRS=(127.0.0.1 127.0.0.1)
XHTTP_PATH_PORTS=(2400 2401)
save_xhttp_path_arrays || fail "save failed"
[[ -f "$(xhttp_paths_path)" ]] || fail "config file missing"

XHTTP_PATH_DOMAINS=()
XHTTP_PATH_PATHS=()
XHTTP_PATH_ADDRS=()
XHTTP_PATH_PORTS=()
load_xhttp_path_arrays
[[ "${XHTTP_PATH_DOMAINS[*]}" == "panel.example.com site.example.com" ]] || fail "domain round-trip failed: ${XHTTP_PATH_DOMAINS[*]}"
[[ "${XHTTP_PATH_PATHS[*]}" == "/xhttp /xhttpdl" ]] || fail "path round-trip failed: ${XHTTP_PATH_PATHS[*]}"
[[ "${XHTTP_PATH_PORTS[*]}" == "2400 2401" ]] || fail "port round-trip failed: ${XHTTP_PATH_PORTS[*]}"

rename_xhttp_path_domain panel.example.com new.example.com
[[ "${XHTTP_PATH_DOMAINS[0]}" == "new.example.com" ]] || fail "rename failed"

remove_xhttp_paths_for_domain new.example.com
[[ ${#XHTTP_PATH_DOMAINS[@]} -eq 1 ]] || fail "remove by domain failed"
[[ "${XHTTP_PATH_DOMAINS[0]}" == "site.example.com" ]] || fail "remove kept wrong entry"

rm -f "$(xhttp_paths_path)"
echo "xhttp path helpers passed."
