# CDT Monitor

[CDT Monitor](https://github.com/wang4386/CDT-Monitor) is a console for Alibaba Cloud CDT traffic monitoring, ECS automation, and cost visibility. VPS-Optimize deploys the official GHCR image through Docker Compose.

## Install and access

Install or manage it from:

```text
Main menu [5 Panels, Nodes and Subscription Tools] -> [16 CDT Monitor]
```

It listens on `127.0.0.1:43210` by default. Its Compose configuration is at `/opt/cdt-monitor/docker-compose.yml`; the first visit opens the administrator setup wizard.

For public HTTPS, configure Caddy or Nginx from main menu `[4 Reverse proxy]`. With Port 443 Reuse enabled, use `[19 Port 443 Reuse Manager] -> [8 Manage Web domains/reverse proxy]`. Do not expose the management port directly to the internet.

## Console configuration

In the console, add Alibaba Cloud RAM accounts, regions, and ECS instances, then configure CDT traffic thresholds and their stop or notification actions. You can also configure scheduled power actions, cost visibility, and SMTP, Telegram Bot, or Webhook notifications.

Grant RAM users only the minimum permissions required for CDT queries, ECS queries and power actions, plus optional BSS queries.

## Migrating from the legacy watchdog

The legacy `aliyun-cdt-watchdog.sh` has been removed. CDT Monitor does not import its configuration automatically. Configure the RAM credentials, instances, and traffic thresholds again in the new console, then remove the old `aliyun-cdt-watchdog` systemd service, timer, and deployment directory only after the new rules are active.

## Data and archiving

CDT Monitor stores its SQLite database and `master.key` in the Docker Compose `cdt-data` volume. Archiving the CDT Monitor deployment deletes this volume. Back up the full volume first, or encrypted credentials cannot be recovered.
