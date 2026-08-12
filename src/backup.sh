# shellcheck shell=bash
# Backup helpers and backup center entrypoint.

sni_stack_backup_dir() {
    echo "/etc/vps-optimize/backups/sni-stack_$(date +%Y%m%d_%H%M%S)"
}

create_sni_stack_backup() {
    local backup_dir
    backup_dir="${1:-$(sni_stack_backup_dir)}"
    mkdir -p "$backup_dir/nginx_stream.d" "$backup_dir/nginx_conf.d" "$backup_dir/caddy_conf.d" "$backup_dir/vps-optimize" "$backup_dir/systemd" "$backup_dir/usr-local-bin" "$backup_dir/x-ui"
    [[ -f /etc/nginx/nginx.conf ]] && cp -a /etc/nginx/nginx.conf "$backup_dir/nginx.conf" 2>/dev/null || true
    [[ -d /etc/nginx/stream.d ]] && cp -a /etc/nginx/stream.d/vps_sni_*.conf "$backup_dir/nginx_stream.d/" 2>/dev/null || true
    [[ -d /etc/nginx/conf.d ]] && cp -a /etc/nginx/conf.d/vps_sni_web_*.conf "$backup_dir/nginx_conf.d/" 2>/dev/null || true
    [[ -d /etc/nginx/conf.d ]] && cp -a /etc/nginx/conf.d/vps_proxy_*.conf "$backup_dir/nginx_conf.d/" 2>/dev/null || true
    [[ -f /etc/nginx/conf.d/00-vps-proxy-map.conf ]] && cp -a /etc/nginx/conf.d/00-vps-proxy-map.conf "$backup_dir/nginx_conf.d/" 2>/dev/null || true
    [[ -f /etc/caddy/Caddyfile ]] && cp -a /etc/caddy/Caddyfile "$backup_dir/Caddyfile" 2>/dev/null || true
    [[ -d /etc/caddy/conf.d ]] && cp -a /etc/caddy/conf.d/*.caddy "$backup_dir/caddy_conf.d/" 2>/dev/null || true
    [[ -f /etc/vps-optimize/sni-stack.env ]] && cp -a /etc/vps-optimize/sni-stack.env "$backup_dir/vps-optimize/sni-stack.env" 2>/dev/null || true
    [[ -f /etc/vps-optimize/xray-sni-routes.conf ]] && cp -a /etc/vps-optimize/xray-sni-routes.conf "$backup_dir/vps-optimize/xray-sni-routes.conf" 2>/dev/null || true
    [[ -f /etc/vps-optimize/443-engine.conf ]] && cp -a /etc/vps-optimize/443-engine.conf "$backup_dir/vps-optimize/443-engine.conf" 2>/dev/null || true
    [[ -f /etc/vps-optimize/vpso-mux.yaml ]] && cp -a /etc/vps-optimize/vpso-mux.yaml "$backup_dir/vps-optimize/vpso-mux.yaml" 2>/dev/null || true
    [[ -f /etc/systemd/system/vpso-mux.service ]] && cp -a /etc/systemd/system/vpso-mux.service "$backup_dir/systemd/vpso-mux.service" 2>/dev/null || true
    [[ -f /usr/local/bin/vpso-mux ]] && cp -a /usr/local/bin/vpso-mux "$backup_dir/usr-local-bin/vpso-mux" 2>/dev/null || true
    [[ -d /etc/x-ui ]] && cp -a /etc/x-ui "$backup_dir/x-ui/etc-x-ui" 2>/dev/null || true
    [[ -f /usr/local/x-ui/bin/config.json ]] && cp -a /usr/local/x-ui/bin/config.json "$backup_dir/x-ui/config.json" 2>/dev/null || true
    echo "$backup_dir" > /etc/vps-optimize/sni-stack.last-backup 2>/dev/null || true
    echo -e "$(localized_text "${GREEN}✅ 已创建配置备份：${backup_dir}${PLAIN}" "${GREEN}✅ Configuration backup created: ${backup_dir}${PLAIN}" "${GREEN}✅ Создана резервная копия конфигурации: ${backup_dir}.${PLAIN}")"
}

make_secure_temp_dir() {
    local prefix="$1"
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXX") || return 1
    chmod 700 "$tmp_dir" 2>/dev/null || true
    printf '%s' "$tmp_dir"
}

backup_cleanup_temp_dir() {
    local target="$1"
    local temp_root resolved_target target_parent target_name

    [[ -n "$target" && -d "$target" && ! -L "$target" ]] || return 0
    temp_root=$(readlink -f -- "${TMPDIR:-/tmp}") || return 1
    resolved_target=$(readlink -f -- "$target") || return 1
    target_parent=$(dirname -- "$resolved_target")
    target_name=$(basename -- "$resolved_target")
    [[ "$target_parent" == "$temp_root" ]] || return 1
    case "$target_name" in
        vps_backup_*.??????|vps_restore.??????) ;;
        *) return 1 ;;
    esac
    find "$resolved_target" -xdev -depth -delete
}

backup_copy_path() {
    local src="$1"
    local dest_rel="$2"
    local manifest_file="$3"
    local work_dir="$4"
    local dest_dir

    [[ -e "$src" || -L "$src" ]] || return 1
    dest_dir=$(dirname "$dest_rel")
    mkdir -p "$work_dir/$dest_dir" || return 1

    if cp -a -- "$src" "$work_dir/$dest_rel" 2>/dev/null; then
        echo " - $src" >> "$manifest_file"
        return 0
    fi
    BACKUP_COPY_FAILURES+=("$src")
    return 1
}

backup_path_size_bytes() {
    local target="$1"
    local size_kib
    size_kib=$(du -sk -- "$target" 2>/dev/null | awk 'NR == 1 {print $1}')
    [[ "$size_kib" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$((size_kib * 1024))"
}

backup_archive_unpacked_size_bytes() {
    local archive_file="$1"
    local size
    size=$(LC_ALL=C tar -tvzf "$archive_file" 2>/dev/null | awk '$3 ~ /^[0-9]+$/ {total += $3} END {printf "%.0f", total + 0}')
    [[ "$size" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$size"
}

backup_available_bytes() {
    local target="$1"
    local available_kib
    available_kib=$(df -Pk -- "$target" 2>/dev/null | awk 'NR == 2 {print $4}')
    [[ "$available_kib" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$((available_kib * 1024))"
}

backup_human_size() {
    local bytes="$1"
    awk -v bytes="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB", units, " ")
        unit_index = 1
        while (bytes >= 1024 && unit_index < 5) { bytes /= 1024; unit_index++ }
        if (unit_index == 1) printf "%d %s", bytes, units[unit_index]
        else printf "%.1f %s", bytes, units[unit_index]
    }'
}

backup_require_free_space() {
    local target="$1"
    local payload_bytes="$2"
    local operation="$3"
    local reserve_bytes=$((64 * 1024 * 1024))
    local required_bytes available_bytes

    required_bytes=$((payload_bytes + payload_bytes / 10 + reserve_bytes))
    if ! available_bytes=$(backup_available_bytes "$target"); then
        echo -e "$(localized_text "${YELLOW}⚠️ 无法读取 ${target} 的可用空间，继续前请自行确认磁盘容量。${PLAIN}" "${YELLOW}⚠️ Available space for ${target} could not be read. Verify disk capacity before continuing.${PLAIN}" "${YELLOW}⚠️ Не удалось определить свободное место для ${target}. Перед продолжением проверьте объём диска.${PLAIN}")"
        return 0
    fi
    if (( available_bytes < required_bytes )); then
        echo -e "$(localized_text "${RED}❌ ${operation}需要约 $(backup_human_size "$required_bytes")，${target} 仅剩 $(backup_human_size "$available_bytes")。操作已停止。${PLAIN}" "${RED}❌ ${operation} needs about $(backup_human_size "$required_bytes"), but ${target} has only $(backup_human_size "$available_bytes") free. Operation stopped.${PLAIN}" "${RED}❌ Для операции «${operation}» требуется около $(backup_human_size "$required_bytes"), а в ${target} свободно только $(backup_human_size "$available_bytes"). Операция остановлена.${PLAIN}")"
        return 1
    fi
    echo -e "$(localized_text "${GREEN}空间预检通过：需要约 $(backup_human_size "$required_bytes")，可用 $(backup_human_size "$available_bytes")。${PLAIN}" "${GREEN}Space check passed: about $(backup_human_size "$required_bytes") required, $(backup_human_size "$available_bytes") available.${PLAIN}" "${GREEN}Проверка места пройдена: требуется около $(backup_human_size "$required_bytes"), доступно $(backup_human_size "$available_bytes").${PLAIN}")"
}

backup_copy_xui_databases() {
    local manifest_file="$1"
    local work_dir="$2"
    local copied=1
    local db suffix src
    local db_paths=(
        "/etc/x-ui/x-ui.db"
        "/usr/local/x-ui/x-ui.db"
        "/usr/local/x-ui/bin/x-ui.db"
    )

    for db in "${db_paths[@]}"; do
        for suffix in "" "-wal" "-shm"; do
            src="${db}${suffix}"
            if backup_copy_path "$src" "${src#/}" "$manifest_file" "$work_dir"; then
                copied=0
            fi
        done
    done
    return "$copied"
}

backup_copy_managed_configuration() {
    local manifest_file="$1"
    local work_dir="$2"
    local copied=1

    backup_copy_path /etc/ssh/sshd_config etc/ssh/sshd_config "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/hostname etc/hostname "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/hosts etc/hosts "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/nginx/nginx.conf etc/nginx/nginx.conf "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/nginx/stream.d etc/nginx/stream.d "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/nginx/conf.d etc/nginx/conf.d "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/nginx/sites-available etc/nginx/sites-available "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/nginx/sites-enabled etc/nginx/sites-enabled "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/caddy/Caddyfile etc/caddy/Caddyfile "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/caddy/conf.d etc/caddy/conf.d "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/caddy/certs etc/caddy/certs "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /root/cert root/cert "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /root/.acme.sh root/.acme.sh "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /root/.config/vps-panel/cloudflare.env root/.config/vps-panel/cloudflare.env "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/vps-optimize/sni-stack.env etc/vps-optimize/sni-stack.env "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/vps-optimize/sni-stack.last-backup etc/vps-optimize/sni-stack.last-backup "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/vps-optimize/443-engine.conf etc/vps-optimize/443-engine.conf "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/vps-optimize/vpso-mux.yaml etc/vps-optimize/vpso-mux.yaml "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/systemd/system/vpso-mux.service etc/systemd/system/vpso-mux.service "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /usr/local/bin/vpso-mux usr/local/bin/vpso-mux "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/vps-optimize/traffic-guard.conf etc/vps-optimize/traffic-guard.conf "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /var/lib/vps-optimize/traffic-guard var/lib/vps-optimize/traffic-guard "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /usr/local/bin/vps-traffic-guard-check usr/local/bin/vps-traffic-guard-check "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/systemd/system/vps-traffic-guard.service etc/systemd/system/vps-traffic-guard.service "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/systemd/system/vps-traffic-guard.timer etc/systemd/system/vps-traffic-guard.timer "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/resolv.conf etc/resolv.conf "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/docker/daemon.json etc/docker/daemon.json "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/fail2ban/jail.local etc/fail2ban/jail.local "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/sysctl.d etc/sysctl.d "$manifest_file" "$work_dir" && copied=0
    backup_copy_path /etc/x-ui etc/x-ui "$manifest_file" "$work_dir" && copied=0
    backup_copy_xui_databases "$manifest_file" "$work_dir" && copied=0
    return "$copied"
}

backup_resolve_custom_directory() {
    local input_path="$1"
    local resolved_path

    [[ "$input_path" == /* && "$input_path" != "/" ]] || return 1
    resolved_path=$(cd -- "$input_path" 2>/dev/null && pwd -P) || return 1
    case "$resolved_path" in
        /proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/tmp|/tmp/*) return 1 ;;
    esac
    printf '%s' "$resolved_path"
}

backup_collect_custom_directories() {
    local array_name="$1"
    local -n directory_list="$array_name"
    local input_path resolved_path existing duplicate

    directory_list=()
    echo -e "$(localized_text "${CYAN}每行填写一个要备份的绝对目录，留空结束。${PLAIN}" "${CYAN}Enter one absolute directory per line; leave blank to finish.${PLAIN}" "${CYAN}Введите один абсолютный каталог в строке; пустая строка завершает ввод.${PLAIN}")"
    echo -e "$(localized_text "示例：/etc、/usr、/home 或 /var/lib/myapp；不支持 /、/proc、/sys、/dev、/run、/tmp。" "Example: /etc, /usr, /home, or /var/lib/myapp. /, /proc, /sys, /dev, /run, and /tmp are not supported." "Пример: /etc, /usr, /home или /var/lib/myapp. /, /proc, /sys, /dev, /run и /tmp не поддерживаются.")"
    while true; do
        IFS= read -r -p "$(localized_text "目录: " "Directory: " "Каталог: ")" input_path || return 1
        input_path=$(trim_input "$input_path")
        [[ -n "$input_path" ]] || break
        if ! resolved_path=$(backup_resolve_custom_directory "$input_path"); then
            echo -e "$(localized_text "${RED}❌ 目录无效或不允许备份。${PLAIN}" "${RED}❌ Directory is invalid or cannot be backed up.${PLAIN}" "${RED}❌ Каталог недопустим или его нельзя резервировать.${PLAIN}")"
            continue
        fi
        duplicate=0
        for existing in "${directory_list[@]}"; do
            if [[ "$existing" == "$resolved_path" ]]; then
                duplicate=1
                break
            fi
        done
        [[ "$duplicate" -eq 1 ]] && continue
        directory_list+=("$resolved_path")
        echo -e "$(localized_text "${GREEN}已加入：${resolved_path}${PLAIN}" "${GREEN}Added: ${resolved_path}${PLAIN}" "${GREEN}Добавлено: ${resolved_path}${PLAIN}")"
    done
    [[ ${#directory_list[@]} -gt 0 ]]
}

backup_select_archive_directory() {
    local default_dir="$1"
    local input_path

    while true; do
        IFS= read -r -p "$(localized_text "备份存放目录 [${default_dir}]: " "Backup storage directory [${default_dir}]: " "Каталог хранения резервной копии [${default_dir}]: ")" input_path || return 1
        input_path=$(trim_input "$input_path")
        input_path=${input_path:-$default_dir}
        if [[ "$input_path" != /* || "$input_path" == "/" ]]; then
            echo -e "$(localized_text "${RED}❌ 请填写非根目录的绝对路径。${PLAIN}" "${RED}❌ Enter an absolute path other than /.${PLAIN}" "${RED}❌ Укажите абсолютный путь, отличный от /.${PLAIN}")"
            continue
        fi
        if mkdir -p -- "$input_path" 2>/dev/null; then
            BACKUP_ARCHIVE_ROOT="$input_path"
            return 0
        fi
        echo -e "$(localized_text "${RED}❌ 无法创建或写入该目录。${PLAIN}" "${RED}❌ Cannot create or write to this directory.${PLAIN}" "${RED}❌ Не удалось создать каталог или записать в него.${PLAIN}")"
    done
}

backup_archive_is_readable() {
    local archive_file="$1"
    [[ -f "$archive_file" && -r "$archive_file" ]] || return 1
    [[ "$archive_file" == *.tar.gz || "$archive_file" == *.tar.gz.enc ]]
}

backup_archive_is_encrypted() {
    [[ "${1:-}" == *.tar.gz.enc ]]
}

backup_read_new_password() {
    local output_name="$1"
    local -n output_password="$output_name"
    local first second

    while true; do
        read_secret_trimmed first "$(localized_text "备份加密密码: " "Backup encryption password: " "Пароль шифрования резервной копии: ")"
        if [[ ${#first} -lt 10 ]]; then
            echo -e "$(localized_text "${YELLOW}密码至少需要 10 个字符。${PLAIN}" "${YELLOW}The password must contain at least 10 characters.${PLAIN}" "${YELLOW}Пароль должен содержать не менее 10 символов.${PLAIN}")"
            continue
        fi
        read_secret_trimmed second "$(localized_text "再次输入密码: " "Enter the password again: " "Введите пароль ещё раз: ")"
        if [[ "$first" == "$second" ]]; then
            output_password="$first"
            first=""
            second=""
            return 0
        fi
        first=""
        second=""
        echo -e "$(localized_text "${YELLOW}两次密码不一致，请重新输入。${PLAIN}" "${YELLOW}The passwords do not match. Try again.${PLAIN}" "${YELLOW}Пароли не совпадают. Повторите ввод.${PLAIN}")"
    done
}

backup_create_archive() {
    local work_dir="$1"
    local archive_file="$2"
    local password="${3:-}"

    if backup_archive_is_encrypted "$archive_file"; then
        (
            set -o pipefail
            umask 077
            exec 3<<<"$password"
            tar -czf - -C "$work_dir" . | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -pass fd:3 -out "$archive_file"
        ) >/dev/null 2>&1 || return 1
        (
            set -o pipefail
            exec 3<<<"$password"
            openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass fd:3 -in "$archive_file" | tar -tzf - >/dev/null
        ) 2>/dev/null
    else
        ( umask 077 && tar -czf "$archive_file" -C "$work_dir" . ) >/dev/null 2>&1 || return 1
        tar -tzf "$archive_file" >/dev/null 2>&1
    fi
}

backup_decrypt_archive() {
    local archive_file="$1"
    local output_file="$2"
    local password="$3"

    (
        umask 077
        exec 3<<<"$password"
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass fd:3 -in "$archive_file" -out "$output_file"
    ) >/dev/null 2>&1
}

backup_register_archive_root() {
    local archive_root="$1"
    local roots_file="/etc/vps-optimize/backup-archive-roots.conf"

    [[ "$archive_root" == /* && "$archive_root" != "/" ]] || return 1
    mkdir -p /etc/vps-optimize || return 1
    touch "$roots_file" || return 1
    chmod 600 "$roots_file" 2>/dev/null || true
    grep -Fqx -- "$archive_root" "$roots_file" 2>/dev/null || printf '%s\n' "$archive_root" >> "$roots_file"
}

backup_collect_archive_roots() {
    local array_name="$1"
    local -n root_list="$array_name"
    local roots_file="/etc/vps-optimize/backup-archive-roots.conf"
    local root existing duplicate

    root_list=()
    while IFS= read -r root; do
        [[ "$root" == /* && "$root" != "/" && -d "$root" ]] || continue
        duplicate=0
        for existing in "${root_list[@]}"; do
            [[ "$existing" == "$root" ]] && duplicate=1 && break
        done
        [[ "$duplicate" -eq 1 ]] || root_list+=("$root")
    done < <(
        printf '%s\n' "/etc/vps-optimize/backups/manual" "/backups" "/root/backups"
        [[ -f "$roots_file" ]] && sed -n '/^\//p' "$roots_file"
    )
}

backup_collect_available_archives() {
    local array_name="$1"
    local -n archive_list="$array_name"
    local -a roots=()
    local root archive existing duplicate

    archive_list=()
    backup_collect_archive_roots roots
    for root in "${roots[@]}"; do
        while IFS= read -r archive; do
            backup_archive_is_readable "$archive" || continue
            duplicate=0
            for existing in "${archive_list[@]}"; do
                [[ "$existing" == "$archive" ]] && duplicate=1 && break
            done
            [[ "$duplicate" -eq 1 ]] || archive_list+=("$archive")
        done < <(ls -1t "$root"/*.tar.gz "$root"/*.tar.gz.enc 2>/dev/null)
    done
}

backup_select_available_archive() {
    local output_name="$1"
    local -n selected_archive="$output_name"
    local -a archives=()
    local choice i

    backup_collect_available_archives archives
    if [[ ${#archives[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}⚠️ 未自动读取到可用的 .tar.gz 或 .tar.gz.enc 备份包。${PLAIN}" "${YELLOW}⚠️ No usable .tar.gz or .tar.gz.enc backup archive was found automatically.${PLAIN}" "${YELLOW}⚠️ Не найден доступный архив .tar.gz или .tar.gz.enc.${PLAIN}")"
        return 1
    fi

    echo -e "$(localized_text "${CYAN}可加载备份：${PLAIN}" "${CYAN}Loadable backups:${PLAIN}" "${CYAN}Доступные для загрузки копии:${PLAIN}")"
    for i in "${!archives[@]}"; do
        echo -e "  ${GREEN}$((i + 1)).${PLAIN} $(basename "${archives[$i]}") ${YELLOW}($(dirname "${archives[$i]}"))${PLAIN}"
    done
    read_trimmed choice "$(localized_text "输入备份序号: " "Enter backup number: " "Введите номер резервной копии: ")"
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#archives[@]} )); then
        echo -e "$(localized_text "${RED}❌ 无效序号。${PLAIN}" "${RED}❌ Invalid number.${PLAIN}" "${RED}❌ Неверный номер.${PLAIN}")"
        return 1
    fi
    selected_archive="${archives[$((choice - 1))]}"
}

backup_copy_custom_directories() {
    local manifest_file="$1"
    local work_dir="$2"
    local array_name="$3"
    local -n directory_list="$array_name"
    local mapping_file="${work_dir}/custom-paths.txt"
    local directory dest_rel
    local copied=1

    for directory in "${directory_list[@]}"; do
        dest_rel="custom${directory}"
        if backup_copy_path "$directory" "$dest_rel" "$manifest_file" "$work_dir"; then
            printf '%s|%s\n' "$dest_rel" "$directory" >> "$mapping_file"
            copied=0
        fi
    done
    [[ "$copied" -eq 0 ]] || rm -f "$mapping_file"
    return "$copied"
}

backup_restore_preflight() {
    local restore_dir="$1"
    local missing=0

    echo -e "$(localized_text "${CYAN}恢复环境预检：${PLAIN}" "${CYAN}Restore environment preflight:${PLAIN}" "${CYAN}Предварительная проверка среды восстановления:${PLAIN}")"
    if [[ -e "$restore_dir/etc/nginx/nginx.conf" || -d "$restore_dir/etc/nginx" ]] && ! command -v nginx >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}- Nginx 配置在备份中，但新系统未安装 Nginx。${PLAIN}" "${YELLOW}- Nginx configuration is in the backup, but Nginx is not installed on this system.${PLAIN}" "${YELLOW}- Конфигурация Nginx есть в резервной копии, но Nginx не установлен в системе.${PLAIN}")"
        missing=1
    fi
    if [[ -e "$restore_dir/etc/caddy/Caddyfile" || -d "$restore_dir/etc/caddy" ]] && ! command -v caddy >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}- Caddy 配置在备份中，但新系统未安装 Caddy。${PLAIN}" "${YELLOW}- Caddy configuration is in the backup, but Caddy is not installed on this system.${PLAIN}" "${YELLOW}- Конфигурация Caddy есть в резервной копии, но Caddy не установлен в системе.${PLAIN}")"
        missing=1
    fi
    if [[ -e "$restore_dir/etc/docker/daemon.json" ]] && ! command -v docker >/dev/null 2>&1; then
        echo -e "$(localized_text "${YELLOW}- Docker 配置在备份中，但新系统未安装 Docker。${PLAIN}" "${YELLOW}- Docker configuration is in the backup, but Docker is not installed on this system.${PLAIN}" "${YELLOW}- Конфигурация Docker есть в резервной копии, но Docker не установлен в системе.${PLAIN}")"
        missing=1
    fi
    if [[ -d "$restore_dir/etc/x-ui" ]] && [[ ! -d /etc/x-ui && ! -d /usr/local/x-ui ]]; then
        echo -e "$(localized_text "${YELLOW}- 3x-ui 配置在备份中，但新系统未检测到 3x-ui。${PLAIN}" "${YELLOW}- 3x-ui configuration is in the backup, but 3x-ui was not detected on this system.${PLAIN}" "${YELLOW}- Конфигурация 3x-ui есть в резервной копии, но 3x-ui не обнаружен в системе.${PLAIN}")"
        missing=1
    fi
    if [[ -f "$restore_dir/custom-paths.txt" ]]; then
        echo -e "$(localized_text "${YELLOW}- 备份包含自定义系统目录，恢复会覆盖这些目录。${PLAIN}" "${YELLOW}- The backup contains custom system directories; restoring will overwrite them.${PLAIN}" "${YELLOW}- Резервная копия содержит пользовательские системные каталоги; восстановление перезапишет их.${PLAIN}")"
    fi
    [[ "$missing" -eq 0 ]] || echo -e "$(localized_text "${YELLOW}缺少的服务不会自动安装；恢复文件后请安装并启动对应服务。${PLAIN}" "${YELLOW}Missing services are not installed automatically. Install and start them after restoring the files.${PLAIN}" "${YELLOW}Отсутствующие службы не устанавливаются автоматически. После восстановления файлов установите и запустите их.${PLAIN}")"
}

backup_restore_custom_directories() {
    local restore_dir="$1"
    local quarantine_root="$2"
    local mapping_file="${restore_dir}/custom-paths.txt"
    local dest_rel target_path
    local failed=0

    [[ -f "$mapping_file" ]] || return 0
    while IFS='|' read -r dest_rel target_path; do
        [[ "$dest_rel" == "custom${target_path}" && "$target_path" == /* && "$target_path" != "/" ]] || return 1
        case "$target_path" in
            /proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/tmp|/tmp/*) return 1 ;;
        esac
        [[ -d "$restore_dir/$dest_rel" ]] || return 1
        if [[ "${target_path#/}" == */* ]]; then
            restore_backup_dir "$restore_dir/$dest_rel" "$target_path" "$quarantine_root" || failed=1
        else
            mkdir -p "$target_path" && cp -a -- "$restore_dir/$dest_rel/." "$target_path/" || failed=1
        fi
    done < "$mapping_file"
    return "$failed"
}

