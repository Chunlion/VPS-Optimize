# REALITY 与 XHTTP 共存：独立域名与共用 443

本文说明在已经跑通 443端口复用的服务器上，如何再增加 XHTTP 节点，并与 REALITY 节点长期共存。

两种接法只能选一种，不要混用：

| 方案 | 公网入口 | TLS 终结位置 | 适合场景 |
| --- | --- | --- | --- |
| A. 独立节点域名 | 入口按 SNI 转发到 XHTTP 本地入站 | XHTTP 入站自己 | 只想要一个独立节点，配置最少 |
| B. 共用 Web 域名 | 入口按 SNI 转到 Caddy/Nginx，再按 path 反代到 XHTTP | 本地 Caddy/Nginx | 想让节点和面板/网站用同一个域名、同一个 `443` |

## 前提

- 443端口复用已经按[部署与配置](../docs/443-single-entry.md)跑通，`ss -lntp | grep ':443'` 只看到一个入口服务。
- 入口模式是 `nginx-stream` 或 `tcp-peek`。`xray-fallback` 下入口由 Xray 主入站独占，本文的菜单不可用。
- 3x-ui 面板、订阅仍在本地 HTTP 端口上运行。
- 保留当前 SSH 连接，并先做一次配置备份。

## 方案 A：独立节点域名

适用：`xhttp.example.com` 这种只给节点用的域名。

### 1. 准备证书

XHTTP 入站自己终结 TLS，所以这张证书必须覆盖节点域名。证书路径仍放在 443端口复用使用的位置：

```text
/etc/caddy/certs/xhttp.example.com.crt
/etc/caddy/certs/xhttp.example.com.key
```

可以用现有脚本重签，或按相同域名、相同路径自行签发。证书和私钥不要放到 Web 根目录。

### 2. 在 3x-ui 创建 XHTTP 入站

| 字段 | 填写 |
| --- | --- |
| 监听地址 | `127.0.0.1` |
| 监听端口 | 一个未占用的本地端口，例如 `2410` |
| 协议 | VLESS（或其他你实际使用的协议） |
| 传输 / network | `xhttp`（旧版界面可能显示 `splithttp`） |
| XHTTP 路径 | 记下来，例如 `/xhttp` |
| 主机 / host | 可留空；若填写，必须是 `xhttp.example.com` |
| 安全 / security | `tls` |
| 证书路径 | 上一步的两个文件 |
| ALPN | `h2,http/1.1` 或与客户端一致 |

入站必须监听 `127.0.0.1`。监听 `0.0.0.0` 会把本地端口直接暴露到公网，绕过 `443` 入口。

### 3. 在脚本登记 SNI 路由

```text
主菜单 [19 443端口复用管理中心] -> [4 管理 Xray SNI 转发规则] -> [2 添加 SNI 路由]
```

- 入站 SNI：`xhttp.example.com`
- 本地监听地址：`127.0.0.1`
- 本地端口：`2410`

保存后会提示是否立即同步到当前入口，选是。

### 4. 客户端

```text
地址：xhttp.example.com
端口：443
传输：xhttp
path：/xhttp
TLS：开启
SNI / serverName：xhttp.example.com
```

客户端 `path` 必须与入站完全一致。入口只做 TCP 透传，不读取 path，所以这里不存在路径冲突问题。

## 方案 B：与 Web 域名共用 443

适用：希望节点和面板或网站使用同一个域名，例如：

```text
https://panel.example.com/panel/   -> 3x-ui 面板
https://panel.example.com/xhttp    -> XHTTP 节点
```

### 1. 在 3x-ui 创建不带 TLS 的 XHTTP 入站

| 字段 | 填写 |
| --- | --- |
| 监听地址 | `127.0.0.1` |
| 监听端口 | 例如 `2400` |
| 协议 / UUID | `VLESS`，生成新 UUID |
| VLESS decryption / 客户端 encryption | `none` |
| flow | 留空 |
| 传输 / network | `xhttp` |
| XHTTP mode | `auto` |
| XHTTP 路径 | 例如 `/xhttp` |
| 主机 / host | 可留空；若填写，必须是面板或网站域名 |
| 安全 / security | `none` |

