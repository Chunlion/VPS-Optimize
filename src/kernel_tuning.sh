# shellcheck shell=bash
# BBR, TCP tuning, ZRAM, optimized kernel installation, and old-kernel cleanup.

func_bbr_manage() {
    clear
    echo -e "$(localized_text "${CYAN}👉 正在调用 ylx2016 网络极速脚本...${PLAIN}" "${CYAN}👉 Calling ylx2016 network speed script...${PLAIN}" "${CYAN}👉 Вызов сценария скорости сети ylx2016...${PLAIN}")"
    run_remote_script "$(localized_text "运行 ylx2016 网络极速脚本" "Run the ylx2016 network speed script" "Запустите сценарий скорости сети ylx2016.")" "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

VPSO_BBR_DIRECT_CONF="/etc/sysctl.d/99-vps-optimize-bbr-direct.conf"

speedtest_client_kind() {
    if command -v speedtest-cli >/dev/null 2>&1; then
        echo "speedtest-cli"
    elif command -v speedtest >/dev/null 2>&1; then
        echo "ookla"
    else
        return 1
    fi
}

ensure_speedtest_client() {
    if speedtest_client_kind >/dev/null 2>&1; then
        return 0
    fi

    echo -e "$(localized_text "${YELLOW}未检测到测速客户端，正在安装 speedtest-cli...${PLAIN}" "${YELLOW}No speed test client detected, installing speedtest-cli...${PLAIN}" "${YELLOW}Клиент теста скорости не обнаружен, устанавливается Speedtest-cli...${PLAIN}")"
    install_pkg speedtest-cli || return 1
    speedtest_client_kind >/dev/null 2>&1
}

run_speedtest_client() {
    case "$(speedtest_client_kind 2>/dev/null)" in
        ookla) speedtest --accept-license --accept-gdpr ;;
        speedtest-cli) speedtest-cli --secure ;;
        *) return 127 ;;
    esac
}

extract_speedtest_upload_mbps() {
    local output="$1"
    printf '%s\n' "$output" | awk '
        BEGIN { IGNORECASE = 1 }
        /Upload:/ {
            for (i = 1; i <= NF; i++) {
                value = $i
                gsub(/[^0-9.]/, "", value)
                if (value ~ /^[0-9]+([.][0-9]+)?$/) {
                    seen_upload = 1
                    candidate = value
                }
                if (seen_upload && $i ~ /Mbit\/s|Mbps/) {
                    printf "%d\n", candidate + 0.5
                    exit
                }
            }
        }
    '
}

bbr_direct_buffer_mb() {
    local bandwidth="$1"
    local profile="${2:-near}"
    local buffer_mb

    [[ "$bandwidth" =~ ^[0-9]+$ ]] && (( bandwidth > 0 )) || return 1
    case "$profile" in
        near)
            if (( bandwidth <= 200 )); then buffer_mb=8
            elif (( bandwidth <= 700 )); then buffer_mb=12
            elif (( bandwidth <= 1500 )); then buffer_mb=16
            elif (( bandwidth <= 5000 )); then buffer_mb=24
            else buffer_mb=32
            fi
            ;;
        long)
            if (( bandwidth <= 100 )); then buffer_mb=8
            elif (( bandwidth <= 300 )); then buffer_mb=20
            elif (( bandwidth <= 700 )); then buffer_mb=48
            else buffer_mb=64
            fi
            ;;
        *) return 1 ;;
    esac
    echo "$buffer_mb"
}

prompt_bbr_bandwidth_mbps() {
    local choice output bandwidth

    echo -e "$(localized_text "${CYAN}带宽获取方式：${PLAIN}" "${CYAN}Bandwidth acquisition method:${PLAIN}" "${CYAN}Метод получения полосы пропускания:${PLAIN}")" >&2
    echo "$(localized_text "  1. 自动测速（使用上传带宽）" "1. Automatic speed measurement (using upload bandwidth)" "1. Автоматическое измерение скорости (с использованием полосы пропускания загрузки)")" >&2
    echo "$(localized_text "  2. 手动输入套餐带宽" "2. Manually enter the package bandwidth" "2. Введите вручную пропускную способность пакета.")" >&2
    read_trimmed choice "$(localized_text "请选择 [1]: " "Please select [1]:" "Пожалуйста, выберите [1]:")"
    choice="${choice:-1}"

    if [[ "$choice" == "1" ]]; then
        if ensure_speedtest_client >&2; then
            echo -e "$(localized_text "${CYAN}正在执行带宽测试...${PLAIN}" "${CYAN}Performing bandwidth test...${PLAIN}" "${CYAN}Выполнение теста пропускной способности...${PLAIN}")" >&2
            output=$(run_speedtest_client 2>&1)
            printf '%s\n' "$output" >&2
            bandwidth=$(extract_speedtest_upload_mbps "$output")
            if [[ "$bandwidth" =~ ^[0-9]+$ ]] && (( bandwidth > 0 )); then
                echo -e "$(localized_text "${GREEN}检测到上传带宽：${bandwidth} Mbps${PLAIN}" "${GREEN}Detected upload bandwidth: ${bandwidth} Mbps${PLAIN}" "${GREEN}Обнаруженная пропускная способность загрузки: ${bandwidth} Мбит/с${PLAIN}")" >&2
                echo "$bandwidth"
                return 0
            fi
            echo -e "$(localized_text "${YELLOW}未能解析测速结果，请手动输入套餐带宽。${PLAIN}" "${YELLOW}Failed to parse the speed measurement results. Please enter the package bandwidth manually.${PLAIN}" "${YELLOW}не удалось проанализировать результаты измерения скорости. Пожалуйста, введите пропускную способность пакета вручную.${PLAIN}")" >&2
        else
            echo -e "$(localized_text "${YELLOW}测速客户端不可用，请手动输入套餐带宽。${PLAIN}" "${YELLOW}Speed test client is not available, please enter the package bandwidth manually.${PLAIN}" "${YELLOW}Клиент теста скорости недоступен. Введите пропускную способность пакета вручную.${PLAIN}")" >&2
        fi
    elif [[ "$choice" != "2" ]]; then
        echo -e "$(localized_text "${RED}无效选择。${PLAIN}" "${RED}Invalid selection.${PLAIN}" "${RED}Неверный выбор.${PLAIN}")" >&2
        return 1
    fi

    while true; do
        read_trimmed bandwidth "$(localized_text "请输入带宽（Mbps，输入 0 取消）: " "Please enter bandwidth (Mbps, enter 0 to cancel):" "Пожалуйста, введите пропускную способность (Мбит/с, для отмены введите 0):")"
        [[ "$bandwidth" == "0" ]] && return 1
        if [[ "$bandwidth" =~ ^[0-9]+$ ]] && (( bandwidth > 0 )); then
            echo "$bandwidth"
            return 0
        fi
        echo -e "$(localized_text "${RED}请输入正整数。${PLAIN}" "${RED}Please enter a positive integer.${PLAIN}" "${RED}Введите положительное целое число.${PLAIN}")" >&2
    done
}

sysctl_tune_capture_runtime() {
    local source_file="$1"
    local output_file="$2"
    local line key value

    : > "$output_file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_input "$line")"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        key="${line%%=*}"
        key="$(trim_input "$key")"
        value=$(sysctl -n "$key" 2>/dev/null) || return 1
        printf '%s = %s\n' "$key" "$value" >> "$output_file"
    done < "$source_file"
}

write_bbr_direct_candidate() {
    local output_file="$1"
    local bandwidth="$2"
    local profile="$3"
    local buffer_mb="$4"
    local buffer_bytes
    buffer_bytes=$((buffer_mb * 1024 * 1024))

    cat > "$output_file" <<EOF
# VPS-Optimize BBR direct/endpoint profile
# Bandwidth: ${bandwidth} Mbps; RTT profile: ${profile}; buffer: ${buffer_mb} MiB
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = ${buffer_bytes}
net.core.wmem_max = ${buffer_bytes}
net.ipv4.tcp_rmem = 4096 87380 ${buffer_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buffer_bytes}
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1
EOF
}

