# Before You Begin

VPS-Optimize will modify system services, firewalls, kernel parameters, reverse proxy configuration, Docker configuration, certificate files and Port 443 Reuse point related services. The backup and recovery methods must be confirmed before running the production environment.

## basic principles

1. Run the script as `root`.
2. Before modifying the SSH port, first release the new port in the cloud provider security group.
3. Preserve the current SSH session before high-risk operations.
4. Confirm the current listener of the public port `443` before enabling Port 443 Reuse.
5. When you are not sure about the source of the configuration, back it up first and then modify it.

## Cloud security groups and system firewall

The cloud provider security group and system firewall are two-layer rules. The script can manage `ufw`, `firewalld`, `iptables` or `ip6tables` related rules in the system, but it cannot open the security group in the cloud provider console for you.

Before modifying the SSH, firewall, Port 443 Reuse, certificate, and reverse proxy configurations, first confirm that the cloud security group allows the necessary ports.

## Port 443 Reuse considerations

After enabling the Port 443 Reuse, Internet `443` should only be bound by a single service corresponding to the current entry mode at the same time:

| Entry mode | public port `443` listener |
|---|---|
| `nginx-stream` | Nginx stream |
| `tcp-peek` | `tcppeek` / `vpso-mux` |
| `xray-fallback` | Xray main inbound |

Caddy, Nginx local web inverses, 3x-ui panels, subscription services, and local Xray inbound should generally listen to `127.0.0.1`.

## Port connection restrictions

The port concurrent connection limit takes effect based on the public internet port and source IP. When setting restrictions on the public port `443`, it restricts the entire 443 entry and cannot be precise to a specific SNI, inbound, UUID or user.
