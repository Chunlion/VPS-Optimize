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

normalize_ascii_digits() {
    local value="$1"
    value="${value//０/0}"
    value="${value//１/1}"
    value="${value//２/2}"
    value="${value//３/3}"
    value="${value//４/4}"
    value="${value//５/5}"
    value="${value//６/6}"
    value="${value//７/7}"
    value="${value//８/8}"
    value="${value//９/9}"
    printf '%s' "$value"
}

normalize_menu_choice_input() {
    local value lower
    value="$(normalize_ascii_digits "$(trim_input "$1")")"
    case "$value" in
        [0-9].|[0-9]\)|[0-9]、|[0-9]．|[0-9]）) value="${value%?}" ;;
        [0-9][0-9].|[0-9][0-9]\)|[0-9][0-9]、|[0-9][0-9]．|[0-9][0-9]）) value="${value%?}" ;;
    esac
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
    case "$__target" in
        mode_choice|action_choice)
            printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
            ;;
        p_choice|final_p|*port*)
            if declare -F normalize_port_input >/dev/null 2>&1; then
                printf -v "$__target" '%s' "$(normalize_port_input "$__raw_input")"
            else
                printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
            fi
            ;;
        *choice*|action|c|t)
            printf -v "$__target" '%s' "$(normalize_menu_choice_input "$__raw_input")"
            ;;
        ip|*_ip|*addr*)
            if declare -F normalize_ip_input >/dev/null 2>&1; then
                printf -v "$__target" '%s' "$(normalize_ip_input "$__raw_input")"
            else
                printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
            fi
            ;;
        *)
            printf -v "$__target" '%s' "$(trim_input "$__raw_input")"
            ;;
    esac
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
    local value
    read_trimmed input "${prompt} (默认: ${default_value}): "
    value="${input:-$default_value}"
    case "$prompt" in
        *路径*)
            ;;
        *端口*|*[Pp][Oo][Rr][Tt]*)
            if declare -F normalize_port_input >/dev/null 2>&1; then
                value="$(normalize_port_input "$value")"
            fi
            ;;
        *监听地址*)
            if declare -F normalize_ip_input >/dev/null 2>&1; then
                value="$(normalize_ip_input "$value")"
            fi
            ;;
    esac
    echo "$value"
}

split_csv_to_array() {
    local input="$1"
    local -n out_array=$2
    local idx cleaned
    input="${input//，/,}"
    input="${input//、/,}"
    input="${input//；/,}"
    input="${input//;/,}"
    input="${input//$'\r'/,}"
    input="${input//$'\n'/,}"
    input="${input//$'\t'/,}"
    input="${input// /,}"
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
