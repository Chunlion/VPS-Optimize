---
title: 3x-ui+Reality Port 443 Reuse Deployment Guide
search: false
outline: false
prev: false
next: false
---

# The 3x-ui+Reality guide has moved

Deployment steps for 3x-ui, REALITY, the panel, subscriptions, and all three port 443 entry modes are now consolidated in [Port 443 Reuse: Setup and Configuration](../docs/443-single-entry.md). This page remains available for old links.

Version note:

- 3x-ui v3.4.0 and later: open `Hosts / Host` and add a Host.
- 3x-ui v3.3.1 and earlier: open `External Proxy` in the REALITY inbound.

Compatibility notes:

`panel.example.com -> current Web reverse proxy engine (Caddy or Nginx, for example 127.0.0.1:8443)`

If `/etc/vps-optimize/sni-stack.env` has no `ENTRY_MODE`, the script treats it as `nginx-stream` only when reading the legacy configuration for compatibility.
