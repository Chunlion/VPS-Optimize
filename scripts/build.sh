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
    main.sh     # feature implementation and menu wiring
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
