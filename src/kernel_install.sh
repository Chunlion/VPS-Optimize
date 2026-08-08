# shellcheck shell=bash
# Optimized kernel detection, repository setup, installation, and boot selection.

normalize_kernel_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "unknown" ;;
    esac
}

apt_pkg_available() {
    local pkg="$1"
    apt-cache show "$pkg" >/dev/null 2>&1
}

set_grub_default_kernel_by_keyword() {
    local kernel_keyword="$1"
    local target_v menu_1 menu_2

    if ! command -v dpkg >/dev/null 2>&1 || [[ ! -f /etc/default/grub ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 dpkg/GRUB 配置，已跳过自动接管引导。${PLAIN}" "${YELLOW}⚠️ No dpkg/GRUB configuration detected, automatic takeover boot skipped.${PLAIN}" "${YELLOW}⚠️ Конфигурация dpkg/GRUB не обнаружена, автоматическая загрузка с дублированием пропущена.${PLAIN}")"
        return 0
    fi

    target_v=$(dpkg -l | awk '/^ii[[:space:]]+linux-image-[0-9]/ && /'"$kernel_keyword"'/ {print $2}' | sed 's/linux-image-//' | sort -V | tail -n 1)
    if [[ -z "$target_v" ]]; then
        echo -e "$(localized_text "${RED}❌ 错误：未找到已安装的 ${kernel_keyword} 内核包，请检查安装日志。${PLAIN}" "${RED}❌ Error: The installed ${kernel_keyword} kernel package was not found, please check the installation log.${PLAIN}" "${RED}❌ Ошибка: установленный пакет ядра ${kernel_keyword} не найден, проверьте журнал установки.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在接管 GRUB 底层引导，锁定启动内核为: $target_v ...${PLAIN}" "${CYAN}▶ Taking over the GRUB bottom boot, the locked boot kernel is: $target_v...${PLAIN}" "${CYAN}▶ Принимая на себя нижнюю загрузку GRUB, заблокированное загрузочное ядро: $target_v...${PLAIN}")"
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    else
        echo "GRUB_DEFAULT=saved" >> /etc/default/grub
    fi
    grep -q "^GRUB_SAVEDEFAULT=true" /etc/default/grub || echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
    if command -v update-grub >/dev/null 2>&1; then
        update-grub >/dev/null 2>&1
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    fi

    local grub_cfg="/boot/grub/grub.cfg"
    [[ -f "$grub_cfg" ]] || grub_cfg="/boot/grub2/grub.cfg"
    if [[ ! -f "$grub_cfg" ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未找到 grub.cfg，新内核已安装，但请重启后手动确认默认启动项。${PLAIN}" "${YELLOW}⚠️ grub.cfg not found, the new kernel has been installed, but please manually confirm the default startup items after restarting.${PLAIN}" "${YELLOW}⚠️ grub.cfg не найден, новое ядро установлено, но после перезапуска вручную подтвердите элементы запуска по умолчанию.${PLAIN}")"
        return 0
    fi

    menu_1=$(grep -i "submenu 'Advanced options for" "$grub_cfg" | cut -d"'" -f2 | head -n 1)
    menu_2=$(grep -i "menuentry '.*$target_v.*'" "$grub_cfg" | grep -iv "recovery" | cut -d"'" -f2 | head -n 1)

    if [[ -n "$menu_1" && -n "$menu_2" ]]; then
        grub-set-default "$menu_1>$menu_2" 2>/dev/null || grub2-set-default "$menu_1>$menu_2" 2>/dev/null || true
        echo -e "$(localized_text "${GREEN}✅ GRUB 引导接管成功！重启后将优先进入：$target_v${PLAIN}" "${GREEN}✅ GRUB boot takeover successful! After restarting, you will enter first: $target_v${PLAIN}" "${GREEN}✅ Перехват загрузки GRUB выполнен успешно! После перезагрузки сначала введите: $target_v.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${YELLOW}⚠️ 警告：GRUB 菜单寻址失败。系统可能仍以最高版本号内核启动。${PLAIN}" "${YELLOW}⚠️ WARNING: GRUB menu addressing failed. The system may still boot with the highest version kernel.${PLAIN}" "${YELLOW}⚠️ ВНИМАНИЕ: не удалось выполнить адресацию меню GRUB. Система по-прежнему может загружаться с ядром самой последней версии.${PLAIN}")"
    return 1
}

install_cloud_kvm_kernel() {
    local arch kernel_keyword="" pkg
    local candidates=()

    if uname -r | grep -qE "kvm|cloud|virtual"; then
        echo -e "$(localized_text "${GREEN}✅ 系统当前已运行 KVM/Cloud/Virtual 优化内核 ($(uname -r))，无需重复安装！${PLAIN}" "${GREEN}✅ The system is currently running the KVM/Cloud/Virtual optimized kernel ($(uname -r)), no need to repeat the installation!${PLAIN}" "${GREEN}✅ В настоящее время в системе установлено оптимизированное ядро KVM/Cloud/Virtual ($(uname -r)), повторять установку не нужно!${PLAIN}")"
        return 0
    fi

    arch=$(normalize_kernel_arch)
    if [[ "$arch" == "unknown" ]]; then
        echo -e "$(localized_text "${RED}❌ 当前架构 $(uname -m) 暂不支持自动切换精简内核。${PLAIN}" "${RED}❌ The current architecture $(uname -m) does not currently support automatic switching of streamlined kernels.${PLAIN}" "${RED}❌ Текущая архитектура $(uname -m) в настоящее время не поддерживает автоматическое переключение оптимизированных ядер.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在安装发行版官方 Cloud/KVM/Virtual 精简内核...${PLAIN}" "${CYAN}▶ Installing the official Cloud/KVM/Virtual streamlined kernel of the distribution...${PLAIN}" "${CYAN}▶ Установка официального Cloud/KVM/Virtual оптимизированного ядра дистрибутива...${PLAIN}")"
    ensure_minimal_system_compat

    if [[ "$OS" == "debian" ]]; then
        if [[ "$arch" == "amd64" ]]; then
            candidates=("linux-image-cloud-amd64" "linux-image-amd64")
        else
            candidates=("linux-image-cloud-arm64" "linux-image-arm64")
        fi
        kernel_keyword="cloud|${arch}"
    elif [[ "$OS" == "ubuntu" ]]; then
        if [[ "$arch" == "amd64" ]]; then
            candidates=("linux-kvm" "linux-virtual" "linux-generic")
        else
            candidates=("linux-virtual" "linux-generic")
        fi
        kernel_keyword="kvm|virtual|generic"
    else
        echo -e "$(localized_text "${RED}❌ Cloud/KVM/Virtual 内核功能目前仅支持 Debian 和 Ubuntu。${PLAIN}" "${RED}❌ Cloud/KVM/Virtual kernel functionality is currently only supported on Debian and Ubuntu.${PLAIN}" "${RED}❌ Функциональность Cloud/KVM/Virtual в настоящее время поддерживается только в Debian и Ubuntu.${PLAIN}")"
        return 1
    fi

    if is_debian; then
        export DEBIAN_FRONTEND=noninteractive
        apt_update_once || true
        unset DEBIAN_FRONTEND
    fi

    for pkg in "${candidates[@]}"; do
        if ! apt_pkg_available "$pkg"; then
            echo -e "$(localized_text "${YELLOW}  - 当前源未提供 ${pkg}，尝试下一个候选...${PLAIN}" "${YELLOW}- ${pkg} is not provided by the current source, try the next candidate...${PLAIN}" "${YELLOW}— ${pkg} не предоставлен текущим источником, попробуйте следующий кандидат...${PLAIN}")"
            continue
        fi
        echo -e "$(localized_text "${CYAN}▶ 尝试安装内核包: ${pkg}${PLAIN}" "${CYAN}▶ Try to install the kernel package: ${pkg}${PLAIN}" "${CYAN}▶ Попробуйте установить пакет ядра: ${pkg}.${PLAIN}")"
        if install_pkg "$pkg"; then
            echo -e "$(localized_text "${GREEN}✅ 已安装内核包: ${pkg}${PLAIN}" "${GREEN}✅ Kernel package installed: ${pkg}${PLAIN}" "${GREEN}✅ Установлен пакет ядра: ${pkg}${PLAIN}")"
            set_grub_default_kernel_by_keyword "$kernel_keyword"
            return $?
        fi
        echo -e "$(localized_text "${YELLOW}  - ${pkg} 安装失败，尝试下一个候选...${PLAIN}" "${YELLOW}- ${pkg} Installation failed, try next candidate...${PLAIN}" "${YELLOW}- ${pkg} Не удалось установить, попробуйте следующий вариант...${PLAIN}")"
    done

    echo -e "$(localized_text "${RED}❌ 未能安装可用的官方精简内核，请检查系统版本、架构和软件源。${PLAIN}" "${RED}❌ Unable to install the available official streamlined kernel, please check the system version, architecture and software source.${PLAIN}" "${RED}❌ Невозможно установить доступное официальное оптимизированное ядро. Проверьте версию системы, архитектуру и источник программного обеспечения.${PLAIN}")"
    return 1
}

xanmod_cpu_level() {
    local flags level="x64v1"
    flags=$(awk -F: '/flags/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
    if [[ "$flags" =~ avx2 ]] && [[ "$flags" =~ bmi2 ]] && [[ "$flags" =~ fma ]] && [[ "$flags" =~ movbe ]]; then
        level="x64v3"
    fi
    if [[ "$flags" =~ avx512f ]] && [[ "$flags" =~ avx512bw ]] && [[ "$flags" =~ avx512vl ]]; then
        level="x64v4"
    fi
    if [[ "$flags" =~ cx16 ]] && [[ "$flags" =~ lahf_lm ]] && [[ "$flags" =~ popcnt ]] && [[ "$flags" =~ sse4_2 ]]; then
        [[ "$level" == "x64v1" ]] && level="x64v2"
    fi
    echo "$level"
}

xanmod_candidate_packages() {
    local level="${1:-x64v1}"
    case "$level" in
        x64v4) printf '%s\n' linux-xanmod-lts-x64v4 linux-xanmod-x64v4 linux-xanmod-lts-x64v3 linux-xanmod-x64v3 linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        x64v3) printf '%s\n' linux-xanmod-lts-x64v3 linux-xanmod-x64v3 linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        x64v2) printf '%s\n' linux-xanmod-lts-x64v2 linux-xanmod-x64v2 linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
        *) printf '%s\n' linux-xanmod-lts-x64v1 linux-xanmod-x64v1 ;;
    esac
}

xanmod_supported_codename() {
    case "$1" in
        bookworm|trixie|forky|sid|jammy|noble|plucky) return 0 ;;
        *) return 1 ;;
    esac
}

