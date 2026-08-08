# shellcheck shell=bash
# Persistent language selection and localized text helpers.

VPSO_LANGUAGE_CONFIG="${VPSO_LANGUAGE_CONFIG:-/etc/vps-optimize/language.conf}"
VPSO_LANGUAGE="zh"

normalize_ui_language() {
    case "${1,,}" in
        en|en_us|en-us|english) printf 'en' ;;
        *) printf 'zh' ;;
    esac
}

load_ui_language() {
    local configured="${VPSO_LANG:-}"
    if [[ -z "$configured" && -r "$VPSO_LANGUAGE_CONFIG" ]]; then
        configured=$(sed -n 's/^[[:space:]]*LANGUAGE[[:space:]]*=[[:space:]]*//p' "$VPSO_LANGUAGE_CONFIG" | tail -n 1)
        configured="${configured%\"}"
        configured="${configured#\"}"
        configured="${configured%\'}"
        configured="${configured#\'}"
    fi
    VPSO_LANGUAGE=$(normalize_ui_language "$configured")
}

save_ui_language() {
    local language
    language=$(normalize_ui_language "$1")
    mkdir -p "$(dirname "$VPSO_LANGUAGE_CONFIG")" || return 1
    printf 'LANGUAGE=%s\n' "$language" > "$VPSO_LANGUAGE_CONFIG" || return 1
    chmod 600 "$VPSO_LANGUAGE_CONFIG" 2>/dev/null || true
    VPSO_LANGUAGE="$language"
}

localized_text() {
    local zh="$1"
    local en="$2"
    if [[ "$VPSO_LANGUAGE" == "en" ]]; then
        printf '%s' "$en"
    else
        printf '%s' "$zh"
    fi
}

localized_echo() {
    echo -e "$(localized_text "$1" "$2")"
}

toggle_ui_language() {
    local target
    if [[ "$VPSO_LANGUAGE" == "en" ]]; then
        target="zh"
    else
        target="en"
    fi
    if save_ui_language "$target"; then
        if [[ "$target" == "en" ]]; then
            echo -e "${GREEN}Language switched to English.${PLAIN}"
        else
            echo -e "${GREEN}界面语言已切换为中文。${PLAIN}"
        fi
    else
        localized_echo \
            "${RED}❌ 无法保存语言配置：${VPSO_LANGUAGE_CONFIG}${PLAIN}" \
            "${RED}❌ Unable to save the language setting: ${VPSO_LANGUAGE_CONFIG}${PLAIN}"
        return 1
    fi
}
