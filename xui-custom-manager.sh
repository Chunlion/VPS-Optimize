#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/xui-custom-manager.conf}"

BACKUP_DIR="${BACKUP_DIR:-/root/x-ui-backups}"
XUI_DB="${XUI_DB:-/etc/x-ui/x-ui.db}"
XUI_ETC_DIR="${XUI_ETC_DIR:-/etc/x-ui}"
XUI_PROGRAM_DIR="${XUI_PROGRAM_DIR:-/usr/local/x-ui}"
XUI_BIN="${XUI_BIN:-/usr/local/x-ui/x-ui}"

DB_BACKUP_KEEP="${DB_BACKUP_KEEP:-20}"
PROGRAM_BACKUP_KEEP="${PROGRAM_BACKUP_KEEP:-10}"
ETC_BACKUP_KEEP="${ETC_BACKUP_KEEP:-10}"
LOG_FILE="${LOG_FILE:-/var/log/xui-custom-manager.log}"
EXPECTED_LISTEN_PORTS="${EXPECTED_LISTEN_PORTS:-40000 1443 2096}"
RESET_CONFIG="${RESET_CONFIG:-/etc/xui-custom-reset.json}"
RESET_STATE="${RESET_STATE:-/var/lib/xui-custom-manager/reset-state.json}"
RESET_SERVICE="${RESET_SERVICE:-/etc/systemd/system/xui-custom-reset.service}"
RESET_TIMER="${RESET_TIMER:-/etc/systemd/system/xui-custom-reset.timer}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/etc/xui-custom-manager.conf
    source "$CONFIG_FILE"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
PLAIN='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 root 用户运行。"
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo
echo "===== $(date '+%F %T') xui-custom-manager start ====="

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请用 root 用户运行。"
        exit 1
    fi
}

pause() {
    echo
    read -rp "按回车继续..."
}

confirm_action() {
    local message="$1"
    local answer

    echo
    echo "危险操作确认：$message"
    read -rp "请输入 YES 确认继续： " answer
    if [ "$answer" != "YES" ]; then
        echo "已取消。"
        return 1
    fi
}

ensure_dirs() {
    mkdir -p "$BACKUP_DIR"
}

install_runtime_deps() {
    if command -v sqlite3 >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        return
    fi

    echo "安装运行依赖..."
    apt update
    apt install -y sqlite3 python3
}

sqlite_has_column() {
    local table="$1"
    local column="$2"
    sqlite3 "$XUI_DB" "PRAGMA table_info(${table});" | awk -F'|' -v col="$column" '$2==col{found=1} END{exit !found}'
}

