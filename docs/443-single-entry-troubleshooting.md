# 443 单入口排错手册

排错前先运行：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

如果要提交 Issue，再运行：

```text
主菜单 [15 服务健康总览] -> [生成反馈诊断信息]
```

请脱敏域名以外的 Token、私钥、订阅密钥后再公开粘贴。

## 网站选择建议

新增网站、反代域名或填写 REALITY 伪装 SNI 时，尽量选择没有 CDN 防护、能直接访问源站的 HTTPS 网站。开启 CDN、防火墙托管或强跳转规则的网站，可能会影响证书验证、SNI 分流和 REALITY 连接判断，排错时容易把 CDN 行为误判成脚本配置问题。

如果使用 Cloudflare 管理自己的面板、节点、订阅或网站域名，建议保持 DNS only / 灰云。

## 基础检查命令

先看监听位置是否符合预期：

下面命令和示例输出里的 `8443`、`1443`、`40000`、`2096` 是示例端口；实际以服务当前监听和脚本保存的配置为准。

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
nginx -t
caddy validate --config /etc/caddy/Caddyfile
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

公网 `443` 只应由当前 `ENTRY_MODE` 对应的单个入口服务监听：

```text
nginx-stream   -> nginx
xray-fallback  -> xray / 3x-ui / x-ui 托管的 Xray
tcp-peek       -> tcppeek / vpso-mux
```

如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，脚本按 `nginx-stream` 兼容读取。其他本地后端大致应该是：

```text
127.0.0.1:8443    caddy
127.0.0.1:1443    x-ui / 3x-ui / xray
127.0.0.1:40000   x-ui / 3x-ui
127.0.0.1:2096    x-ui / 3x-ui
```

## ERR_TOO_MANY_REDIRECTS

### 现象

浏览器提示重定向次数过多，面板页面一直跳转。

### 常见原因

- 3x-ui 面板仍开启自带 HTTPS。
- Caddy 反代到 HTTPS 后端，但后端又强制跳回 HTTPS。
- Cloudflare 开启代理或 SSL 模式不匹配。

### 检查命令

```bash
curl -I https://panel.example.com/panel/
curl -I http://127.0.0.1:40000/panel/
```

### 解决方法

- 清空 3x-ui 面板证书路径，并重启面板。
- 让 Web 反代引擎反代到本地 HTTP 后端。
- 443 单入口相关域名建议使用 DNS only / 灰云。
- 如果刚清空证书，浏览器仍循环跳转，用无痕窗口重新测试。

### 相关菜单入口

