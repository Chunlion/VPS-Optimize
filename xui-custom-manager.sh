#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PROFILE="${CONFIG_PROFILE:-/etc/xui-custom-manager.conf}"
CONFIG_FILE="${CONFIG_FILE:-/etc/xui-custom-reset.json}"
BACKUP_DIR="${BACKUP_DIR:-/root/x-ui-backups}"
XUI_DB="${XUI_DB:-/etc/x-ui/x-ui.db}"
XUI_ETC_DIR="${XUI_ETC_DIR:-/etc/x-ui}"
XUI_PROGRAM_DIR="${XUI_PROGRAM_DIR:-/usr/local/x-ui}"
LOG_FILE="${LOG_FILE:-/var/log/xui-custom-manager.log}"
RESET_STATE="${RESET_STATE:-/var/lib/xui-custom-manager/reset-state.json}"
RESET_SERVICE="${RESET_SERVICE:-/etc/systemd/system/xui-custom-reset.service}"
RESET_TIMER="${RESET_TIMER:-/etc/systemd/system/xui-custom-reset.timer}"
LOCAL_RUNNER="/usr/local/bin/xui-custom-manager.sh"
XCM_PATH="/usr/local/bin/xcm"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PLAIN='\033[0m'

RUN_CHECK=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --reset-check)
            RUN_CHECK=1
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            echo "用法：$0 [--reset-check] [--dry-run]"
            exit 0
            ;;
        *)
            echo "未知参数：$1"
            exit 1
            ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 root 用户运行。"
    exit 1
fi

if [ -f "$CONFIG_PROFILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_PROFILE"
fi

LOCAL_RUNNER="/usr/local/bin/xui-custom-manager.sh"
XCM_PATH="/usr/local/bin/xcm"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

if { [ "$RUN_CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; } && [ ! -t 1 ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "===== $(date '+%F %T') reset-check 执行 ====="
fi

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033c'
    fi
}

pause() {
    echo
    read -rp "按回车返回菜单..."
}

confirm_yes() {
    local message="$1"
    local answer
    echo
    echo -e "${YELLOW}${message}${PLAIN}"
    read -rp "请输入 YES 确认继续： " answer
    [ "$answer" = "YES" ]
}

need_tty() {
    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        echo "错误：该功能需要交互式终端。"
        return 1
    fi
}

ensure_dirs() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$RESET_STATE")"
    chmod 700 "$BACKUP_DIR"
    chmod 700 "$(dirname "$RESET_STATE")"
}

install_runtime_deps() {
    local missing=()

    command -v sqlite3 >/dev/null 2>&1 || missing+=("sqlite3")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi

    if ! command -v apt >/dev/null 2>&1; then
        echo "错误：缺少依赖：${missing[*]}，且未找到 apt，请手动安装后重试。"
        return 1
    fi

    apt update
    apt install -y sqlite3 python3
}

timer_active_status() {
    if systemctl is-active --quiet xui-custom-reset.timer 2>/dev/null; then
        echo "已启用"
    else
        echo "未启用"
    fi
}

timer_enabled_status() {
    if systemctl is-enabled --quiet xui-custom-reset.timer 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

runner_status() {
    if [ -x "$LOCAL_RUNNER" ]; then
        echo "已安装"
    else
        echo "未安装"
    fi
}

register_xcm_shortcut() {
    local need_write=0

    mkdir -p "$(dirname "$XCM_PATH")"

    if [ ! -f "$XCM_PATH" ]; then
        need_write=1
    elif ! grep -q "CACHE_FILE=.*xui-custom-manager.sh" "$XCM_PATH" 2>/dev/null; then
        need_write=1
    elif ! grep -q "wget" "$XCM_PATH" 2>/dev/null; then
        need_write=1
    fi

    if [ "$need_write" -eq 1 ]; then
        cat > "$XCM_PATH" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh"
CACHE_DIR="/usr/local/lib/xui-custom-manager"
CACHE_FILE="$CACHE_DIR/xui-custom-manager.sh"
TMP_FILE="$(mktemp)"

mkdir -p "$CACHE_DIR"

if command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 10 --retry 2 "$URL" -o "$TMP_FILE"; then
    install -m 755 "$TMP_FILE" "$CACHE_FILE"
    rm -f "$TMP_FILE"
    exec bash "$CACHE_FILE" "$@"
fi

if command -v wget >/dev/null 2>&1 && wget -qO "$TMP_FILE" --timeout=10 --tries=2 "$URL"; then
    install -m 755 "$TMP_FILE" "$CACHE_FILE"
    rm -f "$TMP_FILE"
    exec bash "$CACHE_FILE" "$@"
fi

rm -f "$TMP_FILE"

if [ -f "$CACHE_FILE" ]; then
    echo "警告：拉取最新版失败，使用本地缓存版本。"
    exec bash "$CACHE_FILE" "$@"
fi

echo "错误：无法拉取最新版，也没有本地缓存。"
exit 1
EOF
    fi

    chmod 755 "$XCM_PATH"
}

install_local_runner() {
    local self_path
    self_path="$(readlink -f "${BASH_SOURCE[0]}")"

    mkdir -p "$(dirname "$LOCAL_RUNNER")"

    if [ "$self_path" = "$LOCAL_RUNNER" ] && [ -x "$LOCAL_RUNNER" ]; then
        return 0
    fi

    install -m 755 "$self_path" "$LOCAL_RUNNER"
}

ensure_reset_timer_installed() {
    install_local_runner

    cat > "$RESET_SERVICE" <<EOF
[Unit]
Description=x-ui custom reset check
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $LOCAL_RUNNER --reset-check
EOF

    cat > "$RESET_TIMER" <<'EOF'
[Unit]
Description=Run x-ui custom reset check daily

[Timer]
OnCalendar=*-*-* 00:10:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now xui-custom-reset.timer
}

disable_reset_timer() {
    systemctl disable --now xui-custom-reset.timer >/dev/null 2>&1 || true
}

backup_database() {
    ensure_dirs

    if [ ! -f "$XUI_DB" ]; then
        echo "错误：数据库不存在：$XUI_DB"
        return 1
    fi

    local ts backup_file
    ts="$(date +%F_%H%M%S)"
    backup_file="$BACKUP_DIR/x-ui.db.$ts.bak"

    if sqlite3 "$XUI_DB" ".backup '$backup_file'"; then
        chmod 600 "$backup_file"
        echo "$backup_file"
        return 0
    fi

    echo "错误：数据库备份失败，已取消写库。"
    return 1
}

backup_all() {
    ensure_dirs
    install_runtime_deps

    echo "正在备份..."

    if [ -f "$XUI_DB" ]; then
        local db_backup
        db_backup="$(backup_database)" || return 1
        echo "数据库备份：$db_backup"
    else
        echo "数据库不存在，跳过：$XUI_DB"
    fi

    local ts
    ts="$(date +%F_%H%M%S)"

    if [ -d "$XUI_ETC_DIR" ]; then
        tar -czf "$BACKUP_DIR/x-ui-etc.$ts.tar.gz" -C "$(dirname "$XUI_ETC_DIR")" "$(basename "$XUI_ETC_DIR")"
        chmod 600 "$BACKUP_DIR/x-ui-etc.$ts.tar.gz"
        echo "配置目录备份：$BACKUP_DIR/x-ui-etc.$ts.tar.gz"
    else
        echo "配置目录不存在，跳过：$XUI_ETC_DIR"
    fi

    if [ -d "$XUI_PROGRAM_DIR" ]; then
        tar -czf "$BACKUP_DIR/x-ui-program.$ts.tar.gz" -C "$(dirname "$XUI_PROGRAM_DIR")" "$(basename "$XUI_PROGRAM_DIR")"
        chmod 600 "$BACKUP_DIR/x-ui-program.$ts.tar.gz"
        echo "程序目录备份：$BACKUP_DIR/x-ui-program.$ts.tar.gz"
    else
        echo "程序目录不存在，跳过：$XUI_PROGRAM_DIR"
    fi
}

restore_backup() {
    local kind="$1"
    local pattern label target_dir

    ensure_dirs
    install_runtime_deps

    case "$kind" in
        db)
            pattern="x-ui.db.*.bak"
            label="数据库"
            ;;
        program)
            pattern="x-ui-program.*.tar.gz"
            label="程序目录"
            target_dir="$(dirname "$XUI_PROGRAM_DIR")"
            ;;
        etc)
            pattern="x-ui-etc.*.tar.gz"
            label="配置目录"
            target_dir="$(dirname "$XUI_ETC_DIR")"
            ;;
        *)
            echo "未知恢复类型：$kind"
            return 1
            ;;
    esac

    while true; do
        clear_screen
        echo "================================================"
        echo "恢复$label"
        echo "================================================"

        local files=()
        mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$pattern" | sort -r)

        if [ "${#files[@]}" -eq 0 ]; then
            echo "未找到 $label 备份。"
            echo "------------------------------------------------"
            echo " 0. 返回上级"
            echo "================================================"
            read -rp "请选择： " _
            return 0
        fi

        local i
        for i in "${!files[@]}"; do
            echo " $((i + 1)). ${files[$i]}"
        done
        echo "------------------------------------------------"
        echo " 0. 返回上级"
        echo "================================================"

        local choice
        read -rp "请选择备份文件： " choice
        if [ "$choice" = "0" ]; then
            return 0
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#files[@]}" ]; then
            echo "无效选择。"
            sleep 1
            continue
        fi

        local selected="${files[$((choice - 1))]}"
        confirm_yes "恢复会覆盖当前 $label。恢复前会先备份当前状态。" || {
            echo "已取消。"
            return 0
        }

        echo "恢复前备份当前状态..."
        backup_all || return 1

        echo "停止 x-ui..."
        systemctl stop x-ui || true

        if [ "$kind" = "db" ]; then
            cp -a "$selected" "$XUI_DB"
            chmod 600 "$XUI_DB"
        else
            tar -xzf "$selected" -C "$target_dir"
        fi

        echo "启动 x-ui..."
        systemctl start x-ui || true
        echo
        print_health_report
        return 0
    done
}

