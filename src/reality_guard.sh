# shellcheck shell=bash
# REALITY fallback traffic controls for the shared 443 entry.

normalize_strict_sni_gate() {
    case "${1:-false}" in
        1|true|TRUE|yes|YES|on|ON) printf '%s' "true" ;;
        *) printf '%s' "false" ;;
    esac
}

strict_sni_gate_enabled() {
    [[ "$(normalize_strict_sni_gate "${STRICT_SNI_GATE:-false}")" == "true" ]]
}

registered_443_snis() {
    printf '%s\n' "${PANEL_DOMAIN:-}" "${SITE_DOMAINS[@]:-}" "${TCP_ROUTE_SNIS[@]:-}" "${XRAY_SNI_ROUTE_SNIS[@]:-}" "${REALITY_SNI:-}" |
        awk 'NF && !seen[tolower($0)]++'
}

strict_sni_gate_mode_supported() {
    local mode="${1:-$(get_entry_mode)}"
    [[ "$mode" == "nginx-stream" || "$mode" == "tcp-peek" ]]
}

print_strict_sni_gate_summary() {
    local state mode
    mode=$(get_entry_mode)
    if strict_sni_gate_enabled && strict_sni_gate_mode_supported "$mode"; then
        state="$(localized_text "${GREEN}已启用${PLAIN}" "${GREEN}Enabled${PLAIN}" "${GREEN}Включён${PLAIN}")"
    elif strict_sni_gate_enabled; then
        state="$(localized_text "${YELLOW}已保存，当前模式不生效${PLAIN}" "${YELLOW}Saved, inactive in the current mode${PLAIN}" "${YELLOW}Сохранён, не действует в текущем режиме${PLAIN}")"
    else
        state="$(localized_text "${YELLOW}未启用${PLAIN}" "${YELLOW}Disabled${PLAIN}" "${YELLOW}Выключен${PLAIN}")"
    fi
    echo -e "$(localized_text "严格 SNI 门禁：${state}" "Strict SNI gate: ${state}" "Строгий контроль SNI: ${state}")"
    echo -e "$(localized_text "当前入口模式：${mode}" "Current entry mode: ${mode}" "Текущий режим входа: ${mode}")"
    echo -e "$(localized_text "自动放行的已登记 SNI：" "Automatically allowed registered SNIs:" "Автоматически разрешённые зарегистрированные SNI:")"
    registered_443_snis | sed 's/^/  - /'
}

sync_strict_sni_gate_to_current_entry() {
    local mode
    mode=$(get_entry_mode)
    case "$mode" in
        nginx-stream) reapply_sni_stack_from_env --yes ;;
        tcp-peek) sync_xray_sni_routes_to_entry_mode ;;
        xray-fallback)
            echo -e "$(localized_text "${YELLOW}xray-fallback 由 Xray 直接监听公网 443，没有独立前置门禁；请使用 REALITY 回落限速。${PLAIN}" "${YELLOW}In xray-fallback mode, Xray listens on public port 443 directly, so there is no separate front gate. Use REALITY fallback rate limiting instead.${PLAIN}" "${YELLOW}В режиме xray-fallback Xray напрямую слушает публичный порт 443, поэтому отдельного входного фильтра нет. Используйте ограничение скорости REALITY fallback.${PLAIN}")"
            return 1
            ;;
        *) return 1 ;;
    esac
}

