# 安装与使用路线

这篇文档是第一次使用 VPS-Optimize 时的总路线。它不替代详细教程，而是先帮你判断自己属于哪种安装场景，再把菜单入口、准备材料、验证和回滚顺序写清楚。

菜单路径统一写成：

```text
主菜单 [主菜单编号 菜单文案] -> [子菜单编号 菜单文案]
```

例如：

```text
主菜单 [3 基础组件与反代分流] -> [1 Docker 引擎]
主菜单 [4 面板、节点与订阅工具] -> [5 管理 SublinkPro]
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
```

如果菜单文案和本文档不一致，以脚本当前显示为准；完整菜单可看 [docs/menu-map.md](docs/menu-map.md)。

## 安装前准备

| 准备项 | 为什么需要 |
|---|---|
| `root` 权限 | 脚本会安装软件、改服务、写系统配置 |
| VPS 快照 | SSH、防火墙、内核、443 单入口改坏时能整体恢复 |
| 当前 SSH 会话 | 改 SSH、防火墙或 443 前不要关闭当前连接 |
| 云厂商安全组权限 | 系统防火墙放行不等于云安全组放行 |
| VNC / 救援控制台 | SSH 失联时的最后恢复入口 |
| 域名和 DNS 权限 | 443 单入口、Caddy 反代、证书签发需要 |
| Cloudflare API Token | 使用 DNS 签发证书时需要 `Zone.Zone.Read` 和 `Zone.DNS.Edit` |

推荐系统：

| 系统 | 建议 |
|---|---|
| Debian 11/12 | 推荐 |
| Ubuntu 20.04/22.04/24.04 | 推荐 |
| Rocky / Alma / CentOS Stream | 可用，但部分组件依赖软件源 |
| Alpine | 不支持 |
| OpenVZ 老系统 | 不建议做内核和 BBR 相关操作 |

更完整限制见 [docs/compatibility.md](docs/compatibility.md)。

## 下载并运行

在 VPS 上执行：

```bash
sudo -i
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行后会注册快捷命令：

```bash
cy
```

以后直接输入 `cy` 进入主菜单。

## 我是哪种场景

| 当前情况 | 推荐路线 |
|---|---|
| 新买 VPS，还没部署业务 | 先走“新 VPS 初始化”，再部署面板或网站 |
| 已经有 VPS，但只想轻量体检 | 只跑预检和健康检查，不直接改 SSH、防火墙、内核 |
| 想装 3x-ui + REALITY + 443 | 先初始化，再走 3x-ui + 443 教程 |
| 已有 3x-ui，想接入公网 443 | 先看迁移文档，备份后接入 443 单入口 |
| 已有 Caddy/Nginx 网站占用 443 | 先盘点旧站点，再迁移到 443 单入口 |
| 只想部署订阅工具 | 先装 Docker，再选普通 Caddy 或 443 单入口 |
| 只想统计端口流量 | 单独运行 `dog.sh` 或从主菜单进入端口流量监控 |

## 路线一：新 VPS 初始化

适合刚买的机器。目标是先把 SSH、防火墙、基础工具、时间同步、备份这些基础做好。

推荐顺序：

```text
主菜单 [1 运维预检与风险扫描]
主菜单 [2 基础环境初始化]
主菜单 [5 SSH 安全加固]
主菜单 [6 添加 SSH 公钥]
主菜单 [7 Fail2ban 防爆破]
主菜单 [8 防火墙规则管理]
主菜单 [10 网络与内核优化]
主菜单 [15 服务健康总览]
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

也可以走新手向导：

```text
主菜单 [n 新手向导] -> [1 新机器初始化]
```

详细步骤见 [tutorials/01-new-vps-hardening.md](tutorials/01-new-vps-hardening.md)。

完成后验证：

```bash
date -Is
ss -lntp
systemctl --failed --no-pager
systemctl status ssh --no-pager || systemctl status sshd --no-pager
```

再进：

```text
主菜单 [15 服务健康总览]
主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]
```

## 路线二：部署 3x-ui + REALITY + 443

适合新机器部署节点面板，或者已有 3x-ui 想统一接入公网 `443`。

先准备：

| 项目 | 示例 |
|---|---|
| 面板域名 | `panel.example.com` |
| 节点域名 | `node.example.com` |
| REALITY 伪装 SNI | `www.microsoft.com` 这类外部真实 HTTPS 站点 |
| Cloudflare API Token | `Zone.Zone.Read`、`Zone.DNS.Edit` |
| VPS 快照 | 云厂商控制台创建 |

推荐入口：

