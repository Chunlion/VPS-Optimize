# Port 443 Reuse Configuration Guide

When encountering panel failure to open, subscription 404, certificate failure, or REALITY connection failure, first read: [Port 443 Reuse Troubleshooting](443-single-entry-troubleshooting.md).

This document teaches you how to connect the VPS Internet `443` to the Port 443 Reuse of VPS-Optimize. Nginx Stream is recommended by default, and you can also switch to TCP Peek + Splice or Xray Fallback after the configuration is completed. No matter which entry mode is selected, Internet `443` is only bound by a single service corresponding to the current `ENTRY_MODE` at the same time.

The current Port 443 Reuse link is:

```text
public port `443` -> current ENTRY_MODE Corresponding Port 443 Reuse service
  nginx-stream  -> nginx route by SNI routing
  tcp-peek      -> vpso-mux route by SNI routing
  xray-fallback -> Xray main inbound takeover 443, And fallback Ordinary HTTPS

Ordinary HTTPS / Web domain -> currently selected local Web reverse proxy engine (Caddy or Nginx)-> locally reachable HTTP backend
3x-ui Panel -> Currently selected local Web reverse proxy engine -> 127.0.0.1:40000
3x-ui Subscription -> Currently selected local Web reverse proxy engine -> 127.0.0.1:2096
REALITY / Xray SNI    -> local Xray / 3x-ui inbound -> 127.0.0.1:1443
```

`127.0.0.1:40000`, `127.0.0.1:2096`, and `127.0.0.1:1443` in the picture are just example values. The advantage of this is that only one `443` is exposed on the public internet. The ordinary HTTPS falls to the currently selected local web reverse proxy engine (Caddy or Nginx). The certificate is applied and installed by VPS-Optimize using `acme.sh + Cloudflare DNS API`. The 3x-ui panel and subscription service only serve the local HTTP backend. The 3x-ui self-contained certificate is not used as the final public certificate solution to avoid duplication of HTTPS, port conflicts, redirect loops and certificate path confusion.

Newly added websites/reverse proxys use the `127.0.0.1` backend by default. Docker service recommends publishing the container port to the host loopback address, and then filling in the corresponding host port; only fill in the custom backend address if the current VPS can indeed resolve and access the intranet IP or hostname. The script will check whether the backend is connectable before saving. If it fails, explicit confirmation is required before continuing. Do not expose the backend port directly to the public internet.

## Example description

The domains, paths, and ports appearing in this article are only examples to facilitate understanding of the architecture, and are not fixed values that must be copied.

For example:

- `panel.example.com` = Sample panel domain
- `node.example.com` = Sample node domain
- `site.example.com` = Sample website domain
- `40000` = Example 3x-ui panel port
- `2096` = Sample subscription port
- `8443` = Sample Web Reverse Engine local HTTPS port
- `1443` = Example Xray/REALITY local port

During actual deployment, please replace it with your own domain, path and port. If you have already filled in the port in the script, the configuration saved in the script shall prevail. Do not blindly copy the document examples.

| Project | Documentation example | your actual value |
|---|---|---|
| Panel domain | panel.example.com | Please change it to your own |
| Node domain | node.example.com | Please change it to your own |
| website domain | site.example.com | Please change it to your own |
| 3x-ui panel port | 40000 | Based on the actual port on your panel |
| Subscription port | 2096 | Based on the actual port of your subscription service |
| Web reverse proxy engine local port | 8443 | Subject to the current configuration of the script |
| Xray/REALITY local port | 1443 | Subject to the current configuration of the script |
| Panel path | /panel/ | Subject to your panel settings |
| standard subscription path | /sub/ | Subject to your subscription settings |
| Clash/Mihomo path | /clash/ | Subject to your subscription settings |

## Quick conclusion

Ultimately you should access it like this:

| Type | Correct access method |
| --- | --- |
| 3x-ui panel | `https://panel.example.com/panel/` |
| Ordinary subscription | `https://panel.example.com/sub/CLIENT_SUBSCRIPTION` |
| Clash/Mihomo | `https://panel.example.com/clash/CLIENT_SUBSCRIPTION` |
| REALITY node | `node.example.com:443` or `SERVER_PUBLIC_IP:443` |
| Add new website | `https://site.example.com/` |

Do not access these internal ports from the public internet:

```text
https://panel.example.com:40000/
https://panel.example.com:2096/sub/xxxx
https://panel.example.com:8443/
https://panel.example.com:1443/
```

## Look at this table first

