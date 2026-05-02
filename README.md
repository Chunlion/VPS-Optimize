# 🚀 VPS-Optimize

一个面向 VPS 日常运维的 Bash 控制面板，把新机器预检、系统初始化、安全加固、网络优化、面板部署、订阅工具、备份回滚和 `443` 单入口分流集中到一个 `cy` 命令里。

它适合有一定 Linux/VPS 基础、希望少记命令但仍保留可控性的用户。第一次部署建议按 README 的推荐流程走；后续维护通常只需要进入 `cy` 面板选择对应入口。

> ⚠️ 脚本会修改系统服务、防火墙、内核参数、Nginx/Caddy 配置、Docker 配置和证书文件。动 SSH、防火墙、内核、证书、`443` 单入口前，请先做快照或备份，并保留当前 SSH 会话。

## ✨ 核心能力

| 场景 | 能做什么 |
| --- | --- |
| 新机器初始化 | 预检系统、安装常用工具、设置时区、开启基础 BBR |
| 安全加固 | SSH 加固、公钥登录、Fail2ban、防火墙规则管理 |
| 面板与订阅 | 3x-ui、S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari |
| 网络与诊断 | 内核优化、测速、流媒体检测、端口排查、服务健康总览 |
| 443 单入口 | 公网只开放 `443`，按 SNI 分流到面板、订阅、网站和 REALITY |
| 备份回滚 | 重要配置备份、列表查看、恢复和隔离归档 |

## 📚 目录

