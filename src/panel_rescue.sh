# shellcheck shell=bash
# Panel rescue and SSL reset workflows.

func_rescue_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🚑 面板 SSL 修复${PLAIN}" "${BOLD}🚑 Panel SSL Repair${PLAIN}" "${BOLD}🚑 Панель SSL Ремонт${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：清空 3x-ui 面板证书路径，使 Caddy 可通过 HTTP 反代本机面板。${PLAIN}" "${YELLOW}Purpose: clear the 3x-ui panel certificate paths so Caddy can proxy the local panel over HTTP.${PLAIN}" "${YELLOW}Назначение: очистить пути сертификатов панели 3x-ui, чтобы Caddy мог проксировать локальную панель по HTTP.${PLAIN}")"
    echo -e "$(localized_text "优先在 3x-ui 中手动打开“面板设置 -> 常规 -> 证书”，清空证书和私钥路径，保存后重启面板。" "Preferred method: in 3x-ui, open Panel Settings -> General -> Certificate, clear the certificate and private-key paths, save, and restart the panel." "Предпочтительный способ: в 3x-ui откройте «Настройки панели -> Общие -> Сертификат», очистите пути сертификата и закрытого ключа, сохраните изменения и перезапустите панель.")"
    echo -e "$(localized_text "本功能仅用于面板无法打开时，会尝试清空 webCertFile、webKeyFile、CertFile、KeyFile 等常见字段。" "Use this only when the panel cannot be opened. It attempts to clear common fields such as webCertFile, webKeyFile, CertFile, and KeyFile." "Используйте эту функцию только тогда, когда панель не открывается. Она очищает распространённые поля: webCertFile, webKeyFile, CertFile и KeyFile.")"
    echo -e "------------------------------------------------"
    
    if confirm_danger \
        "$(localized_text "清空 3x-ui 面板证书路径" "Clear the 3x-ui panel certificate paths" "Очистить пути сертификатов панели 3x-ui")" \
        "$(localized_text "清空 3x-ui 中常见的面板和订阅证书字段，并尝试改回 HTTP。" "Clear common panel and subscription certificate fields in 3x-ui and try to switch back to HTTP." "Очистить распространённые поля сертификатов панели и подписки в 3x-ui и попробовать вернуться к HTTP.")" \
        "$(localized_text "从 3x-ui 官方菜单重新填写原证书路径，或恢复操作前备份。" "Restore the original certificate paths from the official 3x-ui menu or from a pre-operation backup." "Верните исходные пути сертификатов через официальное меню 3x-ui или восстановите резервную копию.")"; then
        local xui_bin
        xui_bin=$(detect_xui_command 2>/dev/null || true)
        if [[ -n "$xui_bin" ]]; then
            echo -e "$(localized_text "${CYAN}当前 3x-ui 证书状态：${PLAIN}" "${CYAN}Current 3x-ui Certificate status:${PLAIN}" "${CYAN}Current 3x-ui Статус сертификата:${PLAIN}")"
            "$xui_bin" setting -getCert true 2>/dev/null || true
            echo -e "------------------------------------------------"
        fi
        if ! clear_xui_cert_settings_for_single_443; then
            echo -e "$(localized_text "${RED}❌ 未能清空证书路径，请改用 3x-ui 官方菜单手动处理。${PLAIN}" "${RED}❌ Certificate paths could not be cleared. Use the official 3x-ui menu instead.${PLAIN}" "${RED}❌ Не удалось очистить пути сертификатов. Используйте официальное меню 3x-ui.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return 1
        fi
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
