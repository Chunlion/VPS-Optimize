#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_file="${1:-$repo_root/src/traffic_guard.sh}"
dist_file="${2:-$repo_root/dist/vps.sh}"
tmp_dir=$(mktemp -d /tmp/vps-traffic-guard-template.XXXXXX)
src_template="$tmp_dir/src-checker.sh"
dist_template="$tmp_dir/dist-checker.sh"

cleanup() {
    rm -f "$src_template" 2>/dev/null || true
    rm -f "$dist_template" 2>/dev/null || true
    rmdir "$tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT

extract_guard_template() {
    local file="$1"
    local out="$2"
    [[ -f "$file" ]] || {
        printf 'Traffic Guard checker source is missing: %s\n' "$file" >&2
        exit 1
    }
    awk -v label="$file" '
        BEGIN {
            cr = sprintf("%c", 13)
        }
        {
            line = $0
            sub(cr "$", "", line)
        }
        index(line, "<<'\''GUARD_SCRIPT'\''") {
            if (seen) {
                printf "Traffic Guard checker template appears more than once in %s.\n", label > "/dev/stderr"
                err = 1
                exit 1
            }
            seen = 1
            in_template = 1
            next
        }
        in_template && line == "GUARD_SCRIPT" {
            in_template = 0
            closed = 1
            next
        }
        in_template {
            print
        }
        END {
            if (err) exit 1
            if (!seen) {
                printf "Traffic Guard checker template is missing in %s.\n", label > "/dev/stderr"
                exit 1
            }
            if (!closed) {
                printf "Traffic Guard checker template is not closed in %s.\n", label > "/dev/stderr"
                exit 1
            }
        }
    ' "$file" > "$out"
}

first_line_hex() {
    local file="$1"
    head -n 1 "$file" 2>/dev/null | LC_ALL=C od -An -tx1 | awk '{$1=$1; print}'
}

validate_guard_template() {
    local label="$1"
    local file="$2"
    local first_line

    [[ -s "$file" ]] || {
        printf 'Traffic Guard checker template in %s is empty.\n' "$label" >&2
        exit 1
    }
    if grep -q $'\r' "$file"; then
        printf 'Traffic Guard checker template in %s must use LF line endings, found CRLF.\n' "$label" >&2
        exit 1
    fi
    IFS= read -r first_line < "$file" || first_line=""
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
        printf 'Traffic Guard checker template in %s must start with #!/usr/bin/env bash; first-line bytes: %s\n' "$label" "$(first_line_hex "$file")" >&2
        exit 1
    fi
    if ! bash -n "$file"; then
        printf 'Traffic Guard checker template in %s failed bash syntax validation.\n' "$label" >&2
        exit 1
    fi
}

extract_guard_template "$src_file" "$src_template"
extract_guard_template "$dist_file" "$dist_template"
validate_guard_template "$src_file" "$src_template"
validate_guard_template "$dist_file" "$dist_template"

if ! cmp -s "$src_template" "$dist_template"; then
    printf 'Traffic Guard checker template drifted between %s and %s.\n' "$src_file" "$dist_file" >&2
    if command -v diff >/dev/null 2>&1; then
        diff -u "$src_template" "$dist_template" >&2 || true
    fi
    exit 1
fi
