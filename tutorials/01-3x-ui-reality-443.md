# 3x-ui + REALITY + 443 单入口部署

这篇教程讲的是：用 3x-ui 管理节点，让面板、订阅、网站和 REALITY 都通过公网 `443` 工作。核心思路是公网 `443` 只给当前入口模式对应的单个服务：`nginx-stream` 用 Nginx stream 按 SNI 分流，`tcp-peek` 用 `vpso-mux` 按 SNI 分流，`xray-fallback` 用 Xray 主入站接管 443 并 fallback 到本地 Web 反代引擎；本地后端全部尽量监听 `127.0.0.1`。

推荐先读完整 443 教程：

```text
docs/443-single-entry.md
```

排错时看：

```text
docs/443-single-entry-troubleshooting.md
```

## 示例说明

本文中的域名、路径和端口都是示例，不是必须照抄的固定值。`panel.example.com` 是示例面板域名，`node.example.com` 是示例节点域名，`site.example.com` 是示例网站域名，`40000` 是示例 3x-ui 面板端口，`2096` 是示例订阅端口，`8443` 是示例 Web 反代引擎本地端口，`1443` 是示例 Xray/REALITY 本地端口。

实际部署时请替换成你自己的域名、路径和端口；如果脚本已经保存过配置，以脚本当前显示为准，不要盲目照抄教程里的示例。

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
| 当前 443 入口服务 | 公网 `443` 单入口接管和分流 | 端口冲突会导致当前入口模式切换或启动失败 |
| 当前 Web 反代引擎 | 本地 HTTPS 反代和证书 | 配置错会 404/502/证书失败 |
| Xray/REALITY | 本地监听和伪装 SNI | SNI 写错会连接失败 |
| 防火墙 | 建议只保留 SSH 和公网 `443` | 误删端口会断连 |
| 备份 | 创建 SNI stack 和手动配置备份 | 占用少量磁盘 |

## 推荐架构

```text
公网 443 -> 当前入口模式对应的单个服务
  nginx-stream  -> Nginx stream 按 SNI 分流
  tcp-peek      -> vpso-mux 按 SNI 分流
  xray-fallback -> Xray 主入站接管 443 并 fallback 到本地 Web 反代引擎

panel.example.com  -> 当前 Web 反代引擎（Caddy 或 Nginx，例如 127.0.0.1:8443）-> 3x-ui 面板 127.0.0.1:40000
panel.example.com/sub/ -> 当前 Web 反代引擎（Caddy 或 Nginx）-> 3x-ui 订阅 127.0.0.1:2096
REALITY SNI / 未知 SNI -> Xray REALITY 127.0.0.1:1443
site.example.com -> Caddy/Nginx 本地 Web 反代 -> 本地网站后端
```

关键原则：

| 原则 | 说明 |
|---|---|
| 公网 `443` 只给当前入口模式对应的单个服务 | 避免 Caddy、Xray、面板和 `vpso-mux` 互相抢端口 |
| Web 反代引擎监听本地 HTTPS 端口 | 浏览器 HTTPS 由 Caddy 或 Nginx 本地 Web 反代处理，`8443` 只是示例值 |
| 3x-ui 面板不使用自带证书作为公网 HTTPS | 面板作为本地 HTTP 后端 |
| REALITY 使用外部真实 SNI | 不要把 `dest` 写成自己的面板域名 |
| 成功后再收紧防火墙 | 先跑通，再只保留必要端口 |

`Xray 入站管理` 只记录 `SNI -> 本地地址:端口`，不是 3x-ui 入站编辑器；需要先在 3x-ui 中创建并启用本地入站。Nginx Stream 模式和 TCP Peek + Splice 模式支持多个本地 Xray 入站按 SNI 分流；Xray 本身可以有多个入站，但 xray-fallback 模式下公网 `443` 默认由一个 Xray 主入站接管，脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。

普通 TLS 和 REALITY 要分开判断：普通 TLS 更关注本机证书、Web fallback、Host/SNI 是否匹配；REALITY 更关注外部目标站点是否真实可访问、TLS 特征是否稳定，不要求 REALITY `serverName` 加入 Web 反代引擎，也不要求本机证书覆盖 REALITY `serverName`。证书策略仍然使用 `acme.sh + Cloudflare DNS API`，不使用 Caddy DNS 模块，也不需要 `xcaddy`。3x-ui 安装阶段选择的证书只用于完成安装流程，不是 443 单入口最终使用的证书方案。

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