| components | listening position | Responsibilities |
| --- | --- | --- |
| Nginx stream | `0.0.0.0:443` | Default entry mode, route by SNI to route traffic |
| vpso-mux | `0.0.0.0:443` | TCP Peek + Splice mode entry, choose one from Nginx Stream |
| Xray/3x-ui main inbound | `0.0.0.0:443` | Xray Fallback mode entrance, choose one from the first two |
| Caddy or Nginx local web reverse proxy | `127.0.0.1:8443` | Hosted web certificates, reverse proxy panels, subscriptions and websites |
| 3x-ui panel | `127.0.0.1:40000` | The local HTTP backend does not use its own certificate as the public HTTPS |
| 3x-ui Subscribe | `127.0.0.1:2096` | The local HTTP backend is represented by the web reverse proxy engine on the public HTTPS |
| REALITY / Xray local inbound | `127.0.0.1:1443` | Forwarded by the entrance as SNI in Nginx Stream or TCP Peek mode |

Core principles:

1. public port `443` only provides one entry process at the same time: `nginx`, `vpso-mux` or Xray as the main inbound process.
2. The Caddy or Nginx local web backend is responsible for the browser HTTPS, 3x-ui panels and subscriptions only as the local HTTP backend.
3. REALITY's `dest` / `Target` and `serverNames` / `SNI` write the external real HTTPS site, do not write your own panel domain.

## 3x-ui Three entry mode configuration quick check

The three entry modes share the panel domain, subscription path, website reverse proxy, Web reverse proxy engine, local TLS port and certificate configuration. Nginx Stream and TCP Peek also share the web whitelist; `xray-fallback` does not support the web whitelist because after Xray fallback to the local web reverse proxy engine, Caddy/Nginx cannot reliably obtain the real client source IP. The other differences are only who listens on the public port `443`, and whether the main inbound 3x-ui/Xray needs to directly occupy the public port `443`.

### Web reverse proxy engine selection

When configuring `[2 initial setup/installation Port 443 Reuse]` for the first time, you can select Caddy or Nginx as the local Web reverse proxy engine under Port 443 Reuse. You can also follow from:

```text
Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [8 switch Web reverse proxy engine]
```

The script will reuse the current domain, certificate, and backend when switching; the web whitelist will also be reused in the entry mode that supports whitelisting. The script will re-render the selected engine configuration and isolate another set of 443 local Web reverse proxy configurations to prevent Caddy/Nginx from processing the same batch of 443 Web domains at the same time. The certificate paths remain `/etc/caddy/certs/${domain}.crt|key` and `/root/cert/${domain}.crt|key`, and the certificate policy does not change.

If `Main menu [4 reverse proxy]` has previously been configured with independent Caddy/Nginx HTTPS reverse proxy, when enabling or re-applying Port 443 Reuse, the script will isolate these old configurations that may seize the public port `443`. Please use `[19] -> [8 management Web domains / reverse proxy]` to add new websites later.

### Same 3x-ui settings for all three modes

These settings are the same in the three modes: Nginx Stream, TCP Peek + Splice, and Xray Fallback:

| 3x-ui location | What should be filled in |
| --- | --- |
| `webListen` | `127.0.0.1` |
| `webPort` | `40000`, or your actual panel port |
| `webBasePath` | `/panel/`, or your actual panel path |
| `webDomain` | Leave blank; the web reverse proxy owns the public domain |
| `webCertFile` / `webKeyFile` | Clear |
| `subListen` | `127.0.0.1` |
| `subPort` | `2096`, or your actual subscription port |
| `subPath` | `/sub/`, or your actual normal subscription path prefix |
| `subClashPath` | `/clash/`, or your actual Clash/Mihomo path prefix |
| `subDomain` | Public subscription domain, e.g. `panel.example.com`; do not include a scheme, port, or path |
| `subCertFile` / `subKeyFile` | Clear |

`panel.example.com`, `/sub/`, and `/clash/` are examples. Replace them with your actual public domain and paths.

### 3x-ui 3.4.0+ Hosts / Old Version External Proxy

For 3x-ui v3.4.0 and later, configure the public node address in `Hosts / Host`. Older 3x-ui versions use the inbound `External Proxy`.

3x-ui v3.4.0 and later: Open `Hosts / Host` and add a Host:

```text
inbound：Select the corresponding REALITY or local Xray inbound
address：node.example.com Or server public IP
port：443
Security：Same, Or fill in the actual security type of the inbound
SNI / Fingerprint / ALPN：Keep the actual value of the inbound and client consistent
```

3x-ui v3.3.1 and before: Open `External Proxy` in the corresponding inbound REALITY:

```text
Type：Same
address：node.example.com Or server public IP
port：443
```