func_bbr_direct_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "网络/内核优化 > BBR 直连/落地优化" "Network/kernel optimization > BBR direct connection/relay-server tuning" "Оптимизация сети/ядра > BBR оптимизация прямого подключения/промежуточный сервер")"
    echo -e "$(localized_text "${BOLD}🚀 BBR 直连/落地优化（智能带宽检测）${PLAIN}" "${BOLD}🚀 BBR Direct connection/relay-server tuning (intelligent bandwidth detection)${PLAIN}" "${BOLD}🚀 BBR Оптимизация прямого подключения/посадки (интеллектуальное определение пропускной способности)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local bandwidth profile_choice profile buffer_mb buffer_bytes
    local candidate runtime_backup config_backup=""
    bandwidth=$(prompt_bbr_bandwidth_mbps) || { pause_return "$(localized_text "操作已取消，按任意键返回..." "The operation has been canceled. Press any key to return..." "Операция отменена. Нажмите любую клавишу, чтобы вернуться...")"; return 0; }

    echo ""
    echo "$(localized_text "  1. 近距离/亚太为主（主要 RTT 通常低于 100ms）" "1. Short range/Asia-Pacific mainly (main RTT is usually less than 100ms)" "1. Малая дальность/в основном Азиатско-Тихоокеанский регион (основное RTT обычно менее 100 мс)")"
    echo "$(localized_text "  2. 跨洲链路为主（主要 RTT 通常为 150-300ms）" "2. Mainly cross-continental links (main RTT is usually 150-300ms)" "2. В основном межконтинентальные каналы (основное RTT обычно составляет 150–300 мс).")"
    read_trimmed profile_choice "$(localized_text "请选择主要使用场景 [1]: " "Please select the main usage scenario [1]:" "Пожалуйста, выберите основной сценарий использования [1]:")"
    case "${profile_choice:-1}" in
        1) profile="near" ;;
        2) profile="long" ;;
        *) echo -e "$(localized_text "${RED}无效选择。${PLAIN}" "${RED}Invalid selection.${PLAIN}" "${RED}Неверный выбор.${PLAIN}")"; pause_return; return 1 ;;
    esac

    buffer_mb=$(bbr_direct_buffer_mb "$bandwidth" "$profile") || return 1
    buffer_bytes=$((buffer_mb * 1024 * 1024))
    echo -e "$(localized_text "${CYAN}计算结果：${bandwidth} Mbps，TCP 最大缓冲区 ${buffer_mb} MiB。${PLAIN}" "${CYAN}Calculation result: ${bandwidth} Mbps, TCP maximum buffer ${buffer_mb} MiB.${PLAIN}" "${CYAN}Результат расчета : ${bandwidth} Мбит/с, TCP максимальный буфер ${buffer_mb} MiB.${PLAIN}")"

    if ! modprobe tcp_bbr >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}当前内核无法加载 tcp_bbr 模块，未修改配置。${PLAIN}" "${RED}The current kernel cannot load the tcp_bbr module and the configuration has not been modified.${PLAIN}" "${RED}Текущее ядро не может загрузить модуль tcp_bbr, и конфигурация не была изменена.${PLAIN}")"
        pause_return
        return 1
    fi
    if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        echo -e "$(localized_text "${RED}当前内核未提供 BBR 拥塞控制，未修改配置。${PLAIN}" "${RED}The current kernel does not provide BBR congestion control, and the configuration has not been modified.${PLAIN}" "${RED}Текущее ядро не обеспечивает контроль перегрузки BBR, и конфигурация не была изменена.${PLAIN}")"
        pause_return
        return 1
    fi

    candidate=$(mktemp /tmp/vpso-bbr-direct.XXXXXX.conf) || return 1
    runtime_backup=$(mktemp /tmp/vpso-bbr-runtime.XXXXXX.conf) || { rm -f "$candidate"; return 1; }
    write_bbr_direct_candidate "$candidate" "$bandwidth" "$profile" "$buffer_mb"

    if ! sysctl_tune_check_supported_file "$candidate" || ! sysctl_tune_capture_runtime "$candidate" "$runtime_backup"; then
        rm -f "$candidate" "$runtime_backup"
        echo -e "$(localized_text "${RED}当前内核不支持完整调优参数，未修改配置。${PLAIN}" "${RED}The current kernel does not support complete tuning parameters and the configuration has not been modified.${PLAIN}" "${RED}Текущее ядро не поддерживает полные параметры настройки, и конфигурация не была изменена.${PLAIN}")"
        pause_return
        return 1
    fi

    mkdir -p /etc/sysctl.d || { rm -f "$candidate" "$runtime_backup"; return 1; }
    if [[ -f "$VPSO_BBR_DIRECT_CONF" ]]; then
        config_backup="${VPSO_BBR_DIRECT_CONF}.bak_$(date +%Y%m%d_%H%M%S)"
        if ! cp -p "$VPSO_BBR_DIRECT_CONF" "$config_backup"; then
            rm -f "$candidate" "$runtime_backup"
            echo -e "$(localized_text "${RED}旧配置备份失败，未应用新参数。${PLAIN}" "${RED}The old configuration backup failed and the new parameters were not applied.${PLAIN}" "${RED}Не удалось выполнить резервное копирование старой конфигурации, и новые параметры не были применены.${PLAIN}")"
            pause_return
            return 1
        fi
    fi

    if ! sysctl_tune_apply_file "$candidate" || ! install -m 0644 "$candidate" "$VPSO_BBR_DIRECT_CONF"; then
        sysctl_tune_apply_file "$runtime_backup" >/dev/null 2>&1 || true
        if [[ -n "$config_backup" && -f "$config_backup" ]]; then
            cp -p "$config_backup" "$VPSO_BBR_DIRECT_CONF" >/dev/null 2>&1 || true
        else
            rm -f "$VPSO_BBR_DIRECT_CONF"
        fi
        rm -f "$candidate" "$runtime_backup"
        echo -e "$(localized_text "${RED}调优应用失败，已恢复运行时参数和原配置。${PLAIN}" "${RED}Tuning application failed, and the runtime parameters and original configuration have been restored.${PLAIN}" "${RED}Приложение настройки не удалось, параметры времени выполнения и исходная конфигурация были восстановлены.${PLAIN}")"
        pause_return
        return 1
    fi

    rm -f "$candidate" "$runtime_backup"
    echo -e "$(localized_text "${GREEN}✅ BBR 直连/落地优化已应用。${PLAIN}" "${GREEN}✅ BBR direct connection/relay-server tuning has been applied.${PLAIN}" "${GREEN}✅ BBR Применена оптимизация прямого подключения/промежуточный сервер.${PLAIN}")"
    echo "$(localized_text "配置文件：$VPSO_BBR_DIRECT_CONF" "Configuration file: $VPSO_BBR_DIRECT_CONF" "Файл конфигурации: $VPSO_BBR_DIRECT_CONF.")"
    [[ -n "$config_backup" ]] && echo "$(localized_text "原配置备份：$config_backup" "Original configuration backup: $config_backup" "Резервная копия исходной конфигурации: $config_backup.")"
    echo "$(localized_text "当前拥塞控制：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" "Current congestion control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" "Текущий контроль перегрузок: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)")"
    echo "$(localized_text "当前最大缓冲区：${buffer_bytes} bytes (${buffer_mb} MiB)" "Current maximum buffer: ${buffer_bytes} bytes (${buffer_mb} MiB)" "Текущий максимальный буфер: ${buffer_bytes} байт (${buffer_mb} MiB)")"
    echo -e "$(localized_text "${YELLOW}该功能不修改内核、Swap、防火墙、路由或 systemd 服务。${PLAIN}" "${YELLOW}This function does not modify the kernel, Swap, firewall, routing or systemd services.${PLAIN}" "${YELLOW}Эта функция не изменяет ядро, Swap, брандмауэр, маршрутизацию или службы systemd.${PLAIN}")"
    pause_return
}

sysctl_tune_split_line() {
    local line="$1"
    line="${line//$'\r'/}"
    printf '%s\n' "$line" | awk '
        {
            gsub(/;/, "\n")
            parts_count = split($0, parts, /\n/)
            for (part_idx = 1; part_idx <= parts_count; part_idx++) {
                rest = parts[part_idx]
                sub(/^[[:space:]]+/, "", rest)
                sub(/[[:space:]]+$/, "", rest)
                sub(/^(sudo[[:space:]]+)?sysctl[[:space:]]+(-w[[:space:]]+)?/, "", rest)
                while (match(rest, /[[:space:]]+((sudo[[:space:]]+)?sysctl[[:space:]]+(-w[[:space:]]+)?[A-Za-z0-9_.-]+[[:space:]]*=|[A-Za-z0-9_.-]+[[:space:]]*=)/)) {
                    before = substr(rest, 1, RSTART - 1)
                    if (before ~ /[^[:space:]]/) print before
                    rest = substr(rest, RSTART + 1)
                    sub(/^(sudo[[:space:]]+)?sysctl[[:space:]]+(-w[[:space:]]+)?/, "", rest)
                }
                if (rest ~ /[^[:space:]]/) print rest
            }
        }
    '
}

