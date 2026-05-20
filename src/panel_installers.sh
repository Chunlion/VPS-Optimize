# shellcheck shell=bash
# Panel, node, DNS unlock, and IP sentinel installation shortcuts.

func_xpanel() {
    clear
    local version_choice install_url install_desc ssl_hint
    local -a install_args=()
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 3x-ui / x-ui 面板${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}账号密码说明：本入口会运行 3x-ui 官方安装器。${PLAIN}"
    echo -e "${YELLOW}管理员账号、密码和面板路径通常由官方安装器交互设置或在安装结束时输出。${PLAIN}"
    echo -e "${YELLOW}请留意安装结束输出并及时保存；后续也可通过 x-ui / 3x-ui 官方菜单修改。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${GREEN}  1. 安装最新版${PLAIN}       ${YELLOW}(默认，跟随官方 master 安装器)${PLAIN}"
    echo -e "${GREEN}  2. 安装 v2.9.4${PLAIN}      ${YELLOW}(固定版本，适合需要按 2.9.4 教程复现的机器)${PLAIN}"
    echo -e "${RED}  0. 取消${PLAIN}"
    echo -e "------------------------------------------------"
    read_trimmed version_choice "请选择 3x-ui 安装版本（默认 1）: "
    case "$(echo "${version_choice:-1}" | tr '[:upper:]' '[:lower:]')" in
        1|latest|最新版)
            install_desc="安装 3x-ui / x-ui 面板（最新版）"
            install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
            ssl_hint="最新版 3.x 安装器如果询问 SSL certificate setup method，请选择 Skip SSL / 不申请 SSL。443 单入口会由本脚本的 Caddy + acme.sh 统一托管公网证书。"
            ;;
        2|2.9.4|v2.9.4)
            install_desc="安装 3x-ui / x-ui 面板（v2.9.4）"
            install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/v2.9.4/install.sh"
            install_args=("v2.9.4")
            ssl_hint="v2.9.4 属于 2.x 老流程：如果安装器或面板里已经设置过 SSL 证书，后续 443 单入口向导会继续按旧方式清空面板/订阅证书路径。"
            ;;
        0|q|Q)
            echo -e "${BLUE}已取消安装。${PLAIN}"
            pause_after_external_script "按回车键返回菜单..."
            return
            ;;
        *)
            echo -e "${RED}❌ 无效选择，已取消安装。${PLAIN}"
            pause_after_external_script "按回车键返回菜单..."
            return
            ;;
    esac
    echo -e "${YELLOW}${ssl_hint}${PLAIN}"
    echo -e "${CYAN}👉 正在拉取 mhsanaei 的官方 3x-ui 安装脚本...${PLAIN}"
    if run_remote_script "$install_desc" "$install_url" "${install_args[@]}"; then
        detect_xui_single_443_defaults
        print_xui_single_443_detected_defaults
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xpanel_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 3x-ui / x-ui 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入官方管理菜单，执行配置查看、账号管理、更新或卸载等操作。${PLAIN}"
    echo -e "------------------------------------------------"

    local panel_cmd=""
    if command -v x-ui >/dev/null 2>&1; then
        panel_cmd="x-ui"
    elif command -v 3x-ui >/dev/null 2>&1; then
        panel_cmd="3x-ui"
    fi

    if [[ -z "$panel_cmd" ]]; then
        echo -e "${YELLOW}未检测到 x-ui / 3x-ui 命令，当前机器可能尚未安装 3x-ui 面板。${PLAIN}"
        local yn
        read_trimmed yn "是否现在安装 3x-ui 面板？(y/n): "
        if is_yes "$yn"; then
            func_xpanel
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
        fi
        return
    fi

    echo -e "${GREEN}即将打开 ${panel_cmd} 官方管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    "$panel_cmd"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xui_custom_manager() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 3x-ui 外置增强管理${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：补充 3x-ui 面板内没有的维护能力，例如自定义流量重置、校准已用流量、备份恢复和健康检查。${PLAIN}"
    echo -e "${YELLOW}提示：也可以在主菜单直接输入 xcm 或“外置”进入；脚本内输入 ? 可看功能索引。${PLAIN}"
    echo -e "${YELLOW}建议：修改数据库或恢复备份前，先做快照或通过脚本备份 x-ui 数据。${PLAIN}"
    echo -e "------------------------------------------------"
    run_remote_script "运行 3x-ui 外置增强管理脚本" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_sui_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 S-UI 面板${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}账号密码说明：本入口会运行 S-UI 官方安装器。${PLAIN}"
    echo -e "${YELLOW}管理员账号、密码和面板访问参数由官方安装器设置或在安装结束时输出。${PLAIN}"
    echo -e "${YELLOW}请留意安装结束输出并及时保存；后续也可通过 s-ui 官方菜单修改。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${CYAN}👉 正在拉取 alireza0 的 S-UI 官方安装脚本...${PLAIN}"
    run_remote_script "安装 S-UI 面板" "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_sui_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 S-UI 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入 S-UI 官方管理菜单，执行配置查看、账号管理、更新或卸载等操作。${PLAIN}"
    echo -e "------------------------------------------------"

    if ! command -v s-ui >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 s-ui 命令，当前机器可能尚未安装 S-UI。${PLAIN}"
        local yn
        read_trimmed yn "是否现在安装 S-UI？(y/n): "
        if is_yes "$yn"; then
            func_sui_panel
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
        fi
        return
    fi

    echo -e "${GREEN}即将打开 S-UI 官方管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    s-ui
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox_233boy() {
    clear
    echo -e "${CYAN}👉 正在拉取 233boy 的 Sing-box 一键脚本...${PLAIN}"
    echo -e "${YELLOW}脚本来源：https://github.com/233boy/sing-box${PLAIN}"
    echo -e "${YELLOW}使用文档：https://233boy.com/sing-box/sing-box-script/${PLAIN}"
    echo -e "${GREEN}安装完成后通常可使用 sing-box 或 sb 命令进入管理面板。${PLAIN}"
    run_remote_script "安装 Sing-box 233boy 一键脚本" "https://github.com/233boy/sing-box/raw/main/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_singbox_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 Sing-box 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入已安装 Sing-box 一键脚本的管理菜单。${PLAIN}"
    echo -e "------------------------------------------------"

    local sb_cmd=""
    if command -v sb >/dev/null 2>&1; then
        sb_cmd="sb"
    elif command -v sing-box >/dev/null 2>&1; then
        sb_cmd="sing-box"
    fi

    if [[ -z "$sb_cmd" ]]; then
        echo -e "${YELLOW}未检测到 sb / sing-box 管理命令。${PLAIN}"
        echo -e "${BLUE}如果是首次部署，请先选择对应的 Sing-box 安装项。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "${GREEN}即将打开 ${sb_cmd} 管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在脚本菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    "$sb_cmd"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xray_233boy() {
    clear
    echo -e "${CYAN}👉 正在拉取 233boy 的 Xray 一键脚本...${PLAIN}"
    echo -e "${YELLOW}脚本来源：https://github.com/233boy/Xray${PLAIN}"
    echo -e "${YELLOW}使用文档：https://233boy.com/xray/xray-script/${PLAIN}"
    echo -e "${GREEN}安装完成后通常可使用 xray 命令进入管理面板。${PLAIN}"
    run_remote_script "安装 Xray 233boy 一键脚本" "https://github.com/233boy/Xray/raw/main/install.sh"
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

func_xray_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧭 Xray 管理 / 卸载${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：进入 233boy Xray 官方管理菜单。${PLAIN}"
    echo -e "------------------------------------------------"

    if ! command -v xray >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 xray 管理命令，当前机器可能尚未安装 233boy Xray 脚本。${PLAIN}"
        local yn
        read_trimmed yn "是否现在安装 Xray？(y/n): "
        if is_yes "$yn"; then
            func_xray_233boy
        else
            echo -e "${BLUE}已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
        fi
        return
    fi

    echo -e "${GREEN}即将打开 xray 管理菜单。${PLAIN}"
    echo -e "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}"
    echo -e "------------------------------------------------"
    xray
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 17. DNS 流媒体分流解锁 (Alice DNS)
# ---------------------------------------------------------
func_dns_unlock() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔓 DNS 流媒体分流解锁 (DNS-Alice-Unlock)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍与使用说明：${PLAIN}"
    echo -e " 1. 该脚本通过修改本地 DNS 解析，实现 Netflix, Disney+ 等特定区域流媒体的解锁。"
    echo -e " 2. ${GREEN}仅对流媒体域名进行分流${PLAIN}，不影响您的原生 IP 和普通上网速度。"
    echo -e " 3. 项目地址：${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}⚠️  风险提示：运行此脚本会修改您服务器的 /etc/resolv.conf 配置。${PLAIN}"
    echo -e "    如果您不懂如何自行配置解锁机的 DNS 记录，请务必先查阅项目文档！"
    echo -e "------------------------------------------------"
    
    local yn
    read_trimmed yn "❓ 确认现在运行 Alice DNS 解锁脚本吗？(y/n): "
    if is_yes "$yn"; then
        run_remote_script "运行 Alice DNS 解锁脚本" "https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh"
    else
        echo -e "${BLUE}已安全取消操作。${PLAIN}"
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}
# ---------------------------------------------------------
# 新增功能：安装 IP Sentinel (防止 IP 送中)
# ---------------------------------------------------------
func_ip_sentinel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 安装 IP Sentinel (防止 IP 送中)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}该脚本将持续监控并修正路由，防止服务器 IP 被错误定位至中国大陆。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "❓ 确定要安装并配置 IP Sentinel(公共网关) 吗？(y/n): "
    if is_yes "$yn"; then
        run_remote_script "安装并配置 IP Sentinel" "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    pause_after_external_script "操作结束，按回车键返回菜单..."
}

# ---------------------------------------------------------
# 新增功能：安装 SublinkPro (强大的订阅转换与管理面板)
# ---------------------------------------------------------
