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
普通订阅：https://panel.example.com/你的普通订阅路径/订阅密钥
Clash/Mihomo：https://panel.example.com/你的 Clash 路径/订阅密钥
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
面板域名：可以橙云，也可以灰云
节点域名：建议灰云 / DNS only，必须能直连 VPS
REALITY 伪装 SNI：不要指向你的 VPS，不要写面板域名
```

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

然后设置订阅服务：

```text
监听 IP：先留空或用默认；443 分流完成后再改 127.0.0.1
监听域名：留空
监听端口：2096
URI 路径：/sub/，建议改成自己能记住且不容易被猜到的路径
反向代理 URI：/sub/
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：/clash/
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
/sub/673kkdohpwplhywm
```

443 向导里也填同样的路径前缀，不要带订阅密钥。

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

### 6.2 检查订阅路径和反向代理 URI

订阅设置里保持：

```text
URI 路径：/sub/
反向代理 URI：/sub/
URI 路径 (Clash)：/clash/
反向代理 URI (Clash)：/clash/
```

普通订阅公网地址应该是：

```text
https://panel.example.com/sub/订阅密钥
```

Clash/Mihomo 公网地址应该是：

```text
https://panel.example.com/clash/订阅密钥
```

不要带 `:2096`。

### 6.3 配置 External Proxy

在 REALITY 入站里打开 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

如果 `panel.example.com` 开了 Cloudflare 橙云，不要把它填到 External Proxy。REALITY 节点要直连 VPS。

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

### ERR_TOO_MANY_REDIRECTS

优先检查：

```text
3x-ui 面板设置 -> 常规 -> 证书路径是否已清空
3x-ui 订阅设置 -> 证书路径是否已清空
是否保存并重启面板
```

然后检查访问地址是否带正确根路径：

```text
https://panel.example.com/panel/
```

### HTTP 404

通常是路径不一致。

检查三处是否完全一致：

```text
3x-ui URI 路径
443 向导里的订阅路径前缀
浏览器访问路径
```

例如都应该是：

```text
/sublinkqq/
```

### 502 Bad Gateway

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

订阅不带密钥返回 404 不一定代表端口坏了，主要看是不是连接拒绝。

### 节点不能用

检查：

```text
REALITY 入站监听：127.0.0.1:1443
External Proxy：地址是 node.example.com 或服务器公网 IP，端口 443
节点域名不是 Cloudflare 橙云
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

## 9. 最终正确示例

```text
面板：https://panel.example.com/panel/
普通订阅：https://panel.example.com/sub/673kkdohpwplhywm
Clash/Mihomo：https://panel.example.com/clash/673kkdohpwplhywm
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
把订阅密钥填进 443 向导的路径前缀
让 Caddy、Xray、3x-ui 面板同时抢公网 443
```
