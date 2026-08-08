# shellcheck shell=bash
# Caddy and nginx-stream dependency installation for the 443 stack.

install_caddy_if_needed() {
    command -v caddy >/dev/null 2>&1 && return 0
    echo -e "$(localized_text "${CYAN}▶ 未检测到 Caddy，正在安装...${PLAIN}" "${CYAN}▶ Caddy not detected, installing...${PLAIN}" "${CYAN}▶ Caddy не обнаружен, устанавливается...${PLAIN}")"
    if is_debian; then
        local key_tmp repo_tmp
        install_pkg debian-keyring debian-archive-keyring apt-transport-https curl gpg || return 1
        command -v curl >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 缺少 curl，无法添加 Caddy 源。${PLAIN}" "${RED}❌ curl is missing and the Caddy source cannot be added.${PLAIN}" "${RED}❌ curl отсутствует, и источник Caddy не может быть добавлен.${PLAIN}")"; return 1; }
        command -v gpg >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 缺少 gpg，无法校验 Caddy 源。${PLAIN}" "${RED}❌ Missing gpg, unable to verify Caddy source.${PLAIN}" "${RED}❌ Отсутствует gpg, невозможно проверить источник Caddy.${PLAIN}")"; return 1; }
        key_tmp=$(mktemp /tmp/caddy-key.XXXXXX) || return 1
        repo_tmp=$(mktemp /tmp/caddy-repo.XXXXXX) || { rm -f "$key_tmp"; return 1; }
        if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o "$key_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy GPG key 下载失败。${PLAIN}" "${RED}❌ Caddy GPG key download failed.${PLAIN}" "${RED}❌ Caddy Загрузка ключа GPG не удалась.${PLAIN}")"
            return 1
        fi
        if ! gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg "$key_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy GPG key 写入失败。${PLAIN}" "${RED}❌ Caddy GPG key writing failed.${PLAIN}" "${RED}❌ Caddy Не удалось записать ключ GPG.${PLAIN}")"
            return 1
        fi
        if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o "$repo_tmp"; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy APT 源配置下载失败。${PLAIN}" "${RED}❌ Caddy APT source configuration download failed.${PLAIN}" "${RED}❌ Caddy Не удалось загрузить исходную конфигурацию APT.${PLAIN}")"
            return 1
        fi
        if ! mv "$repo_tmp" /etc/apt/sources.list.d/caddy-stable.list; then
            rm -f "$key_tmp"
            rm -f "$repo_tmp"
            echo -e "$(localized_text "${RED}❌ Caddy APT 源配置写入失败。${PLAIN}" "${RED}❌ Caddy APT source configuration failed to write.${PLAIN}" "${RED}❌ Caddy Не удалось записать исходную конфигурацию APT.${PLAIN}")"
            return 1
        fi
        rm -f "$key_tmp"
        install_pkg caddy || return 1
    elif is_redhat; then
        install_pkg yum-utils || true
        if command -v yum-config-manager >/dev/null 2>&1; then
            yum-config-manager --add-repo https://openrepo.io/repo/caddy/caddy.repo >/dev/null 2>&1 || return 1
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 yum-config-manager，将尝试直接从系统源安装 Caddy。${PLAIN}" "${YELLOW}⚠️ yum-config-manager not detected, will try to install Caddy directly from system sources.${PLAIN}" "${YELLOW}⚠️ yum-config-manager не обнаружен, попытается установить Caddy непосредственно из системных источников.${PLAIN}")"
        fi
        install_pkg caddy || return 1
    else
        echo -e "$(localized_text "${RED}❌ 暂不支持当前系统自动安装 Caddy。${PLAIN}" "${RED}❌ The current system does not support automatic installation of Caddy.${PLAIN}" "${RED}❌ Текущая система не поддерживает автоматическую установку Caddy.${PLAIN}")"
        return 1
    fi
    command -v caddy >/dev/null 2>&1
}

