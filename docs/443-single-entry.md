# 443 单入口分流教程

遇到面板打不开、订阅 404、证书失败或 REALITY 连接失败时，先看：[443 单入口排错手册](443-single-entry-troubleshooting.md)。

这篇文档教你把 VPS 的公网 `443` 统一接入 VPS-Optimize 的 443 单入口。默认推荐 Nginx Stream，也可以在配置完成后切换到 TCP Peek + Splice 或 Xray Fallback。无论选择哪种入口模式，公网 `443` 同一时间只由当前 `ENTRY_MODE` 对应的单个服务监听。

当前 443 单入口链路是：

```text
公网 443 -> 当前 ENTRY_MODE 对应的单个入口服务
  nginx-stream  -> nginx 按 SNI 分流
  tcp-peek      -> vpso-mux 按 SNI 分流
  xray-fallback -> Xray 主入站接管 443，并 fallback 普通 HTTPS

普通 HTTPS / Web 域名 -> 当前选择的本地 Web 反代引擎（Caddy 或 Nginx）-> 本机 HTTP 后端
3x-ui 面板            -> 当前选择的本地 Web 反代引擎 -> 127.0.0.1:40000
3x-ui 订阅            -> 当前选择的本地 Web 反代引擎 -> 127.0.0.1:2096
REALITY / Xray SNI    -> 本地 Xray / 3x-ui 入站 -> 127.0.0.1:1443
```

图里的 `127.0.0.1:40000`、`127.0.0.1:2096`、`127.0.0.1:1443` 都只是示例值。这样做的好处是：公网只暴露一个 `443`，普通 HTTPS 落到当前选择的本地 Web 反代引擎（Caddy 或 Nginx），证书由 VPS-Optimize 使用 `acme.sh + Cloudflare DNS API` 申请和安装。3x-ui 面板和订阅服务只做本机 HTTP 后端，3x-ui 自带证书不作为最终公网证书方案，避免重复 HTTPS、端口冲突、重定向循环和证书路径混乱。

## 示例说明

本文中出现的域名、路径和端口都只是示例，方便理解架构，不是必须照抄的固定值。

例如：

- `panel.example.com` = 示例面板域名
- `node.example.com` = 示例节点域名
- `site.example.com` = 示例网站域名
- `40000` = 示例 3x-ui 面板端口
- `2096` = 示例订阅端口
- `8443` = 示例 Web 反代引擎本地 HTTPS 端口
- `1443` = 示例 Xray/REALITY 本地端口

实际部署时，请替换成你自己的域名、路径和端口。如果你已经在脚本里填写过端口，以脚本保存的配置为准，不要盲目照抄文档示例。

| 项目 | 文档示例 | 你的实际值 |
|---|---|---|
| 面板域名 | panel.example.com | 请改成你自己的 |
| 节点域名 | node.example.com | 请改成你自己的 |
| 网站域名 | site.example.com | 请改成你自己的 |
| 3x-ui 面板端口 | 40000 | 以你面板实际端口为准 |
| 订阅端口 | 2096 | 以你订阅服务实际端口为准 |
| Web 反代引擎本地端口 | 8443 | 以脚本当前配置为准 |
| Xray/REALITY 本地端口 | 1443 | 以脚本当前配置为准 |
| 面板路径 | /panel/ | 以你面板设置为准 |
| 普通订阅路径 | /sub/ | 以你订阅设置为准 |
| Clash/Mihomo 路径 | /clash/ | 以你订阅设置为准 |

## 快速结论

最终你应该这样访问：

| 类型 | 正确访问方式 |
| --- | --- |
| 3x-ui 面板 | `https://panel.example.com/panel/` |
| 普通订阅 | `https://panel.example.com/sub/客户端 Subscription` |
| Clash/Mihomo | `https://panel.example.com/clash/客户端 Subscription` |
| REALITY 节点 | `node.example.com:443` 或 `服务器公网IP:443` |
| 新增网站 | `https://site.example.com/` |

不要从公网访问这些内部端口：

```text
https://panel.example.com:40000/
https://panel.example.com:2096/sub/xxxx
https://panel.example.com:8443/
https://panel.example.com:1443/
```

## 先看这张表

