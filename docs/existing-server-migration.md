# 已有服务器迁移到 443 单入口

这篇文档面向已经跑了服务的 VPS：已有 3x-ui、Caddy/Nginx 网站、订阅工具、Docker Compose 项目，想把公网 `443` 统一交给 VPS-Optimize 的 443 单入口。

核心原则：先盘点、再备份、再迁移。不要在不知道旧服务监听什么端口、旧配置在哪里、旧证书怎么签发的情况下直接运行首次配置。

本文菜单路径按“主菜单 [编号 菜单文案] -> [子编号 菜单文案]”格式书写。

## 适合谁

| 当前情况 | 是否适合 |
|---|---|
| 已有 3x-ui，想让面板和订阅走公网 `443` | 适合 |
| 已有 Caddy 网站，想和 3x-ui / REALITY 共用 `443` | 适合 |
| 已有 Nginx/Apache 占用 `443` | 适合，但迁移前必须记录旧站点 |
| 已有 Docker 订阅工具，想加 HTTPS 域名 | 适合 |
| 不知道机器上跑了什么服务 | 先盘点，不要直接迁移 |

## 迁移前准备

| 准备项 | 说明 |
|---|---|
| VPS 快照 | 迁移前必须做 |
| 当前 SSH 会话 | 全程保持不断开 |
| 云厂商安全组 | SSH 端口和 `443/tcp` 已放行 |
| 域名清单 | 面板域名、订阅域名、网站域名、节点域名 |
| 后端清单 | 每个服务的本地监听地址和端口 |
| Cloudflare Token | 用于 DNS 签发证书 |
| 旧配置备份 | Caddy/Nginx/面板/Docker Compose 均要备份 |

## 第一步：盘点现状

先运行：

```text
主菜单 [1 运维预检与风险扫描]
主菜单 [15 服务健康总览]
```

再手动记录：

```bash
ss -lntp
systemctl status caddy nginx apache2 httpd x-ui docker --no-pager
docker ps
```

把下面这张表填出来。表里的域名和端口都是示例值；迁移时请替换成你的实际域名、后端地址和端口。

| 域名 / 服务 | 当前公网入口 | 后端地址 | 后端端口 | 配置位置 | 是否要迁移 |
|---|---|---|---|---|---|
| `panel.example.com` | `:40000` 或 `:443` | `127.0.0.1` | `40000` | 3x-ui 面板 | 是 |
| `sub.example.com` | `:3000` 或 `:443` | `127.0.0.1` | `3000` | Docker / Caddy | 视情况 |
| `site.example.com` | `:443` | `127.0.0.1` | `8080` | Caddy/Nginx | 是 |

重点找谁在占用公网 `443`：

```bash
ss -lntp | grep ':443'
grep -R "listen .*443" /etc/nginx /etc/caddy 2>/dev/null
```

## 第二步：创建备份

先创建脚本全量备份：

```text
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

再确认备份列表：

```text
主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]
```

如果已经有 Caddy/Nginx 配置，额外记录这些目录：

```text
/etc/caddy/Caddyfile
/etc/caddy/conf.d
/etc/caddy/certs
/etc/nginx/nginx.conf
/etc/nginx/conf.d
/etc/nginx/sites-enabled
/etc/nginx/stream.d
```

如果已有 Docker Compose 项目，记录：

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
find /opt -maxdepth 3 -name 'docker-compose.yml' -o -name 'compose.yml' 2>/dev/null
```

## 第三步：选择迁移路线

| 当前状态 | 推荐路线 |
|---|---|
| 只有 3x-ui，没有其他网站 | 直接按 3x-ui + 443 教程部署 |
| 已有 3x-ui 且自带 HTTPS | 先清空 3x-ui 证书路径，再接入 443 |
| 已有 Caddy 反代 | 记录旧域名和后端，启用 443 后逐个补录；可继续选择 Caddy，也可切到 Nginx 本地 Web 反代 |
| 已有 Nginx/Apache 网站 | 先把网站后端改为本地端口，再用 443 单入口的 Web 域名/反代补录；可选择 Caddy 或 Nginx 本地 Web 反代 |
| 已有订阅工具 Docker 容器，暂不启用 443 单入口 | 保留容器，用 `主菜单 [4 反代]` 选择 Caddy 或 Nginx HTTPS 反代 |
| 已有订阅工具 Docker 容器，准备启用 443 单入口 | 保留容器，把外部访问改成 443 单入口的 Web 域名/反代 |

