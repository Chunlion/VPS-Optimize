# 订阅工具接入 Caddy 与 443 单入口

这篇教程讲的是把 SublinkPro、Sub-Store、妙妙屋订阅管理等订阅工具安全地对外提供 HTTPS 访问。你可以走普通 Caddy 反代，也可以接入已经配置好的 443 单入口。

推荐选择：

| 当前状态 | 推荐方式 |
|---|---|
| 还没有启用 443 单入口，只想先访问订阅工具 | 普通 Caddy 反代 |
| 已经启用 443 单入口 | `cy -> 19 -> 2` 新增反代域名 |
| 订阅工具只给自己用 | 后端只监听 `127.0.0.1`，外部通过 Caddy 访问 |
| 不确定应该选哪个 | 先跑 `cy -> 1` 和 `cy -> 15`，确认端口和服务状态 |

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
| 已安装 Docker | 脚本可安装 | 订阅工具通常用 Docker Compose 部署 |

DNS 建议：

| 域名 | 建议 |
|---|---|
| `sub.example.com` | DNS only / 灰云 |
| 443 单入口相关域名 | DNS only / 灰云 |
| 只是普通网站展示 | 可按实际需求决定是否代理，但本教程建议先灰云跑通 |

## 预计耗时

| 阶段 | 预计耗时 |
|---|---|
| 预检 | 2-5 分钟 |
| 安装 Docker 和订阅工具 | 5-20 分钟 |
| 配置 Caddy 或 443 单入口 | 5-15 分钟 |
| 验证订阅输出 | 5-10 分钟 |
| 备份 | 1-3 分钟 |

## 会修改哪些东西

| 项目 | 可能修改内容 | 风险 |
|---|---|---|
| Docker/Compose | 新增容器、网络、部署目录 | 容器端口冲突或镜像拉取失败 |
| Caddy | 新增站点配置、证书、反代规则 | 配置错误会导致 404/502 |
| Nginx stream | 如果接入 443 单入口，会新增 SNI 分流 | 配置错误可能影响公网 443 |
| 防火墙 | 建议只暴露入口端口，不暴露后端端口 | 误放行会暴露内部服务 |
| 备份 | 生成配置备份和隔离目录 | 占用少量磁盘 |

## 操作步骤

### 1. 预检当前服务器

进入：

```text
cy -> 1
```

重点确认：

| 项目 | 期望 |
|---|---|
| Docker | 如未安装，后面先装 Docker |
| 端口占用 | 订阅工具端口不要和已有服务冲突 |
| DNS | 订阅域名能解析到当前 VPS |
| 防火墙 | SSH 和入口端口已放行 |
| 系统时间 | 证书签发需要时间准确 |

手动看端口：

```bash
ss -lntp
```

### 2. 安装 Docker

如果还没有 Docker，进入：

```text
cy -> 3 -> 1
```

验证：

```bash
docker version
docker compose version || docker-compose version
systemctl status docker --no-pager
```

如果 Docker 安装失败，先解决软件源、DNS 或网络连通性，不要继续部署订阅工具。

### 3. 安装订阅工具

进入：

```text
cy -> 4
```

常用入口：

| 工具 | 菜单路径 | 适合场景 |
|---|---|---|
| SublinkPro | `cy -> 4 -> 5` | 订阅转换、聚合、管理 |
| 妙妙屋订阅管理 | `cy -> 4 -> 6` | 图形化订阅管理 |
| Sub-Store | `cy -> 4 -> 7` | 高级订阅处理和脚本化 |
| Dockge | `cy -> 4 -> 8` | 管理多个 Compose 项目 |

安装后先看容器状态：

```bash
docker ps
```

如果脚本把项目部署到 `/opt` 下，也可以进入对应目录查看：

```bash
ls /opt
```

### 4. 确认后端监听方式

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
cy -> 11
cy -> 8
```

Docker 防穿透会修改 Docker 网络行为并重启 Docker，属于高风险操作，确认容器不依赖公网直连端口后再继续。

### 5A. 方案一：普通 Caddy 反代

适合还没启用 443 单入口，只想先用域名访问订阅工具。

进入：

```text
cy -> 3 -> 13
```

填写示例：

| 项目 | 示例 |
|---|---|
| 域名 | `sub.example.com` |
| 后端端口 | `3000` |
| 后端协议 | 按工具实际情况，通常 HTTP |

配置后验证：

```bash
systemctl status caddy --no-pager
curl -I https://sub.example.com/
```

如果 502：

```bash
curl -I http://127.0.0.1:3000/
journalctl -u caddy -n 80 --no-pager
```

如果证书失败，检查 DNS、Cloudflare 代理状态和服务器时间。

### 5B. 方案二：接入 443 单入口

适合已经启用了：

```text
cy -> 19 -> 1
```

后续新增订阅工具域名，不要重跑首次配置，进入：

```text
cy -> 19 -> 2
```

填写示例：

| 项目 | 示例 |
|---|---|
| 新网站/反代域名 | `sub.example.com` |
| 后端监听地址 | `127.0.0.1` |
| 后端端口 | `3000` |

脚本会更新 Caddy/Nginx 配置并申请证书。出现高风险确认时，确认快照、DNS、Token、后端端口都没问题后再输入大写 `YES`。

验证：

```bash
curl -I https://sub.example.com/
openssl s_client -connect 服务器IP:443 -servername sub.example.com </dev/null
```

### 6. 配置订阅工具的外部访问地址

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

### 7. 验证订阅内容

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

### 8. 成功后备份

进入：

```text
cy -> 16 -> 1
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

普通 Caddy 反代：

```bash
systemctl status caddy --no-pager
caddy validate --config /etc/caddy/Caddyfile
curl -I https://sub.example.com/
curl -I http://127.0.0.1:3000/
```

443 单入口：

```bash
cy
# 进入 19 -> 3 做链路体检
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
| 443 单入口新增域名失败 | 使用脚本自动备份回滚，或从 `cy -> 19 -> 2` 删除该域名 |
| 证书失败 | `cy -> 19 -> 6` 检查 Token、DNS、重签 |
| 容器启动失败 | 进入对应工具管理菜单查看状态、重启或重建 |
| 订阅输出内部端口 | 修改工具 External URL / Public URL |
| 端口暴露公网 | `cy -> 11` 或 `cy -> 8` 收紧访问 |
| 配置整体混乱 | `cy -> 16 -> 3` 从备份恢复 |

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
| `cy -> 15` 健康检查 | 每次改反代后 |
| `cy -> 16 -> 1` 备份 | 每次成功改配置后 |
| 检查 `docker ps` | 每次升级订阅工具后 |
| 检查订阅输出 | 每次修改 External URL 后 |
| 更新脚本 | 有明确需要时用 `cy -> 17` |
