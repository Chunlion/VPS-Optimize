# 失联与回滚急救手册

这份手册用于处理已经出问题的情况：SSH 断开、防火墙误封、443 单入口改坏、Nginx 入口或 Caddy/Nginx Web 反代引擎起不来、证书失败、面板打不开。它的目标是先恢复可控状态，再排查根因。

本文菜单路径按“主菜单 [编号 菜单文案] -> [子编号 菜单文案]”格式书写，不把快捷命令写进每条路径。

## 先做三件事

1. 不要关闭还连着的 SSH 窗口。
2. 不要反复重跑同一个高风险向导。
3. 先判断还能不能登录服务器。

| 当前状态 | 优先动作 |
|---|---|
| 当前 SSH 还在 | 保留窗口，先创建备份或查看服务状态 |
| 新 SSH 连不上，但旧窗口还在 | 用旧窗口恢复 SSH、防火墙或云安全组 |
| 所有 SSH 都断了 | 用云厂商 VNC / 救援控制台登录 |
| 系统能登录但 443 坏了 | 先体检，再按入口服务、Web 反代引擎、证书分开处理 |
| 系统和服务都混乱 | 优先从脚本备份或云快照恢复 |

## 能登录时的最小检查

先看端口和失败服务：

```bash
ss -lntp
systemctl --failed --no-pager
systemctl status ssh --no-pager || systemctl status sshd --no-pager
systemctl status nginx caddy x-ui --no-pager
```

再进入：

```text
主菜单 [15 服务健康总览]
主菜单 [13 端口排查与释放]
```

如果是 443 单入口问题，优先：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

如果准备回滚：

```text
主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]
主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]
主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]
```

## SSH 失联

### 现象

- 新端口连不上。
- 改完 SSH 端口后登录超时。
- 公钥或密码登录失败。

### 如果旧 SSH 窗口还在

先确认 SSH 实际监听：

```bash
ss -lntp | grep -E 'ssh|sshd'
systemctl status ssh --no-pager || systemctl status sshd --no-pager
```

检查 SSH 配置：

```bash
sshd -t
grep -nE '^(Port|PasswordAuthentication|PubkeyAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
```

然后确认两层放行：

| 层级 | 怎么处理 |
|---|---|
| 云安全组 | 在云厂商控制台放行新 SSH 端口 |
| 系统防火墙 | 进入 `主菜单 [8 防火墙规则管理]` 放行新端口 |

不要关闭旧窗口。新开本地终端测试：

```bash
ssh -p 新端口 root@服务器IP
```

### 如果所有 SSH 都断了

用云厂商 VNC / 救援控制台登录，然后按顺序处理：

1. 确认 SSH 服务是否运行。
2. 放行 SSH 端口。
3. 修正 `/etc/ssh/sshd_config`。
4. 重启 SSH 服务。
5. 新开终端测试登录。

常用命令：

```bash
systemctl restart ssh || systemctl restart sshd
sshd -t
ss -lntp | grep -E 'ssh|sshd'
ufw status numbered 2>/dev/null || firewall-cmd --list-ports
```

如果不确定改坏了哪里，优先用云快照恢复。脚本备份不能替代整机快照。

## 防火墙误封

### 现象

- SSH 端口监听正常，但公网连不上。
- 网站或面板本机能访问，公网打不开。

### 检查

```bash
ufw status numbered 2>/dev/null || true
firewall-cmd --list-all 2>/dev/null || true
ss -lntp
```

### 处理

先确认云安全组放行，再进入：

```text
主菜单 [8 防火墙规则管理]
```

建议优先选择：

```text
[1 启用防火墙 + 自动放行当前公网端口]
```

如果只是补端口，选择：

```text
[2 手动放行端口]
```

不要删除当前 SSH 端口。关闭防火墙、删除规则都属于高风险操作，脚本会要求输入大写 `YES`。

### 端口并发连接限制误封

`主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制]` 写入的是额外 `iptables` / `ip6tables` connlimit 限制规则，不等同于 UFW/firewalld 的端口放行规则。它会按公网端口限制每来源 IP 的 TCP 并发连接数；如果限制公网 `443` 且启用了 443 单入口，只能限制整个公网 `443`，不能精准到某个 Xray/3x-ui 入站、SNI、UUID 或用户。

