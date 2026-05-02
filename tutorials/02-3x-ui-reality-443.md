# 3x-ui + REALITY + 443 单入口部署

这篇教程讲的是：用 3x-ui 管理节点，让面板、订阅、网站和 REALITY 都通过公网 `443` 工作。核心思路是公网 `443` 只给 Nginx stream，Nginx 按 SNI 分流到 Caddy 或 REALITY，本地后端全部尽量监听 `127.0.0.1`。

推荐先读完整 443 教程：

```text
docs/443-single-entry.md
```

排错时看：

```text
docs/443-single-entry-troubleshooting.md
```

## 适合谁

| 情况 | 是否适合 |
|---|---|
| 新机器准备部署 3x-ui + REALITY | 适合 |
| 已有 3x-ui，想把面板和订阅接入公网 443 | 适合 |
| 已有 Caddy/Nginx 网站占用 443 | 适合，但必须先备份并迁移旧站点 |
| 希望 Caddy、3x-ui、Xray 都各自监听公网 443 | 不适合，应该统一入口 |
| 不清楚 DNS、Cloudflare、证书关系 | 建议先看完整教程再操作 |

## 准备材料

| 材料 | 示例 | 说明 |
|---|---|---|
| VPS 快照 | 云厂商控制台创建 | 首次接管 `443` 前必须做 |
| 面板域名 | `panel.example.com` | 访问 3x-ui 面板和订阅 |
| 节点域名 | `node.example.com` | 可选，也可用服务器 IP |
| Cloudflare API Token | `Zone.Zone.Read`、`Zone.DNS.Edit` | 用于 DNS 签发证书 |
| REALITY 伪装 SNI | `www.microsoft.com` | 外部真实 HTTPS 站点，不要写自己的域名 |
| 当前 SSH 会话 | 不关闭 | 失败时用于恢复 |

Cloudflare 建议：

| 域名 | 建议状态 |
|---|---|
| 面板域名 | DNS only / 灰云 |
| 节点域名 | DNS only / 灰云 |
| 订阅域名 | DNS only / 灰云 |
| REALITY 伪装 SNI | 外部真实 HTTPS 站点，不指向你的 VPS |

## 预计耗时

| 阶段 | 预计耗时 |
|---|---|
| 预检和基础准备 | 5-10 分钟 |
| 安装/配置 3x-ui | 10-20 分钟 |
| 配置 REALITY 入站 | 5-10 分钟 |
| 首次配置 443 单入口 | 10-20 分钟 |
| 验证和备份 | 5-10 分钟 |

## 会修改哪些东西

| 项目 | 修改内容 | 风险 |
|---|---|---|
| 3x-ui | 面板端口、路径、证书路径、订阅设置、REALITY 入站 | 面板路径或证书设置错会打不开 |
| Nginx stream | 公网 `443` SNI 分流 | 端口冲突会导致 Nginx 启动失败 |
| Caddy | 本地 HTTPS 反代和证书 | 配置错会 404/502/证书失败 |
| Xray/REALITY | 本地监听和伪装 SNI | SNI 写错会连接失败 |
| 防火墙 | 建议只保留 SSH 和公网 `443` | 误删端口会断连 |
| 备份 | 创建 SNI stack 和手动配置备份 | 占用少量磁盘 |

## 推荐架构

```text
公网 443 -> Nginx stream 按 SNI 分流

panel.example.com  -> Caddy 127.0.0.1:8443 -> 3x-ui 面板 127.0.0.1:40000
panel.example.com/sub/ -> Caddy -> 3x-ui 订阅 127.0.0.1:2096
REALITY SNI / 未知 SNI -> Xray REALITY 127.0.0.1:1443
site.example.com -> Caddy -> 本地网站后端
```

关键原则：

| 原则 | 说明 |
|---|---|
| 公网 `443` 只给 Nginx stream | 避免 Caddy、Xray、面板抢端口 |
| Caddy 默认监听本地 `8443` | 浏览器 HTTPS 由 Caddy 处理 |
| 3x-ui 面板关闭自带 HTTPS | 面板作为本地 HTTP 后端 |
| REALITY 使用外部真实 SNI | 不要把 `dest` 写成自己的面板域名 |
| 成功后再收紧防火墙 | 先跑通，再只保留必要端口 |

## 操作步骤

### 1. 做预检

进入：

```text
主菜单 [1 运维预检与风险扫描]
```

重点确认：