If the `External Proxy` panel has been set before the upgrade, you should still check whether the address and port in `Hosts / Host` are the public port `443` after the upgrade.

### Mode 1: Nginx Stream

This is the default stable mode. The inbound nodes of 3x-ui/Xray do not listen to the public port `443`, only the local port.

| 3x-ui / Xray Inbound Settings | Example value |
| --- | --- |
| REALITY or other local Xray inbound listening address | `127.0.0.1` |
| REALITY or other local Xray inbound listening port | `1443`, or your actual local inbound port |
| Client connection address | `node.example.com` or server public IP |
| Client connection port | `443` |
| REALITY `dest` / `Target` | External real HTTPS site, e.g. `www.microsoft.com:443` |
| REALITY `serverNames` / `SNI` | The same external real HTTPS site, e.g. `www.microsoft.com` |
| Hosts / External Proxy | 3x-ui v3.4.0+ adds a new Host in `Hosts / Host`; the old version is set in inbound `External Proxy`. Fill in the address `node.example.com` or the server public IP, and fill in the port `443` |

If you want multiple local Xray inbounds to share the public port `443`, first create multiple local inbounds in 3x-ui, each inbound uses a different `127.0.0.1:port`, and then:

```text
Main menu [19 Port 443 Reuse manager] -> [15 Xray inbound management]
```

Only record `SNI -> local address:port` for currently supported Port 443 Reuse mode rendering routing rules. The script does not create, delete, or modify the 3x-ui/Xray inbound connection internal configuration.

### Mode 2: TCP Peek + Splice

In TCP Peek + Splice mode, the configuration process is the same as Nginx Stream: panel, subscription and Xray inbound connections are still bound to the local address, and the client is still connected to the Internet `443`. When switching TCP Peek, reuse the same set of domains, certificates, Web reverse proxy backends, Web whitelists, and Xray SNI routing records.

| Project | Description |
| --- | --- |
| 3x-ui Panel and Subscription | Keep `127.0.0.1` local HTTP backend, certificate path cleared |
| REALITY or other Xray inbound | Keep local bindings like `127.0.0.1:1443` |
| Client connection port | Still `443` |
| Hosts / External Proxy | Still output `node.example.com:443` or `Server public IP:443` |
| Xray Inbound Management | Like Nginx Stream supports multiple local Xray inbound connections routed as SNI |

When switching from Nginx Stream to TCP Peek + Splice, there is usually no need to change any configuration in the 3x-ui panel. What has changed is the listening process of public port `443`: from `nginx` to `vpso-mux`.

Advantages of TCP Peek:

1. The configuration process is the same as Nginx Stream, and there is no need to refill 3x-ui, Web reverse proxy engine, certificate or Xray SNI route.
2. `MSG_PEEK` only checks the ClientHello and does not consume the first packet. The backend still receives the original TLS handshake.
3. For forwarding, splice is used first to reduce user-mode data copy; when it is unavailable, it automatically falls back to ordinary copy.
4. `vpso-mux` has independent status, logs, configuration check and 8444 pre-check to facilitate confirmation of links before and after switching.

Check before switching:

1. The TCP Peek switching process will no longer automatically download the Go tool chain or remotely compile `vpso-mux` during the public port `443` switching process.
2. Before using TCP Peek for the first time, run `Main menu [19] -> [16] View TCP Peek + Splice Status / 8444 Check before switching` first. This step only binds `8444` and will not replace Internet `443`.
3. After `[16]` passes, run `[17] TCP Peek routing rule validation` and finally `[5] switch to TCP Peek + Splice mode`. Before switching, the script will automatically run another independent `8444` pre-check. If it fails, the public port `443` will not be used.
4. If the current SSH session itself is connected to an Internet ingress port, such as `443`, the script will refuse the switch. Please use the cloud provider VNC/Serial Console instead, or log in first using the non-entry port SSH.
5. Before TCP Peek is switched, the local port of the Web reverse proxy engine and the local inbound connection of Xray/REALITY must be connected; if the local inbound connection of `127.0.0.1:1443` is not bound, first enable the corresponding inbound connection on 3x-ui or change the port saved in the script to the actual value.

For first-time configuration, you only need to run the same set of `[2 initial setup/installation Port 443 Reuse]` wizards. After the shared configuration, certificate, Web reverse proxy engine and 3x-ui local port are all connected, follow the `[16] -> [17] -> [5]` process above to switch the Internet entry process to TCP Peek.

### Mode 3: Xray Fallback

Xray Fallback is a special mode. Internet `443` is bound by the 3x-ui/Xray main inbound connection you have configured, and HTTPS is then connected fallback to the current Web reverse proxy engine local port by this main inbound connection. The script will not edit the 3x-ui/Xray inbound connection internal configuration for you.

