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
            echo -e "${GREEN}✅ ${label}: ${host}:${port} 可连接${PLAIN}"
            return 0
        fi
        if local_listen_socket_matches_probe "$host" "$port"; then
            echo -e "${GREEN}✅ ${label}: ${host}:${port} 已检测到本地监听${PLAIN}"
            return 0
        fi
        [[ "$i" -lt "$attempts" ]] && sleep "$delay"
    done

    echo -e "${RED}❌ ${label}: ${host}:${port} 连接失败${PLAIN}"
    return 1
}

tcp_probe_once() {
    local host="$1"
    local port="$2"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w 3 "$host" "$port" >/dev/null 2>&1 && return 0
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null && return 0
    fi
    return 1
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
        echo -e "${YELLOW}⚠️ ${label}: 缺少 timeout 或 openssl，跳过 TLS/SNI 证书探测。${PLAIN}"
        return 0
    fi

    connect_target=$(format_hostport "$host" "$port")
    if timeout 10 openssl s_client -connect "$connect_target" -servername "$sni" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${GREEN}✅ ${label}: ${connect_target} / SNI ${sni} 已返回证书链${PLAIN}"
        return 0
    fi

    echo -e "${RED}❌ ${label}: ${connect_target} / SNI ${sni} 未正常返回证书链${PLAIN}"
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
        echo -e "${YELLOW}⚠️ ${label}: 缺少 curl，跳过 HTTPS 路径探测。${PLAIN}"
        return 1
    fi
    url=$(https_url_for_port "$domain" "$port" "$path")
    code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 12 --resolve "${domain}:${port}:127.0.0.1" "$url" 2>/dev/null)
    curl_rc=$?
    if [[ "$curl_rc" -ne 0 || ! "$code" =~ ^[0-9]{3}$ || "$code" == "000" ]]; then
        echo -e "${RED}❌ ${label}: ${url} 无响应或 TLS/SNI 失败（curl exit ${curl_rc}, HTTP ${code:-000}）${PLAIN}"
        return 1
    fi
    case "$code" in
        404)
            echo -e "${YELLOW}⚠️ ${label}: ${url} HTTP ${code}，443/SNI 已到达，但路径或后端可能不匹配。${PLAIN}"
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
        echo -e "${YELLOW}⚠️ ${label}: 缺少 openssl/timeout，跳过 TLS SNI 探测。${PLAIN}"
        return 1
    fi
    if timeout 10 openssl s_client -connect "127.0.0.1:${port}" -servername "$sni" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${GREEN}✅ ${label}: Nginx 入口能按 ${sni} 命中 TLS 证书链${PLAIN}"
        return 0
    fi
    echo -e "${YELLOW}⚠️ ${label}: 未拿到证书链，请检查 Nginx stream、Caddy 证书或 SNI。${PLAIN}"
    return 1
}

