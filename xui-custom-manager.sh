#!/usr/bin/env bash
set -Eeuo pipefail

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
# 仅在非交互模式下重定向输出到日志 (避免污染终端菜单)
if [ ! -t 0 ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "===== $(date '+%F %T') 自动任务执行 ====="
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
    read -rp "按回车继续..."
}

confirm_action() {
    local message="$1"
    local answer
    echo
    echo -e "${YELLOW}危险操作确认：${message}${PLAIN}"
    read -rp "请输入 YES 确认继续： " answer
    if [ "$answer" != "YES" ]; then
        echo "已取消。"
        return 1
    fi
}

ensure_dirs() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$RESET_STATE")"
    chmod 700 "$BACKUP_DIR"
}

install_runtime_deps() {
    if command -v sqlite3 >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        return
    fi
    apt update && apt install -y sqlite3 python3
}

# --- 架构相关 ---

register_xcm_shortcut() {
    local xcm_path="/usr/local/bin/xcm"
    if [ ! -f "$xcm_path" ]; then
        cat > "$xcm_path" <<'EOF'
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
elif command -v wget >/dev/null 2>&1 && wget -qO "$TMP_FILE" --timeout=10 --tries=2 "$URL"; then
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
        chmod 755 "$xcm_path"
    fi
}

install_local_runner() {
    local self_path
    self_path="$(readlink -f "$0")"
    if [ "$self_path" != "$LOCAL_RUNNER" ]; then
        install -m 755 "$self_path" "$LOCAL_RUNNER"
    fi
}

ensure_reset_timer_installed() {
    install_local_runner

    cat >"$RESET_SERVICE" <<EOF
[Unit]
Description=x-ui custom monthly traffic reset
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $LOCAL_RUNNER --reset-check
EOF

    cat >"$RESET_TIMER" <<'EOF'
[Unit]
Description=Run x-ui custom monthly traffic reset daily

[Timer]
OnCalendar=*-*-* 00:10:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now xui-custom-reset.timer >/dev/null 2>&1
}

# --- 功能实现 ---

cleanup_backups() {
    clear_screen
    echo "================================================"
    echo "清理旧备份"
    echo "================================================"
    ensure_dirs
    local types=("x-ui.db.*.bak" "x-ui-program.*.tar.gz" "x-ui-etc.*.tar.gz")
    local labels=("数据库" "程序目录" "配置目录")
    
    for i in "${!types[@]}"; do
        local pattern="${types[$i]}"
        local label="${labels[$i]}"
        local files=()
        
        mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$pattern" | sort -r)
        if [ "${#files[@]}" -le 10 ]; then
            continue
        fi
        
        echo
        echo "$label 备份超过 10 个，以下旧备份可清理（每类仅删一个明确选择的文件）："
        for idx in "${!files[@]}"; do
            if [ "$idx" -ge 10 ]; then
                printf '  %s) %s\n' "$((idx + 1))" "${files[$idx]}"
            fi
        done
        
        local choice
        read -rp "请输入要删除的 ${label} 备份序号 (0 跳过)： " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -le "${#files[@]}" ]; then
            local file="${files[$((choice - 1))]}"
            if [ -f "$file" ]; then
                confirm_action "删除文件：$file" && rm -f -- "$file" && echo "已删除：$file"
            fi
        fi
    done
    echo "清理完成。"
}

backup_all() {
    ensure_dirs
    local ts
    ts="$(date +%F_%H%M%S)"
    echo "正在备份..."

    if [ -f "$XUI_DB" ]; then
        if sqlite3 "$XUI_DB" ".backup '$BACKUP_DIR/x-ui.db.$ts.bak'"; then
            chmod 600 "$BACKUP_DIR/x-ui.db.$ts.bak"
            echo "数据库备份：$BACKUP_DIR/x-ui.db.$ts.bak"
        else
            echo "数据库备份失败！"
            return 1
        fi
    fi

    if [ -d "$XUI_ETC_DIR" ]; then
        tar -czf "$BACKUP_DIR/x-ui-etc.$ts.tar.gz" -C "$(dirname "$XUI_ETC_DIR")" "$(basename "$XUI_ETC_DIR")"
        echo "配置目录备份：$BACKUP_DIR/x-ui-etc.$ts.tar.gz"
    fi

    if [ -d "$XUI_PROGRAM_DIR" ]; then
        tar -czf "$BACKUP_DIR/x-ui-program.$ts.tar.gz" -C "$(dirname "$XUI_PROGRAM_DIR")" "$(basename "$XUI_PROGRAM_DIR")"
        echo "程序目录备份：$BACKUP_DIR/x-ui-program.$ts.tar.gz"
    fi
}