Before switching to xray-fallback, you need to prepare a "main inbound" in 3x-ui:

| 3x-ui / Xray Main Inbound Settings | Example value |
| --- | --- |
| Primary inbound listening address | `0.0.0.0`, or the Internet binding method allowed by the panel |
| Primary inbound listening port | `443` |
| fallback / fallback dest / fallback target | `127.0.0.1:8443`, the port is based on the local port of the Web reverse proxy engine in the script. |
| Client connection address | `node.example.com` or server public IP |
| Client connection port | `443` |
| Hosts / External Proxy | If the subscription link does not output `:443`, 3x-ui v3.4.0+ is set in `Hosts / Host`; legacy versions are set in inbound `External Proxy`. Fill in the node domain or server public IP for the address, and fill in `443` for the port. |

The web panel and subscriptions still use the current web reverse proxy engine, so the panel certificate path and subscription certificate path must still be cleared. `panel.example.com` access link should be:

```text
Browser -> public port `443` -> Xray main inbound fallback -> Web reverse proxy engine 127.0.0.1:8443 -> 3x-ui Panel/Subscription
```

xray-fallback mode does not support scripts that continue to route multiple SNI to multiple local Xray inbound connections. The `Xray Inbound connection management` menu can only view existing rules and current primary inbound connection candidates, and cannot add, delete or synchronize rules. When multiple local Xray inbound connections are required, use Nginx Stream or TCP Peek + Splice.

If your primary inbound connection is REALITY, please confirm that the 3x-ui/Xray inbound connection type you are using can indeed fallback HTTPS to the current web reverse proxy engine. This script only checks whether the Internet `443` is bound by Xray and whether the Web reverse proxy engine fallback backend is reachable. It will not generate Xray fallback rules for you.

### When switching modes, should 3x-ui be changed?

| Switch direction | 3x-ui What needs to be done? |
| --- | --- |
| Nginx Stream -> TCP Peek + Splice | Usually there is no need to change 3x-ui. Keep Panel/Subscription/Xray to listen to the local address for inbound calls, and the client port is still `443`. |
| TCP Peek + Splice -> Nginx Stream | Usually there is no need to change 3x-ui. After switching back, Internet `443` is bound by Nginx stream. |
| Nginx Stream or TCP Peek + Splice -> Xray Fallback | First change a primary inbound in 3x-ui to the public port `443`, configure fallback to the local port of the web reverse proxy engine, and then execute the script switch. |
| Xray Fallback -> Nginx Stream or TCP Peek + Splice | First move the 3x-ui/Xray main inbound from the public port `443`, change it back to a local port like `127.0.0.1:1443`, or disable the public port `443` main inbound first, and then execute the script switch. |
| Reapply the current pattern | If you just rebuild the configuration, you do not need to change 3x-ui; if you have changed the panel port, subscription path or Xray local port, save the value in the `[10 Modify Port 443 Reuse settings]` synchronization script first. |

Before switching back to Nginx Stream or TCP Peek + Splice from xray-fallback, the most common mistake is to forget to move the 3x-ui/Xray main inbound from the public port `443`. Otherwise, Nginx or `vpso-mux` will grab the same public internet port as Xray, and the switch will fail or automatically roll back.

### Before and after switching checklist

Check before switching:

```text
Main menu [19 Port 443 Reuse manager] -> [1 View current portal status/listener details]
ss -lntp | grep ':443'
```

TCP Peek + Splice switching check:

```text
Main menu [19 Port 443 Reuse manager] -> [16 View TCP Peek + Splice Status / 8444 Preflight]
Main menu [19 Port 443 Reuse manager] -> [17 TCP Peek routing rule validation]
Main menu [19 Port 443 Reuse manager] -> [5 switch to TCP Peek + Splice mode]
```

Only after the `8444` pre-check and routing rule verification passes, `[5] switch to TCP Peek + Splice mode` can be executed. To undo the latest entry mode switch, use `Main menu [19 Port 443 Reuse manager] -> [7 Roll back the last entry-mode switch]`.