cleanup_backups_by_pattern() {
    local pattern="$1"
    local keep="$2"
    local label="$3"
    local files=()
    local delete_files=()
    local idx

    if ! [[ "$keep" =~ ^[0-9]+$ ]]; then
        echo "跳过 $label 清理：保留数量不是数字：$keep"
        return
    fi

    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$pattern" | sort -r)
    if [ "${#files[@]}" -le "$keep" ]; then
        return
    fi

    for ((idx = keep; idx < ${#files[@]}; idx++)); do
        delete_files+=("${files[$idx]}")
    done

    echo
    echo "$label 备份超过保留数量 $keep，以下旧备份可清理。"
    echo "为避免误删，本脚本每类备份只删除一个明确选择的文件。"
    for idx in "${!delete_files[@]}"; do
        printf '  %s) %s\n' "$((idx + 1))" "${delete_files[$idx]}"
    done

    local choice
    read -rp "请输入要删除的文件序号，直接回车跳过： " choice
    if [ -z "$choice" ]; then
        echo "已跳过 $label 清理。"
        return
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#delete_files[@]}" ]; then
        echo "无效选择，已跳过。"
        return
    fi

    local file="${delete_files[$((choice - 1))]}"
    if [ -f "$file" ]; then
        confirm_action "删除旧备份文件：$file" || return
        echo "删除旧备份：$file"
        rm -f -- "$file"
    fi
}

cleanup_backups() {
    ensure_dirs
    cleanup_backups_by_pattern "x-ui.db.*.bak" "$DB_BACKUP_KEEP" "数据库"
    cleanup_backups_by_pattern "x-ui-program.*.tar.gz" "$PROGRAM_BACKUP_KEEP" "程序目录"
    cleanup_backups_by_pattern "x-ui-etc.*.tar.gz" "$ETC_BACKUP_KEEP" "配置目录"
}

backup_all() {
    ensure_dirs
    local cleanup_after="${1:-yes}"
    local ts
    ts="$(date +%F_%H%M%S)"

    echo "备份 x-ui 数据..."

    if [ -f "$XUI_DB" ]; then
        cp -a "$XUI_DB" "$BACKUP_DIR/x-ui.db.$ts.bak"
        echo "数据库备份：$BACKUP_DIR/x-ui.db.$ts.bak"
    else
        echo "警告：未找到数据库 $XUI_DB"
    fi

    if [ -d "$XUI_ETC_DIR" ]; then
        tar -czf "$BACKUP_DIR/x-ui-etc.$ts.tar.gz" -C "$(dirname "$XUI_ETC_DIR")" "$(basename "$XUI_ETC_DIR")"
        echo "配置目录备份：$BACKUP_DIR/x-ui-etc.$ts.tar.gz"
    fi

    if [ -d "$XUI_PROGRAM_DIR" ]; then
        tar -czf "$BACKUP_DIR/x-ui-program.$ts.tar.gz" -C "$(dirname "$XUI_PROGRAM_DIR")" "$(basename "$XUI_PROGRAM_DIR")"
        echo "程序目录备份：$BACKUP_DIR/x-ui-program.$ts.tar.gz"
    fi

    if [ "$cleanup_after" = "yes" ]; then
        cleanup_backups
    fi
}

show_service_status_and_logs() {
    echo
    systemctl status x-ui --no-pager || true

    echo
    echo "最近日志："
    journalctl -u x-ui -n 100 --no-pager || true
}

health_check() {
    local has_problem=0
    local integrity_result
    local recent_logs
    local port

    echo
    echo "执行健康检查..."

    if systemctl is-active --quiet x-ui; then
        echo "OK：x-ui 服务正在运行。"
    else
        echo "!!! 警告：x-ui 服务未处于 active 状态。"
        has_problem=1
    fi

    if [ -f "$XUI_DB" ]; then
        echo "OK：数据库存在：$XUI_DB"
        integrity_result="$(sqlite3 "$XUI_DB" "PRAGMA integrity_check;" 2>&1 || true)"
        if [ "$integrity_result" = "ok" ]; then
            echo "OK：数据库完整性检查通过。"
        else
            echo "!!! 警告：数据库完整性检查异常：$integrity_result"
            has_problem=1
        fi
    else
        echo "!!! 警告：数据库不存在：$XUI_DB"
        has_problem=1
    fi

    recent_logs="$(journalctl -u x-ui -n 100 --no-pager 2>/dev/null || true)"
    if echo "$recent_logs" | grep -Eiq "panic|error|failed|no such column"; then
        echo "!!! 警告：最近 100 行日志包含 panic/error/failed/no such column："
        echo "$recent_logs" | grep -Ein "panic|error|failed|no such column" || true
        has_problem=1
    else
        echo "OK：最近 100 行日志未发现明显错误关键词。"
    fi

    if command -v ss >/dev/null 2>&1; then
        for port in $EXPECTED_LISTEN_PORTS; do
            if ss -ltnH | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
                echo "OK：端口 $port 正在监听。"
            else
                echo "!!! 警告：端口 $port 未监听。"
                has_problem=1
            fi
        done
    else
        echo "!!! 警告：未找到 ss，无法检查端口监听状态。"
        has_problem=1
    fi

    if [ "$has_problem" -eq 0 ]; then
        echo "健康检查通过。"
    else
        echo
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! 健康检查发现问题，请优先查看上方提示。"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    fi

    return "$has_problem"
}

show_traffic() {
    install_runtime_deps

    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        return
    fi

    echo
    echo "入站流量："
    if sqlite_has_column "inbounds" "last_traffic_reset_time"; then
        sqlite3 -header -column "$XUI_DB" "
SELECT id, remark, port, up, down, up + down AS used, total, traffic_reset, last_traffic_reset_time
FROM inbounds;
"
    else
        sqlite3 -header -column "$XUI_DB" "
SELECT id, remark, port, up, down, up + down AS used, total, traffic_reset
FROM inbounds;
"
    fi

    echo
    echo "客户端流量："

    if sqlite_has_column "client_traffics" "all_time"; then
        sqlite3 -header -column "$XUI_DB" "
SELECT id, inbound_id, email, up, down, up + down AS used, all_time, total
FROM client_traffics
ORDER BY inbound_id, email;
"
    else
        sqlite3 -header -column "$XUI_DB" "
SELECT id, inbound_id, email, up, down, up + down AS used, total
FROM client_traffics
ORDER BY inbound_id, email;
"
    fi
}

restore_program_backup() {
    need_root
    ensure_dirs
    local backups=()
    local choice
    local selected

    mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "x-ui-program.*.tar.gz" | sort -r)
    if [ "${#backups[@]}" -eq 0 ]; then
        echo "未找到程序备份：$BACKUP_DIR/x-ui-program.*.tar.gz"
        return
    fi

    echo
    echo "可恢复的程序备份："
    for i in "${!backups[@]}"; do
        printf '%s) %s\n' "$((i + 1))" "${backups[$i]}"
    done

    read -rp "请输入编号选择备份，或 q 退出： " choice
    if [[ "$choice" =~ ^[Qq]$ ]]; then
        echo "已取消。"
        return
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        echo "无效选择。"
        return
    fi

    selected="${backups[$((choice - 1))]}"
    confirm_action "停止 x-ui，并将程序目录恢复为 $selected" || return

    echo "停止 x-ui..."
    systemctl stop x-ui || true

    echo "恢复前先备份当前状态..."
    backup_all no

    echo "恢复程序目录到 $(dirname "$XUI_PROGRAM_DIR") ..."
    tar -xzf "$selected" -C "$(dirname "$XUI_PROGRAM_DIR")"

    echo "启动 x-ui..."
    systemctl start x-ui

    show_service_status_and_logs
    health_check || true
}

restore_database_backup() {
    need_root
    ensure_dirs
    local backups=()
    local choice
    local selected

    mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "x-ui.db.*.bak" | sort -r)
    if [ "${#backups[@]}" -eq 0 ]; then
        echo "未找到数据库备份：$BACKUP_DIR/x-ui.db.*.bak"
        return
    fi

    echo
    echo "可恢复的数据库备份："
    for i in "${!backups[@]}"; do
        printf '%s) %s\n' "$((i + 1))" "${backups[$i]}"
    done

    read -rp "请输入编号选择备份，或 q 退出： " choice
    if [[ "$choice" =~ ^[Qq]$ ]]; then
        echo "已取消。"
        return
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        echo "无效选择。"
        return
    fi

    selected="${backups[$((choice - 1))]}"
    confirm_action "停止 x-ui，并用 $selected 覆盖 $XUI_DB" || return

    echo "停止 x-ui..."
    systemctl stop x-ui || true

    echo "恢复前先备份当前状态..."
    backup_all no

    echo "恢复数据库到 $XUI_DB ..."
    mkdir -p "$(dirname "$XUI_DB")"
    cp -a "$selected" "$XUI_DB"
    chmod 600 "$XUI_DB" || true

    echo "启动 x-ui..."
    systemctl start x-ui

    show_service_status_and_logs
    health_check || true
}

show_reset_config() {
    if [ ! -f "$RESET_CONFIG" ]; then
        echo "未找到自定义重置配置：$RESET_CONFIG"
        echo "可通过菜单创建。"
        return
    fi

    python3 -m json.tool "$RESET_CONFIG"
}

custom_reset_settings() {
    need_root
    install_runtime_deps

    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        return
    fi

    local tmp_py
    local py_status
    tmp_py="$(mktemp --suffix=.py)"
    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import sys
from pathlib import Path

db = os.environ["XUI_DB"]
config_path = Path(os.environ["RESET_CONFIG"])

def load_config():
    if config_path.exists():
        with config_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = {}
    data.setdefault("enabled", True)
    data.setdefault("default_day", 1)
    data.setdefault("inbounds", {})
    return data

def save_config(data):
    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = config_path.with_suffix(config_path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    tmp_path.replace(config_path)
    print(f"已保存：{config_path}")

def input_choice(prompt, valid=None, allow_quit=True):
    while True:
        value = input(prompt).strip()
        if allow_quit and value.lower() in ("q", "quit", "exit"):
            print("已取消。")
            sys.exit(0)
        if valid is None or value in valid:
            return value
        print("输入无效，请重新选择。")

def input_day(prompt, allow_zero=False):
    while True:
        value = input(prompt).strip()
        if allow_zero and value in ("", "0"):
            return 0
        try:
            day = int(value)
        except ValueError:
            print("请输入数字。")
            continue
        min_day = 0 if allow_zero else 1
        if min_day <= day <= 31:
            return day
        print("日期范围必须是 1-31；客户端输入 0 表示继承入站。")

def yes_no(prompt, current):
    default = "Y/n" if current else "y/N"
    value = input(f"{prompt} [{default}] ").strip().lower()
    if value in ("",):
        return current
    return value in ("y", "yes")

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
cur = conn.cursor()
inbounds = cur.execute("""
SELECT id, remark, port, traffic_reset
FROM inbounds
ORDER BY id;
""").fetchall()

if not inbounds:
    print("没有找到任何入站。")
    sys.exit(1)

config = load_config()

while True:
    print()
    print("自定义每月重置日期设置")
    print(f"全局启用：{config.get('enabled', True)}")
    print(f"默认日期：{config.get('default_day', 1)}")
    print("G) 切换全局启用/禁用")
    print("D) 设置默认日期")
    print("S) 保存并退出")
    print("Q) 不保存退出")
    print()
    print("入站列表：")
    for idx, row in enumerate(inbounds, start=1):
        inbound_cfg = config["inbounds"].get(str(row["id"]), {})
        enabled = inbound_cfg.get("enabled", False)
        day = inbound_cfg.get("day", config.get("default_day", 1))
        remark = row["remark"] or "无备注"
        print(
            f"{idx}) ID={row['id']} | 端口={row['port']} | 备注={remark} | "
            f"原版重置={row['traffic_reset']} | 外置启用={enabled} | 日期={day}"
        )

    choice = input("\n选择入站编号，或 G/D/S/Q： ").strip()
    if choice.lower() == "q":
        print("未保存。")
        sys.exit(0)
    if choice.lower() == "s":
        save_config(config)
        sys.exit(0)
    if choice.lower() == "g":
        config["enabled"] = not bool(config.get("enabled", True))
        continue
    if choice.lower() == "d":
        config["default_day"] = input_day("请输入默认每月重置日期 [1-31]： ")
        continue
    if not choice.isdigit() or int(choice) < 1 or int(choice) > len(inbounds):
        print("无效选择。")
        continue

    inbound = inbounds[int(choice) - 1]
    inbound_id = str(inbound["id"])
    inbound_cfg = config["inbounds"].setdefault(inbound_id, {
        "enabled": True,
        "day": config.get("default_day", 1),
        "reset_inbound": True,
        "reset_clients_without_custom_day": False,
        "clients": {},
    })
    inbound_cfg.setdefault("enabled", True)
    inbound_cfg.setdefault("day", config.get("default_day", 1))
    inbound_cfg.setdefault("reset_inbound", True)
    inbound_cfg.setdefault("reset_clients_without_custom_day", False)
    inbound_cfg.setdefault("clients", {})

    clients = cur.execute("""
SELECT id, email, up, down, total
FROM client_traffics
WHERE inbound_id = ?
ORDER BY id;
""", (int(inbound_id),)).fetchall()

    while True:
        print()
        print(f"入站 ID={inbound_id} 设置")
        print(f"1) 启用外置重置：{inbound_cfg.get('enabled', True)}")
        print(f"2) 入站重置日期：{inbound_cfg.get('day', config.get('default_day', 1))}")
        print(f"3) 重置入站自身流量：{inbound_cfg.get('reset_inbound', True)}")
        print(f"4) 未单独设置日期的客户端跟随入站重置：{inbound_cfg.get('reset_clients_without_custom_day', False)}")
        print("5) 设置/删除客户端自定义日期")
        print("B) 返回入站列表")
        sub = input_choice("请选择： ", {"1", "2", "3", "4", "5", "B", "b"}, allow_quit=False)

        if sub.lower() == "b":
            break
        if sub == "1":
            inbound_cfg["enabled"] = not bool(inbound_cfg.get("enabled", True))
        elif sub == "2":
            inbound_cfg["day"] = input_day("请输入该入站每月重置日期 [1-31]： ")
        elif sub == "3":
            inbound_cfg["reset_inbound"] = yes_no("是否重置入站自身 up/down？", bool(inbound_cfg.get("reset_inbound", True)))
        elif sub == "4":
            inbound_cfg["reset_clients_without_custom_day"] = yes_no(
                "是否让未单独设置日期的客户端跟随入站日期重置 up/down？",
                bool(inbound_cfg.get("reset_clients_without_custom_day", False)),
            )
        elif sub == "5":
            if not clients:
                print("该入站下没有客户端。")
                continue
            print()
            print("客户端列表：")
            for cidx, client in enumerate(clients, start=1):
                email = client["email"]
                client_cfg = inbound_cfg["clients"].get(email)
                if client_cfg and client_cfg.get("enabled", True) and int(client_cfg.get("day", 0) or 0) > 0:
                    custom = f"自定义日期={client_cfg['day']}"
                else:
                    custom = "继承入站"
                print(f"{cidx}) {email} | {custom}")
            cchoice = input_choice("选择客户端编号，或 q 返回： ", {str(i) for i in range(1, len(clients) + 1)})
            client = clients[int(cchoice) - 1]
            email = client["email"]
            day = input_day("请输入客户端自定义日期 [1-31]，输入 0 删除自定义日期并继承入站： ", allow_zero=True)
            if day == 0:
                inbound_cfg["clients"].pop(email, None)
                print(f"已删除客户端 {email} 的自定义日期。")
            else:
                inbound_cfg["clients"][email] = {"enabled": True, "day": day}
                print(f"已设置客户端 {email} 每月 {day} 号重置。")
PY
    set +e
    XUI_DB="$XUI_DB" RESET_CONFIG="$RESET_CONFIG" python3 "$tmp_py"
    py_status=$?
    rm -f "$tmp_py"
    set -e
    return "$py_status"
}

run_custom_reset_check() {
    need_root

    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        return 1
    fi

    XUI_DB="$XUI_DB" XUI_BIN="$XUI_BIN" BACKUP_DIR="$BACKUP_DIR" RESET_CONFIG="$RESET_CONFIG" RESET_STATE="$RESET_STATE" python3 <<'PY'
import calendar
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

db = Path(os.environ["XUI_DB"])
xui_bin = Path(os.environ["XUI_BIN"])
backup_dir = Path(os.environ["BACKUP_DIR"])
config_path = Path(os.environ["RESET_CONFIG"])
state_path = Path(os.environ["RESET_STATE"])

def load_json(path, default):
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    tmp_path.replace(path)

def effective_day(year, month, configured_day):
    configured_day = int(configured_day)
    last_day = calendar.monthrange(year, month)[1]
    return min(configured_day, last_day)

def is_due(today, configured_day):
    if configured_day < 1 or configured_day > 31:
        return False
    return today.day == effective_day(today.year, today.month, configured_day)

def has_column(cur, table, column):
    return any(row[1] == column for row in cur.execute(f"PRAGMA table_info({table})"))

def integrity_check(cur, stage):
    result = cur.execute("PRAGMA integrity_check").fetchone()
    value = result[0] if result else ""
    print(f"{stage}数据库完整性检查：{value}")
    if value != "ok":
        raise RuntimeError(f"{stage}数据库完整性检查失败：{value}")

def systemctl(action):
    print(f"systemctl {action} x-ui")
    subprocess.run(["systemctl", action, "x-ui"], check=False)

def panel_signature(path):
    if not path.exists():
        return None
    stat = path.stat()
    return {
        "path": str(path),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }

if not config_path.exists():
    print(f"未找到自定义重置配置：{config_path}，跳过。")
    sys.exit(0)

config = load_json(config_path, {})
if not config.get("enabled", True):
    print("自定义重置全局已禁用，跳过。")
    sys.exit(0)

today = date.today()
today_text = today.isoformat()
state = load_json(state_path, {"inbounds": {}, "clients": {}})
state.setdefault("inbounds", {})
state.setdefault("clients", {})
current_panel_signature = panel_signature(xui_bin)
previous_panel_signature = state.get("panel_signature")
panel_seen_first_time = current_panel_signature and not previous_panel_signature
panel_changed = bool(current_panel_signature and previous_panel_signature and current_panel_signature != previous_panel_signature)
if panel_seen_first_time:
    print(f"记录当前面板程序状态：{xui_bin}")
elif panel_changed:
    print(f"检测到面板程序已更新：{xui_bin}")
    print("自定义重置日期配置保存在外置配置文件中，将继续沿用。")

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

inbounds = cur.execute("SELECT id, up, down, traffic_reset FROM inbounds ORDER BY id").fetchall()
clients = cur.execute("SELECT inbound_id, email, up, down FROM client_traffics ORDER BY inbound_id, email").fetchall()
clients_by_inbound = {}
existing_client_keys = set()
for client in clients:
    inbound_key = str(client["inbound_id"])
    clients_by_inbound.setdefault(inbound_key, []).append(client)
    existing_client_keys.add(f"{inbound_key}|{client['email']}")

planned_inbounds = []
planned_clients = []
reapply_inbounds = []
default_day = int(config.get("default_day", 1) or 1)
configured_inbounds = config.get("inbounds", {})

for inbound in inbounds:
    inbound_id = str(inbound["id"])
    inbound_cfg = configured_inbounds.get(inbound_id, {})
    if not inbound_cfg.get("enabled", False):
        continue
    if inbound["traffic_reset"] == "monthly":
        reapply_inbounds.append(inbound_id)
    inbound_day = int(inbound_cfg.get("day", default_day) or default_day)
    client_cfgs = inbound_cfg.get("clients", {})
    has_inbound_due = is_due(today, inbound_day)

    if has_inbound_due and state["inbounds"].get(inbound_id) != today_text and inbound_cfg.get("reset_inbound", True):
        planned_inbounds.append(inbound_id)

    if has_inbound_due and inbound_cfg.get("reset_clients_without_custom_day", False):
        for client in clients_by_inbound.get(inbound_id, []):
            email = client["email"]
            cfg = client_cfgs.get(email, {})
            has_custom_day = bool(cfg.get("enabled", True)) and int(cfg.get("day", 0) or 0) > 0
            client_key = f"{inbound_id}|{email}"
            if not has_custom_day and state["clients"].get(client_key) != today_text:
                planned_clients.append((inbound_id, email, client_key))

    for email, cfg in client_cfgs.items():
        if not cfg.get("enabled", True):
            continue
        client_day = int(cfg.get("day", 0) or 0)
        if client_day <= 0:
            continue
        client_key = f"{inbound_id}|{email}"
        if client_key not in existing_client_keys:
            print(f"跳过不存在的客户端配置：{client_key}")
            continue
        if is_due(today, client_day) and state["clients"].get(client_key) != today_text:
            planned_clients.append((inbound_id, email, client_key))

unique_clients = []
seen = set()
for item in planned_clients:
    if item[2] not in seen:
        unique_clients.append(item)
        seen.add(item[2])
planned_clients = unique_clients

if not planned_inbounds and not planned_clients and not reapply_inbounds:
    if current_panel_signature:
        state["panel_signature"] = current_panel_signature
        save_json(state_path, state)
    print(f"{today_text} 没有需要执行的自定义重置。")
    conn.close()
    sys.exit(0)

print(f"{today_text} 准备执行外置规则维护：")
for inbound_id in reapply_inbounds:
    print(f"  重套外置规则：入站 {inbound_id} traffic_reset monthly -> never")
for inbound_id in planned_inbounds:
    print(f"  入站：{inbound_id}")
for inbound_id, email, _ in planned_clients:
    print(f"  客户端：{inbound_id}|{email}")

backup_dir.mkdir(parents=True, exist_ok=True)
backup_path = backup_dir / f"x-ui.db.{time.strftime('%Y-%m-%d_%H%M%S')}.bak"

systemctl("stop")
try:
    shutil.copy2(db, backup_path)
    print(f"重置前数据库备份：{backup_path}")
    integrity_check(cur, "修改前")
    now_ms = int(time.time() * 1000)
    inbound_has_reset_time = has_column(cur, "inbounds", "last_traffic_reset_time")
    client_has_reset_time = has_column(cur, "client_traffics", "last_traffic_reset_time")

    for inbound_id in reapply_inbounds:
        cur.execute("UPDATE inbounds SET traffic_reset = 'never' WHERE id = ? AND traffic_reset = 'monthly'", (inbound_id,))

    for inbound_id in planned_inbounds:
        if inbound_has_reset_time:
            cur.execute("UPDATE inbounds SET up = 0, down = 0, last_traffic_reset_time = ? WHERE id = ?", (now_ms, inbound_id))
        else:
            cur.execute("UPDATE inbounds SET up = 0, down = 0 WHERE id = ?", (inbound_id,))
        state["inbounds"][inbound_id] = today_text

    for inbound_id, email, client_key in planned_clients:
        if client_has_reset_time:
            cur.execute(
                "UPDATE client_traffics SET up = 0, down = 0, last_traffic_reset_time = ? WHERE inbound_id = ? AND email = ?",
                (now_ms, inbound_id, email),
            )
        else:
            cur.execute(
                "UPDATE client_traffics SET up = 0, down = 0 WHERE inbound_id = ? AND email = ?",
                (inbound_id, email),
            )
        state["clients"][client_key] = today_text

    integrity_check(cur, "修改后")
    conn.commit()
    if current_panel_signature:
        state["panel_signature"] = current_panel_signature
    save_json(state_path, state)
    print("外置规则维护执行完成。")
except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
    systemctl("start")
PY
}

install_reset_timer() {
    need_root
    local script_path
    script_path="$(readlink -f "$0")"

    confirm_action "安装/更新 systemd timer，每天 00:00:30 执行自定义重置检查" || return

    cat >"$RESET_SERVICE" <<EOF
[Unit]
Description=x-ui custom monthly traffic reset
After=network.target

[Service]
Type=oneshot
ExecStart=$script_path --run-reset-check
EOF

    cat >"$RESET_TIMER" <<'EOF'
[Unit]
Description=Run x-ui custom monthly traffic reset daily

[Timer]
OnCalendar=*-*-* 00:00:30
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now xui-custom-reset.timer
    systemctl status xui-custom-reset.timer --no-pager || true
}

show_reset_logs() {
    echo "管理脚本日志：$LOG_FILE"
    tail -n 200 "$LOG_FILE" || true

    echo
    echo "timer 日志："
    journalctl -u xui-custom-reset.service -u xui-custom-reset.timer -n 100 --no-pager || true
}

disable_monthly_reset() {
    need_root
    install_runtime_deps

    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        return
    fi

    if [ ! -f "$RESET_CONFIG" ]; then
        echo "未找到自定义重置配置：$RESET_CONFIG"
        echo "请先进入 1) 自定义每月重置日期设置，启用需要外置管理的入站。"
        return 1
    fi

    set +e
    XUI_DB="$XUI_DB" RESET_CONFIG="$RESET_CONFIG" BACKUP_DIR="$BACKUP_DIR" python3 <<'PY'
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

db = Path(os.environ["XUI_DB"])
config_path = Path(os.environ["RESET_CONFIG"])
backup_dir = Path(os.environ["BACKUP_DIR"])

def integrity_check(cur, stage):
    result = cur.execute("PRAGMA integrity_check").fetchone()
    value = result[0] if result else ""
    print(f"{stage}数据库完整性检查：{value}")
    if value != "ok":
        raise RuntimeError(f"{stage}数据库完整性检查失败：{value}")

def systemctl(action):
    print(f"systemctl {action} x-ui")
    subprocess.run(["systemctl", action, "x-ui"], check=False)

with config_path.open("r", encoding="utf-8") as f:
    config = json.load(f)

enabled_ids = [
    int(inbound_id)
    for inbound_id, cfg in config.get("inbounds", {}).items()
    if cfg.get("enabled", False)
]
if not enabled_ids:
    print("当前没有启用外置重置的入站。")
    sys.exit(0)

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
cur = conn.cursor()
placeholders = ",".join("?" for _ in enabled_ids)
rows = cur.execute(f"""
SELECT id, remark, port, traffic_reset
FROM inbounds
WHERE traffic_reset = 'monthly' AND id IN ({placeholders})
ORDER BY id
""", enabled_ids).fetchall()

if not rows:
    print("外置管理的入站里没有检测到 traffic_reset='monthly'。")
    conn.close()
    sys.exit(0)

print("以下已启用外置规则的入站仍是原版 monthly，将改为 never：")
for row in rows:
    print(f"  ID={row['id']} | 端口={row['port']} | 备注={row['remark'] or '无备注'} | {row['traffic_reset']}")

answer = input("请输入 YES 确认写入： ").strip()
if answer != "YES":
    print("已取消。")
    conn.close()
    sys.exit(0)

systemctl("stop")
try:
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = backup_dir / f"x-ui.db.{time.strftime('%Y-%m-%d_%H%M%S')}.bak"
    shutil.copy2(db, backup_path)
    print(f"数据库备份：{backup_path}")
    integrity_check(cur, "修改前")
    target_ids = [int(row["id"]) for row in rows]
    target_placeholders = ",".join("?" for _ in target_ids)
    cur.execute(
        f"UPDATE inbounds SET traffic_reset = 'never' WHERE traffic_reset = 'monthly' AND id IN ({target_placeholders})",
        target_ids,
    )
    integrity_check(cur, "修改后")
    conn.commit()
    print("已禁用外置管理入站的原版 monthly 自动重置。")
except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
    systemctl("start")
PY
    local py_status=$?
    set -e
    if [ "$py_status" -ne 0 ]; then
        return "$py_status"
    fi
    show_traffic
}

manual_reset_or_update_total() {
    need_root
    install_runtime_deps

    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        return
    fi

    local tmp_py
    local py_status
    tmp_py="$(mktemp --suffix=.py)"
    cat > "$tmp_py" <<'PY'
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

db = Path(os.environ["XUI_DB"])
backup_dir = Path(os.environ["BACKUP_DIR"])

def human_size(num):
    try:
        num = int(num or 0)
    except Exception:
        num = 0
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    size = float(num)
    for unit in units:
        if abs(size) < 1024 or unit == units[-1]:
            return f"{int(size)} {unit}" if unit == "B" else f"{size:.2f} {unit}"
        size /= 1024

def input_choice(prompt, valid=None, allow_quit=True):
    while True:
        value = input(prompt).strip()
        if allow_quit and value.lower() in ("q", "quit", "exit"):
            print("已取消。")
            sys.exit(0)
        if valid is None or value in valid:
            return value
        print("输入无效，请重新选择。")

def to_bytes(value, unit):
    value = Decimal(value)
    if value < 0:
        raise ValueError("数值不能为负数")
    base = Decimal(1000) ** 3 if unit == "gb" else Decimal(1024) ** 3
    return int((value * base).to_integral_value(rounding=ROUND_HALF_UP))

def has_column(cur, table, column):
    return any(row[1] == column for row in cur.execute(f"PRAGMA table_info({table})"))

def integrity_check(cur, stage):
    value = cur.execute("PRAGMA integrity_check").fetchone()[0]
    print(f"{stage}数据库完整性检查：{value}")
    if value != "ok":
        raise RuntimeError(f"{stage}数据库完整性检查失败：{value}")

def backup_db():
    backup_dir.mkdir(parents=True, exist_ok=True)
    path = backup_dir / f"x-ui.db.{time.strftime('%Y-%m-%d_%H%M%S')}.bak"
    shutil.copy2(db, path)
    print(f"数据库备份：{path}")

def stop_start(action):
    print(f"systemctl {action} x-ui")
    subprocess.run(["systemctl", action, "x-ui"], check=False)

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

inbounds = cur.execute("""
SELECT id, remark, port, up, down, total
FROM inbounds
ORDER BY id;
""").fetchall()
if not inbounds:
    print("没有找到任何入站。")
    sys.exit(1)

print()
print("请选择操作：")
print("1) 手动清零指定入站/客户端 up/down")
print("2) 修改指定入站/客户端流量上限 total")
action = input_choice("请选择 [1/2]： ", {"1", "2"})

print()
print("入站列表：")
for idx, row in enumerate(inbounds, start=1):
    remark = row["remark"] or "无备注"
    used = int(row["up"] or 0) + int(row["down"] or 0)
    print(
        f"{idx}) ID={row['id']} | 端口={row['port']} | 备注={remark} | "
        f"已用={human_size(used)} | 上限={human_size(row['total'])}"
    )

inbound_choice = input_choice("请选择入站编号，或 q 退出： ", {str(i) for i in range(1, len(inbounds) + 1)})
inbound = inbounds[int(inbound_choice) - 1]
inbound_id = int(inbound["id"])

clients = cur.execute("""
SELECT id, inbound_id, email, up, down, total
FROM client_traffics
WHERE inbound_id = ?
ORDER BY id;
""", (inbound_id,)).fetchall()

print()
print("请选择对象：")
print("0) 入站自身")
for idx, client in enumerate(clients, start=1):
    used = int(client["up"] or 0) + int(client["down"] or 0)
    print(f"{idx}) 客户端={client['email']} | 已用={human_size(used)} | 上限={human_size(client['total'])}")

target_choice = input_choice("请选择对象编号，或 q 退出： ", {"0"} | {str(i) for i in range(1, len(clients) + 1)})
target_is_inbound = target_choice == "0"
target_client = None if target_is_inbound else clients[int(target_choice) - 1]

if action == "1":
    target_text = f"入站 ID={inbound_id}" if target_is_inbound else f"客户端 {target_client['email']}"
    confirm = input(f"确认清零 {target_text} 的 up/down？请输入 YES： ").strip()
    if confirm != "YES":
        print("已取消。")
        sys.exit(0)

    stop_start("stop")
    try:
        backup_db()
        integrity_check(cur, "修改前")
        now_ms = int(time.time() * 1000)
        if target_is_inbound:
            if has_column(cur, "inbounds", "last_traffic_reset_time"):
                cur.execute("UPDATE inbounds SET up = 0, down = 0, last_traffic_reset_time = ? WHERE id = ?", (now_ms, inbound_id))
            else:
                cur.execute("UPDATE inbounds SET up = 0, down = 0 WHERE id = ?", (inbound_id,))
        else:
            if has_column(cur, "client_traffics", "last_traffic_reset_time"):
                cur.execute("UPDATE client_traffics SET up = 0, down = 0, last_traffic_reset_time = ? WHERE id = ?", (now_ms, target_client["id"]))
            else:
                cur.execute("UPDATE client_traffics SET up = 0, down = 0 WHERE id = ?", (target_client["id"],))
        integrity_check(cur, "修改后")
        conn.commit()
        print("手动清零完成。")
    except Exception:
        conn.rollback()
        raise
    finally:
        stop_start("start")
else:
    print()
    print("请选择单位：")
    print("1) GB，十进制，1GB = 1000^3 bytes")
    print("2) GiB，二进制，1GiB = 1024^3 bytes")
    unit_choice = input_choice("请选择 [1/2]，默认 2： ", {"", "1", "2"}, allow_quit=False)
    unit = "gb" if unit_choice == "1" else "gib"
    unit_label = "GB" if unit == "gb" else "GiB"
    while True:
        try:
            value = input(f"请输入新的 total（{unit_label}）： ").strip()
            total_bytes = to_bytes(value, unit)
            break
        except Exception as exc:
            print(f"输入无效：{exc}")
    target_text = f"入站 ID={inbound_id}" if target_is_inbound else f"客户端 {target_client['email']}"
    print(f"即将把 {target_text} 的 total 改为 {total_bytes} bytes = {human_size(total_bytes)}")
    confirm = input("确认写入？请输入 YES： ").strip()
    if confirm != "YES":
        print("已取消。")
        sys.exit(0)

    stop_start("stop")
    try:
        backup_db()
        integrity_check(cur, "修改前")
        if target_is_inbound:
            cur.execute("UPDATE inbounds SET total = ? WHERE id = ?", (total_bytes, inbound_id))
        else:
            cur.execute("UPDATE client_traffics SET total = ? WHERE id = ?", (total_bytes, target_client["id"]))
        integrity_check(cur, "修改后")
        conn.commit()
        print("流量上限修改完成。")
    except Exception:
        conn.rollback()
        raise
    finally:
        stop_start("start")

conn.close()
PY
    set +e
    XUI_DB="$XUI_DB" BACKUP_DIR="$BACKUP_DIR" python3 "$tmp_py"
    py_status=$?
    rm -f "$tmp_py"
    set -e
    if [ "$py_status" -ne 0 ]; then
        return "$py_status"
    fi
    show_traffic
}

edit_traffic() {
    need_root
    install_runtime_deps

    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        exit 1
    fi

    echo "读取当前流量数据..."
    show_traffic

    confirm_action "停止 x-ui、备份数据库并修改流量数据" || return

    systemctl stop x-ui || true
    backup_all no

    set +e
    local tmp_py
    tmp_py="$(mktemp --suffix=.py)"
    cat > "$tmp_py" <<'PY'
import os
import sqlite3
import sys
from decimal import Decimal, ROUND_HALF_UP

db = os.environ["XUI_DB"]

def human_size(num):
    try:
        num = int(num or 0)
    except Exception:
        num = 0

    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    size = float(num)
    for unit in units:
        if abs(size) < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.2f} {unit}"
        size /= 1024

def input_choice(prompt, valid=None, allow_quit=True):
    while True:
        s = input(prompt).strip()
        if allow_quit and s.lower() in ("q", "quit", "exit"):
            print("已取消。")
            sys.exit(0)
        if valid is None or s in valid:
            return s
        print("输入无效，请重新选择。")

def has_column(cur, table, column):
    return any(row[1] == column for row in cur.execute(f"PRAGMA table_info({table})"))

def integrity_check(cur, stage):
    result = cur.execute("PRAGMA integrity_check").fetchone()
    value = result[0] if result else ""
    print(f"{stage}数据库完整性检查：{value}")
    if value != "ok":
        raise RuntimeError(f"{stage}数据库完整性检查失败：{value}")

def to_bytes(value, unit):
    value = Decimal(value)
    if value < 0:
        raise ValueError("流量不能为负数")
    base = Decimal(1000) ** 3 if unit == "gb" else Decimal(1024) ** 3
    return int((value * base).to_integral_value(rounding=ROUND_HALF_UP))

def split_by_ratio(total_bytes, current_up, current_down):
    current_up = int(current_up or 0)
    current_down = int(current_down or 0)
    current_total = current_up + current_down
    if current_total <= 0:
        return 0, total_bytes
    up = int((Decimal(total_bytes) * Decimal(current_up) / Decimal(current_total)).to_integral_value(rounding=ROUND_HALF_UP))
    down = total_bytes - up
    return up, down

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

try:
    integrity_check(cur, "修改前")

    inbounds = cur.execute("""
SELECT id, remark, port, up, down, total, traffic_reset
FROM inbounds
ORDER BY id;
""").fetchall()

    if not inbounds:
        print("没有找到任何入站。")
        sys.exit(1)

    print()
    print("请选择要修改的入站：")
    for idx, row in enumerate(inbounds, start=1):
        remark = row["remark"] or "无备注"
        used = int(row["up"] or 0) + int(row["down"] or 0)
        total = int(row["total"] or 0)
        print(
            f"{idx}) ID={row['id']} | 备注={remark} | 端口={row['port']} | "
            f"已用={human_size(used)} | 上行={human_size(row['up'])} | 下行={human_size(row['down'])} | "
            f"上限={human_size(total)} | 重置={row['traffic_reset']}"
        )

    valid_inbound_choices = {str(i) for i in range(1, len(inbounds) + 1)}
    choice = input_choice("\n输入编号选择入站，或 q 退出： ", valid_inbound_choices)
    inbound = inbounds[int(choice) - 1]
    inbound_id = int(inbound["id"])

    clients = cur.execute("""
SELECT id, inbound_id, email, up, down, total
FROM client_traffics
WHERE inbound_id = ?
ORDER BY id;
""", (inbound_id,)).fetchall()

    print()
    print(f"已选择入站 ID={inbound_id}。")
    print("请选择修改对象：")
    print("0) 只修改入站自身流量")

    for idx, row in enumerate(clients, start=1):
        used = int(row["up"] or 0) + int(row["down"] or 0)
        total = int(row["total"] or 0)
        print(
            f"{idx}) 客户端={row['email']} | "
            f"已用={human_size(used)} | 上行={human_size(row['up'])} | 下行={human_size(row['down'])} | "
            f"上限={human_size(total)}"
        )
    if clients:
        print("A) 逐个修改该入站下所有客户端")

    valid_client_choices = {"0"} | {str(i) for i in range(1, len(clients) + 1)}
    if clients:
        valid_client_choices |= {"A", "a"}
    client_choice = input_choice("\n输入编号选择客户端，A=逐个客户端，0=只改入站，q=退出： ", valid_client_choices)

    if client_choice == "0":
        edit_mode = "inbound"
        targets = [{
            "kind": "inbound",
            "id": inbound_id,
            "label": f"入站 ID={inbound_id}",
            "up": inbound["up"],
            "down": inbound["down"],
        }]
    elif client_choice.lower() == "a":
        edit_mode = "clients"
        targets = [{
            "kind": "client",
            "id": int(client["id"]),
            "label": f"客户端 {client['email']}",
            "up": client["up"],
            "down": client["down"],
        } for client in clients]
    else:
        edit_mode = "clients"
        client = clients[int(client_choice) - 1]
        targets = [{
            "kind": "client",
            "id": int(client["id"]),
            "label": f"客户端 {client['email']}",
            "up": client["up"],
            "down": client["down"],
        }]

    print()
    print("请选择单位：")
    print("1) GB，十进制，1GB = 1000^3 bytes，适合对齐商家后台")
    print("2) GiB，二进制，1GiB = 1024^3 bytes，适合让 3x-ui 面板显示接近输入值")
    unit_choice = input_choice("请选择 [1/2]，默认 2： ", {"", "1", "2"}, allow_quit=False)
    unit = "gb" if unit_choice == "1" else "gib"
    unit_label = "GB" if unit == "gb" else "GiB"

    print()
    print("请选择输入模式：")
    print("1) 分别输入上传和下载")
    print("2) 只输入总流量，全部写入 down")
    print("3) 只输入总流量，按当前 up/down 比例分配")
    input_mode = input_choice("请选择 [1/2/3]，默认 1： ", {"", "1", "2", "3"}, allow_quit=False) or "1"

    writes = []
    for target in targets:
        while True:
            try:
                print()
                print(f"设置 {target['label']}：")
                if input_mode == "1":
                    up_value = input(f"请输入上传流量数值（{unit_label}），例如 54.25： ").strip()
                    down_value = input(f"请输入下载流量数值（{unit_label}），例如 59.51： ").strip()
                    up_bytes = to_bytes(up_value, unit)
                    down_bytes = to_bytes(down_value, unit)
                    input_summary = f"上传={up_value}{unit_label}，下载={down_value}{unit_label}"
                else:
                    total_value = input(f"请输入总流量数值（{unit_label}），例如 113.76： ").strip()
                    used_bytes = to_bytes(total_value, unit)
                    if input_mode == "2":
                        up_bytes = 0
                        down_bytes = used_bytes
                    else:
                        up_bytes, down_bytes = split_by_ratio(used_bytes, target["up"], target["down"])
                    input_summary = f"总流量={total_value}{unit_label}"
                writes.append({
                    "kind": target["kind"],
                    "id": target["id"],
                    "label": target["label"],
                    "up": up_bytes,
                    "down": down_bytes,
                    "used": up_bytes + down_bytes,
                    "summary": input_summary,
                })
                break
            except Exception as exc:
                print(f"流量数值格式不正确：{exc}")

    print()
    update_all_time = input("是否同时把累计总流量 all_time 改为 上传+下载？[Y/n] ").strip().lower()
    update_all_time = update_all_time not in ("n", "no")

    print()
    print("即将写入：")
    print(f"入站 ID：{inbound_id}")
    print(f"修改累计总流量 all_time：{'是' if update_all_time else '否'}")
    if edit_mode == "inbound":
        print("修改范围：只修改入站自身，不修改任何客户端")
    else:
        print("修改范围：只修改下面列出的客户端，不修改入站自身")
    for item in writes:
        print(
            f"  - {item['label']} | 输入：{item['summary']} | "
            f"上传={human_size(item['up'])} | 下载={human_size(item['down'])} | 合计={human_size(item['used'])}"
        )

    confirm = input("\n确认写入数据库？请输入 YES： ").strip()
    if confirm != "YES":
        print("已取消，没有修改数据库。")
        sys.exit(0)

    inbound_has_all_time = has_column(cur, "inbounds", "all_time")
    client_has_all_time = has_column(cur, "client_traffics", "all_time")
    for item in writes:
        if item["kind"] == "inbound":
            cur.execute(
                "UPDATE inbounds SET up = ?, down = ? WHERE id = ?",
                (item["up"], item["down"], item["id"])
            )
            if update_all_time and inbound_has_all_time:
                cur.execute(
                    "UPDATE inbounds SET all_time = ? WHERE id = ?",
                    (item["used"], item["id"])
                )
        else:
            cur.execute(
                "UPDATE client_traffics SET up = ?, down = ? WHERE id = ?",
                (item["up"], item["down"], item["id"])
            )
            if update_all_time and client_has_all_time:
                cur.execute(
                    "UPDATE client_traffics SET all_time = ? WHERE id = ?",
                    (item["used"], item["id"])
                )

    integrity_check(cur, "修改后")
    conn.commit()
    print()
    print("数据库修改完成。")
except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
PY
    XUI_DB="$XUI_DB" python3 "$tmp_py"
    local py_status=$?
    rm -f "$tmp_py"
    set -e

    systemctl start x-ui

    if [ "$py_status" -ne 0 ]; then
        echo "流量修改未完成或失败，已尝试启动 x-ui。"
        show_service_status_and_logs
        return "$py_status"
    fi

    echo
    echo "修改后数据："
    show_traffic

    show_service_status_and_logs
    health_check || true
}

main_menu() {
    need_root

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${BOLD}🧭 3x-ui 外置增强管理${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "${YELLOW}补充面板没有的功能：自定义重置、流量校准、备份恢复、健康检查。${PLAIN}"
        echo -e "${YELLOW}写数据库或恢复备份前会自动备份；不确定时先选 [9]。${PLAIN}"
        echo -e "${CYAN}------------------------------------------------${PLAIN}"
        echo -e "${BLUE}配置：${RESET_CONFIG}${PLAIN}"
        echo -e "${BLUE}备份：${BACKUP_DIR}${PLAIN}"
        echo -e "${BLUE}日志：${LOG_FILE}${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ 常用操作${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 自定义重置日期        ${YELLOW}(入站/客户端分开设置)${PLAIN}"
        echo -e "  ${GREEN}2.${PLAIN} 立即执行重置检查      ${YELLOW}(更新面板后也可手动跑一次)${PLAIN}"
        echo -e "  ${GREEN}3.${PLAIN} 安装/更新自动检查     ${YELLOW}(systemd timer，每天执行)${PLAIN}"
        echo -e "  ${GREEN}4.${PLAIN} 查看重置日志          ${YELLOW}(脚本日志和 timer 日志)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ 流量维护${PLAIN}"
        echo -e "  ${GREEN}5.${PLAIN} 接管原版 monthly      ${YELLOW}(仅处理已启用外置规则的入站)${PLAIN}"
        echo -e "  ${GREEN}6.${PLAIN} 清零/修改流量上限      ${YELLOW}(up/down 清零或 total 上限)${PLAIN}"
        echo -e "  ${GREEN}7.${PLAIN} 查看当前流量          ${YELLOW}(入站和客户端分开显示)${PLAIN}"
        echo -e "  ${GREEN}8.${PLAIN} 校准当前流量          ${YELLOW}(入站/客户端分开写入)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ 备份恢复${PLAIN}"
        echo -e "  ${GREEN}9.${PLAIN} 立即备份              ${YELLOW}(数据库/配置/程序目录)${PLAIN}"
        echo -e " ${GREEN}10.${PLAIN} 恢复程序备份          ${YELLOW}(恢复 /usr/local/x-ui)${PLAIN}"
        echo -e " ${GREEN}11.${PLAIN} 恢复数据库备份        ${YELLOW}(恢复 x-ui.db)${PLAIN}"

        echo -e " ${BOLD}${BLUE}▶ 诊断维护${PLAIN}"
        echo -e " ${GREEN}12.${PLAIN} 健康检查              ${YELLOW}(服务/数据库/日志/端口)${PLAIN}"
        echo -e " ${GREEN}13.${PLAIN} 清理旧备份            ${YELLOW}(每类只删一个明确文件)${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "${RED}  0. 退出${PLAIN}"
        echo -e "${CYAN}================================================${PLAIN}"
        read -rp "请选择： " choice

        case "$choice" in
            1)
                custom_reset_settings
                pause
                ;;
            2)
                run_custom_reset_check
                pause
                ;;
            3)
                install_reset_timer
                pause
                ;;
            4)
                show_reset_logs
                pause
                ;;
            5)
                disable_monthly_reset
                pause
                ;;
            6)
                manual_reset_or_update_total
                pause
                ;;
            7)
                show_traffic
                pause
                ;;
            8)
                edit_traffic
                pause
                ;;
            9)
                backup_all
                pause
                ;;
            10)
                restore_program_backup
                pause
                ;;
            11)
                restore_database_backup
                pause
                ;;
            12)
                health_check || true
                pause
                ;;
            13)
                cleanup_backups
                pause
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择。${PLAIN}"
                pause
                ;;
        esac
    done
}

case "${1:-}" in
    --run-reset-check)
        run_custom_reset_check
        ;;
    --show-reset-config)
        show_reset_config
        ;;
    "")
        main_menu
        ;;
    *)
        echo "未知参数：$1"
        echo "可用参数：--run-reset-check, --show-reset-config"
        exit 1
        ;;
esac