add_xanmod_repo() {
    local codename="$1"
    local key_tmp
    mkdir -p /etc/apt/keyrings
    quarantine_path /etc/apt/keyrings/xanmod-archive-keyring.gpg "/etc/vps-optimize/quarantine/apt-keyrings" >/dev/null 2>&1 || true
    key_tmp=$(mktemp /tmp/xanmod-key.XXXXXX) || return 1
    if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 https://dl.xanmod.org/archive.key -o "$key_tmp"; then
        rm -f "$key_tmp"
        echo -e "$(localized_text "${RED}❌ XanMod GPG key 下载失败。${PLAIN}" "${RED}❌ XanMod GPG key download failed.${PLAIN}" "${RED}❌ Не удалось загрузить ключ XanMod GPG.${PLAIN}")"
        return 1
    fi
    if ! gpg --batch --yes --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg "$key_tmp"; then
        rm -f "$key_tmp"
        echo -e "$(localized_text "${RED}❌ XanMod GPG key 下载或写入失败。${PLAIN}" "${RED}❌ XanMod GPG key download or write failed.${PLAIN}" "${RED}❌ Не удалось загрузить или записать ключ XanMod GPG.${PLAIN}")"
        return 1
    fi
    rm -f "$key_tmp"
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${codename} main" > /etc/apt/sources.list.d/xanmod-release.list
    apt-get update -qq && APT_UPDATED=1
}

