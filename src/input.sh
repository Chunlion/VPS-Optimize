# shellcheck shell=bash
# Input normalization and prompt helpers.

trim_input() {
    local value="$*"
    value="${value//$'\r'/}"
    value="${value//$'\xc2\xa0'/ }"
    value="${value//$'\xe3\x80\x80'/ }"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

normalize_menu_choice_input() {
    local value lower
    value="$(trim_input "$1")"
    lower=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        q|quit|exit|back|return|返回|退出) printf '0' ;;
        *) printf '%s' "$value" ;;
    esac
}

read_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local __raw_input
    read -r -p "$prompt" __raw_input
    if [[ "$__target" == *choice* && "$__target" != "mode_choice" && "$__target" != "action_choice" ]]; then
        printf -v "$__target" '%s' "$(normalize_menu_choice_input "$__raw_input")"
    else
        printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
    fi
}

read_secret_trimmed() {
    local __target="$1"
    local prompt="${2:-}"
    local __raw_input
    read -r -s -p "$prompt" __raw_input
    echo ""
    printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
}

ask_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input
    read_trimmed input "${prompt} (默认: ${default_value}): "
    echo "${input:-$default_value}"
}

split_csv_to_array() {
    local input="$1"
    local -n out_array=$2
    local idx cleaned
    input="${input//，/,}"
    out_array=()
    local raw_array=()
    IFS=',' read -ra raw_array <<< "$input"
    for idx in "${!raw_array[@]}"; do
        cleaned=$(echo "${raw_array[$idx]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        [[ -n "$cleaned" ]] && out_array+=("$cleaned")
    done
}

split_pipe_to_array() {
    local input="$1"
    local -n out_array=$2
    local item cleaned
    local raw_array=()
    out_array=()
    IFS='|' read -ra raw_array <<< "$input"
    for item in "${raw_array[@]}"; do
        cleaned=$(trim_input "$item")
        [[ -n "$cleaned" ]] && out_array+=("$cleaned")
    done
}
