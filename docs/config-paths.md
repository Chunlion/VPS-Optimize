# 配置文件与数据目录

这份文档用于排错、备份和迁移时快速定位文件。路径会随系统、第三方安装器和用户自定义配置略有差异，实际以当前机器为准。

本文菜单路径按“主菜单 [编号 菜单文案] -> [子编号 菜单文案]”格式书写。

## 先看菜单入口

| 目标 | 菜单路径 |
|---|---|
| 创建全量配置备份 | `主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]` |
| 查看备份列表 | `主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]` |
| 从备份回滚 | `主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]` |
| 443 链路体检 | `主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]` |
| Caddy/证书体检 | `主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护] -> [13 Caddy/证书一键体检]` |
| 生成反馈诊断信息 | `主菜单 [15 服务健康总览]` |

## VPS-Optimize 自身

| 路径 | 说明 |
|---|---|
| `/usr/local/bin/cy` | 主脚本快捷入口 |
| 当前目录的 `vps.sh` | 手动下载运行时的脚本文件 |
| `/etc/vps-optimize` | VPS-Optimize 配置、备份索引和隔离目录 |
| `/etc/vps-optimize/backups` | 全量备份和 443 单入口备份目录 |
| `/etc/vps-optimize/quarantine` | 隔离目录，脚本尽量把旧配置移入这里而不是直接删除 |

常用检查：

```bash
ls -lah /etc/vps-optimize 2>/dev/null
find /etc/vps-optimize/backups -maxdepth 2 -type d 2>/dev/null
find /etc/vps-optimize/quarantine -maxdepth 2 -type d 2>/dev/null
```

## 443 单入口

| 路径 | 说明 |
|---|---|
| `/etc/vps-optimize/sni-stack.env` | 443 单入口保存的核心参数 |
| `/etc/vps-optimize/sni-stack.last-backup` | 最近一次 443 单入口备份路径记录 |
| `/etc/vps-optimize/backups/sni-stack_*` | 443 单入口自动备份目录 |
| `/etc/nginx/stream.d/vps_sni_*.conf` | Nginx stream SNI 分流配置 |
| `/etc/caddy/conf.d/<domain>.caddy` | Caddy 单域名反代配置 |
| `/etc/caddy/certs/<domain>.crt` | Caddy 使用的证书链 |
| `/etc/caddy/certs/<domain>.key` | Caddy 使用的私钥 |
| `/root/cert/<domain>.crt` | 面向用户查看的证书软链接 |
| `/root/cert/<domain>.key` | 面向用户查看的私钥软链接 |
| `/root/cert/caddy_cf_manifest.txt` | 已管理域名和证书路径清单 |
| `/root/cert/acme_last_error.log` | 最近一次 acme 错误日志，存在时再看 |

检查当前 443 参数：

```bash
grep -E '^(PANEL_DOMAIN|PANEL_WEB_PATH|REALITY_SNI|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_PORT|XRAY_LISTEN_PORT|SUB_URI_PATH|CLASH_URI_PATH)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
```

检查 Nginx / Caddy：

```bash
nginx -t
caddy validate --config /etc/caddy/Caddyfile
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
```

相关入口：

```text
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
主菜单 [19 443 单入口管理中心] -> [4 重新应用上次配置]
主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护]
```

## Caddy

| 路径 | 说明 |
|---|---|
| `/etc/caddy/Caddyfile` | Caddy 主配置 |
| `/etc/caddy/conf.d` | VPS-Optimize 推荐的模块化站点配置目录 |
| `/etc/caddy/conf.d/*.caddy` | 每个域名的反代配置 |
| `/etc/caddy/certs` | DNS 签发后写入的证书目录 |
| `/etc/caddy/Caddyfile.bak_*` | 脚本或手动修改前的备份 |
| `/etc/caddy/conf.d_quarantine_*` | 旧配置隔离目录，名称可能带时间戳 |