sysctl_tune_normalize_record() {
    local candidate="$1" key value
    candidate="$(trim_input "$candidate")"
    [[ -z "$candidate" ]] && return 1

    if [[ "$candidate" =~ ^(sudo[[:space:]]+)?sysctl[[:space:]]+(-w[[:space:]]+)?(.+)$ ]]; then
        candidate="$(trim_input "${BASH_REMATCH[3]}")"
    fi

    if [[ "$candidate" =~ ^([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="$(trim_input "${BASH_REMATCH[2]}")"
        [[ -z "$value" ]] && return 2
        printf '%s = %s\n' "$key" "$value"
        return 0
    fi

    return 2
}

sysctl_tune_check_supported_file() {
    local conf_file="$1"
    local line key item_no=0 output
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_input "$line")"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        item_no=$((item_no + 1))
        if [[ "$line" =~ ^([A-Za-z0-9_.-]+)[[:space:]]*= ]]; then
            key="${BASH_REMATCH[1]}"
        else
            echo -e "$(localized_text "${RED}❌ 第 ${item_no} 项语法错误: $line${PLAIN}" "${RED}❌ Syntax error in item ${item_no}: $line${PLAIN}" "${RED}❌ Синтаксическая ошибка в элементе ${item_no}: $line${PLAIN}")"
            return 1
        fi
        if ! output=$(sysctl -n "$key" 2>&1); then
            echo -e "$(localized_text "${RED}❌ 第 ${item_no} 项当前内核不支持: $key${PLAIN}" "${RED}❌ Item ${item_no} is not supported by the current kernel: $key${PLAIN}" "${RED}❌ Элемент ${item_no} не поддерживается текущим ядром: $key.${PLAIN}")"
            [[ -n "$output" ]] && echo -e "$(localized_text "${YELLOW}sysctl 输出：${output}${PLAIN}" "${YELLOW}Sysctl Output: ${output}${PLAIN}" "${YELLOW}sysctl Выход: ${output}${PLAIN}")"
            return 1
        fi
    done < "$conf_file"
    return 0
}

sysctl_tune_apply_file() {
    local conf_file="$1"
    local line key value item_no=0 output
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_input "$line")"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        item_no=$((item_no + 1))
        if [[ "$line" =~ ^([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="$(trim_input "${BASH_REMATCH[2]}")"
        else
            echo -e "$(localized_text "${RED}❌ 第 ${item_no} 项语法错误: $line${PLAIN}" "${RED}❌ Syntax error in item ${item_no}: $line${PLAIN}" "${RED}❌ Синтаксическая ошибка в элементе ${item_no}: $line${PLAIN}")"
            return 1
        fi
        if ! output=$(sysctl -w "$key=$value" 2>&1); then
            echo -e "$(localized_text "${RED}❌ 第 ${item_no} 项应用失败: ${key} = ${value}${PLAIN}" "${RED}❌ The application of ${item_no} failed: ${key} = ${value}${PLAIN}" "${RED}❌ Не удалось применить ${item_no}: ${key} = ${value}.${PLAIN}")"
            if [[ "$output" == *"cannot stat"* || "$output" == *"No such file"* ]]; then
                echo -e "$(localized_text "${YELLOW}原因：当前内核不支持该参数。${PLAIN}" "${YELLOW}Reason: The current kernel does not support this parameter.${PLAIN}" "${YELLOW}Причина: Текущее ядро не поддерживает этот параметр.${PLAIN}")"
            else
                echo -e "$(localized_text "${YELLOW}原因：当前内核拒绝该值或参数值语法错误。${PLAIN}" "${YELLOW}Reason: The current kernel rejects the value or the parameter value has a syntax error.${PLAIN}" "${YELLOW}Причина: Текущее ядро отклоняет значение или значение параметра содержит синтаксическую ошибку.${PLAIN}")"
            fi
            [[ -n "$output" ]] && echo -e "$(localized_text "${YELLOW}sysctl 输出：${output}${PLAIN}" "${YELLOW}Sysctl Output: ${output}${PLAIN}" "${YELLOW}sysctl Выход: ${output}${PLAIN}")"
            return 1
        fi
    done < "$conf_file"
    return 0
}

sysctl_tune_restore_previous_config() {
    local backup_f="$1"
    local temp_f="$2"
    if [[ -f "$backup_f" ]]; then
        mv "$backup_f" "$temp_f"
        sysctl -p "$temp_f" >/dev/null 2>&1
    else
        rm -f "$temp_f"
    fi
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (修复版：放宽正则以兼容多值与特殊符号)
# ---------------------------------------------------------
func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🚀 动态 TCP 极致调优 (Omnitt)${PLAIN}" "${BOLD}🚀 Dynamic TCP Extreme Tuning (Omnitt)${PLAIN}" "${BOLD}🚀 Dynamic TCP Extreme Tuning (Omnitt)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "👉 推荐浏览器访问: ${BLUE}https://omnitt.com/${PLAIN} 获取针对您网络的定制参数" "👉 Recommended browser access: ${BLUE}Https://omnitt.com/${PLAIN} to obtain customized parameters for your network" "👉 Рекомендуемый доступ через браузер: ${BLUE}https://omnitt.com/${PLAIN} для получения индивидуальных параметров для вашей сети.")"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "$(localized_text "❓ 准备好粘贴参数了吗？(Y/n): " "❓ Are you ready to paste the parameters? (Y/n):" "❓ Готовы ли вы вставить параметры? (Да/Нет):")"
    if ! is_yes "$yn"; then return; fi
    
    local temp_f="/etc/sysctl.d/99-omnitt-tune.conf"
    local backup_f="${temp_f}.bak_$(date +%s)"
    
    # 事务起点：备份原配置
    if [[ -f "$temp_f" ]]; then
        cp "$temp_f" "$backup_f"
    fi
    
    > "$temp_f"
    echo -e "$(localized_text "\n${YELLOW}👇 请在下方直接【右键粘贴】代码。${PLAIN}" "\n${YELLOW}👇 Please directly [right-click and paste] the code below.${PLAIN}" "\n${YELLOW}👇 Пожалуйста, [щелкните правой кнопкой мыши и вставьте] код ниже.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}💡 粘贴完成后，请按下【回车键】，然后输入 ${RED}EOF${YELLOW} 并再次回车保存：${PLAIN}" "${YELLOW}💡 After pasting is completed, please press the [Enter key], then enter EOFand press Enter again to save:${PLAIN}" "${YELLOW}💡 После завершения вставки нажмите [Enter], затем введите EOFи снова нажмите Enter, чтобы сохранить:${PLAIN}")"
    
    local has_content=false
    local parse_failed=false
    while IFS= read -r line; do
        # 极简清洗：去除回车符和前后多余空格
        line="$(trim_input "$line")"
        
        # 结束符匹配（忽略大小写）
        if [[ "${line,,}" == "eof" ]]; then
            break
        fi
        
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            echo "$line" >> "$temp_f"
            continue
        fi

        local candidate record status
        while IFS= read -r candidate; do
            record=$(sysctl_tune_normalize_record "$candidate")
            status=$?
            case "$status" in
                0)
                    echo "$record" >> "$temp_f"
                    has_content=true
                    ;;
                1)
                    ;;
                *)
                    echo -e "$(localized_text "${RED}❌ 参数语法错误，已停止应用: $candidate${PLAIN}" "${RED}❌ Parameter syntax error, application has been stopped: $candidate${PLAIN}" "${RED}❌ Синтаксическая ошибка параметра, приложение остановлено: $candidate${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}格式应为: net.ipv4.tcp_xxx = value${PLAIN}" "${YELLOW}The format of should be: net.ipv4.tcp_xxx = value${PLAIN}" "${YELLOW}Формат должен быть следующим: net.ipv4.tcp_xxx = value.${PLAIN}")"
                    parse_failed=true
                    ;;
            esac
        done < <(sysctl_tune_split_line "$line")
    done
    
    if $parse_failed; then
        echo -e "$(localized_text "${YELLOW}正在触发安全回滚...${PLAIN}" "${YELLOW}Is triggering safe rollback...${PLAIN}" "${YELLOW}запускает безопасный откат...${PLAIN}")"
        sysctl_tune_restore_previous_config "$backup_f" "$temp_f"
        echo -e "$(localized_text "${BLUE}✅ 已恢复系统原 TCP 配置文件。${PLAIN}" "${BLUE}✅ The original TCP configuration file of the system has been restored.${PLAIN}" "${BLUE}. Исходный файл конфигурации системы TCP восстановлен.${PLAIN}")"
    elif $has_content; then
        echo -e "$(localized_text "${CYAN}▶ 正在校验并应用新 TCP 参数...${PLAIN}" "${CYAN}▶ Verifying and applying new TCP parameters...${PLAIN}" "${CYAN}▶ Проверка и применение новых параметров TCP...${PLAIN}")"
        # 验证新配置是否被内核完全接受
        if sysctl_tune_check_supported_file "$temp_f" && sysctl_tune_apply_file "$temp_f"; then
            echo -e "$(localized_text "${GREEN}✅ 动态 TCP 调优参数应用成功！网络吞吐量已提升。${PLAIN}" "${GREEN}✅ Dynamic TCP tuning parameters are applied successfully! Network throughput has been improved.${PLAIN}" "${GREEN}. Параметры динамической настройки TCP успешно применены! Пропускная способность сети была улучшена.${PLAIN}")"
            rm -f "$backup_f" # 成功则删除备份
        else
            echo -e "$(localized_text "${RED}❌ 致命错误：您粘贴的部分参数当前内核不支持或语法错误！${PLAIN}" "${RED}❌ Fatal error: Some of the parameters you pasted are not supported by the current kernel or have syntax errors!${PLAIN}" "${RED}❌ Неустранимая ошибка: некоторые из вставленных вами параметров не поддерживаются текущим ядром или содержат синтаксические ошибки!${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}正在触发安全回滚...${PLAIN}" "${YELLOW}Is triggering safe rollback...${PLAIN}" "${YELLOW}запускает безопасный откат...${PLAIN}")"
            sysctl_tune_restore_previous_config "$backup_f" "$temp_f"
            echo -e "$(localized_text "${BLUE}✅ 已恢复系统原 TCP 状态，未造成任何破坏。${PLAIN}" "${BLUE}✅ The system has been restored to its original TCP state without causing any damage.${PLAIN}" "${BLUE}✅ Система была восстановлена в исходное состояние TCP без каких-либо повреждений.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到有效的 TCP 调优参数，操作已取消。${PLAIN}" "${YELLOW}⚠️ No valid TCP tuning parameters were detected and the operation was cancelled.${PLAIN}" "${YELLOW}⚠️ Не обнаружено действительных параметров настройки TCP, и операция была отменена.${PLAIN}")"
        sysctl_tune_restore_previous_config "$backup_f" "$temp_f"
    fi
    
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

# ---------------------------------------------------------
# 8. 智能内存调优 (重构版：安全接管与 DRY 化)
# ---------------------------------------------------------
func_zram_swap() {
    clear
    local mem
    mem=$(free -m | awk '/^Mem:/{print $2}')
    echo -e "$(localized_text "${CYAN}💡 硬件自适应调优 (检测到本机 ${mem}MB 物理内存)${PLAIN}" "${CYAN}💡 Hardware adaptive tuning (local ${mem}MB physical memory detected)${PLAIN}" "${CYAN}💡 Адаптивная настройка оборудования (обнаружена локальная физическая память ${mem}MB)${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text " ${GREEN}1. 激进档 (适合 1G 以下小鸡)${PLAIN}" "${GREEN}1. Radical file (suitable for chicks below 1G)${PLAIN}" "${GREEN}1. Радикальный напильник (подходит для цыплят весом до 1 г)${PLAIN}")"
    echo -e "$(localized_text "    - ZRAM 100% 压缩, Swappiness=100。全力防止宕机。" "- ZRAM 100% compression, Swappiness=100. Do your best to prevent downtime." "- ZRAM 100% сжатие, Swappiness=100. Сделайте все возможное, чтобы предотвратить простои.")"
    echo -e "$(localized_text " ${GREEN}2. 积极档 (适合 2-4G 主流机型)${PLAIN}" "${GREEN}2. Active mode (suitable for 2-4G mainstream models)${PLAIN}" "${GREEN}2. Активный режим (подходит для основных моделей 2–4G)${PLAIN}")"
    echo -e "$(localized_text "    - ZRAM 70% 压缩, Swappiness=60。平衡性能与空间。" "- ZRAM 70% compression, Swappiness=60. Balance performance and space." "- ZRAM сжатие 70%, Swappiness=60. Баланс производительности и пространства.")"
    echo -e "$(localized_text " ${GREEN}3. 保守档 (适合 8G 以上性能怪兽)${PLAIN}" "${GREEN}3. Conservative file (suitable for performance monsters above 8G)${PLAIN}" "${GREEN}3. Консервативный файл (подходит для монстров производительности выше 8G)${PLAIN}")"
    echo -e "$(localized_text "    - ZRAM 25% 压缩, Swappiness=10。追求极致响应速度。" "- ZRAM 25% compression, Swappiness=10. Pursue the ultimate response speed." "- ZRAM сжатие 25%, Swappiness=10. Добейтесь максимальной скорости отклика.")"
    echo -e "------------------------------------------------"
    
    local choice
    read_trimmed choice "$(localized_text "👉 请选择您的调优挡位 [1/2/3] (直接回车按内存自动匹配): " "👉 Please select your tuning gear [1/2/3] (press Enter directly and press memory to automatically match):" "👉 Пожалуйста, выберите свое тюнинговое оборудование [1/2/3] (нажмите Enter и нажмите «память», чтобы автоматически подобрать совпадение):")"
    
    if [[ -z "$choice" ]]; then
        if [[ "$mem" -lt 1024 ]]; then choice=1
        elif [[ "$mem" -le 4096 ]]; then choice=2
        else choice=3
        fi
        echo -e "$(localized_text "${YELLOW}💡 系统已根据本机内存 (${mem}MB) 自动选择：[ 挡位 $choice ]${PLAIN}" "${YELLOW}💡 The system has automatically selected according to the local memory (${mem}MB): [ Gear $choice ]${PLAIN}" "${YELLOW}💡 Система автоматически выбрала в соответствии с локальной памятью (${mem}MB): [ Gear $choice ]${PLAIN}")"
        sleep 1.5
    fi
    
    # 提早阻断，避免非 Debian 机器运行破坏性 Swap 卸载指令
    if ! is_debian; then
        echo -e "$(localized_text "${RED}❌ 抱歉，当前系统并非 Debian/Ubuntu 衍生系，暂不支持自动化 ZRAM 调优。${PLAIN}" "${RED}❌ Sorry, the current system is not a Debian/Ubuntu derivative and does not currently support automated ZRAM tuning.${PLAIN}" "${RED}❌ Извините, текущая система не является производной Debian/Ubuntu и в настоящее время не поддерживает автоматическую настройку ZRAM.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在进行第一阶段：整理底层磁盘 Swap (保留 512M 保底防假死)...${PLAIN}" "${CYAN}▶ The first phase is in progress: organizing the underlying disk Swap (512M reserved to prevent suspended animation)...${PLAIN}" "${CYAN}▶ Выполняется первый этап: организация подкачки базового диска (512 МБ зарезервировано для предотвращения зависания)...${PLAIN}")"
    
    swapoff -a >/dev/null 2>&1
    local old_swap
    for old_swap in /swapfile /swap.img /var/swap /var/swapfile; do
        quarantine_path "$old_swap" "/root/vps-optimize-quarantine/swap" >/dev/null 2>&1 || true
    done
    
    dd if=/dev/zero of=/swapfile bs=1M count=512 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1
    
    sed -i -E 's/^([^#].*[[:space:]]swap[[:space:]].*)/#\1/' /etc/fstab
    sed -i '\@^/swapfile@d' /etc/fstab
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo -e "$(localized_text "${GREEN}✅ 已建立 512M 极小磁盘 Swap 作为系统崩溃的最后防线！${PLAIN}" "${GREEN}✅ A 512M very small disk Swap has been established as the last line of defense for system crashes!${PLAIN}" "${GREEN}. Очень маленький диск Swap объемом 512 МБ установлен в качестве последней линии защиты от сбоев системы!${PLAIN}")"
    
    echo -e "$(localized_text "${CYAN}▶ 正在进行第二阶段：配置 ZRAM 内存压缩引擎...${PLAIN}" "${CYAN}▶ Phase 2 in progress: Configuring the ZRAM memory compression engine...${PLAIN}" "${CYAN}▶ Выполняется этап 2: настройка механизма сжатия памяти ZRAM...${PLAIN}")"
    
    # 核心修改：使用全局包安装器
    install_pkg zram-tools
    modprobe zram >/dev/null 2>&1
    
    local zram_conf="/etc/default/zramswap"
    local percent=70
    local swap_val=60
    
    case $choice in
        1) percent=100; swap_val=100 ;;
        2) percent=70; swap_val=60 ;;
        3) percent=25; swap_val=10 ;;
        *) percent=70; swap_val=60 ;;
    esac
    
    cat <<EOF > "$zram_conf"
