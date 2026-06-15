# 443 单入口技术实现

本文说明 VPS-Optimize 的三种 443 单入口实现方式：Nginx Stream 默认稳定实现、TCP Peek + Splice / vpso-mux 同配置实现、Xray Fallback 特殊实现。

示例中的 `panel.example.com`、`site.example.com`、`node.example.com`、`SERVER_IP`、`8443`、`8444`、`1443` 都是示例值，仅用于说明链路关系。实际部署时请替换成你的真实域名、服务器 IP 和脚本当前保存的端口。

## 共同配置边界

三种入口模式共用同一套公开配置：

- Web 域名、Web 反代引擎后端映射、证书和 Web 白名单共用。
- 证书仍使用现有 `acme.sh + Cloudflare DNS API` 流程，不引入 Caddy DNS 模块，不使用 `xcaddy`。
- Web 白名单只保护 Web 域名，不用于限制 Xray 节点流量。
- 443 单入口下的 Web 反代引擎可选择 Caddy 或 Nginx，切换入口模式时复用同一份配置。
- 使用 Nginx Stream 或 TCP Peek 时，Web 白名单在入口层按 `SNI + 源 IP` 生效；`xray-fallback + Nginx 本地 Web 反代` 不允许新增或覆盖 Web 白名单。
- 只有一个服务可以监听公网 `443`：`nginx`、`xray` 或 `vpso-mux`。
- 如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，按 `nginx-stream` 兼容处理。
- `ENTRY_MODE` 和 `/etc/vps-optimize/443-engine.conf` 的 `engine` 统一写入 `nginx-stream`、`xray-fallback`、`tcp-peek`。旧版本写过的 `nginx_stream`、`xray_fallback`、`tcp_peek` 只作为读取兼容别名保留；单个简单赋值会自动改写为新命名，无法安全改写时状态页会继续提示。

常用菜单路径：

```text
主菜单 [19 443 单入口管理中心]
  -> [2] 首次配置 / 安装 443 单入口
  -> [3] 切换到 Nginx Stream 模式
  -> [4] 切换到 Xray Fallback 模式
  -> [5] 切换到 TCP Peek + Splice 模式
  -> [7] 回滚上一次入口模式切换
  -> [16] 查看 TCP Peek + Splice 状态 / 8444 预检
  -> [17] TCP Peek 分流规则校验
  -> [18] 查看 TCP Peek + Splice 日志
```

3x-ui 面板、订阅和 Xray 入站的具体填写方式见 [443 单入口分流教程](443-single-entry.md) 的“3x-ui 三种入口模式配置速查”。这里先给结论：

| ENTRY_MODE | 3x-ui/Xray 应怎么监听 | 切换时最重要的注意事项 |
| --- | --- | --- |
| `nginx-stream` | 面板、订阅、Xray 入站都监听 `127.0.0.1` 本地端口 | 3x-ui/Xray 不要直接占用公网 `443` |
| `tcp-peek` | 和 `nginx-stream` 相同，仍是本地端口 | 配置过程相同；公网 `443` 只从 `nginx` 换成 `vpso-mux` |
| `xray-fallback` | 需要一个 3x-ui/Xray 主入站监听公网 `443`，并 fallback 到 Web 反代引擎本地端口 | 切回其他模式前，必须先把这个 Xray 主入站从公网 `443` 移走 |

## Nginx Stream 默认稳定实现

Nginx Stream 是默认稳定模式。公网 `443` 由 Nginx stream 监听，使用 `ssl_preread` 读取 TLS ClientHello 里的 SNI，但不终止 TLS、不解密流量。

```text
公网 443
  -> Nginx stream ssl_preread
  -> panel/site/sub SNI  -> Caddy/Nginx 本地 Web 反代 TLS
  -> Xray/REALITY SNI   -> Xray/3x-ui 本地入站
  -> unknown SNI        -> 默认 Xray/REALITY 后端
```

这个实现覆盖面最完整，适合作为长期默认入口。它负责稳定接入 Web 反代引擎、REALITY、面板、订阅、网站、Web 白名单和回滚流程。

## TCP Peek + Splice / vpso-mux 实现

TCP Peek + Splice / vpso-mux 和 Nginx Stream 使用同一套 443 单入口配置。Web 域名、证书、Web 反代引擎后端、Web 白名单和 Xray SNI 分流记录都不需要另起一套；3x-ui 面板、订阅和 Xray 入站仍按本地监听填写。第一次使用时先运行 `主菜单 [19 443 单入口管理中心] -> [16] 查看 TCP Peek + Splice 状态 / 8444 预检`，确认 `vpso-mux` 能在 `8444` 启动并转发；再运行 `[17] TCP Peek 分流规则校验`。只有用户随后执行 `[5] 切换到 TCP Peek + Splice 模式`，公网 `443` 才会从 Nginx Stream 切到 `vpso-mux`。

