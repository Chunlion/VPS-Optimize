# shellcheck shell=bash
# Help text plus top-level and second-level menu wiring.

show_main_help() {
    if [[ "$VPSO_LANGUAGE" == "ru" ]]; then
        echo -e "${CYAN}VPS-Optimize > Главное меню > Справка${PLAIN}"
        echo "1/2 Проверка и первичная настройка нового сервера."
        echo "3   Установка Docker, Python, WARP и распространённых инструментов."
        echo "4   Настройка обратного прокси Caddy/Nginx для сайтов и панелей вне единого входа 443."
        echo "5   Управление 3x-ui, S-UI, Sing-box, Xray и инструментами подписок."
        echo "6   Управление портом SSH, открытыми ключами и входом только по ключу."
        echo "8   Управление правилами брандмауэра, открытыми портами и лимитами соединений для каждого IP-адреса."
        echo "10  Оптимизация сети и ядра: BBR, TCP, ZRAM и очистка старых ядер."
        echo "15  Обзор состояния служб и создание диагностических данных для поиска неисправностей."
        echo "16  Резервное копирование и откат конфигурации перед операциями с высоким риском."
        echo "19  Управление единым публичным входом 443 для панелей, подписок и REALITY."
        echo "20  Выбор языка интерфейса."
        echo "10 -> 5  Защита от превышения лимита трафика с учётом расчётного периода."
        echo "xcm открывает расширенный набор x-ui; он также доступен через 5 -> 2."
        echo "? показывает справку; 0/q завершает работу."
    elif [[ "$VPSO_LANGUAGE" == "en" ]]; then
        echo -e "${CYAN}VPS-Optimize > Main menu > Help${PLAIN}"
        echo "1/2 Check and initialize a new server."
        echo "3   Install Docker, Python, WARP, and common tools."
        echo "4   Configure Caddy/Nginx reverse proxies not using the shared 443 entry."
        echo "5   Manage 3x-ui, S-UI, Sing-box, Xray, and subscription tools."
        echo "6   Manage the SSH port, public keys, and key-only login modes."
        echo "8   Manage firewall rules, allowed ports, and per-source IP connection limits."
        echo "10  Tune networking and the kernel, including BBR, TCP, ZRAM, and kernel cleanup."
        echo "15  View health status and generate diagnostic details for troubleshooting."
        echo "16  Create backups and roll back configuration before high-risk operations."
        echo "19  Manage the shared public 443 entry for panels, subscriptions, and REALITY."
        echo "20  Select the interface language."
        echo "10 -> 5  Protect against traffic overages based on the billing cycle."
        echo "xcm opens the x-ui extension directly; it is also available through 5 -> 2."
        echo "? shows help; 0/q exits."
    else
        echo -e "${CYAN}VPS-Optimize > 主菜单 > 帮助${PLAIN}"
        echo "1/2 适合新机器先体检和初始化。"
        echo "3   基础组件与常用服务；安装 Docker、Python、WARP 和常用工具。"
        echo "4   反代（Caddy/Nginx）；适合未接入 443 单入口的网站/面板反代。"
        echo "5   管理 3x-ui、S-UI、Sing-box、Xray 和订阅工具。"
        echo "6   SSH 安全中心；管理端口、公钥和用户密钥登录模式。"
        echo "8   管理系统防火墙；支持端口放行、删除和每来源 IP 连接数限制。"
        echo "10  网络/内核优化；涉及 BBR、TCP、ZRAM 和内核清理。"
        echo "15  健康总览和反馈诊断信息，用于排错或提交 Issue。"
        echo "16  备份与回滚，高风险操作前建议先跑。"
        echo "19  443 单入口管理中心，面板/订阅/REALITY 共用公网 443。"
        echo "20  选择界面语言。"
        echo "10 -> 5  流量达量保护，按账单周期防刷流量和超额账单。"
        echo "xcm 直达 x-ui 增强套件；也可走 5 -> 2。"
        echo "? 查看帮助，0/q 退出。"
    fi
}

show_beginner_help() {
    if [[ "$VPSO_LANGUAGE" == "ru" ]]; then
        echo -e "${CYAN}VPS-Optimize > Руководство для начинающих > Справка${PLAIN}"
        echo "1 Первичная настройка сервера в безопасном порядке: проверка, базовая настройка, SSH, ключи, Fail2ban, брандмауэр и резервная копия."
        echo "2 Открыть меню панелей, узлов и инструментов подписок."
        echo "3 Открыть управление общим входом 443 для панелей, подписок и REALITY."
        echo "4 Проверить службы, порты и сертификаты или создать диагностические данные."
        echo "5 Создать резервную копию или восстановить существующую."
        echo "? показывает справку; 0/q возвращает в главное меню."
    elif [[ "$VPSO_LANGUAGE" == "en" ]]; then
        echo -e "${CYAN}VPS-Optimize > Beginner guide > Help${PLAIN}"
        echo "1 Initialize a new server in a safe order: preflight, base setup, SSH, keys, Fail2ban, firewall, and backup."
        echo "2 Open the panel, node, and subscription tools menu."
        echo "3 Open the shared 443 entry manager for panels, subscriptions, and REALITY."
        echo "4 Check services, ports, and certificates, or generate diagnostic details."
        echo "5 Create a backup or restore an existing backup."
        echo "? shows help; 0/q returns to the main menu."
    else
        echo -e "${CYAN}VPS-Optimize > 新手向导 > 帮助${PLAIN}"
        echo "1 新机器初始化：按安全顺序引导预检、初始化、SSH、公钥、Fail2ban、防火墙、备份。"
        echo "2 安装面板/节点：进入面板、节点与订阅工具菜单。"
        echo "3 配置 443 单入口：进入 443 管理中心，适合面板、订阅和 REALITY 共用 443。"
        echo "4 健康检查：查看服务、端口、证书，并可生成反馈诊断信息。"
        echo "5 备份/回滚：创建备份或从已有备份恢复。"
        echo "? 查看帮助，0/q 返回主菜单。"
    fi
}

show_panel_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 面板、节点与订阅工具 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Panels, Nodes and Subscription Tools > Help${PLAIN}" "${CYAN}VPS-Optimize > Панели, узлы и инструменты подписки > Справка${PLAIN}")"
    echo "$(localized_text "1 3x-ui：安装、官方菜单、面板修复。" "1 3x-ui: install, open the official menu, or repair the panel." "1 3x-ui: установка, официальное меню и восстановление панели.")"
    echo "$(localized_text "2 x-ui 增强：重置日期、校准流量、备份恢复、日志。" "2 x-ui extension: reset date, calibrate traffic, back up, restore, and view logs." "2 Расширение x-ui: сброс даты, калибровка трафика, резервное копирование, восстановление и журналы.")"
    echo "$(localized_text "3 面板 SSL 修复：443 接入前清空面板证书路径。" "3 Panel SSL repair: clear panel certificate paths before using shared port 443." "3 Исправление SSL панели: очистить пути сертификатов панели перед настройкой общего порта 443.")"
    echo "$(localized_text "4 S-UI：安装、官方菜单、卸载。" "4 S-UI: install, open the official menu, or uninstall." "4 S-UI: установка, официальное меню и удаление.")"
    echo "$(localized_text "5/6 Sing-box 与 Xray 脚本。" "5/6 Sing-box and Xray scripts." "5/6 Скрипты Sing-box и Xray.")"
    echo "$(localized_text "7/8/9 订阅栈，11 Dockge Compose，12 Compose 迁移；公网 HTTPS：未启用 443 单入口走主菜单 [4 反代]，已启用走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]。" "7/8/9: subscription stacks; 11: Dockge Compose; 12: Compose migration. For public HTTPS, use [4 Reverse proxy] before shared port 443; afterwards use [19 Shared port 443] -> [8 Manage Web domains/reverse proxy]." "7/8/9: стеки подписок; 11: Dockge Compose; 12: перенос Compose. Для публичного HTTPS до общего порта 443 используйте [4 Обратный прокси], после — [19 Общий порт 443] -> [8 Управление Web-доменами и обратным прокси].")"
    echo "$(localized_text "16 dog 流量计：仅统计已监控端口的实际流量。" "16 dog traffic monitor: shows traffic only for monitored ports." "16 Монитор трафика dog: показывает трафик только отслеживаемых портов.")"
    echo "$(localized_text "? 查看帮助，0/q 返回主菜单。" "? View help, 0/q returns to the main menu." "? Просмотр справки, 0/q возвращает в главное меню.")"
}

