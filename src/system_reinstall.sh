# shellcheck shell=bash
# System reinstallation workflow backed by bin456789/reinstall.

SYSTEM_REINSTALL_UPSTREAM_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
SYSTEM_REINSTALL_SCRIPT="/usr/local/lib/vps-optimize/reinstall.sh"

system_reinstall_windows_language() {
    case "$VPSO_LANGUAGE" in
        en) printf 'en-us' ;;
        ru) printf 'ru-ru' ;;
        *) printf 'zh-cn' ;;
    esac
}

system_reinstall_set_target() {
    local choice="$1"
    local windows_language
    SYSTEM_REINSTALL_TARGET=()
    SYSTEM_REINSTALL_LABEL=""
    windows_language=$(system_reinstall_windows_language)

    case "$choice" in
        1) SYSTEM_REINSTALL_TARGET=(debian 13); SYSTEM_REINSTALL_LABEL="Debian 13" ;;
        2) SYSTEM_REINSTALL_TARGET=(debian 12); SYSTEM_REINSTALL_LABEL="Debian 12" ;;
        3) SYSTEM_REINSTALL_TARGET=(debian 11); SYSTEM_REINSTALL_LABEL="Debian 11" ;;
        4) SYSTEM_REINSTALL_TARGET=(debian 10); SYSTEM_REINSTALL_LABEL="Debian 10" ;;
        11) SYSTEM_REINSTALL_TARGET=(ubuntu 26.04); SYSTEM_REINSTALL_LABEL="Ubuntu 26.04" ;;
        12) SYSTEM_REINSTALL_TARGET=(ubuntu 24.04); SYSTEM_REINSTALL_LABEL="Ubuntu 24.04" ;;
        13) SYSTEM_REINSTALL_TARGET=(ubuntu 22.04); SYSTEM_REINSTALL_LABEL="Ubuntu 22.04" ;;
        14) SYSTEM_REINSTALL_TARGET=(ubuntu 20.04); SYSTEM_REINSTALL_LABEL="Ubuntu 20.04" ;;
        21) SYSTEM_REINSTALL_TARGET=(rocky 10); SYSTEM_REINSTALL_LABEL="Rocky Linux 10" ;;
        22) SYSTEM_REINSTALL_TARGET=(rocky 9); SYSTEM_REINSTALL_LABEL="Rocky Linux 9" ;;
        23) SYSTEM_REINSTALL_TARGET=(almalinux 10); SYSTEM_REINSTALL_LABEL="AlmaLinux 10" ;;
        24) SYSTEM_REINSTALL_TARGET=(almalinux 9); SYSTEM_REINSTALL_LABEL="AlmaLinux 9" ;;
        25) SYSTEM_REINSTALL_TARGET=(oracle 10); SYSTEM_REINSTALL_LABEL="Oracle Linux 10" ;;
        26) SYSTEM_REINSTALL_TARGET=(oracle 9); SYSTEM_REINSTALL_LABEL="Oracle Linux 9" ;;
        27) SYSTEM_REINSTALL_TARGET=(fedora 44); SYSTEM_REINSTALL_LABEL="Fedora Linux 44" ;;
        28) SYSTEM_REINSTALL_TARGET=(fedora 43); SYSTEM_REINSTALL_LABEL="Fedora Linux 43" ;;
        29) SYSTEM_REINSTALL_TARGET=(centos 10); SYSTEM_REINSTALL_LABEL="CentOS Stream 10" ;;
        30) SYSTEM_REINSTALL_TARGET=(centos 9); SYSTEM_REINSTALL_LABEL="CentOS Stream 9" ;;
        31) SYSTEM_REINSTALL_TARGET=(alpine 3.24); SYSTEM_REINSTALL_LABEL="Alpine Linux 3.24" ;;
        32) SYSTEM_REINSTALL_TARGET=(arch); SYSTEM_REINSTALL_LABEL="Arch Linux" ;;
        33) SYSTEM_REINSTALL_TARGET=(kali); SYSTEM_REINSTALL_LABEL="Kali Linux" ;;
        34) SYSTEM_REINSTALL_TARGET=(openeuler 24.03); SYSTEM_REINSTALL_LABEL="openEuler 24.03" ;;
        35) SYSTEM_REINSTALL_TARGET=(opensuse tumbleweed); SYSTEM_REINSTALL_LABEL="openSUSE Tumbleweed" ;;
        36) SYSTEM_REINSTALL_TARGET=(fnos 1); SYSTEM_REINSTALL_LABEL="fnOS 1" ;;
        41) SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows 11 Pro" --lang "$windows_language"); SYSTEM_REINSTALL_LABEL="Windows 11 Pro" ;;
        42) SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows 10 Pro" --lang "$windows_language"); SYSTEM_REINSTALL_LABEL="Windows 10 Pro" ;;
        44) SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows Server 2025 Standard" --lang "$windows_language"); SYSTEM_REINSTALL_LABEL="Windows Server 2025 Standard" ;;
        45) SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows Server 2022 Standard" --lang "$windows_language"); SYSTEM_REINSTALL_LABEL="Windows Server 2022 Standard" ;;
        46) SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows Server 2019 Standard" --lang "$windows_language"); SYSTEM_REINSTALL_LABEL="Windows Server 2019 Standard" ;;
        47) SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows 11 Pro" --lang "$windows_language"); SYSTEM_REINSTALL_LABEL="Windows 11 Pro ARM" ;;
        *) return 1 ;;
    esac
}