如果已有 Caddy/Nginx/Apache 占用公网 `443`，先记录现有站点域名和后端端口，后续通过 `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` 重新补录。

### 2. 安装或进入 3x-ui

进入：

```text
主菜单 [5 面板、节点与订阅工具] -> [1 3x-ui 面板脚本]
```

如果未安装，选择安装 3x-ui。安装器可能强制要求选择证书方式，例如为域名申请证书、为 IP 申请证书，或选择已有证书路径。这里的选择只是为了完成 3x-ui 安装流程，不是 443 单入口最终使用的证书方案。

如果安装器强制要求选择证书方式，可以先按提示选择一种方式完成安装。如果你不确定选哪个，可以临时选择为域名申请证书完成安装；后续接入 443 单入口前，需要清空 3x-ui 面板和订阅证书路径。

| 安装器选项 | 在本教程中的作用 | 后续处理 |
|---|---|---|
| 为域名申请证书 | 可用于临时完成 3x-ui 安装 | 接入 443 前清空 3x-ui 证书路径 |
| 为 IP 申请证书 | 仅作为临时过渡，不推荐作为正式公网 HTTPS | 接入 443 前清空 3x-ui 证书路径 |
| 选择已有证书路径 | 可用于临时完成安装 | 接入 443 前清空 3x-ui 证书路径 |

最终架构是：公网 HTTPS 由当前 Web 反代引擎（Caddy 或 Nginx）统一处理，证书由 VPS-Optimize 使用 `acme.sh + Cloudflare DNS API` 申请和安装；3x-ui 面板和订阅只作为本地 HTTP 后端，3x-ui 自带证书不作为最终公网证书方案。

安装时先让它正常跑起来即可，后面接入 443 前再统一整理监听地址和证书路径。

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

只要你准备接入 VPS-Optimize 的 443 单入口，就应清空 3x-ui 面板和订阅证书路径，让 Web 反代引擎接管公网 HTTPS。

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

原因：接入 443 单入口后，公网 HTTPS 由 Web 反代引擎处理，3x-ui 面板只做本地 HTTP 后端。如果不清空，可能导致 502 Bad Gateway、HTTP/HTTPS 后端协议不匹配、重定向循环、证书路径混乱、面板或订阅异常。

### 4. 设置面板监听

一组示例值：

| 项目 | 示例值 |
|---|---|
| 面板监听地址 | `127.0.0.1` |
| 面板端口 | `40000` |
| 面板路径 / webBasePath | `/panel/` |
| 面板 HTTPS | 关闭 |

接入 443 单入口前就应改成 `127.0.0.1` 本地监听并关闭面板 HTTPS；公网访问只走 443 单入口和 Web 反代引擎，不保留面板公网端口作为过渡。

验证本地后端：

```bash
curl -I http://127.0.0.1:40000/panel/
```

### 5. 设置订阅服务

在 3x-ui 订阅设置中示例：

| 项目 | 示例值 |
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

在 3x-ui 新增 VLESS REALITY 入站，示例：