| 组件 | 监听位置 | 职责 |
| --- | --- | --- |
| Nginx stream | `0.0.0.0:443` | 默认入口模式，按 SNI 分流 |
| vpso-mux | `0.0.0.0:443` | TCP Peek + Splice 模式入口，和 Nginx Stream 二选一 |
| Xray/3x-ui 主入站 | `0.0.0.0:443` | Xray Fallback 模式入口，和前两者二选一 |
| Caddy 或 Nginx 本地 Web 反代 | `127.0.0.1:8443` | 托管 Web 证书，反代面板、订阅和网站 |
| 3x-ui 面板 | `127.0.0.1:40000` | 本机 HTTP 后端，不使用自带证书作为公网 HTTPS |
| 3x-ui 订阅 | `127.0.0.1:2096` | 本机 HTTP 后端，由 Web 反代引擎代理公网 HTTPS |
| REALITY / Xray 本地入站 | `127.0.0.1:1443` | 在 Nginx Stream 或 TCP Peek 模式下由入口按 SNI 转发 |

核心原则：

1. 公网 `443` 同一时间只给一个入口进程：`nginx`、`vpso-mux` 或 Xray 主入站。
2. Caddy 或 Nginx 本地 Web 反代负责浏览器 HTTPS，3x-ui 面板和订阅只作为本地 HTTP 后端。
3. REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 写外部真实 HTTPS 站点，不要写自己的面板域名。

## 3x-ui 三种入口模式配置速查

三种入口模式共享同一套 Web 配置：面板域名、订阅路径、网站反代、Web 反代引擎、本地 TLS 端口、证书和 Web 白名单都一样。区别只是谁监听公网 `443`，以及 3x-ui/Xray 主入站是否需要直接占用公网 `443`。

### Web 反代引擎选择

首次配置 `[2 首次配置 / 安装 443 单入口]` 时可以选择 Caddy 或 Nginx 作为 443 单入口下的本地 Web 反代引擎。后续也可以从：

```text
主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [8 切换 Web 反代引擎]
```

切换时脚本会复用当前域名、证书、后端和 Web 白名单，重新渲染所选引擎配置，并把另一套 443 本地 Web 反代配置隔离起来，避免 Caddy/Nginx 同时处理同一批 443 Web 域名。证书路径仍保持 `/etc/caddy/certs/${domain}.crt|key` 和 `/root/cert/${domain}.crt|key`，不改变证书策略。

如果之前在 `主菜单 [4 反代]` 配过独立 Caddy/Nginx HTTPS 反代，启用或重新应用 443 单入口时，脚本会隔离这些可能抢占公网 `443` 的旧配置。之后新增网站请统一走 `[19] -> [8 管理 Web 域名/反代]`。

### 三种模式都相同的 3x-ui 设置

这些设置在 Nginx Stream、TCP Peek + Splice、Xray Fallback 三种模式下都一样：

| 3x-ui 位置 | 应填写的内容 |
| --- | --- |
| 面板设置 -> 常规 -> 面板监听 IP | `127.0.0.1` |
| 面板设置 -> 常规 -> 面板端口 | `40000`，或你的实际面板端口 |
| 面板设置 -> 常规 -> url 根路径 / webBasePath | `/panel/`，或你的实际面板路径 |
| 面板设置 -> 常规 -> webDomain / 监听域名 | 留空；443 单入口会有意清空 3x-ui `webDomain`，公网域名由 Web 反代引擎接管 |
| 面板设置 -> 常规 -> 面板证书路径/私钥路径 | 清空 |
| 订阅设置 -> 监听 IP | `127.0.0.1` |
| 订阅设置 -> 监听端口 | `2096`，或你的实际订阅端口 |
| 订阅设置 -> URI 路径 | `/sub/`，或你的实际普通订阅路径前缀 |
| 订阅设置 -> Clash/Mihomo URI 路径 | `/clash/`，或你的实际 Clash/Mihomo 路径前缀 |
| 订阅设置 -> 证书路径/私钥路径 | 清空 |

443 跑通后，订阅反向代理 URI 建议填写公网 HTTPS 地址：

```text
普通订阅反向代理 URI：https://panel.example.com/sub/
Clash/Mihomo 反向代理 URI：https://panel.example.com/clash/
```

`panel.example.com`、`/sub/`、`/clash/` 都是示例值，请替换成你的实际面板域名和路径。

### 3x-ui 3.4.0+ Hosts / 旧版 External Proxy

3x-ui v3.4.0 及之后，订阅节点公网地址在左侧侧边栏 `Hosts / 主机` 里配置。旧版 3x-ui 仍使用入站里的 `External Proxy`。

