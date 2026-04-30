# 🧩 443 单入口分流详细教程

这篇文档解释脚本里的 **Nginx Stream + Caddy + REALITY 443 单入口分流**。它适合想把面板、订阅、REALITY 节点、多个网站或订阅管理工具都收进同一个公网 `443` 入口的场景。

## 0. 先看懂这一段

一句话解释：公网只开放一个 `443`，先由 Nginx 看客户端访问的域名，再把流量转给正确的本机服务。

```text
浏览器访问 panel.example.com  -> Caddy -> 3x-ui 面板
浏览器访问 sub.example.com    -> Caddy -> 订阅管理工具/网站
客户端访问 REALITY SNI        -> Xray/3x-ui REALITY 入站
其他未知 SNI                  -> Xray/3x-ui REALITY 入站
```

你可以把它理解成：

| 组件 | 负责什么 | 是否直接暴露公网 |
| --- | --- | --- |
| Nginx stream | 公网 `443` 总入口，只按 SNI 分流，不解密内容 | 是，只暴露 `443` |
| Caddy | 处理网站、面板、订阅工具的 HTTPS 证书和反代 | 否，只监听 `127.0.0.1:8443` |
| 3x-ui 面板 | 提供 Web 管理页面 | 否，只监听 `127.0.0.1:40000` |
| REALITY 入站 | 提供节点连接 | 否，只监听 `127.0.0.1:1443` |
| 网站/订阅后端 | SublinkPro、Dockge、妙妙屋、Sub-Store 等 HTTP 服务 | 否，只监听本机端口 |

最容易踩坑的点：

- 浏览器只访问 `https://域名/`，不要访问 `:8443`、`:1443`、`:40000` 这些内部端口。
- 3x-ui 面板不要再开启自己的 SSL，证书交给 Caddy 管。
- REALITY 的 `dest` / `serverNames` 写外部真实 HTTPS 站点，不写面板域名。
- 后续新增网站走 `19 -> 2`，不要重跑首次配置。

## 1. 你需要提前准备什么

建议至少准备 2 到 3 个域名记录：

| 用途 | 示例 | 指向哪里 | 说明 |
| --- | --- | --- | --- |
| 面板域名 | `panel.example.com` | 当前 VPS IP | 浏览器打开 3x-ui 面板 |
| 节点域名 | `node.example.com` | 当前 VPS IP | 客户端连接用，可选，没有时可暂用面板域名 |
| 网站/订阅域名 | `sub.example.com` | 当前 VPS IP | SublinkPro、Dockge、Sub-Store、Komari 等 |
| REALITY 伪装 SNI | `www.microsoft.com` | 不指向你的 VPS | 必须是外部真实 HTTPS 站点 |

Cloudflare API Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

配置前再确认三件事：

- 云厂商安全组已经放行 `443` 和当前 SSH 端口。
- 当前机器没有其他服务占用公网 `443`，可用 `ss -lntp | grep ':443'` 查看。
- 已经保留当前 SSH 会话，必要时先做 VPS 快照。

## 2. 最短配置路径

第一次配置：

```text
1. 先把域名 A/AAAA 记录解析到当前 VPS
2. 进入 cy 主菜单
3. 选择 19. 443 单入口管理中心
4. 选择 1. 首次配置 443 单入口
5. 按提示填写面板域名、REALITY SNI、Cloudflare Token
6. 到 3x-ui 中关闭面板 SSL，并确认面板监听 127.0.0.1:40000
7. 到 3x-ui REALITY 入站中确认监听 127.0.0.1:1443
8. 回到脚本运行 19 -> 3 做链路体检
```

