# Before You Begin

Selected features may change system services, firewall rules, kernel parameters, reverse proxies, Docker, and certificates. Check your backup coverage and recovery options before running them.

::: warning Keep recovery access available
Keep the current SSH session open and prepare a VPS snapshot or provider rescue console. After changing the SSH port, verify access in a new session before closing the old one.
:::

## Basic principles

1. Run the script as `root`.
2. Before modifying the SSH port, allow the new port in your cloud provider’s security group.
3. Preserve the current SSH session before high-risk operations.
4. Confirm the current listener of the public port `443` before enabling Port 443 Reuse.
5. When you are not sure about the source of the configuration, back it up first and then modify it.

## Cloud security groups and system firewall

The cloud security group and the server firewall are separate layers. The script can manage `ufw`, `firewalld`, `iptables` or `ip6tables` related rules in the system, but it cannot open the security group in the cloud provider console for you.

Before modifying the SSH, firewall, Port 443 Reuse, certificate, and reverse proxy configurations, first confirm that the cloud security group allows the necessary ports.

## Port 443 Reuse considerations

Only the service for the selected entry mode should listen on public port `443`:

| Entry mode | public port `443` listener |
|---|---|
| `nginx-stream` | Nginx stream |
| `tcp-peek` | `tcppeek` / `vpso-mux` |
| `xray-fallback` | Xray main inbound |

On a single VPS, Web backends, the 3x-ui panel, subscription services, and Xray inbounds behind the entry service normally listen on `127.0.0.1`. In `xray-fallback` mode, the main Xray inbound is the public entry and must listen on public port `443`.

## Port connection restrictions

The port concurrent connection limit takes effect based on the public internet port and source IP. When setting restrictions on the public port `443`, it restricts the entire 443 entry and cannot be precise to a specific SNI, inbound, UUID or user.
