# shellcheck shell=bash
# Cloudflare DNS and Caddy certificate maintenance menu wiring.

func_caddy_cf_maintenance_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🛠️ 443 / Caddy / Cloudflare 维护中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}用途：排查 443 链路、重签证书、修复软链接、隔离旧配置和回滚。${PLAIN}"
        echo -e "${YELLOW}建议顺序：先 [1] 体检，再按异常选择证书或 Caddy 修复项。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 443 单入口常用${PLAIN}"
        echo -e "${GREEN}  1. 443 链路与安全体检${PLAIN}       ${YELLOW}(Nginx/Caddy/REALITY/面板/版本隐藏)${PLAIN}"
        echo -e "${GREEN}  2. 管理 443 网站/反代域名${PLAIN}    ${YELLOW}(新增/删除/查看，最常用)${PLAIN}"
        echo -e "${GREEN}  3. 修改 443 分流参数${PLAIN}         ${YELLOW}(面板/订阅/REALITY/入口端口与路径)${PLAIN}"
        echo -e "${GREEN}  4. 重新应用上次 443 配置${PLAIN}     ${YELLOW}(读取 sni-stack.env 重建配置)${PLAIN}"
        echo -e "${GREEN}  5. 订阅链接 / External Proxy 提示${PLAIN} ${YELLOW}(检查节点链接是否输出公网 443)${PLAIN}"
        echo -e "${RED}  6. 回滚 443 单入口配置${PLAIN}       ${YELLOW}(从最近备份恢复)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ 证书与 Cloudflare${PLAIN}"
        echo -e "${GREEN}  7. 查看已管理域名 / 证书路径${PLAIN}"
        echo -e "${GREEN}  8. 更新 Cloudflare API Token${PLAIN}"
        echo -e "${GREEN}  9. 重新签发某个域名证书${PLAIN}"
        echo -e "${GREEN} 10. 重建 /root/cert 证书软链接${PLAIN}"
        echo -e "${GREEN} 11. 重建证书清单文件${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${BOLD}${BLUE}▶ Caddy 修复与清理${PLAIN}"
        echo -e "${GREEN} 12. 校验并重载 Caddy${PLAIN}"
        echo -e "${GREEN} 13. Caddy/证书一键体检${PLAIN}       ${YELLOW}(Token/证书/监听/后端)${PLAIN}"
        echo -e "${GREEN} 14. 一键自动修复常见问题${PLAIN}"
        echo -e "${GREEN} 15. 隔离旧 Caddy 配置${PLAIN}        ${YELLOW}(避免抢占 443)${PLAIN}"
        echo -e "${RED} 16. 隔离某个域名的 Caddy 配置与证书${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        local m_choice
        read_trimmed m_choice "👉 请选择操作: "

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
                echo -e "${CYAN}👇 当前清单内容：${PLAIN}"
                cat /root/cert/caddy_cf_manifest.txt 2>/dev/null
                ;;

            2)
                local new_token escaped_token
                mkdir -p /root/.config/vps-panel
                chmod 700 /root/.config/vps-panel
                echo -e "${CYAN}👇 请输入新的 Cloudflare API Token${PLAIN}"
                read_secret_trimmed new_token "CF Token: "
                if [[ -z "$new_token" || ${#new_token} -lt 20 ]]; then
                    echo -e "${RED}❌ Token 长度异常，更新取消。${PLAIN}"
                else
                    echo -e "${CYAN}▶ 正在在线校验 Cloudflare Token...${PLAIN}"
                    verify_cf_token_online "$new_token"
                    local verify_rc=$?
                    if [[ "$verify_rc" -eq 1 ]]; then
                        echo -e "${RED}❌ Token 在线校验失败，未写入。${PLAIN}"
                        echo -e "${YELLOW}需要权限：Zone.DNS.Edit + Zone.Zone.Read${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    elif [[ "$verify_rc" -eq 2 ]]; then
                        echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验，继续写入。${PLAIN}"
                    else
                        echo -e "${GREEN}✅ Token 校验通过。${PLAIN}"
                    fi

                    escaped_token=${new_token//\'/\'"\'"\'}
                    printf "CF_Token='%s'\n" "$escaped_token" > /root/.config/vps-panel/cloudflare.env
                    chmod 600 /root/.config/vps-panel/cloudflare.env
                    echo -e "${GREEN}✅ Cloudflare Token 已更新。${PLAIN}"
                fi
                ;;

            3)
                local domain
                local acme_bin="/root/.acme.sh/acme.sh"
                local cf_env_file="/root/.config/vps-panel/cloudflare.env"

                read_trimmed domain "👉 请输入要重签的域名: "
                domain=$(normalize_domain_input "$domain")
                if ! is_valid_domain "$domain"; then
                    echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if [[ ! -x "$acme_bin" ]]; then
                    echo -e "${RED}❌ 未检测到 acme.sh，请先运行主菜单 [19] -> [2] 首次配置 443 单入口。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi
                if [[ ! -f "$cf_env_file" ]]; then
                    echo -e "${RED}❌ 未检测到 Cloudflare Token，请先执行本菜单 [2]。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                # shellcheck disable=SC1090
                source "$cf_env_file"
                confirm_risk_action "重签并安装 ${domain} 的证书" \
                    "acme.sh 证书缓存、/etc/caddy/certs 和 /root/cert 软链接" \
                    "使用现有 Caddy/证书备份恢复，或重新运行证书维护菜单签发" \
                    "确认域名 DNS 已解析，Cloudflare Token 权限正确。" || {
                    echo -e "${BLUE}已取消证书重签。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                }
                echo -e "${CYAN}▶ 正在重签证书: ${domain}${PLAIN}"

                if ! issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                    echo -e "${RED}❌ 证书签发失败：${domain}${PLAIN}"
                    echo -e "${YELLOW}   提示：建议先执行本菜单 [13] 自动修复再重试。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                mkdir -p /etc/caddy/certs /root/cert
                if ! "$acme_bin" --install-cert -d "$domain" --ecc \
                    --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                    --key-file "/etc/caddy/certs/${domain}.key" \
                    --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1; then
                    echo -e "${RED}❌ 证书安装失败：${domain}${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
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
                echo -e "${GREEN}✅ 重签完成并已更新 /root/cert 软链接。${PLAIN}"
                ;;

            4)
                local link_mode domain
                mkdir -p /root/cert
                read_trimmed link_mode "❓ 重建全部链接还是单域名？(all/one): "

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
                    echo -e "${GREEN}✅ 已重建 ${relink_count} 个域名的证书软链接。${PLAIN}"
                else
                    read_trimmed domain "👉 请输入域名: "
                    domain=$(normalize_domain_input "$domain")
                    if ! is_valid_domain "$domain"; then
                        echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    if [[ -f "/etc/caddy/certs/${domain}.crt" && -f "/etc/caddy/certs/${domain}.key" ]]; then
                        ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                        ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                        generate_caddy_cf_manifest
                        echo -e "${GREEN}✅ 软链接已重建：/root/cert/${domain}.crt 与 /root/cert/${domain}.key${PLAIN}"
                    else
                        echo -e "${RED}❌ 未找到该域名证书文件。${PLAIN}"
                    fi
                fi
                ;;

            5)
                local domain purge_acme
                read_trimmed domain "👉 请输入要隔离的域名: "
                domain=$(normalize_domain_input "$domain")
                if ! is_valid_domain "$domain"; then
                    echo -e "${RED}❌ 域名格式无效。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                if ! confirm_risk_action "隔离 ${domain} 的配置与证书" \
                    "Caddy 配置、证书文件和可选 acme.sh 历史记录" \
                    "从隔离目录手动移回，或重新签发证书并恢复 Caddy 配置" \
                    "确认该域名不再承载线上服务，或已经准备好重新签发。"; then
                    echo -e "${BLUE}已取消隔离。${PLAIN}"
                    read -n 1 -s -r -p "按任意键继续..."
                    continue
                fi

                local domain_quarantine_dir="/etc/vps-optimize/quarantine/caddy-domain-${domain}-$(date +%s)"
                mkdir -p "$domain_quarantine_dir"
                quarantine_path "/etc/caddy/conf.d/${domain}.caddy" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/etc/caddy/certs/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.crt" "$domain_quarantine_dir" >/dev/null 2>&1 || true
                quarantine_path "/root/cert/${domain}.key" "$domain_quarantine_dir" >/dev/null 2>&1 || true

                read_trimmed purge_acme "❓ 是否同时删除 acme.sh 历史记录？(y/n，默认n，建议保留): "
                if is_yes "$purge_acme"; then
                    /root/.acme.sh/acme.sh --remove -d "$domain" --ecc >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                    quarantine_path "/root/.acme.sh/${domain}" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                fi

                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                fi
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ ${domain} 的 Caddy 配置与证书已隔离到：${domain_quarantine_dir}${PLAIN}"
                ;;

            6)
                caddy_format_configs
                if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                    systemctl restart caddy >/dev/null 2>&1
                    echo -e "${GREEN}✅ Caddy 配置已格式化，校验通过并重启生效。${PLAIN}"
                else
                    echo -e "${RED}❌ Caddy 配置校验失败，请检查 /etc/caddy/conf.d/*.caddy${PLAIN}"
                fi
                ;;

            7)
                generate_caddy_cf_manifest
                echo -e "${GREEN}✅ 清单已重建：/root/cert/caddy_cf_manifest.txt${PLAIN}"
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
                    echo -e "${GREEN}✅ 隔离完成，Caddy 已重载。${PLAIN}"
                else
                    echo -e "${RED}❌ 当前 Caddy 配置校验失败，请先修复语法错误。${PLAIN}"
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
            *) echo -e "${RED}❌ 无效选择！${PLAIN}" ;;
        esac

        echo ""
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# ---------------------------------------------------------
# 新增功能：查看 Caddy 已申请证书路径
# ---------------------------------------------------------
