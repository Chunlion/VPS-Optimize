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
        echo -e "${RED}❌ SSH 最终生效值仍为 PasswordAuthentication ${effective}，可能有更早的云镜像子配置覆盖。${PLAIN}"
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
    user=$(ask_with_default "目标 Linux 用户" "$default_user")
    if ! getent passwd "$user" >/dev/null 2>&1; then
        echo -e "${RED}❌ 用户 ${user} 不存在。${PLAIN}" >&2
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
    echo -e "👇 ${CYAN}请粘贴 ${user} 的 SSH 公钥，粘贴后按回车：${PLAIN}"
    read -r ssh_key
    if [[ -z "$ssh_key" ]]; then
        echo -e "${RED}❌ 输入为空，已取消。${PLAIN}"
        return 1
    fi
    if ! ssh_public_key_is_valid "$ssh_key"; then
        echo -e "${RED}❌ 公钥格式无效。支持 ssh-rsa、ssh-ed25519、ecdsa、FIDO2 sk-*。${PLAIN}"
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
        echo -e "${YELLOW}⚠️ 该公钥已存在，无需重复添加。${PLAIN}"
        return 0
    fi
    printf '%s\n' "$ssh_key" >> "$key_file"
    echo -e "${GREEN}✅ 已为 ${user} 添加 SSH 公钥。${PLAIN}"
}

ssh_apply_auth_mode() {
    local mode="$1"
    local label backup_file tmp_file sshd_bin interactive_key auth_dropin auth_dropin_backup auth_reconcile_state timestamp reconciled_count
    sshd_bin=$(command -v sshd 2>/dev/null || true)
    [[ -n "$sshd_bin" && -f /etc/ssh/sshd_config ]] || {
        echo -e "${RED}❌ 未找到 sshd 或 /etc/ssh/sshd_config，已取消。${PLAIN}"
        return 1
    }
    if ! ssh_prepare_runtime_dir; then
        echo -e "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}"
        return 1
    fi
    case "$mode" in
        key_only) label="仅密钥登录（禁用密码）" ;;
        key_preferred) label="密钥优先（保留密码）" ;;
        password) label="恢复密码登录" ;;
        *) return 1 ;;
    esac
    confirm_risk_action "切换 SSH 登录模式：${label}" \
        "/etc/ssh/sshd_config 与 /etc/ssh/sshd_config.d 登录认证配置" \
        "使用本菜单恢复密码登录，或从自动备份恢复 /etc/ssh/sshd_config 与对应子配置备份" \
        "会同步处理 50-cloud-init.conf 等云镜像子配置；切到仅密钥登录前，必须先确认新 SSH 窗口能用私钥登录。" || return 1

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
        echo -e "${RED}❌ SSH 配置备份失败，已取消。${PLAIN}"
        rm -f "$auth_reconcile_state"
        return 1
    }
    if [[ -f "$auth_dropin" ]]; then
        auth_dropin_backup="${auth_dropin}.bak_auth_${timestamp}"
        cp -p "$auth_dropin" "$auth_dropin_backup" || {
            echo -e "${RED}❌ SSH drop-in 配置备份失败，已取消。${PLAIN}"
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
        echo -e "${RED}❌ 写入 SSH drop-in 登录配置失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        rm -f "$auth_reconcile_state"
        return 1
    fi

    if ! ssh_reconcile_cloud_auth_dropins "$mode" "$auth_reconcile_state" "$timestamp"; then
        echo -e "${RED}❌ 处理云镜像 SSH 子配置失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi

    if ! "$sshd_bin" -t; then
        echo -e "${RED}❌ SSH 配置语法检查失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi
    if ! ssh_assert_auth_mode_effective "$mode"; then
        echo -e "${RED}❌ SSH 登录模式未真正生效，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        rm -f "$auth_reconcile_state"
        return 1
    fi
    if ! ssh_restart_runtime; then
        echo -e "${RED}❌ SSH 服务重启失败，正在回滚。${PLAIN}"
        cp -p "$backup_file" /etc/ssh/sshd_config
        ssh_restore_auth_dropin "$auth_dropin" "$auth_dropin_backup"
        ssh_restore_cloud_auth_dropins "$auth_reconcile_state"
        ssh_restart_runtime >/dev/null 2>&1 || true
        rm -f "$auth_reconcile_state"
        return 1
    fi
    echo -e "${GREEN}✅ SSH 登录模式已切换为：${label}${PLAIN}"
    echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
    reconciled_count=$(wc -l < "$auth_reconcile_state" 2>/dev/null | awk '{print $1}')
    if [[ "$reconciled_count" =~ ^[0-9]+$ && "$reconciled_count" -gt 0 ]]; then
        echo -e "${CYAN}已同步 ${reconciled_count} 个云镜像 SSH 子配置，例如 50-cloud-init.conf。${PLAIN}"
    fi
    rm -f "$auth_reconcile_state"
}