restore_backup() {
    local kind="$1"
    local pattern
    local target_dir
    local label

    ensure_dirs
    case "$kind" in
        db) pattern="x-ui.db.*.bak"; label="数据库";;
        program) pattern="x-ui-program.*.tar.gz"; label="程序目录"; target_dir="$(dirname "$XUI_PROGRAM_DIR")";;
        etc) pattern="x-ui-etc.*.tar.gz"; label="配置目录"; target_dir="$(dirname "$XUI_ETC_DIR")";;
        *) return 1;;
    esac

    clear_screen
    echo "================================================"
    echo "恢复$label"
    echo "================================================"
    local files=()
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "$pattern" | sort -r)
    
    if [ "${#files[@]}" -eq 0 ]; then
        echo "未找到 $label 备份。"
        return
    fi

    for i in "${!files[@]}"; do
        printf ' %s. %s\n' "$((i + 1))" "${files[$i]}"
    done
    echo "------------------------------------------------"
    echo " 0. 返回上级"

    local choice
    read -rp "请选择备份文件编号： " choice
    if [ "$choice" = "0" ] || ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -gt "${#files[@]}" ]; then
        return
    fi

    local selected="${files[$((choice - 1))]}"
    confirm_action "停止 x-ui，并将 $label 恢复为 $selected" || return

    echo "停止 x-ui..."
    systemctl stop x-ui || true

    echo "恢复前自动备份当前状态..."
    backup_all

    if [ "$kind" = "db" ]; then
        cp -a "$selected" "$XUI_DB"
        chmod 600 "$XUI_DB"
    else
        tar -xzf "$selected" -C "$target_dir"
    fi

    echo "启动 x-ui..."
    systemctl start x-ui
    echo "恢复完成。"
}

health_check() {
    clear_screen
    echo "================================================"
    echo "健康检查"
    echo "================================================"
    install_runtime_deps

    # 服务状态
    if systemctl is-active --quiet x-ui; then
        echo -e "服务状态: ${GREEN}运行中${PLAIN}"
    else
        echo -e "服务状态: ${RED}未运行${PLAIN}"
    fi

    # 数据库
    if [ -f "$XUI_DB" ]; then
        local check
        check="$(sqlite3 "$XUI_DB" "PRAGMA integrity_check;" 2>&1 || true)"
        if [ "$check" = "ok" ]; then
            echo -e "数据库:   ${GREEN}正常${PLAIN}"
        else
            echo -e "数据库:   ${RED}损坏 ($check)${PLAIN}"
        fi
    else
        echo -e "数据库:   ${RED}缺失${PLAIN}"
    fi

    # timer/runner
    if [ -x "$LOCAL_RUNNER" ]; then
        echo -e "本地执行器: ${GREEN}已安装${PLAIN}"
    else
        echo -e "本地执行器: ${RED}未安装${PLAIN}"
    fi

    if systemctl is-active --quiet xui-custom-reset.timer; then
        echo -e "自动检查: ${GREEN}已启用${PLAIN}"
    else
        echo -e "自动检查: ${YELLOW}未启用${PLAIN}"
    fi

    if [ -x /usr/local/bin/xcm ]; then
        echo -e "快捷命令: ${GREEN}xcm 已注册${PLAIN}"
    else
        echo -e "快捷命令: ${YELLOW}未注册${PLAIN}"
    fi

    # 日志关键词
    local logs
    logs="$(journalctl -u x-ui -n 100 --no-pager 2>/dev/null || true)"
    if echo "$logs" | grep -Eiq "panic|error|failed"; then
        echo -e "最近日志: ${RED}发现错误关键词 (请进入 [5] 查看日志)${PLAIN}"
    else
        echo -e "最近日志: ${GREEN}未见明显异常${PLAIN}"
    fi

    echo "------------------------------------------------"
    echo "外置与原生配置冲突检测："
    local has_conflict=0
    if [ -f "$CONFIG_FILE" ]; then
        local enabled_ids
        enabled_ids=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(','.join(k for k,v in d.get('inbounds',{}).items() if v.get('enabled')))" "$CONFIG_FILE" 2>/dev/null || true)
        if [ -n "$enabled_ids" ]; then
            local conflicts
            conflicts=$(sqlite3 "$XUI_DB" "SELECT id, remark FROM inbounds WHERE traffic_reset='monthly' AND id IN ($enabled_ids);" 2>/dev/null || true)
            if [ -n "$conflicts" ]; then
                has_conflict=1
                echo -e "${YELLOW}发现冲突！以下已启用外置管理的入站，仍在面板启用了原生 monthly：${PLAIN}"
                echo "$conflicts" | awk -F'|' '{print "  入站 ID=" $1 " 备注=" $2}'
                echo -e "${YELLOW}建议：请在 3x-ui 面板中将这些入站的重置改为 'never/不重置'。${PLAIN}"
            fi
        fi
    fi
    if [ "$has_conflict" -eq 0 ]; then
        echo "未发现外置规则与原生 monthly 重置冲突。"
    fi
}

