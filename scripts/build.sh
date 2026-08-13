#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/dist"
out_file="$out_dir/vps.sh"
modules_list="$repo_root/scripts/modules.list"
traffic_guard_checker_validator="$repo_root/scripts/validate-traffic-guard-checker.sh"
modules=()
compat_loader_owners=$(cat <<'EOF'
caddy_cert_tools|caddy_maintenance
caddy_cf_checks|caddy_maintenance
caddy_cf_menu|caddy_maintenance
caddy_cf_wizard|caddy_maintenance
caddy_stack_render|sni_stack_install
caddy_whitelist|caddy_maintenance
entry_mode_state|sni_stack_config
fail2ban|ssh_security
kernel_cleanup|kernel_tuning
kernel_install|kernel_tuning
network_performance|kernel_tuning
nginx_stream_render|sni_stack_install
sni_stack_apply|sni_stack_install
sni_stack_collect|sni_stack_install
sni_stack_deps|sni_stack_install
sni_stack_env_state|sni_stack_config
sni_stack_network_helpers|sni_stack_config
sni_stack_tcp_routes|sni_stack_sites
sni_stack_whitelist_state|sni_stack_config
ssh_auth_keys|ssh_security
ssh_menus|ssh_security
ssh_runtime|ssh_security
system_hosts|system_core
system_init|system_core
system_tweaks|system_core
xray_route_state|sni_stack_config
EOF
)
known_non_release_modules="$({
    printf '%s\n' "$compat_loader_owners" | cut -d'|' -f1
    printf '%s\n' subscription_tools
} | sort -u)"

load_modules() {
    local raw module
    [[ -f "$modules_list" ]] || {
        printf 'Missing module list: %s\n' "$modules_list" >&2
        exit 1
    }
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        module="${raw%%#*}"
        module="${module#"${module%%[![:space:]]*}"}"
        module="${module%"${module##*[![:space:]]}"}"
        [[ -n "$module" ]] || continue
        if [[ "$module" == *.sh ]]; then
            printf 'Module list entries must omit .sh: %s\n' "$module" >&2
            exit 1
        fi
        for existing in "${modules[@]}"; do
            if [[ "$existing" == "${module}.sh" ]]; then
                printf 'Duplicate module list entry: %s\n' "$module" >&2
                exit 1
            fi
        done
        modules+=("${module}.sh")
    done < "$modules_list"
    [[ ${#modules[@]} -gt 0 ]] || {
        printf 'Module list is empty: %s\n' "$modules_list" >&2
        exit 1
    }
}

module_list_names() {
    printf '%s\n' "${modules[@]}" | sed 's/\.sh$//'
}

assert_module_order() {
    local expected="$*"
    local actual
    actual="$(module_list_names | tr '\n' ' ')"
    case " $actual " in
        *" $expected "*) ;;
        *)
            printf 'Critical module order is invalid in scripts/modules.list; expected contiguous order: %s\n' "$expected" >&2
            exit 1
            ;;
    esac
}

validate_module_list_sync() {
    local release_modules src_modules known_modules missing_modules stale_allowlist module
    release_modules="$(module_list_names | sort -u)"
    src_modules="$(find "$repo_root/src" -maxdepth 1 -type f -name '*.sh' -exec basename {} .sh \; | sort)"
    known_modules="$(printf '%s\n%s\n' "$release_modules" "$known_non_release_modules" | sed '/^[[:space:]]*$/d' | sort -u)"
    missing_modules="$(comm -23 <(printf '%s\n' "$src_modules") <(printf '%s\n' "$known_modules"))"
    stale_allowlist="$(comm -23 <(printf '%s\n' "$known_non_release_modules" | sed '/^[[:space:]]*$/d' | sort -u) <(printf '%s\n' "$src_modules"))"

    if [[ -n "$missing_modules" ]]; then
        printf 'Source modules are not registered in scripts/modules.list:\n' >&2
        while IFS= read -r module; do
            [[ -n "$module" ]] && printf '  src/%s.sh\n' "$module" >&2
        done <<< "$missing_modules"
        printf 'Add release modules to scripts/modules.list in order, or classify compatibility-only files in scripts/build.sh.\n' >&2
        exit 1
    fi

    if [[ -n "$stale_allowlist" ]]; then
        printf 'Non-release module allowlist references missing src files:\n' >&2
        while IFS= read -r module; do
            [[ -n "$module" ]] && printf '  src/%s.sh\n' "$module" >&2
        done <<< "$stale_allowlist"
        exit 1
    fi

    assert_module_order common language ui input validate rollback backup runtime
    assert_module_order sni_stack_config vpso_mux_state vpso_mux_config vpso_mux_install tcp_peek_engine sni_stack_health
    assert_module_order panel_installers compose_runtime subscription_apps subscription_compose_manage subscription_service_menus dockge_migration panel_rescue
    assert_module_order menus main
}

validate_compat_loaders() {
    local loader owner loader_file source_count

    while IFS='|' read -r loader owner; do
        [[ -n "$loader" && -n "$owner" ]] || continue
        loader_file="$repo_root/src/${loader}.sh"
        [[ -f "$loader_file" ]] || {
            printf 'Missing compatibility loader: src/%s.sh\n' "$loader" >&2
            exit 1
        }
        if ! module_list_names | grep -Fxq "$owner"; then
            printf 'Compatibility loader owner is not a release module: %s -> %s\n' "$loader" "$owner" >&2
            exit 1
        fi
        if grep -Eq '^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{' "$loader_file"; then
            printf 'Compatibility loader must not define business functions: src/%s.sh\n' "$loader" >&2
            exit 1
        fi
        source_count=$(grep -Ec '^[[:space:]]*(source|\.)[[:space:]]+' "$loader_file" || true)
        if [[ "$source_count" != "1" ]] || ! grep -Fq "/${owner}.sh\"" "$loader_file"; then
            printf 'Compatibility loader must source only src/%s.sh: src/%s.sh\n' "$owner" "$loader" >&2
            exit 1
        fi
    done <<< "$compat_loader_owners"

    if grep -Eq '^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{' "$repo_root/src/subscription_tools.sh"; then
        printf 'Compatibility loader must not define business functions: src/subscription_tools.sh\n' >&2
        exit 1
    fi
}

mkdir -p "$out_dir"
load_modules
validate_module_list_sync
validate_compat_loaders

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
        sed '1{/^#!\/usr\/bin\/env bash$/d;}' "$repo_root/src/$module"
        printf '%s\n' ''
    done
} > "$out_file"

chmod +x "$out_file"
bash -n "$out_file"
bash "$traffic_guard_checker_validator" "$repo_root/src/traffic_guard.sh" "$out_file"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$out_dir" && printf '%s  %s\n' "$(sha256sum "$(basename "$out_file")" | awk '{print $1}')" "$(basename "$out_file")" > "$(basename "$out_file").sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$out_dir" && printf '%s  %s\n' "$(shasum -a 256 "$(basename "$out_file")" | awk '{print $1}')" "$(basename "$out_file")" > "$(basename "$out_file").sha256")
else
    printf 'Missing sha256sum/shasum; cannot write %s.sha256\n' "$out_file" >&2
    exit 1
fi
printf 'Built %s\n' "$out_file"