ALGO=zstd
PERCENT=$percent
PRIORITY=100
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1
    systemctl restart zramswap >/dev/null 2>&1
    
    if ! grep -q zram /proc/swaps; then
        if command -v zramswap >/dev/null 2>&1; then
            zramswap start >/dev/null 2>&1
        elif [[ -x /usr/sbin/zramswap ]]; then
            /usr/sbin/zramswap start >/dev/null 2>&1
        fi
    fi
    
    echo "vm.swappiness = $swap_val" > /etc/sysctl.d/99-zram-swappiness.conf
    sysctl -p /etc/sysctl.d/99-zram-swappiness.conf >/dev/null 2>&1
    
if grep -q zram /proc/swaps; then
        echo -e "$(localized_text "${GREEN}✅ ZRAM 调优落地完成！(已设置: ${percent}% 压缩比, ${swap_val} 交换倾向)${PLAIN}" "${GREEN}✅ ZRAM tuning and implementation completed! (Already set: ${percent}% compression ratio, ${swap_val} exchange tendency)${PLAIN}" "${GREEN}✅ Настройка и внедрение ZRAM завершены! (Уже установлено: степень сжатия ${percent}%, тенденция обмена ${swap_val})${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 警告：内核拒绝挂载 ZRAM (常见于 LXC/OpenVZ 架构)。${PLAIN}" "${RED}❌ Warning: The kernel refused to mount ZRAM (common in LXC/OpenVZ architectures).${PLAIN}" "${RED}❌ Внимание: ядро отказалось монтировать ZRAM (обычно в архитектурах LXC/OpenVZ).${PLAIN}")"
        echo -e "$(localized_text "${CYAN}▶ 正在启动降级优化方案：传统 Swap 扩容与内核防假死调优...${PLAIN}" "${CYAN}▶ Starting the downgrade optimization plan: traditional Swap expansion and kernel anti-suspense tuning...${PLAIN}" "${CYAN}▶ Начинаем план оптимизации перехода на более раннюю версию: традиционное расширение Swap и настройка антиприостановки ядра...${PLAIN}")"
        
        # 1. 扩容保底 Swap：从 512M 升级至 1024M (1GB)
        swapoff /swapfile >/dev/null 2>&1
        quarantine_path /swapfile "/root/vps-optimize-quarantine/swap" >/dev/null 2>&1 || true
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        
        # 2. 注入降级专属的内核内存管理参数
        # swappiness=30 : 只有内存比较吃紧时才使用较慢的磁盘 Swap
        # vfs_cache_pressure=50 : 降低系统回收目录/文件系统缓存的频率，提高小鸡流畅度
        # overcommit_memory=1 : 允许内核分配超过物理内存的空间，防止 Redis/数据库 等服务在启动时被直接 Kill
        cat <<EOF > /etc/sysctl.d/99-fallback-mem.conf
vm.swappiness = 30
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
EOF
        sysctl -p /etc/sysctl.d/99-fallback-mem.conf >/dev/null 2>&1
        
        echo -e "$(localized_text "${GREEN}✅ 降级优化落地：已动态扩充 1GB 磁盘 Swap，并激活保守内存回收策略！${PLAIN}" "${GREEN}✅ Downgrade optimization implemented: 1GB disk swap has been dynamically expanded and conservative memory recycling strategy has been activated!${PLAIN}" "${GREEN}✅ Реализована оптимизация понижения версии: подкачка диска на 1 ГБ была динамически расширена и активирована консервативная стратегия повторного использования памяти!${PLAIN}")"
    fi
    
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 9. 安装/切换优化内核 (Cloud/KVM 稳定优先 + XanMod 高级可选)
# ---------------------------------------------------------
normalize_kernel_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "unknown" ;;
    esac
}