`vpso-mux` 使用 `MSG_PEEK` 查看 TLS ClientHello 中的 SNI，不消费首包；后端收到的 ClientHello 仍与客户端原始数据一致。转发优先使用 splice，失败或不可用时回退普通 copy。

### TCP Peek 的连接生命周期

一次客户端连接进入 `vpso-mux` 后，大致按下面的顺序处理：

```text
客户端 TCP 连接
  -> vpso-mux accept
  -> recv(MSG_PEEK) 只查看接收缓冲区里的 ClientHello
  -> 从 ClientHello 扩展里解析 SNI
  -> 按 SNI 和源 IP 白名单选择 backend
  -> dial 后端本地端口
  -> 双向转发原始 TCP 字节流
```

这里最关键的是 `MSG_PEEK`。普通 `recv` 会把数据从 socket 接收缓冲区取走，后续转发时需要把已经读走的首包重新写给后端；`MSG_PEEK` 只是“看一眼”，不会移动读取位置。因此 `vpso-mux` 解析完 SNI 后，客户端发来的 TLS ClientHello 仍然留在原 socket 缓冲区里。后端连接建立后，第一批被转发过去的字节仍是客户端原始 ClientHello。

所以 TCP Peek 不是 TLS 终止，也不是中间人解密：

- 它不持有、不选择、不签发证书。
- 它不读取 HTTP 路径、Header、WebSocket 内容或 TLS 加密后的应用层数据。
- 证书和 HTTP 反代仍由当前 Web 反代引擎负责；Xray/REALITY 节点流量仍由 Xray/3x-ui 本地入站负责。
- 它只依赖 TLS 握手明文阶段里的 SNI 来做四层分流。

### ClientHello 里到底看什么

TLS 连接开始时，客户端会先发送 ClientHello。ClientHello 仍是明文结构，其中通常包含 `server_name` 扩展，也就是浏览器或代理客户端想访问的域名。`vpso-mux` 只解析这部分字段：

```text
TLS record
  -> record type = handshake
  -> handshake type = ClientHello
  -> extensions
  -> server_name extension
  -> hostname SNI
```

实现上会先 peek 约 4 KiB 数据。如果 ClientHello 没收完整，会继续扩大 peek 缓冲，最多到 16 KiB，并受 `timeouts.peek` 控制，脚本默认写入 `3s`。解析出的 SNI 会统一转成小写，并去掉末尾的点，例如 `Panel.Example.COM.` 会变成 `panel.example.com`。如果数据不是 TLS ClientHello、ClientHello 不完整、没有 SNI，或者协议本身不带 SNI，就不会命中特定域名规则，后续按默认后端处理。

这也是为什么本方案适合 HTTPS/TLS/SNI 流量，不适合按 HTTP path 或明文协议内容分流。到了 TLS 握手之后，应用层内容已经加密，`vpso-mux` 不会也不能靠它判断路径。

### 路由选择规则

脚本根据 443 单入口共享配置生成 `/etc/vps-optimize/vpso-mux.yaml`。生成出来的路由大致分成几类：

| 路由来源 | 目标后端 | 是否使用 Web 白名单 |
| --- | --- | --- |
| 面板域名 | Caddy/Nginx 本地 Web 反代 HTTPS 端口 | 是，如果该域名配置了白名单 |
| 普通网站 / 反代域名 | Caddy/Nginx 本地 Web 反代 HTTPS 端口 | 是，如果该域名配置了白名单 |
| 旧 TCP/SNI 本地入站记录 | 对应本地地址和端口 | 否 |
| Xray 入站管理记录 | 对应本地 Xray 入站地址和端口 | 否 |
| REALITY 伪装 SNI | 默认 Xray/REALITY 本地后端 | 否 |
| 未命中 SNI / 无 SNI / 非 TLS | 默认 Xray/REALITY 本地后端 | 否 |

匹配时先做精确 SNI 匹配，再做通配域名匹配。通配只匹配一层子域名，例如 `*.example.com` 可以匹配 `a.example.com`，不会匹配 `a.b.example.com`。如果某个 Web 路由配置了白名单，`vpso-mux` 会在分流前检查客户端源 IP；不在白名单内时直接拦截该连接。Xray 入站、REALITY SNI 和默认后端不应用 Web 白名单，避免把节点流量误伤。

### splice 和 copy 的区别