system_reinstall_set_windows7_target() {
    local iso_url="$1"
    local windows_language

    case "$iso_url" in
        http://*|https://*|magnet:*) ;;
        *) return 1 ;;
    esac

    windows_language=$(system_reinstall_windows_language)
    SYSTEM_REINSTALL_TARGET=(windows --image-name "Windows 7 Ultimate" --lang "$windows_language" --iso "$iso_url")
    SYSTEM_REINSTALL_LABEL="Windows 7 Ultimate"
}

system_reinstall_is_windows_target() {
    [[ "${SYSTEM_REINSTALL_TARGET[0]:-}" == "windows" ]]
}

system_reinstall_is_valid_ssh_public_key() {
    local ssh_key="$1"
    local key_type key_data

    [[ "$ssh_key" != *$'\n'* && "$ssh_key" != *$'\r'* ]] || return 1
    read -r key_type key_data _ <<<"$ssh_key"
    case "$key_type" in
        ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ;;
        *) return 1 ;;
    esac
    [[ "$key_data" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]
}

system_reinstall_set_password() {
    local password="$1"

    [[ -n "$password" ]] || return 1
    SYSTEM_REINSTALL_AUTH_MODE="password"
    SYSTEM_REINSTALL_ACCESS_ARGS=(--password "$password")
}

system_reinstall_set_ssh_key() {
    local ssh_key="$1"

    system_reinstall_is_valid_ssh_public_key "$ssh_key" || return 1
    SYSTEM_REINSTALL_AUTH_MODE="ssh_key"
    SYSTEM_REINSTALL_ACCESS_ARGS=(--ssh-key "$ssh_key")
}

system_reinstall_set_ssh_port() {
    local ssh_port

    ssh_port=$(normalize_port_input "$1")
    is_valid_port "$ssh_port" || return 1
    SYSTEM_REINSTALL_SSH_PORT="$ssh_port"
}

system_reinstall_read_password() {
    local password password_confirm

    while true; do
        IFS= read -r -p "$(localized_text "设置登录密码（输入会明文显示）: " "Set login password (input is visible): " "Введите пароль для входа (ввод отображается): ")" password || return 1
        if ! system_reinstall_set_password "$password"; then
            echo -e "$(localized_text "${RED}❌ 密码不能为空。${PLAIN}" "${RED}❌ Password cannot be empty.${PLAIN}" "${RED}❌ Пароль не может быть пустым.${PLAIN}")"
            continue
        fi

        printf '%b%s%b%s\n' "$YELLOW" "$(localized_text "将写入的密码：" "Password to be set: " "Устанавливаемый пароль: ")" "$PLAIN" "$password"
        IFS= read -r -p "$(localized_text "再次输入密码确认（输入会明文显示）: " "Retype password to confirm (input is visible): " "Повторите пароль для подтверждения (ввод отображается): ")" password_confirm || return 1
        if [[ "$password" == "$password_confirm" ]]; then
            printf '%b%s%b%s\n' "$GREEN" "$(localized_text "密码已确认：" "Password confirmed: " "Пароль подтверждён: ")" "$PLAIN" "$password"
            return 0
        fi

        echo -e "$(localized_text "${RED}❌ 两次密码不一致，请重新输入。${PLAIN}" "${RED}❌ Passwords do not match. Try again.${PLAIN}" "${RED}❌ Пароли не совпадают. Повторите ввод.${PLAIN}")"
    done
}

