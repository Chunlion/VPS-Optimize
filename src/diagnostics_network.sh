# shellcheck shell=bash
# 443 network probes, benchmark script launchers, and port-dog integration.

probe_host_for_listen_addr() {
    local addr="$1"
    case "$addr" in
        ""|"0.0.0.0"|"::"|"[::]") echo "127.0.0.1" ;;
        *:*) echo "localhost" ;;
        *) echo "$addr" ;;
    esac
}

tcp_probe_host() {
    local label="$1"
    local host="$2"
    local port="$3"
    local attempts="${4:-3}"
    local delay="${5:-1}"
    local i

    for ((i = 1; i <= attempts; i++)); do
        if tcp_probe_once "$host" "$port"; then
            echo -e "$(localized_text "${GREEN}✅ ${label}: ${host}:${port} 可连接${PLAIN}" "${GREEN}✅ ${label}: ${host}:${port} is reachable${PLAIN}" "${GREEN}✅ ${label}: ${host}:${port} доступен${PLAIN}")"
            return 0
        fi
        if local_listen_socket_matches_probe "$host" "$port"; then
            echo -e "$(localized_text "${GREEN}✅ ${label}: ${host}:${port} 已检测到本地监听${PLAIN}" "${GREEN}✅ ${label}: ${host}:${port} Local listening has been detected${PLAIN}" "${GREEN}✅ ${label}: ${host}:${port} Обнаружено локальное прослушивание${PLAIN}")"
            return 0
        fi
        [[ "$i" -lt "$attempts" ]] && sleep "$delay"
    done

    echo -e "$(localized_text "${RED}❌ ${label}: ${host}:${port} 连接失败${PLAIN}" "${RED}❌ ${label}: ${host}:${port} Connection failed${PLAIN}" "${RED}❌ ${label}: ${host}:${port} Не удалось подключиться${PLAIN}")"
    return 1
}

tcp_probe_once() {
    local host="$1"
    local port="$2"

    tcp_target_reachable "$host" "$port"
}

is_loopback_probe_host() {
    case "$1" in
        127.*|localhost|::1|"[::1]") return 0 ;;
        *) return 1 ;;
    esac
}

local_listen_socket_matches_probe() {
    local host="$1"
    local port="$2"
    local endpoint

    is_loopback_probe_host "$host" || return 1
    command -v ss >/dev/null 2>&1 || return 1

    while IFS= read -r endpoint; do
        [[ -n "$endpoint" ]] || continue
        case "$endpoint" in
            127.*:"$port"|0.0.0.0:"$port"|\*:"$port"|"[::1]":"$port"|"[::]":"$port")
                return 0
                ;;
        esac
    done < <(ss -H -lnt 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print $4}')

    return 1
}

