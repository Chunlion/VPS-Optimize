# TCP Peek + Splice 443 分流引擎

`tcp_peek` 是 VPS-Optimize 新增的 experimental 443 单入口引擎。它的目标是用一个轻量本地守护进程 `vpso-mux` 承担原来 Nginx stream 的四层入口职责：

```text
公网 TCP 443
  -> vpso-mux
  -> recv(MSG_PEEK) 偷看 TLS ClientHello SNI
  -> 按 SNI / whitelist 选择后端
  -> splice 零拷贝双向转发
  -> splice 不可用时 fallback 到普通 copy 转发
```

它不终止 TLS，不解密 TLS，不修改首包，不管理证书，不替换 Caddy，也不是让 Xray/REALITY 直接占用 443。

## 为什么新增 tcp_peek

现有稳定方案是 `nginx_stream`：公网只开放 443，由 Nginx stream `ssl_preread` 按 SNI 分流到 Caddy、REALITY、面板、订阅和网站。这套方案继续是默认稳定模式。

`tcp_peek` 提供一个可实验、可回滚的替代入口，便于进阶用户在不引入完整 Nginx stream 入口的情况下做四层 SNI 分流，并观察自研转发链路的行为。

## 和 Nginx Stream 的区别

| 项目 | nginx_stream | tcp_peek |
| --- | --- | --- |
| 状态 | 默认 stable | experimental |
| 入口进程 | Nginx stream | vpso-mux |
| SNI 获取 | `ssl_preread` | `recv(MSG_PEEK)` 解析 ClientHello |
| TLS 终止 | 不终止 | 不终止 |
| 证书 | 仍由 Caddy 处理网站/面板证书 | 仍由 Caddy 处理网站/面板证书 |
| 默认未知 SNI | Xray/REALITY 后端 | Xray/REALITY 后端 |
| 转发 | Nginx proxy | splice，失败回退 copy |

## 架构图

```text
                 +-----------------------+
client:443 ----> | vpso-mux tcp_peek     |
                 | MSG_PEEK ClientHello  |
                 +----------+------------+
                            |
          +-----------------+------------------+
          |                                    |
  SNI = panel/site/sub                 unknown SNI / REALITY SNI
          |                                    |
          v                                    v
  127.0.0.1:8443 Caddy                 127.0.0.1:1443 Xray/REALITY
          |
          +--> panel backend / subscription backend / website backend
```

## 数据流说明

`vpso-mux` accept TCP 连接后，会设置首包 peek 超时，先用 `MSG_PEEK` 读取最多 4KB，必要时扩展到 16KB。`MSG_PEEK` 只偷看 socket 缓冲区，不消费数据，所以后端收到的 TLS ClientHello 与客户端发来的原始数据一致。

解析成功后，`vpso-mux` 按 route 选择后端；解析失败、非 TLS、无 SNI 或未知 SNI 默认走 `default_backend`。默认配置会把 `default_backend` 指向 Xray/REALITY 本地后端。

## splice 转发

Linux `splice` 不能直接 socket 到 socket。`vpso-mux` 使用：

```text
client socket -> pipe -> backend socket
backend socket -> pipe -> client socket
```

每个方向独立转发，并在 `splice` 不可用、失败或被配置关闭时回退到普通 read/write copy。日志里的 `transfer_mode` 会记录 `splice` 或 `copy`。

## 为什么仍保留 nginx_stream

`nginx_stream` 是默认稳定模式，已经覆盖证书、Caddy、REALITY、面板、订阅、网站、白名单和回滚流程。`tcp_peek` 只是新增 experimental 引擎，不会默认接管 443，也不会删除现有 Nginx stream 逻辑。

## 如何先用 8444 测试

菜单路径：

```text
主菜单 [18 443 单入口管理中心]
  -> [14] 生成 tcp_peek 配置
  -> [15] tcp_peek dry-run 配置校验
  -> [16] 启动 tcp_peek 测试端口 8444
```

测试端口阶段不会改公网 443，Nginx stream 仍继续负责线上入口。

