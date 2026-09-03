# CDT Monitor

[CDT Monitor](https://github.com/wang4386/CDT-Monitor) 是阿里云 CDT 流量监控、ECS 自动化控制与费用查看控制台。VPS-Optimize 通过 Docker Compose 部署官方 GHCR 镜像。

## 安装与访问

从以下入口安装或管理：

```text
主菜单 [5 面板、节点与订阅工具] -> [16 CDT Monitor]
```

默认监听 `127.0.0.1:43210`，Compose 配置位于 `/opt/cdt-monitor/docker-compose.yml`。首次访问会进入管理员初始化向导。

如需公网 HTTPS，请通过主菜单 `[4 反代]` 配置 Caddy/Nginx；启用 443端口复用后，使用 `[19 443端口复用管理中心] -> [8 管理 Web 域名/反代]`。不要直接暴露管理端口到公网。

## 控制台配置

在控制台中添加阿里云 RAM 账号、地域和 ECS 实例，再设置 CDT 流量阈值及对应的停机或通知动作。可按需配置定时开关机、费用查看和 SMTP、Telegram Bot 或 Webhook 通知。

RAM 用户仅授予 CDT 查询、ECS 查询/启停以及可选 BSS 查询所需的最小权限。

## 旧保活脚本迁移

旧的 `aliyun-cdt-watchdog.sh` 已移除，CDT Monitor 不会自动导入其配置。请在新控制台重新配置 RAM 凭据、实例和流量阈值；确认新规则生效后再清理旧服务器上的 `aliyun-cdt-watchdog` systemd 服务、定时器和部署目录。

## 数据与归档

CDT Monitor 的 SQLite 数据库与 `master.key` 保存在 Docker Compose 的 `cdt-data` 数据卷中。归档 CDT Monitor 部署时会删除该数据卷；归档前必须完整备份数据卷，否则无法恢复已加密的凭据。
