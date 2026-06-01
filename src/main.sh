# shellcheck shell=bash
# Main bootstrap. Feature implementation lives in the focused src/*.sh modules.

# --- Main entrypoint ---
main() {
    ensure_runtime_root
    main_menu "$@"
}

main "$@"
