#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/xui-custom-manager.conf}"

GITHUB_USER="${GITHUB_USER:-Chunlion}"
REPO_NAME="${REPO_NAME:-3x-ui}"
CUSTOM_BRANCH="${CUSTOM_BRANCH:-release/custom}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/MHSanaei/3x-ui.git}"

WORKDIR="${WORKDIR:-/root/3x-ui-custom}"
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

GO_VERSION="${GO_VERSION:-1.22.12}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/etc/xui-custom-manager.conf
    source "$CONFIG_FILE"
fi

GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
ORIGIN_REPO="${ORIGIN_REPO:-https://github.com/${GITHUB_USER}/${REPO_NAME}.git}"

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

install_deps() {
    echo "安装依赖..."
    apt update
    apt install -y git curl ca-certificates build-essential sqlite3 python3
}

install_runtime_deps() {
    echo "安装运行依赖..."
    apt update
    apt install -y sqlite3 python3
}

install_go_if_needed() {
    if command -v go >/dev/null 2>&1; then
        echo "已检测到 Go：$(go version)"
        return
    fi

    if [ -d /usr/local/go ]; then
        echo "检测到 /usr/local/go 已存在，但当前 PATH 中没有 go。"
        echo "请先确认 Go 目录状态，或把 /usr/local/go/bin 加入 PATH 后重新运行。"
        exit 1
    fi

    echo "未检测到 Go，安装 Go ${GO_VERSION}..."
    cd /tmp
    curl -L -o "$GO_TARBALL" "$GO_URL"
    tar -C /usr/local -xzf "$GO_TARBALL"

    cat >/etc/profile.d/go.sh <<'EOF'
export PATH=/usr/local/go/bin:$PATH
EOF

    export PATH="/usr/local/go/bin:$PATH"
    echo "Go 安装完成：$(go version)"
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
    echo "$label 备份超过保留数量 $keep，以下旧备份可清理："
    printf '  %s\n' "${delete_files[@]}"

    for file in "${delete_files[@]}"; do
        if [ -f "$file" ]; then
            confirm_action "删除旧备份文件：$file" || continue
            echo "删除旧备份：$file"
            rm -f -- "$file"
        fi
    done
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

clone_or_update_repo() {
    echo "准备源码目录：$WORKDIR"

    if [ ! -d "$WORKDIR/.git" ]; then
        if [ -e "$WORKDIR" ]; then
            echo "$WORKDIR 已存在但不是 Git 仓库。为避免误删，请手动处理后重试。"
            exit 1
        fi
        git clone "$ORIGIN_REPO" "$WORKDIR"
    fi

    cd "$WORKDIR"

    if ! git remote get-url origin >/dev/null 2>&1; then
        git remote add origin "$ORIGIN_REPO"
    else
        git remote set-url origin "$ORIGIN_REPO"
    fi

    if ! git remote get-url upstream >/dev/null 2>&1; then
        git remote add upstream "$UPSTREAM_REPO"
    fi

    git fetch origin
    git checkout "$CUSTOM_BRANCH"
    confirm_action "将 $WORKDIR 重置到 origin/${CUSTOM_BRANCH}" || exit 1
    git reset --hard "origin/${CUSTOM_BRANCH}"

    echo "当前分支：$(git branch --show-current)"
    echo "当前提交：$(git log --oneline -1)"
}

build_xui() {
    cd "$WORKDIR"
    export PATH="/usr/local/go/bin:$PATH"

    echo "下载 Go 依赖..."
    go mod download

    echo "编译 x-ui..."
    go build -trimpath -ldflags "-s -w" -o /tmp/x-ui-custom-build main.go

    ls -lh /tmp/x-ui-custom-build
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

deploy_xui() {
    confirm_action "停止 x-ui 并覆盖安装 $XUI_BIN" || return

    echo "停止 x-ui..."
    systemctl stop x-ui || true

    backup_all

    echo "覆盖安装自定义 x-ui..."
    install -m 755 /tmp/x-ui-custom-build "$XUI_BIN"

    echo "启动 x-ui..."
    systemctl start x-ui

    show_service_status_and_logs
    health_check || true
}

build_and_deploy() {
    need_root
    install_deps
    install_go_if_needed
    clone_or_update_repo
    build_xui
    deploy_xui
    echo
    echo "完成。请打开面板并强制刷新页面。"
}

sync_upstream() {
    need_root
    install_deps

    if [ ! -d "$WORKDIR/.git" ]; then
        if [ -e "$WORKDIR" ]; then
            echo "$WORKDIR 已存在但不是 Git 仓库。为避免误删，请手动处理后重试。"
            exit 1
        fi
        git clone "$ORIGIN_REPO" "$WORKDIR"
    fi

    cd "$WORKDIR"

    git remote set-url origin "$ORIGIN_REPO"

    if ! git remote get-url upstream >/dev/null 2>&1; then
        git remote add upstream "$UPSTREAM_REPO"
    fi

    echo "拉取 origin 和 upstream..."
    git fetch origin
    git fetch upstream

    echo "同步 main 到 upstream/main..."
    git checkout main || git checkout -b main origin/main
    confirm_action "将 main 重置到 origin/main 并 fast-forward 合并 upstream/main" || exit 1
    git reset --hard origin/main
    git merge --ff-only upstream/main || {
        echo "main 无法 fast-forward 合并 upstream/main，请手动处理。"
        exit 1
    }

    echo "推送 main 到你的 fork..."
    git push origin main

    echo "rebase 自定义分支 $CUSTOM_BRANCH 到 main..."
    git checkout "$CUSTOM_BRANCH"
    confirm_action "将 $CUSTOM_BRANCH 重置到 origin/${CUSTOM_BRANCH} 并 rebase 到 main" || exit 1
    git reset --hard "origin/${CUSTOM_BRANCH}"
    git rebase main || {
        echo
        echo "rebase 出现冲突。请进入 $WORKDIR 手动解决："
        echo "cd $WORKDIR"
        echo "git status"
        echo "解决冲突后：git add . && git rebase --continue"
        echo "完成后再运行：git push --force-with-lease origin $CUSTOM_BRANCH"
        exit 1
    }

    echo "推送自定义分支..."
    git push --force-with-lease origin "$CUSTOM_BRANCH"

    echo "同步完成。"
}

show_traffic() {
    if [ ! -f "$XUI_DB" ]; then
        echo "未找到数据库：$XUI_DB"
        return
    fi

    echo
    echo "入站流量："
    sqlite3 -header -column "$XUI_DB" "
SELECT id, remark, port, up, down, up + down AS used, total, traffic_reset, last_traffic_reset_time
FROM inbounds;
"

    echo
    echo "客户端流量："

    if sqlite3 "$XUI_DB" "PRAGMA table_info(client_traffics);" | awk -F'|' '$2=="all_time"{found=1} END{exit !found}'; then
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
        "reset_clients_without_custom_day": True,
        "clients": {},
    })
    inbound_cfg.setdefault("enabled", True)
    inbound_cfg.setdefault("day", config.get("default_day", 1))
    inbound_cfg.setdefault("reset_inbound", True)
    inbound_cfg.setdefault("reset_clients_without_custom_day", True)
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
        print(f"4) 重置未单独设置日期的客户端：{inbound_cfg.get('reset_clients_without_custom_day', True)}")
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
                "是否重置未单独设置日期的客户端 up/down？",
                bool(inbound_cfg.get("reset_clients_without_custom_day", True)),
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

    XUI_DB="$XUI_DB" BACKUP_DIR="$BACKUP_DIR" RESET_CONFIG="$RESET_CONFIG" RESET_STATE="$RESET_STATE" python3 <<'PY'
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

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

inbounds = cur.execute("SELECT id, up, down FROM inbounds ORDER BY id").fetchall()
clients = cur.execute("SELECT inbound_id, email, up, down FROM client_traffics ORDER BY inbound_id, email").fetchall()
clients_by_inbound = {}
existing_client_keys = set()
for client in clients:
    inbound_key = str(client["inbound_id"])
    clients_by_inbound.setdefault(inbound_key, []).append(client)
    existing_client_keys.add(f"{inbound_key}|{client['email']}")

planned_inbounds = []
planned_clients = []
default_day = int(config.get("default_day", 1) or 1)
configured_inbounds = config.get("inbounds", {})

for inbound in inbounds:
    inbound_id = str(inbound["id"])
    inbound_cfg = configured_inbounds.get(inbound_id, {})
    if not inbound_cfg.get("enabled", False):
        continue
    inbound_day = int(inbound_cfg.get("day", default_day) or default_day)
    client_cfgs = inbound_cfg.get("clients", {})
    has_inbound_due = is_due(today, inbound_day)

    if has_inbound_due and state["inbounds"].get(inbound_id) != today_text and inbound_cfg.get("reset_inbound", True):
        planned_inbounds.append(inbound_id)

    if has_inbound_due and inbound_cfg.get("reset_clients_without_custom_day", True):
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

if not planned_inbounds and not planned_clients:
    print(f"{today_text} 没有需要执行的自定义重置。")
    conn.close()
    sys.exit(0)

print(f"{today_text} 准备执行自定义重置：")
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
    save_json(state_path, state)
    print("自定义重置执行完成。")
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

    echo
    echo "检测原版 monthly 自动重置入站："
    local monthly_rows
    monthly_rows="$(sqlite3 -header -column "$XUI_DB" "
SELECT id, remark, port, traffic_reset
FROM inbounds
WHERE traffic_reset = 'monthly'
ORDER BY id;
" || true)"

    if ! echo "$monthly_rows" | grep -q "monthly"; then
        echo "未检测到 traffic_reset='monthly' 的入站。"
        return
    fi

    echo "$monthly_rows"
    confirm_action "将上述入站 traffic_reset 从 monthly 改为 never，交由外置脚本管理" || return

    systemctl stop x-ui || true
    backup_all no

    local integrity_result
    integrity_result="$(sqlite3 "$XUI_DB" "PRAGMA integrity_check;" 2>&1 || true)"
    if [ "$integrity_result" != "ok" ]; then
        echo "修改前数据库完整性检查失败：$integrity_result"
        systemctl start x-ui
        return 1
    fi
    sqlite3 "$XUI_DB" "
UPDATE inbounds
SET traffic_reset = 'never'
WHERE traffic_reset = 'monthly';
"
    integrity_result="$(sqlite3 "$XUI_DB" "PRAGMA integrity_check;" 2>&1 || true)"
    if [ "$integrity_result" != "ok" ]; then
        echo "修改后数据库完整性检查失败：$integrity_result"
        systemctl start x-ui
        return 1
    fi

    systemctl start x-ui
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
    backup_all

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
SELECT id, remark, port, up, down, total, traffic_reset, last_traffic_reset_time
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
    print("请选择客户端修改范围：")
    print("0) 只修改入站总流量，不修改客户端")
    print("A) 修改入站总流量，并同步修改该入站下所有客户端")

    for idx, row in enumerate(clients, start=1):
        used = int(row["up"] or 0) + int(row["down"] or 0)
        total = int(row["total"] or 0)
        print(
            f"{idx}) 客户端={row['email']} | "
            f"已用={human_size(used)} | 上行={human_size(row['up'])} | 下行={human_size(row['down'])} | "
            f"上限={human_size(total)}"
        )

    valid_client_choices = {"0", "A", "a"} | {str(i) for i in range(1, len(clients) + 1)}
    client_choice = input_choice("\n输入编号选择客户端，A=全部客户端，0=只改入站，q=退出： ", valid_client_choices)

    if client_choice == "0":
        client_mode = "inbound_only"
        selected_clients = []
    elif client_choice.lower() == "a":
        client_mode = "all"
        selected_clients = clients
    else:
        client_mode = "single"
        selected_clients = [clients[int(client_choice) - 1]]

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

    while True:
        try:
            if input_mode == "1":
                up_value = input(f"\n请输入上传流量数值（{unit_label}），例如 54.25： ").strip()
                down_value = input(f"请输入下载流量数值（{unit_label}），例如 59.51： ").strip()
                up_bytes = to_bytes(up_value, unit)
                down_bytes = to_bytes(down_value, unit)
                input_summary = f"上传={up_value}{unit_label}，下载={down_value}{unit_label}"
            else:
                total_value = input(f"\n请输入总流量数值（{unit_label}），例如 113.76： ").strip()
                used_bytes = to_bytes(total_value, unit)
                if input_mode == "2":
                    up_bytes = 0
                    down_bytes = used_bytes
                else:
                    up_bytes, down_bytes = split_by_ratio(used_bytes, inbound["up"], inbound["down"])
                input_summary = f"总流量={total_value}{unit_label}"
            break
        except Exception as exc:
            print(f"流量数值格式不正确：{exc}")

    used_bytes = up_bytes + down_bytes

    print()
    update_all_time = input("是否同时把累计总流量 all_time 改为 上传+下载？[Y/n] ").strip().lower()
    update_all_time = update_all_time not in ("n", "no")

    print()
    print("即将写入：")
    print(f"入站 ID：{inbound_id}")
    print(f"输入：{input_summary}")
    print(f"上传：{up_bytes} bytes = {human_size(up_bytes)}")
    print(f"下载：{down_bytes} bytes = {human_size(down_bytes)}")
    print(f"合计：{used_bytes} bytes = {human_size(used_bytes)}")
    print(f"修改累计总流量 all_time：{'是' if update_all_time else '否'}")

    if client_mode == "inbound_only":
        print("客户端修改范围：不修改客户端，只改入站")
    elif client_mode == "all":
        print("客户端修改范围：该入站下全部客户端")
        for c in selected_clients:
            print(f"  - {c['email']}")
    else:
        print("客户端修改范围：指定客户端")
        for c in selected_clients:
            print(f"  - {c['email']}")

    confirm = input("\n确认写入数据库？请输入 YES： ").strip()
    if confirm != "YES":
        print("已取消，没有修改数据库。")
        sys.exit(0)

    cur.execute(
        "UPDATE inbounds SET up = ?, down = ? WHERE id = ?",
        (up_bytes, down_bytes, inbound_id)
    )

    if update_all_time and has_column(cur, "inbounds", "all_time"):
        cur.execute(
            "UPDATE inbounds SET all_time = ? WHERE id = ?",
            (used_bytes, inbound_id)
        )

    if client_mode == "all":
        cur.execute(
            "UPDATE client_traffics SET up = ?, down = ? WHERE inbound_id = ?",
            (up_bytes, down_bytes, inbound_id)
        )

        if update_all_time and has_column(cur, "client_traffics", "all_time"):
            cur.execute(
                "UPDATE client_traffics SET all_time = ? WHERE inbound_id = ?",
                (used_bytes, inbound_id)
            )

    elif client_mode == "single":
        client_id = int(selected_clients[0]["id"])

        cur.execute(
            "UPDATE client_traffics SET up = ?, down = ? WHERE id = ?",
            (up_bytes, down_bytes, client_id)
        )

        if update_all_time and has_column(cur, "client_traffics", "all_time"):
            cur.execute(
                "UPDATE client_traffics SET all_time = ? WHERE id = ?",
                (used_bytes, client_id)
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
        echo "x-ui 自定义版管理脚本"
        echo "作者 fork：${GITHUB_USER}/${REPO_NAME}"
        echo "自定义分支：${CUSTOM_BRANCH}"
        echo "源码目录：${WORKDIR}"
        echo "备份目录：${BACKUP_DIR}"
        echo "日志文件：${LOG_FILE}"
        echo "重置配置：${RESET_CONFIG}"
        echo
        echo "1) 自定义每月重置日期设置"
        echo "2) 手动执行一次自定义重置检查"
        echo "3) 安装/更新自定义重置 systemd timer"
        echo "4) 查看自定义重置日志"
        echo "5) 禁用 3x-ui 原版 monthly 自动重置"
        echo "6) 手动重置流量 / 修改流量上限 total"
        echo "7) 查看当前流量数据"
        echo "8) 修改流量数据（校准 up/down）"
        echo "9) 备份 x-ui 数据/配置/程序"
        echo "10) 恢复程序备份"
        echo "11) 恢复数据库备份"
        echo "12) 执行健康检查"
        echo "13) 清理旧备份"
        echo "0) 退出"
        echo
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
                echo "无效选择。"
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