show_sni_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 443 单入口管理中心 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > 443 shared entry Management Center > Help${PLAIN}" "${CYAN}VPS-Optimize > 443 Центр управления общим входом > Справка${PLAIN}")"
    echo "$(localized_text "1 查看入口与监听：公网 443、Web 反代、Xray 和服务状态。" "1 View entry and listener status: public 443, Web proxy, Xray, and services." "1 Состояние входа и прослушивания: публичный 443, Web-прокси, Xray и службы.")"
    echo "$(localized_text "2 首次配置：Web 域名、反代引擎、证书和默认 Nginx Stream。" "2 Initial setup: Web domains, proxy engine, certificates, and default Nginx Stream." "2 Первоначальная настройка: Web-домены, обратный прокси, сертификаты и Nginx Stream по умолчанию.")"
    echo "$(localized_text "3/4/5 切换入口模式：Nginx Stream、Xray Fallback、TCP Peek + Splice。" "3/4/5 Switch entry mode: Nginx Stream, Xray Fallback, or TCP Peek + Splice." "3/4/5 Сменить режим входа: Nginx Stream, Xray Fallback или TCP Peek + Splice.")"
    echo "$(localized_text "6 重新应用：按当前 ENTRY_MODE 重新生成并启动入口配置。" "6 Reapply: regenerate and start the entry configuration for the current ENTRY_MODE." "6 Повторно применить: заново сформировать и запустить конфигурацию для текущего ENTRY_MODE.")"
    echo "$(localized_text "7 回滚：恢复上一次入口模式切换前的备份。" "7 Rollback: Restore the backup before the last entry mode switch." "7 Откат: восстановление резервной копии перед последним переключением режима входа.")"
    echo "$(localized_text "8 管理 Web 域名/反代：后续新增或删除网站，不需要重跑首次配置。" "8 Manage Web domains/reverse proxy: add or remove sites without rerunning the initial setup." "8 Управление Web-доменами и обратным прокси: добавляйте и удаляйте сайты без повторной первоначальной настройки.")"
    echo "$(localized_text "9 Web 域名 IP 白名单：只限制 Web 域名，不影响 Xray 节点。" "9 Web domain IP whitelist: only restricts Web domains and does not affect the Xray node." "9 Белый список IP-адресов имен веб-доменов: ограничивает только имена веб-доменов и не влияет на узел Xray.")"
    echo "$(localized_text "10 修改共享参数：面板、订阅、REALITY、入口端口和路径。" "10 Edit shared settings: panel, subscription, REALITY, entry ports, and paths." "10 Изменить общие параметры: панель, подписка, REALITY, порты входа и пути.")"
    echo "$(localized_text "11 订阅链接 / External Proxy：检查节点是否使用公网 443。" "11 Subscription link / External Proxy: verify that node links use public port 443." "11 Ссылка подписки / External Proxy: проверьте, используют ли ссылки узлов публичный порт 443.")"
    echo "$(localized_text "12 CF DNS / Caddy 证书维护：重签证书、修复软链接、清理和回滚。" "12 CF DNS / Caddy certificate maintenance: reissue certificates, repair symlinks, clean up, or roll back." "12 Обслуживание сертификатов CF DNS / Caddy: перевыпуск сертификатов, восстановление символьных ссылок, очистка и откат.")"
    echo "$(localized_text "13 链路体检：检查 ENTRY_MODE、监听、证书、Web 和 Xray 路由。" "13 Connection diagnostics: check ENTRY_MODE, listeners, certificates, Web, and Xray routing." "13 Диагностика соединения: ENTRY_MODE, прослушивание, сертификаты, Web и маршрутизация Xray.")"
    echo "$(localized_text "14 网络访问测试：检查 DNS、TCP、TLS SNI、面板和订阅响应。" "14 Network access test: check DNS, TCP, TLS SNI, panel, and subscription responses." "14 Проверка доступа: DNS, TCP, TLS SNI, ответы панели и подписки.")"
    echo "$(localized_text "15 Xray 入站管理：记录 SNI -> 本地地址:端口，不编辑 3x-ui/Xray 入站。" "15 Manage Xray routes: record SNI -> local address:port without editing 3x-ui/Xray inbounds." "15 Маршруты Xray: запись SNI -> локальный адрес:порт без изменения входящих подключений 3x-ui/Xray.")"
    echo "$(localized_text "16 TCP Peek + Splice 状态 / 8444 预检：查看 status.json；预检只监听 8444，不改公网 443。" "16 TCP Peek + Splice status / 8444 preflight: show status.json; listens only on 8444 and leaves public 443 unchanged." "16 Статус TCP Peek + Splice / проверка 8444: status.json; слушает только 8444 и не меняет публичный 443.")"
    echo "$(localized_text "17 TCP Peek 分流规则校验：只检查配置，不重启入口。" "17 TCP Peek routing-rule validation: check configuration only; do not restart the entry service." "17 Проверка правил маршрутизации TCP Peek: проверяет только конфигурацию и не перезапускает входной сервис.")"
    echo "$(localized_text "18 查看 TCP Peek + Splice 日志：查看 vpso-mux 分流器日志。" "18 TCP Peek + Splice logs: view the vpso-mux routing log." "18 Журналы TCP Peek + Splice: просмотр журнала маршрутизации vpso-mux.")"
    echo "$(localized_text "修改面板域名请走主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [9 修改面板域名]。" "To modify the panel domain, please go to the main menu [19 443 shared entry Management Center] -> [8 Manage Web domain/Reverse Proxy] -> [9 Modify Panel domain]." "Чтобы изменить имя домена панели, перейдите в главное меню [19 443 центр управления общей точкой входа] -> [8 Управление именем веб-домена/обратным прокси] -> [9 Изменить имя домена панели].")"
    echo "$(localized_text "未接入 443 单入口时，用主菜单 [4 反代] -> [5] 管理 Caddy/Nginx 域名 IP 白名单。" "When the 443 shared entry is not connected, use the main menu [4 reverse proxy] -> [5] to manage the Caddy/Nginx domain IP whitelist." "Если общий вход 443 не подключен, используйте главное меню [4 обратный прокси] -> [5] для управления белым списком IP-адресов доменного имени Caddy/Nginx.")"
    echo "$(localized_text "? 查看帮助，0/q 返回主菜单。" "? View help, 0/q returns to the main menu." "? Просмотр справки, 0/q возвращает в главное меню.")"
}

show_backup_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 备份与回滚 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Backup and Rollback > Help${PLAIN}" "${CYAN}VPS-Optimize > Резервное копирование и откат > Справка${PLAIN}")"
    echo "$(localized_text "1 创建备份：高风险操作前先用。" "1 Create a backup: Use it before high-risk operations." "1 Создайте резервную копию. Используйте ее перед операциями с высоким риском.")"
    echo "$(localized_text "2 查看备份：确认可用备份和时间。" "2 View backups: Confirm available backups and times." "2 Просмотр резервных копий: подтвердите доступные резервные копии и время.")"
    echo "$(localized_text "3 回滚：覆盖当前配置，输入 yes 确认（不区分大小写）。" "3 Rollback: overwrites current configuration. Confirm with yes (case-insensitive)." "3 Откат: перезаписывает текущую конфигурацию. Подтвердите вводом yes в любом регистре.")"
    echo "$(localized_text "4 隔离旧备份：移入隔离目录，不直接删除。" "4 Quarantine old backups: move them to quarantine; do not delete them." "4 Изолировать старые копии: переместить в карантин, не удалять.")"
    echo "$(localized_text "5 查看/编辑已应用配置：先备份，校验后可 reload/restart。" "5 View or edit applied configuration: back up first, validate, then reload or restart if needed." "5 Просмотр или правка применённой конфигурации: сначала копия, затем проверка и reload/restart при необходимости.")"
    echo "$(localized_text "? 查看帮助，0/q 返回主菜单。" "? View help, 0/q returns to the main menu." "? Просмотр справки, 0/q возвращает в главное меню.")"
}

