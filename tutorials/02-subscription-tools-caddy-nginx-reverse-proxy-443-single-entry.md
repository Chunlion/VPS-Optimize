# 订阅工具接入 Caddy/Nginx 反代与 443 单入口

这篇教程讲的是把 SublinkPro、Sub-Store、妙妙屋订阅管理等订阅工具安全地对外提供 HTTPS 访问。未启用 443 单入口时，可以走 `主菜单 [4 反代]` 里的 Caddy 或 Nginx HTTPS 反代；已经启用 443 单入口后，应统一走 443 单入口的 Web 域名/反代入口，并可在该入口选择 Caddy 或 Nginx 作为本地 Web 反代引擎。

推荐选择：

| 当前状态 | 推荐方式 |
|---|---|
| 还没有启用 443 单入口，只想先访问订阅工具 | `主菜单 [4 反代]`，按现有环境选择 Caddy 或 Nginx HTTPS 反代 |
| 已经启用 443 单入口 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` 新增反代域名；需要时用同菜单 `[8 切换 Web 反代引擎]` 在 Caddy/Nginx 间切换 |
| 订阅工具只给自己用 | 后端只监听 `127.0.0.1`，外部通过 Caddy/Nginx 或 443 单入口访问 |
| 不确定应该选哪个 | 先跑 `主菜单 [1 运维预检与风险扫描]` 和 `主菜单 [15 服务健康总览]`，确认端口和服务状态 |

## 适合谁

| 情况 | 是否适合 |
|---|---|
| 想部署 SublinkPro | 适合 |
| 想部署 Sub-Store | 适合 |
| 想部署妙妙屋订阅管理 | 适合 |
| 订阅工具已经在 Docker 里运行，想加域名 HTTPS | 适合 |
| 想把订阅工具内部端口直接暴露公网 | 不建议 |

## 准备材料

| 材料 | 示例 | 说明 |
|---|---|---|
| VPS 快照 | 云厂商控制台创建 | 修改反代和容器前建议做 |
| 订阅域名 | `sub.example.com` | DNS 指向当前 VPS |
| 后端端口 | `3000`、`3001` 等 | 订阅工具实际监听端口 |
| Cloudflare API Token | `Zone.Zone.Read`、`Zone.DNS.Edit` | 需要 DNS 签证书时使用 |
| 当前 SSH 会话 | 不关闭 | 方便失败时恢复 |
| Docker/Compose | 脚本会自动检查并安装 | 订阅工具通常用 Docker Compose 部署 |

DNS 建议：

| 域名 | 建议 |
|---|---|
| `sub.example.com` | DNS only / 灰云 |
| 443 单入口相关域名 | DNS only / 灰云 |
| 只是常规网站展示 | 可按实际需求决定是否代理，但本教程建议先灰云跑通 |

## 预计耗时

| 阶段 | 预计耗时 |
|---|---|
| 预检 | 2-5 分钟 |
| 部署订阅工具 | 5-20 分钟 |
| 配置 Caddy/Nginx 或 443 单入口 | 5-15 分钟 |
| 验证订阅输出 | 5-10 分钟 |
| 备份 | 1-3 分钟 |

## 会修改哪些东西

| 项目 | 可能修改内容 | 风险 |
|---|---|---|
| Docker/Compose | 新增容器、网络、部署目录 | 容器端口冲突或镜像拉取失败 |
| Caddy | 新增站点配置、证书、反代规则 | 配置错误会导致 404/502 |
| Nginx HTTPS 反代 | 未启用 443 单入口时可新增 HTTPS 站点配置 | 配置错误或端口冲突会导致 80/443 访问异常 |
| Nginx stream | 如果接入 443 单入口，会新增 SNI 分流 | 配置错误可能影响公网 443 |
| 防火墙 | 建议只暴露入口端口，不暴露后端端口 | 误放行会暴露内部服务 |
| 备份 | 生成配置备份和隔离目录 | 占用少量磁盘 |

## 操作步骤

### 1. 预检当前服务器

进入：

```text
主菜单 [1 运维预检与风险扫描]
```

重点确认：

| 项目 | 期望 |
|---|---|
| Docker | 如未安装，订阅工具安装流程会自动安装 |
| 端口占用 | 订阅工具端口不要和已有服务冲突 |
| DNS | 订阅域名能解析到当前 VPS |
| 防火墙 | SSH 和入口端口已放行 |
| 系统时间 | 证书签发需要时间准确 |

手动看端口：

```bash
ss -lntp
```

### 2. 安装订阅工具

进入：

```text
主菜单 [5 面板、节点与订阅工具]
```

安装流程会自动检查 Docker/Compose，缺失时先安装。

常用入口：

| 工具 | 菜单路径 | 适合场景 |
|---|---|---|
| SublinkPro | `主菜单 [5 面板、节点与订阅工具] -> [7 SublinkPro 订阅栈]` | 订阅转换、聚合、管理 |
| 妙妙屋订阅管理 | `主菜单 [5 面板、节点与订阅工具] -> [8 妙妙屋订阅栈]` | 图形化订阅管理 |
| Sub-Store | `主菜单 [5 面板、节点与订阅工具] -> [9 Sub-Store 订阅栈]` | 高级订阅处理和脚本化 |
| Dockge | `主菜单 [5 面板、节点与订阅工具] -> [11 Dockge Compose]` | 管理多个 Compose 项目 |

安装后先看容器状态：

```bash
docker ps
```

如果脚本把项目部署到 `/opt` 下，也可以进入对应目录查看：

```bash
ls /opt
```

### 3. 确认后端监听方式

订阅工具后端建议只监听本地或内网，不建议直接暴露公网。理想状态：

```text
127.0.0.1:3000
127.0.0.1:3001
127.0.0.1:3002
```

检查：

```bash
ss -lntp | grep -E ':3000|:3001|:3002'
curl -I http://127.0.0.1:3000/
```

如果后端监听 `0.0.0.0:3000`，代表公网可能能直接访问。你可以通过 Docker 本地防穿透或防火墙限制暴露：

```text
主菜单 [11 Docker 安全管理]
主菜单 [8 防火墙规则管理]
```

Docker 防穿透会修改 Docker 网络行为并重启 Docker，属于高风险操作，确认容器不依赖公网直连端口后再继续。

### 4A. 方案一：未启用 443 单入口时使用 Caddy/Nginx 反代

适合还没启用 443 单入口，只想先用域名访问订阅工具。

进入：

```text
主菜单 [4 反代]
```

按当前环境选择：

| 入口 | 适合情况 |
|---|---|
| `[1 添加 Caddy 反代]` | 已经使用 Caddy，或希望由 Caddy 直接管理站点反代 |
| `[2 添加 Nginx HTTPS 反代]` | 未启用 443 单入口，且希望由 Nginx 直接监听公网 80/443 提供 HTTPS |

填写示例，域名和端口都要替换成你的实际值：

| 项目 | 示例 |
|---|---|
| 域名 | `sub.example.com` |
| 后端端口 | `3000` |
| 后端协议 | 按工具实际情况，通常 HTTP |

如果选择 Nginx HTTPS 反代，脚本会复用现有 `acme.sh + Cloudflare DNS API` 证书流程，证书仍安装到：

```text
/etc/caddy/certs/sub.example.com.crt
/etc/caddy/certs/sub.example.com.key
/root/cert/sub.example.com.crt
/root/cert/sub.example.com.key
```

`sub.example.com` 是示例值，请替换成你的实际订阅域名。Nginx HTTPS 反代只适合未启用 443 单入口的场景；如果脚本检测到 443 单入口配置，会拒绝继续，避免 Nginx 抢占公网 `443`。同一个域名也不要同时交给 Caddy 和 Nginx 接管。

如果用 Caddy 反代，配置后验证：

```bash
systemctl status caddy --no-pager
caddy validate --config /etc/caddy/Caddyfile
curl -I https://sub.example.com/
```

如果用 Nginx HTTPS 反代，配置后验证：

```bash
nginx -t
systemctl status nginx --no-pager
curl -I https://sub.example.com/
```

如果 502：

```bash
curl -I http://127.0.0.1:3000/
journalctl -u caddy -n 80 --no-pager
journalctl -u nginx -n 80 --no-pager
```

如果证书失败，检查 DNS、Cloudflare 代理状态和服务器时间。

### 4B. 方案二：接入 443 单入口

适合已经启用了：

```text
主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]
```

后续新增订阅工具域名，不要重跑首次配置，进入：

```text
主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]
```

填写示例：

| 项目 | 示例 |
|---|---|
| 新网站/反代域名 | `sub.example.com` |
| 后端监听地址 | `127.0.0.1` |
| 后端端口 | `3000` |

脚本会按当前 Web 反代引擎更新 Caddy 或 Nginx 本地配置并申请证书。出现高风险确认时，确认快照、DNS、Token、后端端口都没问题后再输入大写 `YES`。

如果你之前在 `主菜单 [4 反代]` 配过独立 Caddy/Nginx HTTPS 反代，启用或重新应用 443 单入口时，脚本会把可能抢占公网 `443` 的旧配置隔离。之后订阅工具域名都应从 `[19] -> [8]` 补录，不要再让 `[4 反代]` 的 Nginx HTTPS 反代直接监听公网 `443`。

验证：

```bash
curl -I https://sub.example.com/
openssl s_client -connect 服务器IP:443 -servername sub.example.com </dev/null
```

### 5. 配置订阅工具的外部访问地址

不同工具名称不同，常见字段包括：

```text
External URL
Public URL
Base URL
订阅域名
外部访问地址
```

应该填公网 HTTPS 地址：

```text
https://sub.example.com/
```

不要填：

```text
http://127.0.0.1:3000/
http://服务器IP:3000/
https://sub.example.com:3000/
```

如果订阅工具生成的链接里仍然带内部端口，客户端可能无法使用。

### 6. 验证订阅内容

浏览器打开：

```text
https://sub.example.com/
```

命令检查：

```bash
curl -I https://sub.example.com/
curl -L https://sub.example.com/ -o /tmp/sub-tool-home.html
```

检查订阅输出时，关注：

| 项目 | 期望 |
|---|---|
| 域名 | 是公网域名 |
| 协议 | HTTPS |
| 端口 | 默认 `443`，不要带内部端口 |
| Token | 不要出现在公开日志里 |
| 节点地址 | 不要被改成 `127.0.0.1` |

### 7. 成功后备份

进入：

```text
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

