# shellcheck shell=bash
# Help text plus top-level and second-level menu wiring.

show_main_help() {
    if [[ "$VPSO_LANGUAGE" == "ru" ]]; then
        echo -e "${CYAN}VPS-Optimize > Главное меню > Справка${PLAIN}"
        echo "1/2 Проверка и первичная настройка нового сервера."
        echo "3   Установка Docker, Python, WARP и распространённых инструментов."
        echo "4   Настройка обратного прокси Caddy/Nginx для сайтов и панелей без повторного использования порта 443."
        echo "5   Управление 3x-ui, S-UI, Sing-box, Xray и инструментами подписок."
        echo "6   Управление портом SSH, открытыми ключами и входом только по ключу."
        echo "8   Управление правилами брандмауэра, открытыми портами и лимитами соединений для каждого IP-адреса."
        echo "10  Оптимизация сети и ядра: BBR, TCP, ZRAM и очистка старых ядер."
        echo "15  Обзор состояния служб и создание диагностических данных для поиска неисправностей."
        echo "16  Резервное копирование и откат конфигурации перед операциями с высоким риском."
        echo "19  Управление единым публичным входом 443 для панелей, подписок и REALITY."
        echo "20  Выбор языка интерфейса."
        echo "10 -> 5  Защита от превышения лимита трафика с учётом расчётного периода."
        echo "? показывает справку; 0/q завершает работу."
    elif [[ "$VPSO_LANGUAGE" == "en" ]]; then
        echo -e "${CYAN}VPS-Optimize > Main menu > Help${PLAIN}"
        echo "1/2 Check and initialize a new server."
        echo "3   Install Docker, Python, WARP, and common tools."
        echo "4   Configure Caddy/Nginx reverse proxies for sites and panels not using Port 443 Reuse."
        echo "5   Manage 3x-ui, S-UI, Sing-box, Xray, and subscription tools."
        echo "6   Manage the SSH port, public keys, and key-only login modes."
        echo "8   Manage firewall rules, allowed ports, and per-source IP connection limits."
        echo "10  Tune networking and the kernel, including BBR, TCP, ZRAM, and kernel cleanup."
        echo "15  View health status and generate diagnostic details for troubleshooting."
        echo "16  Create backups and roll back configuration before high-risk operations."
        echo "19  Manage Port 443 Reuse for panels, subscriptions, and REALITY."
        echo "20  Select the interface language."
        echo "10 -> 5  Protect against traffic overages based on the billing cycle."
        echo "? shows help; 0/q exits."
    else
        echo -e "${CYAN}VPS-Optimize > 主菜单 > 帮助${PLAIN}"
        echo "1/2 适合新机器先体检和初始化。"
        echo "3   基础组件与常用服务；安装 Docker、Python、WARP 和常用工具。"
        echo "4   配置不使用443端口复用的网站与面板反代。"
        echo "5   管理 3x-ui、S-UI、Sing-box、Xray 和订阅工具。"
        echo "6   SSH 安全中心；管理端口、公钥和用户密钥登录模式。"
        echo "8   管理系统防火墙；支持端口放行、删除和每来源 IP 连接数限制。"
        echo "10  网络/内核优化；涉及 BBR、TCP、ZRAM 和内核清理。"
        echo "15  健康总览和反馈诊断信息，用于排错或提交 Issue。"
        echo "16  备份与回滚，高风险操作前建议先跑。"
        echo "19  443端口复用管理中心，面板/订阅/REALITY 共用公网 443。"
        echo "20  选择界面语言。"
        echo "10 -> 5  流量限额保护，按账单周期统计，并在达到阈值时执行保护动作。"
        echo "? 查看帮助，0/q 退出。"
    fi
}

show_panel_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 面板、节点与订阅工具 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Panels, Nodes and Subscription Tools > Help${PLAIN}" "${CYAN}VPS-Optimize > Панели, узлы и инструменты подписки > Справка${PLAIN}")"
    echo "$(localized_text "1 3x-ui：安装、官方菜单、面板修复。" "1 3x-ui: install, open the official menu, or repair the panel." "1 3x-ui: установка, официальное меню и восстановление панели.")"
    echo "$(localized_text "2 x-ui 增强：重置日期、校准流量、备份恢复、日志。" "2 x-ui extension: reset date, calibrate traffic, back up, restore, and view logs." "2 Расширение x-ui: сброс даты, калибровка трафика, резервное копирование, восстановление и журналы.")"
    echo "$(localized_text "3 面板 SSL 修复：443 接入前清空面板证书路径。" "3 Panel SSL repair: clear panel certificate paths before using Port 443 Reuse." "3 Исправление SSL панели: очистить пути сертификатов панели перед настройкой повторного использования порта 443.")"
    echo "$(localized_text "4 S-UI：安装、官方菜单、卸载。" "4 S-UI: install, open the official menu, or uninstall." "4 S-UI: установка, официальное меню и удаление.")"
    echo "$(localized_text "5/6 Sing-box 与 Xray 脚本。" "5/6 Sing-box and Xray scripts." "5/6 Скрипты Sing-box и Xray.")"
    echo "$(localized_text "7/8/9 订阅工具，10 Komari；Dockge / Compose 管理在主菜单 [11 Docker 管理] -> [19]。公网 HTTPS：未启用 443端口复用走主菜单 [4 反代]，已启用走主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代]。" "7/8/9: subscription tools; 10: Komari. Dockge / Compose management is in main menu [11 Docker Management] -> [19]. For public HTTPS, use [4 Reverse proxy] before Port 443 Reuse; afterwards use [19 Port 443 Reuse] -> [8 Manage Web domains/reverse proxy]." "7/8/9: инструменты подписки; 10: Komari. Управление Dockge / Compose находится в главном меню [11 Управление Docker] -> [19]. Для публичного HTTPS до повторного использования порта 443 используйте [4 Обратный прокси], после — [19 Повторное использование порта 443] -> [8 Управление Web-доменами и обратным прокси].")"
    echo "$(localized_text "13 端口流量监控（dog）：仅统计已监控端口的实际流量。" "13 Per-port traffic monitor (dog): shows traffic only for monitored ports." "13 Монитор трафика по портам (dog): показывает трафик только отслеживаемых портов.")"
    echo "$(localized_text "? 查看帮助，0/q 返回主菜单。" "? View help, 0/q returns to the main menu." "? Просмотр справки, 0/q возвращает в главное меню.")"
}