probe_tls_sni_certificate() {
    local label="$1"
    local host="$2"
    local port="$3"
    local sni="$4"
    local connect_target

    if ! command -v timeout >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${label}: 缺少 timeout 或 openssl，跳过 TLS/SNI 证书探测。${PLAIN}" "${YELLOW}⚠️ ${label}: Missing timeout or openssl, skipping TLS/SNI certificate detection.${PLAIN}" "${YELLOW}⚠️ ${label}: отсутствует тайм-аут или открытие ssl, пропуск обнаружения сертификата TLS/SNI.${PLAIN}")"
        return 0
    fi

    connect_target=$(format_hostport "$host" "$port")
    if timeout 10 openssl s_client -connect "$connect_target" -servername "$sni" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        echo -e "$(localized_text "${GREEN}✅ ${label}: ${connect_target} / SNI ${sni} 已返回证书链${PLAIN}" "${GREEN}✅ ${label}: ${connect_target} / SNI ${sni} Certificate chain has been returned${PLAIN}" "${GREEN}✅ ${label}: ${connect_target} / SNI ${sni} Цепочка сертификатов возвращена${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${RED}❌ ${label}: ${connect_target} / SNI ${sni} 未正常返回证书链${PLAIN}" "${RED}❌ ${label}: ${connect_target} / SNI ${sni} The certificate chain is not returned normally${PLAIN}" "${RED}❌ ${label}: ${connect_target} / SNI ${sni} Цепочка сертификатов не возвращается нормально${PLAIN}")"
    return 1
}

https_url_for_port() {
    local host="$1"
    local port="$2"
    local path="$3"
    if [[ "$port" == "443" ]]; then
        printf 'https://%s%s' "$host" "$path"
    else
        printf 'https://%s:%s%s' "$host" "$port" "$path"
    fi
}

curl_sni_path_probe() {
    local label="$1"
    local domain="$2"
    local port="$3"
    local path="$4"
    local url code curl_rc
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${label}: 缺少 curl，跳过 HTTPS 路径探测。${PLAIN}" "${YELLOW}⚠️ ${label}: Missing curl, skipping HTTPS path detection.${PLAIN}" "${YELLOW}⚠️ ${label}: отсутствует curl, пропускается обнаружение пути HTTPS.${PLAIN}")"
        return 1
    fi
    url=$(https_url_for_port "$domain" "$port" "$path")
    code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 12 --resolve "${domain}:${port}:127.0.0.1" "$url" 2>/dev/null)
    curl_rc=$?
    if [[ "$curl_rc" -ne 0 || ! "$code" =~ ^[0-9]{3}$ || "$code" == "000" ]]; then
        echo -e "$(localized_text "${RED}❌ ${label}: ${url} 无响应或 TLS/SNI 失败（curl exit ${curl_rc}, HTTP ${code:-000}）${PLAIN}" "${RED}❌ ${label}: ${url} does not respond or TLS/SNI fails (curl exit ${curl_rc}, HTTP ${code:-000})${PLAIN}" "${RED}❌ ${label}: ${url} не отвечает или TLS/SNI завершается с ошибкой (curl выходит из ${curl_rc}, HTTP ${code:-000})${PLAIN}")"
        return 1
    fi
    case "$code" in
        404)
            echo -e "$(localized_text "${YELLOW}⚠️ ${label}: ${url} HTTP ${code}，443/SNI 已到达，但路径或后端可能不匹配。${PLAIN}" "${YELLOW}⚠️ ${label}: ${url} HTTP ${code}, 443/SNI arrived, but the path or backend may not match.${PLAIN}" "${YELLOW}⚠️ ${label}: ${url} HTTP ${code}, 443/SNI прибыло, но путь или бэкенд могут не совпадать.${PLAIN}")"
            return 0
            ;;
        *)
            echo -e "${GREEN}✅ ${label}: ${url} HTTP ${code}${PLAIN}"
            return 0
            ;;
    esac
}

tls_sni_probe_local() {
    local label="$1"
    local sni="$2"
    local port="$3"
    if ! command -v openssl >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ ${label}: 缺少 openssl/timeout，跳过 TLS SNI 探测。${PLAIN}" "${YELLOW}⚠️ ${label}: Missing openssl/timeout, skipping TLS SNI detection.${PLAIN}" "${YELLOW}⚠️ ${label}: отсутствует openssl/тайм-аут, пропуск обнаружения TLS SNI.${PLAIN}")"
        return 1
    fi
    if timeout 10 openssl s_client -connect "127.0.0.1:${port}" -servername "$sni" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        echo -e "$(localized_text "${GREEN}✅ ${label}: Nginx 入口能按 ${sni} 命中 TLS 证书链${PLAIN}" "${GREEN}✅ ${label}: Nginx entry can press ${sni} to hit TLS certificate chain${PLAIN}" "${GREEN}✅ ${label}: вход Nginx может нажать ${sni}, чтобы попасть в цепочку сертификатов TLS${PLAIN}")"
        return 0
    fi
    echo -e "$(localized_text "${YELLOW}⚠️ ${label}: 未拿到证书链，请检查 Nginx stream、Caddy 证书或 SNI。${PLAIN}" "${YELLOW}⚠️ ${label}: Did not get the certificate chain, please check Nginx stream, Caddy certificate or SNI.${PLAIN}" "${YELLOW}⚠️ ${label}: Не получена цепочка сертификатов, проверьте сертификат Nginx stream, Caddy или SNI.${PLAIN}")"
    return 1
}

