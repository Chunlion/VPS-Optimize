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

## 443 单入口配置后面板打不开

优先检查：

- 当前入口模式对应的单个服务是否监听公网 `443`。
- 面板和订阅后端是否监听本地地址。
- 3x-ui 面板证书路径是否已经清空。
- Web 反代引擎配置是否通过校验。
- 云安全组是否放行 `443/tcp`。
- 域名 DNS 是否解析到当前服务器。

详细排查见 [443 单入口排错手册](443-single-entry-troubleshooting.md)。

## 浏览器访问内部端口报错

443 单入口模式下，浏览器只访问标准 HTTPS 地址：

```text
https://panel.example.com/panel/
https://sub.example.com/
```

不要从公网访问内部端口：

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

## 动态 TCP 参数怎么粘贴

入口：

```text
主菜单 [10 网络与内核优化] -> [2 动态 TCP 参数调优]
```

进入后按提示粘贴多行 `sysctl` 参数，粘贴完成后另起一行输入 `EOF` 并回车保存。