cleanup_backups() {
    clear_screen
    echo "================================================"
    echo "清理旧备份"
    echo "================================================"
    ensure_dirs

    local patterns=("x-ui.db.*.bak" "x-ui-etc.*.tar.gz" "x-ui-program.*.tar.gz")
    local labels=("数据库" "配置目录" "程序目录")
    local i

    for i in "${!patterns[@]}"; do
        local files=()
        mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${patterns[$i]}" | sort -r)

        if [ "${#files[@]}" -le 10 ]; then
            echo "${labels[$i]}：当前 ${#files[@]} 个，不需要清理。"
            continue
        fi

        echo
        echo "${labels[$i]}：保留最新 10 个，可选择删除一个旧备份。"
        local idx
        for idx in "${!files[@]}"; do
            if [ "$idx" -ge 10 ]; then
                echo " $((idx + 1)). ${files[$idx]}"
            fi
        done
        echo " 0. 跳过"

        local choice
        read -rp "请选择要删除的备份： " choice
        if [ "$choice" = "0" ]; then
            continue
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 11 ] && [ "$choice" -le "${#files[@]}" ]; then
            local selected="${files[$((choice - 1))]}"
            confirm_yes "确认删除文件：$selected" && rm -f -- "$selected" && echo "已删除：$selected"
        else
            echo "无效选择，已跳过。"
        fi
    done

    echo
    echo "清理完成。"
}

run_custom_reset_ui() {
    install_runtime_deps
    need_tty || return 1

    local tmp_py
    tmp_py="$(mktemp --suffix=.py)"

    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

db_path = os.environ.get("XUI_DB", "/etc/x-ui/x-ui.db")
config_path = Path(os.environ.get("CONFIG_FILE", "/etc/xui-custom-reset.json"))

def clear_screen():
    print("\033c", end="")

def pause():
    input("\n按回车返回菜单...")

def valid_day(value):
    try:
        day = int(value)
    except Exception:
        return None
    return day if 1 <= day <= 31 else None

def default_config():
    return {"enabled": False, "default_day": 1, "inbounds": {}}

def normalize_config(data):
    if not isinstance(data, dict):
        raise ValueError("配置根节点不是对象")
    data.setdefault("enabled", False)
    data["enabled"] = bool(data.get("enabled"))
    day = valid_day(data.get("default_day", 1))
    data["default_day"] = day or 1
    if not isinstance(data.get("inbounds"), dict):
        data["inbounds"] = {}
    for iid, cfg in list(data["inbounds"].items()):
        if not isinstance(cfg, dict):
            data["inbounds"].pop(iid, None)
            continue
        cfg["enabled"] = bool(cfg.get("enabled", False))
        cfg["day"] = valid_day(cfg.get("day", data["default_day"])) or data["default_day"]
        cfg["reset_inbound"] = bool(cfg.get("reset_inbound", True))
        cfg["reset_clients_without_custom_day"] = bool(cfg.get("reset_clients_without_custom_day", False))
        if not isinstance(cfg.get("clients"), dict):
            cfg["clients"] = {}
        for email, ccfg in list(cfg["clients"].items()):
            if not isinstance(ccfg, dict):
                cfg["clients"].pop(email, None)
                continue
            cday = valid_day(ccfg.get("day", 0))
            if not cday:
                cfg["clients"].pop(email, None)
                continue
            ccfg["enabled"] = bool(ccfg.get("enabled", True))
            ccfg["day"] = cday
    return data

def load_config():
    if not config_path.exists():
        return default_config()
    try:
        with config_path.open("r", encoding="utf-8") as f:
            return normalize_config(json.load(f))
    except Exception as exc:
        print(f"错误：读取配置失败：{config_path}")
        print(f"原因：{exc}")
        print("请先手动检查配置文件，或从备份恢复。")
        sys.exit(1)

def save_config(data):
    data = normalize_config(data)
    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = config_path.with_name(config_path.name + f".tmp.{os.getpid()}")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp_path, config_path)
    os.chmod(config_path, 0o600)

def input_choice(prompt, valid_choices):
    while True:
        try:
            choice = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        if choice in valid_choices:
            return choice
        print("无效选择，请重新输入。")

def ask_day(prompt, allow_zero=False):
    while True:
        try:
            raw = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        try:
            day = int(raw)
        except Exception:
            print("请输入数字。")
            continue
        if allow_zero and day == 0:
            return 0
        if 1 <= day <= 31:
            return day
        print("日期范围只能是 1-31。")

def trunc(text, limit=20):
    text = text or "无备注"
    return text if len(text) <= limit else text[:limit] + "..."