show_sni_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 443端口复用管理中心 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Port 443 Reuse Manager > Help${PLAIN}" "${CYAN}VPS-Optimize > Управление повторным использованием порта 443 > Справка${PLAIN}")"
    echo "$(localized_text "1 入口状态：查看公网 443、Web 反代、Xray 和相关服务。" "1 Entry status: inspect public 443, Web proxy, Xray, and related services." "1 Состояние входа: публичный порт 443, Web-прокси, Xray и связанные службы.")"
    echo "$(localized_text "2 安装 / 切换入口模式：Nginx Stream、Xray Fallback 或 TCP Peek + Splice。" "2 Install or switch entry mode: Nginx Stream, Xray Fallback, or TCP Peek + Splice." "2 Установить или сменить режим: Nginx Stream, Xray Fallback либо TCP Peek + Splice.")"
    echo "$(localized_text "6 重新应用当前模式：按现有参数重新生成入口配置。" "6 Reapply current mode: regenerate the entry configuration from the saved settings." "6 Повторно применить режим: пересоздать конфигурацию входа из сохранённых параметров.")"
    echo "$(localized_text "7 回滚上次切换：恢复切换前的入口配置。" "7 Roll back the last switch: restore the previous entry configuration." "7 Откатить последнее переключение: восстановить предыдущую конфигурацию входа.")"
    echo "$(localized_text "8 Web 域名与反向代理：新增、删除或查看网站。" "8 Web domains and reverse proxies: add, remove, or view sites." "8 Web-домены и обратный прокси: добавить, удалить или просмотреть сайты.")"
    echo "$(localized_text "9 Web IP 白名单：只限制 Web 访问，不影响 Xray 节点。" "9 Web IP allowlist: restrict Web access without affecting Xray nodes." "9 Список разрешённых IP для Web: не влияет на узлы Xray.")"
    echo "$(localized_text "10 共享参数：修改面板、订阅、REALITY、端口和路径。" "10 Shared settings: edit panel, subscription, REALITY, ports, and paths." "10 Общие параметры: панель, подписка, REALITY, порты и пути.")"
    echo "$(localized_text "11 订阅链接检查：确认节点链接使用公网 443 和正确的 External Proxy。" "11 Subscription link check: verify public 443 and External Proxy values in node links." "11 Проверка ссылок подписки: публичный порт 443 и значения External Proxy.")"
    echo "$(localized_text "12 证书维护：更新 Cloudflare Token，重签、修复或回滚证书。" "12 Certificate maintenance: update the Cloudflare token, reissue, repair, or roll back certificates." "12 Сертификаты: обновить токен Cloudflare, перевыпустить, исправить или откатить сертификаты.")"
    echo "$(localized_text "13 443 配置检查：检查入口、监听、证书、Web 和 Xray 路由。" "13 Port 443 configuration check: inspect the entry, listeners, certificates, Web, and Xray routes." "13 Проверка конфигурации 443: вход, слушатели, сертификаты, Web и маршруты Xray.")"
    echo "$(localized_text "14 外网访问测试：检查 DNS、TCP、TLS、面板和订阅。" "14 External access test: check DNS, TCP, TLS, panel, and subscription access." "14 Проверка внешнего доступа: DNS, TCP, TLS, панель и подписка.")"
    echo "$(localized_text "15 Xray SNI 路由：记录 SNI -> 本地地址:端口，不编辑 3x-ui/Xray 入站。" "15 Xray SNI routes: map SNI -> local address:port without editing 3x-ui/Xray inbounds." "15 Маршруты Xray SNI: SNI -> локальный адрес:порт без изменения входов 3x-ui/Xray.")"
    echo "$(localized_text "16 入口日志：按当前模式查看 Nginx、Xray/3x-ui 或 vpso-mux 日志。" "16 Entry logs: show Nginx, Xray/3x-ui, or vpso-mux logs for the active mode." "16 Журналы входа: Nginx, Xray/3x-ui или vpso-mux для активного режима.")"
    echo "$(localized_text "17 REALITY 流量防护：管理严格 SNI 门禁和回落限速。" "17 REALITY traffic protection: manage the strict SNI gate and fallback rate limits." "17 Защита трафика REALITY: строгий контроль SNI и ограничение скорости fallback.")"
    echo "$(localized_text "修改面板域名：[8 Web 域名与反向代理] -> [9 修改面板域名]。" "Change the panel domain: [8 Web domains and reverse proxies] -> [9 Change panel domain]." "Изменить домен панели: [8 Web-домены и обратный прокси] -> [9 Изменить домен панели].")"
    echo "$(localized_text "未启用 443端口复用时，Web 白名单在主菜单 [4 反代] -> [5] 中管理。" "Before enabling Port 443 Reuse, manage the Web allowlist under main menu [4 Reverse proxy] -> [5]." "До включения общего порта 443 управляйте списком разрешённых IP в главном меню [4 Обратный прокси] -> [5].")"
    echo "$(localized_text "? 查看帮助；0/q 返回。" "? Help; 0/q back." "? Справка; 0/q назад.")"
}

show_backup_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 备份与回滚 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Backup and Rollback > Help${PLAIN}" "${CYAN}VPS-Optimize > Резервное копирование и откат > Справка${PLAIN}")"
    echo "$(localized_text "1 创建备份：选择配置、自定义目录或两者；打包前检查空间，可选 AES-256 加密。" "1 Create a backup: choose configuration, custom directories, or both. Space is checked before packaging; AES-256 encryption is optional." "1 Создать копию: выберите конфигурацию, пользовательские каталоги или оба варианта. Перед упаковкой проверяется место; доступно шифрование AES-256.")"
    echo "$(localized_text "2 加载备份包：自动读取默认目录、/backups、/root/backups 和已记录目录中的 .tar.gz / .tar.gz.enc。" "2 Load a backup: scan the default directory, /backups, /root/backups, and recorded directories for .tar.gz and .tar.gz.enc files." "2 Загрузить копию: найти файлы .tar.gz и .tar.gz.enc в каталоге по умолчанию, /backups, /root/backups и сохранённых каталогах.")"
    echo "$(localized_text "3 恢复：支持已加载备份、自动列表或指定路径；先校验归档、路径安全和解压空间。" "3 Restore: use the loaded backup, automatic list, or a specified path. Archive integrity, path safety, and extraction space are checked first." "3 Восстановление: используйте загруженную копию, автоматический список или указанный путь. Сначала проверяются архив, безопасность путей и место для распаковки.")"
    echo "$(localized_text "4 隔离旧备份：移入隔离目录，不直接删除。" "4 Quarantine old backups: move them to quarantine; do not delete them." "4 Изолировать старые копии: переместить в карантин, не удалять.")"
    echo "$(localized_text "5 查看/编辑已应用配置：先备份，校验后可 reload/restart。" "5 View or edit applied configuration: back up first, validate, then reload or restart if needed." "5 Просмотр или правка применённой конфигурации: сначала копия, затем проверка и reload/restart при необходимости.")"
    echo "$(localized_text "? 查看帮助，0/q 返回主菜单。" "? View help, 0/q returns to the main menu." "? Просмотр справки, 0/q возвращает в главное меню.")"
}

