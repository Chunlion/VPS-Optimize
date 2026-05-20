#!/usr/bin/env bash

# Source entrypoint for repository checkouts.
# Build scripts/build.sh to produce the release single-file dist/vps.sh.
# Compatibility marker for legacy updater: VPS 全能控制面板

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh"
MODULES=(
    common
    ui
    input
    validate
    rollback
    backup
    runtime
    system_core
    firewall
    caddy_certificates
    caddy_proxy
    environment
    caddy_legacy
    sni_stack_config
    vpso_mux_state
    vpso_mux_config
    vpso_mux_install
    tcp_peek_engine
    sni_stack_health
    sni_stack_profiles
    sni_stack_install
    sni_stack_sites
    xray_sni_routes
    sni_stack_menus
    caddy_maintenance
    ssh_security
    docker_manage
    kernel_tuning
    diagnostics_status
    diagnostics_network
    panel_installers
    subscription_tools
    panel_rescue
    server_maintenance
    updater
    preflight
    health_dashboard
    dns_optimize
    traffic_guard
    network_interface
    menus
    main
)

download_release_script() {
    local output_file="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 90 --retry 2 --retry-delay 1 --retry-connrefused "$RELEASE_URL" -o "$output_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 --tries=3 -O "$output_file" "$RELEASE_URL"
    else
        echo "Missing curl/wget, cannot download release script." >&2
        return 1
    fi
    [[ -s "$output_file" ]]
}

switch_to_release_script() {
    local tmp_file self_path
    tmp_file=$(mktemp /tmp/vps-optimize-release.XXXXXX.sh) || {
        echo "Failed to create temporary release script." >&2
        return 1
    }

    echo "Source modules are missing; switching to the generated release script..." >&2
    if ! download_release_script "$tmp_file"; then
        rm -f "$tmp_file"
        echo "Failed to download release script: $RELEASE_URL" >&2
        return 1
    fi
    if ! bash -n "$tmp_file" >/dev/null 2>&1; then
        rm -f "$tmp_file"
        echo "Downloaded release script did not pass bash syntax check." >&2
        return 1
    fi
    if ! grep -q 'func_sni_stack_quick_menu' "$tmp_file" || ! grep -q 'main_menu' "$tmp_file"; then
        rm -f "$tmp_file"
        echo "Downloaded release script did not look complete." >&2
        return 1
    fi

    chmod +x "$tmp_file" 2>/dev/null || true
    self_path="$0"
    if [[ -f "$self_path" && -w "$self_path" ]]; then
        mv "$tmp_file" "$self_path"
        chmod +x "$self_path" 2>/dev/null || true
        exec bash "$self_path" "$@"
    fi

    exec bash "$tmp_file" "$@"
}

missing_module=0
for module in "${MODULES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/src/${module}.sh" ]]; then
        echo "Missing source module: src/${module}.sh" >&2
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