3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host：

```text
入站：选择对应的 REALITY 或本地 Xray 入站
地址：node.example.com 或服务器公网 IP
端口：443
Security：相同，或按该入站实际安全类型填写
SNI / Fingerprint / ALPN：按该入站和客户端实际值保持一致
```

3x-ui v3.3.1 及之前：在对应 REALITY 入站里打开 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

升级前已经设置 `External Proxy` 的面板，升级后仍应检查 `Hosts / 主机` 中地址和端口是否为公网 `443`。

### 模式 1：Nginx Stream

这是默认稳定模式。3x-ui/Xray 节点入站不要监听公网 `443`，只监听本机端口。

| 3x-ui / Xray 入站设置 | 示例值 |
| --- | --- |
| REALITY 或其他本地 Xray 入站监听地址 | `127.0.0.1` |
| REALITY 或其他本地 Xray 入站监听端口 | `1443`，或你的实际本地入站端口 |
| 客户端连接地址 | `node.example.com` 或服务器公网 IP |
| 客户端连接端口 | `443` |
| REALITY `dest` / `Target` | 外部真实 HTTPS 站点，例如 `www.microsoft.com:443` |
| REALITY `serverNames` / `SNI` | 同一个外部真实 HTTPS 站点，例如 `www.microsoft.com` |
| Hosts / External Proxy | 3x-ui v3.4.0+ 在 `Hosts / 主机` 中新增 Host；旧版在入站 `External Proxy` 中设置。地址填 `node.example.com` 或服务器公网 IP，端口填 `443` |

如果要多个本地 Xray 入站共用公网 `443`，先在 3x-ui 里创建多个本地入站，每个入站使用不同的 `127.0.0.1:端口`，再到：

```text
主菜单 [19 443 单入口管理中心] -> [15 Xray 入站管理]
```

只记录 `SNI -> 本地地址:端口`，用于当前支持的单入口模式渲染分流规则。脚本不会创建、删除或修改 3x-ui/Xray 入站内部配置。

### 模式 2：TCP Peek + Splice

TCP Peek + Splice 模式下，配置过程和 Nginx Stream 一样：面板、订阅和 Xray 入站仍然监听本机地址，客户端仍然连接公网 `443`。切换 TCP Peek 时复用同一套域名、证书、Web 反代后端、Web 白名单和 Xray SNI 分流记录。

| 项目 | 说明 |
| --- | --- |
| 3x-ui 面板和订阅 | 保持 `127.0.0.1` 本地 HTTP 后端，证书路径清空 |
| REALITY 或其他 Xray 入站 | 保持 `127.0.0.1:1443` 这类本地监听 |
| 客户端连接端口 | 仍然是 `443` |
| Hosts / External Proxy | 仍然输出 `node.example.com:443` 或 `服务器公网 IP:443` |
| Xray 入站管理 | 和 Nginx Stream 一样支持多个本地 Xray 入站按 SNI 分流 |

从 Nginx Stream 切到 TCP Peek + Splice 时，通常不需要改 3x-ui 面板里的任何配置。变化的是公网 `443` 的监听进程：从 `nginx` 换成 `vpso-mux`。

TCP Peek 的优点：

1. 配置过程和 Nginx Stream 相同，不需要重新填写 3x-ui、Web 反代引擎、证书或 Xray SNI 路由。
2. `MSG_PEEK` 只查看 ClientHello，不消费首包，后端仍收到原始 TLS 握手。
3. 转发优先使用 splice，减少用户态数据拷贝；不可用时自动回退普通 copy。
4. `vpso-mux` 有独立状态、日志、配置校验和 8444 预检，方便确认切换前后链路。

切换前检查：

1. TCP Peek 切换流程不会再在公网 `443` 切换过程中自动下载 Go 工具链或远端编译 `vpso-mux`。
2. 第一次使用 TCP Peek 前，先运行 `主菜单 [19] -> [16] 查看 TCP Peek + Splice 状态 / 8444 预检`。这个步骤只监听 `8444`，不会替换公网 `443`。
3. `[16]` 通过后，再运行 `[17] TCP Peek 分流规则校验`，最后用 `[5] 切换到 TCP Peek + Splice 模式`。切换前脚本还会自动再跑一次独立 `8444` 预检，失败就不动公网 `443`。
4. 如果当前 SSH 会话本身连接在公网入口端口，例如 `443`，脚本会拒绝切换。请改用云厂商 VNC/Serial Console，或先用非入口端口的 SSH 登录。
5. TCP Peek 切换前，Web 反代引擎本地端口和 Xray/REALITY 本地入站都必须能连通；如果 `127.0.0.1:1443` 这类本地入站没监听，先在 3x-ui 启用对应入站或把脚本保存的端口改成实际值。

