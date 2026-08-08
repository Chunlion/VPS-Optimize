# shellcheck shell=bash
# SSH authentication drop-ins, cloud-image reconciliation, and authorized-key helpers.

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
