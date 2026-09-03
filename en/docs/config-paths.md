# Configuration files and data directories

This document is used to quickly locate files during troubleshooting, backup, and migration. The path will vary slightly depending on the system, third-party installer and user-defined configuration. The actual path is based on the current machine.

The menu path in this article is written in the format of "main menu [number menu copy] -> [sub number menu copy]".

## Take a look at the menu entry first

| target | menu path |
|---|---|
| Create a full configuration backup | `Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]` |
| View backup list | `Main menu [16 Configuration backup and rollback] -> [2 View existing backups]` |
| Rollback from backup | `Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]` |
| View/edit script applied configuration | `Main menu [16 Configuration backup and rollback] -> [5 View or edit applied configuration]` |
| 443 Link health check | `Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]` |
| Caddy/certificate health check | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [13 Caddy/Certificate one-click health check]` |
| Generate feedback diagnostic information | `Main menu [15 Service health overview]` |
| Restart common services | `Main menu [15 Service health overview] -> [s Service recovery] -> [r Restart a common service]` |
| Restart failed service | `Main menu [15 Service health overview] -> [s Service recovery] -> [f Restart failed services]` |
| View service logs | `Main menu [15 Service health overview] -> [s Service recovery] -> [l View service logs]` |
| Docker local anti-penetration | `Main menu [11 Docker Security management] -> [3 turn on Docker Local anti-penetration]` |
| Port concurrent connection limit | `Main menu [8 Firewall rules] -> [5 Port concurrent connection limit]` |
| Switch interface language | `Main menu [20 Interface language]` |

"Full configuration backup" is the name of the menu, which actually refers to the script management configuration backup and does not include Docker volume, container business data, mirroring and complete firewall running status.

## VPS-Optimize itself

| path | Description |
|---|---|
| `/usr/local/bin/cy` | Main script quick entry |
| `vps.sh` of the current directory | Manually download the runtime script file |
| `/etc/vps-optimize` | VPS-Optimize configuration, backup index and quarantine directory |
| `/etc/vps-optimize/language.conf` | Interface language setting; supports `LANGUAGE=zh`, `LANGUAGE=en`, `LANGUAGE=ru` |
| `/etc/vps-optimize/backups` | Full backup and Port 443 Reuse point backup directories |
| `/etc/vps-optimize/quarantine` | Isolate directory. The script tries to move old configurations here instead of deleting them directly. |

Commonly used checks:

```bash
ls -lah /etc/vps-optimize 2>/dev/null
find /etc/vps-optimize/backups -maxdepth 2 -type d 2>/dev/null
find /etc/vps-optimize/quarantine -maxdepth 2 -type d 2>/dev/null
```

## Port 443 Reuse

| path | Description |
|---|---|
| `/etc/vps-optimize/sni-stack.env` | Port 443 Reuse core settings; `ENTRY_MODE` stores the entry mode and `STRICT_SNI_GATE` stores the strict SNI gate state |
| `/etc/vps-optimize/443-engine.conf` | Current Port 443 Reuse point engine status, default `nginx-stream` |
| `/etc/vps-optimize/vpso-mux.yaml` | `tcp-peek` / `vpso-mux` routing configuration |
| `/etc/vps-optimize/sni-stack.last-backup` | The most recent Port 443 Reuse point backup path record |
| `/etc/vps-optimize/backups/sni-stack_*` | Port 443 Reuse automatic backup directory |
| `/etc/nginx/stream.d/vps_sni_*.conf` | Nginx stream SNI routing configuration |
| `/etc/caddy/conf.d/<domain>.caddy` | Caddy single domain reverse proxy configuration |
| `/etc/caddy/certs/<domain>.crt` | Certificate chain used by Caddy |
| `/etc/caddy/certs/<domain>.key` | Private key used by Caddy |
| `/root/cert/<domain>.crt` | Certificate symlink for user viewing |
| `/root/cert/<domain>.key` | Private key symlink for user viewing |
| `/root/cert/caddy_cf_manifest.txt` | List of managed domains and certification paths |
| `/root/cert/acme_last_error.log` | The most recent acme error log, check again if it exists |
| `/etc/systemd/system/vpso-mux.service` | `vpso-mux` routing systemd Service |
| `/usr/local/bin/vpso-mux` | vpso-mux routing in TCP Peek + Splice mode |

Check current 443 parameters:

```bash
grep -E '^(ENTRY_MODE|STRICT_SNI_GATE|PANEL_DOMAIN|PANEL_WEB_PATH|REALITY_SNI|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_PORT|XRAY_LISTEN_PORT|SUB_URI_PATH|CLASH_URI_PATH)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
```

Check Nginx / Caddy:

`8443`, `1443`, `40000`, and `2096` in the command are common example ports; the actual configuration is subject to the current service binding and script saved configuration.

```bash
nginx -t
caddy validate --config /etc/caddy/Caddyfile
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
```

Related entrances:

```text
Main menu [16 Configuration backup and rollback] -> [5 View or edit applied configuration]
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
Main menu [19 Port 443 Reuse manager] -> [6 Reapply current entry mode]
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance]
```

## Caddy

| path | Description |
|---|---|
| `/etc/caddy/Caddyfile` | Caddy main configuration |
| `/etc/caddy/conf.d` | VPS-Optimize recommended modular site configuration directory |
| `/etc/caddy/conf.d/*.caddy` | reverse proxy configuration for each domain |
| `/etc/caddy/certs` | DNS Certificate directory written after issuance |
| `/etc/caddy/Caddyfile.bak_*` | Backup before script or manual modification |
| `/etc/caddy/conf.d_quarantine_*` | Old configuration isolation directory, the name may have a timestamp |

Commonly used commands:

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl status caddy --no-pager
journalctl -u caddy -n 100 --no-pager
find /etc/caddy -maxdepth 3 -type f
```

If it is just reverse proxy, the entry is:

```text
Main menu [4 reverse proxy] -> [1 add Caddy reverse proxy]
Main menu [4 reverse proxy] -> [2 add Nginx HTTPS reverse proxy]
Main menu [4 reverse proxy] -> [6 View or edit applied configuration files]
```

If the Port 443 Reuse has been enabled, the new website portal is:

```text
Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]
```

## Nginx

| path | Description |
|---|---|
| `/etc/nginx/nginx.conf` | Nginx main configuration |
| `/etc/nginx/stream.d` | Port 443 Reuse stream configuration directory |
| `/etc/nginx/stream.d/vps_sni_*.conf` | Port 443 Reuse SNI split configuration |
| `/etc/nginx/conf.d/00-vps-default-drop.conf` | Default discard site configuration, used to reduce default site exposure when present |
| `/etc/nginx/conf.d/00-vps-proxy-map.conf` | Nginx HTTPS Reverse WebSocket Connection variable mapping |
| `/etc/nginx/conf.d/vps_proxy_*.conf` | Nginx HTTPS reverse proxy site configuration |
| `/etc/nginx/conf.d` | Traditional Nginx HTTP configuration directory |
| `/etc/nginx/sites-enabled` | Debian/Ubuntu common site enablement directory |
| `/etc/nginx/sites-available` | Debian/Ubuntu common site available directories |

Commonly used commands:

```bash
nginx -t
systemctl status nginx --no-pager
journalctl -u nginx -n 100 --no-pager
grep -R "listen" /etc/nginx 2>/dev/null
```

443 In Port 443 Reuse mode, Internet `443` should only be bound by the Port 443 Reuse service corresponding to the current `ENTRY_MODE`: `nginx-stream` corresponds to `nginx`, and `xray-fallback` corresponds to Xray / 3x-ui / x-ui hosted Xray, `tcp-peek` correspond to `tcppeek` / `vpso-mux`. If `/etc/vps-optimize/sni-stack.env` does not have `ENTRY_MODE`, the script reads compatible with `nginx-stream`.

## Cloudflare Token

| path | Description |
|---|---|
| `/root/.config/vps-panel/cloudflare.env` | Cloudflare Token storage location |

Permission suggestions:

```text
Zone.Zone.Read
Zone.DNS.Edit
```

File permissions should be kept as readable only by root:

```bash
ls -l /root/.config/vps-panel/cloudflare.env 2>/dev/null
```

Do not post file content to Issues or public chats.

Update entry:

```text
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [8 update Cloudflare API Token]
```

## 3x-ui / x-ui

Common official installer paths:

| path | Description |
|---|---|
| `/etc/x-ui/x-ui.db` | Panel SQLite database; PostgreSQL deployments do not use this file |
| `/etc/x-ui` | Panel configuration directory |
| `/usr/local/x-ui` | Panel program directory |
| `x-ui` systemd Service | Common service names |

There may be differences between different 3x-ui branches. First confirm with the command:

```bash
systemctl status x-ui --no-pager
find /etc -maxdepth 3 -name 'x-ui.db' 2>/dev/null
find /usr/local -maxdepth 3 -type d -name '*x-ui*' 2>/dev/null
```

VPS-Optimize entrance:

```text
Main menu [5 panel、Nodes and subscription tools] -> [1 3x-ui panel script]
Main menu [5 panel、Nodes and subscription tools] -> [3 panel SSL Repair]
```

## x-ui Enhancement Kit

`xui-custom-manager.sh` default path:

| path | Description |
|---|---|
| `/etc/xui-custom-manager.conf` | External manager configuration profile |
| `/etc/xui-custom-reset.json` | Custom reset rule configuration |
| `/root/x-ui-backups` | Database, configuration directory, program directory backup |
| `/var/log/xui-custom-manager.log` | External manager log |
| `/var/lib/xui-custom-manager/reset-state.json` | Reset status file monthly |
| `/etc/systemd/system/xui-custom-reset.service` | Automatically check service |
| `/etc/systemd/system/xui-custom-reset.timer` | Automatically check timer |
| `/usr/local/bin/xui-custom-manager.sh` | local stable actuator |
| `/usr/local/bin/xcm` | Manual quick entry |
| `/usr/local/lib/xui-custom-manager` | Remote script cache directory of `xcm` |

Commonly used commands:

```bash
systemctl status xui-custom-reset.timer --no-pager
journalctl -u xui-custom-reset.service -n 100 --no-pager
tail -n 100 /var/log/xui-custom-manager.log 2>/dev/null
```

Entrance:

```text
Main menu [5 panel、Nodes and subscription tools] -> [2 x-ui Enhancement Kit]
```

See [xui-custom-manager.md](xui-custom-manager.md) for detailed instructions.

## Docker and subscription tools

Common paths:

| path | Description |
|---|---|
| `/opt/sublinkpro` | SublinkPro deployment directory |
| `/opt/miaomiaowu` | Miaomiaowu Subscription Management Deployment Catalog |
| `/opt/sub-store` | Sub-Store deployment directory |
| `/opt/dockge` | Dockge deployment directory |
| `/opt/komari` | Komari deployment directory |
| `/opt/komari/data` | Komari data directory |
| `/opt/cdt-monitor` | CDT Monitor Compose configuration directory |

The actual path is based on the script output and `docker ps`.

Commonly used commands:

```bash
docker ps
docker compose ls 2>/dev/null || true
find /opt -maxdepth 3 -name 'docker-compose.yml' -o -name 'compose.yml' 2>/dev/null
```

Entrance:

```text
Main menu [3 Components and common services] -> [1 Docker engine]
Main menu [3 Components and common services] -> [7 Forwardx Forward panel]
Main menu [3 Components and common services] -> [10 nftables NAT forward]
Main menu [3 Components and common services] -> [13 FLVX Doraemon forwarding panel]
Main menu [3 Components and common services] -> [14 EasyTier Networking]
Main menu [3 Components and common services] -> [15 Tailscale Networking]
Main menu [5 panel、Nodes and subscription tools]
Main menu [11 Docker Security management]
```

FLVX is deployed using Docker Compose. Install Docker first. The EasyTier and Tailscale menus only install the client; network name, login, and node authorization are completed by their respective tools.

## dog.sh traffic monitor

`dog.sh` default path:

| path | Description |
|---|---|
| `/etc/port-traffic-dog/config.json` | Main configuration, including scheduled Telegram notifications and the custom template |
| `/etc/port-traffic-dog/traffic_data.json` | traffic statistics |
| `/etc/port-traffic-dog/daily_usage.json` | Daily data |
| `/etc/port-traffic-dog/daily_snapshot_state.json` | Daily snapshot status |
| `/etc/port-traffic-dog/logs/traffic.log` | Log |
| `/usr/local/bin/port-traffic-dog.sh` | Local script used by the bot service and scheduled tasks |

It also uses:

| Project | Description |
|---|---|
| `nftables` | Port traffic count |
| `tc` | speed limit |
| `cron` | Boot recovery, scheduled save, daily snapshot, monthly reset, and scheduled Telegram notifications |
| `conntrack` | Clear connection status |

Check:

```bash
ls -lah /etc/port-traffic-dog 2>/dev/null
crontab -l 2>/dev/null | grep -E 'port-traffic-dog|dog' || true
nft list ruleset 2>/dev/null | grep -i port_traffic_monitor || true
```

Entrance:

```text
Main menu [5 panel、Nodes and subscription tools] -> [16 dog traffic meter]
```

See [dog.md](dog.md) for detailed instructions.

## SSH, firewall, Fail2ban

| path or service | Description |
|---|---|
| `/etc/ssh/sshd_config` | SSH service configuration |
| `ssh` / `sshd` systemd Service | Different system service names are different |
| `ufw` | Ubuntu/Debian common firewall front-ends |
| `firewalld` | RHEL series common firewalls |
| `/etc/fail2ban/jail.local` | Fail2ban local rules |
| `fail2ban` systemd Service | Fail2ban Service |

Commonly used commands:

```bash
sshd -t
systemctl status ssh --no-pager || systemctl status sshd --no-pager
ufw status numbered 2>/dev/null || firewall-cmd --list-ports
systemctl status fail2ban --no-pager
fail2ban-client status sshd 2>/dev/null || fail2ban-client status ssh 2>/dev/null
```

Entrance:

```text
Main menu [6 SSH Security center]
Main menu [6 SSH Security center] -> [2 User key login mode] -> [1 add for user SSH public key]
Main menu [7 Fail2ban Explosion-proof]
Main menu [8 Firewall rules]
```

## Log quick check

| target | command |
|---|---|
| Nginx | `journalctl -u nginx -n 100 --no-pager` |
| Caddy | `journalctl -u caddy -n 100 --no-pager` |
| x-ui | `journalctl -u x-ui -n 100 --no-pager` |
| Docker | `journalctl -u docker -n 100 --no-pager` |
| Fail2ban | `journalctl -u fail2ban -n 100 --no-pager` |
| xui-custom-manager timer | `journalctl -u xui-custom-reset.service -n 100 --no-pager` |
| dog.sh traffic monitor | `tail -n 100 /etc/port-traffic-dog/logs/traffic.log` |

## sensitive information

Don't share publicly:

| content | common locations |
|---|---|
| Cloudflare Token | `/root/.config/vps-panel/cloudflare.env` |
| Certificate private key | `/etc/caddy/certs/*.key`、`/root/cert/*.key` |
| 3x-ui SQLite database | `/etc/x-ui/x-ui.db`; PostgreSQL deployments do not use this path |
| Subscription key | Panel database, subscription link |
| Telegram Bot Token | dog.sh traffic monitor configuration |
| SSH private key | User's own local machine or server |

Desensitize before submitting an issue. Diagnostic information entry:

```text
Main menu [15 Service health overview]
```
