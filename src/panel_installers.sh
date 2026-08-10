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
    read_trimmed version_choice "$(localized_text "请选择 3x-ui 安装版本（默认 1）: " "Please select 3x-ui installation version (default 1):" "Пожалуйста, выберите версию установки 3x-ui (по умолчанию 1):")"
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
    echo -e "$(localized_text "${BOLD}🧭 3x-ui / x-ui 管理 / 卸载${PLAIN}" "${BOLD}🧭 3x-ui / x-ui Manage / Uninstall${PLAIN}" "${BOLD}🧭 3x-ui / x-ui Управление / Удаление${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：进入官方管理菜单，执行配置查看、账号管理、更新或卸载等操作。${PLAIN}" "${YELLOW}Purpose: Enter the official management menu to perform configuration viewing, account management, update or uninstall, etc.${PLAIN}" "${YELLOW}Назначение: войти в официальное меню управления для просмотра конфигурации, управления учетной записью, обновления или удаления и т. д.${PLAIN}")"
    echo -e "------------------------------------------------"

    local panel_cmd=""
    if command -v x-ui >/dev/null 2>&1; then
        panel_cmd="x-ui"
    elif command -v 3x-ui >/dev/null 2>&1; then
        panel_cmd="3x-ui"
    fi

    if [[ -z "$panel_cmd" ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到 x-ui / 3x-ui 命令，当前机器可能尚未安装 3x-ui 面板。${PLAIN}" "${YELLOW}Does not detect the x-ui / 3x-ui command. The current machine may not have the 3x-ui panel installed.${PLAIN}" "${YELLOW}не обнаруживает команду x-ui/3x-ui. Возможно, на текущем компьютере не установлена ​​панель 3x-ui.${PLAIN}")"
        local yn
        read_trimmed yn "$(localized_text "是否现在安装 3x-ui 面板？(Y/n): " "Do you want to install the 3x-ui panel now? (Y/n):" "Хотите установить панель 3x-ui сейчас? (Да/Нет):")"
        if is_yes "$yn"; then
            func_xpanel
        else
            echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        fi
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 ${panel_cmd} 官方管理菜单。${PLAIN}" "${GREEN}Is about to open the ${panel_cmd} official management menu.${PLAIN}" "${GREEN}собирается открыть официальное меню управления ${panel_cmd}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}" "${YELLOW}If you need to uninstall , please select the corresponding uninstall item in the official menu.${PLAIN}" "${YELLOW}Если вам необходимо удалить , выберите соответствующий пункт удаления в официальном меню.${PLAIN}")"
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
    echo -e "$(localized_text "${BOLD}🧭 S-UI 管理 / 卸载${PLAIN}" "${BOLD}🧭 S-UI Manage / Uninstall${PLAIN}" "${BOLD}🧭 S-UI Управление / Удаление${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：进入 S-UI 官方管理菜单，执行配置查看、账号管理、更新或卸载等操作。${PLAIN}" "${YELLOW}Purpose: Enter the S-UI official management menu to perform operations such as configuration viewing, account management, update or uninstallation.${PLAIN}" "${YELLOW}Назначение : Войдите в официальное меню управления S-UI для выполнения таких операций, как просмотр конфигурации, управление учетной записью, обновление или удаление.${PLAIN}")"
    echo -e "------------------------------------------------"

    if ! command -v s-ui >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}未检测到 s-ui 命令，当前机器可能尚未安装 S-UI。${PLAIN}" "${YELLOW}Does not detect the s-ui command. S-UI may not be installed on the current machine.${PLAIN}" "${YELLOW}не обнаруживает команду s-ui. S-UI может быть не установлен на текущем компьютере.${PLAIN}")"
        local yn
        read_trimmed yn "$(localized_text "是否现在安装 S-UI？(Y/n): " "Do you want to install S-UI now? (Y/n):" "Хотите установить S-UI сейчас? (Да/Нет):")"
        if is_yes "$yn"; then
            func_sui_panel
        else
            echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        fi
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 S-UI 官方管理菜单。${PLAIN}" "${GREEN}Is about to open the S-UI official management menu.${PLAIN}" "${GREEN}собирается открыть официальное меню управления S-UI.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}" "${YELLOW}If you need to uninstall , please select the corresponding uninstall item in the official menu.${PLAIN}" "${YELLOW}Если вам необходимо удалить , выберите соответствующий пункт удаления в официальном меню.${PLAIN}")"
    echo -e "------------------------------------------------"
    s-ui
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_singbox_233boy() {
    clear
    echo -e "$(localized_text "${CYAN}👉 正在拉取 233boy 的 Sing-box 一键脚本...${PLAIN}" "${CYAN}👉 Pulling 233boy’s Sing-box one-click script...${PLAIN}" "${CYAN}👉 Вытаскиваем скрипт 233boy Sing-box в один клик...${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}脚本来源：https://github.com/233boy/sing-box${PLAIN}" "${YELLOW}Script source: https://github.com/233boy/sing-box${PLAIN}" "${YELLOW}Источник сценария : https://github.com/233boy/sing-box${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}使用文档：https://233boy.com/sing-box/sing-box-script/${PLAIN}" "${YELLOW}Usage documentation: https://233boy.com/sing-box/sing-box-script/${PLAIN}" "${YELLOW}Документация по использованию : https://233boy.com/sing-box/sing-box-script/${PLAIN}")"
    echo -e "$(localized_text "${GREEN}安装完成后通常可使用 sing-box 或 sb 命令进入管理面板。${PLAIN}" "${GREEN}After is installed, you can usually use the sing-box or sb command to enter the management panel.${PLAIN}" "${GREEN}После установки обычно можно использовать команду sing-box или sb для входа в панель управления.${PLAIN}")"
    run_remote_script "$(localized_text "安装 Sing-box 233boy 一键脚本" "Install Sing-box 233boy one-click script" "Установите скрипт Sing-box 233boy в один клик")" "https://github.com/233boy/sing-box/raw/main/install.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_singbox_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 Sing-box 管理 / 卸载${PLAIN}" "${BOLD}🧭 Sing-box Manage / Uninstall${PLAIN}" "${BOLD}🧭 Sing-box Управление / Удаление${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：进入已安装 Sing-box 一键脚本的管理菜单。${PLAIN}" "${YELLOW}Purpose: Enter the management menu of the installed Sing-box one-click script.${PLAIN}" "${YELLOW}Назначение: Войти в меню управления установленным скриптом Sing-box в один клик.${PLAIN}")"
    echo -e "------------------------------------------------"

    local sb_cmd=""
    if command -v sb >/dev/null 2>&1; then
        sb_cmd="sb"
    elif command -v sing-box >/dev/null 2>&1; then
        sb_cmd="sing-box"
    fi

    if [[ -z "$sb_cmd" ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到 sb / sing-box 管理命令。${PLAIN}" "${YELLOW}Sb/sing-box management command not detected.${PLAIN}" "${YELLOW}Команда управления sb/sing-box не обнаружена.${PLAIN}")"
        echo -e "$(localized_text "${BLUE}如果是首次部署，请先选择对应的 Sing-box 安装项。${PLAIN}" "${BLUE}If is deployed for the first time, please select the corresponding Sing-box installation item first.${PLAIN}" "${BLUE}Если развертывается впервые, сначала выберите соответствующий элемент установки Sing-box.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 ${sb_cmd} 管理菜单。${PLAIN}" "${GREEN}Is about to open the ${sb_cmd} management menu.${PLAIN}" "${GREEN}собирается открыть меню управления ${sb_cmd}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在脚本菜单中选择对应卸载项。${PLAIN}" "${YELLOW}If you need to uninstall , please select the corresponding uninstall item in the script menu.${PLAIN}" "${YELLOW}Если вам необходимо удалить , выберите соответствующий пункт удаления в меню сценариев.${PLAIN}")"
    echo -e "------------------------------------------------"
    "$sb_cmd"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_xray_233boy() {
    clear
    echo -e "$(localized_text "${CYAN}👉 正在拉取 233boy 的 Xray 一键脚本...${PLAIN}" "${CYAN}👉 Pulling 233boy’s Xray one-click script...${PLAIN}" "${CYAN}👉 Вытаскиваем скрипт 233boy Xray в один клик...${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}脚本来源：https://github.com/233boy/Xray${PLAIN}" "${YELLOW}Script source: https://github.com/233boy/Xray${PLAIN}" "${YELLOW}Источник сценария : https://github.com/233boy/Xray${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}使用文档：https://233boy.com/xray/xray-script/${PLAIN}" "${YELLOW}Usage documentation: https://233boy.com/xray/xray-script/${PLAIN}" "${YELLOW}Документация по использованию : https://233boy.com/xray/xray-script/${PLAIN}")"
    echo -e "$(localized_text "${GREEN}安装完成后通常可使用 xray 命令进入管理面板。${PLAIN}" "${GREEN}After is installed, you can usually use the xray command to enter the management panel.${PLAIN}" "${GREEN}После установки обычно можно использовать команду xray для входа в панель управления.${PLAIN}")"
    run_remote_script "$(localized_text "安装 Xray 233boy 一键脚本" "Install Xray 233boy one-click script" "Установите скрипт Xray 233boy в один клик")" "https://github.com/233boy/Xray/raw/main/install.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

func_xray_manage() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧭 Xray 管理 / 卸载${PLAIN}" "${BOLD}🧭 Xray Manage / Uninstall${PLAIN}" "${BOLD}🧭 Xray Управление / Удаление${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}用途：进入 233boy Xray 官方管理菜单。${PLAIN}" "${YELLOW}Purpose: Enter the 233boy Xray official management menu.${PLAIN}" "${YELLOW}Назначение: Войти в официальное меню управления 233boy Xray.${PLAIN}")"
    echo -e "------------------------------------------------"

    if ! command -v xray >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}未检测到 xray 管理命令，当前机器可能尚未安装 233boy Xray 脚本。${PLAIN}" "${YELLOW}Does not detect the xray management command. The current machine may not have the 233boy Xray script installed.${PLAIN}" "${YELLOW}не обнаруживает команду управления xray. На текущей машине может не быть установлен скрипт 233boy Xray.${PLAIN}")"
        local yn
        read_trimmed yn "$(localized_text "是否现在安装 Xray？(Y/n): " "Do you want to install Xray now? (Y/n):" "Хотите установить Xray сейчас? (Да/Нет):")"
        if is_yes "$yn"; then
            func_xray_233boy
        else
            echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        fi
        return
    fi

    echo -e "$(localized_text "${GREEN}即将打开 xray 管理菜单。${PLAIN}" "${GREEN}Is about to open the xray management menu.${PLAIN}" "${GREEN}собирается открыть меню управления xray.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}如需卸载，请在官方菜单中选择对应卸载项。${PLAIN}" "${YELLOW}If you need to uninstall , please select the corresponding uninstall item in the official menu.${PLAIN}" "${YELLOW}Если вам необходимо удалить , выберите соответствующий пункт удаления в официальном меню.${PLAIN}")"
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
    
    local yn
    read_trimmed yn "$(localized_text "❓ 确认现在运行 Alice DNS 解锁脚本吗？(Y/n): " "❓ Are you sure to run the Alice DNS unlocking script now? (Y/n):" "❓ Вы уверены, что сейчас запустите скрипт разблокировки Алисы DNS? (Да/Нет):")"
    if is_yes "$yn"; then
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
    
    read_trimmed yn "$(localized_text "❓ 确定要安装并配置 IP Sentinel(公共网关) 吗？(Y/n): " "❓ Are you sure you want to install and configure IP Sentinel (Public Gateway)? (Y/n):" "❓ Вы уверены, что хотите установить и настроить IP Sentinel (публичный шлюз)? (Да/Нет):")"
    if is_yes "$yn"; then
        run_remote_script "$(localized_text "安装并配置 IP Sentinel" "Install and configure IP Sentinel" "Установка и настройка IP Sentinel")" "https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh"
    else
        echo -e "$(localized_text "${BLUE}已取消操作。${PLAIN}" "${BLUE}The operation has been canceled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
    fi
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

# ---------------------------------------------------------
# 新增功能：安装 SublinkPro (强大的订阅转换与管理面板)
# ---------------------------------------------------------