set_strict_sni_gate() {
    local target="$1" mode
    load_sni_stack_env || return 1
    mode=$(get_entry_mode)
    if [[ "$target" == "true" ]] && ! strict_sni_gate_mode_supported "$mode"; then
        echo -e "$(localized_text "${RED}当前模式不支持前置严格 SNI 门禁。${PLAIN}" "${RED}The current mode does not support a front strict SNI gate.${PLAIN}" "${RED}Текущий режим не поддерживает строгий входной контроль SNI.${PLAIN}")"
        return 1
    fi
    if [[ "$target" == "true" ]]; then
        confirm_danger "$(localized_text "启用严格 SNI 门禁" "Enable the strict SNI gate" "Включить строгий контроль SNI")" \
            "$(localized_text "未登记或不带 SNI 的连接会被直接丢弃，并重新应用当前入口" "drop connections with an unregistered or missing SNI and reapply the current entry" "отклонять подключения с незарегистрированным или отсутствующим SNI и повторно применить текущую точку входа")" \
            "$(localized_text "可重新进入本菜单关闭门禁；已登记的 SNI 清单不会删除" "disable the gate from this menu; the registered SNI list is retained" "контроль можно отключить в этом меню; список зарегистрированных SNI сохранится")" || return 0
    else
        confirm_danger "$(localized_text "关闭严格 SNI 门禁" "Disable the strict SNI gate" "Отключить строгий контроль SNI")" \
            "$(localized_text "未知 SNI 将恢复转发到默认 Xray 后端，并重新应用当前入口" "resume forwarding unknown SNI to the default Xray backend and reapply the current entry" "возобновить пересылку неизвестных SNI на стандартный бэкенд Xray и повторно применить текущую точку входа")" \
            "$(localized_text "可重新进入本菜单启用门禁" "enable the gate again from this menu" "контроль можно снова включить в этом меню")" || return 0
    fi
    STRICT_SNI_GATE="$target"
    save_sni_stack_env
    if sync_strict_sni_gate_to_current_entry; then
        echo -e "$(localized_text "${GREEN}✅ 严格 SNI 门禁已保存并同步到当前入口。${PLAIN}" "${GREEN}✅ The strict SNI gate was saved and synchronized to the current entry.${PLAIN}" "${GREEN}✅ Строгий контроль SNI сохранён и применён к текущему входу.${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}设置已保存，但未能同步到当前入口；请修复入口后重新应用。${PLAIN}" "${YELLOW}The setting was saved but could not be synchronized to the current entry. Fix the entry and reapply it.${PLAIN}" "${YELLOW}Настройка сохранена, но не применена к текущему входу. Исправьте вход и повторите применение.${PLAIN}")"
        return 1
    fi
}

reality_guard_python() {
    python3 - "$@" <<'PY'
import copy
import json
import sqlite3
import sys

operation, db_path = sys.argv[1:3]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
columns = {row[1] for row in conn.execute("pragma table_info(inbounds)")}
required = {"id", "port", "remark", "stream_settings"}
if not required.issubset(columns):
    raise SystemExit("unsupported inbounds schema")

def parse(row):
    try:
        stream = json.loads(row["stream_settings"] or "{}")
    except (TypeError, json.JSONDecodeError):
        return None
    if str(stream.get("security", "")).lower() != "reality":
        return None
    reality = stream.get("realitySettings")
    return stream if isinstance(reality, dict) else None

if operation == "list":
    for row in conn.execute("select id, port, remark, stream_settings from inbounds order by id"):
        stream = parse(row)
        if stream is None:
            continue
        reality = stream["realitySettings"]
        names = ",".join(str(item) for item in reality.get("serverNames", []) if item)
        upload = reality.get("limitFallbackUpload") or {}
        download = reality.get("limitFallbackDownload") or {}
        enabled = bool(upload.get("bytesPerSec", 0) or download.get("bytesPerSec", 0))
        remark = str(row["remark"] or "-").replace("\t", " ").replace("\n", " ")
        print(f"{row['id']}\t{row['port']}\t{remark}\t{names or '-'}\t{'enabled' if enabled else 'disabled'}")
    raise SystemExit(0)

inbound_id = int(sys.argv[3])
row = conn.execute("select id, port, remark, stream_settings from inbounds where id=?", (inbound_id,)).fetchone()
if row is None:
    raise SystemExit("inbound not found")
stream = parse(row)
if stream is None:
    raise SystemExit("selected inbound is not REALITY")
original = copy.deepcopy(stream)
reality = stream["realitySettings"]
if operation == "clear":
    reality.pop("limitFallbackUpload", None)
    reality.pop("limitFallbackDownload", None)
elif operation == "apply":
    values = [int(item) for item in sys.argv[4:10]]
    if any(item < 0 for item in values):
        raise SystemExit("rate-limit values must be non-negative")
    reality["limitFallbackUpload"] = dict(zip(("afterBytes", "bytesPerSec", "burstBytesPerSec"), values[:3]))
    reality["limitFallbackDownload"] = dict(zip(("afterBytes", "bytesPerSec", "burstBytesPerSec"), values[3:]))
else:
    raise SystemExit("unsupported operation")

expected = copy.deepcopy(original)
expected_reality = expected["realitySettings"]
if operation == "clear":
    expected_reality.pop("limitFallbackUpload", None)
    expected_reality.pop("limitFallbackDownload", None)
else:
    expected_reality["limitFallbackUpload"] = reality["limitFallbackUpload"]
    expected_reality["limitFallbackDownload"] = reality["limitFallbackDownload"]
if stream != expected:
    raise SystemExit("refusing to modify fields outside fallback limits")

payload = json.dumps(stream, ensure_ascii=False, separators=(",", ":"))
conn.execute("begin immediate")
cursor = conn.execute(
    "update inbounds set stream_settings=? where id=? and stream_settings=?",
    (payload, inbound_id, row["stream_settings"]),
)
if cursor.rowcount != 1:
    conn.rollback()
    raise SystemExit("inbound changed concurrently")
conn.commit()
saved = conn.execute("select stream_settings from inbounds where id=?", (inbound_id,)).fetchone()[0]
if json.loads(saved) != expected:
    raise SystemExit("post-write verification failed")
PY
}

