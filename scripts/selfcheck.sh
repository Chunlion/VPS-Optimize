#!/usr/bin/env bash
set -euo pipefail
trap 'echo "selfcheck failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> build release artifact"
bash scripts/build.sh

echo "==> bash syntax"
bash -n scripts/build.sh scripts/selfcheck.sh scripts/compat-smoke.sh scripts/validate-traffic-guard-checker.sh tests/golden-render.sh tests/smoke.sh
bash -n vps.sh dist/vps.sh dog.sh xui-custom-manager.sh
for module in src/*.sh; do
    bash -n "$module"
done

echo "==> golden render"
bash tests/golden-render.sh

echo "==> docs build"
npm run build

echo "==> shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S error vps.sh src/*.sh scripts/*.sh dist/vps.sh dog.sh xui-custom-manager.sh
else
    if [[ "${CI:-}" == "true" ]]; then
        echo "shellcheck not found; CI must install shellcheck before running selfcheck." >&2
        exit 1
    fi
    echo "shellcheck not found; skipped locally. CI installs shellcheck before running selfcheck."
fi

if command -v go >/dev/null 2>&1; then
    GO_BIN=go
elif command -v go.exe >/dev/null 2>&1; then
    GO_BIN=go.exe
else
    echo "Go is required for vpso-mux selfcheck." >&2
    exit 1
fi

echo "==> go test"
GOTOOLCHAIN=local "$GO_BIN" test ./...

echo "==> go vet"
GOTOOLCHAIN=local "$GO_BIN" vet ./...

echo "==> compat smoke"
bash scripts/compat-smoke.sh

echo "==> full smoke"
bash tests/smoke.sh

echo "==> dist artifact checks"
git diff --check -- dist/vps.sh dist/vps.sh.sha256
if ! git diff --quiet -- dist/vps.sh dist/vps.sh.sha256; then
    if [[ "${CI:-}" == "true" ]]; then
        echo "dist artifacts changed after build; commit regenerated dist/vps.sh and dist/vps.sh.sha256." >&2
        git diff --name-only -- dist/vps.sh dist/vps.sh.sha256 >&2
        exit 1
    fi
    echo "dist artifacts have working-tree changes; include regenerated files when committing."
fi

echo "==> release markers"
grep -Fq '# Module: common.sh' dist/vps.sh
grep -Fq '# Module: vpso_mux_state.sh' dist/vps.sh
grep -Fq '# Module: health_dashboard.sh' dist/vps.sh
grep -Fq '# Module: traffic_guard.sh' dist/vps.sh
grep -Fq 'main_menu' dist/vps.sh
grep -Fq 'VPS 全能控制面板' dist/vps.sh

echo "Selfcheck passed."