show_net_kernel_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 网络/内核优化 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Network/Kernel Optimization > Help${PLAIN}" "${CYAN}VPS-Optimize > Оптимизация сети/ядра > Справка${PLAIN}")"
    echo "$(localized_text "1 BBR / 拥塞控制：调用外部调优脚本，执行前建议备份。" "1 BBR / Congestion control: Call an external tuning script, and it is recommended to back it up before execution." "1 BBR / Контроль перегрузки: вызовите внешний сценарий настройки, и перед выполнением рекомендуется создать его резервную копию.")"
    echo "$(localized_text "2 TCP 参数：修改 sysctl，适合有明确参数需求的用户。" "2 TCP parameters: Modify sysctl, suitable for users with clear parameter requirements." "2 параметра TCP: Измените sysctl, подходит для пользователей с четкими требованиями к параметрам.")"
    echo "$(localized_text "3 DNS 设置：使用预设或自定义的 IPv4/IPv6 DNS。" "3 DNS settings: use preset or custom IPv4/IPv6 resolvers." "3 Настройки DNS: готовые или собственные DNS-серверы IPv4/IPv6.")"
    echo "$(localized_text "4 网络接口管理：查看网卡、路由和 DNS，临时调整 MTU 或刷新 DHCP。" "4 Network interfaces: view interfaces, routes, and DNS; temporarily change MTU or renew DHCP." "4 Сетевые интерфейсы: просмотр интерфейсов, маршрутов и DNS; временная смена MTU или обновление DHCP.")"
    echo "$(localized_text "5 流量限额保护：按账单周期统计流量，达到阈值后关机或仅保留 SSH。" "5 Traffic quota protection: track usage by billing cycle, then shut down or keep only SSH at the threshold." "5 Защита лимита трафика: учёт по расчётному периоду с выключением сервера или сохранением только SSH при достижении порога.")"
    echo "$(localized_text "6 ZRAM / Swap：适合小内存 VPS。" "6 ZRAM / Swap: suitable for small memory VPS." "6 ZRAM / Swap: подходит для VPS с небольшой памятью.")"
    echo "$(localized_text "7 内核管理：安装、切换或清理内核；操作前确认快照和救援控制台可用。" "7 Kernel management: install, switch, or remove kernels. Confirm snapshot and rescue-console access first." "7 Управление ядрами: установка, смена и удаление ядер. Сначала проверьте доступ к снимку и аварийной консоли.")"
    echo "$(localized_text "8 BBR 直连/落地优化：按上传带宽和主要 RTT 计算缓冲区、连接队列与网卡积压参数。" "8 BBR direct/relay tuning: Size buffers, connection queues, and device backlog from upload bandwidth and primary RTT." "8 Настройка BBR для прямого/промежуточного сервера: рассчитать буферы, очереди соединений и сетевого устройства по отдаче и основному RTT.")"
    echo "$(localized_text "带宽、iperf3、国际互联和网络质量测试已移至主菜单 [12 测速与质量检测]。" "Bandwidth, iperf3, international connectivity, and network-quality tests are under main menu [12 Speed and quality tests]." "Тесты пропускной способности, iperf3, международной связи и качества сети находятся в пункте [12 Тесты скорости и качества] главного меню.")"
    echo "$(localized_text "? 查看帮助，0/q 返回主菜单。" "? View help, 0/q returns to the main menu." "? Просмотр справки, 0/q возвращает в главное меню.")"
}

show_health_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 诊断/健康检查 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Diagnosis/Health Check > Help${PLAIN}" "${CYAN}VPS-Optimize > Диагностика/Проверка состояния > Помощь${PLAIN}")"
    echo "$(localized_text "健康总览会检查关键服务、监听端口和证书摘要。" "The health overview checks critical services, listening ports, and certificate summaries." "Обзор работоспособности проверяет критические службы, порты прослушивания и сводку сертификатов.")"
    echo "$(localized_text "如果存在脚本添加的 connlimit 规则，也会显示持久化后端、运行时/保存文件一致性和重启风险提示。" "If there are connlimit rules added by the script, persistence backend, runtime/save file consistency, and restart risk tips will also be displayed." "Если скриптом добавлены правила connlimit, также будут отображаться советы по сохранению серверной части, согласованности файлов во время выполнения/сохранения и рискам перезапуска.")"
    echo "$(localized_text "健康总览会显示日志容量摘要；输入 p 可做配置、状态和日志文件权限体检，输入 P 可确认后修复。" "The health overview will display a summary of the log capacity; enter p to check the configuration, status and log file permissions, and enter P to confirm and repair." "В обзоре работоспособности будет отображена сводная информация о емкости журнала; введите p, чтобы проверить конфигурацию, состояние и права доступа к файлу журнала, и введите P для подтверждения и восстановления.")"
    echo "$(localized_text "输入 s 可进入服务恢复，支持重启常用/失败服务、清除失败状态和设置失败自动重启。" "Enter s to enter service recovery, which supports restarting common/failed services, clearing failure status and setting automatic restart on failure." "Введите s, чтобы войти в режим восстановления службы, который поддерживает перезапуск общих/сбойных служб, очистку состояния сбоя и настройку автоматического перезапуска при сбое.")"
    echo "$(localized_text "系统硬件探针会附带 443、Caddy、3x-ui、订阅工具和 Docker 场景概览。" "System hardware probes include 443, Caddy, 3x-ui, subscription tools, and Docker scenario overviews." "В комплект системных аппаратных зондов входят 443, Caddy, 3x-ui, инструменты подписки и обзоры сценариев Docker.")"
    echo "$(localized_text "生成反馈诊断信息用于提交 GitHub Issue，会尽量避免输出 Token、私钥和敏感密钥。" "Generate feedback diagnostic information for submitting GitHub Issue, and try to avoid outputting Token, private keys and sensitive keys." "Создайте диагностическую информацию обратной связи для отправки проблемы GitHub и постарайтесь избегать вывода токена, закрытых ключей и конфиденциальных ключей.")"
}