find_reality_guard_database() {
    local db_path
    while IFS= read -r db_path; do
        [[ -f "$db_path" ]] || continue
        if [[ -n "$(reality_guard_python list "$db_path" 2>/dev/null | head -n1)" ]]; then
            printf '%s' "$db_path"
            return 0
        fi
    done < <(find_xui_database_candidates)
    return 1
}

backup_reality_guard_database() {
    local db_path="$1" inbound_id="$2" backup_dir backup_file timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="/root/x-ui-backups"
    backup_file="${backup_dir}/$(basename "$db_path").reality_guard_${inbound_id}_${timestamp}.bak"
    mkdir -p "$backup_dir"
    sqlite3 "$db_path" ".backup '${backup_file}'" >/dev/null 2>&1 || return 1
    printf '%s' "$backup_file"
}

restart_reality_guard_panel_service() {
    local service_name
    for service_name in x-ui 3x-ui x-panel; do
        if systemd_unit_exists "${service_name}.service"; then
            systemctl restart "$service_name" >/dev/null 2>&1 && systemctl is-active --quiet "$service_name" && return 0
            return 1
        fi
    done
    return 2
}

show_reality_guard_inbounds() {
    local db_path="$1" id port remark server_names state state_text
    echo -e "$(localized_text "ID  端口  名称  serverNames  回落限速" "ID  Port  Name  serverNames  Fallback limit" "ID  Порт  Имя  serverNames  Ограничение fallback")"
    while IFS=$'\t' read -r id port remark server_names state; do
        [[ -n "$id" ]] || continue
        if [[ "$state" == "enabled" ]]; then
            state_text="$(localized_text "已启用" "enabled" "включено")"
        else
            state_text="$(localized_text "未启用" "disabled" "выключено")"
        fi
        printf '%-3s %-5s %s | %s | %s\n' "$id" "$port" "$remark" "$server_names" "$state_text"
    done < <(reality_guard_python list "$db_path")
}

