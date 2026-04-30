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

- 浏览器只访问 `https://域名/你的路径/`，例如 `https://panel.example.com/panel-a8f3c9/`，不要访问 `:8443`、`:1443`、`:40000` 这些内部端口。
- 3x-ui 面板不要再开启自己的 SSL，证书交给 Caddy 管。
- REALITY 的 `dest` / `serverNames` 写外部真实 HTTPS 站点，不写面板域名。
- 后续新增网站走 `19 -> 2`，不要重跑首次配置。
- 配置顺序必须是：先把 3x-ui 面板和入站调整好，再跑 443 单入口分流。

## 1. 你需要提前准备什么

建议至少准备 2 到 3 个域名记录：

| 用途 | 示例 | 指向哪里 | 说明 |
| --- | --- | --- | --- |
| 面板域名 | `panel.example.com` | 当前 VPS IP | 浏览器打开 3x-ui 面板 |
| 节点域名 | `node.example.com` | 当前 VPS IP | 客户端连接用，建议灰云 / DNS only；没有时可用服务器公网 IP |
| 网站/订阅域名 | `sub.example.com` | 当前 VPS IP | SublinkPro、Dockge、Sub-Store、Komari 等 |
| REALITY 伪装 SNI | `www.microsoft.com` | 不指向你的 VPS | 必须是外部真实 HTTPS 站点 |

如果你使用 Cloudflare，小云朵要分清：

- 面板域名、网站域名可以开橙云代理，但 Cloudflare SSL/TLS 必须用 `Full` 或 `Full (strict)`。
- REALITY 客户端连接用的节点域名必须能直连 VPS，建议灰云 / DNS only，或者直接用服务器公网 IP。
- 如果面板域名开了橙云，就不要把它当作 REALITY 的节点地址或 `External Proxy` 地址。

Cloudflare API Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

配置前再确认三件事：

- 云厂商安全组已经放行 `443` 和当前 SSH 端口。
- 当前机器没有其他服务占用公网 `443`，可用 `ss -lntp | grep ':443'` 查看。
- 已经保留当前 SSH 会话，必要时先做 VPS 快照。

## 2. 推荐完整流程：先配置 3x-ui，再配置 443

这套方案最容易出错的地方不是 443 本身，而是顺序反了。建议按下面顺序走：

```text
1. DNS 先解析好面板域名、节点域名。
2. 安装 3x-ui，并处理安装器要求的 SSL 选项。
3. 进入 3x-ui，把面板改成 127.0.0.1:40000，关闭面板 SSL。
4. 在 3x-ui 里配置面板路径、普通订阅路径、Clash/Mihomo 订阅路径。
5. 在 3x-ui 里新增 REALITY 入站，监听 127.0.0.1:1443。
6. 确认 3x-ui 本地面板、订阅、REALITY 都在监听。
7. 再进入 cy -> 19 -> 1 配置 443 单入口。
8. 跑 cy -> 19 -> 3 做链路体检。
```

### 2.1 安装 3x-ui 时 SSL 证书怎么选

有些 3x-ui 安装器会强制让你在下面三个选项里选一个：

```text
1. 为域名申请证书
2. 为 IP 申请证书
3. 选择已有证书位置
```

在本项目的 443 单入口架构里，推荐这样选：

```text
优先选择：为域名申请证书
域名填写：你的面板域名，例如 panel.example.com
如果安装器问是否把证书设置给面板：选择 n
```

核心原则是：**可以让安装器申请证书来完成安装，但不要让 3x-ui 面板自己启用 HTTPS**。最终对外 HTTPS 由 Caddy 负责，3x-ui 面板只做本机 HTTP 后端。

如果安装器没有“不要设置给面板”的选项，或者你已经选了 IP 证书/已有证书位置，也没关系。安装完成后立刻执行：

```text
cy -> 4 -> 11 面板救砖 / 重置 SSL
```

这个功能会清空 3x-ui 数据库里的面板证书路径，让面板回到 HTTP 模式。做完后再进入 3x-ui 官方菜单确认面板 SSL 已关闭。

不推荐长期使用：

```text
为 IP 申请证书
把 IP 证书路径填进 3x-ui 面板 SSL
把 Caddy 证书路径填进 3x-ui 面板 SSL
```

这些做法常见后果是 `ERR_TOO_MANY_REDIRECTS`、`502 Bad Gateway`、订阅链接带内部端口，或者面板完全打不开。

### 2.1.1 能不能先用 Caddy 申请证书，再把路径填给 3x-ui？

技术上可以，但**不推荐用于本项目的 443 单入口架构**。

