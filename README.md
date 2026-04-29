# 🚀 VPS-Optimize

一个面向 VPS 日常运维、网络调优、安全加固、面板部署和 443 单入口分流的 Bash 控制面板。

常见操作都集中在 `cy` 面板里：新机器初始化、SSH 加固、Docker 管理、Caddy 反代、443 单入口、订阅管理工具、测速诊断、备份回滚。适合有一定 Linux/VPS 基础、希望少记命令但保留可控性的用户。

> 脚本会修改系统服务、防火墙、内核参数、Nginx/Caddy 配置和 Docker 配置。动 SSH、防火墙、内核、证书、443 单入口前，请先做快照并保留当前 SSH 会话。

## 📚 目录

- [⚡ 快速开始](#quick-start)
- [🎯 适用场景](#scenarios)
- [⚠️ 使用前必读](#before-you-start)
- [🧭 推荐使用流程](#recommended-flow)
- [🧭 菜单速查](#menu-guide)
- [🖥️ 面板预览](#preview)
- [🧰 功能总览](#features)
- [🧩 443 单入口分流](#single-443-entry)
- [📡 订阅管理与节点工具](#node-tools)
- [📊 端口流量监控](#traffic-dog)
- [🛑 高风险功能](#high-risk)
- [❓ 常见问题](#faq)
- [🔄 更新与卸载](#update-uninstall)
- [💬 反馈与联系](#feedback)

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

<a id="scenarios"></a>
## 🎯 适用场景

- 新买 VPS 后快速完成基础初始化、时区、基础工具和 BBR。
- 管理 SSH 端口、防火墙、Fail2ban、SSH 公钥等基础安全项。
- 部署 Docker、Python、Caddy、WARP、哪吒、宝塔、Sing-box、Xray、3x-ui、S-UI 等常见组件。
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
3. 基础组件与反代分流
4. 面板、节点与订阅工具
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

<a id="menu-guide"></a>
## 🧭 菜单速查

| 你想做什么 | 推荐入口 | 说明 |
| --- | --- | --- |
| 新机器先体检 | `1` | 部署前看系统、端口、DNS、磁盘、内存和关键命令 |
| 新机器基础初始化 | `2` | 装常用工具、设置时区、开启基础 BBR |
| 改 SSH 端口 | `5` | 改前先在云厂商安全组放行新端口 |
| 管理防火墙端口 | `8` | 放行、删除、查看、关闭系统防火墙规则 |
| 安装 Docker/Caddy/WARP | `3` | 偏基础组件、普通 Caddy 反代和 443 单入口入口 |
| 安装 3x-ui/S-UI/Sing-box/订阅工具 | `4` | 偏面板、节点、订阅管理工具和 Dockge |
| 部署 3x-ui + REALITY + 443 | `19 -> 1` | 首次配置 443 单入口 |
| 后续新增网站或反代域名 | `19 -> 2` | 不需要重跑首次配置 |
| 443/证书/面板打不开 | `19 -> 3` 或 `19 -> 6` | 先体检链路，再进证书维护 |
| 查看服务是否正常 | `15` | 服务状态、证书摘要、监听端口概览 |
| 备份或回滚配置 | `16` | 重要操作前建议先备份 |
| 端口占用排查 | `13` | 查看占用并按需释放端口 |
| 更新脚本 | `17` | 从 GitHub 拉取最新 `vps.sh` |

<a id="preview"></a>
## 🖥️ 面板预览

![VPS-Optimize 面板预览](https://i.mji.rip/2026/04/28/ed5bf23f4ebf88300819ff3520bac2df.png)

<a id="features"></a>
## 🧰 功能总览

### 🛡️ 基础环境与安全

- 基础环境初始化：常用工具、时区、基础 BBR。
- SSH 安全：改端口、防失联检查、公钥登录、Fail2ban。
- 防火墙管理：查看、放行、删除规则，兼容 `ufw` / `firewalld`。

### 🚀 网络、内核与系统调优

- BBR 增强、动态 TCP 参数、ZRAM/SWAP。
- IPv4/IPv6 优先级、Ping、自动更新、垃圾清理。
- 优化内核安装与旧内核清理。

### 📦 软件安装与反代

- Docker、Python、iperf3、Realm、Gost、WARP、Aria2、哪吒、宝塔、PVE 工具、Argox。
- 普通 Caddy 反代、证书查看、跳过后端证书校验、配置清理、ACME 证书清理。
- Nginx Stream + Caddy + REALITY 443 单入口分流。

### 📡 面板与节点

- 3x-ui / x-ui、S-UI、Sing-box、Xray。
- SublinkPro、妙妙屋订阅管理、Sub-Store、Dockge。
- DNS 流媒体解锁、IP Sentinel、Port Traffic Dog。

### 🩺 诊断、备份与维护

- YABS、融合怪、流媒体解锁、回程路由、IP 质量测试。
- 端口占用查看与释放、系统硬件探针、服务健康总览。
- 配置备份、列表、恢复、清理和脚本热更新。

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
9. 更新订阅管理工具（SublinkPro / 妙妙屋 / Sub-Store）
10. 迁移 Compose 到 Dockge（Dockge 后安装时接管旧项目）
11. 面板救砖 / 重置 SSL
12. DNS 流媒体解锁
13. 防 IP 送中脚本
14. 端口流量监控
```

每个“管理”入口点进去后，再选择安装、进入官方菜单、更新、停止或卸载。Dockge 如果是后安装的，可以用第 10 项扫描 `/opt` 下已有的 Compose 项目，例如 SublinkPro、妙妙屋、Sub-Store，并移动到 Dockge 的 stacks 目录。迁移时脚本会逐项确认，避免覆盖已有 stack。

Docker Compose 部署的项目现在都有独立的“管理 / 卸载”入口。普通停止会保留部署目录和数据；删除部署目录需要输入 `DELETE` 二次确认，避免误删配置和数据库。

### 🌐 部署完节点工具后接入 Caddy 反代

Caddy 主要用来反代 HTTP 面板和订阅管理工具，例如 3x-ui 面板、SublinkPro、妙妙屋、Sub-Store、Dockge。Sing-box、Xray、REALITY 等节点入站端口不是普通 HTTP 服务，通常不要直接用 Caddy 反代。

推荐做法是走 443 单入口：

```text
19. 443 单入口管理中心
2. 管理网站/反代域名
```

按提示新增一个反代域名，填写：

```text
网站/反代域名：sub.example.com
后端监听地址：127.0.0.1
后端监听端口：8000
后端协议：http
```

常见后端端口参考：

```text
3x-ui 面板       -> 127.0.0.1:40000
SublinkPro       -> 127.0.0.1:8000
妙妙屋订阅管理   -> 127.0.0.1:8080
Sub-Store        -> 127.0.0.1:3001 或安装时填写的后端端口
Dockge           -> 127.0.0.1:5001
```

如果没有使用 443 单入口，只想做普通 Caddy 反代，可以进入：

```text
3. 基础组件与反代分流
13. 普通 Caddy 反代
```

普通反代会让 Caddy 直接接管公网 `80/443`。如果已经启用了 443 单入口，就不要再用普通 Caddy 反代新增站点，应统一从 `19 -> 2` 添加。

反代前请先确认：

```text
1. 域名 A/AAAA 记录已经解析到当前 VPS。
2. 云厂商安全组已经放行 80 和 443。
3. 后端服务能在本机访问，例如 curl http://127.0.0.1:8000。
4. 管理面板类服务建议只监听 127.0.0.1，再通过 Caddy 暴露 HTTPS 域名。
```

配置完成后，用浏览器访问：

```text
https://sub.example.com/
```

如果打不开，优先进入：

```text
19. 443 单入口管理中心
3. 443 单入口链路体检
```

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


操作前先确认：

- VPS 已有快照、备份或救援控制台。
- 当前 SSH 会话不要断开，尤其是修改 SSH、防火墙、网络和内核时。
- 云厂商安全组已经放行新 SSH 端口、`80`、`443` 或业务端口。
- 你知道当前 `80/443` 由谁监听：`ss -lntp | grep -E ':80|:443'`。
- 重要配置建议先备份：`/etc/ssh`、`/etc/caddy`、`/etc/nginx`、`/etc/vps-optimize`。

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