Check after switching:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
Main menu [19 Port 443 Reuse manager] -> [14 443 Network access test]
```

Expected listeners:

| ENTRY_MODE | Who should bind public port 443? |
| --- | --- |
| `nginx-stream` | `nginx` |
| `tcp-peek` | `vpso-mux` |
| `xray-fallback` | `xray` / `3x-ui` / `x-ui` Hosted Xray |

The new configuration value of `ENTRY_MODE` is only written to `nginx-stream`, `xray-fallback`, and `tcp-peek`. If there is no `ENTRY_MODE` in the old configuration, the script reads as `nginx-stream`; if there are `nginx_stream`, `xray_fallback`, and `tcp_peek` in the old configuration or `/etc/vps-optimize/443-engine.conf`, the script reads as the corresponding new values ​​compatible. A single simple assignment will be automatically rewritten to a new name; when it cannot be safely rewritten, the status page will continue to prompt for migration.

Regardless of the mode, do not allow the web reverse proxy engine, 3x-ui panel port, subscription port, or additional local inbound to directly expose the public internet.

## Xray Inbound Management Boundary

`Xray inbound management` only records `SNI -> local address:port` routing records for currently supported Port 443 Reuse mode rendering routing rules, it is not the 3x-ui/Xray inbound editor. Users need to first create and enable local inbound in 3x-ui/Xray, and then write the corresponding SNI, local listening address and port into the script.

TCP Peek + Splice mode: Read SNI in TLS ClientHello based on MSG_PEEK, without consuming the first packet, and routing the connection to the Web reverse proxy engine or Xray local backend based on SNI; splice zero copy is preferred when forwarding, and ordinary copy is automatically rolled back when it fails. The actual running routing program is vpso-mux.

Nginx Stream mode and TCP Peek + Splice mode support forwarding multiple SNI to multiple local Xray inbound connections based on the same Xray inbound connection routing rule. Web domains are still forwarded to the current web reverse proxy engine, and Xray inbound connections are not affected by the web whitelist.

Xray itself can have multiple inbounds. However, in xray-fallback mode, the public port `443` is taken over by one Xray main inbound by default. The script cannot route multiple SNI values to multiple local Xray inbounds in this mode. Use Nginx Stream or TCP Peek + Splice when you need multiple local Xray routes.

After switching to xray-fallback, the script will retain the existing rules in `/etc/vps-optimize/xray-sni-routes.conf` and will not delete them. The selected rule is used as the xray-fallback main inbound connection; other rules will be marked as "reserved, but not effective in the current xray-fallback mode". When later switching back to Nginx Stream mode or TCP Peek + Splice mode, these rules can be reused to route by SNI.

In xray-fallback mode, the `Xray inbound management` menu allows viewing of rules and the current primary inbound, but does not allow adding, deleting or synchronizing rules. This script does not automatically modify the 3x-ui/Xray inbound internal configuration.

## The difference between ordinary TLS and REALITY

Ordinary TLS nodes pay more attention to whether the local certificate, Web fallback, and Host/SNI match. For example, for nodes such as VLESS + TLS, Trojan + TLS, VMess + WS + TLS, VLESS + gRPC + TLS, when troubleshooting, you should confirm whether the node domain is controlled by the user, whether the local certificate covers the SNI, whether the web reverse proxy engine has a matching fallback, and whether the browser access returns 200/301/302.

REALITY nodes are different. REALITY pays more attention to whether the external target site is truly accessible, whether the characteristics of TLS are stable, and whether `serverName` and `dest` are logically consistent. Do not require REALITY `serverName` to join the Web reverse proxy engine, nor do you require native certificates to cover REALITY `serverName`.

## Certificate policy

Port 443 Reuse continues to use `acme.sh + Cloudflare DNS API` to issue and install web domain certificates. Do not use the Caddy DNS module, do not require `xcaddy`, and do not let Caddy be responsible for the DNS-01 certificate application.

DNS-01 Verifies domain control through the `_acme-challenge` TXT record. Cloudflare Chengyun itself is not the direct cause of the `dns_cf` issuance failure; if the issuance fails, you should first check the Token permissions, authorization zone, TXT propagation, server time and acme.sh logs. Orange Cloud will still change the source IP of web requests, and is not suitable for REALITY/node domains that need to be directly connected to VPS, so "certificate issuance" and "public internet access link" must be checked separately.

The certificate selection that appears during the 3x-ui installation phase is only to complete the 3x-ui installation process; it is not the certificate scheme ultimately used by Port 443 Reuse. The final architecture is: the public HTTPS is uniformly processed by the current Web reverse proxy engine, and the 3x-ui panel and subscription only serve as the local HTTP backend.

## domain IP whitelist

If you only want a fixed IP to access the 3x-ui panel domain, you can enable the IP whitelist for the specified Web domain. This restriction takes effect "by domain": adding a whitelist to `panel.example.com` will only restrict this web domain; site domains that are not whitelisted, Xray inbound, REALITY SNI and unknown SNI will continue to work according to the original 443 routing rules.

The implementation of the two deployment methods is different:

| Deployment method | Use the entrance | Effective position | Scope of influence |
| --- | --- | --- | --- |
| Port 443 Reuse is not enabled, only Caddy/Nginx is used for reverse proxy | Use `Main menu [4 reverse proxy] -> [1 add Caddy reverse proxy]` or `[2 add Nginx HTTPS reverse proxy]` when adding a new domain; use `[4] -> [5 domain IP whitelist]` for existing domains; use `[4] -> [6 View or edit applied configuration files]` for direct editing and configuration | Caddy The current domain site block uses `remote_ip` for matching; Nginx HTTPS uses `allow/deny` for reverse proxy | Only affects the current Caddy/Nginx web domain |
| Enabled 443 Nginx Stream Port 443 Reuse | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [5 Manage domains IP whitelist]` | Nginx stream entrance layer, judge by `SNI + source IP` | Only affects the selected SNI domain |
| Enabled 443 TCP Peek + Splice Port 443 Reuse | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [5 Manage domains IP whitelist]` | vpso-mux entrance layer, judge by `SNI + source IP` | Only affects the selected SNI domain |
| `xray-fallback`, whether using Caddy or Nginx local web reverse proxy | Do not allow new, retained or applied web whitelists | Use is prohibited; the local web reverse proxy engine cannot reliably obtain the real client source IP after Xray fallback | For whitelist, please switch to Nginx Stream or TCP Peek |

Whitelisting supports individual IPs and CIDRs, such as:

```text
1.2.3.4
1.2.3.0/24
2001:db8::/32
```

Please put the current management IP into the whitelist before enabling it, otherwise you may block yourself from the panel. The script will prompt the current SSH source IP, and will automatically try to add the VPS local public IPv4/IPv6, loopback address and current Docker network subnet to the whitelist; if the automatic detection fails, please manually add the VPS public IP or the Docker subnet where the subscription tool is located.

Note: This plan recommends that the relevant domains be kept as Cloudflare Gray Cloud / DNS only. If Orange Cloud proxy is enabled for the domain, the source IP seen by the server may be the Cloudflare edge IP instead of your real access IP. The whitelist should be changed to the Cloudflare edge segment or the proxy should be turned off first.

## Preparation

Prepare at least one panel domain:

```text
panel.example.com -> current VPS IP
```

It is recommended to prepare another node domain:

```text
node.example.com -> current VPS IP
```

Cloudflare Suggestions:

| domain | Suggestions |
| --- | --- |
| Panel domain | Gray cloud / DNS only |
| Node domain | Huiyun / DNS only, must be able to directly connect to VPS |
| Website or reverse domain | Gray cloud / DNS only |
| REALITY disguise SNI | Write external real HTTPS site, do not point to your VPS |

It is not recommended to enable the Cloudflare proxy for domains related to this plan. Gray Cloud direct connection is more suitable for Nginx stream to be diverted by SNI, and can also reduce exceptions in REALITY, subscription links and Hosts / External Proxy.

For a REALITY disguise SNI, choose a stable external HTTPS site without CDN protection that is easy to reach from your users' networks. Do not use your own panel, node, or subscription domain, or a site that frequently redirects, rejects unusual requests, or requires a CAPTCHA. In current 3x-ui, an empty `Min Client Ver` uses Xray core's built-in minimum version rather than allowing every version; update a failing third-party client first, and consider `1.0.0` only after accepting the risk of outdated fingerprints.

If you use Cloudflare DNS to sign the certificate, the API Token needs at least:

```text
Zone.Zone.Read
Zone.DNS.Edit
```

## Recommended deployment process

Follow this order to avoid getting dizzy:

```text
1. Prepare domain and Cloudflare Token
2. Installation 3x-ui
3. Use 3x-ui as a local HTTP backend
4. Configure the REALITY inbound
5. Open `Main menu [19 Port 443 Reuse manager] -> [2 initial setup/installation Port 443 Reuse]`
6. Return to 3x-ui and confirm local listeners, subscription fields, and Hosts / External Proxy
7. Open `Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]`
```

### 1. Install 3x-ui

When the current 3x-ui installer asks for SSL setup, choose option 4, `Skip SSL (advanced — behind reverse proxy / SSH tunnel only)`, then enter `y` when asked to bind only to `127.0.0.1`. Use this only behind a reverse proxy or SSH tunnel; never expose an unencrypted public HTTP panel. For 2.x or existing installations with SSL configured, clear the panel and subscription certificate paths before using 443.

| Installer options | Role in this tutorial | Follow-up processing |
|---|---|---|
| Skip SSL | Recommended local HTTP backend | Bind only to `127.0.0.1` |
| Apply for a certificate for a domain | Can be used to temporarily complete the 3x-ui installation | Clear the 3x-ui certificate path before accessing 443 |
| Request a certificate for an IP | It is only used as a temporary transition and is not recommended as a formal public HTTPS | Clear the 3x-ui certificate path before accessing 443 |
| Select an existing certificate path | Can be used to temporarily complete the installation | Clear the 3x-ui certificate path before accessing 443 |

Example:

```text
Certificate domain：panel.example.com
Whether to set it to the panel：You can choose to be
```

The above values are just examples, please replace them with your actual domains. When the Port 443 Reuse is officially connected later, the certificate path of 3x-ui needs to be cleared and the web reverse proxy engine can take over the public HTTPS.

It is recommended to customize these values and write them down:

```text
Panel port：40000
panel url root path：/panel/
Username/Password：Set it yourself
listening IP：127.0.0.1
SSL：Skip SSL / Do not apply SSL
```

Native backend check address:

```text
http://127.0.0.1:40000/panel/
```

If your port or path is different, replace it with your own value. The panel path is recommended with front and rear `/`.

### 2. Clear the 3x-ui panel certificate

As long as you are ready to access the Port 443 Reuse of VPS-Optimize, you should clear the 3x-ui panel and subscription certificate path and let the Web reverse proxy engine take over the public HTTPS.

Enter:

```text
The `webCertFile` and `webKeyFile` fields in Panel Settings
```

Clear all the following paths:

```text
Certificate path
Private key path
Public key file path
Private key file path
```

Save and restart the panel.

If not cleared, it may result in 502 Bad Gateway, HTTP/HTTPS backend protocol mismatch, redirect loop, certificate path confusion, panel or subscription exception.

After clearing, the 3x-ui panel only serves as the native HTTP backend:

```text
http://127.0.0.1:40000/panel/
```

The public internet only accesses Port 443 Reuse address: `https://panel.example.com/panel/`.

