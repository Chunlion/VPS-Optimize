# Subscription management and node tools

Entries related to nodes and subscriptions are concentrated in:

```text
Main menu [5 panel、Nodes and subscription tools]
```

## Contains content

This entry manages related tools such as 3x-ui, S-UI, 2S-UI, Sing-box, Xray, SublinkPro, Sub-Store, Dockge, Komari, CDT Monitor, the dog.sh traffic monitor, and the x-ui extension.

CDT Monitor is at `[5 Panels, Nodes and Subscription Tools] -> [16 CDT Monitor]`. It monitors Alibaba Cloud CDT traffic, manages ECS automation, and shows costs. See [CDT Monitor](cdt-monitor.md).

## Deployment recommendations

The subscription tool is recommended to be deployed in the manner of "local binding + Caddy/Nginx/443 external". Newly deployed subscription tools are bound to `127.0.0.1` first by default.

After enabling the Port 443 Reuse, it is recommended to add the Internet HTTPS domain through the following entry:

```text
Main menu [19 Port 443 Reuse manager] -> [8 management Web domains / reverse proxy]
```

When the Port 443 Reuse is not enabled, a standalone reverse proxy portal can be used:

```text
Main menu [4 reverse proxy]
```

For detailed scenarios, see [Subscription Tool Access Caddy/Nginx reverse proxy and Port 443 Reuse](../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md).
