# 3x-ui + REALITY: Port 443 Reuse Deployment Guide

This guide shows how to run the 3x-ui panel, subscription, websites, and REALITY through one public port, `443`.

Only one service listens on public port `443` at a time:

- `nginx-stream`: Nginx Stream routes by SNI.
- `tcp-peek`: `vpso-mux` routes by SNI.
- `xray-fallback`: the Xray main inbound listens on `443` and falls back to the local web reverse proxy.

Local backends should listen on `127.0.0.1` whenever possible.

- [Port 443 Reuse Configuration Guide](../docs/443-single-entry.md)
- [Port 443 Reuse Troubleshooting](../docs/443-single-entry-troubleshooting.md)

## Example description

The domains, paths, and ports in this article are examples and are not fixed values that must be copied. `panel.example.com` is an example panel domain, `node.example.com` is an example node domain, `site.example.com` is an example website domain, `40000` is an example 3x-ui panel port, `2096` is an example subscription port, and `8443` is an example Web The reverse proxy engine local port, `1443` is the example Xray/REALITY local port.

Please replace it with your own domain, path and port during actual deployment; if the script has already saved the configuration, the current display of the script shall prevail. Do not blindly copy the examples in the tutorial.

## Suitable for whom

| situation | Is it suitable |
|---|---|
| New machine ready for deployment 3x-ui + REALITY | suitable for |
| I already have 3x-ui and want to connect the panel and subscription to the public port `443` | suitable for |
| The Caddy/Nginx website already occupies 443 | Suitable, but the old site must be backed up and migrated first |
| It is hoped that Caddy, 3x-ui, and Xray will each listens on the public port `443` | Not suitable, should be unified entrance |
| Not sure about the relationship between DNS, Cloudflare and certificates | It is recommended to read the complete tutorial before proceeding |

## Prepare materials

| Material | Example | Description |
|---|---|---|
| VPS Snapshot | cloud provider console creation | Must be done before taking over `443` for the first time |
| Panel domain | `panel.example.com` | Access the 3x-ui panel and subscribe |
| Node domain | `node.example.com` | Optional, server IP can also be used |
| Cloudflare API Token | `Zone.Zone.Read`、`Zone.DNS.Edit` | Used to issue certificates for DNS |
| REALITY disguise SNI | `www.microsoft.com` | External real HTTPS site, do not write your own domain |
| Current SSH session | not closed | Used for recovery in case of failure |

Cloudflare Suggestions:

| domain | Suggestion status |
|---|---|
| Panel domain | DNS only / gray cloud |
| Node domain | DNS only / gray cloud |
| Subscribe to domain | DNS only / gray cloud |
| REALITY disguise SNI | External real HTTPS site, not pointing to your VPS |

## Estimated time

| stage | Estimated time |
|---|---|
| Pre-check and basic preparation | 5-10 minutes |
| Install/Configure 3x-ui | 10-20 minutes |
| Configure REALITY inbound | 5-10 minutes |
| initial setup Port 443 Reuse | 10-20 minutes |
| Verification and backup | 5-10 minutes |

## What will be modified?

| Project | Modify content | risk |
|---|---|---|
| 3x-ui | Panel port, path, certificate path, subscription settings, REALITY inbound | If the panel path or certificate is set incorrectly, it will not open. |
| Current Port 443 Reuse service | Handles public port `443` and routes traffic | Port conflicts can prevent the current entry mode from starting or switching. |
| Current web reverse proxy engine | Local HTTPS reverse proxy and certificate | Configuration error will result in 404/502/certificate failure |
| Xray/REALITY | Local binding and masquerading SNI | If SNI is written incorrectly, the connection will fail. |
| firewall | It is recommended to keep only SSH and public port `443` | Deleting the port by mistake will cause the connection to be disconnected |
| backup | Create SNI stack and manual configuration backup | Occupies a small amount of disk |

## Recommended architecture

```text
public port `443` -> A single service corresponding to the current entry mode
  nginx-stream  -> Nginx stream route by SNI routing
  tcp-peek      -> vpso-mux route by SNI routing
  xray-fallback -> Xray main inbound takeover 443 And fallback to local Web reverse proxy engine

panel.example.com  -> current Web reverse proxy engine (Caddy or Nginx, For example 127.0.0.1:8443)-> 3x-ui panel 127.0.0.1:40000
panel.example.com/sub/ -> current Web reverse proxy engine (Caddy or Nginx)-> 3x-ui Subscribe 127.0.0.1:2096
REALITY SNI / unknown SNI -> Xray REALITY 127.0.0.1:1443
site.example.com -> Caddy/Nginx local Web reverse proxy -> Local website backend
```

Key principles:

| principles | Description |
|---|---|
| public port `443` only provides a single service corresponding to the current entry mode. | Avoid Caddy, Xray, panel and `vpso-mux` from grabbing ports from each other |
| The web reverse proxy engine listens to the local HTTPS port | Browser HTTPS is handled by Caddy or Nginx native web reverse proxy, `8443` is just an example value |
| 3x-ui panel does not use its own certificate as the public HTTPS | Panel as local HTTP backend |
| REALITY uses external real SNI | Do not write `dest` as your own panel domain |
| Tighten the firewall after success | Run through first, then keep only necessary ports |

`Xray Inbound connection management` only records `SNI -> local address:port`, not the 3x-ui inbound connection editor; the local inbound connection needs to be created and enabled in 3x-ui first. Nginx Stream mode and TCP Peek + Splice mode support multiple local Xray inbound connections routed by SNI; Xray itself can have multiple inbound connections, but in xray-fallback mode the Internet `443` defaults to one Xray The main inbound connection connection takes over, and the script currently does not support continuing to route multiple local Xray inbound connections by multiple SNI in this mode.

Ordinary TLS and REALITY should be judged separately: Ordinary TLS pays more attention to whether the local certificate, Web fallback, and Host/SNI match; REALITY pays more attention to whether the external target site is truly accessible and whether the TLS characteristics are stable. REALITY is not required. `serverName` joins the Web reverse proxy engine and does not require the local certificate to cover REALITY `serverName`. The certificate policy still uses `acme.sh + Cloudflare DNS API`, does not use the Caddy DNS module, and does not require `xcaddy`. The certificate selected during the 3x-ui installation phase is only used to complete the installation process and is not the certificate scheme ultimately used by Port 443 Reuse.

## Operation steps

### 1. Do a pre-check

Enter:

```text
Main menu [1 Preflight and risk scan]
```

Key points to confirm:

| Project | Expectation |
|---|---|
| DNS | Can resolve your domain and external HTTPS site |
| port | The current occupancy status of `443` is clear |
| system | Available for Debian/Ubuntu/RHEL systems |
| time | System time is accurate, certificate issuance depends on time |
| Package manager | Not occupied by other processes |

Check the public port `443`:

```bash
ss -lntp | grep ':443' || echo "443 not listening"
```

If Caddy/Nginx/Apache already occupies the public port `443`, first record the existing site domain and back-end port, and then re-register it through `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]`.

### 2. Install or enter 3x-ui

Enter:

```text
Main menu [5 panel、Nodes and subscription tools] -> [1 3x-ui panel script]
```

If 3x-ui is not installed, install it. The current official installer provides option 4, `Skip SSL (advanced — behind reverse proxy / SSH tunnel only)`. Choose it for this Port 443 Reuse setup; when asked whether to bind only to `127.0.0.1`, enter `y`.

Risk: choose Skip SSL only when a reverse proxy or SSH tunnel is already in use. Bind the panel to loopback during installation; never expose an unencrypted public HTTP panel port.

| Installer options | Role in this tutorial | Follow-up processing |
|---|---|---|
| Skip SSL | Recommended local HTTP backend | Bind only to `127.0.0.1` |
| Apply for a certificate for a domain | Can be used to temporarily complete the 3x-ui installation | Clear the 3x-ui certificate path before accessing 443 |
| Request a certificate for an IP | It is only used as a temporary transition and is not recommended as a formal public HTTPS | Clear the 3x-ui certificate path before accessing 443 |
| Select an existing certificate path | Can be used to temporarily complete the installation | Clear the 3x-ui certificate path before accessing 443 |

The final architecture is: the public HTTPS is uniformly processed by the current Web reverse proxy engine (Caddy or Nginx), and the certificate is applied and installed by VPS-Optimize using `acme.sh + Cloudflare DNS API`; the 3x-ui panel and subscription are only used as local HTTP Backend, 3x-ui's own certificate is not used as the final public certificate solution.

With Skip SSL, configure the loopback listener during installation; do not use a public panel port as a temporary workaround.

It is recommended to record these values:

| Project | Example |
|---|---|
| Panel port | `40000` |
| Panel path | `/panel/` |
| Administrator account | Save it yourself |
| Administrator password | Save it yourself |
| Subscription port | `2096` |
| standard subscription path | `/sub/` |
| Clash/Mihomo path | `/clash/` |

### 3. Clear the 3x-ui panel certificate path

As long as you are ready to access the Port 443 Reuse of VPS-Optimize, you should clear the 3x-ui panel and subscription certificate path and let the Web reverse proxy engine take over the public HTTPS.

Enter the 3x-ui panel:

```text
The `webCertFile` and `webKeyFile` fields in Panel Settings
```