| 项目 | 示例值 |
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
主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]
```

示例填写：

| 项目 | 示例值 |
|---|---|
| 面板域名 | `panel.example.com` |
| REALITY 伪装 SNI | `www.microsoft.com` |
| 443 入口模式 | `nginx-stream` / `xray-fallback` / `tcp-peek` |
| 公网 `443` 监听者 | 由当前入口模式对应的单个入口服务接管 |
| Web 反代引擎本地监听地址 | `127.0.0.1` |
| Web 反代引擎本地监听端口 | `8443` |
| Xray REALITY 本地监听地址 | `127.0.0.1` |
| Xray REALITY 本地监听端口 | `1443` |
| 3x-ui 面板监听地址 | `127.0.0.1` |
| 3x-ui 面板端口 | `40000` |
| 3x-ui 面板公网路径 | `/panel/` |
| 3x-ui 订阅监听地址 | `127.0.0.1` |
| 3x-ui 订阅端口 | `2096` |
| 普通订阅路径前缀 | `/sub/` |
| Clash/Mihomo 路径前缀 | `/clash/` |

如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本只在兼容读取旧配置时按 `nginx-stream` 处理；新配置和后续保存应以实际选择的 `ENTRY_MODE` 为准。

脚本出现高风险确认卡片时，确认以下条件都满足再输入大写 `YES`：

- 已创建 VPS 快照。
- 当前 SSH 会话没有断开。
- 云安全组已放行 SSH 端口和 `443/tcp`。
- 面板域名 DNS 已解析到当前 VPS。
- Cloudflare Token 权限正确。

### 8. 运行链路体检

进入：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

体检会检查当前入口服务、Web 反代引擎、REALITY、面板后端、3x-ui 面板/订阅证书路径残留和安全项。

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
| 公网 `443` | 只由当前 `ENTRY_MODE` 对应的单个入口服务监听 |
| Web 反代引擎 | `127.0.0.1:8443`，以脚本当前配置为准 |
| REALITY | `127.0.0.1:1443` |
| 面板 | `127.0.0.1:40000` |
| 订阅 | `127.0.0.1:2096` |
| 浏览器访问 | `https://panel.example.com/panel/` |

### 9. 检查客户端订阅、Hosts / External Proxy 和 REALITY

订阅链接里不应该出现：

```text
:2096
:40000
:8443
127.0.0.1
```

节点链接需要输出公网 `443`。

3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host：

```text
入站：选择这个 REALITY 入站
地址：node.example.com 或服务器公网 IP
端口：443
Security：相同，或按该入站实际安全类型填写
SNI / Fingerprint / ALPN：按该入站和客户端实际值保持一致
```

3x-ui v3.3.1 及之前：在 REALITY 入站里打开 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

REALITY 节点里重点确认：

| 项目 | 期望 |
|---|---|
| 地址 | 节点域名或服务器公网 IP |
| 端口 | `443` |
| security | `reality` |
| SNI | 外部真实 HTTPS 站点 |
| flow | 按你的客户端和入站配置一致 |

如果面板打开正常但 REALITY 连不上，优先看 `dest`、`serverNames`、本地监听端口，以及当前入口模式的 SNI 分流或 Xray fallback 接管是否符合预期。

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
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
主菜单 [15 服务健康总览]
```

## 失败怎么回滚

| 情况 | 处理 |
|---|---|
| Nginx/Caddy 配置写入后失败 | 脚本会尽量自动回滚到本次备份 |
| 面板打不开 | `主菜单 [5 面板、节点与订阅工具] -> [3 面板 SSL 修复]` 清理面板 SSL，再检查本地端口 |
| 证书失败 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]` 检查 Token、DNS、重签证书 |
| 443 被占用 | `ss -lntp | grep ':443'` 找占用方，再调整为本地监听 |
| 订阅 404 | 检查 3x-ui 订阅路径和当前 Web 反代引擎路径是否一致 |
| REALITY 失败 | 检查 REALITY 本地监听、SNI、dest 和客户端节点端口 |
| 配置整体混乱 | `主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]` 从手动备份回滚 |

## 常见错误

| 错误 | 现象 | 处理 |
|---|---|---|
| Web 反代引擎也监听公网 `443` | 当前入口服务启动失败或端口冲突 | Web 反代引擎改为本地监听，例如 `127.0.0.1:8443` |
| 3x-ui 面板自带 HTTPS 没关 | 重定向循环、证书错误 | 清空面板证书路径并重启 |
| REALITY 写自己的域名做 SNI | 客户端连接失败 | 改成外部真实 HTTPS 站点 |
| 订阅路径不带 `/` | 订阅 404 | 统一写 `/sub/`、`/clash/` |
| Cloudflare 开橙云 | REALITY 或证书异常 | 改 DNS only / 灰云 |
| External URL 输出内部端口 | 客户端无法订阅 | 改成 `https://panel.example.com/sub/` |
| Hosts / External Proxy 输出内部端口 | 客户端节点连不上公网 `443` | 3x-ui v3.4.0+ 检查 `Hosts / 主机`；旧版检查 `External Proxy` |
| 没备份就反复重跑 | 配置越来越乱 | 先备份，再按排错手册逐项修 |