install_xanmod_kernel_package() {
    local preferred_level="$1"
    local pkg
    while IFS= read -r pkg; do
        apt_pkg_available "$pkg" || continue
        echo -e "$(localized_text "${CYAN}▶ 尝试安装 XanMod 包: ${pkg}${PLAIN}" "${CYAN}▶ Try to install the XanMod package: ${pkg}${PLAIN}" "${CYAN}▶ Попробуйте установить пакет XanMod: ${pkg}.${PLAIN}")"
        if install_pkg "$pkg"; then
            echo -e "$(localized_text "${GREEN}✅ 已安装 XanMod 内核包: ${pkg}${PLAIN}" "${GREEN}✅ XanMod kernel package installed: ${pkg}${PLAIN}" "${GREEN}✅ Установлен пакет ядра XanMod: ${pkg}${PLAIN}")"
            return 0
        fi
        echo -e "$(localized_text "${YELLOW}  - ${pkg} 安装失败，尝试更保守候选...${PLAIN}" "${YELLOW}- ${pkg} Installation failed, try more conservative candidate...${PLAIN}" "${YELLOW}- ${pkg} Не удалось установить, попробуйте более консервативный вариант...${PLAIN}")"
    done < <(xanmod_candidate_packages "$preferred_level")

    return 1
}