def timer_status():
    return subprocess.run(["systemctl", "is-active", "--quiet", "xui-custom-reset.timer"]).returncode == 0

def load_db():
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        try:
            inbounds = conn.execute("SELECT id, remark, port, traffic_reset FROM inbounds ORDER BY id").fetchall()
        except sqlite3.OperationalError:
            inbounds = conn.execute("SELECT id, remark, port, 'unknown' AS traffic_reset FROM inbounds ORDER BY id").fetchall()
        try:
            clients = conn.execute("SELECT id, inbound_id, email FROM client_traffics ORDER BY id").fetchall()
        except sqlite3.OperationalError:
            clients = []
        conn.close()
        return inbounds, clients
    except Exception as exc:
        print(f"数据库读取失败：{exc}")
        sys.exit(1)

config = load_config()
inbounds, clients = load_db()
clients_by_inbound = {}
for client in clients:
    clients_by_inbound.setdefault(str(client["inbound_id"]), []).append(client)

def show_config():
    clear_screen()
    print("================================================")
    print("当前自定义重置配置")
    print("================================================")
    print(json.dumps(config, ensure_ascii=False, indent=2))
    pause()

def manage_clients(inbound_id, inbound_cfg):
    clients_for_inbound = clients_by_inbound.get(str(inbound_id), [])
    while True:
        clear_screen()
        print("================================================")
        print("客户端单独日期")
        print("================================================")
        print(f"入站 ID：{inbound_id}")
        print("说明：不单独设置时，客户端按入站规则处理。")
        print("------------------------------------------------")

        if not clients_for_inbound:
            print("当前入站没有客户端。")
        for idx, client in enumerate(clients_for_inbound, start=1):
            email = client["email"] or "无邮箱"
            ccfg = inbound_cfg.get("clients", {}).get(email, {})
            if ccfg.get("enabled") and ccfg.get("day"):
                status = f"每月 {ccfg['day']} 号"
            else:
                status = "不单独设置"
            print(f" {idx}. {email}")
            print(f"    {status}")

        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")

        valid = {"0"} | {str(i) for i in range(1, len(clients_for_inbound) + 1)}
        choice = input_choice("请选择客户端： ", valid)
        if choice == "0":
            return

        email = clients_for_inbound[int(choice) - 1]["email"] or ""
        day = ask_day("输入 1-31 设置该客户端日期，输入 0 删除单独日期：", allow_zero=True)
        inbound_cfg.setdefault("clients", {})
        if day == 0:
            inbound_cfg["clients"].pop(email, None)
            print("已删除该客户端单独日期。")
        else:
            inbound_cfg["clients"][email] = {"enabled": True, "day": day}
            print(f"已设置为每月 {day} 号。")
        save_config(config)

def manage_inbound(inbound):
    iid = str(inbound["id"])
    config.setdefault("inbounds", {})
    cfg = config["inbounds"].setdefault(iid, {})
    cfg.setdefault("enabled", False)
    cfg.setdefault("day", config.get("default_day", 1))
    cfg.setdefault("reset_inbound", True)
    cfg.setdefault("reset_clients_without_custom_day", False)
    cfg.setdefault("clients", {})
    save_config(config)

    while True:
        clear_screen()
        print("================================================")
        print("入站设置")
        print("================================================")
        print(f"ID：{iid}")
        print(f"端口：{inbound['port']}")
        print(f"备注：{inbound['remark'] or '无备注'}")
        print()
        print(f"外置重置：{'开启' if cfg.get('enabled') else '关闭'}")
        print(f"入站日期：每月 {cfg.get('day', config.get('default_day', 1))} 号")
        print(f"入站自身 up/down：{'重置' if cfg.get('reset_inbound', True) else '不重置'}")
        print(f"未单独设置日期的客户端：{'跟随入站' if cfg.get('reset_clients_without_custom_day', False) else '忽略'}")
        if inbound["traffic_reset"] == "monthly":
            print()
            print("提醒：面板原生 monthly 仍启用，请在 3x-ui 面板中改为 never/不重置。")
        print("------------------------------------------------")
        print(" 1. 开启/关闭该入站外置重置")
        print(" 2. 设置该入站日期")
        print(" 3. 开启/关闭重置入站自身 up/down")
        print(" 4. 开启/关闭客户端跟随入站")
        print(" 5. 管理客户端单独日期")
        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")

        choice = input_choice("请选择： ", {"0", "1", "2", "3", "4", "5"})
        if choice == "0":
            return
        if choice == "1":
            cfg["enabled"] = not cfg.get("enabled", False)
        elif choice == "2":
            cfg["day"] = ask_day("请输入该入站每月重置日期 (1-31)：")
        elif choice == "3":
            cfg["reset_inbound"] = not cfg.get("reset_inbound", True)
        elif choice == "4":
            cfg["reset_clients_without_custom_day"] = not cfg.get("reset_clients_without_custom_day", False)
        elif choice == "5":
            manage_clients(iid, cfg)
        save_config(config)

def choose_inbound():
    while True:
        clear_screen()
        print("================================================")
        print("选择入站")
        print("================================================")

        if not inbounds:
            print("未读取到入站。")
        for idx, inbound in enumerate(inbounds, start=1):
            iid = str(inbound["id"])
            cfg = config.get("inbounds", {}).get(iid, {})
            enabled = "开启" if cfg.get("enabled") else "关闭"
            day = cfg.get("day", config.get("default_day", 1))
            print(f" {idx}. ID={iid}  端口={inbound['port']}  备注={trunc(inbound['remark'])}")
            print(f"    外置重置：{enabled}  日期：每月 {day} 号")
            if inbound["traffic_reset"] == "monthly":
                print("    面板原生：monthly  警告：请在面板中改为 never/不重置")
            else:
                print(f"    面板原生：{inbound['traffic_reset'] or 'unknown'}")
            print()

        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")

        valid = {"0"} | {str(i) for i in range(1, len(inbounds) + 1)}
        choice = input_choice("请选择入站： ", valid)
        if choice == "0":
            return
        manage_inbound(inbounds[int(choice) - 1])

while True:
    clear_screen()
    print("================================================")
    print("自定义重置日期")
    print("================================================")
    print(f"全局状态：{'启用' if config.get('enabled') else '禁用'}")
    print(f"默认日期：每月 {config.get('default_day', 1)} 号")
    print(f"自动检查：{'已启用' if timer_status() else '未启用'}")
    print()
    print("提示：请在 3x-ui 面板里关闭对应入站的原生 monthly 重置。")
    print("------------------------------------------------")
    print(" 1. 开启/关闭自定义重置")
    print(f" 2. 设置默认日期 当前：每月 {config.get('default_day', 1)} 号")
    print(" 3. 管理入站/客户端 单独设置某个入站或客户端")
    print(" 4. 立即检查一次 先预览，确认后执行")
    print(" 5. 查看当前配置")
    print("------------------------------------------------")
    print(" 0. 返回主菜单")
    print("================================================")

    choice = input_choice("请选择： ", {"0", "1", "2", "3", "4", "5"})
    if choice == "0":
        sys.exit(0)
    if choice == "1":
        config["enabled"] = not config.get("enabled", False)
        save_config(config)
        sys.exit(200 if config["enabled"] else 201)
    if choice == "2":
        config["default_day"] = ask_day("请输入默认日期 (1-31)：")
        save_config(config)
    elif choice == "3":
        choose_inbound()
    elif choice == "4":
        sys.exit(202)
    elif choice == "5":
        show_config()
