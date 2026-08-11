---
title: 3x-ui+Reality：443端口复用部署指南
search: false
outline: false
prev: false
next: false
---

# 3x-ui+Reality 教程已合并

3x-ui、REALITY、面板、订阅和三种 443 入口模式的部署步骤已统一到 [443端口复用：部署与配置](../docs/443-single-entry.md)。本页仅用于兼容旧链接。

版本提示：

- 3x-ui v3.4.0 及之后：打开 `Hosts / 主机`，新增 Host
- 3x-ui v3.3.1 及之前：在 REALITY 入站里打开 `External Proxy`

兼容说明：

`panel.example.com  -> 当前 Web 反代引擎（Caddy 或 Nginx，例如 127.0.0.1:8443）`

如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本只在兼容读取旧配置时按 `nginx-stream` 处理。
