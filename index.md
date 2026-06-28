# VPS-Optimize 文档

VPS-Optimize 是一个面向 VPS 日常运维的 Bash 控制面板，通过 `cy` 命令集中处理系统初始化、安全加固、面板部署、443 单入口、订阅工具、备份回滚和故障排查。

## 快速入口

| 目标 | 文档 |
|---|---|
| 直接安装运行 | [快速开始](quick-start.md) |
| 运行前确认风险 | [使用前必读](docs/before-use.md) |
| 查看支持系统 | [支持系统](docs/supported-systems.md) |
| 更新或卸载 | [更新与卸载](docs/update-uninstall.md) |
| 常见问题 | [常见问题](docs/faq.md) |

## 443 单入口

| 目标 | 文档 |
|---|---|
| 配置 443 单入口 | [443 单入口分流教程](docs/443-single-entry.md) |
| 排查 443 问题 | [443 单入口排错手册](docs/443-single-entry-troubleshooting.md) |
| 了解 TCP Peek / vpso-mux | [443 单入口技术实现](docs/443-tcp-peek-engine.md) |
| 迁移已有服务器 | [已有服务器迁移到 443 单入口](docs/existing-server-migration.md) |

## 场景教程

| 场景 | 文档 |
|---|---|
| 3x-ui + REALITY + 443 | [3x-ui + REALITY + 443 单入口部署](tutorials/01-3x-ui-reality-443.md) |
| 订阅工具 HTTPS 接入 | [订阅工具接入 Caddy/Nginx 反代与 443 单入口](tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md) |

## 工具与维护

| 目标 | 文档 |
|---|---|
| 查看配置路径 | [配置文件与数据目录](docs/config-paths.md) |
| 管理订阅与节点工具 | [订阅管理与节点工具](docs/subscription-tools.md) |
| 查看端口流量 | [端口流量狗 dog.sh](docs/dog.md) |
| 使用 x-ui 增强套件 | [x-ui 增强套件 xui-custom-manager.sh 使用说明](docs/xui-custom-manager.md) |
| 处理安全与回滚 | [安全与回滚](docs/security-rollback.md) |
| 失联或复杂故障急救 | [失联与回滚急救手册](docs/recovery-runbook.md) |
