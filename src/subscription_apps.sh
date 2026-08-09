# shellcheck shell=bash
# Subscription and management app installers.

generate_random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        echo "secret_$(date +%s)_$RANDOM$RANDOM"
    fi
}

print_public_https_reverse_proxy_hint() {
    echo -e "$(localized_text "${YELLOW}公网 HTTPS 访问建议：未启用 443端口复用时，请走主菜单 [4 反代] 里的 Caddy 或 Nginx HTTPS 反代；已启用 443端口复用时，请走主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代]。${PLAIN}" "${YELLOW}Public HTTPS Access Suggestions: When Port 443 Reuse is not enabled, please go to Caddy or Nginx HTTPS in the main menu [4 reverse proxy]; when Port 443 Reuse is enabled, please go to the main menu [19 Port 443 Reuse Manager] -> [8 Managing Web Domains/reverse proxies].${PLAIN}" "${YELLOW}публичную сеть HTTPS Доступ к предложениям: Если повторное использование порта 443 не включен, перейдите к Caddy или Nginx HTTPS в главном меню [4 обратный прокси]; Когда включен повторное использование порта 443, перейдите в главное меню [19 Центр управления повторным использованием порта 443] -> [8 Управление веб-доменами/обратными прокси].${PLAIN}")"
}

func_sublinkpro() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔗 安装 SublinkPro (节点订阅转换与管理面板)${PLAIN}" "${BOLD}🔗 Install SublinkPro (node subscription conversion and management panel)${PLAIN}" "${BOLD}🔗 Установите SublinkPro (панель преобразования и управления подпиской узла)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    # 部署目录初始化
    local install_dir="/opt/sublinkpro"
    local sublink_bind_addr="127.0.0.1"
    local sublink_port="8000"
    sublink_bind_addr=$(ask_with_default "$(localized_text "请输入 SublinkPro 监听地址" "Please enter the SublinkPro listening address" "Пожалуйста, введите адрес прослушивания SublinkPro")" "$sublink_bind_addr")
    is_valid_listen_addr "$sublink_bind_addr" || { echo -e "$(localized_text "${RED}❌ 监听地址无效。${PLAIN}" "${RED}❌ The listening address is invalid.${PLAIN}" "${RED}❌ Неверный адрес прослушивания.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    while true; do
        sublink_port=$(ask_with_default "$(localized_text "请输入 SublinkPro 对外访问端口" "Please enter SublinkPro external access port" "Пожалуйста, введите порт внешнего доступа SublinkPro")" "$sublink_port")
        if is_valid_port "$sublink_port"; then
            break
        fi
        echo -e "$(localized_text "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}" "${RED}❌ The port is invalid, please enter a number between 1-65535.${PLAIN}" "${RED}❌ Порт недействителен. Введите число от 1 до 65535.${PLAIN}")"
    done
    warn_if_public_bind "SublinkPro" "$sublink_bind_addr" "$sublink_port" || return 1

    echo -e "$(localized_text "${YELLOW}💡 SublinkPro 将被安全部署在: ${CYAN}$install_dir${PLAIN}" "${YELLOW}💡 SublinkPro will be safely deployed at: $install_dir${PLAIN}" "${YELLOW}💡 SublinkPro будет безопасно развернут по адресу: $install_dir.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}💡 SublinkPro 监听地址将使用: ${CYAN}${sublink_bind_addr}:${sublink_port}${PLAIN}" "${YELLOW}💡 SublinkPro listening address will use: ${sublink_bind_addr}:${sublink_port}${PLAIN}" "${YELLOW}💡 Адрес прослушивания SublinkPro будет использовать: ${sublink_bind_addr}:${sublink_port}${PLAIN}")"
    print_public_https_reverse_proxy_hint
    echo -e "$(localized_text "${YELLOW}账号密码说明：当前安装流程不提供自定义后台账号密码。${PLAIN}" "${YELLOW}Account and Password Description: The current installation process does not provide custom background account passwords.${PLAIN}" "${YELLOW}Описание учетной записи и пароля: Текущий процесс установки не предоставляет пользовательские пароли фоновой учетной записи.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}默认后台账号：${CYAN}admin${PLAIN} / 默认后台密码：${CYAN}123456${PLAIN}" "${YELLOW}Default background account: admin / Default background password: 123456${PLAIN}" "${YELLOW}Фоновая учетная запись по умолчанию: admin / Фоновый пароль по умолчанию: 123456${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}部署完成后请尽快登录后台修改默认密码。${PLAIN}" "${YELLOW}After the deployment is completed, please log in to the background as soon as possible to change the default password.${PLAIN}" "${YELLOW}После завершения развертывания как можно скорее войдите в фоновый режим, чтобы изменить пароль по умолчанию.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "$(localized_text "❓ 确认现在开始一键安装吗？(Y/n): " "❓ Are you sure you want to start the one-click installation now? (Y/n):" "❓ Вы уверены, что хотите начать установку в один клик сейчас? (Да/Нет):")"
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
        
        echo -e "$(localized_text "${CYAN}▶ 正在拉取镜像并启动 SublinkPro 容器...${PLAIN}" "${CYAN}▶ Pulling the image and starting the SublinkPro container...${PLAIN}" "${CYAN}▶ Извлечение образа и запуск контейнера SublinkPro...${PLAIN}")"
        $DOCKER_COMPOSE_CMD up -d
        
        local access_host
        access_host="$sublink_bind_addr"
        [[ "$sublink_bind_addr" == "0.0.0.0" || "$sublink_bind_addr" == "::" ]] && access_host=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null || echo "$(localized_text "您的服务器IP" "Your server IP" "IP вашего сервера")")
        
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}🎉 SublinkPro 部署并启动成功！${PLAIN}" "${GREEN}🎉 SublinkPro was deployed and started successfully!${PLAIN}" "${GREEN}🎉 SublinkPro был развернут и успешно запущен!${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "🌐 ${BOLD}本地访问地址:${PLAIN} http://${access_host}:${sublink_port}" "🌐 ${BOLD}Local access address:${PLAIN} http://${access_host}:${sublink_port}" "🌐 ${BOLD}адрес локального доступа:${PLAIN} http://${access_host}:${sublink_port}")"
        echo -e "$(localized_text "👤 ${BOLD}默认后台账号:${PLAIN} admin" "👤 ${BOLD}Default background account:${PLAIN} admin" "👤 Фоновая учетная запись ${BOLD}по умолчанию: администратор${PLAIN}.")"
        echo -e "$(localized_text "🔑 ${BOLD}默认后台密码:${PLAIN} 123456" "🔑 ${BOLD}Default background password:${PLAIN} 123456" "🔑 ${BOLD}фоновый пароль по умолчанию:${PLAIN} 123456")"
        echo -e "$(localized_text "${YELLOW}⚠️ 当前安装流程未提供自定义账号密码，请登录后尽快修改默认密码。${PLAIN}" "${YELLOW}⚠️ The current installation process does not provide a custom account password. Please change the default password as soon as possible after logging in.${PLAIN}" "${YELLOW}⚠️ Текущий процесс установки не предоставляет индивидуальный пароль учетной записи. Пожалуйста, измените пароль по умолчанию как можно скорее после входа в систему.${PLAIN}")"
        print_public_https_reverse_proxy_hint
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${YELLOW}⚠️ 核心防丢提示：${PLAIN}" "${YELLOW}⚠️ Core lockout prevention tips:${PLAIN}" "${YELLOW}⚠️ Основные советы по предотвращению потерь:${PLAIN}")"
        echo -e "$(localized_text "系统产生的数据库、模板和日志都已持久化映射在 ${CYAN}$install_dir${PLAIN} 下。" "The database, templates and logs generated by the system have been persistently mapped under ${CYAN}$install_dir${PLAIN}." "База данных, шаблоны и журналы, созданные системой, постоянно сопоставлены с ${CYAN}$install_dir${PLAIN}.")"
        echo -e "$(localized_text "如果您日后需要升级容器或重装 VPS，请务必提前打包备份该目录下的 ${GREEN}./db${PLAIN} 和 ${GREEN}./template${PLAIN} 文件夹！" "If you need to upgrade the container or reinstall the VPS in the future, be sure to pack and back up the ${GREEN}./db${PLAIN} and ${GREEN}./template${PLAIN} folders in this directory in advance!" "Если в будущем вам потребуется обновить контейнер или переустановить VPS, обязательно заранее запакуйте и сделайте резервную копию папок ${GREEN}./db${PLAIN} и ${GREEN}./template${PLAIN} в этом каталоге!")"
        echo -e "------------------------------------------------"
    else
        echo -e "$(localized_text "${BLUE}已安全取消部署。${PLAIN}" "${BLUE}Has been safely undeployed.${PLAIN}" "${BLUE}благополучно деразвернут.${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_miaomiaowu() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}安装 妙妙屋订阅管理 (Docker Compose)${PLAIN}" "${BOLD}Installation Miaomiaowu subscription management (Docker Compose)${PLAIN}" "${BOLD}Установка Управление подпиской Miiaomiaowu (Docker Compose)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    local install_dir="/opt/miaomiaowu"
    local mmw_bind_addr="127.0.0.1"
    local mmw_port="8080"
    local jwt_secret

    mmw_bind_addr=$(ask_with_default "$(localized_text "妙妙屋监听地址" "Miaomiaowu listening address" "Адрес прослушивания Мяомяову")" "$mmw_bind_addr")
    is_valid_listen_addr "$mmw_bind_addr" || { echo -e "$(localized_text "${RED}❌ 监听地址无效。${PLAIN}" "${RED}❌ The listening address is invalid.${PLAIN}" "${RED}❌ Неверный адрес прослушивания.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    while true; do
        mmw_port=$(ask_with_default "$(localized_text "请输入 妙妙屋 对外访问端口" "Please enter Miaomiaowu external access port" "Пожалуйста, введите внешний порт доступа Miaomiaowu")" "$mmw_port")
        if is_valid_port "$mmw_port"; then
            break
        fi
        echo -e "$(localized_text "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}" "${RED}❌ The port is invalid, please enter a number between 1-65535.${PLAIN}" "${RED}❌ Порт недействителен. Введите число от 1 до 65535.${PLAIN}")"
    done
    warn_if_public_bind "$(localized_text "妙妙屋订阅管理" "Miaomiaowu Subscription Management" "Управление подпиской Miaomiaowu")" "$mmw_bind_addr" "$mmw_port" || return 1

    jwt_secret=$(ask_with_default "$(localized_text "JWT_SECRET（回车自动生成随机密钥）" "JWT_SECRET (Press enter to automatically generate a random key)" "JWT_SECRET (нажмите Enter, чтобы автоматически сгенерировать случайный ключ)")" "")
    if [[ -z "$jwt_secret" ]]; then
        jwt_secret=$(generate_random_secret)
    fi

    echo -e "$(localized_text "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}" "${YELLOW}Deployment directory: ${install_dir}${PLAIN}" "${YELLOW}Каталог развертывания : ${install_dir}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}监听地址：${CYAN}${mmw_bind_addr}:${mmw_port}${PLAIN}" "${YELLOW}Listening address: ${mmw_bind_addr}:${mmw_port}${PLAIN}" "${YELLOW}Адрес прослушивания : ${mmw_bind_addr}:${mmw_port}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}数据目录：${CYAN}${install_dir}/data、subscribes、rule_templates${PLAIN}" "${YELLOW}Data directory: ${install_dir}/data,subscribes,rule_templates${PLAIN}" "${YELLOW}Каталог данных : ${install_dir}/data,subscribes,rule_templates${PLAIN}")"
    print_public_https_reverse_proxy_hint
    echo -e "$(localized_text "${YELLOW}不要直接开放容器端口到公网。${PLAIN}" "${YELLOW}Do not directly open the container port to the public.${PLAIN}" "${YELLOW}Не открывайте порт контейнера напрямую в публичную сеть.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}账号密码说明：当前安装流程不预设账号密码。${PLAIN}" "${YELLOW}Account password description: The current installation process does not preset the account password.${PLAIN}" "${YELLOW}Описание пароля учетной записи : В текущем процессе установки пароль учетной записи не устанавливается.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}首次打开面板会进入初始化页，请在页面中创建管理员账号和密码。${PLAIN}" "${YELLOW}When opens the panel for the first time, it will enter the initialization page. Please create an administrator account and password on the page.${PLAIN}" "${YELLOW}Когда впервые откроет панель, он перейдет на страницу инициализации. Пожалуйста, создайте учетную запись администратора и пароль на странице.${PLAIN}")"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "$(localized_text "确认现在部署 妙妙屋订阅管理 吗？(Y/n): " "Are you sure to deploy Miaomiaowu Subscription Management now? (Y/n):" "Вы уверены, что развернете управление подписками Miaomiaowu сейчас? (Да/Нет):")"
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

        echo -e "$(localized_text "${CYAN}▶ 正在拉取镜像并启动 妙妙屋 容器...${PLAIN}" "${CYAN}▶ Pulling the image and starting the Miaomiaowu container...${PLAIN}" "${CYAN}▶ Извлечение образа и запуск контейнера Miaomiaowu...${PLAIN}")"
        $DOCKER_COMPOSE_CMD up -d

        local access_host
        access_host="$mmw_bind_addr"
        [[ "$mmw_bind_addr" == "0.0.0.0" || "$mmw_bind_addr" == "::" ]] && access_host=$(curl -s4 --max-time 3 icanhazip.com 2>/dev/null || echo "$(localized_text "您的服务器IP" "Your server IP" "IP вашего сервера")")
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}✅ 妙妙屋订阅管理部署完成！${PLAIN}" "${GREEN}✅ Miaomiaowu subscription management deployment completed!${PLAIN}" "${GREEN}✅ Развертывание управления подписками Miaomiaowu завершено!${PLAIN}")"
        echo -e "$(localized_text "本地访问地址：${BOLD}http://${access_host}:${mmw_port}${PLAIN}" "Local access address: ${BOLD}Http://${access_host}:${mmw_port}${PLAIN}" "Адрес локального доступа: ${BOLD}http://${access_host}:${mmw_port}${PLAIN}.")"
        echo -e "$(localized_text "账号密码：${YELLOW}无默认账号密码，首次打开页面创建管理员账号。${PLAIN}" "Account password: ${YELLOW}Has no default account password. Create an administrator account when you open the page for the first time.${PLAIN}" "Пароль учетной записи: ${YELLOW}не имеет пароля учетной записи по умолчанию. Создайте учетную запись администратора при первом открытии страницы.${PLAIN}")"
        echo -e "$(localized_text "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}" "Configuration file: ${CYAN}${install_dir}/docker-compose.yml${PLAIN}" "Файл конфигурации: ${CYAN}${install_dir}/docker-compose.yml${PLAIN}")"
        print_public_https_reverse_proxy_hint
        echo -e "$(localized_text "${YELLOW}请定期备份 ${install_dir}/data、subscribes、rule_templates。${PLAIN}" "${YELLOW}Please back up ${install_dir}/data, subscribers, rule_templates regularly.${PLAIN}" "${YELLOW}Регулярно создавайте резервные копии ${install_dir}/data, подписчиков, rule_templates.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}已安全取消部署。${PLAIN}" "${BLUE}Has been safely undeployed.${PLAIN}" "${BLUE}благополучно деразвернут.${PLAIN}")"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_substore() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}安装 Sub-Store (Docker Compose / HTTP-META)${PLAIN}" "${BOLD}Installation Sub-Store (Docker Compose / HTTP-META)${PLAIN}" "${BOLD}Дополнительный магазин установки (Docker Compose / HTTP-META)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    local install_dir="/opt/sub-store"
    local backend_port="3001"
    local meta_port="9876"
    local backend_path="/$(generate_random_secret | cut -c1-48)"

    while true; do
        backend_port=$(ask_with_default "$(localized_text "Sub-Store 后端 API 端口" "Sub-Store backend API port" "Порт внутреннего API дочернего магазина")" "$backend_port")
        if is_valid_port "$backend_port"; then break; fi
        echo -e "$(localized_text "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}" "${RED}❌ The port is invalid, please enter a number between 1-65535.${PLAIN}" "${RED}❌ Порт недействителен. Введите число от 1 до 65535.${PLAIN}")"
    done

    while true; do
        meta_port=$(ask_with_default "$(localized_text "HTTP-META 本地端口" "HTTP-META local port" "HTTP-META локальный порт")" "$meta_port")
        if is_valid_port "$meta_port"; then break; fi
        echo -e "$(localized_text "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}" "${RED}❌ The port is invalid, please enter a number between 1-65535.${PLAIN}" "${RED}❌ Порт недействителен. Введите число от 1 до 65535.${PLAIN}")"
    done

    backend_path=$(ask_with_default "$(localized_text "前端访问后端路径（建议保留随机路径）" "Front-end access back-end path (it is recommended to keep a random path)" "Внутренний путь внешнего доступа (рекомендуется оставить случайный путь)")" "$backend_path")
    if [[ "$backend_path" != /* ]]; then
        backend_path="/${backend_path}"
    fi

    echo -e "$(localized_text "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}" "${YELLOW}Deployment directory: ${install_dir}${PLAIN}" "${YELLOW}Каталог развертывания : ${install_dir}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}Sub-Store 后端：${CYAN}127.0.0.1:${backend_port}${PLAIN}" "${YELLOW}Sub-Store backend: 127.0.0.1:${backend_port}${PLAIN}" "${YELLOW}Бэкенд подмагазина: 127.0.0.1:${backend_port}${PLAIN}")"
    echo -e "${YELLOW}HTTP-META：${CYAN}127.0.0.1:${meta_port}${PLAIN}"
    echo -e "$(localized_text "${YELLOW}前端后端路径：${CYAN}${backend_path}${PLAIN}" "${YELLOW}Front-end back-end path: ${backend_path}${PLAIN}" "${YELLOW}внешний и внутренний путь: ${backend_path}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}默认使用 host 网络并绑定 127.0.0.1。${PLAIN}" "${YELLOW}Uses the host network by default and binds to 127.0.0.1.${PLAIN}" "${YELLOW}по умолчанию использует хост-сеть и привязывается к 127.0.0.1.${PLAIN}")"
    print_public_https_reverse_proxy_hint
    echo -e "$(localized_text "${YELLOW}账号密码说明：当前 Sub-Store 部署不使用登录账号密码。${PLAIN}" "${YELLOW}Account and Password Description: The current Sub-Store deployment does not use the login account and password.${PLAIN}" "${YELLOW}Описание учетной записи и пароля. В текущем развертывании дополнительного магазина не используются учетная запись и пароль для входа.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}请保存随机后端路径；如对公网开放，请在反代侧额外加认证。${PLAIN}" "${YELLOW}Please save the random backend path; if it is open to the public, please add additional authentication on the reverse proxy side.${PLAIN}" "${YELLOW}Сохраните случайный путь к серверу; если он открыт для доступа в Интернет, добавьте дополнительную аутентификацию на стороне обратного прокси-сервера.${PLAIN}")"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "$(localized_text "确认现在部署 Sub-Store 吗？(Y/n): " "Are you sure you want to deploy Sub-Store now? (Y/n):" "Вы уверены, что хотите развернуть дополнительный магазин сейчас? (Да/Нет):")"
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

        echo -e "$(localized_text "${CYAN}▶ 正在拉取镜像并启动 Sub-Store 容器...${PLAIN}" "${CYAN}▶ Pulling the image and starting the Sub-Store container...${PLAIN}" "${CYAN}▶ Извлечение образа и запуск контейнера дополнительного магазина...${PLAIN}")"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}✅ Sub-Store 部署完成！${PLAIN}" "${GREEN}✅ Sub-Store deployment completed!${PLAIN}" "${GREEN}✅ Развертывание дополнительного магазина завершено!${PLAIN}")"
        echo -e "$(localized_text "本地后端地址：${BOLD}http://127.0.0.1:${backend_port}${backend_path}${PLAIN}" "Local backend address: ${BOLD}Http://127.0.0.1:${backend_port}${backend_path}${PLAIN}" "Локальный внутренний адрес: ${BOLD}http://127.0.0.1:${backend_port}${backend_path}${PLAIN}.")"
        echo -e "$(localized_text "HTTP-META 地址：${BOLD}http://127.0.0.1:${meta_port}${PLAIN}" "HTTP-META Address: ${BOLD}Http://127.0.0.1:${meta_port}${PLAIN}" "HTTP-META Адрес: ${BOLD}http://127.0.0.1:${meta_port}${PLAIN}")"
        echo -e "$(localized_text "账号密码：${YELLOW}无默认登录账号密码，请妥善保存上面的随机后端路径。${PLAIN}" "Account password: ${YELLOW}Has no default login account and password. Please properly save the random backend path above.${PLAIN}" "Пароль учетной записи: ${YELLOW}не имеет учетной записи и пароля по умолчанию. Пожалуйста, правильно сохраните случайный путь к серверу, указанный выше.${PLAIN}")"
        echo -e "$(localized_text "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}" "Configuration file: ${CYAN}${install_dir}/docker-compose.yml${PLAIN}" "Файл конфигурации: ${CYAN}${install_dir}/docker-compose.yml${PLAIN}")"
        print_public_https_reverse_proxy_hint
        echo -e "$(localized_text "${YELLOW}请定期备份 ${install_dir}/data。${PLAIN}" "${YELLOW}Please back up ${install_dir}/data regularly.${PLAIN}" "${YELLOW}Регулярно создавайте резервные копии ${install_dir}/data.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}已安全取消部署。${PLAIN}" "${BLUE}Has been safely undeployed.${PLAIN}" "${BLUE}благополучно деразвернут.${PLAIN}")"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_dockge() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}安装 Dockge (Docker Compose 管理面板)${PLAIN}" "${BOLD}Installation Dockge (Docker Compose management panel)${PLAIN}" "${BOLD}Установка Dockge (панель управления Docker Compose)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}Dockge 用来管理 compose.yaml stack，可创建、编辑、启动、停止、重启和更新镜像。${PLAIN}" "${YELLOW}Dockge is used to manage the compose.yaml stack and can create, edit, start, stop, restart and update images.${PLAIN}" "${YELLOW}Dockge используется для управления стеком compose.yaml и может создавать, редактировать, запускать, останавливать, перезапускать и обновлять изображения.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}注意：Dockge 会挂载 Docker socket，建议只监听本地地址，再通过 Caddy/Nginx 反代访问。${PLAIN}" "${YELLOW}Note: Dockge will mount the Docker socket. It is recommended to only listen to the local address and then access it through the Caddy/Nginx reverse proxy.${PLAIN}" "${YELLOW}Примечание: Dockge будет монтировать сокет Docker. Рекомендуется отслеживать только локальный адрес, а затем получать к нему доступ через Caddy/Nginx.${PLAIN}")"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    local install_dir="/opt/dockge"
    local stacks_dir="/opt/stacks"
    local dockge_bind_addr="127.0.0.1"
    local dockge_port="5001"

    dockge_bind_addr=$(ask_with_default "$(localized_text "Dockge 监听地址" "Dockge listening address" "Адрес прослушивания Dockge")" "$dockge_bind_addr")
    is_valid_listen_addr "$dockge_bind_addr" || { echo -e "$(localized_text "${RED}❌ 监听地址无效。${PLAIN}" "${RED}❌ The listening address is invalid.${PLAIN}" "${RED}❌ Неверный адрес прослушивания.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    while true; do
        dockge_port=$(ask_with_default "$(localized_text "Dockge 访问端口" "Dockge access port" "Порт доступа Dockge")" "$dockge_port")
        if is_valid_port "$dockge_port"; then break; fi
        echo -e "$(localized_text "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}" "${RED}❌ The port is invalid, please enter a number between 1-65535.${PLAIN}" "${RED}❌ Порт недействителен. Введите число от 1 до 65535.${PLAIN}")"
    done
    warn_if_public_bind "$(localized_text "Dockge 管理面板" "Dockge Management Panel" "Dockge Панель управления")" "$dockge_bind_addr" "$dockge_port" || return 1
    stacks_dir=$(ask_with_default "$(localized_text "Dockge stacks 目录" "Dockge stacks directory" "Каталог стеков Dockge")" "$stacks_dir")

    echo -e "$(localized_text "${YELLOW}Dockge 目录：${CYAN}${install_dir}${PLAIN}" "${YELLOW}Dockge Catalog: ${install_dir}${PLAIN}" "${YELLOW}Dockge Каталог: ${install_dir}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}Stacks 目录：${CYAN}${stacks_dir}${PLAIN}" "${YELLOW}Stacks Directory: ${stacks_dir}${PLAIN}" "${YELLOW}Каталог стеков: ${stacks_dir}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}监听地址：${CYAN}${dockge_bind_addr}:${dockge_port}${PLAIN}" "${YELLOW}Listening address: ${dockge_bind_addr}:${dockge_port}${PLAIN}" "${YELLOW}Адрес прослушивания : ${dockge_bind_addr}:${dockge_port}${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}账号密码说明：Dockge 不预设默认账号密码。${PLAIN}" "${YELLOW}Account password description: Dockge does not preset the default account password.${PLAIN}" "${YELLOW}Описание пароля учетной записи : Dockge не устанавливает пароль учетной записи по умолчанию.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}首次打开面板会进入初始化页，请在页面中创建管理员账号和密码。${PLAIN}" "${YELLOW}When opens the panel for the first time, it will enter the initialization page. Please create an administrator account and password on the page.${PLAIN}" "${YELLOW}Когда впервые откроет панель, он перейдет на страницу инициализации. Пожалуйста, создайте учетную запись администратора и пароль на странице.${PLAIN}")"
    echo -e "------------------------------------------------"

    local yn
    read_trimmed yn "$(localized_text "确认现在部署 Dockge 吗？(Y/n): " "Are you sure you want to deploy Dockge now? (Y/n):" "Вы уверены, что хотите развернуть Dockge сейчас? (Да/Нет):")"
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

        echo -e "$(localized_text "${CYAN}▶ 正在拉取镜像并启动 Dockge...${PLAIN}" "${CYAN}▶ Pulling the image and starting Dockge...${PLAIN}" "${CYAN}▶ Вытаскиваем образ и запускаем Dockge...${PLAIN}")"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}✅ Dockge 部署完成！${PLAIN}" "${GREEN}✅ Dockge deployment completed!${PLAIN}" "${GREEN}✅ Развертывание Dockge завершено!${PLAIN}")"
        echo -e "$(localized_text "访问地址：${BOLD}http://${dockge_bind_addr}:${dockge_port}${PLAIN}" "Access address: ${BOLD}Http://${dockge_bind_addr}:${dockge_port}${PLAIN}" "Адрес доступа: ${BOLD}http://${dockge_bind_addr}:${dockge_port}${PLAIN}")"
        echo -e "$(localized_text "Stacks 目录：${CYAN}${stacks_dir}${PLAIN}" "Stacks directory: ${CYAN}${stacks_dir}${PLAIN}" "Каталог стеков: ${CYAN}${stacks_dir}${PLAIN}")"
        echo -e "$(localized_text "账号密码：${YELLOW}无默认账号密码，首次打开页面创建管理员账号。${PLAIN}" "Account password: ${YELLOW}Has no default account password. Create an administrator account when you open the page for the first time.${PLAIN}" "Пароль учетной записи: ${YELLOW}не имеет пароля учетной записи по умолчанию. Создайте учетную запись администратора при первом открытии страницы.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}已有 compose 项目可返回部署菜单选择 [10] 迁移到 Dockge 后，在 Dockge 里扫描 stacks 目录。${PLAIN}" "${YELLOW}Already has the compose project. You can return to the deployment menu and select [10]. After migrating to Dockge, scan the stacks directory in Dockge.${PLAIN}" "${YELLOW}У уже есть проект compose. Вы можете вернуться в меню развертывания и выбрать [10]. После перехода на Dockge просканируйте каталог stacks в Dockge.${PLAIN}")"
    else
        echo -e "$(localized_text "${BLUE}已安全取消部署。${PLAIN}" "${BLUE}Has been safely undeployed.${PLAIN}" "${BLUE}благополучно деразвернут.${PLAIN}")"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

func_komari() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}安装 Komari 探针监控面板 (Docker Compose)${PLAIN}" "${BOLD}Install the Komari monitoring panel (Docker Compose)${PLAIN}" "${BOLD}Установка панели мониторинга Komari (Docker Compose)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}Komari 用于服务器探针监控。默认只监听本地地址。${PLAIN}" "${YELLOW}Komari monitors server probes and listens only on a local address by default.${PLAIN}" "${YELLOW}Komari отслеживает серверные агенты и по умолчанию слушает только локальный адрес.${PLAIN}")"
    print_public_https_reverse_proxy_hint
    echo -e "$(localized_text "${YELLOW}如果探针客户端需要直连端口，可把监听地址改为 0.0.0.0，并确认云安全组已放行。${PLAIN}" "${YELLOW}If the probe client needs to directly connect to the port, you can change the listening address to 0.0.0.0 and confirm that the cloud security group allows it.${PLAIN}" "${YELLOW}Если зондовому клиенту необходимо напрямую подключиться к порту, вы можете изменить адрес прослушивания на 0.0.0.0 и подтвердить, что группа безопасности облака освободила его.${PLAIN}")"
    echo -e "------------------------------------------------"

    ensure_docker_compose_ready || { read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    local install_dir="/opt/komari"
    local komari_bind_addr="127.0.0.1"
    local komari_port="25774"
    local custom_admin="n"
    local admin_username=""
    local admin_password=""
    local yn

    komari_bind_addr=$(ask_with_default "$(localized_text "Komari 监听地址" "Komari listening address" "Адрес прослушивания Комари")" "$komari_bind_addr")
    is_valid_listen_addr "$komari_bind_addr" || { echo -e "$(localized_text "${RED}❌ 监听地址无效。${PLAIN}" "${RED}❌ The listening address is invalid.${PLAIN}" "${RED}❌ Неверный адрес прослушивания.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return; }

    while true; do
        komari_port=$(ask_with_default "$(localized_text "Komari 访问端口" "Komari access port" "Порт доступа Комари")" "$komari_port")
        if is_valid_port "$komari_port"; then break; fi
        echo -e "$(localized_text "${RED}❌ 端口无效，请输入 1-65535 之间的数字。${PLAIN}" "${RED}❌ The port is invalid, please enter a number between 1-65535.${PLAIN}" "${RED}❌ Порт недействителен. Введите число от 1 до 65535.${PLAIN}")"
    done
    warn_if_public_bind "$(localized_text "Komari 探针监控面板" "Komari monitoring panel" "Панель мониторинга Komari")" "$komari_bind_addr" "$komari_port" || return 1

    read_trimmed custom_admin "$(localized_text "是否自定义初始管理员账号和密码？(Y/n，默认 y): " "Do you want to customize the initial administrator account and password? (Y/n, default y):" "Хотите настроить исходную учетную запись и пароль администратора? (Да/нет, по умолчанию y):")"
    if is_yes "$custom_admin"; then
        while true; do
            read_trimmed admin_username "$(localized_text "管理员用户名（默认 admin）: " "Administrator username (default admin):" "Имя пользователя администратора (администратор по умолчанию):")"
            admin_username="${admin_username:-admin}"
            if [[ "$admin_username" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
                break
            fi
            echo -e "$(localized_text "${RED}❌ 用户名只能包含字母、数字、点、下划线和短横线，长度 3-32。${PLAIN}" "${RED}❌ The username can only contain letters, numbers, dots, underscores and dashes, and the length is 3-32 characters.${PLAIN}" "${RED}❌ Имя пользователя может содержать только буквы, цифры, точки, подчеркивания и тире, а его длина составляет 3–32 символа.${PLAIN}")"
        done

        while true; do
            read_secret_trimmed admin_password "$(localized_text "管理员密码（至少 8 位，留空自动生成）: " "Administrator password (at least 8 characters, leave blank to automatically generate):" "Пароль администратора (не менее 8 символов, оставьте пустым для автоматической генерации):")"
            if [[ -z "$admin_password" ]]; then
                admin_password=$(generate_random_secret | cut -c1-24)
                echo -e "$(localized_text "${YELLOW}已自动生成管理员密码，部署完成后会显示一次，请及时保存。${PLAIN}" "${YELLOW}Has automatically generated the administrator password. It will be displayed once after the deployment is completed. Please save it in time.${PLAIN}" "${YELLOW}автоматически сгенерировал пароль администратора. Он будет отображен один раз после завершения развертывания. Пожалуйста, сохраните его вовремя.${PLAIN}")"
                break
            fi
            if [[ ${#admin_password} -ge 8 ]]; then
                break
            fi
            echo -e "$(localized_text "${RED}❌ 密码至少需要 8 位。${PLAIN}" "${RED}❌ Password requires at least 8 characters.${PLAIN}" "${RED}❌ Пароль должен содержать не менее 8 символов.${PLAIN}")"
        done
    fi

    echo -e "$(localized_text "${YELLOW}部署目录：${CYAN}${install_dir}${PLAIN}" "${YELLOW}Deployment directory: ${install_dir}${PLAIN}" "${YELLOW}Каталог развертывания : ${install_dir}.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}数据目录：${CYAN}${install_dir}/data${PLAIN}" "${YELLOW}Data directory: ${install_dir}/data${PLAIN}" "${YELLOW}Каталог данных : ${install_dir}/data${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}监听地址：${CYAN}${komari_bind_addr}:${komari_port}${PLAIN}" "${YELLOW}Listening address: ${komari_bind_addr}:${komari_port}${PLAIN}" "${YELLOW}Адрес прослушивания : ${komari_bind_addr}:${komari_port}${PLAIN}")"
    if [[ -n "$admin_username" ]]; then
        echo -e "$(localized_text "${YELLOW}初始管理员：${CYAN}${admin_username}${PLAIN}" "${YELLOW}Initial administrator: ${admin_username}${PLAIN}" "${YELLOW}первоначальный администратор: ${admin_username}${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}账号密码说明：未自定义时 Komari 会生成默认管理员账号。${PLAIN}" "${YELLOW}Account password description: Komari will generate a default administrator account when it is not customized.${PLAIN}" "${YELLOW}Описание пароля учетной записи : Komari создаст учетную запись администратора по умолчанию, если она не настроена.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}初始管理员：${CYAN}使用 Komari 默认生成账号，请安装后查看容器日志${PLAIN}" "${YELLOW}Initial administrator: uses Komari to generate an account by default. Please check the container log after installation.${PLAIN}" "${YELLOW}Начальный администратор : по умолчанию использует Komari для создания учетной записи. Пожалуйста, проверьте журнал контейнера после установки.${PLAIN}")"
    fi
    echo -e "------------------------------------------------"
    read_trimmed yn "$(localized_text "确认现在部署 Komari 吗？(Y/n): " "Are you sure you want to deploy Komari now? (Y/n):" "Вы уверены, что хотите развернуть Комари сейчас? (Да/Нет):")"
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

        echo -e "$(localized_text "${CYAN}▶ 正在拉取镜像并启动 Komari...${PLAIN}" "${CYAN}▶ Pulling the image and starting Komari...${PLAIN}" "${CYAN}▶ Вытаскиваем образ и запускаем Komari...${PLAIN}")"
        $DOCKER_COMPOSE_CMD up -d

        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}✅ Komari 部署完成！${PLAIN}" "${GREEN}✅ Komari deployment completed!${PLAIN}" "${GREEN}✅ Развертывание Комари завершено!${PLAIN}")"
        echo -e "$(localized_text "访问地址：${BOLD}http://${komari_bind_addr}:${komari_port}${PLAIN}" "Access address: ${BOLD}Http://${komari_bind_addr}:${komari_port}${PLAIN}" "Адрес доступа: ${BOLD}http://${komari_bind_addr}:${komari_port}${PLAIN}")"
        echo -e "$(localized_text "配置文件：${CYAN}${install_dir}/docker-compose.yml${PLAIN}" "Configuration file: ${CYAN}${install_dir}/docker-compose.yml${PLAIN}" "Файл конфигурации: ${CYAN}${install_dir}/docker-compose.yml${PLAIN}")"
        if [[ -n "$admin_username" ]]; then
            echo -e "$(localized_text "管理员账号：${BOLD}${admin_username}${PLAIN}" "Administrator account: ${BOLD}${admin_username}${PLAIN}" "Учетная запись администратора: ${BOLD}${admin_username}${PLAIN}")"
            echo -e "$(localized_text "管理员密码：${BOLD}${admin_password}${PLAIN}" "Administrator password: ${BOLD}${admin_password}${PLAIN}" "Пароль администратора: ${BOLD}${admin_password}${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}请及时保存密码，后续也可在 ${install_dir}/docker-compose.yml 中查看或修改。${PLAIN}" "${YELLOW}Please save the password in time, and you can view or modify it in ${install_dir}/docker-compose.yml later.${PLAIN}" "${YELLOW}Пожалуйста, сохраните пароль вовремя, и вы сможете просмотреть или изменить его в ${install_dir}/docker-compose.yml позже.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}默认管理员账号请查看日志：${CYAN}$DOCKER_COMPOSE_CMD logs komari${PLAIN}" "${YELLOW}Default administrator account, please check the logs: $DOCKER_COMPOSE_CMD logs komari${PLAIN}" "${YELLOW}Учетная запись администратора по умолчанию , проверьте журналы: $DOCKER_COMPOSE_CMD журналы komari${PLAIN}")"
        fi
        print_public_https_reverse_proxy_hint
    else
        echo -e "$(localized_text "${BLUE}已安全取消部署。${PLAIN}" "${BLUE}Has been safely undeployed.${PLAIN}" "${BLUE}благополучно деразвернут.${PLAIN}")"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}
