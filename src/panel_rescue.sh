# shellcheck shell=bash
# Panel rescue and SSL reset workflows.

func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🚑 面板紧急救砖 / SSL 清理工具${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}用途：清空 3x-ui 面板证书路径，让 Caddy 可以按 HTTP 反代本机面板。${PLAIN}"
    echo -e "更推荐在 3x-ui 面板里手动进入：面板设置 -> 常规 -> 证书，把证书路径和私钥路径清空后保存重启。"
    echo -e "本功能只作为打不开面板时的救急方案，会尝试清空常见证书字段：webCertFile/webKeyFile/CertFile/KeyFile 等。"
    echo -e "------------------------------------------------"
    
    local yn
    read_trimmed yn "❓ 确定要清空面板证书路径并尝试退回 HTTP 吗？(y/n): "
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        
        # 核心修改：使用我们的全局极简包管理器！兼容了包名差异。
        if ! command -v sqlite3 >/dev/null 2>&1; then
            echo -e "${CYAN}▶ 正在安装 sqlite3 数据库工具...${PLAIN}"
            install_pkg sqlite3 sqlite
        fi
        
        local xui_bin=""
        if [[ -x /usr/local/x-ui/x-ui ]]; then
            xui_bin="/usr/local/x-ui/x-ui"
        elif command -v x-ui >/dev/null 2>&1; then
            xui_bin="$(command -v x-ui)"
        elif command -v 3x-ui >/dev/null 2>&1; then
            xui_bin="$(command -v 3x-ui)"
        fi
        if [[ -n "$xui_bin" ]]; then
            echo -e "${CYAN}当前 3x-ui 证书状态：${PLAIN}"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi

        # 停服务
        systemctl stop x-ui >/dev/null 2>&1
        systemctl stop 3x-ui >/dev/null 2>&1
        systemctl stop x-panel >/dev/null 2>&1
        
        local cert_cmd_done=false
        if [[ -n "$xui_bin" ]]; then
            if "$xui_bin" cert -webCert "" -webCertKey "" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ 已通过 3x-ui 官方 cert 命令清空面板与订阅证书路径。${PLAIN}"
                cert_cmd_done=true
            else
                echo -e "${YELLOW}⚠️ 官方 cert 命令清理失败，将继续尝试直接修正数据库。${PLAIN}"
            fi
        fi

        # 新版/旧版字段名不完全一致，所以按 key 的小写形式兼容面板和订阅证书字段。
        local db_found=false
        local cert_key_sql
        local db_path
        cert_key_sql=$(xui_cert_setting_key_sql_list)
        while IFS= read -r db_path; do
            if [[ -f "$db_path" ]]; then
                if sqlite3 "$db_path" "update settings set value='' where lower(key) in (${cert_key_sql});" 2>/dev/null; then
                    echo -e "${GREEN}✅ 已清空常见 SSL 证书字段：${db_path}${PLAIN}"
                    db_found=true
                else
                    echo -e "${YELLOW}⚠️ 数据库存在但更新失败：${db_path}${PLAIN}"
                fi
            fi
        done < <(find_xui_database_candidates)
        
        if ! $db_found && ! $cert_cmd_done; then
            echo -e "${RED}❌ 未检测到常见面板的数据库文件！您可能没有安装 x-ui 或 x-panel。${PLAIN}"
        elif ! $db_found; then
            echo -e "${YELLOW}⚠️ 未在常见路径找到数据库，已依赖官方 cert 命令处理。${PLAIN}"
        fi
        
        # 重启服务
        systemctl restart x-ui >/dev/null 2>&1 || systemctl start x-ui >/dev/null 2>&1
        systemctl restart 3x-ui >/dev/null 2>&1 || systemctl start 3x-ui >/dev/null 2>&1
        systemctl start x-panel >/dev/null 2>&1
        
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
