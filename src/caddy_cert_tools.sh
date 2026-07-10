# shellcheck shell=bash
# Caddy certificate viewing, deletion, config cleanup, and insecure upstream helpers.

func_view_caddy_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 Caddy 已申请证书路径查询${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    if [[ ! -f "/etc/caddy/Caddyfile" ]]; then
        echo -e "${RED}❌ 未检测到 /etc/caddy/Caddyfile，请先配置反代！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 提取 Caddyfile 与 conf.d 中的域名 (排除注释，简单匹配)
    local domains
    domains=$(cat /etc/caddy/Caddyfile /etc/caddy/conf.d/*.caddy 2>/dev/null | grep -vE '^[[:space:]]*#' | grep '{' | awk '{print $1}' | tr -d '{')
    
    if [[ -z "$domains" ]]; then
        echo -e "${YELLOW}⚠️ Caddyfile 中没有配置明确的域名。${PLAIN}"
    else
        # Caddy 默认的证书存储根路径
        local cert_root="/var/lib/caddy/.local/share/caddy/certificates"
        [[ ! -d "$cert_root" ]] && cert_root="/root/.local/share/caddy/certificates"
        
        for domain in $domains; do
            # 过滤掉本地回环等无意义的块
            if [[ "$domain" == ":80" || "$domain" == "localhost" ]]; then continue; fi
            
            echo -e "${BLUE}🌐 域名: ${BOLD}${domain}${PLAIN}"
            
            local found=false
            if [[ -d "$cert_root" ]]; then
                # 递归查找对应的 .crt 和 .key 文件
                local cert_file
                local key_file
                cert_file=$(find "$cert_root" -name "${domain}.crt" -print -quit 2>/dev/null)
                key_file=$(find "$cert_root" -name "${domain}.key" -print -quit 2>/dev/null)
                
                if [[ -n "$cert_file" && -n "$key_file" ]]; then
                    echo -e "   ${GREEN}📄 公钥 (CRT):${PLAIN} ${cert_file}"
                    echo -e "   ${YELLOW}🔑 密钥 (KEY):${PLAIN} ${key_file}"
                    found=true
                fi
            fi
            
            if ! $found; then
                echo -e "   ${RED}❌ 未找到证书，可能尚未签发成功或路径异常。${PLAIN}"
            fi
            echo -e "------------------------------------------------"
        done
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：清空 Caddy 配置文件 (适配模块化安全架构)
# ---------------------------------------------------------

func_caddy_clear_config() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🧹 清空 Caddy 配置文件 (模块化版本)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 检查主文件与模块化目录是否存在
    if [[ -f /etc/caddy/Caddyfile ]] || [[ -d /etc/caddy/conf.d ]]; then
        echo -e "${YELLOW}将清空 /etc/caddy/conf.d/*.caddy，并重置 /etc/caddy/Caddyfile 为模块化初始状态。${PLAIN}"
        if confirm_danger "清空 Caddy 反代配置" "所有独立 Caddy 反代配置会失效，相关网站/面板可能暂时打不开。" "脚本会备份 Caddyfile 和 conf.d 目录，可按备份路径手动恢复。"; then
            
            # 1. 备份现有的模块化配置目录
            if [[ -d /etc/caddy/conf.d ]]; then
                local backup_dir="/etc/caddy/conf.d_bak_$(date +%s)"
                cp -r /etc/caddy/conf.d "$backup_dir" 2>/dev/null
                echo -e "${BLUE}已备份原配置目录为 $backup_dir${PLAIN}"
                
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
            echo -e "${GREEN}✅ 所有反代配置已清空并成功重载！系统已恢复纯净的模块化初始状态。${PLAIN}"
        else
            echo -e "${BLUE}已取消清空操作。${PLAIN}"
        fi
    else
        echo -e "${RED}❌ 未检测到 Caddy 配置文件或模块化目录！${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

func_caddy_delete_cert() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}清理域名证书与配置${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}将隔离指定域名的证书和配置，并清理 acme.sh 残留。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read_trimmed domain "👉 请输入要清理的域名（例如 panel.site.com）: "
    domain=$(normalize_domain_input "$domain")
    if [[ -z "$domain" ]]; then
        echo -e "${RED}❌ 域名不能为空！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    if ! is_valid_domain "$domain"; then
        echo -e "${RED}❌ 域名格式无效，已取消清理。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo -e "\n${CYAN}▶ 正在清理域名证书与配置...${PLAIN}"
    echo -e "${YELLOW}此操作会移走该域名的证书与配置，相关网站会暂时不可用。${PLAIN}"
    echo -e "请确认操作...${PLAIN}"
    if confirm_danger "清理 ${domain} 的证书与配置" "会停止 Caddy，隔离该域名证书、acme.sh 残留和 Caddy 配置，再启动 Caddy。" "请先确认已有系统快照或 Caddy 备份；清理后的证书需要重新签发。"; then
        # 1. 停止 Caddy，强制释放 80/443 端口
        systemctl stop caddy >/dev/null 2>&1
        echo -e "${GREEN}✅ [1/5] 已强制停止 Caddy 服务，释放网络端口。${PLAIN}"
        
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
            echo -e "${GREEN}✅ [2/5] Caddy 引擎中关于 ${domain} 的密钥与证书已抹除。${PLAIN}"
        else
            echo -e "${BLUE}ℹ️ [2/5] 未在 Caddy 引擎中发现该域名的证书。${PLAIN}"
        fi
        
        # 3. 清理 acme.sh 残留
        if [[ -d "/root/.acme.sh" ]]; then
            local acme_target=$(find "/root/.acme.sh" -type d -name "*${domain}*" -print -quit 2>/dev/null)
            if [[ -n "$acme_target" ]]; then
                quarantine_path "$acme_target" "/root/.acme.sh/_quarantine" >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ [3/5] 面板底层 (~/.acme.sh) 关于 ${domain} 的残留已抹除。${PLAIN}"
            else
                echo -e "${BLUE}ℹ️ [3/5] 未在 acme.sh 引擎中发现残留。${PLAIN}"
            fi
        else
            echo -e "${BLUE}ℹ️ [3/5] 系统未安装独立 acme.sh 环境，已跳过。${PLAIN}"
        fi
        
        # 4. 外科手术：模块化安全删除
        local domain_conf="/etc/caddy/conf.d/${domain}.caddy"
        if [[ -f "$domain_conf" ]]; then
            echo -e "${YELLOW}⏳ [4/5] 检测到专属配置文件，正在隔离...${PLAIN}"
            quarantine_path "$domain_conf" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ [4/5] 专属配置文件 ($domain_conf) 已隔离！${PLAIN}"
        else
            echo -e "${GREEN}✅ [4/5] 未发现该域名的专属配置文件。${PLAIN}"
        fi

        local shared_cert_file
        echo -e "${YELLOW}⏳ [5/5] 正在隔离共享证书安装路径...${PLAIN}"
        for shared_cert_file in "/etc/caddy/certs/${domain}.crt" "/etc/caddy/certs/${domain}.key" "/root/cert/${domain}.crt" "/root/cert/${domain}.key"; do
            if [[ -e "$shared_cert_file" || -L "$shared_cert_file" ]]; then
                quarantine_path "$shared_cert_file" "/etc/vps-optimize/quarantine/shared-certs" >/dev/null 2>&1 || true
                echo -e "${GREEN}✅ 已隔离共享证书路径：${shared_cert_file}${PLAIN}"
            fi
        done

        # 重启 Caddy 以加载干净的配置
        systemctl start caddy >/dev/null 2>&1
        generate_caddy_cf_manifest 2>/dev/null || true

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ 清理完成；相关配置和证书已移入隔离目录。${PLAIN}"
    else
        echo -e "${BLUE}操作已取消。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# ---------------------------------------------------------
# 新增功能：独立追加 Caddy 跳过不安全证书反代块 (模块化版)
# ---------------------------------------------------------

func_caddy_add_insecure() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ 独立配置：追加 Caddy 跳过证书验证反代${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        echo -e "${RED}❌ 未检测到 Caddy 配置文件，请先运行 [13] 安装 Caddy！${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    local domain
    local backend_addr port
    local backend_hostport
    local enable_ip_whitelist ip_whitelist_input ip_whitelist_ranges current_client_ip
    local -a ip_whitelist_array=()
    read_trimmed domain "👉 请输入解析后的域名 (如 panel.site.com): "
    read_trimmed port "👉 请输入面板 HTTPS 本地映射端口 (如 40000): "
    backend_addr=$(ask_with_default "后端地址" "127.0.0.1")
    backend_addr=$(normalize_backend_addr_input "$backend_addr")
    domain=$(normalize_domain_input "$domain")
    
    if ! is_valid_domain "$domain" || ! is_valid_port "$port" || ! is_valid_backend_addr "$backend_addr"; then
        echo -e "${RED}❌ 域名为空或端口格式错误！已取消操作。${PLAIN}"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    backend_hostport=$(format_hostport "$backend_addr" "$port")

    read_trimmed enable_ip_whitelist "❓ 是否只允许指定 IP/CIDR 访问该域名？(y/n，默认 n): "
    if [[ "$enable_ip_whitelist" =~ ^[Yy]$ ]]; then
        current_client_ip=$(detect_ssh_client_ip)
        [[ -n "$current_client_ip" ]] && echo -e "${YELLOW}当前 SSH 来源 IP 可能是：${current_client_ip}，请确认已加入白名单。${PLAIN}"
        read_trimmed ip_whitelist_input "请输入允许访问 ${domain} 的 IP/CIDR（多个用空格或英文逗号分隔）: "
        if ! normalize_ip_whitelist_input "$ip_whitelist_input" ip_whitelist_array; then
            echo -e "${RED}❌ 白名单为空或格式错误，已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键继续..."
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
            echo -e "${RED}❌ 现有配置备份失败，已取消操作。${PLAIN}"
            read -n 1 -s -r -p "按任意键继续..."
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
        echo -e "${GREEN}✅ 独立跳过验证配置已成功建立并生效！${PLAIN}"
        [[ -n "$ip_whitelist_ranges" ]] && echo -e "${GREEN}✅ 已为 ${domain} 启用 IP 白名单：${ip_whitelist_ranges}${PLAIN}"
    else
        echo -e "${RED}❌ 新配置语法错误，正在回滚...${PLAIN}"
        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/caddy-conf" >/dev/null 2>&1 || true
        [[ -n "$backup_file" && -f "$backup_file" ]] && mv "$backup_file" "$conf_file"
    fi

    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 4. SSH 安全加固 (终极完美版：防截断、防覆盖、防 Socket 冲突)
# ---------------------------------------------------------
