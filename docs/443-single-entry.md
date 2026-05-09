# 443 单入口分流教程

遇到面板打不开、订阅 404、证书失败或 REALITY 连接失败时，先看：[443 单入口排错手册](443-single-entry-troubleshooting.md)。

这篇文档教你把 VPS 的公网 `443` 统一交给 Nginx stream，再按 SNI 分流到 Caddy、3x-ui 面板、订阅服务、网站反代和 REALITY 入站。

推荐架构是：

```text
公网 443 -> Nginx stream 按 SNI 分流

Web 域名        -> Caddy -> 本机 HTTP 后端
3x-ui 面板      -> Caddy -> 127.0.0.1:40000
3x-ui 订阅      -> Caddy -> 127.0.0.1:2096
REALITY SNI     -> Xray / 3x-ui REALITY -> 127.0.0.1:1443
未知 SNI        -> Xray / 3x-ui REALITY -> 127.0.0.1:1443
```

这样做的好处是：公网只暴露一个 `443`，公网 HTTPS 由 Caddy 统一处理，证书由 VPS-Optimize 使用 `acme.sh + Cloudflare DNS API` 申请和安装。3x-ui 面板和订阅服务只做本机 HTTP 后端，3x-ui 自带证书不作为最终公网证书方案，避免重复 HTTPS、端口冲突、重定向循环和证书路径混乱。

## 示例说明

本文中出现的域名、路径和端口都只是示例，方便理解架构，不是必须照抄的固定值。

例如：

- `panel.example.com` = 示例面板域名
- `node.example.com` = 示例节点域名
- `site.example.com` = 示例网站域名
- `40000` = 示例 3x-ui 面板端口
- `2096` = 示例订阅端口
- `8443` = 示例 Caddy 本地 HTTPS 端口
- `1443` = 示例 Xray/REALITY 本地端口

实际部署时，请替换成你自己的域名、路径和端口。如果你已经在脚本里填写过端口，以脚本保存的配置为准，不要盲目照抄文档示例。

| 项目 | 文档示例 | 你的实际值 |
|---|---|---|
| 面板域名 | panel.example.com | 请改成你自己的 |
| 节点域名 | node.example.com | 请改成你自己的 |
| 网站域名 | site.example.com | 请改成你自己的 |
| 3x-ui 面板端口 | 40000 | 以你面板实际端口为准 |
| 订阅端口 | 2096 | 以你订阅服务实际端口为准 |
| Caddy 本地端口 | 8443 | 以脚本当前配置为准 |
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
| Nginx stream | `0.0.0.0:443` | 公网唯一入口，按 SNI 分流 |
| Caddy | `127.0.0.1:8443` | 签发 Web 证书，反代面板、订阅和网站 |
| 3x-ui 面板 | `127.0.0.1:40000` | 本机 HTTP 后端，不使用自带证书作为公网 HTTPS |
| 3x-ui 订阅 | `127.0.0.1:2096` | 本机 HTTP 后端，由 Caddy 代理公网 HTTPS |
| REALITY 入站 | `127.0.0.1:1443` | 由 Nginx stream 转发 REALITY 流量 |

核心原则只有三条：

1. 公网 `443` 只给 Nginx stream。
2. Caddy 负责浏览器 HTTPS，3x-ui 面板和订阅只作为本地 HTTP 后端。
3. REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 写外部真实 HTTPS 站点，不要写自己的面板域名。

## Xray 入站管理边界

`Xray 入站管理` 只记录 `SNI -> 本地地址:端口` 分流记录，它不是 3x-ui 入站编辑器。用户需要先在 3x-ui 中创建并启用本地入站，然后再把对应的 SNI、本地监听地址和端口写入脚本。

TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Caddy 或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。

Nginx Stream 模式和 TCP Peek + Splice 模式支持根据同一份 Xray 入站分流规则，把多个 SNI 转发到多个本地 Xray 入站。Web 域名仍然转发到 Caddy，Xray 入站不受 Web 白名单影响。

Xray 本身可以有多个入站。但在 xray-fallback 模式下，公网 `443` 默认由一个 Xray 主入站接管。脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。如需多个本地 Xray 入站分流，请使用 Nginx Stream 模式或 TCP Peek + Splice 模式。

