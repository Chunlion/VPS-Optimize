# Reverse Proxy a Standalone Subscription Tool through Caddy/Nginx and Port 443 Reuse

Use this guide to publish subscription tools such as SublinkPro, Sub-Store, and Miaomiaowu Subscription Management over HTTPS. Before Port 443 Reuse is enabled, use the Caddy or Nginx HTTPS reverse proxy in `Main menu [4 Reverse proxy]`. After it is enabled, add the domain through Port 443 Reuse's Web-domain/reverse-proxy menu, where you can choose Caddy or Nginx as the local Web reverse-proxy engine.

## Choose a path

| Current status | Recommended method |
|---|---|
| Port 443 Reuse is not enabled; you only need domain access to the tool | Use `Main menu [4 Reverse proxy]` and choose Caddy or Nginx HTTPS for the current environment. |
| Port 443 Reuse is enabled | Add the reverse-proxy domain in `Main menu [19 Port 443 Reuse] -> [8 Manage Web domains/reverse proxy]`. Use its `[8 Switch Web reverse-proxy engine]` option to change between Caddy and Nginx. |
| The tool is for personal use only | Bind its backend to localhost or a private-network address; expose it through Caddy, Nginx, or Port 443 Reuse. |
| You are unsure which path applies | Run `Main menu [1 Preflight and risk scan]` and `Main menu [15 Service health overview]` to check port and service status. |

## When to use this guide

| Situation | Suitable? |
|---|---|
| Deploy SublinkPro | Yes |
| Deploy Sub-Store | Yes |
| Deploy Miaomiaowu Subscription Management | Yes |
| Add HTTPS to a subscription tool already running in Docker | Yes |
| Expose the tool's internal port directly to the Internet | No |

## Prerequisites

| Material | Example | Description |
|---|---|---|
| VPS snapshot | Create one in your cloud provider's console | Recommended before changing reverse-proxy or container configuration. |
| Subscription domain | `sub.example.com` | Its DNS record points to this VPS. |
| Backend address and port | `127.0.0.1:3000`, `10.0.0.20:3000` | Example local or private-network backends; replace them with your actual values. |
| Cloudflare API Token | `Zone.Zone.Read`, `Zone.DNS.Edit` | Required when using DNS validation to issue certificates. |
| Current SSH session | Keep open | Lets you recover from a failure. |
| Docker/Compose | Checked and installed by the script when missing | Subscription tools are normally deployed with Docker Compose. |

DNS recommendations:

| Domain | Recommendation |
|---|---|
| `sub.example.com` | DNS only / Cloudflare proxy disabled |
| Domains used with Port 443 Reuse | DNS only / Cloudflare proxy disabled |
| Regular Web-only site | Choose whether to proxy it as needed, but start with the proxy disabled while completing this guide. |

## Estimated time

| Stage | Estimated time |
|---|---|
| Preflight | 2-5 minutes |
| Deploy subscription tools | 5-20 minutes |
| Configure Caddy/Nginx or Port 443 Reuse | 5-15 minutes |
| Verify subscription output | 5-10 minutes |
| Backup | 1–3 minutes |

## What will be modified?

| Component | Possible changes | Risk |
|---|---|---|
| Docker/Compose | Add new containers, networks, and deployment directories | Container port conflict or image pull failure |
| Caddy | Site configuration, certificates, and reverse-proxy rules | A bad configuration can cause 404 or 502 errors. |
| Nginx HTTPS reverse proxy | HTTPS site configuration when Port 443 Reuse is disabled | A configuration error or port conflict can disrupt ports 80/443. |
| Nginx Stream | SNI routing when using Port 443 Reuse | A configuration error can affect public port `443`. |
| Firewall | Only ingress ports should be public; backend ports should not be | An incorrect rule can expose internal services. |
| Backups | Configuration backups and quarantine directories | Uses a small amount of disk space. |

## Steps

### 1. Check the server first

Enter:

```text
Main menu [1 Preflight and risk scan]
```

Confirm the following:

| Item | Expected state |
|---|---|
| Docker | If missing, the tool installer will install it. |
| Port usage | The subscription-tool port does not conflict with an existing service. |
| DNS | The subscription domain resolves to this VPS. |
| Firewall | SSH and the ingress port are allowed. |
| System time | Accurate time is required for certificate issuance. |

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

Common menu paths:

