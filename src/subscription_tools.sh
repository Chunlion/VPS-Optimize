# shellcheck shell=bash
# Compatibility loader for the split subscription-tool modules.
#
# scripts/build.sh includes the focused modules directly. Keep this file as a
# thin source-compatible entry point so manual `source src/subscription_tools.sh`
# still loads the same public functions without duplicating implementations.

_subscription_tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _subscription_tools_module in \
    compose_runtime.sh \
    subscription_apps.sh \
    subscription_service_menus.sh \
    dockge_migration.sh
do
    # shellcheck source=/dev/null
    source "${_subscription_tools_dir}/${_subscription_tools_module}"
done
unset _subscription_tools_dir _subscription_tools_module