# --- 核心交互 Python (通过 /dev/tty 执行避免 EOF) ---

run_custom_reset_ui() {
    install_runtime_deps
    local tmp_py
    tmp_py="$(mktemp --suffix=.py)"
    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import sys
from pathlib import Path

db_path = os.environ.get("XUI_DB", "/etc/x-ui/x-ui.db")
config_path = Path(os.environ.get("CONFIG_FILE", "/etc/xui-custom-reset.json"))

def load_config():
    if config_path.exists():
        try:
            with config_path.open("r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"enabled": False, "default_day": 1, "inbounds": {}}

def save_config(data):
    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = config_path.with_suffix(".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, config_path)
    os.chmod(config_path, 0o600)

def clear():
    print('\033c', end='')

def input_choice(prompt, valid_choices):
    while True:
        try:
            c = input(prompt).strip()
            if c in valid_choices:
                return c
        except EOFError:
            sys.exit(100)

config = load_config()

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    inbounds = conn.execute("SELECT id, remark, port, traffic_reset FROM inbounds ORDER BY id").fetchall()
    clients_by_inbound = {}
    for c in conn.execute("SELECT id, inbound_id, email FROM client_traffics").fetchall():
        clients_by_inbound.setdefault(str(c["inbound_id"]), []).append(c)
except Exception as e:
    print(f"数据库读取失败: {e}")
    sys.exit(1)
finally:
    conn.close()

def manage_clients(inbound_id, inbound_cfg):
    clients = clients_by_inbound.get(str(inbound_id), [])
    while True:
        clear()
        print("================================================")
        print("客户端单独日期")
        print("================================================")
        print(f"入站 ID：{inbound_id}")
        print("说明：不单独设置时，客户端按入站规则处理。")
        print("------------------------------------------------")
        for idx, c in enumerate(clients, start=1):
            email = c["email"]
            c_cfg = inbound_cfg.get("clients", {}).get(email, {})
            day = c_cfg.get("day", 0)
            status = f"每月 {day} 号" if c_cfg.get("enabled") and day > 0 else "不单独设置"
            print(f" {idx}. {email}    {status}")
        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")
        
        valid = {"0"} | {str(i) for i in range(1, len(clients) + 1)}
        choice = input_choice("请选择客户端： ", valid)
        if choice == "0":
            break
        
        c = clients[int(choice) - 1]
        email = c["email"]
        while True:
            try:
                day_input = input(f"输入 {email} 每月重置日期 (1-31)，输入 0 取消单独设置: ").strip()
                day = int(day_input)
                if 0 <= day <= 31:
                    break
            except Exception:
                pass
        
        inbound_cfg.setdefault("clients", {})
        if day == 0:
            inbound_cfg["clients"].pop(email, None)
        else:
            inbound_cfg["clients"][email] = {"enabled": True, "day": day}
        save_config(config)

def manage_inbound(inbound):
    iid = str(inbound["id"])
    while True:
        cfg = config.get("inbounds", {}).get(iid, {})
        cfg.setdefault("enabled", False)
        cfg.setdefault("day", config.get("default_day", 1))
        cfg.setdefault("reset_inbound", True)
        cfg.setdefault("reset_clients_without_custom_day", True)

        clear()
        print("================================================")
        print("入站设置")
        print("================================================")
        print(f"ID：{iid}")
        print(f"端口：{inbound['port']}")
        print(f"备注：{inbound['remark'] or '无'}")
        print()
        print(f"外置重置：{'开启' if cfg['enabled'] else '关闭'}")
        print(f"入站日期：每月 {cfg['day']} 号")
        print(f"入站自身 up/down：{'重置' if cfg['reset_inbound'] else '不重置'}")
        print(f"未单独设置日期的客户端：{'跟随入站' if cfg['reset_clients_without_custom_day'] else '忽略'}")
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
            break
        
        config.setdefault("inbounds", {})[iid] = cfg
        if choice == "1":
            cfg["enabled"] = not cfg["enabled"]
        elif choice == "2":
            while True:
                try:
                    day = int(input("请输入日期 (1-31): ").strip())
                    if 1 <= day <= 31:
                        cfg["day"] = day
                        break
                except Exception:
                    pass
        elif choice == "3":
            cfg["reset_inbound"] = not cfg["reset_inbound"]
        elif choice == "4":
            cfg["reset_clients_without_custom_day"] = not cfg["reset_clients_without_custom_day"]
        elif choice == "5":
            manage_clients(iid, cfg)
        
        save_config(config)

def choose_inbound():
    while True:
        clear()
        print("================================================")
        print("选择入站")
        print("================================================")
        for idx, row in enumerate(inbounds, start=1):
            iid = str(row["id"])
            cfg = config.get("inbounds", {}).get(iid, {})
            enabled = "开启" if cfg.get("enabled") else "关闭"
            day = cfg.get("day", config.get("default_day", 1))
            remark = (row["remark"] or "无备注")[:20]
            print(f" {idx}. ID={iid}  端口={row['port']}  备注={remark}")
            print(f"    外置重置：{enabled}  日期：每月 {day} 号")
            if row["traffic_reset"] == "monthly":
                print(f"    面板原生：monthly  警告：请在面板中改为 never/不重置")
            else:
                print(f"    面板原生：{row['traffic_reset']}")
            print()
        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")
        
        valid = {"0"} | {str(i) for i in range(1, len(inbounds) + 1)}
        choice = input_choice("请选择入站： ", valid)
        if choice == "0":
            break
        manage_inbound(inbounds[int(choice) - 1])

while True:
    is_timer_active = os.system("systemctl is-active --quiet xui-custom-reset.timer") == 0
    clear()
    print("================================================")
    print("自定义重置日期")
    print("================================================")
    print(f"全局状态：{'启用' if config.get('enabled') else '禁用'}")
    print(f"默认日期：每月 {config.get('default_day', 1)} 号")
    print(f"自动检查：{'已启用' if is_timer_active else '未启用'}")
    print()
    print("提示：请在 3x-ui 面板里关闭对应入站的原生 monthly 重置。")
    print("------------------------------------------------")
    print(" 1. 开启/关闭自定义重置")
    print(" 2. 设置默认日期")
    print(" 3. 管理入站/客户端")
    print(" 4. 立即检查一次 (预览/执行)")
    print("------------------------------------------------")
    print(" 0. 返回主菜单")
    print("================================================")
    
    choice = input_choice("请选择： ", {"0", "1", "2", "3", "4"})
    if choice == "0":
        break
    elif choice == "1":
        config["enabled"] = not config.get("enabled", False)
        save_config(config)
        if config["enabled"]:
            sys.exit(200) # 告知 bash 启用 timer
        else:
            sys.exit(201) # 告知 bash 停用 timer
    elif choice == "2":
        while True:
            try:
                day = int(input("请输入默认日期 (1-31): ").strip())
                if 1 <= day <= 31:
                    config["default_day"] = day
                    save_config(config)
                    break
            except Exception:
                pass
    elif choice == "3":
        choose_inbound()
    elif choice == "4":
        sys.exit(202) # 告知 bash 运行 reset-check 交互
PY
    
    if [ ! -t 0 ]; then echo "需要交互式终端"; return 1; fi
    set +e
    XUI_DB="$XUI_DB" CONFIG_FILE="$CONFIG_FILE" python3 "$tmp_py" < /dev/tty
    local ret=$?
    rm -f "$tmp_py"
    set -e
    
    if [ "$ret" -eq 200 ]; then
        ensure_reset_timer_installed
        echo "自定义重置已启用，自动检查 timer 已安装并启动。"
        pause
        run_custom_reset_ui
    elif [ "$ret" -eq 201 ]; then
        systemctl disable --now xui-custom-reset.timer >/dev/null 2>&1 || true
        echo "自定义重置已禁用，自动检查 timer 已停用。"
        pause
        run_custom_reset_ui
    elif [ "$ret" -eq 202 ]; then
        clear_screen
        # 内部调用 dry-run 预览
        bash "$LOCAL_RUNNER" --reset-check --dry-run
        echo
        read -rp "是否立即真实执行以上重置？请输入 YES 确认： " ans
        if [ "$ans" = "YES" ]; then
            bash "$LOCAL_RUNNER" --reset-check
        else
            echo "已取消，没有写入数据库。"
        fi
        pause
        run_custom_reset_ui
    fi
}

run_edit_traffic_ui() {
    install_runtime_deps
    local tmp_py
    tmp_py="$(mktemp --suffix=.py)"
    cat > "$tmp_py" <<'PY'
import json
import os
import sqlite3
import sys
from decimal import Decimal, ROUND_HALF_UP

db_path = os.environ.get("XUI_DB", "/etc/x-ui/x-ui.db")

def clear():
    print('\033c', end='')

def human_gib(bytes_val):
    try:
        val = int(bytes_val or 0)
        gib = val / (1024**3)
        return f"{gib:.2f} GiB"
    except:
        return "0.00 GiB"

def to_bytes(gib_str):
    val = Decimal(gib_str)
    if val < 0: raise ValueError
    return int((val * Decimal(1024**3)).to_integral_value(rounding=ROUND_HALF_UP))

def input_choice(prompt, valid_choices, allow_quit=True):
    while True:
        try:
            c = input(prompt).strip()
            if allow_quit and c == "0":
                sys.exit(100)
            if c in valid_choices:
                return c
        except EOFError:
            sys.exit(100)

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    inbounds = conn.execute("SELECT id, remark, port, up, down, total FROM inbounds ORDER BY id").fetchall()
except Exception as e:
    print(f"数据库读取失败: {e}")
    sys.exit(1)

if not inbounds:
    print("无入站。")
    sys.exit(100)

while True:
    clear()
    print("================================================")
    print("流量校准")
    print("================================================")
    print("说明：这里只校准已用流量 up/down，不修改流量上限 total。")
    print("单位：GiB，1 GiB = 1024^3 bytes")
    print("------------------------------------------------")
    for idx, row in enumerate(inbounds, start=1):
        used = int(row["up"] or 0) + int(row["down"] or 0)
        tot = int(row["total"] or 0)
        tot_str = human_gib(tot) if tot > 0 else "不限量"
        remark = (row["remark"] or "无备注")[:20]
        print(f" {idx}. ID={row['id']}  端口={row['port']}  备注={remark}")
        print(f"    已用：{human_gib(used)} / 上限：{tot_str}")
        print()
    print("------------------------------------------------")
    print(" 0. 返回主菜单")
    print("================================================")
    
    choice = input_choice("请选择入站： ", {"0"} | {str(i) for i in range(1, len(inbounds) + 1)}, allow_quit=True)
    inbound = inbounds[int(choice) - 1]
    iid = inbound["id"]
    
    clients = conn.execute("SELECT id, email, up, down, total FROM client_traffics WHERE inbound_id=? ORDER BY id", (iid,)).fetchall()
    
    while True:
        clear()
        print("================================================")
        print("选择校准对象")
        print("================================================")
        print(f"入站 ID：{iid}  端口：{inbound['port']}  备注：{inbound['remark'] or '无备注'}")
        print("------------------------------------------------")
        
        used_inb = int(inbound["up"] or 0) + int(inbound["down"] or 0)
        print(f" 1. 入站自身\n    已用：{human_gib(used_inb)}\n")
        
        for idx, c in enumerate(clients, start=2):
            used_c = int(c["up"] or 0) + int(c["down"] or 0)
            tot_c = int(c["total"] or 0)
            tot_str = human_gib(tot_c) if tot_c > 0 else "不限量"
            print(f" {idx}. {c['email']}\n    已用：{human_gib(used_c)} / 上限：{tot_str}\n")
        
        all_clients_opt = str(len(clients) + 2)
        if clients:
            print(f" {all_clients_opt}. 逐个校准该入站下全部客户端")
            
        print("------------------------------------------------")
        print(" 0. 返回上级")
        print("================================================")
        
        valid_objs = {"0", "1"} | {str(i) for i in range(2, len(clients) + 2)}
        if clients: valid_objs.add(all_clients_opt)
        
        obj_choice = input_choice("请选择对象： ", valid_objs, allow_quit=False)
        if obj_choice == "0":
            break
            
        targets = []
        if obj_choice == "1":
            targets.append({"type": "inbounds", "id": iid, "label": f"入站 ID={iid}", "up": inbound["up"], "down": inbound["down"]})
        elif obj_choice == all_clients_opt:
            for c in clients:
                targets.append({"type": "client_traffics", "id": c["id"], "label": f"{c['email']}", "up": c["up"], "down": c["down"]})
        else:
            c = clients[int(obj_choice) - 2]
            targets.append({"type": "client_traffics", "id": c["id"], "label": f"{c['email']}", "up": c["up"], "down": c["down"]})
            
        writes = []
        for t in targets:
            clear()
            print("================================================")
            print("输入校准流量")
            print("================================================")
            print(f"对象：{t['label']}")
            print(f"当前已用：{human_gib((t['up'] or 0) + (t['down'] or 0))}")
            print()
            print("请选择写入方式：")
            print(" 1. 输入总已用流量，全部写入 down")
            print(" 2. 输入总已用流量，按当前 up/down 比例分配")
            print(" 3. 分别输入 up 和 down")
            print("------------------------------------------------")
            print(" 0. 返回上级")
            print("================================================")
            mode = input_choice("请选择： ", {"0", "1", "2", "3"}, allow_quit=False)
            if mode == "0":
                writes = []
                break
                
            try:
                if mode in ("1", "2"):
                    tot_val = input("请输入总已用流量 (GiB): ").strip()
                    tot_bytes = to_bytes(tot_val)
                    if mode == "1":
                        w_up, w_down = 0, tot_bytes
                    else:
                        cur_tot = int(t['up'] or 0) + int(t['down'] or 0)
                        if cur_tot <= 0:
                            w_up, w_down = 0, tot_bytes
                        else:
                            w_up = int(Decimal(tot_bytes) * Decimal(t['up'] or 0) / Decimal(cur_tot))
                            w_down = tot_bytes - w_up
                else:
                    up_val = input("请输入上传 up 流量 (GiB): ").strip()
                    down_val = input("请输入下载 down 流量 (GiB): ").strip()
                    w_up = to_bytes(up_val)
                    w_down = to_bytes(down_val)
                writes.append((t["type"], t["id"], w_up, w_down))
            except Exception as e:
                print(f"输入无效: {e}")
                writes = []
                break
        
        if not writes:
            continue
            
        ans = input("\n确认写入数据库？(写库前会自动备份并停启服务) 请输入 YES: ").strip()
        if ans == "YES":
            for w in writes:
                print(f"准备写入 {w[0]} id={w[1]} up={w[2]} down={w[3]}")
            conn.close()
            with open("/tmp/xui_traffic_writes.json", "w") as f:
                json.dump(writes, f)
            sys.exit(200) # 通知 bash 执行写库
PY

    if [ ! -t 0 ]; then echo "需要交互式终端"; return 1; fi
    set +e
    XUI_DB="$XUI_DB" python3 "$tmp_py" < /dev/tty
    local ret=$?
    rm -f "$tmp_py"
    set -e

    if [ "$ret" -eq 100 ]; then
        return 0
    elif [ "$ret" -eq 200 ] && [ -f /tmp/xui_traffic_writes.json ]; then
        echo "正在备份并写入数据库..."
        systemctl stop x-ui || true
        backup_all
        
        python3 -c "
import json, sqlite3, sys
try:
    writes = json.load(open('/tmp/xui_traffic_writes.json'))
    conn = sqlite3.connect('$XUI_DB')
    cur = conn.cursor()
    for w in writes:
        table, tid, up, down = w
        cur.execute(f'UPDATE {table} SET up=?, down=? WHERE id=?', (up, down, tid))
    conn.commit()
    conn.close()
    print('写入成功。')
except Exception as e:
    print(f'写入失败: {e}')
    sys.exit(1)
"
        rm -f /tmp/xui_traffic_writes.json
        systemctl start x-ui
        pause
    fi
}

# --- 后台重置引擎 (支持 dry-run) ---

run_reset_engine() {
    install_runtime_deps
    XUI_DB="$XUI_DB" CONFIG_FILE="$CONFIG_FILE" RESET_STATE="$RESET_STATE" DRY_RUN="$DRY_RUN" BACKUP_DIR="$BACKUP_DIR" python3 <<'PY'
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

db_path = Path(os.environ["XUI_DB"])
config_path = Path(os.environ["CONFIG_FILE"])
state_path = Path(os.environ["RESET_STATE"])
backup_dir = Path(os.environ["BACKUP_DIR"])
dry_run = os.environ.get("DRY_RUN") == "1"

def load_json(path, default):
    if not path.exists(): return default
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        print(f"解析 {path} 失败，将使用默认值。")
        return default

def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, path)
    os.chmod(path, 0o600)

config = load_json(config_path, {})
state = load_json(state_path, {"schema_version": 1, "inbounds": {}, "clients": {}})
state.setdefault("inbounds", {})
state.setdefault("clients", {})

if dry_run:
    print("================================================")
    print("本次重置预览")
    print("================================================")
    print(f"日期：{date.today().isoformat()}")
    print("模式：dry-run，只预览，不写数据库\n")

if not config.get("enabled", False):
    if dry_run: print("全局未启用自定义重置。")
    sys.exit(0)

today = date.today()
cur_month_str = today.strftime("%Y-%m")

def get_effective_day(year, month, configured_day):
    last_day = calendar.monthrange(year, month)[1]
    return min(int(configured_day), last_day)

def should_reset(configured_day, state_record):
    if not configured_day or configured_day <= 0: return False, "未设置有效日期"
    eff_day = get_effective_day(today.year, today.month, configured_day)
    if today.day < eff_day:
        return False, f"未到本月重置日 (有效日:{eff_day})"
    if state_record.get("last_reset_month") == cur_month_str:
        return False, f"本月已在 {state_record.get('last_reset_date')} 重置过"
    return True, f"每月 {configured_day} 号 (有效日:{eff_day})，本月尚未重置"

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    inbounds = conn.execute("SELECT id, remark, port, traffic_reset FROM inbounds ORDER BY id").fetchall()
    clients = conn.execute("SELECT id, inbound_id, email FROM client_traffics ORDER BY id").fetchall()
except Exception as e:
    print(f"数据库读取失败: {e}")
    sys.exit(1)

plan_inbounds = []
plan_clients = []
warnings = []
skip_msgs = []

for inbound in inbounds:
    iid = str(inbound["id"])
    cfg = config.get("inbounds", {}).get(iid, {})
    if not cfg.get("enabled"): continue
    
    if inbound["traffic_reset"] == "monthly":
        warnings.append(f"入站 ID={iid} 仍启用面板原生 monthly。建议改为 never/不重置。")
        
    inb_day = cfg.get("day", config.get("default_day", 1))
    inb_state = state["inbounds"].get(iid, {})
    
    inb_due, inb_reason = should_reset(inb_day, inb_state)
    remark_str = (inbound["remark"] or "无")[:15]
    
    if inb_due:
        if cfg.get("reset_inbound", True):
            plan_inbounds.append((iid, f"入站 ID={iid}，端口={inbound['port']}，备注={remark_str}", inb_reason))
            
        if cfg.get("reset_clients_without_custom_day", True):
            for c in clients:
                if str(c["inbound_id"]) == iid:
                    email = c["email"]
                    c_cfg = cfg.get("clients", {}).get(email, {})
                    if not (c_cfg.get("enabled") and c_cfg.get("day", 0) > 0):
                        ckey = f"{iid}|{email}"
                        c_state = state["clients"].get(ckey, {})
                        if c_state.get("last_reset_month") != cur_month_str:
                            plan_clients.append((iid, email, ckey, f"跟随入站，{inb_reason}"))
    else:
        skip_msgs.append(f"入站 ID={iid}\n    原因：{inb_reason}")

    for email, c_cfg in cfg.get("clients", {}).items():
        if not c_cfg.get("enabled"): continue
        c_day = c_cfg.get("day", 0)
        if c_day <= 0: continue
        
        ckey = f"{iid}|{email}"
        c_state = state["clients"].get(ckey, {})
        c_due, c_reason = should_reset(c_day, c_state)
        
        if c_due:
            plan_clients.append((iid, email, ckey, f"客户端独立设置，{c_reason}"))
        else:
            skip_msgs.append(f"客户端 {email} (入站 ID={iid})\n    原因：{c_reason}")

if dry_run:
    print("将重置：")
    if not plan_inbounds and not plan_clients:
        print("  (无)")
    for p in plan_inbounds:
        print(f"  {p[1]}\n    原因：{p[2]}")
    for p in plan_clients:
        print(f"  客户端 {p[1]}，入站 ID={p[0]}\n    原因：{p[3]}")
        
    print("\n不会重置：")
    if not skip_msgs:
        print("  (无)")
    for msg in skip_msgs:
        print(f"  {msg}")
        
    if warnings:
        print("\n提醒：")
        for w in warnings:
            print(f"  {w}")
    print("================================================")
    conn.close()
    sys.exit(0)

if not plan_inbounds and not plan_clients:
    if warnings:
        for w in warnings: print(w)
    conn.close()
    sys.exit(0)

print("准备执行重置任务...")
backup_dir.mkdir(parents=True, exist_ok=True)
ts = time.strftime('%Y-%m-%d_%H%M%S')
backup_path = backup_dir / f"x-ui.db.{ts}.bak"

subprocess.run(["systemctl", "stop", "x-ui"], check=False)
try:
    shutil.copy2(db_path, backup_path)
    cur = conn.cursor()
    
    for p in plan_inbounds:
        cur.execute("UPDATE inbounds SET up=0, down=0 WHERE id=?", (p[0],))
        state["inbounds"][p[0]] = {"last_reset_month": cur_month_str, "last_reset_date": today.isoformat()}
        
    for p in plan_clients:
        cur.execute("UPDATE client_traffics SET up=0, down=0 WHERE inbound_id=? AND email=?", (p[0], p[1]))
        state["clients"][p[2]] = {"last_reset_month": cur_month_str, "last_reset_date": today.isoformat()}
        
    conn.commit()
    save_json(state_path, state)
    print("数据库写入与状态更新成功。")
except Exception as e:
    conn.rollback()
    print(f"执行重置异常：{e}")
finally:
    conn.close()
    subprocess.run(["systemctl", "start", "x-ui"], check=False)
PY
}

# --- 菜单框架 ---

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
            1) tail -n 100 "$LOG_FILE" || true; pause;;
            2) journalctl -u xui-custom-reset.service -n 100 --no-pager || true; pause;;
            3) journalctl -u x-ui -n 100 --no-pager || true; pause;;
            0) return;;
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
        echo " 1. 立即备份 (数据库/配置/程序)"
        echo " 2. 恢复数据库"
        echo " 3. 恢复配置目录"
        echo " 4. 恢复程序目录"
        echo "------------------------------------------------"
        echo " 0. 返回主菜单"
        echo "================================================"
        read -rp "请选择： " choice
        case "$choice" in
            1) backup_all; pause;;
            2) restore_backup "db"; pause;;
            3) restore_backup "etc"; pause;;
            4) restore_backup "program"; pause;;
            0) return;;
        esac
    done
}