### 3. Clear 3x-ui subscription certificate

Enter:

```text
The `subCertFile` and `subKeyFile` fields in Subscription Settings
```

Also clear the certificate path and private key path. After accessing the Port 443 Reuse, the subscription to the public HTTPS is also uniformly processed by the current Web reverse proxy engine, and the 3x-ui subscription service only serves as the local HTTP backend.

Then set up the subscription service:

```text
subListen：127.0.0.1
subDomain：panel.example.com
subPort：2096
subPath：/sub/
subClashPath：/clash/
```

`subDomain` contains only the domain, not a scheme, port, or path. 3x-ui does not add `/` to subscription paths automatically. Use:

```text
/sub/
/clash/
/mihomo/
```

Don't write:

```text
sub
/sub
sub/
/sub/CLIENT_SUBSCRIPTION
```

443 The wizard fills in the path prefix, such as `/sub/`, `/clash/`. Do not fill in the domain, and do not fill in the `Subscription` of the client below the site.

### 4. Configure REALITY inbound

Add VLESS REALITY inbound at 3x-ui:

```text
agreement：VLESS
listen address：127.0.0.1
listen port：1443
transmission：TCP / RAW
Security：Reality
uTLS：chrome
Target / dest：external reality HTTPS site:443, For example www.microsoft.com:443
serverNames / SNI：same external reality HTTPS site, For example www.microsoft.com
SpiderX：/
Fallbacks：Leave blank
```

