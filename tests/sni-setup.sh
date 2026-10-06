#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
source src/common.sh
source src/input.sh
source src/validate.sh
source src/sni_stack_config.sh
source src/sni_stack_install.sh
source src/reality_guard.sh
source src/tcp_peek_engine.sh
source src/caddy_maintenance.sh
localized_text() { printf '%s' "$1"; }

(
    nginx() { echo 'nginx version: nginx/1.25.1' >&2; }
    [[ "$(nginx_http_listen_directive ::1 8443)" == $'    listen [::1]:8443 ssl;\n    http2 on;' ]]
    nginx() { echo 'nginx version: nginx/1.25.0' >&2; }
    [[ "$(nginx_http_listen_directive 127.0.0.1 8443)" == '    listen 127.0.0.1:8443 ssl http2;' ]]
)

fixture_db="$tmp_dir/x-ui.db"
python3 - "$fixture_db" <<'PY'
import json, sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute('create table inbounds (id integer, port integer, remark text, stream_settings text, enable integer)')
for ident, names, enabled in [(1, ['www.example.org', 'example.org'], 1), (2, ['disabled.example.org'], 0)]:
    stream = {'security': 'reality', 'realitySettings': {'serverNames': names}}
    conn.execute('insert into inbounds values (?,1443,?,?,?)', (ident, 'fixture', json.dumps(stream), enabled))
