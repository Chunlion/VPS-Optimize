#!/usr/bin/env bash
set -euo pipefail
trap 'echo "selfcheck failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> build release artifact"
bash scripts/build.sh

echo "==> bash syntax"
for script in vps.sh dist/vps.sh dog.sh xui-custom-manager.sh src/*.sh scripts/*.sh tests/*.sh; do
    bash -n "$script"
done

echo "==> golden render"
bash tests/golden-render.sh
bash tests/xhttp-paths.sh
bash tests/sni-setup.sh
bash tests/sni-rollback.sh

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
elif [[ "${CI:-}" == "true" ]]; then
    echo "Go is required for vpso-mux selfcheck." >&2
    exit 1
else
    echo "Go not found; skipping vpso-mux go test/vet locally."
fi

if [[ -n "${GO_BIN:-}" ]]; then
    echo "==> go test"
    GOTOOLCHAIN=local "$GO_BIN" test ./...

    echo "==> go vet"
    GOTOOLCHAIN=local "$GO_BIN" vet ./...
fi

echo "==> compat smoke"
bash scripts/compat-smoke.sh

echo "==> full smoke"
bash tests/smoke.sh

echo "==> dist artifact checks"
if ! git diff --quiet -- dist/vps.sh dist/vps.sh.sha256; then
    if [[ "${CI:-}" == "true" ]]; then
        echo "dist artifacts changed after build; commit regenerated dist/vps.sh and dist/vps.sh.sha256." >&2
        git diff --name-only -- dist/vps.sh dist/vps.sh.sha256 >&2
        exit 1
    fi
    echo "dist artifacts have working-tree changes; include regenerated files when committing."
fi

echo "Selfcheck passed."