原因是 3x-ui 安装器里的“选择已有证书位置”不是“跳过 SSL”，而是把你提供的证书和私钥路径写入 3x-ui 面板配置。这样 3x-ui 面板会自己启用 HTTPS。后续 Caddy 默认按 HTTP 去反代 `127.0.0.1:40000`，就会出现协议不匹配、循环跳转或 502。

本项目推荐的职责分工是：

```text
公网 HTTPS 证书：Caddy 负责
3x-ui 面板：只监听 127.0.0.1:40000 的 HTTP
3x-ui 订阅：只监听 127.0.0.1:2096 的 HTTP
REALITY：只监听 127.0.0.1:1443
```

所以安装 3x-ui 时如果被强制要求选 SSL，建议按下面优先级处理：

```text
优先：为域名申请证书，但不要把证书设置给面板；如果已经设置，马上用 cy -> 4 -> 11 清空。
可用：选择已有证书路径完成安装，但安装后必须清空 3x-ui 面板 SSL。
不推荐：为 IP 申请证书并长期挂在面板上。
```

只有在你明确要让 Caddy 反代 HTTPS 后端时，才把证书路径填给 3x-ui。那需要额外把 Caddy 改成类似 `reverse_proxy https://127.0.0.1:40000`，并处理本地证书校验；这比本项目默认方案复杂，不建议新手采用。

如果安装器问你是否自定义面板端口、路径、用户名密码等，建议选择自定义。先按下面值填，让 3x-ui 从一开始就作为本机后端运行：

```text
面板监听 IP：127.0.0.1
面板监听域名：留空
面板监听端口：40000
面板 url 根路径：/cuty/  或你自己的随机路径
面板 SSL/HTTPS：关闭
证书路径：留空
私钥路径：留空
```

`/cuty/` 只是示例，可以换成你自己的路径。它必须以 `/` 开头、以 `/` 结尾。后续公网面板入口就是：

```text
https://panel.example.com/cuty/
```

如果安装器还问会话时长、分页大小等普通面板参数，可以按个人习惯设置：

```text
会话时长：360
分页大小：默认值即可；设置 0 通常表示禁用分页
```

### 2.2 3x-ui 面板先改成本机 HTTP 后端

安装完成后，先进入 3x-ui，建议这样设置：

```text
面板监听地址：127.0.0.1
面板端口：40000
webBasePath：/panel-a8f3c9/  或你自己的随机路径
面板 SSL/HTTPS：关闭
证书路径：留空
私钥路径：留空
Panel URL / Public URL / External URL：https://panel.example.com/panel-a8f3c9/
```

`webBasePath` 可以自定义，但不要用 `/`。建议使用随机路径，例如：

```text
/panel-a8f3c9/
/my-xui-9d2k/
/admin-7q2m4x/
```

浏览器以后访问面板时，要带这个路径：

```text
https://panel.example.com/panel-a8f3c9/
```

不要访问：

```text
https://panel.example.com/
https://panel.example.com:40000/
https://panel.example.com:8443/
```

### 2.3 普通订阅和 Clash/Mihomo 订阅路径都先在 3x-ui 里定好

3x-ui 通常会有两个订阅入口：

```text
普通订阅：/sub/
Clash/Mihomo 订阅：/clash/
```

这两个路径都可以自定义。你可以使用默认：

```text
Subscription URI Path：/sub/
Subscription External URL：https://panel.example.com/sub/
Clash/Mihomo URI Path：/clash/
Clash/Mihomo External URL：https://panel.example.com/clash/
```

也可以改成你自己的路径，例如：

```text
普通订阅路径：/sublinkqq/
普通订阅外部地址：https://panel.example.com/sublinkqq/
Clash/Mihomo 路径：/mihomoqq/
Clash/Mihomo 外部地址：https://panel.example.com/mihomoqq/
```

如果 3x-ui 的订阅设置页面显示这些字段，建议这样填：

```text
监听 IP：127.0.0.1
监听域名：留空
监听端口：2096

URI 路径：/sublinkqq/          # 普通订阅，默认可用 /sub/
反向代理 URI：/sublinkqq/      # 和 URI 路径保持一致

URI 路径 (Clash)：/clash/      # Clash/Mihomo 订阅
反向代理 URI (Clash)：/clash/  # 和 URI 路径 (Clash) 保持一致
```

`监听域名` 建议留空，让 Caddy 通过 Host 头和路径转发过来。`反向代理 URI` 的推荐值是和对应的 `URI 路径` 一样；本项目默认不做路径剥离或改写，所以不要一个填 `/sub/`、另一个填 `/sublinkqq/`，除非你非常清楚自己在 Caddy 里做了 rewrite。