首次配置只需要跑同一套 `[2 首次配置 / 安装 443 单入口]` 向导。等共享配置、证书、Web 反代引擎和 3x-ui 本地端口都跑通后，再按上面的 `[16] -> [17] -> [5]` 流程把公网入口进程切到 TCP Peek。

### 模式 3：Xray Fallback

Xray Fallback 是特殊模式。公网 `443` 由你已经配置好的 3x-ui/Xray 主入站监听，HTTPS 再由这个主入站 fallback 到当前 Web 反代引擎本地端口。脚本不会替你编辑 3x-ui/Xray 入站内部配置。

切到 xray-fallback 之前，你需要先在 3x-ui 里准备一个“主入站”：

| 3x-ui / Xray 主入站设置 | 示例值 |
| --- | --- |
| 主入站监听地址 | `0.0.0.0`，或面板允许的公网监听方式 |
| 主入站监听端口 | `443` |
| fallback / fallback dest / 回落目标 | `127.0.0.1:8443`，端口以脚本里的 Web 反代引擎本地端口为准 |
| 客户端连接地址 | `node.example.com` 或服务器公网 IP |
| 客户端连接端口 | `443` |
| Hosts / External Proxy | 如果订阅链接没有输出 `:443`，3x-ui v3.4.0+ 在 `Hosts / 主机` 中设置；旧版在入站 `External Proxy` 中设置。地址填节点域名或服务器公网 IP，端口填 `443` |

Web 面板和订阅仍然走当前 Web 反代引擎，所以面板证书路径、订阅证书路径仍然必须清空。`panel.example.com` 访问链路应是：

```text
浏览器 -> 公网 443 -> Xray 主入站 fallback -> Web 反代引擎 127.0.0.1:8443 -> 3x-ui 面板/订阅
```

xray-fallback 模式不支持脚本继续把多个 SNI 分流到多个本地 Xray 入站。`Xray 入站管理` 菜单只能查看已有规则和当前主入站候选，不能新增、删除或同步规则。需要多个本地 Xray 入站时，请使用 Nginx Stream 或 TCP Peek + Splice。

如果你的主入站是 REALITY，请确认你使用的 3x-ui/Xray 入站类型确实能把 HTTPS fallback 到当前 Web 反代引擎。本脚本只检查公网 `443` 是否由 Xray 监听、Web 反代引擎 fallback 后端是否可达，不会替你生成 Xray fallback 规则。

### 模式切换时 3x-ui 要不要改

| 切换方向 | 3x-ui 需要做什么 |
| --- | --- |
| Nginx Stream -> TCP Peek + Splice | 通常不用改 3x-ui。保持面板/订阅/Xray 入站都监听本机地址，客户端端口仍是 `443`。 |
| TCP Peek + Splice -> Nginx Stream | 通常不用改 3x-ui。切回后公网 `443` 由 Nginx stream 监听。 |
| Nginx Stream 或 TCP Peek + Splice -> Xray Fallback | 先在 3x-ui 里把一个主入站改为公网 `443`，并配置 fallback 到 Web 反代引擎本地端口，再执行脚本切换。 |
| Xray Fallback -> Nginx Stream 或 TCP Peek + Splice | 先把 3x-ui/Xray 主入站从公网 `443` 移走，改回 `127.0.0.1:1443` 这类本地端口，或先禁用该公网 443 主入站，再执行脚本切换。 |
| 重新应用当前模式 | 如果只是重建配置，不需要改 3x-ui；如果你改过面板端口、订阅路径或 Xray 本地端口，先在 `[10 修改 443 共享参数]` 同步脚本保存值。 |

从 xray-fallback 切回 Nginx Stream 或 TCP Peek + Splice 前，最容易出错的是忘记把 3x-ui/Xray 主入站从公网 `443` 移走。否则 Nginx 或 `vpso-mux` 会和 Xray 抢同一个公网端口，切换会失败或自动回滚。

### 切换前后检查清单

切换前检查：

```text
主菜单 [19 443 单入口管理中心] -> [1 查看当前入口状态 / 监听详情]
ss -lntp | grep ':443'
```

