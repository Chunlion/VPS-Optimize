# shellcheck shell=bash
# vpso-mux build, install, systemd, and failure-context helpers.

go_install_vpso_mux_latest() {
    local module_version tmp_dir
    echo -e "${CYAN}▶ 正在使用本机 Go 以兼容模式构建 vpso-mux...${PLAIN}"
    if ! go version 2>/dev/null | grep -Eq 'go1\.(2[2-9]|[3-9][0-9])'; then
        echo -e "${RED}❌ 当前 Go 版本低于 1.22，拒绝在生产机上自动下载临时 Go 工具链。${PLAIN}"
        echo -e "${YELLOW}请先通过系统包管理器安装 Go 1.22+，或在安全环境构建 /usr/local/bin/vpso-mux 后再切换 TCP Peek。${PLAIN}"
        return 1
    fi
    vpso_mux_build_resource_check || return 1
    module_version=$(GOTOOLCHAIN=local go list -m -f '{{.Version}}' github.com/Chunlion/VPS-Optimize@latest 2>/dev/null) || return 1
    tmp_dir=$(mktemp -d /tmp/vpso-mux-build.XXXXXX) || return 1
    cat <<EOF > "${tmp_dir}/go.mod"
module vpso-mux-build

go 1.22

require github.com/Chunlion/VPS-Optimize ${module_version}

replace golang.org/x/sys => golang.org/x/sys v0.30.0
EOF
    (
        local mod_dir patched_dir patch_file
        cd "$tmp_dir" || exit 1
        GOMAXPROCS=1 GOTOOLCHAIN=local go mod download github.com/Chunlion/VPS-Optimize || exit 1
        mod_dir=$(GOTOOLCHAIN=local go list -m -f '{{.Dir}}' github.com/Chunlion/VPS-Optimize) || exit 1
        patched_dir="${tmp_dir}/VPS-Optimize-src"
        cp -a "$mod_dir" "$patched_dir" || exit 1
        chmod -R u+w "$patched_dir" 2>/dev/null || true
        patch_file="${patched_dir}/cmd/vpso-mux/main.go"
        if grep -q 'unix\.Splice(pipeFD\[0\], nil, dstFD, nil, remaining,' "$patch_file" 2>/dev/null; then
            echo -e "${YELLOW}⚠️ 检测到远程 vpso-mux 旧源码，正在应用 Go 兼容修补...${PLAIN}"
            sed -i 's/unix\.Splice(pipeFD\[0\], nil, dstFD, nil, remaining,/unix.Splice(pipeFD[0], nil, dstFD, nil, int(remaining),/' "$patch_file" || exit 1
        fi
        cat <<EOF >> "${tmp_dir}/go.mod"

replace github.com/Chunlion/VPS-Optimize => ./VPS-Optimize-src
EOF
        GOMAXPROCS=1 GOTOOLCHAIN=local go get "github.com/Chunlion/VPS-Optimize/cmd/vpso-mux@${module_version}" || exit 1
        GOMAXPROCS=1 GOTOOLCHAIN=local go build -p 1 -o /usr/local/bin/vpso-mux github.com/Chunlion/VPS-Optimize/cmd/vpso-mux
    )
}

