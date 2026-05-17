# shellcheck shell=bash
# Subscription tool containers, compose project operations, Dockge migration, and service menus.

install_docker_compose_standalone() {
    local compose_url tmp_file
    compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    tmp_file=$(mktemp /tmp/docker-compose.XXXXXX) || { echo -e "${RED}❌ 临时文件创建失败。${PLAIN}"; return 1; }

    if ! download_remote_script "$compose_url" "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 下载失败，请检查网络或 GitHub 访问。${PLAIN}"
        return 1
    fi

    if [[ ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 下载文件为空，已取消安装。${PLAIN}"
        return 1
    fi

    if ! mv "$tmp_file" /usr/local/bin/docker-compose; then
        rm -f "$tmp_file"
        echo -e "${RED}❌ Docker Compose 写入 /usr/local/bin 失败。${PLAIN}"
        return 1
    fi
    chmod +x /usr/local/bin/docker-compose || return 1
}

ensure_docker_compose_ready() {
    DOCKER_COMPOSE_CMD=""
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 基础组件与常用服务] 中安装 Docker。${PLAIN}"
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您安装...${PLAIN}"
        install_docker_compose_standalone || return 1
        DOCKER_COMPOSE_CMD="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi
}

generate_random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        echo "secret_$(date +%s)_$RANDOM$RANDOM"
    fi
}

