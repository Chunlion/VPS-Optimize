# 443 单入口分流详细教程

这篇文档解释脚本里的 **Nginx Stream + Caddy + REALITY 443 单入口分流**。它适合想把面板、订阅、REALITY 节点、多个网站或订阅管理工具都收进同一个公网 `443` 入口的场景。

## 1. 这套架构解决什么问题

传统做法经常会出现几个服务抢端口：

- 3x-ui 面板想用 `443`
- Xray REALITY 想用 `443`
- Caddy/Nginx 网站也想用 `443`
- 订阅链接又容易生成 `127.0.0.1:40000` 或 `:1443`

单入口模式的目标很简单：

```text
公网唯一入口：0.0.0.0:443 -> Nginx stream
```

Nginx 不解密 TLS，只看客户端握手里的 SNI 域名，然后分流：

```text
面板域名 panel.example.com
-> 127.0.0.1:8443
-> Caddy 终止 TLS
-> 127.0.0.1:40000
-> 3x-ui 面板

网站/反代域名 site.example.com
-> 127.0.0.1:8443
-> Caddy 终止 TLS
-> 127.0.0.1:3000
-> SublinkPro / Dockge / 博客 / 订阅管理工具 / 普通 HTTP 服务

REALITY 伪装 SNI your-reality-sni.example.com
-> 127.0.0.1:1443
-> Xray 或 3x-ui REALITY 入站

未知 SNI
-> 127.0.0.1:1443
-> Xray 或 3x-ui REALITY 入站
```

最终公网只需要放行 `443` 和 SSH 端口。`8443`、`1443`、`40000`、`2096`、`3000` 这类端口默认都只监听 `127.0.0.1`。

## 2. 首次配置怎么进入

脚本菜单路径：

```text
3. 软件安装与反代分流
18. 443 单入口分流向导
```

建议普通用户一路使用默认本地监听：

```text
面板域名：panel.example.com
网站/反代域名：可留空，也可以填多个，用英文逗号分隔
REALITY 伪装 SNI：your-reality-sni.example.com
Nginx 公网监听地址：0.0.0.0
Nginx 公网监听端口：443
Caddy 本地监听地址：127.0.0.1
Caddy 本地监听端口：8443
Xray REALITY 本地监听地址：127.0.0.1
Xray REALITY 本地监听端口：1443
3x-ui 面板监听地址：127.0.0.1
3x-ui 面板端口：40000
3x-ui 订阅服务监听地址：127.0.0.1
3x-ui 订阅服务端口：2096
网站/反代后端地址：127.0.0.1
网站/反代后端端口：3000
Cloudflare API Token：用于 DNS 签发证书
```

注意：

- 面板域名、网站/反代域名、REALITY SNI 不能相同。
- REALITY SNI 必须是外部真实 HTTPS 站点，不要照抄模板域名。
- 不建议选择有 CDN 防护、会拦截非浏览器 TLS 指纹、会跳人机验证的网站做 REALITY SNI。
- Caddy 不监听公网 `443`，Xray/3x-ui REALITY 也不监听公网 `443`。
- 3x-ui 面板不要暴露公网 `40000`。

Cloudflare Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

## 3. 后续新增网站，不用重跑完整向导

如果已经跑过一次 `[18] 443 单入口分流向导`，后续新增网站走独立入口：

```text
3. 软件安装与反代分流
20. 管理 443 网站/反代域名
2. 新增网站/反代域名
```

也可以从维护菜单进入：

```text
3. 软件安装与反代分流
19. CF DNS / Caddy 维护菜单
15. 管理 443 网站/反代域名
```

例如新增三个服务：

```text
sub.example.com      -> 127.0.0.1:3000  -> SublinkPro
dockge.example.com   -> 127.0.0.1:5001  -> Dockge
mmw.example.com      -> 127.0.0.1:8080  -> 妙妙屋订阅管理
```

新增流程会自动做这些事：

- 读取 `/etc/vps-optimize/sni-stack.env` 中上次保存的 443 配置。
- 为新域名使用 Cloudflare DNS 申请证书。
- 写入 `/etc/caddy/conf.d/域名.caddy`。
- 更新 `/etc/nginx/stream.d/vps_sni_端口.conf` 的 SNI 分流表。
- 校验 `nginx -t` 和 `caddy validate`。
- 重启 Nginx 与 Caddy。
- 更新 `/etc/vps-optimize/sni-stack.env`。

新增网站时，后端服务本身需要已经在本机监听对应端口。例如 Dockge 监听 `127.0.0.1:5001`，那脚本里就填：

```text
网站/反代域名：dockge.example.com
后端监听地址：127.0.0.1
后端端口：5001
```

浏览器访问的是：

```text
https://dockge.example.com/
```

不要访问：

```text
https://dockge.example.com:5001/
https://dockge.example.com:8443/
```

## 4. 3x-ui 面板怎么设置

脚本配置好 Caddy 后，3x-ui 面板不要再填写 SSL 证书路径。

推荐设置：

```text
面板监听地址：127.0.0.1
面板端口：40000
webBasePath：/
面板 SSL / HTTPS：关闭
证书路径：留空
私钥路径：留空
Panel URL / Public URL / External URL：https://panel.example.com/
Subscription URI Path：/sub/
Subscription External URL：https://panel.example.com/sub/
```