patch_reality_fallback_limits() {
    local operation="${1:-apply}" db_path inbound_id backup_file result
    local upload_after upload_rate upload_burst download_after download_rate download_burst
    load_sni_stack_env || return 1
    if xui_uses_postgresql; then
        echo -e "$(localized_text "${RED}检测到 PostgreSQL。为避免误改远程数据库，此功能仅支持本机 3x-ui SQLite。${PLAIN}" "${RED}PostgreSQL was detected. To avoid modifying a remote database by mistake, this function supports only local 3x-ui SQLite.${PLAIN}" "${RED}Обнаружен PostgreSQL. Чтобы исключить ошибочное изменение удалённой базы, функция поддерживает только локальный SQLite 3x-ui.${PLAIN}")"
        return 1
    fi
    command -v python3 >/dev/null 2>&1 || install_pkg python3 python3 >/dev/null 2>&1 || true
    command -v sqlite3 >/dev/null 2>&1 || install_pkg sqlite3 sqlite >/dev/null 2>&1 || true
    if ! command -v python3 >/dev/null 2>&1 || ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "$(localized_text "${RED}需要 python3 和 sqlite3，自动安装失败。${PLAIN}" "${RED}python3 and sqlite3 are required, and automatic installation failed.${PLAIN}" "${RED}Требуются python3 и sqlite3; автоматическая установка не удалась.${PLAIN}")"
        return 1
    fi
    db_path=$(find_reality_guard_database) || { echo -e "$(localized_text "${RED}未找到包含 REALITY 入站的 3x-ui SQLite 数据库。${PLAIN}" "${RED}No 3x-ui SQLite database containing a REALITY inbound was found.${PLAIN}" "${RED}Не найдена база SQLite 3x-ui с входящим REALITY.${PLAIN}")"; return 1; }
    echo -e "$(localized_text "数据库：${db_path}" "Database: ${db_path}" "База данных: ${db_path}")"
    show_reality_guard_inbounds "$db_path"
    read_trimmed inbound_id "$(localized_text "输入要处理的 REALITY 入站 ID（0 取消）: " "Enter the REALITY inbound ID to modify (0 cancels): " "Введите ID входящего REALITY (0 — отмена): ")"
    [[ "$inbound_id" == "0" || -z "$inbound_id" ]] && return 0
    [[ "$inbound_id" =~ ^[0-9]+$ ]] || { echo -e "$(localized_text "${RED}入站 ID 无效。${PLAIN}" "${RED}Invalid inbound ID.${PLAIN}" "${RED}Недопустимый ID входящего подключения.${PLAIN}")"; return 1; }

    if [[ "$operation" == "apply" ]]; then
        upload_after=$((10485760 + (RANDOM % 4194305) - 2097152))
        upload_rate=$((1048576 + (RANDOM % 419431) - 209715))
        upload_burst=$((5242880 + (RANDOM % 2097153) - 1048576))
        download_after=$((10485760 + (RANDOM % 4194305) - 2097152))
        download_rate=$((1048576 + (RANDOM % 419431) - 209715))
        download_burst=$((5242880 + (RANDOM % 2097153) - 1048576))
        echo -e "$(localized_text "将使用本次随机生成的回落限速参数（字节）：" "Randomized fallback limits for this operation (bytes):" "Случайные параметры ограничения fallback для этой операции (байты):")"
        echo "  upload:   afterBytes=${upload_after}, bytesPerSec=${upload_rate}, burstBytesPerSec=${upload_burst}"
        echo "  download: afterBytes=${download_after}, bytesPerSec=${download_rate}, burstBytesPerSec=${download_burst}"
        confirm_danger "$(localized_text "设置 REALITY 回落限速" "Set REALITY fallback rate limits" "Настроить ограничение REALITY fallback")" \
            "$(localized_text "只修改所选入站的两个 limitFallback 字段，并重启面板/Xray" "change only the two limitFallback fields of the selected inbound, then restart the panel/Xray" "изменить только два поля limitFallback выбранного входящего подключения, затем перезапустить панель/Xray")" \
            "$(localized_text "脚本会先备份数据库；可用本菜单清除限速或从备份恢复" "the database is backed up first; clear the limits from this menu or restore the backup" "сначала будет создана резервная копия базы; ограничения можно удалить в этом меню или восстановить базу из копии")" || return 0
    else
        confirm_danger "$(localized_text "清除 REALITY 回落限速" "Clear REALITY fallback rate limits" "Удалить ограничение REALITY fallback")" \
            "$(localized_text "删除所选入站的两个 limitFallback 字段，并重启面板/Xray" "remove the two limitFallback fields from the selected inbound, then restart the panel/Xray" "удалить два поля limitFallback выбранного входящего подключения, затем перезапустить панель/Xray")" \
            "$(localized_text "脚本会先备份数据库；可从备份恢复原参数" "the database is backed up first; restore the original values from the backup" "сначала будет создана резервная копия базы; исходные значения можно восстановить из неё")" || return 0
    fi

    backup_file=$(backup_reality_guard_database "$db_path" "$inbound_id") || { echo -e "$(localized_text "${RED}数据库备份失败，未执行修改。${PLAIN}" "${RED}Database backup failed; no changes were made.${PLAIN}" "${RED}Не удалось создать резервную копию базы; изменения не внесены.${PLAIN}")"; return 1; }
    if [[ "$operation" == "apply" ]]; then
        reality_guard_python apply "$db_path" "$inbound_id" "$upload_after" "$upload_rate" "$upload_burst" "$download_after" "$download_rate" "$download_burst" || result=$?
    else
        reality_guard_python clear "$db_path" "$inbound_id" || result=$?
    fi
    if [[ "${result:-0}" -ne 0 ]]; then
        echo -e "$(localized_text "${RED}入站更新失败，数据库保持原样。备份：${backup_file}${PLAIN}" "${RED}Inbound update failed; the database remains unchanged. Backup: ${backup_file}${PLAIN}" "${RED}Не удалось обновить входящее подключение; база не изменена. Резервная копия: ${backup_file}${PLAIN}")"
        return 1
    fi
    if restart_reality_guard_panel_service; then
        echo -e "$(localized_text "${GREEN}✅ REALITY 回落限速已更新并生效。数据库备份：${backup_file}${PLAIN}" "${GREEN}✅ REALITY fallback rate limiting was updated and activated. Database backup: ${backup_file}${PLAIN}" "${GREEN}✅ Ограничение скорости REALITY fallback обновлено и применено. Резервная копия: ${backup_file}${PLAIN}")"
    else
        echo -e "$(localized_text "${YELLOW}数据库已更新，但未检测到可成功重启的面板服务。请手动重启并检查 Xray；备份：${backup_file}${PLAIN}" "${YELLOW}The database was updated, but no panel service could be restarted successfully. Restart it manually and check Xray. Backup: ${backup_file}${PLAIN}" "${YELLOW}База обновлена, но службу панели не удалось перезапустить. Перезапустите её вручную и проверьте Xray. Резервная копия: ${backup_file}${PLAIN}")"
        return 1
    fi
}