vpso_mux_build_resource_check() {
    local mem_kb swap_kb available_kb tmp_kb
    if [[ -r /proc/meminfo ]]; then
        mem_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
        swap_kb=$(awk '/SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
        mem_kb=${mem_kb:-0}
        swap_kb=${swap_kb:-0}
        available_kb=$((mem_kb + swap_kb))
        if (( available_kb > 0 && available_kb < 262144 )); then
            echo -e "${RED}❌ 可用内存+Swap 低于 256MB，拒绝在当前服务器上编译 vpso-mux，避免系统失联。${PLAIN}"
            return 1
        fi
    fi
    tmp_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    tmp_kb=${tmp_kb:-0}
    if (( tmp_kb > 0 && tmp_kb < 524288 )); then
        echo -e "${RED}❌ /tmp 可用空间低于 512MB，拒绝构建 vpso-mux。${PLAIN}"
        return 1
    fi
}

require_vpso_mux_binary_for_cutover() {
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        return 0
    fi
    echo -e "${RED}❌ 缺少 /usr/local/bin/vpso-mux，拒绝切换到 TCP Peek + Splice 模式。${PLAIN}"
    echo -e "${YELLOW}为避免生产机在 443 切换过程中下载 Go 工具链或远端编译，公网 443 切换流程不会自动构建 vpso-mux。${PLAIN}"
    echo -e "${YELLOW}请先在 443 管理中心运行 TCP Peek 8444 预检/测试，确认 vpso-mux 安装和测试端口都正常后，再切换公网 443。${PLAIN}"
    return 1
}

install_vpso_mux_binary() {
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        return 0
    fi

    if ! command -v go >/dev/null 2>&1; then
        echo -e "${CYAN}▶ 未检测到 Go，正在安装 vpso-mux 构建工具链...${PLAIN}"
        if is_debian; then
            install_pkg golang-go || install_pkg golang || return 1
        elif is_redhat; then
            install_pkg golang || return 1
        else
            echo -e "${RED}❌ 当前系统暂不支持自动安装 Go，请先安装 Go 1.22+ 后重试。${PLAIN}"
            return 1
        fi
    fi

    command -v go >/dev/null 2>&1 || { echo -e "${RED}❌ Go 安装后仍不可用，无法构建 vpso-mux。${PLAIN}"; return 1; }

    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if [[ -d "$source_dir/cmd/vpso-mux" ]]; then
        echo -e "${CYAN}▶ 正在从当前源码构建 vpso-mux...${PLAIN}"
        (cd "$source_dir" && go build -o /usr/local/bin/vpso-mux ./cmd/vpso-mux) || return 1
        chmod 755 /usr/local/bin/vpso-mux
        return 0
    fi

    go_install_vpso_mux_latest || return 1
    chmod 755 /usr/local/bin/vpso-mux 2>/dev/null || true
    [[ -x /usr/local/bin/vpso-mux ]] || { echo -e "${RED}❌ vpso-mux 安装后仍不可执行：/usr/local/bin/vpso-mux${PLAIN}"; return 1; }
    return 0
}

write_vpso_mux_systemd_service() {
    local service_file="${1:-/etc/systemd/system/vpso-mux.service}"
    cat <<'EOF' > "$service_file"
[Unit]
Description=VPS-Optimize TCP Peek + Splice vpso-mux router
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$service_file"
    if [[ "$service_file" == "/etc/systemd/system/vpso-mux.service" ]]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

run_vpso_mux_config_check() {
    local config_file="${1:-$(vpso_mux_config_path)}"
    if [[ -x /usr/local/bin/vpso-mux ]]; then
        /usr/local/bin/vpso-mux -config "$config_file" -check
        return $?
    fi
    local source_dir="${SCRIPT_DIR:-$(pwd)}"
    if command -v go >/dev/null 2>&1 && [[ -d "$source_dir/cmd/vpso-mux" ]]; then
        (cd "$source_dir" && go run ./cmd/vpso-mux -config "$config_file" -check)
        return $?
    fi
    echo -e "${RED}❌ 缺少 vpso-mux 二进制或 Go 工具链，无法执行完整配置校验。${PLAIN}"
    return 1
}

print_vpso_mux_failure_context() {
    local port="${1:-$NGINX_LISTEN_PORT}"
    echo -e "${YELLOW}▶ vpso-mux 未能稳定监听 ${port}，下面是最近状态和日志：${PLAIN}"
    systemctl status vpso-mux --no-pager -l 2>/dev/null || true
    echo -e "${YELLOW}▶ 最近 40 行 vpso-mux 日志：${PLAIN}"
    journalctl -u vpso-mux -n 40 --no-pager 2>/dev/null || true
    echo -e "${YELLOW}▶ 当前 ${port} 监听情况：${PLAIN}"
    if command -v ss >/dev/null 2>&1; then
        ss -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true
    else
        netstat -lntp 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print}' || true
    fi
}
