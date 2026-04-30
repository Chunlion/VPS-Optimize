# 443 单入口分流教程

本文档采用推荐部署方案：**公网 `443` 由 Nginx stream 统一接入并按 SNI 分流；Web 流量转交给 Caddy，由 Caddy 负责公网 TLS 证书与 HTTPS 入口；3x-ui 面板与订阅服务不直接对外提供 HTTPS，Caddy 再通过 HTTP 反向代理到本机 3x-ui 服务**。

该方案将公网入口集中在 Nginx，将 Web 证书终止点集中在 Caddy，避免 3x-ui 与反向代理之间重复启用 HTTPS 导致重定向循环、空响应、连接关闭或证书路径不一致等问题，同时也便于后续排查和维护。

组件职责如下：

| 组件 | 监听位置 | 主要作用 |
| --- | --- | --- |
| Nginx stream | `0.0.0.0:443` | 公网唯一入口，按 SNI 把流量分给 Caddy 或 REALITY |
| Caddy | `127.0.0.1:8443` | 负责 Web 域名证书、HTTPS 入口、反向代理面板和订阅 |
| 3x-ui 面板 | `127.0.0.1:40000` | 只作为本机 HTTP 后端，不直接暴露公网 HTTPS |
| 3x-ui 订阅 | `127.0.0.1:2096` | 只作为本机 HTTP 后端，由 Caddy 代理到公网 443 |
| REALITY 入站 | `127.0.0.1:1443` | 由 Nginx stream 按 REALITY SNI 转发 |

## 0. 最短结论

最终访问方式应该是：

```text
面板：https://panel.example.com/你的面板根路径/
普通订阅：https://panel.example.com/你的普通订阅路径/客户端 Subscription
Clash/Mihomo：https://panel.example.com/你的 Clash 路径/客户端 Subscription
REALITY 节点：node.example.com:443 或 服务器公网IP:443
```

不要从公网访问：

```text
https://panel.example.com:40000/
https://panel.example.com:2096/sub/xxxx
https://panel.example.com:8443/
https://panel.example.com:1443/
```

## 1. 先准备域名

至少准备：

```text
面板域名：panel.example.com -> 当前 VPS IP
节点域名：node.example.com  -> 当前 VPS IP，可选
REALITY 伪装 SNI：www.microsoft.com 这类外部真实 HTTPS 站点
```

Cloudflare 小云朵建议：

```text
面板域名：推荐灰云 / DNS only
节点域名：推荐灰云 / DNS only，必须能直连 VPS
网站/反代域名：推荐灰云 / DNS only
REALITY 伪装 SNI：不要指向你的 VPS，不要写面板域名
```

本教程不推荐开启 Cloudflare 代理。灰云能让域名直连 VPS，Nginx stream 才能稳定按 SNI 分流；也能避免 REALITY、订阅链接和 External Proxy 因为走 Cloudflare 代理而出现连接异常。

Cloudflare API Token 需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

## 2. 安装 3x-ui 面板

安装 3x-ui 时，如果安装器要求选择 SSL 证书方式，推荐：

```text
选择：为域名申请证书
域名：填写已经解析到 VPS 的面板域名，例如 panel.example.com
如果提示是否把证书设置给面板：可以选择是
```

这样做的目的，是先让安装器顺利完成。进入面板后，再把 3x-ui 自己的证书路径清空，让 Caddy 接管公网 HTTPS。

安装器如果问是否自定义，建议选择自定义：

```text
面板端口：40000，或你自己记得住的端口
面板 url 根路径：/panel/，或你自己的随机路径
用户名/密码：自己设置并记住
监听 IP：首次安装阶段不要急着设 127.0.0.1
```

首次登录通常用：

```text
https://panel.example.com:40000/panel/
```

如果你的端口或路径不同，就替换成自己的值。这里的路径必须带前后 `/`。

## 3. 清空 3x-ui 自带证书

登录 3x-ui 后，先做这个，不然后面容易出现 `ERR_TOO_MANY_REDIRECTS`。

### 3.1 清空面板证书

进入：

```text
面板设置 -> 常规 -> 证书
```

把类似下面的路径全部清空：