后续新增网站：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
2. 新增网站/反代域名
```

排错优先入口：

```text
19. 443 单入口管理中心
3. 443 单入口链路体检
```

## 3. 这套架构解决什么问题

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

脚本还会顺手加固 Nginx 默认错误页：

- 自动设置 `server_tokens off`，避免默认错误页显示 Nginx 具体版本号。
- 隔离 Nginx 自带默认站点，避免错误域名命中欢迎页。
- 写入 `/etc/nginx/conf.d/00-vps-default-drop.conf`，让公网 `80` 的未知访问直接 `return 444` 丢弃连接。

## 4. 首次配置怎么进入

脚本菜单路径：

```text
19. 443 单入口管理中心
1. 首次配置 443 单入口
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

### 已经有普通 Caddy 反代怎么办

如果你之前已经用普通 Caddy 反代配置过网站，需要注意：

- 普通 Caddy 反代通常会让 Caddy 直接监听公网 `80/443`。
- 443 单入口要求公网 `443` 只由 Nginx stream 监听，Caddy 改为监听 `127.0.0.1:8443`。
- 首次配置 443 单入口时，脚本会尝试隔离可能抢占 `443` 的旧式 Caddy 配置，避免端口冲突。
- 目前脚本不会自动解析旧 Caddy 配置并迁移成新的 443 单入口站点。

所以启用 443 单入口前，请先记录旧站点的：

```text
域名
后端监听地址
后端端口
后端协议
```

启用 443 单入口后，再通过下面入口手动把旧网站补录回来：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
2. 新增网站/反代域名
```

建议先执行 `16. 配置备份与回滚`，或手动备份 `/etc/caddy`。

## 5. 后续新增网站，不用重跑完整向导

如果已经跑过一次 443 单入口分流向导，后续新增网站走独立入口：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
2. 新增网站/反代域名
```

也可以从维护菜单进入：

```text
19. 443 单入口管理中心
6. CF DNS / Caddy 证书维护
15. 管理 443 网站/反代域名
```

例如新增三个服务：

```text
sub.example.com      -> 127.0.0.1:3000  -> SublinkPro
dockge.example.com   -> 127.0.0.1:5001  -> Dockge
mmw.example.com      -> 127.0.0.1:8080  -> 妙妙屋订阅管理
komari.example.com   -> 127.0.0.1:25774 -> Komari 探针监控
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

## 6. 3x-ui 面板怎么设置

脚本配置好 Caddy 后，3x-ui 面板不要再填写 SSL 证书路径。

推荐设置：

```text
面板监听地址：127.0.0.1
面板端口：40000
webBasePath：/panel-a8f3c9/
面板 SSL / HTTPS：关闭
证书路径：留空
私钥路径：留空
Panel URL / Public URL / External URL：https://panel.example.com/panel-a8f3c9/
Subscription URI Path：/sub/
Subscription External URL：https://panel.example.com/sub/
```

`webBasePath` 不建议使用根路径 `/`。建议设置一个不容易被猜到的随机路径，例如 `/panel-a8f3c9/`、`/my-xui-9d2k/`，并让面板 URL 同步带上这个路径。这样公网访问 `https://panel.example.com/` 时不会直接暴露面板登录页，能降低被批量扫描命中的概率。

原因是证书由 Caddy 负责：

```text
浏览器 HTTPS -> Nginx stream -> Caddy 终止 TLS -> HTTP 反代到 3x-ui
```

如果又在 3x-ui 里启用面板 SSL，常见结果是：

- `ERR_TOO_MANY_REDIRECTS`
- `502 Bad Gateway`
- 面板打不开
- 订阅链接生成异常

## 7. 3x-ui REALITY 入站怎么设置

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

## 8. 订阅和 External Proxy 怎么设置

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

## 9. 可以反代哪些服务

只要服务提供普通 HTTP 后端，并且能监听本机端口，就可以放到 443 分流里。

常见例子：