func_443_network_test() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "测速与质量检测 > 443 单入口测试" "Speed Test and Quality Test > 443 Shared Entry Test" "Тестирование скорости и качества > Тест 443 с одним входом")"
    echo -e "$(localized_text "${BOLD}🧪 443 单入口网络访问测试${PLAIN}" "${BOLD}🧪 443 shared entry network access test${PLAIN}" "${BOLD}🧪 443 Тест доступа к сети с одним входом${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    if [[ ! -f /etc/vps-optimize/sni-stack.env ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到 443 单入口配置。请先进入 [19] -> [2] 安装入口。${PLAIN}" "${YELLOW}No shared 443 entry configuration was found. Use [19] -> [2] to install it first.${PLAIN}" "${YELLOW}Конфигурация общего входа 443 не найдена. Сначала установите её через [19] -> [2].${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    load_sni_stack_env || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    echo -e "$(localized_text "面板入口：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}" "Panel entry: https://${PANEL_DOMAIN}${PANEL_WEB_PATH}" "Входная панель: https://${PANEL_DOMAIN}${PANEL_WEB_PATH}")"
    echo -e "$(localized_text "订阅入口：https://${PANEL_DOMAIN}${SUB_URI_PATH}" "Subscription entry: https://${PANEL_DOMAIN}${SUB_URI_PATH}" "Вход по подписке: https://${PANEL_DOMAIN}${SUB_URI_PATH}")"
    echo -e "Clash/Mihomo：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "REALITY SNI：${REALITY_SNI}:${NGINX_LISTEN_PORT} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "------------------------------------------------"

    check_domain_dns_sanity "$PANEL_DOMAIN" "$(localized_text "面板域名" "Panel domain" "Доменное имя панели")" "warn" || true
    [[ "$PANEL_DOMAIN" != "$REALITY_SNI" ]] && check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "warn" || true

    echo -e "------------------------------------------------"
    tcp_probe_host "$(localized_text "公网入口 TCP" "public entry TCP" "Вход в публичную сеть TCP")" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" || true
    tcp_probe_host "$(localized_text "本机 Nginx 入口" "This machine Nginx entry" "Эта машина Nginx вход")" "127.0.0.1" "$NGINX_LISTEN_PORT" || true
    tcp_probe_host "$(localized_text "$(web_proxy_engine_label) 本地 TLS" "$(web_proxy_engine_label) local TLS" "$(web_proxy_engine_label) локальный TLS")" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "$(localized_text "3x-ui 面板后端" "3x-ui panel backend" "бэкенд панели 3x-ui")" "$(probe_host_for_listen_addr "$PANEL_LISTEN_ADDR")" "$PANEL_LISTEN_PORT" || true
    tcp_probe_host "$(localized_text "3x-ui 订阅后端" "3x-ui subscription backend" "Сервер подписки 3x-ui")" "$(probe_host_for_listen_addr "$SUB_LISTEN_ADDR")" "$SUB_LISTEN_PORT" || true
    tcp_probe_host "$(localized_text "REALITY 本地入站" "REALITY local inbound" "REALITY локальное входящее подключение")" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true

    echo -e "------------------------------------------------"
    tls_sni_probe_local "$(localized_text "面板 SNI TLS" "Panel SNI TLS" "Панель SNI TLS")" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" || true
    curl_sni_path_probe "$(localized_text "面板路径" "Panel path" "Путь панели")" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$PANEL_WEB_PATH" || true
    curl_sni_path_probe "$(localized_text "普通订阅路径" "Common subscription path" "Общий путь подписки")" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$SUB_URI_PATH" || true
    curl_sni_path_probe "$(localized_text "Clash/Mihomo 路径" "Clash/Mihomo path" "Clash/Mihomo путь")" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$CLASH_URI_PATH" || true

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}说明：HTTP 401/403/302 通常表示链路已到达后端；404 多数是路径或 3x-ui 订阅设置不一致。${PLAIN}" "${YELLOW}Description: HTTP 401/403/302 usually indicates that the link has reached the backend; 404 is mostly caused by inconsistent paths or 3x-ui subscription settings.${PLAIN}" "${YELLOW}Описание: HTTP 401/403/302 обычно указывает, что ссылка достигла серверной части; Ошибка 404 в основном вызвана несогласованными путями или настройками подписки 3x-ui.${PLAIN}")"
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}📊 VPS 综合测速与质量检验合集库${PLAIN}" "${BOLD}📊 VPS comprehensive speed measurement and quality inspection collection library${PLAIN}" "${BOLD}📊 Комплексная библиотека VPS для измерения скорости и контроля качества${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${GREEN}  1. YABS 硬件性能测试      ${YELLOW}  2. SuperBench 综合测速${PLAIN}" "${GREEN}1. YABS hardware performance test 2. SuperBench comprehensive speed test${PLAIN}" "${GREEN}1. YABS тест производительности оборудования 2. Комплексный тест скорости SuperBench${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. bench.sh 基础测试      ${YELLOW}  4. 融合怪详细测速${PLAIN}" "${GREEN}3. bench.sh basic test 4. Fusion monster detailed speed test${PLAIN}" "${GREEN}3. Базовый тест Bench.sh 4. Подробный тест скорости Fusion Monster${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 三网回程路由测试       ${YELLOW}  6. IP 质量 / 欺诈度检测${PLAIN}" "${GREEN}5. Three network backhaul routing test 6. IP quality/fraud detection${PLAIN}" "${GREEN}5. Тест маршрутизации для трех сетей 6. Качество IP/обнаружение мошенничества${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. NodeSeek 综合测试      ${YELLOW}  8. 流媒体解锁检测${PLAIN}" "${GREEN}7. NodeSeek comprehensive test 8. Streaming media unlocking test${PLAIN}" "${GREEN}7. Комплексный тест NodeSeek 8. Тест разблокировки потокового мультимедиа${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  9. TcpQuality TCP 质量测试${PLAIN}" "${GREEN}9. TcpQuality TCP Quality test${PLAIN}" "${GREEN}9. TcpКачество TCP Проверка качества${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local t
        local ran_test=false
        read_trimmed t "$(localized_text "👉 请输入对应序号选择: " "👉 Please enter the corresponding serial number to select:" "👉 Пожалуйста, введите соответствующий серийный номер, чтобы выбрать:")"
        case $t in
            1) ran_test=true; run_remote_script "$(localized_text "运行 YABS 硬件性能测试" "Run the YABS hardware performance test" "Запустите тест производительности оборудования YABS.")" "https://yabs.sh" ;;
            2) ran_test=true; run_remote_script "$(localized_text "运行 SuperBench 综合测速" "Run SuperBench comprehensive speed test" "Запустите комплексный тест скорости SuperBench")" "https://about.superbench.pro" ;;
            3) ran_test=true; run_remote_script "$(localized_text "运行 bench.sh 基础测试" "Run bench.sh basic test" "Запустите базовый тест Bench.sh")" "https://bench.sh" ;;
            4) ran_test=true; run_remote_script "$(localized_text "运行融合怪详细测速" "Run the fusion monster detailed speed test" "Запустите подробный тест скорости Fusion Monster")" "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh" ;;
            5) ran_test=true; run_remote_script "$(localized_text "运行三网回程路由测试" "Run the three-network backhaul routing test" "Запустите тест транспортной маршрутизации для трех сетей.")" "https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh" ;;
            6) ran_test=true; run_remote_script "$(localized_text "运行 IP 质量 / 欺诈度检测" "Run IP quality/fraud detection" "Запустите качество IP/обнаружение мошенничества")" "https://IP.Check.Place" ;;
            7) ran_test=true; run_remote_script "$(localized_text "运行 NodeSeek 综合测试" "Run NodeSeek synthetic tests" "Запуск синтетических тестов NodeSeek")" "https://run.NodeQuality.com" ;;
            8) ran_test=true; run_remote_script "$(localized_text "运行流媒体解锁检测" "Run streaming unblock detection" "Запустить обнаружение разблокировки потоковой передачи")" "https://check.unlock.media" ;;
            9) ran_test=true; run_remote_script "$(localized_text "运行 TcpQuality TCP 质量测试" "Run the TcpQuality TCP quality test" "Запустите тест качества TcpQuality TCP.")" "https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh" ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效的选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1; continue ;;
        esac
        echo ""
        if [[ "$ran_test" == "true" ]]; then
            pause_after_external_script "$(localized_text "操作结束，按回车键返回测试菜单..." "When the operation is over, press Enter to return to the test menu..." "По завершении операции нажмите Enter, чтобы вернуться в тестовое меню...")"
        fi
    done
}

