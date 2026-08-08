# shellcheck shell=bash
# Persistent language selection and localized text helpers.

VPSO_LANGUAGE_CONFIG="${VPSO_LANGUAGE_CONFIG:-/etc/vps-optimize/language.conf}"
VPSO_LANGUAGE="zh"
VPSO_LANGUAGE_CONFIGURED=0

normalize_ui_language() {
    case "${1,,}" in
        en|en_us|en-us|english) printf 'en' ;;
        ru|ru_ru|ru-ru|russian|русский) printf 'ru' ;;
        zh|zh_cn|zh-cn|chinese|中文|简体中文) printf 'zh' ;;
        *) return 1 ;;
    esac
}

load_ui_language() {
    local configured="${VPSO_LANG:-}"
    VPSO_LANGUAGE_CONFIGURED=0
    if [[ -z "$configured" && -r "$VPSO_LANGUAGE_CONFIG" ]]; then
        configured=$(sed -n 's/^[[:space:]]*LANGUAGE[[:space:]]*=[[:space:]]*//p' "$VPSO_LANGUAGE_CONFIG" | tail -n 1)
        configured="${configured%\"}"
        configured="${configured#\"}"
        configured="${configured%\'}"
        configured="${configured#\'}"
    fi
    if VPSO_LANGUAGE=$(normalize_ui_language "$configured"); then
        VPSO_LANGUAGE_CONFIGURED=1
    else
        VPSO_LANGUAGE="zh"
    fi
}

save_ui_language() {
    local language config_dir tmp_file
    language=$(normalize_ui_language "$1") || return 1
    config_dir=$(dirname "$VPSO_LANGUAGE_CONFIG")
    mkdir -p "$config_dir" || return 1
    tmp_file=$(mktemp "${config_dir}/.language.conf.XXXXXX") || return 1
    if ! printf 'LANGUAGE=%s\n' "$language" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    chmod 600 "$tmp_file" 2>/dev/null || true
    if ! mv -f "$tmp_file" "$VPSO_LANGUAGE_CONFIG"; then
        rm -f "$tmp_file"
        return 1
    fi
    VPSO_LANGUAGE="$language"
    VPSO_LANGUAGE_CONFIGURED=1
}

localized_text() {
    local zh="$1"
    local en="$2"
    local ru="${3:-$en}"
    case "$VPSO_LANGUAGE" in
        en) printf '%s' "$en" ;;
        ru) printf '%s' "$ru" ;;
        *) printf '%s' "$zh" ;;
    esac
}

localized_echo() {
    echo -e "$(localized_text "$@")"
}

select_ui_language() {
    local mode="${1:-menu}"
    local choice target prompt

    while true; do
        echo -e "${CYAN}Select interface language:${PLAIN}"
        echo "  1. English"
        echo "  2. 简体中文 (Simplified Chinese)"
        echo "  3. Русский (Russian)"
        [[ "$mode" == "initial" ]] || echo "  0. Cancel"
        if [[ "$mode" == "initial" ]]; then
            prompt="Enter 1-3 [default: 1]: "
        else
            prompt="Enter 0-3: "
        fi
        if ! read -r -p "$prompt" choice; then
            return 1
        fi
        choice="${choice:-1}"
        case "${choice,,}" in
            1|en|english) target="en" ;;
            2|zh|chinese|中文|简体中文) target="zh" ;;
            3|ru|russian|русский) target="ru" ;;
            0|q|quit|cancel)
                [[ "$mode" == "initial" ]] || return 0
                echo -e "${RED}Please select a language before continuing.${PLAIN}"
                continue
                ;;
            *)
                echo -e "${RED}Invalid selection. Enter a number from 1 to 3.${PLAIN}"
                continue
                ;;
        esac

        if ! save_ui_language "$target"; then
            echo -e "${RED}Unable to save the language setting: ${VPSO_LANGUAGE_CONFIG}${PLAIN}"
            return 1
        fi
        case "$target" in
            zh) echo -e "${GREEN}界面语言已切换为简体中文。${PLAIN}" ;;
            en) echo -e "${GREEN}Interface language changed to English.${PLAIN}" ;;
            ru) echo -e "${GREEN}Язык интерфейса изменён на русский.${PLAIN}" ;;
        esac
        return 0
    done
}

prompt_initial_ui_language() {
    [[ "$VPSO_LANGUAGE_CONFIGURED" == "1" ]] && return 0
    [[ -t 0 ]] || return 0
    select_ui_language initial
}

toggle_ui_language() {
    select_ui_language menu
}
