# Recovery and Rollback Runbook

This manual is used to deal with problems that have already occurred: SSH disconnection, firewall error blocking, Port 443 Reuse corruption, Nginx entry or Caddy/Nginx Web reverse proxy engine cannot start, certificate failure, panel cannot be opened. Its goal is to first restore control and then troubleshoot the root cause.

The menu paths in this article are written in the format of "main menu [number menu copy] -> [sub-number menu copy]", and shortcut commands are not written into each path.

## do three things first

1. Do not close the SSH window that is still attached.
2. Don't rerun the same high-risk guide over and over again.
3. First determine whether you can still log in to the server.

| Current status | priority action |
|---|---|
| Currently SSH is still there | Keep window, create backup first or check service status |
| The new SSH cannot connect, but the old window is still there | Restore SSH, firewall or cloud security group with old window |
| All SSH are broken | Log in using cloud provider VNC/rescue console |
| The system can log in but 443 is broken. | Check the health first, and then process it separately according to the entry service, web reverse proxy engine, and certificate. |
| Systems and services are in disarray | Prioritize recovery from script backup or cloud snapshot |

## Minimum check to be able to log in

Let’s first look at the port and failed service:

```bash
ss -lntp
systemctl --failed --no-pager
systemctl status ssh --no-pager || systemctl status sshd --no-pager
systemctl status nginx caddy x-ui --no-pager
```

Re-enter:

```text
Main menu [15 Service health overview]
Main menu [13 Inspect and release ports]
```

When you need to restart the service or check the logs:

```text
Main menu [15 Service health overview] -> [s Service recovery] -> [r Restart a common service]
Main menu [15 Service health overview] -> [s Service recovery] -> [f Restart failed services]
Main menu [15 Service health overview] -> [s Service recovery] -> [l View service logs]
```

If it is a Port 443 Reuse point problem, priority:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

If you are ready to roll back:

```text
Main menu [16 Configuration backup and rollback] -> [5 View or edit applied configuration]
Main menu [16 Configuration backup and rollback] -> [2 View existing backups]
Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]
```

## SSH lost contact

### phenomenon

- The new port cannot be connected.
- Login times out after changing the SSH port.
- Public key or password login failed.

### If the old SSH window is still there

First confirm the actual binding of SSH:

```bash
ss -lntp | grep -E 'ssh|sshd'
systemctl status ssh --no-pager || systemctl status sshd --no-pager
```

Check SSH configuration:

```bash
sshd -t
grep -nE '^(Port|PasswordAuthentication|PubkeyAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
```

Then confirm the two-layer release:

| Hierarchy | what to do |
|---|---|
| Cloud Security Group | Release the new SSH port in the cloud provider console |
| System firewall | Enter `Main menu [8 Firewall rules]` to release the new port |

Don't close the old window. Open a new local terminal for testing:

```bash
ssh -p NEW_PORT root@serverIP
```

### If all SSH are broken

Log in with the cloud provider VNC/Rescue Console and proceed in sequence:

1. Confirm whether the SSH service is running.
2. Release the SSH port.
3. Fix `/etc/ssh/sshd_config`.
4. Restart the SSH service.
5. Open a new terminal to test login.

Commonly used commands:

```bash
systemctl restart ssh || systemctl restart sshd
sshd -t
ss -lntp | grep -E 'ssh|sshd'
ufw status numbered 2>/dev/null || firewall-cmd --list-ports
```

If you are not sure what has been changed, use cloud snapshot recovery first. Script backup cannot replace full machine snapshots.

## Firewall blocked by mistake

### phenomenon

- SSH port binding is normal, but the Internet cannot be connected.
- The website or panel can be accessed locally, but cannot be opened from the public internet.

### Check

```bash
ufw status numbered 2>/dev/null || true
firewall-cmd --list-all 2>/dev/null || true
ss -lntp
```

### Process

First confirm permission from the cloud security group before entering:

```text
Main menu [8 Firewall rules]
```

Recommended priority:

```text
[1 Enable firewall and allow current public ports]
```

If you only need to add ports, choose:

```text
[2 Manually allow ports]
```

Do not delete the current SSH port. Turning off the firewall and deleting rules are high-risk operations, and the script will ask for the uppercase `YES`.

