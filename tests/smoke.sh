#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash -n vps.sh
bash -n dog.sh
bash -n xui-custom-manager.sh

dangerous_patterns='rm -rf|rm -r[[:space:]]|wget .*[&][&]|curl .*\|[[:space:]]*gpg|\|[[:space:]]*bash|bash[[:space:]]*<'
if grep -En "$dangerous_patterns" vps.sh dog.sh; then
    echo "Dangerous shell patterns found." >&2
    exit 1
fi

source <(sed -n '1,91p' vps.sh)
[[ "$(trim_input "  q  ")" == "q" ]]
[[ "$(normalize_domain_input " HTTPS://Panel.Example.COM:443/path ")" == "panel.example.com" ]]

source <(sed -n '1,411p' dog.sh)
[[ "$(normalize_main_choice " add ")" == "1" ]]
[[ "$(normalize_main_choice "tg")" == "7" ]]
[[ "$(normalize_main_choice "q")" == "0" ]]
[[ "$(format_bytes "")" == "0B" ]]
[[ "$(format_bytes 1023)" == "1023B" ]]
declare -f sanitize_nftables_config >/dev/null
declare -f update_telegram_config >/dev/null

grep -q 'func_sni_stack_quick_menu' vps.sh
grep -q 'func_health_dashboard' vps.sh
grep -q 'func_backup_center' vps.sh
grep -q 'install_update_script' dog.sh

echo "Smoke tests passed."