show_net_kernel_help() {
    echo -e "$(localized_text "${CYAN}VPS-Optimize > 网络/内核优化 > 帮助${PLAIN}" "${CYAN}VPS-Optimize > Network/Kernel Optimization > Help${PLAIN}" "${CYAN}VPS-Optimize > Оптимизация сети/ядра > Справка${PLAIN}")"
    echo "$(localized_text "1 BBR / 拥塞控制：调用外部调优脚本，执行前建议备份。" "1 BBR / Congestion control: Call an external tuning script, and it is recommended to back it up before execution." "1 BBR / Контроль перегрузки: вызовите внешний сценарий настройки, и перед выполнением рекомендуется создать его резервную копию.")"
    echo "$(localized_text "2 TCP 参数：修改 sysctl，适合有明确参数需求的用户。" "2 TCP parameters: Modify sysctl, suitable for users with clear parameter requirements." "2 параметра TCP: Измените sysctl, подходит для пользователей с четкими требованиями к параметрам.")"
    echo "$(localized_text "3 DNS 更改优化：国内/国外默认 DNS，也支持自定义 IPv4 和 IPv6。" "3 DNS change optimization: domestic/foreign default DNS, also supports customized IPv4 and IPv6." "3 Оптимизация изменений DNS: внутренний/зарубежный DNS по умолчанию, также поддерживает настроенные IPv4 и IPv6.")"
    echo "$(localized_text "4 网卡管理工具：查看网卡、路由、DNS，临时调整 MTU 或刷新 DHCP。" "4 Network card management tool: View network card, routing, DNS, temporarily adjust MTU or refresh DHCP." "4 Инструмент управления сетевой картой: просмотр сетевой карты, маршрутизации, DNS, временная настройка MTU или обновление DHCP.")"
    echo "$(localized_text "5 流量达量保护：按网卡流量和账单周期自动关机或仅保留 SSH，防止超额账单。" "5 Traffic volume protection: Automatically shut down or only retain SSH according to network card traffic and billing cycle to prevent excessive bills." "5 Защита объема трафика: автоматическое отключение или сохранение SSH в зависимости от трафика сетевой карты и цикла выставления счетов, чтобы предотвратить чрезмерные счета.")"
    echo "$(localized_text "6 ZRAM / Swap：适合小内存 VPS。" "6 ZRAM / Swap: suitable for small memory VPS." "6 ZRAM / Swap: подходит для VPS с небольшой памятью.")"
    echo "$(localized_text "7 安装/切换内核：高风险，必须确认快照和救援控制台可用。" "7 Install/switch kernel: High risk, must confirm snapshot and rescue console are available." "7. Установка/переключение ядра: высокий риск, необходимо подтвердить доступность моментального снимка и консоли восстановления.")"
    echo "$(localized_text "8 清理旧内核：不要删除当前内核和云厂商定制内核。" "8 Clean up old kernels: Do not delete the current kernel and cloud vendor-customized kernels." "8. Очистите старые ядра. Не удаляйте текущее ядро и ядра, настроенные поставщиком облака.")"
    echo "$(localized_text "9 BBR 直连/落地优化：按上传带宽和主要 RTT 场景计算 TCP 缓冲区，并安全应用独立配置。" "9 BBR direct connection/relay-server tuning: Calculate the TCP buffer according to upload bandwidth and main RTT scenarios, and apply independent configuration safely." "9 BBR оптимизация прямого соединения/посадки: рассчитайте буфер TCP в соответствии с полосой пропускания загрузки и основными сценариями RTT и безопасно примените независимую конфигурацию.")"
    echo "$(localized_text "10 服务器带宽测试：调用已安装的 Ookla speedtest，或安装发行版提供的 speedtest-cli。" "10 Server bandwidth test: Call the installed Ookla speedtest, or install the speedtest-cli provided by the distribution." "10 Тест пропускной способности сервера: вызовите установленный Speedtest Ookla или установите Speedtest-cli, входящий в дистрибутив.")"
    echo "$(localized_text "11 iperf3 单线程测试：连接你自己的 iperf3 服务端，固定使用 1 条并行流。" "11 iperf3 single-thread test: connect your own iperf3 server and use 1 parallel stream." "11 Однопоточный тест iperf3: подключите собственный сервер iperf3 и используйте 1 параллельный поток.")"
    echo "$(localized_text "12 国际互联速度测试：调用 network-latency-tester；执行前会显示来源并确认。" "12 International Internet speed test: call network-latency-tester; the source will be displayed and confirmed before execution." "12. Международный тест скорости Интернета: позвоните в тестер задержки сети; источник будет отображен и подтвержден перед выполнением.")"
    echo "$(localized_text "13 网络延迟质量检测：调用 Check.Place 网络质量检测；执行前会显示来源并确认。" "13 Network delay quality detection: Call Check.Place network quality detection; the source will be displayed and confirmed before execution." "13 Обнаружение качества задержки сети: Проверка вызова. Обнаружение качества сети; источник будет отображен и подтвержден перед выполнением.")"
    echo "$(localized_text "三网回程路由测试已在主菜单 [12 测速与质量检测] 中提供，不重复添加。" "The three-network backhaul routing test has been provided in the main menu [12 Speed Test and Quality Test] and will not be added repeatedly." "Тест маршрутизации транзитной сети с тремя сетями представлен в главном меню [12 Тест скорости и тест качества] и не будет добавляться повторно.")"
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
    "3|DNS 更改优化|国内/国外/自定义，IPv4+IPv6|func_dns_optimize|"
    "4|网卡管理工具|网卡/路由/DNS/MTU/DHCP|func_network_interface_manage|"
    "5|流量达量保护|防刷流量 / 防超额账单|func_traffic_guard_menu|"
    "6|ZRAM / Swap 内存调优|按内存分档优化小鸡|func_zram_swap|"
    "7|安装/切换优化内核|Cloud/KVM 稳定推荐 / XanMod 高级可选|func_install_kernel|net_kernel_install"
    "8|清理旧内核|释放磁盘空间，谨慎操作|func_clean_kernel|"
    "9|BBR 直连/落地优化|智能带宽检测，按主要 RTT 调整缓冲区|func_bbr_direct_tune|net_bbr_direct"
    "10|服务器带宽测试|Speedtest 上下行带宽与延迟|func_server_bandwidth_test|"
    "11|iperf3 单线程测试|自定义服务端、方向、端口和时长|func_iperf3_single_thread_test|"
    "12|国际互联速度测试|多地区网络互联质量测试|func_international_speed_test|"
    "13|网络延迟质量检测|三网延迟、连通性与网络质量|func_network_latency_quality_test|"
)

NET_KERNEL_MENU_ITEMS_EN=(
    "1|BBR / congestion control|Run the ylx2016 multi-kernel tuning script|func_bbr_manage|net_bbr"
    "2|Dynamic TCP tuning|Paste and validate Omnitt parameters|func_tcp_tune|net_tcp_tune"
    "3|DNS optimization|China, overseas, or custom IPv4/IPv6 DNS|func_dns_optimize|"
    "4|Network interface manager|Interfaces, routes, DNS, MTU, and DHCP|func_network_interface_manage|"
    "5|Traffic quota protection|Prevent abuse and overage charges|func_traffic_guard_menu|"
    "6|ZRAM / Swap tuning|Tune memory compression by available RAM|func_zram_swap|"
    "7|Install or switch kernel|Stable Cloud/KVM option or advanced XanMod option|func_install_kernel|net_kernel_install"
    "8|Remove old kernels|Free disk space with safety checks|func_clean_kernel|"
    "9|BBR direct/relay tuning|Size buffers from bandwidth and primary RTT|func_bbr_direct_tune|net_bbr_direct"
    "10|Server bandwidth test|Speedtest upload, download, and latency|func_server_bandwidth_test|"
    "11|iperf3 single-stream test|Custom server, direction, port, and duration|func_iperf3_single_thread_test|"
    "12|International speed test|Test connectivity across multiple regions|func_international_speed_test|"
    "13|Network latency and quality|Carrier latency, reachability, and network quality|func_network_latency_quality_test|"
)