func_sublinkpro() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔗 安装 SublinkPro (节点订阅转换与管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    # 1. 检查 Docker 引擎
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ 致命错误：未检测到 Docker！请先在菜单 [3 基础组件与常用服务] 中安装 Docker。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    # 2. 检查并兼容 Docker Compose
    local compose_cmd=""
    if docker compose version >/dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker-compose"
    else
        echo -e "${YELLOW}⚠️ 未检测到 Docker Compose 插件，正在为您静默安装...${PLAIN}"
        install_docker_compose_standalone || {
            read -n 1 -s -r -p "按任意键返回..."
            return
        }
        compose_cmd="docker-compose"
        echo -e "${GREEN}✅ Docker Compose 安装完成。${PLAIN}"
    fi

    # 3. 部署目录初始化
    local install_dir="/opt/sublinkpro"
    local sublink_bind_addr="127.0.0.1"
    local sublink_port="8000"
    sublink_bind_addr=$(ask_with_default "请输入 SublinkPro 监听地址" "$sublink_bind_addr")
    is_valid_listen_addr "$sublink_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        sublink_port=$(ask_with_default "请输入 SublinkPro 对外访问端口" "$sublink_port")
        if is_valid_port "$sublink_port"; then
            break
        fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "SublinkPro" "$sublink_bind_addr" "$sublink_port" || return 1

    echo -e "${YELLOW}💡 SublinkPro 将被安全部署在: ${CYAN}$install_dir${PLAIN}"
    echo -e "${YELLOW}💡 SublinkPro 监听地址将使用: ${CYAN}${sublink_bind_addr}:${sublink_port}${PLAIN}"
    echo -e "${YELLOW}💡 需要公网 HTTPS 访问时，建议部署后走 [19] -> [8] 添加 443 单入口反代域名。${PLAIN}"
    echo -e "${YELLOW}账号密码说明：当前安装流程不提供自定义后台账号密码。${PLAIN}"
    echo -e "${YELLOW}默认后台账号：${CYAN}admin${PLAIN} / 默认后台密码：${CYAN}123456${PLAIN}"
    echo -e "${YELLOW}部署完成后请尽快登录后台修改默认密码。${PLAIN}"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "❓ 确认现在开始一键安装吗？(y/n): "
    if is_yes "$yn"; then
        mkdir -p "$install_dir"
        cd "$install_dir" || return

        # 生成 docker-compose.yml 文件
        cat <<EOF > docker-compose.yml
services:
  sublinkpro:
    image: zerodeng/sublink-pro
    container_name: sublinkpro
    ports:
      - "${sublink_bind_addr}:${sublink_port}:8000"
    volumes:
      - "./db:/app/db"
      - "./template:/app/template"
      - "./logs:/app/logs"
    restart: unless-stopped
EOF
        
        echo -e "${CYAN}▶ 正在拉取镜像并启动 SublinkPro 容器...${PLAIN}"
        $compose_cmd up -d
        
        local access_host
        access_host="$sublink_bind_addr"
        [[ "$sublink_bind_addr" == "0.0.0.0" || "$sublink_bind_addr" == "::" ]] && access_host=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null || echo "您的服务器IP")
        
        echo -e "------------------------------------------------"
        echo -e "${GREEN}🎉 SublinkPro 部署并启动成功！${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "🌐 ${BOLD}本地访问地址:${PLAIN} http://${access_host}:${sublink_port}"
        echo -e "👤 ${BOLD}默认后台账号:${PLAIN} admin"
        echo -e "🔑 ${BOLD}默认后台密码:${PLAIN} 123456"
        echo -e "${YELLOW}⚠️ 当前安装流程未提供自定义账号密码，请登录后尽快修改默认密码。${PLAIN}"
        echo -e "${YELLOW}公网访问建议：主菜单 [19] -> [8] 为该本地端口添加 443 反代域名。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}⚠️ 核心防丢提示：${PLAIN}"
        echo -e "系统产生的数据库、模板和日志都已持久化映射在 ${CYAN}$install_dir${PLAIN} 下。"
        echo -e "如果您日后需要升级容器或重装 VPS，请务必提前打包备份该目录下的 ${GREEN}./db${PLAIN} 和 ${GREEN}./template${PLAIN} 文件夹！"
        echo -e "------------------------------------------------"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_miaomiaowu() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 妙妙屋订阅管理 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/miaomiaowu"
    local mmw_bind_addr="127.0.0.1"
    local mmw_port="8080"
    local jwt_secret

    mmw_bind_addr=$(ask_with_default "妙妙屋监听地址" "$mmw_bind_addr")
    is_valid_listen_addr "$mmw_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        mmw_port=$(ask_with_default "请输入 妙妙屋 对外访问端口" "$mmw_port")
        if is_valid_port "$mmw_port"; then
            break
        fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "妙妙屋订阅管理" "$mmw_bind_addr" "$mmw_port" || return 1

    jwt_secret=$(ask_with_default "JWT_SECRET（回车自动生成随机密钥）" "")
    if [[ -z "$jwt_secret" ]]; then
        jwt_secret=$(generate_random_secret)
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${mmw_bind_addr}:${mmw_port}${PLAIN}"
    echo -e "${YELLOW}数据目录：${CYAN}${install_dir}/data、subscribes、rule_templates${PLAIN}"
    echo -e "${YELLOW}公网 HTTPS 访问建议走 [19] -> [8]，不要直接开放容器端口。${PLAIN}"
    echo -e "${YELLOW}账号密码说明：当前安装流程不预设账号密码。${PLAIN}"
    echo -e "${YELLOW}首次打开面板会进入初始化页，请在页面中创建管理员账号和密码。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "确认现在部署 妙妙屋订阅管理 吗？(y/n): "
    if is_yes "$yn"; then
        mkdir -p "$install_dir"/{data,subscribes,rule_templates}
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'

services:
  miaomiaowu:
    image: ghcr.io/iluobei/miaomiaowu:latest
    container_name: miaomiaowu
    restart: unless-stopped
    user: root
    environment:
      PORT: "${mmw_port}"
      DATABASE_PATH: /app/data/traffic.db
      LOG_LEVEL: info
      JWT_SECRET: "${jwt_secret}"
    ports:
      - "${mmw_bind_addr}:${mmw_port}:${mmw_port}"
    volumes:
      - ./data:/app/data
      - ./subscribes:/app/subscribes
      - ./rule_templates:/app/rule_templates
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:${mmw_port}/"]
      interval: 30s
      timeout: 3s
      start_period: 5s
      retries: 3
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 妙妙屋 容器...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        local access_host
        access_host="$mmw_bind_addr"
        [[ "$mmw_bind_addr" == "0.0.0.0" || "$mmw_bind_addr" == "::" ]] && access_host=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null || echo "您的服务器IP")
        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ 妙妙屋订阅管理部署完成！${PLAIN}"
        echo -e "本地访问地址：${BOLD}http://${access_host}:${mmw_port}${PLAIN}"
        echo -e "账号密码：${YELLOW}无默认账号密码，首次打开页面创建管理员账号。${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        echo -e "${YELLOW}公网访问建议：主菜单 [19] -> [8] 为该本地端口添加 443 反代域名。${PLAIN}"
        echo -e "${YELLOW}请定期备份 ${install_dir}/data、subscribes、rule_templates。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