system_reinstall_read_ssh_key() {
    local ssh_key

    while true; do
        IFS= read -r -p "$(localized_text "SSH 公钥（单行）: " "SSH public key (one line): " "Открытый ключ SSH (одна строка): ")" ssh_key || return 1
        if system_reinstall_set_ssh_key "$ssh_key"; then
            echo -e "$(localized_text "${GREEN}✅ SSH 公钥格式检查通过。${PLAIN}" "${GREEN}✅ SSH public-key format accepted.${PLAIN}" "${GREEN}✅ Формат открытого ключа SSH принят.${PLAIN}")"
            return 0
        fi

        echo -e "$(localized_text "${RED}❌ SSH 公钥格式无效，仅支持单行 ssh-rsa、ssh-ed25519 或 ecdsa-sha2-nistp* 公钥。${PLAIN}" "${RED}❌ Invalid SSH public-key format. Use a one-line ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistp* public key.${PLAIN}" "${RED}❌ Недопустимый формат открытого ключа SSH. Используйте однострочный ключ ssh-rsa, ssh-ed25519 или ecdsa-sha2-nistp*.${PLAIN}")"
    done
}

system_reinstall_read_ssh_port() {
    local ssh_port

    while true; do
        IFS= read -r -p "$(localized_text "SSH 登录端口 [22]: " "SSH login port [22]: " "Порт входа SSH [22]: ")" ssh_port || return 1
        ssh_port=${ssh_port:-22}
        if system_reinstall_set_ssh_port "$ssh_port"; then
            echo -e "$(localized_text "${YELLOW}请确认云厂商安全组和防火墙允许 TCP ${SYSTEM_REINSTALL_SSH_PORT}。${PLAIN}" "${YELLOW}Ensure the cloud security group and firewall allow TCP ${SYSTEM_REINSTALL_SSH_PORT}.${PLAIN}" "${YELLOW}Убедитесь, что облачная группа безопасности и межсетевой экран разрешают TCP ${SYSTEM_REINSTALL_SSH_PORT}.${PLAIN}")"
            return 0
        fi

        echo -e "$(localized_text "${RED}❌ SSH 端口必须在 1-65535。${PLAIN}" "${RED}❌ SSH port must be between 1 and 65535.${PLAIN}" "${RED}❌ Порт SSH должен быть от 1 до 65535.${PLAIN}")"
    done
}

