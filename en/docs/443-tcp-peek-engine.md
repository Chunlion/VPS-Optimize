# Port 443 Reuse: Entry Modes and Internals

VPS-Optimize provides three ways to share public port 443: Nginx Stream, TCP Peek + Splice (`vpso-mux`), and Xray Fallback. Start with Nginx Stream unless you have a specific reason to use another mode.

`panel.example.com`, `site.example.com`, `node.example.com`, `SERVER_IP`, `8443`, `8444`, and `1443` are example values. Replace them with your actual domains, server IP, and the ports saved by the script.

## Choose a mode

| Mode | 3x-ui/Xray listener | Use it when |
| --- | --- | --- |
| `nginx-stream` | Panel, subscription service, and Xray inbounds listen on local `127.0.0.1` ports | Recommended default; broadest compatibility and simplest recovery |
| `tcp-peek` | Same local listeners as `nginx-stream` | You want `vpso-mux` while keeping the same domains, certificates, backends, and routes |
| `xray-fallback` | One Xray main inbound listens on public `443` and falls back to the local Web proxy | You already understand and maintain the Xray fallback chain yourself |

Only one process may listen on public port `443`: `nginx`, `vpso-mux`, or the Xray main inbound.

## Shared configuration

The three entry modes share the same set of public configurations:

- Web domains, Web reverse-proxy backend mappings, and certificates are shared by all modes. Web allowlists are shared only between Nginx Stream and TCP Peek.
- The certificate still uses the existing `acme.sh + Cloudflare DNS API` process, does not introduce the Caddy DNS module, and does not use `xcaddy`.
- The Web allowlist protects Web domains only; it never filters Xray node traffic.
- The local Web reverse proxy may be Caddy or Nginx, and the same mapping is reused when switching entry modes.
- In Nginx Stream and TCP Peek, the Web allowlist is checked at the entry layer using `SNI + source IP`. Xray Fallback does not support that front allowlist.
- If `/etc/vps-optimize/sni-stack.env` has no `ENTRY_MODE`, the script reads it as `nginx-stream` for compatibility.
- New configurations use `nginx-stream`, `xray-fallback`, or `tcp-peek`. The old names `nginx_stream`, `xray_fallback`, and `tcp_peek` remain read-compatible.

Common menu paths:

```text
Main menu [19 Port 443 Reuse Management]
  -> [2] Install / switch the port 443 entry mode
  -> [7] Roll back the last entry-mode switch
  -> [16] View the current entry log
```

For exact 3x-ui panel, subscription, and inbound fields, see [Port 443 Reuse: Setup and Configuration](443-single-entry.md).

## Nginx Stream default stable implementation

Nginx Stream is the stable default. Nginx listens on public port `443` and uses `ssl_preread` to read SNI from the TLS ClientHello. It does not terminate TLS or decrypt traffic.

```text
public port `443`
  -> Nginx stream ssl_preread
  -> panel/site/sub SNI  -> Caddy/Nginx local Web reverse proxy TLS
  -> Xray/REALITY SNI   -> Xray/3x-ui local inbound
  -> unknown SNI        -> Default Xray/REALITY backend
```

This is the recommended long-term default. It supports the complete Web, REALITY, panel, subscription, allowlist, and rollback workflow.

## TCP Peek + Splice / vpso-mux implementation

TCP Peek and Nginx Stream use the same saved configuration. Do not create a second set of domains, certificates, Web backends, allowlists, or Xray SNI routes. Open `[2 Install / switch the port 443 entry mode]` and choose TCP Peek. The script builds `vpso-mux` when required, validates its configuration, and tests the routes on the isolated port `8444`. Public port `443` changes hands only after the preflight succeeds.

`vpso-mux` uses `MSG_PEEK` to inspect SNI in the TLS ClientHello without consuming the first packet. The backend receives the original ClientHello. Forwarding uses splice when available and falls back to ordinary copy when necessary.

### Connection life cycle of TCP Peek

After a client connection enters `vpso-mux`, it is processed roughly in the following order:

```text
client TCP connect
  -> vpso-mux accept
  -> recv(MSG_PEEK) inspects ClientHello in the receive buffer
  -> parse SNI from the ClientHello extension
  -> select a backend using SNI and the source-IP allowlist
  -> connect to the local backend
  -> forward the original TCP byte stream in both directions
```