NET_KERNEL_MENU_ITEMS_RU=(
    "1|BBR / контроль перегрузки|Запустить многовариантную настройку ядра ylx2016|func_bbr_manage|net_bbr"
    "2|Динамическая настройка TCP|Вставить и проверить параметры Omnitt|func_tcp_tune|net_tcp_tune"
    "3|Оптимизация DNS|DNS для Китая, зарубежных сетей или свои IPv4/IPv6|func_dns_optimize|"
    "4|Управление сетевыми интерфейсами|Интерфейсы, маршруты, DNS, MTU и DHCP|func_network_interface_manage|"
    "5|Защита лимита трафика|Предотвращение злоупотреблений и перерасхода|func_traffic_guard_menu|"
    "6|Настройка ZRAM / Swap|Сжатие памяти с учётом объёма ОЗУ|func_zram_swap|"
    "7|Установка или смена ядра|Стабильное ядро Cloud/KVM или расширенный вариант XanMod|func_install_kernel|net_kernel_install"
    "8|Удаление старых ядер|Безопасное освобождение места на диске|func_clean_kernel|"
    "9|Настройка BBR для прямого/промежуточного сервера|Буферы по пропускной способности и основному RTT|func_bbr_direct_tune|net_bbr_direct"
    "10|Тест пропускной способности|Скорость загрузки, отдачи и задержка Speedtest|func_server_bandwidth_test|"
    "11|Однопоточный тест iperf3|Свой сервер, направление, порт и длительность|func_iperf3_single_thread_test|"
    "12|Международный тест скорости|Проверка связи с несколькими регионами|func_international_speed_test|"
    "13|Задержка и качество сети|Задержка операторов, доступность и качество сети|func_network_latency_quality_test|"
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
        echo -e "$(localized_text "${YELLOW}用途：调整网络栈、内存压缩和内核；涉及内核安装/清理前建议先做快照。${PLAIN}" "${YELLOW}Purpose: Adjust network stack, memory compression and kernel; it is recommended to take a snapshot before kernel installation/cleaning.${PLAIN}" "${YELLOW}Назначение: Настройка сетевого стека, сжатия памяти и ядра; рекомендуется сделать снимок перед установкой/очисткой ядра.${PLAIN}")"
        echo -e "------------------------------------------------"
        render_menu "$menu_items_name"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Return to the main menu / q Return to the previous level${PLAIN}" "${RED}0. Возврат в главное меню / q Возврат на предыдущий уровень${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local nk_choice
        read_trimmed nk_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
        case $nk_choice in
            "?"|help) show_net_kernel_help; pause_return ;;
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
        echo -e "$(localized_text "${BOLD}🛰️ 面板、节点与订阅工具部署${PLAIN}" "${BOLD}🛰️ Panel, node and subscription tool deployment${PLAIN}" "${BOLD}🛰️ Развертывание панели, узла и инструмента подписки${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 面板 / 核心${PLAIN}" "${BOLD}▶ Panel / Core${PLAIN}" "${BOLD}▶ Панель/ядро${PLAIN}")"
        echo -e "$(localized_text "  ${BOLD}${GREEN}1.${PLAIN} ${BOLD}3x-ui 面板脚本${PLAIN}     ${BOLD}${GREEN}2.${PLAIN} ${BOLD}x-ui 增强套件${PLAIN}      ${BOLD}${GREEN}3.${PLAIN} ${BOLD}面板 SSL 修复${PLAIN}" "${BOLD}${GREEN}1.${PLAIN} ${BOLD}3x-ui Panel script${PLAIN} ${BOLD}${GREEN}2.${PLAIN} ${BOLD}X-ui Enhancement Kit${PLAIN} ${BOLD}${GREEN}3.${PLAIN} ${BOLD}Panel SSL Repair${PLAIN}" "${BOLD}${GREEN}1.${PLAIN} ${BOLD}3x-ui Сценарий панели${PLAIN} ${BOLD}${GREEN}2.${PLAIN} ${BOLD}x-ui Комплект расширения${PLAIN} ${BOLD}${GREEN}3.${PLAIN} ${BOLD}Панель SSL Ремонт${PLAIN}")"
        echo -e "$(localized_text "  ${BOLD}${GREEN}4.${PLAIN} ${BOLD}S-UI 面板脚本${PLAIN}      ${BOLD}${GREEN}5.${PLAIN} ${BOLD}Sing-box 脚本${PLAIN}      ${BOLD}${GREEN}6.${PLAIN} ${BOLD}Xray 脚本${PLAIN}" "${BOLD}${GREEN}4.${PLAIN} ${BOLD}S-UI Panel script${PLAIN} ${BOLD}${GREEN}5.${PLAIN} ${BOLD}Sing-box Script${PLAIN} ${BOLD}${GREEN}6.${PLAIN} ${BOLD}Xray Script${PLAIN}" "${BOLD}${GREEN}4.${PLAIN} ${BOLD}S-UI Скрипт панели${PLAIN} ${BOLD}${GREEN}5.${PLAIN} ${BOLD}Sing-box Скрипт${PLAIN} ${BOLD}${GREEN}6.${PLAIN} ${BOLD}Xray Скрипт${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 订阅 / Compose${PLAIN}" "${BOLD}▶ Subscribe / Compose${PLAIN}" "${BOLD}▶ Подписаться / Compose${PLAIN}")"
        echo -e "$(localized_text "  ${BOLD}${GREEN}7.${PLAIN} ${BOLD}SublinkPro 订阅栈${PLAIN}  ${BOLD}${GREEN}8.${PLAIN} ${BOLD}妙妙屋订阅栈${PLAIN}       ${BOLD}${GREEN}9.${PLAIN} ${BOLD}Sub-Store 订阅栈${PLAIN}" "${BOLD}${GREEN}7.${PLAIN} ${BOLD}SublinkPro subscription stack${PLAIN} ${BOLD}${GREEN}8.${PLAIN} ${BOLD}Miaomiaowu subscription stack${PLAIN} ${BOLD}${GREEN}9.${PLAIN} ${BOLD}Sub-Store Subscription Stack${PLAIN}" "${BOLD}${GREEN}7.${PLAIN} ${BOLD}SublinkPro стек подписки${PLAIN} ${BOLD}${GREEN}8.${PLAIN} ${BOLD}Подписка на Miaomiaowu stack${PLAIN} ${BOLD}${GREEN}9.${PLAIN} ${BOLD}Стек подписки подмагазина${PLAIN}")"
        echo -e "$(localized_text " ${BOLD}${YELLOW}10.${PLAIN} ${BOLD}订阅栈更新${PLAIN}        ${BOLD}${GREEN}11.${PLAIN} ${BOLD}Dockge Compose${PLAIN}    ${BOLD}${GREEN}12.${PLAIN} ${BOLD}Compose 迁移${PLAIN}" "${BOLD}${YELLOW}10.${PLAIN} ${BOLD}Subscription stack update${PLAIN} ${BOLD}${GREEN}11.${PLAIN} ${BOLD}Dockge Compose${PLAIN} ${BOLD}${GREEN}12.${PLAIN} ${BOLD}Compose Migrate${PLAIN}" "${BOLD}${YELLOW}10.${PLAIN} ${BOLD}Обновление стека подписки${PLAIN} ${BOLD}${GREEN}11.${PLAIN} ${BOLD}Dockge Compose${PLAIN} ${BOLD}${GREEN}12.${PLAIN} ${BOLD}Compose Миграция${PLAIN}")"
        echo -e "$(localized_text " ${BOLD}${GREEN}13.${PLAIN} ${BOLD}Komari 探针面板${PLAIN}" "${BOLD}${GREEN}13.${PLAIN} ${BOLD}Komari probe panel${PLAIN}" "${BOLD}${GREEN}13.${PLAIN} ${BOLD}Панель датчика Комари${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 工具 / 辅助${PLAIN}" "${BOLD}▶ Tools / Auxiliary${PLAIN}" "${BOLD}▶ Инструменты/Вспомогательные${PLAIN}")"
        echo -e "$(localized_text " ${BOLD}${GREEN}14.${PLAIN} ${BOLD}DNS 解锁脚本${PLAIN}      ${BOLD}${GREEN}15.${PLAIN} ${BOLD}IP-Sentinel 脚本${PLAIN}  ${BOLD}${GREEN}16.${PLAIN} ${BOLD}dog 流量计${PLAIN}" "${BOLD}${GREEN}14.${PLAIN} ${BOLD}DNS Unlock script${PLAIN} ${BOLD}${GREEN}15.${PLAIN} ${BOLD}IP-Sentinel Script${PLAIN} ${BOLD}${GREEN}16.${PLAIN} ${BOLD}Dog Flowmeter${PLAIN}" "${BOLD}${GREEN}14.${PLAIN} ${BOLD}DNS Скрипт разблокировки${PLAIN} ${BOLD}${GREEN}15.${PLAIN} ${BOLD}IP-Скрипт Sentinel${PLAIN} ${BOLD}${GREEN}16.${PLAIN} ${BOLD}dog Расходомер${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Return to the main menu / q Return to the previous level${PLAIN}" "${RED}0. Возврат в главное меню / q Возврат на предыдущий уровень${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local pd_choice
        read_trimmed pd_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"
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
            10) func_update_subscription_tools ;;
            11) func_dockge_menu ;;
            12) func_migrate_compose_to_dockge ;;
            13) func_komari_menu ;;
            14) func_dns_unlock ;;
            15) func_ip_sentinel ;;
            16) func_port_dog ;;
            xcm|XCM|xui-custom|外置|外置增强|外置管理) func_xui_custom_manager ;;
            "?"|help) show_panel_help; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_sni_stack_quick_menu() {
    while true; do
        clear
        show_current_entry_summary
        echo -e "------------------------------------------------"
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "443 单入口管理中心" "Shared 443 Entry Manager" "Управление общей точкой входа 443")"
        echo -e "$(localized_text "${BOLD}🧩 443 单入口管理中心${PLAIN}" "${BOLD}🧩 Shared 443 Entry Manager${PLAIN}" "${BOLD}🧩 Управление общей точкой входа 443${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：统一管理公网 443 的入口模式、Web 域名、Xray 入站分流和链路体检。${PLAIN}" "${YELLOW}Manage the public port 443 entry mode, Web domains, Xray inbound routes, and connection health checks.${PLAIN}" "${YELLOW}Управление режимом публичного порта 443, веб-доменами, маршрутами входящих подключений Xray и проверкой соединений.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}首次部署先选 [2]；已有配置后用 [3]/[4]/[5] 在三种入口模式间切换。${PLAIN}" "${YELLOW}When deploying for the first time, select [2] first; after configuration, use [3]/[4]/[5] to switch between the three entry modes.${PLAIN}" "${YELLOW}При первом развертывании сначала выберите [2]; после настройки используйте [3]/[4]/[5] для переключения между тремя режимами входа.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 当前状态与入口模式${PLAIN}" "${BOLD}▶ Current status and entry mode${PLAIN}" "${BOLD}▶ Текущее состояние и режим входа${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  1. 查看当前入口状态 / 监听详情${PLAIN} ${YELLOW}(公网 443、Web 反代、Xray、服务状态)${PLAIN}" "${GREEN}1. View entry status and listeners (public port 443, Web proxy, Xray, and services)${PLAIN}" "${GREEN}1. Состояние входа и прослушивания (публичный порт 443, веб-прокси, Xray и службы)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 首次配置 / 安装 443 单入口${PLAIN} ${YELLOW}(默认 Nginx Stream 模式，第一次部署用)${PLAIN}" "${GREEN}2. Set up the shared 443 entry (Nginx Stream by default; use for initial deployment)${PLAIN}" "${GREEN}2. Настроить общую точку входа 443 (по умолчанию Nginx Stream; для первого развёртывания)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 切换到 Nginx Stream 模式${PLAIN}  ${YELLOW}(默认稳定模式)${PLAIN}" "${GREEN}3. Switch to Nginx Stream mode (default stable mode)${PLAIN}" "${GREEN}3. Переключиться в режим Nginx Stream (стабильный режим по умолчанию)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 切换到 Xray Fallback 模式${PLAIN} ${YELLOW}(需已有 Xray/3x-ui 主入站)${PLAIN}" "${GREEN}4. Switch to Xray Fallback mode (requires an existing Xray/3x-ui main inbound)${PLAIN}" "${GREEN}4. Переключиться в режим Xray Fallback (требуется основное входящее подключение Xray/3x-ui)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 切换到 TCP Peek + Splice 模式${PLAIN} ${YELLOW}(需先完成 8444 预检，切换时不自动编译)${PLAIN}" "${GREEN}5. Switch to TCP Peek + Splice (complete the 8444 preflight first; switching does not build automatically)${PLAIN}" "${GREEN}5. Переключиться в TCP Peek + Splice (сначала выполните проверку на 8444; сборка при переключении не запускается)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  6. 重新应用当前入口模式${PLAIN}" "${CYAN}6. Reapply the current entry mode${PLAIN}" "${CYAN}6. Повторно применить текущий режим входа${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}  7. 回滚上一次入口模式切换${PLAIN}" "${YELLOW}7. Roll back the last entry mode switch${PLAIN}" "${YELLOW}7. Откатить последнее переключение режима входа${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 共享配置与体检${PLAIN}" "${BOLD}▶ Shared configuration and health check${PLAIN}" "${BOLD}▶ Общая конфигурация и проверка состояния${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  8. 管理 Web 域名/反代${PLAIN}        ${YELLOW}(新增/删除/查看网站，最常用)${PLAIN}" "${GREEN}8. Manage Web domains and reverse proxies (add, delete, or view sites)${PLAIN}" "${GREEN}8. Управление веб-доменами и обратным прокси (добавить, удалить или просмотреть сайт)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  9. 管理 Web 域名 IP 白名单${PLAIN}   ${YELLOW}(只限制 Web 域名)${PLAIN}" "${CYAN}9. Manage the Web-domain IP whitelist (applies only to Web domains)${PLAIN}" "${CYAN}9. Белый список IP-адресов веб-доменов (только для веб-доменов)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 10. 修改 443 共享参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}" "${CYAN}10. Change shared 443 settings (panel, subscription, REALITY, entry port, and paths)${PLAIN}" "${CYAN}10. Изменить общие параметры 443 (панель, подписка, REALITY, входной порт и пути)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 11. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}" "${CYAN}11. Subscription link / External Proxy guidance (check whether node links use public port 443)${PLAIN}" "${CYAN}11. Подсказки для ссылок подписки / External Proxy (проверка публичного порта 443 в ссылках узлов)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 12. CF DNS / Caddy 证书维护${PLAIN}   ${YELLOW}(重签/软链/清理/修复/回滚)${PLAIN}" "${CYAN}12. CF DNS / Caddy certificate maintenance (renew, symlink, clean, repair, or roll back)${PLAIN}" "${CYAN}12. Обслуживание сертификатов CF DNS / Caddy (перевыпуск, ссылки, очистка, восстановление, откат)${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 13. 443 链路体检${PLAIN}              ${YELLOW}(ENTRY_MODE/监听/证书/Web/Xray 分流)${PLAIN}" "${GREEN}13. Port 443 connection health check (ENTRY_MODE, listeners, certificates, Web, and Xray routes)${PLAIN}" "${GREEN}13. Проверка соединений порта 443 (ENTRY_MODE, прослушивание, сертификаты, Web и маршруты Xray)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 14. 443 网络访问测试${PLAIN}          ${YELLOW}(DNS/TCP/TLS/面板/订阅路径)${PLAIN}" "${CYAN}14. 443 Network access test (DNS/TCP/TLS/panel/subscription path)${PLAIN}" "${CYAN}14. 443 Проверка доступа к сети (DNS/TCP/TLS/панель/путь подписки)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 15. Xray 入站管理${PLAIN}             ${YELLOW}(SNI -> 本地地址:端口 分流记录)${PLAIN}" "${CYAN}15. Manage Xray inbounds (SNI -> local address:port routes)${PLAIN}" "${CYAN}15. Управление входящими подключениями Xray (SNI -> локальный адрес:порт)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 16. 查看 TCP Peek + Splice 状态 / 8444 预检${PLAIN} ${YELLOW}(不改公网 443)${PLAIN}" "${CYAN}16. View TCP Peek + Splice status / run the 8444 preflight (does not change public port 443)${PLAIN}" "${CYAN}16. Состояние TCP Peek + Splice / проверка на 8444 (публичный порт 443 не изменяется)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 17. TCP Peek 分流规则校验${PLAIN} ${YELLOW}(只检查配置，不重启入口)${PLAIN}" "${CYAN}17. Validate TCP Peek routing rules (checks configuration without restarting the entry)${PLAIN}" "${CYAN}17. Проверить маршруты TCP Peek (только конфигурация, без перезапуска входа)${PLAIN}")"
        echo -e "$(localized_text "${CYAN} 18. 查看 TCP Peek + Splice 日志${PLAIN} ${YELLOW}(vpso-mux 分流器日志)${PLAIN}" "${CYAN}18. View TCP Peek + Splice logs (vpso-mux routing logs)${PLAIN}" "${CYAN}18. Журналы TCP Peek + Splice (маршрутизация vpso-mux)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${YELLOW}说明：三种 443 入口不是三套独立安装器；[2] 建立共享配置，[3]/[4]/[5] 负责检查依赖、生成目标配置并切换入口。${PLAIN}" "${YELLOW}Description: The three 443 entries are not three sets of independent installers; [2] creates a shared configuration, [3]/[4]/[5] are responsible for checking dependencies, generating target configurations and switching entries.${PLAIN}" "${YELLOW}Описание: Три входа 443 — это не три группы независимых установщиков; [2] создает общую конфигурацию, [3]/[4]/[5] отвечают за проверку зависимостей, генерацию целевых конфигураций и переключение входов.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q/back/返回${PLAIN}" "${RED}0. Main menu / q/back${PLAIN}" "${RED}0. Главное меню / q/back${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local sni_choice
        read_trimmed sni_choice "$(localized_text "👉 请输入菜单编号或 ?: " "👉 Please enter menu number or ?:" "👉 Пожалуйста, введите номер меню или ?:")"
        case "$sni_choice" in
            1) show_current_entry_status ;;
            2) func_caddy_cf_reality_wizard ;;
            3) switch_entry_mode "nginx-stream" ;;
            4) switch_entry_mode "xray-fallback" ;;
            5) switch_entry_mode "tcp-peek" ;;
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
            16) start_tcp_peek_test_port ;;
            17) tcp_peek_dry_run_config ;;
            18) view_vpso_mux_logs ;;
            "?"|help) show_sni_help; pause_return; continue ;;
            0) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择，请输入菜单编号或 ?。${PLAIN}" "${RED}❌ Invalid selection, please enter the menu number or ?.${PLAIN}" "${RED}❌ Неверный выбор, введите номер меню или ?.${PLAIN}")"; sleep 1 ;;
        esac
        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

