# shellcheck shell=bash
# Cloudflare/Caddy certificate health checks and auto-fix workflows.

func_caddy_cf_health_check() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🩺 CF DNS 一键体检${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local ok_count=0
    local warn_count=0
    local err_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"

    echo -e "${YELLOW}▶ [1/5] 检查 Cloudflare Token ...${PLAIN}"
    if [[ -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            if command -v curl >/dev/null 2>&1; then
                local verify_resp
                verify_resp=$(curl -s --max-time 8 -H "Authorization: Bearer ${CF_Token}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null)
                if echo "$verify_resp" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
                    echo -e "${GREEN}✅ Cloudflare Token 校验通过${PLAIN}"
                    ((ok_count++))
                else
                    echo -e "${YELLOW}⚠️ Token 文件存在，但在线校验失败（可能权限不足/网络异常）${PLAIN}"
                    ((warn_count++))
                fi
            else
                echo -e "${YELLOW}⚠️ 未安装 curl，跳过在线校验。${PLAIN}"
                ((warn_count++))
            fi
        else
            echo -e "${RED}❌ Token 文件为空，请在维护菜单 [2] 重新写入。${PLAIN}"
            ((err_count++))
        fi
    else
        echo -e "${RED}❌ 未找到 Token 文件: ${cf_env_file}${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [2/5] 检查 Caddy 服务状态...${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if systemctl is-active --quiet caddy; then
            echo -e "${GREEN}✅ Caddy 服务运行中${PLAIN}"
            ((ok_count++))
        else
            echo -e "${YELLOW}⚠️ Caddy 已安装但未运行${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${RED}❌ 未安装 Caddy${PLAIN}"
        ((err_count++))
    fi

    echo -e "${YELLOW}▶ [3/5] 检查域名配置、证书与软链接...${PLAIN}"
    local domain_count=0
    if [[ -d /etc/caddy/conf.d ]]; then
        while IFS= read -r conf_file; do
            local domain
            local listen_addr
            local listen_port
            local listen_target
            local backend
            local backend_port
            local cert_file
            local key_file
            local cert_end
            local cert_ts
            local now_ts
            local days_left

            domain=$(basename "$conf_file" .caddy)
            cert_file="/etc/caddy/certs/${domain}.crt"
            key_file="/etc/caddy/certs/${domain}.key"

            if ! head -n1 "$conf_file" | grep -q '^https://'; then
                continue
            fi
            ((domain_count++))

            listen_addr=$(caddy_conf_site_bind_addr "$conf_file")
            listen_port=$(caddy_conf_site_listen_port "$conf_file")
            listen_target=$(caddy_conf_site_listen_target "$conf_file")
            backend=$(caddy_conf_first_reverse_proxy_target "$conf_file")
            backend_port=$(caddy_reverse_proxy_target_port "$backend")

            echo -e "${CYAN}  - 域名: ${domain}${PLAIN}"

            if [[ -f "$cert_file" && -f "$key_file" ]]; then
                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -n "$cert_end" && "$days_left" -gt 15 ]]; then
                    echo -e "    ${GREEN}证书状态: 正常 (剩余约 ${days_left} 天)${PLAIN}"
                    ((ok_count++))
                elif [[ -n "$cert_end" ]]; then
                    echo -e "    ${YELLOW}证书状态: 即将到期 (剩余约 ${days_left} 天)${PLAIN}"
                    ((warn_count++))
                else
                    echo -e "    ${RED}证书状态: 无法读取有效期${PLAIN}"
                    ((err_count++))
                fi
            else
                echo -e "    ${RED}证书状态: 缺失 /etc/caddy/certs/${domain}.crt|.key${PLAIN}"
                ((err_count++))
            fi

            if [[ -L "/root/cert/${domain}.crt" && -e "/root/cert/${domain}.crt" && -L "/root/cert/${domain}.key" && -e "/root/cert/${domain}.key" ]]; then
                echo -e "    ${GREEN}软链接状态: /root/cert 已正确挂载${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}软链接状态: 缺失或失效，建议执行维护菜单 [10] 重建软链接${PLAIN}"
                ((warn_count++))
            fi

            [[ -z "$listen_target" ]] && listen_target="未知"
            if [[ -n "$listen_port" ]] && caddy_listen_addr_port_is_visible "$listen_addr" "$listen_port"; then
                echo -e "    ${GREEN}监听状态: Caddy 本地端口 ${listen_target} 可见${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}监听状态: 未检测到 ${listen_target} 在监听${PLAIN}"
                ((warn_count++))
            fi

            [[ -z "$backend" ]] && backend="未知"
            if [[ -n "$backend_port" ]] && caddy_listen_port_is_visible "$backend_port"; then
                echo -e "    ${GREEN}后端状态: ${backend} 有服务监听${PLAIN}"
                ((ok_count++))
            else
                echo -e "    ${YELLOW}后端状态: ${backend} 未检测到监听${PLAIN}"
                ((warn_count++))
            fi
        done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)
    fi

    if [[ "$domain_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ 未检测到本功能托管的域名配置（https://域名:端口）。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [4/5] 检查清单文件...${PLAIN}"
    if [[ -f /root/cert/caddy_cf_manifest.txt ]]; then
        echo -e "${GREEN}✅ 清单文件存在: /root/cert/caddy_cf_manifest.txt${PLAIN}"
        ((ok_count++))
    else
        echo -e "${YELLOW}⚠️ 清单文件不存在，建议执行维护菜单 [11] 重建。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/5] 总结...${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${CYAN}体检结果: ${GREEN}${ok_count} 正常${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${err_count} 异常${PLAIN}"
    if [[ "$err_count" -gt 0 ]]; then
        echo -e "${RED}建议优先修复异常项，再继续业务切流。${PLAIN}"
    elif [[ "$warn_count" -gt 0 ]]; then
        echo -e "${YELLOW}当前可继续运行，但建议处理警告项提高稳定性。${PLAIN}"
    else
        echo -e "${GREEN}环境健康，可放心使用 Reality 回落 + Caddy 反代链路。${PLAIN}"
    fi
}

func_caddy_cf_auto_fix() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧰 CF DNS 一键自动修复${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local fixed_count=0
    local warn_count=0
    local fail_count=0
    local cf_env_file="/root/.config/vps-panel/cloudflare.env"
    local acme_bin="/root/.acme.sh/acme.sh"

    echo -e "${YELLOW}▶ [1/7] 修复基础目录与主配置...${PLAIN}"
    mkdir -p /root/cert /etc/caddy/certs /etc/caddy/conf.d /root/.config/vps-panel
    chmod 700 /root/.config/vps-panel >/dev/null 2>&1

    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<EOF > /etc/caddy/Caddyfile
# Managed by VPS-Optimize
import conf.d/*
EOF
        ((fixed_count++))
    elif ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        echo -e "\nimport conf.d/*" >> /etc/caddy/Caddyfile
        ((fixed_count++))
    fi

    echo -e "${YELLOW}▶ [1.5/7] 隔离旧式站点配置（避免抢占 443）...${PLAIN}"
    quarantine_legacy_caddy_443_configs

    echo -e "${YELLOW}▶ [2/7] 修复证书权限...${PLAIN}"
    if [[ -d /etc/caddy/certs ]]; then
        if id caddy >/dev/null 2>&1; then
            chown root:caddy /etc/caddy/certs/* 2>/dev/null
            chmod 640 /etc/caddy/certs/* 2>/dev/null
        else
            chmod 600 /etc/caddy/certs/* 2>/dev/null
        fi
        ((fixed_count++))
    else
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [3/7] 全量重建 /root/cert 软链接...${PLAIN}"
    local relink_count=0
    if [[ -d /etc/caddy/certs ]]; then
        while IFS= read -r cert_path; do
            local domain
            domain=$(basename "$cert_path" .crt)
            if [[ -f "/etc/caddy/certs/${domain}.key" ]]; then
                ln -sfn "/etc/caddy/certs/${domain}.crt" "/root/cert/${domain}.crt"
                ln -sfn "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.key"
                ((relink_count++))
            fi
        done < <(find /etc/caddy/certs -maxdepth 1 -type f -name "*.crt" 2>/dev/null | sort)
    fi
    echo -e "${GREEN}✅ 已重建 ${relink_count} 组软链接。${PLAIN}"
    ((fixed_count++))

    echo -e "${YELLOW}▶ [4/7] 近效期证书自动续签...${PLAIN}"
    local renew_count=0
    local renew_fail=0
    if [[ -x "$acme_bin" && -f "$cf_env_file" ]]; then
        # shellcheck disable=SC1090
        source "$cf_env_file"
        if [[ -n "$CF_Token" ]]; then
            while IFS= read -r conf_file; do
                local domain
                local cert_file
                local cert_end
                local cert_ts
                local now_ts
                local days_left

                domain=$(basename "$conf_file" .caddy)
                cert_file="/etc/caddy/certs/${domain}.crt"

                if ! head -n1 "$conf_file" | grep -q '^https://'; then
                    continue
                fi
                if [[ ! -f "$cert_file" ]]; then
                    continue
                fi

                cert_end=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2-)
                cert_ts=$(date -d "$cert_end" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (cert_ts - now_ts) / 86400 ))

                if [[ -z "$cert_end" || "$days_left" -le 15 ]]; then
                    if issue_cf_dns_cert_with_retry "$domain" "$CF_Token" "$acme_bin"; then
                        "$acme_bin" --install-cert -d "$domain" --ecc \
                            --fullchain-file "/etc/caddy/certs/${domain}.crt" \
                            --key-file "/etc/caddy/certs/${domain}.key" \
                            --reloadcmd "systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1 || true" >/dev/null 2>&1
                        ((renew_count++))
                    else
                        ((renew_fail++))
                    fi
                fi
            done < <(find /etc/caddy/conf.d -maxdepth 1 -type f -name "*.caddy" 2>/dev/null | sort)

            if [[ "$renew_fail" -gt 0 ]]; then
                ((warn_count+=renew_fail))
            fi
            echo -e "${GREEN}✅ 自动续签完成，成功 ${renew_count} 个，失败 ${renew_fail} 个。${PLAIN}"
            ((fixed_count++))
        else
            echo -e "${YELLOW}⚠️ Token 为空，跳过自动续签。${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${YELLOW}⚠️ 未检测到 acme.sh 或 Token 文件，跳过自动续签。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "${YELLOW}▶ [5/7] 校验并重载 Caddy...${PLAIN}"
    if command -v caddy >/dev/null 2>&1; then
        if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            systemctl enable caddy >/dev/null 2>&1
            if systemctl restart caddy >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Caddy 配置校验通过并重启成功。${PLAIN}"
                ((fixed_count++))
            else
                echo -e "${RED}❌ Caddy 重启失败，请手动检查日志。${PLAIN}"
                ((fail_count++))
            fi
        else
            echo -e "${RED}❌ Caddy 配置校验失败，未执行重启。${PLAIN}"
            ((fail_count++))
        fi
    else
        echo -e "${RED}❌ 未安装 Caddy，无法执行重载。${PLAIN}"
        ((fail_count++))
    fi

    echo -e "${YELLOW}▶ [6/7] 重建清单文件...${PLAIN}"
    generate_caddy_cf_manifest
    ((fixed_count++))
    echo -e "${GREEN}✅ 清单已重建: /root/cert/caddy_cf_manifest.txt${PLAIN}"

    echo -e "${YELLOW}▶ [7/7] 补全 acme 自动续签任务...${PLAIN}"
    if [[ -x "$acme_bin" ]]; then
        if "$acme_bin" --install-cronjob >/dev/null 2>&1; then
            echo -e "${GREEN}✅ acme.sh 自动续签任务已确认。${PLAIN}"
            ((fixed_count++))
        else
            echo -e "${YELLOW}⚠️ 无法确认 acme.sh 续签任务，请手动检查 crontab。${PLAIN}"
            ((warn_count++))
        fi
    else
        echo -e "${YELLOW}⚠️ 未安装 acme.sh，跳过续签任务补全。${PLAIN}"
        ((warn_count++))
    fi

    echo -e "------------------------------------------------"
    echo -e "${CYAN}自动修复结果: ${GREEN}${fixed_count} 已修复${PLAIN} / ${YELLOW}${warn_count} 警告${PLAIN} / ${RED}${fail_count} 失败${PLAIN}"
    if [[ "$fail_count" -gt 0 ]]; then
        echo -e "${RED}存在失败项，建议先执行维护菜单 [13] 体检复查并查看 caddy 日志。${PLAIN}"
    else
        echo -e "${GREEN}自动修复流程完成，可执行维护菜单 [13] 复检确认。${PLAIN}"
    fi
}