TCP Peek + Splice 切换检查：

```text
主菜单 [19 443 单入口管理中心] -> [16 查看 TCP Peek + Splice 状态 / 8444 预检]
主菜单 [19 443 单入口管理中心] -> [17 TCP Peek 分流规则校验]
主菜单 [19 443 单入口管理中心] -> [5 切换到 TCP Peek + Splice 模式]
```

只有 `8444` 预检和分流规则校验通过后，再执行 `[5] 切换到 TCP Peek + Splice 模式`。如需撤销最近一次入口模式切换，使用 `主菜单 [19 443 单入口管理中心] -> [7 回滚上一次入口模式切换]`。

切换后检查：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
主菜单 [19 443 单入口管理中心] -> [14 443 网络访问测试]
```

预期监听方：

| ENTRY_MODE | 公网 443 应由谁监听 |
| --- | --- |
| `nginx-stream` | `nginx` |
| `tcp-peek` | `vpso-mux` |
| `xray-fallback` | `xray` / `3x-ui` / `x-ui` 托管的 Xray |

`ENTRY_MODE` 的新配置值只写入 `nginx-stream`、`xray-fallback`、`tcp-peek`。如果旧配置里没有 `ENTRY_MODE`，脚本按 `nginx-stream` 读取；如果旧配置或 `/etc/vps-optimize/443-engine.conf` 里还有 `nginx_stream`、`xray_fallback`、`tcp_peek`，脚本会按对应的新值兼容读取。单个简单赋值会自动改写为新命名；无法安全改写时，状态页会继续提示迁移。

无论哪种模式，都不要让 Web 反代引擎、3x-ui 面板端口、订阅端口或额外本地入站直接暴露公网。

## Xray 入站管理边界

`Xray 入站管理` 只记录 `SNI -> 本地地址:端口` 分流记录，用于当前支持的单入口模式渲染分流规则，它不是 3x-ui/Xray 入站编辑器。用户需要先在 3x-ui/Xray 中创建并启用本地入站，然后再把对应的 SNI、本地监听地址和端口写入脚本。

TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Web 反代引擎或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。

Nginx Stream 模式和 TCP Peek + Splice 模式支持根据同一份 Xray 入站分流规则，把多个 SNI 转发到多个本地 Xray 入站。Web 域名仍然转发到当前 Web 反代引擎，Xray 入站不受 Web 白名单影响。

Xray 本身可以有多个入站。但在 xray-fallback 模式下，公网 `443` 默认由一个 Xray 主入站接管。脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。如需多个本地 Xray 入站分流，请使用 Nginx Stream 模式或 TCP Peek + Splice 模式。

切换到 xray-fallback 后，脚本会保留 `/etc/vps-optimize/xray-sni-routes.conf` 中已有的规则，不会删除。被选中的规则作为 xray-fallback 主入站使用；其他规则会标记为“已保留，但当前 xray-fallback 模式下不生效”。以后切回 Nginx Stream 模式或 TCP Peek + Splice 模式时，这些规则可以重新用于按 SNI 分流。

xray-fallback 模式下，`Xray 入站管理` 菜单允许查看规则和当前主入站，但不允许新增、删除或同步规则。本脚本不会自动修改 3x-ui/Xray 入站内部配置。

## 普通 TLS 与 REALITY 的区别

普通 TLS 节点更关注本机证书、Web fallback、Host/SNI 是否匹配。例如 VLESS + TLS、Trojan + TLS、VMess + WS + TLS、VLESS + gRPC + TLS 这类节点，排查时应确认节点域名是否由用户控制、本机证书是否覆盖该 SNI、Web 反代引擎是否有匹配 fallback，以及浏览器访问是否返回 200/301/302。

REALITY 节点不同。REALITY 更关注外部目标站点是否真实可访问、TLS 特征是否稳定、`serverName` 和 `dest` 是否逻辑一致。不要要求 REALITY `serverName` 加入 Web 反代引擎，也不要要求本机证书覆盖 REALITY `serverName`。

## 证书策略

443 单入口继续使用 `acme.sh + Cloudflare DNS API` 签发和安装 Web 域名证书。不使用 Caddy DNS 模块，不需要 `xcaddy`，也不让 Caddy 负责 DNS-01 证书申请。

3x-ui 安装阶段出现的证书选择，只是为了完成 3x-ui 安装流程；它不是 443 单入口最终使用的证书方案。最终架构是：公网 HTTPS 由当前 Web 反代引擎统一处理，3x-ui 面板和订阅只作为本地 HTTP 后端。

## 域名 IP 白名单

如果只想让固定 IP 访问 3x-ui 面板域名，可以给指定 Web 域名启用 IP 白名单。这个限制是“按域名”生效的：给 `panel.example.com` 加白名单，只会限制这个 Web 域名；没有加入白名单的站点域名、Xray 入站、REALITY SNI 和未知 SNI 会继续按原来的 443 分流规则工作。

两种部署方式的实现不同：

| 部署方式 | 使用入口 | 生效位置 | 影响范围 |
| --- | --- | --- | --- |
| 未启用 443 单入口，只用 Caddy/Nginx 反代 | 新增时用 `主菜单 [4 反代] -> [1 添加 Caddy 反代]` 或 `[2 添加 Nginx HTTPS 反代]`；已有域名用 `[4] -> [5 域名 IP 白名单]`；直接编辑配置用 `[4] -> [6 查看/编辑已应用配置文件]` | Caddy 当前域名站点块使用 `remote_ip` 匹配；Nginx HTTPS 反代使用 `allow/deny` 匹配 | 只影响当前 Caddy/Nginx Web 域名 |
| 已启用 443 Nginx Stream 单入口 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]` | Nginx stream 入口层，按 `SNI + 源 IP` 判断 | 只影响被选择的 SNI 域名 |
| 已启用 443 TCP Peek + Splice 单入口 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]` | vpso-mux 入口层，按 `SNI + 源 IP` 判断 | 只影响被选择的 SNI 域名 |
| `xray-fallback` + Nginx 本地 Web 反代 | 不允许新增或覆盖 Web 白名单 | 禁止使用；Xray fallback 到本地 Nginx 后无法可靠获得真实客户端源 IP | 如需白名单，请切到 Nginx Stream/TCP Peek，或选择 Caddy 作为 Web 反代引擎 |

白名单支持单个 IP 和 CIDR，例如：

```text
1.2.3.4
1.2.3.0/24
2001:db8::/32
```

启用前请把当前管理 IP 放进白名单，否则可能把自己挡在面板外。脚本会提示当前 SSH 来源 IP，并会自动尝试把 VPS 本机公网 IPv4/IPv6、loopback 地址和当前 Docker 网络子网加入白名单；如果自动探测失败，请手动补上 VPS 公网 IP 或订阅工具所在的 Docker 子网。

注意：本方案建议相关域名保持 Cloudflare 灰云 / DNS only。若域名开了橙云代理，服务器看到的源 IP 可能是 Cloudflare 边缘 IP，而不是你的真实访问 IP，白名单应改为 Cloudflare 边缘段或先关闭代理。

## 准备工作

至少准备一个面板域名：

```text
panel.example.com -> 当前 VPS IP
```

建议再准备一个节点域名：

```text
node.example.com -> 当前 VPS IP
```

Cloudflare 建议：

| 域名 | 建议 |
| --- | --- |
| 面板域名 | 灰云 / DNS only |
| 节点域名 | 灰云 / DNS only，必须能直连 VPS |
| 网站或反代域名 | 灰云 / DNS only |
| REALITY 伪装 SNI | 写外部真实 HTTPS 站点，不要指向你的 VPS |

不推荐给本方案相关域名开启 Cloudflare 代理。灰云直连更适合 Nginx stream 按 SNI 分流，也能减少 REALITY、订阅链接和 Hosts / External Proxy 的异常。

REALITY 伪装 SNI 建议选没有 CDN 防护、HTTPS 稳定、国内外都容易访问的外部网站。不要选自己的面板域名、节点域名、订阅域名，也不要选会频繁跳转、拦截异常请求或强制人机验证的网站。

如果使用 Cloudflare DNS 签证书，API Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

## 推荐部署流程

按这个顺序走，最不容易绕晕：

```text
1. 准备域名和 Cloudflare Token
2. 安装 3x-ui
3. 让 3x-ui 面板和订阅使用 Skip SSL / 本机 HTTP 后端
4. 配置 REALITY 入站
5. 进入 `主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]`
6. 回到 3x-ui 收尾：确认本机监听、订阅反代 URI、Hosts / External Proxy
7. 进入 `主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]`
```

### 1. 安装 3x-ui

3x-ui 3.x 新安装如果询问 SSL certificate setup method，选择 `Skip SSL / 不申请 SSL`。2.x 或旧配置如果已经设置过 SSL 证书，接入 443 前清空面板和订阅证书路径。

| 安装器选项 | 在本教程中的作用 | 后续处理 |
|---|---|---|
| Skip SSL / 不申请 SSL | 推荐，直接作为本机 HTTP 后端 | 继续设置本机监听 |
| 为域名申请证书 | 可用于临时完成 3x-ui 安装 | 接入 443 前清空 3x-ui 证书路径 |
| 为 IP 申请证书 | 仅作为临时过渡，不推荐作为正式公网 HTTPS | 接入 443 前清空 3x-ui 证书路径 |
| 选择已有证书路径 | 可用于临时完成安装 | 接入 443 前清空 3x-ui 证书路径 |

示例：

```text
证书域名：panel.example.com
是否设置给面板：可以选择是
```

上面的值只是示例，请替换成你的实际域名。后面正式接入 443 单入口时，需要把 3x-ui 自带证书路径清空，让 Web 反代引擎接管公网 HTTPS。

建议自定义这些值，并记下来：

```text
面板端口：40000
面板 url 根路径：/panel/
用户名/密码：自己设置
监听 IP：127.0.0.1
SSL：Skip SSL / 不申请 SSL
```

本机后端检查地址：

```text
http://127.0.0.1:40000/panel/
```

如果你的端口或路径不同，替换成自己的值。面板路径建议带前后 `/`。

### 2. 清空 3x-ui 面板证书

只要你准备接入 VPS-Optimize 的 443 单入口，就应清空 3x-ui 面板和订阅证书路径，让 Web 反代引擎接管公网 HTTPS。

进入：

```text
面板设置 -> 常规 -> 证书
```

把下面这类路径全部清空：

```text
证书路径
私钥路径
公钥文件路径
私钥文件路径
```

保存并重启面板。

如果不清空，可能导致 502 Bad Gateway、HTTP/HTTPS 后端协议不匹配、重定向循环、证书路径混乱、面板或订阅异常。

清空后，3x-ui 面板只作为本机 HTTP 后端：

```text
http://127.0.0.1:40000/panel/
```

公网只访问 443 单入口地址：`https://panel.example.com/panel/`。