func_server_bandwidth_test() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "网络/内核优化 > 服务器带宽测试" "Network/Kernel Optimization > Server Bandwidth Test" "Оптимизация сети/ядра > Тест пропускной способности сервера")"
    echo -e "$(localized_text "${BOLD}📶 服务器带宽测试${PLAIN}" "${BOLD}📶 Server bandwidth test${PLAIN}" "${BOLD}📶 Тест пропускной способности сервера${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    if ! ensure_speedtest_client; then
        echo -e "$(localized_text "${RED}测速客户端安装失败，无法执行测试。${PLAIN}" "${RED}Speed test client failed to install and the test could not be executed.${PLAIN}" "${RED}Клиент теста скорости не удалось установить, и тест не удалось выполнить.${PLAIN}")"
        pause_return
        return 1
    fi

    echo -e "$(localized_text "${YELLOW}测速会产生较大流量，结果受测速节点和线路负载影响。${PLAIN}" "${YELLOW}Speed measurement will generate a large amount of traffic, and the results will be affected by the speed measurement node and line load.${PLAIN}" "${YELLOW}Измерение скорости будет генерировать большой объем трафика, а на результаты будут влиять узел измерения скорости и нагрузка на линию.${PLAIN}")"
    echo ""
    if run_speedtest_client; then
        echo -e "$(localized_text "${GREEN}✅ 带宽测试完成。${PLAIN}" "${GREEN}✅ Bandwidth test completed.${PLAIN}" "${GREEN}✅ Тест пропускной способности завершен.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}带宽测试失败，请检查网络连通性或更换测速时段。${PLAIN}" "${RED}Bandwidth test failed, please check the network connectivity or change the speed test period.${PLAIN}" "${RED}Проверка пропускной способности не удалась. Проверьте подключение к сети или измените период проверки скорости.${PLAIN}")"
    fi
    pause_return
}