apt_pkg_available() {
    local pkg="$1"
    apt-cache show "$pkg" >/dev/null 2>&1
}

set_grub_default_kernel_by_keyword() {
    local kernel_keyword="$1"
    local target_v menu_1 menu_2

    if ! command -v dpkg >/dev/null 2>&1 || [[ ! -f /etc/default/grub ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 dpkg/GRUB 配置，已跳过自动接管引导。${PLAIN}" "${YELLOW}⚠️ No dpkg/GRUB configuration detected, automatic takeover boot skipped.${PLAIN}" "${YELLOW}⚠️ Конфигурация dpkg/GRUB не обнаружена, автоматическая загрузка с дублированием пропущена.${PLAIN}")"
        return 0
    fi

    target_v=$(dpkg -l | awk '/^ii[[:space:]]+linux-image-[0-9]/ && /'"$kernel_keyword"'/ {print $2}' | sed 's/linux-image-//' | sort -V | tail -n 1)
    if [[ -z "$target_v" ]]; then
        echo -e "$(localized_text "${RED}❌ 错误：未找到已安装的 ${kernel_keyword} 内核包，请检查安装日志。${PLAIN}" "${RED}❌ Error: The installed ${kernel_keyword} kernel package was not found, please check the installation log.${PLAIN}" "${RED}❌ Ошибка: установленный пакет ядра ${kernel_keyword} не найден, проверьте журнал установки.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在接管 GRUB 底层引导，锁定启动内核为: $target_v ...${PLAIN}" "${CYAN}▶ Taking over the GRUB bottom boot, the locked boot kernel is: $target_v...${PLAIN}" "${CYAN}▶ Принимая на себя нижнюю загрузку GRUB, заблокированное загрузочное ядро: $target_v...${PLAIN}")"
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    else
        echo "GRUB_DEFAULT=saved" >> /etc/default/grub
    fi
    grep -q "^GRUB_SAVEDEFAULT=true" /etc/default/grub || echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
    if command -v update-grub >/dev/null 2>&1; then
        update-grub >/dev/null 2>&1
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    fi

    local grub_cfg="/boot/grub/grub.cfg"
    [[ -f "$grub_cfg" ]] || grub_cfg="/boot/grub2/grub.cfg"
    if [[ ! -f "$grub_cfg" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 grub.cfg，新内核已安装，但请重启后手动确认默认启动项。${PLAIN}" "${YELLOW}⚠️ grub.cfg not found, the new kernel has been installed, but please manually confirm the default startup items after restarting.${PLAIN}" "${YELLOW}⚠️ grub.cfg не найден, новое ядро установлено, но после перезапуска вручную подтвердите элементы запуска по умолчанию.${PLAIN}")"
        return 0
    fi

    menu_1=$(grep -i "submenu 'Advanced options for" "$grub_cfg" | cut -d"'" -f2 | head -n 1)
    menu_2=$(grep -i "menuentry '.*$target_v.*'" "$grub_cfg" | grep -iv "recovery" | cut -d"'" -f2 | head -n 1)

    if [[ -n "$menu_1" && -n "$menu_2" ]]; then
        grub-set-default "$menu_1>$menu_2" 2>/dev/null || grub2-set-default "$menu_1>$menu_2" 2>/dev/null || true
        echo -e "$(localized_text "${GREEN}✅ GRUB 引导接管成功！重启后将优先进入：$target_v${PLAIN}" "${GREEN}✅ GRUB boot takeover successful! After restarting, you will enter first: $target_v${PLAIN}" "${GREEN}✅ Перехват загрузки GRUB выполнен успешно! После перезагрузки сначала введите: $target_v.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${YELLOW}⚠️ 警告：GRUB 菜单寻址失败。系统可能仍以最高版本号内核启动。${PLAIN}" "${YELLOW}⚠️ WARNING: GRUB menu addressing failed. The system may still boot with the highest version kernel.${PLAIN}" "${YELLOW}⚠️ ВНИМАНИЕ: не удалось выполнить адресацию меню GRUB. Система по-прежнему может загружаться с ядром самой последней версии.${PLAIN}")"
    return 1
}

install_cloud_kvm_kernel() {
    local arch kernel_keyword="" pkg
    local candidates=()

    if uname -r | grep -qE "kvm|cloud|virtual"; then
        echo -e "$(localized_text "${GREEN}✅ 系统当前已运行 KVM/Cloud/Virtual 优化内核 ($(uname -r))，无需重复安装！${PLAIN}" "${GREEN}✅ The system is currently running the KVM/Cloud/Virtual optimized kernel ($(uname -r)), no need to repeat the installation!${PLAIN}" "${GREEN}✅ В настоящее время в системе установлено оптимизированное ядро KVM/Cloud/Virtual ($(uname -r)), повторять установку не нужно!${PLAIN}")"
        return 0
    fi

    arch=$(normalize_kernel_arch)
    if [[ "$arch" == "unknown" ]]; then
        echo -e "$(localized_text "${RED}❌ 当前架构 $(uname -m) 暂不支持自动切换精简内核。${PLAIN}" "${RED}❌ The current architecture $(uname -m) does not currently support automatic switching of streamlined kernels.${PLAIN}" "${RED}❌ Текущая архитектура $(uname -m) в настоящее время не поддерживает автоматическое переключение оптимизированных ядер.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在安装发行版官方 Cloud/KVM/Virtual 精简内核...${PLAIN}" "${CYAN}▶ Installing the official Cloud/KVM/Virtual streamlined kernel of the distribution...${PLAIN}" "${CYAN}▶ Установка официального Cloud/KVM/Virtual оптимизированного ядра дистрибутива...${PLAIN}")"
    ensure_minimal_system_compat

    if [[ "$OS" == "debian" ]]; then
        if [[ "$arch" == "amd64" ]]; then
            candidates=("linux-image-cloud-amd64" "linux-image-amd64")
        else
            candidates=("linux-image-cloud-arm64" "linux-image-arm64")
        fi
        kernel_keyword="cloud|${arch}"
    elif [[ "$OS" == "ubuntu" ]]; then
        if [[ "$arch" == "amd64" ]]; then
            candidates=("linux-kvm" "linux-virtual" "linux-generic")
        else
            candidates=("linux-virtual" "linux-generic")
        fi
        kernel_keyword="kvm|virtual|generic"
    else
        echo -e "$(localized_text "${RED}❌ Cloud/KVM/Virtual 内核功能目前仅支持 Debian 和 Ubuntu。${PLAIN}" "${RED}❌ Cloud/KVM/Virtual kernel functionality is currently only supported on Debian and Ubuntu.${PLAIN}" "${RED}❌ Функциональность Cloud/KVM/Virtual в настоящее время поддерживается только в Debian и Ubuntu.${PLAIN}")"
        return 1
    fi

    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt_update_once || true
        unset DEBIAN_FRONTEND
    fi

    for pkg in "${candidates[@]}"; do
        if ! apt_pkg_available "$pkg"; then
            echo -e "$(localized_text "${YELLOW}  - 当前源未提供 ${pkg}，尝试下一个候选...${PLAIN}" "${YELLOW}- ${pkg} is not provided by the current source, try the next candidate...${PLAIN}" "${YELLOW}— ${pkg} не предоставлен текущим источником, попробуйте следующий кандидат...${PLAIN}")"
            continue
        fi
        echo -e "$(localized_text "${CYAN}▶ 尝试安装内核包: ${pkg}${PLAIN}" "${CYAN}▶ Try to install the kernel package: ${pkg}${PLAIN}" "${CYAN}▶ Попробуйте установить пакет ядра: ${pkg}.${PLAIN}")"
        if install_pkg "$pkg"; then
            echo -e "$(localized_text "${GREEN}✅ 已安装内核包: ${pkg}${PLAIN}" "${GREEN}✅ Kernel package installed: ${pkg}${PLAIN}" "${GREEN}✅ Установлен пакет ядра: ${pkg}${PLAIN}")"
            set_grub_default_kernel_by_keyword "$kernel_keyword"
            return $?
        fi
        echo -e "$(localized_text "${YELLOW}  - ${pkg} 安装失败，尝试下一个候选...${PLAIN}" "${YELLOW}- ${pkg} Installation failed, try next candidate...${PLAIN}" "${YELLOW}- ${pkg} Не удалось установить, попробуйте следующий вариант...${PLAIN}")"
    done

    echo -e "$(localized_text "${RED}❌ 未能安装可用的官方精简内核，请检查系统版本、架构和软件源。${PLAIN}" "${RED}❌ Unable to install the available official streamlined kernel, please check the system version, architecture and software source.${PLAIN}" "${RED}❌ Невозможно установить доступное официальное оптимизированное ядро. Проверьте версию системы, архитектуру и источник программного обеспечения.${PLAIN}")"
    return 1
}

xanmod_cpu_level() {
    local flags level="x64v1"
    flags=$(awk -F: '/flags/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
    if [[ "$flags" =~ avx2 ]] && [[ "$flags" =~ bmi2 ]] && [[ "$flags" =~ fma ]] && [[ "$flags" =~ movbe ]]; then
        level="x64v3"
    fi
    if [[ "$flags" =~ avx512f ]] && [[ "$flags" =~ avx512bw ]] && [[ "$flags" =~ avx512vl ]]; then
        level="x64v4"
    fi
    if [[ "$flags" =~ cx16 ]] && [[ "$flags" =~ lahf_lm ]] && [[ "$flags" =~ popcnt ]] && [[ "$flags" =~ sse4_2 ]]; then
        [[ "$level" == "x64v1" ]] && level="x64v2"
    fi
    echo "$level"
}

xanmod_candidate_packages() {
    local level="${1:-x64v1}"
    case "$level" in
        x64v4) printf '%s\n' linux-xanmod-lts-x64v4 linux-xanmod-x64v4 linux-xanmod-lts-x64v3 linux-xanmod-x64v3 linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        x64v3) printf '%s\n' linux-xanmod-lts-x64v3 linux-xanmod-x64v3 linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        x64v2) printf '%s\n' linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        *) printf '%s\n' linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
    esac
}

xanmod_supported_codename() {
    case "$1" in
        bookworm|trixie|forky|sid|jammy|noble|plucky) return 0 ;;
        *) return 1 ;;
    esac
}

