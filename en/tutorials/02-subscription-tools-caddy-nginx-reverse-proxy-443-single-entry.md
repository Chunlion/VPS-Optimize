# Subscription Tools with Caddy/Nginx and Shared Port 443

This tutorial talks about how to securely provide HTTPS access to subscription tools such as SublinkPro, Sub-Store, and Miaomiaowu Subscription Management. When the 443 shared entry is not enabled, you can use the Caddy or Nginx HTTPS reverse proxy in `Main menu [4 reverse proxy]`; after the 443 shared entry is enabled, you should uniformly go to the Web domain/reverse proxy portal of the 443 shared entry, and you can select Caddy or Caddy or Caddy in this portal. Nginx acts as a local web reverse proxy engine.

Recommended choices:

| Current status | Recommended method |
|---|---|
| The shared port 443 has not been enabled yet. I just want to access the subscription tool first. | `Main menu [4 reverse proxy]`, choose Caddy or Nginx HTTPS according to the existing environment |
| shared port 443 enabled | `Main menu [19 443 shared entry manager] -> [8 management Web domains / reverse proxy]` adds reverse proxy domain; use the same menu `[8 switch Web reverse proxy engine]` to switch between Caddy/Nginx when needed |
| Subscription tools are for your own use only | The backend is only bound to the local machine or intranet address, and can be accessed externally through the Caddy/Nginx or 443 shared entry. |
| Not sure which one to choose | First run `Main menu [1 Preflight and risk scan]` and `Main menu [15 Service health overview]` to confirm the port and service status |

## Suitable for whom

| situation | Is it suitable |
|---|---|
| Want to deploy SublinkPro | suitable for |
| Want to deploy Sub-Store | suitable for |
| Want to deploy Miaomiaowu subscription management | suitable for |
| The subscription tool is already running in Docker, and I want to add the domain HTTPS | suitable for |
| Want to directly expose the internal port of the subscription tool to the public internet | Not recommended |

## Prepare materials

| Material | Example | Description |
|---|---|---|
| VPS Snapshot | cloud provider console creation | It is recommended to do this before modifying the reverse proxy and container |
| Subscribe to domain | `sub.example.com` | DNS points to the current VPS |
| Backend address/port | `127.0.0.1:3000`, `10.0.0.20:3000`, etc. | Example values for local machine or intranet backend, please replace them with actual values. |
| Cloudflare API Token | `Zone.Zone.Read`、`Zone.DNS.Edit` | Used when DNS visa certificate is required |
| Current SSH session | not closed | Facilitates recovery in case of failure |
| Docker/Compose | The script will automatically check and install | Subscription tools are usually deployed with Docker Compose |

DNS Suggestions:

| domain | Suggestions |
|---|---|
| `sub.example.com` | DNS only / gray cloud |
| shared port 443 point related domains | DNS only / gray cloud |
| Just a regular website display | You can decide whether to be an agent based on actual needs, but this tutorial recommends running through Huiyun first. |

## Estimated time

| stage | Estimated time |
|---|---|
| Preflight | 2-5 minutes |
| Deploy subscription tools | 5-20 minutes |
| Configure Caddy/Nginx or shared port 443 | 5-15 minutes |
| Verify subscription output | 5-10 minutes |
| backup | 1-3 minutes |

## What will be modified?

| Project | Content may be modified | risk |
|---|---|---|
| Docker/Compose | Add new containers, networks, and deployment directories | Container port conflict or image pull failure |
| Caddy | Added site configuration, certificate, and reverse proxy rules | Configuration errors can cause 404/502 |
| Nginx HTTPS reverse proxy | When shared port 443 is not enabled, the HTTPS site configuration can be added | Configuration errors or port conflicts can cause 80/443 access exceptions |
| Nginx stream | If shared port 443 is connected, SNI routing will be added | Configuration errors may affect the public port `443` |
| firewall | It is recommended to expose only the entry port and not the backend port. | Misrelease can expose internal services |
| backup | Generate configuration backup and quarantine directories | Occupies a small amount of disk |

## Operation steps

### 1. Precheck the current server

Enter:

```text
Main menu [1 Preflight and risk scan]
```

Key points to confirm:

| Project | Expectation |
|---|---|
| Docker | If it is not installed, the subscription tool installation process will automatically install it. |
| Port occupied | The subscription tool port should not conflict with existing services. |
| DNS | The subscribed domain can be resolved to the current VPS |
| firewall | SSH and the ingress port have been released |
| system time | Certificate issuance requires accurate time |

Check the port manually:

```bash
ss -lntp
```

### 2. Install the subscription tool

Enter:

```text
Main menu [5 panel、Nodes and subscription tools]
```

The installation process will automatically check Docker/Compose and install it first if missing.

Common entrances:

| Tools | menu path | Suitable for the scene |
|---|---|---|
| SublinkPro | `Main menu [5 panel、Nodes and subscription tools] -> [7 SublinkPro subscription stack]` | Subscription conversion, aggregation, management |
| Miaomiaowu Subscription Management | `Main menu [5 panel、Nodes and subscription tools] -> [8 Miaomiaowu subscription stack]` | Graphical subscription management |
| Sub-Store | `Main menu [5 panel、Nodes and subscription tools] -> [9 Sub-Store subscription stack]` | Advanced subscription handling and scripting |
| Dockge | `Main menu [5 panel、Nodes and subscription tools] -> [11 Dockge Compose]` | Manage multiple Compose projects |

After installation, check the container status first:

```bash
docker ps
```

If the script deploys the project to `/opt`, you can also enter the corresponding directory to view:

```bash
ls /opt
```

### 3. Confirm the backend binding method

It is recommended that the backend of the subscription tool is only bound to the local or intranet, and is not recommended to be directly exposed to the Internet. The following are all example values:

```text
127.0.0.1:3000
10.0.0.20:3000
```

Check:

Select the corresponding command according to the actual backend address.

```bash
ss -lntp | grep -E ':3000|:3001|:3002'
curl -I http://127.0.0.1:3000/
curl -I http://10.0.0.20:3000/
```

If the backend is bound to `0.0.0.0:3000`, it means that the Internet may be directly accessible. You can limit exposure through Docker local exposure protection or firewall:

```text
Main menu [11 Docker Security management]
Main menu [8 Firewall rules]
```

Docker anti-penetration will modify the network behavior of Docker and restart Docker, which is a high-risk operation. Make sure that the container does not rely on the public internet direct connection port before continuing.

### 4A. Option 1: Use Caddy/Nginx reverse proxy when shared port 443 is not enabled

It is suitable for those who have not enabled shared port 443 yet and just want to use the domain to access the subscription tool first.

Enter:

```text
Main menu [4 reverse proxy]
```

Select according to current environment:

| entrance | Suitable for the situation |
|---|---|
| `[1 add Caddy reverse proxy]` | Already using Caddy, or want to have the site directly managed by Caddy? |
| `[2 add Nginx HTTPS reverse proxy]` | The 443 shared entry is not enabled, and it is hoped that Nginx will be directly bound to the Internet 80/443 to provide HTTPS |

Fill in the example, replace the domain and port with your actual values:

| Project | Example |
|---|---|
| domain | `sub.example.com` |
| backend port | `3000` |
| backend protocol | According to the actual situation of the tool, usually HTTP |

If you choose Nginx HTTPS reverse proxy, the script will reuse the existing `acme.sh + Cloudflare DNS API` certificate process and the certificate will still be installed to:

```text
/etc/caddy/certs/sub.example.com.crt
/etc/caddy/certs/sub.example.com.key
/root/cert/sub.example.com.crt
/root/cert/sub.example.com.key
```

`sub.example.com` is an example value, please replace it with your actual subscription domain. Nginx HTTPS reverse proxy is only suitable for scenarios where shared port 443 is not enabled; if the script detects shared port 443 configuration, it will refuse to continue to prevent Nginx from seizing the public port `443`. Do not hand over the same domain to Caddy and Nginx at the same time.

If you use Caddy for reverse proxy, verify after configuration:

```bash
systemctl status caddy --no-pager
caddy validate --config /etc/caddy/Caddyfile
curl -I https://sub.example.com/
```

If you use Nginx HTTPS for reverse proxy, verify after configuration:

```bash
nginx -t
systemctl status nginx --no-pager
curl -I https://sub.example.com/
```

If 502:

```bash
curl -I http://127.0.0.1:3000/
journalctl -u caddy -n 80 --no-pager
journalctl -u nginx -n 80 --no-pager
```

If the certificate fails, check the Cloudflare Token permissions, authorization zone, `_acme-challenge` TXT propagation, server time and acme.sh logs. The script uses DNS-01, and the Orange Cloud status is not the direct cause of the issuance failure.

### 4B. Option 2: Access shared port 443

Suitable for already enabled:

```text
Main menu [19 443 shared entry manager] -> [2 initial setup/installation 443 shared entry]
```

If you add a new subscription tool domain later, do not rerun the first configuration. Enter:

```text
Main menu [19 443 shared entry manager] -> [8 management Web domains / reverse proxy]
```

Fill in example:

| Project | Example |
|---|---|
| New website/reverse domain | `sub.example.com` |
| Backend address | `127.0.0.1` |
| backend port | `3000` |

The Docker service recommends publishing the container port to the host `127.0.0.1`, and then filling in the corresponding host port. When connecting to other intranet servers, you can fill in the actual intranet IP or hostname, but you must first confirm that the current VPS can be directly accessed.

The script will update the Caddy or Nginx local configuration according to the current web reverse proxy engine and apply for a certificate. When a high-risk confirmation occurs, confirm that the snapshot, DNS, Token, and backend port are all correct before entering uppercase `YES`.

If you have previously configured independent Caddy/Nginx HTTPS reverse proxy on `Main menu [4 reverse proxy]`, when enabling or reapplying shared port 443, the script will isolate the old configuration that may seize the public port `443`. In the future, the domain of the subscription tool should be re-recorded from `[19] -> [8]`. Do not let Nginx HTTPS of `[4 reverse proxy]` directly listens on the public port `443`.

