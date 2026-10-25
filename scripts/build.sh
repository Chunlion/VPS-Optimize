#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/dist"
out_file="$out_dir/vps.sh"
modules_list="$repo_root/scripts/modules.list"
traffic_guard_checker_validator="$repo_root/scripts/validate-traffic-guard-checker.sh"
modules=()
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
        modules+=("${module%.sh}.sh")
    done < "$modules_list"
    [[ ${#modules[@]} -gt 0 ]] || {
        printf 'Module list is empty: %s\n' "$modules_list" >&2
        exit 1
    }
}

mkdir -p "$out_dir"
load_modules

# 防止新增真实模块忘记登记：非 Compatibility loader stub 的 src 模块必须出现在模块清单里。
check_module_list_coverage() {
    local src_file module_name listed
    for src_file in "$repo_root"/src/*.sh; do
        grep -q 'Compatibility loader' "$src_file" && continue
        module_name="$(basename "$src_file" .sh)"
        listed=0
        for module in "${modules[@]}"; do
            if [[ "$module" == "${module_name}.sh" ]]; then
                listed=1
                break
            fi
        done
        [[ "$listed" -eq 1 ]] || {
            printf 'src/%s.sh is not a stub but missing from %s\n' "$module_name" "$modules_list" >&2
            exit 1
        }
    done
}
check_module_list_coverage

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
bash "$traffic_guard_checker_validator" "$repo_root/src/traffic_guard.sh"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$out_dir" && printf '%s  %s\n' "$(sha256sum "$(basename "$out_file")" | awk '{print $1}')" "$(basename "$out_file")" > "$(basename "$out_file").sha256")
elif command -v shasum >/dev/null 2>&1; then
    (cd "$out_dir" && printf '%s  %s\n' "$(shasum -a 256 "$(basename "$out_file")" | awk '{print $1}')" "$(basename "$out_file")" > "$(basename "$out_file").sha256")
else
    printf 'Missing sha256sum/shasum; cannot write %s.sha256\n' "$out_file" >&2
    exit 1
fi
printf 'Built %s\n' "$out_file"