- `sub.example.com -> 127.0.0.1:3000`：SublinkPro
- `mmw.example.com -> 127.0.0.1:8080`：妙妙屋订阅管理
- `substore.example.com -> 127.0.0.1:9876`：Sub-Store 前端或服务
- `dockge.example.com -> 127.0.0.1:5001`：Dockge Compose 管理
- `komari.example.com -> 127.0.0.1:25774`：Komari 探针监控
- `blog.example.com -> 127.0.0.1:2368`：博客或普通网站
- `status.example.com -> 127.0.0.1:3001`：状态页

如果服务本身只支持 HTTPS 后端，暂时不要直接填进这个入口，除非你清楚 Caddy 需要额外配置 `reverse_proxy https://...` 和 TLS 校验策略。

## 10. 按现象快速排错

先看这张表，能解决大部分问题：

| 现象 | 最可能原因 | 先检查什么 |
| --- | --- | --- |
| 域名打不开 | DNS 没解析、云安全组没放行、Nginx/Caddy 未启动 | `dig 域名`、安全组、`systemctl status nginx caddy` |
| 浏览器提示 SSL 协议错误 | 访问了内部端口，或 SNI 没进 Caddy | 只访问 `https://域名/`，不要带 `:8443` |
| 面板 502 | 3x-ui 面板没启动或端口不是 `40000` | `curl -I http://127.0.0.1:40000/` |
| 面板 404 | 访问路径和 `webBasePath` 不一致 | 面板 URL 是否带 `/panel-a8f3c9/` 这类路径 |
| 面板循环跳转 | 3x-ui 面板 SSL/HTTPS 仍开启 | 关闭面板 SSL，清空证书和私钥路径 |
| 节点链接仍是 `:1443` | External Proxy 没生效 | 3x-ui 入站 External Proxy 地址和端口 |
| REALITY 不通 | 入站没监听本机 `1443`，或 SNI/dest 写错 | `ss -lntp`、REALITY `Target` / `serverNames` |
| 证书签发失败 | Cloudflare Token 权限不足或域名不在该账号 | Token 权限、域名 zone、脚本证书维护菜单 |

### 具体错误判断

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

如果本地也是 404，优先检查你访问的路径是否和 3x-ui 的 `webBasePath` 一致。例如 `webBasePath` 设置为 `/panel-a8f3c9/`，面板入口就应该访问 `https://panel.example.com/panel-a8f3c9/`。

`502 Bad Gateway`：

通常是后端没启动、端口填错，或后端开了 HTTPS 但 Caddy 按 HTTP 连接。

## 11. 验证命令

检查监听：

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096|:3000|:5001|:8080|:25774'
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
127.0.0.1:25774   -> Komari，可选
```

检查配置：

```bash
nginx -t
caddy validate --config /etc/caddy/Caddyfile
grep -n "server_tokens off" /etc/nginx/nginx.conf
cat /etc/nginx/conf.d/00-vps-default-drop.conf
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

## 12. 正确和错误示例

✅ 正确：

```text
浏览器打开：https://panel.example.com/panel-a8f3c9/
浏览器打开：https://sub.example.com/
客户端连接：node.example.com:443
3x-ui 面板监听：127.0.0.1:40000
REALITY 入站监听：127.0.0.1:1443
Caddy 监听：127.0.0.1:8443
Nginx stream 监听：0.0.0.0:443
```

❌ 错误：

```text
浏览器打开：https://panel.example.com:40000/
浏览器打开：https://panel.example.com:8443/
REALITY dest 写 panel.example.com:443
3x-ui 面板开启 SSL 并填写 Caddy 证书
Caddy 直接监听公网 0.0.0.0:443
```

## 13. 绝对不要这样做

- 不要让 Caddy 监听公网 `443`。
- 不要让 Xray/3x-ui REALITY 直接监听公网 `443`。
- 不要让 3x-ui 面板暴露公网 `40000`。
- 不要把 Caddy 的证书路径填进 3x-ui 面板 SSL。
- 不要把 REALITY 的 `dest/serverNames` 写成面板域名。
- 不要把网站分流继续交给 Xray fallback。
- 不要用内部端口当浏览器访问入口。