```text
证书路径
私钥路径
公钥文件路径
私钥文件路径
```

保存，并重启面板。

清空后，如果还要临时从公网端口访问面板，地址会变成 HTTP：

```text
http://panel.example.com:40000/panel/
```

如果浏览器仍然显示旧的 HTTPS 跳转或证书状态，建议使用无痕窗口重新测试。

### 3.2 清空订阅证书

进入：

```text
订阅设置 -> 证书
```

同样把证书路径、私钥路径全部清空。

然后先设置订阅服务的本机监听和路径：

```text
监听 IP：先留空或用默认；443 分流完成后再改 127.0.0.1
监听域名：留空
监听端口：2096
URI 路径：/sub/，建议改成自己能记住且不容易被猜到的路径
反向代理 URI：先留空，443 分流完成后再填写公网地址
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：先留空，443 分流完成后再填写公网地址
```

注意：**3x-ui 的 URI 路径不会自动补 `/`**。你必须手动写成：

```text
/subl/
/clash/
/mihomo/
```

不要写：

```text
sub
/sub
sub/
/sub/客户端 Subscription
```

443 向导里填的是路径前缀，例如 `/sub/`、`/clash/`，不要填写面板域名，也不要带入站下面客户端的 `Subscription`。

保存并重启面板。

## 4. 配置 REALITY 入站

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

`REALITY SNI` 后续可以在脚本里改：

```text
cy -> 19 -> 7 -> 2 修改 REALITY 本地监听 / 伪装 SNI
```

## 5. 配置 443 单入口

确认 3x-ui 已经清空面板证书和订阅证书后，再运行：

```text
cy -> 19 -> 1 首次配置 443 单入口
```

推荐填写：

```text
面板域名：panel.example.com
网站/反代域名：首次可以留空
REALITY 伪装 SNI：www.microsoft.com 或其他外部真实 HTTPS 站点
Nginx 公网监听地址：0.0.0.0
Nginx 公网监听端口：443
Caddy 本地监听地址：127.0.0.1
Caddy 本地监听端口：8443
Xray REALITY 本地监听地址：127.0.0.1
Xray REALITY 本地监听端口：1443
3x-ui 面板监听地址：127.0.0.1
3x-ui 面板端口：40000
3x-ui 面板公网路径 / webBasePath：/panel/
3x-ui 订阅服务监听地址：127.0.0.1
3x-ui 订阅服务端口：2096
3x-ui 普通订阅路径前缀：/sub/
3x-ui Clash/Mihomo 订阅路径前缀：/clash/
Cloudflare API Token：你的 CF Token
```

这里的面板路径、普通订阅路径、Clash/Mihomo 路径必须和 3x-ui 里完全一致。

脚本会生成：

```text
公网 443 -> Nginx stream
panel.example.com -> Caddy 127.0.0.1:8443 -> 3x-ui 面板 127.0.0.1:40000
/sub/ 和 /clash/ -> 3x-ui 订阅 127.0.0.1:2096
其他 REALITY SNI -> 3x-ui REALITY 127.0.0.1:1443
```

## 6. 443 完成后回到 3x-ui 收尾

### 6.1 把监听 IP 改成本机

443 分流已经成功后，回 3x-ui：

```text
面板监听 IP：127.0.0.1
订阅监听 IP：127.0.0.1
```

保存并重启面板。

如果你改了端口或路径，再同步脚本：

```text
cy -> 19 -> 7 -> 1 修改面板/订阅端口与路径
```

### 6.2 设置订阅反向代理 URI

443 分流跑通后，再回到 3x-ui 的订阅设置，把反向代理 URI 改成公网 443 地址：

```text
URI 路径：/sub/
反向代理 URI：https://panel.example.com/sub/
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：https://panel.example.com/clash/
```

如果你把订阅路径改成了 `/sublinkqq/` 或 `/mihomo/`，这里也要同步改成：

```text
反向代理 URI：https://panel.example.com/sublinkqq/
反向代理 URI (Clash)：https://panel.example.com/mihomo/
```

普通订阅公网地址应该是：

```text
https://panel.example.com/sub/客户端 Subscription
```

Clash/Mihomo 公网地址应该是：

