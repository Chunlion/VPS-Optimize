#!/usr/bin/env bash
set -euo pipefail
trap 'echo "system-mirrors failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# shellcheck source=/dev/null
source src/common.sh
# shellcheck source=/dev/null
source src/language.sh
# shellcheck source=/dev/null
source src/ui.sh
# shellcheck source=/dev/null
source src/input.sh
# shellcheck source=/dev/null
source src/validate.sh
# shellcheck source=/dev/null
source src/system_core.sh

clear() { :; }
print_breadcrumb() { :; }
sleep() { :; }
pause_after_external_script() { :; }
system_package_mirror_host() { printf '%s' "mirrors.example.com"; }
mirror_status=0
mirror_call=()
run_remote_script() { mirror_call=("$@"); return "$mirror_status"; }
system_mirror_source_reachable() { return 0; }

# 目录结构：每站都有中英标签与地址，地址不含协议，且不重复。
mapfile -t catalog_all < <(for catalog_category in {1..7}; do system_mirror_catalog "$catalog_category"; done)
[[ "${#catalog_all[@]}" -ge 40 ]]
for catalog_entry in "${catalog_all[@]}"; do
    IFS='|' read -r catalog_zh catalog_en catalog_source <<<"$catalog_entry"
    [[ -n "$catalog_zh" && -n "$catalog_en" && -n "$catalog_source" ]]
    case "$catalog_source" in *://*) exit 1 ;; esac
done
[[ "$(printf '%s\n' "${catalog_all[@]}" | awk -F'|' '{print $3}' | sort -u | wc -l)" -eq "${#catalog_all[@]}" ]]

# 探测地址按发行版拼装；非 apt 系不探测。
OS=debian
VERSION_CODENAME=bookworm
[[ "$(system_mirror_repo_probe_url "mirrors.aliyun.com" "")" == "https://mirrors.aliyun.com/debian/dists/bookworm/Release" ]]
[[ "$(system_mirror_repo_probe_url "mirrors.aliyun.com" "rockylinux")" == "https://mirrors.aliyun.com/rockylinux/dists/bookworm/Release" ]]
OS=ubuntu
VERSION_CODENAME=noble
[[ "$(system_mirror_repo_probe_url "mirrors.aliyun.com" "")" == "https://mirrors.aliyun.com/ubuntu/dists/noble/Release" ]]
OS=rocky
if system_mirror_repo_probe_url "mirrors.aliyun.com" "" >/dev/null 2>&1; then
    echo 'A non-apt distribution must not build a probe URL.' >&2
    exit 1
fi
OS=debian
VERSION_CODENAME=bookworm

# 语言映射：zh 用中文，en/ru 走英文（LinuxMirrors 没有俄语包）。
for VPSO_LANGUAGE in zh en ru; do
    if [[ "$VPSO_LANGUAGE" == zh ]]; then mirror_language=zh; else mirror_language=en; fi
    UPDATE_MIRROR=https://mirror.example
    mirror_call=()
    func_system_mirrors <<< $'1\n1\n' >/dev/null
    [[ "${mirror_call[1]}" == https://mirror.example/https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh ]]
    [[ "${mirror_call[*]:2:4}" == "--upgrade-software false --lang $mirror_language" ]]
    [[ "${mirror_call[*]:6}" == "--source mirrors.aliyun.com" ]]
done

# 每个地区分类的末项都能正常解析并原样传参。
VPSO_LANGUAGE=zh
UPDATE_MIRROR=https://mirror.example
for mirror_category in {1..7}; do
    mapfile -t mirror_entries < <(system_mirror_catalog "$mirror_category")
    mirror_last=$(( ${#mirror_entries[@]} - 1 ))
    mirror_last_source=$(printf '%s' "${mirror_entries[mirror_last]}" | awk -F'|' '{print $3}')
    mirror_call=()
    func_system_mirrors <<< "$mirror_category"$'\n'"$((mirror_last + 1))"$'\n' >/dev/null
    [[ "${mirror_call[*]:6}" == "--source ${mirror_last_source}" ]]
done

# 分类输入接受 1. 与全角数字。
mirror_call=()
func_system_mirrors <<< $'1.\n1\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirrors.aliyun.com' ]]
mirror_call=()
func_system_mirrors <<< $'１\n2\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirrors.tencent.com' ]]

# 非法输入后仍可继续选择。
mirror_call=()
func_system_mirrors <<< $'invalid\n1\n99\n2\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirrors.tencent.com' ]]

# Rocky Linux + 阿里云使用 rockylinux 仓库目录。
OS=rocky
mirror_call=()
func_system_mirrors <<< $'1\n1\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirrors.aliyun.com --branch rockylinux' ]]
OS=debian

# 自定义地址：域名自动去掉协议与结尾斜杠。
mirror_call=()
func_system_mirrors <<< $'8\nhttps://mirror.example.com/\nlinux/debian\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirror.example.com --branch linux/debian' ]]
mirror_call=()
func_system_mirrors <<< $'8\nmirror.example.com\n\n\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirror.example.com' ]]

# 返回路径不触发换源。
mirror_call=()
func_system_mirrors <<< $'8\n\n0' >/dev/null
[[ ${#mirror_call[@]} == 0 ]]
for mirror_back in 0 q Q ''; do
    mirror_call=()
    func_system_mirrors <<<"$mirror_back" >/dev/null
    [[ ${#mirror_call[@]} == 0 ]]
done
mirror_call=()
func_system_mirrors <<< $'1\nq\n0' >/dev/null
[[ ${#mirror_call[@]} == 0 ]]

# 探测不到仓库时默认不换源，用户明确继续才执行。
system_mirror_source_reachable() { return 1; }
mirror_call=()
func_system_mirrors <<< $'1\n1\nn\n0' >/dev/null
[[ ${#mirror_call[@]} == 0 ]]
mirror_call=()
func_system_mirrors <<< $'1\n1\ny\n' >/dev/null
[[ "${mirror_call[*]:6}" == '--source mirrors.aliyun.com' ]]
system_mirror_source_reachable() { return 0; }

# 未配置 GitHub 镜像时直接请求原始地址。
UPDATE_MIRROR=""
mirror_call=()
func_system_mirrors <<< $'1\n2\n' >/dev/null
[[ "${mirror_call[1]}" == https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh ]]

# 换源失败要原样返回退出码。
mirror_status=23
if func_system_mirrors <<< $'1\n1\n' >/dev/null; then
    echo 'Mirror switch must preserve the remote script failure.' >&2
    exit 1
else
    [[ $? == 23 ]]
fi

echo "System mirror tests passed."
