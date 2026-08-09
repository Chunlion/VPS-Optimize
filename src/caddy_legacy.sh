# shellcheck shell=bash
# Disabled legacy Caddy + Reality wizard compatibility stub.

func_caddy_cf_reality_wizard_legacy_disabled() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧩 Reality 443 复用 + Cloudflare DNS 自动化向导${PLAIN}" "${BOLD}🧩 Reality 443 Multiplex + Cloudflare DNS Automation Wizard${PLAIN}" "${BOLD}🧩 Reality 443 Multiplex + Cloudflare DNS Мастер автоматизации${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}本向导会让 Caddy 仅监听本地端口，不占用公网 80/443。${PLAIN}" "${YELLOW}This wizard will make Caddy only listen to the local port and not occupy the public 80/443.${PLAIN}" "${YELLOW}Этот мастер заставит Caddy только прослушивать локальный порт и не занимать публичную сеть 80/443.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}推荐用于：3x-ui+Reality 已占用 443，同时 Web 服务需要同域名 HTTPS。${PLAIN}" "${YELLOW}Recommended when 3x-ui+Reality occupies 443 and the Web service needs HTTPS on the same domain.${PLAIN}" "${YELLOW}Рекомендуется, когда 3x-ui+Reality занимает 443, а веб-службе нужен HTTPS на том же домене.${PLAIN}")"
    echo -e "------------------------------------------------"

    read_trimmed reality_occupied "$(localized_text "❓ 当前 443 端口是否已被 3x-ui+Reality 入站占用？(Y/n): " "❓ Is port 443 currently occupied by a 3x-ui+Reality inbound? (Y/n):" "❓ Занят ли порт 443 входящим 3x-ui+Reality? (Да/Нет):")"
    if is_no "$reality_occupied"; then
        echo -e "$(localized_text "${BLUE}ℹ️ 您选择了未占用 443，本向导仍将使用本地端口模式，避免与未来业务冲突。${PLAIN}" "${BLUE}ℹ️ If you select Unoccupied 443, this wizard will still use the local port mode to avoid conflicts with future services.${PLAIN}" "${BLUE}ℹ️ Если вы выберете Незанятый 443, этот мастер по-прежнему будет использовать режим локального порта, чтобы избежать конфликтов с будущими службами.${PLAIN}")"
    fi

    local listen_port
    read_trimmed listen_port "$(localized_text "👉 请输入 Caddy 本地 TLS 监听端口 (默认 8443): " "👉 Please enter Caddy local TLS listening port (default 8443):" "👉 Пожалуйста, введите локальный порт прослушивания Caddy TLS (по умолчанию 8443):")"
    listen_port=${listen_port:-8443}
    if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [[ "$listen_port" -lt 1 || "$listen_port" -gt 65535 ]]; then
        echo -e "$(localized_text "${RED}❌ 监听端口无效！必须是 1-65535 的纯数字。${PLAIN}" "${RED}❌ The listening port is invalid! Must be a number from 1-65535.${PLAIN}" "${RED}❌ Неверный порт прослушивания! Должно быть чистое число от 1 до 65535.${PLAIN}")"
        return
    fi
    if is_yes "$reality_occupied" && [[ "$listen_port" -eq 443 ]]; then
        echo -e "$(localized_text "${RED}❌ 443 已用于 Reality，请改用本地高位端口 (如 8443/9443)。${PLAIN}" "${RED}❌ 443 has been used for Reality, please use the local high port (such as 8443/9443) instead.${PLAIN}" "${RED}❌ 443 использовался для Reality, вместо этого используйте локальный высокий порт (например, 8443/9443).${PLAIN}")"
        return
    fi

    local cf_token
    echo -e "$(localized_text "${CYAN}👇 请输入 Cloudflare API Token（需 Zone.DNS 编辑权限）${PLAIN}" "${CYAN}👇 Please enter Cloudflare API Token (Zone.DNS editing permission required)${PLAIN}" "${CYAN}👇 Введите Cloudflare API Token (требуется разрешение на редактирование Zone.DNS)${PLAIN}")"
    read_secret_trimmed cf_token "CF Token: "
    if [[ -z "$cf_token" || ${#cf_token} -lt 20 ]]; then
        echo -e "$(localized_text "${RED}❌ Token 长度异常，已取消。${PLAIN}" "${RED}❌ Token length is abnormal and has been cancelled.${PLAIN}" "${RED}❌ Длина токена ненормальная, и он был отменен.${PLAIN}")"
        return
    fi
    echo -e "$(localized_text "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}" "${CYAN}▶ Verifying online Cloudflare Token...${PLAIN}" "${CYAN}▶ Проверка токена Cloudflare онлайн...${PLAIN}")"
    verify_cf_token_online "$cf_token"
    local verify_rc=$?
    if [[ "$verify_rc" -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ Token 校验通过。${PLAIN}" "${GREEN}✅ Token verification passed.${PLAIN}" "${GREEN}✅ Проверка токена пройдена.${PLAIN}")"
    elif [[ "$verify_rc" -eq 2 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}" "${YELLOW}⚠️ curl is not installed, skip online verification.${PLAIN}" "${YELLOW}⚠️ curl не установлен, пропустите онлайн-проверку.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ Token 在线校验失败：请检查权限或确认 Token 未填错。${PLAIN}" "${RED}❌ Token online verification failed: please check the permissions or confirm that the Token is not filled in incorrectly.${PLAIN}" "${RED}❌ Не удалось выполнить онлайн-проверку токена: проверьте разрешения или убедитесь, что токен заполнен правильно.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}" "${YELLOW}Requires permissions: Zone.DNS.Edit + Zone.Zone.Read${PLAIN}" "${YELLOW}требуются разрешения: Zone.DNS.Edit + Zone.Zone.Read.${PLAIN}")"
        return
    fi

    if ! install_caddy_if_needed; then
        echo -e "$(localized_text "${RED}❌ Caddy 安装失败，请检查网络后重试。${PLAIN}" "${RED}❌ Caddy installation failed, please check the network and try again.${PLAIN}" "${RED}❌ Установка Caddy не удалась, проверьте сеть и повторите попытку.${PLAIN}")"
        return
    fi

    local acme_bin="/root/.acme.sh/acme.sh"
    local acme_email
    acme_email=$(get_acme_account_email)
    if [[ ! -x "$acme_bin" ]]; then
        if ! install_acme_sh "$acme_email"; then
            echo -e "$(localized_text "${RED}❌ acme.sh 安装失败，请检查网络后重试。${PLAIN}" "${RED}❌ acme.sh installation failed, please check the network and try again.${PLAIN}" "${RED}❌ Установка acme.sh не удалась, проверьте сеть и повторите попытку.${PLAIN}")"
            return
        fi
    fi
    if [[ ! -x "$acme_bin" ]]; then
        echo -e "$(localized_text "${RED}❌ 未找到 acme.sh，可执行文件异常。${PLAIN}" "${RED}❌ acme.sh not found, the executable file is abnormal.${PLAIN}" "${RED}❌ acme.sh не найден, исполняемый файл ненормальный.${PLAIN}")"
        return
    fi
    if ! prepare_acme_account "$acme_bin" "$acme_email"; then
        echo -e "$(localized_text "${RED}❌ acme 账户初始化失败，请检查邮箱配置后重试。${PLAIN}" "${RED}❌ acme account initialization failed, please check the email configuration and try again.${PLAIN}" "${RED}❌ Ошибка инициализации учетной записи acme. Проверьте конфигурацию электронной почты и повторите попытку.${PLAIN}")"
        return
    fi

    local cf_env_dir="/root/.config/vps-panel"
    local cf_env_file="${cf_env_dir}/cloudflare.env"
    mkdir -p "$cf_env_dir"
    chmod 700 "$cf_env_dir"
    local escaped_token
    escaped_token=${cf_token//\'/\'"\'"\'}
    printf "CF_Token='%s'\n" "$escaped_token" > "$cf_env_file"
    chmod 600 "$cf_env_file"

    mkdir -p /etc/caddy/conf.d /etc/caddy/certs /root/cert

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在扫描并隔离旧式 Caddy 配置（防止抢占 443）...${PLAIN}" "${CYAN}▶ Scanning and quarantining legacy Caddy configuration (preventing preemption 443)...${PLAIN}" "${CYAN}▶ Сканирование и помещение в карантин устаревшей конфигурации Caddy (предотвращение приоритетного вытеснения 443)...${PLAIN}")"
    quarantine_legacy_caddy_443_configs

    echo -e "$(localized_text "${YELLOW}👇 开始添加域名反代规则（可连续添加多个）${PLAIN}" "${YELLOW}👇 Start adding domain reverse proxy rules (you can add multiple consecutively)${PLAIN}" "${YELLOW}👇 Начните добавлять правила защиты от подмены доменных имен (вы можете добавить несколько последовательно)${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}格式：域名 -> 本地端口，例如 panel.example.com -> 8000${PLAIN}" "${YELLOW}Format: domain -> local port, such as panel.example.com -> 8000${PLAIN}" "${YELLOW}Формат : имя домена -> локальный порт, например, Panel.example.com -> 8000.${PLAIN}")"
    echo -e "------------------------------------------------"

    local success_count=0
    local fail_count=0
    local summary_file="/root/cert/caddy_cf_manifest.txt"

    while true; do
        local domain domain_input backend_port continue_add
        read_trimmed domain_input "$(localized_text "👉 请输入域名 (回车结束添加): " "👉 Please enter the domain (press enter to end adding):" "👉 Пожалуйста, введите имя домена (нажмите Enter, чтобы завершить добавление):")"
        domain=$(normalize_domain_input "$domain_input")
        if [[ -z "$domain" ]]; then
            break
        fi

        if ! is_valid_domain "$domain"; then
            print_domain_validation_error "$(localized_text "域名" "domain" "доменное имя")" "$domain_input" "$domain"
            ((fail_count++))
            continue
        fi

        read_trimmed backend_port "$(localized_text "👉 请输入该域名反代的本地端口: " "👉 Please enter the local port for the reverse proxy of this domain:" "👉 Пожалуйста, введите локальный порт для обратного прокси-сервера этого доменного имени:")"
        if ! is_valid_port "$backend_port"; then
            echo -e "$(localized_text "${RED}❌ 端口无效：$backend_port${PLAIN}" "${RED}❌ Invalid port: $backend_port${PLAIN}" "${RED}❌ Неверный порт: $backend_port.${PLAIN}")"
            ((fail_count++))
            continue
        fi

        local conf_file="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$conf_file" ]]; then
            echo -e "$(localized_text "${RED}❌ 已存在域名配置：$conf_file，请先删除后再添加。${PLAIN}" "${RED}❌ domain configuration: $conf_file already exists. Please delete it first and then add it.${PLAIN}" "${RED}❌ Конфигурация доменного имени: $conf_file уже существует. Пожалуйста, сначала удалите его, а затем добавьте.${PLAIN}")"
            ((fail_count++))
            continue
        fi

        # shellcheck disable=SC1090
        source "$cf_env_file"
        echo -e "$(localized_text "${CYAN}▶ 正在为 ${domain} 申请 DNS 证书...${PLAIN}" "${CYAN}▶ Applying for DNS certificate for ${domain}...${PLAIN}" "${CYAN}▶ Подача заявки на сертификат DNS для ${domain}...${PLAIN}")"
        if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
            echo -e "$(localized_text "${RED}❌ 证书申请失败：${domain}${PLAIN}" "${RED}❌ Certificate application failed: ${domain}${PLAIN}" "${RED}❌ Не удалось применить сертификат: ${domain}.${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}   提示：可进入主菜单 [19] -> [12] -> [14] 一键自动修复后再重试。${PLAIN}" "${YELLOW}Tip: You can enter the main menu [19] -> [12] -> [14] to automatically repair it with one click and then try again.${PLAIN}" "${YELLOW}Совет: вы можете войти в главное меню [19] -> [12] -> [14], чтобы автоматически восстановить его одним щелчком мыши, а затем повторить попытку.${PLAIN}")"
            ((fail_count++))
            continue
        fi

        local cert_file="/etc/caddy/certs/${domain}.crt"
        local key_file="/etc/caddy/certs/${domain}.key"

        if ! "$acme_bin" --install-cert -d "$domain" --ecc \
            --fullchain-file "$cert_file" \
            --key-file "$key_file" \
            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
            echo -e "$(localized_text "${RED}❌ 证书安装失败：${domain}${PLAIN}" "${RED}❌ Certificate installation failed: ${domain}${PLAIN}" "${RED}❌ Не удалось установить сертификат: ${domain}.${PLAIN}")"
            ((fail_count++))
            continue
        fi

        if id caddy >/dev/null 2>&1; then
            chown root:caddy "$cert_file" "$key_file" >/dev/null 2>&1
            chmod 640 "$cert_file" "$key_file"
        else
            chmod 600 "$cert_file" "$key_file"
        fi

        ln -sfn "$cert_file" "/root/cert/${domain}.crt"
        ln -sfn "$key_file" "/root/cert/${domain}.key"

        cat <<EOF > "$conf_file"
https://${domain}:${listen_port} {
    bind 127.0.0.1
    tls ${cert_file} ${key_file}
    reverse_proxy 127.0.0.1:${backend_port}
}
EOF

        echo -e "$(localized_text "${GREEN}✅ 域名 ${domain} 已完成：证书签发 + 反代配置 + 证书挂载。${PLAIN}" "${GREEN}✅ domain ${domain} has been completed: certificate issuance + reverse proxy configuration + certificate mounting.${PLAIN}" "${GREEN}✅ Доменное имя ${domain} завершено: выпуск сертификата + настройка обратного прокси + монтирование сертификата.${PLAIN}")"
        ((success_count++))

        read_trimmed continue_add "$(localized_text "继续添加下一个域名？(Y/n): " "Continue adding the next domain? (Y/n):" "Продолжить добавление следующего доменного имени? (Да/Нет):")"
        if ! is_yes "$continue_add"; then
            break
        fi
    done

    echo -e "$(localized_text "${CYAN}▶ 正在校验并加载 Caddy 配置...${PLAIN}" "${CYAN}▶ Verifying and loading Caddy configuration...${PLAIN}" "${CYAN}▶ Проверка и загрузка конфигурации Caddy...${PLAIN}")"
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl enable caddy >/dev/null 2>&1
        systemctl restart caddy >/dev/null 2>&1
        echo -e "$(localized_text "${GREEN}✅ Caddy 已成功重载，配置生效。${PLAIN}" "${GREEN}✅ Caddy has been successfully reloaded and the configuration has taken effect.${PLAIN}" "${GREEN}✅ Caddy был успешно перезагружен, и конфигурация вступила в силу.${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ Caddy 配置校验失败！请检查 /etc/caddy/conf.d/ 下新增文件语法。${PLAIN}" "${RED}❌ Caddy configuration validation failed! Please check the new file syntax under /etc/caddy/conf.d/.${PLAIN}" "${RED}❌ Caddy Проверка конфигурации не удалась! Пожалуйста, проверьте новый синтаксис файла под /etc/caddy/conf.d/.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}已保留证书文件，您修正配置后可手动执行: systemctl restart caddy${PLAIN}" "${YELLOW}Has reserved the certificate file. You can manually execute it after correcting the configuration: systemctl restart caddy${PLAIN}" "${YELLOW}зарезервировал файл сертификата. Вы можете выполнить его вручную после исправления конфигурации: systemctl restart caddy${PLAIN}")"
    fi

    generate_caddy_cf_manifest

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${GREEN}🎯 向导执行完成：成功 ${success_count} 个，失败 ${fail_count} 个。${PLAIN}" "${GREEN}🎯 Wizard execution completed: ${success_count} successfully, ${fail_count} failed.${PLAIN}" "${GREEN}🎯 Выполнение мастера завершено: ${success_count} успешно, ${fail_count} не удалось.${PLAIN}")"
    echo -e "$(localized_text "${CYAN}证书软链接目录:${PLAIN} /root/cert" "${CYAN}Certificate symlink directory:${PLAIN} /root/cert" "Каталог программных ссылок сертификата ${CYAN}:${PLAIN} /root/cert")"
    echo -e "$(localized_text "${CYAN}清单文件路径:${PLAIN} ${summary_file}" "${CYAN}Manifest file path:${PLAIN} ${summary_file}" "Путь к файлу манифеста ${CYAN}:${PLAIN} ${summary_file}")"
    echo -e "$(localized_text "${YELLOW}💡 3x-ui 手动配置提示：${PLAIN}" "${YELLOW}💡 3x-ui Manual configuration prompt:${PLAIN}" "${YELLOW}💡 3x-ui Подсказка для ручной настройки:${PLAIN}")"
    echo -e "$(localized_text "1) 在 Reality 节点里设置 fallback/dest 指向: 127.0.0.1:${listen_port}" "1) Set fallback/dest in the Reality node to point to: 127.0.0.1:${listen_port}" "1) Установите резервный/назначение в узле Reality, чтобы он указывал на: 127.0.0.1:${listen_port}.")"
    echo -e "$(localized_text "2) 每个回落域名需与本向导录入域名一致，SNI 才能命中对应证书和反代规则" "2) Each fallback domain must be consistent with the domain entered in this wizard, so that SNI can hit the corresponding certificate and reverse proxy rules" "2) Каждое резервное доменное имя должно соответствовать доменному имени, введенному в этом мастере, чтобы SNI мог соответствовать соответствующему сертификату и правилам защиты от подмены.")"
    echo -e "$(localized_text "3) 如业务强依赖真实访客IP，请后续再单独启用 PROXY Protocol 高阶方案" "3) If your business relies heavily on real visitor IP, please enable the PROXY Protocol high-end solution later." "3) Если ваш бизнес в значительной степени зависит от реального IP-адреса посетителя, пожалуйста, включите высокопроизводительное решение протокола PROXY позже.")"
}

# ---------------------------------------------------------
# 新增功能：CF DNS 证书二次维护菜单
# ---------------------------------------------------------