NET_KERNEL_MENU_ITEMS=(
    "1|BBR / 拥塞控制管理|调用 ylx2016 多内核调优脚本|func_bbr_manage|net_bbr"
    "2|动态 TCP 参数调优|粘贴 Omnitt 参数并自动校验|func_tcp_tune|net_tcp_tune"
    "3|DNS 设置|国内/国外/自定义，IPv4+IPv6|func_dns_optimize|"
    "4|网络接口管理|网卡/路由/DNS/MTU/DHCP|func_network_interface_manage|"
    "5|流量限额保护|流量统计 / 超额处置|func_traffic_guard_menu|"
    "6|ZRAM / Swap 内存调优|根据内存容量选择配置|func_zram_swap|"
    "7|内核管理|安装、切换或清理内核|func_kernel_manage|"
    "8|BBR 直连/落地优化|检测带宽与 RTT，动态生成 BBR/TCP 参数|func_bbr_direct_tune|net_bbr_direct"
)

NET_KERNEL_MENU_ITEMS_EN=(
    "1|BBR / congestion control|Run the ylx2016 multi-kernel tuning script|func_bbr_manage|net_bbr"
    "2|Dynamic TCP tuning|Paste and validate Omnitt parameters|func_tcp_tune|net_tcp_tune"
    "3|DNS optimization|China, overseas, or custom IPv4/IPv6 DNS|func_dns_optimize|"
    "4|Network interface manager|Interfaces, routes, DNS, MTU, and DHCP|func_network_interface_manage|"
    "5|Traffic quota protection|Prevent abuse and overage charges|func_traffic_guard_menu|"
    "6|ZRAM / Swap tuning|Tune memory compression by available RAM|func_zram_swap|"
    "7|Kernel management|Install, switch, or remove kernels|func_kernel_manage|"
    "8|BBR direct/relay tuning|Detect bandwidth and RTT; generate BBR/TCP parameters|func_bbr_direct_tune|net_bbr_direct"
)

NET_KERNEL_MENU_ITEMS_RU=(
    "1|BBR / контроль перегрузки|Запустить многовариантную настройку ядра ylx2016|func_bbr_manage|net_bbr"
    "2|Динамическая настройка TCP|Вставить и проверить параметры Omnitt|func_tcp_tune|net_tcp_tune"
    "3|Оптимизация DNS|DNS для Китая, зарубежных сетей или свои IPv4/IPv6|func_dns_optimize|"
    "4|Управление сетевыми интерфейсами|Интерфейсы, маршруты, DNS, MTU и DHCP|func_network_interface_manage|"
    "5|Защита лимита трафика|Предотвращение злоупотреблений и перерасхода|func_traffic_guard_menu|"
    "6|Настройка ZRAM / Swap|Сжатие памяти с учётом объёма ОЗУ|func_zram_swap|"
    "7|Управление ядрами|Установка, смена и удаление ядер|func_kernel_manage|"
    "8|Настройка BBR для прямого/промежуточного сервера|Определить скорость и RTT; создать параметры BBR/TCP|func_bbr_direct_tune|net_bbr_direct"
)

confirm_menu_risk() {
    local risk="$1"
    case "$risk" in
        net_bbr)
            confirm_risk_action "$(localized_text "BBR / 拥塞控制管理" "BBR / Congestion Control Management" "BBR / Управление контролем перегрузок")" \
                "$(localized_text "内核网络模块、拥塞控制和 TCP 参数" "Kernel Network Module, Congestion Control, and TCP Parameters" "Сетевой модуль ядра, контроль перегрузки и параметры TCP")" \
                "$(localized_text "从快照恢复，或重新进入本菜单切换回原配置" "Restore from a snapshot, or re-enter this menu to switch back to the original configuration" "Восстановите из моментального снимка или повторно войдите в это меню, чтобы вернуться к исходной конфигурации.")" \
                "$(localized_text "外部调优脚本可能安装/切换内核，请确认救援控制台可用。" "External tuning scripts may install/switch kernels, please confirm rescue console is available." "Внешние сценарии настройки могут устанавливать/переключать ядра. Убедитесь, что консоль восстановления доступна.")"
            ;;
        net_tcp_tune)
            confirm_risk_action "$(localized_text "动态 TCP 参数调优" "Dynamic TCP parameter tuning" "Динамическая настройка параметров TCP")" \
                "$(localized_text "sysctl TCP 参数和网络栈配置" "sysctl TCP parameters and network stack configuration" "sysctl TCP параметры и конфигурация сетевого стека")" \
                "$(localized_text "恢复 /etc/sysctl.d 中的备份配置，或手动回退参数" "Restore the backup configuration in /etc/sysctl.d, or manually roll back parameters" "Восстановите конфигурацию резервной копии в /etc/sysctl.d или откатите параметры вручную.")" \
                "$(localized_text "确认参数来源可信，错误参数可能影响网络连接。" "Confirm that the source of the parameters is trustworthy. Wrong parameters may affect the network connection." "Убедитесь, что источник параметров заслуживает доверия. Неправильные параметры могут повлиять на сетевое соединение.")"
            ;;
        net_bbr_direct)
            confirm_risk_action "$(localized_text "BBR 直连/落地优化" "BBR direct connection/relay-server tuning" "BBR прямое подключение/оптимизация площадки")" \
                "$(localized_text "BBR/FQ 拥塞控制及 TCP 缓冲区、连接队列参数" "BBR/FQ congestion control and TCP buffer and connection queue parameters" "Управление перегрузкой BBR/FQ и параметры буфера TCP и очереди подключений")" \
                "$(localized_text "恢复 /etc/sysctl.d/99-vps-optimize-bbr-direct.conf 的时间戳备份，并执行 sysctl --system" "Restore the timestamp backup of /etc/sysctl.d/99-vps-optimize-bbr-direct.conf and execute sysctl --system" "Восстановите резервную копию временной метки /etc/sysctl.d/99-vps-optimize-bbr-direct.conf и выполните sysctl --system.")" \
                "$(localized_text "保留当前 SSH 会话；脚本会在应用失败时自动恢复运行时参数和原配置。" "Preserve the current SSH session; the script will automatically restore runtime parameters and original configuration if the application fails." "Сохраните текущую сессию SSH; сценарий автоматически восстановит параметры времени выполнения и исходную конфигурацию в случае сбоя приложения.")"
            ;;
        net_kernel_install)
            confirm_risk_action "$(localized_text "安装/切换优化内核" "Install/switch optimized kernel" "Установить/переключить оптимизированное ядро")" \
                "$(localized_text "内核包、引导配置和 GRUB 菜单" "Kernel packages, boot configurations, and GRUB menus" "Пакеты ядра, конфигурации загрузки и меню GRUB")" \
                "$(localized_text "从云厂商控制台选择旧内核启动，或使用救援模式恢复" "Select the old kernel to boot from the cloud vendor console, or use rescue mode to restore" "Выберите старое ядро для загрузки из консоли поставщика облака или используйте режим восстановления для восстановления.")" \
                "$(localized_text "确认已创建快照，且当前 VPS 不是 OpenVZ 老系统。" "Confirm that a snapshot has been created and the current VPS is not the OpenVZ old system." "Убедитесь, что снимок создан и текущий VPS не является старой системой OpenVZ.")"
            ;;
        *) return 0 ;;
    esac
}