还能进菜单时，优先走：

```text
主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制] -> [3 查看当前连接数限制规则]
主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制] -> [2 删除端口并发连接限制]
主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制] -> [5 保存/检查重启持久化]
```

脚本删除规则后会自动尝试刷新持久化快照；`[5]` 用来确认保存文件是否已经同步。如果系统没有 `netfilter-persistent`、`iptables-persistent` 或 RHEL 系列已有的 `iptables-services` 持久化路径，菜单会提示当前 connlimit 规则只在本次运行期生效。

菜单进不去时，用 VNC / 救援控制台查看脚本规则标记：

```bash
iptables -S INPUT | grep 'VPSO_CONN_LIMIT_PORT_'
ip6tables -S INPUT | grep 'VPSO_CONN_LIMIT_PORT_'
```

只删除确认属于本脚本、且端口和连接数匹配的单条规则。做法是复制输出里的那一整条 `-A INPUT ... VPSO_CONN_LIMIT_PORT_端口 ...`，把开头的 `-A INPUT` 改成 `-D INPUT` 后执行；IPv6 规则同理用 `ip6tables`。不要批量清空 INPUT 链，也不要把 UFW/firewalld 放行规则和 connlimit 限制规则混在一起处理。

## 443 单入口改坏

### 现象

- 面板、订阅或网站都打不开。
- 入口服务或 Web 反代引擎启动失败。
- 浏览器 404、502、证书错误。
- REALITY 连不上。

### 第一轮检查

下面命令和表格里的 `8443`、`1443`、`40000`、`2096` 是示例端口；实际以服务当前监听和脚本保存的配置为准。

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096'
systemctl status nginx --no-pager
systemctl status caddy --no-pager
systemctl status vpso-mux --no-pager
nginx -t
caddy validate --config /etc/caddy/Caddyfile
```

然后进入：

```text
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

### 不要先重跑首次配置

新增网站、改后端端口、修证书，都不应该先重跑首次配置。常用入口是：

| 目标 | 菜单路径 |
|---|---|
| 新增或删除网站 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` |
| 切换 Caddy/Nginx Web 反代引擎 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [8 切换 Web 反代引擎]` |
| 重新生成配置 | `主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]` |
| 修改面板/订阅/REALITY 参数 | `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数]` |
| Caddy/证书维护 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护]` |
| 回滚 443 配置 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [6 回滚 443 单入口配置]` |

### 切换 Caddy/Nginx Web 反代引擎后坏了

脚本管理的 443 配置以 `/etc/vps-optimize/sni-stack.env` 为准。通过 `[19] -> [8] -> [8]` 切换 Web 反代引擎时，会读取已经保存的面板、订阅、网站、证书、白名单和后端参数重建目标引擎配置；不会反向解析手写的 Caddy/Nginx 配置。

如果之前手动改过 `/etc/caddy/conf.d`、`/etc/nginx/conf.d/vps_sni_web_*.conf` 或旧 `[4 反代]` 生成的 `/etc/nginx/conf.d/vps_proxy_*.conf`，先通过 `[8 管理 Web 域名/反代]` 或 `[10 修改 443 共享参数]` 把参数同步到脚本，再切换。切换到 Nginx 本地 Web 反代会隔离脚本管理的 Caddy 443 Web 配置；切换回 Caddy 会隔离脚本管理的 Nginx 本地 Web 配置。重新应用 443 时也会隔离旧 Nginx HTTPS 公网反代配置，避免继续抢公网 `443`。

如果当前是 `ENTRY_MODE=xray-fallback` 且 `WEB_PROXY_ENGINE=nginx`，脚本会禁止新增或覆盖 Web 白名单。原因是 Xray fallback 到本地 Nginx 后，Nginx 不能可靠拿到真实客户端源 IP。如需 Web 白名单，切到 Nginx Stream/TCP Peek 入口层白名单，或选择 Caddy 作为 Web 反代引擎。

## Nginx 起不来

### 常见原因