原因是证书由 Caddy 负责：

```text
浏览器 HTTPS -> Nginx stream -> Caddy 终止 TLS -> HTTP 反代到 3x-ui
```

如果又在 3x-ui 里启用面板 SSL，常见结果是：

- `ERR_TOO_MANY_REDIRECTS`
- `502 Bad Gateway`
- 面板打不开
- 订阅链接生成异常

## 5. 3x-ui REALITY 入站怎么设置

在 3x-ui 新增或编辑 VLESS 入站：

```text
协议：vless
监听：127.0.0.1
端口：1443
传输：TCP (RAW)
decryption：none
Fallbacks：留空
安全：Reality
uTLS：chrome
Target / dest：your-reality-sni.example.com:443
SNI / serverNames：your-reality-sni.example.com
SpiderX：/
```

不要把 `Target / dest` 写成：

```text
127.0.0.1:8443
panel.example.com:443
site.example.com:443
```

这套架构不再使用 Xray fallback 分流网站，网站分流由 Nginx stream 按 SNI 完成。

## 6. 订阅和 External Proxy 怎么设置

REALITY 入站真实监听在本机：

```text
127.0.0.1:1443
```

但客户端应该连接公网入口：

```text
node.example.com:443
```

所以需要在 3x-ui 入站里打开 `External Proxy`：

```text
类型：相同
地址：node.example.com
端口：443
备注：可留空
```

如果暂时没有单独节点域名，也可以填：

```text
地址：panel.example.com
端口：443
```

保存后复制节点链接，应看到类似：

```text
vless://uuid@node.example.com:443?security=reality&sni=your-reality-sni.example.com&...
```

如果链接里还是 `:1443`，说明 External Proxy 没有生效。把这个订阅交给 SublinkPro、妙妙屋或 Sub-Store 转换后，也可能继续得到错误端口。

## 7. 可以反代哪些服务

只要服务提供普通 HTTP 后端，并且能监听本机端口，就可以放到 443 分流里。

常见例子：

- `sub.example.com -> 127.0.0.1:3000`：SublinkPro
- `mmw.example.com -> 127.0.0.1:8080`：妙妙屋订阅管理
- `substore.example.com -> 127.0.0.1:9876`：Sub-Store 前端或服务
- `dockge.example.com -> 127.0.0.1:5001`：Dockge Compose 管理
- `blog.example.com -> 127.0.0.1:2368`：博客或普通网站
- `status.example.com -> 127.0.0.1:3001`：状态页

如果服务本身只支持 HTTPS 后端，暂时不要直接填进这个入口，除非你清楚 Caddy 需要额外配置 `reverse_proxy https://...` 和 TLS 校验策略。

## 8. 常见错误判断

`ERR_SSL_PROTOCOL_ERROR`：

通常是访问了内部端口，外部只访问标准 HTTPS 地址。

```text
正确：https://panel.example.com/
错误：https://panel.example.com:8443/
错误：https://panel.example.com:1443/
错误：https://panel.example.com:40000/
```

`ERR_TOO_MANY_REDIRECTS`：

通常是 3x-ui 面板还开启了 SSL 或强制 HTTPS。关闭面板 SSL，并清空证书和私钥路径。

`HTTP 404`：

先检查后端本地是否正常：

```bash
curl -I http://127.0.0.1:40000/
```

如果本地也是 404，优先检查 3x-ui 的 `webBasePath` 是否为 `/`。

`502 Bad Gateway`：

通常是后端没启动、端口填错，或后端开了 HTTPS 但 Caddy 按 HTTP 连接。

## 9. 验证命令

检查监听：

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096|:3000|:5001|:8080'
```

期望类似：

```text
0.0.0.0:443       -> nginx
127.0.0.1:8443    -> caddy
127.0.0.1:1443    -> xray / 3x-ui REALITY
127.0.0.1:40000   -> 3x-ui 面板
127.0.0.1:2096    -> 3x-ui 订阅，可选
127.0.0.1:3000    -> SublinkPro 或其他网站后端，可选
127.0.0.1:5001    -> Dockge，可选
127.0.0.1:8080    -> 妙妙屋，可选
```

检查配置：

```bash
nginx -t
caddy validate --config /etc/caddy/Caddyfile
```

测试面板证书：

```bash
openssl s_client -connect 服务器IP:443 -servername panel.example.com
```

测试 REALITY SNI：

```bash
openssl s_client -connect 服务器IP:443 -servername your-reality-sni.example.com
```

查看日志：

```bash
journalctl -u nginx -n 80 --no-pager
journalctl -u caddy -n 80 --no-pager
journalctl -u x-ui -u 3x-ui -n 80 --no-pager
```

## 10. 绝对不要这样做

- 不要让 Caddy 监听公网 `443`。
- 不要让 Xray/3x-ui REALITY 直接监听公网 `443`。
- 不要让 3x-ui 面板暴露公网 `40000`。
- 不要把 Caddy 的证书路径填进 3x-ui 面板 SSL。
- 不要把 REALITY 的 `dest/serverNames` 写成面板域名。
- 不要把网站分流继续交给 Xray fallback。
- 不要用内部端口当浏览器访问入口。

