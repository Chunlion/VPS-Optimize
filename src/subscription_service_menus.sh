# shellcheck shell=bash
# Panel, node, subscription-tool, and compose service action menus.

func_manage_sublinkpro() {
    manage_compose_project "SublinkPro" "/opt/sublinkpro" "$(localized_text "db / template / logs 会保存在部署目录中" "db/template/logs will be saved in the deployment directory" "db/template/logs будет сохранен в каталоге развертывания.")"
}

func_manage_miaomiaowu() {
    manage_compose_project "$(localized_text "妙妙屋订阅管理" "Miaomiaowu Subscription Management" "Управление подпиской Miaomiaowu")" "/opt/miaomiaowu" "$(localized_text "data / subscribes / rule_templates 会保存在部署目录中" "data/subscribes/rule_templates will be saved in the deployment directory" "data/subscribes/rule_templates будут сохранены в каталоге развертывания.")"
}

func_manage_substore() {
    manage_compose_project "Sub-Store" "/opt/sub-store" "$(localized_text "data 会保存在部署目录中" "data will be saved in the deployment directory" "данные будут сохранены в каталоге развертывания")"
}

func_manage_dockge() {
    manage_compose_project "Dockge" "/opt/dockge" "$(localized_text "Dockge 数据在 /opt/dockge/data；Stacks 默认在 /opt/stacks，不会随 Dockge 目录删除" "Dockge data is in /opt/dockge/data; Stacks is in /opt/stacks by default and will not be deleted with the Dockge directory." "Данные Dockge находятся в /opt/dockge/data; По умолчанию стеки находятся в /opt/stacks и не будут удалены вместе с каталогом Dockge.")"
}

func_manage_komari() {
    manage_compose_project "Komari" "/opt/komari" "$(localized_text "Komari 数据会保存在 /opt/komari/data" "Komari data will be saved in /opt/komari/data" "Данные Комари будут сохранены в /opt/komari/data.")"
}

func_service_action_menu() {
    local title="$1"
    local usage="$2"
    local install_label="$3"
    local install_func="$4"
    local manage_label="$5"
    local manage_func="$6"
    local choice

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "面板、节点与订阅工具 > ${title}" "Panels, Nodes and Subscription Tools > ${title}" "Панели, узлы и инструменты подписки > ${title}")"
        echo -e "${BOLD}🧭 ${title}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}${usage}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. ${install_label}${PLAIN}"
        echo -e "${GREEN}  2. ${manage_label}${PLAIN}"
        echo -e "$(localized_text "${RED}  0. 返回上级菜单 / q 返回${PLAIN}" "${RED}  0. Back / q Back${PLAIN}" "${RED}  0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"

        case "$choice" in
            1) "$install_func" ;;
            2) "$manage_func" ;;
            0|q|Q) return ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_xpanel_menu() {
    func_service_action_menu "$(localized_text "3x-ui / x-ui 面板" "3x-ui / x-ui panel" "Панель 3x-ui / x-ui")" "$(localized_text "安装面板，或进入官方菜单配置、更新、重置和卸载。" "Install the panel or open its official menu to configure, update, reset, or uninstall it." "Установить панель либо открыть официальное меню для настройки, обновления, сброса или удаления.")" "$(localized_text "安装 3x-ui 面板" "Install 3x-ui panel" "Установить панель 3x-ui")" func_xpanel "$(localized_text "管理 / 卸载 3x-ui 面板" "Manage or uninstall 3x-ui" "Управление или удаление 3x-ui")" func_xpanel_manage
}

func_sui_menu() {
    func_service_action_menu "$(localized_text "S-UI 面板" "S-UI panel" "Панель S-UI")" "$(localized_text "安装或进入 S-UI 官方菜单进行配置、更新、卸载。" "Install or enter the S-UI official menu to configure, update, and uninstall." "Установите или войдите в официальное меню S-UI для настройки, обновления и удаления.")" "$(localized_text "安装 S-UI 面板" "Install S-UI panel" "Установите панель S-UI.")" func_sui_panel "$(localized_text "管理 / 卸载 S-UI 面板" "Manage/Uninstall S-UI Panel" "Управление/удаление панели S-UI")" func_sui_manage
}