main_menu() {
    register_xcm_shortcut
    while true; do
        clear_screen
        local is_timer_active
        if systemctl is-active --quiet xui-custom-reset.timer; then
            is_timer_active="已启用"
        else
            is_timer_active="未启用"
        fi
        
        echo "================================================"
        echo "x-ui 自定义管理器"
        echo "================================================"
        echo "用于自定义重置日期、流量校准、备份恢复和健康检查。"
        echo ""
        echo "配置：$CONFIG_FILE"
        echo "备份：$BACKUP_DIR"
        echo "日志：$LOG_FILE"
        echo "自动检查：$is_timer_active"
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
            1) run_custom_reset_ui ;;
            2) run_edit_traffic_ui ;;
            3) menu_backup_restore ;;
            4) health_check; pause ;;
            5) menu_logs ;;
            6) cleanup_backups; pause ;;
            0) clear_screen; exit 0 ;;
            *) echo -e "${RED}无效选择。${PLAIN}"; pause ;;
        esac
    done
}

# --- 入口解析 ---

DRY_RUN=0
RUN_CHECK=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --reset-check) RUN_CHECK=1 ;;
        --dry-run) DRY_RUN=1 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

if [ "$RUN_CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    export DRY_RUN
    run_reset_engine
else
    main_menu
fi