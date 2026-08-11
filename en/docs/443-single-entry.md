---
outline: 2
---

# Port 443 Reuse: Setup and Configuration

This guide puts the panel, subscription service, websites, and REALITY on one public `443` port. Replace every example domain and port with your own value.

## Choose the entry mode first

If you are unsure, choose **Nginx Stream**. It is the recommended first deployment and the easiest path to troubleshoot.

| Mode | Use it when | Recommendation |
| --- | --- | --- |
| **Nginx Stream** | First deployment or a stable setup | **Recommended** |
| **TCP Peek + Splice** | Nginx Stream already works and you want the TCP Peek path | Switch to it later |
| **Xray Fallback** | You already have a complete Xray main inbound that can own public `443` | Advanced; not the first choice |

Only one service can listen on public `443` at a time:

```text
Public 443 -> the single service selected by the current ENTRY_MODE
Normal HTTPS / websites -> Caddy or Nginx -> your local website
Panel / subscription -> Caddy or Nginx -> the local 3x-ui HTTP ports
REALITY nodes -> the local Xray / 3x-ui inbound
```

For a normal 3x-ui + website + REALITY setup, select Nginx Stream and continue.

## See one complete example

The values below show what each field means. They are examples only; replace them in production.

| Item | Example value | Used for |
| --- | --- | --- |
| Panel domain | `panel.example.com` | Open the 3x-ui panel in a browser |
| Node domain | `node.example.com` | Client node address and subscription domain |
| Website domain | `site.example.com` | Normal HTTPS website |
| REALITY target | `www.example.org` | Camouflage HTTPS site; example value |
| Local panel port | `40000` | 3x-ui listens on the VPS only |
| Local subscription port | `2096` | Subscription service listens on the VPS only |
| Local REALITY port | `1443` | Xray / 3x-ui inbound used by the local entry |
| Website backend | `127.0.0.1:3000` | The website process behind the entry |

With these example values, users visit `https://panel.example.com`, `https://node.example.com/sub/`, and use node port `443`. Do not expose `40000`, `2096`, `1443`, or `3000` directly to the Internet.

Keep these three kinds of values separate:

- `panel.example.com` and `node.example.com` are public names used by visitors and clients.
- `127.0.0.1:40000`, `127.0.0.1:2096`, and `127.0.0.1:1443` are local forwarding addresses inside the VPS.
- The REALITY `serverName` is the camouflage target, such as `www.example.org`; it is not your panel domain or node domain.

## Before deployment

### Prepare domains and DNS