normalize_main_choice() {
    local choice
    choice="$(trim_input "$1")"
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
        q|quit|exit|0|退出) echo "0" ;;
        pre|preflight|check|预检) echo "1" ;;
        init|base|初始化) echo "2" ;;
        env|docker|组件) echo "3" ;;
        caddy|nginx|ngx|proxy|reverse|反代) echo "4" ;;
        xcm|xui-custom|外置|外置增强|外置管理) echo "xui-custom" ;;
        panel|node|nodes|面板|节点) echo "5" ;;
        ssh) echo "6" ;;
        fail2ban|f2b) echo "7" ;;
        fw|firewall|防火墙) echo "8" ;;
        tweak|system|系统) echo "9" ;;
        net|kernel|bbr|网络|内核) echo "10" ;;
        docker-safe|docker安全) echo "11" ;;
        test|speed|测速) echo "12" ;;
        port|端口) echo "13" ;;
        info|hardware|探针) echo "14" ;;
        h|health|健康|体检) echo "15" ;;
        b|backup|bak|备份) echo "16" ;;
        u|upd|update|更新) echo "17" ;;
        reboot|重启) echo "18" ;;
        sni|443|单入口) echo "19" ;;
        l|lang|language|язык|语言) echo "20" ;;
        traffic|quota|bill|流量|达量|账单) echo "10" ;;
        *) echo "$choice" ;;
    esac
}