system_reinstall_collect_access_options() {
    local access_choice

    SYSTEM_REINSTALL_AUTH_MODE=""
    SYSTEM_REINSTALL_ACCESS_ARGS=()
    SYSTEM_REINSTALL_SSH_PORT=""
    while true; do
        echo -e "$(localized_text "${BOLD}登录方式${PLAIN}" "${BOLD}Login method${PLAIN}" "${BOLD}Способ входа${PLAIN}")"
        echo -e "  1. $(localized_text "密码登录" "Password" "Пароль")"
        echo -e "  2. $(localized_text "SSH 公钥登录" "SSH public key" "Открытый ключ SSH")"
        echo -e "  0. $(localized_text "返回系统选择" "Back to system selection" "Назад к выбору системы")"
        if system_reinstall_is_windows_target; then
            echo -e "$(localized_text "${YELLOW}Windows 重装不支持 SSH 公钥，选择 [1] 设置密码。${PLAIN}" "${YELLOW}Windows reinstallation does not support SSH public keys; select [1] to set a password.${PLAIN}" "${YELLOW}Переустановка Windows не поддерживает открытые ключи SSH; выберите [1], чтобы задать пароль.${PLAIN}")"
        fi

        read_trimmed access_choice "$(localized_text "选择登录方式: " "Select login method: " "Выберите способ входа: ")"
        case "$access_choice" in
            0|q|Q) return 1 ;;
            1)
                system_reinstall_read_password || return 1
                break
                ;;
            2)
                if system_reinstall_is_windows_target; then
                    echo -e "$(localized_text "${RED}❌ Windows 不支持 SSH 公钥登录。${PLAIN}" "${RED}❌ Windows does not support SSH public-key login.${PLAIN}" "${RED}❌ Windows не поддерживает вход по открытому ключу SSH.${PLAIN}")"
                    continue
                fi
                system_reinstall_read_ssh_key || return 1
                break
                ;;
            *)
                echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
                ;;
        esac
    done

    system_reinstall_read_ssh_port || return 1
    if [[ "$SYSTEM_REINSTALL_AUTH_MODE" == "password" ]]; then
        printf '%b%s%b%s\n' "$YELLOW" "$(localized_text "确认使用密码登录，密码：" "Password login confirmed, password: " "Подтверждён вход по паролю, пароль: ")" "$PLAIN" "${SYSTEM_REINSTALL_ACCESS_ARGS[1]}"
    else
        echo -e "$(localized_text "${GREEN}确认使用 SSH 公钥登录。${PLAIN}" "${GREEN}SSH public-key login confirmed.${PLAIN}" "${GREEN}Подтверждён вход по открытому ключу SSH.${PLAIN}")"
    fi
    echo -e "$(localized_text "${GREEN}SSH 登录端口：${SYSTEM_REINSTALL_SSH_PORT}${PLAIN}" "${GREEN}SSH login port: ${SYSTEM_REINSTALL_SSH_PORT}${PLAIN}" "${GREEN}Порт входа SSH: ${SYSTEM_REINSTALL_SSH_PORT}${PLAIN}")"
}

system_reinstall_fetch_upstream() {
    local script_dir temp_script

    script_dir=$(dirname "$SYSTEM_REINSTALL_SCRIPT")
    mkdir -p "$script_dir" || return 1
    temp_script=$(mktemp "${script_dir}/.reinstall.sh.XXXXXX") || return 1

    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 10 --retry 3 --retry-delay 1 -o "$temp_script" "$SYSTEM_REINSTALL_UPSTREAM_URL" || {
            rm -f "$temp_script"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$temp_script" "$SYSTEM_REINSTALL_UPSTREAM_URL" || {
            rm -f "$temp_script"
            return 1
        }
    else
        echo -e "$(localized_text "${RED}❌ 缺少 curl 或 wget，无法下载重装脚本。${PLAIN}" "${RED}❌ curl or wget is required to download the reinstallation script.${PLAIN}" "${RED}❌ Для загрузки сценария переустановки требуется curl или wget.${PLAIN}")"
        rm -f "$temp_script"
        return 1
    fi

    if [[ ! -s "$temp_script" ]] || ! bash -n "$temp_script"; then
        echo -e "$(localized_text "${RED}❌ 上游重装脚本下载或语法校验失败，未执行。${PLAIN}" "${RED}❌ The upstream reinstallation script download or syntax check failed; it was not run.${PLAIN}" "${RED}❌ Загрузка или проверка синтаксиса сценария переустановки не удалась; запуск отменён.${PLAIN}")"
        rm -f "$temp_script"
        return 1
    fi

    chmod 700 "$temp_script" 2>/dev/null || true
    mv -f "$temp_script" "$SYSTEM_REINSTALL_SCRIPT" || {
        rm -f "$temp_script"
        return 1
    }
}

system_reinstall_cancel_pending() {
    [[ -x "$SYSTEM_REINSTALL_SCRIPT" ]] || {
        echo -e "$(localized_text "${YELLOW}未找到已下载的重装脚本，无法取消。${PLAIN}" "${YELLOW}No downloaded reinstallation script was found to cancel.${PLAIN}" "${YELLOW}Загруженный сценарий переустановки не найден; отмена невозможна.${PLAIN}")"
        return 1
    }

    confirm_risk_action \
        "$(localized_text "取消已安排的系统重装" "Cancel scheduled system reinstallation" "Отменить запланированную переустановку системы")" \
        "$(localized_text "删除上游脚本写入的临时引导项" "Remove the temporary boot entry written by the upstream script" "Удалить временную загрузочную запись, созданную исходным сценарием")" \
        "$(localized_text "如取消失败，请使用云厂商控制台或救援模式恢复" "If cancellation fails, recover through the cloud console or rescue mode" "Если отмена не удалась, используйте облачную консоль или режим восстановления")" \
        "$(localized_text "仅在尚未重启进入安装环境时使用" "Use only before rebooting into the installer" "Используйте только до перезагрузки в установщик")" || return

    bash "$SYSTEM_REINSTALL_SCRIPT" reset
}

