# shellcheck shell=bash
# Panel, node, DNS unlock, and IP sentinel installation shortcuts.

func_xpanel() {
    clear
    local version_choice install_url install_desc ssl_hint
    local -a install_args=()
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}安装 3x-ui / x-ui 面板${PLAIN}" "${BOLD}Installation 3x-ui / x-ui panel${PLAIN}" "${BOLD}Установка 3x-ui / x-ui Панель${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}账号密码说明：本入口会运行 3x-ui 官方安装器。${PLAIN}" "${YELLOW}Account password description: This entry will run the 3x-ui official installer.${PLAIN}" "${YELLOW}Описание пароля учетной записи : при этом входе будет запущен официальный установщик 3x-ui.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}管理员账号、密码和面板路径通常由官方安装器交互设置或在安装结束时输出。${PLAIN}" "${YELLOW}The administrator account, password and panel path are usually set interactively by the official installer or output at the end of the installation.${PLAIN}" "${YELLOW}Учетная запись администратора , пароль и путь к панели обычно задаются в интерактивном режиме официальным установщиком или выводятся в конце установки.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请留意安装结束输出并及时保存；后续也可通过 x-ui / 3x-ui 官方菜单修改。${PLAIN}" "${YELLOW}Please pay attention to the output after installation and save it in time; it can also be modified later through the x-ui / 3x-ui official menu.${PLAIN}" "${YELLOW}Обратите внимание на выходные данные после установки и сохраните их вовремя; его также можно изменить позже через официальное меню x-ui / 3x-ui.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${GREEN}  1. 安装最新版${PLAIN}       ${YELLOW}(默认，跟随官方 master 安装器)${PLAIN}" "${GREEN}1. Install the latest version (default, follow the official master installer)${PLAIN}" "${GREEN}1. Установите последнюю версию (по умолчанию, следуйте официальному мастеру установки)${PLAIN}")"
    echo -e "$(localized_text "${GREEN}  2. 安装 v2.9.4${PLAIN}      ${YELLOW}(固定版本，适合需要按 2.9.4 教程复现的机器)${PLAIN}" "${GREEN}2. Install v2.9.4 (fixed version, suitable for machines that need to be reproduced according to the 2.9.4 tutorial)${PLAIN}" "${GREEN}2. Установите v2.9.4 (исправленная версия, подходит для машин, которые необходимо воспроизвести по туториалу 2.9.4)${PLAIN}")"
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    echo -e "------------------------------------------------"
    read_trimmed version_choice "$(localized_text "选择 3x-ui 版本 [1]: " "Select a 3x-ui version [1]: " "Выберите версию 3x-ui [1]: ")"
    case "$(echo "${version_choice:-1}" | tr '[:upper:]' '[:lower:]')" in
        1|latest|最新版)
            install_desc="$(localized_text "安装 3x-ui / x-ui 面板（最新版）" "Install 3x-ui / x-ui panel (latest version)" "Установите панель 3x-ui/x-ui (последняя версия)")"
            install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
            ssl_hint="$(localized_text "最新版 3.x 安装器询问 SSL 时选第 4 项 Skip SSL；再选 y 仅绑定 127.0.0.1。443端口复用由本脚本的 Caddy + acme.sh 托管公网证书。" "When the latest 3.x installer asks about SSL, choose option 4, Skip SSL, then enter y to bind only to 127.0.0.1. The Port 443 Reuse uses this script's Caddy + acme.sh for public certificates." "Когда установщик 3.x спросит об SSL, выберите пункт 4 Skip SSL, затем введите y для привязки только к 127.0.0.1. Публичные сертификаты повторного использования порта 443 обслуживают Caddy + acme.sh этого сценария.")"
            ;;
        2|2.9.4|v2.9.4)
            install_desc="$(localized_text "安装 3x-ui / x-ui 面板（v2.9.4）" "Install 3x-ui / x-ui panel (v2.9.4)" "Установите панель 3x-ui/x-ui (v2.9.4)")"
            install_url="https://raw.githubusercontent.com/mhsanaei/3x-ui/v2.9.4/install.sh"
            install_args=("v2.9.4")
            ssl_hint="$(localized_text "v2.9.4 属于 2.x 老流程：如果安装器或面板里已经设置过 SSL 证书，后续 443端口复用向导会继续按旧方式清空面板/订阅证书路径。" "v2.9.4 belongs to the 2.x old process: if the SSL certificate has been set in the installer or panel, the subsequent Port 443 Reuse Wizard will continue to clear the panel/subscription certificate path in the old way." "Версия 2.9.4 принадлежит старому процессу 2.x: если сертификат SSL был установлен в установщике или панели, последующие 443 мастера с повторным использованием порта 443 продолжат очищать путь к сертификату панели/подписки старым способом.")"
            ;;
        0|q|Q)
            echo -e "$(localized_text "${BLUE}已取消安装。${PLAIN}" "${BLUE}Installation has been canceled.${PLAIN}" "${BLUE}Установка отменена.${PLAIN}")"
            pause_after_external_script "$(localized_text "按回车键返回菜单..." "Press Enter to return to the menu..." "Нажмите Enter, чтобы вернуться в меню...")"
            return
            ;;
        *)
            echo -e "$(localized_text "${RED}❌ 无效选择，已取消安装。${PLAIN}" "${RED}❌ Invalid selection, installation canceled.${PLAIN}" "${RED}❌ Неверный выбор, установка отменена.${PLAIN}")"
            pause_after_external_script "$(localized_text "按回车键返回菜单..." "Press Enter to return to the menu..." "Нажмите Enter, чтобы вернуться в меню...")"
            return
            ;;
    esac
    echo -e "${YELLOW}${ssl_hint}${PLAIN}"
    echo -e "$(localized_text "${CYAN}👉 正在拉取 mhsanaei 的官方 3x-ui 安装脚本...${PLAIN}" "${CYAN}👉 Pulling mhsanaei’s official 3x-ui installation script...${PLAIN}" "${CYAN}👉 Получение официального сценария установки 3x-ui от mhsanaei...${PLAIN}")"
    if run_remote_script "$install_desc" "$install_url" "${install_args[@]}"; then
        detect_xui_single_443_defaults
        print_xui_single_443_detected_defaults
    fi
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_xpanel_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 3x-ui / x-ui 管理 / 卸载${PLAIN}" "${BOLD}🧭 Manage or uninstall 3x-ui / x-ui${PLAIN}" "${BOLD}🧭 Управление или удаление 3x-ui / x-ui${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}打开官方管理菜单，查看配置、管理账号、更新或卸载面板。${PLAIN}" "${YELLOW}Open the official menu to view settings, manage accounts, update, or uninstall the panel.${PLAIN}" "${YELLOW}Открыть официальное меню для просмотра настроек, управления учётными записями, обновления или удаления панели.${PLAIN}")"
    echo -e "------------------------------------------------"

    local panel_cmd=""
    if command -v x-ui >/dev/null 2>&1; then
        panel_cmd="x-ui"
    elif command -v 3x-ui >/dev/null 2>&1; then
        panel_cmd="3x-ui"
    fi

    if [[ -z "$panel_cmd" ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到 x-ui 或 3x-ui 管理命令，可能尚未安装面板。${PLAIN}" "${YELLOW}The x-ui and 3x-ui management commands were not found; the panel may not be installed.${PLAIN}" "${YELLOW}Команды управления x-ui и 3x-ui не найдены; возможно, панель не установлена.${PLAIN}")"
        if confirm_danger "$(localized_text "安装 3x-ui 面板" "Install the 3x-ui panel" "Установить панель 3x-ui")" \
            "$(localized_text "下载并执行 3x-ui 官方安装脚本" "download and run the official 3x-ui installer" "скачать и запустить официальный установщик 3x-ui")" \
            "$(localized_text "安装前备份现有面板配置；卸载方式以 3x-ui 官方菜单为准" "back up any existing panel configuration first; use the official 3x-ui menu to uninstall" "сначала сохраните существующую конфигурацию панели; для удаления используйте официальное меню 3x-ui")"; then
            func_xpanel
        else
            echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        fi
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 ${panel_cmd} 官方管理菜单。${PLAIN}" "${GREEN}Opening the official ${panel_cmd} management menu.${PLAIN}" "${GREEN}Открывается официальное меню управления ${panel_cmd}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在该菜单中选择卸载。${PLAIN}" "${YELLOW}To uninstall it, select the uninstall option in that menu.${PLAIN}" "${YELLOW}Для удаления выберите соответствующий пункт в этом меню.${PLAIN}")"
    echo -e "------------------------------------------------"
    "$panel_cmd"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_xui_custom_manager() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 x-ui 增强套件${PLAIN}" "${BOLD}🧭 x-ui Enhancement Kit${PLAIN}" "${BOLD}🧭 x-ui Комплект расширения${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：补充 3x-ui 面板内没有的维护能力，例如自定义流量重置、校准已用流量、备份恢复和健康检查。${PLAIN}" "${YELLOW}Purpose: to supplement the maintenance capabilities not available in the 3x-ui panel, such as custom flow reset, calibration of used flow, backup recovery and health check.${PLAIN}" "${YELLOW}Назначение: дополнить возможности обслуживания, недоступные на панели 3x-ui, такие как сброс пользовательского потока, калибровка используемого потока, восстановление резервной копии и проверка работоспособности.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}在当前菜单输入 ? 可查看功能索引。${PLAIN}" "${YELLOW}Enter ? in the current menu to view the feature index.${PLAIN}" "${YELLOW}Введите ? в текущем меню, чтобы посмотреть список функций.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}建议：修改数据库或恢复备份前，先做快照或通过脚本备份 x-ui 数据。${PLAIN}" "${YELLOW}Recommendation: Before modifying the database or restoring the backup, take a snapshot or back up the x-ui data through a script.${PLAIN}" "${YELLOW}Рекомендация : перед изменением базы данных или восстановлением резервной копии сделайте снимок или создайте резервную копию данных x-ui с помощью сценария.${PLAIN}")"
    echo -e "------------------------------------------------"
    run_remote_script "$(localized_text "运行 x-ui 增强套件脚本" "Run the x-ui enhancement kit script" "Запустите сценарий комплекта расширения x-ui.")" "https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_sui_panel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}安装 S-UI 面板${PLAIN}" "${BOLD}Installation S-UI panel${PLAIN}" "${BOLD}Установка Панель S-UI${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}账号密码说明：本入口会运行 S-UI 官方安装器。${PLAIN}" "${YELLOW}Account password description: This entry will run the S-UI official installer.${PLAIN}" "${YELLOW}Описание пароля учетной записи : при этом входе будет запущен официальный установщик S-UI.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}管理员账号、密码和面板访问参数由官方安装器设置或在安装结束时输出。${PLAIN}" "${YELLOW}The administrator account, password and panel access parameters are set by the official installer or output at the end of the installation.${PLAIN}" "${YELLOW}Учетная запись администратора , пароль и параметры доступа к панели задаются официальным установщиком или выводятся в конце установки.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请留意安装结束输出并及时保存；后续也可通过 s-ui 官方菜单修改。${PLAIN}" "${YELLOW}Please pay attention to the output after installation and save it in time; it can also be modified later through the s-ui official menu.${PLAIN}" "${YELLOW}Обратите внимание на выходные данные после установки и сохраните их вовремя; его также можно изменить позже через официальное меню s-ui.${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${CYAN}👉 正在拉取 alireza0 的 S-UI 官方安装脚本...${PLAIN}" "${CYAN}👉 Pulling alireza0's S-UI official installation script...${PLAIN}" "${CYAN}👉 Получение официального сценария установки S-UI от alireza0...${PLAIN}")"
    run_remote_script "$(localized_text "安装 S-UI 面板" "Install S-UI panel" "Установите панель S-UI.")" "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_sui_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 S-UI 管理 / 卸载${PLAIN}" "${BOLD}🧭 Manage or uninstall S-UI${PLAIN}" "${BOLD}🧭 Управление или удаление S-UI${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}打开 S-UI 官方管理菜单，查看配置、管理账号、更新或卸载面板。${PLAIN}" "${YELLOW}Open the official S-UI menu to view settings, manage accounts, update, or uninstall the panel.${PLAIN}" "${YELLOW}Открыть официальное меню S-UI для просмотра настроек, управления учётными записями, обновления или удаления панели.${PLAIN}")"
    echo -e "------------------------------------------------"

    if ! command -v s-ui >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}未检测到 s-ui 管理命令，可能尚未安装 S-UI。${PLAIN}" "${YELLOW}The s-ui management command was not found; S-UI may not be installed.${PLAIN}" "${YELLOW}Команда управления s-ui не найдена; возможно, S-UI не установлен.${PLAIN}")"
        if confirm_danger "$(localized_text "安装 S-UI" "Install S-UI" "Установить S-UI")" \
            "$(localized_text "下载并执行 S-UI 官方安装脚本" "download and run the official S-UI installer" "скачать и запустить официальный установщик S-UI")" \
            "$(localized_text "安装前备份现有配置；卸载方式以 S-UI 官方菜单为准" "back up existing configuration first; use the official S-UI menu to uninstall" "сначала сохраните существующую конфигурацию; для удаления используйте официальное меню S-UI")"; then
            func_sui_panel
        else
            echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        fi
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 S-UI 官方管理菜单。${PLAIN}" "${GREEN}Opening the official S-UI management menu.${PLAIN}" "${GREEN}Открывается официальное меню управления S-UI.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在官方菜单中选择卸载。${PLAIN}" "${YELLOW}To uninstall S-UI, select the uninstall option in its official menu.${PLAIN}" "${YELLOW}Для удаления S-UI выберите соответствующий пункт в официальном меню.${PLAIN}")"
    echo -e "------------------------------------------------"
    s-ui
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_singbox_233boy() {
    clear
    echo -e "$(localized_text "${CYAN}▶ 正在获取 233boy Sing-box 安装脚本...${PLAIN}" "${CYAN}▶ Fetching the 233boy Sing-box installer...${PLAIN}" "${CYAN}▶ Загрузка установщика 233boy Sing-box...${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}脚本来源：https://github.com/233boy/sing-box${PLAIN}" "${YELLOW}Script source: https://github.com/233boy/sing-box${PLAIN}" "${YELLOW}Источник сценария : https://github.com/233boy/sing-box${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}使用文档：https://233boy.com/sing-box/sing-box-script/${PLAIN}" "${YELLOW}Usage documentation: https://233boy.com/sing-box/sing-box-script/${PLAIN}" "${YELLOW}Документация по использованию : https://233boy.com/sing-box/sing-box-script/${PLAIN}")"
    echo -e "$(localized_text "${GREEN}安装完成后，通常可运行 sing-box 或 sb 打开管理菜单。${PLAIN}" "${GREEN}After installation, run sing-box or sb to open its management menu.${PLAIN}" "${GREEN}После установки запустите sing-box или sb, чтобы открыть меню управления.${PLAIN}")"
    run_remote_script "$(localized_text "安装 233boy Sing-box" "Install 233boy Sing-box" "Установить 233boy Sing-box")" "https://github.com/233boy/sing-box/raw/main/install.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_singbox_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 Sing-box 管理 / 卸载${PLAIN}" "${BOLD}🧭 Manage or uninstall Sing-box${PLAIN}" "${BOLD}🧭 Управление или удаление Sing-box${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}打开已安装的 233boy Sing-box 管理菜单。${PLAIN}" "${YELLOW}Open the management menu for an installed 233boy Sing-box deployment.${PLAIN}" "${YELLOW}Открыть меню управления установленным 233boy Sing-box.${PLAIN}")"
    echo -e "------------------------------------------------"

    local sb_cmd=""
    if command -v sb >/dev/null 2>&1; then
        sb_cmd="sb"
    elif command -v sing-box >/dev/null 2>&1; then
        sb_cmd="sing-box"
    fi

    if [[ -z "$sb_cmd" ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到 sb 或 sing-box 管理命令。${PLAIN}" "${YELLOW}The sb and sing-box management commands were not found.${PLAIN}" "${YELLOW}Команды управления sb и sing-box не найдены.${PLAIN}")"
        echo -e "$(localized_text "${BLUE}首次部署请先选择 Sing-box 安装项。${PLAIN}" "${BLUE}For a first-time deployment, select the Sing-box installation option first.${PLAIN}" "${BLUE}При первой установке сначала выберите установку Sing-box.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 ${sb_cmd} 管理菜单。${PLAIN}" "${GREEN}Opening the ${sb_cmd} management menu.${PLAIN}" "${GREEN}Открывается меню управления ${sb_cmd}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在该菜单中选择卸载。${PLAIN}" "${YELLOW}To uninstall it, select the uninstall option in that menu.${PLAIN}" "${YELLOW}Для удаления выберите соответствующий пункт в этом меню.${PLAIN}")"
    echo -e "------------------------------------------------"
    "$sb_cmd"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_xray_233boy() {
    clear
    echo -e "$(localized_text "${CYAN}▶ 正在获取 233boy Xray 安装脚本...${PLAIN}" "${CYAN}▶ Fetching the 233boy Xray installer...${PLAIN}" "${CYAN}▶ Загрузка установщика 233boy Xray...${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}脚本来源：https://github.com/233boy/Xray${PLAIN}" "${YELLOW}Script source: https://github.com/233boy/Xray${PLAIN}" "${YELLOW}Источник сценария : https://github.com/233boy/Xray${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}使用文档：https://233boy.com/xray/xray-script/${PLAIN}" "${YELLOW}Usage documentation: https://233boy.com/xray/xray-script/${PLAIN}" "${YELLOW}Документация по использованию : https://233boy.com/xray/xray-script/${PLAIN}")"
    echo -e "$(localized_text "${GREEN}安装完成后，通常可运行 xray 打开管理菜单。${PLAIN}" "${GREEN}After installation, run xray to open its management menu.${PLAIN}" "${GREEN}После установки запустите xray, чтобы открыть меню управления.${PLAIN}")"
    run_remote_script "$(localized_text "安装 233boy Xray" "Install 233boy Xray" "Установить 233boy Xray")" "https://github.com/233boy/Xray/raw/main/install.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_xray_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 Xray 管理 / 卸载${PLAIN}" "${BOLD}🧭 Manage or uninstall Xray${PLAIN}" "${BOLD}🧭 Управление или удаление Xray${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}打开已安装的 233boy Xray 管理菜单。${PLAIN}" "${YELLOW}Open the management menu for an installed 233boy Xray deployment.${PLAIN}" "${YELLOW}Открыть меню управления установленным 233boy Xray.${PLAIN}")"
    echo -e "------------------------------------------------"

    if ! command -v xray >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}未检测到 xray 管理命令，可能尚未安装 233boy Xray。${PLAIN}" "${YELLOW}The xray management command was not found; 233boy Xray may not be installed.${PLAIN}" "${YELLOW}Команда управления xray не найдена; возможно, 233boy Xray не установлен.${PLAIN}")"
        if confirm_danger "$(localized_text "安装 233boy Xray" "Install 233boy Xray" "Установить 233boy Xray")" \
            "$(localized_text "下载并执行 233boy Xray 安装脚本" "download and run the 233boy Xray installer" "скачать и запустить установщик 233boy Xray")" \
            "$(localized_text "安装前备份现有 Xray 配置；卸载方式以该项目菜单为准" "back up existing Xray configuration first; use the project menu to uninstall" "сначала сохраните существующую конфигурацию Xray; для удаления используйте меню проекта")"; then
            func_xray_233boy
        else
            echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        fi
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 xray 管理菜单。${PLAIN}" "${GREEN}Opening the xray management menu.${PLAIN}" "${GREEN}Открывается меню управления xray.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在该菜单中选择卸载。${PLAIN}" "${YELLOW}To uninstall it, select the uninstall option in that menu.${PLAIN}" "${YELLOW}Для удаления выберите соответствующий пункт в этом меню.${PLAIN}")"
    echo -e "------------------------------------------------"
    xray
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

# ---------------------------------------------------------
# 17. DNS 流媒体分流解锁 (Alice DNS)
# ---------------------------------------------------------
func_dns_unlock() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔓 DNS 流媒体分流解锁 (DNS-Alice-Unlock)${PLAIN}" "${BOLD}🔓 DNS Streaming media split unlock (DNS-Alice-Unlock)${PLAIN}" "${BOLD}🔓 DNS Разделенная разблокировка потокового мультимедиа (DNS-Alice-Unlock)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}功能介绍与使用说明：${PLAIN}" "${YELLOW}Purpose and instructions for use:${PLAIN}" "${YELLOW}Описание функции и инструкции по использованию:${PLAIN}")"
    echo -e "$(localized_text " 1. 该脚本通过修改本地 DNS 解析，实现 Netflix, Disney+ 等特定区域流媒体的解锁。" "1. This script modifies the local DNS parsing to unlock streaming media in specific regions such as Netflix and Disney+." "1. Этот скрипт изменяет локальный анализ DNS, чтобы разблокировать потоковое мультимедиа в определенных регионах, таких как Netflix и Disney+.")"
    echo -e "$(localized_text " 2. ${GREEN}仅对流媒体域名进行分流${PLAIN}，不影响您的原生 IP 和普通上网速度。" "2. ${GREEN}Only offloads the streaming domain${PLAIN} and does not affect your native IP and normal Internet speed." "2. ${GREEN}только разгружает потоковое доменное имя${PLAIN} и не влияет на ваш собственный IP-адрес и нормальную скорость Интернета.")"
    echo -e "$(localized_text " 3. 项目地址：${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}" "3. Project address: ${BLUE}Https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}" "3. Адрес проекта: ${BLUE}https://github.com/Jimmyzxk/DNS-Alice-Unlock/${PLAIN}.")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${RED}⚠️  风险提示：运行此脚本会修改您服务器的 /etc/resolv.conf 配置。${PLAIN}" "${RED}⚠️ Risk warning: Running this script will modify the /etc/resolv.conf configuration of your server.${PLAIN}" "${RED}⚠️ Предупреждение о риске: запуск этого сценария приведет к изменению конфигурации /etc/resolv.conf вашего сервера.${PLAIN}")"
    echo -e "$(localized_text "    如果您不懂如何自行配置解锁机的 DNS 记录，请务必先查阅项目文档！" "If you don’t know how to configure the DNS record of the unlocking machine yourself, please be sure to check the project documentation first!" "Если вы не знаете, как самостоятельно настроить запись DNS устройства разблокировки, обязательно сначала ознакомьтесь с проектной документацией!")"
    echo -e "------------------------------------------------"
    
    if confirm_danger "$(localized_text "运行 Alice DNS 解锁脚本" "Run the Alice DNS unlock script" "Запустить сценарий Alice DNS Unlock")" \
        "$(localized_text "执行远程脚本并修改 /etc/resolv.conf" "run a remote script and modify /etc/resolv.conf" "запустить удалённый сценарий и изменить /etc/resolv.conf")" \
        "$(localized_text "运行前备份 DNS 配置；恢复方式以项目文档为准" "back up the DNS configuration first; follow the project documentation to restore it" "сначала сохраните конфигурацию DNS; восстановление выполняйте по документации проекта")"; then
        run_remote_script "$(localized_text "运行 Alice DNS 解锁脚本" "Run the Alice DNS unlocking script" "Запустите скрипт разблокировки Алисы DNS.")" "https://raw.githubusercontent.com/Jimmyzxk/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh"
    else
        echo -e "$(localized_text "${BLUE}已安全取消操作。${PLAIN}" "${BLUE}The operation has been safely canceled.${PLAIN}" "${BLUE}Операция была благополучно отменена.${PLAIN}")"
    fi
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}
# ---------------------------------------------------------
# 新增功能：安装 IP Sentinel (防止 IP 送中)
# ---------------------------------------------------------
func_ip_sentinel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🛡️ 安装 IP Sentinel (防止 IP 送中)${PLAIN}" "${BOLD}🛡️ Install IP Sentinel (prevent IP from being sent)${PLAIN}" "${BOLD}🛡️ Установить IP Sentinel (запретить отправку IP)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}该脚本将持续监控并修正路由，防止服务器 IP 被错误定位至中国大陆。${PLAIN}" "${YELLOW}This script will continuously monitor and correct routing to prevent the server IP from being incorrectly located in mainland China.${PLAIN}" "${YELLOW}Этот сценарий будет постоянно отслеживать и корректировать маршрутизацию, чтобы предотвратить неправильное определение IP-адреса сервера в материковом Китае.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    if confirm_danger "$(localized_text "安装并配置 IP Sentinel" "Install and configure IP Sentinel" "Установить и настроить IP Sentinel")" \
        "$(localized_text "执行远程安装脚本并持续修改网络路由" "run a remote installer that continuously adjusts network routes" "запустить удалённый установщик, который будет постоянно изменять сетевые маршруты")" \
        "$(localized_text "运行前备份网络配置；停止与卸载方式以项目文档为准" "back up the network configuration first; follow the project documentation to stop or uninstall it" "сначала сохраните сетевую конфигурацию; остановку и удаление выполняйте по документации проекта")"; then
        run_remote_script "$(localized_text "安装并配置 IP Sentinel" "Install and configure IP Sentinel" "Установка и настройка IP Sentinel")" "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh"
    else
        echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
    fi
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