beginner_run_optional_step() {
    local step="$1"
    local total="$2"
    local label="$3"
    local function_name="$4"
    local choice

    echo -e "${CYAN}[${step}/${total}] ${label}${PLAIN}"
    read_trimmed choice "$(localized_text "是否进入此步骤？(Y/n): " "Do you want to proceed to this step? (Y/n):" "Хотите перейти к этому шагу? (Да/Нет):")"
    if [[ "${choice:-yes}" =~ ^[Nn]([Oo])?$ ]]; then
        echo -e "$(localized_text "${BLUE}已跳过：${label}${PLAIN}" "${BLUE}Skipped: ${label}${PLAIN}" "${BLUE}пропущен: ${label}${PLAIN}")"
        return 2
    fi
    "$function_name"
}

func_beginner_machine_init() {
    local total=7
    local step_rc step_entry step label function_name
    local VPSO_BEGINNER_FLOW=1
    local completed=("$(localized_text "部署前预检" "Preflight check" "Предварительная проверка")")
    local skipped=()
    local optional_steps=(
        "3|$(localized_text "SSH 安全配置" "SSH security" "Безопасность SSH")|func_security"
        "4|$(localized_text "SSH 公钥配置" "SSH public key" "Открытый ключ SSH")|func_add_ssh_key"
        "5|$(localized_text "Fail2ban 配置" "Fail2ban" "Fail2ban")|func_fail2ban"
        "6|$(localized_text "防火墙配置" "Firewall" "Брандмауэр")|func_firewall_manage"
        "7|$(localized_text "配置备份" "Configuration backup" "Резервная копия конфигурации")|func_backup_center"
    )

    echo -e "$(localized_text "${CYAN}[1/${total}] 部署前预检${PLAIN}" "${CYAN}[1/${total}] preflight check before deployment${PLAIN}" "${CYAN}[1/${total}] Предварительная проверка перед развертыванием.${PLAIN}")"
    if ! func_preflight_check; then
        echo -e "$(localized_text "${RED}❌ 预检存在异常，新机器初始化已停止，未继续修改系统。${PLAIN}" "${RED}❌ Preflight checks failed. New-server initialization stopped without further system changes.${PLAIN}" "${RED}❌ Предварительная проверка завершилась ошибкой. Инициализация нового сервера остановлена без дальнейших изменений системы.${PLAIN}")"
        pause_return
        return 1
    fi

    echo -e "$(localized_text "${CYAN}[2/${total}] 基础初始化${PLAIN}" "${CYAN}[2/${total}] Basic initialization${PLAIN}" "${CYAN}[2/${total}] Базовая инициализация${PLAIN}")"
    if ! func_base_init; then
        echo -e "$(localized_text "${RED}❌ 基础初始化未完整完成，后续安全配置已停止。${PLAIN}" "${RED}❌ Basic initialization is not completely completed, and subsequent security configuration has been stopped.${PLAIN}" "${RED}❌ Базовая инициализация не полностью завершена, и последующая настройка безопасности остановлена.${PLAIN}")"
        pause_return
        return 1
    fi
    completed+=("$(localized_text "基础初始化" "Base initialization" "Базовая инициализация")")

    for step_entry in "${optional_steps[@]}"; do
        IFS='|' read -r step label function_name <<< "$step_entry"
        beginner_run_optional_step "$step" "$total" "$label" "$function_name"
        step_rc=$?
        if [[ "$step_rc" -eq 0 ]]; then
            completed+=("$label")
        elif [[ "$step_rc" -eq 2 ]]; then
            skipped+=("$label")
        else
            echo -e "$(localized_text "${RED}❌ ${label} 执行失败，新机器初始化已停止。${PLAIN}" "${RED}❌ ${label} execution failed, new machine initialization has stopped.${PLAIN}" "${RED}❌ ${label} не удалось выполнить, инициализация новой машины остановлена.${PLAIN}")"
            echo -e "$(localized_text "${CYAN}已完成：${completed[*]}${PLAIN}" "${CYAN}Completed: ${completed[*]}${PLAIN}" "${CYAN}Завершено: ${completed[*]}${PLAIN}")"
            pause_return
            return 1
        fi
    done

    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}✅ 新机器初始化流程结束。${PLAIN}" "${GREEN}✅ The new machine initialization process is completed.${PLAIN}" "${GREEN}✅ Процесс инициализации нового устройства завершен.${PLAIN}")"
    echo -e "$(localized_text "已完成：${completed[*]}" "Completed: ${completed[*]}" "Завершено: ${completed[*]}")"
    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}已跳过：${skipped[*]}${PLAIN}" "${YELLOW}Skipped: ${skipped[*]}${PLAIN}" "${YELLOW}пропущен: ${skipped[*]}${PLAIN}")"
    fi
    pause_return
}