PY

    set +e
    XUI_DB="$XUI_DB" CONFIG_FILE="$CONFIG_FILE" python3 "$tmp_py" </dev/tty
    local ret=$?
    rm -f "$tmp_py"
    set -e

    case "$ret" in
        0|100)
            return 0
            ;;
        200)
            if ensure_reset_timer_installed; then
                echo "自定义重置已启用，自动检查已安装并启动。"
                echo "timer 状态：$(timer_active_status)"
            else
                echo "错误：自定义重置已启用，但自动检查安装或启动失败。"
                echo "你仍然可以使用“立即检查一次”手动执行。"
            fi
            pause
            ;;
        201)
            disable_reset_timer
            echo "自定义重置已禁用，自动检查 timer 已停用。"
            echo "配置文件未删除：$CONFIG_FILE"
            pause
            ;;
        202)
            run_reset_check_interactive
            ;;
        *)
            echo "自定义重置菜单异常退出，状态码：$ret"
            pause
            ;;
    esac
}

run_traffic_ui() {
    install_runtime_deps
    need_tty || return 1

    local writes_file tmp_py
    writes_file="$(mktemp)"
    tmp_py="$(mktemp --suffix=.py)"

    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

db_path = os.environ.get("XUI_DB", "/etc/x-ui/x-ui.db")
writes_file = os.environ["WRITES_FILE"]
GIB = Decimal(1024) ** 3

def clear_screen():
    print("\033c", end="")

def format_gib(value):
    try:
        amount = Decimal(int(value or 0)) / GIB
    except Exception:
        amount = Decimal(0)
    return f"{amount.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)} GiB"

def parse_gib(raw):
    try:
        value = Decimal(raw.strip())
    except (InvalidOperation, AttributeError):
        raise ValueError("请输入有效数字")
    if value < 0:
        raise ValueError("流量不能为负数")
    return int((value * GIB).to_integral_value(rounding=ROUND_HALF_UP))

def input_choice(prompt, valid_choices):
    while True:
        try:
            choice = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        if choice in valid_choices:
            return choice
        print("无效选择，请重新输入。")

def ask_gib(prompt):
    while True:
        try:
            return parse_gib(input(prompt))
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        except ValueError as exc:
            print(f"输入无效：{exc}")

def trunc(text, limit=20):
    text = text or "无备注"
    return text if len(text) <= limit else text[:limit] + "..."

def load_rows():
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    inbounds = conn.execute("SELECT id, remark, port, up, down, total FROM inbounds ORDER BY id").fetchall()
    return conn, inbounds

try:
    conn, inbounds = load_rows()
except Exception as exc:
    print(f"数据库读取失败：{exc}")
    sys.exit(1)

def build_write(target, up, down):
    before_up = int(target["up"] or 0)
    before_down = int(target["down"] or 0)
    return {
        "table": target["table"],
        "id": target["id"],
        "label": target["label"],
        "before_up": before_up,
        "before_down": before_down,
        "after_up": int(up),
        "after_down": int(down),
    }

def calibrate_target(target):
    clear_screen()
    print("================================================")
    print("输入校准流量")
    print("================================================")
    print(f"对象：{target['label']}")
    print(f"当前已用：{format_gib((target['up'] or 0) + (target['down'] or 0))}")
    print()
    print("请选择写入方式：")
    print(" 1. 输入总已用流量，全部写入 down")
    print(" 2. 输入总已用流量，按当前 up/down 比例分配")
    print(" 3. 分别输入 up 和 down")
    print("------------------------------------------------")
    print(" 0. 返回上级")
    print("================================================")
    mode = input_choice("请选择： ", {"0", "1", "2", "3"})
    if mode == "0":
        return None

    cur_up = int(target["up"] or 0)
    cur_down = int(target["down"] or 0)
    cur_total = cur_up + cur_down

    if mode in ("1", "2"):
        total = ask_gib("请输入总已用流量 (GiB)：")
        if mode == "1" or cur_total <= 0:
            new_up, new_down = 0, total
        else:
            new_up = int(Decimal(total) * Decimal(cur_up) / Decimal(cur_total))
            new_down = total - new_up
    else:
        new_up = ask_gib("请输入上传 up 流量 (GiB)：")
        new_down = ask_gib("请输入下载 down 流量 (GiB)：")

    return build_write(target, new_up, new_down)

while True:
    clear_screen()
    print("================================================")
    print("流量校准")
    print("================================================")
    print("说明：这里只校准已用流量 up/down，不修改流量上限 total。")
    print("单位：GiB，1 GiB = 1024^3 bytes")
    print("------------------------------------------------")

    if not inbounds:
        print("当前没有入站。")
    for idx, inbound in enumerate(inbounds, start=1):
        used = int(inbound["up"] or 0) + int(inbound["down"] or 0)
        total = int(inbound["total"] or 0)
        total_text = format_gib(total) if total > 0 else "不限量"
        print(f" {idx}. ID={inbound['id']}  端口={inbound['port']}  备注={trunc(inbound['remark'])}")
        print(f"    已用：{format_gib(used)} / 上限：{total_text}")
        print()

    print("------------------------------------------------")
    print(" 0. 返回主菜单")
    print("================================================")

    valid_inbounds = {"0"} | {str(i) for i in range(1, len(inbounds) + 1)}
    choice = input_choice("请选择入站： ", valid_inbounds)
    if choice == "0":
        sys.exit(100)

    inbound = inbounds[int(choice) - 1]
    inbound_id = inbound["id"]

    try:
        clients = conn.execute(
            "SELECT id, email, up, down, total FROM client_traffics WHERE inbound_id=? ORDER BY id",
            (inbound_id,),
        ).fetchall()
    except sqlite3.OperationalError:
        clients = []

    while True:
        clear_screen()
        print("================================================")
        print("选择校准对象")
        print("================================================")
        print(f"入站 ID：{inbound_id}")
        print(f"端口：{inbound['port']}")
        print(f"备注：{inbound['remark'] or '无备注'}")
        print("------------------------------------------------")

        inbound_used = int(inbound["up"] or 0) + int(inbound["down"] or 0)
        print(" 1. 入站自身")
        print(f"    已用：{format_gib(inbound_used)}")
        print()

        for idx, client in enumerate(clients, start=2):
            used = int(client["up"] or 0) + int(client["down"] or 0)
            total = int(client["total"] or 0)
            total_text = format_gib(total) if total > 0 else "不限量"
            print(f" {idx}. {client['email'] or '无邮箱'}")
            print(f"    已用：{format_gib(used)} / 上限：{total_text}")
            print()

        all_clients_choice = str(len(clients) + 2)
        if clients:
            print(f" {all_clients_choice}. 逐个校准全部客户端")
        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")

        valid_objects = {"0", "1"} | {str(i) for i in range(2, len(clients) + 2)}
        if clients:
            valid_objects.add(all_clients_choice)

        obj_choice = input_choice("请选择对象： ", valid_objects)
        if obj_choice == "0":
            break

        targets = []
        if obj_choice == "1":
            targets.append({
                "table": "inbounds",
                "id": inbound_id,
                "label": f"入站 ID={inbound_id}",
                "up": inbound["up"],
                "down": inbound["down"],
            })
        elif clients and obj_choice == all_clients_choice:
            for client in clients:
                targets.append({
                    "table": "client_traffics",
                    "id": client["id"],
                    "label": client["email"] or f"客户端 ID={client['id']}",
                    "up": client["up"],
                    "down": client["down"],
                })
        else:
            client = clients[int(obj_choice) - 2]
            targets.append({
                "table": "client_traffics",
                "id": client["id"],
                "label": client["email"] or f"客户端 ID={client['id']}",
                "up": client["up"],
                "down": client["down"],
            })

        writes = []
        for target in targets:
            write = calibrate_target(target)
            if write is None:
                writes = []
                break
            writes.append(write)

        if not writes:
            continue

        clear_screen()
        print("================================================")
        print("确认写入")
        print("================================================")
        print("以下操作只会修改 up/down，不会修改 total。")
        print("写库前会自动备份数据库，并重启 x-ui。")
        print("------------------------------------------------")
        for write in writes:
            before_total = write["before_up"] + write["before_down"]
            after_total = write["after_up"] + write["after_down"]
            print(f"对象：{write['label']}")
            print(f"  修改前：up {format_gib(write['before_up'])} / down {format_gib(write['before_down'])} / 合计 {format_gib(before_total)}")
            print(f"  修改后：up {format_gib(write['after_up'])} / down {format_gib(write['after_down'])} / 合计 {format_gib(after_total)}")
            print()
        try:
            answer = input("请输入 YES 确认写入：").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(100)
        if answer != "YES":
            print("已取消，没有写入数据库。")
            sys.exit(100)

        with open(writes_file, "w", encoding="utf-8") as f:
            json.dump(writes, f, ensure_ascii=False)
        sys.exit(200)
PY

    set +e
    XUI_DB="$XUI_DB" WRITES_FILE="$writes_file" python3 "$tmp_py" </dev/tty
    local ret=$?
    rm -f "$tmp_py"
    set -e

    if [ "$ret" -eq 100 ]; then
        rm -f "$writes_file"
        return 0
    fi
    if [ "$ret" -ne 200 ]; then
        rm -f "$writes_file"
        echo "流量校准已取消或失败。"
        pause
        return 0
    fi

    echo "正在备份数据库..."
    local db_backup
    db_backup="$(backup_database)" || {
        rm -f "$writes_file"
        pause
        return 1
    }
    echo "数据库备份：$db_backup"

    echo "停止 x-ui..."
    systemctl stop x-ui || true

    set +e
    XUI_DB="$XUI_DB" WRITES_FILE="$writes_file" python3 <<'PY'
import json
import os
import sqlite3
import sys

db_path = os.environ["XUI_DB"]
writes_file = os.environ["WRITES_FILE"]

try:
    with open(writes_file, "r", encoding="utf-8") as f:
        writes = json.load(f)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("BEGIN")
    for write in writes:
        table = write["table"]
        if table not in {"inbounds", "client_traffics"}:
            raise ValueError(f"非法表名：{table}")
        cur.execute(f"UPDATE {table} SET up=?, down=? WHERE id=?", (write["after_up"], write["after_down"], write["id"]))
        if cur.rowcount <= 0:
            raise RuntimeError(f"未找到对象：{write['label']}")
    conn.commit()
    print("写入成功。")
except Exception as exc:
    try:
        conn.rollback()
    except Exception:
        pass
    print(f"写入失败：{exc}")
    sys.exit(1)
finally:
    try:
        conn.close()
    except Exception:
        pass
PY
    local write_ret=$?
    set -e

    rm -f "$writes_file"
    echo "启动 x-ui..."
    systemctl start x-ui || true

    if [ "$write_ret" -eq 0 ]; then
        echo "流量校准完成。"
    else
        echo "流量校准失败，数据库已保留写入前备份：$db_backup"
    fi
    pause
}