Clear all similar fields:

```text
Certificate path
Private key path
Public key file path
Private key file path
```

Save and restart the panel.

Reason: After accessing the Port 443 Reuse, the public HTTPS is processed by the Web reverse proxy engine, and the 3x-ui panel only uses the local HTTP backend. If not cleared, it may result in 502 Bad Gateway, HTTP/HTTPS backend protocol mismatch, redirect loop, certificate path confusion, panel or subscription exception.

### 4. Set up panel binding

A set of example values:

| Project | Example value |
|---|---|
| `webListen` | `127.0.0.1` |
| `webPort` | `40000` |
| `webBasePath` | `/panel/` |
| `webCertFile` / `webKeyFile` | Clear |

Before accessing the Port 443 Reuse, you should change it to `127.0.0.1`, bind it locally and close the panel HTTPS; Internet access only uses the Port 443 Reuse and the Web reverse proxy engine, and does not reserve the panel public port as a transition.

Verify local backend:

```bash
curl -I http://127.0.0.1:40000/panel/
```

### 5. Set up a subscription service

Example in 3x-ui subscription settings:

| Project | Example value |
|---|---|
| `subListen` | `127.0.0.1` |
| `subPort` | `2096` |
| `subPath` | `/sub/` |
| `subClashPath` | `/clash/` |
| `subCertFile` / `subKeyFile` | Clear |
| `subDomain` | `panel.example.com` |

`subDomain` is only a domain: do not include `https://`, a port, or a path. Keep leading and trailing `/` in `subPath` and `subClashPath`. Do not use:

```text
sub
/sub
sub/
/sub/CustomerSubscription
```

Verify local subscription:

```bash
curl -I http://127.0.0.1:2096/sub/
```

If 404, first confirm whether the subscription service of 3x-ui is enabled and whether the paths are consistent.

### 6. Create a new REALITY inbound

Add VLESS REALITY inbound in 3x-ui, example:

| Project | Example value |
|---|---|
| agreement | VLESS |
| transmission | TCP / RAW |
| Security | REALITY |
| listening address | `127.0.0.1` |
| listening port | `1443` |
| uTLS | chrome |
| `dest` / `Target` | `www.microsoft.com:443` or other external real HTTPS site |
| `serverNames` / `SNI` | `www.microsoft.com` |
| SpiderX | `/` |
| Fallbacks | Leave blank |

Don't write:

```text
panel.example.com:443
node.example.com:443
127.0.0.1:8443
```

First verify that the disguised SNI can be connected:

```bash
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com </dev/null
```

You can see the certificate output, indicating that the external SNI site is available.

In current 3x-ui, leaving `Min Client Ver` empty does not mean unrestricted support; it uses Xray core's built-in minimum version. If a third-party client cannot connect, update its core first. Consider `1.0.0` only when the compatibility requirement is confirmed and you accept the risk of admitting outdated fingerprints.

### 7. initial setup of Port 443 Reuse

Enter:

```text
Main menu [19 Port 443 Reuse manager] -> [2 initial setup/installation Port 443 Reuse]
```

Example to fill in:

| Project | Example value |
|---|---|
| Panel domain | `panel.example.com` |
| REALITY disguise SNI | `www.microsoft.com` |
| 443 Entry mode | `nginx-stream` / `xray-fallback` / `tcp-peek` |
| public port `443` listener | Taken over by a Port 443 Reuse service corresponding to the current entry mode |
| Web reverse proxy engine local listening address | `127.0.0.1` |
| Web reverse proxy engine local listening port | `8443` |
| Xray REALITY local listening address | `127.0.0.1` |
| Xray REALITY local listening port | `1443` |
| 3x-ui panel binding address | `127.0.0.1` |
| 3x-ui panel port | `40000` |
| 3x-ui panel public internet path | `/panel/` |
| 3x-ui subscription listening address | `127.0.0.1` |
| 3x-ui subscription port | `2096` |
| standard subscription path prefix | `/sub/` |
| Clash/Mihomo path prefix | `/clash/` |

If `/etc/vps-optimize/sni-stack.env` does not have `ENTRY_MODE`, the script will only be processed as `nginx-stream` when it is compatible with reading the old configuration; new configurations and subsequent saves should be based on the actual selected `ENTRY_MODE`.

When a high-risk confirmation card appears in the script, confirm that the following conditions are met before entering uppercase `YES`:

- VPS snapshot created.
- The current SSH session is not disconnected.
- The cloud security group allows ports SSH and `443/tcp`.
- The panel domain DNS has been resolved to the current VPS.
- Cloudflare Token has correct permissions.

### 8. Run link health check

Enter:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