func_beginner_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "新手向导" "Beginner guide" "Руководство для начинающих")"
        echo -e "${BOLD}VPS-Optimize ${SCRIPT_VERSION}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        localized_echo \
            "${YELLOW}这是简化入口，只保留第一次部署最常用的路径；老用户可返回完整菜单。${PLAIN}" \
            "${YELLOW}This simplified guide contains the most common first-deployment paths. Return to the full menu for all features.${PLAIN}" \
            "${YELLOW}Это упрощённый раздел с основными действиями для первого запуска. Все функции доступны в полном меню.${PLAIN}"
        echo -e "------------------------------------------------"
        localized_echo \
            "${GREEN}  1. 新机器初始化${PLAIN}       ${YELLOW}(预检 -> 初始化 -> SSH/公钥/Fail2ban/防火墙 -> 备份)${PLAIN}" \
            "${GREEN}  1. Initialize a new server${PLAIN}  ${YELLOW}(preflight -> base setup -> SSH/keys/Fail2ban/firewall -> backup)${PLAIN}" \
            "${GREEN}  1. Первичная настройка сервера${PLAIN}  ${YELLOW}(проверка -> базовая настройка -> SSH/ключи/Fail2ban/брандмауэр -> резервная копия)${PLAIN}"
        localized_echo \
            "${GREEN}  2. 安装面板/节点${PLAIN}     ${YELLOW}(进入面板、节点与订阅工具菜单)${PLAIN}" \
            "${GREEN}  2. Install a panel/node${PLAIN}    ${YELLOW}(open panel, node, and subscription tools)${PLAIN}" \
            "${GREEN}  2. Установить панель/узел${PLAIN}     ${YELLOW}(открыть меню панелей, узлов и подписок)${PLAIN}"
        localized_echo \
            "${GREEN}  3. 配置 443 单入口${PLAIN}   ${YELLOW}(面板/订阅/REALITY 共用公网 443)${PLAIN}" \
            "${GREEN}  3. Configure shared port 443${PLAIN} ${YELLOW}(panels, subscriptions, and REALITY share public port 443)${PLAIN}" \
            "${GREEN}  3. Настроить общий вход 443${PLAIN}   ${YELLOW}(общий публичный порт 443 для панелей, подписок и REALITY)${PLAIN}"
        localized_echo \
            "${GREEN}  4. 健康检查${PLAIN}          ${YELLOW}(服务状态、端口、证书、反馈诊断)${PLAIN}" \
            "${GREEN}  4. Health check${PLAIN}              ${YELLOW}(services, ports, certificates, and diagnostics)${PLAIN}" \
            "${GREEN}  4. Проверка состояния${PLAIN}          ${YELLOW}(службы, порты, сертификаты и диагностика)${PLAIN}"
        localized_echo \
            "${GREEN}  5. 备份/回滚${PLAIN}         ${YELLOW}(创建备份或恢复配置)${PLAIN}" \
            "${GREEN}  5. Backup/rollback${PLAIN}           ${YELLOW}(create a backup or restore configuration)${PLAIN}" \
            "${GREEN}  5. Резервная копия/откат${PLAIN}       ${YELLOW}(создать копию или восстановить конфигурацию)${PLAIN}"
        echo -e "------------------------------------------------"
        localized_echo "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}  ?. Help${PLAIN}" "${BLUE}  ?. Справка${PLAIN}"
        localized_echo "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}  0. Main menu / q Back${PLAIN}" "${RED}  0. Главное меню / q Назад${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local beginner_choice
        read_trimmed beginner_choice "$(localized_text "👉 请选择操作: " "👉 Choose an action: " "👉 Выберите действие: ")"
        case "$beginner_choice" in
            1)
                func_beginner_machine_init
                ;;
            2) func_panel_deploy_menu ;;
            3) func_sni_stack_quick_menu ;;
            4) func_health_dashboard ;;
            5) func_backup_center ;;
            "?"|help|h) show_beginner_help; echo ""; pause_return ;;
            0|q|Q) break ;;
            *) localized_echo "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid choice.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}"; sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------