- `443` 已被 Apache、旧 Nginx server、3x-ui、Xray 或非当前入口服务占用。
- `/etc/nginx/nginx.conf` 的 `stream` 配置语法错误。
- 旧公网 HTTPS 反代配置和 443 单入口配置重复。
- 选择 Nginx 作为 Web 反代引擎后，`/etc/nginx/conf.d/vps_sni_web_*.conf` 语法或证书路径异常。

### 检查

```bash
ss -lntp | grep ':443'
nginx -t
journalctl -u nginx -n 80 --no-pager
grep -R "listen .*443" /etc/nginx /etc/caddy 2>/dev/null
```

### 处理

目标状态：

| 组件 | 应该监听 |
|---|---|
| 443 入口服务 | Nginx Stream、vpso-mux 或 Xray 主入站三选一监听公网 `443` |
| Web 反代引擎 | Caddy 或 Nginx 监听本地 HTTPS，例如 `127.0.0.1:8443` |
| REALITY 本地入站 | Nginx Stream/TCP Peek 模式下通常是 `127.0.0.1:1443` |
| 3x-ui 面板 | `127.0.0.1:40000` |

如果是旧配置抢占或 Web 反代引擎切换后 Nginx 起不来，先确认：

```bash
grep -E '^(ENTRY_MODE|WEB_PROXY_ENGINE|NGINX_LISTEN_ADDR|NGINX_LISTEN_PORT|CADDY_LISTEN_ADDR|CADDY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
grep -R "listen .*443" /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/caddy 2>/dev/null
nginx -t
```

再进入：

```text
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [15 隔离旧 Caddy 配置]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
```

## Web 反代引擎起不来或 502

### 常见原因

- 当前 Web 反代引擎配置语法错误。
- 后端端口没有服务。
- 反代地址写错。
- 证书文件缺失或权限不对。
- Nginx 本地 Web 反代的 server/location 写法或证书路径异常。

### 检查

```bash
grep -E '^(ENTRY_MODE|WEB_PROXY_ENGINE|PANEL_DOMAIN|CADDY_LISTEN_ADDR|CADDY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
caddy validate --config /etc/caddy/Caddyfile
systemctl status caddy --no-pager
journalctl -u caddy -n 100 --no-pager
nginx -t
systemctl status nginx --no-pager
journalctl -u nginx -n 100 --no-pager
ls -l /etc/nginx/conf.d/vps_sni_web_*.conf 2>/dev/null
curl -I http://127.0.0.1:40000/panel/
curl -I http://127.0.0.1:2096/sub/
```

### 处理

| 问题 | 菜单路径 |
|---|---|
| 只是 Caddy 语法或重载问题 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [12 校验并重载 Caddy]` |
| Nginx 本地 Web 反代语法或重载问题 | `主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]` |
| 需要切换 Caddy/Nginx Web 反代引擎 | `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代] -> [8 切换 Web 反代引擎]` |
| 后端端口或路径写错 | `主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [1 修改面板/订阅端口与路径]` |
| 证书文件或软链接异常 | `主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [10 重建 /root/cert 证书软链接]` |
| 不知道是哪类问题 | `主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]` |

## 证书失败

### 先确认

```bash
date -Is
dig +short A panel.example.com @1.1.1.1
dig +short AAAA panel.example.com @1.1.1.1
grep -E '^(WEB_PROXY_ENGINE|PANEL_DOMAIN|CADDY_LISTEN_ADDR|CADDY_LISTEN_PORT)=' /etc/vps-optimize/sni-stack.env 2>/dev/null
systemctl status nginx caddy --no-pager
journalctl -u caddy -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
```

Cloudflare Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

相关域名建议先保持 DNS only / 灰云。

### 处理入口

```text
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [8 更新 Cloudflare API Token]
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [9 重新签发某个域名证书]
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [13 Caddy/证书一键体检]
```

菜单名称里保留 Caddy 是历史命名；无论 Web 反代引擎选择 Caddy 还是 Nginx，证书仍由 `acme.sh + Cloudflare DNS API` 签发，并继续使用 `/etc/caddy/certs/${domain}.crt|key` 和 `/root/cert/${domain}.crt|key`。

最近的 acme 错误日志可能在：

```text
/root/cert/acme_last_error.log
```

不要公开粘贴 Token、私钥或完整订阅密钥。

## 面板打不开

### 快速判断

```bash
curl -I http://127.0.0.1:40000/panel/
curl -I https://panel.example.com/panel/
systemctl status x-ui --no-pager
```

| 结果 | 判断 |
|---|---|
| 本地 HTTP 正常，公网 HTTPS 不通 | 多半是入口服务、Web 反代引擎或证书问题 |
| 本地 HTTP 也不通 | 先修 3x-ui 或面板端口 |
| 重定向循环 | 3x-ui 可能仍开启自带 HTTPS |
| 404 | 面板路径和 Web 反代引擎路径不一致 |
| 502 | Web 反代引擎找不到后端 |

常用入口：

```text
主菜单 [5 面板、节点与订阅工具] -> [3 面板 SSL 修复]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [1 修改面板/订阅端口与路径]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 订阅不可用

