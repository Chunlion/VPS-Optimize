#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROGRAM_NAME="aliyun-cdt-watchdog"
readonly INSTALL_DIR="/opt/${PROGRAM_NAME}"
readonly VENV_DIR="${INSTALL_DIR}/venv"
readonly APP_FILE="${INSTALL_DIR}/watchdog.py"
readonly ENV_FILE="/etc/${PROGRAM_NAME}.env"
readonly SERVICE_FILE="/etc/systemd/system/${PROGRAM_NAME}.service"
readonly TIMER_FILE="/etc/systemd/system/${PROGRAM_NAME}.timer"
readonly MANAGER_FILE="/usr/local/sbin/${PROGRAM_NAME}"
readonly SERVICE_NAME="${PROGRAM_NAME}.service"
readonly TIMER_NAME="${PROGRAM_NAME}.timer"
readonly SCRIPT_URL="https://raw.githubusercontent.com/Chunlion/VPS-Optimize/refs/heads/main/aliyun-cdt-watchdog.sh"

info() {
    printf '[INFO] %s\n' "$*"
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

on_error() {
    local exit_code=$?
    local line=${BASH_LINENO[0]:-未知}
    trap - ERR
    error "操作失败（行 ${line}，退出码 ${exit_code}）。"
    exit "${exit_code}"
}

trap on_error ERR

usage() {
    cat <<'EOF'
用法：
  sudo bash aliyun-cdt-watchdog.sh [install]
  sudo aliyun-cdt-watchdog status
  sudo aliyun-cdt-watchdog log [行数]
  sudo aliyun-cdt-watchdog run
  sudo aliyun-cdt-watchdog uninstall [--yes]

子命令：
  install     交互安装或重新配置（默认）
  status      查看定时器、服务和最近一次执行结果
  log         查看最近日志，默认 100 行
  run         立即执行一次流量检查及启停控制
  uninstall   删除服务、定时器、程序和密钥配置
EOF
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die "请使用 root 运行，例如：sudo bash $0 ${1:-install}"
}

require_supported_os() {
    [[ -r /etc/os-release ]] || die "无法识别操作系统。仅支持 Debian/Ubuntu。"
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) ;;
        *) die "当前系统 ${ID:-unknown} 不受支持。仅支持 Debian/Ubuntu。" ;;
    esac
    command -v apt-get >/dev/null 2>&1 || die "未找到 apt-get。"
    command -v systemctl >/dev/null 2>&1 || die "未找到 systemctl。"
}

read_input() {
    local variable_name=$1
    local prompt=$2
    local secret=${3:-false}
    if [[ -r /dev/tty ]]; then
        if [[ ${secret} == true ]]; then
            IFS= read -r -s -p "${prompt}" "${variable_name}" </dev/tty
        else
            IFS= read -r -p "${prompt}" "${variable_name}" </dev/tty
        fi
    elif [[ ${secret} == true ]]; then
        IFS= read -r -s -p "${prompt}" "${variable_name}"
    else
        IFS= read -r -p "${prompt}" "${variable_name}"
    fi
}

prompt_nonempty() {
    local prompt=$1
    local value
    while true; do
        read_input value "${prompt}: " || die "输入已取消。"
        [[ -n ${value} ]] && {
            printf '%s' "${value}"
            return
        }
        error "不能留空。"
    done
}

prompt_secret() {
    local first second
    while true; do
        read_input first "新的 AccessKey Secret: " true || die "输入已取消。"
        printf '\n' >&2
        read_input second "再次输入 AccessKey Secret: " true || die "输入已取消。"
        printf '\n' >&2
        [[ -n ${first} ]] || {
            error "AccessKey Secret 不能为空。"
            continue
        }
        [[ ${first} == "${second}" ]] || {
            error "两次输入不一致。"
            continue
        }
        [[ ${first} =~ ^[A-Za-z0-9]+$ ]] || {
            error "AccessKey Secret 格式无效，只允许字母和数字。"
            continue
        }
        printf '%s' "${first}"
        return
    done
}

validate_inputs() {
    [[ ${ACCESS_KEY_ID} =~ ^[A-Za-z0-9]+$ ]] || die "AccessKey ID 格式无效。"
    [[ ${REGION_ID} =~ ^[a-z0-9-]+$ ]] || die "Region ID 格式无效，例如 cn-hongkong。"
    [[ ${INSTANCE_ID} =~ ^i-[A-Za-z0-9]+$ ]] || die "ECS Instance ID 格式无效，例如 i-bp1234567890。"
    [[ ${THRESHOLD_GB} =~ ^([0-9]+)(\.[0-9]+)?$ ]] || die "流量阈值必须是大于 0 的数字。"
    awk -v value="${THRESHOLD_GB}" 'BEGIN { exit !(value > 0) }' || die "流量阈值必须大于 0。"
}