func_singbox_menu() {
    local choice

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🧭 Sing-box 管理${PLAIN}" "${BOLD}🧭 Sing-box management${PLAIN}" "${BOLD}🧭 Управление Sing-box${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}安装 233boy Sing-box 脚本，或进入已安装脚本的管理菜单。${PLAIN}" "${YELLOW}Install the 233boy Sing-box script or open its management menu.${PLAIN}" "${YELLOW}Установить скрипт Sing-box от 233boy либо открыть его меню управления.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 安装 Sing-box（233boy）${PLAIN}" "${GREEN}  1. Install Sing-box (233boy)${PLAIN}" "${GREEN}  1. Установить Sing-box (233boy)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 管理 / 卸载 Sing-box${PLAIN}" "${GREEN}  2. Manage or uninstall Sing-box${PLAIN}" "${GREEN}  2. Управление или удаление Sing-box${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回上级菜单 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"

        case "$choice" in
            1) func_singbox_233boy ;;
            2) func_singbox_manage ;;
            0|q|Q) return ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_xray_menu() {
    func_service_action_menu "$(localized_text "Xray 管理" "Xray management" "Управление Xray")" "$(localized_text "安装 233boy Xray 脚本，或进入其管理菜单配置、更新和卸载。" "Install the 233boy Xray script or open its menu to configure, update, or uninstall it." "Установить скрипт Xray от 233boy либо открыть его меню для настройки, обновления или удаления.")" "$(localized_text "安装 Xray（233boy）" "Install Xray (233boy)" "Установить Xray (233boy)")" func_xray_233boy "$(localized_text "管理 / 卸载 Xray" "Manage or uninstall Xray" "Управление или удаление Xray")" func_xray_manage
}

func_sublinkpro_menu() {
    func_service_action_menu "$(localized_text "SublinkPro 管理" "SublinkPro management" "Управление SublinkPro")" "$(localized_text "安装或管理通过 Docker Compose 部署的 SublinkPro。" "Install or manage SublinkPro deployed with Docker Compose." "Установить или управлять SublinkPro, развёрнутым через Docker Compose.")" "$(localized_text "安装 SublinkPro" "Install SublinkPro" "Установить SublinkPro")" func_sublinkpro "$(localized_text "管理 / 卸载 SublinkPro" "Manage or uninstall SublinkPro" "Управление или удаление SublinkPro")" func_manage_sublinkpro
}

func_miaomiaowu_menu() {
    func_service_action_menu "$(localized_text "妙妙屋订阅管理" "Miaomiaowu Subscription Management" "Управление подпиской Miaomiaowu")" "$(localized_text "安装或管理 Docker Compose 部署的妙妙屋订阅管理。" "Install or manage Docker Compose deployment of Miaomiaowu Subscription Management." "Установите или управляйте развертыванием Docker Compose для управления подписками Miaomiaowu.")" "$(localized_text "安装 妙妙屋订阅管理" "Install Miaomiaowu Subscription Management" "Установите управление подпиской Miaomiaowu")" func_miaomiaowu "$(localized_text "管理 / 卸载 妙妙屋" "Manage / Uninstall Miaomiaowu" "Управление / Удаление")" func_manage_miaomiaowu
}

func_substore_menu() {
    func_service_action_menu "$(localized_text "Sub-Store 管理" "Sub-Store management" "Управление Sub-Store")" "$(localized_text "安装或管理通过 Docker Compose 部署的 Sub-Store。" "Install or manage Sub-Store deployed with Docker Compose." "Установить или управлять Sub-Store, развёрнутым через Docker Compose.")" "$(localized_text "安装 Sub-Store" "Install Sub-Store" "Установить Sub-Store")" func_substore "$(localized_text "管理 / 卸载 Sub-Store" "Manage or uninstall Sub-Store" "Управление или удаление Sub-Store")" func_manage_substore
}

func_dockge_menu() {
    func_service_action_menu "$(localized_text "Dockge 管理" "Dockge management" "Управление Dockge")" "$(localized_text "安装或管理通过 Docker Compose 部署的 Dockge。" "Install or manage Dockge deployed with Docker Compose." "Установить или управлять Dockge, развёрнутым через Docker Compose.")" "$(localized_text "安装 Dockge" "Install Dockge" "Установить Dockge")" func_dockge "$(localized_text "管理 / 卸载 Dockge" "Manage or uninstall Dockge" "Управление или удаление Dockge")" func_manage_dockge
}

func_komari_menu() {
    func_service_action_menu "$(localized_text "Komari 探针监控" "Komari monitoring" "Мониторинг Komari")" "$(localized_text "安装或管理 Docker Compose 部署的 Komari 探针监控面板。" "Install or manage the Komari monitoring panel deployed with Docker Compose." "Установить или настроить панель мониторинга Komari, развёрнутую через Docker Compose.")" "$(localized_text "安装 Komari" "Install Komari" "Установить Komari")" func_komari "$(localized_text "管理 / 卸载 Komari" "Manage / Uninstall Komari" "Управление / удаление Komari")" func_manage_komari
}