Unlike an ordinary `recv`, `MSG_PEEK` does not remove data from the socket buffer. After `vpso-mux` parses SNI, the original ClientHello remains available and is forwarded unchanged when the backend connection is established.

So TCP Peek is not terminated by TLS, nor is it decrypted by a man-in-the-middle:

- It does not hold, select, or issue certificates.
- It does not read the HTTP path, header, WebSocket content, or TLS encrypted application layer data.
- Certificates and the HTTP reverse proxy are still handled by the current web reverse proxy engine; Xray/REALITY node traffic is still handled by the Xray/3x-ui local inbound connection.
- It only relies on SNI in the clear text phase of the TLS handshake for layer four routing.

### What do you see in ClientHello?

TLS When the connection starts, the client will first send ClientHello. ClientHello is still a clear text structure, which usually contains the `server_name` extension, which is the domain that the browser or proxy client wants to access. `vpso-mux` only parses these fields:

```text
TLS record
  -> record type = handshake
  -> handshake type = ClientHello
  -> extensions
  -> server_name extension
  -> hostname SNI
```

The implementation will first peek about 4 KiB of data. If the ClientHello is not received completely, the peek buffer will continue to be expanded, up to 16 KiB, and controlled by `timeouts.peek`. The script writes `3s` by default. The parsed SNI will be uniformly converted to lowercase, and the dot at the end will be removed. For example, `Panel.Example.COM.` will become `panel.example.com`. If the data is not TLS ClientHello, the ClientHello is incomplete, there is no SNI, or the protocol itself does not contain SNI, the specific domain rule will not be hit, and subsequent processing will be based on the default backend.

This is why this solution is suitable for HTTPS/TLS/SNI traffic, but not suitable for diverting traffic based on HTTP path or plain text protocol content. After the TLS handshake, the application layer content has been encrypted, and `vpso-mux` cannot and cannot rely on it to determine the path.

### routing rules

The script generates `/etc/vps-optimize/vpso-mux.yaml` based on the Port 443 Reuse configuration. The generated routes are roughly divided into several categories:

| Route source | target backend | Whether to use web whitelist |
| --- | --- | --- |
| Panel domain | Caddy/Nginx local web reverse proxy HTTPS port | Yes, if the domain is configured with a whitelist |
| Ordinary website / reverse proxy domain | Caddy/Nginx local web reverse proxy HTTPS port | Yes, if the domain is configured with a whitelist |
| Old TCP/SNI local inbound records | Corresponds to local address and port | No |
| Xray Inbound management record | Corresponds to the local Xray inbound address and port | No |
| REALITY disguise SNI | Default Xray/REALITY local backend | No |
| Miss SNI / None SNI / Not TLS | Default Xray/REALITY local backend | No |

When matching, first do the exact SNI match, and then do the wildcard domain match. Wildcards only match one level of subdomains. For example, `*.example.com` can match `a.example.com`, but will not match `a.b.example.com`. If a web route is configured with a whitelist, `vpso-mux` will check the client source IP before routing; if it is not in the whitelist, the connection will be intercepted directly. Xray inbound connections, REALITY SNI and the default backend do not use the web whitelist to avoid accidentally damaging node traffic.

### The difference between splice and copy

`vpso-mux` only starts forwarding after routing is completed and connected to the backend. There are two modes of forwarding:

| mode | working method | Suitable for the situation |
| --- | --- | --- |
| `splice` | The Linux kernel transfers data between sockets and pipes to minimize user state copying. | Normal priority path |
| `copy` | The Go process forwards data with ordinary read/write loops | Fallback when splice is unavailable, fails, or is disabled |

The default configuration is:

```yaml
splice:
  enabled: true
  pipe_size: 1048576
  fallback_to_copy: true
```

In other words, `vpso-mux` will try splice first. If the current kernel, socket status or operating environment is not suitable for splice, and `fallback_to_copy` is `true`, it will automatically fall back to normal copy. copy is not an error, it just lacks zero-copy optimization; the status page or `copy_fallback` in `status.json` can be used to observe whether there are frequent rollbacks.

Splice changes only how bytes are forwarded after a backend is selected. SNI routing still happens once during the initial ClientHello; application data does not trigger another routing decision.

`timeouts.idle` applies to the splice path. An idle connection is closed after the configured timeout instead of occupying forwarding resources indefinitely. The copy path uses ordinary read/write deadlines.