常用测试命令：

```bash
openssl s_client -connect SERVER_IP:8444 -servername panel.example.com
openssl s_client -connect SERVER_IP:8444 -servername site.example.com
openssl s_client -connect SERVER_IP:8444 -servername random.example.com
curl -vk --resolve site.example.com:8444:SERVER_IP https://site.example.com:8444/
```

把示例域名替换成脚本生成配置里的真实域名。

## 如何切换 443

确认 8444 测试正常后再进入：

```text
主菜单 [18 443 单入口管理中心]
  -> [17] 切换公网 443 到 tcp_peek
```

切换会执行事务式流程：

1. 生成临时 `vpso-mux.yaml`。
2. dry-run 校验配置。
3. 创建完整备份。
4. 替换正式 mux 配置。
5. 隔离当前 VPS-Optimize 管理的 Nginx stream 443 配置。
6. 重启 Nginx。
7. 启动 `vpso-mux` 接管公网 443。
8. 检查 `ss -lntup` 中 443 是否由 `vpso-mux` 监听。
9. 检查 Caddy 和 Xray 本地后端可达。
10. 失败自动回滚。

## 如何回滚

菜单路径：

```text
主菜单 [18 443 单入口管理中心]
  -> [18] 从 tcp_peek 回滚到 nginx_stream
```

回滚会停止并禁用 `vpso-mux`，读取 `sni-stack.env` 重新生成 Nginx stream 和 Caddy 配置，恢复默认 stable 引擎，并运行链路体检。

## 白名单如何生效

白名单是按 route 生效，不是全局锁死 443：

- 面板域名配置 whitelist 时，只有命中的 IPv4、IPv6、CIDR 可以访问该 route。
- 未配置 whitelist 的网站域名保持公开。
- `default_backend` 不默认套用面板白名单。
- unknown SNI 默认仍走 Xray/REALITY。
- 单 IP 会被程序按 `/32` 或 `/128` 处理。

如果面板或订阅 route 没有 whitelist，dry-run 会给出高亮警告。

## 常见故障

### 443 被占用

运行：

```bash
ss -lntup | grep ':443'
```

切换到 `tcp_peek` 后应看到 `vpso-mux`。如果仍是 Nginx、Caddy 或 Xray，说明入口关系没有切干净，建议立即回滚。

### SNI 解析失败

非 TLS、无 SNI、ClientHello 不完整或客户端协议不带 SNI 时会走 `default_backend`。这不是 TLS 终止失败，因为 `vpso-mux` 不解密、不终止 TLS。

### 面板白名单失效

检查 `/etc/vps-optimize/vpso-mux.yaml` 中 panel route 是否有 `whitelist`，再看日志里的 `allowed` / `blocked` 字段。不要把白名单写成全局规则。

### Caddy 后端不可达

确认 Caddy 只监听本地 TLS 端口：

```bash
ss -lntup | grep ':8443'
systemctl status caddy --no-pager
```

### Xray 后端不可达

确认 Xray/REALITY 本地入站监听：

```bash
ss -lntup | grep ':1443'
systemctl status xray --no-pager
```

### splice 失败 fallback

查看日志：

```bash
journalctl -u vpso-mux -n 80 --no-pager
```

如果 `transfer_mode` 是 `copy`，说明 splice 未使用或已回退。可以在 `vpso-mux.yaml` 中设置：

```yaml
splice:
  enabled: false
  fallback_to_copy: true
```

### IPv6 监听失败

如果 VPS 没有 IPv6 或系统禁用了 IPv6，`[::]:443` 可能监听失败。可以只保留：

```yaml
listen:
  tcp:
    - "0.0.0.0:443"
```

### systemd 启动失败

检查：

```bash
systemctl status vpso-mux --no-pager
journalctl -u vpso-mux -n 120 --no-pager
/usr/local/bin/vpso-mux -config /etc/vps-optimize/vpso-mux.yaml -check
```

若 `/usr/local/bin/vpso-mux` 不存在，需要先安装发布版二进制，或在源码目录安装 Go 后构建。
