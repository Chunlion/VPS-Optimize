# 443 单入口技术实现

本文说明 VPS-Optimize 的三种 443 单入口实现方式：Nginx Stream 默认稳定实现、TCP Peek + Splice / vpso-mux 进阶实现、Xray Fallback 特殊实现。

示例中的 `panel.example.com`、`site.example.com`、`node.example.com`、`SERVER_IP`、`8443`、`8444`、`1443` 都是示例值，仅用于说明链路关系。实际部署时请替换成你的真实域名、服务器 IP 和脚本当前保存的端口。

## 共同配置边界

三种入口模式共用同一套公开配置：

- Web 域名、Caddy 后端映射、证书和 Web 白名单共用。
- 证书仍使用现有 `acme.sh + Cloudflare DNS API` 流程，不引入 Caddy DNS 模块，不使用 `xcaddy`。
- Web 白名单只保护 Caddy/Web 域名，不用于限制 Xray 节点流量。
- 只有一个服务可以监听公网 `443`：`nginx`、`xray` 或 `vpso-mux`。
- 如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，按 `nginx-stream` 兼容处理。

常用菜单路径：

```text
主菜单 [19 443 单入口管理中心]
  -> [2] 首次配置 / 安装 443 单入口
  -> [3] 切换到 Nginx Stream 模式
  -> [4] 切换到 Xray Fallback 模式
  -> [5] 切换到 TCP Peek + Splice 模式
  -> [7] 回滚上一次入口模式切换
  -> [16] TCP Peek 8444 预检 / 安装测试
  -> [17] TCP Peek 分流规则校验
  -> [18] 查看 TCP Peek + Splice 日志
```

3x-ui 面板、订阅和 Xray 入站的具体填写方式见 [443 单入口分流教程](443-single-entry.md) 的“3x-ui 三种入口模式配置速查”。这里先给结论：

| ENTRY_MODE | 3x-ui/Xray 应怎么监听 | 切换时最重要的注意事项 |
| --- | --- | --- |
| `nginx-stream` | 面板、订阅、Xray 入站都监听 `127.0.0.1` 本地端口 | 3x-ui/Xray 不要直接占用公网 `443` |
| `tcp-peek` | 和 `nginx-stream` 相同，仍是本地端口 | 通常不需要改 3x-ui；公网 `443` 只从 `nginx` 换成 `vpso-mux` |
| `xray-fallback` | 需要一个 3x-ui/Xray 主入站监听公网 `443`，并 fallback 到 Caddy 本地端口 | 切回其他模式前，必须先把这个 Xray 主入站从公网 `443` 移走 |

## Nginx Stream 默认稳定实现

Nginx Stream 是默认稳定模式。公网 `443` 由 Nginx stream 监听，使用 `ssl_preread` 读取 TLS ClientHello 里的 SNI，但不终止 TLS、不解密流量。

```text
公网 443
  -> Nginx stream ssl_preread
  -> panel/site/sub SNI  -> Caddy 本地 TLS
  -> Xray/REALITY SNI   -> Xray/3x-ui 本地入站
  -> unknown SNI        -> 默认 Xray/REALITY 后端
```

这个实现覆盖面最完整，适合作为长期默认入口。它负责稳定接入 Caddy、REALITY、面板、订阅、网站、Web 白名单和回滚流程。

## TCP Peek + Splice / vpso-mux 进阶实现

TCP Peek + Splice / vpso-mux 是进阶模式、可回滚，默认不接管 `443`。第一次使用时先运行 `主菜单 [19 443 单入口管理中心] -> [16] TCP Peek 8444 预检 / 安装测试`，确认 `vpso-mux` 能在 `8444` 启动并转发。只有用户随后执行 `[5] 切换到 TCP Peek + Splice 模式`，公网 `443` 才会从 Nginx Stream 切到 `vpso-mux`。

`vpso-mux` 使用 `MSG_PEEK` 查看 TLS ClientHello 中的 SNI，不消费首包；后端收到的 ClientHello 仍与客户端原始数据一致。转发优先使用 splice，失败或不可用时回退普通 copy。

TCP Peek 生成的 `vpso-mux.yaml` 会按脚本保存的公网监听地址只写一个监听项。默认 `0.0.0.0:443` 只监听 IPv4；如果你明确需要 IPv6 入口，请把公网监听地址设置为 `::` 后重新生成配置，避免同一端口同时写 `0.0.0.0` 和 `[::]` 导致双栈绑定冲突。

```text
公网 443
  -> vpso-mux
  -> recv(MSG_PEEK) 查看 TLS ClientHello SNI
  -> 按 SNI / whitelist 选择后端
  -> splice 双向转发，失败时回退 copy
```

