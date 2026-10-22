# REALITY and xhttp Together: Dedicated Domain vs Shared 443

This guide covers adding xhttp nodes to a server that already runs Port 443 Reuse, and keeping them alongside REALITY nodes long term.

Pick one of the two wirings. Do not mix them:

| Option | Public entry | Terminates TLS | Best for |
| --- | --- | --- | --- |
| A. Dedicated node domain | Entry forwards by SNI to the local xhttp inbound | The xhttp inbound | One standalone node, least configuration |
| B. Shared Web domain | Entry forwards by SNI to Caddy/Nginx, which reverse-proxies by path to xhttp | Local Caddy/Nginx | Node and panel/site on the same domain and the same `443` |

## Prerequisites

- Port 443 Reuse already works as described in [Setup and Configuration](../docs/443-single-entry.md), and `ss -lntp | grep ':443'` shows a single entry listener.
- The entry mode is `nginx-stream` or `tcp-peek`. In `xray-fallback` the Xray main inbound owns the entry, so the menus used here are unavailable.
- The 3x-ui panel and subscription still run on local HTTP ports.
- Keep the current SSH session open and take a configuration backup first.

## Option A: Dedicated node domain

Use this when a domain such as `xhttp.example.com` serves nodes only.

### 1. Prepare the certificate

The xhttp inbound terminates TLS itself, so the certificate must cover the node domain. Keep the files where Port 443 Reuse expects them:

```text
/etc/caddy/certs/xhttp.example.com.crt
/etc/caddy/certs/xhttp.example.com.key
```

Reissue through the existing script, or issue a certificate for the same domain and paths yourself. Never put the key under a Web root.

### 2. Create the xhttp inbound in 3x-ui

| Field | Value |
| --- | --- |
| Listen address | `127.0.0.1` |
| Listen port | An unused local port, for example `2410` |
| Protocol | VLESS (or whatever you actually use) |
| Transport / network | `xhttp` (older builds may show `splithttp`) |
| xhttp path | Note it down, for example `/xhttp` |
| Host | Optional; if set, it must be `xhttp.example.com` |
| Security | `tls` |
| Certificate paths | The two files from the previous step |
| ALPN | `h2,http/1.1`, or whatever the client uses |

The inbound must listen on `127.0.0.1`. Binding `0.0.0.0` exposes the local port directly and bypasses the `443` entry.

### 3. Register the SNI route in the script

```text
Main menu [19 Port 443 Reuse manager] -> [4 Manage Xray SNI forwarding rules] -> [2 Add an SNI route]
```

- Inbound SNI: `xhttp.example.com`
- Local listen address: `127.0.0.1`
- Local port: `2410`

When asked whether to sync to the active entry, answer yes.

### 4. Client

```text
Address: xhttp.example.com
Port: 443
Transport: xhttp
path: /xhttp
TLS: enabled
SNI / serverName: xhttp.example.com
```

The client `path` must match the inbound exactly. The entry only forwards TCP and never reads the path, so there is no path conflict to manage here.

## Option B: Share port 443 with a Web domain

Use this when the node and the panel or site should answer on one domain:

```text
https://panel.example.com/panel/   -> 3x-ui panel
https://panel.example.com/xhttp    -> xhttp node
```

### 1. Create an xhttp inbound without TLS in 3x-ui

| Field | Value |
| --- | --- |
| Listen address | `127.0.0.1` |
| Listen port | For example `2400` |
| Transport / network | `xhttp` |
| xhttp path | For example `/xhttp` |
| Host | Optional; if set, it must be the panel or site domain |
| Security | `none` |

The critical point: **do not enable TLS on this inbound**. Caddy/Nginx terminates TLS at local `8443` and the inbound only receives plain HTTP. TLS on both sides always fails the handshake.

### 2. Register the path reverse proxy in the script

```text
Main menu [19 Port 443 Reuse manager] -> [2 Manage Web domains and reverse proxies] -> [10 xhttp node path reverse proxy] -> [2 Add an xhttp path rule]
```

Fill in:

| Prompt | Example |
| --- | --- |
| Web domain carrying xhttp | `panel.example.com` |
| xhttp path | `/xhttp` |
| Local listen address | `127.0.0.1` |
| Local port | `2400` |

The script enforces these checks:

- The domain must already exist as the panel domain or a Web domain, so the certificate and Web entry are ready.
- The path must not overlap the panel `webBasePath`, the subscription paths, or the Clash path. Prefix overlaps such as `/panelx` are rejected too, because Nginx matches by prefix.
- The local port must be listening and must differ from the entry, Web proxy, panel, and subscription ports.

Confirm the reapply step; the script regenerates the Caddy or Nginx configuration and restarts the Web service.

### 3. Client

```text
Address: panel.example.com
Port: 443
Transport: xhttp
path: /xhttp
TLS: enabled
SNI / serverName: panel.example.com
```

The client connects to the Web domain and uses the existing panel or site certificate. No extra certificate is needed.

## Choosing between them

| Question | Option A | Option B |
| --- | --- | --- |
| Do you have a dedicated node domain? | Yes | Not needed |
| Same domain for node and panel? | Not possible | Yes |
| Fewer certificates to maintain? | No | Yes |
| Planning to use a CDN? | Depends on CDN protocol support | Better fit, verify with grey cloud first |
| Change configuration only once? | Yes | No |

REALITY nodes are unaffected by either option. They keep using their own SNI routes and never touch the xhttp path rules.

## Known limits

- **No HTTP/3**: the xhttp QUIC mode needs UDP `443`, and the entry listens on TCP `443` only.
- **Unavailable in xray-fallback**: that mode has no separate Web front layer, so `[2] -> [10]` reports it as unavailable. Configure xhttp inside the main inbound `fallbacks` instead.
- **Web allowlists also limit xhttp**: Option B rules live under a Web domain, so an IP allowlist on that domain applies to xhttp as well. REALITY and Option A SNI routes are unaffected.
- **SNI filtering works on domains**: Option B adds no new SNI because the domain is already listed. Option A must register the node domain as an SNI route, or the strict gate drops it.
- **Long-lived xhttp connections**: the script disables response and request buffering for the path proxy and sets a one-hour read/write timeout. Do not add a short timeout in the Web proxy on top of that.

## Verification

Check the listeners first:

```bash
ss -lntp | grep -E ':(443|2400|2410)'
```

Expected: `443` belongs to the active entry service; `2400` and `2410` belong to Xray and bind `127.0.0.1`.

For Option B, check whether the path reaches the xhttp backend:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://panel.example.com/xhttp
```

A 404 or 400 is normal here: the request reached the xhttp backend rather than the panel. If you get the panel login HTML or a 502, the path rule is not active or the backend port is wrong:

```bash
curl -sS -D - -o /dev/null https://panel.example.com/xhttp | head -20
curl -sS http://127.0.0.1:2400/xhttp -o /dev/null -w '%{http_code}\n'
```

Compare the status code and headers. If the two differ, the problem is in the Web proxy layer. If they match but the client still fails, the problem is in the inbound or the client settings.

Finally, connect with a real client. TLS and port checks do not prove an xhttp session works.

## Troubleshooting

| Symptom | Check first |
| --- | --- |
| Handshake succeeds, then no data | Inbound path versus client path; a missing or extra trailing slash |
| Option B returns the panel login page | Path rule inactive: confirm the reapply, and confirm the path does not overlap `webBasePath` |
| Option B returns 502 | Local xhttp inbound not listening or wrong port; verify with a direct `curl` |
| Option A handshake fails | Certificate does not cover the node domain, or TLS is off on the inbound |
| Option B handshake fails | TLS was enabled on the inbound while the local backend is plain HTTP |
| Entry drops the node | Option A did not register the SNI route, or did not sync it to the active entry |
| Web works, node does not | The domain has a Web IP allowlist; add the client egress IP or switch to Option A |

Logs:

```bash
journalctl -u caddy -n 80 --no-pager     # Option B, Caddy engine
journalctl -u nginx -n 80 --no-pager     # Option B, Nginx engine
journalctl -u x-ui -u 3x-ui -n 80 --no-pager
```

## Do not

- Do not enable TLS on an inbound that is also served through the plain-HTTP Option B proxy.
- Do not bind the xhttp local port to `0.0.0.0`.
- Do not place the xhttp path on `/panel/`, `/sub/`, `/clash/`, or their subpaths.
- Do not try to manage paths through `[2] -> [10]` in `xray-fallback` mode.
- Do not deploy with the example domains and ports.
