# Existing servers migrated to Port 443 Reuse

This document is for VPSs that have already run services: they already have 3x-ui, Caddy/Nginx websites, subscription tools, and Docker Compose projects. They want to hand over the public port `443` to the Port 443 Reuse of VPS-Optimize.

Core principles: Inventory first, then back up, then migrate. Do not run the first configuration without knowing what port the old service is listening on, where the old configuration is, and how the old certificate was issued.

The menu path in this article is written in the format of "main menu [number menu copy] -> [sub number menu copy]".

## Suitable for whom

| current situation | Is it suitable |
|---|---|
| Already have 3x-ui, and want to use the public internet for panel and subscription `443` | suitable for |
| Already have a Caddy website and want to share `443` with 3x-ui+Reality | suitable for |
| Already occupied by Nginx/Apache `443` | Suitable, but old site must be documented before migration |
| Already have Docker subscription tool and want to add HTTPS domain | suitable for |
| I don’t know what services are running on the machine. | Take inventory first, don’t migrate directly |

## Preparing for migration

| Preparatory items | Description |
|---|---|
| VPS Snapshot | Must do before migration |
| Current SSH session | Remain uninterrupted throughout the process |
| cloud provider security group | Port SSH and `443/tcp` have been released |
| Domain list | Panel domain, the 3x-ui subscription URI under that domain, website domains, and node domains; record a separate domain only when using a standalone subscription tool |
| backend manifest | Local listening address and port for each service |
| Cloudflare Token | Used to issue certificates for DNS |
| Old configuration backup | Caddy/Nginx/panel/Docker Compose must be backed up |

## Step One: Take Stock of Current Situation

First run:

```text
Main menu [1 Preflight and risk scan]
Main menu [15 Service health overview]
```

Record manually again:

```bash
ss -lntp
systemctl status caddy nginx apache2 httpd x-ui docker --no-pager
docker ps
```

Fill out the table below. The domain and port in the table are sample values; please replace them with your actual domain, backend address and port when migrating.

| domain / service | Current Internet entry | Backend address | backend port | Configuration location | Do you want to migrate |
|---|---|---|---|---|---|
| `panel.example.com` | `:40000` or `:443` | `127.0.0.1` | `40000` | 3x-ui panel | Yes |
| `sub.example.com` | `:3000` or `:443` | `127.0.0.1` | `3000` | Docker / Caddy | Depends on the situation |
| `site.example.com` | `:443` | `127.0.0.1` | `8080` | Caddy/Nginx | Yes |

Focus on finding who is occupying the public port `443`:

```bash
ss -lntp | grep ':443'
grep -R "listen.*443" /etc/nginx /etc/caddy 2>/dev/null
```

## Step 2: Create a backup

First create a full backup of the script:

```text
Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]
```

Confirm the backup list again:

```text
Main menu [16 Configuration backup and rollback] -> [2 View existing backups]
```

If there is already a Caddy/Nginx configuration, additionally record these directories:

```text
/etc/caddy/Caddyfile
/etc/caddy/conf.d
/etc/caddy/certs
/etc/nginx/nginx.conf
/etc/nginx/conf.d
/etc/nginx/sites-enabled
/etc/nginx/stream.d
```