add_xanmod_repo() {
    local codename="$1"
    local key_tmp
    mkdir -p /etc/apt/keyrings
    quarantine_path /etc/apt/keyrings/xanmod-archive-keyring.gpg "/etc/vps-optimize/quarantine/apt-keyrings" >/dev/null 2>&1 || true
    key_tmp=$(mktemp /tmp/xanmod-key.XXXXXX) || return 1
    if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 https://dl.xanmod.org/archive.key -o "$key_tmp"; then
        rm -f "$key_tmp"
        echo -e "$(localized_text "${RED}❌ XanMod GPG key 下载失败。${PLAIN}" "${RED}❌ XanMod GPG key download failed.${PLAIN}" "${RED}❌ Не удалось загрузить ключ XanMod GPG.${PLAIN}")"
        return 1
    fi
    if ! gpg --batch --yes --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg "$key_tmp"; then
        rm -f "$key_tmp"
        echo -e "$(localized_text "${RED}❌ XanMod GPG key 下载或写入失败。${PLAIN}" "${RED}❌ XanMod GPG key download or write failed.${PLAIN}" "${RED}❌ Не удалось загрузить или записать ключ XanMod GPG.${PLAIN}")"
        return 1
    fi
    rm -f "$key_tmp"
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${codename} main" > /etc/apt/sources.list.d/xanmod-release.list
    apt-get update -qq && APT_UPDATED=1
}

install_xanmod_kernel_package() {
    local preferred_level="$1"
    local pkg
    while IFS= read -r pkg; do
        apt_pkg_available "$pkg" || continue
        echo -e "$(localized_text "${CYAN}▶ 尝试安装 XanMod 包: ${pkg}${PLAIN}" "${CYAN}▶ Try to install the XanMod package: ${pkg}${PLAIN}" "${CYAN}▶ Попробуйте установить пакет XanMod: ${pkg}.${PLAIN}")"
        if install_pkg "$pkg"; then
            echo -e "$(localized_text "${GREEN}✅ 已安装 XanMod 内核包: ${pkg}${PLAIN}" "${GREEN}✅ XanMod kernel package installed: ${pkg}${PLAIN}" "${GREEN}✅ Установлен пакет ядра XanMod: ${pkg}${PLAIN}")"
            return 0
        fi
        echo -e "$(localized_text "${YELLOW}  - ${pkg} 安装失败，尝试更保守候选...${PLAIN}" "${YELLOW}- ${pkg} Installation failed, try more conservative candidate...${PLAIN}" "${YELLOW}- ${pkg} Не удалось установить, попробуйте более консервативный вариант...${PLAIN}")"
    done < <(xanmod_candidate_packages "$preferred_level")

    return 1
}

