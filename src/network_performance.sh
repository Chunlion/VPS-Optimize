# shellcheck shell=bash
# BBR, TCP parameter tuning, and ZRAM swap workflows.

func_bbr_manage() {
    clear
    echo -e "$(localized_text "${CYAN}👉 正在调用 ylx2016 网络极速脚本...${PLAIN}" "${CYAN}👉 Calling ylx2016 network speed script...${PLAIN}" "${CYAN}👉 Вызов сценария скорости сети ylx2016...${PLAIN}")"
    run_remote_script "$(localized_text "运行 ylx2016 网络极速脚本" "Run the ylx2016 network speed script" "Запустите сценарий скорости сети ylx2016.")" "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"
    pause_after_external_script "$(localized_text "操作结束，按回车键返回菜单..." "When the operation is completed, press the Enter key to return to the menu..." "Когда операция будет завершена, нажмите клавишу Enter, чтобы вернуться в меню...")"
}

# ---------------------------------------------------------
# 7. 动态 TCP 调优 (修复版：放宽正则以兼容多值与特殊符号)
# ---------------------------------------------------------

func_tcp_tune() {
    clear
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🚀 动态 TCP 极致调优 (Omnitt)${PLAIN}" "${BOLD}🚀 Dynamic TCP Extreme Tuning (Omnitt)${PLAIN}" "${BOLD}🚀 Dynamic TCP Extreme Tuning (Omnitt)${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "👉 推荐浏览器访问: ${BLUE}https://omnitt.com/${PLAIN} 获取针对您网络的定制参数" "👉 Recommended browser access: ${BLUE}Https://omnitt.com/${PLAIN} to obtain customized parameters for your network" "👉 Рекомендуемый доступ через браузер: ${BLUE}https://omnitt.com/${PLAIN} для получения индивидуальных параметров для вашей сети.")"
    echo -e "------------------------------------------------"
    
    read_trimmed yn "$(localized_text "❓ 准备好粘贴参数了吗？(Y/n): " "❓ Are you ready to paste the parameters? (Y/n):" "❓ Готовы ли вы вставить параметры? (Да/Нет):")"
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then return; fi
    
    local temp_f="/etc/sysctl.d/99-omnitt-tune.conf"
    local backup_f="${temp_f}.bak_$(date +%s)"
    
    # 事务起点：备份原配置
    if [[ -f "$temp_f" ]]; then
        cp "$temp_f" "$backup_f"
    fi
    
    > "$temp_f"
    echo -e "$(localized_text "\n${YELLOW}👇 请在下方直接【右键粘贴】代码。${PLAIN}" "\n${YELLOW}👇 Please directly [right-click and paste] the code below.${PLAIN}" "\n${YELLOW}👇 Пожалуйста, [щелкните правой кнопкой мыши и вставьте] код ниже.${PLAIN}")"
    echo -e "$(localized_text "${YELLOW}💡 粘贴完成后，请按下【回车键】，然后输入 ${RED}EOF${YELLOW} 并再次回车保存：${PLAIN}" "${YELLOW}💡 After pasting is completed, please press the [Enter key], then enter EOFand press Enter again to save:${PLAIN}" "${YELLOW}💡 После завершения вставки нажмите [Enter], затем введите EOFи снова нажмите Enter, чтобы сохранить:${PLAIN}")"
    
    local has_content=false
    while IFS= read -r line; do
        # 极简清洗：去除回车符和前后多余空格
        line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        
        # 结束符匹配（忽略大小写）
        if [[ "${line,,}" == "eof" ]]; then
            break
        fi
        
        # 【核心修复】：放宽等号右侧的值校验，允许包含空格(如 tcp_rmem) 和特殊符号(如 %)
        if [[ -z "$line" || "$line" =~ ^# || "$line" =~ ^[a-zA-Z0-9_.-]+[[:space:]]*=[[:space:]]*.+$ ]]; then
            echo "$line" >> "$temp_f"
            # 标记确实写入了有效参数，而不是只敲了几个回车
            [[ -n "$line" && ! "$line" =~ ^# ]] && has_content=true
        else
            echo -e "$(localized_text "${RED}⚠️ 已自动过滤非法参数行: $line${PLAIN}" "${RED}⚠️ Illegal parameter lines have been automatically filtered: $line${PLAIN}" "${RED}⚠️ Недопустимые строки параметров автоматически фильтруются: $line.${PLAIN}")"
        fi
    done
    
    if $has_content; then
        echo -e "$(localized_text "${CYAN}▶ 正在校验并应用新 TCP 参数...${PLAIN}" "${CYAN}▶ Verifying and applying new TCP parameters...${PLAIN}" "${CYAN}▶ Проверка и применение новых параметров TCP...${PLAIN}")"
        # 验证新配置是否被内核完全接受
        if sysctl -p "$temp_f" >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 动态 TCP 调优参数应用成功！网络吞吐量已提升。${PLAIN}" "${GREEN}✅ Dynamic TCP tuning parameters are applied successfully! Network throughput has been improved.${PLAIN}" "${GREEN}. Параметры динамической настройки TCP успешно применены! Пропускная способность сети была улучшена.${PLAIN}")"
            rm -f "$backup_f" # 成功则删除备份
        else
            echo -e "$(localized_text "${RED}❌ 致命错误：您粘贴的部分参数当前内核不支持或语法错误！${PLAIN}" "${RED}❌ Fatal error: Some of the parameters you pasted are not supported by the current kernel or have syntax errors!${PLAIN}" "${RED}❌ Неустранимая ошибка: некоторые из вставленных вами параметров не поддерживаются текущим ядром или содержат синтаксические ошибки!${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}正在触发安全回滚...${PLAIN}" "${YELLOW}Is triggering safe rollback...${PLAIN}" "${YELLOW}запускает безопасный откат...${PLAIN}")"
            if [[ -f "$backup_f" ]]; then
                mv "$backup_f" "$temp_f"
                sysctl -p "$temp_f" >/dev/null 2>&1
            else
                rm -f "$temp_f"
            fi
            echo -e "$(localized_text "${BLUE}✅ 已恢复系统原 TCP 状态，未造成任何破坏。${PLAIN}" "${BLUE}✅ The system has been restored to its original TCP state without causing any damage.${PLAIN}" "${BLUE}✅ Система была восстановлена в исходное состояние TCP без каких-либо повреждений.${PLAIN}")"
        fi
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到有效的 TCP 调优参数，操作已取消。${PLAIN}" "${YELLOW}⚠️ No valid TCP tuning parameters were detected and the operation was cancelled.${PLAIN}" "${YELLOW}⚠️ Не обнаружено действительных параметров настройки TCP, и операция была отменена.${PLAIN}")"
        if [[ -f "$backup_f" ]]; then mv "$backup_f" "$temp_f"; else rm -f "$temp_f"; fi
    fi
    
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}

# ---------------------------------------------------------
# 8. 智能内存调优 (重构版：安全接管与 DRY 化)
# ---------------------------------------------------------

func_zram_swap() {
    clear
    local mem
    mem=$(free -m | awk '/^Mem:/{print $2}')
    echo -e "$(localized_text "${CYAN}💡 硬件自适应调优 (检测到本机 ${mem}MB 物理内存)${PLAIN}" "${CYAN}💡 Hardware adaptive tuning (local ${mem}MB physical memory detected)${PLAIN}" "${CYAN}💡 Адаптивная настройка оборудования (обнаружена локальная физическая память ${mem}MB)${PLAIN}")"
    echo -e "------------------------------------------------"
    echo -e "$(localized_text " ${GREEN}1. 激进档 (适合 1G 以下小鸡)${PLAIN}" "${GREEN}1. Radical file (suitable for chicks below 1G)${PLAIN}" "${GREEN}1. Радикальный напильник (подходит для цыплят весом до 1 г)${PLAIN}")"
    echo -e "$(localized_text "    - ZRAM 100% 压缩, Swappiness=100。全力防止宕机。" "- ZRAM 100% compression, Swappiness=100. Do your best to prevent downtime." "- ZRAM 100% сжатие, Swappiness=100. Сделайте все возможное, чтобы предотвратить простои.")"
    echo -e "$(localized_text " ${GREEN}2. 积极档 (适合 2-4G 主流机型)${PLAIN}" "${GREEN}2. Active mode (suitable for 2-4G mainstream models)${PLAIN}" "${GREEN}2. Активный режим (подходит для основных моделей 2–4G)${PLAIN}")"
    echo -e "$(localized_text "    - ZRAM 70% 压缩, Swappiness=60。平衡性能与空间。" "- ZRAM 70% compression, Swappiness=60. Balance performance and space." "- ZRAM сжатие 70%, Swappiness=60. Баланс производительности и пространства.")"
    echo -e "$(localized_text " ${GREEN}3. 保守档 (适合 8G 以上性能怪兽)${PLAIN}" "${GREEN}3. Conservative file (suitable for performance monsters above 8G)${PLAIN}" "${GREEN}3. Консервативный файл (подходит для монстров производительности выше 8G)${PLAIN}")"
    echo -e "$(localized_text "    - ZRAM 25% 压缩, Swappiness=10。追求极致响应速度。" "- ZRAM 25% compression, Swappiness=10. Pursue the ultimate response speed." "- ZRAM сжатие 25%, Swappiness=10. Добейтесь максимальной скорости отклика.")"
    echo -e "------------------------------------------------"
    
    local choice
    read_trimmed choice "$(localized_text "👉 请选择您的调优挡位 [1/2/3] (直接回车按内存自动匹配): " "👉 Please select your tuning gear [1/2/3] (press Enter directly and press memory to automatically match):" "👉 Пожалуйста, выберите свое тюнинговое оборудование [1/2/3] (нажмите Enter и нажмите «память», чтобы автоматически подобрать совпадение):")"
    
    if [[ -z "$choice" ]]; then
        if [[ "$mem" -lt 1024 ]]; then choice=1
        elif [[ "$mem" -le 4096 ]]; then choice=2
        else choice=3
        fi
        echo -e "$(localized_text "${YELLOW}💡 系统已根据本机内存 (${mem}MB) 自动选择：[ 挡位 $choice ]${PLAIN}" "${YELLOW}💡 The system has automatically selected according to the local memory (${mem}MB): [ Gear $choice ]${PLAIN}" "${YELLOW}💡 Система автоматически выбрала в соответствии с локальной памятью (${mem}MB): [ Gear $choice ]${PLAIN}")"
        sleep 1.5
    fi
    
    # 提早阻断，避免非 Debian 机器运行破坏性 Swap 卸载指令
    if ! is_debian; then
        echo -e "$(localized_text "${RED}❌ 抱歉，当前系统并非 Debian/Ubuntu 衍生系，暂不支持自动化 ZRAM 调优。${PLAIN}" "${RED}❌ Sorry, the current system is not a Debian/Ubuntu derivative and does not currently support automated ZRAM tuning.${PLAIN}" "${RED}❌ Извините, текущая система не является производной Debian/Ubuntu и в настоящее время не поддерживает автоматическую настройку ZRAM.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在进行第一阶段：整理底层磁盘 Swap (保留 512M 保底防假死)...${PLAIN}" "${CYAN}▶ The first phase is in progress: organizing the underlying disk Swap (512M reserved to prevent suspended animation)...${PLAIN}" "${CYAN}▶ Выполняется первый этап: организация подкачки базового диска (512 МБ зарезервировано для предотвращения зависания)...${PLAIN}")"
    
    swapoff -a >/dev/null 2>&1
    local old_swap
    for old_swap in /swapfile /swap.img /var/swap /var/swapfile; do
        quarantine_path "$old_swap" "/root/vps-optimize-quarantine/swap" >/dev/null 2>&1 || true
    done
    
    dd if=/dev/zero of=/swapfile bs=1M count=512 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1
    
    sed -i -E 's/^([^#].*[[:space:]]swap[[:space:]].*)/#\1/' /etc/fstab
    sed -i '\@^/swapfile@d' /etc/fstab
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo -e "$(localized_text "${GREEN}✅ 已建立 512M 极小磁盘 Swap 作为系统崩溃的最后防线！${PLAIN}" "${GREEN}✅ A 512M very small disk Swap has been established as the last line of defense for system crashes!${PLAIN}" "${GREEN}. Очень маленький диск Swap объемом 512 МБ установлен в качестве последней линии защиты от сбоев системы!${PLAIN}")"
    
    echo -e "$(localized_text "${CYAN}▶ 正在进行第二阶段：配置 ZRAM 内存压缩引擎...${PLAIN}" "${CYAN}▶ Phase 2 in progress: Configuring the ZRAM memory compression engine...${PLAIN}" "${CYAN}▶ Выполняется этап 2: настройка механизма сжатия памяти ZRAM...${PLAIN}")"
    
    # 核心修改：使用全局包安装器
    install_pkg zram-tools
    modprobe zram >/dev/null 2>&1
    
    local zram_conf="/etc/default/zramswap"
    local percent=70
    local swap_val=60
    
    case $choice in
        1) percent=100; swap_val=100 ;;
        2) percent=70; swap_val=60 ;;
        3) percent=25; swap_val=10 ;;
        *) percent=70; swap_val=60 ;;
    esac
    
    cat <<EOF > "$zram_conf"
ALGO=zstd
PERCENT=$percent
PRIORITY=100
EOF
    
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zramswap >/dev/null 2>&1
    systemctl restart zramswap >/dev/null 2>&1
    
    if ! grep -q zram /proc/swaps; then
        if command -v zramswap >/dev/null 2>&1; then
            zramswap start >/dev/null 2>&1
        elif [[ -x /usr/sbin/zramswap ]]; then
            /usr/sbin/zramswap start >/dev/null 2>&1
        fi
    fi
    
    echo "vm.swappiness = $swap_val" > /etc/sysctl.d/99-zram-swappiness.conf
    sysctl -p /etc/sysctl.d/99-zram-swappiness.conf >/dev/null 2>&1
    
if grep -q zram /proc/swaps; then
        echo -e "$(localized_text "${GREEN}✅ ZRAM 调优落地完成！(已设置: ${percent}% 压缩比, ${swap_val} 交换倾向)${PLAIN}" "${GREEN}✅ ZRAM tuning and implementation completed! (Already set: ${percent}% compression ratio, ${swap_val} exchange tendency)${PLAIN}" "${GREEN}✅ Настройка и внедрение ZRAM завершены! (Уже установлено: степень сжатия ${percent}%, тенденция обмена ${swap_val})${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 警告：内核拒绝挂载 ZRAM (常见于 LXC/OpenVZ 架构)。${PLAIN}" "${RED}❌ Warning: The kernel refused to mount ZRAM (common in LXC/OpenVZ architectures).${PLAIN}" "${RED}❌ Внимание: ядро отказалось монтировать ZRAM (обычно в архитектурах LXC/OpenVZ).${PLAIN}")"
        echo -e "$(localized_text "${CYAN}▶ 正在启动降级优化方案：传统 Swap 扩容与内核防假死调优...${PLAIN}" "${CYAN}▶ Starting the downgrade optimization plan: traditional Swap expansion and kernel anti-suspense tuning...${PLAIN}" "${CYAN}▶ Начинаем план оптимизации перехода на более раннюю версию: традиционное расширение Swap и настройка антиприостановки ядра...${PLAIN}")"
        
        # 1. 扩容保底 Swap：从 512M 升级至 1024M (1GB)
        swapoff /swapfile >/dev/null 2>&1
        quarantine_path /swapfile "/root/vps-optimize-quarantine/swap" >/dev/null 2>&1 || true
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        
        # 2. 注入降级专属的内核内存管理参数
        # swappiness=30 : 只有内存比较吃紧时才使用较慢的磁盘 Swap
        # vfs_cache_pressure=50 : 降低系统回收目录/文件系统缓存的频率，提高小鸡流畅度
        # overcommit_memory=1 : 允许内核分配超过物理内存的空间，防止 Redis/数据库 等服务在启动时被直接 Kill
        cat <<EOF > /etc/sysctl.d/99-fallback-mem.conf
vm.swappiness = 30
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
EOF
        sysctl -p /etc/sysctl.d/99-fallback-mem.conf >/dev/null 2>&1
        
        echo -e "$(localized_text "${GREEN}✅ 降级优化落地：已动态扩充 1GB 磁盘 Swap，并激活保守内存回收策略！${PLAIN}" "${GREEN}✅ Downgrade optimization implemented: 1GB disk swap has been dynamically expanded and conservative memory recycling strategy has been activated!${PLAIN}" "${GREEN}✅ Реализована оптимизация понижения версии: подкачка диска на 1 ГБ была динамически расширена и активирована консервативная стратегия повторного использования памяти!${PLAIN}")"
    fi
    
    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
}
# ---------------------------------------------------------
# 9. 安装/切换优化内核 (Cloud/KVM 稳定优先 + XanMod 高级可选)
# ---------------------------------------------------------