If there is already a Docker Compose project, record:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
find /opt -maxdepth 3 -name 'docker-compose.yml' -o -name 'compose.yml' 2>/dev/null
```

## Step Three: Choose a Migration Route

| Current status | Recommended route |
|---|---|
| Only 3x-ui, no other website | Directly press 3x-ui + 443 tutorial to deploy |
| Already have 3x-ui and comes with HTTPS | First clear the 3x-ui certificate path, and then access 443 |
| Already have Caddy reverse proxy | Record the old domain and backend, enable 443 and add them one by one; you can continue to select Caddy, or switch to Nginx local web reverse proxy |
| There is already a Nginx/Apache website | First change the website backend to the local port, and then use the Port 443 Reuse point Web domain/reverse proxy; you can choose Caddy or Nginx local web reverse proxy |
| There is already a subscription tool Docker container, but the Port 443 Reuse is not enabled yet. | Keep the container, use `Main menu [4 reverse proxy]` to select Caddy or Nginx HTTPS to reverse proxy |
| Already have subscription tool Docker container, ready to enable Port 443 Reuse | Keep the container and change external access to Port 443 Reuse point Web domain/reverse proxy |

For complete steps, see [Port 443 Reuse: Setup and Configuration](443-single-entry.md).

For subscription tool migration, see [Subscription Tools on Port 443](../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md).

## HTTPS reverse proxy transition when Port 443 Reuse is not enabled

If you are not ready to enable the Port 443 Reuse for the time being, but just want to add the HTTPS domain to the subscription tool or website first, you can use the independent reverse proxy portal:

```text
Main menu [4 reverse proxy]
```

Optional process:

| entrance | Suitable for the situation |
|---|---|
| `[1 add Caddy reverse proxy]` | Already using Caddy, or wishing to have Caddy manage the domain reverse proxy |
| `[2 add Nginx HTTPS reverse proxy]` | The Port 443 Reuse is not enabled, and it is hoped that Nginx will be directly bound to the Internet 80/443 |

Nginx HTTPS will reuse the existing `acme.sh + Cloudflare DNS API` certificate process, and the certificate will still be installed to `/etc/caddy/certs/${domain}.crt|key` and symlinked to `/root/cert/`. `${domain}` is a placeholder and will be replaced with your real domain when used.

Things to note:

1. This process is only suitable for servers that have not yet enabled Port 443 Reuse.
2. If Port 443 Reuse has been enabled, Nginx HTTPS reverse proxy will seize the public port `443`. You should use `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]` instead, and select Caddy or Nginx local web reverse proxy engine in this menu.
3. The same domain can only be managed by one of the portals Caddy or Nginx. Do not configure it repeatedly.
4. The backend is still recommended to listen to `127.0.0.1:port`, such as `127.0.0.1:3000`. The domain and port are example values, please replace them with your actual values.

## Migrate existing 3x-ui

### target state

The following `40000`, `2096`, and `1443` are sample ports; the actual configuration is subject to 3x-ui, Xray and the configuration saved in the script.

| Project | target |
|---|---|
| Panel binding | `127.0.0.1:40000` |
| Panel HTTPS | Close, the certificate path is cleared |
| Panel path | For example `/panel/` |
| Subscribe to listen | `127.0.0.1:2096` |
| Subscription path | For example `/sub/`, `/clash/` |
| REALITY binding | `127.0.0.1:1443` |
| Client node port | `443` |

### Operation entrance

Enter 3x-ui:

```text
Main menu [5 panel、Nodes and subscription tools] -> [1 3x-ui panel script]
```

If the panel certificate or path is messed up, first use the brick rescue entrance:

```text
Main menu [5 panel、Nodes and subscription tools] -> [3 panel SSL Repair]
```

Access 443 for the first time again:

```text
Main menu [19 Port 443 Reuse manager] -> [2 initial setup/installation Port 443 Reuse]
```

health check after running:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

### Verify

```bash
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
```

Subscription links and node links should no longer appear:

```text
:2096
:40000
:1443
127.0.0.1
```

## Migrate existing Caddy website

### Pre-migration records

```bash
find /etc/caddy -maxdepth 3 -type f -print
grep -R "reverse_proxy" /etc/caddy 2>/dev/null
grep -R "tls " /etc/caddy 2>/dev/null
```

Log each site:

| domain | backend protocol | Backend address | backend port | Remarks |
|---|---|---|---|---|
| `site.example.com` | HTTP | `127.0.0.1` | `8080` | website |
| `sub.example.com` | HTTP | `127.0.0.1` | `3000` | Subscription tool |

### Enable 443 post-recording

First-time configuration or re-applying Port 443 Reuse may isolate the old Caddy configuration and the old Nginx HTTPS reverse proxy configuration managed by scripts to prevent the old configuration from continuing to seize the public port `443`. After enabling it, do not write down the old rules for preempting `443` by hand, but make up the records one by one:

```text
Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]
```

When adding, only fill in the local backend:

| Input | Example |
|---|---|
| Website/reverse domain | `site.example.com` |
| Backend listening address | `127.0.0.1` |
| backend port | `8080` |

Verify:

```bash
curl -I http://127.0.0.1:8080/
curl -I https://site.example.com/
openssl s_client -connect serverIP:443 -servername site.example.com </dev/null
```

## Migrate existing Nginx/Apache website

443 In Port 443 Reuse mode, Internet `443` should be bound uniformly by the current entry mode. The old Nginx server, Apache, panel, Xray should no longer be directly bound to the Internet `443`; if you want to continue to use Nginx as a website reverse proxy, please switch to the Nginx local web reverse proxy engine in `[19] -> [8]` instead of retaining the old Internet `443` server.

Recommended practices:

1. Have the old website service change to the native HTTP backend, such as `127.0.0.1:8080`.
2. Use the Port 443 Reuse point "Manage Web domain/Reverse Proxy" to reverse the domain to the backend.
3. Verify the public HTTPS domain.
4. After confirming that everything is correct, tighten the firewall and old public internet ports.

Check old services:

```bash
ss -lntp | grep -E ':80|:443|:8080|:8081'
grep -R "listen" /etc/nginx /etc/apache2 /etc/httpd 2>/dev/null
```

If the old service must continue to use Nginx/Apache, at least don't let it grab `0.0.0.0:443`.

## Migrate Docker Subscription Tool

The goal is that the container backend is only bound to the local machine or intranet, and the Internet only uses the Caddy/Nginx reverse proxy or Port 443 Reuse. After enabling the Port 443 Reuse, Caddy/Nginx is an optional local web reverse proxy engine and no longer directly grabs the Internet `443`.

Let’s look at the container port first:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
ss -lntp | grep -E ':3000|:3001|:3002'
```