Verify:

```bash
curl -I https://sub.example.com/
openssl s_client -connect serverIP:443 -servername sub.example.com </dev/null
```

### 5. Configure the external access address of the subscription tool

Different tools have different names. Common fields include:

```text
External URL
Public URL
Base URL
SUBSCRIPTION_DOMAIN
External access address
```

The public internet address HTTPS should be filled in:

```text
https://sub.example.com/
```

Do not fill in:

```text
http://127.0.0.1:3000/
http://serverIP:3000/
https://sub.example.com:3000/
```

If the link generated by the subscription tool still contains an internal port, the client may not be able to use it.

### 6. Verify subscription content

Browser opens:

```text
https://sub.example.com/
```

Command check:

```bash
curl -I https://sub.example.com/
curl -L https://sub.example.com/ -o /tmp/sub-tool-home.html
```

When inspecting the subscription output, focus on:

| Project | Expectation |
|---|---|
| domain | It is a public domain |
| agreement | HTTPS |
| port | Default `443`, do not bring internal port |
| Token | Do not appear in public logs |
| Node address | Do not be changed to `127.0.0.1` |

### 7. Backup after success

Enter:

```text
Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]
```

If the subscription tool is deployed with Docker Compose, additional records are also recommended:

| content | location |
|---|---|
| Compose Catalog | `/opt/<PROJECT_NAME>` |
| Administrator account | Your own password manager |
| External access domain | Operation and maintenance notes |
| backend port | Operation and maintenance notes |
| Cloudflare Token permissions | Cloudflare console |

## Verification method

The Caddy/Nginx reverse proxy of the 443 shared entry is not enabled, verify according to the actual entry used.

Caddy：

```bash
systemctl status caddy --no-pager
caddy validate --config /etc/caddy/Caddyfile
curl -I https://sub.example.com/
curl -I http://127.0.0.1:3000/
```

Nginx HTTPS reverse proxy:

```bash
systemctl status nginx --no-pager
nginx -t
curl -I https://sub.example.com/
curl -I http://127.0.0.1:3000/
```

shared port 443 menu verification:

```text
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

You can also do it manually:

```bash
ss -lntp | grep -E ':443|:8443|:3000'
curl -I https://sub.example.com/
openssl s_client -connect serverIP:443 -servername sub.example.com </dev/null
```

Docker status:

```bash
docker ps
docker logs --tail=80 CONTAINER_NAME
```

## How to roll back if failed

| question | Process |
|---|---|
| Caddy configuration error | Use Caddy backup and restore, or isolate the new site configuration and then reload |
| Nginx HTTPS reverse proxy configuration error | Check the `nginx -t` output; the Nginx reverse proxy configuration created by the script will be placed in `/etc/nginx/conf.d/vps_proxy_${domain}.conf` |
| 443 Failed to add domain to shared entry | Use scripts to automate backup rollback or delete the domain from `Main menu [19 443 shared entry manager] -> [8 management Web domains / reverse proxy]` |
| Certificate failed | `Main menu [19 443 shared entry manager] -> [12 CF DNS / Caddy Certificate maintenance]` Check Token, DNS, re-sign |
| Container startup failed | Enter the corresponding tool management menu to view status, restart or rebuild |
| Subscribe to output internal port | Modify tools External URL / Public URL |
| Port exposed to public internet | `Main menu [11 Docker Security management]` or `Main menu [8 Firewall rules]` tighten access |
| The overall configuration is confusing | `Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]` Restore from backup |

## Common mistakes

| Error | phenomenon | Process |
|---|---|---|
| Backend cannot be connected | 502 | Start the service first, and then confirm that `curl http://127.0.0.1:port/` or `curl http://PRIVATE_ADDRESS:port/` is available according to the actual backend |
| DNS did not resolve the VPS | The domain cannot be opened or the wrong server is accessed | Correct the A/AAAA record and wait for it to take effect |
| REALITY/node domain enabled Cloudflare Orange Cloud | Client cannot connect directly to VPS | The node domain is changed to DNS only / Gray Cloud; whether the Web domain is a proxy is determined according to actual needs. |
| Duplicate configuration of the same domain | Caddy/Nginx behaves erratically | Check existing sites first, then add new ones |
| Direct access to internal ports | security exposure | Only the HTTPS domain can be accessed externally |
| Subscription tool output `127.0.0.1` | Client is unavailable | Set external access address |
| When deleting the container, I mistakenly thought that the data was also backed up. | Data loss risk | Confirm Compose data directory and volume before stopping/archiving |

## Recommended maintenance habits

| Maintenance action | Recommended frequency |
|---|---|
| `Main menu [15 Service health overview]` Health Check | After every change |
| `Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]` backup | After each successful configuration change |
| Check `docker ps` | Every time you upgrade your subscription tool |
| Check subscription output | After each modification of the External URL |
| update script | Use `Main menu [17 Update script]` when there is a clear need |
