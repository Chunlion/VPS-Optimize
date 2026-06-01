#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/dist"
out_file="$out_dir/vps.sh"
modules_list="$repo_root/scripts/modules.list"
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
        if [[ "$module" == *.sh ]]; then
            printf 'Module list entries must omit .sh: %s\n' "$module" >&2
            exit 1
        fi
        modules+=("${module}.sh")
    done < "$modules_list"
    [[ ${#modules[@]} -gt 0 ]] || {
        printf 'Module list is empty: %s\n' "$modules_list" >&2
        exit 1
    }
}

mkdir -p "$out_dir"
load_modules

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