常用命令：

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl status caddy --no-pager
journalctl -u caddy -n 100 --no-pager
find /etc/caddy -maxdepth 3 -type f
```

如果只是普通反代，入口是：

```text
主菜单 [3 基础组件与反代分流] -> [13 普通 Caddy 反代]
```

如果已经启用 443 单入口，新增网站入口是：

```text
主菜单 [19 443 单入口管理中心] -> [2 管理网站/反代域名]
```

## Nginx

| 路径 | 说明 |
|---|---|
| `/etc/nginx/nginx.conf` | Nginx 主配置 |
| `/etc/nginx/stream.d` | 443 单入口 stream 配置目录 |
| `/etc/nginx/stream.d/vps_sni_*.conf` | 443 单入口 SNI 分流配置 |
| `/etc/nginx/conf.d/00-vps-default-drop.conf` | 默认丢弃站点配置，存在时用于减少默认站点暴露 |
| `/etc/nginx/conf.d` | 传统 Nginx HTTP 配置目录 |
| `/etc/nginx/sites-enabled` | Debian/Ubuntu 常见站点启用目录 |
| `/etc/nginx/sites-available` | Debian/Ubuntu 常见站点可用目录 |

常用命令：

```bash
nginx -t
systemctl status nginx --no-pager
journalctl -u nginx -n 100 --no-pager
grep -R "listen" /etc/nginx 2>/dev/null
```

443 单入口模式下，公网 `443` 只应由 Nginx stream 监听。

## Cloudflare Token

| 路径 | 说明 |
|---|---|
| `/root/.config/vps-panel/cloudflare.env` | Cloudflare Token 保存位置 |

权限建议：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

文件权限应尽量保持仅 root 可读：

```bash
ls -l /root/.config/vps-panel/cloudflare.env 2>/dev/null
```

不要把文件内容贴到 Issue 或公开聊天里。

更新入口：

```text
主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护] -> [8 更新 Cloudflare API Token]
```

## 3x-ui / x-ui

常见官方安装器路径：

| 路径 | 说明 |
|---|---|
| `/etc/x-ui/x-ui.db` | 面板 SQLite 数据库 |
| `/etc/x-ui` | 面板配置目录 |
| `/usr/local/x-ui` | 面板程序目录 |
| `x-ui` systemd 服务 | 常见服务名 |

不同 3x-ui 分支可能有差异。先用命令确认：

```bash
systemctl status x-ui --no-pager
find /etc -maxdepth 3 -name 'x-ui.db' 2>/dev/null
find /usr/local -maxdepth 3 -type d -name '*x-ui*' 2>/dev/null
```

VPS-Optimize 入口：

```text
主菜单 [4 面板、节点与订阅工具] -> [1 管理 3x-ui 面板]
主菜单 [4 面板、节点与订阅工具] -> [11 面板救砖 / SSL 清理]
```

## 3x-ui 外置增强管理

`xui-custom-manager.sh` 默认路径：

| 路径 | 说明 |
|---|---|
| `/etc/xui-custom-manager.conf` | 外置管理器配置 profile |
| `/etc/xui-custom-reset.json` | 自定义重置规则配置 |
| `/root/x-ui-backups` | 数据库、配置目录、程序目录备份 |
| `/var/log/xui-custom-manager.log` | 外置管理器日志 |
| `/var/lib/xui-custom-manager/reset-state.json` | 每月重置状态文件 |
| `/etc/systemd/system/xui-custom-reset.service` | 自动检查 service |
| `/etc/systemd/system/xui-custom-reset.timer` | 自动检查 timer |
| `/usr/local/bin/xui-custom-manager.sh` | 本地稳定执行器 |
| `/usr/local/bin/xcm` | 手动快捷入口 |
| `/usr/local/lib/xui-custom-manager` | `xcm` 的远程脚本缓存目录 |

常用命令：

```bash
systemctl status xui-custom-reset.timer --no-pager
journalctl -u xui-custom-reset.service -n 100 --no-pager
tail -n 100 /var/log/xui-custom-manager.log 2>/dev/null
```

入口：

```text
主菜单 [4 面板、节点与订阅工具] -> [16 3x-ui 外置增强管理]
```

详细说明见 [../README_xui_custom_manager.md](../README_xui_custom_manager.md)。

## Docker 和订阅工具

常见路径：

| 路径 | 说明 |
|---|---|
| `/opt/sublinkpro` | SublinkPro 部署目录 |
| `/opt/miaomiaowu` | 妙妙屋订阅管理部署目录 |
| `/opt/sub-store` | Sub-Store 部署目录 |
| `/opt/dockge` | Dockge 部署目录 |
| `/opt/komari` | Komari 部署目录 |
| `/opt/komari/data` | Komari 数据目录 |

实际路径以脚本输出和 `docker ps` 为准。

常用命令：

```bash
docker ps
docker compose ls 2>/dev/null || true
find /opt -maxdepth 3 -name 'docker-compose.yml' -o -name 'compose.yml' 2>/dev/null
```

入口：

```text
主菜单 [3 基础组件与反代分流] -> [1 Docker 引擎]
主菜单 [4 面板、节点与订阅工具]
主菜单 [11 Docker 安全管理]
```

## Port Traffic Dog

`dog.sh` 默认路径：

| 路径 | 说明 |
|---|---|
| `/etc/port-traffic-dog/config.json` | 主配置 |
| `/etc/port-traffic-dog/traffic_data.json` | 流量统计数据 |
| `/etc/port-traffic-dog/daily_usage.json` | 日报数据 |
| `/etc/port-traffic-dog/daily_snapshot_state.json` | 日快照状态 |
| `/etc/port-traffic-dog/logs/traffic.log` | 日志 |
| `/usr/local/bin/port-traffic-dog.sh` | 本地脚本路径，存在时用于定时任务 |

它还会使用：

| 项目 | 说明 |
|---|---|
| `nftables` | 端口流量计数 |
| `tc` | 限速 |
| `cron` | 开机恢复、定时保存、日报快照、月度重置 |
| `conntrack` | 清理连接状态 |

检查：

```bash
ls -lah /etc/port-traffic-dog 2>/dev/null
crontab -l 2>/dev/null | grep -E 'port-traffic-dog|dog' || true
nft list ruleset 2>/dev/null | grep -i port_traffic_monitor || true
```

入口：

```text
主菜单 [4 面板、节点与订阅工具] -> [14 端口流量监控]
```

详细说明见 [../README_dog.md](../README_dog.md)。

## SSH、防火墙、Fail2ban

| 路径或服务 | 说明 |
|---|---|
| `/etc/ssh/sshd_config` | SSH 服务配置 |
| `ssh` / `sshd` systemd 服务 | 不同系统服务名不同 |
| `ufw` | Ubuntu/Debian 常见防火墙前端 |
| `firewalld` | RHEL 系常见防火墙 |
| `/etc/fail2ban/jail.local` | Fail2ban 本地规则 |
| `fail2ban` systemd 服务 | Fail2ban 服务 |

常用命令：

```bash
sshd -t
systemctl status ssh --no-pager || systemctl status sshd --no-pager
ufw status numbered 2>/dev/null || firewall-cmd --list-ports
systemctl status fail2ban --no-pager
fail2ban-client status sshd 2>/dev/null || fail2ban-client status ssh 2>/dev/null
```

入口：

```text
主菜单 [5 SSH 安全加固]
主菜单 [6 添加 SSH 公钥]
主菜单 [7 Fail2ban 防爆破]
主菜单 [8 防火墙规则管理]
```

## 日志速查

| 目标 | 命令 |
|---|---|
| Nginx | `journalctl -u nginx -n 100 --no-pager` |
| Caddy | `journalctl -u caddy -n 100 --no-pager` |
| x-ui | `journalctl -u x-ui -n 100 --no-pager` |
| Docker | `journalctl -u docker -n 100 --no-pager` |
| Fail2ban | `journalctl -u fail2ban -n 100 --no-pager` |
| xui-custom-manager timer | `journalctl -u xui-custom-reset.service -n 100 --no-pager` |
| Port Traffic Dog | `tail -n 100 /etc/port-traffic-dog/logs/traffic.log` |

## 敏感信息

不要公开分享：

| 内容 | 常见位置 |
|---|---|
| Cloudflare Token | `/root/.config/vps-panel/cloudflare.env` |
| 证书私钥 | `/etc/caddy/certs/*.key`、`/root/cert/*.key` |
| 3x-ui 数据库 | `/etc/x-ui/x-ui.db` |
| 订阅密钥 | 面板数据库、订阅链接 |
| Telegram Bot Token | Port Traffic Dog 配置 |
| SSH 私钥 | 用户自己的本地机器或服务器 |

提交 Issue 前先脱敏。诊断信息入口：

```text
主菜单 [15 服务健康总览]
```