The health check will check the current entry service, web reverse proxy engine, REALITY, panel backend, 3x-ui panel/subscription certificate path residue and security items.

Manual additional checks:

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
openssl s_client -connect serverIP:443 -servername panel.example.com </dev/null
```

Expectations:

| Check items | Expectation |
|---|---|
| public port `443` | Only bound by a Port 443 Reuse service corresponding to the current `ENTRY_MODE` |
| Web reverse proxy engine | `127.0.0.1:8443`, subject to the current configuration of the script |
| REALITY | `127.0.0.1:1443` |
| panel | `127.0.0.1:40000` |
| Subscribe | `127.0.0.1:2096` |
| Browser access | `https://panel.example.com/panel/` |

### 9. Check CLIENT_SUBSCRIPTION, Hosts / External Proxy and REALITY

Subscription links should not appear:

```text
:2096
:40000
:8443
127.0.0.1
```

The node link needs to output the public port `443`.

3x-ui v3.4.0 and later: Open `Hosts / Host` and add a Host:

```text
inbound：select this REALITY inbound
address：node.example.com Or server public IP
port：443
Security：Same, Or fill in the actual security type of the inbound
SNI / Fingerprint / ALPN：Keep the actual value of the inbound and client consistent
```

3x-ui v3.3.1 and before: Open `External Proxy` in REALITY inbound:

```text
Type：Same
address：node.example.com Or server public IP
port：443
```

Key points to confirm in the REALITY node:

| Project | Expectation |
|---|---|
| address | Node domain or server public IP |
| port | `443` |
| security | `reality` |
| SNI | External real HTTPS site |
| flow | Consistent with your client and inbound configurations |

If the panel opens normally but REALITY cannot connect, first check whether `dest`, `serverNames`, local listening port, and SNI routing or Xray fallback takeover in current entry mode are as expected.

### 10. Backup after success

Enter:

```text
Main menu [16 Configuration backup and rollback] -> [1 Create full configuration backup]
```

Check again:

```text
Main menu [16 Configuration backup and rollback] -> [2 View existing backups]
```

It is recommended to record additionally:

| content | record location |
|---|---|
| Panel domain and path | Your own password manager or operation and maintenance notes |
| REALITY SNI | Operation and maintenance notes |
| Subscription path | Operation and maintenance notes |
| Cloudflare Token permissions | Cloudflare console |

## Verification method

Complete verification command:

```bash
ss -lntp
systemctl status nginx --no-pager
systemctl status caddy --no-pager
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
openssl s_client -connect serverIP:443 -servername panel.example.com </dev/null
```

Menu verification:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
Main menu [15 Service health overview]
```

## How to roll back if failed

| situation | Process |
|---|---|
| Nginx/Caddy failed after configuration writing | The script will try its best to automatically roll back to this backup. |
| Panel cannot be opened | `Main menu [5 panel、Nodes and subscription tools] -> [3 panel SSL Repair]` Clean the panel SSL, then check the local port |
| Certificate failed | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance]` Check Token, DNS, and re-sign certificate |
| 443 occupied | `ss -lntp | grep ':443''` to find the occupier, and then adjust it to local binding |
| Subscribe 404 | Check whether the 3x-ui subscription path is consistent with the current web reverse proxy engine path |
| REALITY failed | Check REALITY local listening, SNI, dest and client node ports |
| The overall configuration is confusing | `Main menu [16 Configuration backup and rollback] -> [3 Restore from backup]` Rollback from manual backup |

## Common mistakes

| Error | phenomenon | Process |
|---|---|---|
| The web reverse proxy engine also listens on the public port `443` | The current entry service failed to start or there is a port conflict. | The web reverse proxy engine is changed to local binding, such as `127.0.0.1:8443` |
| 3x-ui comes with the panel HTTPS Doesn’t matter | Redirect loop, certificate error | Clear the panel certificate path and restart |
| REALITY Write your own domain to make SNI | Client connection failed | Change to external real HTTPS site |
| The subscription path does not contain `/` | Subscribe 404 | Write uniformly `/sub/`, `/clash/` |
| REALITY/node domain enabled Cloudflare Orange Cloud | Client cannot connect directly to VPS | The node domain is changed to DNS only / Gray Cloud; the DNS-01 certificate issue is individually checked for Token, zone and TXT propagation |
| `subDomain` includes a scheme, port, or path | Subscription returns 404 or the Host does not match | Use only `panel.example.com` |
| Hosts / External Proxy output internal port | The client node cannot connect to the public port `443` | 3x-ui v3.4.0+ check `Hosts / Host`; old version check `External Proxy` |
| Repeatedly rerun without backup | The configuration is getting messy | Make a backup first, then follow the troubleshooting manual to fix it item by item. |
