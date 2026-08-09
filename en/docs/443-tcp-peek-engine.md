# Shared Port 443 Entry Implementations

This article explains three shared port 443 point implementations of VPS-Optimize: Nginx Stream default stable implementation, TCP Peek + Splice / vpso-mux same configuration implementation, Xray Fallback special implementation.

`panel.example.com`, `site.example.com`, `node.example.com`, `SERVER_IP`, `8443`, `8444`, and `1443` in the example are all example values and are only used to illustrate the link relationship. During actual deployment, please replace it with your real domain, server IP and port where the script is currently saved.

## common configuration boundaries

The three entry modes share the same set of public configurations:

- Web domains, Web reverse proxy engine backend mappings, and certificates are shared; the Web whitelist is only shared between Nginx Stream and TCP Peek.
- The certificate still uses the existing `acme.sh + Cloudflare DNS API` process, does not introduce the Caddy DNS module, and does not use `xcaddy`.
- The web whitelist only protects web domains and is not used to limit Xray node traffic.
- 443 The Web reverse proxy engine under shared entry can choose Caddy or Nginx, and the same configuration can be reused when switching the entry mode.
- When using Nginx Stream or TCP Peek, the web whitelist takes effect at the entry layer as `SNI + source IP`; `xray-fallback` does not allow new, reserved or applied web whitelists regardless of whether Caddy or Nginx local web reverse proxy is selected.
- Only one service can listen to the public port `443`: `nginx`, `xray` or `vpso-mux`.
- If `/etc/vps-optimize/sni-stack.env` does not have `ENTRY_MODE`, it will be processed as `nginx-stream` compatible.
- `engine` of `ENTRY_MODE` and `/etc/vps-optimize/443-engine.conf` are written uniformly to `nginx-stream`, `xray-fallback`, and `tcp-peek`. `nginx_stream`, `xray_fallback`, and `tcp_peek` written in the old version are only reserved as read-compatible aliases; a single simple assignment will be automatically rewritten to a new name. If it cannot be safely rewritten, the status page will continue to prompt.

Common menu paths:

```text
Main menu [19 443 shared entry manager]
  -> [2] initial setup/installation 443 shared entry
  -> [3] switch to Nginx Stream mode
  -> [4] switch to Xray Fallback mode
  -> [5] switch to TCP Peek + Splice mode
  -> [7] Roll back the last entry-mode switch
  -> [16] View TCP Peek + Splice Status / 8444 Preflight
  -> [17] TCP Peek routing rule validation
  -> [18] View TCP Peek + Splice Log
```

For the specific filling methods of 3x-ui panel, subscription and Xray inbound, please refer to "3x-ui Three Entry Mode Configuration Quick Check" of [shared port 443 routing Tutorial](443-single-entry.md). Here is the conclusion first:

| ENTRY_MODE | How to bind 3x-ui/Xray | The most important considerations when switching |
| --- | --- | --- |
| `nginx-stream` | Panels, subscriptions, and Xray inbound all listen on the `127.0.0.1` local port | 3x-ui/Xray Do not directly occupy the public port `443` |
| `tcp-peek` | Same as `nginx-stream`, still a local port | The configuration process is the same; public port `443` only changes from `nginx` to `vpso-mux` |
| `xray-fallback` | Requires a 3x-ui/Xray primary inbound connection to bind the Internet `443` and fallback to the web reverse proxy engine local port | Before switching back to other modes, the main inbound Xray must be moved from the public port `443` |

## Nginx Stream default stable implementation

Nginx Stream is the default stable mode. Internet `443` is bound by Nginx stream. Use `ssl_preread` to read SNI in TLS ClientHello, but does not terminate TLS and does not decrypt the traffic.

```text
public port `443`
  -> Nginx stream ssl_preread
  -> panel/site/sub SNI  -> Caddy/Nginx local Web reverse proxy TLS
  -> Xray/REALITY SNI   -> Xray/3x-ui local inbound
  -> unknown SNI        -> Default Xray/REALITY backend
```

This implementation has the most complete coverage and is suitable as a long-term default entry. It is responsible for stable access to the web reverse proxy engine, REALITY, panels, subscriptions, websites, web whitelists and rollback processes.

## TCP Peek + Splice / vpso-mux implementation