# 界面主循环 (新增 IP 防送中 & SublinkPro)
# ---------------------------------------------------------
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
            echo -e "  ${GREEN}1.${PLAIN} Предварительная проверка    ${YELLOW}(порты, система, службы и возможные риски)${PLAIN}"
            echo -e "  ${GREEN}2.${PLAIN} Базовая настройка системы   ${YELLOW}(инструменты, часовой пояс, обновления и базовый BBR)${PLAIN}"
            echo -e "  ${GREEN}3.${PLAIN} Компоненты и службы          ${YELLOW}(Docker, Python, WARP и распространённые инструменты)${PLAIN}"
            echo -e "  ${GREEN}4.${PLAIN} Обратный прокси             ${YELLOW}(Caddy/Nginx вне единого входа 443)${PLAIN}"
            echo -e "  ${GREEN}5.${PLAIN} Панели, узлы и подписки     ${YELLOW}(3x-ui, Sing-box, подписки и Dockge)${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ② Безопасность и контроль доступа${PLAIN}"
            echo -e "  ${GREEN}6.${PLAIN} Центр безопасности SSH      ${YELLOW}(порт, открытые ключи и вход только по ключу)${PLAIN}"
            echo -e "  ${GREEN}7.${PLAIN} Защита Fail2ban             ${YELLOW}(автоматическая блокировка перебора паролей SSH)${PLAIN}"
            echo -e "  ${GREEN}8.${PLAIN} Управление брандмауэром     ${YELLOW}(разрешение, удаление и просмотр правил, лимиты соединений)${PLAIN}"
            echo -e "  ${GREEN}9.${PLAIN} Системные настройки         ${YELLOW}(IPv6, приоритет IPv4, ping, имя хоста и очистка)${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ③ Производительность сети и контейнеры${PLAIN}"
            echo -e " ${GREEN}10.${PLAIN} Оптимизация сети и ядра     ${YELLOW}(BBR, TCP, ZRAM, DNS и облегчённые ядра)${PLAIN}"
            echo -e " ${GREEN}11.${PLAIN} Безопасность Docker         ${YELLOW}(блокировка или восстановление внешнего доступа)${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ④ Диагностика, резервное копирование и обслуживание${PLAIN}"
            echo -e " ${GREEN}12.${PLAIN} Тест скорости и качества    ${YELLOW}(YABS, стриминг, маршруты и качество IP)${PLAIN}"
            echo -e " ${GREEN}13.${PLAIN} Диагностика портов          ${YELLOW}(поиск слушающих процессов и принудительное завершение)${PLAIN}"
            echo -e " ${GREEN}14.${PLAIN} Сведения о системе          ${YELLOW}(CPU, память, диски и сеть в реальном времени)${PLAIN}"
            echo -e " ${GREEN}15.${PLAIN} Состояние служб            ${YELLOW}(службы, сертификаты и слушающие порты)${PLAIN}"
            echo -e " ${GREEN}16.${PLAIN} Резервная копия и откат    ${YELLOW}(создание, просмотр, восстановление и очистка)${PLAIN}"
            echo -e " ${BOLD}${YELLOW}17.${PLAIN} Обновить скрипт          ${CYAN}(команды: u / update / upd)${PLAIN}"
            echo -e " ${RED}18.${PLAIN} Перезагрузить сервер"
            echo -e ""
            echo -e " ${BOLD}${BLUE}▶ ⑤ Часто используемые функции${PLAIN}"
            echo -e " ${GREEN}19.${PLAIN} общий вход 443            ${YELLOW}(настройка, сайты, диагностика и сертификаты)${PLAIN}"
            echo -e " ${GREEN}20.${PLAIN} Язык интерфейса           ${YELLOW}(中文 / English / Русский)${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e " ${RED} 0.${PLAIN} Выход"
            echo -e "${CYAN}================================================${PLAIN}"
        elif [[ "$VPSO_LANGUAGE" == "en" ]]; then
            echo -e "${CYAN}================================================${PLAIN}"
            print_breadcrumb "Main menu"
            echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (shortcut: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            print_auto_update_notice
            echo -e "${CYAN}================================================${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ① Recommended setup for a new server${PLAIN}"
            echo -e "  ${GREEN}1.${PLAIN} Preflight and risk scan     ${YELLOW}(check ports, OS, and services before deployment)${PLAIN}"
            echo -e "  ${GREEN}2.${PLAIN} Base system initialization  ${YELLOW}(tools, timezone, updates, and basic BBR)${PLAIN}"
            echo -e "  ${GREEN}3.${PLAIN} Components and services      ${YELLOW}(Docker, Python, WARP, and common tools)${PLAIN}"
            echo -e "  ${GREEN}4.${PLAIN} Reverse proxy               ${YELLOW}(Caddy/Nginx sites outside the shared 443 entry)${PLAIN}"
            echo -e "  ${GREEN}5.${PLAIN} Panels, nodes, subscriptions ${YELLOW}(3x-ui, Sing-box, subscriptions, and Dockge)${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ② Security and access control${PLAIN}"
            echo -e "  ${GREEN}6.${PLAIN} SSH security center         ${YELLOW}(port, public keys, and key-only login modes)${PLAIN}"
            echo -e "  ${GREEN}7.${PLAIN} Fail2ban protection         ${YELLOW}(automatically block SSH brute-force IPs)${PLAIN}"
            echo -e "  ${GREEN}8.${PLAIN} Firewall rules              ${YELLOW}(allow, remove, inspect, disable, and limit connections)${PLAIN}"
            echo -e "  ${GREEN}9.${PLAIN} System switches and cleanup ${YELLOW}(IPv6, IPv4 priority, ping, hostname, and cleanup)${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ③ Network performance and containers${PLAIN}"
            echo -e " ${GREEN}10.${PLAIN} Network and kernel tuning    ${YELLOW}(BBR, TCP, ZRAM, DNS, and lightweight kernels)${PLAIN}"
            echo -e " ${GREEN}11.${PLAIN} Docker security management  ${YELLOW}(block or restore unintended external access)${PLAIN}"

            echo -e " ${BOLD}${BLUE}▶ ④ Diagnostics, backup, and maintenance${PLAIN}"
            echo -e " ${GREEN}12.${PLAIN} Speed and quality tests      ${YELLOW}(YABS, streaming, routes, and IP quality)${PLAIN}"
            echo -e " ${GREEN}13.${PLAIN} Inspect and release ports    ${YELLOW}(find listeners and terminate a process)${PLAIN}"
            echo -e " ${GREEN}14.${PLAIN} System hardware probe       ${YELLOW}(live CPU, memory, disk, and network details)${PLAIN}"
            echo -e " ${GREEN}15.${PLAIN} Service health overview     ${YELLOW}(services, certificates, and listening ports)${PLAIN}"
            echo -e " ${GREEN}16.${PLAIN} Configuration backup        ${YELLOW}(back up, list, restore, and clean up)${PLAIN}"
            echo -e " ${BOLD}${YELLOW}17.${PLAIN} Update script              ${CYAN}(shortcut: u / update / upd)${PLAIN}"
            echo -e " ${RED}18.${PLAIN} Reboot server"
            echo -e ""
            echo -e " ${BOLD}${BLUE}▶ ⑤ Frequently used${PLAIN}"
            echo -e " ${GREEN}19.${PLAIN} Shared 443 entry manager    ${YELLOW}(initialize, add sites, check health, and repair certificates)${PLAIN}"
            echo -e " ${GREEN}20.${PLAIN} Interface language          ${YELLOW}(中文 / English / Русский)${PLAIN}"
            echo -e "${CYAN}================================================${PLAIN}"
            echo -e " ${RED} 0.${PLAIN} Exit"
            echo -e "${CYAN}================================================${PLAIN}"
        else
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "主菜单"
        echo -e " ${BOLD}🚀 VPS-Optimize ${SCRIPT_VERSION} (快捷键: ${YELLOW}cy${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        print_auto_update_notice
        echo -e "${CYAN}================================================${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ① 推荐流程：新机器先跑这里${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 运维预检与风险扫描    ${YELLOW}(部署前先看端口/系统/服务状态)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 基础环境初始化        ${YELLOW}(工具/时区/系统更新/基础 BBR)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 基础组件与常用服务    ${YELLOW}(Docker/Python/WARP/常用工具)${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} 反代（Caddy/Nginx）   ${YELLOW}(未接入 443 单入口的网站/面板反代)${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} 面板、节点与订阅工具  ${YELLOW}(3x-ui/Sing-box/订阅管理/Dockge)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ② 安全与访问控制${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} SSH 安全中心          ${YELLOW}(端口/公钥/密钥登录模式)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} Fail2ban 防爆破       ${YELLOW}(自动封禁 SSH 爆破 IP)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 防火墙规则管理        ${YELLOW}(放行/删除/查看/关闭/连接数限制)${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 系统开关与清理        ${YELLOW}(IPv6/IPv4优先/Ping/主机名/清理)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ③ 网络性能与容器${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 网络与内核优化        ${YELLOW}(BBR/TCP/ZRAM/DNS/轻量内核)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} Docker 安全管理       ${YELLOW}(本地防穿透/恢复访问)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ ④ 诊断、备份与维护${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 测速与质量检测        ${YELLOW}(YABS/流媒体/回程/IP质量)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 端口排查与释放        ${YELLOW}(查看占用并强杀进程)${PLAIN}"
        echo -e " ${GREEN}14.${PLAIN} 系统硬件探针          ${YELLOW}(CPU/内存/磁盘/网络实时信息)${PLAIN}"
        echo -e " ${GREEN}15.${PLAIN} 服务健康总览          ${YELLOW}(服务状态/证书摘要/端口概览)${PLAIN}"
        echo -e " ${GREEN}16.${PLAIN} 配置备份与回滚        ${YELLOW}(备份/列表/恢复/清理)${PLAIN}"
        echo -e " ${BOLD}${YELLOW}17.${PLAIN} 更新脚本              ${CYAN}(快捷词：u / update / upd)${PLAIN}"
        echo -e " ${RED}18.${PLAIN} 重启服务器"
        echo -e ""
        echo -e " ${BOLD}${BLUE}▶ ⑤ 高频直达${PLAIN}"
        echo -e " ${GREEN}19.${PLAIN} 443 单入口管理中心    ${YELLOW}(初始化/加网站/体检/证书修复)${PLAIN}"
        echo -e " ${GREEN}20.${PLAIN} 界面语言              ${YELLOW}(中文 / English / Русский)${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e " ${RED} 0.${PLAIN} 退出面板"
        echo -e "${CYAN}================================================${PLAIN}"
        fi

        local choice
        read_trimmed choice "$(localized_text "👉 请输入数字或快捷词选择功能: " "👉 Enter a number or shortcut: " "👉 Введите номер или команду: ")"
        choice=$(normalize_main_choice "$choice")

        case $choice in
            n|N|newbie|guide|新手|向导) func_beginner_menu ;;
            "?"|help|帮助) show_main_help; echo ""; pause_return ;;
            20|l|L|lang|language|язык|语言) select_ui_language; sleep 1 ;;
            xui-custom) func_xui_custom_manager ;;
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
                    "${RED}❌ 无效的输入，请输入菜单中存在的数字！${PLAIN}" \
                    "${RED}❌ Invalid input. Enter a number or shortcut shown in the menu.${PLAIN}" \
                    "${RED}❌ Неверный ввод. Введите номер или команду из меню.${PLAIN}"
                sleep 1
                ;;
        esac
    done
}