切换到 xray-fallback 后，脚本会保留 `/etc/vps-optimize/xray-sni-routes.conf` 中已有的规则，不会删除。被选中的规则作为 xray-fallback 主入站使用；其他规则会标记为“已保留，但当前 xray-fallback 模式下不生效”。以后切回 Nginx Stream 模式或 TCP Peek + Splice 模式时，这些规则可以重新用于按 SNI 分流。

xray-fallback 模式下，`Xray 入站管理` 菜单允许查看规则和当前主入站，但不允许新增、删除或同步规则。本脚本不会自动修改 3x-ui/Xray 入站内部配置。

## 普通 TLS 与 REALITY 的区别

普通 TLS 节点更关注本机证书、Caddy fallback、Host/SNI 是否匹配。例如 VLESS + TLS、Trojan + TLS、VMess + WS + TLS、VLESS + gRPC + TLS 这类节点，排查时应确认节点域名是否由用户控制、本机证书是否覆盖该 SNI、Caddy 是否有匹配 fallback，以及浏览器访问是否返回 200/301/302。

REALITY 节点不同。REALITY 更关注外部目标站点是否真实可访问、TLS 特征是否稳定、`serverName` 和 `dest` 是否逻辑一致。不要要求 REALITY `serverName` 加入 Caddy，也不要要求本机证书覆盖 REALITY `serverName`。

## 证书策略

443 单入口继续使用 `acme.sh + Cloudflare DNS API` 签发和安装 Web 域名证书。不使用 Caddy DNS 模块，不需要 `xcaddy`，也不让 Caddy 负责 DNS-01 证书申请。

3x-ui 安装阶段出现的证书选择，只是为了完成 3x-ui 安装流程；它不是 443 单入口最终使用的证书方案。最终架构是：公网 HTTPS 由 Caddy 统一处理，3x-ui 面板和订阅只作为本地 HTTP 后端。

## 域名 IP 白名单

如果只想让固定 IP 访问 3x-ui 面板域名，可以给指定域名启用 IP 白名单。这个限制是“按域名”生效的：给 `panel.example.com` 加白名单，只会限制这个域名；没有加入白名单的站点域名、REALITY SNI 和未知 SNI 会继续按原来的 443 分流规则工作。

两种部署方式的实现不同：

| 部署方式 | 使用入口 | 生效位置 | 影响范围 |
| --- | --- | --- | --- |
| 未启用 443 单入口，只用普通 Caddy 反代 | 新增时用 `主菜单 [3] -> [13] 普通 Caddy 反代`；已有域名用 `[3] -> [21] 普通 Caddy 域名 IP 白名单` | Caddy 当前域名站点块，使用 `remote_ip` 匹配 | 只影响当前 Caddy 域名 |
| 已启用 443 Nginx stream 单入口 | `主菜单 [19] -> [8] 管理域名 IP 白名单`，或 `[19] -> [2] -> [5]` | Nginx stream 层，按 `SNI + 源 IP` 判断 | 只影响被选择的 SNI 域名 |

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

