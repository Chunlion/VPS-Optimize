# shellcheck shell=bash
# Panel rescue and SSL reset workflows.

func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🚑 面板 SSL 修复${PLAIN}" "${BOLD}🚑 Panel SSL Repair${PLAIN}" "${BOLD}🚑 Панель SSL Ремонт${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：清空 3x-ui 面板证书路径，让 Caddy 可以按 HTTP 反代本机面板。${PLAIN}" "${YELLOW}Purpose of : Clear the 3x-ui panel certificate path so that Caddy can reverse the local panel by HTTP.${PLAIN}" "${YELLOW}Назначение : Очистите путь сертификата панели 3x-ui, чтобы Caddy мог отменить локальную панель с помощью HTTP.${PLAIN}")"
    echo -e "$(localized_text "更推荐在 3x-ui 面板里手动进入：面板设置 -> 常规 -> 证书，把证书路径和私钥路径清空后保存重启。" "It is more recommended to enter manually in the 3x-ui panel: Panel Settings -> General -> Certificate, clear the certificate path and private key path, save and restart." "Рекомендуется ввести вручную в панели 3x-ui: Настройки панели -> Общие -> Сертификат, очистить путь к сертификату и путь к закрытому ключу, сохранить и перезапустить.")"
    echo -e "$(localized_text "本功能只作为打不开面板时的救急方案，会尝试清空常见证书字段：webCertFile/webKeyFile/CertFile/KeyFile 等。" "This function is only used as a rescue solution when the panel cannot be opened. It will try to clear common certificate fields: webCertFile/webKeyFile/CertFile/KeyFile, etc." "Эта функция используется только в качестве спасательного решения, когда панель невозможно открыть. Он попытается очистить общие поля сертификата: webCertFile/webKeyFile/CertFile/KeyFile и т. д.")"
    echo -e "------------------------------------------------"
    
    local yn
    read_trimmed yn "$(localized_text "❓ 确定要清空面板证书路径并尝试退回 HTTP 吗？(Y/n): " "❓ Are you sure you want to clear the panel certificate path and try to fall back to HTTP? (Y/n):" "❓ Вы уверены, что хотите очистить путь сертификата панели и попытаться вернуться к HTTP? (Да/Нет):")"
    if is_yes "$yn"; then
        local xui_bin
        xui_bin=$(detect_xui_command 2>/dev/null || true)
        if [[ -n "$xui_bin" ]]; then
            echo -e "$(localized_text "${CYAN}当前 3x-ui 证书状态：${PLAIN}" "${CYAN}Current 3x-ui Certificate status:${PLAIN}" "${CYAN}Current 3x-ui Статус сертификата:${PLAIN}")"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi
        clear_xui_cert_settings_for_single_443 || true
        echo -e "------------------------------------------------"
        if [[ -n "$xui_bin" ]]; then
            echo -e "$(localized_text "${CYAN}清理后的 3x-ui 证书状态：${PLAIN}" "${CYAN}Cleaned 3x-ui Certificate status:${PLAIN}" "${CYAN}Очищен 3x-ui Статус сертификата:${PLAIN}")"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi
        echo -e "$(localized_text "${GREEN}✅ 已尝试清空证书路径。${PLAIN}" "${GREEN}✅ Tried clearing the certificate path.${PLAIN}" "${GREEN}✅ Попробовал очистить путь к сертификату.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请用本机测试确认协议：curl -I http://127.0.0.1:面板端口/你的面板路径/${PLAIN}" "${YELLOW}Please use this machine to test and confirm the protocol: curl -I http://127.0.0.1:面板端口/你的面板路径/${PLAIN}" "${YELLOW}Используйте это устройство для проверки и подтверждения протокола: curl -I http://127.0.0.1:面板端口/你的面板路径/${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}如果 HTTP 仍不通，请先进入 3x-ui 官方菜单或面板设置确认常规证书、订阅证书路径都已清空并重启面板。${PLAIN}" "${YELLOW}If HTTP is still unavailable, please first enter the 3x-ui official menu or panel settings to confirm that the general certificate and subscription certificate paths have been cleared and restart the panel.${PLAIN}" "${YELLOW}Если HTTP по-прежнему недоступен, сначала войдите в официальное меню 3x-ui или в настройки панели, чтобы убедиться, что пути общего сертификата и сертификата подписки очищены, и перезапустите панель.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}
# ---------------------------------------------------------
# 新增功能：网络端口占用可视化排查与进程查杀 (底层调用优化版)
# ---------------------------------------------------------