# ---------------------------------------------------------
# 安装 VPS_BOT_X Telegram 远程管理机器人
# ---------------------------------------------------------
func_vps_bot_x() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🤖 Telegram VPS Bot 远程管理${PLAIN}" "${BOLD}🤖 Telegram VPS Bot remote management${PLAIN}" "${BOLD}🤖 Удалённое управление Telegram VPS Bot${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}第三方脚本会安装 Telegram 管理 Bot，并要求 Bot Token 与管理员 Telegram ID。${PLAIN}" "${YELLOW}The third-party script installs a Telegram management bot and requires a Bot Token and an administrator Telegram ID.${PLAIN}" "${YELLOW}Сторонний скрипт устанавливает Telegram-бота управления; потребуются Bot Token и Telegram ID администратора.${PLAIN}")"

    if ! confirm_danger \
        "$(localized_text "安装 Telegram VPS Bot" "Install Telegram VPS Bot" "Установить Telegram VPS Bot")" \
        "$(localized_text "将以 root 运行第三方安装脚本，写入 /root/vps_bot-x、/root/sentinel_config.json、vpsbot.service 和 /usr/bin/kk；授权账户可通过 Telegram 执行服务器管理操作。" "A third-party installer will run as root and create /root/vps_bot-x, /root/sentinel_config.json, vpsbot.service, and /usr/bin/kk; authorized accounts can perform server management through Telegram." "Сторонний установщик будет запущен от root и создаст /root/vps_bot-x, /root/sentinel_config.json, vpsbot.service и /usr/bin/kk; авторизованные аккаунты смогут управлять сервером через Telegram.")" \
        "$(localized_text "仅授权受信任的 Telegram 账户，并妥善保管 Bot Token。" "Authorize only trusted Telegram accounts and protect the Bot Token." "Разрешайте доступ только доверенным Telegram-аккаунтам и храните Bot Token в безопасности.")" \
        "$(localized_text "项目地址：https://github.com/MEILOI/VPS_BOT_X" "Project URL: https://github.com/MEILOI/VPS_BOT_X" "Адрес проекта: https://github.com/MEILOI/VPS_BOT_X")"; then
        echo -e "$(localized_text "${BLUE}已取消安装。${PLAIN}" "${BLUE}Installation canceled.${PLAIN}" "${BLUE}Установка отменена.${PLAIN}")"
        pause_after_external_script "$(localized_text "按回车键返回菜单..." "Press Enter to return to the menu..." "Нажмите Enter, чтобы вернуться в меню...")"
        return
    fi

    run_remote_script \
        "$(localized_text "安装 Telegram VPS Bot" "Install Telegram VPS Bot" "Установить Telegram VPS Bot")" \
        "https://raw.githubusercontent.com/MEILOI/VPS_BOT_X/main/vps_bot-x/install.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

# ---------------------------------------------------------
# 新增功能：安装 SublinkPro (强大的订阅转换与管理面板)
# ---------------------------------------------------------