func_ssh_login_mode_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "SSH 安全中心 > 用户密钥登录模式"
        echo -e "${BOLD}🔐 用户密钥登录模式${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "PubkeyAuthentication      : ${CYAN}$(ssh_effective_setting PubkeyAuthentication || echo 未知)${PLAIN}"
        echo -e "PasswordAuthentication    : ${CYAN}$(ssh_effective_setting PasswordAuthentication || echo 未知)${PLAIN}"
        echo -e "KbdInteractiveAuthentication: ${CYAN}$(ssh_effective_setting KbdInteractiveAuthentication || echo 未知)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  1. 为用户添加 SSH 公钥${PLAIN}"
        echo -e "${GREEN}  2. 密钥优先，保留密码登录${PLAIN}"
        echo -e "${RED}  3. 仅密钥登录，禁用密码登录${PLAIN}"
        echo -e "${YELLOW}  4. 恢复密码登录${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回上一级 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice user key_count
        read_trimmed choice "👉 请选择操作: "
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
                    echo -e "${RED}❌ 用户 ${user} 还没有 authorized_keys，不能切到仅密钥登录。${PLAIN}"
                    echo -e "${YELLOW}请先用本菜单 [1] 添加公钥，并用新 SSH 窗口测试成功。${PLAIN}"
                    pause_return
                    continue
                fi
                echo -e "${YELLOW}检测到 ${user} 已有 ${key_count} 条公钥。切换后密码登录会被禁用。${PLAIN}"
                ssh_apply_auth_mode key_only
                pause_return
                ;;
            4) ssh_apply_auth_mode password; pause_return ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_ssh_security_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "SSH 安全中心"
        echo -e "${BOLD}🛡️ SSH 安全中心${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${GREEN}  1. 修改 SSH 端口${PLAIN}             ${YELLOW}(防失联校验和回滚)${PLAIN}"
        echo -e "${GREEN}  2. 用户密钥登录模式${PLAIN}         ${YELLOW}(添加公钥 / 禁用或恢复密码登录)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 返回主菜单 / q 返回${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        local choice
        read_trimmed choice "👉 请选择操作: "
        case "$choice" in
            1) func_security ;;
            2) func_ssh_login_mode_menu ;;
            0|q|Q) break ;;
            *) echo -e "${RED}❌ 无效选择！${PLAIN}"; sleep 1 ;;
        esac
    done
}