| 项目 | 期望 |
|---|---|
| DNS | 能解析你的域名和外部 HTTPS 站点 |
| 端口 | 当前 `443` 占用情况明确 |
| 系统 | Debian/Ubuntu/RHEL 系可用 |
| 时间 | 系统时间准确，证书签发依赖时间 |
| 包管理器 | 没有被其他进程占用 |

检查公网 `443`：

```bash
ss -lntp | grep ':443' || echo "443 未监听"
```

如果已有 Caddy/Nginx/Apache 占用公网 `443`，先记录现有站点域名和后端端口，后续通过 `主菜单 [19 443 单入口管理中心] -> [2 管理网站/反代域名]` 重新补录。

### 2. 安装或进入 3x-ui

进入：

```text
主菜单 [4 面板、节点与订阅工具] -> [1 管理 3x-ui 面板]
```

如果未安装，选择安装 3x-ui。安装时先让它正常跑起来即可，后面接入 443 前再统一整理监听地址和证书路径。

建议记录这些值：

| 项目 | 示例 |
|---|---|
| 面板端口 | `40000` |
| 面板路径 | `/panel/` |
| 管理员账号 | 自己保存 |
| 管理员密码 | 自己保存 |
| 订阅端口 | `2096` |
| 普通订阅路径 | `/sub/` |
| Clash/Mihomo 路径 | `/clash/` |

### 3. 清空 3x-ui 面板证书路径

进入 3x-ui 面板：

```text
面板设置 -> 常规 -> 证书
```

清空所有类似字段：

```text
证书路径
私钥路径
公钥文件路径
私钥文件路径
```

保存并重启面板。

原因：接入 443 单入口后，公网 HTTPS 由 Caddy 处理，3x-ui 面板只做本地 HTTP 后端。如果面板自己也开 HTTPS，很容易出现重定向循环、502 或证书路径混乱。

### 4. 设置面板监听

推荐最终值：

| 项目 | 推荐值 |
|---|---|
| 面板监听地址 | `127.0.0.1` |
| 面板端口 | `40000` |
| 面板路径 / webBasePath | `/panel/` |
| 面板 HTTPS | 关闭 |

如果你担心马上改成 `127.0.0.1` 后面板从公网打不开，可以先保留当前访问方式，等 `主菜单 [19 443 单入口管理中心] -> [1 首次配置 443 单入口]` 跑通后再收紧到本地监听。但最终建议是本地监听。

验证本地后端：

```bash
curl -I http://127.0.0.1:40000/panel/
```

### 5. 设置订阅服务

在 3x-ui 订阅设置中推荐：

| 项目 | 推荐值 |
|---|---|
| 订阅监听地址 | `127.0.0.1` |
| 订阅端口 | `2096` |
| 普通订阅路径 | `/sub/` |
| Clash/Mihomo 路径 | `/clash/` |
| 订阅证书路径 | 清空 |
| External URL / Public URL | `https://panel.example.com/sub/` |

注意路径要带前后 `/`。不要写成：

```text
sub
/sub
sub/
/sub/客户Subscription
```

验证本地订阅：

```bash
curl -I http://127.0.0.1:2096/sub/
```

如果 404，先确认 3x-ui 的订阅服务是否启用，以及路径是否一致。

### 6. 新建 REALITY 入站

在 3x-ui 新增 VLESS REALITY 入站，推荐：

| 项目 | 推荐值 |
|---|---|
| 协议 | VLESS |
| 传输 | TCP / RAW |
| Security | REALITY |
| 监听地址 | `127.0.0.1` |
| 监听端口 | `1443` |
| uTLS | chrome |
| `dest` / `Target` | `www.microsoft.com:443` 或其他外部真实 HTTPS 站点 |
| `serverNames` / `SNI` | `www.microsoft.com` |
| SpiderX | `/` |
| Fallbacks | 留空 |

不要写：

```text
panel.example.com:443
node.example.com:443
127.0.0.1:8443
```

先验证伪装 SNI 可连：

```bash
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com </dev/null
```

能看到证书输出，说明外部 SNI 站点可用。

### 7. 首次配置 443 单入口

进入：

```text
主菜单 [19 443 单入口管理中心] -> [1 首次配置 443 单入口]
```

建议填写：