write_python_app() {
    local output_file=${1:-${APP_FILE}}
    install -d -m 0700 "${INSTALL_DIR}"
    cat >"${output_file}" <<'PYTHON'
#!/usr/bin/env python3
import argparse
import json
import logging
import os
import sys
from decimal import Decimal, InvalidOperation

from aliyunsdkcore.client import AcsClient
from aliyunsdkcore.request import CommonRequest
from aliyunsdkecs.request.v20140526.DescribeInstancesRequest import DescribeInstancesRequest
from aliyunsdkecs.request.v20140526.StartInstanceRequest import StartInstanceRequest
from aliyunsdkecs.request.v20140526.StopInstanceRequest import StopInstanceRequest


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("aliyun-cdt-watchdog")


def required_env(name):
    value = os.environ.get(name)
    if not value:
        raise RuntimeError("缺少配置：{}".format(name))
    return value


def load_config():
    access_key_id = required_env("CDT_ACCESS_KEY_ID")
    access_key_secret = required_env("CDT_ACCESS_KEY_SECRET")
    region_id = required_env("CDT_REGION_ID")
    instance_id = required_env("CDT_INSTANCE_ID")
    try:
        threshold_gb = Decimal(required_env("CDT_THRESHOLD_GB"))
    except InvalidOperation as exc:
        raise RuntimeError("CDT_THRESHOLD_GB 不是有效数字") from exc
    if not threshold_gb.is_finite() or threshold_gb <= 0:
        raise RuntimeError("CDT_THRESHOLD_GB 必须是大于 0 的有限数字")
    return access_key_id, access_key_secret, region_id, instance_id, threshold_gb


def decode_response(response):
    try:
        payload = json.loads(response.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("阿里云 API 返回了无效的 JSON 响应") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("阿里云 API 响应格式异常")
    return payload


def get_total_traffic_gb(client, threshold_gb):
    request = CommonRequest()
    request.set_domain("cdt.aliyuncs.com")
    request.set_version("2021-08-13")
    request.set_action_name("ListCdtInternetTraffic")
    request.set_method("POST")
    payload = decode_response(client.do_action_with_exception(request))

    if "TrafficDetails" not in payload:
        raise RuntimeError("CDT 响应缺少 TrafficDetails；为避免误操作，已中止处理")
    details = payload["TrafficDetails"]
    if not isinstance(details, list):
        raise RuntimeError("CDT 响应中的 TrafficDetails 格式异常")

    total_bytes = Decimal(0)
    for index, detail in enumerate(details, start=1):
        if not isinstance(detail, dict) or "Traffic" not in detail:
            raise RuntimeError("CDT 流量明细第 {} 项格式异常".format(index))
        try:
            traffic = Decimal(str(detail["Traffic"]))
        except InvalidOperation as exc:
            raise RuntimeError("CDT 流量明细第 {} 项数值无效".format(index)) from exc
        if not traffic.is_finite() or traffic < 0:
            raise RuntimeError("CDT 流量明细第 {} 项不是有效的非负数".format(index))
        total_bytes += traffic

    total_gb = total_bytes / Decimal(1024 ** 3)
    logger.info("当前 CDT 公网累计流量：%.2f GiB；阈值：%.2f GiB", total_gb, threshold_gb)
    return total_gb


def get_instance(client, instance_id):
    request = DescribeInstancesRequest()
    request.set_InstanceIds(json.dumps([instance_id]))
    request.set_accept_format("json")
    payload = decode_response(client.do_action_with_exception(request))
    instances = payload.get("Instances", {}).get("Instance", [])
    if not isinstance(instances, list) or len(instances) != 1:
        raise RuntimeError("未找到唯一的 ECS 实例：{}".format(instance_id))
    instance = instances[0]
    if not isinstance(instance, dict) or instance.get("InstanceId") != instance_id:
        raise RuntimeError("ECS 实例查询响应与目标实例不匹配")
    return instance


def start_instance(client, instance_id):
    request = StartInstanceRequest()
    request.set_InstanceId(instance_id)
    request.set_accept_format("json")
    client.do_action_with_exception(request)
    logger.info("已提交启动请求：%s", instance_id)


def stop_instance(client, instance_id):
    request = StopInstanceRequest()
    request.set_InstanceId(instance_id)
    request.set_ForceStop(False)
    request.set_StoppedMode("StopCharging")
    request.set_accept_format("json")
    client.do_action_with_exception(request)
    logger.warning("已提交节省停机请求：%s", instance_id)


def run(check_only=False):
    access_key_id, access_key_secret, region_id, instance_id, threshold_gb = load_config()
    client = AcsClient(access_key_id, access_key_secret, region_id)
    total_gb = get_total_traffic_gb(client, threshold_gb)
    instance = get_instance(client, instance_id)
    status = instance.get("Status")
    stopped_mode = instance.get("StoppedMode", "unknown")
    logger.info("ECS %s 状态：%s；停机模式：%s", instance_id, status, stopped_mode)

    if check_only:
        logger.info("只读检查通过，未执行启动或停止操作。")
        return

    if total_gb < threshold_gb:
        if status == "Stopped":
            start_instance(client, instance_id)
        elif status in ("Running", "Starting"):
            logger.info("流量低于阈值，实例已运行或正在启动，无需操作。")
        else:
            logger.warning("流量低于阈值，但实例状态为 %s；本次不操作。", status)
    else:
        if status == "Running":
            stop_instance(client, instance_id)
        elif status in ("Stopped", "Stopping"):
            logger.info("流量达到阈值，实例已停止或正在停止，无需操作。")
        else:
            logger.warning("流量达到阈值，但实例状态为 %s；本次不操作。", status)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只读验证配置和 API")
    args = parser.parse_args()
    try:
        run(check_only=args.check)
    except Exception as exc:
        logger.error("执行失败：%s: %s", type(exc).__name__, exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON
    chmod 0700 "${output_file}"
}

write_environment() {
    umask 077
    cat >"${ENV_FILE}" <<EOF
CDT_ACCESS_KEY_ID=${ACCESS_KEY_ID}
CDT_ACCESS_KEY_SECRET=${ACCESS_KEY_SECRET}
CDT_REGION_ID=${REGION_ID}
CDT_INSTANCE_ID=${INSTANCE_ID}
CDT_THRESHOLD_GB=${THRESHOLD_GB}
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
EOF
    chown root:root "${ENV_FILE}"
    chmod 0600 "${ENV_FILE}"
}

write_systemd_units() {
    cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=Aliyun CDT ECS Watchdog
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/python ${APP_FILE}
User=root
Group=root
TimeoutStartSec=55s
UMask=0077
NoNewPrivileges=true
PrivateDevices=true
PrivateTmp=true
ProtectControlGroups=true
ProtectHome=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectSystem=strict
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

    cat >"${TIMER_FILE}" <<EOF
[Unit]
Description=Run Aliyun CDT ECS Watchdog Every Minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=10s
Persistent=true
Unit=${SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF

    chmod 0644 "${SERVICE_FILE}" "${TIMER_FILE}"
}

install_manager() {
    local source_path target_path temp_file
    source_path=$(readlink -f "${BASH_SOURCE[0]:-}" 2>/dev/null || true)
    target_path=$(readlink -f "${MANAGER_FILE}" 2>/dev/null || printf '%s' "${MANAGER_FILE}")
    install -d -m 0755 "$(dirname "${MANAGER_FILE}")"

    if [[ -n ${source_path} && -f ${source_path} ]]; then
        if [[ ${source_path} != "${target_path}" ]]; then
            install -m 0755 "${source_path}" "${MANAGER_FILE}"
        fi
        return
    fi

    command -v curl >/dev/null 2>&1 || die "通过直链运行时需要 curl 才能安装管理命令。"
    temp_file=$(mktemp)
    if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 "${SCRIPT_URL}" -o "${temp_file}"; then
        rm -f -- "${temp_file}"
        die "下载安装脚本失败。"
    fi
    if ! bash -n "${temp_file}"; then
        rm -f -- "${temp_file}"
        die "下载的安装脚本语法检查失败。"
    fi
    install -m 0755 "${temp_file}" "${MANAGER_FILE}"
    rm -f -- "${temp_file}"
}

check_candidate_config() {
    local candidate_app=$1
    info "执行只读 API 检查，不会启停 ECS。"
    CDT_ACCESS_KEY_ID="${ACCESS_KEY_ID}" \
        CDT_ACCESS_KEY_SECRET="${ACCESS_KEY_SECRET}" \
        CDT_REGION_ID="${REGION_ID}" \
        CDT_INSTANCE_ID="${INSTANCE_ID}" \
        CDT_THRESHOLD_GB="${THRESHOLD_GB}" \
        PYTHONDONTWRITEBYTECODE=1 \
        PYTHONUNBUFFERED=1 \
        "${VENV_DIR}/bin/python" "${candidate_app}" --check
}

install_watchdog() {
    local candidate_app
    require_root install
    require_supported_os

    info "请输入专用 RAM 用户的 AccessKey；不要继续使用曾经泄露的密钥。"
    ACCESS_KEY_ID=$(prompt_nonempty "AccessKey ID")
    ACCESS_KEY_SECRET=$(prompt_secret)
    REGION_ID=$(prompt_nonempty "ECS Region ID（例如 cn-hongkong）")
    INSTANCE_ID=$(prompt_nonempty "ECS Instance ID")
    read_input THRESHOLD_GB "CDT 公网流量阈值 GiB [180]: " || die "输入已取消。"
    THRESHOLD_GB=${THRESHOLD_GB:-180}
    validate_inputs

    info "安装系统依赖。"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends python3 python3-venv ca-certificates

    install -d -m 0700 "${INSTALL_DIR}"
    if [[ ! -x ${VENV_DIR}/bin/python ]]; then
        python3 -m venv "${VENV_DIR}"
    fi
    "${VENV_DIR}/bin/python" -m pip install --disable-pip-version-check --no-cache-dir --upgrade \
        aliyun-python-sdk-core aliyun-python-sdk-ecs

    candidate_app=$(mktemp "${INSTALL_DIR}/watchdog.py.XXXXXX")
    write_python_app "${candidate_app}"
    if ! check_candidate_config "${candidate_app}"; then
        rm -f -- "${candidate_app}"
        die "只读检查失败，现有密钥配置和定时器未修改。请检查 RAM 权限、Region、实例 ID 或密钥。"
    fi
    install_manager

    if systemctl list-unit-files "${TIMER_NAME}" --no-legend 2>/dev/null | grep -q "${TIMER_NAME}"; then
        systemctl disable --now "${TIMER_NAME}" >/dev/null 2>&1 || true
    fi

    install -m 0700 "${candidate_app}" "${APP_FILE}"
    rm -f -- "${candidate_app}"
    write_environment
    write_systemd_units
    systemctl daemon-reload
    systemctl enable --now "${TIMER_NAME}"
    info "安装完成。定时器每分钟检查一次。"
    printf '管理命令：%s {status|log|run|uninstall}\n' "${MANAGER_FILE}"
}

show_status() {
    require_root status
    [[ -f ${SERVICE_FILE} && -f ${TIMER_FILE} ]] || die "尚未安装。"
    printf 'timer enabled: %s\n' "$(systemctl is-enabled "${TIMER_NAME}" 2>/dev/null || true)"
    printf 'timer active:  %s\n' "$(systemctl is-active "${TIMER_NAME}" 2>/dev/null || true)"
    printf 'last service:  %s\n' "$(systemctl show "${SERVICE_NAME}" -p Result --value 2>/dev/null || true)"
    systemctl list-timers "${TIMER_NAME}" --no-pager || true
    journalctl -u "${SERVICE_NAME}" -n 10 --no-pager || true
}

show_log() {
    require_root log
    local lines=${1:-100}
    [[ ${lines} =~ ^[1-9][0-9]{0,5}$ ]] || die "日志行数必须是 1 到 999999 的整数。"
    journalctl -u "${SERVICE_NAME}" -n "${lines}" --no-pager
}

run_now() {
    require_root run
    [[ -f ${SERVICE_FILE} ]] || die "尚未安装。"
    if ! systemctl start "${SERVICE_NAME}"; then
        journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true
        die "立即检查失败。"
    fi
    journalctl -u "${SERVICE_NAME}" -n 20 --no-pager
}

uninstall_watchdog() {
    require_root uninstall
    local assume_yes=${1:-}
    if [[ ${assume_yes} != "--yes" ]]; then
        local answer
        read_input answer "将删除程序、定时器和包含密钥的配置，输入 YES 确认: " || die "输入已取消。"
        [[ ${answer} == "YES" ]] || die "已取消。"
    fi

    systemctl disable --now "${TIMER_NAME}" >/dev/null 2>&1 || true
    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    [[ -f ${SERVICE_FILE} ]] && rm -f -- "${SERVICE_FILE}"
    [[ -f ${TIMER_FILE} ]] && rm -f -- "${TIMER_FILE}"
    systemctl daemon-reload
    systemctl reset-failed "${SERVICE_NAME}" >/dev/null 2>&1 || true
    [[ -d ${INSTALL_DIR} ]] && rm -rf -- "${INSTALL_DIR}"
    if [[ -f ${ENV_FILE} ]]; then
        rm -f -- "${ENV_FILE}"
        info "已删除密钥配置 ${ENV_FILE}，无法恢复。"
    fi
    [[ -f ${MANAGER_FILE} ]] && rm -f -- "${MANAGER_FILE}"
    info "卸载完成。系统 Python 和已安装的软件包未移除。"
}

main() {
    local command=${1:-install}
    shift || true
    case "${command}" in
        install) install_watchdog "$@" ;;
        status) show_status "$@" ;;
        log) show_log "$@" ;;
        run) run_now "$@" ;;
        uninstall) uninstall_watchdog "$@" ;;
        help|-h|--help) usage ;;
        *) usage >&2; die "未知子命令：${command}" ;;
    esac
}

main "$@"