如果订阅工具用 Docker Compose 部署，也建议额外记录：

| 内容 | 位置 |
|---|---|
| Compose 目录 | `/opt/<项目名>` |
| 管理员账号 | 自己的密码管理器 |
| 外部访问域名 | 运维笔记 |
| 后端端口 | 运维笔记 |
| Cloudflare Token 权限 | Cloudflare 控制台 |

## 验证方法

未启用 443 单入口的 Caddy/Nginx 反代，按实际使用的入口验证。

Caddy：

```bash
systemctl status caddy --no-pager
caddy validate --config /etc/caddy/Caddyfile
curl -I https://sub.example.com/
curl -I http://127.0.0.1:3000/
```

Nginx HTTPS 反代：

```bash
systemctl status nginx --no-pager
nginx -t
curl -I https://sub.example.com/
curl -I http://127.0.0.1:3000/
```

443 单入口菜单验证：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

也可以手动：

```bash
ss -lntp | grep -E ':443|:8443|:3000'
curl -I https://sub.example.com/
openssl s_client -connect 服务器IP:443 -servername sub.example.com </dev/null
```

Docker 状态：

```bash
docker ps
docker logs --tail=80 容器名
```

## 失败怎么回滚

| 问题 | 处理 |
|---|---|
| Caddy 配置错误 | 使用 Caddy 备份恢复，或隔离新站点配置后重载 |
| Nginx HTTPS 反代配置错误 | 检查 `nginx -t` 输出；脚本创建的 Nginx 反代配置会放在 `/etc/nginx/conf.d/vps_proxy_${domain}.conf` |
| 443 单入口新增域名失败 | 使用脚本自动备份回滚，或从 `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` 删除该域名 |
| 证书失败 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]` 检查 Token、DNS、重签 |
| 容器启动失败 | 进入对应工具管理菜单查看状态、重启或重建 |
| 订阅输出内部端口 | 修改工具 External URL / Public URL |
| 端口暴露公网 | `主菜单 [11 Docker 安全管理]` 或 `主菜单 [8 防火墙规则管理]` 收紧访问 |
| 配置整体混乱 | `主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]` 从备份恢复 |

## 常见错误

| 错误 | 现象 | 处理 |
|---|---|---|
| 后端端口没监听 | 502 | 先启动容器，确认 `curl http://127.0.0.1:端口/` 可用 |
| DNS 没解析到 VPS | 证书失败或打不开 | 修正 A 记录并等待生效 |
| Cloudflare 开橙云 | REALITY/证书/链路异常 | 先改 DNS only / 灰云跑通 |
| 同一个域名重复配置 | Caddy/Nginx 行为不稳定 | 先查看现有站点，再新增 |
| 直接访问内部端口 | 安全暴露 | 外部只访问 HTTPS 域名 |
| 订阅工具输出 `127.0.0.1` | 客户端不可用 | 设置外部访问地址 |
| 删除容器时误以为数据也备份了 | 数据丢失风险 | 停止/归档前确认 Compose 数据目录和卷 |

## 推荐维护习惯

| 维护动作 | 建议频率 |
|---|---|
| `主菜单 [15 服务健康总览]` 健康检查 | 每次改反代后 |
| `主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]` 备份 | 每次成功改配置后 |
| 检查 `docker ps` | 每次升级订阅工具后 |
| 检查订阅输出 | 每次修改 External URL 后 |
| 更新脚本 | 有明确需要时用 `主菜单 [17 更新脚本]` |
