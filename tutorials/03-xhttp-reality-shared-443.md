# REALITY 与 xhttp 共存：独立域名与共用 443

本文说明在已经跑通 443端口复用的服务器上，如何再增加 xhttp 节点，并与 REALITY 节点长期共存。

两种接法只能选一种，不要混用：

| 方案 | 公网入口 | TLS 终结位置 | 适合场景 |
| --- | --- | --- | --- |
| A. 独立节点域名 | 入口按 SNI 转发到 xhttp 本地入站 | xhttp 入站自己 | 只想要一个独立节点，配置最少 |
| B. 共用 Web 域名 | 入口按 SNI 转到 Caddy/Nginx，再按 path 反代到 xhttp | 本地 Caddy/Nginx | 想让节点和面板/网站用同一个域名、同一个 `443` |

## 前提

- 443端口复用已经按[部署与配置](../docs/443-single-entry.md)跑通，`ss -lntp | grep ':443'` 只看到一个入口服务。
- 入口模式是 `nginx-stream` 或 `tcp-peek`。`xray-fallback` 下入口由 Xray 主入站独占，本文的菜单不可用。
- 3x-ui 面板、订阅仍在本地 HTTP 端口上运行。
- 保留当前 SSH 连接，并先做一次配置备份。

## 方案 A：独立节点域名

适用：`xhttp.example.com` 这种只给节点用的域名。

### 1. 准备证书

xhttp 入站自己终结 TLS，所以这张证书必须覆盖节点域名。证书路径仍放在 443端口复用使用的位置：

```text
/etc/caddy/certs/xhttp.example.com.crt
/etc/caddy/certs/xhttp.example.com.key
```

可以用现有脚本重签，或按相同域名、相同路径自行签发。证书和私钥不要放到 Web 根目录。

### 2. 在 3x-ui 创建 xhttp 入站

| 字段 | 填写 |
| --- | --- |
| 监听地址 | `127.0.0.1` |
| 监听端口 | 一个未占用的本地端口，例如 `2410` |
| 协议 | VLESS（或其他你实际使用的协议） |
| 传输 / network | `xhttp`（旧版界面可能显示 `splithttp`） |
| xhttp 路径 | 记下来，例如 `/xhttp` |
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
https://panel.example.com/xhttp    -> xhttp 节点
```

### 1. 在 3x-ui 创建不带 TLS 的 xhttp 入站

| 字段 | 填写 |
| --- | --- |
| 监听地址 | `127.0.0.1` |
| 监听端口 | 例如 `2400` |
| 传输 / network | `xhttp` |
| xhttp 路径 | 例如 `/xhttp` |
| 主机 / host | 可留空；若填写，必须是面板或网站域名 |
| 安全 / security | `none` |

关键点：**这个入站不能开 TLS**。TLS 由本地 Caddy/Nginx 在 `8443` 终结，入站只接收明文 HTTP。两边都开 TLS 一定会握手失败。

### 2. 在脚本登记路径反代

```text
主菜单 [19 443端口复用管理中心] -> [2 管理 Web 域名与反向代理] -> [10 xhttp 节点路径反代] -> [2 添加 xhttp 路径规则]
```

按提示填写：

| 提示 | 示例 |
| --- | --- |
| 选择承载 xhttp 的 Web 域名 | `panel.example.com` |
| xhttp 路径 | `/xhttp` |
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

## 两种方案怎么选

| 判断项 | 选方案 A | 选方案 B |
| --- | --- | --- |
| 已经有独立节点域名 | 是 | 不必 |
| 想让节点和面板同域名 | 做不到 | 是 |
| 想少维护一张证书 | 否 | 是 |
| 以后要走 CDN | 视 CDN 是否支持该协议 | 更合适，但需先按灰云验证 |
| 只想改一次配置 | 是 | 否 |

REALITY 节点不受这两种方案影响：它继续走自己的 SNI 路由，和 xhttp 的路径规则互不干扰。

## 已知限制

- **不支持 HTTP/3**：xhttp 的 QUIC 模式需要 UDP `443`，当前入口只监听 TCP `443`。
- **xray-fallback 不可用**：该模式没有独立的 Web 前置层，`[2] -> [10]` 会提示不可用；xhttp 只能在该模式的主入站 `fallbacks` 里自行配置。
- **Web 白名单会连带限制 xhttp**：方案 B 的规则挂在 Web 域名下，该域名开了 IP 白名单，xhttp 也一起受限。REALITY 和方案 A 的 SNI 路由不受影响。
- **SNI 清洗看的是域名**：方案 B 不新增 SNI，域名已在清单里；方案 A 需要把节点域名登记成 SNI 路由，否则严格门禁会丢弃它。
- **xhttp 的长连接**：脚本为路径反代关闭了响应缓冲和请求缓冲，并把读写超时设为 1 小时。不要在 Web 反代引擎里再手动加短超时。

## 验证

先确认监听：

```bash
ss -lntp | grep -E ':(443|2400|2410)'
```

预期：`443` 由当前入口服务监听；`2400`、`2410` 由 Xray 监听且绑定 `127.0.0.1`。

方案 B 检查路径是否落到 xhttp 后端：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://panel.example.com/xhttp
```

返回 404 或 400 都属于正常范围——说明请求已经到达 xhttp 后端，而不是面板。返回面板的登录页 HTML、或 502，说明路径没生效或后端端口不对：

```bash
curl -sS -D - -o /dev/null https://panel.example.com/xhttp | head -20
curl -sS http://127.0.0.1:2400/xhttp -o /dev/null -w '%{http_code}\n'
```

对比两次响应的状态码和响应头。两次不一致时，问题在 Web 反代层；两次一致但客户端仍连不上，问题在入站或客户端参数。

最后用客户端实连。TLS 和端口检查不能代替真实的 xhttp 会话。

## 排错

| 现象 | 优先检查 |
| --- | --- |
| 客户端握手成功但一直无数据 | 入站 path 与客户端 path 是否完全一致；是否多写或少写了结尾斜杠 |
| 方案 B 返回面板登录页 | 路径规则没生效：确认已重新应用，且路径没有和 `webBasePath` 重叠 |
| 方案 B 返回 502 | 本地 xhttp 入站没监听或端口填错；`curl` 直连本地端口复核 |
| 方案 A 握手失败 | 证书未覆盖节点域名，或 xhttp 入站没开 TLS |
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

- 不要在同一个 xhttp 入站上同时开 TLS 又走方案 B 的明文反代。
- 不要把 xhttp 本地端口监听在 `0.0.0.0`。
- 不要让 xhttp 路径占用 `/panel/`、`/sub/`、`/clash/` 或它们的子路径。
- 不要在 `xray-fallback` 模式下尝试用 `[2] -> [10]` 管理路径。
- 不要用示例域名和端口直接上线。
