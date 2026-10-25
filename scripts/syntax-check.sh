#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for script in vps.sh dist/vps.sh dog.sh xui-custom-manager.sh src/*.sh scripts/*.sh tests/*.sh; do
    bash -n "$script"
done