### 检查

```bash
curl -I http://127.0.0.1:2096/sub/
curl -I https://panel.example.com/sub/
curl -I https://panel.example.com/clash/
```

订阅链接里不应该出现：

```text
:2096
:40000
:8443
127.0.0.1
```

处理入口：

```text
主菜单 [19 443 单入口管理中心] -> [11 订阅链接 / External Proxy 提示]
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [1 修改面板/订阅端口与路径]
```

## REALITY 连接失败

### 检查

```bash
ss -lntp | grep -E ':443|:1443'
openssl s_client -connect www.microsoft.com:443 -servername www.microsoft.com </dev/null
```

重点确认：

| 项目 | 检查重点 |
|---|---|
| REALITY 本地监听 | `127.0.0.1:1443` |
| 客户端端口 | `443` |
| `dest` / `Target` | 外部真实 HTTPS 站点 |
| `serverNames` / `SNI` | 与外部真实 HTTPS 站点一致 |
| 节点域名 | DNS only / 灰云 |

处理入口：

```text
主菜单 [19 443 单入口管理中心] -> [10 修改 443 共享参数] -> [2 修改 REALITY 本地监听 / 伪装 SNI]
主菜单 [19 443 单入口管理中心] -> [6 重新应用当前入口模式]
主菜单 [19 443 单入口管理中心] -> [13 443 链路体检]
```

## 从备份恢复

### 脚本全量备份

适合系统还能登录、脚本菜单还能打开时：

```text
主菜单 [16 配置备份与回滚] -> [2 查看现有备份列表]
主菜单 [16 配置备份与回滚] -> [3 从备份一键回滚]
```

备份通常位于：

```text
/etc/vps-optimize/backups
```

### 443 单入口备份

适合只回滚入口服务、Web 反代和 443 配置：

```text
主菜单 [19 443 单入口管理中心] -> [12 CF DNS / Caddy 证书维护] -> [6 回滚 443 单入口配置]
```

相关路径：

```text
/etc/vps-optimize/backups/sni-stack_*
/etc/vps-optimize/sni-stack.last-backup
```

### 云快照

适合这些情况：

| 情况 | 建议 |
|---|---|
| SSH、VNC 都无法稳定修复 | 恢复云快照 |
| 内核切换后无法启动 | 恢复云快照或从救援模式修 GRUB |
| 配置来源不明，反复修复失败 | 恢复到最近明确可用的快照 |
| 数据目录或数据库损坏 | 先确认备份，再考虑快照 |

## 提交 Issue 前

先运行：

```text
主菜单 [15 服务健康总览]
```

在健康总览里生成反馈诊断信息。公开粘贴前务必脱敏：

| 内容 | 处理方式 |
|---|---|
| Cloudflare Token | 删除 |
| 私钥和证书私钥 | 删除 |
| 面板密码 | 删除 |
| 订阅密钥 | 删除 |
| 真实用户域名 | 可按需要替换为 `example.com` |

Issue 模板见 [VPS-Optimize Bug report](https://github.com/Chunlion/VPS-Optimize/blob/main/.github/ISSUE_TEMPLATE/bug_report.md)。
