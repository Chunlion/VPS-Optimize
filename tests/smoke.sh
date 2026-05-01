#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash -n vps.sh
bash -n dog.sh
bash -n xui-custom-manager.sh

source <(sed -n '1,91p' vps.sh)
[[ "$(trim_input "  q  ")" == "q" ]]
[[ "$(normalize_domain_input " HTTPS://Panel.Example.COM:443/path ")" == "panel.example.com" ]]

source <(sed -n '1,101p' dog.sh)
[[ "$(normalize_main_choice " add ")" == "1" ]]
[[ "$(normalize_main_choice "tg")" == "7" ]]
[[ "$(normalize_main_choice "q")" == "0" ]]

grep -q 'func_sni_stack_quick_menu' vps.sh
grep -q 'func_health_dashboard' vps.sh
grep -q 'func_backup_center' vps.sh
grep -q 'install_update_script' dog.sh

echo "Smoke tests passed."