install_xanmod_kernel() {
    local codename confirm arch cpu_level

    if uname -r | grep -qi "xanmod"; then
        echo -e "$(localized_text "${GREEN}✅ 系统当前已运行 XanMod 内核 ($(uname -r))，无需重复安装！${PLAIN}" "${GREEN}✅ The system is currently running the XanMod kernel ($(uname -r)), no need to reinstall!${PLAIN}" "${GREEN}✅ В настоящее время в системе установлено ядро XanMod ($(uname -r)), переустанавливать не нужно!${PLAIN}")"
        return 0
    fi

    if ! is_debian; then
        echo -e "$(localized_text "${RED}❌ XanMod 自动安装目前仅支持 Debian/Ubuntu 衍生系统。${PLAIN}" "${RED}❌ XanMod automatic installation currently only supports Debian/Ubuntu derivative systems.${PLAIN}" "${RED}❌ Автоматическая установка XanMod в настоящее время поддерживает только производные системы Debian/Ubuntu.${PLAIN}")"
        return 1
    fi

    arch=$(normalize_kernel_arch)
    if [[ "$arch" != "amd64" ]]; then
        echo -e "$(localized_text "${RED}❌ XanMod 官方 x64v 内核仅支持 x86_64/amd64，本机为 $(uname -m)。${PLAIN}" "${RED}❌ XanMod official x64v kernel only supports x86_64/amd64, this machine is $(uname -m).${PLAIN}" "${RED}❌ Официальное ядро ​​XanMod x64v поддерживает только x86_64/amd64, эта машина — $(uname -m).${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}建议改用官方 Cloud/Virtual 内核。${PLAIN}" "${YELLOW}Recommends using the official Cloud/Virtual kernel instead.${PLAIN}" "${YELLOW}рекомендует вместо этого использовать официальное облачное/виртуальное ядро.${PLAIN}")"
        return 1
    fi

    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi
    if [[ -z "$codename" ]]; then
        echo -e "$(localized_text "${RED}❌ 无法识别系统代号，无法安全添加 XanMod 源。${PLAIN}" "${RED}❌ The system code cannot be recognized and the XanMod source cannot be safely added.${PLAIN}" "${RED}❌ Невозможно распознать системный код и безопасно добавить источник XanMod.${PLAIN}")"
        return 1
    fi
    if ! xanmod_supported_codename "$codename"; then
        echo -e "$(localized_text "${YELLOW}⚠️ 当前系统代号 ${codename} 可能不在脚本内置 XanMod 兼容列表中。${PLAIN}" "${YELLOW}⚠️ The current system code ${codename} may not be in the XanMod compatibility list built into the script.${PLAIN}" "${YELLOW}⚠️ Текущий системный код ${codename} может отсутствовать в списке совместимости XanMod, встроенном в скрипт.${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}脚本仍会尝试添加源；若 apt update 失败，请改用官方 Cloud/Virtual 内核。${PLAIN}" "${YELLOW}The script will still try to add the source; if apt update fails, please use the official Cloud/Virtual kernel instead.${PLAIN}" "${YELLOW}Сценарий все равно попытается добавить источник; Если обновление apt не удалось, используйте вместо него официальное облачное/виртуальное ядро.${PLAIN}")"
    fi

    cpu_level=$(xanmod_cpu_level)

    echo -e "$(localized_text "${RED}⚠️  XanMod 是第三方性能内核，可能影响 DKMS/驱动/部分云厂商兼容性。${PLAIN}" "${RED}⚠️ XanMod is a third-party performance kernel, which may affect DKMS/driver/some cloud vendor compatibility.${PLAIN}" "${RED}⚠️ XanMod — это ядро производительности стороннего производителя, которое может повлиять на совместимость DKMS/драйвера/некоторых облачных поставщиков.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}检测到 CPU 兼容级别：${cpu_level}，将从对应 XanMod LTS 包开始尝试，并自动向下兜底。${PLAIN}" "${YELLOW}Detects the CPU compatibility level: ${cpu_level}, and will start trying from the corresponding XanMod LTS package and automatically search downwards.${PLAIN}" "${YELLOW}определяет уровень совместимости ЦП: ${cpu_level}, начинает попытки из соответствующего пакета XanMod LTS и автоматически выполняет поиск вниз.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}建议先确认有快照、救援控制台，且知道如何从 GRUB 切回旧内核。${PLAIN}" "${YELLOW}It is recommended to first confirm that you have a snapshot, rescue console, and know how to switch back to the old kernel from GRUB.${PLAIN}" "${YELLOW}Рекомендуется сначала подтвердить, что у вас есть снимок, консоль восстановления и вы знаете, как вернуться к старому ядру из GRUB.${PLAIN}")"
    confirm_risk_action "$(localized_text "安装 XanMod 内核" "Install XanMod kernel" "Установите ядро XanMod.")" \
        "$(localized_text "内核包、引导配置和 GRUB 菜单" "Kernel packages, boot configurations, and GRUB menus" "Пакеты ядра, конфигурации загрузки и меню GRUB")" \
        "$(localized_text "使用当前可启动内核或云厂商救援模式恢复" "Recovery using current bootable kernel or cloud vendor rescue mode" "Восстановление с использованием текущего загрузочного ядра или режима восстановления облачного поставщика.")" \
        "$(localized_text "建议先创建 VPS 快照，并确认不是 OpenVZ 老系统。" "It is recommended to create a VPS snapshot first and confirm that it is not the old system OpenVZ." "Рекомендуется сначала создать снимок VPS и убедиться, что это не старая система OpenVZ.")" || { echo -e "$(localized_text "${BLUE}已取消 XanMod 安装。${PLAIN}" "${BLUE}XanMod installation has been canceled.${PLAIN}" "${BLUE}Установка XanMod отменена.${PLAIN}")"; return 1; }

    echo -e "$(localized_text "${CYAN}▶ 正在添加 XanMod 官方 APT 源并安装兼容内核...${PLAIN}" "${CYAN}▶ Adding XanMod official APT source and installing compatible kernel...${PLAIN}" "${CYAN}▶ Добавление официального источника APT XanMod и установка совместимого ядра...${PLAIN}")"
    ensure_minimal_system_compat
    install_pkg ca-certificates curl gpg gnupg || return 1
    add_xanmod_repo "$codename" || return 1

    if ! install_xanmod_kernel_package "$cpu_level"; then
        echo -e "$(localized_text "${RED}❌ XanMod 内核安装失败，可能是当前系统代号/软件源/CPU 级别暂不兼容。${PLAIN}" "${RED}❌ The XanMod kernel installation failed. It may be that the current system code/software source/CPU level is temporarily incompatible.${PLAIN}" "${RED}❌ Не удалось установить ядро XanMod. Возможно, текущий системный код/исходный код программного обеспечения/уровень ЦП временно несовместим.${PLAIN}")"
        return 1
    fi

    set_grub_default_kernel_by_keyword "xanmod"
}