| Tool | Menu path | Use case |
|---|---|---|
| SublinkPro | `Main menu [5 Panels, nodes, and subscription tools] -> [7 SublinkPro subscription stack]` | Convert, aggregate, and manage subscriptions. |
| Miaomiaowu Subscription Management | `Main menu [5 Panels, nodes, and subscription tools] -> [8 Miaomiaowu subscription stack]` | Manage subscriptions through a graphical interface. |
| Sub-Store | `Main menu [5 Panels, nodes, and subscription tools] -> [9 Sub-Store subscription stack]` | Advanced subscription processing and scripting. |
| Dockge | `Main menu [5 Panels, nodes, and subscription tools] -> [11 Dockge Compose]` | Manage multiple Compose projects. |

After installation, check the container status first:

```bash
docker ps
```

If the script deploys the project under `/opt`, list that directory to locate it:

```bash
ls /opt
```

### 3. Check the backend listener

Bind the subscription-tool backend to localhost or a private-network address rather than exposing it directly to the Internet. These are example values:

```text
127.0.0.1:3000
10.0.0.20:3000
```

Check:

Run the command that matches the backend address in use.

```bash
ss -lntp | grep -E ':3000|:3001|:3002'
curl -I http://127.0.0.1:3000/
curl -I http://10.0.0.20:3000/
```

If the backend listens on `0.0.0.0:3000`, it may be reachable from the Internet. Limit exposure with Docker's local exposure protection or firewall rules:

```text
Main menu [11 Docker Security management]
Main menu [8 Firewall rules]
```

Docker local exposure protection changes Docker networking and restarts Docker. Before using it, confirm that no container depends on a directly exposed public port.

### 4A. Option 1: Use Caddy or Nginx before Port 443 Reuse is enabled

Use this option when Port 443 Reuse is not enabled and you only need to access the subscription tool by domain.

Enter:

```text
Main menu [4 reverse proxy]
```

Choose for the current environment:

| Option | Use when |
|---|---|
| `[1 Add Caddy reverse proxy]` | You already use Caddy or want Caddy to manage the site. |
| `[2 Add Nginx HTTPS reverse proxy]` | Port 443 Reuse is disabled and Nginx should listen publicly on ports 80/443 for HTTPS. |

Use the following example values only as a reference; replace the domain and port with your actual values:

| Item | Example |
|---|---|
| Domain | `sub.example.com` |
| Backend port | `3000` |
| Backend protocol | Depends on the tool; usually HTTP. |

If you choose Nginx HTTPS reverse proxy, the script will reuse the existing `acme.sh + Cloudflare DNS API` certificate process and the certificate will still be installed to:

```text
/etc/caddy/certs/sub.example.com.crt
/etc/caddy/certs/sub.example.com.key
/root/cert/sub.example.com.crt
/root/cert/sub.example.com.key
```

`sub.example.com` is an example; replace it with the actual subscription domain. Nginx HTTPS reverse proxy is available only while Port 443 Reuse is disabled. If the script detects Port 443 Reuse configuration, it stops to prevent Nginx from taking public port `443`. Do not assign the same domain to both Caddy and Nginx.

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

If you receive a 502 response:

```bash
curl -I http://127.0.0.1:3000/
journalctl -u caddy -n 80 --no-pager
journalctl -u nginx -n 80 --no-pager
```

If certificate issuance fails, check Cloudflare token permissions, the authorized zone, `_acme-challenge` TXT propagation, server time, and the acme.sh logs. The script uses DNS-01; enabling Cloudflare proxying is not itself the direct cause of an issuance failure.

### 4B. Option 2: Add the service to Port 443 Reuse

Use this option after you have enabled:

```text
Main menu [19 Port 443 Reuse manager] -> [2 initial setup/installation Port 443 Reuse]
```

To add another subscription-tool domain later, do not rerun initial setup. Use:

```text
Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]
```

Use these example values:

| Item | Example |
|---|---|
| New Web/reverse-proxy domain | `sub.example.com` |
| Backend address | `127.0.0.1` |
| Backend port | `3000` |

For a Docker service, publish the container port on host address `127.0.0.1`, then enter that host port. For another private-network server, enter its actual private IP address or hostname only after confirming that this VPS can reach it directly.

The script updates the local Caddy or Nginx configuration for the selected Web reverse-proxy engine and issues a certificate. When it shows a high-risk confirmation, verify the snapshot, DNS, token, and backend port before entering uppercase `YES`.

