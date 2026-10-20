# Subscription management and node tools

Entries related to nodes and subscriptions are concentrated in:

```text
Main menu [5 Panels, nodes, and subscription tools]
```

## Contains content

This entry manages related tools such as 3x-ui, S-UI, 2S-UI, Sing-box, Xray, xray-relay, SublinkPro, Sub-Store, Dockge, Komari, CDT Monitor, the dog.sh traffic monitor, and the x-ui extension.

Xray relay is at `[5 Panels, nodes, and subscription tools] -> [9 Xray relay (xrelay)]`. It runs the [xray-relay installer](https://raw.githubusercontent.com/Chunlion/xray-relay/main/install.sh) to install or update `xrelay` and open its management menu.

CDT Monitor is at `[5 Panels, nodes, and subscription tools] -> [14 CDT Monitor]`. It monitors Alibaba Cloud CDT traffic, manages ECS automation, and shows costs. See [CDT Monitor](cdt-monitor.md).

## Deployment recommendations

The subscription tool is recommended to be deployed in the manner of "local binding + Caddy/Nginx/443 external". Newly deployed subscription tools are bound to `127.0.0.1` first by default.

After enabling the Port 443 Reuse, it is recommended to add the Internet HTTPS domain through the following entry:

```text
Main menu [19 Port 443 Reuse manager] -> [2 Manage Web domains and reverse proxies]
```

When the Port 443 Reuse is not enabled, a standalone reverse proxy portal can be used:

```text
Main menu [4 Reverse proxy]
```

For detailed scenarios, see [Subscription Tool Access Caddy/Nginx reverse proxy and Port 443 Reuse](../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md).