func_net_kernel_menu() {
    local menu_items_name="NET_KERNEL_MENU_ITEMS"
    case "$VPSO_LANGUAGE" in
        en) menu_items_name="NET_KERNEL_MENU_ITEMS_EN" ;;
        ru) menu_items_name="NET_KERNEL_MENU_ITEMS_RU" ;;
    esac
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "网络/内核优化" "Network/kernel optimization" "Оптимизация сети/ядра")"
        echo -e "$(localized_text "${BOLD}🚀 网络性能与内核管理${PLAIN}" "${BOLD}🚀 Network performance and kernel management${PLAIN}" "${BOLD}🚀 Производительность сети и управление ядром${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}调整网络栈、内存压缩和内核。安装或清理内核前，建议先创建系统快照。${PLAIN}" "${YELLOW}Tune the network stack, memory compression, and kernel. Create a system snapshot before installing or removing kernels.${PLAIN}" "${YELLOW}Настройка сети, сжатия памяти и ядра. Перед установкой или удалением ядер создайте снимок системы.${PLAIN}")"
        echo -e "------------------------------------------------"
        render_menu "$menu_items_name"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local nk_choice
        read_trimmed nk_choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case $nk_choice in
            "?") show_net_kernel_help; pause_return ;;
            0|q|Q) break ;;
            *) dispatch_menu_choice "$nk_choice" NET_KERNEL_MENU_ITEMS || { echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1; } ;;
        esac
    done
}

