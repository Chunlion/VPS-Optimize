# shellcheck shell=bash
# Main bootstrap. Feature implementation lives in the focused src/*.sh modules.

# --- Main entrypoint ---
main() {
    load_ui_language
    ensure_runtime_root
    prompt_initial_ui_language
    main_menu "$@"
}

main "$@"
