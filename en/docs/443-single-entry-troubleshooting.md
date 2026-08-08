# Shared Port 443 Troubleshooting

Before troubleshooting, run:

```text
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

If you want to submit an issue, run:

```text
Main menu [15 Service health overview] -> [Generate feedback diagnostic information]
```

Please desensitize the Token, private key, and subscription key other than the domain before pasting them publicly.

## Website selection suggestions

When adding a new website, reverse proxy domain or filling in REALITY to disguise SNI, you must first distinguish the purpose. The web domain can use CDN according to actual needs, but the origin site will see the CDN node IP; REALITY/node domain requires the client to directly connect to the VPS, and the Cloudflare proxy should not be enabled; REALITY should use the external real HTTPS site to disguise SNI.

When troubleshooting for the first time, you can first set the relevant domain to DNS only / gray cloud to reduce link variables. This suggestion is used to troubleshoot access links and does not mean that Orange Cloud will directly cause the DNS-01 certificate issuance failure.

## Basic check command

First check whether the listening position is as expected:

`8443`, `1443`, `40000`, and `2096` in the following commands and sample output are sample ports; the actual configuration is subject to the current binding of the service and the configuration saved by the script.

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
nginx -t
caddy validate --config /etc/caddy/Caddyfile
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

Internet `443` should only be bound by the shared entry service corresponding to the current `ENTRY_MODE`:

```text
nginx-stream   -> nginx
xray-fallback  -> xray / 3x-ui / x-ui managed Xray
tcp-peek       -> tcppeek / vpso-mux
```

If `/etc/vps-optimize/sni-stack.env` does not have `ENTRY_MODE`, the script reads as `nginx-stream` compatible. Other local backends should roughly be:

```text
127.0.0.1:8443    caddy
127.0.0.1:1443    x-ui / 3x-ui / xray
127.0.0.1:40000   x-ui / 3x-ui
127.0.0.1:2096    x-ui / 3x-ui
```

## ERR_TOO_MANY_REDIRECTS

### phenomenon

The browser prompts that there are too many redirects and the panel page keeps jumping.

### Common causes

- The 3x-ui panel is still enabled and comes with HTTPS.
- Caddy is reversed to the HTTPS backend, but the backend is forced to jump back to HTTPS.
- Cloudflare Enable proxy or SSL pattern mismatch.

### check command

```bash
curl -I https://panel.example.com/panel/
curl -I http://127.0.0.1:40000/panel/
```

### Solution

- Clear the 3x-ui panel certificate path and restart the panel.
- Let the web generation engine backend to the local HTTP backend.
- shared port 443 point related domains are recommended to use DNS only / Gray Cloud.
- If you just cleared the certificate and the browser still jumps in a loop, try again with an incognito window.

### Related menu entry

```text
Main menu [5 panel、Nodes and subscription tools] -> [3 panel SSL Repair]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## ERR_EMPTY_RESPONSE

### phenomenon

The browser prompts `ERR_EMPTY_RESPONSE`, and the page does not return content normally.

### Common causes

- Internal ports such as `:8443`, `:1443`, `:40000` were accessed.
- SNI misses Caddy, and the traffic falls to REALITY.
- The current entry mode SNI/Web domain route does not include the panel or website domain; for `nginx-stream`, see the Nginx stream configuration, and for `tcp-peek`, see the `vpso-mux` configuration.

### check command

```bash
grep -n "panel.example.com" /etc/nginx/stream.d/*.conf
grep -n "panel.example.com" /etc/vps-optimize/vpso-mux.yaml
ss -lntp | grep -E ':443|:8443|:1443'
```

The correct access address should be:

```text
https://panel.example.com/panel/
```

Do not visit:

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

### Solution

- Confirm that the access is to the standard HTTPS address of the domain without an internal port.
- Confirm that the panel, subscription, or website domain has been written to the Web/SNI route used by the current entry mode.
- Reapply the currently saved 443 configuration.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings] -> [5 Reapply saved configuration]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## ERR_CONNECTION_CLOSED / ERR_SSL_PROTOCOL_ERROR

### phenomenon

The browser prompts that the connection is closed, or prompts a SSL protocol error.

### Common causes

- Internet `443` is not currently bound to the entry service corresponding to `ENTRY_MODE`.
- The Caddy, 3x-ui, REALITY or old Nginx server outside the current entry mode has preempted the public port `443`.
- TLS traffic is forwarded to a backend that is not supposed to receive browser HTTPS.

### check command

