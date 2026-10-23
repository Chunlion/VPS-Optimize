# REALITY and XHTTP Together: Dedicated Domain vs Shared 443

This guide covers adding XHTTP nodes to a server that already runs Port 443 Reuse, and keeping them alongside REALITY nodes long term.

Pick one of the two wirings. Do not mix them:

| Option | Public entry | Terminates TLS | Best for |
| --- | --- | --- | --- |
| A. Dedicated node domain | Entry forwards by SNI to the local XHTTP inbound | The XHTTP inbound | One standalone node, least configuration |
| B. Shared Web domain | Entry forwards by SNI to Caddy/Nginx, which reverse-proxies by path to XHTTP | Local Caddy/Nginx | Node and panel/site on the same domain and the same `443` |

## Prerequisites

- Port 443 Reuse already works as described in [Setup and Configuration](../docs/443-single-entry.md), and `ss -lntp | grep ':443'` shows a single entry listener.
- The entry mode is `nginx-stream` or `tcp-peek`. In `xray-fallback` the Xray main inbound owns the entry, so the menus used here are unavailable.
- The 3x-ui panel and subscription still run on local HTTP ports.
- Keep the current SSH session open and take a configuration backup first.

## Option A: Dedicated node domain

Use this when a domain such as `xhttp.example.com` serves nodes only.

### 1. Prepare the certificate

The XHTTP inbound terminates TLS itself, so the certificate must cover the node domain. Keep the files where Port 443 Reuse expects them:

```text
/etc/caddy/certs/xhttp.example.com.crt
/etc/caddy/certs/xhttp.example.com.key
```

Reissue through the existing script, or issue a certificate for the same domain and paths yourself. Never put the key under a Web root.

### 2. Create the XHTTP inbound in 3x-ui