关键点：**这个入站不能开 TLS**。TLS 由本地 Caddy/Nginx 在 `8443`（默认值，以实际配置为准）终结，入站只接收明文 HTTP。

### 2. 在脚本登记路径反代

```text
主菜单 [19 443端口复用管理中心] -> [2 管理 Web 域名与反向代理] -> [10 XHTTP 节点路径反代] -> [2 添加 XHTTP 路径规则]
```

按提示填写：

| 提示 | 示例 |
| --- | --- |
| 选择承载 XHTTP 的 Web 域名 | `panel.example.com` |
| XHTTP 路径 | `/xhttp` |
| 本地监听地址 | `127.0.0.1` |
| 本地端口 | `2400` |

脚本会做这些检查：

- 域名必须是已存在的面板域名或 Web 域名（证书和反代入口都已就绪）。
- 路径不能与面板 `webBasePath`、普通订阅路径、Clash 路径重叠。`/panelx` 这种前缀重叠也会被拒绝，因为 Nginx 用前缀匹配。
- 本地端口必须处于监听状态，且不能与入口、Web 反代、面板、订阅端口相同。

保存后确认重新应用，脚本会重新渲染 Caddy 或 Nginx 配置并重启对应的 Web 服务。

### 3. 客户端

```text
地址：panel.example.com
端口：443
传输：xhttp
path：/xhttp
TLS：开启
SNI / serverName：panel.example.com
```

客户端连接的域名和 SNI 都是 Web 域名，TLS 证书就是面板或网站那张，不需要额外证书。

UUID 使用新入站的值，`encryption=none`、flow 留空、证书验证开启，ALPN 填 `h2,http/1.1`。客户端 mode 先用 `packet-up`：当前 Web 反代使用 HTTP/1.1 回源，而客户端 `auto` 在 TLS H2 下会选择 `stream-up`。不要填写原 REALITY 的公钥或 Short ID。

## 套 CDN：先直连，再启用代理

以下以 Cloudflare 为例，沿用方案 B；不需要改入口引擎或自动创建入站。

1. 先完成方案 B 并用客户端实连。建议为节点使用单独的 Web 域名，例如 `down.example.com`，保留面板原有白名单和访问方式。在 `[19] -> [2] -> [2 新增 Web 域名与反向代理]` 登记域名及实际默认后端，再通过 `[10] -> [2]` 添加 `/xhttp -> 127.0.0.1:2400`。
2. 域名 A/AAAA 记录指向 VPS，仅发布可用地址；源站继续使用现有 `acme.sh + Cloudflare DNS API` 流程签发覆盖该域名的证书。直连验证通过后，将该记录改为橙云代理，SSL/TLS 使用 **Full (strict)**，回源仍为 HTTPS `443`。
3. Cache Rules 为该域名的 `/xhttp` 及 `/xhttp/` 子路径设置 **Bypass cache**。例如匹配表达式：

   ```text
   http.host eq "down.example.com" and (http.request.uri.path eq "/xhttp" or starts_with(http.request.uri.path, "/xhttp/"))
   ```

4. 该路径必须允许 XHTTP 的 GET/POST 请求及流式响应，不应出现浏览器挑战、Access 登录、路径改写或重定向。若发生拦截，根据安全事件只调整对应域名和路径的规则，不关闭整个站点防护。
5. 客户端地址、SNI、Host 使用 `down.example.com`，端口 `443`、TLS 开启、path `/xhttp`、mode `packet-up`；UUID 等保持与入站一致。先验证此单域名 CDN 节点，再做上下行分离。

源站 Web 白名单按连接来源判断，套 CDN 后看到的是 CDN 回源 IP，不能继续用校园网出口 IP 限制访客，也不要通过放宽面板白名单解决；使用单独的节点 Web 域名。原 REALITY 仍走原有直连地址和 SNI 路由，普通 HTTP CDN 不能代理 REALITY。