### Concurrency protection and status refresh

`vpso-mux` has built-in connection concurrency protection. The new configuration generated by the script will write:

```yaml
limits:
  max_connections: 4096
```

The old `vpso-mux.yaml` even without the `limits` field will automatically use the same default value by the program; users do not need to manually migrate the configuration. If you really want to turn off this restriction, you can set `max_connections` to `0`, which means there is no limit on the number of connections within the program.

If the client does not send a complete ClientHello within `timeouts.peek`, `vpso-mux` closes the connection instead of forwarding it to the default Xray/REALITY backend. The generated default is `3s`.

Runtime counters are written to `/var/lib/vps-optimize/vpso-mux/status.json` at intervals and again on exit. The status view reports active and rejected connections, connection limits, backend dial errors, peek errors and timeouts, route hits, and forwarded bytes.

### Route index

`vpso-mux` will precompile the routing index after the configuration validation passes. Exact SNI uses map query, and wildcard SNI remains as an ordered list; the matching semantics remain unchanged, exact matching still takes precedence over wildcard matching, and wildcard matching maintains the order in the configuration. This optimization will not change the `vpso-mux.yaml` format, nor will it require users to refill the domain.

Main advantages of TCP Peek:

- The configuration process is the same as Nginx Stream. The saved domain, certificate, Web reverse proxy engine backend, Web whitelist and Xray SNI routing are reused during switching.
- `MSG_PEEK` only checks ClientHello and does not consume the first packet. What the backend receives is still the client’s original TLS handshake data.
- For forwarding, splice is used first to reduce user-mode data copy; when it is unavailable, it automatically falls back to ordinary copy.
- `vpso-mux` is an entry program specially prepared for 443 SNI routing. Status, logs, configuration validation and 8444 pre-switching checks all revolve around this link.

The generated `vpso-mux.yaml` contains one public listener. `0.0.0.0:443` is IPv4 only. To accept IPv6, set the public listen address to `::` and regenerate the configuration; do not add both listeners manually on the same port.

```text
public port `443`
  -> vpso-mux
  -> recv(MSG_PEEK) View TLS ClientHello SNI
  -> route by SNI / whitelist Select backend
  -> bidirectional splice forwarding, with copy fallback
```

Core differences from Nginx Stream:

| Item | Nginx Stream | TCP Peek + Splice / vpso-mux |
| --- | --- | --- |
| Configuration process | Use Port 443 Reuse configuration | Use the same Port 443 Reuse configuration |
| Entry process | `nginx` | `vpso-mux` |
| SNI inspection | `ssl_preread` | Parse ClientHello with `MSG_PEEK` |
| TLS processing | Do not terminate TLS | Do not terminate TLS |
| Certificate | Current web reverse proxy engine handles web/panel certificates | Current web reverse proxy engine handles web/panel certificates |
| Unknown SNI | Default Xray/REALITY backend | Default Xray/REALITY backend |
| Forwarding | Nginx stream proxy | splice with copy fallback |

View status and logs:

```text
Main menu [19 Port 443 Reuse Management]
  -> [16] View the current entry log
```

Commonly used diagnostic commands:

```bash
systemctl status vpso-mux --no-pager
journalctl -u vpso-mux -n 120 --no-pager
/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml -check
```

If `transfer_mode` is displayed as `copy`, it means that the splice is not used or has been rolled back. Splice can be turned off in `/etc/vps-optimize/vpso-mux.yaml`:

```yaml
splice:
  enabled: false
  fallback_to_copy: true
```

## Xray Fallback

In Xray Fallback mode, an existing Xray/3x-ui main inbound owns public port `443` and sends ordinary HTTPS fallback traffic to the local Web reverse proxy. VPS-Optimize does not create or edit the internal 3x-ui/Xray inbound configuration.

```text
public port `443`
  -> Xray/3x-ui main inbound
  -> the main inbound handles Xray node traffic
  -> ordinary HTTPS falls back to the local Caddy/Nginx Web backend
```

The Xray inbound route menu cannot add multi-inbound SNI routes in this mode because the Xray main inbound already owns public `443`. Use Nginx Stream or TCP Peek when several local Xray inbounds must share port `443`.

## Switch and rollback

To switch to TCP Peek + Splice:

```text
Main menu [19 Port 443 Reuse Management]
  -> [2] Install / switch the port 443 entry mode
  -> [3] TCP Peek + Splice
```

If `/usr/local/bin/vpso-mux` or Go is missing, the installer attempts to add the required toolchain and build the binary. It then starts `vpso-mux-preflight.service` on isolated port `8444` to test Web and Xray backends. A failed preflight leaves public port `443` unchanged and shows the service status and recent logs.

Formal switching will generate and verify `vpso-mux.yaml`, create a backup, isolate the Nginx stream 443 configuration currently managed by VPS-Optimize, start `vpso-mux` to take over the public port `443`, and check that the web reverse proxy engine and Xray local backend are reachable. Automatic rollback is attempted on failure.

`8444` pre-check will do an additional TCP Peek routing matrix check: the panel domain and web domain will obtain the certificate chain through the test port according to SNI; the default Xray/REALITY backend, old TCP/SNI records and The `Xray inbound management` record will check whether the corresponding local address and port are connectable. In this way, problems such as missing certificates, the web reverse proxy engine is not ready, or the local Xray inbound port is not listening can be discovered before the public port `443` is officially taken over.

If the current SSH session is connected to the ingress port, such as `443`, the script will reject the switch to avoid directly disconnecting the current management connection. Please use the cloud provider VNC/Serial Console instead, or log in using the non-entry port SSH first.

Roll back the previous round of entry mode switching:

```text
Main menu [19 Port 443 Reuse Management]
  -> [7] Roll back the last entry-mode switch
```

Universal rollback will restore the backup before the last entry mode switch, and is suitable for undoing the latest portal switch triggered by `[3]`, `[4]` or `[5]`. TCP Peek This wider rollback entry is also used when rollback is required after switching.

## Common faults

Check public port `443` current listening party:

```bash
ss -lntup | grep ':443'
```

Switch to TCP Peek + Splice and you should see `vpso-mux`. If it is still Nginx, Caddy or Xray, it means that the entry relationship has not been switched cleanly, and it is recommended to roll back immediately.

Check the web reverse proxy engine local TLS backend:

```bash
ss -lntup | grep ':8443'
systemctl status caddy --no-pager
```

Check Xray/REALITY local inbound:

```bash
ss -lntup | grep ':1443'
systemctl status xray --no-pager
```

The default backend will be used when there is no TLS, no SNI, incomplete ClientHello or the client protocol does not include SNI. This is not a TLS termination failure because neither Nginx Stream nor `vpso-mux` decrypts and does not terminate TLS.

TCP Peek Common boundaries:

| phenomenon | Reason | processing direction |
| --- | --- | --- |
| `no_sni` times increased | The client does not have SNI, or the connection is not standard TLS ClientHello | Confirm the client node domain/SNI settings; non-TLS traffic will go through the default backend |
| Default backend hit | SNI does not match any route, or SNI fails to parse | Check the routes in `/etc/vps-optimize/vpso-mux.yaml` and the actual client SNI |
| Web domain blocked | This Web route is configured with a whitelist, and the source IP is not within the range. | Check the Web whitelist of the corresponding domain, do not regard it as the Xray node limit |
| `copy_fallback` increase | splice is not used or is rolled back during operation copy | Generally, it does not affect availability; if you need to observe performance stably, you can keep the default fallback first. |
| `backend_dial_errors` increase | SNI The rule was hit, but the target local backend connection failed. | Check Caddy / Xray / 3x-ui local listening port |
| `peek_errors` increase | An exception occurred when parsing or reading ClientHello | Check for unusual clients, scan traffic, or excessively large handshakes |
| `peek_timeouts` increase | A connection did not issue a complete ClientHello within the timeout period | Check for slow connections, probe traffic, or unusual clients |
| `rejected_connections` increase | The connection limit is reached, peek times out, or is blocked by the whitelist | Look at `recent_errors` and route hits before deciding whether to adjust the client or connection limit |
| Forwarded bytes are always 0 | The connection entered the portal but did not complete effective bidirectional forwarding. | Combine route hits, backend dial-up errors and logs to continue locating |
| Backend connection failed | SNI The rule is hit, but the local backend port is not listening or the address is inconsistent. | Check whether the local listening port of Caddy / Xray / 3x-ui is consistent with the value saved in the script |
