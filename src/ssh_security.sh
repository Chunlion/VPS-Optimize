# shellcheck shell=bash
# SSH hardening, SSH key workflows, authentication modes, and Fail2ban management.

ssh_service_restart() {
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
}

ssh_prepare_runtime_dir() {
    if [[ ! -d /run/sshd ]]; then
        mkdir -p /run/sshd 2>/dev/null || return 1
    fi
    chmod 755 /run/sshd 2>/dev/null || true
}

ssh_socket_unit_exists() {
    local unit="$1"
    local active_state enabled_state
    active_state=$(systemctl is-active "$unit" 2>/dev/null || true)
    enabled_state=$(systemctl is-enabled "$unit" 2>/dev/null || true)
    [[ "$active_state" == "active" ]] && return 0
    [[ "$enabled_state" == "enabled" || "$enabled_state" == "enabled-runtime" ]]
}

ssh_socket_units_for_host() {
    local unit
    for unit in ssh.socket sshd.socket; do
        if ssh_socket_unit_exists "$unit"; then
            echo "$unit"
        fi
    done
}

ssh_write_socket_port_dropins() {
    local port="$1"
    local unit dir found=false
    while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        found=true
        dir="/etc/systemd/system/${unit}.d"
        mkdir -p "$dir" || return 1
        cat > "${dir}/10-vps-optimize-port.conf" <<EOF
[Socket]
ListenStream=
ListenStream=${port}
EOF
    done < <(ssh_socket_units_for_host)
    $found
}

ssh_restart_socket_units() {
    local unit found=false ok=true
    systemctl daemon-reload >/dev/null 2>&1 || true
    while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        found=true
        systemctl restart "$unit" >/dev/null 2>&1 || ok=false
    done < <(ssh_socket_units_for_host)
    $found && $ok
}

ssh_restart_runtime() {
    local restarted=false
    if ssh_restart_socket_units; then
        restarted=true
    fi
    if ssh_service_restart; then
        restarted=true
    fi
    $restarted
}

ssh_write_sshd_port_dropin() {
    local port="$1"
    mkdir -p /etc/ssh/sshd_config.d 2>/dev/null || return 1
    cat > /etc/ssh/sshd_config.d/00-vps-optimize-port.conf <<EOF
# VPS-Optimize SSH port mirror
Port ${port}
EOF
}

ssh_write_auth_dropin() {
    local mode="$1"
    local interactive_key="$2"
    case "$mode" in
        key_only|key_preferred|password) ;;
        *) return 1 ;;
    esac
    mkdir -p /etc/ssh/sshd_config.d 2>/dev/null || return 1
    {
        echo "# VPS-Optimize SSH auth mode mirror"
        echo "PubkeyAuthentication yes"
        case "$mode" in
            key_only)
                echo "PasswordAuthentication no"
                echo "${interactive_key} no"
                ;;
            key_preferred|password)
                echo "PasswordAuthentication yes"
                echo "${interactive_key} yes"
                ;;
        esac
    } > /etc/ssh/sshd_config.d/00-vps-optimize-auth.conf
}

ssh_restore_auth_dropin() {
    local dropin="$1"
    local backup="$2"
    if [[ -n "$backup" && -f "$backup" ]]; then
        cp -p "$backup" "$dropin" 2>/dev/null || true
    else
        mkdir -p "$(dirname "$dropin")" 2>/dev/null || return 0
        cat > "$dropin" <<EOF
# VPS-Optimize SSH auth mode mirror disabled after rollback
EOF
    fi
}

