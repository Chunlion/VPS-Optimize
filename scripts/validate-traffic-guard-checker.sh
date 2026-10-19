#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_file="${1:-$repo_root/src/traffic_guard.sh}"

# Validate the checker template embedded in src/traffic_guard.sh's
# <<'GUARD_SCRIPT' heredoc. dist/vps.sh is a concatenation of the src modules,
# so the template is identical there by construction; no comparison needed.
tmp_file=$(mktemp /tmp/vps-traffic-guard-template.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT

awk -v marker="<<'GUARD_SCRIPT'" '
    index($0, marker) {
        if (seen) {
            printf "Traffic Guard checker template appears more than once in %s.\n", FILENAME > "/dev/stderr"
            exit 1
        }
        seen = 1
        next
    }
    seen && $0 == "GUARD_SCRIPT" { closed = 1; exit }
    seen { print }
    END {
        if (!seen) {
            printf "Traffic Guard checker template is missing in %s.\n", FILENAME > "/dev/stderr"
            exit 1
        }
        if (!closed) {
            printf "Traffic Guard checker template is not closed in %s.\n", FILENAME > "/dev/stderr"
            exit 1
        }
    }
' "$src_file" > "$tmp_file"

[[ -s "$tmp_file" ]] || {
    printf 'Traffic Guard checker template in %s is empty.\n' "$src_file" >&2
    exit 1
}
if grep -q $'\r' "$tmp_file"; then
    printf 'Traffic Guard checker template in %s must use LF line endings.\n' "$src_file" >&2
    exit 1
fi
first_line=$(head -n 1 "$tmp_file" 2>/dev/null || true)
if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
    printf 'Traffic Guard checker template in %s must start with #!/usr/bin/env bash.\n' "$src_file" >&2
    exit 1
fi
if ! bash -n "$tmp_file"; then
    printf 'Traffic Guard checker template in %s failed bash syntax validation.\n' "$src_file" >&2
    exit 1
fi
