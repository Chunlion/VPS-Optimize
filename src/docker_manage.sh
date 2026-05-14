# shellcheck shell=bash
# Docker exposure audit, managed project status, and Docker safety workflows.

docker_port_line_is_public() {
    local line="$1"
    case "$line" in
        *"0.0.0.0:"*|*":::"*|*"[::]:"*|*"[0:0:0:0:0:0:0:0]:"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_managed_container_status() {
    local title="$1"
    local container="$2"
    local dir="$3"
    local state health ports compose_file

    if docker inspect "$container" >/dev/null 2>&1; then
        state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container" 2>/dev/null || true)
        ports=$(docker port "$container" 2>/dev/null | tr '\n' '; ')
        [[ -z "$ports" ]] && ports="未暴露 Docker 端口或使用 host 网络"
        [[ -z "$health" ]] && health="无 healthcheck"
        echo -e "${GREEN}${title}${PLAIN}: ${state} / ${health}"
        echo -e "  端口: ${ports}"
    else
        echo -e "${YELLOW}${title}${PLAIN}: 未检测到容器 ${container}"
    fi

    compose_file=$(find_compose_file "$dir" 2>/dev/null || true)
    if [[ -n "$compose_file" ]]; then
        echo -e "  Compose: ${CYAN}${compose_file}${PLAIN}"
    else
        echo -e "  Compose: ${BLUE}未检测到 ${dir} 部署目录${PLAIN}"
    fi
}

print_subscription_compose_status() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}未安装 Docker，跳过订阅工具容器状态。${PLAIN}"
        return 0
    fi
    print_managed_container_status "SublinkPro" "sublinkpro" "/opt/sublinkpro"
    print_managed_container_status "妙妙屋订阅管理" "miaomiaowu" "/opt/miaomiaowu"
    print_managed_container_status "Sub-Store" "sub-store" "/opt/sub-store"
    print_managed_container_status "Dockge" "dockge" "/opt/dockge"
    print_managed_container_status "Komari" "komari" "/opt/komari"
}

func_docker_project_status() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "Docker 安全管理 > 项目容器状态"
    echo -e "${BOLD}🐳 443 / 订阅工具相关容器状态${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}这里只看本项目场景相关容器：SublinkPro、妙妙屋、Sub-Store、Dockge、Komari。${PLAIN}"
    echo -e "${YELLOW}3x-ui、Caddy、Nginx 通常是 systemd 服务，状态请看 [15] 或 [19] 体检。${PLAIN}"
    echo -e "------------------------------------------------"
    print_subscription_compose_status
    echo -e "------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回..."
}

func_docker_443_exposure_audit() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    print_breadcrumb "Docker 安全管理 > 443 暴露审计"
    echo -e "${BOLD}🔎 Docker 端口暴露审计${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}目标：启用 443 单入口后，订阅工具和管理面板应尽量只绑定 127.0.0.1，再由 Caddy/Nginx 对外。${PLAIN}"
    echo -e "------------------------------------------------"

    local found_public=false
    local line name ports
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        ports=$(docker port "$name" 2>/dev/null || true)
        [[ -z "$ports" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if docker_port_line_is_public "$line"; then
                found_public=true
                echo -e "${YELLOW}⚠️ ${name}: ${line}${PLAIN}"
            fi
        done <<< "$ports"
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)

    if $found_public; then
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}建议：订阅工具、Dockge、Komari 用 127.0.0.1 绑定，公网访问走 [19] -> [8] 添加 443 反代域名。${PLAIN}"
        echo -e "${YELLOW}如确实需要公网直连，请确认云安全组、系统防火墙和访问密码都已收紧。${PLAIN}"
    else
        echo -e "${GREEN}✅ 未发现 Docker 容器通过 0.0.0.0 / :: 直接暴露端口。${PLAIN}"
    fi

    echo -e "------------------------------------------------"
    print_subscription_compose_status
    echo -e "------------------------------------------------"
    read -n 1 -s -r -p "按任意键返回..."
}

