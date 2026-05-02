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

这样做的好处是：公网只暴露一个 `443`，Web 证书由 Caddy 统一处理，3x-ui 和订阅服务只做本机 HTTP 后端，避免重复 HTTPS、端口冲突、重定向循环和证书路径混乱。

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
| 3x-ui 面板 | `127.0.0.1:40000` | 本机 HTTP 后端，不直接对公网启用 HTTPS |
| 3x-ui 订阅 | `127.0.0.1:2096` | 本机 HTTP 后端，由 Caddy 代理 |
| REALITY 入站 | `127.0.0.1:1443` | 由 Nginx stream 转发 REALITY 流量 |

核心原则只有三条：

1. 公网 `443` 只给 Nginx stream。
2. Caddy 负责浏览器 HTTPS，3x-ui 面板和订阅不要自己开 HTTPS。
3. REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 写外部真实 HTTPS 站点，不要写自己的面板域名。

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
5. 进入 `主菜单 [19 443 单入口管理中心] -> [1 首次配置 443 单入口]`
6. 回到 3x-ui 收尾：监听改本机、订阅反代 URI、External Proxy
7. 进入 `主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]`
```

### 1. 安装 3x-ui

安装 3x-ui 时，如果安装器要求选择 SSL 证书方式，可以先让安装器正常申请证书：

```text
证书域名：panel.example.com
是否设置给面板：可以选择是
```

这样只是为了让安装顺利完成。后面正式接入 443 单入口时，需要把 3x-ui 自带证书路径清空，让 Caddy 接管公网 HTTPS。

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

同样清空证书路径和私钥路径。

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
主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]
```

### 5. 运行 443 首次配置

确认面板证书和订阅证书都清空后，再运行：

```text
主菜单 [19 443 单入口管理中心] -> [1 首次配置 443 单入口]
```

推荐填写：

| 项目 | 推荐值 |
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
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
```

## 后续维护

不要为了小改动重跑首次配置。常用入口如下：

| 你想做什么 | 入口 |
| --- | --- |
| 新增网站或反代域名 | `主菜单 [19 443 单入口管理中心] -> [2 管理网站/反代域名]` |
| 检查 443 链路 | `主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]` |
| 修改面板/订阅端口与路径 | `主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [1 修改面板/订阅端口与路径]` |
| 修改 REALITY 本地监听 / 伪装 SNI | `主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]` |
| 修改 Nginx / Caddy 监听 | `主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [3 修改 Nginx 公网入口 / Caddy 本地 TLS]` |
| 修改面板域名 | `主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [4 修改面板域名]` |
| 重新应用当前配置 | `主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [5 重新应用当前保存的配置]` |
| 证书维护 | `主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护]` |
| 回滚 443 单入口配置 | `主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护]` 中的回滚入口 |

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

## 快速排错

先看这一张表定位方向：

| 报错 / 现象 | 常见原因 | 优先处理 |
| --- | --- | --- |
| `ERR_TOO_MANY_REDIRECTS` | 3x-ui 仍启用 HTTPS，和 Caddy 重复跳转 | 清空面板和订阅证书路径，重新应用配置 |
| `ERR_EMPTY_RESPONSE` | SNI 没命中 Caddy，或流量落到 REALITY | 确认访问地址、灰云、Nginx stream 配置 |
| `ERR_CONNECTION_CLOSED` | 连接被提前关闭 | 检查 Nginx、Caddy、REALITY 监听和日志 |
| `ERR_SSL_PROTOCOL_ERROR` | 协议或端口错了 | 确认公网 `443` 只由 Nginx 监听 |
| `HTTP 404` | 路径不匹配 | 对齐 3x-ui URI、443 向导路径和访问路径 |
| `502 Bad Gateway` | Caddy 找不到后端 | 检查 3x-ui 服务、端口和 HTTP 后端 |
| 订阅链接仍带 `:2096` | 订阅反向代理 URI 没设置 | 改成 `https://面板域名/路径/` |
| 节点链接仍带 `:1443` | External Proxy 没生效 | 设置地址为节点域名或公网 IP，端口 `443` |
| 证书签发失败 | Cloudflare Token 或 DNS 问题 | 检查 Token 权限、zone、解析记录 |

### 基础检查命令

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
nginx -t
caddy validate --config /etc/caddy/Caddyfile
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

期望监听大致是：

```text
0.0.0.0:443       nginx
127.0.0.1:8443    caddy
127.0.0.1:1443    x-ui / 3x-ui / xray
127.0.0.1:40000   x-ui / 3x-ui
127.0.0.1:2096    x-ui / 3x-ui
```

### ERR_TOO_MANY_REDIRECTS