If you previously created an independent Caddy/Nginx HTTPS reverse proxy in `Main menu [4 Reverse proxy]`, enabling or reapplying Port 443 Reuse isolates old configurations that could take public port `443`. Add future subscription-tool domains through `[19] -> [8]`; do not let the Nginx HTTPS reverse proxy in `[4 Reverse proxy]` listen directly on public port `443`.

Verify:

```bash
curl -I https://sub.example.com/
openssl s_client -connect serverIP:443 -servername sub.example.com </dev/null
```

### 5. Set the tool's external URL

Different tools have different names. Common fields include:

```text
External URL
Public URL
Base URL
SUBSCRIPTION_DOMAIN
External access address
```

Set it to the public HTTPS URL:

```text
https://sub.example.com/
```

Do not use:

```text
http://127.0.0.1:3000/
http://serverIP:3000/
https://sub.example.com:3000/
```

If generated subscription links still contain an internal port, clients may not be able to use them.

### 6. Verify the subscription output

Open in a browser:

```text
https://sub.example.com/
```

Or run:

```bash
curl -I https://sub.example.com/
curl -L https://sub.example.com/ -o /tmp/sub-tool-home.html
```

When inspecting the subscription output, focus on:

| Item | Expected value |
|---|---|
| Domain | A public domain. |
| Protocol | HTTPS. |
| Port | Default `443`; do not include an internal port. |
| Token | Does not appear in public logs. |
| Node address | Is not changed to `127.0.0.1`. |

### 7. Back up after success

Enter:

```text
Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]
```

If the tool uses Docker Compose, also record:

| Item | Where to keep it |
|---|---|
| Compose directory | `/opt/<PROJECT_NAME>` |
| Administrator account | Your password manager |
| External domain | Operations notes |
| Backend port | Operations notes |
| Cloudflare Token permissions | Cloudflare console |

## Verification

When Port 443 Reuse is disabled, verify the Caddy or Nginx reverse proxy that you use.

Caddy:

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

Port 443 Reuse diagnostics:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

You can also check manually:

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

## Rollback after a failure

| Problem | Action |
|---|---|
| Caddy configuration error | Restore a Caddy backup, or quarantine the new site configuration and reload Caddy. |
| Nginx HTTPS reverse-proxy error | Check `nginx -t`; the script writes its Nginx reverse-proxy configuration to `/etc/nginx/conf.d/vps_proxy_${domain}.conf`. |
| Unable to add a domain to Port 443 Reuse | Roll back using the script's automatic backup, or remove the domain in `Main menu [19 Port 443 Reuse] -> [8 Manage Web domains/reverse proxy]`. |
| Certificate failure | In `Main menu [19 Port 443 Reuse] -> [12 CF DNS / Caddy certificate maintenance]`, check the token and DNS, then reissue the certificate. |
| Container will not start | Open the corresponding tool-management menu to check status, restart, or rebuild. |
| Subscription output includes an internal port | Change the tool's External URL or Public URL. |
| A port is public | Restrict access in `Main menu [11 Docker security management]` or `Main menu [8 Firewall rules]`. |
| Configuration is inconsistent | Restore a backup in `Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]`. |

## Common problems

| Problem | Symptom | Action |
|---|---|---|
| Backend unreachable | 502 | Start the service, then confirm that `curl http://127.0.0.1:port/` or `curl http://PRIVATE_ADDRESS:port/` reaches the actual backend. |
| DNS does not resolve to the VPS | The domain fails or opens the wrong server | Correct the A/AAAA record and wait for it to propagate. |
| Cloudflare proxy enabled for a REALITY/node domain | Client cannot connect directly to the VPS | Set the node domain to DNS only; proxy Web domains only when appropriate. |
| Duplicate configuration for one domain | Caddy/Nginx behaves inconsistently | Check existing sites before adding a new one. |
| Direct access to an internal port | Security exposure | Expose only the HTTPS domain externally. |
| Subscription output contains `127.0.0.1` | The client cannot use it | Set the external URL. |
| Container removal was assumed to back up its data | Data-loss risk | Confirm the Compose data directory and volumes before stopping or archiving. |

## Ongoing maintenance

| Maintenance action | Recommended frequency |
|---|---|
| Run `Main menu [15 Service health overview]` | After each reverse-proxy change. |
| Back up in `Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]` | After every successful configuration change. |
| Check `docker ps` | Each time you update the subscription tool. |
| Check subscription output | After changing the External URL. |
| Update the script | Use `Main menu [17 Update script]` only when needed. |