func_iperf3_single_thread_test() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "$(localized_text "网络/内核优化 > iperf3 单线程测试" "Network/kernel optimization > iperf3 single-thread test" "Оптимизация сети/ядра > Однопоточный тест iperf3")"
    echo -e "$(localized_text "${BOLD}📡 iperf3 单线程测试${PLAIN}" "${BOLD}📡 iperf3 Single thread test${PLAIN}" "${BOLD}📡 iperf3 Тест одной резьбы${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    if ! command -v iperf3 >/dev/null 2>&1 && ! install_pkg iperf3; then
        echo -e "$(localized_text "${RED}iperf3 安装失败，无法执行测试。${PLAIN}" "${RED}Iperf3 The installation failed and the test could not be performed.${PLAIN}" "${RED}iperf3 Не удалось выполнить установку, и невозможно выполнить тест.${PLAIN}")"
        pause_return
        return 1
    fi

    local target port direction duration
    local -a args
    read_trimmed target "$(localized_text "请输入已运行 iperf3 服务端的 IP 或域名: " "Please enter the IP or domain of the running iperf3 server:" "Пожалуйста, введите IP или доменное имя работающего сервера iperf3:")"
    if ! is_valid_backend_addr "$target"; then
        echo -e "$(localized_text "${RED}目标地址格式无效。${PLAIN}" "${RED}Destination address format is invalid.${PLAIN}" "${RED}Неверный формат адреса назначения .${PLAIN}")"
        pause_return
        return 1
    fi
    read_trimmed port "$(localized_text "请输入服务端端口 [5201]: " "Please enter the server port [5201]:" "Пожалуйста, введите порт сервера [5201]:")"
    port="${port:-5201}"
    if ! is_valid_port "$port"; then
        echo -e "$(localized_text "${RED}端口必须为 1-65535。${PLAIN}" "${RED}Port must be 1-65535.${PLAIN}" "${RED}Порт должен быть 1-65535.${PLAIN}")"
        pause_return
        return 1
    fi

    echo "$(localized_text "  1. 上传（本机 -> 服务端）" "1. Upload (local machine -> server)" "1. Загрузка (локальный компьютер -> сервер)")"
    echo "$(localized_text "  2. 下载（服务端 -> 本机）" "2. Download (server -> local machine)" "2. Скачать (сервер -> локальная машина)")"
    read_trimmed direction "$(localized_text "请选择方向 [1]: " "Please select direction [1]:" "Пожалуйста, выберите направление [1]:")"
    direction="${direction:-1}"
    [[ "$direction" == "1" || "$direction" == "2" ]] || { echo -e "$(localized_text "${RED}无效方向。${PLAIN}" "${RED}Invalid direction.${PLAIN}" "${RED}неверное направление.${PLAIN}")"; pause_return; return 1; }

    read_trimmed duration "$(localized_text "请输入测试时长（秒，1-300）[30]: " "Please enter the test duration (seconds, 1-300) [30]:" "Пожалуйста, введите продолжительность теста (секунды, 1–300) [30]:")"
    duration="${duration:-30}"
    if [[ ! "$duration" =~ ^[0-9]+$ ]] || (( duration < 1 || duration > 300 )); then
        echo -e "$(localized_text "${RED}测试时长必须为 1-300 秒。${PLAIN}" "${RED}Test duration must be 1-300 seconds.${PLAIN}" "${RED}Продолжительность теста должна составлять 1–300 секунд.${PLAIN}")"
        pause_return
        return 1
    fi

    args=(-c "$target" -p "$port" -P 1 -t "$duration" -f m)
    [[ "$direction" == "2" ]] && args+=(-R)
    echo -e "$(localized_text "${YELLOW}目标端必须已启动 iperf3 服务；本测试固定使用 1 条并行流。${PLAIN}" "${YELLOW}The iperf3 service must have been started on the target; this test uses 1 parallel stream.${PLAIN}" "${YELLOW}Служба iperf3 должна быть запущена на цели ; в этом тесте используется 1 параллельный поток.${PLAIN}")"
    echo ""
    if iperf3 "${args[@]}"; then
        echo -e "$(localized_text "${GREEN}✅ iperf3 单线程测试完成。${PLAIN}" "${GREEN}✅ iperf3 single-thread test completed.${PLAIN}" "${GREEN}✅ iperf3 Однопоточный тест завершен.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}测试失败，请检查服务端监听、防火墙和端口。${PLAIN}" "${RED}Test failed, please check the server listening, firewall and port.${PLAIN}" "${RED}Тест не пройден, проверьте прослушивающий сервер, брандмауэр и порт.${PLAIN}")"
    fi
    pause_return
}