与 Nginx Stream 的核心差异：

| 项目 | Nginx Stream | TCP Peek + Splice / vpso-mux |
| --- | --- | --- |
| 定位 | 默认稳定模式 | 进阶可选模式 |
| 入口进程 | `nginx` | `vpso-mux` |
| SNI 获取 | `ssl_preread` | `MSG_PEEK` 解析 ClientHello |
| TLS 处理 | 不终止 TLS | 不终止 TLS |
| 证书 | Caddy 处理 Web/面板证书 | Caddy 处理 Web/面板证书 |
| 未知 SNI | 默认 Xray/REALITY 后端 | 默认 Xray/REALITY 后端 |
| 转发 | Nginx stream proxy | splice，失败回退 copy |

查看状态和日志：

```text
主菜单 [19 443 单入口管理中心]
  -> [18] 查看 TCP Peek + Splice 日志
```

常用诊断命令：

```bash
systemctl status vpso-mux --no-pager
journalctl -u vpso-mux -n 120 --no-pager
/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml -check
```

如果 `transfer_mode` 显示为 `copy`，表示 splice 未使用或已回退。可以在 `/etc/vps-optimize/vpso-mux.yaml` 中关闭 splice：

```yaml
splice:
  enabled: false
  fallback_to_copy: true
```

## Xray Fallback 特殊实现

Xray Fallback 是特殊模式：公网 `443` 由已有 Xray/3x-ui 主入站监听，普通 HTTPS fallback 到 Caddy。本脚本不会创建、删除或修改 3x-ui/Xray 入站内部配置。

```text
公网 443
  -> Xray/3x-ui 主入站
  -> Xray 节点流量由该主入站处理
  -> 普通 HTTPS fallback 到 Caddy 本地后端
```

在 xray-fallback 模式下，`Xray 入站管理` 菜单不可用于多本地入站 SNI 分流。原因是公网 `443` 已由 Xray 主入站接管，脚本当前不支持在该模式下继续把多个 SNI 分流到多个本地 Xray 入站。如需多个本地 Xray 入站分流，请使用 Nginx Stream 模式或 TCP Peek + Splice / vpso-mux 模式。

## 切换与回滚

切换到 TCP Peek + Splice：

```text
主菜单 [19 443 单入口管理中心]
  -> [16] TCP Peek 8444 预检 / 安装测试
  -> [17] TCP Peek 分流规则校验
  -> [5] 切换到 TCP Peek + Splice 模式
```

切换流程不会在公网 `443` 切换路径里自动下载 Go 工具链或远端编译 `vpso-mux`。如果 `/usr/local/bin/vpso-mux` 不存在，脚本会拒绝切换，要求先走 `[16]` 的 `8444` 预检。正式切换前脚本会再次启动独立 `vpso-mux-preflight.service` 监听 `8444`，确认 Caddy 和 Xray 本地后端可达；预检失败时公网 `443` 不会被替换。

正式切换会生成并校验 `vpso-mux.yaml`、创建备份、隔离当前 VPS-Optimize 管理的 Nginx stream 443 配置、启动 `vpso-mux` 接管公网 `443`，并检查 Caddy 和 Xray 本地后端可达。失败时会尝试自动回滚。

如果当前 SSH 会话连接在入口端口，例如 `443`，脚本会拒绝切换，避免直接断开当前管理连接。请改用云厂商 VNC/Serial Console，或先用非入口端口 SSH 登录。

回滚上一轮入口模式切换：

```text
主菜单 [19 443 单入口管理中心]
  -> [7] 回滚上一次入口模式切换
```

回滚会停止并禁用 `vpso-mux`，读取 `sni-stack.env` 重新生成 Nginx Stream 和 Caddy 配置，恢复到上一次入口模式，并运行链路体检。

## 常见故障

检查公网 443 当前监听方：

```bash
ss -lntup | grep ':443'
```

切换到 TCP Peek + Splice 后应看到 `vpso-mux`。如果仍是 Nginx、Caddy 或 Xray，说明入口关系没有切换干净，建议立即回滚。

检查 Caddy 本地 TLS 后端：

```bash
ss -lntup | grep ':8443'
systemctl status caddy --no-pager
```

检查 Xray/REALITY 本地入站：

```bash
ss -lntup | grep ':1443'
systemctl status xray --no-pager
```

非 TLS、无 SNI、ClientHello 不完整或客户端协议不带 SNI 时会走默认后端。这不是 TLS 终止失败，因为 Nginx Stream 和 `vpso-mux` 都不解密、不终止 TLS。