```text
https://panel.example.com/clash/客户端 Subscription
```

不要带 `:2096`。

### 6.3 配置 External Proxy

在 REALITY 入站里打开 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

推荐所有用于本教程的域名都使用 Cloudflare 灰云 / DNS only。External Proxy 的地址必须能直连 VPS，可以填灰云节点域名或服务器公网 IP。

保存后复制节点链接，端口应该是：

```text
:443
```

如果还是 `:1443`，说明 External Proxy 没生效。

## 7. 后续怎么修改

不要为了小改动重跑首次配置。走这个入口：

```text
cy -> 19 -> 7 修改 443 分流参数
```

可以修改：

```text
1. 面板/订阅端口与路径
2. REALITY 本地监听 / 伪装 SNI
3. Nginx 公网入口 / Caddy 本地 TLS
4. 面板域名
5. 重新应用当前保存的配置
```

新增网站或反代服务走：

```text
cy -> 19 -> 2 管理网站/反代域名
```

可用于：

```text
SublinkPro
Sub-Store
Dockge
Komari
博客
其他本机 HTTP 服务
```

新增网站时，只填本机后端，例如：

```text
网站域名：dockge.example.com
后端监听地址：127.0.0.1
后端端口：5001
```

浏览器访问：

```text
https://dockge.example.com/
```

## 8. 快速排错

先看这一张表，定位方向后再看下面对应小节：

| 报错 / 现象 | 重点判断 | 优先处理 |
| --- | --- | --- |
| `ERR_TOO_MANY_REDIRECTS` | 3x-ui 仍在启用 HTTPS 或重复跳转 | 清空面板和订阅证书路径，确认 Caddy 反代 HTTP |
| `ERR_EMPTY_RESPONSE` | 请求没有进入正确 Web 后端 | 检查访问地址、Nginx SNI、Cloudflare 灰云 |
| `ERR_CONNECTION_CLOSED` | 连接被提前断开 | 检查 Nginx/Caddy/REALITY 监听和服务状态 |
| `ERR_SSL_PROTOCOL_ERROR` | 协议或端口错了 | 确认公网 `443` 只由 Nginx 监听 |
| `HTTP 404` | 证书大概率没问题，路径分流不匹配 | 对齐 3x-ui URI 路径、443 向导路径、Caddy `@sub path` |
| `502 Bad Gateway` | Caddy 找不到后端 | 检查 3x-ui 是否启动、端口是否一致、后端是否 HTTP |
| 订阅链接仍带 `:2096` | 订阅公网地址没设置好 | 设置订阅反向代理 URI 为 `https://面板域名/路径/` |
| 节点链接仍带 `:1443` | External Proxy 没生效 | 在 REALITY 入站里设置 External Proxy 为公网 `443` |
| 节点不能用 | REALITY 或节点地址问题 | 检查 SNI、灰云、External Proxy，必要时重启 VPS |
| 证书签发失败 | Cloudflare / DNS 问题 | 检查 Token 权限、域名 zone、DNS 解析 |

### ERR_TOO_MANY_REDIRECTS

**重点：3x-ui 面板或订阅还在启用自己的 HTTPS，导致和 Caddy 重复跳转。**

这个报错通常说明浏览器已经进入了面板域名，但 3x-ui 和反向代理之间出现了重复 HTTPS 或重复跳转。

优先检查 3x-ui 证书是否清空：

```text
3x-ui 面板设置 -> 常规 -> 证书路径是否已清空
3x-ui 订阅设置 -> 证书路径是否已清空
是否保存并重启面板
```

然后检查访问地址是否带正确根路径：

```text
https://panel.example.com/panel/
```

如果你刚刚清空过证书，浏览器仍然循环跳转，可以用无痕窗口重新测试，或者换一个浏览器测试。

VPS 上检查 Caddy 是否按 HTTP 反代本机 3x-ui：

```bash
grep -n "reverse_proxy" /etc/caddy/conf.d/panel.example.com.caddy
```

正确方向应该类似：

```text
reverse_proxy 127.0.0.1:40000
reverse_proxy 127.0.0.1:2096
```