### 3. 清空 3x-ui 订阅证书

进入：

```text
订阅设置 -> 证书
```

同样清空证书路径和私钥路径。接入 443 单入口后，订阅公网 HTTPS 也由当前 Web 反代引擎统一处理，3x-ui 订阅服务只作为本地 HTTP 后端。

再设置订阅服务：

```text
监听 IP：127.0.0.1
监听域名：留空
监听端口：2096
URI 路径：/sub/
反向代理 URI：https://panel.example.com/sub/
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：https://panel.example.com/clash/
```

注意：3x-ui 的 URI 路径不会自动补 `/`。请写成：

```text
/sub/
/clash/
/mihomo/
```

不要写成：

```text
sub
/sub
sub/
/sub/客户端 Subscription
```

443 向导里填的是路径前缀，例如 `/sub/`、`/clash/`，不要填域名，也不要填入站下面客户端的 `Subscription`。

### 4. 配置 REALITY 入站

在 3x-ui 新增 VLESS REALITY 入站：

```text
协议：VLESS
监听地址：127.0.0.1
监听端口：1443
传输：TCP / RAW
Security：Reality
uTLS：chrome
Target / dest：外部真实 HTTPS 站点:443，例如 www.microsoft.com:443
serverNames / SNI：同一个外部真实 HTTPS 站点，例如 www.microsoft.com
SpiderX：/
Fallbacks：留空
```