不要把公网 `443` 用防火墙收窄成 CDN 回源段：REALITY 和方案 A 的 SNI 路由共用这个 `443`，按来源 IP 限制端口会同时掐掉直连节点。CDN 回源固定用 `443`，不支持改回源端口；访问控制放在域名和路由层。

XHTTP 的 POST 上传不会被 Web 反代截断：脚本生成的 Nginx 路径 location 已设 `client_max_body_size 0`，Caddy 默认也不限请求体。CDN 侧仍需按第 3 步绕过该路径缓存。

参考：[Cloudflare Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)、[Cache Rules](https://developers.cloudflare.com/cache/how-to/cache-rules/settings/)。

## 上下行分离：直连上传、CDN 下载

这里的分离是使用不同连接入口，不是创建两个互不相干的节点。复用同一个 XHTTP 入站，服务端 Host 留空、mode `auto`，并在脚本登记两条规则：

| 用途 | DNS | 路径反代 |
| --- | --- | --- |
| 上传 `up.example.com` | DNS only（灰云），直连 VPS | `/xhttp -> 127.0.0.1:2400` |
| 下载 `down.example.com` | Proxied（橙云），经 CDN 回源 | `/xhttp -> 127.0.0.1:2400` |

两个域名都须登记为 Web 域名、有对应源站证书，且能通过公网 `443` 到达**同一个 Xray 进程的同一个入站、同一路径**；不要分别创建上传和下载入站，也不要把请求负载均衡到不同实例。脚本在添加第二条同路径规则时会比对本地地址和端口，不一致会直接提示。

下载域名仍是一个普通 Web 域名，它的默认后端在 `/` 上照常对外；不要把该默认后端指向内网服务、面板或订阅端口。

客户端主连接改用 `up.example.com:443`，TLS 开启，SNI/Host 为 `up.example.com`，path `/xhttp`、mode `packet-up`。使用支持 `downloadSettings` 的 Xray 客户端，在 **XHTTP extra** 中填入以下对象（自定义 JSON 的位置为 `streamSettings.xhttpSettings.extra`）：

```json
{
  "downloadSettings": {
    "address": "down.example.com",
    "port": 443,
    "network": "xhttp",
    "security": "tls",
    "tlsSettings": {
      "serverName": "down.example.com",
      "alpn": ["h2", "http/1.1"]
    },
    "xhttpSettings": {
      "host": "down.example.com",
      "path": "/xhttp",
      "mode": "packet-up"
    }
  }
}
```

以上域名和端口均为示例值。下载配置不继承上传配置，因此 `network`、TLS、SNI 和 path 都要填写；不使用 `stream-one`。客户端没有 extra/自定义 JSON 支持时，先使用单域名 CDN 节点。订阅转换器若丢弃 `downloadSettings`，需直接导入到支持该配置的客户端并检查活动配置。

先分别测试两个域名作为普通 XHTTP 节点，再启用分离。客户端日志设为 `info`，确认实际下载地址；同时在 Web 访问日志（已启用时）确认上传 POST 经 `up.example.com`、下载 GET 经 `down.example.com`，最后通过本地代理完成真实上传与下载。只有 TCP/TLS 成功或一次 HTTP 204，不能证明分离生效。

本例两端都使用 TCP HTTPS，不增加源站 UDP `443`。如果校园网连源站上传方向也超时，直连上传仍可能失败；可先测试上下行均走 CDN，再比较同设备、同网络、同故障时段的失败率和传输表现，不能保证解决此前超时。

参考：[Xray 官方 XHTTP 上下行分离说明](https://github.com/XTLS/Xray-core/discussions/4113)。

## 两种方案怎么选

| 判断项 | 选方案 A | 选方案 B |
| --- | --- | --- |
| 已经有独立节点域名 | 是 | 不必 |
| 想让节点和面板同域名 | 做不到 | 是 |
| 想少维护一张证书 | 否 | 是 |
| 以后要走 CDN | 视 CDN 是否支持该协议 | 更合适，但需先按灰云验证 |
| 只想改一次配置 | 是 | 否 |

REALITY 节点不受这两种方案影响：它继续走自己的 SNI 路由，和 XHTTP 的路径规则互不干扰。

## 已知限制

- **不支持 HTTP/3**：XHTTP 的 QUIC 模式需要 UDP `443`，当前入口只监听 TCP `443`。
- **xray-fallback 不可用**：该模式没有独立的 Web 前置层，`[2] -> [10]` 会提示不可用；XHTTP 只能在该模式的主入站 `fallbacks` 里自行配置。
- **Web 白名单会连带限制 XHTTP**：方案 B 的规则挂在 Web 域名下，该域名开了 IP 白名单，XHTTP 也一起受限。REALITY 和方案 A 的 SNI 路由不受影响。
- **SNI 清洗看的是域名**：方案 B 不新增 SNI，域名已在清单里；方案 A 需要把节点域名登记成 SNI 路由，否则严格门禁会丢弃它。
- **XHTTP 的长连接**：脚本为路径反代关闭了响应缓冲和请求缓冲，并把读写超时设为 1 小时。不要在 Web 反代引擎里再手动加短超时。

## 验证

先确认监听：

```bash
ss -lntp | grep -E ':(443|2400|2410)'
```

预期：`443` 由当前入口服务监听；`2400`、`2410` 由 Xray 监听且绑定 `127.0.0.1`。

方案 B 检查路径是否落到 XHTTP 后端：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://panel.example.com/xhttp
```

裸 GET 返回 404 或 400 不代表节点失败，也不能单凭状态码证明请求到达了 XHTTP 后端。返回面板登录页 HTML 时检查路径匹配；502 时检查后端监听和端口：

```bash
curl -sS -D - -o /dev/null https://panel.example.com/xhttp | head -20
curl -sS http://127.0.0.1:2400/xhttp -o /dev/null -w '%{http_code}\n'
```

结合两次响应和日志定位；Web 反代、CDN 可能修改响应头，状态码相同也不能证明路由正确。

最后用客户端实连。TLS 和端口检查不能代替真实的 XHTTP 会话。

## 排错

| 现象 | 优先检查 |
| --- | --- |
| 客户端握手成功但一直无数据 | 入站 path 与客户端 path 是否完全一致；是否多写或少写了结尾斜杠 |
| 方案 B 返回面板登录页 | 路径规则没生效：确认已重新应用，且路径没有和 `webBasePath` 重叠 |
| 方案 B 返回 502 | 本地 XHTTP 入站没监听或端口填错；`curl` 直连本地端口复核 |
| 方案 A 握手失败 | 证书未覆盖节点域名，或 XHTTP 入站没开 TLS |
| 方案 B 握手失败 | 入站误开了 TLS，本地是明文 HTTP |
| 节点被入口丢弃 | 方案 A 未登记 SNI 路由，或未同步到当前入口 |
| Web 域名能开、节点不行 | 该域名开了 Web IP 白名单，把客户端出口 IP 加进去，或换方案 A |

日志位置：

```bash
journalctl -u caddy -n 80 --no-pager     # 方案 B，Caddy 引擎
journalctl -u nginx -n 80 --no-pager     # 方案 B，Nginx 引擎
journalctl -u x-ui -u 3x-ui -n 80 --no-pager
```

## 不要这样做

- 不要在同一个 XHTTP 入站上同时开 TLS 又走方案 B 的明文反代。
- 不要把 XHTTP 本地端口监听在 `0.0.0.0`。
- 不要让 XHTTP 路径占用 `/panel/`、`/sub/`、`/clash/` 或它们的子路径。
- 不要在 `xray-fallback` 模式下尝试用 `[2] -> [10]` 管理路径。
- 不要用示例域名和端口直接上线。