### Port concurrent connection limit is blocked by mistake

`Main menu [8 Firewall rules] -> [5 Port concurrent connection limit]` writes additional `iptables` / `ip6tables` connlimit restriction rules, which are not equivalent to UFW/firewalld's port access rules. It will limit the number of TCP concurrent connections per source IP by public port; if you limit the Internet `443` and enable the Port 443 Reuse, you can only limit the entire Internet `443`, and cannot be precise to a specific Xray/3x-ui inbound connection, SNI, UUID or user. Don't choose `[6 Disable firewall]` by mistake.

When you can still enter the menu, go first:

```text
Main menu [8 Firewall rules] -> [5 Port concurrent connection limit] -> [3 View connection-limit rules]
Main menu [8 Firewall rules] -> [5 Port concurrent connection limit] -> [2 Remove port connection limit]
Main menu [8 Firewall rules] -> [5 Port concurrent connection limit] -> [5 Save/check persistence after reboot]
```

After the script deletes the rule, it will automatically try to refresh the persistent snapshot; `[5]` is used to confirm whether the saved file has been synchronized. If the system does not have an existing `netfilter-persistent`, `iptables-persistent` or RHEL series persistence path for `iptables-services`, the menu will prompt that the current connlimit rule will only take effect during this run.

When the menu cannot be entered, use VNC/Rescue Console to view the script rule tags:

```bash
iptables -S INPUT | grep 'VPSO_CONN_LIMIT_PORT_'
ip6tables -S INPUT | grep 'VPSO_CONN_LIMIT_PORT_'
```

Only delete a single rule that is confirmed to belong to this script and whose port and connection number match. The method is to copy the entire `-A INPUT... VPSO_CONN_LIMIT_PORT_port...` in the output, change the `-A INPUT` at the beginning to `-D INPUT` and then execute it; the IPv6 rule uses `ip6tables` in the same way. Do not clear INPUT chains in batches, and do not mix UFW/firewalld access rules and connlimit restriction rules.

## Port 443 Reuse modification

### phenomenon

- Neither the panel, subscription, nor website can be opened.
- The entry service or web reverse proxy engine failed to start.
- Browser 404, 502, certificate error.
- REALITY cannot be connected.

### First round of inspection