func_security() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🛡️ SSH 安全加固 (端口修改与防失联)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}功能介绍：该脚本将修改 SSH 端口并配置防失联机制，确保服务稳定。${PLAIN}"
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
    read_trimmed final_p "👉 当前生效的 SSH 端口为 $current_p, 请输入新端口 [10000-65535] (回车保持不变): "
    final_p=${final_p:-$current_p}

    if [[ "$final_p" != "$current_p" ]]; then
        if [[ -z "$sshd_bin" ]]; then
            echo -e "${RED}❌ 未找到 sshd 命令，无法安全校验 SSH 配置，已取消。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! command -v systemctl >/dev/null 2>&1; then
            echo -e "${RED}❌ 未检测到 systemctl，无法安全重启 SSH 服务，已取消。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! ssh_prepare_runtime_dir; then
            echo -e "${RED}❌ 无法创建 /run/sshd，sshd 无法完成语法检查。请确认当前为 root 权限。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        # [严格检验] 端口合法性
        if ! [[ "$final_p" =~ ^[0-9]+$ ]] || (( 10#$final_p < 10000 || 10#$final_p > 65535 )); then
            echo -e "${RED}❌ 错误：无效的端口号！必须是 10000-65535 之间的纯数字。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        echo -e "${YELLOW}即将修改：/etc/ssh/sshd_config、/etc/ssh/sshd_config.d、SSH systemd socket/服务、系统防火墙放行规则。${PLAIN}"
        echo -e "${YELLOW}请先确认云厂商安全组已经放行 ${final_p}/tcp，并保留当前 SSH 会话。${PLAIN}"
        confirm_danger "修改 SSH 端口为 ${final_p}" "新端口未放行会导致后续无法重新连接 SSH。" "脚本会先备份 sshd_config，校验语法失败或服务重启失败时自动回滚。" || {
            echo -e "${BLUE}已取消 SSH 端口修改。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        }

        echo -e "${CYAN}▶ 正在备份原生 SSH 配置文件...${PLAIN}"
        local backup_file="/etc/ssh/sshd_config.bak_$(date +%s)"
        if ! cp -p /etc/ssh/sshd_config "$backup_file"; then
            echo -e "${RED}❌ SSH 配置备份失败，已取消修改。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 2. 核心黑科技：安全的置顶替换
        # - 先安全删除所有带 Port 的行 (忽略注释符和空格)
        # - 然后在文件绝对第一行 (1i) 插入新端口，秒杀所有 include 配置覆盖！
        if ! sed -i '/^[[:space:]]*#\?Port /d' /etc/ssh/sshd_config || ! sed -i "1i Port $final_p" /etc/ssh/sshd_config; then
            echo -e "${RED}❌ 写入 SSH 配置失败，正在恢复备份。${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        if ! ssh_write_sshd_port_dropin "$final_p"; then
            echo -e "${RED}❌ 写入 SSH drop-in 端口配置失败，正在恢复备份。${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        # 3. [CentOS 专属] SELinux 放行
        if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
            echo -e "${YELLOW}检测到 SELinux 开启，正在配置底层端口安全策略...${PLAIN}"
            if command -v semanage >/dev/null 2>&1; then
                semanage port -a -t ssh_port_t -p tcp "$final_p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$final_p" 2>/dev/null
            else
                echo -e "${RED}❌ 致命错误：缺少 semanage 工具！已触发安全回滚。${PLAIN}"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi

        # 4. 防失联核心：验证新配置语法
        if ! "$sshd_bin" -t; then
            echo -e "${RED}❌ 致命错误：SSH 配置存在语法异常！正在全盘恢复...${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" false
            read -n 1 -s -r -p "按任意键返回..."
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
            echo -e "${YELLOW}检测到 SSH socket (${socket_units})，正在同步底层监听端口...${PLAIN}"
            if ssh_write_socket_port_dropins "$final_p"; then
                socket_managed=true
                systemctl daemon-reload >/dev/null 2>&1 || true
            else
                echo -e "${RED}❌ 写入 SSH socket drop-in 失败，正在回滚。${PLAIN}"
                ssh_rollback_port_change "$backup_file" "$current_p" false
                read -n 1 -s -r -p "按任意键返回..."
                return
            fi
        fi
        
        # 7. 严格隔离的服务重启逻辑
        echo -e "${CYAN}▶ 正在重启底层 SSH 引擎...${PLAIN}"
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
            echo -e "${GREEN}✅ SSH 端口已成功更改为 $final_p 并自动放行！${PLAIN}"
            echo -e "${CYAN}配置备份已保留：${backup_file}${PLAIN}"
        else
            echo -e "${RED}❌ 致命错误：重启 SSH 服务失败！正在回滚至原端口...${PLAIN}"
            ssh_rollback_port_change "$backup_file" "$current_p" "$socket_managed"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
        echo -e "${YELLOW}⚠️ 终极保命提示：${PLAIN}"
        echo -e "现在的这扇 SSH 窗口【千万不要关闭】！"
        echo -e "请立刻使用新端口 $final_p 新建一个连接进行测试。"
        echo -e "如果云平台有【安全组】，请确保也已放行 $final_p 端口！"
        echo -e "${RED}${BOLD}======================================================${PLAIN}"
    else
        echo -e "${BLUE}端口未做更改。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增：Fail2ban 防爆破系统管理 (抽象精简版)
# ---------------------------------------------------------
func_fail2ban() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}Fail2ban 防爆破系统管理${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    
    local current_p
    current_p=$(ss -tlnp 2>/dev/null | grep -w 'sshd' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
    if [[ -z "$current_p" ]]; then
        current_p=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
    fi
    current_p=${current_p:-22}
    
    echo -e "${YELLOW}👉 当前系统检测到的 SSH 端口为: ${GREEN}$current_p${PLAIN}"
    echo -e "------------------------------------------------"
    
    local f2b_status="${RED}未安装${PLAIN}"
    if command -v fail2ban-server >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            f2b_status="${GREEN}已运行${PLAIN}"
        else
            f2b_status="${YELLOW}已停止${PLAIN}"
        fi
    fi
    
    echo -e "当前 Fail2ban 状态: [ $f2b_status ]"
    echo -e "  ${GREEN}1.${PLAIN} 一键安装并配置 Fail2ban ${YELLOW}(自动绑定当前 SSH 端口)${PLAIN}"
    echo -e "  ${BLUE}2.${PLAIN} 更新防护端口 ${YELLOW}(如果您刚改了 SSH 端口，选此项重载)${PLAIN}"
    echo -e "  ${RED}3.${PLAIN} 彻底卸载 Fail2ban"
    echo -e "  ${RED}0.${PLAIN} 返回主菜单"
    echo -e "------------------------------------------------"
    
    local f_choice
    read_trimmed f_choice "👉 请选择操作: "
    
    case $f_choice in
        1|2)
            if [[ "$f_choice" == "1" ]]; then
                echo -e "${CYAN}正在安装 Fail2ban...${PLAIN}"
                if is_debian; then
                    install_pkg fail2ban python3-systemd
                else
                    install_pkg fail2ban
                fi
            fi
            
            if command -v fail2ban-server >/dev/null 2>&1; then
                echo -e "${CYAN}正在写入配置并绑定端口 $current_p ...${PLAIN}"
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
                    echo -e "${GREEN}✅ Fail2ban 配置完成并已启动！(保护端口: $current_p，日志后端: $f2b_backend)${PLAIN}"
                    echo -e "${YELLOW}💡 规则：10分钟内密码错误5次，自动封禁该IP 24小时。${PLAIN}"
                else
                    echo -e "${RED}❌ Fail2ban 启动失败，正在显示关键日志：${PLAIN}"
                    fail2ban-client -t 2>/dev/null || true
                    journalctl -u fail2ban -n 20 --no-pager 2>/dev/null || true
                fi
            else
                echo -e "${RED}❌ Fail2ban 安装或检测失败，请检查网络源。${PLAIN}"
            fi
            ;;
        3)
            echo -e "${CYAN}正在卸载 Fail2ban...${PLAIN}"
            remove_pkg fail2ban # <--- 核心修改：一句话极简卸载
            quarantine_path /etc/fail2ban "/etc/vps-optimize/quarantine" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ Fail2ban 已卸载，旧配置已隔离到 /etc/vps-optimize/quarantine。${PLAIN}"
            ;;
        0) return ;;
        *) echo -e "${RED}❌ 无效的输入！${PLAIN}"; sleep 1 ;;
    esac
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 新增功能：添加 SSH 公钥登录
# ---------------------------------------------------------
func_add_ssh_key() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${BOLD}🔑 添加 SSH 公钥登录 (免密安全认证)${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${YELLOW}使用 SSH 密钥登录不仅免去输密码的烦恼，更能彻底免疫密码爆破！${PLAIN}"
    echo -e "请准备好您的公钥 (通常以 ssh-rsa, ssh-ed25519、ecdsa 或 sk-* 开头)。"
    echo -e "------------------------------------------------"
    local user enable_mode
    user=$(ssh_choose_user) || { read -n 1 -s -r -p "按任意键继续..."; return; }
    if ssh_add_public_key_for_user "$user"; then
        echo -e "${GREEN}✅ 公钥添加完成。请立刻新开一个 SSH 窗口测试私钥登录。${PLAIN}"
        read_trimmed enable_mode "是否同时写入“密钥优先，保留密码登录”模式？(y/N): "
        if [[ "$enable_mode" =~ ^[Yy]$ ]]; then
            ssh_apply_auth_mode key_preferred || true
        fi
        echo -e "${YELLOW}确认私钥登录 100% 成功后，可进入 [5 SSH 安全中心] -> [2 用户密钥登录模式] 禁用密码登录。${PLAIN}"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}
# ---------------------------------------------------------
# 5. Docker 深度管理 (重构版：非破坏性修改与防宕机回滚)
# ---------------------------------------------------------