不推荐给本方案相关域名开启 Cloudflare 代理。灰云直连更适合 Nginx stream 按 SNI 分流，也能减少 REALITY、订阅链接和 External Proxy 的异常。

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
3. 清空 3x-ui 面板和订阅证书路径
4. 配置 REALITY 入站
5. 进入 `主菜单 [19 443 单入口管理中心] -> [2 首次配置 / 安装 443 单入口]`
6. 回到 3x-ui 收尾：监听改本机、订阅反代 URI、External Proxy
7. 进入 `主菜单 [19 443 单入口管理中心] -> [11 443 链路体检]`
```

### 1. 安装 3x-ui

安装 3x-ui 时，安装器可能强制要求选择证书方式，例如为域名申请证书、为 IP 申请证书，或选择已有证书路径。这里的选择只是为了完成 3x-ui 安装流程，不是 443 单入口最终使用的证书方案。

如果安装器强制要求选择证书方式，可以先按提示选择一种方式完成安装。如果你不确定选哪个，可以临时选择为域名申请证书完成安装；后续接入 443 单入口前，需要清空 3x-ui 面板和订阅证书路径。

| 安装器选项 | 在本教程中的作用 | 后续处理 |
|---|---|---|
| 为域名申请证书 | 可用于临时完成 3x-ui 安装 | 接入 443 前清空 3x-ui 证书路径 |
| 为 IP 申请证书 | 仅作为临时过渡，不推荐作为正式公网 HTTPS | 接入 443 前清空 3x-ui 证书路径 |
| 选择已有证书路径 | 可用于临时完成安装 | 接入 443 前清空 3x-ui 证书路径 |

示例：

```text
证书域名：panel.example.com
是否设置给面板：可以选择是
```

上面的值只是示例，请替换成你的实际域名。后面正式接入 443 单入口时，需要把 3x-ui 自带证书路径清空，让 Caddy 接管公网 HTTPS。

建议自定义这些值，并记下来：

```text
面板端口：40000
面板 url 根路径：/panel/
用户名/密码：自己设置
监听 IP：首次安装阶段可以先留空或用默认
```

首次临时登录通常是：

```text
https://panel.example.com:40000/panel/
```

如果你的端口或路径不同，替换成自己的值。面板路径建议带前后 `/`。

### 2. 清空 3x-ui 面板证书

只要你准备接入 VPS-Optimize 的 443 单入口，就应清空 3x-ui 面板和订阅证书路径，让 Caddy 接管公网 HTTPS。

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

清空后，如果还需要临时从公网端口访问面板，地址会变成 HTTP：

```text
http://panel.example.com:40000/panel/
```

如果浏览器仍然跳 HTTPS，可以用无痕窗口重新测。

### 3. 清空 3x-ui 订阅证书

进入：

```text
订阅设置 -> 证书
```

同样清空证书路径和私钥路径。接入 443 单入口后，订阅公网 HTTPS 也由 Caddy 统一处理，3x-ui 订阅服务只作为本地 HTTP 后端。

再设置订阅服务：

```text
监听 IP：先留空或用默认，443 跑通后再改 127.0.0.1
监听域名：留空
监听端口：2096
URI 路径：/sub/
反向代理 URI：先留空，443 跑通后再填
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：先留空，443 跑通后再填
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
主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]
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
| Cloudflare API Token | 你的 CF Token |

面板路径、普通订阅路径、Clash/Mihomo 路径必须和 3x-ui 里完全一致。

脚本每次首次配置、重新应用或增删网站时，都会先创建 SNI stack 备份。若 `nginx -t`、`caddy validate` 或服务重启失败，会尝试回滚，并把异常配置移入隔离目录。

常见备份和隔离目录：

```text
/etc/vps-optimize/backups/sni-stack_*
/etc/vps-optimize/quarantine/nginx-sni
/etc/vps-optimize/quarantine/caddy-sni
/etc/vps-optimize/quarantine/caddy-certs
```

### 6. 回到 3x-ui 收尾

443 分流成功后，把 3x-ui 的监听改成本机：

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

然后在 REALITY 入站里打开 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

保存后重新复制节点链接，端口应该是 `:443`。如果还是 `:1443`，说明 External Proxy 没生效。

最后运行：

```text
主菜单 [19 443 单入口管理中心] -> [11 443 链路体检]
```

## 后续维护

不要为了小改动重跑首次配置。常用入口如下：

| 你想做什么 | 入口 |
| --- | --- |
| 新增网站或反代域名 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` |
| 检查 443 链路 | `主菜单 [19 443 单入口管理中心] -> [11 443 链路体检]` |
| 修改面板/订阅端口与路径 | `主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数] -> [1 修改面板/订阅端口与路径]` |
| 修改 REALITY 本地监听 / 伪装 SNI | `主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]` |
| 修改 Nginx / Caddy 监听 | `主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数] -> [3 修改 Nginx 公网入口 / Caddy 本地 TLS]` |
| 修改面板域名 | `主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数] -> [4 修改面板域名]` |
| 重新应用当前配置 | `主菜单 [19 443 单入口管理中心] -> [14 修改 443 共享参数] -> [5 重新应用当前保存的配置]` |
| 证书维护 | `主菜单 [19 443 单入口管理中心] -> [13 CF DNS / Caddy 证书维护]` |
| 回滚 443 单入口配置 | `主菜单 [19 443 单入口管理中心] -> [13 CF DNS / Caddy 证书维护]` 中的回滚入口 |

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
Caddy 监听：127.0.0.1:8443
Nginx stream 监听：0.0.0.0:443
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
让 Caddy、Xray、3x-ui 面板同时抢公网 443
```
