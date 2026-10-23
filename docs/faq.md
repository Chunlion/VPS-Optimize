# 常见问题

## 运行脚本提示不是 root

先切换到 root：

```bash
sudo -i
```

然后重新运行脚本。

## 修改 SSH 端口后连不上

先检查云厂商安全组是否放行了新端口。如果旧 SSH 会话还在，不要关闭它。

```bash
ss -lntp | grep ssh
systemctl status ssh --no-pager || systemctl status sshd --no-pager
```

不同发行版 SSH 服务名可能是 `ssh` 或 `sshd`。

## 443端口复用配置后面板打不开

优先检查：

- 当前入口模式对应的单个服务是否监听公网 `443`。
- 面板和订阅后端是否监听本地地址。
- 3x-ui 面板证书路径是否已经清空。
- Web 反代引擎配置是否通过校验。
- 云安全组是否放行 `443/tcp`。
- 域名 DNS 是否解析到当前服务器。

详细排查见 [443端口复用排错指南](443-single-entry-troubleshooting.md)。

## 浏览器访问内部端口报错

443端口复用模式下，浏览器只访问标准 HTTPS 地址：

```text
https://panel.example.com/panel/
https://panel.example.com/sub/
```

3x-ui 的订阅走面板域名加 URI 路径。只有独立订阅工具（SublinkPro、Sub-Store 等）才使用它自己的域名，例如 `https://tool.example.com/`。不要从公网访问内部端口：

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

## XHTTP 节点能和面板共用 443 吗

可以，但有两种接法：

- **共用 Web 域名**：`主菜单 [19 443端口复用管理中心] -> [2 管理 Web 域名与反向代理] -> [10 XHTTP 节点路径反代]`。3x-ui 里的 XHTTP 入站要监听 `127.0.0.1` 且不启用 TLS，TLS 由本地 Caddy/Nginx 处理。客户端使用同一个域名，路径填登记过的路径。
- **独立节点域名**：和普通 TLS 节点一样，在 `[4 管理 Xray SNI 转发规则]` 登记域名到本地端口，证书由 XHTTP 入站自己使用。

共用域名时，该域名的 Web 白名单会一起限制 XHTTP；`xray-fallback` 模式不支持路径反代；XHTTP 的 HTTP/3 需要 UDP `443`，当前入口不支持。完整步骤见 [REALITY 与 XHTTP 共存教程](../tutorials/03-xhttp-reality-shared-443.md)。

## 动态 TCP 参数怎么粘贴

入口：

```text
主菜单 [10 网络与内核优化] -> [2 动态 TCP 参数调优]
```

进入后按提示粘贴多行 `sysctl` 参数，粘贴完成后另起一行输入 `EOF` 并回车保存。