`8443`, `1443`, `40000`, and `2096` in the following commands and tables are sample ports; the actual configuration is subject to the current binding of the service and the configuration saved by the script.

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
systemctl status vpso-mux --no-pager
nginx -t
caddy validate --config /etc/caddy/Caddyfile
```

Then enter:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

### Do not rerun the first configuration first

When adding a new website, changing the backend port, or revising the certificate, you should not run the first configuration again. Commonly used entrances are:

| target | menu path |
|---|---|
| Add or delete sites | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]` |
| Switch Caddy/Nginx Web reverse proxy engine | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [8 switch Web reverse proxy engine]` |
| Rebuild configuration | `Main menu [19 Port 443 Reuse manager] -> [6 Reapply current entry mode]` |
| Modify panel/subscription/REALITY parameters | `Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings]` |
| Caddy/Certificate Maintenance | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance]` |
| Rollback 443 configuration | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [6 rollback Port 443 Reuse configuration]` |

### Broken after switching Caddy/Nginx Web reverse proxy engine

The 443 configuration of script management is subject to `/etc/vps-optimize/sni-stack.env`. When switching the web reverse proxy engine through `[19] -> [8] -> [8]`, the saved panel, subscription, website, certificate, whitelist and backend parameters will be read to rebuild the target engine configuration; the handwritten Caddy/Nginx configuration will not be reversely parsed.

If you have manually changed `/etc/caddy/conf.d`, `/etc/nginx/conf.d/vps_sni_web_*.conf` or `/etc/nginx/conf.d/vps_proxy_*.conf` generated by the old `[4 reverse proxy]` before, synchronize the parameters to the script through `[8 management Web domains / reverse proxy]` or `[10 Modify Port 443 Reuse settings]` first, and then switch. Switching to the Nginx local web reverse proxy isolates the script-managed Caddy 443 web configuration; switching back to Caddy isolates the script-managed Nginx local web configuration. When 443 is reapplied, the old Nginx HTTPS public internet reverse proxy configuration will also be isolated to avoid continuing to grab the public port `443`.

`ENTRY_MODE=xray-fallback` does not support web whitelisting, regardless of whether the local web reverse proxy engine selects Caddy or Nginx. The reason is that after Xray fallback, the local web reverse proxy engine cannot reliably obtain the real client source IP. If you need Web whitelist, switch to Nginx Stream or TCP Peek, and press `SNI + source IP` limit at the Internet entry layer.

## Nginx Can’t get up

### Common causes

- `443` is occupied by Apache, old Nginx server, 3x-ui, Xray or non-current entry service.
- `stream` configuration syntax error for `/etc/nginx/nginx.conf`.
- The old public HTTPS reverse proxy configuration and Port 443 Reuse point configuration are duplicated.
- After selecting Nginx as the web reverse proxy engine, the `/etc/nginx/conf.d/vps_sni_web_*.conf` syntax or certificate path is abnormal.

### Check

```bash
ss -lntp | grep ':443'
nginx -t
journalctl -u nginx -n 80 --no-pager
grep -R "listen.*443" /etc/nginx /etc/caddy 2>/dev/null
```

### Process

Target status:

| components | should listen |
|---|---|
| 443 Entrance Services | Nginx Stream, vpso-mux or Xray Primary inbound connection choose one of three to bind to the Internet `443` |
| Web reverse proxy engine | Caddy or Nginx is bound to the local HTTPS, such as `127.0.0.1:8443` |
| REALITY local inbound | In Nginx Stream/TCP Peek mode it is usually `127.0.0.1:1443` |
| 3x-ui panel | `127.0.0.1:40000` |

If Nginx cannot be started after preemption of the old configuration or switching of the Web reverse proxy engine, first confirm:

```bash
grep -E '^(ENTRY_MODE|WEB_PROXY_ENGINE|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_ADDR|CADDY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
grep -R "listen.*443" /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/caddy 2>/dev/null
nginx -t
```

Re-enter:

```text
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [15 isolate old Caddy Configuration]
Main menu [19 Port 443 Reuse manager] -> [6 Reapply current entry mode]
```

## Web reverse proxy engine cannot start or 502

### Common causes

- The current web reverse proxy engine configuration syntax error.
- There is no service on the backend port.
- The reverse address is written incorrectly.
- The certificate file is missing or has incorrect permissions.
- Nginx The server/location writing method or certificate path of local Web reverse proxy is abnormal.

### Check

```bash
grep -E '^(ENTRY_MODE|WEB_PROXY_ENGINE|PANEL_DOMAIN|CADDY_LISTEN_ADDR|CADDY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
caddy validate --config /etc/caddy/Caddyfile
systemctl status caddy --no-pager
journalctl -u caddy -n 100 --no-pager
nginx -t
systemctl status nginx --no-pager
journalctl -u nginx -n 100 --no-pager
ls -l /etc/nginx/conf.d/vps_sni_web_*.conf 2>/dev/null
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
```

### Process

| question | menu path |
|---|---|
| Just a Caddy syntax or overloading issue | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [12 Check and reload Caddy]` |
| Nginx Local Web reverse syntax or overloading problem | `Main menu [19 Port 443 Reuse manager] -> [6 Reapply current entry mode]` |
| Need to switch Caddy/Nginx Web reverse proxy engine | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [8 switch Web reverse proxy engine]` |
| The backend port or path is incorrectly written | `Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [1 Edit panel/subscription ports and paths]` |
| Certificate file or symlink is abnormal | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [10 rebuild /root/cert Certificate symlink]` |
| I don’t know what kind of problem it is | `Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]` |

## Certificate failed

### Confirm first

```bash
date -Is
dig +short A panel.example.com @1.1.1.1
dig +short AAAA panel.example.com @1.1.1.1
grep -E '^(WEB_PROXY_ENGINE|PANEL_DOMAIN|CADDY_LISTEN_ADDR|CADDY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
systemctl status nginx caddy --no-pager
journalctl -u caddy -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
```

Cloudflare Token requires at least:

```text
Zone.Zone.Read
Zone.DNS.Edit
```

The script uses Cloudflare DNS-01 to issue the certificate. Orange cloud is not the direct cause of the issuance failure; switching to gray cloud here is only used to eliminate public internet access link problems. If the issuance fails, you should first check the Token permissions, authorization zone, `_acme-challenge` TXT propagation, server time and acme.sh logs.

