# 🚀 VPS-Optimize

一个面向 VPS 日常运维、网络调优、安全加固、面板部署和 443 单入口分流的 Bash 控制面板。

它不是单个功能脚本，而是把常见 VPS 操作整理成一个可反复调用的菜单：新机器初始化、SSH 加固、Docker 管理、Caddy 反代、Nginx Stream + Caddy + REALITY 单入口、订阅管理工具、测速诊断、备份回滚都集中在 `cy` 面板里。

> 项目适合有一定 Linux/VPS 基础的用户。脚本会修改系统服务、防火墙、内核参数、Nginx/Caddy 配置和 Docker 配置，请先看完“使用前必读”和“高风险功能”。

![VPS-Optimize 面板预览](https://i.mji.rip/2026/04/28/ed5bf23f4ebf88300819ff3520bac2df.png)

## 📚 目录

- [🎯 适用场景](#scenarios)
- [⚠️ 使用前必读](#before-you-start)
- [⚡ 快速开始](#quick-start)
- [🧭 推荐使用流程](#recommended-flow)
- [🧰 功能总览](#features)
- [🧩 443 单入口分流](#single-443-entry)
- [📡 订阅管理与节点工具](#node-tools)
- [📊 端口流量监控](#traffic-dog)
- [🛑 高风险功能](#high-risk)
- [❓ 常见问题](#faq)
- [🔄 更新与卸载](#update-uninstall)
- [💬 反馈与联系](#feedback)

<a id="scenarios"></a>
## 🎯 适用场景

- 新买 VPS 后快速完成基础初始化、时区、基础工具和 BBR。
- 管理 SSH 端口、防火墙、Fail2ban、SSH 公钥等基础安全项。
- 部署 Docker、Python、Caddy、WARP、哪吒、宝塔、Sing-box、Xray、3x-ui 等常见组件。
- 把 3x-ui 面板、订阅入口、REALITY 入站、SublinkPro、Dockge、妙妙屋、Sub-Store 或普通网站统一收进公网 `443`。
- 排查端口占用、服务状态、证书、系统资源、IP 质量、流媒体解锁和回程线路。
- 做配置备份、恢复、健康检查和脚本热更新。

不建议在以下环境直接无脑运行：

- 生产业务机器，且没有快照、备份或救援控制台。
- 已有复杂 Nginx/Caddy/防火墙/Docker 网络配置，且不清楚现有规则依赖关系。
- LXC/OpenVZ 等受限虚拟化环境，尤其是涉及内核、ZRAM、BBR 增强时。

<a id="before-you-start"></a>
## ⚠️ 使用前必读

1. 请优先使用 `root` 运行。非 root 用户先执行：

   ```bash
   sudo -i
   ```

2. 云厂商安全组和系统防火墙是两层东西。脚本能改系统内的 `ufw`/`firewalld`，但不能替你打开阿里云、甲骨文、AWS、Azure 等网页后台安全组。

3. 修改 SSH 端口前，必须先在云厂商安全组放行新端口，并保留一个未断开的 SSH 会话。脚本有防失联检查，但云平台外层规则仍然需要你自己确认。

4. 使用 443 单入口后，公网 `443` 应只由 Nginx stream 监听。Caddy、3x-ui 面板、REALITY 入站、订阅服务和网站后端默认都应监听 `127.0.0.1`。

5. 执行内核、网络、Docker、防火墙、证书清理、强杀端口等功能前，建议先做 VPS 快照。

<a id="quick-start"></a>
## ⚡ 快速开始

下载并运行主脚本：

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行后会注册全局快捷命令：

```bash
cy
```

以后在服务器终端输入 `cy` 即可进入控制面板。

<a id="recommended-flow"></a>
## 🧭 推荐使用流程

### 🆕 新机器基础流程

```text
1. 运维预检与风险扫描
2. 基础环境初始化
5. SSH 安全加固
6. 添加 SSH 公钥
7. Fail2ban 防爆破
8. 防火墙规则管理
10. 网络与内核优化
15. 服务健康总览
16. 配置备份与回滚
```

建议先跑预检，看系统状态、DNS、公网连通、时间同步、磁盘、内存、包管理器占用和关键命令是否正常。

### 🧱 面板和节点部署流程

```text
1. 运维预检与风险扫描
3. 软件安装与反代分流
4. 面板与节点部署
19. 443 单入口管理中心
15. 服务健康总览
16. 配置备份与回滚
```

如果你准备使用 3x-ui + REALITY + 订阅管理工具，推荐直接走 `19. 443 单入口管理中心`，不要把 Caddy 普通反代、3x-ui SSL、Xray fallback 混在一起。

### 🛠️ 后续维护流程

```text
15. 服务健康总览
13. 端口排查与释放
16. 配置备份与回滚
17. UPD 更新脚本
19. 443 单入口管理中心
```

后续新增网站或订阅管理工具时，优先进入：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
```

不需要重跑首次配置向导。

<a id="features"></a>
## 🧰 功能总览

### 🛡️ 基础环境与安全

- 基础环境初始化：安装 `curl`、`wget`、`git`、`jq`、`sqlite3`、`iproute2` 等常用工具。
- 时区设置：默认设置为 `Asia/Shanghai`。
- 基础 BBR：写入 `net.core.default_qdisc=fq` 和 `net.ipv4.tcp_congestion_control=bbr`。
- SSH 加固：修改 SSH 端口、检查新端口连通、防止直接失联。
- SSH 公钥：追加公钥到 `authorized_keys`。
- Fail2ban：按当前 SSH 端口配置 SSH 爆破防护。
- 防火墙管理：支持查看、放行、删除规则，兼容 `ufw` / `firewalld`。

### 🚀 网络、内核与系统调优

- BBR 增强：调用 `ylx2016` 网络加速脚本。
- 动态 TCP 调优：写入更激进或更稳妥的 TCP 参数。
- ZRAM/SWAP：按内存大小选择压缩策略。
- IPv4/IPv6 优先级：可切换 IPv4 优先，缓解部分 IPv6 环境下载超时。
- Ping、自动更新、垃圾清理等系统开关。
- 内核安装与旧内核清理。

### 📦 软件安装与反代

- Docker 引擎。
- Python 环境。
- iperf3。
- Realm、Gost、WARP、Aria2、哪吒、宝塔、PVE 工具、Argox。
- Caddy 普通反代。
- Caddy 证书查看、跳过后端证书校验、配置清理、ACME 证书清理。
- Nginx Stream + Caddy + REALITY 443 单入口分流。

### 📡 面板与节点

- 3x-ui / x-ui 面板入口。
- Sing-box 甬哥四合一脚本。
- Sing-box 233boy 一键脚本。
- Xray 233boy 一键脚本。
- SublinkPro。
- 妙妙屋订阅管理。
- Sub-Store。
- Dockge。
- DNS 流媒体解锁。
- IP Sentinel。
- Port Traffic Dog。

### 🩺 诊断、备份与维护

- YABS、融合怪、流媒体解锁、回程路由、IP 质量等测试入口。
- 端口占用查看与释放。
- CPU、内存、磁盘、网络实时信息。
- 服务健康总览：服务状态、证书摘要、端口概览。
- 配置备份、列表、恢复与清理。
- 脚本热更新。

<a id="single-443-entry"></a>
## 🧩 443 单入口分流

443 单入口是本项目最重要的进阶功能之一，用来解决多个服务抢公网 `443` 的问题。

典型结构：

```text
公网 443 -> Nginx stream 按 SNI 分流

panel.example.com       -> Caddy -> 3x-ui 面板
sub.example.com         -> Caddy -> SublinkPro / Sub-Store / 其他 HTTP 后端
dockge.example.com      -> Caddy -> Dockge
REALITY 伪装 SNI        -> Xray / 3x-ui REALITY 入站
未知 SNI                -> Xray / 3x-ui REALITY 入站
```

首次配置入口：

```text
19. 443 单入口管理中心
1. 首次配置 443 单入口
```

后续新增或删除网站：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
```

体检和维护：

```text
19. 443 单入口管理中心
3. 443 单入口链路体检
6. CF DNS / Caddy 证书维护
```

核心原则：

- 公网 `443` 只给 Nginx stream。
- Caddy 默认监听 `127.0.0.1:8443`。
- REALITY 默认监听 `127.0.0.1:1443`。
- 3x-ui 面板默认监听 `127.0.0.1:40000`。
- 3x-ui 面板 SSL/HTTPS 应关闭，证书路径和私钥路径留空。
- REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 必须写外部真实 HTTPS 站点，不要写面板域名。

完整教程请看：[443 单入口分流详细教程](docs/443-single-entry.md)。

<a id="node-tools"></a>
## 📡 订阅管理与节点工具

节点和订阅相关入口集中在：

```text
4. 面板与节点部署
```

常用入口：

```text
2. 安装 Sing-box（甬哥四合一脚本）
3. 安装 Sing-box（233boy 一键脚本）
4. 安装 Xray（233boy 一键脚本）
5. 安装 SublinkPro（订阅转换与管理面板）
6. 安装 妙妙屋订阅管理（Docker Compose）
7. 安装 Sub-Store（HTTP-META / Docker Compose）
8. 更新订阅管理工具（SublinkPro / 妙妙屋 / Sub-Store）
9. 安装 Dockge（Docker Compose 管理面板）
10. 迁移 Compose 到 Dockge（Dockge 后安装时接管旧项目）
```

Dockge 如果是后安装的，可以用第 10 项扫描 `/opt` 下已有的 Compose 项目，例如 SublinkPro、妙妙屋、Sub-Store，并移动到 Dockge 的 stacks 目录。迁移时脚本会逐项确认，避免覆盖已有 stack。

233boy 文档：

- Sing-box: <https://233boy.com/sing-box/sing-box-script/>
- Xray: <https://233boy.com/xray/xray-script/>

安装完成后，233boy Sing-box 通常可以用 `sing-box` 或 `sb` 进入管理面板；233boy Xray 通常可以用 `xray` 进入管理面板。

<a id="traffic-dog"></a>
## 📊 端口流量监控

项目包含 `dog.sh`，用于部署 Port Traffic Dog。它基于 `nftables` 和 `tc` 做端口流量统计、限额、限速和 Telegram 查询。

运行方式：

```bash
wget -qO dog.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh && chmod +x dog.sh && ./dog.sh
```

安装后通常可以用：

```bash
dog
```

进入管理菜单。

详细说明请看：[README_dog.md](README_dog.md)。

<a id="high-risk"></a>
## 🛑 高风险功能

这些功能不是不能用，而是使用前要确认上下文：

| 功能 | 风险 | 建议 |
| --- | --- | --- |
| SSH 改端口 | 云安全组未放行会失联 | 先开安全组，保留当前 SSH 会话 |
| 防火墙关闭/删除规则 | 可能暴露服务或阻断连接 | 修改前记录现有规则 |
| 端口强杀 | 可能杀掉 `sshd`、数据库、面板 | 不要强杀 SSH 端口和未知关键服务 |
| Caddy 清空配置 | 可能导致所有反代失效 | 先备份 `/etc/caddy` |
| 删除 ACME 证书 | 可能导致 HTTPS 无法续签或加载 | 确认域名和证书路径 |
| 旧内核清理 | 删除正在运行或云厂商定制内核会无法启动 | 不要删除当前内核和 `cloud` 内核 |
| Docker 本地防穿透 | 会改变 Docker 默认端口绑定行为 | 确认容器是否需要公网直连 |
| 443 单入口 | 会接管公网 `443` | 先确认没有其他服务占用公网 `443` |

<a id="faq"></a>
## ❓ 常见问题

### 🔐 运行脚本提示不是 root

执行：

```bash
sudo -i
```

再重新运行脚本。

### 🔌 修改 SSH 端口后连不上

优先检查云厂商安全组是否放行了新端口。其次从当前未断开的 SSH 会话里检查：

```bash
ss -lntp | grep ssh
systemctl status ssh --no-pager
systemctl status sshd --no-pager
```

不同发行版 SSH 服务名可能是 `ssh` 或 `sshd`。

### 🧩 443 单入口配置后面板打不开

检查这些点：

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
https://panel.example.com/
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

<a id="update-uninstall"></a>
## 🔄 更新与卸载

### ⬆️ 更新

在主菜单选择：

```text
17. UPD 更新脚本
```

脚本会从 GitHub 拉取最新 `vps.sh`，先执行 `bash -n` 语法检查，通过后覆盖 `/usr/local/bin/cy` 并重新进入面板。

### 🧪 手动更新

```bash
wget -qO /usr/local/bin/cy https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh
chmod +x /usr/local/bin/cy
cy
```

### 🧹 卸载快捷命令

只删除快捷入口：

```bash
rm -f /usr/local/bin/cy
```

这不会自动恢复脚本已经修改过的系统配置。系统服务、Nginx/Caddy 配置、防火墙规则、Docker 配置、证书和内核参数需要按实际情况单独回滚，建议优先使用脚本内的备份与回滚功能。

<a id="feedback"></a>
## 💬 反馈与联系

如有 Bug 或建议，欢迎前往 GitHub 提交 Issue，也可以通过作者 GitHub 主页展示的邮箱联系。

## 📜 开源协议

本项目使用 [MIT License](LICENSE)。