如果你看到 `reverse_proxy https://127.0.0.1:40000`，说明还在反代 HTTPS 后端。按本教程推荐路线，应清空 3x-ui 证书路径，再重新应用 443 配置：

```text
cy -> 19 -> 7 -> 5 重新应用当前保存的配置
```

### ERR_EMPTY_RESPONSE

**重点：请求没有进入正确的 Web 后端，常见于地址写错或面板 SNI 没命中 Caddy。**

这个报错通常说明浏览器连到了入口，但对端没有返回 HTTP 内容。常见原因是访问了错误协议、错误端口、SNI 没命中 Caddy，或者流量落到了 REALITY 后端。

先确认浏览器地址必须是：

```text
https://panel.example.com/panel/
```

不要访问：

```text
http://panel.example.com/
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

然后在 VPS 上跑链路体检：

```text
cy -> 19 -> 3 443 单入口链路体检
```

如果体检提示面板 SNI 没有命中 Caddy，检查 Nginx stream 配置里是否包含面板域名：

```bash
grep -n "panel.example.com" /etc/nginx/stream.d/*.conf
```

如果没有，重新应用 443 配置：

```text
cy -> 19 -> 7 -> 5 重新应用当前保存的配置
```

如果你使用 Cloudflare，请确认本教程相关域名都是灰云 / DNS only，不推荐开启代理。

### ERR_CONNECTION_CLOSED

**重点：连接被提前关闭，优先看 Nginx stream、Caddy、REALITY 有没有按端口监听。**

这个报错通常说明 TCP/TLS 连接建立过程中被提前关闭。常见原因是 Nginx stream 把面板域名分到了 REALITY 后端，或者 Caddy 没有正常监听本地 TLS 端口。

先检查监听：

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
```

期望看到：

```text
0.0.0.0:443       nginx
127.0.0.1:8443    caddy
127.0.0.1:1443    x-ui / 3x-ui / xray
127.0.0.1:40000   x-ui / 3x-ui
127.0.0.1:2096    x-ui / 3x-ui
```

再检查配置：

```bash
nginx -t
caddy validate --config /etc/caddy/Caddyfile
systemctl restart nginx
systemctl restart caddy
```

如果 Nginx 或 Caddy 重启失败，查看日志：

```bash
journalctl -u nginx -n 80 --no-pager
journalctl -u caddy -n 80 --no-pager
```

### ERR_SSL_PROTOCOL_ERROR

**重点：协议或端口不匹配，公网 `443` 只能交给 Nginx stream。**

这个报错通常是协议层不匹配。最常见是访问了内部端口，或者公网 `443` 被 Caddy、Xray、3x-ui 多个服务同时抢占。

先确认公网只应该由 Nginx 监听 `443`：

```bash
ss -lntp | grep ':443'
```

正确结果应只有 Nginx 监听公网 `443`。Caddy 应监听 `127.0.0.1:8443`，REALITY 应监听 `127.0.0.1:1443`，3x-ui 面板应监听 `127.0.0.1:40000`。

如果 Caddy 或 3x-ui 也在监听公网 `443`，先回 3x-ui 清空证书路径并改成本机监听，再重新应用：

```text
cy -> 19 -> 7 -> 5 重新应用当前保存的配置
```

### HTTP 404

**重点：404 多数不是证书问题，而是路径分流不一致。**

如果访问订阅地址返回 404，例如：

```text
https://panel.example.com/clash/客户端 Subscription
```

通常说明证书和公网 HTTPS 已经不是主要问题，问题在路径分流：浏览器访问的是 `/clash/`，那么 3x-ui 和 Caddy 都必须使用 `/clash/` 这个订阅路径。

先检查三处是否完全一致：

```text
3x-ui URI 路径
443 向导里的订阅路径前缀
浏览器访问路径
```

例如都应该是：

```text
/sublinkqq/
```

如果你访问的是 `/clash/客户端 Subscription`，3x-ui 里应确认：

```text
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：https://panel.example.com/clash/
```

然后同步脚本里的路径：

```text
cy -> 19 -> 7 -> 1 修改面板/订阅端口与路径
```

把 `3x-ui Clash/Mihomo 订阅路径前缀` 填成：

```text
/clash/
```

保存后选择重新应用配置。

如果需要手动修复 Caddy，可以编辑面板域名配置：

```bash
nano /etc/caddy/conf.d/panel.example.com.caddy
```

确认订阅匹配包含你的真实路径，例如只使用 `/clash/` 时：

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

保存后执行：

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy
```

注意：如果普通订阅和 Clash/Mihomo 都要使用，Caddy 的 `@sub path` 应同时包含两个路径，例如：

```caddy
@sub path /sub /sub/* /clash /clash/*
```

### 502 Bad Gateway

**重点：Caddy 已经接到请求，但连不上 3x-ui 后端。**

通常是：

```text
3x-ui 没启动
端口填错
证书路径没清空，3x-ui 仍然在本机启用了 HTTPS
Caddy 连接不到 127.0.0.1:40000 或 127.0.0.1:2096
```

本机测试：

```bash
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
```

订阅不带入站下面客户端的 `Subscription` 返回 404 不一定代表端口坏了，主要看是不是连接拒绝。

如果本机 `curl` 也连接拒绝，说明 3x-ui 没监听对应端口，先回 3x-ui 检查面板端口和订阅端口。
如果本机正常、公网 502，说明 Caddy 反代地址或端口和 3x-ui 实际监听不一致，进入：

```text
cy -> 19 -> 7 -> 1 修改面板/订阅端口与路径
```

同步端口后重新应用配置。

### 订阅链接仍然带 :2096

**重点：订阅的公网地址没设置好，3x-ui 还在输出本机订阅端口。**

这个现象说明 3x-ui 生成订阅时仍在使用本机订阅端口，没有使用公网 443 地址。

443 分流跑通后，回到 3x-ui：

```text
订阅设置 -> 反向代理 URI
```

填公网地址：

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

### 节点链接仍然带 :1443

**重点：REALITY 入站的 `External Proxy` 没生效。**

这个现象说明 REALITY 入站的 `External Proxy` 没有生效，客户端还在使用本机 REALITY 入站端口。

回到 3x-ui 的 REALITY 入站，打开 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

保存后重新复制节点链接。正确链接应该类似：

```text
vless://...@node.example.com:443?...&sni=www.microsoft.com...
```

如果节点域名通过 Cloudflare 解析，必须是灰云 / DNS only。

### 节点不能用

**重点：先确认 REALITY 入站、External Proxy、节点域名灰云和 REALITY SNI。**

检查：

```text
REALITY 入站监听：127.0.0.1:1443
External Proxy：地址是 node.example.com 或服务器公网 IP，端口 443
节点域名是 Cloudflare 灰云 / DNS only
REALITY dest/serverNames 是外部真实 HTTPS 站点
```

如果你确认配置都对，但节点还是不能用，重启一次服务器：

```bash
reboot
```

重启后再跑：

```text
cy -> 19 -> 3 443 单入口链路体检
```

### 证书签发失败

**重点：证书签发失败通常和 3x-ui 无关，优先查 Cloudflare Token、域名 zone 和 DNS。**

证书签发失败通常和 3x-ui 无关，优先检查 Cloudflare Token、域名 zone 和 DNS。

确认 Cloudflare Token 权限至少有：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

确认域名在这个 Cloudflare 账号里，并且已经解析到当前 VPS。然后进入维护菜单：

```text
cy -> 19 -> 6 CF DNS / Caddy 证书维护
```

推荐顺序：

```text
1. 443 链路与安全体检
8. 更新 Cloudflare API Token
9. 重新签发某个域名证书
12. 校验并重载 Caddy
```

如果你手动验证 Caddy 配置，使用：

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy
```

## 9. 最终正确示例

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

## 10. 绝对不要这样做

```text
公网访问 https://panel.example.com:40000/
公网访问 https://panel.example.com:2096/sub/xxxx
把 REALITY dest 写成 panel.example.com:443
3x-ui 证书路径没清空就跑 443 分流
订阅 URI 路径写成 sub 或 /sub
把入站下面客户端的 Subscription 填进 443 向导的路径前缀
让 Caddy、Xray、3x-ui 面板同时抢公网 443
```