# ---------------------------------------------------------
# 24. 面板与节点部署菜单 (二级直达)
# ---------------------------------------------------------
func_panel_deploy_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "面板、节点与订阅工具" "Panels, Nodes and Subscription Tools" "Панели, узлы и инструменты подписки")"
        echo -e "$(localized_text "${BOLD}🛰️ 面板、节点与订阅工具${PLAIN}" "${BOLD}🛰️ Panels, nodes, and subscription tools${PLAIN}" "${BOLD}🛰️ Панели, узлы и инструменты подписки${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 面板 / 核心服务${PLAIN}" "${BOLD}▶ Panels / Core services${PLAIN}" "${BOLD}▶ Панели / основные службы${PLAIN}")"
        echo -e "$(localized_text "  ${BOLD}${GREEN}1.${PLAIN} ${BOLD}3x-ui 管理${PLAIN}          ${BOLD}${GREEN}2.${PLAIN} ${BOLD}x-ui 增强工具${PLAIN}      ${BOLD}${GREEN}3.${PLAIN} ${BOLD}面板 SSL 修复${PLAIN}" "${BOLD}${GREEN}1.${PLAIN} ${BOLD}3x-ui Management${PLAIN} ${BOLD}${GREEN}2.${PLAIN} ${BOLD}x-ui Tools${PLAIN} ${BOLD}${GREEN}3.${PLAIN} ${BOLD}Panel SSL Repair${PLAIN}" "${BOLD}${GREEN}1.${PLAIN} ${BOLD}Управление 3x-ui${PLAIN} ${BOLD}${GREEN}2.${PLAIN} ${BOLD}Инструменты x-ui${PLAIN} ${BOLD}${GREEN}3.${PLAIN} ${BOLD}Исправление SSL панели${PLAIN}")"
        echo -e "$(localized_text "  ${BOLD}${GREEN}4.${PLAIN} ${BOLD}S-UI 管理${PLAIN}           ${BOLD}${GREEN}5.${PLAIN} ${BOLD}Sing-box 管理${PLAIN}       ${BOLD}${GREEN}6.${PLAIN} ${BOLD}Xray 管理${PLAIN}" "${BOLD}${GREEN}4.${PLAIN} ${BOLD}S-UI Management${PLAIN} ${BOLD}${GREEN}5.${PLAIN} ${BOLD}Sing-box Management${PLAIN} ${BOLD}${GREEN}6.${PLAIN} ${BOLD}Xray Management${PLAIN}" "${BOLD}${GREEN}4.${PLAIN} ${BOLD}Управление S-UI${PLAIN} ${BOLD}${GREEN}5.${PLAIN} ${BOLD}Управление Sing-box${PLAIN} ${BOLD}${GREEN}6.${PLAIN} ${BOLD}Управление Xray${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 订阅 / 监控${PLAIN}" "${BOLD}▶ Subscription / Monitoring${PLAIN}" "${BOLD}▶ Подписки / Мониторинг${PLAIN}")"
        echo -e "$(localized_text "  ${BOLD}${GREEN}7.${PLAIN} ${BOLD}SublinkPro${PLAIN}            ${BOLD}${GREEN}8.${PLAIN} ${BOLD}妙妙屋订阅${PLAIN}          ${BOLD}${GREEN}9.${PLAIN} ${BOLD}Sub-Store${PLAIN}" "${BOLD}${GREEN}7.${PLAIN} ${BOLD}SublinkPro${PLAIN} ${BOLD}${GREEN}8.${PLAIN} ${BOLD}Miaomiaowu${PLAIN} ${BOLD}${GREEN}9.${PLAIN} ${BOLD}Sub-Store${PLAIN}" "${BOLD}${GREEN}7.${PLAIN} ${BOLD}SublinkPro${PLAIN} ${BOLD}${GREEN}8.${PLAIN} ${BOLD}Miaomiaowu${PLAIN} ${BOLD}${GREEN}9.${PLAIN} ${BOLD}Sub-Store${PLAIN}")"
        echo -e "$(localized_text " ${BOLD}${GREEN}10.${PLAIN} ${BOLD}Komari 监控${PLAIN}" "${BOLD}${GREEN}10.${PLAIN} ${BOLD}Komari monitoring${PLAIN}" "${BOLD}${GREEN}10.${PLAIN} ${BOLD}Мониторинг Komari${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 网络 / 监控${PLAIN}" "${BOLD}▶ Network / Monitoring${PLAIN}" "${BOLD}▶ Сеть / Мониторинг${PLAIN}")"
        echo -e "$(localized_text " ${BOLD}${GREEN}11.${PLAIN} ${BOLD}DNS 解锁${PLAIN}            ${BOLD}${GREEN}12.${PLAIN} ${BOLD}IP-Sentinel${PLAIN}         ${BOLD}${GREEN}13.${PLAIN} ${BOLD}端口流量监控（dog）${PLAIN}" "${BOLD}${GREEN}11.${PLAIN} ${BOLD}DNS Unlock${PLAIN} ${BOLD}${GREEN}12.${PLAIN} ${BOLD}IP-Sentinel${PLAIN} ${BOLD}${GREEN}13.${PLAIN} ${BOLD}Per-port traffic (dog)${PLAIN}" "${BOLD}${GREEN}11.${PLAIN} ${BOLD}Разблокировка DNS${PLAIN} ${BOLD}${GREEN}12.${PLAIN} ${BOLD}IP-Sentinel${PLAIN} ${BOLD}${GREEN}13.${PLAIN} ${BOLD}Трафик по портам (dog)${PLAIN}")"
        echo -e "$(localized_text " ${BOLD}${GREEN}14.${PLAIN} ${BOLD}Telegram VPS Bot${PLAIN}" "${BOLD}${GREEN}14.${PLAIN} ${BOLD}Telegram VPS Bot${PLAIN}" "${BOLD}${GREEN}14.${PLAIN} ${BOLD}Telegram VPS Bot${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local pd_choice
        read_trimmed pd_choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case $pd_choice in
            1) func_xpanel_menu ;;
            2) func_xui_custom_manager ;;
            3) func_rescue_panel ;;
            4) func_sui_menu ;;
            5) func_singbox_menu ;;
            6) func_xray_menu ;;
            7) func_sublinkpro_menu ;;
            8) func_miaomiaowu_menu ;;
            9) func_substore_menu ;;
            10) func_komari_menu ;;
            11) func_dns_unlock ;;
            12) func_ip_sentinel ;;
            13) func_port_dog ;;
            14) func_vps_bot_x ;;
            "?") show_panel_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_sni_stack_quick_menu() {
    local sni_title_column
    case "$VPSO_LANGUAGE" in
        en) sni_title_column=34 ;;
        ru) sni_title_column=39 ;;
        *) sni_title_column=27 ;;
    esac
    while true; do
        clear
        show_current_entry_summary
        echo -e "------------------------------------------------"
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "443端口复用管理中心" "Port 443 Reuse Manager" "Управление повторным использованием порта 443")"
        echo -e "$(localized_text "${BOLD}🧩 443端口复用管理中心${PLAIN}" "${BOLD}🧩 Port 443 Reuse Manager${PLAIN}" "${BOLD}🧩 Управление повторным использованием порта 443${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 入口模式${PLAIN}" "${BOLD}▶ Entry mode${PLAIN}" "${BOLD}▶ Режим входа${PLAIN}")"
        print_menu_item 1 "$(localized_text "入口状态" "Entry status" "Состояние входа")" "$(localized_text "公网 443 / Web / Xray / 服务" "public 443 / Web / Xray / services" "публичный 443 / Web / Xray / службы")" "$sni_title_column" "$GREEN" "$YELLOW" "$GREEN"
        print_menu_item 2 "$(localized_text "安装 / 切换入口模式" "Install or switch entry mode" "Установить или сменить режим")" "Nginx Stream / Xray Fallback / TCP Peek" "$sni_title_column" "$GREEN" "$YELLOW" "$GREEN"
        print_menu_item 6 "$(localized_text "重新应用当前模式" "Reapply current mode" "Повторно применить режим")" "$(localized_text "按现有参数重新生成" "regenerate from saved settings" "пересоздать из сохранённых параметров")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 7 "$(localized_text "回滚上次模式切换" "Roll back the last switch" "Откатить последнее переключение")" "$(localized_text "恢复切换前配置" "restore the previous configuration" "восстановить предыдущую конфигурацию")" "$sni_title_column" "$YELLOW" "$YELLOW" "$YELLOW"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ Web、订阅与证书${PLAIN}" "${BOLD}▶ Web, subscriptions, and certificates${PLAIN}" "${BOLD}▶ Web, подписки и сертификаты${PLAIN}")"
        print_menu_item 8 "$(localized_text "Web 域名与反向代理" "Web domains and reverse proxies" "Web-домены и обратный прокси")" "$(localized_text "新增 / 删除 / 查看" "add / remove / view" "добавить / удалить / просмотреть")" "$sni_title_column" "$GREEN" "$YELLOW" "$GREEN"
        print_menu_item 9 "$(localized_text "Web IP 白名单" "Web IP allowlist" "Список разрешённых IP для Web")" "$(localized_text "仅限制 Web 访问" "Web access only" "только доступ к Web")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 10 "$(localized_text "共享参数" "Shared settings" "Общие параметры")" "$(localized_text "面板 / 订阅 / REALITY / 端口 / 路径" "panel / subscription / REALITY / ports / paths" "панель / подписка / REALITY / порты / пути")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 11 "$(localized_text "订阅链接检查" "Subscription link check" "Проверка ссылок подписки")" "$(localized_text "公网 443 / External Proxy" "public 443 / External Proxy" "публичный 443 / External Proxy")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 12 "$(localized_text "证书维护" "Certificate maintenance" "Обслуживание сертификатов")" "$(localized_text "Cloudflare DNS / 重签 / 修复 / 回滚" "Cloudflare DNS / reissue / repair / rollback" "Cloudflare DNS / перевыпуск / исправление / откат")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 路由、安全与排查${PLAIN}" "${BOLD}▶ Routing, security, and diagnostics${PLAIN}" "${BOLD}▶ Маршруты, защита и диагностика${PLAIN}")"
        print_menu_item 13 "$(localized_text "443 配置检查" "Port 443 configuration check" "Проверка конфигурации 443")" "$(localized_text "入口 / 监听 / 证书 / Web / Xray" "entry / listeners / certificates / Web / Xray" "вход / слушатели / сертификаты / Web / Xray")" "$sni_title_column" "$GREEN" "$YELLOW" "$GREEN"
        print_menu_item 14 "$(localized_text "外网访问测试" "External access test" "Проверка внешнего доступа")" "DNS / TCP / TLS / $(localized_text "面板 / 订阅" "panel / subscription" "панель / подписка")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 15 "$(localized_text "Xray SNI 路由" "Xray SNI routes" "Маршруты Xray SNI")" "SNI -> $(localized_text "本地地址:端口" "local address:port" "локальный адрес:порт")" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 16 "$(localized_text "入口日志" "Entry logs" "Журналы входа")" "Nginx / Xray / vpso-mux" "$sni_title_column" "$CYAN" "$YELLOW" "$CYAN"
        print_menu_item 17 "REALITY $(localized_text "流量防护" "traffic protection" "защита трафика")" "$(localized_text "SNI 门禁 / 回落限速" "SNI gate / fallback rate limits" "контроль SNI / ограничение fallback")" "$sni_title_column" "$GREEN" "$YELLOW" "$GREEN"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local sni_choice
        read_trimmed sni_choice "$(localized_text "输入菜单编号，? 查看帮助: " "Menu number or ? for help: " "Номер пункта или ? для справки: ")"
        case "$sni_choice" in
            1) show_current_entry_status ;;
            2) manage_entry_mode_install_or_switch ;;
            6) reapply_current_entry_mode ;;
            7) rollback_last_entry_mode ;;
            8) manage_sni_stack_sites; continue ;;
            9) manage_sni_stack_ip_whitelist; continue ;;
            10) edit_sni_stack_runtime_profile; continue ;;
            11) check_sni_stack_subscription_hint ;;
            12) func_caddy_cf_maintenance_menu; continue ;;
            13) sni_stack_health_check_enhanced ;;
            14) func_443_network_test; continue ;;
            15) manage_xray_inbound_routes; continue ;;
            16) view_current_entry_logs ;;
            17) manage_reality_traffic_guard; continue ;;
            "?") show_sni_help; pause_return; continue ;;
            0) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择，请输入菜单编号或 ?。${PLAIN}" "${RED}❌ Invalid selection, please enter the menu number or ?.${PLAIN}" "${RED}❌ Неверный выбор, введите номер меню или ?.${PLAIN}")"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

