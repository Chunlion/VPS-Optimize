#!/usr/bin/env bash
set -euo pipefail
trap 'echo "update-mirror failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp_dir=$(mktemp -d /tmp/vps-update-mirror.XXXXXX)
trap 'rm -rf -- "$tmp_dir"' EXIT

cp dist/vps.sh "$tmp_dir/remote.sh"
printf '\n# mirrored update payload\n' >> "$tmp_dir/remote.sh"
sha256sum "$tmp_dir/remote.sh" > "$tmp_dir/remote.sh.sha256"
expected_version=$(grep -m1 '^SCRIPT_VERSION=' src/common.sh | cut -d= -f2 | tr -d '"')

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
source src/updater.sh

UPDATE_MIRROR_CONFIG="$tmp_dir/mirror.conf"
SCRIPT_UPDATE_CACHE="$tmp_dir/update.cache"
clear() { :; }
print_breadcrumb() { :; }
pause_after_external_script() { :; }
sleep() { :; }
update_mirror_prefix_is_reachable() { return 0; }

# 1. 环境变量残留不会生效；默认直连 GitHub。
UPDATE_MIRROR=https://previous.example
load_script_update_mirror
[[ -z "$UPDATE_MIRROR" ]]
[[ "$UPDATE_URL" == https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh ]]
[[ "$UPDATE_SHA256_URL" == "${UPDATE_URL}.sha256" ]]

# 2. 回车/q 不写配置。
func_configure_update_mirror <<<q >/dev/null
[[ ! -e "$UPDATE_MIRROR_CONFIG" && -z "$UPDATE_MIRROR" ]]

# 3. 非法前缀被拒绝，合法前缀写入配置并清空更新缓存。
for VPSO_LANGUAGE in zh en ru; do
    touch "$SCRIPT_UPDATE_CACHE"
    func_configure_update_mirror <<< $'http://mirror.example\nhttps://mirror.example/' >/dev/null
    [[ "$(cat "$UPDATE_MIRROR_CONFIG")" == https://mirror.example ]]
    [[ ! -f "$SCRIPT_UPDATE_CACHE" ]]
    UPDATE_MIRROR=""
    load_script_update_mirror
    [[ "$UPDATE_URL" == https://mirror.example/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh ]]
    [[ "$UPDATE_SHA256_URL" == "${UPDATE_URL}.sha256" ]]
    for mirror_back in q Q ''; do
        func_configure_update_mirror <<<"$mirror_back" >/dev/null
        [[ "$(cat "$UPDATE_MIRROR_CONFIG")" == https://mirror.example ]]
    done
done

# 4. 通配符前缀会被拒绝，不会写进配置。
func_configure_update_mirror <<< $'https://*.example.com\nq' >/dev/null
[[ "$(cat "$UPDATE_MIRROR_CONFIG")" == https://mirror.example ]]

# 5. “-”恢复直连：删除配置、清空缓存。
touch "$SCRIPT_UPDATE_CACHE"
func_configure_update_mirror <<< - >/dev/null
[[ ! -e "$UPDATE_MIRROR_CONFIG" ]]
[[ -z "$UPDATE_MIRROR" ]]
[[ "$UPDATE_URL" == https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh ]]

# 6. 配置文件被改坏时忽略内容，不拼出无效更新地址。
printf '%s\n' 'http://broken.example' > "$UPDATE_MIRROR_CONFIG"
load_script_update_mirror
[[ -z "$UPDATE_MIRROR" ]]
[[ "$UPDATE_URL" == https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh ]]
rm -f "$UPDATE_MIRROR_CONFIG"

# 7. 探测失败时默认不保存，明确同意后才保存。
update_mirror_prefix_is_reachable() { return 1; }
func_configure_update_mirror <<< $'https://mirror.example\nn' >/dev/null
[[ ! -e "$UPDATE_MIRROR_CONFIG" ]]
func_configure_update_mirror <<< $'https://mirror.example\ny' >/dev/null
[[ "$(cat "$UPDATE_MIRROR_CONFIG")" == https://mirror.example ]]
update_mirror_prefix_is_reachable() { return 0; }

# 8. 镜像来源与官方来源使用不同说明，且镜像地址仍属已知来源。
VPSO_LANGUAGE=zh
[[ "$(is_trusted_remote_script_url "https://mirror.example/https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh")" == *"内容由镜像方提供"* ]]
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh")" == *"官方换源脚本"* ]]
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/Chunlion/xray-relay/main/install.sh")" == *"xray-relay"* ]]
UPDATE_MIRROR=""
[[ "$(is_trusted_remote_script_url "https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh")" == *"官方换源脚本"* ]]
load_script_update_mirror
[[ "$UPDATE_MIRROR" == https://mirror.example ]]

# 9. 版本与校验和通过镜像前缀获取，校验不通过时拒绝安装。
curl() {
    local url="${!#}"
    case "$url" in
        "$UPDATE_URL") cat "$tmp_dir/remote.sh" ;;
        "$UPDATE_SHA256_URL") cat "$tmp_dir/remote.sh.sha256" ;;
        *) return 1 ;;
    esac
}
[[ "$(fetch_latest_script_version)" == "$expected_version" ]]
[[ "$(fetch_latest_script_sha256)" == "$(sha256sum "$tmp_dir/remote.sh" | awk '{print $1}')" ]]
(
    download_remote_script() {
        case "$1" in
            "$UPDATE_URL") cp "$tmp_dir/remote.sh" "$2" ;;
            "$UPDATE_SHA256_URL") cp "$tmp_dir/remote.sh.sha256" "$2" ;;
            *) return 1 ;;
        esac
    }
    download_verified_update_script "$tmp_dir/verified.sh"
    cmp "$tmp_dir/remote.sh" "$tmp_dir/verified.sh"
    printf '%064d  remote.sh\n' 0 > "$tmp_dir/remote.sh.sha256"
    if download_verified_update_script "$tmp_dir/rejected.sh"; then
        echo 'A mirrored update with a checksum mismatch must be rejected.' >&2
        exit 1
    fi
    [[ ! -e "$tmp_dir/rejected.sh" ]]
)

echo "Update mirror tests passed."