func_install_kernel() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}☁️  安装/切换优化内核${PLAIN}" "${BOLD}☁️ Install/switch optimized kernel${PLAIN}" "${BOLD}☁️ Установить/переключить оптимизированное ядро${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${GREEN}  1. Cloud/KVM/Virtual 官方云内核${PLAIN} ${YELLOW}(推荐：稳定、轻量、云厂商兼容更好)${PLAIN}" "${GREEN}1. Cloud/KVM/Virtual official cloud kernel (recommended: stable, lightweight, better compatible with cloud vendors)${PLAIN}" "${GREEN}1. Облако/KVM/Официальное виртуальное облачное ядро (рекомендуется: стабильное, легкое, лучше совместимое с поставщиками облачных услуг)${PLAIN}")"
    echo -e "$(localized_text "     Debian/Ubuntu 会按架构自动尝试 cloud/kvm/virtual/generic 候选。" "Debian/Ubuntu will automatically try the cloud/kvm/virtual/generic candidate by architecture." "Debian/Ubuntu автоматически попробует кандидата Cloud/kvm/virtual/generic по архитектуре.")"
    echo -e "$(localized_text "${GREEN}  2. XanMod 性能内核${PLAIN} ${YELLOW}(高级：自动匹配 x64v1-v4 并向下兜底)${PLAIN}" "${GREEN}2. XanMod performance core (Advanced: automatically match x64v1-v4 and dig down)${PLAIN}" "${GREEN}2. Ядро производительности XanMod (Дополнительно: автоматическое сопоставление x64v1-v4 и поиск)${PLAIN}")"
    echo -e "$(localized_text "     适合：愿意折腾、追求低延迟/新特性；仅 amd64，建议有快照或救援控制台。" "Suitable for: willing to toss, pursuing low latency/new features; amd64 only, snapshot or rescue console recommended." "Подходит для: желающих бросить, стремящихся к низкой задержке/новым функциям; Только amd64, рекомендуется снимок или консоль восстановления.")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${RED}  0. 返回${PLAIN}" "${RED}0. Return${PLAIN}" "${RED}0. Возврат${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local kernel_choice virt
    read_trimmed kernel_choice "$(localized_text "👉 请选择要安装的内核类型 [推荐 1]: " "👉 Please select the kernel type to install [Recommended 1]:" "👉 Пожалуйста, выберите тип ядра для установки [рекомендуется 1]:")"
    kernel_choice="${kernel_choice:-1}"
    [[ "$kernel_choice" == "0" ]] && return

    virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    if [[ "$virt" =~ lxc|openvz ]]; then
        echo -e "$(localized_text "${RED}❌ 致命错误：检测到当前 VPS 为 $virt 容器架构！${PLAIN}" "${RED}❌ Fatal error: The current VPS is detected as $virt container architecture!${PLAIN}" "${RED}❌ Неустранимая ошибка: текущий VPS определен как контейнерная архитектура $virt!${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}💡 容器与母机共享内核，无法更改内核。操作已安全中止。${PLAIN}" "${YELLOW}💡 The container and the host machine share the kernel, and the kernel cannot be changed. The operation has been safely aborted.${PLAIN}" "${YELLOW}💡 Контейнер и хост-машина используют общее ядро, и ядро нельзя изменить. Операция благополучно прервана.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    local arch
    arch=$(normalize_kernel_arch)
    if [[ "$arch" == "unknown" ]]; then
        echo -e "$(localized_text "${RED}❌ 致命错误：当前架构暂不支持自动切换内核，本机为 $(uname -m)！${PLAIN}" "${RED}❌ Fatal error: The current architecture does not support automatic kernel switching. This machine is $(uname -m)!${PLAIN}" "${RED}❌ Неустранимая ошибка: текущая архитектура не поддерживает автоматическое переключение ядра. Эта машина $(uname -m)!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi
    if [[ "$kernel_choice" == "2" && "$arch" != "amd64" ]]; then
        echo -e "$(localized_text "${RED}❌ XanMod x64v 内核仅支持 x86_64/amd64，本机为 $(uname -m)。${PLAIN}" "${RED}❌ XanMod x64v kernel only supports x86_64/amd64, natively $(uname -m).${PLAIN}" "${RED}❌ Ядро XanMod x64v поддерживает только x86_64/amd64, изначально $(uname -m).${PLAIN}")"
        echo -e "$(localized_text "${YELLOW}建议选择 [1] 官方 Cloud/KVM/Virtual 内核。${PLAIN}" "${YELLOW}For , it is recommended to choose [1] official Cloud/KVM/Virtual kernel.${PLAIN}" "${YELLOW}Для рекомендуется выбрать [1] официальное ядро Cloud/KVM/Virtual.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    local install_rc=0
    case "$kernel_choice" in
        1) install_cloud_kvm_kernel ;;
        2) install_xanmod_kernel ;;
        *) echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"; read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"; return ;;
    esac
    install_rc=$?
    if [[ "$install_rc" -ne 0 ]]; then
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${YELLOW}⚠️ 内核安装/切换未完成，未继续提示重启。${PLAIN}" "${YELLOW}⚠️ The kernel installation/switching is not completed and the prompt to restart is not continued.${PLAIN}" "${YELLOW}⚠️ Установка/переключение ядра не завершено, а запрос на перезагрузку не продолжается.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "------------------------------------------------"
    echo -e "$(localized_text "${YELLOW}⚠️ 核心生效指引：${PLAIN}" "${YELLOW}⚠️ Core Validation Guide:${PLAIN}" "${YELLOW}⚠️ Руководство по проверке ядра:${PLAIN}")"
    echo -e "$(localized_text "1. 新内核引导已配置完毕，请先选择主菜单的 ${RED}[17] 重启服务器${PLAIN}。" "1. The new kernel boot configuration has been completed. Please select ${RED}[17] in the main menu to restart the server${PLAIN}." "1. Новая конфигурация загрузки ядра завершена. Пожалуйста, выберите ${RED}[17] в главном меню, чтобы перезапустить сервер${PLAIN}.")"
    echo -e "$(localized_text "2. 重启后请运行 ${GREEN}uname -r${PLAIN} 确认实际进入的新内核。" "2. After restarting, please run ${GREEN}Uname -r${PLAIN} to confirm the new kernel actually entered." "2. После перезапуска запустите ${GREEN}uname -r${PLAIN}, чтобы подтвердить, что новое ядро действительно введено.")"
    echo -e "$(localized_text "3. 确认稳定后，再进入本菜单选择 ${GREEN}[5] 清理旧内核${PLAIN}。" "3. After confirming that it is stable, enter this menu and select ${GREEN}[5] to clean up the old kernel${PLAIN}." "3. Убедившись, что оно стабильно, войдите в это меню и выберите ${GREEN}[5], чтобы очистить старое ядро${PLAIN}.")"

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

# ---------------------------------------------------------
# 10. 清理冗余旧内核 (数组菜单驱动 + 核心防砖拦截版)
# ---------------------------------------------------------