注意三件事：

- 外部订阅地址不要带 `:2096`。
- 3x-ui 面板里的路径、443 向导里填写的路径、Caddy 的 `@sub path` 必须一致。
- 443 向导里填的是路径前缀，例如 `/sublinkqq/`，不要填完整订阅链接里的密钥部分，例如 `/sublinkqq/673kkdohpwplhywm`。
- 路径建议以 `/` 开头并以 `/` 结尾，例如 `/sub/`、`/clash/`、`/sublinkqq/`。
- 路径建议只使用英文、数字、点、下划线和短横线，避免空格、中文和特殊符号。

### 2.4 REALITY 入站先建好

如果你要让未知 SNI 默认落到 REALITY，必须先在 3x-ui 里建一个 REALITY 入站：

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

不要把 `Target / dest` 写成：

```text
panel.example.com:443
127.0.0.1:8443
自己的节点域名:443
```

然后在该入站里配置 `External Proxy`，让客户端最终连接公网 443：

```text
类型：相同
地址：节点域名或服务器公网 IP
端口：443
```

这里的地址必须能直连你的 VPS。若面板域名开了 Cloudflare 橙云代理，不要用面板域名做 REALITY 节点地址；请改用灰云节点域名或服务器公网 IP。

保存后复制节点链接，应看到公网端口是 `443`，不是 `1443`。

### 2.5 本地状态确认

在跑 443 分流前，先检查本地监听：

```bash
ss -lntp | grep -E ':40000|:2096|:1443'
curl -I http://127.0.0.1:40000/
curl -I http://127.0.0.1:2096/sub/
curl -I http://127.0.0.1:2096/clash/
```

`/sub/` 和 `/clash/` 如果你改成了自定义路径，就用你的真实路径测试。没有带订阅密钥时返回 404 不一定代表端口坏了；这里主要确认不是连接拒绝。拿到真实订阅密钥后，再用完整路径测试。

### 2.6 再配置 443 单入口

确认 3x-ui 已经配置好后，再进入：

```text
cy -> 19 -> 1 首次配置 443 单入口
```

建议普通用户保持默认本地监听，只按自己的实际情况填写：

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
3x-ui 面板公网路径 / webBasePath：/cuty/ 或你的实际面板根路径
3x-ui 订阅服务监听地址：127.0.0.1
3x-ui 订阅服务端口：2096
3x-ui 普通订阅路径前缀：/sub/ 或你的自定义路径，不要带订阅密钥
3x-ui Clash/Mihomo 订阅路径前缀：/clash/ 或你的自定义路径，不要带订阅密钥
3x-ui 面板是否已经开启内置 SSL：n
Cloudflare API Token：用于 DNS 签发 Caddy 证书
```

这里填写的面板路径必须和 3x-ui 的“面板 url 根路径”一致。脚本不会自动修改 3x-ui 数据库里的面板路径，它只负责让 Caddy/Nginx 把公网流量送到正确的本机端口。

如果你刚才安装时已经误开了 3x-ui SSL，这里不要硬继续，先返回执行：

```text
cy -> 4 -> 11 面板救砖 / 重置 SSL
```

### 2.7 配置完成后的公网访问方式

假设你使用默认路径：

```text
面板：https://panel.example.com/panel-a8f3c9/
普通订阅：https://panel.example.com/sub/订阅密钥
Clash/Mihomo：https://panel.example.com/clash/订阅密钥
节点连接：node.example.com:443 或 panel.example.com:443
```

如果你使用自定义路径：

```text
面板：https://panel.example.com/my-xui-9d2k/
普通订阅：https://panel.example.com/sublinkqq/订阅密钥
Clash/Mihomo：https://panel.example.com/mihomoqq/订阅密钥
```

不要从公网访问这些内部端口：

```text
https://panel.example.com:40000/
https://panel.example.com:2096/sub/xxxx
https://panel.example.com:8443/
https://panel.example.com:1443/
```

后续新增网站：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
2. 新增网站/反代域名
```

后续修改 3x-ui 面板端口、面板根路径、订阅端口、REALITY 端口或订阅路径：

```text
19. 443 单入口管理中心
7. 修改本地端口 / 订阅路径
```

常见场景：

```text
3x-ui 面板端口从 40000 改成 41000
面板 url 根路径从 /cuty/ 改成 /adminqq/
订阅服务端口从 2096 改成 3096
普通订阅路径从 /sub/ 改成 /sublinkqq/
Clash/Mihomo 路径从 /clash/ 改成 /mihomo/
REALITY 本地端口从 1443 改成 2443
```

