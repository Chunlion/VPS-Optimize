# shellcheck shell=bash
# Cloudflare DNS and Caddy certificate maintenance menu wiring.

func_caddy_cf_maintenance_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}🛠️ 443 / Caddy / Cloudflare 维护中心${PLAIN}" "${BOLD}🛠️ 443 / Caddy / Cloudflare Maintenance Center${PLAIN}" "${BOLD}🛠️ 443 / Caddy / Cloudflare Центр технического обслуживания${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}用途：排查 443 链路、重签证书、修复软链接、隔离旧配置和回滚。${PLAIN}" "${YELLOW}Purpose: troubleshooting 443 links, re-signing certificates, repairing symlinks, isolating old configurations and rolling back.${PLAIN}" "${YELLOW}Назначение: устранение неполадок 443 ссылок, переподписка сертификатов, восстановление программных ссылок, изоляция старых конфигураций и откат.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}建议顺序：先 [1] 体检，再按异常选择证书或 Caddy 修复项。${PLAIN}" "${YELLOW}Recommended order: [1] health check first, then select the certificate or Caddy repair item according to the abnormality.${PLAIN}" "${YELLOW}Рекомендуемый порядок: [1] Сначала проверка состояния, затем выберите сертификат или элемент ремонта Caddy в соответствии с неисправностью.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 443 单入口常用${PLAIN}" "${BOLD}▶ 443 shared entry commonly used${PLAIN}" "${BOLD}▶ 443 Обычно используется с одним входом${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  1. 443 链路与安全体检${PLAIN}       ${YELLOW}(Nginx/Caddy/REALITY/面板/版本隐藏)${PLAIN}" "${GREEN}1. 443 Link and security health check (Nginx/Caddy/REALITY/panel/version hidden)${PLAIN}" "${GREEN}1. 443 проверка состояния канала и безопасности (Nginx/Caddy/REALITY/панель/версия скрыта)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 管理 443 网站/反代域名${PLAIN}    ${YELLOW}(新增/删除/查看，最常用)${PLAIN}" "${GREEN}2. Management 443 website/reverse domain (add/delete/view, most commonly used)${PLAIN}" "${GREEN}2. Веб-сайт Management 443/обратное доменное имя (добавление/удаление/просмотр, наиболее часто используемый)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 修改 443 分流参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}" "${GREEN}3. Modify 443 routing parameters   (Panel/Subscription/REALITY/Entry Port and Path)${PLAIN}" "${GREEN}3. Измените 443 параметра маршрутизации   (Панель/Подписка/REALITY/Входной порт и путь)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 重新应用上次 443 配置${PLAIN}     ${YELLOW}(读取 sni-stack.env 重建配置)${PLAIN}" "${GREEN}4. Reapply the last 443 configuration (read sni-stack.env and rebuild the configuration)${PLAIN}" "${GREEN}4. Повторно примените последнюю конфигурацию 443 (прочитайте sni-stack.env и перестройте конфигурацию)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  5. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}" "${GREEN}5. Subscription link / External Proxy prompt (check whether the node link outputs public port 443)${PLAIN}" "${GREEN}5. Ссылка на подписку/запрос внешнего прокси (проверьте, выводит ли ссылка узла публичный порт 443)${PLAIN}")"
        echo -e "$(localized_text "${RED}  6. 回滚 443 单入口配置${PLAIN}       ${YELLOW}(从最近备份恢复)${PLAIN}" "${RED}6. Rollback 443 Shared entry configuration   (restore from recent backup)${PLAIN}" "${RED}6. Откат 443 Конфигурация с общей точкой входа (восстановление из последней резервной копии)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ 证书与 Cloudflare${PLAIN}" "${BOLD}▶ Certificate and Cloudflare${PLAIN}" "${BOLD}▶ Сертификат и Cloudflare${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  7. 查看已管理域名 / 证书路径${PLAIN}" "${GREEN}7. View the managed domain/certificate path${PLAIN}" "${GREEN}7. Просмотрите имя управляемого домена/путь сертификата.${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  8. 更新 Cloudflare API Token${PLAIN}" "${GREEN}8. Update Cloudflare API Token${PLAIN}" "${GREEN}8. Обновите Cloudflare API-токен${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  9. 重新签发某个域名证书${PLAIN}" "${GREEN}9. Reissue a domain certificate${PLAIN}" "${GREEN}9. Перевыпустите сертификат доменного имени.${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 10. 重建 /root/cert 证书软链接${PLAIN}" "${GREEN}10. Rebuild /root/cert certificate symlink${PLAIN}" "${GREEN}10. Перестройте программную ссылку сертификата /root/cert.${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 11. 重建证书清单文件${PLAIN}" "${GREEN}11. Rebuild the certificate list file${PLAIN}" "${GREEN}11. Перестройте файл списка сертификатов.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BOLD}${BLUE}▶ Caddy 修复与清理${PLAIN}" "${BOLD}▶ Caddy Repair and Cleanup${PLAIN}" "${BOLD}▶ Caddy Ремонт и очистка${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 12. 校验并重载 Caddy${PLAIN}" "${GREEN}12. Verify and reload Caddy${PLAIN}" "${GREEN}12. Проверьте и перезагрузите Caddy.${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 13. Caddy/证书一键体检${PLAIN}       ${YELLOW}(Token/证书/监听/后端)${PLAIN}" "${GREEN}13. Caddy/certificate one-click health check (Token/certificate/listening/backend)${PLAIN}" "${GREEN}13. Caddy/сертификат, проверка состояния в один клик (токен/сертификат/прослушивание/бэкенд)${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 14. 一键自动修复常见问题${PLAIN}" "${GREEN}14. One-click automatic repair of common problems${PLAIN}" "${GREEN}14. Автоматическое устранение распространенных проблем в один клик${PLAIN}")"
        echo -e "$(localized_text "${GREEN} 15. 隔离旧 Caddy 配置${PLAIN}        ${YELLOW}(避免抢占 443)${PLAIN}" "${GREEN}15. Isolate the old Caddy and configure (avoid preemption 443)${PLAIN}" "${GREEN}15. Изолируйте старый Caddy и настройте (избегайте вытеснения 443)${PLAIN}")"
        echo -e "$(localized_text "${RED} 16. 隔离某个域名的 Caddy 配置与证书${PLAIN}" "${RED}16. Isolate a domain Caddy configuration and certificate${PLAIN}" "${RED}16. Изолируйте конфигурацию доменного имени Caddy и сертификат.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local m_choice
        read_trimmed m_choice "$(localized_text "👉 请选择操作: " "👉 Please select an operation:" "👉 Пожалуйста, выберите операцию:")"

        case "$m_choice" in
            1) m_choice=11 ;;
            2) m_choice=15 ;;
            3) m_choice=16 ;;
            4) m_choice=12 ;;
            5) m_choice=13 ;;
            6) m_choice=14 ;;
            7) m_choice=1 ;;
            8) m_choice=2 ;;
            9) m_choice=3 ;;
            10) m_choice=4 ;;
            11) m_choice=7 ;;
            12) m_choice=6 ;;
            13) m_choice=8 ;;
            14) m_choice=9 ;;
            15) m_choice=10 ;;
            16) m_choice=5 ;;
        esac

        case $m_choice in
            16)
                edit_sni_stack_runtime_profile
                ;;

            1)
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${CYAN}👇 当前清单内容：${PLAIN}" "${CYAN}👇 Current list content:${PLAIN}" "${CYAN}👇 Текущее содержимое списка:${PLAIN}")"
                cat /root/cert/caddy_cf_manifest.txt 2>/dev/null
                ;;

            2)
                local new_token escaped_token
                mkdir -p /root/.config/vps-panel
                chmod 700 /root/.config/vps-panel
                echo -e "$(localized_text "${CYAN}👇 请输入新的 Cloudflare API Token${PLAIN}" "${CYAN}👇 Please enter the new Cloudflare API Token${PLAIN}" "${CYAN}👇 Введите новый токен API Cloudflare.${PLAIN}")"
                read_secret_trimmed new_token "CF Token: "
                if [[ -z "$new_token" || ${#new_token} -lt 20 ]]; then
                    echo -e "$(localized_text "${RED}❌ Token 长度异常，更新取消。${PLAIN}" "${RED}❌ Token length is abnormal and the update is cancelled.${PLAIN}" "${RED}❌ Неверная длина токена, обновление отменено.${PLAIN}")"
                else
                    echo -e "$(localized_text "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}" "${CYAN}▶ Verifying online Cloudflare Token...${PLAIN}" "${CYAN}▶ Проверка токена Cloudflare онлайн...${PLAIN}")"
                    verify_cf_token_online "$new_token"
                    local verify_rc=$?
                    if [[ "$verify_rc" -eq 1 ]]; then
                        echo -e "$(localized_text "${RED}❌ Token 在线校验失败，未写入。${PLAIN}" "${RED}❌ Token failed online verification and was not written.${PLAIN}" "${RED}❌ Токен не прошел онлайн-проверку и не был записан.${PLAIN}")"
                        echo -e "$(localized_text "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}" "${YELLOW}Requires permissions: Zone.DNS.Edit + Zone.Zone.Read${PLAIN}" "${YELLOW}требуются разрешения: Zone.DNS.Edit + Zone.Zone.Read.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    elif [[ "$verify_rc" -eq 2 ]]; then
                        echo -e "$(localized_text "${YELLOW}⚠️ 未安装 curl，跳过在线校验，继续写入。${PLAIN}" "${YELLOW}⚠️ curl is not installed, skip online verification and continue writing.${PLAIN}" "${YELLOW}⚠️ curl не установлен, пропустите онлайн-проверку и продолжайте писать.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${GREEN}✅ Token 校验通过。${PLAIN}" "${GREEN}✅ Token verification passed.${PLAIN}" "${GREEN}✅ Проверка токена пройдена.${PLAIN}")"
                    fi

                    escaped_token=${new_token//\'/\'"\'"\'}
                    printf "CF_Token='%s'\n" "$escaped_token" > /root/.config/vps-panel/cloudflare.env
                    chmod 600 /root/.config/vps-panel/cloudflare.env
                    echo -e "$(localized_text "${GREEN}✅ Cloudflare Token 已更新。${PLAIN}" "${GREEN}✅ Cloudflare Token has been updated.${PLAIN}" "${GREEN}✅ Cloudflare Токен обновлен.${PLAIN}")"
                fi
                ;;

            3)
                local domain
                local acme_bin="/root/.acme.sh/acme.sh"
                local cf_env_file="/root/.config/vps-panel/cloudflare.env"

                read_trimmed domain "$(localized_text "👉 请输入要重签的域名: " "👉 Please enter the domain you want to re-sign:" "👉 Пожалуйста, введите доменное имя, которое вы хотите переподписать:")"
                domain=$(normalize_domain_input "$domain")
                if ! is_valid_domain "$domain"; then
                    echo -e "$(localized_text "${RED}❌ 域名格式无效。${PLAIN}" "${RED}❌ The domain format is invalid.${PLAIN}" "${RED}❌ Неверный формат доменного имени.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "$(localized_text "${RED}❌ 未检测到 acme.sh，请先运行主菜单 [19] -> [2] 首次配置 443 单入口。${PLAIN}" "${RED}❌ acme.sh is not detected, please run the main menu [19] -> [2] first to configure 443 shared entry.${PLAIN}" "${RED}❌ acme.sh не обнаружен, запустите главное меню [19] -> [2], чтобы настроить общую запись 443 в первый раз.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi
                if [[ ! -f "$cf_env_file" ]]; then
                    echo -e "$(localized_text "${RED}❌ 未检测到 Cloudflare Token，请先执行本菜单 [2]。${PLAIN}" "${RED}❌ Cloudflare Token is not detected, please execute this menu [2] first.${PLAIN}" "${RED}❌ Cloudflare Токен не обнаружен, сначала откройте это меню [2].${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                # shellcheck disable=SC1090
                source "$cf_env_file"
                confirm_risk_action "$(localized_text "重签并安装 ${domain} 的证书" "Re-sign and install the certificate of ${domain}" "Переподпишите и установите сертификат ${domain}.")" \
                    "$(localized_text "acme.sh 证书缓存、/etc/caddy/certs 和 /root/cert 软链接" "acme.sh certificate cache, /etc/caddy/certs and /root/cert symlinks" "Кэш сертификатов acme.sh, символическая ссылка /etc/caddy/certs и /root/cert")" \
                    "$(localized_text "使用现有 Caddy/证书备份恢复，或重新运行证书维护菜单签发" "Use the existing Caddy/certificate backup to restore, or re-run the certificate maintenance menu to issue" "Используйте существующую резервную копию Caddy/сертификата для восстановления или повторно запустите меню обслуживания сертификата для выдачи.")" \
                    "$(localized_text "确认域名 DNS 已解析，Cloudflare Token 权限正确。" "Confirm that the domain DNS has been resolved and the Cloudflare Token permissions are correct." "Убедитесь, что доменное имя DNS разрешено и разрешения токена Cloudflare верны.")" || {
                    echo -e "$(localized_text "${BLUE}已取消证书重签。${PLAIN}" "${BLUE}Certificate re-signing has been canceled.${PLAIN}" "${BLUE}Переподписка сертификата отменена.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                }
                echo -e "$(localized_text "${CYAN}▶ 正在重签证书: ${domain}${PLAIN}" "${CYAN}▶ Re-issuing certificate: ${domain}${PLAIN}" "${CYAN}▶ Перевыпуск сертификата: ${domain}${PLAIN}")"

                if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                    echo -e "$(localized_text "${RED}❌ 证书签发失败：${domain}${PLAIN}" "${RED}❌ Certificate issuance failed: ${domain}${PLAIN}" "${RED}❌ Не удалось выдать сертификат: ${domain}.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}   提示：建议先执行本菜单 [14] 自动修复再重试。${PLAIN}" "${YELLOW}Tip: It is recommended to perform automatic repair in this menu [14] and then try again.${PLAIN}" "${YELLOW}Совет: рекомендуется выполнить автоматическое восстановление в этом меню [14], а затем повторить попытку.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                mkdir -p /etc/caddy/certs /root/cert
                if ! "$acme_bin" --install-cert -d "$domain" --ecc \
                    --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                    --key-file "/etc/caddy/certs/${domain}.key" \
                    --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
                    echo -e "$(localized_text "${RED}❌ 证书安装失败：${domain}${PLAIN}" "${RED}❌ Certificate installation failed: ${domain}${PLAIN}" "${RED}❌ Не удалось установить сертификат: ${domain}.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if id caddy >/dev/null 2>&1; then
                    chown root:caddy "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" >/dev/null 2>&1
                    chmod 640 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                else
                    chmod 600 "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key"
                fi

                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${GREEN}✅ 重签完成并已更新 /root/cert 软链接。${PLAIN}" "${GREEN}✅ The re-signing is completed and the /root/cert symlink has been updated.${PLAIN}" "${GREEN}✅ Переподписка завершена, символическая ссылка /root/cert обновлена.${PLAIN}")"
                ;;

            4)
                local link_mode domain
                mkdir -p /root/cert
                read_trimmed link_mode "$(localized_text "❓ 重建全部链接还是单域名？(all/one): " "❓ Rebuild all links or a single domain? (all/one):" "❓Перестроить все ссылки или одно доменное имя? (все/один):")"

                if [[ "$link_mode" == "all" ]]; then
                    local relink_count=0
                    if [[ -d /etc/caddy/certs ]]; then
                        while IFS= read -r cert_path; do
                            domain=$(basename "$cert_path" .crt)
                            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                                ((relink_count++))
                            fi
                        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
                    fi
                    generate_caddy_cf_manifest
                    echo -e "$(localized_text "${GREEN}✅ 已重建 ${relink_count} 个域名的证书软链接。${PLAIN}" "${GREEN}✅ The certificate symlinks of ${relink_count} domains have been rebuilt.${PLAIN}" "${GREEN}✅ символическая ссылка сертификатов доменных имен ${relink_count} были перестроены.${PLAIN}")"
                else
                    read_trimmed domain "$(localized_text "👉 请输入域名: " "👉 Please enter domain:" "👉 Пожалуйста, введите доменное имя:")"
                    domain=$(normalize_domain_input "$domain")
                    if ! is_valid_domain "$domain"; then
                        echo -e "$(localized_text "${RED}❌ 域名格式无效。${PLAIN}" "${RED}❌ The domain format is invalid.${PLAIN}" "${RED}❌ Неверный формат доменного имени.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    fi
                    if [[ -f "/etc/caddy/certs/${domain}.crt" && -f "/etc/caddy/certs/${domain}.key" ]]; then
                        ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                        ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                        generate_caddy_cf_manifest
                        echo -e "$(localized_text "${GREEN}✅ 软链接已重建：/root/cert/${domain}.crt 与 /root/cert/${domain}.key${PLAIN}" "${GREEN}✅ symlink has been rebuilt: /root/cert/${domain}.crt and /root/cert/${domain}.key${PLAIN}" "${GREEN}✅ символическая ссылка была перестроена: /root/cert/${domain}.crt и /root/cert/${domain}.key.${PLAIN}")"
                    else
                        echo -e "$(localized_text "${RED}❌ 未找到该域名证书文件。${PLAIN}" "${RED}❌ The domain certificate file was not found.${PLAIN}" "${RED}❌ Файл сертификата доменного имени не найден.${PLAIN}")"
                    fi
                fi
                ;;

            5)
                local domain purge_acme
                read_trimmed domain "$(localized_text "👉 请输入要隔离的域名: " "👉 Please enter the domain to be isolated:" "👉 Пожалуйста, введите доменное имя, которое необходимо изолировать:")"
                domain=$(normalize_domain_input "$domain")
                if ! is_valid_domain "$domain"; then
                    echo -e "$(localized_text "${RED}❌ 域名格式无效。${PLAIN}" "${RED}❌ The domain format is invalid.${PLAIN}" "${RED}❌ Неверный формат доменного имени.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                if ! confirm_risk_action "$(localized_text "隔离 ${domain} 的配置与证书" "Isolate the configuration and certificate of ${domain}" "Изолируйте конфигурацию и сертификат ${domain}.")" \
                    "$(localized_text "Caddy 配置、证书文件和可选 acme.sh 历史记录" "Caddy configuration, certificate files, and optional acme.sh history" "Конфигурация Caddy, файлы сертификатов и дополнительная история acme.sh.")" \
                    "$(localized_text "从隔离目录手动移回，或重新签发证书并恢复 Caddy 配置" "Manually move back from the quarantine directory, or reissue the certificate and restore the Caddy configuration" "Вручную вернитесь из каталога карантина или перевыпустите сертификат и восстановите конфигурацию Caddy.")" \
                    "$(localized_text "确认该域名不再承载线上服务，或已经准备好重新签发。" "Confirm that the domain no longer hosts online services or is ready for re-issuance." "Подтвердите, что доменное имя больше не размещает онлайн-сервисы или готово к перевыпуску.")"; then
                    echo -e "$(localized_text "${BLUE}已取消隔离。${PLAIN}" "${BLUE}Has been cancelled.${PLAIN}" "${BLUE}отменен.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                local domain_quarantine_dir="/etc/vps-optimize/quarantine/caddy-domain-${domain}-$(date +%s)"
                mkdir -p "$domain_quarantine_dir"
                quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true

                read_trimmed purge_acme "$(localized_text "❓ 是否同时删除 acme.sh 历史记录？(Y/n，默认 y，建议保留): " "❓ Do you want to delete the acme.sh history at the same time? (Y/n, default y, recommended to keep):" "❓ Хотите одновременно удалить историю acme.sh? (Да/нет, по умолчанию y, рекомендуется сохранить):")"
                if is_yes "$purge_acme"; then
                    /root/.acme.sh/acme.sh --remove -d "$domain" --ecc >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                fi

                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                fi
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${GREEN}✅ ${domain} 的 Caddy 配置与证书已隔离到：${domain_quarantine_dir}${PLAIN}" "${GREEN}✅ Caddy configuration and certificate of ${domain} have been isolated to: ${domain_quarantine_dir}${PLAIN}" "${GREEN}✅ Конфигурация Caddy и сертификат ${domain} изолированы от: ${domain_quarantine_dir}.${PLAIN}")"
                ;;

            6)
                caddy_format_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ Caddy 配置已格式化，校验通过并重启生效。${PLAIN}" "${GREEN}✅ Caddy configuration has been formatted, passed verification and will take effect after restarting.${PLAIN}" "${GREEN}✅ Конфигурация Caddy отформатирована, прошла проверку и вступит в силу после перезагрузки.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Caddy 配置校验失败，请检查 /etc/caddy/conf.d/*.caddy${PLAIN}" "${RED}❌ Caddy configuration validation failed, please check /etc/caddy/conf.d/*.caddy${PLAIN}" "${RED}❌ Caddy Проверка конфигурации не удалась, проверьте /etc/caddy/conf.d/*.caddy${PLAIN}")"
                fi
                ;;

            7)
                generate_caddy_cf_manifest
                echo -e "$(localized_text "${GREEN}✅ 清单已重建：/root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ List has been rebuilt: /root/cert/caddy_cf_manifest.txt${PLAIN}" "${GREEN}✅ Список был перестроен: /root/cert/caddy_cf_manifest.txt${PLAIN}")"
                ;;

            8)
                func_caddy_cf_health_check
                ;;

            9)
                func_caddy_cf_auto_fix
                ;;

            10)
                quarantine_legacy_caddy_443_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "$(localized_text "${GREEN}✅ 隔离完成，Caddy 已重载。${PLAIN}" "${GREEN}✅ Isolation completed, Caddy has been reloaded.${PLAIN}" "${GREEN}. Изоляция завершена, Caddy перезагружен.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ 当前 Caddy 配置校验失败，请先修复语法错误。${PLAIN}" "${RED}❌ The current Caddy configuration validation failed, please fix the syntax error first.${PLAIN}" "${RED}❌ Текущая проверка конфигурации Caddy не удалась, сначала исправьте синтаксическую ошибку.${PLAIN}")"
                fi
                ;;

            11)
                sni_stack_health_check
                ;;

            12)
                reapply_sni_stack_from_env
                ;;

            13)
                check_sni_stack_subscription_hint
                ;;

            14)
                rollback_sni_stack_config
                ;;

            15)
                manage_sni_stack_sites
                ;;

            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")" ;;
        esac

        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}

# ---------------------------------------------------------
# 新增功能：查看 Caddy 已申请证书路径
# ---------------------------------------------------------