func_international_speed_test() {
    clear
    run_remote_script "$(localized_text "运行国际互联速度测试" "Run an international internet speed test" "Запустите международный тест скорости интернета")" \
        "https://raw.githubusercontent.com/Cd1s/network-latency-tester/main/latency.sh"
    local rc=$?
    pause_after_external_script "$(localized_text "操作结束，按回车键返回网络优化菜单..." "When the operation is completed, press Enter to return to the network optimization menu..." "Когда операция будет завершена, нажмите Enter, чтобы вернуться в меню оптимизации сети...")"
    return "$rc"
}

func_network_latency_quality_test() {
    clear
    run_remote_script "$(localized_text "运行网络延迟质量检测" "Run network latency quality check" "Запустите проверку качества задержки сети")" "https://Check.Place" -N
    local rc=$?
    pause_after_external_script "$(localized_text "操作结束，按回车键返回网络优化菜单..." "When the operation is completed, press Enter to return to the network optimization menu..." "Когда операция будет завершена, нажмите Enter, чтобы вернуться в меню оптимизации сети...")"
    return "$rc"
}
# ---------------------------------------------------------
# 13, 14, 15 面板与流量狗快速部署
# ---------------------------------------------------------
func_port_dog() {
    clear
    echo -e "$(localized_text "${CYAN}👉 正在拉取并执行端口实际流量监控工具...${PLAIN}" "${CYAN}👉 Downloading and running the per-port traffic monitor...${PLAIN}" "${CYAN}👉 Загрузка и запуск монитора трафика по портам...${PLAIN}")"
    run_remote_script "$(localized_text "安装端口实际流量监控工具" "Install the per-port traffic monitor" "Установить монитор трафика по портам")" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}