```text
主菜单 [5 面板、节点与订阅工具] -> [3 面板 SSL 修复]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## ERR_EMPTY_RESPONSE

### 现象

浏览器提示 `ERR_EMPTY_RESPONSE`，页面没有正常返回内容。

### 常见原因

- 访问了内部端口，例如 `:8443`、`:1443`、`:40000`。
- SNI 没命中 Caddy，流量落到了 REALITY。
- 当前入口模式的 SNI/Web 域名路由没有包含面板或网站域名；`nginx-stream` 看 Nginx stream 配置，`tcp-peek` 看 `vpso-mux` 配置。

### 检查命令

```bash
grep -n "panel.example.com" /etc/nginx/stream.d/*.conf
grep -n "panel.example.com" /etc/vps-optimize/vpso-mux.yaml
ss -lntp | grep -E ':443|:8443|:1443'
```

正确访问地址应是：

```text
https://panel.example.com/panel/
```

不要访问：

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

### 解决方法

- 确认访问的是域名的标准 HTTPS 地址，不带内部端口。
- 确认面板、订阅或网站域名已经写入当前入口模式使用的 Web/SNI 路由。
- 重新应用当前保存的 443 配置。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [5 重新应用当前保存的配置]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## ERR_CONNECTION_CLOSED / ERR_SSL_PROTOCOL_ERROR

### 现象

浏览器提示连接被关闭，或提示 SSL 协议错误。

### 常见原因

- 公网 `443` 不是当前 `ENTRY_MODE` 对应的入口服务在监听。
- 当前入口模式之外的 Caddy、3x-ui、REALITY 或旧 Nginx server 抢占了公网 `443`。
- TLS 流量被转发到了不该接收浏览器 HTTPS 的后端。

### 检查命令

```bash
ss -lntp | grep ':443'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

### 解决方法

- 确认公网 `443` 只由当前 `ENTRY_MODE` 对应的单个入口服务监听：`nginx-stream` 对应 `nginx`，`xray-fallback` 对应 Xray 主入站，`tcp-peek` 对应 `tcppeek` / `vpso-mux`。
- Caddy 使用 `127.0.0.1:8443`。
- 非 `xray-fallback` 主入站的 REALITY / Xray 本地入站使用 `127.0.0.1:1443` 这类本地监听。
- 面板和订阅后端只作为本机 HTTP 服务。

### 相关菜单入口

```text
主菜单 [13 端口排查与释放]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
```

## 端口并发连接限制误伤

### 现象

某个节点、订阅或网站偶发连接失败、握手被断开，或者只有部分来源 IP 访问公网 `443` 异常。

### 常见原因

- 公网 `443` 存在本脚本添加的 connlimit 规则。
- 规则按公网端口和来源 IP 统计 TCP 并发连接数，不认识 SNI、Xray/3x-ui 入站、UUID 或用户。
- 多个网站、订阅和节点共用公网 `443` 时，同一个来源 IP 的连接可能会一起计入限制。

### 检查方法

先看 443 链路体检里的“端口并发连接限制”段落：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

如果公网 `443` 存在本脚本添加的 connlimit 规则，它只能作用于整个公网 `443`，不能精准到某个 SNI、Xray/3x-ui 入站、UUID 或用户。不要把它当作某个单独节点、某个入站或某个用户的精确限制。

### 解决方法

- 如果确认是误伤，到端口并发连接限制菜单查看或删除公网 `443` 的 connlimit 规则。
- 删除规则后，再回到 443 链路体检确认运行时和持久化文件里是否还残留公网 `443` 规则。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制]
```

## Nginx 运行中但 443 未监听

### 现象

`当前 443 入口状态` 显示 `配置模式：nginx-stream`，`nginx：运行中`，但 `公网 443：未监听`。

如果状态页同时出现旧命名兼容提示，例如 `nginx_stream` 或 `tcp_peek`，说明脚本无法安全自动改写该文件。先按提示重新应用当前入口模式，脚本会按新命名读取并写回 `nginx-stream`、`xray-fallback` 或 `tcp-peek`。

### 常见原因

- `/etc/nginx/stream.d/vps_sni_443.conf` 被切换或回滚流程隔离后没有重新生成。
- `/etc/nginx/nginx.conf` 没有实际加载 `stream { include /etc/nginx/stream.d/*.conf; }`。
- Nginx stream 动态模块安装了，但主配置没有加载模块目录。

### 解决方法

先运行：

```text
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
```

重新应用会强制生成 Nginx Stream 配置，并检查 `nginx -T` 是否实际加载 `/etc/nginx/stream.d/vps_sni_443.conf`。如果仍失败，脚本会打印 Nginx 状态、最近日志、stream include 和端口监听线索。

## 404

### 现象

面板、订阅或 Clash/Mihomo 链接返回 404。

### 常见原因

- 访问路径与 3x-ui 的 `webBasePath` 不一致。
- 订阅路径前缀写错，例如写成 `sub` 而不是 `/sub/`。
- Caddy 配置没有包含对应路径。

### 检查命令

```bash
curl -I https://panel.example.com/panel/
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
grep -R "panel.example.com" /etc/caddy/conf.d /etc/caddy/Caddyfile 2>/dev/null
grep -n "path" /etc/caddy/conf.d/panel.example.com.caddy
grep -n "reverse_proxy" /etc/caddy/conf.d/panel.example.com.caddy
```

### 解决方法

- 统一面板路径，例如 `/panel/`。
- 统一订阅路径，例如 `/sub/`、`/clash/`。
- 443 向导里填的是路径前缀，不要把客户端的 `Subscription` 一起填进去。
- 重新应用 443 配置。

例如 Clash/Mihomo 使用 `/clash/` 时，三处都应该一致：

```text
3x-ui URI 路径 (Clash)：/clash/
443 向导 Clash/Mihomo 路径前缀：/clash/
https://panel.example.com/clash/客户端 Subscription
```

只使用 `/clash/` 时，Caddy 里应能看到类似配置：

```caddy
@sub path /clash /clash/*
handle @sub {
    reverse_proxy 127.0.0.1:2096
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

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [1 修改面板/订阅端口与路径]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 502

### 现象

浏览器能连上 HTTPS，但页面显示 502。

### 常见原因

- Caddy 能收到请求，但面板或订阅后端没有运行。
- 后端监听端口和脚本配置不一致。
- 后端只监听公网地址或只监听 IPv6。

### 检查命令

```bash
systemctl status caddy --no-pager
ss -lntp
curl -I http://127.0.0.1:40000/
curl -I http://127.0.0.1:2096/
```

### 解决方法

- 启动或重启 3x-ui / x-ui。
- 在 `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]` 修正后端监听地址和端口。
- 重新应用配置并体检。

如果本机测试能通，但公网仍是 502，通常是 Caddy 反代地址或端口和实际监听不一致。

### 相关菜单入口

```text
主菜单 [5 面板、节点与订阅工具] -> [1 3x-ui 面板脚本]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 订阅链接仍带 :2096

### 现象

复制出来的订阅链接仍然包含 `:2096`，例如：

```text
https://panel.example.com:2096/sub/xxxx
```

### 常见原因

- 3x-ui 订阅反向代理 URI 没设置。
- Public URL / External URL 仍输出内部端口。
- 如果是订阅内容里的节点仍带本地端口，按下一节检查 `Hosts / 主机` 或 `External Proxy`。

### 解决方法

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

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [11 订阅链接 / External Proxy 提示]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
```

## 节点链接仍带 :1443

### 现象

客户端节点链接仍然包含 `:1443`，没有使用公网 `443`。

### 常见原因

- 旧版 3x-ui 的 REALITY 入站没有设置 External Proxy。
- 3x-ui v3.4.0+ 的 `Hosts / 主机` 没有给该入站设置公网地址和端口。
- 节点域名走了 Cloudflare 代理，客户端无法直连 VPS。

### 解决方法

3x-ui v3.4.0 及之后：左侧侧边栏 -> `Hosts / 主机` -> 新增 Host：

```text
入站：选择对应的 REALITY 入站
地址：node.example.com 或服务器公网 IP
端口：443
Security：相同，或按该入站实际安全类型填写
SNI / Fingerprint / ALPN：按该入站和客户端实际值保持一致
```

3x-ui v3.3.1 及之前：回到 REALITY 入站，设置 `External Proxy`：

```text
类型：相同
地址：node.example.com 或服务器公网 IP
端口：443
```

节点域名如果走 Cloudflare，必须是灰云 / DNS only。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [11 订阅链接 / External Proxy 提示]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
```

## 证书申请失败

### 现象

Caddy 或 acme.sh 申请证书失败，HTTPS 无法正常打开。

### 常见原因

- DNS 没解析到当前 VPS。
- Cloudflare API Token 权限不足。
- 域名被 Cloudflare 代理，导致验证异常。
- 服务器时间不准。

### 检查命令

```bash
date -Is
dig +short A panel.example.com @1.1.1.1
systemctl status caddy --no-pager
journalctl -u caddy -n 80 --no-pager
```

### 解决方法

- 确认 DNS A 记录正确。
- 使用 DNS only / 灰云。
- 修正 Token 权限后重新签发。
- 开启 NTP 时间同步。

推荐顺序：

```text
1. 443 链路与安全体检
8. 更新 Cloudflare API Token
9. 重新签发某个域名证书
12. 校验并重载 Caddy
```

### 相关菜单入口

```text
主菜单 [1 运维预检与风险扫描]
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## Cloudflare Token 权限问题

### 现象

证书签发提示认证失败、无权限访问 zone 或 DNS 记录无法写入。

### 常见原因

- Token 没有 `Zone.Zone.Read`。
- Token 没有 `Zone.DNS.Edit`。
- Token 只授权了错误的 zone。

### 检查命令

```bash
grep -n "CF_" /root/.config/vps-panel/cloudflare.env 2>/dev/null
```

不要把 Token 原文贴到 Issue。

### 解决方法

- 在 Cloudflare 重新创建 Token。
- 权限至少包含 `Zone.Zone.Read` 和 `Zone.DNS.Edit`。
- 只授权需要签发证书的域名 zone。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]
```

## DNS 不是灰云 / DNS only

### 现象

REALITY 连接失败，订阅链接异常，或者证书验证结果和预期不一致。

### 常见原因

- Cloudflare 开启橙云代理。
- REALITY 节点域名被代理后无法直连 VPS。

### 检查命令

```bash
dig +short A panel.example.com @1.1.1.1
dig +short A node.example.com @1.1.1.1
```

### 解决方法

- 将面板、节点、订阅相关域名改为 DNS only / 灰云。
- 等 DNS 生效后重新体检。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 443 端口被占用

### 现象

Nginx 无法启动，提示 `bind() to 0.0.0.0:443 failed`。

### 常见原因

- 当前入口模式之外的 Caddy、Apache、旧 Nginx server、3x-ui 或 Xray 仍监听公网 `443`。
- 在 `nginx-stream` / `tcp-peek` 模式下，REALITY 直接监听 `0.0.0.0:443`，没有改成本地监听。

### 检查命令

```bash
ss -lntp | grep ':443'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

### 解决方法

- 让公网 `443` 只交给当前 `ENTRY_MODE` 对应的单个入口服务；切到 `nginx-stream` 时是 Nginx stream，切到 `tcp-peek` 时是 `vpso-mux`，切到 `xray-fallback` 时是 Xray 主入站。
- Caddy 改为 `127.0.0.1:8443`。
- 非 `xray-fallback` 主入站的 REALITY / Xray 本地入站改为 `127.0.0.1:1443` 这类本地监听。

### 相关菜单入口

```text
主菜单 [13 端口排查与释放]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
```

## Caddy/Nginx/REALITY 监听地址错误

### 现象

体检提示服务监听在公网，或者链路能通但暴露了内部端口。

### 常见原因

- Caddy 监听 `0.0.0.0:8443`。
- 面板后端监听 `0.0.0.0:40000`。
- REALITY 监听公网 `443`，和 Nginx stream 冲突。

### 检查命令

```bash
ss -lntp
grep -R "listen" /etc/nginx /etc/caddy 2>/dev/null
```

### 解决方法

- 非公网入口统一改为 `127.0.0.1`。
- 重新应用 443 配置。
- 收紧防火墙时保留 SSH 和公网 443。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 面板能打开但订阅不可用

### 现象

`/panel/` 正常，但 `/sub/`、`/clash/` 或客户端订阅链接不可用。

### 常见原因

- 3x-ui 订阅服务没有开启。
- 订阅路径前缀与 Caddy 配置不一致。
- Public URL 仍输出内部端口。
- 3x-ui v3.4.0+ 的 `Hosts / 主机` 或旧版 `External Proxy` 仍输出内部端口。

### 检查命令

```bash
curl -I http://127.0.0.1:2096/sub/
curl -I https://panel.example.com/sub/
```

### 解决方法

- 在 3x-ui 中启用订阅。
- 订阅路径统一使用 `/sub/`、`/clash/`。
- 检查订阅链接不要出现 `:2096`、`:40000`、`:8443`。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [11 订阅链接 / External Proxy 提示]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## REALITY 连接失败

### 现象

面板和订阅正常，但客户端 REALITY 节点无法连接。

### 常见原因

- REALITY 本地监听端口和 Nginx stream 转发端口不一致。
- `dest` / `Target` 写成了自己的域名。
- `serverNames` / `SNI` 不是外部真实 HTTPS 站点。
- 节点域名被 Cloudflare 代理。

### 检查命令

```bash
ss -lntp | grep -E ':1443|:443'
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com </dev/null
```

### 解决方法

- REALITY 本地监听建议使用 `127.0.0.1:1443`。
- REALITY 伪装 SNI 使用外部真实 HTTPS 站点。
- 节点域名保持 DNS only / 灰云。
- 重新应用 443 配置。

### 相关菜单入口

```text
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```
