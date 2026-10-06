#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/etc/nginx/stream.d" "$fixture/etc/nginx/conf.d" "$fixture/etc/vps-optimize"
mkdir -p "$fixture/etc/nginx/sites-available" "$fixture/etc/nginx/sites-enabled"
printf 'original nginx\n' > "$fixture/etc/nginx/nginx.conf"
printf 'original stream\n' > "$fixture/etc/nginx/stream.d/vps_sni_443.conf"
printf 'original map\n' > "$fixture/etc/nginx/conf.d/00-vps-proxy-map.conf"
printf 'original default site\n' > "$fixture/etc/nginx/sites-available/default"
ln -s ../sites-available/default "$fixture/etc/nginx/sites-enabled/default"
printf 'original default conf\n' > "$fixture/etc/nginx/conf.d/default.conf"

# Run the production functions against a disposable filesystem instead of /etc.
for module in backup rollback; do
    source <(sed -e "s|/etc/|$fixture/etc/|g" -e "s|/usr/local/|$fixture/usr/local/|g" "$repo_root/src/$module.sh")
done
localized_text() { printf '%s' "$1"; }
RED= YELLOW= GREEN= PLAIN= PANEL_DOMAIN=
SITE_DOMAINS=()
service_log="$fixture/services.log"
: > "$service_log"
caddy_active=0
nginx_valid=1
systemctl() {
    case "$1:$*" in
        is-enabled:*)
            if [[ "$2" == nginx ]]; then printf 'enabled\n'; else printf 'disabled\n'; return 1; fi
            ;;
        is-active:*) [[ "${*: -1}" == nginx || "$caddy_active" == 1 ]] ;;
        stop:*) printf 'stop %s\n' "$2" >> "$service_log" ;;
        enable:*|disable:*) printf '%s %s\n' "$1" "$2" >> "$service_log" ;;
        *) return 0 ;;
    esac
}
nginx() { printf 'validate nginx\n' >> "$service_log"; [[ "$nginx_valid" == 1 ]]; }
caddy() { printf 'validate caddy\n' >> "$service_log"; return 1; }
restart_service_if_available() { printf 'restart %s\n' "$1" >> "$service_log"; }

backup_dir="$fixture/snapshot"
create_sni_stack_backup "$backup_dir" >/dev/null
grep -Fxq "$fixture/etc/vps-optimize/sni-stack.env" "$backup_dir/absent-files"
grep -Fxq 'caddy|inactive' "$backup_dir/web-services"
grep -Fxq 'caddy|disabled' "$backup_dir/web-services"
[[ "$(stat -c %a "$backup_dir")" == 700 ]]
printf 'new config\n' > "$fixture/etc/vps-optimize/sni-stack.env"
printf 'new state\n' > "$fixture/etc/vps-optimize/443-engine.conf"
printf 'changed stream\n' > "$fixture/etc/nginx/stream.d/vps_sni_443.conf"
printf 'changed map\n' > "$fixture/etc/nginx/conf.d/00-vps-proxy-map.conf"
rm "$fixture/etc/nginx/sites-enabled/default" "$fixture/etc/nginx/sites-available/default" "$fixture/etc/nginx/conf.d/default.conf"
printf 'new drop\n' > "$fixture/etc/nginx/conf.d/00-vps-default-drop.conf"
mkdir -p "$fixture/etc/caddy"
printf 'new caddy\n' > "$fixture/etc/caddy/Caddyfile"
restore_sni_stack_backup_files "$backup_dir"
[[ ! -e "$fixture/etc/vps-optimize/sni-stack.env" && ! -e "$fixture/etc/vps-optimize/443-engine.conf" && ! -e "$fixture/etc/caddy/Caddyfile" ]]
grep -Fxq 'original stream' "$fixture/etc/nginx/stream.d/vps_sni_443.conf"
grep -Fxq 'original map' "$fixture/etc/nginx/conf.d/00-vps-proxy-map.conf"
[[ ! -e "$fixture/etc/nginx/conf.d/00-vps-default-drop.conf" ]]
[[ -L "$fixture/etc/nginx/sites-enabled/default" ]]
[[ "$(readlink "$fixture/etc/nginx/sites-enabled/default")" == ../sites-available/default ]]
grep -Fxq 'original default site' "$fixture/etc/nginx/sites-enabled/default"
grep -Fxq 'original default conf' "$fixture/etc/nginx/conf.d/default.conf"

caddy_active=1
restore_sni_stack_web_services "$backup_dir"
grep -Fxq 'restart nginx' "$service_log"
grep -Fxq 'stop caddy' "$service_log"
grep -Fxq 'disable caddy' "$service_log"
grep -Fxq 'enable nginx' "$service_log"
[[ "$(grep -E '^(stop|restart) ' "$service_log" | head -n1)" == 'stop caddy' ]]
! grep -Eq 'validate caddy|xray' "$service_log"

: > "$service_log"
nginx_valid=0
if restore_sni_stack_web_services "$backup_dir"; then
    echo 'Invalid Nginx rollback must fail.' >&2
    exit 1
fi
! grep -Fxq 'restart nginx' "$service_log"

cp() { return 1; }
if restore_sni_stack_backup_files "$backup_dir"; then
    echo 'A failed configuration copy must fail rollback.' >&2
    exit 1
fi
if create_sni_stack_backup "$fixture/failed-snapshot" >/dev/null; then
    echo 'A failed configuration copy must fail backup.' >&2
    exit 1
fi
echo 'SNI rollback regression checks passed.'