完成路由选择并连接到后端后，`vpso-mux` 才开始转发。转发有两种模式：

| 模式 | 工作方式 | 适合情况 |
| --- | --- | --- |
| `splice` | Linux 内核在 socket 和 pipe 之间搬运数据，尽量减少用户态拷贝 | 正常优先路径 |
| `copy` | Go 进程用普通读写循环转发数据 | splice 不可用、失败或被关闭时的回退路径 |

默认配置是：

```yaml
splice:
  enabled: true
  pipe_size: 1048576
  fallback_to_copy: true
```

也就是说，`vpso-mux` 会优先尝试 splice。如果当前内核、socket 状态或运行环境不适合 splice，并且 `fallback_to_copy` 为 `true`，它会自动回退到普通 copy。copy 不是错误，只是少了零拷贝优化；状态页或 `status.json` 里的 `copy_fallback` 可以用来观察是否经常回退。

需要注意的是，splice 优化的是“已选定后端之后的字节转发”，不改变分流逻辑。SNI 判断仍然发生在连接开始时的 ClientHello 阶段；一旦后端选定，后续同一条 TCP 连接不会再根据内容重新分流。

splice 路径也会受 `timeouts.idle` 控制。`vpso-mux` 使用非阻塞 splice 并在读写文件描述符前等待可读/可写事件；如果连接长时间没有数据，会按 idle 超时关闭，而不是让空闲连接一直占住转发 goroutine。copy 路径继续使用普通读写 deadline。

### 并发保护和状态刷新

`vpso-mux` 内置连接并发保护。脚本生成的新配置会写入：

```yaml
limits:
  max_connections: 4096
```

旧的 `vpso-mux.yaml` 即使没有 `limits` 字段，也会由程序自动使用同样的默认值；用户不需要手动迁移配置。如果确实要关闭这个限制，可以把 `max_connections` 设为 `0`，表示不做程序内连接数限制。

慢速握手也会被保护：客户端连接后如果在 `timeouts.peek` 时间内没有发出完整的 ClientHello，`vpso-mux` 会关闭这条连接，而不是把它转到默认 Xray/REALITY 后端。默认 `timeouts.peek` 是 `3s`，正常浏览器和代理客户端不会感知到这个变化。

运行状态写入 `/var/lib/vps-optimize/vpso-mux/status.json`。新版本不再每条连接都立即写磁盘，而是把计数保存在内存里并定时刷新，退出前再写一次。状态页会显示当前连接数、连接上限、拒绝连接数、后端拨号错误、peek 错误、peek 超时次数和双向转发字节数，便于判断是否遇到连接洪峰、慢握手占用或后端端口异常。

### 路由索引

`vpso-mux` 会在配置校验通过后预编译路由索引。精确 SNI 使用 map 查询，通配 SNI 保留为有序列表；匹配语义保持不变，仍然是精确匹配优先于通配匹配，通配匹配保持配置中的顺序。这个优化不会改变 `vpso-mux.yaml` 格式，也不要求用户重新填写域名。

TCP Peek 的主要优点：

- 配置过程和 Nginx Stream 一样，切换时复用已经保存的域名、证书、Web 反代引擎后端、Web 白名单和 Xray SNI 路由。
- `MSG_PEEK` 只查看 ClientHello，不消费首包，后端收到的仍是客户端原始 TLS 握手数据。
- 转发优先使用 splice，减少用户态数据拷贝；不可用时自动回退普通 copy。
- `vpso-mux` 是专门为 443 SNI 分流准备的入口程序，状态、日志、配置校验和 8444 预检都围绕这个链路展开。

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
| 配置过程 | 使用 443 单入口共享配置 | 使用同一套 443 单入口共享配置 |
| 入口进程 | `nginx` | `vpso-mux` |
| SNI 获取 | `ssl_preread` | `MSG_PEEK` 解析 ClientHello |
| TLS 处理 | 不终止 TLS | 不终止 TLS |
| 证书 | 当前 Web 反代引擎处理 Web/面板证书 | 当前 Web 反代引擎处理 Web/面板证书 |
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

Xray Fallback 是特殊模式：公网 `443` 由已有 Xray/3x-ui 主入站监听，HTTPS fallback 到当前 Web 反代引擎。本脚本不会创建、删除或修改 3x-ui/Xray 入站内部配置。

```text
公网 443
  -> Xray/3x-ui 主入站
  -> Xray 节点流量由该主入站处理
  -> HTTPS fallback 到 Caddy/Nginx 本地 Web 反代后端
```