Do not write `dest` or `serverNames` of REALITY as:

```text
panel.example.com:443
node.example.com:443
127.0.0.1:8443
```

To modify REALITY SNI later, you can do:

```text
Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [2 Modify REALITY local listener / camouflage SNI]
```

### 5. Run 443 First Configuration

After confirming that the panel certificate and subscription certificate are cleared, run:

```text
Main menu [19 Port 443 Reuse manager] -> [2 initial setup/installation Port 443 Reuse]
```

Example to fill in:

| Project | Example value |
| --- | --- |
| Panel domain | `panel.example.com` |
| Website/reverse domain | Can be left blank for the first time |
| REALITY disguise SNI | `www.microsoft.com` or other external real HTTPS site |
| Nginx public internet listening address | `0.0.0.0` |
| Nginx public internet listening port | `443` |
| Web reverse proxy engine | `Caddy` or `Nginx` |
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
| Cloudflare API Token | Your CF Token |

The panel path, normal subscription path, and Clash/Mihomo path must be exactly the same as 3x-ui.

Every time the script is configured for the first time, re-applied, switches web reverse proxy engines, or adds or deletes websites, it will first create a SNI stack backup. If `nginx -t`, `caddy validate` or the service fails to restart, it will try to roll back and move the abnormal configuration into the isolation directory.

Common backup and quarantine directories:

```text
/etc/vps-optimize/backups/sni-stack_*
/etc/vps-optimize/quarantine/nginx-sni
/etc/vps-optimize/quarantine/nginx-sni-web
/etc/vps-optimize/quarantine/nginx-proxy-to-443-entry
/etc/vps-optimize/quarantine/caddy-sni
/etc/vps-optimize/quarantine/caddy-sni-web
/etc/vps-optimize/quarantine/caddy-certs
```

### 6. Return to 3x-ui to finish

Confirm that 3x-ui is still the native HTTP backend:

```text
panel listener IP：127.0.0.1
subscription listener IP：127.0.0.1
```

Confirm the current subscription fields:

```text
subDomain：panel.example.com
subPath：/sub/
subClashPath：/clash/
```

Do not put a scheme, port, or path in `subDomain`; when using custom paths, update the corresponding path prefixes saved by this script.

Then set the node public internet address according to the 3x-ui version.

3x-ui v3.4.0 and later: Open `Hosts / Host` and add a Host:

```text
inbound：Select the corresponding REALITY or local Xray inbound
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

After saving, copy the node link again. The port should be `:443`. If it is still `:1443`, please check `Hosts / Host` for 3x-ui v3.4.0+, and please check `External Proxy` for older versions.

Finally run:

```text
Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]
```

## Follow-up maintenance

Don't rerun the first configuration just for small changes. Commonly used entrances are as follows:

| what do you want to do | entrance |
| --- | --- |
| Add a new website or reverse domain | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]` |
| Switch Caddy/Nginx Web reverse proxy engine | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [8 switch Web reverse proxy engine]` |
| Check 443 link | `Main menu [19 Port 443 Reuse manager] -> [13 443 Connection health check]` |
| Modify panel/subscription port and path | `Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [1 Edit panel/subscription ports and paths]` |
| Modify REALITY local binding/disguise SNI | `Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [2 Modify REALITY local listener / camouflage SNI]` |
| Modify Nginx/Web reverse proxy binding | `Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [3 Modify Nginx public internet entry / Web anti-local TLS]` |
| Modify panel domain | `Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy] -> [9 Edit panel domain]` |
| Reapply current configuration | `Main menu [19 Port 443 Reuse manager] -> [10 Modify Port 443 Reuse settings] -> [5 Reapply saved configuration]` |
| Certificate maintenance | `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance]` |
| Rollback Port 443 Reuse configuration | Rollback entry in `Main menu [19 Port 443 Reuse manager] -> [12 CF DNS / Caddy Certificate maintenance]` |

When adding a new website/reverse proxy, fill in the backend accessible to the current VPS. The Docker service can first publish the container port to `127.0.0.1`:

```text
website domain：dockge.example.com
Backend address：127.0.0.1
backend port：5001
```

`127.0.0.1:5001` is an example value, please replace Docker with the address and port actually published to the host. Intranet services can also use the actual intranet IP or hostname, but you must first confirm that the current VPS can be directly accessed.

Then the browser accesses:

```text
https://dockge.example.com/
```

Services suitable for integration include SublinkPro, Sub-Store, Dockge, Komari, blogs, and other native HTTP services.

## Debug entry

If you encounter panel failure to open, subscription 404, certificate failure, a port conflict, or REALITY connection failure, see [Port 443 Reuse Troubleshooting](443-single-entry-troubleshooting.md).

## A complete set of examples for reference only

```text
panel：https://panel.example.com/panel/
Ordinary subscription：https://panel.example.com/sub/CLIENT_SUBSCRIPTION
Clash/Mihomo：https://panel.example.com/clash/CLIENT_SUBSCRIPTION
REALITY node：node.example.com:443

3x-ui panel listener：127.0.0.1:40000
3x-ui subscription listener：127.0.0.1:2096
REALITY Inbound listening：127.0.0.1:1443
Web reverse proxy engine listening：127.0.0.1:8443 (Example, The actual configuration is subject to the current configuration of the script.)
public port `443` entry listener：current ENTRY_MODE Corresponding service (nginx-stream=nginx；xray-fallback=Xray main inbound；tcp-peek=vpso-mux)
```

## Never do this

```text
public internet access https://panel.example.com:40000/
public internet access https://panel.example.com:2096/sub/xxxx
put REALITY dest written as panel.example.com:443
put REALITY serverNames Write as panel domain
3x-ui Run without clearing the certificate path 443 routing
Subscribe URI The path is written as sub or /sub
Put the CLIENT_SUBSCRIPTION Fill in 443 The path prefix of the wizard
let Web reverse proxy engine、Xray、3x-ui The panel simultaneously grabs the public port `443`
```
