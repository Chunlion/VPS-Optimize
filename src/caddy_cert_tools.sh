# shellcheck shell=bash
# Caddy certificate viewing, deletion, config cleanup, and insecure upstream helpers.

func_view_caddy_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔑 Caddy 已申请证书路径查询${PLAIN}" "${BOLD}🔑 Caddy Applied certificate path query${PLAIN}" "${BOLD}🔑 Caddy Запрос пути примененного сертификата${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    if [[ ! -f "/etc/caddy/Caddyfile" ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 /etc/caddy/Caddyfile，请先配置反代！${PLAIN}" "${RED}❌ /etc/caddy/Caddyfile is not detected, please configure reverse proxy first!${PLAIN}" "${RED}❌ /etc/caddy/Caddyfile не обнаружен, сначала настройте обратный прокси-сервер!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    
    # 提取 Caddyfile 与 conf.d 中的域名 (排除注释，简单匹配)
    local domains
    domains=$(cat /etc/caddy/Caddyfile /etc/caddy/conf.d/*.caddy 2>/dev/null | grep -vE '^[[:space:]]*#' | grep '{' | awk '{print $1}' | tr -d '{')
    
    if [[ -z "$domains" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ Caddyfile 中没有配置明确的域名。${PLAIN}" "${YELLOW}⚠️ There is no clear domain configured in Caddyfile.${PLAIN}" "${YELLOW}⚠️ В файле Caddy нет четкого доменного имени.${PLAIN}")"
    else
        # Caddy 默认的证书存储根路径
        local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
        [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"
        
        for domain in $domains; do
            # 过滤掉本地回环等无意义的块
            if [[ "$domain" == ":80" || "$domain" == "localhost" ]]; then continue; fi
            
            echo -e "$(localized_text "${BLUE}🌐 域名: ${BOLD}${domain}${PLAIN}" "${BLUE}🌐 domain: ${domain}${PLAIN}" "${BLUE}🌐 Доменное имя: ${domain}${PLAIN}")"
            
            local found=false
            if [[ -d "$cert_root" ]]; then
                # 递归查找对应的 .crt 和 .key 文件
                local cert_file
                local key_file
                cert_file=$(find "$cert_root" -name "${domain}.crt" -print -quit 2>/dev/null)
                key_file=$(find "$cert_root" -name "${domain}.key" -print -quit 2>/dev/null)
                
                if [[ -n "$cert_file" && -n "$key_file" ]]; then
                    echo -e "$(localized_text "   ${GREEN}📄 公钥 (CRT):${PLAIN} ${cert_file}" "${GREEN}📄 Public key (CRT):${PLAIN} ${cert_file}" "${GREEN}📄 Открытый ключ (CRT):${PLAIN} ${cert_file}")"
                    echo -e "$(localized_text "   ${YELLOW}🔑 密钥 (KEY):${PLAIN} ${key_file}" "${YELLOW}🔑 Key (KEY):${PLAIN} ${key_file}" "${YELLOW}🔑 Ключ (KEY):${PLAIN} ${key_file}")"
                    found=true
                fi
            fi
            
            if ! $found; then
                echo -e "$(localized_text "   ${RED}❌ 未找到证书，可能尚未签发成功或路径异常。${PLAIN}" "${RED}❌ The certificate was not found. It may not have been successfully issued or the path may be abnormal.${PLAIN}" "${RED}❌ Сертификат не найден. Возможно, он не был успешно выдан или путь может быть ненормальным.${PLAIN}")"
            fi
            echo -e "------------------------------------------------"
        done
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

# ---------------------------------------------------------
# 新增功能：清空 Caddy 配置文件 (适配模块化安全架构)
# ---------------------------------------------------------

func_caddy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧹 清空 Caddy 配置文件 (模块化版本)${PLAIN}" "${BOLD}🧹 Clear Caddy configuration file (modular version)${PLAIN}" "${BOLD}🧹 Очистить файл конфигурации Caddy (модульная версия)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 检查主文件与模块化目录是否存在
    if [[ -f /etc/caddy/Caddyfile ]] || [[ -d /etc/caddy/conf.d ]]; then
        echo -e "$(localized_text "${YELLOW}将清空 /etc/caddy/conf.d/*.caddy，并重置 /etc/caddy/Caddyfile 为模块化初始状态。${PLAIN}" "${YELLOW}Will clear /etc/caddy/conf.d/*.caddy and reset /etc/caddy/Caddyfile to the modular initial state.${PLAIN}" "${YELLOW}очистит /etc/caddy/conf.d/*.caddy и сбросит /etc/caddy/Caddyfile в модульное исходное состояние.${PLAIN}")"
        if confirm_danger "$(localized_text "清空 Caddy 反代配置" "Clear Caddy reverse proxy configuration" "Очистить конфигурацию обратного прокси-сервера Caddy.")" "$(localized_text "所有独立 Caddy 反代配置会失效，相关网站/面板可能暂时打不开。" "All independent Caddy reverse proxy configurations will become invalid, and related websites/panels may not be opened temporarily." "Все независимые конфигурации обратный прокси Caddy станут недействительными, а соответствующие веб-сайты/панели могут быть временно недоступны.")" "$(localized_text "脚本会备份 Caddyfile 和 conf.d 目录，可按备份路径手动恢复。" "The script will back up the Caddyfile and conf.d directories, which can be restored manually according to the backup path." "Скрипт создаст резервную копию каталогов Caddyfile и conf.d, которые можно восстановить вручную в соответствии с путем резервной копии.")"; then
            
            # 1. 备份现有的模块化配置目录
            if [[ -d /etc/caddy/conf.d ]]; then
                local backup_dir="/etc/caddy/conf.d_bak_$(date +%s)"
                cp -r /etc/caddy/conf.d "$backup_dir" 2>/dev/null
                echo -e "$(localized_text "${BLUE}已备份原配置目录为 $backup_dir${PLAIN}" "${BLUE}Has backed up the original configuration directory to $backup_dir${PLAIN}" "${BLUE}создал резервную копию исходного каталога конфигурации в $backup_dir.${PLAIN}")"
                
                # 精准隔离所有 .caddy 配置文件，避免不可逆删除。
                while IFS= read -r caddy_conf; do
                    mv "$caddy_conf" "$backup_dir/" 2>/dev/null || true
                done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name '*.caddy' 2>/dev/null | sort)
            fi
            
            # 2. 守护主文件架构，重置为极简模式并注入模块化指令
            cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null
            echo "# Caddyfile Cleared and Reset to Modular Architecture" > /etc/caddy/Caddyfile
            echo "import conf.d/*" >> /etc/caddy/Caddyfile
            
            # 3. 重启生效
            systemctl restart caddy >/dev/null 2>&1
            echo -e "$(localized_text "${GREEN}✅ 所有反代配置已清空并成功重载！系统已恢复纯净的模块化初始状态。${PLAIN}" "${GREEN}✅ All reverse proxy configurations have been cleared and reloaded successfully! The system has been restored to its pristine, modular initial state.${PLAIN}" "${GREEN}✅ Все конфигурации обратный прокси очищены и успешно перезагружены! Система была восстановлена ​​в первозданном, модульном исходном состоянии.${PLAIN}")"
        else
            echo -e "$(localized_text "${BLUE}已取消清空操作。${PLAIN}" "${BLUE}The clearing operation has been canceled.${PLAIN}" "${BLUE}Операция очистки была отменена.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "${RED}❌ 未检测到 Caddy 配置文件或模块化目录！${PLAIN}" "${RED}❌ No Caddy configuration file or modular directory detected!${PLAIN}" "${RED}❌ Файл конфигурации или модульный каталог Caddy не обнаружен!${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

func_caddy_delete_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}清理域名证书与配置${PLAIN}" "${BOLD}Clean up domain certificate and configuration${PLAIN}" "${BOLD}Очистка сертификата и конфигурации доменного имени${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}将隔离指定域名的证书和配置，并清理 acme.sh 残留。${PLAIN}" "${YELLOW}Will isolate the certificate and configuration of the specified domain and clean up the residue of acme.sh.${PLAIN}" "${YELLOW}изолирует сертификат и конфигурацию указанного доменного имени и очистит остатки acme.sh.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    read_trimmed domain "$(localized_text "👉 请输入要清理的域名（例如 panel.site.com）: " "👉 Please enter the domain to be cleaned (for example panel.site.com):" "👉 Введите имя домена, который необходимо очистить (например, Panel.site.com):")"
    domain=$(normalize_domain_input "$domain")
    if [[ -z "$domain" ]]; then
        echo -e "$(localized_text "${RED}❌ 域名不能为空！${PLAIN}" "${RED}❌ The domain cannot be empty!${PLAIN}" "${RED}❌ Доменное имя не может быть пустым!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    if ! is_valid_domain "$domain"; then
        echo -e "$(localized_text "${RED}❌ 域名格式无效，已取消清理。${PLAIN}" "${RED}❌ The domain format is invalid and the cleanup has been cancelled.${PLAIN}" "${RED}❌ Неверный формат имени домена, очистка отменена.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "\n${CYAN}▶ 正在清理域名证书与配置...${PLAIN}" "\n${CYAN}▶ Cleaning up domain certificate and configuration...${PLAIN}" "\n${CYAN}▶ Очистка сертификата и конфигурации доменного имени...${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}此操作会移走该域名的证书与配置，相关网站会暂时不可用。${PLAIN}" "${YELLOW}This operation will remove the certificate and configuration of the domain, and the related website will be temporarily unavailable.${PLAIN}" "${YELLOW}Эта операция приведет к удалению сертификата и конфигурации доменного имени, а соответствующий веб-сайт будет временно недоступен.${PLAIN}")"
    echo -e "$(localized_text "请确认操作...${PLAIN}" "Please confirm the operation...${PLAIN}" "Пожалуйста, подтвердите операцию...${PLAIN}")"
    if confirm_danger "$(localized_text "清理 ${domain} 的证书与配置" "Clean up the certificate and configuration of ${domain}" "Очистите сертификат и конфигурацию ${domain}.")" "$(localized_text "会停止 Caddy，隔离该域名证书、acme.sh 残留和 Caddy 配置，再启动 Caddy。" "Caddy will be stopped, the domain certificate, acme.sh residue and Caddy configuration will be isolated, and then Caddy will be started." "Caddy будет остановлен, сертификат доменного имени, остаток acme.sh и конфигурация Caddy будут изолированы, а затем будет запущен Caddy.")" "$(localized_text "请先确认已有系统快照或 Caddy 备份；清理后的证书需要重新签发。" "Please first confirm that you have a system snapshot or Caddy backup; the cleaned certificate needs to be re-issued." "Сначала подтвердите, что у вас есть снимок системы или резервная копия Caddy; очищенный сертификат необходимо перевыпустить.")"; then
        # 1. 停止 Caddy，强制释放 80/443 端口
        systemctl stop caddy >/dev/null 2>&1
        echo -e "$(localized_text "${GREEN}✅ [1/5] 已强制停止 Caddy 服务，释放网络端口。${PLAIN}" "${GREEN}✅ [1/5] The Caddy service has been forcibly stopped and the network port has been released.${PLAIN}" "${GREEN}✅ [1/5] Служба Caddy была принудительно остановлена, а сетевой порт освобожден.${PLAIN}")"
        
        # 2. 深度清理 Caddy 底层证书缓存
        local caddy_paths=("/var/lib/caddy/.local/share/caddy/certificates" "/root/.local/share/caddy/certificates")
        local caddy_found=false
        for cp in "${caddy_paths[@]}"; do
            if [[ -d "$cp" ]]; then
                local target=$(find "$cp" -type d -name "${domain}" -print -quit 2>/dev/null)
                if [[ -n "$target" ]]; then
                    quarantine_path "$target" "/root/vps-optimize-quarantine/caddy-certs" >/dev/null 2>&1 || true
                    caddy_found=true
                fi
            fi
        done
        if $caddy_found; then
            echo -e "$(localized_text "${GREEN}✅ [2/5] Caddy 引擎中关于 ${domain} 的密钥与证书已抹除。${PLAIN}" "${GREEN}✅ [2/5] The key and certificate related to ${domain} in the Caddy engine have been erased.${PLAIN}" "${GREEN}✅ [2/5] Ключ и сертификат, относящиеся к ${domain} в движке Caddy, были стерты.${PLAIN}")"
        else
            echo -e "$(localized_text "${BLUE}ℹ️ [2/5] 未在 Caddy 引擎中发现该域名的证书。${PLAIN}" "${BLUE}ℹ️ [2/5] The certificate for this domain was not found in the Caddy engine.${PLAIN}" "${BLUE}ℹ️ [2/5] Сертификат для этого доменного имени не найден в движке Caddy.${PLAIN}")"
        fi
        
        # 3. 清理 acme.sh 残留
        if [[ -d "/root/.acme.sh" ]]; then
            local acme_target=$(find "/root/.acme.sh" -type d -name "*${domain}*" -print -quit 2>/dev/null)
            if [[ -n "$acme_target" ]]; then
                quarantine_path "$acme_target" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ [3/5] 面板底层 (~/.acme.sh) 关于 ${domain} 的残留已抹除。${PLAIN}" "${GREEN}✅ [3/5] The remnants of ${domain} on the bottom layer of the panel (~/.acme.sh) have been erased.${PLAIN}" "${GREEN}✅ [3/5] Остатки ${domain} на нижнем слое панели (~/.acme.sh) стерты.${PLAIN}")"
            else
                echo -e "$(localized_text "${BLUE}ℹ️ [3/5] 未在 acme.sh 引擎中发现残留。${PLAIN}" "${BLUE}ℹ️ [3/5] No residue found in acme.sh engine.${PLAIN}" "${BLUE}ℹ️ [3/5] В двигателе acme.sh остатков не обнаружено.${PLAIN}")"
            fi
        else
            echo -e "$(localized_text "${BLUE}ℹ️ [3/5] 系统未安装独立 acme.sh 环境，已跳过。${PLAIN}" "${BLUE}ℹ️ [3/5] The independent acme.sh environment is not installed on the system and has been skipped.${PLAIN}" "${BLUE}ℹ️ [3/5] Независимая среда acme.sh не установлена в системе и пропущена.${PLAIN}")"
        fi
        
        # 4. 外科手术：模块化安全删除
        local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$domain_conf" ]]; then
            echo -e "$(localized_text "${YELLOW}⏳ [4/5] 检测到专属配置文件，正在隔离...${PLAIN}" "${YELLOW}⏳ [4/5] Exclusive configuration file detected, isolating...${PLAIN}" "${YELLOW}⏳ [4/5] Обнаружен эксклюзивный файл конфигурации, изолирующий...${PLAIN}")"
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ [4/5] 专属配置文件 ($domain_conf) 已隔离！${PLAIN}" "${GREEN}✅ [4/5] Exclusive profile ($domain_conf) is quarantined!${PLAIN}" "${GREEN}✅ [4/5] Эксклюзивный профиль ($domain_conf) помещен на карантин!${PLAIN}")"
        else
            echo -e "$(localized_text "${GREEN}✅ [4/5] 未发现该域名的专属配置文件。${PLAIN}" "${GREEN}✅ [4/5] No exclusive configuration file for this domain was found.${PLAIN}" "${GREEN}✅ [4/5] Не найден эксклюзивный файл конфигурации для этого доменного имени.${PLAIN}")"
        fi

        local shared_cert_file
        echo -e "$(localized_text "${YELLOW}⏳ [5/5] 正在隔离共享证书安装路径...${PLAIN}" "${YELLOW}⏳ [5/5] Isolating the shared certificate installation path...${PLAIN}" "${YELLOW}⏳ [5/5] Изолирование пути установки общего сертификата...${PLAIN}")"
        for shared_cert_file in "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.crt" "/root/cert/${domain}.key"; do
            if [[ -e "$shared_cert_file" || -L "$shared_cert_file" ]]; then
                quarantine_path "$shared_cert_file" "/etc/vps-optimize/quarantine/shared-certs" >/dev/null 2>&1 || true
                echo -e "$(localized_text "${GREEN}✅ 已隔离共享证书路径：${shared_cert_file}${PLAIN}" "${GREEN}✅ Isolated shared certificate path: ${shared_cert_file}${PLAIN}" "${GREEN}✅ Путь к изолированному общему сертификату: ${shared_cert_file}${PLAIN}")"
            fi
        done

        # 重启 Caddy 以加载干净的配置
        systemctl start caddy >/dev/null 2>&1
        generate_caddy_cf_manifest 2>/dev/null || true

        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}✅ 清理完成；相关配置和证书已移入隔离目录。${PLAIN}" "${GREEN}✅ Cleanup completed; related configurations and certificates have been moved to the isolation directory.${PLAIN}" "${GREEN}✅ Очистка завершена; связанные конфигурации и сертификаты были перемещены в каталог изоляции.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}操作已取消。${PLAIN}" "${BLUE}Operation has been cancelled.${PLAIN}" "${BLUE}Операция отменена.${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

# ---------------------------------------------------------
# 新增功能：独立追加 Caddy 跳过不安全证书反代块 (模块化版)
# ---------------------------------------------------------

func_caddy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🛡️ 独立配置：追加 Caddy 跳过证书验证反代${PLAIN}" "${BOLD}🛡️ Independent configuration: append Caddy to skip certificate verification and replace with${PLAIN}" "${BOLD}🛡️ Независимая конфигурация: добавьте Caddy, чтобы пропустить проверку сертификата, и замените на.${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "$(localized_text "${RED}❌ 未检测到 Caddy 配置文件，请先运行 [13] 安装 Caddy！${PLAIN}" "${RED}❌ The Caddy configuration file is not detected, please run [13] to install Caddy first!${PLAIN}" "${RED}❌ Файл конфигурации Caddy не обнаружен, пожалуйста, запустите [13], чтобы сначала установить Caddy!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    
    local domain
    local backend_addr port
    local backend_hostport
    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed domain "$(localized_text "👉 请输入解析后的域名 (如 panel.site.com): " "👉 Please enter the resolved domain (such as panel.site.com):" "👉 Введите разрешенное доменное имя (например, Panel.site.com):")"
    read_trimmed port "$(localized_text "👉 请输入面板 HTTPS 本地映射端口 (如 40000): " "👉 Please enter the panel HTTPS local mapping port (such as 40000):" "👉 Введите локальный порт сопоставления панели HTTPS (например, 40000):")"
    backend_addr=$(ask_with_default "$(localized_text "后端地址" "Backend address" "Внутренний адрес")" "127.0.0.1")
    backend_addr=$(normalize_backend_addr_input "$backend_addr")
    domain=$(normalize_domain_input "$domain")
    
    if ! is_valid_domain "$domain" || ! is_valid_port "$port" || ! is_valid_backend_addr "$backend_addr"; then
        echo -e "$(localized_text "${RED}❌ 域名为空或端口格式错误！已取消操作。${PLAIN}" "${RED}❌ The domain is empty or the port format is wrong! Operation canceled.${PLAIN}" "${RED}❌ Доменное имя пусто или неверный формат порта! Операция отменена.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
        return
    fi
    backend_hostport=$(format_hostport "$backend_addr" "$port")

    read_trimmed enable_ip_whitelist "$(localized_text "❓ 是否只允许指定 IP/CIDR 访问该域名？(y/N，默认 N): " "❓ Restrict this domain to specified IP/CIDR ranges? (y/N, default N): " "❓ Ограничить доступ к домену указанными IP/CIDR? (y/N, по умолчанию N): ")"
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "$(localized_text "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}" "${YELLOW}The current source IP of SSH may be: ${current_client_ip}. Please confirm that it has been added to the whitelist.${PLAIN}" "${YELLOW}Текущий исходный IP-адрес SSH может быть: ${current_client_ip}. Пожалуйста, подтвердите, что он был добавлен в белый список.${PLAIN}")"
        read_trimmed ip_whitelist_input "$(localized_text "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: " "Please enter the IP/CIDR that allows access to ${domain} (separate multiple by spaces or commas):" "Введите IP/CIDR, который разрешает доступ к ${domain} (разделяйте кратные пробелами или запятыми):")"
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "$(localized_text "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}" "${RED}❌ The whitelist is empty or has an incorrect format, and the operation has been cancelled.${PLAIN}" "${RED}❌ Белый список пуст или имеет неверный формат, и операция отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
            return
        fi
        append_vps_public_ips_to_whitelist ip_whitelist_array
        ip_whitelist_ranges=$(join_array_by_space "${ip_whitelist_array[@]}")
    else
        ip_whitelist_ranges=""
    fi
    
    # 确保主文件包含模块化目录
    grep -q "import conf.d/\*" /etc/caddy/Caddyfile || echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
    
    mkdir -p /etc/caddy/conf.d
    local conf_file="/etc/caddy/conf.d/${domain}.caddy"
    local backup_file=""
    if [[ -f "$conf_file" ]]; then
        backup_file="${conf_file}.bak_$(date +%s)"
        if ! cp -p "$conf_file" "$backup_file"; then
            echo -e "$(localized_text "${RED}❌ 现有配置备份失败，已取消操作。${PLAIN}" "${RED}❌ The existing configuration backup failed and the operation has been cancelled.${PLAIN}" "${RED}❌ Не удалось выполнить резервное копирование существующей конфигурации, и операция была отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
            return
        fi
    fi
    
    cat <<EOF > "$conf_file"
$domain {
$(caddy_ip_whitelist_block "$ip_whitelist_ranges")    reverse_proxy https://${backend_hostport} {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
EOF
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl reload caddy >/dev/null 2>&1
        echo -e "$(localized_text "${GREEN}✅ 独立跳过验证配置已成功建立并生效！${PLAIN}" "${GREEN}✅ The independent skip verification configuration has been successfully established and takes effect!${PLAIN}" "${GREEN}✅ Конфигурация независимой проверки пропуска успешно установлена и вступила в силу!${PLAIN}")"
        [[ -n "$ip_whitelist_ranges" ]] && echo -e "$(localized_text "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ IP whitelist enabled for ${domain}: ${ip_whitelist_ranges}${PLAIN}" "${GREEN}✅ Белый список IP-адресов включен для ${domain}: ${ip_whitelist_ranges}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 新配置语法错误，正在回滚...${PLAIN}" "${RED}❌ New configuration syntax error, rolling back...${PLAIN}" "${RED}❌ Синтаксическая ошибка новой конфигурации, откат...${PLAIN}")"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
        [[ -n "$backup_file" && -f "$backup_file" ]] && mv "$backup_file" "$conf_file"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 4. SSH 安全加固 (终极完美版：防截断、防覆盖、防 Socket 冲突)
# ---------------------------------------------------------