TCP Peek + Splice / vpso-mux and Nginx Stream use the same set of 443 shared entry configuration. There is no need to create a new set of web domains, certificates, web reverse proxy engine backends, web whitelists, and Xray SNI routing records; 3x-ui panels, subscriptions, and Xray inbound connections are still filled in according to local bindings. When using it for the first time, run `Main menu [19 443 Shared entry management center] -> [16] View TCP Peek + Splice Status / 8444 Check before switching` first to confirm that `vpso-mux` can start and forward in `8444`; then run `[17] TCP Peek Routing rule verification`. Only when the user subsequently executes `[5] switch to TCP Peek + Splice mode` will the Internet `443` be switched from Nginx Stream to `vpso-mux`.

`vpso-mux` uses `MSG_PEEK` to view SNI in TLS ClientHello without consuming the first packet; the ClientHello received by the backend is still consistent with the client's original data. For forwarding, splice is used first, and ordinary copy is fallbacked when it fails or is unavailable.

### Connection life cycle of TCP Peek

After a client connection enters `vpso-mux`, it is processed roughly in the following order:

```text
client TCP connect
  -> vpso-mux accept
  -> recv(MSG_PEEK) Only view what is in the receive buffer ClientHello
  -> from ClientHello Analysis in extension SNI
  -> route by SNI Heyuan IP Whitelist selection backend
  -> dial Backend local port
  -> Forward original in both directions TCP byte stream
```

The most critical thing here is `MSG_PEEK`. Ordinary `recv` will take the data from the socket receiving buffer, and the first packet that has been read needs to be rewritten to the backend during subsequent forwarding; `MSG_PEEK` just "takes a look" and will not move the reading position. Therefore, after `vpso-mux` parses SNI, the TLS ClientHello sent by the client still remains in the original socket buffer. After the backend connection is established, the first batch of bytes forwarded is still the client's original ClientHello.

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

The script generates `/etc/vps-optimize/vpso-mux.yaml` based on the shared port 443 shared configuration. The generated routes are roughly divided into several categories:

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
| `copy` | Go process forwards data using ordinary read and write cycles | Fallback path when splice is unavailable, fails or is closed |

The default configuration is:

```yaml
splice:
  enabled: true
  pipe_size: 1048576
  fallback_to_copy: true
```

In other words, `vpso-mux` will try splice first. If the current kernel, socket status or operating environment is not suitable for splice, and `fallback_to_copy` is `true`, it will automatically fall back to normal copy. copy is not an error, it just lacks zero-copy optimization; the status page or `copy_fallback` in `status.json` can be used to observe whether there are frequent rollbacks.

It should be noted that splice optimizes "byte forwarding after the selected backend" and does not change the routing logic. The SNI judgment still occurs in the ClientHello phase at the beginning of the connection; once the backend is selected, subsequent TCP connections will not be rerouted based on the content.

The splice path will also be controlled by `timeouts.idle`. `vpso-mux` uses non-blocking splice and waits for readable/writable events before reading and writing file descriptors; if the connection has no data for a long time, it will be closed according to the idle timeout instead of letting the idle connection occupy the forwarding goroutine. The copy path continues to use normal read and write deadlines.

### Concurrency protection and status refresh

`vpso-mux` has built-in connection concurrency protection. The new configuration generated by the script will write:

```yaml
limits:
  max_connections: 4096
```

The old `vpso-mux.yaml` even without the `limits` field will automatically use the same default value by the program; users do not need to manually migrate the configuration. If you really want to turn off this restriction, you can set `max_connections` to `0`, which means there is no limit on the number of connections within the program.

The slow handshake is also protected: if the client does not send a complete ClientHello within the `timeouts.peek` time after connecting, `vpso-mux` will close the connection instead of forwarding it to the default Xray/REALITY backend. The default `timeouts.peek` is `3s`, and normal browsers and proxy clients will not perceive this change.

The running status is written to `/var/lib/vps-optimize/vpso-mux/status.json`. The new version no longer writes to disk immediately for each connection. Instead, it saves the count in memory and refreshes it regularly, and writes it again before exiting. The status page will display the current number of connections, the upper limit of connections, the number of rejected connections, backend dialing errors, peek errors, peek timeouts, and the number of bidirectional forwarded bytes, making it easy to determine whether there is a connection flood, slow handshake occupation, or backend port exception.

### Route index

`vpso-mux` will precompile the routing index after the configuration validation passes. Exact SNI uses map query, and wildcard SNI remains as an ordered list; the matching semantics remain unchanged, exact matching still takes precedence over wildcard matching, and wildcard matching maintains the order in the configuration. This optimization will not change the `vpso-mux.yaml` format, nor will it require users to refill the domain.

Main advantages of TCP Peek:

- The configuration process is the same as Nginx Stream. The saved domain, certificate, Web reverse proxy engine backend, Web whitelist and Xray SNI routing are reused during switching.
- `MSG_PEEK` only checks ClientHello and does not consume the first packet. What the backend receives is still the client’s original TLS handshake data.
- For forwarding, splice is used first to reduce user-mode data copy; when it is unavailable, it automatically falls back to ordinary copy.
- `vpso-mux` is an entry program specially prepared for 443 SNI routing. Status, logs, configuration validation and 8444 pre-switching checks all revolve around this link.

The `vpso-mux.yaml` generated by TCP Peek will only write one listening item according to the public internet listening address saved by the script. By default, `0.0.0.0:443` only listens to IPv4; if you clearly need the IPv6 entry, please set the public internet listening address to `::` and then regenerate the configuration to avoid dual-stack binding conflicts caused by writing `0.0.0.0` and `[::]` at the same time on the same port.

```text
public port `443`
  -> vpso-mux
  -> recv(MSG_PEEK) View TLS ClientHello SNI
  -> route by SNI / whitelist Select backend
  -> splice Two-way forwarding, Fallback on failure copy
```

Core differences from Nginx Stream:

| Project | Nginx Stream | TCP Peek + Splice / vpso-mux |
| --- | --- | --- |
| Configuration process | Use shared port 443 shared configuration | Use the same shared port 443 shared configuration |
| Entry process | `nginx` | `vpso-mux` |
| SNI Get | `ssl_preread` | `MSG_PEEK` parsing ClientHello |
| TLS processing | Do not terminate TLS | Do not terminate TLS |
| Certificate | Current web reverse proxy engine handles web/panel certificates | Current web reverse proxy engine handles web/panel certificates |
| Unknown SNI | Default Xray/REALITY backend | Default Xray/REALITY backend |
| forward | Nginx stream proxy | splice, fallback on failure copy |

View status and logs:

```text
Main menu [19 443 shared entry manager]
  -> [18] View TCP Peek + Splice Log
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

## Xray Fallback special implementation

Xray Fallback is a special mode: Internet `443` is bound by the existing Xray/3x-ui main inbound connection connection, and HTTPS fallback to the current Web reverse proxy engine. This script does not create, delete, or modify the 3x-ui/Xray inbound connection internal configuration.

```text
public port `443`
  -> Xray/3x-ui main inbound
  -> Xray Node traffic is handled inbound by this master
  -> HTTPS fallback Arrive Caddy/Nginx local Web reverse proxy backend
```

In xray-fallback mode, the `Xray Inbound connection management` menu is not available for connecting to SNI routes with multiple local inbound connections. The reason is that the Internet `443` has been taken over by the Xray main inbound connection, and the script currently does not support continuing to route multiple SNI to multiple local Xray inbound connections in this mode. To route multiple local Xray inbound connections, use Nginx Stream mode or TCP Peek + Splice / vpso-mux mode.

## Switch and rollback

Switch to TCP Peek + Splice:

```text
Main menu [19 443 shared entry manager]
  -> [16] View TCP Peek + Splice Status / 8444 Preflight
  -> [17] TCP Peek routing rule validation
  -> [5] switch to TCP Peek + Splice mode
```

The switching process will not automatically download the Go tool chain or remotely compile `vpso-mux` in the Internet `443` switching path. If `/usr/local/bin/vpso-mux` does not exist, the script will reject the switch and require the `8444` pre-switch check of `[16]` to be performed first. Before the official switch, the script will start the independent `vpso-mux-preflight.service` binding `8444` again to confirm that the web reverse proxy engine and Xray local backend are reachable; if the pre-switch check fails, the Internet `443` will not be replaced.

Formal switching will generate and verify `vpso-mux.yaml`, create a backup, isolate the Nginx stream 443 configuration currently managed by VPS-Optimize, start `vpso-mux` to take over the public port `443`, and check that the web reverse proxy engine and Xray local backend are reachable. Automatic rollback is attempted on failure.

`8444` pre-check will do an additional TCP Peek routing matrix check: the panel domain and web domain will obtain the certificate chain through the test port according to SNI; the default Xray/REALITY backend, old TCP/SNI records and The `Xray inbound management` record will check whether the corresponding local address and port are connectable. In this way, problems such as missing certificates, the web reverse proxy engine is not ready, or the local Xray inbound port is not listening can be discovered before the public port `443` is officially taken over.

If the current SSH session is connected to the ingress port, such as `443`, the script will reject the switch to avoid directly disconnecting the current management connection. Please use the cloud provider VNC/Serial Console instead, or log in using the non-entry port SSH first.

Roll back the previous round of entry mode switching:

```text
Main menu [19 443 shared entry manager]
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