不要把 REALITY 的 `dest` 或 `serverNames` 写成：

```text
panel.example.com:443
node.example.com:443
127.0.0.1:8443
```

后续要修改 REALITY SNI，可以走：

```text
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]
```

### 5. 运行 443 首次配置

确认面板证书和订阅证书都清空后，再运行：

```text
主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]
```

示例填写：

| 项目 | 示例值 |
| --- | --- |
| 面板域名 | `panel.example.com` |
| 网站/反代域名 | 首次可以留空 |
| REALITY 伪装 SNI | `www.microsoft.com` 或其他外部真实 HTTPS 站点 |
| Nginx 公网监听地址 | `0.0.0.0` |
| Nginx 公网监听端口 | `443` |
| Web 反代引擎 | `Caddy` 或 `Nginx` |
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
| Cloudflare API Token | 你的 CF Token |

面板路径、普通订阅路径、Clash/Mihomo 路径必须和 3x-ui 里完全一致。

脚本每次首次配置、重新应用、切换 Web 反代引擎或增删网站时，都会先创建 SNI stack 备份。若 `nginx -t`、`caddy validate` 或服务重启失败，会尝试回滚，并把异常配置移入隔离目录。

常见备份和隔离目录：

```text
/etc/vps-optimize/backups/sni-stack_*
/etc/vps-optimize/quarantine/nginx-sni
/etc/vps-optimize/quarantine/nginx-sni-web
/etc/vps-optimize/quarantine/nginx-proxy-to-443-entry
/etc/vps-optimize/quarantine/caddy-sni
/etc/vps-optimize/quarantine/caddy-sni-web
/etc/vps-optimize/quarantine/caddy-certs
```