完整 3x-ui + REALITY + 443 步骤见 [../tutorials/01-3x-ui-reality-443.md](../tutorials/01-3x-ui-reality-443.md)。

订阅工具迁移见 [../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md](../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md)。

## 未启用 443 单入口时的 HTTPS 反代过渡

如果你暂时不准备启用 443 单入口，只是想先给订阅工具或网站加 HTTPS 域名，可以走独立反代入口：

```text
主菜单 [4 反代]
```

可选流程：

| 入口 | 适合情况 |
|---|---|
| `[1 添加 Caddy 反代]` | 已经使用 Caddy，或希望由 Caddy 管理该域名反代 |
| `[2 添加 Nginx HTTPS 反代]` | 未启用 443 单入口，且希望由 Nginx 直接监听公网 80/443 |

Nginx HTTPS 反代会复用现有 `acme.sh + Cloudflare DNS API` 证书流程，证书仍安装到 `/etc/caddy/certs/${domain}.crt|key` 并软链到 `/root/cert/`。`${domain}` 是占位写法，实际使用时会换成你的真实域名。

注意事项：

1. 该流程只适合还没有启用 443 单入口的服务器。
2. 如果已经启用 443 单入口，Nginx HTTPS 反代会抢占公网 `443`，应改用 `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]`，并在该菜单里选择 Caddy 或 Nginx 本地 Web 反代引擎。
3. 同一个域名只交给 Caddy 或 Nginx 其中一个入口管理，不要重复配置。
4. 后端仍建议监听 `127.0.0.1:端口`，例如 `127.0.0.1:3000`。域名和端口都是示例值，请替换为你的实际值。

## 迁移已有 3x-ui

### 目标状态

下面的 `40000`、`2096`、`1443` 是示例端口；实际以 3x-ui、Xray 和脚本保存的配置为准。

| 项目 | 目标 |
|---|---|
| 面板监听 | `127.0.0.1:40000` |
| 面板 HTTPS | 关闭，证书路径清空 |
| 面板路径 | 例如 `/panel/` |
| 订阅监听 | `127.0.0.1:2096` |
| 订阅路径 | 例如 `/sub/`、`/clash/` |
| REALITY 监听 | `127.0.0.1:1443` |
| 客户端节点端口 | `443` |

### 操作入口

进入 3x-ui：

```text
主菜单 [5 面板、节点与订阅工具] -> [1 3x-ui 面板脚本]
```

如果面板证书或路径已经乱了，先用救砖入口：

```text
主菜单 [5 面板、节点与订阅工具] -> [3 面板 SSL 修复]
```

再首次接入 443：

```text
主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]
```

跑完后体检：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

### 验证

```bash
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
```

订阅链接和节点链接里不应该再出现：

```text
:2096
:40000
:1443
127.0.0.1
```

## 迁移已有 Caddy 网站

### 迁移前记录

```bash
find /etc/caddy -maxdepth 3 -type f -print
grep -R "reverse_proxy" /etc/caddy 2>/dev/null
grep -R "tls " /etc/caddy 2>/dev/null
```

记录每个站点：

| 域名 | 后端协议 | 后端地址 | 后端端口 | 备注 |
|---|---|---|---|---|
| `site.example.com` | HTTP | `127.0.0.1` | `8080` | 网站 |
| `sub.example.com` | HTTP | `127.0.0.1` | `3000` | 订阅工具 |

### 启用 443 后补录

首次配置或重新应用 443 单入口可能会隔离旧 Caddy 配置和脚本管理的旧 Nginx HTTPS 反代配置，避免旧配置继续抢占公网 `443`。启用后不要再手写抢占 `443` 的旧规则，而是逐个补录：

```text
主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]
```

新增时只填本地后端：

| 输入项 | 示例 |
|---|---|
| 网站/反代域名 | `site.example.com` |
| 后端监听地址 | `127.0.0.1` |
| 后端端口 | `8080` |

验证：

```bash
curl -I http://127.0.0.1:8080/
curl -I https://site.example.com/
openssl s_client -connect 服务器IP:443 -servername site.example.com </dev/null
```

## 迁移已有 Nginx/Apache 网站

443 单入口模式下，公网 `443` 应由当前入口模式统一监听。旧 Nginx server、Apache、面板、Xray 都不应该再直接监听公网 `443`；如果希望继续用 Nginx 做网站反代，请在 `[19] -> [8]` 切换到 Nginx 本地 Web 反代引擎，而不是保留旧的公网 `443` server。

建议做法：