redact_sensitive_output() {
    sed -E \
        -e 's/(authorization:[[:space:]]*(bearer|basic)[[:space:]]+)[^[:space:]]+/\1***REDACTED***/gI' \
        -e 's/((^|[^[:alnum:]_])(token|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|CF_Token|CF_Key)[[:space:]]*[=:][[:space:]]*)[^[:space:],;"'\''}]+/\1***REDACTED***/gI' \
        -e 's/("(token|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|CF_Token|CF_Key)"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/gI' \
        -e 's/([?&](token|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret)=)[^&[:space:]]+/\1***REDACTED***/gI' \
        -e 's#(https?://)[^/@[:space:]]+@#\1***REDACTED***@#g'
}

dns_backup_current_config() {
    local ts backup_dir
    ts=$(date +%Y%m%d_%H%M%S)
    backup_dir="${DNS_OPTIMIZE_BACKUP_DIR}/${ts}"
    mkdir -p "$backup_dir"
    chmod 700 "$DNS_OPTIMIZE_BACKUP_DIR" "$backup_dir" 2>/dev/null || true
    [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]] && cp -a /etc/resolv.conf "$backup_dir/resolv.conf" 2>/dev/null || true
    [[ -f "$DNS_OPTIMIZE_RESOLVED_DROPIN" ]] && cp -a "$DNS_OPTIMIZE_RESOLVED_DROPIN" "$backup_dir/99-vps-optimize-dns.conf" 2>/dev/null || true
    echo "$backup_dir" > "${DNS_OPTIMIZE_BACKUP_DIR}/last" 2>/dev/null || true
    echo "$backup_dir"
}