```bash
ss -lntp | grep ':443'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

### Solution

- Confirm that the Internet `443` is only bound by the single ingress service corresponding to the current `ENTRY_MODE`: `nginx-stream` corresponds to `nginx`, `xray-fallback` corresponds to the Xray main inbound connection, and `tcp-peek` corresponds to `tcppeek` / `vpso-mux`.
- Caddy Use `127.0.0.1:8443`.
- REALITY / Xray local inbound connections that are not connected to the `xray-fallback` primary inbound connection use local bindings such as `127.0.0.1:1443`.
- The panel and subscription backends only serve as native HTTP.

### Related menu entry

```text
Main menu [13 Inspect and release ports]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [6 Reapply current entry mode]
```

## Port concurrent connection limit accidental damage

### phenomenon

A certain node, subscription or website occasionally fails to connect, the handshake is disconnected, or only some source IPs access the public internet. `443` exception.

### Common causes

- The connlimit rule added by this script exists on public port `443`.
- The rule counts the number of concurrent connections of TCP by public internet port and source IP, and does not recognize SNI, Xray/3x-ui inbound, UUID or user.
- When multiple websites, subscriptions, and nodes share the public port `443`, connections from the same source IP may be counted together in the limit.

### Check method

Let’s first look at the “Port Concurrent Connection Limitation” paragraph in the 443 link health check:

```text
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

If the public port `443` has the connlimit rule added by this script, it can only be applied to the entire public port `443`, and cannot be precise to a certain SNI, Xray/3x-ui inbound, UUID or user. Don't think of it as a precise limit on an individual node, an inbound, or a user.

### Solution

