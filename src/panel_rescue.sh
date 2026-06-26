# shellcheck shell=bash
# Panel rescue and SSL reset workflows.

func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚑 面板 SSL 修复${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：清空 3x-ui 面板证书路径，让 Caddy 可以按 HTTP 反代本机面板。${PLAIN}"
    echo -e "更推荐在 3x-ui 面板里手动进入：面板设置 -> 常规 -> 证书，把证书路径和私钥路径清空后保存重启。"
    echo -e "本功能只作为打不开面板时的救急方案，会尝试清空常见证书字段：webCertFile/webKeyFile/CertFile/KeyFile 等。"
    echo -e "------------------------------------------------"
    
    local yn
    read_trimmed yn "❓ 确定要清空面板证书路径并尝试退回 HTTP 吗？(y/n): "
    if is_yes "$yn"; then
        local xui_bin
        xui_bin=$(detect_xui_command 2>/dev/null || true)
        if [[ -n "$xui_bin" ]]; then
            echo -e "${CYAN}当前 3x-ui 证书状态：${PLAIN}"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi
        clear_xui_cert_settings_for_single_443 || true
        echo -e "------------------------------------------------"
        if [[ -n "$xui_bin" ]]; then
            echo -e "${CYAN}清理后的 3x-ui 证书状态：${PLAIN}"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi
        echo -e "${GREEN}✅ 已尝试清空证书路径。${PLAIN}"
        echo -e "${YELLOW}请用本机测试确认协议：curl -I http://127.0.0.1:面板端口/你的面板路径/${PLAIN}"
        echo -e "${YELLOW}如果 HTTP 仍不通，请先进入 3x-ui 官方菜单或面板设置确认常规证书、订阅证书路径都已清空并重启面板。${PLAIN}"
    else
        echo -e "${BLUE}已取消操作。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 新增功能：网络端口占用可视化排查与进程查杀 (底层调用优化版)
# ---------------------------------------------------------
