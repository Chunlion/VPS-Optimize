# shellcheck shell=bash
# Old kernel cleanup workflow.

func_clean_kernel() {
    clear
    if [[ ! "$OS" =~ debian|ubuntu ]]; then
        echo -e "$(localized_text "${RED}❌ 此功能目前仅支持 Debian/Ubuntu 衍生系统！${PLAIN}" "${RED}❌ This function currently only supports Debian/Ubuntu derivative systems!${PLAIN}" "${RED}❌ В настоящее время эта функция поддерживает только производные системы Debian/Ubuntu!${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    local current_k
    current_k=$(uname -r)
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "${BOLD}🧹 清理冗余旧内核${PLAIN}" "${BOLD}🧹 Clean up redundant old core${PLAIN}" "${BOLD}🧹 Очистите избыточное старое ядро${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "$(localized_text "当前正在运行的内核为: ${GREEN}${current_k}${PLAIN}" "The currently running kernel is: ${GREEN}${current_k}${PLAIN}" "Текущее работающее ядро: ${GREEN}${current_k}${PLAIN}.")"
    echo -e "$(localized_text "${RED}⚠️ 系统已自动为您屏蔽正在运行的内核以及常用云/虚拟化/性能内核。${PLAIN}" "${RED}⚠️ The system has automatically blocked running kernels and commonly used cloud/virtualization/performance kernels for you.${PLAIN}" "${RED}⚠️ Система автоматически заблокировала для вас работающие ядра и часто используемые облачные ядра/ядра виртуализации/производительности.${PLAIN}")"
    echo -e "------------------------------------------------"
    
    # 自动提取所有非当前的内核包存入数组 (排除元包，采用高可用字段匹配)
    mapfile -t old_kernels < <(dpkg -l | awk '$1 == "ii" && $2 ~ /^linux-image-[0-9]/ {print $2}' | grep -v "$current_k" | grep -Ev "cloud|kvm|virtual|generic|xanmod")

    if [[ ${#old_kernels[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${GREEN}✅ 系统非常干净，没有发现需要清理的冗余旧内核。${PLAIN}" "${GREEN}✅ The system is very clean and no redundant old cores that need to be cleaned are found.${PLAIN}" "${GREEN}✅ Система очень чистая и не обнаружено лишних старых ядер, требующих очистки.${PLAIN}")"
        read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
        return
    fi

    echo -e "$(localized_text "${YELLOW}扫描到以下冗余内核可供清理：${PLAIN}" "${YELLOW}Scanned the following redundant cores for cleaning:${PLAIN}" "${YELLOW}просканировал следующие резервные ядра для очистки:${PLAIN}")"
    for i in "${!old_kernels[@]}"; do
        echo -e " [${CYAN}$((i+1))${PLAIN}] ${old_kernels[$i]}"
    done
    echo -e "$(localized_text " [${RED}0${PLAIN}] 取消并返回" "[${RED}0${PLAIN}] Cancel and return" "[${RED}0${PLAIN}] Отменить и вернуться")"
    echo -e "------------------------------------------------"

    local k_choice
    read_trimmed k_choice "$(localized_text "👉 请输入要卸载的序号: " "👉 Please enter the serial number to be uninstalled:" "👉 Пожалуйста, введите серийный номер для удаления:")"

    if [[ "$k_choice" == "0" ]]; then
        echo -e "$(localized_text "${BLUE}已取消卸载操作。${PLAIN}" "${BLUE}The uninstall operation has been canceled.${PLAIN}" "${BLUE}Операция удаления отменена.${PLAIN}")"
    elif [[ "$k_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$k_choice" -le "${#old_kernels[@]}" ]]; then
        local target_k="${old_kernels[$((k_choice-1))]}"
        confirm_danger "$(localized_text "卸载旧内核 ${target_k}" "Uninstall old kernel ${target_k}" "Удалить старое ядро ${target_k}")" "$(localized_text "会删除内核包并刷新 GRUB，引导异常时可能影响下次启动。" "The kernel package will be deleted and GRUB will be refreshed. If the boot is abnormal, it may affect the next startup." "Пакет ядра будет удален, а GRUB будет обновлен. Если загрузка ненормальная, это может повлиять на следующий запуск.")" "$(localized_text "建议先创建 VPS 快照；当前运行内核已自动排除，如失败请从快照或救援模式恢复。" "It is recommended to create a VPS snapshot first; the currently running kernel has been automatically excluded. If it fails, please restore from the snapshot or rescue mode." "Рекомендуется сначала создать снимок VPS; работающее в данный момент ядро ​​было автоматически исключено. В случае сбоя восстановите систему из снимка или режима восстановления.")" || {
            echo -e "$(localized_text "${BLUE}已取消卸载操作。${PLAIN}" "${BLUE}The uninstall operation has been canceled.${PLAIN}" "${BLUE}Операция удаления отменена.${PLAIN}")"
            read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
            return
        }
        echo -e "$(localized_text "${CYAN}正在静默卸载 $target_k 并刷新引导...${PLAIN}" "${CYAN}Is silently uninstalling $target_k and refreshing the boot...${PLAIN}" "${CYAN}автоматически удаляет $target_k и обновляет загрузку...${PLAIN}")"
        export DEBIAN_FRONTEND=noninteractive
        if apt-get purge -yq "$target_k" && update-grub >/dev/null 2>&1 && apt-get autoremove --purge -yq >/dev/null 2>&1; then
            echo -e "$(localized_text "${GREEN}✅ 旧内核 [$target_k] 清理完成！磁盘空间已释放。${PLAIN}" "${GREEN}✅ Old kernel [$target_k] cleanup completed! Disk space has been released.${PLAIN}" "${GREEN}✅ Очистка старого ядра [$target_k] завершена! Дисковое пространство освобождено.${PLAIN}")"
        else
            echo -e "$(localized_text "${RED}❌ 清理失败！存在依赖问题或执行被中断。${PLAIN}" "${RED}❌ Cleanup failed! There is a dependency issue or execution is interrupted.${PLAIN}" "${RED}❌ Очистка не удалась! Возникла проблема с зависимостями или выполнение прервано.${PLAIN}")"
        fi
        unset DEBIAN_FRONTEND
    else
        echo -e "$(localized_text "${RED}❌ 无效的选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")"
    fi

    read -n 1 -s -r -p "$(localized_text "按任意键返回..." "Press any key to return..." "Нажмите любую клавишу, чтобы вернуться...")"
}

# ---------------------------------------------------------
# 11. 极速硬件探针
# ---------------------------------------------------------
