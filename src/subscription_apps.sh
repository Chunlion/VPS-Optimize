# shellcheck shell=bash
# Subscription and management app installers.

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
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
    if [[ "$custom_admin" =~ ^[Yy]$ ]]; then
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
    if [[ "$yn" =~ ^[Yy]$ ]]; then
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