### handle entry

```text
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [8 update Cloudflare API Token]
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [9 Reissue a domain certificate]
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [13 Caddy/Certificate one-click health check]
```

Retaining Caddy in the menu name is a historical naming; no matter whether the web reverse proxy engine selects Caddy or Nginx, the certificate is still issued by `acme.sh + Cloudflare DNS API`, and `/etc/caddy/certs/${domain}.crt|key` and `/root/cert/${domain}.crt|key` continue to be used.

The most recent acme error log may be at:

```text
/root/cert/acme_last_error.log
```

Do not paste the token, private key, or full subscription key publicly.

## Panel cannot be opened

### Quick judgment

```bash
curl -I http://127.0.0.1:40000/panel/
curl -I https://panel.example.com/panel/
systemctl status x-ui --no-pager
```

| result | judge |
|---|---|
| The local HTTP is normal, but the public HTTPS is unreachable. | Mostly it is an issue with the entry service, web reverse proxy engine or certificate. |
| Local HTTP also does not work. | Repair 3x-ui or panel port first |
| redirect loop | 3x-ui may still turn on the built-in HTTPS |
| 404 | The panel path and the web reverse proxy engine path are inconsistent |
| 502 | Web reverse proxy engine cannot find the backend |

Common entrances:

```text
Main menu [5 panel、Nodes and subscription tools] -> [3 panel SSL Repair]
Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [1 Edit panel/subscription ports and paths]
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

## Subscription not available

### Check

```bash
curl -I http://127.0.0.1:2096/sub/
curl -I https://panel.example.com/sub/
curl -I https://panel.example.com/clash/
```

Subscription links should not appear:

```text
:2096
:40000
:8443
127.0.0.1
```

Processing entry:

```text
Main menu [19 Port 443 Reuse manager] -> [11 Subscription link / External Proxy Tips]
Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [1 Edit panel/subscription ports and paths]
```

## REALITY connection failed

### Check

```bash
ss -lntp | grep -E ':443|:1443'
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com </dev/null
```

Key points to confirm:

| Project | Check the key points |
|---|---|
| REALITY local binding | `127.0.0.1:1443` |
| client port | `443` |
| `dest` / `Target` | External real HTTPS site |
| `serverNames` / `SNI` | Consistent with external real HTTPS site |
| Node domain | DNS only / gray cloud |

Processing entry:

```text
Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [2 Modify REALITY local listener / camouflage SNI]
Main menu [19 Port 443 Reuse manager] -> [6 Reapply current entry mode]
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

## Restore from backup

### Full script backup

Suitable when the system can still be logged in and the script menu can still be opened:

```text
Main menu [16 Configuration backup and rollback] -> [2 View existing backups]
Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]
```

Backups are usually located at:

```text
/etc/vps-optimize/backups
```

### Port 443 Reuse Backup

Suitable for rolling back only ingress services, web reverse proxy and 443 configurations:

```text
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [6 rollback Port 443 Reuse configuration]
```

Related paths:

```text
/etc/vps-optimize/backups/sni-stack_*
/etc/vps-optimize/sni-stack.last-backup
```

### cloud snapshot

Suitable for these situations:

| situation | Suggestions |
|---|---|
| SSH and VNC cannot be stably repaired | Restore cloud snapshot |
| Unable to start after kernel switch | Restore cloud snapshot or repair GRUB from rescue mode |
| The source of the configuration is unknown and repairs failed repeatedly. | Revert to the most recent clearly available snapshot |
| Data directory or database corruption | Confirm backup first, then consider snapshots |

## Before submitting an issue

First run:

```text
Main menu [15 Service health overview]
```

Generate feedback diagnostic information in the health overview. Be sure to desensitize before posting publicly:

| content | Processing method |
|---|---|
| Cloudflare Token | Delete |
| Private key and certificate private key | Delete |
| Panel password | Delete |
| Subscription key | Delete |
| Real user domain | Can be replaced with `example.com` as needed |

For the Issue template, see [VPS-Optimize Bug report](https://github.com/Chunlion/VPS-Optimize/blob/main/.github/ISSUE_TEMPLATE/bug_report.md)。