- Prepare a panel domain and a node domain, such as `panel.example.com` and `node.example.com`.
- Point them to the VPS in your DNS provider.
- For REALITY `serverName` / `target`, prefer a stable, directly reachable HTTPS site without CDN protection. If a CDN domain is unavoidable, enable [REALITY fallback traffic protection](#reality-fallback-traffic-protection) after setup; otherwise failed REALITY connections may turn the server into a CDN relay and consume bandwidth.
- Keep the current SSH session open. Allow SSH and TCP `443` in the cloud security group and the system firewall.

Use the example domains like this:

| Domain | DNS points to | Used for |
| --- | --- | --- |
| `panel.example.com` | VPS public IP | Panel and Web reverse proxy |
| `node.example.com` | VPS public IP | Node address, subscription domain, Hosts address |
| `www.example.org` | The target site's own address | REALITY `serverName` / `target`, not the VPS |

Panel and node domains may use a CDN if that fits your access needs. Prefer a non-CDN site for the REALITY target. Do not use the node domain as the REALITY camouflage target.

### Cloudflare DNS API (when using Cloudflare)

VPS-Optimize uses `acme.sh + Cloudflare DNS API` for certificates. Create a token with DNS-edit permission only for the required zone, and never paste the token into documentation or chat. DNS-01 validation lets the script issue the certificate for the Web reverse proxy; 3x-ui and the subscription service do not need separate public certificates.

### Keep an SSH fallback and a backup

Before changing port ownership, keep one SSH session open and make a configuration backup. If your provider has an out-of-band console, confirm that it is available. Do not start a first-time `443` switch while relying on the same connection that may be interrupted.

### Check that 443 is available

Run on the VPS:

```bash
ss -lntp | grep ':443'
```

If Nginx, Caddy, or another service already uses `443`, note what it does before continuing. The script checks conflicts during a switch but cannot decide which service you want to replace.

## Deploy in this order

### 1. Install 3x-ui on loopback

During 3x-ui installation:

1. Choose `Skip SSL (advanced — behind reverse proxy / SSH tunnel only)` for the panel certificate.
2. Set the listen IP to `127.0.0.1`.
3. Choose a panel port and path, and keep them for the reverse-proxy step. To follow the example, use:

   ```text
   Panel port: 40000
   Panel path: /panel/
   ```

   If the installer does not offer a path, keep the path it displays instead of inventing one.

The panel is then reachable through the shared `443` entry instead of a public panel port.

After installation, do not use `http://server-ip:40000` as the permanent URL. Finish the shared `443` setup first, then use `https://panel.example.com/panel/` (or the path actually shown by your panel).

If the panel settings still show certificate and key file fields, clear both. Public HTTPS is handled by Caddy or Nginx; 3x-ui should provide only a local HTTP page.

### 2. Configure the local subscription service

In the 3x-ui subscription settings:

- Listen address: `127.0.0.1`.
- Subscription port: an unused local port, for example `2096`.
- Subscription domain: your node domain.
- Paths: use the paths shown by the panel, for example `/sub/` and `/clash/`.
- Do not give the subscription service a separate public certificate; the selected Web reverse proxy handles public HTTPS.

Using the example values:

```text
Listen address: 127.0.0.1
Listen port: 2096
Subscription domain: node.example.com
Subscription path: /sub/
Clash/Mihomo path: /clash/
```

Users eventually open `https://node.example.com/sub/`; do not put `:2096` into the public link.

If the subscription settings show subscription certificate and key fields, clear both as well. Otherwise 3x-ui may try to provide a second HTTPS service on the local port.

### 3. Configure the REALITY inbound

Create or edit a VLESS REALITY inbound in 3x-ui:

- Listen address: `127.0.0.1`.
- Listen port: a local port such as `1443`, not public `443`.
- Transport: TCP.
- Security: REALITY.
- `serverName` / `target`: the real HTTPS site you prepared.
- `serverNames`: use the same SNI.
- Fingerprint: `chrome` is a common choice.
- Leave `Fallbacks` empty unless you specifically need them.

Using the example values, the important fields look like this:

```text
Listen address: 127.0.0.1
Listen port: 1443
serverName / target: www.example.org
serverNames: www.example.org
Fingerprint: chrome
```

Let 3x-ui generate the UUID, private/public keys, and short ID. Do not copy another user's example values. Give the inbound a clear remark such as `VLESS-REALITY`; you will select this inbound in Hosts.

The client link should use your node domain and port `443`, not `127.0.0.1:1443`.

### 4. Run the Port 443 wizard

Open:

```text
Main menu [19 Port 443 Reuse Management] -> [2 Install / switch 443 entry mode]
```

For the first deployment:

1. Select **Nginx Stream**.
2. Select Caddy or Nginx as the Web reverse-proxy engine; keep the default if unsure.
3. Enter the panel domain, node domain, and REALITY SNI.
4. For the panel, enter backend address `127.0.0.1` and port `40000`; for the subscription, use `127.0.0.1` and `2096`.
5. For a new website, use `Backend address: 127.0.0.1` and a port such as `3000`. If the app runs in Docker, publish its container port to the host loopback address (for example `127.0.0.1:3000:3000`) and enter host port `3000` here.
6. Review every domain and port before saving.

Before saving, the script checks whether the backend is reachable. Fix the address or port if that check fails. Do not expose backend ports directly to the Internet.

### 5. Link the node domain in 3x-ui

Return to 3x-ui after the wizard finishes:

- Confirm the panel still listens on `127.0.0.1`.
- Confirm the subscription domain, path, and port.
- For 3x-ui v3.4.0 and later: open `Hosts` and add a Host. With the example values, fill it as follows:
  - Inbound: select the VLESS REALITY inbound listening on `127.0.0.1:1443`.
  - Address: `node.example.com`.
  - Port: `443`.
  - Security / SNI / Fingerprint / ALPN: keep them consistent with the inbound and client, for example `REALITY`, `www.example.org`, `chrome`, and the inbound's actual ALPN.
- For 3x-ui v3.3.1 and earlier: open `External Proxy` in the REALITY inbound. Keep the type consistent, set the address to `node.example.com`, and set the port to `443`; do not enter `127.0.0.1:1443`.
- Copy the node link and verify that it uses the node domain and port `443`.

The Hosts **address** is the public node domain, not the local listen address. The **Inbound** field is what connects that public name to the local REALITY inbound. The expected result is:

```text
Client address: node.example.com
Client port: 443
Hosts address: node.example.com
Hosts port: 443
REALITY inbound listen: 127.0.0.1:1443
REALITY SNI: www.example.org
```

If the generated link still contains `127.0.0.1:1443` or `node.example.com:1443`, fix Hosts / External Proxy before testing the client.

### 6. Test and back up

Open the panel domain in a browser, open the subscription URL, and test a node. When all three work, create a configuration backup from the menu.

These read-only checks are useful on the VPS:

```bash
ss -lntp | grep -E ':(443|40000|2096|1443)'
curl -I https://panel.example.com/panel/
curl -I https://node.example.com/sub/
```

Only the shared entry needs to be public on `443`; the other example ports should be bound to `127.0.0.1`. Use the paths actually shown by your panel.

If the panel is unavailable, check local ports and the current entry status before reinstalling anything. See [Troubleshooting and Recovery](443-single-entry-troubleshooting.md).

## Switch modes and roll back

### Switch to TCP Peek + Splice

TCP Peek uses a lightweight early SNI decision. It is not a second panel setup: **the configuration process is the same as Nginx Stream**. Finish the deployment above first, then switch:

```text
Main menu [19 Port 443 Reuse Management] -> [2 Install / switch 443 entry mode] -> [3 TCP Peek + Splice]
```

The script checks dependencies, ports, and backend reachability. Keep the SSH session open until the new entry is confirmed.

### Use Xray Fallback

Choose this only when an Xray main inbound is already configured to own public `443`. Xray receives `443` and sends normal HTTPS to the selected Caddy or Nginx Web reverse proxy. This mode is not intended for managing several Xray inbounds through the script's SNI route menu.

### Roll back the last switch

If a switch fails, run:

```text
Main menu [19 Port 443 Reuse Management] -> [7 Roll back the previous entry-mode switch]
```

Then check the panel domain, node link, and `ss -lntp | grep ':443'` again.

## Common maintenance

### Manage Web domains and reverse proxies

Use:

```text
Main menu [19 Port 443 Reuse Management] -> [8 Manage Web domains / reverse proxy]
```

To change Caddy or Nginx, choose `[8 Switch Web reverse-proxy engine]`. Both engines use the same domain and certificate settings; check the backend before switching.

The full path is:

```text
Main menu [19 Port 443 Reuse Management] -> [8 Manage Web domains / reverse proxy] -> [8 Switch Web reverse-proxy engine]
```

The script regenerates the selected engine's configuration and keeps the saved domains, certificates, and backends. Do not start a second hand-written Caddy/Nginx configuration that can take the same port.

For a new website, fill the fields in this order: domain, backend address, backend port. For an app listening on `127.0.0.1:3000`:

```text
Domain: site.example.com
Backend address: 127.0.0.1
Backend port: 3000
```

Then open `https://site.example.com` in a browser. If the app is inside a container, publish it to the host loopback address first; do not use a container-only hostname as the VPS backend address.

### Manage the Web IP allowlist

The Web allowlist applies to websites and the panel, not REALITY node traffic. In `nginx-stream` or `tcp-peek`, use `[4] -> [5 Domain IP allowlist]`. From Web domain management, use:

```text
Main menu [19 Port 443 Reuse Management] -> [8 Manage Web domains / reverse proxy] -> [5 Manage domain IP allowlist]
```

For `xray-fallback`, regardless of whether Caddy or Nginx is the local Web reverse proxy, the allowlist only protects Web domains. It is not REALITY authentication.

## REALITY fallback traffic protection

When a CDN domain is used as the REALITY SNI, enable both controls where available:

1. **SNI filtering**: only registered Web domains, SNI routes, and the REALITY SNI are accepted; unknown SNI is dropped.
2. **Fallback rate limiting**: only connections that fail REALITY verification and are sent to fallback are limited.

Nginx Stream and TCP Peek support both controls. Xray Fallback has no front SNI filter, but it can still use fallback rate limiting. SNI filtering does not replace REALITY keys or normal client verification, and it does not interrupt a correctly configured node.

Open the controls here:

```text
Main menu [19 Port 443 Reuse Management] -> [17 REALITY fallback traffic protection]
```

The useful actions are:

1. `[1] Enable strict SNI gate`: allow only registered SNIs in Nginx Stream / TCP Peek.
2. `[3] Resynchronize the current SNI list`: run this after adding a domain or route.
3. `[4] Set REALITY fallback rate limits`: limit only failed-authentication fallback connections; the script generates randomized values and asks for confirmation.
4. `[5] Clear REALITY fallback rate limits`: restore Xray's default behavior; confirmation is required.

Changing fallback limits restarts the panel or Xray service. Do it outside important transfers and keep the generated backup. For a non-CDN REALITY target, fallback limiting is usually unnecessary.

The strict SNI list is generated from registered Web domains, SNI routes, and the REALITY SNI. After adding a domain or changing a node SNI, save the configuration and run `[3] Resynchronize the current SNI list`; otherwise the new name may be rejected as unknown. This filter does not verify UUIDs, keys, or other REALITY credentials.

If possible, use a non-CDN HTTPS site as the REALITY target; it reduces the impact of a configuration mistake.

## Verify and troubleshoot

1. Run `ss -lntp | grep ':443'` and confirm that only the current entry service owns public `443`.
2. Open the panel domain and the subscription URL in a browser.
3. Test a node whose link uses the node domain and port `443`.
4. Confirm that the REALITY SNI is the selected target site.
5. For `403/401`, check the Web allowlist, CDN/WAF, and Host/SNI first. For `502`, check the backend address and port. For timeouts, check the firewall, cloud security group, and the `443` listener.
6. Use `Main menu [19 Port 443 Reuse Management] -> [13 Port 443 connection health check]` for entry, certificate, Web, and Xray status. Use `[14 Port 443 network access test]` for public DNS/TCP/TLS tests.
7. For failures, read [Troubleshooting and Recovery](443-single-entry-troubleshooting.md). For mode details, read [Entry Modes and Internals](443-tcp-peek-engine.md).

## Avoid these mistakes

- Do not expose the 3x-ui panel, subscription service, or website backend directly to the Internet.
- Do not let two services listen on public `443` at the same time.
- Do not use the panel domain, node domain, or a local address as the REALITY camouflage target.
- Do not switch the entry without a working SSH session and a backup.
- Do not copy example domains, ports, or paths into production unchanged.