| Field | Value |
| --- | --- |
| Listen address | `127.0.0.1` |
| Listen port | An unused local port, for example `2410` |
| Protocol | VLESS (or whatever you actually use) |
| Transport / network | `xhttp` (older builds may show `splithttp`) |
| XHTTP path | Note it down, for example `/xhttp` |
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
https://panel.example.com/xhttp    -> XHTTP node
```

### 1. Create an XHTTP inbound without TLS in 3x-ui

| Field | Value |
| --- | --- |
| Listen address | `127.0.0.1` |
| Listen port | For example `2400` |
| Protocol / UUID | `VLESS`, generate a new UUID |
| VLESS decryption / client encryption | `none` |
| flow | Leave empty |
| Transport / network | `xhttp` |
| XHTTP mode | `auto` |
| XHTTP path | For example `/xhttp` |
| Host | Optional; if set, it must be the panel or site domain |
| Security | `none` |

The critical point: **do not enable TLS on this inbound**. Caddy/Nginx terminates TLS at local `8443` (the default; use your actual setting), and the inbound receives plain HTTP.

### 2. Register the path reverse proxy in the script

```text
Main menu [19 Port 443 Reuse manager] -> [2 Manage Web domains and reverse proxies] -> [10 XHTTP node path reverse proxy] -> [2 Add an XHTTP path rule]
```

Fill in:

| Prompt | Example |
| --- | --- |
| Web domain carrying XHTTP | `panel.example.com` |
| XHTTP path | `/xhttp` |
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

Use the new inbound's UUID, `encryption=none`, empty flow, certificate verification enabled, and ALPN `h2,http/1.1`. Start with client mode `packet-up`: the current Web proxy uses HTTP/1.1 to the backend, while client `auto` selects `stream-up` over TLS H2. Do not copy the original REALITY public key or Short ID.

## Add a CDN after verifying direct access

This example uses Cloudflare with Option B. It needs neither a different entry engine nor automatic inbound creation.

1. Complete Option B and connect with a real client first. Use a separate Web domain such as `down.example.com` to keep the panel's existing allowlist and access method. Register it with its actual default backend under `[19] -> [2] -> [2 Add a Web domain or reverse proxy]`, then add `/xhttp -> 127.0.0.1:2400` under `[10] -> [2]`.
2. Point its A/AAAA records to the VPS, publishing only working addresses. Continue issuing an origin certificate for that domain through the existing `acme.sh + Cloudflare DNS API` workflow. After direct access works, enable the orange cloud and use SSL/TLS **Full (strict)**, with HTTPS port `443` to the origin.
3. Set **Bypass cache** in Cache Rules for `/xhttp` and its `/xhttp/` subpaths on that domain. Example expression:

   ```text
   http.host eq "down.example.com" and (http.request.uri.path eq "/xhttp" or starts_with(http.request.uri.path, "/xhttp/"))
   ```

4. The path must allow XHTTP GET/POST requests and streaming responses, without browser challenges, Access login, path rewrites, or redirects. If blocked, use security events to adjust only the relevant domain and path rules; do not disable protection for the whole site.
5. Set the client address, SNI, and Host to `down.example.com`, port `443`, TLS enabled, path `/xhttp`, and mode `packet-up`. Keep the inbound UUID and other protocol settings. Verify this single-domain CDN node before splitting upload and download.

The origin Web allowlist checks connection source IPs. Behind a CDN, these are CDN origin-facing IPs, so a campus egress IP no longer identifies the visitor. Use a separate node Web domain rather than relaxing the panel allowlist. Keep the original REALITY address and SNI route direct; an ordinary HTTP CDN cannot proxy REALITY.

Do not narrow public `443` to CDN origin ranges with a firewall: REALITY and Option A SNI routes share that `443`, so an origin-IP filter on the port also cuts every direct node. The CDN origin must stay on `443`; custom origin ports are not supported. Put access control on the domain and route layer, not on the port.

XHTTP POST uploads are not truncated by the Web proxy: the generated Nginx path location sets `client_max_body_size 0`, and Caddy imposes no body limit by default. The CDN side still needs the cache bypass from step 3.

References: [Cloudflare Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/), [Cache Rules](https://developers.cloudflare.com/cache/how-to/cache-rules/settings/).

## Split upload and download: direct upload, CDN download

Splitting uses different connection entry points, not two unrelated nodes. Reuse one XHTTP inbound with an empty server Host and mode `auto`, and register two path rules:

| Direction | DNS | Path proxy |
| --- | --- | --- |
| Upload `up.example.com` | DNS only (grey cloud), direct to VPS | `/xhttp -> 127.0.0.1:2400` |
| Download `down.example.com` | Proxied (orange cloud), through CDN | `/xhttp -> 127.0.0.1:2400` |

Both must be registered Web domains with matching origin certificates. Public `443` on both must reach **the same inbound in the same Xray process, with the same path**. Do not create separate upload and download inbounds or load-balance requests across instances. When a second rule reuses an existing path, the script compares the local address and port and warns on any mismatch.

The download domain is still an ordinary Web domain, so its default backend stays reachable at `/`; do not point that default backend at an internal service, the panel, or a subscription port.

Set the client's main connection to `up.example.com:443`, TLS enabled, SNI/Host `up.example.com`, path `/xhttp`, and mode `packet-up`. In an Xray client supporting `downloadSettings`, enter this object in **XHTTP extra** (the location in custom JSON is `streamSettings.xhttpSettings.extra`):

```json
{
  "downloadSettings": {
    "address": "down.example.com",
    "port": 443,
    "network": "xhttp",
    "security": "tls",
    "tlsSettings": {
      "serverName": "down.example.com",
      "alpn": ["h2", "http/1.1"]
    },
    "xhttpSettings": {
      "host": "down.example.com",
      "path": "/xhttp",
      "mode": "packet-up"
    }
  }
}
```

Domains and ports above are example values. Download settings do not inherit upload settings: fill in `network`, TLS, SNI, and path explicitly. Do not use `stream-one`. If the client lacks extra/custom JSON support, use the single-domain CDN node first. If a subscription converter drops `downloadSettings`, import directly into a supporting client and check its active configuration.

Test each domain as a normal XHTTP node before enabling separation. Set client logging to `info` and check the actual download address. If Web access logging is enabled, also confirm upload POST requests through `up.example.com` and download GET requests through `down.example.com`; then perform real uploads and downloads through the local proxy. TCP/TLS success or one HTTP 204 does not prove separation works.

Both directions in this example use TCP HTTPS; no origin UDP `443` is added. Direct upload can still fail if the campus network times out on the origin path. Test both directions through the CDN first if needed, then compare failures and transfers on the same device, network, and failure window. This does not guarantee a fix for the previous timeouts.

Reference: [Xray's official XHTTP upload/download separation explanation](https://github.com/XTLS/Xray-core/discussions/4113).

## Choosing between them

| Question | Option A | Option B |
| --- | --- | --- |
| Do you have a dedicated node domain? | Yes | Not needed |
| Same domain for node and panel? | Not possible | Yes |
| Fewer certificates to maintain? | No | Yes |
| Planning to use a CDN? | Depends on CDN protocol support | Better fit, verify with grey cloud first |
| Change configuration only once? | Yes | No |

REALITY nodes are unaffected by either option. They keep using their own SNI routes and never touch the XHTTP path rules.

## Known limits

- **No HTTP/3**: the XHTTP QUIC mode needs UDP `443`, and the entry listens on TCP `443` only.
- **Unavailable in xray-fallback**: that mode has no separate Web front layer, so `[2] -> [10]` reports it as unavailable. Configure XHTTP inside the main inbound `fallbacks` instead.
- **Web allowlists also limit XHTTP**: Option B rules live under a Web domain, so an IP allowlist on that domain applies to XHTTP as well. REALITY and Option A SNI routes are unaffected.
- **SNI filtering works on domains**: Option B adds no new SNI because the domain is already listed. Option A must register the node domain as an SNI route, or the strict gate drops it.
- **Long-lived XHTTP connections**: the script disables response and request buffering for the path proxy and sets a one-hour read/write timeout. Do not add a short timeout in the Web proxy on top of that.

## Verification

Check the listeners first:

```bash
ss -lntp | grep -E ':(443|2400|2410)'
```

Expected: `443` belongs to the active entry service; `2400` and `2410` belong to Xray and bind `127.0.0.1`.

For Option B, check whether the path reaches the XHTTP backend:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://panel.example.com/xhttp
```

A plain GET returning 404 or 400 does not mean the node failed, but the status alone cannot prove it reached XHTTP. If you get the panel login HTML, check path matching; for a 502, check the backend listener and port:

```bash
curl -sS -D - -o /dev/null https://panel.example.com/xhttp | head -20
curl -sS http://127.0.0.1:2400/xhttp -o /dev/null -w '%{http_code}\n'
```

Use both responses together with logs to locate the fault. A Web proxy or CDN may change headers, and matching status codes do not prove correct routing.

Finally, connect with a real client. TLS and port checks do not prove an XHTTP session works.

## Troubleshooting

| Symptom | Check first |
| --- | --- |
| Handshake succeeds, then no data | Inbound path versus client path; a missing or extra trailing slash |
| Option B returns the panel login page | Path rule inactive: confirm the reapply, and confirm the path does not overlap `webBasePath` |
| Option B returns 502 | Local XHTTP inbound not listening or wrong port; verify with a direct `curl` |
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
- Do not bind the XHTTP local port to `0.0.0.0`.
- Do not place the XHTTP path on `/panel/`, `/sub/`, `/clash/`, or their subpaths.
- Do not try to manage paths through `[2] -> [10]` in `xray-fallback` mode.
- Do not deploy with the example domains and ports.