1. 让旧网站服务改为本机 HTTP 后端，例如 `127.0.0.1:8080`。
2. 用 443 单入口的“管理 Web 域名/反代”把域名反代到该后端。
3. 验证公网 HTTPS 域名。
4. 确认无误后再收紧防火墙和旧公网端口。

检查旧服务：

```bash
ss -lntp | grep -E ':80|:443|:8080|:8081'
grep -R "listen" /etc/nginx /etc/apache2 /etc/httpd 2>/dev/null
```

如果旧服务必须继续用 Nginx/Apache，至少不要让它抢 `0.0.0.0:443`。

## 迁移 Docker 订阅工具

目标是容器后端只在本机或内网监听，公网只走 Caddy/Nginx 反代或 443 单入口。启用 443 单入口后，Caddy/Nginx 是可选的本地 Web 反代引擎，不再直接抢公网 `443`。

先看容器端口：

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
ss -lntp | grep -E ':3000|:3001|:3002'
```

如果后端暴露在 `0.0.0.0`，可以考虑：

```text
主菜单 [11 Docker 安全管理] -> [1 开启 Docker 本地防穿透]
```

这个操作会影响 Docker 网络行为，执行前确认容器不依赖公网直连端口。

如果暂时不启用 443 单入口，进入：

```text
主菜单 [4 反代]
```

选择 `[1 添加 Caddy 反代]` 或 `[2 添加 Nginx HTTPS 反代]`，把订阅域名反代到本地后端端口。Nginx HTTPS 反代会申请或复用 `/etc/caddy/certs/${domain}.crt|key` 证书，并由 Nginx 直接监听公网 80/443；该方式不能和 443 单入口同时抢公网 `443`。

如果已经启用或准备启用 443 单入口，则通过 443 单入口新增外部域名：

```text
主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]
```

并在工具后台把外部访问地址改成：

```text
https://sub.example.com/
```

不要写：

```text
http://127.0.0.1:3000/
http://服务器IP:3000/
https://sub.example.com:3000/
```

## 迁移后的验证清单

| 检查项 | 命令或入口 | 期望 |
|---|---|---|
| 端口监听 | `ss -lntp` | 公网 `443` 只给当前入口服务 |
| Nginx 配置 | `nginx -t` | 通过 |
| Caddy 配置 | `caddy validate --config /etc/caddy/Caddyfile` | 使用 Caddy 作为 Web 反代引擎时通过 |
| 面板后端 | `curl -I http://127.0.0.1:40000/panel/` | 200/302/401 均可，不能拒绝连接 |
| 订阅后端 | `curl -I http://127.0.0.1:2096/sub/` | 能连通 |
| 面板公网 | `curl -I https://panel.example.com/panel/` | HTTPS 正常 |
| 网站公网 | `curl -I https://site.example.com/` | HTTPS 正常 |
| 443 体检 | `主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]` | 无关键失败 |
| 服务总览 | `主菜单 [15 服务健康总览]` | 无异常失败服务 |

成功后立刻备份：

```text
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

## 回滚方案

| 问题 | 优先处理 |
|---|---|
| 只是新增站点失败 | 删除刚新增的域名或使用脚本自动回滚 |
| Caddy 配置失败 | 校验 Caddy，隔离新站点配置，再重载 |
| Nginx stream 失败 | 回滚 443 单入口配置 |
| 面板打不开 | 清理 3x-ui SSL，检查本地端口和路径 |
| 服务整体混乱 | 从脚本全量备份或云快照恢复 |

443 单入口回滚入口：

```text
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [6 回滚 443 单入口配置]
```

脚本全量回滚入口：

```text
主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]
```

失联或复杂故障见 [recovery-runbook.md](recovery-runbook.md)。

## 常见迁移错误

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 不盘点旧 `443` 占用就直接首次配置 | Nginx/Caddy 端口冲突 | 先 `ss -lntp`，记录旧服务 |
| 新增网站时重跑首次配置 | 配置被重复改写，排错变复杂 | 后续新增只走 `[8 管理 Web 域名/反代]` |
| 保留 3x-ui 自带 HTTPS | 重定向循环或 502 | 清空证书路径，让 Web 反代引擎接管 HTTPS |
| 把后端写成公网域名 | 反代绕路，证书和 Header 混乱 | 后端使用 `127.0.0.1:端口` |
| Cloudflare 开橙云 | REALITY、证书或 SNI 行为异常 | 先用 DNS only / 灰云跑通 |
| 没有迁移旧 Caddy/Nginx 站点 | 旧网站启用 443 后打不开 | 逐个通过 `[8 管理 Web 域名/反代]` 补录，并选择需要的 Web 反代引擎 |