run_reset_engine() {
    install_runtime_deps
    ensure_dirs

    XUI_DB="$XUI_DB" \
    CONFIG_FILE="$CONFIG_FILE" \
    RESET_STATE="$RESET_STATE" \
    BACKUP_DIR="$BACKUP_DIR" \
    DRY_RUN="$DRY_RUN" \
    PLAN_COUNT_FILE="${PLAN_COUNT_FILE:-}" \
    python3 <<'PY'
import calendar
import json
import os
import sqlite3
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

db_path = Path(os.environ["XUI_DB"])
config_path = Path(os.environ["CONFIG_FILE"])
state_path = Path(os.environ["RESET_STATE"])
backup_dir = Path(os.environ["BACKUP_DIR"])
dry_run = os.environ.get("DRY_RUN") == "1"
plan_count_file = os.environ.get("PLAN_COUNT_FILE")

today = date.today()
current_month = today.strftime("%Y-%m")

def write_plan_count(count):
    if not plan_count_file:
        return
    try:
        Path(plan_count_file).write_text(str(count), encoding="utf-8")
    except Exception:
        pass

def non_negative_int(value, default=0):
    try:
        parsed = int(value or default)
    except Exception:
        parsed = default
    return max(parsed, 0)

def load_config():
    if not config_path.exists():
        return {"enabled": False, "default_day": 1, "inbounds": {}}
    try:
        with config_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        print(f"错误：读取配置失败：{config_path}")
        print(f"原因：{exc}")
        return None
    if not isinstance(data, dict):
        print(f"错误：配置格式无效：{config_path}")
        return None
    data.setdefault("enabled", False)
    data.setdefault("default_day", 1)
    data.setdefault("inbounds", {})
    if not isinstance(data["inbounds"], dict):
        data["inbounds"] = {}
    return data

def load_state():
    if not state_path.exists():
        return {"schema_version": 2, "inbounds": {}, "clients": {}}
    try:
        with state_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        print(f"错误：读取状态文件失败：{state_path}")
        print(f"原因：{exc}")
        print("为避免重复重置，脚本不会覆盖损坏的状态文件。请手动检查或恢复备份。")
        return None
    if not isinstance(data, dict):
        print(f"错误：状态文件格式无效：{state_path}")
        return None
    if "schema_version" not in data:
        data = {
            "schema_version": 2,
            "inbounds": data.get("inbounds", {}) if isinstance(data.get("inbounds"), dict) else {},
            "clients": data.get("clients", {}) if isinstance(data.get("clients"), dict) else {},
        }
    data["schema_version"] = max(non_negative_int(data.get("schema_version", 1), 1), 2)
    data.setdefault("inbounds", {})
    data.setdefault("clients", {})
    if not isinstance(data["inbounds"], dict):
        data["inbounds"] = {}
    if not isinstance(data["clients"], dict):
        data["clients"] = {}
    for records in (data["inbounds"], data["clients"]):
        for key, record in list(records.items()):
            if not isinstance(record, dict):
                records[key] = {"traffic_totals": {"up": 0, "down": 0, "total": 0}}
                continue
            totals = record.get("traffic_totals")
            if not isinstance(totals, dict):
                totals = {}
            totals["up"] = non_negative_int(totals.get("up", 0))
            totals["down"] = non_negative_int(totals.get("down", 0))
            totals["total"] = totals["up"] + totals["down"]
            record["traffic_totals"] = totals
    return data

def save_state(data):
    state_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = state_path.with_name(state_path.name + f".tmp.{os.getpid()}")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp_path, state_path)
    os.chmod(state_path, 0o600)