install_xanmod_kernel() {
    local codename confirm arch cpu_level

    if uname -r | grep -qi "xanmod"; then
        echo -e "$(localized_text "${GREEN}✅ 系统当前已运行 XanMod 内核 ($(uname -r))，无需重复安装！${PLAIN}" "${GREEN}✅ The system is currently running the XanMod kernel ($(uname -r)), no need to reinstall!${PLAIN}" "${GREEN}✅ В настоящее время в системе установлено ядро XanMod ($(uname -r)), переустанавливать не нужно!${PLAIN}")"
        return 0
    fi

    if ! is_debian; then
        echo -e "$(localized_text "${RED}❌ XanMod 自动安装目前仅支持 Debian/Ubuntu 衍生系统。${PLAIN}" "${RED}❌ XanMod automatic installation currently only supports Debian/Ubuntu derivative systems.${PLAIN}" "${RED}❌ Автоматическая установка XanMod в настоящее время поддерживает только производные системы Debian/Ubuntu.${PLAIN}")"
        return 1
    fi

    arch=$(normalize_kernel_arch)
    if [[ "$arch" != "amd64" ]]; then
        echo -e "$(localized_text "${RED}❌ XanMod 官方 x64v 内核仅支持 x86_64/amd64，本机为 $(uname -m)。${PLAIN}" "${RED}❌ XanMod official x64v kernel only supports x86_64/amd64, this machine is $(uname -m).${PLAIN}" "${RED}❌ Официальное ядро ​​XanMod x64v поддерживает только x86_64/amd64, эта машина — $(uname -m).${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}建议改用官方 Cloud/Virtual 内核。${PLAIN}" "${YELLOW}Recommends using the official Cloud/Virtual kernel instead.${PLAIN}" "${YELLOW}рекомендует вместо этого использовать официальное облачное/виртуальное ядро.${PLAIN}")"
        return 1
    fi

    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi
    if [[ -z "$codename" ]]; then
        echo -e "$(localized_text "${RED}❌ 无法识别系统代号，无法安全添加 XanMod 源。${PLAIN}" "${RED}❌ The system code cannot be recognized and the XanMod source cannot be safely added.${PLAIN}" "${RED}❌ Невозможно распознать системный код и безопасно добавить источник XanMod.${PLAIN}")"
        return 1
    fi
    if ! xanmod_supported_codename "$codename"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 当前系统代号 ${codename} 可能不在脚本内置 XanMod 兼容列表中。${PLAIN}" "${YELLOW}⚠️ The current system code ${codename} may not be in the XanMod compatibility list built into the script.${PLAIN}" "${YELLOW}⚠️ Текущий системный код ${codename} может отсутствовать в списке совместимости XanMod, встроенном в скрипт.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}脚本仍会尝试添加源；若 apt update 失败，请改用官方 Cloud/Virtual 内核。${PLAIN}" "${YELLOW}The script will still try to add the source; if apt update fails, please use the official Cloud/Virtual kernel instead.${PLAIN}" "${YELLOW}Сценарий все равно попытается добавить источник; Если обновление apt не удалось, используйте вместо него официальное облачное/виртуальное ядро.${PLAIN}")"
    fi

    cpu_level=$(xanmod_cpu_level)

    echo -e "$(localized_text "${RED}⚠️  XanMod 是第三方性能内核，可能影响 DKMS/驱动/部分云厂商兼容性。${PLAIN}" "${RED}⚠️ XanMod is a third-party performance kernel, which may affect DKMS/driver/some cloud vendor compatibility.${PLAIN}" "${RED}⚠️ XanMod — это ядро производительности стороннего производителя, которое может повлиять на совместимость DKMS/драйвера/некоторых облачных поставщиков.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}检测到 CPU 兼容级别：${cpu_level}，将从对应 XanMod LTS 包开始尝试，并自动向下兜底。${PLAIN}" "${YELLOW}Detects the CPU compatibility level: ${cpu_level}, and will start trying from the corresponding XanMod LTS package and automatically search downwards.${PLAIN}" "${YELLOW}определяет уровень совместимости ЦП: ${cpu_level}, начинает попытки из соответствующего пакета XanMod LTS и автоматически выполняет поиск вниз.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}建议先确认有快照、救援控制台，且知道如何从 GRUB 切回旧内核。${PLAIN}" "${YELLOW}It is recommended to first confirm that you have a snapshot, rescue console, and know how to switch back to the old kernel from GRUB.${PLAIN}" "${YELLOW}Рекомендуется сначала подтвердить, что у вас есть снимок, консоль восстановления и вы знаете, как вернуться к старому ядру из GRUB.${PLAIN}")"
    confirm_risk_action "$(localized_text "安装 XanMod 内核" "Install XanMod kernel" "Установите ядро XanMod.")" \
        "$(localized_text "内核包、引导配置和 GRUB 菜单" "Kernel packages, boot configurations, and GRUB menus" "Пакеты ядра, конфигурации загрузки и меню GRUB")" \
        "$(localized_text "使用当前可启动内核或云厂商救援模式恢复" "Recovery using current bootable kernel or cloud vendor rescue mode" "Восстановление с использованием текущего загрузочного ядра или режима восстановления облачного поставщика.")" \
        "$(localized_text "建议先创建 VPS 快照，并确认不是 OpenVZ 老系统。" "It is recommended to create a VPS snapshot first and confirm that it is not the old system OpenVZ." "Рекомендуется сначала создать снимок VPS и убедиться, что это не старая система OpenVZ.")" || { echo -e "$(localized_text "${BLUE}已取消 XanMod 安装。${PLAIN}" "${BLUE}XanMod installation has been canceled.${PLAIN}" "${BLUE}Установка XanMod отменена.${PLAIN}")"; return 1; }

    echo -e "$(localized_text "${CYAN}▶ 正在添加 XanMod 官方 APT 源并安装兼容内核...${PLAIN}" "${CYAN}▶ Adding XanMod official APT source and installing compatible kernel...${PLAIN}" "${CYAN}▶ Добавление официального источника APT XanMod и установка совместимого ядра...${PLAIN}")"
    ensure_minimal_system_compat
    install_pkg ca-certificates curl gpg gnupg || return 1
    add_xanmod_repo "$codename" || return 1

    if ! install_xanmod_kernel_package "$cpu_level"; then
        echo -e "$(localized_text "${RED}❌ XanMod 内核安装失败，可能是当前系统代号/软件源/CPU 级别暂不兼容。${PLAIN}" "${RED}❌ The XanMod kernel installation failed. It may be that the current system code/software source/CPU level is temporarily incompatible.${PLAIN}" "${RED}❌ Не удалось установить ядро XanMod. Возможно, текущий системный код/исходный код программного обеспечения/уровень ЦП временно несовместим.${PLAIN}")"
        return 1
    fi

    set_grub_default_kernel_by_keyword "xanmod"
}

func_install_kernel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}☁️  安装/切换优化内核${PLAIN}" "${BOLD}☁️ Install/switch optimized kernel${PLAIN}" "${BOLD}☁️ Установить/переключить оптимизированное ядро${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}  1. Cloud/KVM/Virtual 官方云内核${PLAIN} ${YELLOW}(推荐：稳定、轻量、云厂商兼容更好)${PLAIN}" "${GREEN}1. Cloud/KVM/Virtual official cloud kernel (recommended: stable, lightweight, better compatible with cloud vendors)${PLAIN}" "${GREEN}1. Облако/KVM/Официальное виртуальное облачное ядро (рекомендуется: стабильное, легкое, лучше совместимое с поставщиками облачных услуг)${PLAIN}")"
    echo -e "$(localized_text "     Debian/Ubuntu 会按架构自动尝试 cloud/kvm/virtual/generic 候选。" "Debian/Ubuntu will automatically try the cloud/kvm/virtual/generic candidate by architecture." "Debian/Ubuntu автоматически попробует кандидата Cloud/kvm/virtual/generic по архитектуре.")"
    echo -e "$(localized_text "${GREEN}  2. XanMod 性能内核${PLAIN} ${YELLOW}(高级：自动匹配 x64v1-v4 并向下兜底)${PLAIN}" "${GREEN}2. XanMod performance core (Advanced: automatically match x64v1-v4 and dig down)${PLAIN}" "${GREEN}2. Ядро производительности XanMod (Дополнительно: автоматическое сопоставление x64v1-v4 и поиск)${PLAIN}")"
    echo -e "$(localized_text "     适合：愿意折腾、追求低延迟/新特性；仅 amd64，建议有快照或救援控制台。" "Suitable for: willing to toss, pursuing low latency/new features; amd64 only, snapshot or rescue console recommended." "Подходит для: желающих бросить, стремящихся к низкой задержке/новым функциям; Только amd64, рекомендуется снимок или консоль восстановления.")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Return / q Return${PLAIN}" "${RED}0. Возврат / q Возврат${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local kernel_choice virt
    read_trimmed kernel_choice "$(localized_text "👉 请选择要安装的内核类型 [推荐 1]: " "👉 Please select the kernel type to install [Recommended 1]:" "👉 Пожалуйста, выберите тип ядра для установки [рекомендуется 1]:")"
    kernel_choice="${kernel_choice:-1}"
    [[ "$kernel_choice" == "0" ]] && return

    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    if [[ "$virt" =~ lxc|openvz ]]; then
        echo -e "$(localized_text "${RED}❌ 致命错误：检测到当前 VPS 为 $virt 容器架构！${PLAIN}" "${RED}❌ Fatal error: The current VPS is detected as $virt container architecture!${PLAIN}" "${RED}❌ Неустранимая ошибка: текущий VPS определен как контейнерная архитектура $virt!${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}💡 容器与母机共享内核，无法更改内核。操作已安全中止。${PLAIN}" "${YELLOW}💡 The container and the host machine share the kernel, and the kernel cannot be changed. The operation has been safely aborted.${PLAIN}" "${YELLOW}💡 Контейнер и хост-машина используют общее ядро, и ядро нельзя изменить. Операция благополучно прервана.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    local arch
    arch=$(normalize_kernel_arch)
    if [[ "$arch" == "unknown" ]]; then
        echo -e "$(localized_text "${RED}❌ 致命错误：当前架构暂不支持自动切换内核，本机为 $(uname -m)！${PLAIN}" "${RED}❌ Fatal error: The current architecture does not support automatic kernel switching. This machine is $(uname -m)!${PLAIN}" "${RED}❌ Неустранимая ошибка: текущая архитектура не поддерживает автоматическое переключение ядра. Эта машина $(uname -m)!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    if [[ "$kernel_choice" == "2" && "$arch" != "amd64" ]]; then
        echo -e "$(localized_text "${RED}❌ XanMod x64v 内核仅支持 x86_64/amd64，本机为 $(uname -m)。${PLAIN}" "${RED}❌ XanMod x64v kernel only supports x86_64/amd64, natively $(uname -m).${PLAIN}" "${RED}❌ Ядро XanMod x64v поддерживает только x86_64/amd64, изначально $(uname -m).${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}建议选择 [1] 官方 Cloud/KVM/Virtual 内核。${PLAIN}" "${YELLOW}For , it is recommended to choose [1] official Cloud/KVM/Virtual kernel.${PLAIN}" "${YELLOW}Для рекомендуется выбрать [1] официальное ядро Cloud/KVM/Virtual.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    local install_rc=0
    case "$kernel_choice" in
        1) install_cloud_kvm_kernel ;;
        2) install_xanmod_kernel ;;
        *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return ;;
    esac
    install_rc=$?
    if [[ "$install_rc" -ne 0 ]]; then
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${YELLOW}⚠️ 内核安装/切换未完成，未继续提示重启。${PLAIN}" "${YELLOW}⚠️ The kernel installation/switching is not completed and the prompt to restart is not continued.${PLAIN}" "${YELLOW}⚠️ Установка/переключение ядра не завершено, а запрос на перезагрузку не продолжается.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}⚠️ 核心生效指引：${PLAIN}" "${YELLOW}⚠️ Core Validation Guide:${PLAIN}" "${YELLOW}⚠️ Руководство по проверке ядра:${PLAIN}")"
    echo -e "$(localized_text "1. 新内核引导已配置完毕，请先选择主菜单的 ${RED}[17] 重启服务器${PLAIN}。" "1. The new kernel boot configuration has been completed. Please select ${RED}[17] in the main menu to restart the server${PLAIN}." "1. Новая конфигурация загрузки ядра завершена. Пожалуйста, выберите ${RED}[17] в главном меню, чтобы перезапустить сервер${PLAIN}.")"
    echo -e "$(localized_text "2. 重启后请运行 ${GREEN}uname -r${PLAIN} 确认实际进入的新内核。" "2. After restarting, please run ${GREEN}Uname -r${PLAIN} to confirm the new kernel actually entered." "2. После перезапуска запустите ${GREEN}uname -r${PLAIN}, чтобы подтвердить, что новое ядро действительно введено.")"
    echo -e "$(localized_text "3. 确认稳定后，再进入本菜单选择 ${GREEN}[5] 清理旧内核${PLAIN}。" "3. After confirming that it is stable, enter this menu and select ${GREEN}[5] to clean up the old kernel${PLAIN}." "3. Убедившись, что оно стабильно, войдите в это меню и выберите ${GREEN}[5], чтобы очистить старое ядро${PLAIN}.")"

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