| 项目 | 推荐值 |
|---|---|
| 面板域名 | `panel.example.com` |
| REALITY 伪装 SNI | `www.microsoft.com` |
| Nginx 公网监听地址 | `0.0.0.0` |
| Nginx 公网监听端口 | `443` |
| Caddy 本地监听地址 | `127.0.0.1` |
| Caddy 本地监听端口 | `8443` |
| Xray REALITY 本地监听地址 | `127.0.0.1` |
| Xray REALITY 本地监听端口 | `1443` |
| 3x-ui 面板监听地址 | `127.0.0.1` |
| 3x-ui 面板端口 | `40000` |
| 3x-ui 面板公网路径 | `/panel/` |
| 3x-ui 订阅监听地址 | `127.0.0.1` |
| 3x-ui 订阅端口 | `2096` |
| 普通订阅路径前缀 | `/sub/` |
| Clash/Mihomo 路径前缀 | `/clash/` |

脚本出现高风险确认卡片时，确认以下条件都满足再输入大写 `YES`：

- 已创建 VPS 快照。
- 当前 SSH 会话没有断开。
- 云安全组已放行 SSH 端口和 `443/tcp`。
- 面板域名 DNS 已解析到当前 VPS。
- Cloudflare Token 权限正确。

### 8. 运行链路体检

进入：

```text
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
```

体检会检查 Nginx、Caddy、REALITY、面板后端、证书和安全项。

手动补充检查：

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
openssl s_client -connect 服务器IP:443 -servername panel.example.com </dev/null
```

期望：

| 检查项 | 期望 |
|---|---|
| 公网 `443` | Nginx stream 监听 |
| Caddy | `127.0.0.1:8443` |
| REALITY | `127.0.0.1:1443` |
| 面板 | `127.0.0.1:40000` |
| 订阅 | `127.0.0.1:2096` |
| 浏览器访问 | `https://panel.example.com/panel/` |

### 9. 检查客户端订阅和 REALITY

订阅链接里不应该出现：

```text
:2096
:40000
:8443
127.0.0.1
```

REALITY 节点里重点确认：

| 项目 | 期望 |
|---|---|
| 地址 | 节点域名或服务器公网 IP |
| 端口 | `443` |
| security | `reality` |
| SNI | 外部真实 HTTPS 站点 |
| flow | 按你的客户端和入站配置一致 |

如果面板打开正常但 REALITY 连不上，优先看 `dest`、`serverNames`、本地监听端口和 Nginx stream 分流。

### 10. 成功后备份

进入：

```text
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
```

再查看：

```text
主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]
```

建议另外记录：

| 内容 | 记录位置 |
|---|---|
| 面板域名和路径 | 自己的密码管理器或运维笔记 |
| REALITY SNI | 运维笔记 |
| 订阅路径 | 运维笔记 |
| Cloudflare Token 权限 | Cloudflare 控制台 |

## 验证方法

完整验证命令：

```bash
ss -lntp
systemctl status nginx --no-pager
systemctl status caddy --no-pager
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
openssl s_client -connect 服务器IP:443 -servername panel.example.com </dev/null
```

菜单验证：

```text
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
主菜单 [15 服务健康总览]
```

## 失败怎么回滚

| 情况 | 处理 |
|---|---|
| Nginx/Caddy 配置写入后失败 | 脚本会尽量自动回滚到本次备份 |
| 面板打不开 | `主菜单 [4 面板、节点与订阅工具] -> [11 面板救砖 / SSL 清理]` 清理面板 SSL，再检查本地端口 |
| 证书失败 | `主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护]` 检查 Token、DNS、重签证书 |
| 443 被占用 | `ss -lntp | grep ':443'` 找占用方，再调整为本地监听 |
| 订阅 404 | 检查 3x-ui 订阅路径和 Caddy 路径是否一致 |
| REALITY 失败 | 检查 REALITY 本地监听、SNI、dest 和客户端节点端口 |
| 配置整体混乱 | `主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]` 从手动备份回滚 |

## 常见错误

| 错误 | 现象 | 处理 |
|---|---|---|
| Caddy 也监听公网 `443` | Nginx 启动失败或端口冲突 | Caddy 改 `127.0.0.1:8443` |
| 3x-ui 面板自带 HTTPS 没关 | 重定向循环、证书错误 | 清空面板证书路径并重启 |
| REALITY 写自己的域名做 SNI | 客户端连接失败 | 改成外部真实 HTTPS 站点 |
| 订阅路径不带 `/` | 订阅 404 | 统一写 `/sub/`、`/clash/` |
| Cloudflare 开橙云 | REALITY 或证书异常 | 改 DNS only / 灰云 |
| External URL 输出内部端口 | 客户端无法订阅 | 改成 `https://panel.example.com/sub/` |
| 没备份就反复重跑 | 配置越来越乱 | 先备份，再按排错手册逐项修 |