applied_config_editor_command() {
    local editor="${EDITOR:-}"
    if [[ -n "$editor" && "$editor" != *" "* ]] && command -v "$editor" >/dev/null 2>&1; then
        printf '%s' "$editor"
        return 0
    fi

    local candidate
    for candidate in nano vim vi; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

append_applied_config_file() {
    local label="$1"
    local path="$2"
    local kind="$3"
    local existing

    [[ -e "$path" || -L "$path" ]] || return 0
    for existing in "${applied_config_paths[@]}"; do
        [[ "$existing" == "$path" ]] && return 0
    done

    applied_config_labels+=("$label")
    applied_config_paths+=("$path")
    applied_config_kinds+=("$kind")
}

collect_applied_config_files() {
    local scope="${1:-all}"
    local conf_file

    applied_config_labels=()
    applied_config_paths=()
    applied_config_kinds=()

    append_applied_config_file "$(localized_text "Caddy 主配置" "Caddy main configuration" "Основная конфигурация Caddy")" "/etc/caddy/Caddyfile" "caddy"
    for conf_file in /etc/caddy/conf.d/*.caddy; do
        [[ -f "$conf_file" ]] && append_applied_config_file "$(localized_text "Caddy 站点 $(basename "$conf_file")" "Caddy site $(basename \"$conf_file\")" "Caddy сайт $(basename \"$conf_file\")")" "$conf_file" "caddy"
    done
    append_applied_config_file "$(localized_text "Nginx 主配置" "Nginx main configuration" "Основная конфигурация Nginx")" "/etc/nginx/nginx.conf" "nginx"
    for conf_file in /etc/nginx/conf.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Nginx conf.d $(basename "$conf_file")" "$conf_file" "nginx"
    done
    for conf_file in /etc/nginx/sites-enabled/*; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Nginx sites-enabled $(basename "$conf_file")" "$conf_file" "nginx"
    done

    [[ "$scope" == "proxy" ]] && return 0

    for conf_file in /etc/nginx/stream.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Nginx stream.d $(basename "$conf_file")" "$conf_file" "nginx"
    done
    append_applied_config_file "$(localized_text "443端口复用参数" "Port 443 Reuse Parameters" "Параметры повторного использования порта 443")" "/etc/vps-optimize/sni-stack.env" "entry-mode"
    append_applied_config_file "$(localized_text "443 引擎状态" "443 Engine status" "443 Статус двигателя")" "/etc/vps-optimize/443-engine.conf" "entry-mode"
    append_applied_config_file "$(localized_text "Xray SNI 分流记录" "Xray SNI routing record" "Xray SNI маршрутизирующая пластинка")" "/etc/vps-optimize/xray-sni-routes.conf" "xray-routes"
    append_applied_config_file "$(localized_text "TCP Peek vpso-mux 配置" "TCP Peek vpso-mux configuration" "Конфигурация TCP Peek vpso-mux")" "/etc/vps-optimize/vpso-mux.yaml" "vpso-mux"
    append_applied_config_file "vpso-mux systemd" "/etc/systemd/system/vpso-mux.service" "systemd"
    append_applied_config_file "$(localized_text "vpso-mux 8444 预检 systemd" "vpso-mux 8444 preflight check systemd" "vpso-mux 8444 Предварительная проверка systemd")" "/etc/systemd/system/vpso-mux-preflight.service" "systemd"
    append_applied_config_file "$(localized_text "Traffic Guard 配置" "Traffic Guard configuration" "Конфигурация Traffic Guard")" "$TRAFFIC_GUARD_CONFIG" "traffic-guard"
    append_applied_config_file "Traffic Guard service" "/etc/systemd/system/vps-traffic-guard.service" "systemd"
    append_applied_config_file "Traffic Guard timer" "/etc/systemd/system/vps-traffic-guard.timer" "systemd"
    append_applied_config_file "$(localized_text "Cloudflare DNS API 配置" "Cloudflare DNS API configuration" "Cloudflare DNS Конфигурация API")" "/root/.config/vps-panel/cloudflare.env" "env"
    append_applied_config_file "Docker daemon.json" "/etc/docker/daemon.json" "docker-json"
    append_applied_config_file "$(localized_text "SSH 主配置" "SSH main configuration" "Основная конфигурация SSH")" "/etc/ssh/sshd_config" "ssh"
    for conf_file in /etc/ssh/sshd_config.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "SSH drop-in $(basename "$conf_file")" "$conf_file" "ssh"
    done
    append_applied_config_file "$(localized_text "Hosts 文件" "Hosts file" "Файл хостов")" "/etc/hosts" "hosts"
    append_applied_config_file "$(localized_text "Hostname 文件" "Hostname file" "Файл имени хоста")" "/etc/hostname" "hostname"
    append_applied_config_file "DNS resolv.conf" "/etc/resolv.conf" "dns"
    append_applied_config_file "systemd-resolved DNS drop-in" "$DNS_OPTIMIZE_RESOLVED_DROPIN" "dns"
    append_applied_config_file "Fail2ban jail.local" "/etc/fail2ban/jail.local" "fail2ban"
    append_applied_config_file "x-ui config.json" "/usr/local/x-ui/bin/config.json" "xui-json"
    for conf_file in /etc/sysctl.d/*.conf; do
        [[ -f "$conf_file" ]] && append_applied_config_file "sysctl.d $(basename "$conf_file")" "$conf_file" "sysctl"
    done
    for conf_file in /opt/sublinkpro/docker-compose.yml /opt/miaomiaowu/docker-compose.yml /opt/sub-store/docker-compose.yml /opt/dockge/docker-compose.yml /opt/komari/docker-compose.yml /opt/*/compose.yaml /opt/*/compose.yml /opt/*/docker-compose.yml /opt/*/docker-compose.yaml; do
        [[ -f "$conf_file" ]] && append_applied_config_file "Compose $(basename "$(dirname "$conf_file")")/$(basename "$conf_file")" "$conf_file" "compose"
    done
}

validate_xray_routes_file() {
    local target_file="$1"
    awk -F'|' '
        /^[[:space:]]*($|#)/ { next }
        { for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
        NF != 3 { exit 1 }
        $1 == "" || $2 == "" || $3 !~ /^[0-9]+$/ || $3 < 1 || $3 > 65535 { exit 1 }
    ' "$target_file"
}

validate_hosts_file() {
    local target_file="$1"
    awk '
        /^[[:space:]]*($|#)/ { next }
        NF < 2 { exit 1 }
    ' "$target_file"
}

validate_hostname_file() {
    local target_file="$1"
    local hostname_value
    hostname_value=$(head -n1 "$target_file" 2>/dev/null | tr -d '[:space:]')
    [[ -n "$hostname_value" && "$hostname_value" != *"/"* ]]
}

validate_json_file() {
    local target_file="$1"
    if command -v jq >/dev/null 2>&1; then
        jq empty "$target_file"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m json.tool "$target_file" >/dev/null
    else
        echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 jq/python3，已跳过 JSON 语法校验。${PLAIN}" "${YELLOW}⚠️ jq/python3 not detected, JSON syntax check skipped.${PLAIN}" "${YELLOW}⚠️ jq/python3 не обнаружен, проверка синтаксиса JSON пропущена.${PLAIN}")"
        return 0
    fi
}

load_docker_compose_runtime_helper() {
    local helper_path
    local -a helper_paths=()

    declare -F ensure_docker_compose_ready >/dev/null 2>&1 && return 0

    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        helper_paths+=("${SCRIPT_DIR}/src/compose_runtime.sh")
    fi
    helper_paths+=("$(dirname "${BASH_SOURCE[0]}")/compose_runtime.sh")

    for helper_path in "${helper_paths[@]}"; do
        [[ -f "$helper_path" ]] || continue
        # shellcheck source=/dev/null
        . "$helper_path"
        declare -F ensure_docker_compose_ready >/dev/null 2>&1 && return 0
    done

    return 1
}

run_applied_config_compose() {
    local target_file="$1"
    local project_dir
    shift

    if ! load_docker_compose_runtime_helper; then
        echo -e "$(localized_text "${RED}❌ 未加载 Docker Compose 自动安装/检测逻辑，无法应用 Compose 操作。${PLAIN}" "${RED}❌ The Docker Compose automatic installation/detection logic is not loaded and the Compose operation cannot be applied.${PLAIN}" "${RED}❌ Логика автоматической установки/обнаружения Docker Compose не загружена, и операцию Compose невозможно применить.${PLAIN}")"
        return 1
    fi

    ensure_docker_compose_ready || return 1
    project_dir=$(dirname "$target_file")
    (cd "$project_dir" && $DOCKER_COMPOSE_CMD -f "$target_file" "$@")
}

validate_applied_config_kind() {
    local kind="$1"
    local target_file="$2"

    case "$kind" in
        caddy)
            command -v caddy >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 caddy 命令，无法校验配置。${PLAIN}" "${RED}❌ The caddy command is not detected and the configuration cannot be verified.${PLAIN}" "${RED}❌ Команда caddy не обнаружена, и конфигурация не может быть проверена.${PLAIN}")"; return 1; }
            caddy validate --config /etc/caddy/Caddyfile
            ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 nginx 命令，无法校验配置。${PLAIN}" "${RED}❌ The nginx command is not detected and the configuration cannot be verified.${PLAIN}" "${RED}❌ Команда nginx не обнаружена, и конфигурация не может быть проверена.${PLAIN}")"; return 1; }
            nginx -t
            ;;
        systemd)
            if command -v systemd-analyze >/dev/null 2>&1; then
                systemd-analyze verify "$target_file"
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 systemd-analyze，已跳过 systemd unit 静态校验。${PLAIN}" "${YELLOW}⚠️ systemd-analyze is not detected and systemd unit static verification has been skipped.${PLAIN}" "${YELLOW}⚠️ systemd-анализ не обнаружен, а статическая проверка блока systemd пропущена.${PLAIN}")"
            fi
            ;;
        docker-json|xui-json)
            validate_json_file "$target_file"
            ;;
        compose)
            run_applied_config_compose "$target_file" config >/dev/null
            ;;
        ssh)
            command -v sshd >/dev/null 2>&1 || { echo -e "$(localized_text "${RED}❌ 未检测到 sshd 命令，无法校验 SSH 配置。${PLAIN}" "${RED}❌ The sshd command was not detected and the SSH configuration could not be verified.${PLAIN}" "${RED}❌ Команда sshd не обнаружена, и конфигурацию SSH проверить не удалось.${PLAIN}")"; return 1; }
            sshd -t
            ;;
        vpso-mux)
            if declare -F run_vpso_mux_config_check >/dev/null 2>&1; then
                run_vpso_mux_config_check "$target_file"
            elif [[ -x /usr/local/bin/vpso-mux ]]; then
                /usr/local/bin/vpso-mux -config "$target_file" -check
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 vpso-mux 二进制，已跳过运行时配置校验。${PLAIN}" "${YELLOW}⚠️ vpso-mux binary not detected, runtime configuration validation skipped.${PLAIN}" "${YELLOW}⚠️ Двоичный файл vpso-mux не обнаружен, проверка конфигурации во время выполнения пропущена.${PLAIN}")"
            fi
            ;;
        entry-mode|traffic-guard|env)
            bash -n "$target_file"
            ;;
        xray-routes)
            validate_xray_routes_file "$target_file"
            ;;
        hosts)
            validate_hosts_file "$target_file"
            ;;
        hostname)
            validate_hostname_file "$target_file"
            ;;
        dns|sysctl)
            return 0
            ;;
        fail2ban)
            if command -v fail2ban-client >/dev/null 2>&1; then
                fail2ban-client -t
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 未检测到 fail2ban-client，已跳过 Fail2ban 配置校验。${PLAIN}" "${YELLOW}⚠️ fail2ban-client is not detected and Fail2ban configuration validation has been skipped.${PLAIN}" "${YELLOW}⚠️ fail2ban-клиент не обнаружен и проверка конфигурации Fail2ban пропущена.${PLAIN}")"
            fi
            ;;
        *)
            echo -e "$(localized_text "${YELLOW}⚠️ 未知配置类型 ${kind}，仅保存备份，不执行额外校验。${PLAIN}" "${YELLOW}⚠️ Unknown configuration type ${kind}, only save backup and do not perform additional verification.${PLAIN}" "${YELLOW}⚠️ Неизвестный тип конфигурации ${kind}, сохраняйте только резервную копию и не выполняйте дополнительную проверку.${PLAIN}")"
            ;;
    esac
}

restart_named_service_if_available() {
    local service_name="$1"
    local rc
    restart_service_if_available "$service_name"
    rc=$?
    [[ "$rc" -eq 0 || "$rc" -eq 2 ]]
}

reload_applied_config_kind() {
    local kind="$1"
    local target_file="$2"
    local previous_file="${3:-${target_file}.bak}"
    local unit_name

    case "$kind" in
        caddy)
            systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy >/dev/null 2>&1
            ;;
        nginx)
            systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1
            ;;
        systemd)
            systemctl daemon-reload >/dev/null 2>&1 || return 1
            unit_name=$(basename "$target_file")
            if confirm_danger \
                "$(localized_text "重启或重新加载 ${unit_name}" "Restart or reload ${unit_name}" "Перезапустить или перезагрузить ${unit_name}")" \
                "$(localized_text "立即让已编辑的 systemd 单元配置生效。" "Apply the edited systemd unit configuration immediately." "Немедленно применить изменённую конфигурацию systemd.")" \
                "$(localized_text "恢复 ${previous_file} 后执行 systemctl daemon-reload，并重新启动该单元。" "Restore ${previous_file}, run systemctl daemon-reload, and start the unit again." "Восстановите ${previous_file}, выполните systemctl daemon-reload и снова запустите службу.")"; then
                systemctl try-reload-or-restart "$unit_name" >/dev/null 2>&1 || systemctl restart "$unit_name" >/dev/null 2>&1
            else
                echo -e "$(localized_text "${BLUE}unit 修改已保存，${unit_name} 尚未重启。${PLAIN}" "${BLUE}The unit change is saved; ${unit_name} has not been restarted.${PLAIN}" "${BLUE}Изменения unit сохранены; ${unit_name} не перезапущен.${PLAIN}")"
            fi
            ;;
        docker-json)
            if confirm_danger \
                "$(localized_text "重启 Docker" "Restart Docker" "Перезапустить Docker")" \
                "$(localized_text "应用已校验的 daemon.json；运行中容器的网络可能短暂中断。" "Apply the validated daemon.json; networking for running containers may be interrupted briefly." "Применить проверенный daemon.json; сеть запущенных контейнеров может кратковременно прерваться.")" \
                "$(localized_text "恢复 ${previous_file} 后再次重启 Docker。" "Restore ${previous_file} and restart Docker again." "Восстановите ${previous_file} и снова перезапустите Docker.")"; then
                restart_named_service_if_available docker
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Docker 未重启，daemon.json 修改尚未生效。${PLAIN}" "${YELLOW}⚠️ Docker has not restarted, and the modification of daemon.json has not yet taken effect.${PLAIN}" "${YELLOW}⚠️ Docker не перезапустился, а модификация daemon.json еще не вступила в силу.${PLAIN}")"
            fi
            ;;
        compose)
            if confirm_danger \
                "$(localized_text "应用 Compose 配置" "Apply the Compose configuration" "Применить конфигурацию Compose")" \
                "$(localized_text "执行 up -d；相关容器可能被创建、重建或重启。" "Run up -d; related containers may be created, recreated, or restarted." "Выполнить up -d; связанные контейнеры могут быть созданы, пересозданы или перезапущены.")" \
                "$(localized_text "恢复 ${previous_file} 后再次执行 Compose up -d。" "Restore ${previous_file} and run Compose up -d again." "Восстановите ${previous_file} и снова выполните Compose up -d.")"; then
                run_applied_config_compose "$target_file" up -d
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Compose 修改已保存，但尚未应用到容器。${PLAIN}" "${YELLOW}⚠️ The Compose change is saved but has not been applied to the containers.${PLAIN}" "${YELLOW}⚠️ Изменения Compose сохранены, но ещё не применены к контейнерам.${PLAIN}")"
            fi
            ;;
        ssh)
            if confirm_risk_action "$(localized_text "重启 SSH 服务" "Restart SSH service" "Перезапустите службу SSH.")" \
                "$(localized_text "当前 SSH 服务运行状态" "Current SSH service running status" "Текущее состояние работы службы SSH")" \
                "$(localized_text "使用当前未断开的 SSH 会话恢复 ${target_file}.bak_*，或通过云厂商控制台恢复 SSH 配置" "Use the currently undisconnected SSH session to restore ${target_file}.bak_*, or restore the SSH configuration through the cloud vendor console" "Используйте текущий неотключенный сеанс SSH для восстановления ${target_file}.bak_* или восстановите конфигурацию SSH через консоль облачного поставщика.")" \
                "$(localized_text "确认新 SSH 配置已经通过 sshd -t 校验。" "Confirm that the new SSH configuration has passed sshd -t verification." "Убедитесь, что новая конфигурация SSH прошла проверку sshd -t.")"; then
                restart_service_if_available sshd >/dev/null 2>&1 || restart_service_if_available ssh >/dev/null 2>&1
            else
                echo -e "$(localized_text "${YELLOW}⚠️ SSH 未重启，修改可能尚未生效。${PLAIN}" "${YELLOW}⚠️ SSH has not been restarted, and the modification may not yet take effect.${PLAIN}" "${YELLOW}⚠️ SSH не был перезапущен, и модификация может еще не вступить в силу.${PLAIN}")"
            fi
            ;;
        vpso-mux)
            if confirm_risk_action "$(localized_text "重启 vpso-mux" "Restart vpso-mux" "Перезагрузите vpso-mux.")" \
                "$(localized_text "TCP Peek/vpso-mux 分流器运行进程" "TCP Peek/vpso-mux routing running process" "Процесс работы маршрутизации TCP Peek/vpso-mux")" \
                "$(localized_text "使用当前未断开的 SSH 会话恢复 ${target_file}.bak_*，或回到 443端口复用菜单重新应用/回滚入口模式" "Restore ${target_file}.bak_* using the currently undisconnected SSH session, or return to the Port 443 Reuse menu to reapply/rollback entry mode" "Восстановите ${target_file}.bak_*, используя текущий неотключенный сеанс SSH, или вернитесь в меню повторное использование порта 443, чтобы повторно применить/откатить режим входа.")" \
                "$(localized_text "确认公网 443 当前入口模式和本机后端端口都正常。" "Confirm that the current entry mode of public port 443 and the local backend port are normal." "Убедитесь, что текущий режим входа в публичный порт 443 и локальный внутренний порт являются нормальными.")"; then
                restart_named_service_if_available vpso-mux
            else
                echo -e "$(localized_text "${YELLOW}⚠️ vpso-mux 未重启，修改尚未生效。${PLAIN}" "${YELLOW}⚠️ vpso-mux has not been restarted and the modification has not yet taken effect.${PLAIN}" "${YELLOW}⚠️ vpso-mux не был перезапущен и модификация еще не вступила в силу.${PLAIN}")"
            fi
            ;;
        entry-mode|xray-routes)
            if declare -F reapply_current_entry_mode >/dev/null 2>&1; then
                if confirm_risk_action "$(localized_text "重新应用当前 443 入口模式" "Reapply current 443 entry pattern" "Повторно применить текущий шаблон входа 443")" \
                    "$(localized_text "公网 443 入口配置、Caddy/Nginx/vpso-mux/Xray 相关路由" "public port 443 entry configuration, Caddy/Nginx/vpso-mux/Xray related routes" "Конфигурация входа в публичную сеть 443, маршруты, связанные с Caddy/Nginx/vpso-mux/Xray")" \
                    "$(localized_text "脚本会创建入口模式备份并在失败时回滚；也可从备份与回滚中心恢复" "Script creates entry mode backup and rolls back on failure; can also be restored from the Backup and Rollback Center" "Скрипт создает резервную копию в режим входа и выполняет откат в случае сбоя; также можно восстановить из Центра резервного копирования и отката.")" \
                    "$(localized_text "确认配置文件中的域名、端口和 ENTRY_MODE 值已经匹配。" "Confirm that the domain, port, and ENTRY_MODE value in the configuration file match." "Убедитесь, что имя домена, порт и значение ENTRY_MODE в файле конфигурации совпадают.")"; then
                    reapply_current_entry_mode
                else
                    echo -e "$(localized_text "${YELLOW}⚠️ 已保存配置，但未重新应用 443 入口模式。${PLAIN}" "${YELLOW}⚠️ Configuration saved, but 443 entry mode was not reapplied.${PLAIN}" "${YELLOW}⚠️ Конфигурация сохранена, но режим входа 443 не был применен повторно.${PLAIN}")"
                fi
            else
                echo -e "$(localized_text "${YELLOW}⚠️ 已保存配置；请回到 443端口复用菜单重新应用当前入口模式。${PLAIN}" "${YELLOW}⚠️ The configuration has been saved; please return to the Port 443 Reuse menu to reapply the current entry mode.${PLAIN}" "${YELLOW}⚠️ Конфигурация сохранена; вернитесь в меню повторного использования порта 443, чтобы повторно применить текущий режим ввода.${PLAIN}")"
            fi
            ;;
        traffic-guard)
            if [[ -n "$previous_file" ]] && declare -F traffic_guard_restore_ssh_only_firewall_from_config >/dev/null 2>&1; then
                traffic_guard_restore_ssh_only_firewall_from_config "$previous_file" || {
                    echo -e "$(localized_text "${RED}❌ 无法解除编辑前配置的仅保留 SSH 封锁规则，已取消应用。${PLAIN}" "${RED}❌ The keep-only SSH blocking rule configured before editing cannot be released and the application has been cancelled.${PLAIN}" "${RED}❌ Правило блокировки SSH «только сохранение», настроенное до редактирования, не может быть отменено, и приложение было отменено.${PLAIN}")"
                    return 1
                }
            fi
            if confirm_risk_action "$(localized_text "重启 Traffic Guard timer" "Restart Traffic Guard timer" "Перезапустить таймер Traffic Guard")" \
                "$(localized_text "vps-traffic-guard.timer 和流量阈值检查周期" "vps-traffic-guard.timer and traffic threshold check period" "vps-traffic-guard.timer и период проверки порога трафика")" \
                "$(localized_text "重新编辑 ${target_file} 或从 ${target_file}.bak_* 恢复；必要时停用 vps-traffic-guard.timer" "Re-edit ${target_file} or restore from ${target_file}.bak_*; disable vps-traffic-guard.timer if necessary" "Отредактируйте ${target_file} повторно или восстановите из ${target_file}.bak_*; при необходимости отключите vps-traffic-guard.timer")" \
                "$(localized_text "如果 ACTION=poweroff，请确认阈值、账单周期和云厂商救援方式。" "If ACTION=poweroff, confirm the threshold, billing cycle, and cloud vendor rescue method." "Если ACTION=poweroff, подтвердите пороговое значение, цикл выставления счетов и метод восстановления поставщика облачных услуг.")"; then
                systemctl daemon-reload >/dev/null 2>&1 || true
                systemctl restart vps-traffic-guard.timer >/dev/null 2>&1
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Traffic Guard timer 未重启，下一次运行前请确认配置已生效。${PLAIN}" "${YELLOW}⚠️ Traffic Guard timer has not been restarted. Please confirm that the configuration has taken effect before running it next time.${PLAIN}" "${YELLOW}⚠️ Таймер Traffic Guard не был перезапущен. Пожалуйста, подтвердите, что конфигурация вступила в силу, прежде чем запускать ее в следующий раз.${PLAIN}")"
            fi
            ;;
        hostname)
            local hostname_value
            hostname_value=$(head -n1 "$target_file" 2>/dev/null | tr -d '[:space:]')
            if [[ -n "$hostname_value" ]]; then
                hostnamectl set-hostname "$hostname_value" >/dev/null 2>&1 || hostname "$hostname_value" 2>/dev/null || true
            fi
            ;;
        dns)
            if confirm_risk_action "$(localized_text "重启 systemd-resolved" "Restart systemd-resolved" "Перезапуск systemd-решено")" \
                "$(localized_text "系统 DNS 解析服务和 resolved drop-in 配置" "System DNS resolution service and resolved drop-in configuration" "Служба разрешения проблем системы DNS и решенная прямая конфигурация")" \
                "$(localized_text "恢复 ${target_file}.bak_*，或重新进入 DNS 设置菜单切换回原配置" "Restore ${target_file}.bak_*, or reopen DNS settings and select the previous configuration." "Восстановите ${target_file}.bak_* или откройте настройки DNS и выберите прежнюю конфигурацию.")" \
                "$(localized_text "确认当前 SSH 会话保持连接，必要时可用 IP 直连排障。" "Confirm that the current SSH session remains connected, and use IP direct connection to troubleshoot if necessary." "Убедитесь, что текущий сеанс SSH остается подключенным, и при необходимости используйте прямое IP-соединение для устранения неполадок.")"; then
                restart_named_service_if_available systemd-resolved
            else
                echo -e "$(localized_text "${BLUE}DNS 配置已保存，未重启 systemd-resolved。${PLAIN}" "${BLUE}DNS configuration saved, no restart systemd-resolved.${PLAIN}" "${BLUE}Конфигурация DNS сохранена, проблема с systemd решена без перезагрузки.${PLAIN}")"
            fi
            ;;
        sysctl)
            if confirm_risk_action "$(localized_text "应用 sysctl 配置" "Apply sysctl configuration" "Применить конфигурацию sysctl")" \
                "$(localized_text "当前内核运行中的 sysctl 参数" "sysctl parameters currently running in the kernel" "Параметры sysctl, работающие в настоящее время в ядре")" \
                "$(localized_text "恢复 ${target_file}.bak_* 后重新执行 sysctl --system，或手动回退异常参数" "Restore ${target_file}.bak_* and re-execute sysctl --system, or manually roll back the abnormal parameters" "Восстановите ${target_file}.bak_* и повторно выполните sysctl --system или вручную откатите ненормальные параметры.")" \
                "$(localized_text "确认参数来源可信；错误网络参数可能影响远程连接。" "Confirm that the source of the parameters is trustworthy; incorrect network parameters may affect remote connections." "Подтвердите, что источник параметров заслуживает доверия; неправильные параметры сети могут повлиять на удаленные подключения.")"; then
                sysctl --system >/dev/null
            else
                echo -e "$(localized_text "${YELLOW}⚠️ sysctl 修改尚未应用到当前内核。${PLAIN}" "${YELLOW}⚠️ The sysctl modification has not yet been applied to the current kernel.${PLAIN}" "${YELLOW}⚠️ Модификация sysctl пока не применена к текущему ядру.${PLAIN}")"
            fi
            ;;
        fail2ban)
            if confirm_risk_action "$(localized_text "重启 fail2ban" "Restart fail2ban" "Перезагрузите fail2ban.")" \
                "$(localized_text "Fail2ban 服务和登录防护规则" "Fail2ban Service and Login Protection Rules" "Fail2ban Правила защиты и защиты входа в систему")" \
                "$(localized_text "恢复 ${target_file}.bak_* 后重启 fail2ban，或临时停用异常 jail" "Restore ${target_file}.bak_* and then restart fail2ban, or temporarily disable the abnormal jail" "Восстановите ${target_file}.bak_*, а затем перезапустите fail2ban или временно отключите аварийный джейл.")" \
                "$(localized_text "确认当前 SSH 来源不会被新规则误封。" "Confirm that the current SSH source will not be accidentally blocked by the new rules." "Убедитесь, что текущий источник SSH не будет случайно заблокирован новыми правилами.")"; then
                restart_named_service_if_available fail2ban
            else
                echo -e "$(localized_text "${YELLOW}⚠️ Fail2ban 未重启，修改尚未生效。${PLAIN}" "${YELLOW}⚠️ Fail2ban has not been restarted and the modification has not yet taken effect.${PLAIN}" "${YELLOW}⚠️ Fail2ban не был перезапущен и модификация еще не вступила в силу.${PLAIN}")"
            fi
            ;;
        xui-json)
            if confirm_risk_action "$(localized_text "重启 x-ui/3x-ui" "Restart x-ui/3x-ui" "Перезагрузите x-ui/3x-ui.")" \
                "$(localized_text "x-ui/3x-ui 面板进程和 config.json 运行配置" "x-ui/3x-ui panel process and config.json running configuration" "Процесс и конфигурация панели x-ui/3x-ui. Текущая конфигурация json")" \
                "$(localized_text "恢复 ${target_file}.bak_* 后重启面板，或用官方 x-ui/3x-ui 命令进入管理菜单修复" "Restore ${target_file}.bak_* and then restart the panel, or use the official x-ui/3x-ui command to enter the management menu to repair" "Восстановите ${target_file}.bak_*, а затем перезапустите панель или используйте официальную команду x-ui/3x-ui, чтобы войти в меню управления для восстановления.")" \
                "$(localized_text "确认面板端口、证书路径和 443端口复用设置匹配。" "Verify that the panel port, certificate path, and Port 443 Reuse settings match." "Убедитесь, что порт панели, путь к сертификату и настройки записи общего ресурса 443 совпадают.")"; then
                restart_named_service_if_available x-ui
                restart_named_service_if_available 3x-ui
            else
                echo -e "$(localized_text "${YELLOW}⚠️ x-ui/3x-ui 未重启，修改可能尚未生效。${PLAIN}" "${YELLOW}⚠️ x-ui/3x-ui has not been restarted, and the modification may not yet take effect.${PLAIN}" "${YELLOW}⚠️ x-ui/3x-ui не был перезапущен, и модификация может еще не вступить в силу.${PLAIN}")"
            fi
            ;;
        env|hosts)
            echo -e "$(localized_text "${BLUE}配置已保存；该文件通常由系统或脚本后续读取，无需立即 reload。${PLAIN}" "${BLUE}Configuration has been saved; this file is usually read later by the system or script and does not need to be reloaded immediately.${PLAIN}" "${BLUE}Конфигурация сохранена; этот файл обычно читается позже системой или сценарием, и его не нужно перезагружать немедленно.${PLAIN}")"
            ;;
        *)
            echo -e "$(localized_text "${BLUE}配置已保存；未为 ${kind} 定义自动 reload。${PLAIN}" "${BLUE}Configuration saved; no automatic reload is defined for ${kind}.${PLAIN}" "${BLUE}Конфигурация сохранена; для ${kind} автоматическая перезагрузка не определена.${PLAIN}")"
            ;;
    esac
}

edit_applied_config_file() {
    local target_file="$1"
    local target_kind="$2"
    local target_label="${3:-$1}"
    local backup_file editor confirm rollback_confirm

    [[ -e "$target_file" || -L "$target_file" ]] || { echo -e "$(localized_text "${RED}❌ 文件不存在：${target_file}${PLAIN}" "${RED}❌ File does not exist: ${target_file}${PLAIN}" "${RED}❌ Файл не существует: ${target_file}${PLAIN}")"; return 1; }
    [[ -f "$target_file" || -L "$target_file" ]] || { echo -e "$(localized_text "${RED}❌ 不是普通配置文件：${target_file}${PLAIN}" "${RED}❌ is not an ordinary configuration file: ${target_file}${PLAIN}" "${RED}❌ — это не обычный файл конфигурации: ${target_file}.${PLAIN}")"; return 1; }

    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    echo -e "$(localized_text "${BOLD}当前文件：${target_label}${PLAIN}" "${BOLD}Current file: ${target_label}${PLAIN}" "${BOLD}Текущий файл: ${target_label}${PLAIN}")"
    echo -e "${CYAN}${target_file}${PLAIN}"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    nl -ba "$target_file"
    echo -e "${CYAN}------------------------------------------------${PLAIN}"
    read_trimmed confirm "$(localized_text "是否打开编辑器修改该文件？(Y/n，默认 y): " "Do you want to open an editor to modify the file? (Y/n, default y):" "Хотите открыть редактор и изменить файл? (Да/нет, по умолчанию y):")"
    is_yes "$confirm" || return 0

    editor=$(applied_config_editor_command) || {
        echo -e "$(localized_text "${RED}❌ 未找到可用编辑器。请先安装 nano/vim/vi，或设置 EDITOR。${PLAIN}" "${RED}❌ No available editor found. Please install nano/vim/vi first, or set up EDITOR.${PLAIN}" "${RED}❌ Доступный редактор не найден. Пожалуйста, сначала установите nano/vim/vi или настройте РЕДАКТОР.${PLAIN}")"
        return 1
    }
    backup_file="${target_file}.bak_$(date +%s)"
    cp -p "$target_file" "$backup_file" || { echo -e "$(localized_text "${RED}❌ 备份失败，已取消编辑。${PLAIN}" "${RED}❌ Backup failed, editing canceled.${PLAIN}" "${RED}❌ Не удалось выполнить резервное копирование, редактирование отменено.${PLAIN}")"; return 1; }
    echo -e "$(localized_text "${CYAN}编辑前备份：${backup_file}${PLAIN}" "${CYAN}Backup before editing: ${backup_file}${PLAIN}" "${CYAN}Резервная копия перед редактированием: ${backup_file}${PLAIN}")"

    "$editor" "$target_file" || {
        echo -e "$(localized_text "${RED}❌ 编辑器异常退出，配置未重新加载。${PLAIN}" "${RED}❌ The editor exited abnormally and the configuration was not reloaded.${PLAIN}" "${RED}❌ Редактор завершился аварийно, и конфигурация не была перезагружена.${PLAIN}")"
        return 1
    }

    if cmp -s "$target_file" "$backup_file"; then
        echo -e "$(localized_text "${BLUE}配置未变化。${PLAIN}" "${BLUE}The configuration has not changed.${PLAIN}" "${BLUE}Конфигурация не изменилась.${PLAIN}")"
        return 0
    fi

    echo -e "$(localized_text "${CYAN}▶ 正在校验配置...${PLAIN}" "${CYAN}▶ Verifying configuration...${PLAIN}" "${CYAN}▶ Проверка конфигурации...${PLAIN}")"
    if ! validate_applied_config_kind "$target_kind" "$target_file"; then
        echo -e "$(localized_text "${RED}❌ 校验失败，服务不会 reload。${PLAIN}" "${RED}❌ The verification failed and the service will not reload.${PLAIN}" "${RED}❌ Проверка не удалась, и служба не перезагрузится.${PLAIN}")"
        read_trimmed rollback_confirm "$(localized_text "是否恢复编辑前备份？(Y/n，默认 yes): " "Restore pre-edit backup? (Y/n, default yes):" "Восстановить предварительно отредактированную резервную копию? (Да/нет, по умолчанию да):")"
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && echo -e "$(localized_text "${GREEN}✅ 已恢复：${target_file}${PLAIN}" "${GREEN}✅ Restored: ${target_file}${PLAIN}" "${GREEN}✅ Восстановлено: ${target_file}${PLAIN}")"
        else
            echo -e "$(localized_text "${YELLOW}⚠️ 已保留未通过校验的修改，请手动修正后再应用。${PLAIN}" "${YELLOW}⚠️ The modifications that failed the verification have been retained. Please correct them manually before applying them.${PLAIN}" "${YELLOW}⚠️ Модификации, не прошедшие проверку, сохранены. Пожалуйста, исправьте их вручную перед применением.${PLAIN}")"
        fi
        return 1
    fi

    if reload_applied_config_kind "$target_kind" "$target_file" "$backup_file"; then
        echo -e "$(localized_text "${GREEN}✅ 配置已保存并完成可执行的校验/应用步骤。${PLAIN}" "${GREEN}✅ Configuration saved and executable verification/application steps completed.${PLAIN}" "${GREEN}✅ Конфигурация сохранена, исполняемые этапы проверки/приложения выполнены.${PLAIN}")"
        echo -e "$(localized_text "${CYAN}备份文件：${backup_file}${PLAIN}" "${CYAN}Backup file: ${backup_file}${PLAIN}" "${CYAN}Файл резервной копии : ${backup_file}${PLAIN}")"
    else
        echo -e "$(localized_text "${RED}❌ 配置校验通过，但应用/reload 失败。${PLAIN}" "${RED}❌ configuration validation passed, but application/reload failed.${PLAIN}" "${RED}❌ Проверка конфигурации пройдена, но приложение/перезагрузка не удалась.${PLAIN}")"
        read_trimmed rollback_confirm "$(localized_text "是否恢复编辑前备份？(Y/n，默认 yes): " "Restore pre-edit backup? (Y/n, default yes):" "Восстановить предварительно отредактированную резервную копию? (Да/нет, по умолчанию да):")"
        if ! is_no "$rollback_confirm"; then
            cp -p "$backup_file" "$target_file" && reload_applied_config_kind "$target_kind" "$target_file" >/dev/null 2>&1 || true
            echo -e "$(localized_text "${GREEN}✅ 已尝试恢复编辑前配置。${PLAIN}" "${GREEN}✅ An attempt has been made to restore the pre-edit configuration.${PLAIN}" "${GREEN}✅ Предпринята попытка восстановить предредактированную конфигурацию.${PLAIN}")"
        fi
        return 1
    fi
}

func_edit_applied_config_center() {
    local scope="${1:-all}"
    local -a applied_config_labels=()
    local -a applied_config_paths=()
    local -a applied_config_kinds=()
    collect_applied_config_files "$scope"

    clear
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ "$scope" == "proxy" ]]; then
        echo -e "$(localized_text "${BOLD}📝 查看/编辑已应用反代配置${PLAIN}" "${BOLD}📝 View/edit applied reverse proxy configuration${PLAIN}" "${BOLD}📝 Просмотр/редактирование примененной конфигурации обратного прокси-сервера${PLAIN}")"
    else
        echo -e "$(localized_text "${BOLD}📝 查看/编辑脚本已应用配置${PLAIN}" "${BOLD}📝 View/edit script has applied configuration${PLAIN}" "${BOLD}📝 Скрипт просмотра/редактирования применил конфигурацию${PLAIN}")"
    fi
    echo -e "${CYAN}================================================${PLAIN}"
    if [[ ${#applied_config_paths[@]} -eq 0 ]]; then
        echo -e "$(localized_text "${YELLOW}未检测到可编辑的已应用配置文件。${PLAIN}" "${YELLOW}No editable applied profile detected.${PLAIN}" "${YELLOW}Не обнаружен редактируемый прикладной профиль.${PLAIN}")"
        return 0
    fi

    local i
    for i in "${!applied_config_paths[@]}"; do
        printf '%b%3d. %s%b\n' "$GREEN" "$((i + 1))" "${applied_config_labels[$i]} -> ${applied_config_paths[$i]}" "$PLAIN"
    done
    echo -e "$(localized_text "${RED}  0. 取消${PLAIN}" "${RED}0. Cancel${PLAIN}" "${RED}0. Отмена${PLAIN}")"
    echo -e "${CYAN}================================================${PLAIN}"

    local choice idx
    read_trimmed choice "$(localized_text "选择要查看 / 编辑的配置文件: " "Select a configuration file to view or edit: " "Выберите файл конфигурации для просмотра или правки: ")"
    [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "Q" ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#applied_config_paths[@]} )); then
        echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
        return 1
    fi

    idx=$((choice - 1))
    edit_applied_config_file "${applied_config_paths[$idx]}" "${applied_config_kinds[$idx]}" "${applied_config_labels[$idx]}"
}

func_backup_center() {
    local backup_root="/etc/vps-optimize/backups/manual"
    local loaded_archive=""
    mkdir -p "$backup_root"
    chmod 700 "$backup_root" 2>/dev/null || true

    while true; do
        clear
        echo -e "${CYAN}================================================${PLAIN}"
        print_breadcrumb "$(localized_text "备份与回滚" "Backup and rollback" "Резервное копирование и откат")"
        echo -e "$(localized_text "${BOLD}🗂️ 配置备份与回滚${PLAIN}" "${BOLD}🗂️ Configuration backup and rollback${PLAIN}" "${BOLD}🗂️ Резервное копирование и откат конфигурации${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"
        echo -e "$(localized_text "当前备份目录: ${YELLOW}${backup_root}${PLAIN}" "Current backup directory: ${YELLOW}${backup_root}${PLAIN}" "Текущий каталог резервной копии: ${YELLOW}${backup_root}${PLAIN}.")"
        [[ -n "$loaded_archive" && ! -r "$loaded_archive" ]] && loaded_archive=""
        [[ -n "$loaded_archive" ]] && echo -e "$(localized_text "已加载备份包: ${YELLOW}$(basename "$loaded_archive")${PLAIN}" "Loaded backup archive: ${YELLOW}$(basename "$loaded_archive")${PLAIN}" "Загруженный архив резервной копии: ${YELLOW}$(basename "$loaded_archive")${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${GREEN}  1. 创建备份${PLAIN} ${YELLOW}(配置 / 自定义目录 / 两者)${PLAIN}" "${GREEN}  1. Create a backup${PLAIN} ${YELLOW}(configuration / custom directories / both)${PLAIN}" "${GREEN}  1. Создать резервную копию${PLAIN} ${YELLOW}(конфигурация / свои каталоги / оба варианта)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  2. 加载备份包${PLAIN} ${YELLOW}(.tar.gz / 加密 .tar.gz.enc)${PLAIN}" "${GREEN}  2. Load a backup archive${PLAIN} ${YELLOW}(.tar.gz / encrypted .tar.gz.enc)${PLAIN}" "${GREEN}  2. Загрузить архив резервной копии${PLAIN} ${YELLOW}(.tar.gz / зашифрованный .tar.gz.enc)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  3. 从备份恢复${PLAIN} ${YELLOW}(已加载 / 自动列表 / 指定路径)${PLAIN}" "${GREEN}  3. Restore from a backup${PLAIN} ${YELLOW}(loaded / detected / specified path)${PLAIN}" "${GREEN}  3. Восстановить из резервной копии${PLAIN} ${YELLOW}(загруженная / найденная / указанный путь)${PLAIN}")"
        echo -e "$(localized_text "${GREEN}  4. 隔离旧备份${PLAIN} ${YELLOW}(保留最近 5 份)${PLAIN}" "${GREEN}  4. Quarantine old backups${PLAIN} ${YELLOW}(keep the latest 5)${PLAIN}" "${GREEN}  4. Изолировать старые копии${PLAIN} ${YELLOW}(сохранить последние 5)${PLAIN}")"
        echo -e "$(localized_text "${CYAN}  5. 查看 / 编辑已应用配置${PLAIN} ${YELLOW}(备份、校验、reload / restart)${PLAIN}" "${CYAN}  5. View or edit applied configuration${PLAIN} ${YELLOW}(backup, validate, reload / restart)${PLAIN}" "${CYAN}  5. Просмотр или правка применённой конфигурации${PLAIN} ${YELLOW}(копия, проверка, reload / restart)${PLAIN}")"
        echo -e "------------------------------------------------"
        echo -e "$(localized_text "${BLUE}  ?. 查看帮助${PLAIN}" "${BLUE}?. View help${PLAIN}" "${BLUE}?. Посмотреть справку${PLAIN}")"
        echo -e "$(localized_text "${RED}  0. 返回主菜单 / q 返回上一级${PLAIN}" "${RED}0. Main menu / q Back${PLAIN}" "${RED}0. Главное меню / q Назад${PLAIN}")"
        echo -e "${CYAN}================================================${PLAIN}"

        local b_choice
        read_trimmed b_choice "$(localized_text "选择操作: " "Select an option: " "Выберите действие: ")"

        case $b_choice in
            1)
                local backup_scope scope_choice ts
                ts=$(date +%Y%m%d_%H%M%S)
                local work_dir
                local tar_file
                local manifest_file
                local copied=0
                local encrypt_choice=""
                local backup_password=""
                local -a custom_directories=()
                local -a BACKUP_COPY_FAILURES=()

                echo -e "$(localized_text "${BOLD}备份范围${PLAIN}" "${BOLD}Backup scope${PLAIN}" "${BOLD}Область резервного копирования${PLAIN}")"
                echo -e "  1. $(localized_text "脚本与服务配置（默认）" "Script and service configuration (default)" "Конфигурация скрипта и служб (по умолчанию)")"
                echo -e "  2. $(localized_text "自定义系统目录" "Custom system directories" "Пользовательские системные каталоги")"
                echo -e "  3. $(localized_text "配置 + 自定义系统目录" "Configuration + custom system directories" "Конфигурация + пользовательские системные каталоги")"
                echo -e "  0. $(localized_text "取消" "Cancel" "Отмена")"
                read_trimmed scope_choice "$(localized_text "选择备份范围: " "Select backup scope: " "Выберите область резервного копирования: ")"
                case "$scope_choice" in
                    1) backup_scope="managed" ;;
                    2) backup_scope="custom" ;;
                    3) backup_scope="both" ;;
                    0|q|Q) continue ;;
                    *)
                        echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
                        continue
                        ;;
                esac
                if [[ "$backup_scope" == "custom" || "$backup_scope" == "both" ]]; then
                    echo -e "$(localized_text "${YELLOW}数据库或 Docker 数据目录请先停止相关服务，文件复制不保证运行中数据一致。${PLAIN}" "${YELLOW}Stop related services before backing up database or Docker data directories; file copying does not guarantee consistency for active data.${PLAIN}" "${YELLOW}Перед резервным копированием каталогов баз данных или Docker остановите связанные службы: копирование файлов не гарантирует согласованность активных данных.${PLAIN}")"
                    if ! backup_collect_custom_directories custom_directories; then
                        echo -e "$(localized_text "${YELLOW}未填写可备份目录，已取消。${PLAIN}" "${YELLOW}No backupable directory entered; canceled.${PLAIN}" "${YELLOW}Не указан каталог для резервного копирования; операция отменена.${PLAIN}")"
                        continue
                    fi
                    confirm_risk_action \
                        "$(localized_text "备份自定义系统目录" "Back up custom system directories" "Создать резервную копию пользовательских системных каталогов")" \
                        "$(localized_text "复制所选目录到权限为 600 的压缩包；运行中的数据库或 Docker 数据可能处于不一致状态。" "Copy the selected directories into a mode-600 archive. Active databases or Docker data may be inconsistent." "Скопировать выбранные каталоги в архив с правами 600. Активные базы данных и данные Docker могут оказаться несогласованными.")" \
                        "$(localized_text "备份不会修改源目录；若需一致快照，请先停止相关服务后重新创建备份。" "The source directories are not modified. Stop related services and recreate the backup if a consistent snapshot is required." "Исходные каталоги не изменяются. Для согласованной копии остановите связанные службы и создайте архив заново.")" || continue
                fi
                backup_select_archive_directory "$backup_root" || continue
                read_trimmed encrypt_choice "$(localized_text "是否使用 AES-256 加密备份？(y/N，默认 N): " "Encrypt the backup with AES-256? (y/N, default N): " "Зашифровать резервную копию с помощью AES-256? (y/N, по умолчанию N): ")"
                if is_yes "$encrypt_choice"; then
                    if ! command -v openssl >/dev/null 2>&1; then
                        echo -e "$(localized_text "${RED}❌ 缺少 openssl，无法创建加密备份。${PLAIN}" "${RED}❌ openssl is required to create an encrypted backup.${PLAIN}" "${RED}❌ Для создания зашифрованной копии требуется openssl.${PLAIN}")"
                        continue
                    fi
                    backup_read_new_password backup_password
                    tar_file="${BACKUP_ARCHIVE_ROOT}/backup_${ts}.tar.gz.enc"
                else
                    tar_file="${BACKUP_ARCHIVE_ROOT}/backup_${ts}.tar.gz"
                fi

                work_dir=$(make_secure_temp_dir "vps_backup_${ts}") || {
                    echo -e "$(localized_text "${RED}❌ 无法创建安全临时目录，备份已取消。${PLAIN}" "${RED}❌ Unable to create secure temporary directory, backup canceled.${PLAIN}" "${RED}❌ Невозможно создать безопасный временный каталог, резервное копирование отменено.${PLAIN}")"
                    sleep 2
                    continue
                }
                manifest_file="${work_dir}/manifest.txt"
                {
                    echo "VPS-Optimize backup manifest"
                    echo "Created: $(date -Is 2>/dev/null || date)"
                    echo "Backup file: ${tar_file}"
                    echo "Scope: ${backup_scope}"
                    echo "Included paths:"
                } > "$manifest_file"

                if [[ "$backup_scope" == "managed" || "$backup_scope" == "both" ]]; then
                    backup_copy_managed_configuration "$manifest_file" "$work_dir" && copied=1
                fi
                if [[ "$backup_scope" == "custom" || "$backup_scope" == "both" ]]; then
                    backup_copy_custom_directories "$manifest_file" "$work_dir" custom_directories && copied=1
                fi

                if (( ${#BACKUP_COPY_FAILURES[@]} > 0 )); then
                    backup_cleanup_temp_dir "$work_dir" || true
                    echo -e "$(localized_text "${RED}❌ 以下路径复制失败，未创建不完整备份：${BACKUP_COPY_FAILURES[*]}${PLAIN}" "${RED}❌ These paths could not be copied; an incomplete backup was not created: ${BACKUP_COPY_FAILURES[*]}${PLAIN}" "${RED}❌ Не удалось скопировать следующие пути; неполная резервная копия не создана: ${BACKUP_COPY_FAILURES[*]}${PLAIN}")"
                elif [[ "$copied" -eq 0 ]]; then
                    backup_cleanup_temp_dir "$work_dir" || true
                    echo -e "$(localized_text "${YELLOW}⚠️ 未检测到可备份配置文件，已取消创建。${PLAIN}" "${YELLOW}⚠️ The backupable configuration file was not detected and the creation has been cancelled.${PLAIN}" "${YELLOW}⚠️ Резервный файл конфигурации не обнаружен, и его создание отменено.${PLAIN}")"
                else
                    local backup_payload_bytes
                    backup_payload_bytes=$(backup_path_size_bytes "$work_dir") || backup_payload_bytes=0
                    if ! backup_require_free_space "$BACKUP_ARCHIVE_ROOT" "$backup_payload_bytes" "$(localized_text "创建备份" "Backup creation" "Создание резервной копии")"; then
                        backup_cleanup_temp_dir "$work_dir" || true
                        continue
                    fi
                    if backup_create_archive "$work_dir" "$tar_file" "$backup_password"; then
                        backup_password=""
                        chmod 600 "$tar_file" 2>/dev/null || true
                        backup_register_archive_root "$BACKUP_ARCHIVE_ROOT" || true
                        loaded_archive="$tar_file"
                        echo -e "$(localized_text "${GREEN}✅ 备份创建成功: ${tar_file}${PLAIN}" "${GREEN}✅ Backup created successfully: ${tar_file}${PLAIN}" "${GREEN}. Резервная копия успешно создана: ${tar_file}.${PLAIN}")"
                        echo -e "$(localized_text "已加载备份包: $(basename "$tar_file")，可在 [3] -> [1] 恢复。" "Loaded backup archive: $(basename "$tar_file"). Restore it with [3] -> [1]." "Загружен архив: $(basename "$tar_file"). Восстановление: [3] -> [1].")"
                        if backup_archive_is_encrypted "$tar_file"; then
                            echo -e "$(localized_text "${YELLOW}⚠️ 加密密码不会保存；丢失后无法恢复该备份。${PLAIN}" "${YELLOW}⚠️ The encryption password is not stored. The backup cannot be restored if the password is lost.${PLAIN}" "${YELLOW}⚠️ Пароль шифрования не сохраняется. Без него восстановить копию невозможно.${PLAIN}")"
                        else
                            echo -e "$(localized_text "${YELLOW}⚠️ 备份包含证书私钥、面板数据库和 API Token；文件权限已设为 600，请勿公开传输。${PLAIN}" "${YELLOW}⚠️ This archive contains certificate keys, panel databases, and API tokens. Its mode is 600; do not transfer it publicly.${PLAIN}" "${YELLOW}⚠️ Архив содержит закрытые ключи, базы данных панели и API-токены. Права установлены в 600; не передавайте его публично.${PLAIN}")"
                        fi
                    else
                        backup_password=""
                        rm -f -- "$tar_file"
                        echo -e "$(localized_text "${RED}❌ 备份打包失败，请检查磁盘空间与权限。${PLAIN}" "${RED}❌ Backup packaging failed, please check the disk space and permissions.${PLAIN}" "${RED}❌ Не удалось создать резервную копию, проверьте место на диске и разрешения.${PLAIN}")"
                    fi
                    backup_cleanup_temp_dir "$work_dir" || true
                fi
                ;;

            2)
                backup_select_available_archive loaded_archive || true
                [[ -n "$loaded_archive" ]] && echo -e "$(localized_text "${GREEN}✅ 已加载: ${loaded_archive}${PLAIN}" "${GREEN}✅ Loaded: ${loaded_archive}${PLAIN}" "${GREEN}✅ Загружено: ${loaded_archive}${PLAIN}")"
                ;;

            3)
                local restore_source target_file
                echo -e "  1. $(localized_text "已加载备份包" "Loaded backup archive" "Загруженный архив резервной копии")"
                echo -e "  2. $(localized_text "自动读取的备份列表" "Automatically detected backup list" "Автоматически найденный список копий")"
                echo -e "  3. $(localized_text "指定备份包路径" "Specify backup archive path" "Указать путь к архиву резервной копии")"
                echo -e "  0. $(localized_text "取消" "Cancel" "Отмена")"
                read_trimmed restore_source "$(localized_text "选择恢复来源: " "Select restore source: " "Выберите источник восстановления: ")"
                case "$restore_source" in
                    1)
                        if ! backup_archive_is_readable "$loaded_archive"; then
                            echo -e "$(localized_text "${YELLOW}⚠️ 尚未加载可用备份包。${PLAIN}" "${YELLOW}⚠️ No usable backup archive is loaded.${PLAIN}" "${YELLOW}⚠️ Доступный архив резервной копии не загружен.${PLAIN}")"
                            read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                            continue
                        fi
                        target_file="$loaded_archive"
                        ;;
                    2)
                        backup_select_available_archive target_file || continue
                        loaded_archive="$target_file"
                        ;;
                    3)
                        IFS= read -r -p "$(localized_text "备份包绝对路径（.tar.gz 或 .tar.gz.enc）: " "Absolute backup archive path (.tar.gz or .tar.gz.enc): " "Абсолютный путь к архиву (.tar.gz или .tar.gz.enc): ")" target_file || continue
                        target_file=$(trim_input "$target_file")
                        if ! backup_archive_is_readable "$target_file"; then
                            echo -e "$(localized_text "${RED}❌ 未找到可读取的 .tar.gz 或 .tar.gz.enc 备份包。${PLAIN}" "${RED}❌ A readable .tar.gz or .tar.gz.enc backup archive was not found.${PLAIN}" "${RED}❌ Не найден доступный для чтения архив .tar.gz или .tar.gz.enc.${PLAIN}")"
                            continue
                        fi
                        loaded_archive="$target_file"
                        ;;
                    0|q|Q) continue ;;
                    *)
                        echo -e "$(localized_text "${RED}❌ 无效选择。${PLAIN}" "${RED}❌ Invalid selection.${PLAIN}" "${RED}❌ Неверный выбор.${PLAIN}")"
                        continue
                        ;;
                esac

                local restore_dir restore_archive restore_password
                local restore_failed=0
                local restore_quarantine="/etc/vps-optimize/quarantine/manual-restore"
                restore_dir=$(make_secure_temp_dir "vps_restore") || {
                    echo -e "$(localized_text "${RED}❌ 无法创建安全临时目录，回滚中止。${PLAIN}" "${RED}❌ Unable to create secure temporary directory, rollback aborted.${PLAIN}" "${RED}❌ Невозможно создать безопасный временный каталог, откат прерван.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                }
                restore_archive="$target_file"
                restore_password=""
                if backup_archive_is_encrypted "$target_file"; then
                    if ! command -v openssl >/dev/null 2>&1; then
                        backup_cleanup_temp_dir "$restore_dir" || true
                        echo -e "$(localized_text "${RED}❌ 缺少 openssl，无法解密该备份。${PLAIN}" "${RED}❌ openssl is required to decrypt this backup.${PLAIN}" "${RED}❌ Для расшифровки этой копии требуется openssl.${PLAIN}")"
                        continue
                    fi
                    read_secret_trimmed restore_password "$(localized_text "备份解密密码: " "Backup decryption password: " "Пароль для расшифровки: ")"
                    if [[ -z "$restore_password" ]]; then
                        backup_cleanup_temp_dir "$restore_dir" || true
                        echo -e "$(localized_text "${YELLOW}未输入密码，恢复已取消。${PLAIN}" "${YELLOW}No password was entered; restore canceled.${PLAIN}" "${YELLOW}Пароль не введён; восстановление отменено.${PLAIN}")"
                        continue
                    fi
                    local encrypted_archive_bytes
                    encrypted_archive_bytes=$(backup_path_size_bytes "$target_file") || encrypted_archive_bytes=0
                    if ! backup_require_free_space "$restore_dir" "$encrypted_archive_bytes" "$(localized_text "解密备份" "Backup decryption" "Расшифровка резервной копии")"; then
                        restore_password=""
                        backup_cleanup_temp_dir "$restore_dir" || true
                        continue
                    fi
                    restore_archive="${restore_dir}/.decrypted-backup.tar.gz"
                    if ! backup_decrypt_archive "$target_file" "$restore_archive" "$restore_password"; then
                        restore_password=""
                        rm -f -- "$restore_archive"
                        backup_cleanup_temp_dir "$restore_dir" || true
                        echo -e "$(localized_text "${RED}❌ 解密失败：密码错误或文件已损坏。${PLAIN}" "${RED}❌ Decryption failed: the password is incorrect or the file is damaged.${PLAIN}" "${RED}❌ Ошибка расшифровки: неверный пароль или повреждённый файл.${PLAIN}")"
                        continue
                    fi
                    restore_password=""
                fi

                if ! tar -tzf "$restore_archive" >/dev/null 2>&1; then
                    [[ "$restore_archive" == "$target_file" ]] || rm -f -- "$restore_archive"
                    backup_cleanup_temp_dir "$restore_dir" || true
                    echo -e "$(localized_text "${RED}❌ 备份文件无法读取，回滚中止。${PLAIN}" "${RED}❌ The backup file cannot be read and the rollback is aborted.${PLAIN}" "${RED}❌ Файл резервной копии не может быть прочитан, и откат прерывается.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi
                if tar -tzf "$restore_archive" 2>/dev/null | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
                    [[ "$restore_archive" == "$target_file" ]] || rm -f -- "$restore_archive"
                    backup_cleanup_temp_dir "$restore_dir" || true
                    echo -e "$(localized_text "${RED}❌ 备份文件包含不安全路径，回滚中止。${PLAIN}" "${RED}❌ The backup file contains an unsafe path and the rollback is aborted.${PLAIN}" "${RED}❌ Файл резервной копии содержит небезопасный путь, и откат прерывается.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi

                local unpacked_bytes
                unpacked_bytes=$(backup_archive_unpacked_size_bytes "$restore_archive") || unpacked_bytes=0
                if ! backup_require_free_space "$restore_dir" "$unpacked_bytes" "$(localized_text "解压备份" "Backup extraction" "Распаковка резервной копии")"; then
                    [[ "$restore_archive" == "$target_file" ]] || rm -f -- "$restore_archive"
                    backup_cleanup_temp_dir "$restore_dir" || true
                    continue
                fi

                if ! tar -xzf "$restore_archive" -C "$restore_dir" >/dev/null 2>&1; then
                    [[ "$restore_archive" == "$target_file" ]] || rm -f -- "$restore_archive"
                    backup_cleanup_temp_dir "$restore_dir" || true
                    echo -e "$(localized_text "${RED}❌ 备份解压失败，回滚中止。${PLAIN}" "${RED}❌ Backup decompression failed and rollback aborted.${PLAIN}" "${RED}❌ Не удалось распаковать резервную копию, и откат прерван.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                fi
                [[ "$restore_archive" == "$target_file" ]] || rm -f -- "$restore_archive"

                backup_restore_preflight "$restore_dir"
                confirm_danger "$(localized_text "确认从备份恢复" "Confirm backup restore" "Подтвердите восстановление из резервной копии")" "$(localized_text "会覆盖 SSH、Caddy、Docker、Fail2ban、sysctl 及备份中的自定义系统目录。" "It will overwrite SSH, Caddy, Docker, Fail2ban, sysctl, and custom system directories in the backup." "Будут перезаписаны SSH, Caddy, Docker, Fail2ban, sysctl и пользовательские системные каталоги из резервной копии.")" "$(localized_text "恢复后脚本会尝试重启已安装服务；请保持当前 SSH 会话并准备好云厂商救援控制台。" "After restoring, the script will try to restart installed services. Keep the current SSH session and prepare the cloud rescue console." "После восстановления скрипт попытается перезапустить установленные службы. Сохраните текущий сеанс SSH и подготовьте облачную консоль восстановления.")" || {
                    backup_cleanup_temp_dir "$restore_dir" || true
                    echo -e "$(localized_text "${BLUE}已取消恢复操作。${PLAIN}" "${BLUE}Restore operation canceled.${PLAIN}" "${BLUE}Операция восстановления отменена.${PLAIN}")"
                    read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                    continue
                }

                if [[ -f "$restore_dir/etc/vps-optimize/traffic-guard.conf" || -f "$restore_dir/usr/local/bin/vps-traffic-guard-check" ]]; then
                    if declare -F traffic_guard_restore_ssh_only_firewall >/dev/null 2>&1 && ! traffic_guard_restore_ssh_only_firewall; then
                        backup_cleanup_temp_dir "$restore_dir" || true
                        echo -e "$(localized_text "${RED}❌ 无法解除当前仅保留 SSH 封锁规则，回滚中止。${PLAIN}" "${RED}❌ Unable to unblock the current blocking rule of SSH, the rollback is aborted.${PLAIN}" "${RED}❌ Невозможно разблокировать текущее правило блокировки SSH, откат прерывается.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    fi
                fi

                restore_backup_file "$restore_dir/etc/ssh/sshd_config" /etc/ssh/sshd_config || restore_failed=1
                restore_backup_file "$restore_dir/etc/hostname" /etc/hostname || restore_failed=1
                restore_backup_file "$restore_dir/etc/hosts" /etc/hosts || restore_failed=1
                restore_backup_file "$restore_dir/etc/nginx/nginx.conf" /etc/nginx/nginx.conf || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/stream.d" /etc/nginx/stream.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/conf.d" /etc/nginx/conf.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/sites-available" /etc/nginx/sites-available "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/nginx/sites-enabled" /etc/nginx/sites-enabled "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/etc/caddy/Caddyfile" /etc/caddy/Caddyfile || restore_failed=1
                restore_backup_dir "$restore_dir/etc/caddy/conf.d" /etc/caddy/conf.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/caddy/certs" /etc/caddy/certs "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/root/cert" /root/cert "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/root/.acme.sh" /root/.acme.sh "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/root/.config/vps-panel/cloudflare.env" /root/.config/vps-panel/cloudflare.env || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/sni-stack.env" /etc/vps-optimize/sni-stack.env || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/sni-stack.last-backup" /etc/vps-optimize/sni-stack.last-backup || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/443-engine.conf" /etc/vps-optimize/443-engine.conf || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/vpso-mux.yaml" /etc/vps-optimize/vpso-mux.yaml || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/system/vpso-mux.service" /etc/systemd/system/vpso-mux.service || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/bin/vpso-mux" /usr/local/bin/vpso-mux || restore_failed=1
                restore_backup_file "$restore_dir/etc/vps-optimize/traffic-guard.conf" /etc/vps-optimize/traffic-guard.conf || restore_failed=1
                restore_backup_dir "$restore_dir/var/lib/vps-optimize/traffic-guard" /var/lib/vps-optimize/traffic-guard "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/bin/vps-traffic-guard-check" /usr/local/bin/vps-traffic-guard-check || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/system/vps-traffic-guard.service" /etc/systemd/system/vps-traffic-guard.service || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/system/vps-traffic-guard.timer" /etc/systemd/system/vps-traffic-guard.timer || restore_failed=1
                restore_backup_file "$restore_dir/etc/resolv.conf" /etc/resolv.conf || restore_failed=1
                restore_backup_file "$restore_dir/etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf" /etc/systemd/resolved.conf.d/99-vps-optimize-dns.conf || restore_failed=1
                restore_backup_file "$restore_dir/etc/docker/daemon.json" /etc/docker/daemon.json || restore_failed=1
                restore_backup_file "$restore_dir/etc/fail2ban/jail.local" /etc/fail2ban/jail.local || restore_failed=1
                restore_backup_dir "$restore_dir/etc/sysctl.d" /etc/sysctl.d "$restore_quarantine" || restore_failed=1
                restore_backup_dir "$restore_dir/etc/x-ui" /etc/x-ui "$restore_quarantine" || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/x-ui.db" /usr/local/x-ui/x-ui.db || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/x-ui.db-wal" /usr/local/x-ui/x-ui.db-wal || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/x-ui.db-shm" /usr/local/x-ui/x-ui.db-shm || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/bin/x-ui.db" /usr/local/x-ui/bin/x-ui.db || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/bin/x-ui.db-wal" /usr/local/x-ui/bin/x-ui.db-wal || restore_failed=1
                restore_backup_file "$restore_dir/usr/local/x-ui/bin/x-ui.db-shm" /usr/local/x-ui/bin/x-ui.db-shm || restore_failed=1
                backup_restore_custom_directories "$restore_dir" "$restore_quarantine" || restore_failed=1

                if [[ -d "$restore_dir/etc/sysctl.d" ]]; then
                    sysctl --system >/dev/null 2>&1
                fi
                if [[ -f "$restore_dir/etc/hostname" ]]; then
                    local restored_hostname
                    restored_hostname=$(cat /etc/hostname 2>/dev/null | head -n1)
                    restored_hostname="$(trim_input "$restored_hostname")"
                    if [[ -n "$restored_hostname" ]]; then
                        hostnamectl set-hostname "$restored_hostname" >/dev/null 2>&1 || hostname "$restored_hostname" 2>/dev/null || true
                    fi
                fi
                if [[ -f "$restore_dir/etc/systemd/system/vps-traffic-guard.timer" || -f "$restore_dir/etc/systemd/system/vps-traffic-guard.service" || -f "$restore_dir/etc/systemd/system/vpso-mux.service" ]]; then
                    systemctl daemon-reload >/dev/null 2>&1 || true
                fi

                local restart_failed=0
                local restart_rc=0
                restart_service_if_available sshd
                restart_rc=$?
                if [[ "$restart_rc" -eq 2 ]]; then
                    restart_service_if_available ssh
                    restart_rc=$?
                fi
                [[ "$restart_rc" -eq 1 ]] && restart_failed=1

                for svc in nginx caddy docker fail2ban systemd-resolved x-ui 3x-ui xray sing-box vpso-mux; do
                    restart_service_if_available "$svc"
                    restart_rc=$?
                    [[ "$restart_rc" -eq 1 ]] && restart_failed=1
                done

                backup_cleanup_temp_dir "$restore_dir" || true
                if [[ "$restore_failed" -eq 0 && "$restart_failed" -eq 0 ]]; then
                    echo -e "$(localized_text "${GREEN}✅ 回滚完成！建议立即验证 SSH、反代和容器服务状态。${PLAIN}" "${GREEN}✅ Rollback completed! It is recommended to verify SSH, reverse proxy and container service status immediately.${PLAIN}" "${GREEN}✅ Откат завершен! Рекомендуется немедленно проверить статус SSH, обратный прокси и контейнерной службы.${PLAIN}")"
                elif [[ "$restore_failed" -ne 0 ]]; then
                    echo -e "$(localized_text "${YELLOW}⚠️ 部分备份文件恢复失败，请检查权限、磁盘空间和 ${restore_quarantine}。${PLAIN}" "${YELLOW}⚠️ Partial backup file recovery failed, please check permissions, disk space and ${restore_quarantine}.${PLAIN}" "${YELLOW}⚠️ Не удалось частично восстановить файл резервной копии. Проверьте разрешения, место на диске и ${restore_quarantine}.${PLAIN}")"
                else
                    echo -e "$(localized_text "${YELLOW}⚠️ 回滚文件已写入，但至少一个服务重启失败，请立即查看 systemctl status。${PLAIN}" "${YELLOW}⚠️ The rollback file has been written, but at least one service failed to restart. Please check systemctl status immediately.${PLAIN}" "${YELLOW}⚠️ Файл отката записан, но как минимум одну службу не удалось перезапустить. Пожалуйста, немедленно проверьте статус systemctl.${PLAIN}")"
                fi
                ;;

            4)
                mapfile -t backups < <(ls -1t "$backup_root"/backup_*.tar.gz "$backup_root"/backup_*.tar.gz.enc 2>/dev/null)
                if [[ ${#backups[@]} -le 5 ]]; then
                    echo -e "$(localized_text "${BLUE}当前备份不超过 5 份，无需清理。${PLAIN}" "${BLUE}There are no more than five backups; no cleanup is needed.${PLAIN}" "${BLUE}Резервных копий не больше пяти; очистка не требуется.${PLAIN}")"
                else
                    confirm_danger "$(localized_text "隔离旧备份" "Quarantine old backups" "Поместить старые резервные копии в карантин")" "$(localized_text "会把第 6 份及更早的备份移入隔离目录，不会直接删除。" "The 6th and earlier backups will be moved to the quarantine directory and will not be deleted directly." "Шестая и более ранние резервные копии будут перемещены в каталог карантина и не будут удалены напрямую.")" "$(localized_text "如需恢复，可到 /etc/vps-optimize/quarantine/manual-backups 手动查看。保留最近 5 份不动。" "If you need to restore, you can go to /etc/vps-optimize/quarantine/manual-backups to check manually. Leave the last 5 copies unchanged." "Если вам нужно восстановить, вы можете перейти к /etc/vps-optimize/quarantine/manual-backups и проверить вручную. Последние 5 копий оставьте без изменений.")" || {
                        echo -e "$(localized_text "${BLUE}已取消旧备份隔离。${PLAIN}" "${BLUE}The old backup has been dequarantined.${PLAIN}" "${BLUE}Старая резервная копия выведена из карантина.${PLAIN}")"
                        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
                        continue
                    }
                    for i in "${!backups[@]}"; do
                        if [[ "$i" -ge 5 ]]; then
                            quarantine_path "${backups[$i]}" "/etc/vps-optimize/quarantine/manual-backups" >/dev/null 2>&1 || echo -e "$(localized_text "${YELLOW}⚠️ 隔离失败: ${backups[$i]}${PLAIN}" "${YELLOW}⚠️ Isolation failed: ${backups[$i]}${PLAIN}" "${YELLOW}⚠️ Сбой изоляции: ${backups[$i]}${PLAIN}")"
                        fi
                    done
                    echo -e "$(localized_text "${GREEN}✅ 旧备份隔离完成，最近 5 份备份已保留。${PLAIN}" "${GREEN}✅ Old backup isolation completed, the last 5 backups have been retained.${PLAIN}" "${GREEN}✅ Изоляция старых резервных копий завершена, последние 5 резервных копий сохранены.${PLAIN}")"
                fi
                ;;

            5)
                func_edit_applied_config_center
                ;;

            "?") show_backup_help ;;
            0|q|Q) break ;;
            *) echo -e "$(localized_text "${RED}❌ 无效选择！${PLAIN}" "${RED}❌ Invalid selection!${PLAIN}" "${RED}❌ Неверный выбор!${PLAIN}")" ;;
        esac

        echo ""
        read -n 1 -s -r -p "$(localized_text "按任意键继续..." "Press any key to continue..." "Нажмите любую клавишу, чтобы продолжить...")"
    done
}