def safe_day(value, fallback=1):
    try:
        day = int(value)
    except Exception:
        day = fallback
    if day < 1:
        day = fallback
    if day > 31:
        day = 31
    return day

def effective_day(configured_day):
    last_day = calendar.monthrange(today.year, today.month)[1]
    return min(safe_day(configured_day), last_day)

def should_reset(configured_day, state_record):
    day = safe_day(configured_day)
    eff = effective_day(day)
    if today.day < eff:
        return False, f"未到本月重置日：每月 {day} 号，本月有效日 {eff} 号"
    if state_record.get("last_reset_month") == current_month:
        reset_date = state_record.get("last_reset_date", "未知日期")
        return False, f"本月已在 {reset_date} 重置过"
    return True, f"每月 {day} 号，本月有效日 {eff} 号，本月尚未重置"

def truncate(text, limit=20):
    text = text or "无备注"
    return text if len(text) <= limit else text[:limit] + "..."

def connect_db():
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn

def load_db_rows(conn):
    try:
        inbounds = conn.execute("SELECT id, remark, port, traffic_reset FROM inbounds ORDER BY id").fetchall()
    except sqlite3.OperationalError:
        inbounds = conn.execute("SELECT id, remark, port, 'unknown' AS traffic_reset FROM inbounds ORDER BY id").fetchall()
    try:
        clients = conn.execute("SELECT id, inbound_id, email FROM client_traffics ORDER BY id").fetchall()
    except sqlite3.OperationalError:
        clients = []
    return inbounds, clients

def build_plan(config, state, inbounds, clients):
    inbound_map = {str(row["id"]): row for row in inbounds}
    clients_by_inbound = {}
    client_lookup = set()
    for client in clients:
        iid = str(client["inbound_id"])
        email = client["email"] or ""
        clients_by_inbound.setdefault(iid, []).append(client)
        client_lookup.add((iid, email))

    plan_inbounds = []
    plan_clients = []
    skipped = []
    warnings = []
    default_day = safe_day(config.get("default_day", 1))

    for iid, cfg in sorted(config.get("inbounds", {}).items(), key=lambda item: int(item[0]) if str(item[0]).isdigit() else str(item[0])):
        if not isinstance(cfg, dict) or not cfg.get("enabled", False):
            continue

        inbound = inbound_map.get(str(iid))
        if inbound is None:
            skipped.append((f"入站 ID={iid}", "入站已不存在，跳过"))
            continue

        if inbound["traffic_reset"] == "monthly":
            warnings.append(f"入站 ID={iid} 仍启用面板原生 monthly。")
            warnings.append("使用外置自定义重置日期时，请在 3x-ui 面板中改为 never/不重置。")

        inbound_day = safe_day(cfg.get("day", default_day), default_day)
        inbound_due, inbound_reason = should_reset(inbound_day, state["inbounds"].get(str(iid), {}))
        inbound_label = f"入站 ID={iid}，端口={inbound['port']}，备注={truncate(inbound['remark'])}"

        if cfg.get("reset_inbound", True):
            if inbound_due:
                plan_inbounds.append({"id": str(iid), "label": inbound_label, "reason": inbound_reason})
            else:
                skipped.append((f"入站 ID={iid}", inbound_reason))
        else:
            skipped.append((f"入站 ID={iid}", "入站自身 up/down 已设置为不重置"))

        client_rules = cfg.get("clients", {}) if isinstance(cfg.get("clients"), dict) else {}

        if cfg.get("reset_clients_without_custom_day", False):
            for client in clients_by_inbound.get(str(iid), []):
                email = client["email"] or ""
                custom_rule = client_rules.get(email, {})
                if isinstance(custom_rule, dict) and custom_rule.get("enabled") and safe_day(custom_rule.get("day", 0), 0) > 0:
                    continue
                key = f"{iid}|{email}"
                due, reason = should_reset(inbound_day, state["clients"].get(key, {}))
                label = f"客户端 {email or '无邮箱'}，入站 ID={iid}"
                if due:
                    plan_clients.append({"inbound_id": str(iid), "email": email, "key": key, "label": label, "reason": f"跟随入站，{reason}"})
                else:
                    skipped.append((label, reason))

        for email, ccfg in sorted(client_rules.items()):
            if not isinstance(ccfg, dict) or not ccfg.get("enabled", True):
                continue
            cday = safe_day(ccfg.get("day", 0), 0)
            if cday <= 0:
                continue
            key_tuple = (str(iid), email)
            label = f"客户端 {email or '无邮箱'}，入站 ID={iid}"
            if key_tuple not in client_lookup:
                skipped.append((label, "客户端已不存在，跳过"))
                continue
            key = f"{iid}|{email}"
            due, reason = should_reset(cday, state["clients"].get(key, {}))
            if due:
                plan_clients.append({"inbound_id": str(iid), "email": email, "key": key, "label": label, "reason": f"客户端单独日期，{reason}"})
            else:
                skipped.append((label, reason))

    return plan_inbounds, plan_clients, skipped, warnings

def print_preview(plan_inbounds, plan_clients, skipped, warnings):
    print("================================================")
    print("本次重置预览")
    print("================================================")
    print(f"日期：{today.isoformat()}")
    print("模式：预览模式，只预览，不写数据库")
    print("说明：真实执行时会先把本月 up/down 累加到状态文件的历史总流量，再清零本月流量")
    print()
    if not plan_inbounds and not plan_clients:
        print("本次没有需要重置的入站或客户端。")
    else:
        print("将重置：")
        for item in plan_inbounds:
            print(f"  {item['label']}")
            print(f"    原因：{item['reason']}")
            print()
        for item in plan_clients:
            print(f"  {item['label']}")
            print(f"    原因：{item['reason']}")
            print()
    print("不会重置：")
    if not skipped:
        print("  无")
    else:
        for label, reason in skipped:
            print(f"  {label}")
            print(f"    原因：{reason}")
    if warnings:
        print()
        print("提醒：")
        seen = set()
        for warning in warnings:
            if warning in seen:
                continue
            seen.add(warning)
            print(f"  {warning}")
    print("================================================")

def backup_database():
    backup_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(backup_dir, 0o700)
    backup_path = backup_dir / f"x-ui.db.{time.strftime('%Y-%m-%d_%H%M%S')}.bak"
    src = sqlite3.connect(db_path)
    dst = sqlite3.connect(backup_path)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    os.chmod(backup_path, 0o600)
    return backup_path

def quick_health():
    print()
    print("简短健康检查：")
    active = subprocess.run(["systemctl", "is-active", "--quiet", "x-ui"]).returncode == 0
    print(f"  x-ui 服务：{'运行中' if active else '未运行'}")
    try:
        conn = sqlite3.connect(db_path)
        result = conn.execute("PRAGMA integrity_check;").fetchone()[0]
        conn.close()
        print(f"  数据库完整性：{result}")
    except Exception as exc:
        print(f"  数据库完整性：检查失败：{exc}")

def add_preserved_traffic(state_record, up, down):
    totals = state_record.setdefault("traffic_totals", {})
    previous_up = non_negative_int(totals.get("up", 0))
    previous_down = non_negative_int(totals.get("down", 0))
    up = non_negative_int(up)
    down = non_negative_int(down)
    totals["up"] = previous_up + up
    totals["down"] = previous_down + down
    totals["total"] = totals["up"] + totals["down"]
    return totals

