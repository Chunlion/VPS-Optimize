# 443 单入口排错手册

排错前先运行：

```text
cy -> 19 -> 3
```

如果要提交 Issue，再运行：

```text
cy -> 15 -> 生成反馈诊断信息
```

请脱敏域名以外的 Token、私钥、订阅密钥后再公开粘贴。

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
- 让 Caddy 反代到本地 HTTP 后端。
- 443 单入口相关域名建议使用 DNS only / 灰云。

### 相关菜单入口

```text
cy -> 4 -> 11
cy -> 19 -> 7
cy -> 19 -> 3
```

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
grep -R "panel.example.com" /etc/caddy/conf.d /etc/caddy/Caddyfile 2>/dev/null
```

### 解决方法

- 统一面板路径，例如 `/panel/`。
- 统一订阅路径，例如 `/sub/`、`/clash/`。
- 重新应用 443 配置。

### 相关菜单入口

```text
cy -> 19 -> 7
cy -> 19 -> 4
cy -> 19 -> 3
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
- 在 `cy -> 19 -> 7` 修正后端监听地址和端口。
- 重新应用配置并体检。

### 相关菜单入口

```text
cy -> 4 -> 1
cy -> 19 -> 7
cy -> 19 -> 3
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

### 相关菜单入口

```text
cy -> 1
cy -> 19 -> 6
cy -> 19 -> 3
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
cy -> 19 -> 6
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
cy -> 19 -> 3
```

## 443 端口被占用

### 现象

Nginx 无法启动，提示 `bind() to 0.0.0.0:443 failed`。

### 常见原因

- Caddy、Apache、旧 Nginx server 或 3x-ui 仍监听公网 `443`。
- REALITY 直接监听 `0.0.0.0:443`。

### 检查命令

```bash
ss -lntp | grep ':443'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
```

### 解决方法

- 让公网 `443` 只交给 Nginx stream。
- Caddy 改为 `127.0.0.1:8443`。
- REALITY 改为 `127.0.0.1:1443`。

### 相关菜单入口

```text
cy -> 13
cy -> 19 -> 7
cy -> 19 -> 4
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
cy -> 19 -> 7
cy -> 19 -> 4
cy -> 19 -> 3
```

## 面板能打开但订阅不可用

### 现象

`/panel/` 正常，但 `/sub/`、`/clash/` 或客户端订阅链接不可用。

### 常见原因

- 3x-ui 订阅服务没有开启。
- 订阅路径前缀与 Caddy 配置不一致。
- External Proxy / Public URL 仍输出内部端口。

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
cy -> 19 -> 5
cy -> 19 -> 7
cy -> 19 -> 3
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
cy -> 19 -> 7
cy -> 19 -> 4
cy -> 19 -> 3
```