- If it is confirmed that the fault is accidental, go to the port concurrent connection limit menu to view or delete the connlimit rule of the public port `443`.
- After deleting the rule, return to the 443 link health check to confirm whether the public port `443` rule remains in the runtime and persistence files.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
Main menu [8 Firewall rules] -> [5 Port concurrent connection limit]
```

## Nginx is running but 443 is not listening.

### phenomenon

`current 443 Entry status` shows `configuration mode：nginx-stream`, `nginx：Running`, but not `public port `443`：not listening`.

If the status page also displays an old naming compatibility prompt, such as `nginx_stream` or `tcp_peek`, it means that the script cannot safely automatically rewrite the file. Follow the prompts to reapply the current entry mode. The script will read and write back `nginx-stream`, `xray-fallback` or `tcp-peek` according to the new name.

### Common causes

- `/etc/nginx/stream.d/vps_sni_443.conf` was not regenerated after being isolated by a switch or rollback process.
- `/etc/nginx/nginx.conf` does not actually load `stream { include /etc/nginx/stream.d/*.conf; }`.
- Nginx stream The dynamic module is installed, but the main configuration does not load the module directory.

### Solution

First run:

```text
Main menu [19 443 shared entry manager] -> [6 Reapply current entry mode]
```

Reapplying will force the generation of the Nginx Stream configuration and check that `nginx -T` actually loads `/etc/nginx/stream.d/vps_sni_443.conf`. If it still fails, the script prints the Nginx status, recent logs, stream include, and port listening clues.

## 404

### phenomenon

Panel, subscription, or Clash/Mihomo link returns 404.

### Common causes

- The access path is inconsistent with `webBasePath` of 3x-ui.
- The subscription path prefix is written incorrectly, for example, `sub` instead of `/sub/`.
- Caddy configuration does not contain the corresponding path.

### check command

```bash
curl -I https://panel.example.com/panel/
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
grep -R "panel.example.com" /etc/caddy/conf.d /etc/caddy/Caddyfile 2>/dev/null
grep -n "path" /etc/caddy/conf.d/panel.example.com.caddy
grep -n "reverse_proxy" /etc/caddy/conf.d/panel.example.com.caddy
```

### Solution

- Unified panel path, such as `/panel/`.
- Unified subscription path, such as `/sub/`, `/clash/`.
- 443 The wizard fills in the path prefix. Do not fill in the client's `Subscription` together.
- Reapply the 443 configuration.

For example, when Clash/Mihomo uses `/clash/`, the three places should be consistent:

```text
3x-ui URI path (Clash)：/clash/
443 wizard Clash/Mihomo path prefix：/clash/
https://panel.example.com/clash/CLIENT_SUBSCRIPTION
```

When only using `/clash/`, you should see similar configuration in Caddy:

```text
@sub path /clash /clash/*
handle @sub {
    reverse_proxy 127.0.0.1:2096
}
```

If both normal subscription and Clash/Mihomo are used, `@sub path` should contain both paths:

```text
@sub path /sub /sub/* /clash /clash/*
```

After manually changing Caddy, remember to verify and reload:

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy
```

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings] -> [1 Edit panel/subscription ports and paths]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [6 Reapply current entry mode]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## 502

### phenomenon

The browser can connect to HTTPS, but the page displays 502.

### Common causes

- Caddy The request can be received, but the panel or subscription backend is not running.
- The backend listening port and script configuration are inconsistent.
- The custom website/reverse proxy Docker or intranet backend address cannot be accessed from the host where Caddy/Nginx is located.
- The backend only listens to the public internet address or only IPv6.

### check command

For intranet backend, please replace the example address with the actual address.

```bash
systemctl status caddy --no-pager
ss -lntp
curl -I http://127.0.0.1:40000/
curl -I http://127.0.0.1:2096/
curl -I http://10.0.0.20:3000/
```

### Solution

- Start or restart 3x-ui / x-ui.
- Panel/Subscription Backend: Fixed listening address and port at `Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]`.
- Custom website/reverse backend: Corrected backend address and port at `Main menu [19 443 shared entry manager] -> [8 management Web domains / reverse proxy] -> [3 Edit website/reverse proxy backend]`.
- Reapply the configuration and perform a health check.

If the test works according to the actual backend address, but the Internet is still 502, it is usually Caddy/Nginx. The reverse proxy address or port is inconsistent with the actual binding.

### Related menu entry

```text
Main menu [5 panel、Nodes and subscription tools] -> [1 3x-ui panel script]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## The subscription link still has:2096

### phenomenon

The copied subscription link still contains `:2096`, for example:

```text
https://panel.example.com:2096/sub/xxxx
```

### Common causes

- 3x-ui Subscription reverse proxy URI is not set.
- Public URL / External URL still outputs the internal port.
- If the node in the subscription content still has a local port, check `Hosts / Host` or `External Proxy` in the next section.

### Solution

Return to 3x-ui:

```text
Subscription settings -> Reverse proxy URI
```

Fill in the public internet address:

```text
reverse proxy URI：https://panel.example.com/sub/
reverse proxy URI (Clash)：https://panel.example.com/clash/
```

Don't write:

```text
https://panel.example.com:2096/sub/
http://127.0.0.1:2096/sub/
```

After saving and restarting the panel, copy the subscription link again.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [11 Subscription link / External Proxy Tips]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
```

## Node link still has:1443

### phenomenon

The client node link still contains `:1443`, and the public port `443` is not used.

### Common causes

- The external proxy is not set for the REALITY inbound of the old version of 3x-ui.
- 3x-ui v3.4.0+ of `Hosts / Host` does not set the public internet address and port for this inbound.
- The node domain has gone through the Cloudflare proxy, and the client cannot directly connect to the VPS.

### Solution

3x-ui v3.4.0 and later: Left sidebar -> `Hosts / Host` -> New Host:

```text
inbound：Select the corresponding REALITY inbound
address：node.example.com Or server public IP
port：443
Security：Same, Or fill in the actual security type of the inbound
SNI / Fingerprint / ALPN：Keep the actual value of the inbound and client consistent
```

3x-ui v3.3.1 and before: Return to REALITY inbound and set `External Proxy`:

```text
Type：Same
address：node.example.com Or server public IP
port：443
```

If the node domain is Cloudflare, it must be Huiyun/DNS only.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [11 Subscription link / External Proxy Tips]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
```

## Certificate application failed

### phenomenon

Caddy or acme.sh failed to apply for a certificate, and HTTPS could not be opened normally.

### Common causes

- Cloudflare API Token has insufficient permissions.
- The token does not authorize the zone where the current domain is located.
- `_acme-challenge` TXT record has not been propagated or the residual record is abnormal.
- The server time is incorrect.

### check command

```bash
date -Is
dig +short A panel.example.com @1.1.1.1
systemctl status caddy --no-pager
journalctl -u caddy -n 80 --no-pager
```

### Solution

- Confirm that the domain is located in the Cloudflare zone that Token has authorized.
- Check the `_acme-challenge` TXT record and acme.sh error log.
- Correct the Token permissions and re-issue it.
- Enable NTP time synchronization.

Recommended order:

```text
1. 443 Connection and security check
8. update Cloudflare API Token
9. Reissue a domain certificate
12. Check and reload Caddy
```

### Related menu entry

```text
Main menu [1 Preflight and risk scan]
Main menu [19 443 shared entry manager] -> [12 CF DNS / Caddy Certificate maintenance]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## Cloudflare Token permission issue

### phenomenon

The certificate issuance prompts that the authentication failed, there is no permission to access the zone, or the DNS record cannot be written.

### Common causes

- Token does not have `Zone.Zone.Read`.
- Token does not have `Zone.DNS.Edit`.
- The token is only authorized for the wrong zone.

### check command

```bash
grep -n "CF_" /root/.config/vps-panel/cloudflare.env 2>/dev/null
```

Do not post the original Token text to the Issue.

### Solution

- Re-create the Token at Cloudflare.
- Permissions include at least `Zone.Zone.Read` and `Zone.DNS.Edit`.
- Only authorize the domain zone that needs to issue a certificate.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [12 CF DNS / Caddy Certificate maintenance]
```

## DNS is not a gray cloud / DNS only

### phenomenon

REALITY The connection fails, the subscription link is abnormal, the real source IP cannot be obtained from the Web whitelist, or the browser access result is different from the directly connected VPS.

### Common causes

- Cloudflare opens the Orange Cloud agent.
- REALITY The node domain cannot be directly connected to the VPS after being proxied.

### check command

```bash
dig +short A panel.example.com @1.1.1.1
dig +short A node.example.com @1.1.1.1
```

### Solution

- Change the REALITY/node domain to DNS only/Huiyun to ensure that the client is directly connected to the VPS.
- Web panels, subscriptions and website domains can use Orange Cloud according to actual needs; when a real source IP whitelist is required, change to Gray Cloud first, or redesign access control based on the Cloudflare source address.
- Wait for DNS to take effect and then re-examine.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## Port 443 is occupied

### phenomenon

Nginx cannot start, prompting `bind() to 0.0.0.0:443 failed`.

### Common causes

- Caddy, Apache, old Nginx server, 3x-ui or Xray outside the current entry mode still listen to the public port `443`.
- In `nginx-stream` / `tcp-peek` mode, REALITY is directly bound to `0.0.0.0:443` without changing to local binding.

### check command

```bash
ss -lntp | grep ':443'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

### Solution

- Let the public port `443` only hand over the single ingress service corresponding to the current `ENTRY_MODE`; when switching to `nginx-stream`, it is Nginx stream, when switching to `tcp-peek`, it is `vpso-mux`, and when switching to `xray-fallback`, it is the main inbound service of Xray.
- Caddy is changed to `127.0.0.1:8443`.
- REALITY / Xray local inbound connections that are not `xray-fallback` primary inbound connections are changed to `127.0.0.1:1443` such local bindings.

### Related menu entry

```text
Main menu [13 Inspect and release ports]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [6 Reapply current entry mode]
```

## Caddy/Nginx/REALITY wrong listening address

### phenomenon

The health check indicates that the service is listening on the public internet, or the link is open but the internal port is exposed.

### Common causes

- Caddy binds `0.0.0.0:8443`.
- The panel backend is bound to `0.0.0.0:40000`.
- REALITY listens on the public port `443` and conflicts with Nginx stream.

### check command

```bash
ss -lntp
grep -R "listen" /etc/nginx /etc/caddy 2>/dev/null
```

### Solution

- Web reverse proxy engine local listening, 3x-ui panel/subscription and Xray/TCP/SNI inbound continue to use local addresses such as `127.0.0.1`.
- The custom website/reverse proxy backend uses `127.0.0.1` by default; when you need to connect to the intranet service, you can fill in the intranet IP or hostname that the current VPS can directly access.
- Reapply the 443 configuration.
- Keep SSH and public port `443` when tightening the firewall.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [6 Reapply current entry mode]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## Panel can be opened but subscription is not available

### phenomenon

`/panel/` is OK, but `/sub/`, `/clash/` or the CLIENT_SUBSCRIPTION link is not available.

### Common causes

- 3x-ui The subscription service is not enabled.
- The subscription path prefix is inconsistent with the Caddy configuration.
- Public URL still outputs the internal port.
- 3x-ui v3.4.0+ of `Hosts / Host` or older `External Proxy` still output internal ports.

### check command

```bash
curl -I http://127.0.0.1:2096/sub/
curl -I https://panel.example.com/sub/
```

### Solution

- Enable subscription in 3x-ui.
- The subscription paths use `/sub/` and `/clash/` uniformly.
- Check that the subscription link does not appear `:2096`, `:40000`, `:8443`.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [11 Subscription link / External Proxy Tips]
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```

## REALITY connection failed

### phenomenon

The panel and subscriptions are fine, but the client REALITY node cannot connect.

### Common causes

- The REALITY local listening port and the Nginx stream forwarding port are inconsistent.
- `dest` / `Target` is written as its own domain.
- `serverNames` / `SNI` is not the external real HTTPS site.
- The node domain is proxied by Cloudflare.

### check command

```bash
ss -lntp | grep -E ':1443|:443'
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com </dev/null
```

### Solution

- REALITY It is recommended to use `127.0.0.1:1443` for local binding.
- REALITY pretends to be SNI using the external real HTTPS site.
- The node domain remains DNS only / gray cloud.
- Reapply the 443 configuration.

### Related menu entry

```text
Main menu [19 443 shared entry manager] -> [10 Modify 443 shared settings]
Main menu [19 443 shared entry manager] -> [6 Reapply current entry mode]
Main menu [19 443 shared entry manager] -> [13 443 Connection health check]
```