先在 3x-ui 里保存新端口或路径，再进入这个菜单同步脚本并重新应用。面板路径、普通订阅路径、Clash/Mihomo 路径不能相同。不要为这种小改动重跑首次配置，也不需要重签证书。

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

如果你已经看完第 2 章，可以把这一节当成菜单字段速查；真正的操作顺序仍然以第 2 章为准，先配 3x-ui，再配 443。

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
3x-ui 面板公网路径 / webBasePath：/cuty/ 或你在面板里设置的实际路径
3x-ui 订阅服务监听地址：127.0.0.1
3x-ui 订阅服务端口：2096
3x-ui 普通订阅路径前缀：/sub/
3x-ui Clash/Mihomo 订阅路径前缀：/clash/
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
面板监听域名：留空
面板端口：40000
webBasePath：/panel-a8f3c9/
面板 SSL / HTTPS：关闭
证书路径：留空
私钥路径：留空
Panel URL / Public URL / External URL：https://panel.example.com/panel-a8f3c9/
Subscription URI Path：/sub/，也可以用自定义路径如 /sublinkqq/
Subscription External URL：https://panel.example.com/sub/，不要带 :2096
Clash/Mihomo URI Path：/clash/，也可以用自定义路径如 /mihomoqq/
Clash/Mihomo External URL：https://panel.example.com/clash/，不要带 :2096
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

如果暂时没有单独节点域名，也可以填服务器公网 IP。只有在面板域名是灰云 / DNS only、能直连 VPS 时，才可以临时填面板域名：

```text
地址：panel.example.com
端口：443
```

如果 `panel.example.com` 开了 Cloudflare 橙云代理，就不要这样填；REALITY 客户端会连到 Cloudflare，而不是连到你的 Nginx stream 入口。

保存后复制节点链接，应看到类似：

```text
vless://uuid@node.example.com:443?security=reality&sni=your-reality-sni.example.com&...
```

如果链接里还是 `:1443`，说明 External Proxy 没有生效。把这个订阅交给 SublinkPro、妙妙屋或 Sub-Store 转换后，也可能继续得到错误端口。

3x-ui 订阅服务端口真实监听在本机：

```text
127.0.0.1:2096
```

公网访问时不要打开：

```text
https://panel.example.com:2096/sublinkqq/xxxx
```

应该通过 443 单入口访问：

```text
https://panel.example.com/sublinkqq/xxxx
```

如果你把 `Subscription URI Path` 设置成 `/sublinkqq/`，443 向导里的“3x-ui 普通订阅路径前缀”也要填 `/sublinkqq/`，不要把后面的订阅密钥一起填进去。这样 Caddy 才会把该路径转发到本机订阅端口。

如果你把 Clash/Mihomo 路径设置成 `/mihomoqq/`，443 向导里的“3x-ui Clash/Mihomo 订阅路径前缀”也要填 `/mihomoqq/`，同样不要带订阅密钥。

`/sub/`、`/sublinkqq/`、`/clash/`、`/mihomoqq/` 都只是路径示例。浏览器访问的路径、3x-ui 中对应的 URI Path、Caddy 的 `@sub path` 三者必须一致；否则 HTTPS 正常也会返回 404。

脚本会为面板域名生成类似下面的 Caddy 规则：

