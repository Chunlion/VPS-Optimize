# shellcheck shell=bash
# Compatibility loader; release implementation is owned by ssh_security.sh.

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssh_security.sh"