func_system_reinstall() {
    local reinstall_choice windows7_iso result

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "系统重装" "System reinstallation" "Переустановка системы")"
        echo -e "$(localized_text "${BOLD}⚠️ 系统重装${PLAIN}" "${BOLD}⚠️ System reinstallation${PLAIN}" "${BOLD}⚠️ Переустановка системы${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${RED}重装会在重启后清空主硬盘数据，可能导致 SSH 失联。请先备份并确认云厂商控制台或救援模式可用。${PLAIN}" "${RED}Reinstallation erases the main disk after reboot and may disconnect SSH. Back up data and confirm cloud-console or rescue access first.${PLAIN}" "${RED}После перезагрузки переустановка очистит основной диск и может отключить SSH. Сначала создайте резервную копию и проверьте доступ к облачной консоли или режиму восстановления.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}后端：bin456789/reinstall；参考：leitbogioro/Tools。选择系统后设置登录方式和 SSH 端口。${PLAIN}" "${YELLOW}Backend: bin456789/reinstall; reference: leitbogioro/Tools. After selecting a system, set the login method and SSH port.${PLAIN}" "${YELLOW}Основа: bin456789/reinstall; справочный проект: leitbogioro/Tools. После выбора системы задайте способ входа и порт SSH.${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "  1. Debian 13                 2. Debian 12"
        echo -e "  3. Debian 11                 4. Debian 10"
        echo -e "------------------------------------------------"
        echo -e " 11. Ubuntu 26.04             12. Ubuntu 24.04"
        echo -e " 13. Ubuntu 22.04             14. Ubuntu 20.04"
        echo -e "------------------------------------------------"
        echo -e " 21. Rocky Linux 10           22. Rocky Linux 9"
        echo -e " 23. AlmaLinux 10             24. AlmaLinux 9"
        echo -e " 25. Oracle Linux 10          26. Oracle Linux 9"
        echo -e " 27. Fedora Linux 44          28. Fedora Linux 43"
        echo -e " 29. CentOS Stream 10         30. CentOS Stream 9"
        echo -e "------------------------------------------------"
        echo -e " 31. Alpine Linux 3.24        32. Arch Linux"
        echo -e " 33. Kali Linux               34. openEuler 24.03"
        echo -e " 35. openSUSE Tumbleweed      36. fnOS 1"
        echo -e "------------------------------------------------"
        echo -e " 41. Windows 11               42. Windows 10"
        echo -e "$(localized_text " 43. Windows 7（需自备 ISO） 44. Windows Server 2025" " 43. Windows 7 (custom ISO)  44. Windows Server 2025" " 43. Windows 7 (свой ISO)    44. Windows Server 2025")"
        echo -e " 45. Windows Server 2022      46. Windows Server 2019"
        echo -e " 47. Windows 11 ARM"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text " ${YELLOW}50. 取消已安排的重装${PLAIN}" " ${YELLOW}50. Cancel scheduled reinstallation${PLAIN}" " ${YELLOW}50. Отменить запланированную переустановку${PLAIN}")"
        echo -e "${RED}  0. $(localized_text "返回上一级菜单" "Back to the previous menu" "Назад в предыдущее меню")${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        read_trimmed reinstall_choice "$(localized_text "请选择要重装的系统: " "Select a system to reinstall: " "Выберите систему для переустановки: ")"
        case "$reinstall_choice" in
            0|q|Q) return ;;
            50|cancel)
                system_reinstall_cancel_pending
                pause_return
                continue
                ;;
            43)
                read_trimmed windows7_iso "$(localized_text "Windows 7 ISO 地址（HTTP(S) 或磁力链接，留空取消）: " "Windows 7 ISO URL (HTTP(S) or magnet link; leave blank to cancel): " "URL ISO Windows 7 (HTTP(S) или magnet; пусто — отмена): ")"
                [[ -n "$windows7_iso" ]] || continue
                if ! system_reinstall_set_windows7_target "$windows7_iso"; then
                    echo -e "$(localized_text "${RED}❌ ISO 地址无效。${PLAIN}" "${RED}❌ Invalid ISO URL.${PLAIN}" "${RED}❌ Недопустимый URL ISO.${PLAIN}")"
                    pause_return
                    continue
                fi
                ;;
            47)
                case "$(uname -m)" in
                    aarch64|arm64) ;;
                    *)
                        echo -e "$(localized_text "${RED}❌ Windows 11 ARM 仅适用于 ARM64 服务器。${PLAIN}" "${RED}❌ Windows 11 ARM is available only on ARM64 servers.${PLAIN}" "${RED}❌ Windows 11 ARM доступна только на серверах ARM64.${PLAIN}")"
                        pause_return
                        continue
                        ;;
                esac
                system_reinstall_set_target "$reinstall_choice"
                ;;
            *)
                if ! system_reinstall_set_target "$reinstall_choice"; then
                    echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
                    sleep 1
                    continue
                fi
                ;;
        esac

        if ! system_reinstall_collect_access_options; then
            continue
        fi

        confirm_risk_action \
            "$(localized_text "重装为 ${SYSTEM_REINSTALL_LABEL}" "Reinstall as ${SYSTEM_REINSTALL_LABEL}" "Переустановить как ${SYSTEM_REINSTALL_LABEL}")" \
            "$(localized_text "下载并执行第三方上游脚本，写入一次性安装引导项；重启后会清空主硬盘及全部分区数据" "Download and run a third-party upstream script that writes a one-time installer boot entry; rebooting will erase the main disk and all its partitions" "Загрузить и запустить сторонний исходный сценарий, который создаст одноразовую загрузочную запись; после перезагрузки основной диск и все его разделы будут очищены")" \
            "$(localized_text "重启前可用本菜单 [50] 取消已安排的重装；重启后只能用快照、云控制台或救援模式恢复" "Before rebooting, use [50] in this menu to cancel the scheduled reinstallation; after rebooting, recovery requires a snapshot, cloud console, or rescue mode" "До перезагрузки отмените запланированную переустановку через [50]; после перезагрузки восстановление возможно только из снимка, через облачную консоль или режим восстановления")" \
            "$(localized_text "确认已完成备份，且能使用云厂商控制台或救援模式" "Confirm that backups are complete and cloud-console or rescue access is available" "Подтвердите наличие резервной копии и доступа к облачной консоли или режиму восстановления")" || continue

        if ! system_reinstall_fetch_upstream; then
            echo -e "$(localized_text "${RED}❌ 无法准备上游重装脚本，未写入引导项。${PLAIN}" "${RED}❌ Unable to prepare the upstream reinstallation script; no boot entry was written.${PLAIN}" "${RED}❌ Не удалось подготовить исходный сценарий; загрузочная запись не создана.${PLAIN}")"
            pause_return
            continue
        fi

        bash "$SYSTEM_REINSTALL_SCRIPT" "${SYSTEM_REINSTALL_TARGET[@]}" "${SYSTEM_REINSTALL_ACCESS_ARGS[@]}" --ssh-port "$SYSTEM_REINSTALL_SSH_PORT"
        result=$?
        if [[ "$result" -eq 0 ]]; then
            echo -e "$(localized_text "${YELLOW}重装已安排，重启后开始执行；如需取消，请在重启前选择 [50]。${PLAIN}" "${YELLOW}Reinstallation is scheduled and starts after reboot. To cancel, select [50] before rebooting.${PLAIN}" "${YELLOW}Переустановка запланирована и начнётся после перезагрузки. Для отмены выберите [50] до перезагрузки.${PLAIN}")"
        else
            echo -e "$(localized_text "${RED}❌ 上游重装脚本退出失败，未自动重启。请检查上方输出。${PLAIN}" "${RED}❌ The upstream reinstallation script failed and did not reboot automatically. Check the output above.${PLAIN}" "${RED}❌ Исходный сценарий переустановки завершился с ошибкой и не перезагрузил сервер. Проверьте вывод выше.${PLAIN}")"
        fi
        pause_return
    done
}