```caddy
@sub path /sub /sub/* /clash /clash/*
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

如果你自定义为 `/sublinkqq/` 和 `/mihomoqq/`，对应规则应变成：

```caddy
@sub path /sublinkqq /sublinkqq/* /mihomoqq /mihomoqq/*
```

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
| 浏览器提示 SSL 协议错误 | 访问了内部端口，或 SNI 没进 Caddy | 只访问 `https://域名/你的路径/`，不要带 `:8443` |
| 面板 502 | 3x-ui 面板没启动或端口不是 `40000` | `curl -I http://127.0.0.1:40000/` |
| 面板 404 | 访问路径和 `webBasePath` 不一致 | 面板 URL 是否带 `/panel-a8f3c9/` 这类路径 |
| 订阅 404 | 普通订阅或 Clash/Mihomo 路径不一致 | 对比 3x-ui URI Path、Caddy `@sub path`、浏览器访问路径 |
| 面板循环跳转 | 3x-ui 面板 SSL/HTTPS 仍开启 | 关闭面板 SSL，清空证书和私钥路径 |
| 节点链接仍是 `:1443` | External Proxy 没生效 | 3x-ui 入站 External Proxy 地址和端口 |
| REALITY 不通 | 入站没监听本机 `1443`，或 SNI/dest 写错 | `ss -lntp`、REALITY `Target` / `serverNames` |
| 证书签发失败 | Cloudflare Token 权限不足或域名不在该账号 | Token 权限、域名 zone、脚本证书维护菜单 |
| `ERR_EMPTY_RESPONSE` | 访问了 `http://` 被 Nginx 80 默认丢弃、Cloudflare SSL 模式错误、面板 SNI 没有进入 Caddy、或默认 REALITY 后端未监听 | 使用完整 `https://面板域名/webBasePath/`，检查 Cloudflare SSL/TLS 为 Full/Full(strict)，再跑 `19 -> 3` |

### 具体错误判断

`ERR_SSL_PROTOCOL_ERROR`：

通常是访问了内部端口，外部只访问标准 HTTPS 地址。

```text
正确：https://panel.example.com/panel-a8f3c9/
错误：https://panel.example.com:8443/
错误：https://panel.example.com:1443/
错误：https://panel.example.com:40000/
```

`ERR_TOO_MANY_REDIRECTS`：

通常是 3x-ui 面板还开启了 SSL 或强制 HTTPS。关闭面板 SSL，并清空证书和私钥路径。

如果出现在订阅路径上，再确认两件事：

- 订阅外部地址不要带内部端口，写 `https://panel.example.com/sublinkqq/`，不要写 `https://panel.example.com:2096/sublinkqq/`。
- Caddy 反代块需要带 `X-Forwarded-Host`、`X-Forwarded-Proto`、`X-Forwarded-Port`，否则 3x-ui 可能拼出错误跳转地址。

`ERR_EMPTY_RESPONSE`：

先确认浏览器地址是完整的 `https://panel.example.com/panel-a8f3c9/`，不是 `http://panel.example.com/`。本项目会把公网 `80` 的未知访问直接丢弃，所以访问 HTTP 时浏览器可能显示“未发送任何数据”。

如果你本地代理开启了 fake-ip 模式，本机查到 `198.18.x.x` 不一定代表公网 DNS 错误；请在 VPS 上或可信公共 DNS/DoH 上复查。若 VPS 侧也解析到 `198.18.x.x`、`10.x.x.x`、`127.x.x.x`、`192.168.x.x` 等地址，说明面板域名没有指向真实公网入口。

使用 Cloudflare 小云朵时，SSL/TLS 模式建议使用 `Full` 或 `Full (strict)`；`Flexible` 会让 Cloudflare 用 HTTP 回源，容易撞上 80 端口丢弃规则。

如果还没有创建 REALITY 入站，`127.0.0.1:1443` 通常不会监听。面板域名精确匹配时不会受影响；但如果 Nginx SNI 表里没有这个面板域名，或访问了其他域名，流量会落到默认 REALITY 后端，浏览器也可能显示空响应。

`HTTP 404`：

先检查后端本地是否正常：

```bash
curl -I http://127.0.0.1:40000/
```

如果本地也是 404，优先检查你访问的路径是否和 3x-ui 的 `webBasePath` 一致。例如 `webBasePath` 设置为 `/panel-a8f3c9/`，面板入口就应该访问 `https://panel.example.com/panel-a8f3c9/`。

如果 404 出现在订阅链接，分别测试普通订阅和 Clash/Mihomo 后端：

```bash
curl -I http://127.0.0.1:2096/sub/订阅密钥
curl -I http://127.0.0.1:2096/clash/订阅密钥
```

如果你用了自定义路径，就把 `/sub/`、`/clash/` 换成你的真实路径。若本地 `127.0.0.1:2096` 都返回 404，说明 3x-ui 里的路径或密钥不对；若本地正常、公网 404，说明 Caddy 的 `@sub path` 没有包含该路径。

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
普通订阅：https://panel.example.com/sub/订阅密钥
Clash/Mihomo：https://panel.example.com/clash/订阅密钥
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
订阅打开：https://panel.example.com:2096/sub/订阅密钥
Clash/Mihomo 打开：https://panel.example.com:2096/clash/订阅密钥
REALITY dest 写 panel.example.com:443
3x-ui 面板开启 SSL 并填写 Caddy 证书
Caddy 直接监听公网 0.0.0.0:443
```

## 13. 绝对不要这样做

- 不要让 Caddy 监听公网 `443`。
- 不要让 Xray/3x-ui REALITY 直接监听公网 `443`。
- 不要让 3x-ui 面板暴露公网 `40000`。
- 不要从公网访问或放行 `2096` 订阅端口，订阅也走公网 `443`。
- 不要把 Caddy 的证书路径填进 3x-ui 面板 SSL。
- 不要把 REALITY 的 `dest/serverNames` 写成面板域名。
- 不要把网站分流继续交给 Xray fallback。
- 不要用内部端口当浏览器访问入口。