def execute_plan(plan_inbounds, plan_clients, state):
    print("准备执行自定义重置...")
    backup_path = backup_database()
    print(f"数据库备份：{backup_path}")

    service_stopped = False
    conn = None
    updated_inbounds = []
    updated_clients = []
    skipped_write = []

    try:
        subprocess.run(["systemctl", "stop", "x-ui"], check=False)
        service_stopped = True

        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("BEGIN")

        for item in plan_inbounds:
            row = cur.execute("SELECT up, down FROM inbounds WHERE id=?", (item["id"],)).fetchone()
            if row is None:
                skipped_write.append((item["label"], "写入时入站已不存在"))
                continue
            cur.execute("UPDATE inbounds SET up=0, down=0 WHERE id=?", (item["id"],))
            if cur.rowcount > 0:
                item["preserved_totals"] = add_preserved_traffic(
                    state["inbounds"].setdefault(item["id"], {}),
                    row[0],
                    row[1],
                )
                updated_inbounds.append(item)
            else:
                skipped_write.append((item["label"], "写入时入站已不存在"))

        for item in plan_clients:
            row = cur.execute(
                "SELECT up, down FROM client_traffics WHERE inbound_id=? AND email=?",
                (item["inbound_id"], item["email"]),
            ).fetchone()
            if row is None:
                skipped_write.append((item["label"], "写入时客户端已不存在"))
                continue
            cur.execute(
                "UPDATE client_traffics SET up=0, down=0 WHERE inbound_id=? AND email=?",
                (item["inbound_id"], item["email"]),
            )
            if cur.rowcount > 0:
                item["preserved_totals"] = add_preserved_traffic(
                    state["clients"].setdefault(item["key"], {}),
                    row[0],
                    row[1],
                )
                updated_clients.append(item)
            else:
                skipped_write.append((item["label"], "写入时客户端已不存在"))

        conn.commit()

        for item in updated_inbounds:
            state["inbounds"].setdefault(item["id"], {}).update({"last_reset_month": current_month, "last_reset_date": today.isoformat()})
        for item in updated_clients:
            state["clients"].setdefault(item["key"], {}).update({"last_reset_month": current_month, "last_reset_date": today.isoformat()})
        save_state(state)

        if updated_inbounds or updated_clients:
            print("重置完成：")
            for item in updated_inbounds:
                print(f"  {item['label']}，累计历史总流量已保留 {item['preserved_totals']['total']} bytes")
            for item in updated_clients:
                print(f"  {item['label']}，累计历史总流量已保留 {item['preserved_totals']['total']} bytes")
        else:
            print("没有对象被写入，状态文件未新增记录。")
        for label, reason in skipped_write:
            print(f"跳过：{label}，{reason}")
        return 0
    except Exception as exc:
        if conn is not None:
            try:
                conn.rollback()
            except Exception:
                pass
        print(f"执行失败：{exc}")
        return 1
    finally:
        if conn is not None:
            conn.close()
        if service_stopped:
            subprocess.run(["systemctl", "start", "x-ui"], check=False)
        quick_health()

def main():
    config = load_config()
    if config is None:
        write_plan_count(0)
        return 1

    if not config.get("enabled", False):
        if dry_run:
            print("================================================")
            print("本次重置预览")
            print("================================================")
            print(f"日期：{today.isoformat()}")
            print("模式：预览模式，只预览，不写数据库")
            print("说明：真实执行时会先把本月 up/down 累加到状态文件的历史总流量，再清零本月流量")
            print()
            print("自定义重置已禁用，跳过。")
            print("================================================")
        else:
            print("自定义重置已禁用，跳过。")
        write_plan_count(0)
        return 0

    state = load_state()
    if state is None:
        write_plan_count(0)
        return 1

    if not db_path.exists():
        print(f"错误：数据库不存在：{db_path}")
        write_plan_count(0)
        return 1

    try:
        conn = connect_db()
        inbounds, clients = load_db_rows(conn)
        conn.close()
    except Exception as exc:
        print(f"数据库读取失败：{exc}")
        write_plan_count(0)
        return 1

    plan_inbounds, plan_clients, skipped, warnings = build_plan(config, state, inbounds, clients)
    plan_count = len(plan_inbounds) + len(plan_clients)
    write_plan_count(plan_count)

    if dry_run:
        print_preview(plan_inbounds, plan_clients, skipped, warnings)
        return 0

    for warning in warnings:
        print(f"提醒：{warning}")

    if plan_count == 0:
        print("本次没有需要重置的对象。")
        return 0

    return execute_plan(plan_inbounds, plan_clients, state)

try:
    sys.exit(main())
except KeyboardInterrupt:
    print("已取消。")
    sys.exit(100)
except Exception as exc:
    print(f"执行异常：{exc}")
    sys.exit(1)
PY
}

run_reset_check_interactive() {
    clear_screen

    local count_file count
    count_file="$(mktemp)"

    set +e
    PLAN_COUNT_FILE="$count_file" DRY_RUN=1 run_reset_engine
    local dry_ret=$?
    set -e

    count="0"
    if [ -f "$count_file" ]; then
        count="$(tr -cd '0-9' < "$count_file")"
    fi
    rm -f "$count_file"
    count="${count:-0}"

    if [ "$dry_ret" -ne 0 ]; then
        echo
        echo "预览失败，未执行任何写库操作。"
        pause
        return 0
    fi

    if [ "$count" -eq 0 ]; then
        pause
        return 0
    fi

    echo
    local answer
    read -rp "是否立即执行以上重置？请输入 YES 确认： " answer
    if [ "$answer" != "YES" ]; then
        echo "已取消，没有写入数据库。"
        pause
        return 0
    fi

    echo
    DRY_RUN=0 run_reset_engine
    pause
}

collect_db_ports() {
    if [ ! -f "$XUI_DB" ]; then
        return 0
    fi

    XUI_DB="$XUI_DB" python3 <<'PY' 2>/dev/null || true
import os
import sqlite3

db_path = os.environ["XUI_DB"]
conn = sqlite3.connect(db_path)
cols = [row[1] for row in conn.execute("PRAGMA table_info(inbounds)").fetchall()]
if "port" not in cols:
    raise SystemExit(0)
if "enable" in cols:
    rows = conn.execute("SELECT port FROM inbounds WHERE enable=1").fetchall()
else:
    rows = conn.execute("SELECT port FROM inbounds").fetchall()
for (port,) in rows:
    try:
        port = int(port)
    except Exception:
        continue
    if port > 0:
        print(port)
conn.close()
PY
}

collect_process_ports() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnpH 2>/dev/null \
            | awk '/x-ui|3x-ui/ {print $4}' \
            | awk -F: '{print $NF}' \
            | grep -E '^[0-9]+$' || true
    fi
}

port_is_listening() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    fi

    return 2
}

print_monthly_conflicts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$XUI_DB" ]; then
        echo "monthly 冲突：未发现"
        return 0
    fi

    XUI_DB="$XUI_DB" CONFIG_FILE="$CONFIG_FILE" python3 <<'PY' 2>/dev/null || true
import json
import os
import sqlite3

db_path = os.environ["XUI_DB"]
config_path = os.environ["CONFIG_FILE"]

try:
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
except Exception:
    print("monthly 冲突：配置读取失败")
    raise SystemExit(0)

enabled_ids = [str(k) for k, v in config.get("inbounds", {}).items() if isinstance(v, dict) and v.get("enabled")]
if not enabled_ids:
    print("monthly 冲突：未发现")
    raise SystemExit(0)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