# ---------------------------------------------------------
# 界面主循环 (新增 IP 防送中 & SublinkPro)
# ---------------------------------------------------------
normalize_main_choice() {
    local choice
    choice="$(trim_input "$1")"
    choice=$(printf '%s' "$choice" | LC_ALL=C tr '[:upper:]' '[:lower:]')

    case "$choice" in
        proxy) echo "4" ;;
        panel) echo "5" ;;
        ssh) echo "6" ;;
        firewall) echo "8" ;;
        bbr) echo "10" ;;
        docker) echo "11" ;;
        speed) echo "12" ;;
        health) echo "15" ;;
        backup) echo "16" ;;
        u|update|upd) echo "17" ;;
        443) echo "19" ;;
        lang) echo "20" ;;
        *) echo "$choice" ;;
    esac
}

main_menu() {
    create_shortcut
    while true; do
        clear
        if [[ "$VPSO_LANGUAGE" == "ru" ]]; then
            echo -e "${CYAN}================================================${PLAIN}"
            print_breadcrumb "Главное меню"
            echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (команда: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            print_auto_update_notice
            echo -e "${CYAN}================================================${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ① Рекомендуемый порядок для нового сервера${PLAIN}"
            print_menu_item 1 "Предварительная проверка" "порты, система, службы и возможные риски"
            print_menu_item 2 "Базовая настройка системы" "инструменты, часовой пояс, обновления, приоритет IPv4 и базовый BBR"
            print_menu_item 3 "Компоненты и службы" "Docker, Python, WARP и распространённые инструменты"
            print_menu_item 4 "Обратный прокси" "сайты и панели без повторного использования порта 443"
            print_menu_item 5 "Панели, узлы и подписки" "3x-ui, Sing-box, подписки и Komari"

            echo -e " ${BOLD}${BLUE}▶ ② Безопасность и контроль доступа${PLAIN}"
            print_menu_item 6 "Центр безопасности SSH" "порт, открытые ключи и вход только по ключу"
            print_menu_item 7 "Защита Fail2ban" "автоматическая блокировка перебора паролей SSH"
            print_menu_item 8 "Управление брандмауэром" "разрешение, удаление и просмотр правил, лимиты соединений"
            print_menu_item 9 "Системные настройки" "IPv6, приоритет IPv4, ping, имя хоста и очистка"

            echo -e " ${BOLD}${BLUE}▶ ③ Производительность сети и контейнеры${PLAIN}"
            print_menu_item 10 "Оптимизация сети и ядра" "BBR, TCP, ZRAM, DNS и облегчённые ядра"
            print_menu_item 11 "Безопасность Docker" "блокировка или восстановление внешнего доступа"

            echo -e " ${BOLD}${BLUE}▶ ④ Диагностика, резервное копирование и обслуживание${PLAIN}"
            print_menu_item 12 "Тест скорости и качества" "YABS, стриминг, маршруты и качество IP"
            print_menu_item 13 "Диагностика портов" "поиск слушающих процессов и принудительное завершение"
            print_menu_item 14 "Сведения о системе" "CPU, память, диски и сеть в реальном времени"
            print_menu_item 15 "Состояние служб" "службы, сертификаты и слушающие порты"
            print_menu_item 16 "Резервная копия и откат" "создание, просмотр, восстановление и очистка"
            print_menu_item 17 "Обновить скрипт" "проверка и установка последней версии" 28 "${BOLD}${YELLOW}" "$CYAN"
            echo -e " ${RED}18.${PLAIN} Перезагрузить сервер"
            echo -e ""
            echo -e " ${BOLD}${BLUE}▶ ⑤ Часто используемые функции${PLAIN}"
            print_menu_item 19 "Общий порт 443" "настройка, сайты, диагностика и сертификаты"
            print_menu_item 20 "Язык интерфейса" "中文 / English / Русский"
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e " ${RED} 0.${PLAIN} Выход / ${RED}q${PLAIN} Выход"
            echo -e "${CYAN}================================================${PLAIN}"
        elif [[ "$VPSO_LANGUAGE" == "en" ]]; then
            echo -e "${CYAN}================================================${PLAIN}"
            print_breadcrumb "Main menu"
            echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (shortcut: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            print_auto_update_notice
            echo -e "${CYAN}================================================${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ① Recommended setup for a new server${PLAIN}"
            print_menu_item 1 "Preflight and risk scan" "check ports, OS, and services before deployment"
            print_menu_item 2 "Base system initialization" "tools, timezone, updates, IPv4 preference, and basic BBR"
            print_menu_item 3 "Components and services" "Docker, Python, WARP, and common tools"
            print_menu_item 4 "Reverse proxy" "sites and panels not using Port 443 Reuse"
            print_menu_item 5 "Panels, nodes, subscriptions" "3x-ui, Sing-box, subscriptions, and Komari"

            echo -e " ${BOLD}${BLUE}▶ ② Security and access control${PLAIN}"
            print_menu_item 6 "SSH security center" "port, public keys, and key-only login modes"
            print_menu_item 7 "Fail2ban protection" "automatically block SSH brute-force IPs"
            print_menu_item 8 "Firewall rules" "allow, remove, inspect, disable, and limit connections"
            print_menu_item 9 "System switches and cleanup" "IPv6, IPv4 priority, ping, hostname, and cleanup"

            echo -e " ${BOLD}${BLUE}▶ ③ Network performance and containers${PLAIN}"
            print_menu_item 10 "Network and kernel tuning" "BBR, TCP, ZRAM, DNS, and lightweight kernels"
            print_menu_item 11 "Docker security management" "block or restore unintended external access"

            echo -e " ${BOLD}${BLUE}▶ ④ Diagnostics, backup, and maintenance${PLAIN}"
            print_menu_item 12 "Speed and quality tests" "YABS, streaming, routes, and IP quality"
            print_menu_item 13 "Inspect and release ports" "find listeners and terminate a process"
            print_menu_item 14 "System hardware probe" "live CPU, memory, disk, and network details"
            print_menu_item 15 "Service health overview" "services, certificates, and listening ports"
            print_menu_item 16 "Configuration backup" "back up, list, restore, and clean up"
            print_menu_item 17 "Update script" "check for and install the latest version" 28 "${BOLD}${YELLOW}" "$CYAN"
            echo -e " ${RED}18.${PLAIN} Reboot server"
            echo -e ""
            echo -e " ${BOLD}${BLUE}▶ ⑤ Frequently used${PLAIN}"
            print_menu_item 19 "Port 443 Reuse manager" "initialize, add sites, check health, and repair certificates"
            print_menu_item 20 "Interface language" "中文 / English / Русский"
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e " ${RED} 0.${PLAIN} Exit / ${RED}q${PLAIN} Exit"
            echo -e "${CYAN}================================================${PLAIN}"
        else
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "主菜单"
        echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        print_auto_update_notice
        echo -e "${CYAN}================================================${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ① 推荐流程：新机器先跑这里${PLAIN}"
        print_menu_item 1 "运维预检与风险扫描" "部署前先看端口/系统/服务状态"
        print_menu_item 2 "基础环境初始化" "工具/时区/系统更新/IPv4优先/基础 BBR"
        print_menu_item 3 "基础组件与常用服务" "Docker/Python/WARP/常用工具"
        print_menu_item 4 "反代（Caddy/Nginx）" "非443端口复用的网站与面板反代"
        print_menu_item 5 "面板、节点与订阅工具" "3x-ui/Sing-box/订阅管理/Komari"

        echo -e " ${BOLD}${BLUE}▶ ② 安全与访问控制${PLAIN}"
        print_menu_item 6 "SSH 安全中心" "端口/公钥/密钥登录模式"
        print_menu_item 7 "Fail2ban 防爆破" "自动封禁 SSH 爆破 IP"
        print_menu_item 8 "防火墙规则管理" "放行/删除/查看/关闭/连接数限制"
        print_menu_item 9 "系统开关与清理" "IPv6/IPv4优先/Ping/主机名/清理"

        echo -e " ${BOLD}${BLUE}▶ ③ 网络性能与容器${PLAIN}"
        print_menu_item 10 "网络与内核优化" "BBR/TCP/ZRAM/DNS/轻量内核"
        print_menu_item 11 "Docker 管理" "容器/镜像/网络/安全"

        echo -e " ${BOLD}${BLUE}▶ ④ 诊断、备份与维护${PLAIN}"
        print_menu_item 12 "测速与质量检测" "YABS/流媒体/回程/IP质量"
        print_menu_item 13 "端口排查与释放" "查看占用并结束进程"
        print_menu_item 14 "系统硬件探针" "CPU/内存/磁盘/网络实时信息"
        print_menu_item 15 "服务健康总览" "服务状态/证书摘要/端口概览"
        print_menu_item 16 "配置备份与回滚" "备份/列表/恢复/清理"
        print_menu_item 17 "更新脚本" "检查并安装最新版本" 28 "${BOLD}${YELLOW}" "$CYAN"
        echo -e " ${RED}18.${PLAIN} 重启服务器"
        echo -e ""
        echo -e " ${BOLD}${BLUE}▶ ⑤ 高频直达${PLAIN}"
        print_menu_item 19 "443端口复用管理中心" "初始化/加网站/体检/证书修复"
        print_menu_item 20 "界面语言" "中文 / English / Русский"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${RED} 0.${PLAIN} 退出面板 / ${RED}q${PLAIN} 退出"
        echo -e "${CYAN}================================================${PLAIN}"
        fi

        local choice
        read_trimmed choice "$(localized_text "输入菜单编号或 ?: " "Enter a menu number or ?: " "Введите номер пункта или ?: ")"
        choice=$(normalize_main_choice "$choice")

        case $choice in
            "?") show_main_help; echo ""; pause_return ;;
            20) select_ui_language; sleep 1 ;;
            1) func_preflight_check ;;
            2) func_base_init ;;
            3) func_env_install ;;
            4) func_caddy_reverse_proxy_menu ;;
            5) func_panel_deploy_menu ;;
            6) func_ssh_security_menu ;;
            7) func_fail2ban ;;
            8) func_firewall_manage ;;
            9) func_system_tweaks ;;
            10) func_net_kernel_menu ;;
            11) func_docker_manage ;;
            12) func_test_scripts ;;
            13) func_port_kill ;;
            14) func_system_info ;;
            15) func_health_dashboard ;;
            16) func_backup_center ;;
            17) func_update_script ;;
            18) func_reboot_server ;;
            19) func_sni_stack_quick_menu ;;
            0) exit 0 ;;
            *)
                localized_echo \
                    "${RED}❌ 无效输入，请输入菜单中存在的编号或 ?。${PLAIN}" \
                    "${RED}❌ Invalid input. Enter a displayed menu number or ?.${PLAIN}" \
                    "${RED}❌ Неверный ввод. Введите номер из меню или ?.${PLAIN}"
                sleep 1
                ;;
        esac
    done
}