func_docker_manage() {
    if ! command -v docker >/dev/null 2>&1; then 
        clear
        echo -e "${RED}❌ 错误：检测到系统尚未安装 Docker 引擎！${PLAIN}"
        echo -e "${YELLOW}💡 请先在主菜单进入 [3 基础组件与常用服务] 安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    # 确保依赖工具存在 (使用我们抽象的 install_pkg)
    if ! command -v jq >/dev/null 2>&1; then install_pkg jq; fi

    while true; do
        clear
        local docker_ver
        docker_ver=$(docker -v | awk '{print $3}' | tr -d ',')
        
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "Docker 安全管理"
        echo -e "${BOLD}🐳 Docker 安全管理 (版本: ${GREEN}${docker_ver}${PLAIN}${BOLD})${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 开启 Docker 本地防穿透${PLAIN} ${YELLOW}(限制映射端口仅 127.0.0.1 访问)${PLAIN}"
        echo -e "${GREEN}  2. 解除 Docker 本地防穿透${PLAIN} ${YELLOW}(恢复全网可访，不破坏原配置)${PLAIN}"
        echo -e "${GREEN}  3. 查看 443 / 订阅工具容器状态${PLAIN}"
        echo -e "${GREEN}  4. Docker 端口暴露审计${PLAIN} ${YELLOW}(检查是否绕过 443 单入口)${PLAIN}"
        echo -e "${BOLD}${YELLOW}  5. UPD 更新订阅工具容器${PLAIN} ${CYAN}(SublinkPro / 妙妙屋 / Sub-Store)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单${PLAIN}"
        
        local c
        read_trimmed c "👉 请选择操作: "
        case $c in
            1) 
                confirm_risk_action "开启 Docker 本地防穿透" \
                    "Docker daemon.json 和 Docker 服务重启" \
                    "使用自动备份的 daemon.json 恢复并重启 Docker" \
                    "确认现有容器不依赖公网直连映射端口。" || { echo -e "${BLUE}已取消操作。${PLAIN}"; sleep 1; continue; }
                echo -e "${CYAN}▶ 正在配置 Docker 安全策略...${PLAIN}"
                mkdir -p /etc/docker
                local conf_file="/etc/docker/daemon.json"
                local backup_file="${conf_file}.bak_$(date +%s)"
                local tmp_json
                tmp_json=$(mktemp /tmp/docker-daemon.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败，已取消操作。${PLAIN}"; sleep 1; continue; }
                
                # 检查并备份
                if [[ -f "$conf_file" ]]; then
                    if ! cp -p "$conf_file" "$backup_file"; then
                        echo -e "${RED}❌ Docker 配置备份失败，已取消操作。${PLAIN}"
                        rm -f "$tmp_json"
                        sleep 1
                        continue
                    fi
                    echo -e "${YELLOW}⚠️ 已备份原有配置至 $backup_file${PLAIN}"
                    
                    # 使用 jq 进行非破坏性合并，保留用户原有配置
                    if ! jq '. + {"ip": "127.0.0.1", "log-driver": "json-file", "log-opts": {"max-size": "50m", "max-file": "3"}}' "$conf_file" > "$tmp_json" 2>/dev/null; then
                        echo -e "${RED}❌ 原 daemon.json 格式损坏，合并失败！操作中止。${PLAIN}"
                        rm -f "$tmp_json"
                        echo -e "${YELLOW}备份已保留：$backup_file${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    mv "$tmp_json" "$conf_file"
                else
                    # 文件不存在时初始生成
                    cat <<EOF > "$conf_file"
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
                fi
                
                # 防宕机重启机制：如果新配置导致引擎崩溃，立刻回滚！
                if systemctl restart docker >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ 已开启安全保护，Docker 容器端口仅限本地反代访问！${PLAIN}"
                    [[ -f "$backup_file" ]] && echo -e "${CYAN}Docker 配置备份已保留：$backup_file${PLAIN}"
                else
                    echo -e "${RED}❌ 致命错误：新配置导致 Docker 引擎无法启动！正在自动回滚...${PLAIN}"
                    if [[ -f "$backup_file" ]]; then
                        mv "$backup_file" "$conf_file"
                    else
                        quarantine_path "$conf_file" "/etc/vps-optimize/quarantine/docker" >/dev/null 2>&1 || true
                    fi
                    systemctl restart docker >/dev/null 2>&1
                fi
                sleep 2
                ;;
            2) 
                local conf_file="/etc/docker/daemon.json"
                if [[ -f "$conf_file" ]]; then
                    confirm_risk_action "解除 Docker 本地防穿透" \
                        "Docker daemon.json 和 Docker 服务重启" \
                        "使用自动备份的 daemon.json 恢复并重启 Docker" \
                        "解除后容器映射端口可能重新公网可达，请确认防火墙和云安全组。" || { echo -e "${BLUE}已取消操作。${PLAIN}"; sleep 1; continue; }
                    echo -e "${CYAN}▶ 正在安全移除 Docker 端口限制...${PLAIN}"
                    local backup_file="${conf_file}.bak_$(date +%s)"
                    local tmp_json
                    tmp_json=$(mktemp /tmp/docker-daemon.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败，已取消操作。${PLAIN}"; sleep 1; continue; }
                    if ! cp -p "$conf_file" "$backup_file"; then
                        echo -e "${RED}❌ Docker 配置备份失败，已取消操作。${PLAIN}"
                        rm -f "$tmp_json"
                        sleep 1
                        continue
                    fi

                    # 核心修复：只精准删除 ip 限制，绝不误删国内镜像源等其他配置！
                    if ! jq 'del(.ip)' "$conf_file" > "$tmp_json" 2>/dev/null; then
                        echo -e "${RED}❌ JSON 解析失败，操作中止。${PLAIN}"
                        rm -f "$tmp_json"
                        echo -e "${YELLOW}备份已保留：$backup_file${PLAIN}"
                        read -n 1 -s -r -p "按任意键继续..."
                        continue
                    fi
                    mv "$tmp_json" "$conf_file"

                    if systemctl restart docker >/dev/null 2>&1; then
                        echo -e "${GREEN}✅ 已解除限制，容器端口恢复公网可访状态！${PLAIN}"
                        echo -e "${CYAN}Docker 配置备份已保留：$backup_file${PLAIN}"
                    else
                        echo -e "${RED}❌ 卸载异常：导致引擎无法启动！正在回滚...${PLAIN}"
                        mv "$backup_file" "$conf_file"
                        systemctl restart docker >/dev/null 2>&1
                    fi
                else
                    echo -e "${BLUE}未检测到限制配置文件，当前已是全网开放状态。${PLAIN}"
                fi
                sleep 2
                ;;
            3) func_docker_project_status ;;
            4) func_docker_443_exposure_audit ;;
            5) func_update_subscription_tools ;;
            0) break ;;
            *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
        esac
    done
}
# ---------------------------------------------------------
# 6. BBR 增强管理
# ---------------------------------------------------------