# ---------------------------------------------------------
# 10. 清理冗余旧内核 (数组菜单驱动 + 核心防砖拦截版)
# ---------------------------------------------------------
func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "$(localized_text "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}" "${RED}❌ This function currently only supports Debian/Ubuntu derivative systems!${PLAIN}" "${RED}❌ В настоящее время эта функция поддерживает только производные системы Debian/Ubuntu!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    local current_k
    current_k=$(uname -r)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧹 清理冗余旧内核${PLAIN}" "${BOLD}🧹 Clean up redundant old core${PLAIN}" "${BOLD}🧹 Очистите избыточное старое ядро${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "当前正在运行的内核为: ${GREEN}${current_k}${PLAIN}" "The currently running kernel is: ${GREEN}${current_k}${PLAIN}" "Текущее работающее ядро: ${GREEN}${current_k}${PLAIN}.")"
    echo -e "$(localized_text "${RED}⚠️ 系统已自动为您屏蔽正在运行的内核以及常用云/虚拟化/性能内核。${PLAIN}" "${RED}⚠️ The system has automatically blocked running kernels and commonly used cloud/virtualization/performance kernels for you.${PLAIN}" "${RED}⚠️ Система автоматически заблокировала для вас работающие ядра и часто используемые облачные ядра/ядра виртуализации/производительности.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    # 自动提取所有非当前的内核包存入数组 (排除元包，采用高可用字段匹配)
    mapfile -t old_kernels < <(dpkg -l | awk '$1 == "ii" && $2 ~ /^linux-image-[0-9]/ {print $2}' | grep -v "$current_k" | grep -Ev "cloud|kvm|virtual|generic|xanmod")

    if [[ ${#old_kernels[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 系统非常干净，没有发现需要清理的冗余旧内核。${PLAIN}" "${GREEN}✅ The system is very clean and no redundant old cores that need to be cleaned are found.${PLAIN}" "${GREEN}✅ Система очень чистая и не обнаружено лишних старых ядер, требующих очистки.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "${YELLOW}扫描到以下冗余内核可供清理：${PLAIN}" "${YELLOW}Scanned the following redundant cores for cleaning:${PLAIN}" "${YELLOW}просканировал следующие резервные ядра для очистки:${PLAIN}")"
    for i in "${!old_kernels[@]}"; do
        echo -e " [${CYAN}$((i+1))${PLAIN}] ${old_kernels[$i]}"
    done
    echo -e "$(localized_text " [${RED}0${PLAIN}] 取消并返回" "[${RED}0${PLAIN}] Cancel and return" "[${RED}0${PLAIN}] Отменить и вернуться")"
    echo -e "------------------------------------------------"

    local k_choice
    read_trimmed k_choice "$(localized_text "👉 请输入要卸载的序号: " "👉 Please enter the serial number to be uninstalled:" "👉 Пожалуйста, введите серийный номер для удаления:")"

    if [[ "$k_choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消卸载操作。${PLAIN}" "${BLUE}The uninstall operation has been canceled.${PLAIN}" "${BLUE}Операция удаления отменена.${PLAIN}")"
    elif [[ "$k_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$k_choice" -le "${#old_kernels[@]}" ]]; then
        local target_k="${old_kernels[$((k_choice-1))]}"
        confirm_danger "$(localized_text "卸载旧内核 ${target_k}" "Uninstall old kernel ${target_k}" "Удалить старое ядро ${target_k}")" "$(localized_text "会删除内核包并刷新 GRUB，引导异常时可能影响下次启动。" "The kernel package will be deleted and GRUB will be refreshed. If the boot is abnormal, it may affect the next startup." "Пакет ядра будет удален, а GRUB будет обновлен. Если загрузка ненормальная, это может повлиять на следующий запуск.")" "$(localized_text "建议先创建 VPS 快照；当前运行内核已自动排除，如失败请从快照或救援模式恢复。" "It is recommended to create a VPS snapshot first; the currently running kernel has been automatically excluded. If it fails, please restore from the snapshot or rescue mode." "Рекомендуется сначала создать снимок VPS; работающее в данный момент ядро ​​было автоматически исключено. В случае сбоя восстановите систему из снимка или режима восстановления.")" || {
            echo -e "$(localized_text "${BLUE}已取消卸载操作。${PLAIN}" "${BLUE}The uninstall operation has been canceled.${PLAIN}" "${BLUE}Операция удаления отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        }
        echo -e "$(localized_text "${CYAN}正在静默卸载 $target_k 并刷新引导...${PLAIN}" "${CYAN}Is silently uninstalling $target_k and refreshing the boot...${PLAIN}" "${CYAN}автоматически удаляет $target_k и обновляет загрузку...${PLAIN}")"
        export DEBIAN_FRONTEND=noninteractive
        if apt-get purge -yq "$target_k" && update-grub >/dev/null 2>&1 && apt-get autoremove --purge -yq >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 旧内核 [$target_k] 清理完成！磁盘空间已释放。${PLAIN}" "${GREEN}✅ Old kernel [$target_k] cleanup completed! Disk space has been released.${PLAIN}" "${GREEN}✅ Очистка старого ядра [$target_k] завершена! Дисковое пространство освобождено.${PLAIN}")"
        else
            echo -e "$(localized_text "${RED}❌ 清理失败！存在依赖问题或执行被中断。${PLAIN}" "${RED}❌ Cleanup failed! There is a dependency issue or execution is interrupted.${PLAIN}" "${RED}❌ Очистка не удалась! Возникла проблема с зависимостями или выполнение прервано.${PLAIN}")"
        fi
        unset DEBIAN_FRONTEND
    else
        echo -e "$(localized_text "${RED}❌ 无效的选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

# ---------------------------------------------------------
# 11. 极速硬件探针
# ---------------------------------------------------------