重点检查 3x-ui 是否还在启用自己的 HTTPS：

```text
3x-ui 面板设置 -> 常规 -> 证书路径是否清空
3x-ui 订阅设置 -> 证书路径是否清空
是否保存并重启面板
```

正确访问地址应带面板根路径：

```text
https://panel.example.com/panel/
```

如果你刚清空证书，浏览器仍然循环跳转，用无痕窗口重新测试。

### ERR_EMPTY_RESPONSE

先确认浏览器只访问标准 HTTPS 地址：

```text
https://panel.example.com/panel/
```

不要访问内部端口：

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

再运行：

```text
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
```

如果面板 SNI 没命中 Caddy，检查 Nginx stream 是否包含面板域名：

```bash
grep -n "panel.example.com" /etc/nginx/stream.d/*.conf
```

没有的话重新应用：

```text
主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [5 重新应用当前保存的配置]
```

### HTTP 404

404 通常不是证书问题，而是路径不一致。

如果浏览器已经能打开 HTTPS，但访问订阅地址返回 404，例如：

```text
https://panel.example.com/clash/客户端 Subscription
```

通常说明公网 `443`、证书和 Caddy 都已经工作了，问题大多出在路径分流：你访问的是 `/clash/`，但 3x-ui、443 向导或 Caddy 配置里可能写的是另一个路径。

检查这三处是否完全一致：

```text
3x-ui URI 路径
443 向导里的订阅路径前缀
浏览器访问路径
```

例如 Clash/Mihomo 使用 `/clash/` 时，三处都应该是：

```text
3x-ui URI 路径 (Clash)：/clash/
443 向导 Clash/Mihomo 路径前缀：/clash/
https://panel.example.com/clash/客户端 Subscription
```

注意：443 向导里填的是路径前缀，不要把客户端的 `Subscription` 一起填进去。

不同步时进入：

```text
主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [1 修改面板/订阅端口与路径]
```

把 `3x-ui 普通订阅路径前缀` 和 `3x-ui Clash/Mihomo 订阅路径前缀` 改成和面板里一致，然后选择重新应用配置。

如果需要手动确认 Caddy 配置，可以查看面板域名配置：

```bash
grep -n "path" /etc/caddy/conf.d/panel.example.com.caddy
grep -n "reverse_proxy" /etc/caddy/conf.d/panel.example.com.caddy
```

只使用 `/clash/` 时，Caddy 里应能看到类似配置：

```caddy
@sub path /clash /clash/*
handle @sub {
    reverse_proxy 127.0.0.1:2096 {
        header_up Host {http.request.host}
        header_up X-Forwarded-Host {http.request.host}
        header_up X-Forwarded-Proto https
        header_up X-Forwarded-Port 443
        header_up X-Real-IP {remote_host}
    }
}
```

如果普通订阅和 Clash/Mihomo 都要使用，`@sub path` 应同时包含两个路径：

```caddy
@sub path /sub /sub/* /clash /clash/*
```

手动改过 Caddy 后，记得校验并重载：

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy
```

### 502 Bad Gateway

Caddy 已经接到请求，但连不上 3x-ui 后端。先本机测试：

```bash
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
```

如果连接拒绝，说明 3x-ui 没监听对应端口。回 3x-ui 检查面板端口和订阅端口。

如果本机正常但公网 502，说明 Caddy 反代地址或端口和实际监听不一致，进入：

```text
主菜单 [19 443 单入口管理中心] -> [7 修改 443 分流参数] -> [1 修改面板/订阅端口与路径]
```

### 订阅链接仍带 :2096

回到 3x-ui：

```text
订阅设置 -> 反向代理 URI
```

填写公网地址：

```text
反向代理 URI：https://panel.example.com/sub/
反向代理 URI (Clash)：https://panel.example.com/clash/
```

不要写：

```text
https://panel.example.com:2096/sub/
http://127.0.0.1:2096/sub/
```

保存并重启面板后，重新复制订阅链接。

### 节点链接仍带 :1443

回到 3x-ui 的 REALITY 入站，设置 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

节点域名如果走 Cloudflare，必须是灰云 / DNS only。

### 证书签发失败

优先检查：

```text
Cloudflare Token 是否有 Zone.Zone.Read 和 Zone.DNS.Edit
域名是否在当前 Cloudflare 账号里
DNS 是否解析到当前 VPS
域名是否灰云 / DNS only
```

再进入维护菜单：

```text
主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护]
```

推荐顺序：

```text
1. 443 链路与安全体检
8. 更新 Cloudflare API Token
9. 重新签发某个域名证书
12. 校验并重载 Caddy
```

## 最终正确示例

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