```text
主菜单 [1 运维预检与风险扫描]
主菜单 [4 面板、节点与订阅工具] -> [1 管理 3x-ui 面板]
主菜单 [19 443 单入口管理中心] -> [1 首次配置 443 单入口]
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

完整步骤必须看 [tutorials/02-3x-ui-reality-443.md](tutorials/02-3x-ui-reality-443.md) 和 [docs/443-single-entry.md](docs/443-single-entry.md)。这里不提供“简化版 443 教程”，因为 443 单入口要同时处理证书、Caddy、Nginx stream、3x-ui 监听、订阅路径和 REALITY SNI，省步骤容易让用户无法完整复刻。

成功后的状态应该是：

| 组件 | 期望 |
|---|---|
| 公网 `443` | 只由 Nginx stream 监听 |
| Caddy | `127.0.0.1:8443` |
| 3x-ui 面板 | `127.0.0.1:40000`，关闭自带 HTTPS |
| 3x-ui 订阅 | `127.0.0.1:2096`，由 Caddy 代理 |
| REALITY 入站 | `127.0.0.1:1443` |
| 面板访问 | `https://panel.example.com/panel/` |
| 订阅访问 | `https://panel.example.com/sub/...` 或 `https://panel.example.com/clash/...` |

## 路线三：已有服务器迁移

适合机器上已经有 Caddy、Nginx、3x-ui、网站或订阅工具。

不要直接重跑首次配置。先看 [docs/existing-server-migration.md](docs/existing-server-migration.md)，把这些东西盘点出来：

```bash
ss -lntp
systemctl status caddy nginx x-ui --no-pager
find /etc/caddy -maxdepth 3 -type f 2>/dev/null
find /etc/nginx -maxdepth 3 -type f 2>/dev/null
docker ps
```

迁移前先备份：

```text
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

已有站点迁移到 443 单入口后，新增或补录网站走：

```text
主菜单 [19 443 单入口管理中心] -> [2 管理网站/反代域名]
```

不要为了新增网站反复运行：

```text
主菜单 [19 443 单入口管理中心] -> [1 首次配置 443 单入口]
```

## 路线四：订阅工具接入 HTTPS

适合 SublinkPro、Sub-Store、妙妙屋订阅管理、Dockge 等 Docker Compose 项目。

先安装 Docker：

```text
主菜单 [3 基础组件与反代分流] -> [1 Docker 引擎]
```

再进入工具菜单：

```text
主菜单 [4 面板、节点与订阅工具]
```

常用入口：

| 工具 | 菜单路径 |
|---|---|
| SublinkPro | `主菜单 [4 面板、节点与订阅工具] -> [5 管理 SublinkPro]` |
| 妙妙屋订阅管理 | `主菜单 [4 面板、节点与订阅工具] -> [6 管理 妙妙屋订阅管理]` |
| Sub-Store | `主菜单 [4 面板、节点与订阅工具] -> [7 管理 Sub-Store]` |
| Dockge | `主菜单 [4 面板、节点与订阅工具] -> [8 管理 Dockge]` |

没有启用 443 单入口时，可以走普通 Caddy：

```text
主菜单 [3 基础组件与反代分流] -> [13 普通 Caddy 反代]
```

已经启用 443 单入口时，新增域名走：

```text
主菜单 [19 443 单入口管理中心] -> [2 管理网站/反代域名]
```

详细步骤见 [tutorials/03-subscription-tools-with-caddy.md](tutorials/03-subscription-tools-with-caddy.md)。

## 路线五：只看端口流量

可以单独运行：

```bash
wget -qO dog.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh && chmod +x dog.sh && ./dog.sh
```

也可以从主脚本进入：

```text
主菜单 [4 面板、节点与订阅工具] -> [14 端口流量监控]
```

详细说明见 [README_dog.md](README_dog.md)。

## 常用验证入口

| 目标 | 菜单路径 |
|---|---|
| 看系统、DNS、端口、资源 | `主菜单 [1 运维预检与风险扫描]` |
| 看服务、证书、端口总览 | `主菜单 [15 服务健康总览]` |
| 排查端口占用 | `主菜单 [13 端口排查与释放]` |
| 443 链路体检 | `主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]` |
| Caddy/证书体检 | `主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护] -> [13 Caddy/证书一键体检]` |
| 创建备份 | `主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]` |
| 查看备份 | `主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]` |

## 失败时先看哪里

| 问题 | 优先文档 |
|---|---|
| SSH 断开、防火墙误封、服务起不来 | [docs/recovery-runbook.md](docs/recovery-runbook.md) |
| 443、证书、Caddy、REALITY 异常 | [docs/443-single-entry-troubleshooting.md](docs/443-single-entry-troubleshooting.md) |
| 已有站点或面板迁移 | [docs/existing-server-migration.md](docs/existing-server-migration.md) |
| 找不到菜单入口 | [docs/menu-map.md](docs/menu-map.md) |
| 不确定系统是否支持 | [docs/compatibility.md](docs/compatibility.md) |
| 想知道配置和备份在哪里 | [docs/config-paths.md](docs/config-paths.md) |