ensure_caddy_module_layout() {
    mkdir -p /etc/caddy/conf.d || return 1
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        cat <<'EOF' > /etc/caddy/Caddyfile
import conf.d/*
EOF
        return 0
    fi
    if ! grep -q "import conf.d/\*" /etc/caddy/Caddyfile; then
        cp -p /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak_$(date +%s)" 2>/dev/null || true
        printf '\nimport conf.d/*\n' >> /etc/caddy/Caddyfile
    fi
}

install_nginx_stream_stack() {
    echo -e "$(localized_text "${CYAN}▶ 正在检查 Nginx stream 组件...${PLAIN}" "${CYAN}▶ Checking Nginx stream assembly...${PLAIN}" "${CYAN}▶ Проверка сборки Nginx stream...${PLAIN}")"
    local need_install=0
    local nginx_build
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 Nginx，正在安装基础组件...${PLAIN}" "${YELLOW}⚠️ Nginx not detected, installing basic components...${PLAIN}" "${YELLOW}⚠️ Nginx не обнаружен, установка основных компонентов...${PLAIN}")"
        need_install=1
    else
        nginx_build=$(nginx -V 2>&1 || true)
    fi

    if [[ "$need_install" -eq 0 ]]; then
        if [[ "$nginx_build" == *"--with-stream=dynamic"* ]]; then
            if grep -Rqs 'load_module .*ngx_stream_module\.so' /etc/nginx/nginx.conf /etc/nginx/modules-enabled 2>/dev/null; then
                echo -e "$(localized_text "${GREEN}✅ 已检测到 Nginx stream 动态模块加载配置，跳过安装步骤。${PLAIN}" "${GREEN}✅ The Nginx stream dynamic module loading configuration has been detected, skipping the installation step.${PLAIN}" "${GREEN}✅ Обнаружена конфигурация динамической загрузки модуля Nginx stream, этап установки пропущен.${PLAIN}")"
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Nginx 支持动态 stream 模块，但未确认模块已加载，正在尝试补齐模块...${PLAIN}" "${YELLOW}⚠️ Nginx supports dynamic stream module, but the module has not been confirmed to be loaded. Trying to complete the module...${PLAIN}" "${YELLOW}⚠️ Nginx поддерживает модуль динамического потока, но загрузка модуля не подтверждена. Пытаюсь завершить модуль...${PLAIN}")"
                need_install=1
            fi
        elif [[ "$nginx_build" == *"--with-stream"* || "$nginx_build" == *"--with-stream_ssl_preread_module"* ]]; then
            echo -e "$(localized_text "${GREEN}✅ 已检测到 Nginx stream 静态支持，跳过安装步骤。${PLAIN}" "${GREEN}✅ Static support for Nginx stream has been detected, skipping the installation step.${PLAIN}" "${GREEN}✅ Обнаружена статическая поддержка Nginx stream, пропуская этап установки.${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 未确认 Nginx stream 支持，正在尝试补齐模块...${PLAIN}" "${YELLOW}⚠️ Unconfirmed Nginx stream support, trying to complete the module...${PLAIN}" "${YELLOW}⚠️ Неподтвержденная поддержка Nginx stream, пытаюсь завершить модуль...${PLAIN}")"
            need_install=1
        fi
    fi

    if [[ "$need_install" -eq 1 ]]; then
        if is_debian; then
            install_pkg nginx libnginx-mod-stream
        elif is_redhat; then
            install_pkg nginx
            install_pkg nginx-mod-stream || echo -e "$(localized_text "${YELLOW}⚠️ nginx-mod-stream 安装失败或仓库未提供，将继续检测 Nginx stream 支持。${PLAIN}" "${YELLOW}⚠️ If the installation of nginx-mod-stream fails or the warehouse does not provide it, Nginx stream support will continue to be detected.${PLAIN}" "${YELLOW}⚠️ Если установка nginx-mod-stream не удалась или склад не предоставляет его, поддержка Nginx stream продолжит обнаруживаться.${PLAIN}")"
        fi
    fi
    command -v nginx >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ Nginx 安装失败。${PLAIN}" "${RED}❌ Nginx installation failed.${PLAIN}" "${RED}❌ Установка Nginx не удалась.${PLAIN}")"; return 1; }
    mkdir -p /etc/nginx/stream.d
    if ! grep -Eq '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        cat <<'EOF' >> /etc/nginx/nginx.conf

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF
    elif ! grep -q '/etc/nginx/stream.d/\*.conf' /etc/nginx/nginx.conf 2>/dev/null; then
        cp -f /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak_$(date +%s)" 2>/dev/null || true
        sed -i '/^[[:space:]]*stream[[:space:]]*{/a\    include /etc/nginx/stream.d/*.conf;' /etc/nginx/nginx.conf
    fi
}

harden_nginx_public_errors() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local drop_conf="/etc/nginx/conf.d/00-vps-default-drop.conf"
    local quarantine_dir="/etc/vps-optimize/nginx-default-sites-disabled_$(date +%s)"
    local moved=0
    local default_file

    command -v nginx >/dev/null 2>&1 || return 0
    mkdir -p /etc/nginx/conf.d /etc/vps-optimize

    if [[ -f "$nginx_conf" ]]; then
        if grep -Eq '^[#[:space:]]*server_tokens[[:space:]]+' "$nginx_conf"; then
            sed -i 's/^[#[:space:]]*server_tokens[[:space:]].*;/    server_tokens off;/' "$nginx_conf"
        elif grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$nginx_conf"; then
            sed -i '/^[[:space:]]*http[[:space:]]*{/a\    server_tokens off;' "$nginx_conf"
        fi
    fi

    for default_file in \
        /etc/nginx/sites-enabled/default \
        /etc/nginx/sites-available/default \
        /etc/nginx/conf.d/default.conf; do
        if [[ -e "$default_file" ]]; then
            mkdir -p "$quarantine_dir"
            mv "$default_file" "$quarantine_dir/" >/dev/null 2>&1 && ((moved++))
        fi
    done

    cat <<'EOF' > "$drop_conf"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
EOF

    if [[ "$moved" -gt 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 已隔离 ${moved} 个 Nginx 默认站点配置到：${quarantine_dir}${PLAIN}" "${YELLOW}⚠️ Isolated ${moved} Nginx The default site is configured to: ${quarantine_dir}${PLAIN}" "${YELLOW}⚠️ Изолированный ${moved} Nginx Сайт по умолчанию настроен на: ${quarantine_dir}${PLAIN}")"
    fi
    echo -e "$(localized_text "${GREEN}✅ 已关闭 Nginx 版本号显示，并写入 80 端口默认丢弃规则。${PLAIN}" "${GREEN}✅ The Nginx version number display has been turned off, and the default discard rule of port 80 has been written.${PLAIN}" "${GREEN}. Отображение номера версии Nginx отключено и записано правило отбрасывания по умолчанию для порта 80.${PLAIN}")"
}