conn.commit()
PY
(
    find_reality_guard_database() { echo "$fixture_db"; }
    XRAY_LISTEN_ADDR=127.0.0.1 XRAY_LISTEN_PORT=1443 REALITY_SNI=www.example.org
    PANEL_DOMAIN=panel.example.com
    SITE_DOMAINS=() TCP_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_SNIS=() XRAY_SNI_ROUTE_ADDRS=() XRAY_SNI_ROUTE_PORTS=()
    register_reality_server_name_routes
    [[ "${XRAY_SNI_ROUTE_SNIS[*]}" == example.org ]]
    [[ "${XRAY_SNI_ROUTE_ADDRS[*]}" == 127.0.0.1 && "${XRAY_SNI_ROUTE_PORTS[*]}" == 1443 ]]
    register_reality_server_name_routes
    [[ ${#XRAY_SNI_ROUTE_SNIS[@]} == 1 ]]
    XRAY_SNI_ROUTE_SNIS=() XRAY_SNI_ROUTE_ADDRS=() XRAY_SNI_ROUTE_PORTS=()
    SITE_DOMAINS=(example.org)
    if register_reality_server_name_routes >/dev/null; then
        echo 'Conflicting Web/REALITY routes must fail.' >&2; exit 1
    fi
    [[ ${#XRAY_SNI_ROUTE_SNIS[@]} == 0 ]]
)

python3 - "$fixture_db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute('alter table inbounds add column listen text')
conn.execute("update inbounds set listen='::1'")
conn.commit()
PY
(
    find_reality_guard_database() { echo "$fixture_db"; }
    XRAY_LISTEN_ADDR=127.0.0.1 XRAY_LISTEN_PORT=1443 REALITY_SNI=www.example.org
    PANEL_DOMAIN=panel.example.com SITE_DOMAINS=() TCP_ROUTE_SNIS=()
    XRAY_SNI_ROUTE_SNIS=() XRAY_SNI_ROUTE_ADDRS=() XRAY_SNI_ROUTE_PORTS=()
    if register_reality_server_name_routes >/dev/null; then
        echo 'Aliases must not be imported from an inbound on a different address.' >&2; exit 1
    fi
    [[ ${#XRAY_SNI_ROUTE_SNIS[@]} == 0 ]]
    XRAY_LISTEN_ADDR=::1
    register_reality_server_name_routes
    [[ "${XRAY_SNI_ROUTE_ADDRS[*]}" == ::1 ]]
)

(
    create_sni_stack_backup() { return 1; }
    cat() { echo 'Stale backup pointer must not be read.' >&2; exit 1; }
    if backup_entry_mode_config; then exit 1; fi
)

(
    get_listen_line_by_port() { echo 'LISTEN 127.0.0.1:1443 users:(("xray",pid=123,fd=4))'; }
    ps() { echo x-ui.service; }
    systemctl() {
        case "${@: -1}" in xray.service|x-ui.service) echo loaded ;; *) echo not-found ;; esac
    }
    [[ "$(xray_entry_service_name)" == x-ui ]]
    if systemd_unit_exists missing.service; then exit 1; fi
    get_listen_line_by_port() { :; }
    if xray_entry_service_name >/dev/null; then
        echo 'Multiple Xray services must not be selected by name priority.' >&2; exit 1
    fi
)

(
    install_nginx_stream_stack() { :; }
    harden_nginx_public_errors() { :; }
    apply_web_proxy_configs_for_single_443() { :; }
    cleanup_old_nginx_sni_stream_configs() { :; }
    write_nginx_sni_stream_config() { :; }
    assert_nginx_stream_config_loaded() { :; }
    current_web_proxy_engine() { echo nginx; }
    systemctl() { :; }
    verify_public_443_listener_for_mode() { :; }
    probe_tls_sni_certificate() { :; }
    tcp_probe_host() { :; }
    probe_host_for_listen_addr() { echo "$1"; }
    web_proxy_engine_label() { echo Nginx; }
    write_single_443_engine_state() { :; }
    restart_xray_entry_service() { printf '%s\n' "$1" >> "$tmp_dir/restarts"; }
    NGINX_LISTEN_ADDR=0.0.0.0 NGINX_LISTEN_PORT=443 PANEL_DOMAIN=panel.example.com
    CADDY_LISTEN_ADDR=127.0.0.1 CADDY_LISTEN_PORT=8443
    XRAY_LISTEN_ADDR=127.0.0.1 XRAY_LISTEN_PORT=1443
    XRAY_ENTRY_STOPPED_SERVICE=""
    apply_nginx_stream_mode
    [[ ! -f "$tmp_dir/restarts" ]]
    XRAY_ENTRY_STOPPED_SERVICE=x-ui
    apply_nginx_stream_mode
    [[ "$(cat "$tmp_dir/restarts")" == x-ui ]]
)

(
    sni_stack_env_path() { echo "$tmp_dir/sni-stack.env"; }
    xray_sni_routes_path() { echo "$tmp_dir/routes"; }
    ENTRY_MODE=nginx-stream WEB_PROXY_ENGINE=nginx STRICT_SNI_GATE=true
    PANEL_DOMAIN=panel.example.com REALITY_SNI=www.example.org
    NGINX_LISTEN_ADDR=0.0.0.0 NGINX_LISTEN_PORT=443
    CADDY_LISTEN_ADDR=127.0.0.1 CADDY_LISTEN_PORT=8443
    XRAY_LISTEN_ADDR=127.0.0.1 XRAY_LISTEN_PORT=1443
    PANEL_LISTEN_ADDR=127.0.0.1 PANEL_LISTEN_PORT=40000 PANEL_WEB_PATH=/panel/
    SUB_LISTEN_ADDR=127.0.0.1 SUB_LISTEN_PORT=2096 SUB_URI_PATH=/sub/ CLASH_URI_PATH=/clash/
    SITE_DOMAINS=() SITE_BACKEND_ADDRS=() SITE_BACKEND_PORTS=()
    TCP_ROUTE_SNIS=() TCP_ROUTE_ADDRS=() TCP_ROUTE_PORTS=()
    SNI_IP_WHITELIST_DOMAINS=() SNI_IP_WHITELIST_RANGES=()
    XRAY_SNI_ROUTE_SNIS=(example.org) XRAY_SNI_ROUTE_ADDRS=(127.0.0.1) XRAY_SNI_ROUTE_PORTS=(1443)
    save_sni_stack_env
    [[ "$(cat "$tmp_dir/routes")" == 'example.org|127.0.0.1|1443' ]]
    [[ "$(stat -c %a "$tmp_dir/sni-stack.env")" == 600 ]]
    cp "$tmp_dir/sni-stack.env" "$tmp_dir/original.env"
    PANEL_DOMAIN=changed.example.com
    mv() { return 1; }
    if save_sni_stack_env; then exit 1; fi
    cmp "$tmp_dir/original.env" "$tmp_dir/sni-stack.env"
    [[ -z "$(find "$tmp_dir" -name '*.tmp.*' -print)" ]]
)

(
    wizard_definition=$(declare -f func_caddy_cf_reality_wizard)
    wizard_definition=${wizard_definition//\/root\/.config\/vps-panel/$tmp_dir/cf}
    wizard_definition=${wizard_definition//\/etc\/vps-optimize\/sni-stack.env/$tmp_dir/no-existing.env}
    eval "$wizard_definition"
    select_initial_entry_mode() { ENTRY_MODE=nginx-stream; }
    collect_sni_stack_config() { CF_TOKEN=fixture; REALITY_SNI=www.example.org; STRICT_SNI_GATE=true; }
    load_xray_sni_route_arrays() { :; }
    register_reality_server_name_routes() { return 1; }
    backup_entry_mode_config() { echo touched >> "$tmp_dir/backup-called"; echo "$tmp_dir/backup"; }
    if func_caddy_cf_reality_wizard; then exit 1; fi
    [[ ! -f "$tmp_dir/backup-called" && ! -d "$tmp_dir/cf" ]]
    register_reality_server_name_routes() { :; }
    probe_reality_sni() { :; }
    print_sni_stack_preview() { :; }
    guard_current_ssh_not_on_entry_port() { :; }
    rollback_sni_stack_after_failure() { echo rollback >> "$tmp_dir/rollback-called"; return 1; }
    prepare_initial_entry_mode_dependencies() { kill -HUP "$BASHPID"; }
    if func_caddy_cf_reality_wizard; then exit 1; else [[ $? == 129 ]]; fi
    [[ "$(cat "$tmp_dir/rollback-called")" == rollback ]]
    rm "$tmp_dir/rollback-called"
    prepare_initial_entry_mode_dependencies() { :; }
    quarantine_legacy_caddy_443_configs() { :; }
    quarantine_legacy_nginx_https_proxy_configs() { :; }
    issue_and_install_cert_for_domain() { :; }
    preflight_entry_mode_before_cutover() { :; }
    stop_public_443_entry_services_for_target() { :; }
    apply_entry_mode_by_name() { :; }
    save_sni_stack_env() { return 1; }
    SITE_DOMAINS=() PANEL_DOMAIN=panel.example.com
    if func_caddy_cf_reality_wizard; then exit 1; fi
    [[ "$(cat "$tmp_dir/rollback-called")" == rollback ]]
)
echo 'SNI setup regression checks passed.'
