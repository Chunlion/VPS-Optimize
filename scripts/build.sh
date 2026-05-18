#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/dist"
out_file="$out_dir/vps.sh"
modules=(
    common.sh   # constants, platform/package helpers, remote script execution
    ui.sh       # display helpers and high-risk confirmations
    input.sh    # input normalization and array splitting
    validate.sh # validation and normalization helpers
    rollback.sh # quarantine and restore helpers
    backup.sh   # backup center and backup helper functions
    runtime.sh  # root/runtime guard
    system_core.sh
    caddy_certificates.sh
    caddy_proxy.sh
    environment.sh
    caddy_legacy.sh
    sni_stack_config.sh
    vpso_mux_state.sh   # vpso-mux paths, engine state, and runtime status
    vpso_mux_config.sh  # vpso-mux YAML rendering
    vpso_mux_install.sh # vpso-mux binary/systemd helpers
    tcp_peek_engine.sh  # TCP Peek preflight and entry-mode switching
    sni_stack_health.sh
    sni_stack_profiles.sh
    sni_stack_install.sh
    sni_stack_sites.sh
    xray_sni_routes.sh
    sni_stack_menus.sh
    caddy_maintenance.sh
    ssh_security.sh
    docker_manage.sh
    kernel_tuning.sh
    diagnostics_status.sh
    diagnostics_network.sh
    panel_installers.sh
    compose_runtime.sh
    subscription_apps.sh
    subscription_compose_manage.sh
    subscription_service_menus.sh
    dockge_migration.sh
    panel_rescue.sh
    server_maintenance.sh
    updater.sh
    preflight.sh
    health_dashboard.sh
    dns_optimize.sh
    traffic_guard.sh
    network_interface.sh
    menus.sh
    main.sh     # bootstrap into menu wiring
)

mkdir -p "$out_dir"

{
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' ''
    printf '%s\n' '# ========================================================='
    printf '%s\n' '#  Project:  VPS Optimize'
    printf '%s\n' '#  Generated: scripts/build.sh'
    printf '%s\n' '#  Source modules: src/*.sh'
    printf '%s\n' '#  Compatibility marker: VPS 全能控制面板'
    printf '%s\n' '# ========================================================='
    printf '%s\n' ''

    for module in "${modules[@]}"; do
        [[ -f "$repo_root/src/$module" ]] || {
            printf 'Missing module: %s\n' "$module" >&2
            exit 1
        }
        printf '%s\n' '# ---------------------------------------------------------'
        printf '# Module: %s\n' "$module"
        printf '%s\n' '# ---------------------------------------------------------'
        sed '/^#!\/usr\/bin\/env bash$/d' "$repo_root/src/$module"
        printf '%s\n' ''
    done
} > "$out_file"

chmod +x "$out_file"
bash -n "$out_file"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$out_dir" && sha256sum "$(basename "$out_file")" > "$(basename "$out_file").sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$out_dir" && shasum -a 256 "$(basename "$out_file")" > "$(basename "$out_file").sha256")
else
    printf 'Missing sha256sum/shasum; cannot write %s.sha256\n' "$out_file" >&2
    exit 1
fi
printf 'Built %s\n' "$out_file"