### 6. 回到 3x-ui 收尾

确认 3x-ui 仍是本机 HTTP 后端：

```text
面板监听 IP：127.0.0.1
订阅监听 IP：127.0.0.1
```

再设置订阅反向代理 URI：

```text
URI 路径：/sub/
反向代理 URI：https://panel.example.com/sub/

URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：https://panel.example.com/clash/
```

如果你的路径是 `/sublinkqq/` 或 `/mihomo/`，反向代理 URI 也要同步：

```text
https://panel.example.com/sublinkqq/
https://panel.example.com/mihomo/
```

然后按 3x-ui 版本设置节点公网地址。

3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host：

```text
入站：选择对应的 REALITY 或本地 Xray 入站
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

保存后重新复制节点链接，端口应该是 `:443`。如果还是 `:1443`，3x-ui v3.4.0+ 请检查 `Hosts / 主机`，旧版请检查 `External Proxy`。

最后运行：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 后续维护

不要为了小改动重跑首次配置。常用入口如下：

| 你想做什么 | 入口 |
| --- | --- |
| 新增网站或反代域名 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` |
| 切换 Caddy/Nginx Web 反代引擎 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [8 切换 Web 反代引擎]` |
| 检查 443 链路 | `主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]` |
| 修改面板/订阅端口与路径 | `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [1 修改面板/订阅端口与路径]` |
| 修改 REALITY 本地监听 / 伪装 SNI | `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]` |
| 修改 Nginx / Web 反代监听 | `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [3 修改 Nginx 公网入口 / Web 反代本地 TLS]` |
| 修改面板域名 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [9 修改面板域名]` |
| 重新应用当前配置 | `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [5 重新应用当前保存的配置]` |
| 证书维护 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]` |
| 回滚 443 单入口配置 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]` 中的回滚入口 |

新增网站时，只填本机后端：

```text
网站域名：dockge.example.com
后端监听地址：127.0.0.1
后端端口：5001
```

然后浏览器访问：

```text
https://dockge.example.com/
```

适合接入的服务包括 SublinkPro、Sub-Store、Dockge、Komari、博客和其他本机 HTTP 服务。

## 排错入口

遇到面板打不开、订阅 404、证书失败、端口被占用或 REALITY 连接失败，统一看：[443 单入口排错手册](443-single-entry-troubleshooting.md)。

## 一组完整示例，仅供参考

```text
面板：https://panel.example.com/panel/
普通订阅：https://panel.example.com/sub/客户端 Subscription
Clash/Mihomo：https://panel.example.com/clash/客户端 Subscription
REALITY 节点：node.example.com:443

3x-ui 面板监听：127.0.0.1:40000
3x-ui 订阅监听：127.0.0.1:2096
REALITY 入站监听：127.0.0.1:1443
Web 反代引擎监听：127.0.0.1:8443（示例，实际以脚本当前配置为准）
公网 443 入口监听：当前 ENTRY_MODE 对应服务（nginx-stream=nginx；xray-fallback=Xray 主入站；tcp-peek=vpso-mux）
```

## 绝对不要这样做

```text
公网访问 https://panel.example.com:40000/
公网访问 https://panel.example.com:2096/sub/xxxx
把 REALITY dest 写成 panel.example.com:443
把 REALITY serverNames 写成面板域名
3x-ui 证书路径没清空就跑 443 分流
订阅 URI 路径写成 sub 或 /sub
把客户端 Subscription 填进 443 向导的路径前缀
让 Web 反代引擎、Xray、3x-ui 面板同时抢公网 443
```