func_443_network_test() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "测速与质量检测 > 443 单入口测试"
    echo -e "${BOLD}🧪 443 单入口网络访问测试${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    if [[ ! -f /etc/vps-optimize/sni-stack.env ]]; then
        echo -e "${YELLOW}未检测到 443 单入口配置。请先进入 [19] -> [2] 完成首次配置。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    load_sni_stack_env || { read -n 1 -s -r -p "按任意键返回..."; return; }

    echo -e "面板入口：https://${PANEL_DOMAIN}${PANEL_WEB_PATH}"
    echo -e "订阅入口：https://${PANEL_DOMAIN}${SUB_URI_PATH}"
    echo -e "Clash/Mihomo：https://${PANEL_DOMAIN}${CLASH_URI_PATH}"
    echo -e "REALITY SNI：${REALITY_SNI}:${NGINX_LISTEN_PORT} -> ${XRAY_LISTEN_ADDR}:${XRAY_LISTEN_PORT}"
    echo -e "------------------------------------------------"

    check_domain_dns_sanity "$PANEL_DOMAIN" "面板域名" "warn" || true
    [[ "$PANEL_DOMAIN" != "$REALITY_SNI" ]] && check_domain_dns_sanity "$REALITY_SNI" "REALITY SNI" "warn" || true

    echo -e "------------------------------------------------"
    tcp_probe_host "公网入口 TCP" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" || true
    tcp_probe_host "本机 Nginx 入口" "127.0.0.1" "$NGINX_LISTEN_PORT" || true
    tcp_probe_host "Caddy 本地 TLS" "$(probe_host_for_listen_addr "$CADDY_LISTEN_ADDR")" "$CADDY_LISTEN_PORT" || true
    tcp_probe_host "3x-ui 面板后端" "$(probe_host_for_listen_addr "$PANEL_LISTEN_ADDR")" "$PANEL_LISTEN_PORT" || true
    tcp_probe_host "3x-ui 订阅后端" "$(probe_host_for_listen_addr "$SUB_LISTEN_ADDR")" "$SUB_LISTEN_PORT" || true
    tcp_probe_host "REALITY 本地入站" "$(probe_host_for_listen_addr "$XRAY_LISTEN_ADDR")" "$XRAY_LISTEN_PORT" || true

    echo -e "------------------------------------------------"
    tls_sni_probe_local "面板 SNI TLS" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" || true
    curl_sni_path_probe "面板路径" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$PANEL_WEB_PATH" || true
    curl_sni_path_probe "普通订阅路径" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$SUB_URI_PATH" || true
    curl_sni_path_probe "Clash/Mihomo 路径" "$PANEL_DOMAIN" "$NGINX_LISTEN_PORT" "$CLASH_URI_PATH" || true

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}说明：HTTP 401/403/302 通常表示链路已到达后端；404 多数是路径或 3x-ui 订阅设置不一致。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

func_test_scripts() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}📊 VPS 综合测速与质量检验合集库${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. YABS 硬件性能测试      ${YELLOW}  2. 融合怪详细测速${PLAIN}"
        echo -e "${GREEN}  3. SuperBench 综合测速    ${YELLOW}  4. bench.sh 基础测试${PLAIN}"
        echo -e "${GREEN}  5. 流媒体解锁检测         ${YELLOW}  6. 三网回程路由测试${PLAIN}"
        echo -e "${GREEN}  7. IP 质量 / 欺诈度检测   ${YELLOW}  8. NodeSeek 综合测试${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        
        local t
        local ran_test=false
        read_trimmed t "👉 请输入对应序号选择: "
        case $t in
            1) ran_test=true; run_remote_script "运行 YABS 硬件性能测试" "https://yabs.sh" ;;
            2) ran_test=true; run_remote_script "运行融合怪详细测速" "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh" ;;
            3) ran_test=true; run_remote_script "运行 SuperBench 综合测速" "https://about.superbench.pro" ;;
            4) ran_test=true; run_remote_script "运行 bench.sh 基础测试" "https://bench.sh" ;;
            5) ran_test=true; run_remote_script "运行流媒体解锁检测" "https://check.unlock.media" ;;
            6) ran_test=true; run_remote_script "运行三网回程路由测试" "https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh" ;;
            7) ran_test=true; run_remote_script "运行 IP 质量 / 欺诈度检测" "https://IP.Check.Place" ;;
            8) ran_test=true; run_remote_script "运行 NodeSeek 综合测试" "https://run.NodeQuality.com" ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效的选择！${PLAIN}"; sleep 1; continue ;;
        esac
        echo ""
        if [[ "$ran_test" == "true" ]]; then
            pause_after_external_script "操作结束，按回车键返回测试菜单..."
        fi
    done
}
# ---------------------------------------------------------
# 13, 14, 15 面板与流量狗快速部署
# ---------------------------------------------------------
func_port_dog() {
    clear
    echo -e "${CYAN}👉 正在拉取并执行端口实际流量监控工具...${PLAIN}"
    run_remote_script "安装端口实际流量监控工具" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}