ssh_reconcile_cloud_auth_dropins() {
    local mode="$1"
    local state_file="$2"
    local timestamp="$3"
    local dir="/etc/ssh/sshd_config.d"
    local conf tmp backup current_auth_dropin

    : > "$state_file" || return 1
    [[ -d "$dir" ]] || return 0
    current_auth_dropin="/etc/ssh/sshd_config.d/00-vps-optimize-auth.conf"

    for conf in "$dir"/*.conf; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == "$current_auth_dropin" ]] && continue
        tmp=$(mktemp /tmp/vps-sshd-dropin.XXXXXX) || return 1
        if ! awk -v mode="$mode" '
            function desired_for(key, lkey) {
                lkey = tolower(key)
                if (lkey == "pubkeyauthentication") return "yes"
                if (lkey == "passwordauthentication") return mode == "key_only" ? "no" : "yes"
                if (lkey == "kbdinteractiveauthentication") return mode == "key_only" ? "no" : "yes"
                if (lkey == "challengeresponseauthentication") return mode == "key_only" ? "no" : "yes"
                return ""
            }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
            /^[[:space:]]*Match[[:space:]]+/ { in_match = 1; print; next }
            in_match { print; next }
            {
                desired = desired_for($1)
                if (desired != "") {
                    if (tolower($2) == desired) {
                        print
                    } else {
                        print $1 " " desired " # VPS-Optimize reconciled cloud image setting"
                    }
                    next
                }
                print
            }
        ' "$conf" > "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
        if ! cmp -s "$conf" "$tmp"; then
            backup="${conf}.bak_auth_${timestamp}"
            if ! cp -p "$conf" "$backup"; then
                rm -f "$tmp"
                return 1
            fi
            if ! cp "$tmp" "$conf"; then
                cp -p "$backup" "$conf" 2>/dev/null || true
                rm -f "$tmp"
                return 1
            fi
            printf '%s\t%s\n' "$conf" "$backup" >> "$state_file"
        fi
        rm -f "$tmp"
    done
}

ssh_restore_cloud_auth_dropins() {
    local state_file="$1"
    local conf backup
    [[ -f "$state_file" ]] || return 0
    while IFS=$'\t' read -r conf backup; do
        [[ -n "$conf" && -n "$backup" && -f "$backup" ]] || continue
        cp -p "$backup" "$conf" 2>/dev/null || true
    done < "$state_file"
}

ssh_assert_auth_mode_effective() {
    local mode="$1"
    local expected effective
    expected="yes"
    [[ "$mode" == "key_only" ]] && expected="no"
    effective=$(ssh_effective_setting PasswordAuthentication)
    [[ -z "$effective" ]] && return 0
    if [[ "$effective" != "$expected" ]]; then
        echo -e "$(localized_text "${RED}❌ SSH 最终生效值仍为 PasswordAuthentication ${effective}，可能有更早的云镜像子配置覆盖。${PLAIN}" "${RED}❌ SSH The final effective value is still PasswordAuthentication ${effective}, which may be covered by earlier cloud image sub-configurations.${PLAIN}" "${RED}❌ SSH Окончательным действующим значением по-прежнему является PasswordAuthentication ${effective}, которое может быть включено в более ранние подконфигурации облачного образа.${PLAIN}")"
        return 1
    fi
}

ssh_rollback_port_change() {
    local backup_file="$1"
    local current_port="$2"
    local socket_managed="${3:-false}"
    cp -p "$backup_file" /etc/ssh/sshd_config 2>/dev/null || true
    ssh_write_sshd_port_dropin "$current_port" >/dev/null 2>&1 || true
    if $socket_managed; then
        ssh_write_socket_port_dropins "$current_port" >/dev/null 2>&1 || true
        ssh_restart_socket_units >/dev/null 2>&1 || true
    fi
    ssh_service_restart >/dev/null 2>&1 || true
}

ssh_effective_setting() {
    local key="$1"
    local sshd_bin value
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    if [[ -n "$sshd_bin" ]]; then
        ssh_prepare_runtime_dir >/dev/null 2>&1 || true
        value=$("$sshd_bin" -T 2>/dev/null | awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" '$1 == k {print $2; exit}')
        [[ -n "$value" ]] || return 1
        printf '%s' "$value"
        return 0
    fi
    return 1
}

ssh_public_key_is_valid() {
    local key="$1"
    [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]]
}

ssh_user_home() {
    local user="$1"
    getent passwd "$user" 2>/dev/null | awk -F: '{print $6; exit}'
}

ssh_authorized_keys_path() {
    local user="$1"
    local home_dir
    home_dir=$(ssh_user_home "$user")
    [[ -n "$home_dir" ]] || return 1
    printf '%s/.ssh/authorized_keys' "$home_dir"
}

ssh_authorized_key_count() {
    local user="$1"
    local key_file
    key_file=$(ssh_authorized_keys_path "$user" 2>/dev/null) || { echo 0; return 0; }
    [[ -r "$key_file" ]] || { echo 0; return 0; }
    grep -E '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-|sk-)' "$key_file" 2>/dev/null | wc -l | awk '{print $1}'
}

ssh_choose_user() {
    local default_user user
    default_user="${SUDO_USER:-root}"
    [[ "$default_user" == "root" || -n "$(getent passwd "$default_user" 2>/dev/null)" ]] || default_user="root"
    user=$(ask_with_default "$(localized_text "目标 Linux 用户" "Target Linux user" "Целевой пользователь Linux")" "$default_user")
    if ! getent passwd "$user" >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}❌ 用户 ${user} 不存在。${PLAIN}" "${RED}❌ User ${user} does not exist.${PLAIN}" "${RED}❌ Пользователь ${user} не существует.${PLAIN}")" >&2
        return 1
    fi
    printf '%s' "$user"
}

ssh_add_public_key_for_user() {
    local user="$1"
    local ssh_key key_file ssh_dir home_dir
    home_dir=$(ssh_user_home "$user")
    [[ -n "$home_dir" ]] || return 1
    key_file="${home_dir}/.ssh/authorized_keys"
    ssh_dir="${home_dir}/.ssh"
    echo -e "$(localized_text "👇 ${CYAN}请粘贴 ${user} 的 SSH 公钥，粘贴后按回车：${PLAIN}" "👇 ${CYAN}Please paste the SSH public key of ${user} and press Enter after pasting:${PLAIN}" "👇 ${CYAN}Вставьте открытый ключ SSH ${user} и нажмите Enter после вставки:${PLAIN}")"
    read -r ssh_key
    if [[ -z "$ssh_key" ]]; then
        echo -e "$(localized_text "${RED}❌ 输入为空，已取消。${PLAIN}" "${RED}❌ The input is empty and canceled.${PLAIN}" "${RED}❌ Ввод пуст и отменен.${PLAIN}")"
        return 1
    fi
    if ! ssh_public_key_is_valid "$ssh_key"; then
        echo -e "$(localized_text "${RED}❌ 公钥格式无效。支持 ssh-rsa、ssh-ed25519、ecdsa、FIDO2 sk-*。${PLAIN}" "${RED}❌ The public key format is invalid. Support ssh-rsa, ssh-ed25519, ecdsa, FIDO2 sk-*.${PLAIN}" "${RED}❌ Неверный формат открытого ключа. Поддержка ssh-rsa, ssh-ed25519, ecdsa, FIDO2 sk-*.${PLAIN}")"
        return 1
    fi
    mkdir -p "$ssh_dir" || return 1
    touch "$key_file" || return 1
    chmod 700 "$ssh_dir"
    chmod 600 "$key_file"
    if [[ "$user" != "root" ]]; then
        chown -R "$user:$user" "$ssh_dir" 2>/dev/null || true
    fi
    if grep -q -F -x "$ssh_key" "$key_file"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 该公钥已存在，无需重复添加。${PLAIN}" "${YELLOW}⚠️ This public key already exists and there is no need to add it again.${PLAIN}" "${YELLOW}⚠️ Этот открытый ключ уже существует, и нет необходимости добавлять его снова.${PLAIN}")"
        return 0
    fi
    printf '%s\n' "$ssh_key" >> "$key_file"
    echo -e "$(localized_text "${GREEN}✅ 已为 ${user} 添加 SSH 公钥。${PLAIN}" "${GREEN}✅ The SSH public key has been added for ${user}.${PLAIN}" "${GREEN}. Для ${user} добавлен открытый ключ SSH.${PLAIN}")"
}

ssh_apply_auth_mode() {
    local mode="$1"
    local label backup_file tmp_file sshd_bin interactive_key auth_dropin auth_dropin_backup auth_reconcile_state timestamp reconciled_count
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    [[ -n "$sshd_bin" && -f /etc/ssh/sshd_config ]] || {
        echo -e "$(localized_text "${RED}❌ 未找到 sshd 或 /etc/ssh/sshd_config，已取消。${PLAIN}" "${RED}❌ sshd or /etc/ssh/sshd_config not found, canceled.${PLAIN}" "${RED}❌ sshd или /etc/ssh/sshd_config не найден, отменен.${PLAIN}")"
        return 1
    }
    if ! ssh_prepare_runtime_dir; then
        echo -e "$(localized_text "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}" "${RED}❌ Unable to create /run/sshd, sshd Unable to complete syntax check. Please confirm that you currently have root privileges.${PLAIN}" "${RED}❌ Невозможно создать /run/sshd, sshd Невозможно завершить проверку синтаксиса. Пожалуйста, подтвердите, что у вас есть root-права.${PLAIN}")"
        return 1
    fi
    case "$mode" in
        key_only) label="$(localized_text "仅密钥登录（禁用密码）" "Key login only (password disabled)" "Вход только с помощью ключа (пароль отключен)")" ;;
        key_preferred|password) label="$(localized_text "密钥 + 密码登录（保留/恢复密码）" "Key + Password Login (Keep/Recover Password)" "Ключ + пароль для входа (Сохранить/Восстановить пароль)")" ;;
        *) return 1 ;;
    esac
    confirm_risk_action "$(localized_text "切换 SSH 登录模式：${label}" "Switch SSH login mode: ${label}" "Переключить режим входа в SSH: ${label}")" \
        "$(localized_text "/etc/ssh/sshd_config 与 /etc/ssh/sshd_config.d 登录认证配置" "/etc/ssh/sshd_config and /etc/ssh/sshd_config.d login authentication configuration" "Конфигурация аутентификации входа в систему /etc/ssh/sshd_config и /etc/ssh/sshd_config.d")" \
        "$(localized_text "使用本菜单的“密钥 + 密码登录”恢复密码登录，或从自动备份恢复 /etc/ssh/sshd_config 与对应子配置备份" "Use \"Key + Password Login\" in this menu to restore password login, or restore /etc/ssh/sshd_config and corresponding sub-configuration backup from automatic backup" "Используйте «Ключ + пароль для входа» в этом меню, чтобы восстановить вход с паролем или восстановить /etc/ssh/sshd_config и соответствующую резервную копию подконфигурации из автоматической резервной копии.")" \
        "$(localized_text "会同步处理 50-cloud-init.conf 等云镜像子配置；切到仅密钥登录前，必须先确认新 SSH 窗口能用私钥登录。" "Cloud image sub-configurations such as 50-cloud-init.conf will be processed synchronously; before switching to key-only login, you must first confirm that the new SSH window can be logged in with the private key." "Подконфигурации облачного образа, такие как 50-cloud-init.conf, будут обрабатываться синхронно; перед переключением на вход только по ключу вы должны сначала подтвердить, что в новое окно SSH можно войти с помощью закрытого ключа.")" || return 1

    timestamp=$(date +%s)
    interactive_key="KbdInteractiveAuthentication"
    if ! "$sshd_bin" -T 2>/dev/null | grep -qi '^kbdinteractiveauthentication '; then
        interactive_key="ChallengeResponseAuthentication"
    fi
    auth_dropin="/etc/ssh/sshd_config.d/00-vps-optimize-auth.conf"
    auth_dropin_backup=""
    auth_reconcile_state=$(mktemp /tmp/vps-sshd-reconcile.XXXXXX) || return 1
    backup_file="/etc/ssh/sshd_config.bak_auth_${timestamp}"
    cp -p /etc/ssh/sshd_config "$backup_file" || {
        echo -e "$(localized_text "${RED}❌ SSH 配置备份失败，已取消。${PLAIN}" "${RED}❌ SSH Configuration backup failed and has been cancelled.${PLAIN}" "${RED}❌ SSH Резервное копирование конфигурации не выполнено и было отменено.${PLAIN}")"
        rm -f "$auth_reconcile_state"
        return 1
    }
    if [[ -f "$auth_dropin" ]]; then
        auth_dropin_backup="${auth_dropin}.bak_auth_${timestamp}"
        cp -p "$auth_dropin" "$auth_dropin_backup" || {
            echo -e "$(localized_text "${RED}❌ SSH drop-in 配置备份失败，已取消。${PLAIN}" "${RED}❌ SSH drop-in configuration backup failed and has been cancelled.${PLAIN}" "${RED}❌ SSH Резервное копирование конфигурации Drop-In не удалось и было отменено.${PLAIN}")"
            rm -f "$auth_reconcile_state"
            return 1
        }
    fi
    tmp_file=$(mktemp /tmp/vps-sshd.XXXXXX) || { rm -f "$auth_reconcile_state"; return 1; }
    awk '
        /^# VPS-Optimize SSH auth mode begin$/ {skip=1; next}
        /^# VPS-Optimize SSH auth mode end$/ {skip=0; next}
        skip != 1 {print}
    ' /etc/ssh/sshd_config > "$tmp_file" || {
        rm -f "$tmp_file"
        rm -f "$auth_reconcile_state"
        return 1
    }
    {
        echo "# VPS-Optimize SSH auth mode begin"
        echo "PubkeyAuthentication yes"
        case "$mode" in
            key_only)
                echo "PasswordAuthentication no"
                echo "${interactive_key} no"
                ;;
            key_preferred|password)
                echo "PasswordAuthentication yes"
                echo "${interactive_key} yes"
                ;;
        esac
        echo "# VPS-Optimize SSH auth mode end"
        cat "$tmp_file"
    } > /etc/ssh/sshd_config
    rm -f "$tmp_file"

    if ! ssh_write_auth_dropin "$mode" "$interactive_key"; then
        echo -e "$(localized_text "${RED}❌ 写入 SSH drop-in 登录配置失败，正在回滚。${PLAIN}" "${RED}❌ Write SSH drop-in The login configuration failed and is being rolled back.${PLAIN}" "${RED}❌ Запись SSH. Не удалось настроить вход в систему, и выполняется откат.${PLAIN}")"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        rm -f "$auth_reconcile_state"
        return 1
    fi

    if ! ssh_reconcile_cloud_auth_dropins "$mode" "$auth_reconcile_state" "$timestamp"; then
        echo -e "$(localized_text "${RED}❌ 处理云镜像 SSH 子配置失败，正在回滚。${PLAIN}" "${RED}❌ Processing cloud image SSH sub-configuration failed and is being rolled back.${PLAIN}" "${RED}❌ Не удалось обработать облачный образ подконфигурации SSH, и выполняется откат.${PLAIN}")"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi

    if ! "$sshd_bin" -t; then
        echo -e "$(localized_text "${RED}❌ SSH 配置语法检查失败，正在回滚。${PLAIN}" "${RED}❌ SSH The configuration syntax check failed and is being rolled back.${PLAIN}" "${RED}❌ SSH Проверка синтаксиса конфигурации не удалась, и выполняется откат.${PLAIN}")"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi
    if ! ssh_assert_auth_mode_effective "$mode"; then
        echo -e "$(localized_text "${RED}❌ SSH 登录模式未真正生效，正在回滚。${PLAIN}" "${RED}❌ SSH The login mode has not really taken effect and is being rolled back.${PLAIN}" "${RED}❌ SSH Режим входа в систему на самом деле не вступил в силу и выполняется откат.${PLAIN}")"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi
    if ! ssh_restart_runtime; then
        echo -e "$(localized_text "${RED}❌ SSH 服务重启失败，正在回滚。${PLAIN}" "${RED}❌ SSH The service failed to restart and is being rolled back.${PLAIN}" "${RED}❌ SSH Службу не удалось перезапустить, и выполняется откат.${PLAIN}")"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        ssh_restart_runtime >/dev/null 2>&1 || true
        rm -f "$auth_reconcile_state"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}✅ SSH 登录模式已切换为：${label}${PLAIN}" "${GREEN}✅ SSH login mode has been switched to: ${label}${PLAIN}" "${GREEN}✅ SSH Режим входа в систему переключен на: ${label}${PLAIN}")"
    echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
    reconciled_count=$(wc -l < "$auth_reconcile_state" 2>/dev/null | awk '{print $1}')
    if [[ "$reconciled_count" =~ ^[0-9]+$ && "$reconciled_count" -gt 0 ]]; then
        echo -e "$(localized_text "${CYAN}已同步 ${reconciled_count} 个云镜像 SSH 子配置，例如 50-cloud-init.conf。${PLAIN}" "${CYAN}Has synchronized ${reconciled_count} cloud image SSH sub-configuration, such as 50-cloud-init.conf.${PLAIN}" "${CYAN}синхронизировал подконфигурацию облачного образа ${reconciled_count} SSH, например 50-cloud-init.conf.${PLAIN}")"
    fi
    rm -f "$auth_reconcile_state"
}

func_ssh_login_mode_menu() {
    local unknown_label
    unknown_label="$(localized_text "未知" "Unknown" "Неизвестно")"
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "SSH 安全中心 > 登录方式" "SSH Security Center > Authentication" "Центр безопасности SSH > Аутентификация")"
        echo -e "$(localized_text "${BOLD}🔐 SSH 登录方式${PLAIN}" "${BOLD}🔐 SSH authentication${PLAIN}" "${BOLD}🔐 Аутентификация SSH${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "PubkeyAuthentication       : ${CYAN}$(ssh_effective_setting PubkeyAuthentication || echo "$unknown_label")${PLAIN}"
        echo -e "PasswordAuthentication     : ${CYAN}$(ssh_effective_setting PasswordAuthentication || echo "$unknown_label")${PLAIN}"
        echo -e "KbdInteractiveAuthentication: ${CYAN}$(ssh_effective_setting KbdInteractiveAuthentication || echo "$unknown_label")${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 添加 / 更新用户 SSH 公钥${PLAIN} ${YELLOW}(不修改登录方式)${PLAIN}" "${GREEN}  1. Add or update a user's SSH key${PLAIN} ${YELLOW}(authentication mode unchanged)${PLAIN}" "${GREEN}  1. Добавить или обновить SSH-ключ пользователя${PLAIN} ${YELLOW}(режим входа не меняется)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 允许密钥和密码登录${PLAIN}" "${GREEN}  2. Allow key and password login${PLAIN}" "${GREEN}  2. Разрешить вход по ключу и паролю${PLAIN}")"
        echo -e "$(localized_text "${RED}  3. 仅允许密钥登录${PLAIN} ${YELLOW}(禁用密码登录)${PLAIN}" "${RED}  3. Allow key-only login${PLAIN} ${YELLOW}(disable password login)${PLAIN}" "${RED}  3. Разрешить вход только по ключу${PLAIN} ${YELLOW}(отключить пароль)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回上一级 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice user key_count
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1)
                user=$(ssh_choose_user) || { pause_return; continue; }
                ssh_add_public_key_for_user "$user"
                pause_return
                ;;
            2) ssh_apply_auth_mode key_preferred; pause_return ;;
            3)
                user=$(ssh_choose_user) || { pause_return; continue; }
                key_count=$(ssh_authorized_key_count "$user")
                if [[ "$key_count" -eq 0 ]]; then
                    echo -e "$(localized_text "${RED}❌ 用户 ${user} 还没有 authorized_keys，不能切到仅密钥登录。${PLAIN}" "${RED}❌ User ${user} has no authorized_keys and cannot switch to key-only login.${PLAIN}" "${RED}❌ У пользователя ${user} нет authorized_keys, поэтому вход только по ключу включить нельзя.${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}请先用本菜单 [1] 添加公钥，并用新 SSH 窗口测试成功。${PLAIN}" "${YELLOW}Please use this menu [1] to add the public key first, and test successfully with the new SSH window.${PLAIN}" "${YELLOW}Используйте это меню [1], чтобы сначала добавить открытый ключ и успешно протестировать его в новом окне SSH.${PLAIN}")"
                    pause_return
                    continue
                fi
                echo -e "$(localized_text "${YELLOW}检测到 ${user} 已有 ${key_count} 条公钥。切换后密码登录会被禁用。${PLAIN}" "${YELLOW}${user} has ${key_count} public key(s). Password login will be disabled.${PLAIN}" "${YELLOW}У пользователя ${user} есть открытые ключи: ${key_count}. Вход по паролю будет отключён.${PLAIN}")"
                ssh_apply_auth_mode key_only
                pause_return
                ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_ssh_security_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "SSH 安全中心" "SSH Security Center" "SSH Центр безопасности")"
        echo -e "$(localized_text "${BOLD}🛡️ SSH 安全中心${PLAIN}" "${BOLD}🛡️ SSH Security Center${PLAIN}" "${BOLD}🛡️ SSH Центр безопасности${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${GREEN}  1. 修改 SSH 端口${PLAIN}             ${YELLOW}(防失联校验和回滚)${PLAIN}" "${GREEN}1. Modify SSH port (lockout checks and rollback)${PLAIN}" "${GREEN}1. Измените порт SSH (проверки защиты от потери доступа и откат)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 用户密钥登录模式${PLAIN}         ${YELLOW}(添加公钥 / 切换密钥或密码登录)${PLAIN}" "${GREEN}2. User key login mode (add public key / switch key or password login)${PLAIN}" "${GREEN}2. Режим входа в систему с помощью ключа пользователя (добавление открытого ключа/переключение ключа или вход с паролем)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1) func_security ;;
            2) func_ssh_login_mode_menu ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"; sleep 1 ;;
        esac
    done
}

func_security() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🛡️ SSH 安全加固 (端口修改与防失联)${PLAIN}" "${BOLD}🛡️ SSH hardening (port change with lockout prevention)${PLAIN}" "${BOLD}🛡️ Защита SSH (смена порта с защитой от потери доступа)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}功能介绍：该脚本将修改 SSH 端口并配置防失联机制，确保服务稳定。${PLAIN}" "${YELLOW}Purpose: change the SSH port safely, validate the configuration, and roll back on failure.${PLAIN}" "${YELLOW}Назначение: безопасно сменить порт SSH, проверить конфигурацию и выполнить откат при ошибке.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    # 1. 极致精准：读取内存和进程，获取当前真实生效的 SSH 端口
    local current_p sshd_bin
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1)
    if [[ -z "$current_p" && -n "$sshd_bin" ]]; then
        ssh_prepare_runtime_dir >/dev/null 2>&1 || true
        current_p=$("$sshd_bin" -T 2>/dev/null | grep -i "^port " | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}

    local final_p
    # 交互提示优化：引导用户使用高位端口避开特权冲突
    read_trimmed final_p "$(localized_text "👉 当前生效的 SSH 端口为 $current_p, 请输入新端口 [10000-65535] (回车保持不变): " "👉 The currently effective SSH port is $current_p, please enter the new port [10000-65535] (press Enter to remain unchanged):" "👉 В настоящее время действующим портом SSH является $current_p. Введите новый порт [10000-65535] (нажмите Enter, чтобы сохранить изменения):")"
    final_p=${final_p:-$current_p}

    if [[ "$final_p" != "$current_p" ]]; then
        if [[ -z "$sshd_bin" ]]; then
            echo -e "$(localized_text "${RED}❌ 未找到 sshd 命令，无法安全校验 SSH 配置，已取消。${PLAIN}" "${RED}❌ The sshd command was not found. The SSH configuration cannot be safely verified and has been cancelled.${PLAIN}" "${RED}❌ Команда sshd не найдена. Конфигурацию SSH невозможно безопасно проверить, и она была отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi
        if ! command -v systemctl >/dev/null 2>&1; then
            echo -e "$(localized_text "${RED}❌ 未检测到 systemctl，无法安全重启 SSH 服务，已取消。${PLAIN}" "${RED}❌ systemctl not detected, cannot safely restart SSH service, canceled.${PLAIN}" "${RED}❌ systemctl не обнаружен, невозможно безопасно перезапустить службу SSH, отменено.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi
        if ! ssh_prepare_runtime_dir; then
            echo -e "$(localized_text "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}" "${RED}❌ Unable to create /run/sshd, sshd Unable to complete syntax check. Please confirm that you currently have root privileges.${PLAIN}" "${RED}❌ Невозможно создать /run/sshd, sshd Невозможно завершить проверку синтаксиса. Пожалуйста, подтвердите, что у вас есть root-права.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi
        # [严格检验] 端口合法性
        if ! [[ "$final_p" =~ ^[0-9]+$ ]] || (( 10#$final_p < 10000 || 10#$final_p > 65535 )); then
            echo -e "$(localized_text "${RED}❌ 错误：无效的端口号！必须是 10000-65535 之间的纯数字。${PLAIN}" "${RED}❌ Error: Invalid port number! Must be a number between 10000-65535.${PLAIN}" "${RED}❌ Ошибка: неверный номер порта! Должно быть чистым числом в диапазоне 10000–65535.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi

        echo -e "$(localized_text "${YELLOW}即将修改：/etc/ssh/sshd_config、/etc/ssh/sshd_config.d、SSH systemd socket/服务、系统防火墙放行规则。${PLAIN}" "${YELLOW}The following will be changed: /etc/ssh/sshd_config、/etc/ssh/sshd_config.d、SSH systemd socket/service, system firewall allow rules.${PLAIN}" "${YELLOW}скоро будет изменен: /etc/ssh/sshd_config、/etc/ssh/sshd_config.d、SSH systemd сокет/сервис, правила выпуска системного брандмауэра.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}请先确认云厂商安全组已经放行 ${final_p}/tcp，并保留当前 SSH 会话。${PLAIN}" "${YELLOW}Please first confirm that the cloud vendor security group allows ${final_p}/tcp and retain the current SSH session.${PLAIN}" "${YELLOW}Сначала подтвердите, что группа безопасности поставщика облака разрешила ${final_p}/tcp и сохраните текущий сеанс SSH.${PLAIN}")"
        confirm_danger "$(localized_text "修改 SSH 端口为 ${final_p}" "Modify the SSH port to ${final_p}" "Измените порт SSH на ${final_p}.")" "$(localized_text "新端口未放行会导致后续无法重新连接 SSH。" "If the new port is not released, SSH cannot be reconnected later." "Если новый порт не разрешён, SSH нельзя будет повторно подключить позже.")" "$(localized_text "脚本会先备份 sshd_config，校验语法失败或服务重启失败时自动回滚。" "The script will first back up sshd_config and automatically roll back when the syntax verification fails or the service restart fails." "Сценарий сначала создаст резервную копию sshd_config и автоматически откатится назад, если проверка синтаксиса не удалась или перезапуск службы не удался.")" || {
            echo -e "$(localized_text "${BLUE}已取消 SSH 端口修改。${PLAIN}" "${BLUE}Canceled the SSH port modification.${PLAIN}" "${BLUE}отменил модификацию порта SSH.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        }

        echo -e "$(localized_text "${CYAN}▶ 正在备份原生 SSH 配置文件...${PLAIN}" "${CYAN}▶ Backing up the native SSH configuration file...${PLAIN}" "${CYAN}▶ Резервное копирование собственного файла конфигурации SSH...${PLAIN}")"
        local backup_file="/etc/ssh/sshd_config.bak_$(date +%s)"
        if ! cp -p /etc/ssh/sshd_config "$backup_file"; then
            echo -e "$(localized_text "${RED}❌ SSH 配置备份失败，已取消修改。${PLAIN}" "${RED}❌ SSH The configuration backup failed and the modification has been cancelled.${PLAIN}" "${RED}❌ SSH Не удалось выполнить резервное копирование конфигурации, и изменение было отменено.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi

        # 2. 核心黑科技：安全的置顶替换
        # - 先安全删除所有带 Port 的行 (忽略注释符和空格)
        # - 然后在文件绝对第一行 (1i) 插入新端口，秒杀所有 include 配置覆盖！
        if ! sed -i '/^[[:space:]]*#\?Port /d' /etc/ssh/sshd_config || ! sed -i "1i Port $final_p" /etc/ssh/sshd_config; then
            echo -e "$(localized_text "${RED}❌ 写入 SSH 配置失败，正在恢复备份。${PLAIN}" "${RED}❌ Writing to SSH configuration failed and the backup is being restored.${PLAIN}" "${RED}❌ Не удалось записать конфигурацию SSH, резервная копия восстанавливается.${PLAIN}")"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi
        if ! ssh_write_sshd_port_dropin "$final_p"; then
            echo -e "$(localized_text "${RED}❌ 写入 SSH drop-in 端口配置失败，正在恢复备份。${PLAIN}" "${RED}❌ Write SSH drop-in port configuration failed and backup is being restored.${PLAIN}" "${RED}❌ Не удалось записать конфигурацию вставного порта SSH, и резервная копия восстанавливается.${PLAIN}")"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi

        # 3. [CentOS 专属] SELinux 放行
        if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
            echo -e "$(localized_text "${YELLOW}检测到 SELinux 开启，正在配置底层端口安全策略...${PLAIN}" "${YELLOW}Detects that SELinux is turned on, and the underlying port security policy is being configured...${PLAIN}" "${YELLOW}обнаруживает, что SELinux включен и базовая политика безопасности порта настраивается...${PLAIN}")"
            if command -v semanage >/dev/null 2>&1; then
                semanage port -a -t ssh_port_t -p tcp "$final_p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$final_p" 2>/dev/null
            else
                echo -e "$(localized_text "${RED}❌ 致命错误：缺少 semanage 工具！已触发安全回滚。${PLAIN}" "${RED}❌ Fatal error: Missing semanage tool! Safe rollback has been triggered.${PLAIN}" "${RED}❌ Неустранимая ошибка: отсутствует инструмент Semanage! Безопасный откат запущен.${PLAIN}")"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                return
            fi
        fi

        # 4. 防失联核心：验证新配置语法
        if ! "$sshd_bin" -t; then
            echo -e "$(localized_text "${RED}❌ 致命错误：SSH 配置存在语法异常！正在全盘恢复...${PLAIN}" "${RED}❌ Fatal error: There is a syntax exception in the SSH configuration! Full recovery in progress...${PLAIN}" "${RED}❌ Неустранимая ошибка: в конфигурации SSH имеется синтаксическое исключение! Выполняется полное восстановление...${PLAIN}")"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi
        
        # 5. 放行全栈防火墙
        if command -v ufw >/dev/null 2>&1; then ufw allow "$final_p"/tcp >/dev/null 2>&1; fi
        if command -v firewall-cmd >/dev/null 2>&1; then 
            firewall-cmd --permanent --add-port="$final_p"/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT -p tcp --dport "$final_p" -j ACCEPT 2>/dev/null || true
        fi
        
        # 6. systemd Socket 端口接管：兼容 Ubuntu/Debian 云镜像的 ssh.socket 与 sshd.socket
        local socket_managed=false socket_units
        socket_units=$(ssh_socket_units_for_host | tr '\n' ' ')
        if [[ -n "$socket_units" ]]; then
            echo -e "$(localized_text "${YELLOW}检测到 SSH socket (${socket_units})，正在同步底层监听端口...${PLAIN}" "${YELLOW}Detects SSH socket (${socket_units}) and is synchronizing the underlying listening port...${PLAIN}" "${YELLOW}обнаруживает сокет SSH (${socket_units}) и синхронизирует базовый порт прослушивания...${PLAIN}")"
            if ssh_write_socket_port_dropins "$final_p"; then
                socket_managed=true
                systemctl daemon-reload >/dev/null 2>&1 || true
            else
                echo -e "$(localized_text "${RED}❌ 写入 SSH socket drop-in 失败，正在回滚。${PLAIN}" "${RED}❌ Writing to SSH socket drop-in failed and is being rolled back.${PLAIN}" "${RED}❌ Не удалось выполнить запись в сокет SSH, и выполняется откат.${PLAIN}")"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
                return
            fi
        fi
        
        # 7. 严格隔离的服务重启逻辑
        echo -e "$(localized_text "${CYAN}▶ 正在重启底层 SSH 引擎...${PLAIN}" "${CYAN}▶ Restarting the underlying SSH engine...${PLAIN}" "${CYAN}▶ Перезапуск базового механизма SSH...${PLAIN}")"
        local restart_ok=false
        if $socket_managed; then
            if ssh_restart_socket_units; then
                restart_ok=true
                ssh_service_restart >/dev/null 2>&1 || true
            fi
        else
            ssh_service_restart && restart_ok=true
        fi
        
        if $restart_ok; then
            echo -e "$(localized_text "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行！${PLAIN}" "${GREEN}✅ The SSH port has been successfully changed to $final_p and automatically released!${PLAIN}" "${GREEN}. Порт SSH был успешно изменен на $final_p и автоматически освобожден!${PLAIN}")"
            echo -e "$(localized_text "${CYAN}配置备份已保留：${backup_file}${PLAIN}" "${CYAN}Configuration backup has been retained: ${backup_file}${PLAIN}" "${CYAN}Резервная копия конфигурации сохранена: ${backup_file}.${PLAIN}")"
        else
            echo -e "$(localized_text "${RED}❌ 致命错误：重启 SSH 服务失败！正在回滚至原端口...${PLAIN}" "${RED}❌ Fatal error: Restart SSH service failed! Rolling back to original port...${PLAIN}" "${RED}❌ Неустранимая ошибка: не удалось перезапустить службу SSH! Откат к исходному порту...${PLAIN}")"
            ssh_rollback_port_change "$backup_file" "$current_p" "$socket_managed"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        fi
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
        echo -e "$(localized_text "${YELLOW}⚠️ 终极保命提示：${PLAIN}" "${YELLOW}⚠️ The ultimate life-saving tip:${PLAIN}" "${YELLOW}⚠️ Главный совет по спасению жизни:${PLAIN}")"
        echo -e "$(localized_text "现在的这扇 SSH 窗口【千万不要关闭】！" "The current SSH window [Never close it]!" "Текущее окно SSH [Никогда не закрывайте]!")"
        echo -e "$(localized_text "请立刻使用新端口 $final_p 新建一个连接进行测试。" "Please immediately use the new port $final_p to create a new connection for testing." "Пожалуйста, немедленно используйте новый порт $final_p, чтобы создать новое соединение для тестирования.")"
        echo -e "$(localized_text "如果云平台有【安全组】，请确保也已放行 $final_p 端口！" "If the cloud platform has a [security group], please ensure that the $final_p port has also been released!" "Если у облачной платформы есть [группа безопасности], убедитесь, что порт $final_p также освобожден!")"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
    else
        echo -e "$(localized_text "${BLUE}端口未做更改。${PLAIN}" "${BLUE}The port has not been changed.${PLAIN}" "${BLUE}Порт не был изменен.${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 新增：Fail2ban 防爆破系统管理 (抽象精简版)
# ---------------------------------------------------------
func_fail2ban() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}Fail2ban 防爆破系统管理${PLAIN}" "${BOLD}Fail2ban Explosion-proof system management${PLAIN}" "${BOLD}Fail2ban Управление взрывозащищенной системой${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    
    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -z "$current_p" ]]; then
        current_p=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}
    
    echo -e "$(localized_text "${YELLOW}👉 当前系统检测到的 SSH 端口为: ${GREEN}$current_p${PLAIN}" "${YELLOW}👉 The current SSH port detected by the system is: $current_p${PLAIN}" "${YELLOW}👉 Текущий порт SSH, обнаруженный системой: $current_p${PLAIN}")"
    echo -e "------------------------------------------------"
    
    local f2b_status="$(localized_text "${RED}未安装${PLAIN}" "${RED}Is not installed${PLAIN}" "${RED}не установлен${PLAIN}")"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_status="$(localized_text "${GREEN}已运行${PLAIN}" "${GREEN}Has run${PLAIN}" "${GREEN}запустил${PLAIN}")"
        else
            f2b_status="$(localized_text "${YELLOW}已停止${PLAIN}" "${YELLOW}Has stopped${PLAIN}" "${YELLOW}остановлен${PLAIN}")"
        fi
    fi
    
    echo -e "$(localized_text "当前 Fail2ban 状态: [ $f2b_status ]" "Current Fail2ban status: [ $f2b_status ]" "Текущий статус Fail2ban: [ $f2b_status ]")"
    echo -e "$(localized_text "  ${GREEN}1.${PLAIN} 安装并配置 Fail2ban ${YELLOW}(自动使用当前 SSH 端口)${PLAIN}" "${GREEN}1.${PLAIN} Install and configure Fail2ban ${YELLOW}(use the current SSH port)${PLAIN}" "${GREEN}1.${PLAIN} Установить и настроить Fail2ban ${YELLOW}(использовать текущий порт SSH)${PLAIN}")"
    echo -e "$(localized_text "  ${BLUE}2.${PLAIN} 更新防护端口 ${YELLOW}(修改 SSH 端口后使用)${PLAIN}" "${BLUE}2.${PLAIN} Update protected port ${YELLOW}(after changing the SSH port)${PLAIN}" "${BLUE}2.${PLAIN} Обновить защищаемый порт ${YELLOW}(после смены порта SSH)${PLAIN}")"
    echo -e "$(localized_text "  ${RED}3.${PLAIN} 彻底卸载 Fail2ban" "${RED}3.${PLAIN} Completely uninstall Fail2ban" "${RED}3.${PLAIN} Полностью удалить Fail2ban")"
    echo -e "$(localized_text "  ${RED}0.${PLAIN} 返回主菜单 / q 返回" "${RED}0.${PLAIN} Return to main menu / q Return" "${RED}0.${PLAIN} Возврат в главное меню / q Возврат")"
    echo -e "------------------------------------------------"
    
    local f_choice
    read_trimmed f_choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
    
    case $f_choice in
        1|2)
            if [[ "$f_choice" == "1" ]]; then
                echo -e "$(localized_text "${CYAN}正在安装 Fail2ban...${PLAIN}" "${CYAN}Is installing Fail2ban...${PLAIN}" "${CYAN}устанавливает Fail2ban...${PLAIN}")"
                if is_debian; then
                    install_pkg fail2ban python3-systemd
                else
                    install_pkg fail2ban
                fi
            fi
            
            if command -v fail2ban-server >/dev/null 2>&1; then
                echo -e "$(localized_text "${CYAN}正在写入配置并绑定端口 $current_p ...${PLAIN}" "${CYAN}Is writing configuration and binding port $current_p ...${PLAIN}" "${CYAN}записывает конфигурацию и порт привязки $current_p ...${PLAIN}")"
                local f2b_backend="auto"
                if command -v journalctl >/dev/null 2>&1; then
                    f2b_backend="systemd"
                fi
                cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = $current_p
backend = $f2b_backend
EOF
                systemctl enable fail2ban >/dev/null 2>&1
                systemctl restart fail2ban >/dev/null 2>&1
                if systemctl is-active --quiet fail2ban; then
                    echo -e "$(localized_text "${GREEN}✅ Fail2ban 配置完成并已启动！(保护端口: $current_p，日志后端: $f2b_backend)${PLAIN}" "${GREEN}✅ Fail2ban is configured and started! (Protected port: $current_p, log backend: $f2b_backend)${PLAIN}" "${GREEN}✅ Fail2ban настроен и запущен! (Защищенный порт: $current_p, бэкенд журнала: $f2b_backend)${PLAIN}")"
                    echo -e "$(localized_text "${YELLOW}💡 规则：10分钟内密码错误5次，自动封禁该IP 24小时。${PLAIN}" "${YELLOW}💡 Rules: If the password is incorrect 5 times within 10 minutes, the IP will be automatically blocked for 24 hours.${PLAIN}" "${YELLOW}💡 Правила: При неверном пароле 5 раз в течение 10 минут IP автоматически блокируется на 24 часа.${PLAIN}")"
                else
                    echo -e "$(localized_text "${RED}❌ Fail2ban 启动失败，正在显示关键日志：${PLAIN}" "${RED}❌ Fail2ban failed to start, the key log is being displayed:${PLAIN}" "${RED}❌ Fail2ban не удалось запустить, отображается журнал ключей:${PLAIN}")"
                    fail2ban-client -t 2>/dev/null || true
                    journalctl -u fail2ban -n 20 --no-pager 2>/dev/null || true
                fi
            else
                echo -e "$(localized_text "${RED}❌ Fail2ban 安装或检测失败，请检查网络源。${PLAIN}" "${RED}❌ Fail2ban Installation or detection failed, please check the network source.${PLAIN}" "${RED}❌ Fail2ban Не удалось установить или обнаружить, проверьте сетевой источник.${PLAIN}")"
            fi
            ;;
        3)
            echo -e "$(localized_text "${CYAN}正在卸载 Fail2ban...${PLAIN}" "${CYAN}Is uninstalling Fail2ban...${PLAIN}" "${CYAN}удаляет Fail2ban...${PLAIN}")"
            remove_pkg fail2ban # <--- 核心修改：一句话极简卸载
            quarantine_path /etc/fail2ban "/etc/vps-optimize/quarantine" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ Fail2ban 已卸载，旧配置已隔离到 /etc/vps-optimize/quarantine。${PLAIN}" "${GREEN}✅ Fail2ban has been uninstalled and the old configuration has been isolated to /etc/vps-optimize/quarantine.${PLAIN}" "${GREEN}✅ Fail2ban удален, а старая конфигурация изолирована от /etc/vps-optimize/quarantine.${PLAIN}")"
            ;;
        0|q|Q) return ;;
        *) echo -e "$(localized_text "${RED}❌ 无效的输入！${PLAIN}" "${RED}❌ Invalid input!${PLAIN}" "${RED}❌ Неверный ввод!${PLAIN}")"; sleep 1 ;;
    esac
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 新增功能：添加 SSH 公钥登录
# ---------------------------------------------------------
func_add_ssh_key() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🔑 添加 SSH 公钥登录 (免密安全认证)${PLAIN}" "${BOLD}🔑 Add SSH public key login (password-free security authentication)${PLAIN}" "${BOLD}🔑 Добавить вход с открытым ключом SSH (безопасная аутентификация без пароля)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${YELLOW}使用 SSH 密钥登录不仅免去输密码的烦恼，更能彻底免疫密码爆破！${PLAIN}" "${YELLOW}Using the SSH key to log in not only eliminates the trouble of entering passwords, but also provides complete immunity to password blasting!${PLAIN}" "${YELLOW}Использование ключа SSH для входа в систему не только избавляет от проблем с вводом паролей, но и обеспечивает полную невосприимчивость к взлому паролей!${PLAIN}")"
    echo -e "$(localized_text "请准备好您的公钥 (通常以 ssh-rsa, ssh-ed25519、ecdsa 或 sk-* 开头)。" "Please have your public key ready (usually starting with ssh-rsa, ssh-ed25519, ecdsa or sk-*)." "Подготовьте свой открытый ключ (обычно начинающийся с ssh-rsa, ssh-ed25519, ecdsa или sk-*).")"
    echo -e "------------------------------------------------"
    local user enable_mode
    user=$(ssh_choose_user) || { read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"; return; }
    if ssh_add_public_key_for_user "$user"; then
        echo -e "$(localized_text "${GREEN}✅ 公钥添加完成。请立刻新开一个 SSH 窗口测试私钥登录。${PLAIN}" "${GREEN}✅ The public key has been added. Please open a new SSH window immediately to test private key login.${PLAIN}" "${GREEN}✅ Открытый ключ добавлен. Немедленно откройте новое окно SSH, чтобы проверить вход в систему с закрытым ключом.${PLAIN}")"
        read_trimmed enable_mode "$(localized_text "是否同时启用“密钥 + 密码登录（保留/恢复密码）”模式？(y/N，默认 N): " "Also enable key + password login? (y/N, default N): " "Также включить вход по ключу и паролю? (y/N, по умолчанию N): ")"
        if is_yes "$enable_mode"; then
            ssh_apply_auth_mode key_preferred || true
        fi
        echo -e "$(localized_text "${YELLOW}确认私钥登录 100% 成功后，可进入 [6 SSH 安全中心] -> [2 用户密钥登录模式] 禁用密码登录。${PLAIN}" "${YELLOW}After confirms that private key login is 100% successful, you can enter [6 SSH Security Center] -> [2 User Key Login Mode] to disable password login.${PLAIN}" "${YELLOW}После того, как подтвердит, что вход с закрытым ключом прошел на 100% успешно, вы можете ввести [6 SSH Центр безопасности] -> [2 Режим входа с помощью ключа пользователя], чтобы отключить вход с паролем.${PLAIN}")"
    fi
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 5. Docker 深度管理 (重构版：非破坏性修改与防宕机回滚)
# ---------------------------------------------------------