try:
    rows = conn.execute("SELECT id, remark, traffic_reset FROM inbounds").fetchall()
except sqlite3.OperationalError:
    rows = []
conflicts = [row for row in rows if str(row["id"]) in enabled_ids and row["traffic_reset"] == "monthly"]
conn.close()

if not conflicts:
    print("monthly 冲突：未发现")
else:
    print("monthly 冲突：发现提醒")
    for row in conflicts:
        remark = row["remark"] or "无备注"
        if len(remark) > 20:
            remark = remark[:20] + "..."
        print(f"  入站 ID={row['id']} 备注={remark}")
    print("  建议：请在 3x-ui 面板中关闭原生 monthly，改为 never/不重置。")
PY
}

print_health_report() {
    install_runtime_deps

    echo "x-ui 服务："
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        echo -e "  ${GREEN}运行中${PLAIN}"
    else
        echo -e "  ${RED}未运行${PLAIN}"
    fi

    echo "数据库文件："
    if [ -f "$XUI_DB" ]; then
        echo -e "  ${GREEN}存在：$XUI_DB${PLAIN}"
        local integrity
        integrity="$(sqlite3 "$XUI_DB" "PRAGMA integrity_check;" 2>&1 || true)"
        if [ "$integrity" = "ok" ]; then
            echo -e "  ${GREEN}完整性：ok${PLAIN}"
        else
            echo -e "  ${RED}完整性异常：$integrity${PLAIN}"
        fi
    else
        echo -e "  ${RED}缺失：$XUI_DB${PLAIN}"
    fi

    echo "本地执行器："
    if [ -x "$LOCAL_RUNNER" ]; then
        echo -e "  ${GREEN}已安装：$LOCAL_RUNNER${PLAIN}"
    else
        echo -e "  ${YELLOW}未安装：$LOCAL_RUNNER${PLAIN}"
    fi

    echo "xcm："
    if [ -x "$XCM_PATH" ]; then
        echo -e "  ${GREEN}已注册：$XCM_PATH${PLAIN}"
    else
        echo -e "  ${YELLOW}未注册：$XCM_PATH${PLAIN}"
    fi

    echo "自动检查 timer："
    if [ -f "$RESET_TIMER" ]; then
        echo "  文件：存在"
    else
        echo "  文件：不存在"
    fi
    echo "  enabled：$(timer_enabled_status)"
    echo "  active：$(timer_active_status)"

    echo "端口监听："
    local ports=()
    mapfile -t ports < <({ collect_db_ports; collect_process_ports; } | sort -n | uniq)
    if [ "${#ports[@]}" -eq 0 ]; then
        echo "  未从数据库读取到入站端口。"
    else
        local port
        for port in "${ports[@]}"; do
            if port_is_listening "$port"; then
                echo -e "  ${GREEN}$port 已监听${PLAIN}"
            else
                echo -e "  ${YELLOW}$port 未监听，请检查 x-ui / xray 服务${PLAIN}"
            fi
        done
    fi

    print_monthly_conflicts

    echo "最近日志关键词："
    local log_hit=0
    if [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" | grep -Eiq "panic|error|failed|no such column"; then
        log_hit=1
    fi
    if journalctl -u x-ui -n 100 --no-pager 2>/dev/null | grep -Eiq "panic|error|failed|no such column"; then
        log_hit=1
    fi
    if [ "$log_hit" -eq 1 ]; then
        echo -e "  ${YELLOW}发现错误关键词，请进入 [5] 查看日志。${PLAIN}"
    else
        echo -e "  ${GREEN}未发现明显错误关键词。${PLAIN}"
    fi

    echo "预览模式："
    echo "  可在“自定义重置日期 -> 立即检查一次”预览本次计划。"
}

health_check() {
    clear_screen
    echo "================================================"
    echo "健康检查"
    echo "================================================"
    print_health_report
}

menu_logs() {
    while true; do
        clear_screen
        echo "================================================"
        echo "查看日志"
        echo "================================================"
        echo " 1. 查看脚本日志"
        echo " 2. 查看自动检查 timer 日志"
        echo " 3. 查看 x-ui 服务日志"
        echo "------------------------------------------------"
        echo " 0. 返回主菜单"
        echo "================================================"
        read -rp "请选择： " choice

        case "$choice" in
            1)
                clear_screen
                echo "脚本日志：$LOG_FILE"
                echo "------------------------------------------------"
                tail -n 100 "$LOG_FILE" || true
                pause
                ;;
            2)
                clear_screen
                echo "自动检查 timer 日志"
                echo "------------------------------------------------"
                journalctl -u xui-custom-reset.service -n 100 --no-pager || true
                pause
                ;;
            3)
                clear_screen
                echo "x-ui 服务日志"
                echo "------------------------------------------------"
                journalctl -u x-ui -n 100 --no-pager || true
                pause
                ;;
            0)
                return 0
                ;;
            *)
                echo "无效选择。"
                sleep 1
                ;;
        esac
    done
}

menu_backup_restore() {
    while true; do
        clear_screen
        echo "================================================"
        echo "备份与恢复"
        echo "================================================"
        echo "备份目录：$BACKUP_DIR"
        echo "------------------------------------------------"
        echo " 1. 立即备份"
        echo " 2. 恢复数据库"
        echo " 3. 恢复程序目录"
        echo " 4. 恢复配置目录"
        echo "------------------------------------------------"
        echo " 0. 返回主菜单"
        echo "================================================"
        read -rp "请选择： " choice

        case "$choice" in
            1)
                clear_screen
                backup_all
                pause
                ;;
            2)
                restore_backup "db"
                pause
                ;;
            3)
                restore_backup "program"
                pause
                ;;
            4)
                restore_backup "etc"
                pause
                ;;
            0)
                return 0
                ;;
            *)
                echo "无效选择。"
                sleep 1
                ;;
        esac
    done
}

main_menu() {
    register_xcm_shortcut

    while true; do
        clear_screen
        echo "================================================"
        echo "x-ui 自定义管理器"
        echo "================================================"
        echo "用于自定义重置日期、流量校准、备份恢复和健康检查。"
        echo
        echo "配置：$CONFIG_FILE"
        echo "备份：$BACKUP_DIR"
        echo "日志：$LOG_FILE"
        echo "自动检查：$(timer_active_status)"
        echo "本地执行器：$(runner_status)"
        echo "快捷命令：xcm"
        echo "------------------------------------------------"
        echo " 1. 自定义重置日期"
        echo " 2. 流量校准"
        echo " 3. 备份与恢复"
        echo " 4. 健康检查"
        echo " 5. 查看日志"
        echo " 6. 清理旧备份"
        echo "------------------------------------------------"
        echo " 0. 退出"
        echo "================================================"
        read -rp "请选择： " choice

        case "$choice" in
            1)
                run_custom_reset_ui
                ;;
            2)
                run_traffic_ui
                ;;
            3)
                menu_backup_restore
                ;;
            4)
                health_check
                pause
                ;;
            5)
                menu_logs
                ;;
            6)
                cleanup_backups
                pause
                ;;
            0)
                clear_screen
                exit 0
                ;;
            *)
                echo "无效选择。"
                sleep 1
                ;;
        esac
    done
}

if [ "$RUN_CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    run_reset_engine
else
    main_menu
fi