在 xray-fallback 模式下，`Xray 入站管理` 菜单不可用于多本地入站 SNI 分流。原因是公网 `443` 已由 Xray 主入站接管，脚本当前不支持在该模式下继续把多个 SNI 分流到多个本地 Xray 入站。如需多个本地 Xray 入站分流，请使用 Nginx Stream 模式或 TCP Peek + Splice / vpso-mux 模式。

## 切换与回滚

切换到 TCP Peek + Splice：

```text
主菜单 [19 443 单入口管理中心]
  -> [16] 查看 TCP Peek + Splice 状态 / 8444 预检
  -> [17] TCP Peek 分流规则校验
  -> [5] 切换到 TCP Peek + Splice 模式
```

切换流程不会在公网 `443` 切换路径里自动下载 Go 工具链或远端编译 `vpso-mux`。如果 `/usr/local/bin/vpso-mux` 不存在，脚本会拒绝切换，要求先走 `[16]` 的 `8444` 预检。正式切换前脚本会再次启动独立 `vpso-mux-preflight.service` 监听 `8444`，确认 Web 反代引擎和 Xray 本地后端可达；预检失败时公网 `443` 不会被替换。

正式切换会生成并校验 `vpso-mux.yaml`、创建备份、隔离当前 VPS-Optimize 管理的 Nginx stream 443 配置、启动 `vpso-mux` 接管公网 `443`，并检查 Web 反代引擎和 Xray 本地后端可达。失败时会尝试自动回滚。

`8444` 预检会额外做 TCP Peek 路由矩阵检查：面板域名和 Web 域名会通过测试端口按 SNI 获取证书链；默认 Xray/REALITY 后端、旧 TCP/SNI 记录和 `Xray 入站管理` 记录会检查对应本地地址和端口是否可连。这样可以在正式接管公网 `443` 之前发现缺失证书、Web 反代引擎未就绪或本地 Xray 入站端口未监听的问题。

如果当前 SSH 会话连接在入口端口，例如 `443`，脚本会拒绝切换，避免直接断开当前管理连接。请改用云厂商 VNC/Serial Console，或先用非入口端口 SSH 登录。

回滚上一轮入口模式切换：

```text
主菜单 [19 443 单入口管理中心]
  -> [7] 回滚上一次入口模式切换
```

通用回滚会恢复上一次入口模式切换前的备份，适合撤销最近一次 `[3]`、`[4]` 或 `[5]` 触发的入口切换。TCP Peek 切换后需要回退时，也使用这个范围更广的回滚入口。

## 常见故障

检查公网 443 当前监听方：

```bash
ss -lntup | grep ':443'
```

切换到 TCP Peek + Splice 后应看到 `vpso-mux`。如果仍是 Nginx、Caddy 或 Xray，说明入口关系没有切换干净，建议立即回滚。

检查 Web 反代引擎本地 TLS 后端：

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

TCP Peek 常见边界：

| 现象 | 原因 | 处理方向 |
| --- | --- | --- |
| `no_sni` 次数增加 | 客户端没有带 SNI，或连接不是标准 TLS ClientHello | 确认客户端节点域名/SNI 设置；非 TLS 流量会走默认后端 |
| 命中了默认后端 | SNI 没有匹配任何 route，或 SNI 解析失败 | 检查 `/etc/vps-optimize/vpso-mux.yaml` 里的 routes 和实际客户端 SNI |
| Web 域名被拦截 | 该 Web route 配了白名单，源 IP 不在范围内 | 检查对应域名的 Web 白名单，不要把它当成 Xray 节点限制 |
| `copy_fallback` 增加 | splice 未使用或运行中回退 copy | 一般不影响可用性；如需稳定观察性能，可先保持默认回退 |
| `backend_dial_errors` 增加 | SNI 命中了规则，但目标本地后端连接失败 | 检查 Caddy / Xray / 3x-ui 本地监听端口 |
| `peek_errors` 增加 | ClientHello 解析或读取出现异常 | 检查异常客户端、扫描流量或过大的握手包 |
| `peek_timeouts` 增加 | 有连接在超时时间内没有发出完整 ClientHello | 检查是否有慢连接、探测流量或异常客户端 |
| `rejected_connections` 增加 | 达到连接上限、peek 超时或被白名单拦截 | 看 `recent_errors` 和 route hits，再决定是否调整客户端或连接上限 |
| 转发字节一直为 0 | 连接进入了入口，但没有完成有效双向转发 | 结合 route hits、后端拨号错误和日志继续定位 |
| 后端连接失败 | SNI 命中了规则，但本地后端端口没监听或地址不一致 | 检查 Caddy / Xray / 3x-ui 本地监听端口是否与脚本保存值一致 |
