# shellcheck shell=bash
# Panel, node, subscription-tool, and compose service action menus.

func_manage_sublinkpro() {
    manage_compose_project "SublinkPro" "/opt/sublinkpro" "db / template / logs 会保存在部署目录中"
}

func_manage_miaomiaowu() {
    manage_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" "data / subscribes / rule_templates 会保存在部署目录中"
}

func_manage_substore() {
    manage_compose_project "Sub-Store" "/opt/sub-store" "data 会保存在部署目录中"
}

func_manage_dockge() {
    manage_compose_project "Dockge" "/opt/dockge" "Dockge 数据在 /opt/dockge/data；Stacks 默认在 /opt/stacks，不会随 Dockge 目录删除"
}

func_manage_komari() {
    manage_compose_project "Komari" "/opt/komari" "Komari 数据会保存在 /opt/komari/data"
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
        print_breadcrumb "面板、节点与订阅工具 > ${title}"
        echo -e "${BOLD}🧭 ${title}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}${usage}${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. ${install_label}${PLAIN}"
        echo -e "${GREEN}  2. ${manage_label}${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "👉 请选择操作: "

        case "$choice" in
            1) "$install_func" ;;
            2) "$manage_func" ;;
            0|q|Q) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_xpanel_menu() {
    func_service_action_menu "3x-ui / x-ui 面板" "安装或进入官方菜单进行配置、更新、重置、卸载。" "安装 3x-ui 面板" func_xpanel "管理 / 卸载 3x-ui 面板" func_xpanel_manage
}

func_singbox_menu() {
    local choice

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 Sing-box 管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}可安装 Sing-box 一键脚本，也可进入已安装脚本的管理菜单。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 安装 Sing-box（233boy 一键脚本）${PLAIN}"
        echo -e "${GREEN}  2. 管理 / 卸载 Sing-box${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "👉 请选择操作: "

        case "$choice" in
            1) func_singbox_233boy ;;
            2) func_singbox_manage ;;
            0|q|Q) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_xray_menu() {
    func_service_action_menu "Xray 管理" "安装或进入 233boy Xray 官方菜单进行配置、更新、卸载。" "安装 Xray（233boy 一键脚本）" func_xray_233boy "管理 / 卸载 Xray" func_xray_manage
}

func_sublinkpro_menu() {
    func_service_action_menu "SublinkPro 管理" "安装或管理 Docker Compose 部署的 SublinkPro。" "安装 SublinkPro" func_sublinkpro "管理 / 卸载 SublinkPro" func_manage_sublinkpro
}

func_miaomiaowu_menu() {
    func_service_action_menu "妙妙屋订阅管理" "安装或管理 Docker Compose 部署的妙妙屋订阅管理。" "安装 妙妙屋订阅管理" func_miaomiaowu "管理 / 卸载 妙妙屋" func_manage_miaomiaowu
}

func_substore_menu() {
    func_service_action_menu "Sub-Store 管理" "安装或管理 Docker Compose 部署的 Sub-Store。" "安装 Sub-Store" func_substore "管理 / 卸载 Sub-Store" func_manage_substore
}

func_dockge_menu() {
    func_service_action_menu "Dockge 管理" "安装或管理 Docker Compose 部署的 Dockge。" "安装 Dockge" func_dockge "管理 / 卸载 Dockge" func_manage_dockge
}

func_komari_menu() {
    func_service_action_menu "Komari 探针监控" "安装或管理 Docker Compose 部署的 Komari 探针监控面板。" "安装 Komari" func_komari "管理 / 卸载 Komari" func_manage_komari
}