func_substore() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Sub-Store (Docker Compose / HTTP-META)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/sub-store"
    local backend_port="3001"
    local meta_port="9876"
    local backend_path="/$(generate_random_secret | cut -c1-48)"

    while true; do
        backend_port=$(ask_with_default "Sub-Store 后端 API 端口" "$backend_port")
        if is_valid_port "$backend_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    while true; do
        meta_port=$(ask_with_default "HTTP-META 本地端口" "$meta_port")
        if is_valid_port "$meta_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done

    backend_path=$(ask_with_default "前端访问后端路径（建议保留随机路径）" "$backend_path")
    if [[ "$backend_path" != /* ]]; then
        backend_path="/${backend_path}"
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}Sub-Store 后端：${CYAN}127.0.0.1:${backend_port}${PLAIN}"
    echo -e "${YELLOW}HTTP-META：${CYAN}127.0.0.1:${meta_port}${PLAIN}"
    echo -e "${YELLOW}前端后端路径：${CYAN}${backend_path}${PLAIN}"
    echo -e "${YELLOW}默认使用 host 网络并绑定 127.0.0.1，如需公网访问建议再接 Caddy/Nginx 反代。${PLAIN}"
    echo -e "${YELLOW}账号密码说明：当前 Sub-Store 部署不使用登录账号密码。${PLAIN}"
    echo -e "${YELLOW}请保存随机后端路径；公网访问建议通过反代额外加认证。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "确认现在部署 Sub-Store 吗？(y/n): "
    if is_yes "$yn"; then
        mkdir -p "$install_dir/data"
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'

services:
  sub-store:
    image: xream/sub-store:http-meta
    container_name: sub-store
    restart: always
    network_mode: host
    environment:
      SUB_STORE_BACKEND_API_HOST: "127.0.0.1"
      SUB_STORE_BACKEND_API_PORT: "${backend_port}"
      SUB_STORE_BACKEND_MERGE: "true"
      SUB_STORE_FRONTEND_BACKEND_PATH: "${backend_path}"
      PORT: "${meta_port}"
      HOST: "127.0.0.1"
    volumes:
      - ./data:/opt/app/data
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Sub-Store 容器...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Sub-Store 部署完成！${PLAIN}"
        echo -e "本地后端地址：${BOLD}http://127.0.0.1:${backend_port}${backend_path}${PLAIN}"
        echo -e "HTTP-META 地址：${BOLD}http://127.0.0.1:${meta_port}${PLAIN}"
        echo -e "账号密码：${YELLOW}无默认登录账号密码，请妥善保存上面的随机后端路径。${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        echo -e "${YELLOW}请定期备份 ${install_dir}/data。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

update_compose_project() {
    local name="$1"
    local dir="$2"

    if [[ ! -d "$dir" || ! -f "$dir/docker-compose.yml" ]]; then
        echo -e "${YELLOW}⚠️ 未找到 ${name} 的 Compose 配置：${dir}/docker-compose.yml，已跳过。${PLAIN}"
        return 1
    fi

    echo -e "${CYAN}▶ 正在更新 ${name}...${PLAIN}"
    (
        cd "$dir" || exit 1
        $DOCKER_COMPOSE_CMD pull
        $DOCKER_COMPOSE_CMD up -d
    )
}

func_update_subscription_tools() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}${YELLOW}UPD 更新订阅管理工具 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}这个菜单只更新订阅管理工具容器，不会更新 3x-ui / Sing-box / Xray。${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${BOLD}${YELLOW}  1. UPD 更新 SublinkPro${PLAIN}       ${CYAN}(/opt/sublinkpro)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  2. UPD 更新 妙妙屋订阅管理${PLAIN}     ${CYAN}(/opt/miaomiaowu)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  3. UPD 更新 Sub-Store${PLAIN}        ${CYAN}(/opt/sub-store)${PLAIN}"
    echo -e "${BOLD}${YELLOW}  4. UPD 全部更新${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${RED}  0. 返回 / q 返回${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice
    read_trimmed choice "请选择要更新的项目: "
    [[ "$choice" == "0" ]] && return

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    case "$choice" in
        1) update_compose_project "SublinkPro" "/opt/sublinkpro" ;;
        2) update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" ;;
        3) update_compose_project "Sub-Store" "/opt/sub-store" ;;
        4)
            update_compose_project "SublinkPro" "/opt/sublinkpro" || true
            update_compose_project "妙妙屋订阅管理" "/opt/miaomiaowu" || true
            update_compose_project "Sub-Store" "/opt/sub-store" || true
            ;;
        *)
            echo -e "${RED}❌ 无效选择！${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
            ;;
    esac

    echo -e "------------------------------------------------"
    echo -e "${GREEN}✅ 更新流程已执行完成。${PLAIN}"
    local prune_confirm
    read_trimmed prune_confirm "是否清理无标签旧镜像以释放磁盘空间？(y/n，默认 n): "
    if is_yes "$prune_confirm"; then
        docker image prune -f
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

func_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Dockge (Docker Compose 管理面板)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}Dockge 用来管理 compose.yaml stack，可创建、编辑、启动、停止、重启和更新镜像。${PLAIN}"
    echo -e "${YELLOW}注意：Dockge 会挂载 Docker socket，建议只监听本地地址，再通过 Caddy/Nginx 反代访问。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/dockge"
    local stacks_dir="/opt/stacks"
    local dockge_bind_addr="127.0.0.1"
    local dockge_port="5001"

    dockge_bind_addr=$(ask_with_default "Dockge 监听地址" "$dockge_bind_addr")
    is_valid_listen_addr "$dockge_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        dockge_port=$(ask_with_default "Dockge 访问端口" "$dockge_port")
        if is_valid_port "$dockge_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "Dockge 管理面板" "$dockge_bind_addr" "$dockge_port" || return 1
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")

    echo -e "${YELLOW}Dockge 目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}Stacks 目录：${CYAN}${stacks_dir}${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${dockge_bind_addr}:${dockge_port}${PLAIN}"
    echo -e "${YELLOW}账号密码说明：Dockge 不预设默认账号密码。${PLAIN}"
    echo -e "${YELLOW}首次打开面板会进入初始化页，请在页面中创建管理员账号和密码。${PLAIN}"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "确认现在部署 Dockge 吗？(y/n): "
    if is_yes "$yn"; then
        mkdir -p "$install_dir" "$stacks_dir"
        cd "$install_dir" || return

        cat <<EOF > compose.yaml
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - "${dockge_bind_addr}:${dockge_port}:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - ${stacks_dir}:${stacks_dir}
    environment:
      DOCKGE_STACKS_DIR: "${stacks_dir}"
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Dockge...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Dockge 部署完成！${PLAIN}"
        echo -e "访问地址：${BOLD}http://${dockge_bind_addr}:${dockge_port}${PLAIN}"
        echo -e "Stacks 目录：${CYAN}${stacks_dir}${PLAIN}"
        echo -e "账号密码：${YELLOW}无默认账号密码，首次打开页面创建管理员账号。${PLAIN}"
        echo -e "${YELLOW}已有 compose 项目可返回部署菜单选择 [10] 迁移到 Dockge 后，在 Dockge 里扫描 stacks 目录。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

func_komari() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}安装 Komari 探针监控面板 (Docker Compose)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}Komari 用于服务器探针监控。默认只监听本地地址；公网 HTTPS 可走 Caddy 反代，已启用 443 单入口时走 [19] -> [8]。${PLAIN}"
    echo -e "${YELLOW}如果探针客户端需要直连端口，可把监听地址改为 0.0.0.0，并确认云安全组已放行。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local install_dir="/opt/komari"
    local komari_bind_addr="127.0.0.1"
    local komari_port="25774"
    local custom_admin="n"
    local admin_username=""
    local admin_password=""
    local yn

    komari_bind_addr=$(ask_with_default "Komari 监听地址" "$komari_bind_addr")
    is_valid_listen_addr "$komari_bind_addr" || { echo -e "${RED}❌ 监听地址无效。${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    while true; do
        komari_port=$(ask_with_default "Komari 访问端口" "$komari_port")
        if is_valid_port "$komari_port"; then break; fi
        echo -e "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}"
    done
    warn_if_public_bind "Komari 探针监控面板" "$komari_bind_addr" "$komari_port" || return 1

    read_trimmed custom_admin "是否自定义初始管理员账号和密码？(y/n，默认 n): "
    if is_yes "$custom_admin"; then
        while true; do
            read_trimmed admin_username "管理员用户名（默认 admin）: "
            admin_username="${admin_username:-admin}"
            if [[ "$admin_username" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
                break
            fi
            echo -e "${RED}❌ 用户名只能包含字母、数字、点、下划线和短横线，长度 3-32。${PLAIN}"
        done

        while true; do
            read_secret_trimmed admin_password "管理员密码（至少 8 位，留空自动生成）: "
            if [[ -z "$admin_password" ]]; then
                admin_password=$(generate_random_secret | cut -c1-24)
                echo -e "${YELLOW}已自动生成管理员密码，部署完成后会显示一次，请及时保存。${PLAIN}"
                break
            fi
            if [[ ${#admin_password} -ge 8 ]]; then
                break
            fi
            echo -e "${RED}❌ 密码至少需要 8 位。${PLAIN}"
        done
    fi

    echo -e "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}"
    echo -e "${YELLOW}数据目录：${CYAN}${install_dir}/data${PLAIN}"
    echo -e "${YELLOW}监听地址：${CYAN}${komari_bind_addr}:${komari_port}${PLAIN}"
    if [[ -n "$admin_username" ]]; then
        echo -e "${YELLOW}初始管理员：${CYAN}${admin_username}${PLAIN}"
    else
        echo -e "${YELLOW}账号密码说明：未自定义时 Komari 会生成默认管理员账号。${PLAIN}"
        echo -e "${YELLOW}初始管理员：${CYAN}使用 Komari 默认生成账号，请安装后查看容器日志${PLAIN}"
    fi
    echo -e "------------------------------------------------"
    read_trimmed yn "确认现在部署 Komari 吗？(y/n): "
    if is_yes "$yn"; then
        mkdir -p "$install_dir/data"
        cd "$install_dir" || return

        cat <<EOF > docker-compose.yml
version: '3.8'
services:
  komari:
    image: ghcr.io/komari-monitor/komari:latest
    container_name: komari
    ports:
      - "${komari_bind_addr}:${komari_port}:25774"
    volumes:
      - ./data:/app/data
    environment:
EOF

        if [[ -n "$admin_username" ]]; then
            cat <<EOF >> docker-compose.yml
      ADMIN_USERNAME: "${admin_username}"
      ADMIN_PASSWORD: "${admin_password}"
EOF
        else
            cat <<'EOF' >> docker-compose.yml
      # 可选：如需自定义初始管理员账号，请停止容器后取消注释并填写。
      # ADMIN_USERNAME: admin
      # ADMIN_PASSWORD: yourpassword
EOF
        fi

        cat <<EOF >> docker-compose.yml
    restart: unless-stopped
EOF

        echo -e "${CYAN}▶ 正在拉取镜像并启动 Komari...${PLAIN}"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "${GREEN}✅ Komari 部署完成！${PLAIN}"
        echo -e "访问地址：${BOLD}http://${komari_bind_addr}:${komari_port}${PLAIN}"
        echo -e "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}"
        if [[ -n "$admin_username" ]]; then
            echo -e "管理员账号：${BOLD}${admin_username}${PLAIN}"
            echo -e "管理员密码：${BOLD}${admin_password}${PLAIN}"
            echo -e "${YELLOW}请及时保存密码，后续也可在 ${install_dir}/docker-compose.yml 中查看或修改。${PLAIN}"
        else
            echo -e "${YELLOW}默认管理员账号请查看日志：${CYAN}$DOCKER_COMPOSE_CMD logs komari${PLAIN}"
        fi
        echo -e "${YELLOW}如需公网 HTTPS 访问：未启用 443 单入口可用 [4] -> [1] Caddy 反代；已启用 443 单入口请用 [19] -> [8] 添加反代域名。${PLAIN}"
    else
        echo -e "${BLUE}已安全取消部署。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回..."
}

find_compose_file() {
    local dir="$1"
    local file
    for file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        if [[ -f "${dir}/${file}" ]]; then
            echo "${dir}/${file}"
            return 0
        fi
    done
    return 1
}

is_managed_compose_dir() {
    local dir="${1%/}"
    case "$dir" in
        /opt/sublinkpro|/opt/miaomiaowu|/opt/sub-store|/opt/dockge|/opt/komari)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

manage_compose_project() {
    local project_name="$1"
    local project_dir="${2%/}"
    local data_hint="$3"
    local compose_file choice yn

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 ${project_name} 管理 / 卸载${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}部署目录：${CYAN}${project_dir}${PLAIN}"
        echo -e "${YELLOW}数据提示：${CYAN}${data_hint}${PLAIN}"
        echo -e "------------------------------------------------"

        if [[ ! -d "$project_dir" ]] || ! compose_file=$(find_compose_file "$project_dir"); then
            echo -e "${YELLOW}未检测到 ${project_name} 的 Compose 部署。${PLAIN}"
            echo -e "${BLUE}可以先返回上级菜单选择对应安装项。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${GREEN}  1. 查看运行状态${PLAIN}"
        echo -e "${GREEN}  2. 重启服务${PLAIN}"
        echo -e "${GREEN}  3. 更新镜像并重建${PLAIN}"
        echo -e "${YELLOW}  4. 停止并移除容器（保留目录数据）${PLAIN}"
        echo -e "${RED}  5. 归档部署目录（停止容器并隔离配置/数据）${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" ps)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            2)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" restart)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            3)
                ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" pull && $DOCKER_COMPOSE_CMD -f "$compose_file" up -d)
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            4)
                if confirm_risk_action "停止并移除 ${project_name} 容器" \
                    "Docker Compose 容器运行状态" \
                    "在 ${project_dir} 中重新执行 compose up -d，或回到管理菜单重建" \
                    "目录数据会保留，但服务会立即中断。"; then
                    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down)
                    echo -e "${GREEN}✅ 已停止并移除容器，部署目录仍保留：${project_dir}${PLAIN}"
                else
                    echo -e "${BLUE}已取消操作。${PLAIN}"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            5)
                echo -e "${RED}⚠️  高风险：这会停止容器并把 ${project_dir} 移入隔离目录，配置、数据库或本地数据不再原地可用。${PLAIN}"
                echo -e "${YELLOW}隔离后如需彻底清理，请确认无误后手动处理隔离目录。${PLAIN}"
                if confirm_risk_action "归档 ${project_name} 部署目录" \
                    "Docker Compose 容器、部署目录、配置和本地数据位置" \
                    "从 /opt/.vps-optimize-quarantine 手动移回原路径后重新启动" \
                    "确认已经备份数据库和配置，且服务可以中断。"; then
                    if ! is_managed_compose_dir "$project_dir"; then
                        echo -e "${RED}❌ 安全检查未通过，拒绝归档非脚本托管目录：${project_dir}${PLAIN}"
                    else
                        ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }
                        (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$compose_file" down -v)
                        if quarantine_path "$project_dir" "/opt/.vps-optimize-quarantine"; then
                            echo -e "${GREEN}✅ 已归档 ${project_name} 部署目录。${PLAIN}"
                        else
                            echo -e "${RED}❌ 归档失败，请手动检查目录：${project_dir}${PLAIN}"
                        fi
                    fi
                else
                    echo -e "${BLUE}已取消归档。${PLAIN}"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            0|q|Q) return ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

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
        echo -e "${YELLOW}可选择不同一键脚本安装，也可进入已安装脚本的管理菜单。${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 安装 Sing-box（甬哥四合一脚本）${PLAIN}"
        echo -e "${GREEN}  2. 安装 Sing-box（233boy 一键脚本）${PLAIN}"
        echo -e "${GREEN}  3. 管理 / 卸载 Sing-box${PLAIN}"
        echo -e "${RED}  0. 返回上级菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read_trimmed choice "👉 请选择操作: "

        case "$choice" in
            1) func_singbox ;;
            2) func_singbox_233boy ;;
            3) func_singbox_manage ;;
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

is_dockge_migration_seen() {
    local needle="$1"
    local item
    for item in "${DOCKGE_MIGRATION_DIRS[@]}"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

add_dockge_migration_candidate() {
    local dir="$1"
    local stacks_dir="$2"
    local name

    dir="${dir%/}"
    [[ -d "$dir" ]] || return 0
    [[ "$dir" == "/opt/dockge" ]] && return 0
    [[ "$dir" == "$stacks_dir" || "$dir" == "$stacks_dir"/* ]] && return 0
    find_compose_file "$dir" >/dev/null 2>&1 || return 0
    is_dockge_migration_seen "$dir" && return 0

    name=$(basename "$dir")
    DOCKGE_MIGRATION_NAMES+=("$name")
    DOCKGE_MIGRATION_DIRS+=("$dir")
}

discover_dockge_migration_candidates() {
    local stacks_dir="$1"
    local dir file
    DOCKGE_MIGRATION_NAMES=()
    DOCKGE_MIGRATION_DIRS=()

    for dir in /opt/sublinkpro /opt/miaomiaowu /opt/sub-store; do
        add_dockge_migration_candidate "$dir" "$stacks_dir"
    done

    for file in /opt/*/compose.yaml /opt/*/compose.yml /opt/*/docker-compose.yml /opt/*/docker-compose.yaml; do
        [[ -e "$file" ]] || continue
        add_dockge_migration_candidate "$(dirname "$file")" "$stacks_dir"
    done
}

migrate_compose_project_to_dockge() {
    local source_dir="$1"
    local stacks_dir="$2"
    local source_compose stack_name target_dir compose_name restart_confirm
    local restart_stack="true"

    source_dir="${source_dir%/}"
    source_compose=$(find_compose_file "$source_dir") || {
        echo -e "${RED}❌ 未找到 Compose 配置：${source_dir}${PLAIN}"
        return 1
    }

    stack_name=$(ask_with_default "Dockge stack 名称" "$(basename "$source_dir")")
    if [[ ! "$stack_name" =~ ^[A-Za-z0-9_.-]+$ || "$stack_name" == "." || "$stack_name" == ".." ]]; then
        echo -e "${RED}❌ stack 名称无效，只能使用字母、数字、点、下划线和短横线。${PLAIN}"
        return 1
    fi

    target_dir="${stacks_dir%/}/${stack_name}"
    if [[ "$source_dir" == "$target_dir" ]]; then
        echo -e "${YELLOW}⚠️ ${source_dir} 已经在 Dockge stacks 目录内，已跳过。${PLAIN}"
        return 0
    fi
    if [[ -e "$target_dir" ]]; then
        echo -e "${RED}❌ 目标目录已存在：${target_dir}${PLAIN}"
        echo -e "${YELLOW}请先在 Dockge 中确认是否已有同名 stack，或换一个 stack 名称。${PLAIN}"
        return 1
    fi

    echo -e "------------------------------------------------"
    echo -e "${YELLOW}将迁移：${CYAN}${source_dir}${PLAIN}"
    echo -e "${YELLOW}迁移到：${CYAN}${target_dir}${PLAIN}"
    echo -e "${YELLOW}Compose：${CYAN}${source_compose}${PLAIN}"
    echo -e "${YELLOW}说明：会移动整个项目目录，保留相对挂载的数据目录。${PLAIN}"
    echo -e "${YELLOW}如果项目使用 Docker 命名卷，建议保持 stack 名称与原目录名一致。${PLAIN}"
    confirm_risk_action "迁移 Compose 项目到 Dockge" \
        "Compose 项目目录、容器停止/启动位置和 Dockge stack 路径" \
        "把 ${target_dir} 手动移回 ${source_dir}，并用原 compose 文件重新启动" \
        "确认项目没有绝对路径依赖，且已备份重要数据。" || { echo -e "${BLUE}已取消迁移 ${source_dir}。${PLAIN}"; return 0; }

    read_trimmed restart_confirm "是否先停止旧容器并在新目录重新启动？(Y/n): "
    if is_no "$restart_confirm"; then
        restart_stack="false"
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在停止旧目录中的 Compose 项目...${PLAIN}"
        ( cd "$source_dir" && $DOCKER_COMPOSE_CMD down ) || {
            echo -e "${RED}❌ 停止旧项目失败，已中止迁移。${PLAIN}"
            return 1
        }
    fi

    mkdir -p "$stacks_dir" || return 1
    mv "$source_dir" "$target_dir" || {
        echo -e "${RED}❌ 移动目录失败：${source_dir} -> ${target_dir}${PLAIN}"
        return 1
    }

    compose_name=$(basename "$source_compose")
    if [[ "$compose_name" == docker-compose.y* && ! -f "${target_dir}/compose.yaml" ]]; then
        mv "${target_dir}/${compose_name}" "${target_dir}/compose.yaml" || {
            echo -e "${RED}❌ 重命名 Compose 文件失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    if [[ "$restart_stack" == "true" ]]; then
        echo -e "${CYAN}▶ 正在新目录中重新启动 Compose 项目...${PLAIN}"
        ( cd "$target_dir" && $DOCKER_COMPOSE_CMD up -d ) || {
            echo -e "${RED}❌ 新目录启动失败，请手动检查：${target_dir}${PLAIN}"
            return 1
        }
    fi

    echo -e "${GREEN}✅ 已迁移到 Dockge stacks：${target_dir}${PLAIN}"
    echo -e "${YELLOW}请在 Dockge 页面里扫描/刷新 stacks 目录后接管。${PLAIN}"
}

func_migrate_compose_to_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}迁移已有 Compose 项目到 Dockge${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}适合 Dockge 后安装的场景：把已有 docker-compose.yml / compose.yaml 项目移动到 Dockge stacks 目录。${PLAIN}"
    echo -e "${YELLOW}建议先确认相关服务可以短暂停机，并已做好重要数据备份。${PLAIN}"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "按任意键返回..."; return; }

    local stacks_dir="/opt/stacks"
    local choice custom_dir i
    stacks_dir=$(ask_with_default "Dockge stacks 目录" "$stacks_dir")
    mkdir -p "$stacks_dir" || { echo -e "${RED}❌ 无法创建 stacks 目录：${stacks_dir}${PLAIN}"; read -n 1 -s -r -p "按任意键返回..."; return; }

    discover_dockge_migration_candidates "$stacks_dir"

    if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -gt 0 ]]; then
        echo -e "${GREEN}检测到以下可迁移 Compose 项目：${PLAIN}"
        for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
            echo -e "${GREEN}  $((i + 1)). ${DOCKGE_MIGRATION_NAMES[$i]}${PLAIN} ${CYAN}(${DOCKGE_MIGRATION_DIRS[$i]})${PLAIN}"
        done
        echo -e "${BOLD}${YELLOW}  a. 迁移全部检测到的项目${PLAIN}"
    else
        echo -e "${YELLOW}⚠️ 未在 /opt 下检测到常见 Compose 项目。${PLAIN}"
    fi
    echo -e "${CYAN}  c. 手动输入项目目录${PLAIN}"
    echo -e "${RED}  0. 返回 / q 返回${PLAIN}"
    echo -e "------------------------------------------------"

    read_trimmed choice "请选择要迁移的项目: "
    case "$choice" in
        0|q|Q) return ;;
        a|A)
            if [[ "${#DOCKGE_MIGRATION_DIRS[@]}" -eq 0 ]]; then
                echo -e "${YELLOW}⚠️ 没有可自动迁移的项目。${PLAIN}"
            else
                for i in "${!DOCKGE_MIGRATION_DIRS[@]}"; do
                    migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$i]}" "$stacks_dir" || true
                    echo -e "------------------------------------------------"
                done
            fi
            ;;
        c|C)
            read_trimmed custom_dir "请输入已有 Compose 项目目录: "
            migrate_compose_project_to_dockge "$custom_dir" "$stacks_dir"
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DOCKGE_MIGRATION_DIRS[@]} )); then
                migrate_compose_project_to_dockge "${DOCKGE_MIGRATION_DIRS[$((choice - 1))]}" "$stacks_dir"
            else
                echo -e "${RED}❌ 无效选择！${PLAIN}"
            fi
            ;;
    esac

    read -n 1 -s -r -p "按任意键返回..."
}
# ---------------------------------------------------------
# 18. 面板救砖/重置 SSL (兼容新版 3x-ui 证书字段)
# ---------------------------------------------------------