If the backend is exposed to `0.0.0.0`, consider:

```text
Main menu [11 Docker Security management] -> [3 turn on Docker Local anti-penetration]
```

This operation will affect the Docker network behavior. Before execution, confirm that the container does not rely on the public internet direct port.

If the Port 443 Reuse is not enabled temporarily, enter:

```text
Main menu [4 reverse proxy]
```

Select `[1 Add Caddy reverse proxy]` or `[2 Add Nginx HTTPS reverse proxy]` and point the standalone subscription tool domain at its local backend port. Nginx HTTPS reverse proxy requests or reuses `/etc/caddy/certs/${domain}.crt|key` and listens directly on public ports 80/443, so it cannot own public `443` at the same time as Port 443 Reuse.

If the Port 443 Reuse has been enabled or is ready to be enabled, add an external domain through the Port 443 Reuse:

```text
Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]
```

And change the external access address to:

```text
https://sub.example.com/
```

Don't write:

```text
http://127.0.0.1:3000/
http://serverIP:3000/
https://sub.example.com:3000/
```

## Post-migration verification checklist

| Check items | command or entry | Expectation |
|---|---|---|
| Port listening | `ss -lntp` | Internet `443` only serves the current entry. |
| Nginx configuration | `nginx -t` | Pass |
| Caddy configuration | `caddy validate --config /etc/caddy/Caddyfile` | Passed when using Caddy as the web reverse proxy engine |
| Panel backend | `curl -I http://127.0.0.1:40000/panel/` | 200/302/401 are acceptable, but the connection cannot be refused. |
| Subscription backend | `curl -I http://127.0.0.1:2096/sub/` | able to connect |
| Panel public internet | `curl -I https://panel.example.com/panel/` | HTTPS normal |
| Website public internet | `curl -I https://site.example.com/` | HTTPS normal |
| 443 health check | `Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]` | No critical failure |
| Service overview | `Main menu [15 Service health overview]` | No exception failed service |

Back up immediately after success:

```text
Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]
```

## Rollback scenario

| question | Prioritize processing |
|---|---|
| Just adding a new site failed | Delete the newly added domain or use script to automatically roll back |
| Caddy configuration failed | Verify Caddy, isolate the new site configuration, and then reload |
| Nginx stream failed | Rollback Port 443 Reuse configuration |
| Panel cannot be opened | Clean 3x-ui SSL, check local port and path |
| Overall chaotic service | Restore from scripted full backup or cloud snapshot |

Port 443 Reuse rollback entry:

```text
Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance] -> [6 rollback Port 443 Reuse configuration]
```

Script full rollback entry:

```text
Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]
```

For lost connection or complex faults, see [recovery-runbook.md](recovery-runbook.md).

## Common migration mistakes

| Error | Consequences | Correct approach |
|---|---|---|
| Directly configure it for the first time without taking inventory of the old `443` occupancy | Nginx/Caddy port conflict | First `ss -lntp`, record the old service |
| Rerun the first configuration when adding a new website | Configurations are repeatedly rewritten, making troubleshooting complicated. | Subsequent new additions will only go to `[8 management Web domains / reverse proxy]` |
| Reserved 3x-ui Comes with HTTPS | Redirect loop or 502 | Clear the certificate path and let the web reverse proxy engine take over HTTPS |
| Write the backend as a public domain | reverse proxy detour, certificate and header confusion | The backend uses `127.0.0.1:port` |
| REALITY/node domain enabled Cloudflare Orange Cloud | The client cannot directly connect to the VPS, REALITY or SNI link abnormality | The node domain is changed to DNS only / Gray Cloud; the DNS-01 certificate issue is individually checked for Token, zone and TXT propagation |
| Old Caddy/Nginx sites are not migrated | The old website cannot be opened after enabling 443 | Go through `[8 management Web domains / reverse proxy]` one by one and select the required web reverse proxy engine |