- [⚡ 快速开始](#quick-start)
- [⚠️ 使用前必读](#before-you-start)
- [🧭 推荐流程](#recommended-flow)
- [🧰 功能地图](#features)
- [⌨️ 快捷输入](#shortcuts)
- [🧩 443 单入口分流](#single-443-entry)
- [📡 订阅管理与节点工具](#node-tools)
- [🧩 独立工具](#standalone-tools)
- [🛡️ 安全与回滚](#safety)
- [🔄 更新与卸载](#update-uninstall)
- [❓ 常见问题](#faq)
- [💬 反馈与联系](#feedback)

<a id="quick-start"></a>
## ⚡ 快速开始

在服务器上使用 `root` 运行：

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行后会注册全局快捷命令，以后直接输入：

```bash
cy
```

面板预览：

![VPS-Optimize 面板预览](https://i.mji.rip/2026/04/28/ed5bf23f4ebf88300819ff3520bac2df.png)

<a id="before-you-start"></a>
## ⚠️ 使用前必读

1. 建议使用 `root` 运行。非 root 用户先执行：

   ```bash
   sudo -i
   ```

2. 云厂商安全组和系统防火墙是两层东西。脚本能管理系统里的 `ufw` / `firewalld`，但不能替你打开阿里云、甲骨文、AWS、Azure 等网页后台安全组。

3. 修改 SSH 端口前，先在云厂商安全组放行新端口，并保留一个未断开的 SSH 会话。

4. 启用 443 单入口后，公网 `443` 应只由 Nginx stream 监听。Caddy、3x-ui 面板、REALITY 入站、订阅服务和网站后端默认都应监听 `127.0.0.1`。

5. 不建议在没有快照、备份或救援控制台的生产机器上直接运行高风险功能。

<a id="recommended-flow"></a>
## 🧭 推荐流程

第一次使用时，不建议一上来直接装面板。先预检、再初始化、再部署服务，排错会简单很多。

| 目标 | 推荐顺序 |
| --- | --- |
| 新机器基础初始化 | `1` 运维预检 → `2` 基础环境初始化 → `5` SSH 加固 → `6` 添加 SSH 公钥 → `7` Fail2ban → `8` 防火墙 → `10` 网络与内核优化 → `15` 健康总览 → `16` 备份 |
| 部署面板、节点和订阅工具 | `1` 运维预检 → `3` 基础组件与反代分流 → `4` 面板、节点与订阅工具 → `19` 443 单入口管理中心 → `15` 健康总览 → `16` 备份 |
| 后续维护 | `15` 健康总览 → `13` 端口排查 → `16` 备份/回滚 → `17` 更新脚本 → `19` 443 单入口维护 |
| 新增网站或反代域名 | `19` 443 单入口管理中心 → `2` 管理网站/反代域名 |

<a id="features"></a>
## 🧰 功能地图

主菜单按使用频率分组。新机器先从 `1` 开始，面板和节点进 `4`，所有 443 相关操作进 `19`。

| 你想做什么 | 入口 | 说明 |
| --- | --- | --- |
| 新机器先体检 | `1` | 看系统、端口、DNS、磁盘、内存和关键命令 |
| 做基础初始化 | `2` | 安装常用工具、设置时区、系统更新、基础 BBR |
| 安装 Docker/Caddy/WARP | `3` | 基础组件、普通 Caddy 反代和 443 向导入口 |
| 安装面板、节点、订阅工具 | `4` | 3x-ui、S-UI、Sing-box、Xray、订阅管理、Dockge、Komari |
| 改 SSH 端口 | `5` | 改前先放行云厂商安全组新端口 |
| 管理防火墙端口 | `8` | 放行、删除、查看、关闭系统防火墙规则 |
| 网络与内核优化 | `10` | BBR/TCP/ZRAM/轻量内核 |
| 测速和质量检测 | `12` | YABS、流媒体、回程、IP 质量 |
| 排查端口占用 | `13` | 查看监听端口，必要时释放端口 |
| 查看服务是否正常 | `15` | 服务状态、证书摘要、监听端口概览 |
| 备份或回滚配置 | `16` | 重要操作前建议先备份 |
| 更新脚本 | `17` | 从 GitHub 拉取最新 `vps.sh` |
| 部署 3x-ui + REALITY + 443 | `19 -> 1` | 首次配置 443 单入口 |
| 后续新增网站或反代域名 | `19 -> 2` | 不需要重跑首次配置 |
| 443/证书/面板打不开 | `19 -> 3` 或 `19 -> 6` | 先体检链路，再进证书维护 |

<a id="shortcuts"></a>
## ⌨️ 快捷输入

主面板除了数字，也支持常用快捷词：

| 输入 | 入口 |
| --- | --- |
| `443` / `sni` | 443 单入口管理中心 |
| `h` / `health` | 服务健康总览 |
| `b` / `backup` | 配置备份与回滚 |
| `u` / `update` | 更新脚本 |
| `q` / `exit` | 退出面板 |

`dog` 面板也支持：

| 输入 | 入口 |
| --- | --- |
| `add` | 添加/删除端口监控 |
| `limit` | 配额/限速管理 |
| `tg` | Telegram 通知管理 |
| `report` | 日报与趋势报表 |
| `u` | 检查并热更新脚本 |
| `q` | 退出 |

<a id="single-443-entry"></a>
## 🧩 443 单入口分流

443 单入口用于解决多个服务争抢公网 `443` 的问题。

典型结构：

```text
公网 443 -> Nginx stream 按 SNI 分流

panel.example.com       -> Caddy -> 3x-ui 面板
sub.example.com         -> Caddy -> SublinkPro / Sub-Store / 其他 HTTP 后端
dockge.example.com      -> Caddy -> Dockge
REALITY 伪装 SNI        -> Xray / 3x-ui REALITY 入站
未知 SNI                -> Xray / 3x-ui REALITY 入站
```

核心原则：

- 公网 `443` 只给 Nginx stream。
- Caddy 默认监听 `127.0.0.1:8443`。
- REALITY 默认监听 `127.0.0.1:1443`。
- 3x-ui 面板默认监听 `127.0.0.1:40000`。
- 3x-ui 面板 SSL/HTTPS 应关闭，证书路径和私钥路径留空。
- REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 必须写外部真实 HTTPS 站点，不要写面板域名。

如果机器上已经有普通 Caddy 反代，启用 443 单入口前请先备份并记录旧站点的域名、后端地址和端口。脚本会隔离可能抢占公网 `443` 的旧 Caddy 配置，但不会自动把旧反代规则迁移成新的 443 单入口站点；启用后需要通过 `19 -> 2` 手动补录旧网站。

完整教程请看：[443 单入口分流详细教程](docs/443-single-entry.md)。

<a id="node-tools"></a>
## 📡 订阅管理与节点工具

节点和订阅相关入口集中在：

```text
4. 面板、节点与订阅工具
```

常用入口：

```text
1. 管理 3x-ui 面板
2. 管理 S-UI 面板
3. 管理 Sing-box
4. 管理 Xray
5. 管理 SublinkPro
6. 管理 妙妙屋订阅管理
7. 管理 Sub-Store
8. 管理 Dockge
9. 更新订阅管理工具
10. 迁移 Compose 到 Dockge
11. 面板救砖 / 重置 SSL
12. DNS 流媒体解锁
13. 防 IP 送中脚本
14. 端口流量监控
15. 管理 Komari 探针监控
16. 3x-ui 外置增强管理
```

Docker Compose 部署项目都有独立的“管理 / 归档”入口。普通停止会保留部署目录和数据；归档部署目录需要输入 `ARCHIVE` 二次确认，目录会移动到隔离区，避免误删配置和数据库。

Komari 默认部署到 `/opt/komari`，数据保存在 `/opt/komari/data`。安装时可选择自定义初始管理员账号和密码；如果不自定义，安装完成后可查看容器日志获取默认管理员账号。如需 HTTPS 访问，建议通过 `19 -> 2` 添加 443 单入口反代域名。

<a id="standalone-tools"></a>
## 🧩 独立工具

仓库里除了主脚本 `vps.sh`，还包含两个可以单独运行的维护工具。

### 3x-ui 外置增强管理

项目包含 `xui-custom-manager.sh`，用于补充 3x-ui / x-ui 面板外更适合脚本处理的维护功能：自定义重置日期、流量校准、备份恢复、健康检查、查看日志和清理旧备份。

入口：

```text
4. 面板、节点与订阅工具
16. 3x-ui 外置增强管理
```

单独运行：

```bash
wget -qO xui-custom-manager.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh && chmod +x xui-custom-manager.sh && ./xui-custom-manager.sh
```

首次打开后会自动注册 `xcm` 快捷命令。`xcm` 是手动入口，会优先拉取最新版；systemd timer 只调用本地稳定执行器 `/usr/local/bin/xui-custom-manager.sh --reset-check`。

详细说明请看：[README_xui_custom_manager.md](README_xui_custom_manager.md)。

### 端口流量狗

项目包含 `dog.sh`，用于部署 Port Traffic Dog。它基于 `nftables` 和 `tc` 做端口流量统计、限额、限速、日报趋势和 Telegram 查询。

运行方式：

```bash
wget -qO dog.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh && chmod +x dog.sh && ./dog.sh
```

安装后通常可以用：

```bash
dog
```

进入管理菜单。详细说明请看：[README_dog.md](README_dog.md)。

<a id="safety"></a>
## 🛡️ 安全与回滚

高风险功能会要求输入 `YES`。不确定时先做 `16. 配置备份与回滚`。

脚本现在对目录级清理采用“隔离/归档优先”的策略：旧证书缓存、Compose 部署目录、Fail2ban 配置、手动旧备份、Port Traffic Dog 配置等会尽量移动到隔离目录，而不是直接递归删除。常见隔离目录包括：

```text
/root/vps-optimize-quarantine
/root/.acme.sh/_quarantine
/opt/.vps-optimize-quarantine
/etc/vps-optimize/quarantine
/etc/vps-optimize/quarantine/nginx-sni
/etc/vps-optimize/quarantine/caddy-sni
/etc/vps-optimize/quarantine/caddy-certs
/etc/vps-optimize/quarantine/caddy-conf
/etc/vps-optimize/quarantine/docker
/etc/vps-optimize/quarantine/sysctl
/etc/vps-optimize/quarantine/manual-backups
/root/port-traffic-dog-quarantine
```

确认隔离内容无用后，再手动清理对应目录。

高风险操作建议：

| 功能 | 风险 | 建议 |
| --- | --- | --- |
| SSH 改端口 | 云安全组未放行会失联 | 先开安全组，保留当前 SSH 会话 |
| 防火墙关闭/删除规则 | 可能暴露服务或阻断连接 | 修改前记录现有规则 |
| 端口强杀 | 可能杀掉 `sshd`、数据库、面板 | 不要强杀 SSH 端口和未知关键服务 |
| Caddy 配置重置 | 可能导致反代暂时失效 | 先备份 `/etc/caddy` |
| 证书缓存隔离 | 可能需要重新签发 HTTPS 证书 | 确认域名和证书路径 |
| 旧内核清理 | 误删云厂商定制内核会影响启动 | 不要删除当前内核和 `cloud` 内核 |
| Docker 本地防穿透 | 会改变 Docker 默认端口绑定行为 | 确认容器是否需要公网直连 |
| 443 单入口 | 会接管公网 `443` | 先确认没有其他服务占用公网 `443`，失败时优先用脚本生成的 SNI stack 备份回滚 |

<a id="update-uninstall"></a>
## 🔄 更新与卸载

更新主脚本：

```text
17. UPD 更新脚本
```

手动更新：

```bash
wget -qO /usr/local/bin/cy https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh
chmod +x /usr/local/bin/cy
cy
```

只卸载快捷命令：

```bash
rm -f /usr/local/bin/cy
```

这不会自动恢复脚本已经修改过的系统配置。系统服务、Nginx/Caddy 配置、防火墙规则、Docker 配置、证书和内核参数需要按实际情况单独回滚，建议优先使用脚本内的备份与回滚功能。

<a id="faq"></a>
## ❓ 常见问题

### 🔐 运行脚本提示不是 root

执行：

```bash
sudo -i
```

再重新运行脚本。

### 🔌 修改 SSH 端口后连不上

先检查云厂商安全组是否放行了新端口。然后在当前未断开的 SSH 会话里检查：

```bash
ss -lntp | grep ssh
systemctl status ssh --no-pager
systemctl status sshd --no-pager
```

不同发行版 SSH 服务名可能是 `ssh` 或 `sshd`。

### 🧩 443 单入口配置后面板打不开

优先检查：

- 3x-ui 面板是否监听 `127.0.0.1:40000`。
- 3x-ui 面板 SSL/HTTPS 是否关闭。
- Caddy 是否监听 `127.0.0.1:8443`。
- Nginx stream 是否监听公网 `0.0.0.0:443`。
- 云安全组是否放行 `443`。
- 面板域名 DNS 是否解析到当前服务器。

详细排错请看：[443 单入口分流详细教程](docs/443-single-entry.md)。

### 🌐 浏览器访问内部端口报错

单入口模式下，浏览器只访问标准 HTTPS 地址：

```text
https://panel.example.com/panel-a8f3c9/
https://sub.example.com/
```

不要访问：

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

### 🔄 更新脚本失败

检查 DNS 和 GitHub 连通性：

```bash
getent ahosts raw.githubusercontent.com
curl -I https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh
```

如果你的环境访问 GitHub 不稳定，可以先解决 DNS、IPv4/IPv6 优先级或代理出口问题。

<a id="feedback"></a>
## 💬 反馈与联系

如有 Bug 或建议，欢迎前往 [GitHub Issues](https://github.com/Chunlion/VPS-Optimize/issues) 提交反馈。

也可以通过作者 [GitHub 主页](https://github.com/Chunlion) 展示的联系方式或邮箱联系。

## 📜 开源协议

本项目使用 [MIT License](LICENSE)。