manage_reality_traffic_guard() {
    while true; do
        local postgresql_mode=0
        clear
        load_sni_stack_env || return 1
        xui_uses_postgresql && postgresql_mode=1
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "${BOLD}REALITY 回落流量防护${PLAIN}" "${BOLD}REALITY fallback traffic protection${PLAIN}" "${BOLD}Защита трафика REALITY fallback${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "REALITY 验证失败的连接会转发到 target；使用 CDN 目标时可能被扫描后当作转发节点滥用。" "REALITY forwards failed-authentication connections to the target; a CDN target can make the server abusable as a relay after scanning." "REALITY пересылает подключения с ошибкой проверки на target; при CDN-цели сервер после сканирования может использоваться как ретранслятор.")"
        print_strict_sni_gate_summary
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 启用严格 SNI 门禁${PLAIN}      ${YELLOW}(仅放行自动登记的 SNI)${PLAIN}" "${GREEN}1. Enable strict SNI gate${PLAIN} (allow only automatically registered SNIs)" "${GREEN}1. Включить строгий контроль SNI${PLAIN} (только автоматически зарегистрированные SNI)")"
        echo -e "$(localized_text "${CYAN}  2. 关闭严格 SNI 门禁${PLAIN}      ${YELLOW}(恢复未知 SNI 默认转发)${PLAIN}" "${CYAN}2. Disable strict SNI gate${PLAIN} (restore default forwarding for unknown SNI)" "${CYAN}2. Отключить строгий контроль SNI${PLAIN} (вернуть стандартную пересылку неизвестных SNI)")"
        echo -e "$(localized_text "${CYAN}  3. 重新同步当前 SNI 清单${PLAIN}    ${YELLOW}(按已保存的域名和路由生成)${PLAIN}" "${CYAN}3. Resynchronize the current SNI list${PLAIN} (generated from saved domains and routes)" "${CYAN}3. Повторно синхронизировать список SNI${PLAIN} (из сохранённых доменов и маршрутов)")"
        if [[ "$postgresql_mode" -eq 1 ]]; then
            echo -e "$(localized_text "${YELLOW}  4. 设置 REALITY 回落限速${PLAIN}  ${RED}(不可用：仅支持本机 SQLite)${PLAIN}" "${YELLOW}4. Set REALITY fallback rate limits${PLAIN} ${RED}(unavailable: local SQLite only)${PLAIN}" "${YELLOW}4. Настроить ограничение REALITY fallback${PLAIN} ${RED}(недоступно: только локальный SQLite)${PLAIN}")"
            echo -e "$(localized_text "${YELLOW}  5. 清除 REALITY 回落限速${PLAIN}  ${RED}(不可用：仅支持本机 SQLite)${PLAIN}" "${YELLOW}5. Clear REALITY fallback rate limits${PLAIN} ${RED}(unavailable: local SQLite only)${PLAIN}" "${YELLOW}5. Удалить ограничение REALITY fallback${PLAIN} ${RED}(недоступно: только локальный SQLite)${PLAIN}")"
        else
            echo -e "$(localized_text "${GREEN}  4. 设置 REALITY 回落限速${PLAIN}  ${YELLOW}(仅修改两个 limitFallback 字段)${PLAIN}" "${GREEN}4. Set REALITY fallback rate limits${PLAIN} (changes only the two limitFallback fields)" "${GREEN}4. Настроить ограничение REALITY fallback${PLAIN} (только два поля limitFallback)")"
            echo -e "$(localized_text "${YELLOW}  5. 清除 REALITY 回落限速${PLAIN}  ${YELLOW}(恢复 Xray 默认行为)${PLAIN}" "${YELLOW}5. Clear REALITY fallback rate limits${PLAIN} (restore Xray defaults)" "${YELLOW}5. Удалить ограничение REALITY fallback${PLAIN} (вернуть настройки Xray по умолчанию)")"
        fi
        echo -e "$(localized_text "${RED}  0. 返回 / q 返回${PLAIN}" "${RED}0. Back / q Back${PLAIN}" "${RED}0. Назад / q Назад${PLAIN}")"
        local choice
        read_trimmed choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"
        case "$choice" in
            1) set_strict_sni_gate true ; pause_return ;;
            2) set_strict_sni_gate false ; pause_return ;;
            3)
                confirm_danger "$(localized_text "重新同步严格 SNI 清单" "Resynchronize the strict SNI list" "Повторно синхронизировать строгий список SNI")" \
                    "$(localized_text "重新生成当前入口配置；运行中的 Nginx 或 vpso-mux 可能重启" "regenerate the current entry configuration; the running Nginx or vpso-mux service may restart" "заново создать текущую конфигурацию точки входа; работающий Nginx или vpso-mux может быть перезапущен")" \
                    "$(localized_text "已保存的域名与路由不会删除；修正后可再次同步" "saved domains and routes are retained; correct them and synchronize again" "сохранённые домены и маршруты останутся; исправьте их и повторите синхронизацию")" && sync_strict_sni_gate_to_current_entry
                pause_return
                ;;
            4)
                if [[ "$postgresql_mode" -eq 1 ]]; then
                    echo -e "$(localized_text "${RED}当前 3x-ui 使用 PostgreSQL，回落限速仅支持本机 SQLite。${PLAIN}" "${RED}3x-ui currently uses PostgreSQL; fallback limits support only local SQLite.${PLAIN}" "${RED}3x-ui использует PostgreSQL; ограничение fallback поддерживает только локальный SQLite.${PLAIN}")"
                else
                    patch_reality_fallback_limits apply
                fi
                pause_return
                ;;
            5)
                if [[ "$postgresql_mode" -eq 1 ]]; then
                    echo -e "$(localized_text "${RED}当前 3x-ui 使用 PostgreSQL，回落限速仅支持本机 SQLite。${PLAIN}" "${RED}3x-ui currently uses PostgreSQL; fallback limits support only local SQLite.${PLAIN}" "${RED}3x-ui использует PostgreSQL; ограничение fallback поддерживает только локальный SQLite.${PLAIN}")"
                else
                    patch_reality_fallback_limits clear
                fi
                pause_return
                ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}无效选择。${PLAIN}" "${RED}Invalid selection.${PLAIN}" "${RED}Неверный выбор.${PLAIN}")"; sleep 1 ;;
        esac
    done
}
