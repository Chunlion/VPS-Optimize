# 🚀 VPS-Optimize

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/github/license/Chunlion/VPS-Optimize)
![Release](https://img.shields.io/github/v/release/Chunlion/VPS-Optimize?display_name=tag&sort=semver)
![Stars](https://img.shields.io/github/stars/Chunlion/VPS-Optimize?style=social)

一个 `cy` 命令，完成 VPS 初始化、安全加固、面板部署、443 单入口、订阅工具和故障排查。

一个面向 VPS 日常运维的 Bash 控制面板，把新机器预检、系统初始化、安全加固、网络优化、面板部署、订阅工具、备份回滚和 `443` 单入口分流集中到一个 `cy` 命令里。

它适合有一定 Linux/VPS 基础、希望少记命令但仍保留可控性的用户。第一次部署建议按 README 的推荐流程走；后续维护通常只需要进入 `cy` 面板选择对应入口。

> ⚠️ 脚本会修改系统服务、防火墙、内核参数、Nginx/Caddy 配置、Docker 配置和证书文件。动 SSH、防火墙、内核、证书、`443` 单入口前，请先做快照或备份，并保留当前 SSH 会话。

## ✨ 核心能力

| 场景 | 能做什么 |
| --- | --- |
| 新机器初始化 | 预检系统、安装常用工具、设置时区、开启基础 BBR |
| 安全加固 | SSH 加固、公钥登录、Fail2ban、防火墙规则管理 |
| 面板与订阅 | 3x-ui、S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari |
| 网络与诊断 | 内核优化、测速、443 链路测试、流量达量关机、端口排查、服务健康总览 |
| 443 单入口 | 公网只开放 `443`，按 SNI 分流到面板、订阅、网站和 REALITY，并支持按域名设置 IP 白名单 |
| 备份回滚 | 重要配置备份、列表查看、恢复和隔离归档 |

## 📚 目录

- [⚡ 快速开始](#quick-start)
- [🗂️ 文档导航](#docs)
- [🧭 我该选哪个？](#choose-path)
- [✅ 运行前检查清单](#pre-run-checklist)
- [🖥️ 支持系统矩阵](#supported-systems)
- [⚠️ 使用前必读](#before-you-start)
- [🧭 推荐流程](#recommended-flow)
- [📖 场景教程](#tutorials)
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
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

`dist/vps.sh` 是由 `scripts/build.sh` 从 `src/*.sh` 生成的单文件发布版；仓库根目录的 `vps.sh` 是源码入口，用于本地开发和调试。
发布版已经内置全部模块，运行各项功能时不会再按模块拉取脚本；源码入口只适合完整克隆仓库后运行。

首次运行后会注册全局快捷命令，以后直接输入：

```bash
cy
```

面板预览：

![VPS-Optimize 面板预览](https://i.mji.rip/2026/05/02/53aa776a44cef18d91eb29cd7d7883fb.png)

<a id="docs"></a>
## 🗂️ 文档导航

第一次使用建议先看 [INSTALL.md](INSTALL.md)。

| 文档 | 适合情况 |
|---|---|
| [INSTALL.md](INSTALL.md) | 第一次安装，不知道该走哪条路线 |
| [docs/443-tcp-peek-engine.md](docs/443-tcp-peek-engine.md) | 了解 443 单入口技术实现 |
| [docs/existing-server-migration.md](docs/existing-server-migration.md) | 已有 3x-ui、Caddy/Nginx、网站或订阅工具，需要迁移 |
| [docs/recovery-runbook.md](docs/recovery-runbook.md) | SSH 失联、防火墙误封、443 改坏、服务起不来 |
| [docs/compatibility.md](docs/compatibility.md) | 系统、虚拟化、IPv6、Docker 兼容性不确定 |
| [docs/config-paths.md](docs/config-paths.md) | 真正排错时查配置、证书、备份路径 |

<a id="choose-path"></a>
## 🧭 我该选哪个？

第一次使用先从这里选路径。旧用户仍可直接进入完整菜单，菜单编号尽量保持兼容。

| 你的目标 | 推荐路径 |
|---|---|
| 新买 VPS，先安全初始化 | `主菜单 [n 新手向导] -> [1 新机器初始化]`，或看 [tutorials/01-new-vps-hardening.md](tutorials/01-new-vps-hardening.md) |
| 只想部署 3x-ui + REALITY | `主菜单 [1 运维预检与风险扫描] -> [5 面板、节点与订阅工具] -> [19 443 单入口管理中心]` |
| 已有面板，想接入 443 单入口 | 先看 [`docs/443-single-entry.md`](docs/443-single-entry.md)，再跑 `主菜单 [19 443 单入口管理中心] -> [2 首次配置 443 单入口]` |
| 面板打不开 / 订阅 404 / 证书失败 | `主菜单 [19 443 单入口管理中心] -> [11 443 单入口链路体检]`，再看 [`docs/443-single-entry-troubleshooting.md`](docs/443-single-entry-troubleshooting.md) |
| 只想看流量统计 | 单独运行 `dog.sh` 或进入 `主菜单 [5 面板、节点与订阅工具] -> [14 端口流量监控]` |

<a id="pre-run-checklist"></a>
## ✅ 运行前检查清单

- [ ] 已创建 VPS 快照
- [ ] 当前 SSH 会话保持不断开
- [ ] 云厂商安全组已放行 SSH 端口
- [ ] 域名 DNS 已解析到当前 VPS
- [ ] 如使用 Cloudflare，相关域名为 DNS only / 灰云
- [ ] 已准备 Cloudflare API Token
- [ ] 已确认服务器系统版本在支持范围内

<a id="supported-systems"></a>
## 🖥️ 支持系统矩阵

| 系统 | 支持状态 | 备注 |
|---|---|---|
| Debian 11/12 | 推荐 | 最稳 |
| Ubuntu 20.04/22.04/24.04 | 推荐 | 最稳 |
| Rocky/Alma/CentOS Stream | 可用 | 部分组件依赖源 |
| Alpine | 不支持 | 不建议运行 |
| OpenVZ 老系统 | 不建议 | 内核功能可能缺失 |

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
| 新机器基础初始化 | `主菜单 [1 运维预检与风险扫描]` → `[2 基础环境初始化]` → `[6 SSH 安全中心]` → `[7 Fail2ban 防爆破]` → `[8 防火墙规则管理]` → `[10 网络与内核优化]` → `[15 服务健康总览]` → `[16 配置备份与回滚]` |
| 部署面板、节点和订阅工具 | `主菜单 [1 运维预检与风险扫描]` → `[3 基础组件与常用服务]` → `[5 面板、节点与订阅工具]` → `[19 443 单入口管理中心]` → `[15 服务健康总览]` → `[16 配置备份与回滚]` |
| 后续维护 | `主菜单 [15 服务健康总览]` → `[13 端口排查与释放]` → `[10 网络与内核优化] -> [7 流量达量关机保护]` → `[16 配置备份与回滚]` → `[17 更新脚本]` → `[19 443 单入口管理中心]` |
| 新增网站或反代域名 | `主菜单 [19 443 单入口管理中心] -> [8 管理网站/反代域名]` |

<a id="tutorials"></a>
## 📖 场景教程

| 场景 | 教程 |
|---|---|
| 新 VPS 先做初始化和安全加固 | [01-new-vps-hardening.md](tutorials/01-new-vps-hardening.md) |
| 部署 3x-ui + REALITY 并接入 443 | [02-3x-ui-reality-443.md](tutorials/02-3x-ui-reality-443.md) |
| 用 Caddy 接入订阅工具 | [03-subscription-tools-with-caddy.md](tutorials/03-subscription-tools-with-caddy.md) |
| 已有服务器迁移到 443 单入口 | [existing-server-migration.md](docs/existing-server-migration.md) |
| 失联、回滚和急救 | [recovery-runbook.md](docs/recovery-runbook.md) |

<a id="features"></a>
## 🧰 功能地图

主菜单按使用频率分组。新机器先从 `1` 开始，普通 Caddy 反代进 `4`，面板和节点进 `5`，所有 443 相关操作进 `19`。

| 你想做什么 | 入口 | 说明 |
| --- | --- | --- |
| 新机器先体检 | `主菜单 [1 运维预检与风险扫描]` | 看系统、端口、DNS、磁盘、内存和关键命令 |
| 做基础初始化 | `主菜单 [2 基础环境初始化]` | 安装常用工具、设置时区、系统更新、基础 BBR |
| 安装 Docker/Python/WARP | `主菜单 [3 基础组件与常用服务]` | 基础组件、转发隧道和常用服务 |
| 普通 Caddy 反代 | `主菜单 [4 普通 Caddy 反代]` | 未接入 443 单入口的普通网站/面板反代 |
| 安装面板、节点、订阅工具 | `主菜单 [5 面板、节点与订阅工具]` | 3x-ui、S-UI、Sing-box、Xray、订阅管理、Dockge、Komari |
| 改 SSH 端口 | `主菜单 [6 SSH 安全中心] -> [1 修改 SSH 端口]` | 改前先放行云厂商安全组新端口；会同步 `sshd_config.d` 与已启用的 `ssh.socket/sshd.socket` |
| 管理 SSH 密钥登录 | `主菜单 [6 SSH 安全中心] -> [2 用户密钥登录模式]` | 添加用户公钥、切换密钥优先或仅密钥登录；会同步 `sshd_config.d`，并处理 `50-cloud-init.conf` 等云镜像限制 |
| 管理防火墙端口 | `主菜单 [8 防火墙规则管理]` | 放行、删除、查看、关闭系统防火墙规则 |
| 修改主机名 | `主菜单 [9 系统开关与清理] -> [6 修改主机名]` | 修改运行时主机名，并同步 `/etc/hostname` 和 `/etc/hosts` |
| 修改本机 hosts | `主菜单 [9 系统开关与清理] -> [7 本机 hosts 解析管理]` | 修改当前 VPS 的 `/etc/hosts` 本机解析，自动备份 |
| DNS 更改优化 | `主菜单 [10 网络与内核优化] -> [6 DNS 更改优化]` | 国内/国外默认 DNS，也可自定义 IPv4 和 IPv6 DNS |
| 网络与内核优化 | `主菜单 [10 网络与内核优化]` | BBR/TCP/ZRAM/轻量内核 |
| 防止流量超额账单 | `主菜单 [10 网络与内核优化] -> [7 流量达量关机保护]` | 自动推荐活跃网卡，按账单周期和阈值自动关机，也支持只写日志测试 |
| 管理网卡 | `主菜单 [10 网络与内核优化] -> [8 网卡管理工具]` | 查看网卡、路由、DNS、MTU，必要时刷新 DHCP |
| 测速和质量检测 | `主菜单 [12 测速与质量检测]` | YABS、流媒体、回程、IP 质量，以及 443 面板/订阅链路测试 |
| 排查端口占用 | `主菜单 [13 端口排查与释放]` | 查看监听端口，必要时释放端口 |
| 查看服务是否正常 | `主菜单 [15 服务健康总览]` | 服务状态、证书摘要、监听端口概览、443/Caddy/3x-ui/订阅工具场景概览 |
| 备份或回滚配置 | `主菜单 [16 配置备份与回滚]` | 重要操作前建议先备份 |
| 更新脚本 | `主菜单 [17 更新脚本]` | 从 GitHub 拉取最新发布版；主菜单会缓存式自动检查更新 |
| 部署 3x-ui + REALITY + 443 | `主菜单 [19 443 单入口管理中心] -> [2 首次配置 443 单入口]` | 首次配置 443 单入口 |
| 后续新增网站或反代域名 | `主菜单 [19 443 单入口管理中心] -> [8 管理网站/反代域名]` | 不需要重跑首次配置 |
| 限制面板域名访问 IP | `主菜单 [19 443 单入口管理中心] -> [9 管理域名 IP 白名单]` | 只限制被选择的域名，不影响其他 SNI |
| 普通 Caddy 域名访问 IP 限制 | `主菜单 [4 普通 Caddy 反代] -> [4 普通 Caddy 域名 IP 白名单]` | 未启用 443 单入口时使用 |
| 443/证书/面板打不开 | `主菜单 [19 443 单入口管理中心] -> [11 443 单入口链路体检]` 或 `[13 CF DNS / Caddy 证书维护]` | 先体检链路，再进证书维护 |
| 检查容器是否绕过 443 | `主菜单 [11 Docker 安全管理] -> [4 Docker 端口暴露审计]` | 查看订阅工具/Dockge/Komari 是否直接暴露公网端口 |

<a id="shortcuts"></a>
## ⌨️ 快捷输入

主面板除了数字，也支持常用快捷词：

| 输入 | 入口 |
| --- | --- |
| `443` / `sni` | 443 单入口管理中心 |
| `caddy` / `反代` | 普通 Caddy 反代 |
| `h` / `health` | 服务健康总览 |
| `b` / `backup` | 配置备份与回滚 |
| `u` / `update` | 更新脚本 |
| `traffic` / `quota` / `流量` | 网络与内核优化菜单，再选 `[7 流量达量关机保护]` |
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

### 示例说明

本文中出现的域名、路径和端口都只是示例，方便理解架构，不是必须照抄的固定值。

例如：

- `panel.example.com` = 示例面板域名
- `node.example.com` = 示例节点域名
- `site.example.com` = 示例网站域名
- `40000` = 示例 3x-ui 面板端口
- `2096` = 示例订阅端口
- `8443` = 示例 Caddy 本地 HTTPS 端口
- `1443` = 示例 Xray/REALITY 本地端口

实际部署时，请替换成你自己的域名、路径和端口。如果你已经在脚本里填写过端口，以脚本保存的配置为准，不要盲目照抄文档示例。

| 项目 | 文档示例 | 你的实际值 |
|---|---|---|
| 面板域名 | panel.example.com | 请改成你自己的 |
| 节点域名 | node.example.com | 请改成你自己的 |
| 网站域名 | site.example.com | 请改成你自己的 |
| 3x-ui 面板端口 | 40000 | 以你面板实际端口为准 |
| 订阅端口 | 2096 | 以你订阅服务实际端口为准 |
| Caddy 本地端口 | 8443 | 以脚本当前配置为准 |
| Xray/REALITY 本地端口 | 1443 | 以脚本当前配置为准 |
| 面板路径 | /panel/ | 以你面板设置为准 |
| 普通订阅路径 | /sub/ | 以你订阅设置为准 |
| Clash/Mihomo 路径 | /clash/ | 以你订阅设置为准 |

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
- 3x-ui 安装阶段选择证书只是临时完成安装流程；接入 443 单入口前，应清空 3x-ui 面板和订阅证书路径，让 Caddy 接管公网 HTTPS。
- REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 必须写外部真实 HTTPS 站点，不要写面板域名。

TCP Peek + Splice 模式：基于 MSG_PEEK 读取 TLS ClientHello 中的 SNI，不消费首包，并根据 SNI 将连接分流到 Caddy 或 Xray 本地后端；转发时优先使用 splice 零拷贝，失败时自动回退普通 copy。实际运行的分流器程序为 vpso-mux。

Xray 入站管理只记录 `SNI -> 本地地址:端口`，不是 3x-ui 入站编辑器。用户需要先在 3x-ui 中创建并启用本地入站，再把 SNI 分流记录写入脚本。Nginx Stream 模式和 TCP Peek + Splice 模式支持多个 Xray 本地入站分流。Xray 本身可以有多个入站。但在 xray-fallback 模式下，公网 `443` 默认由一个 Xray 主入站接管。脚本暂不支持在该模式下继续按多个 SNI 分流到多个本地 Xray 入站。如需多个本地 Xray 入站分流，请使用 Nginx Stream 模式或 TCP Peek + Splice 模式。

3x-ui 具体怎么填请看 [443 单入口分流详细教程](docs/443-single-entry.md) 里的“三种入口模式配置速查”。简要原则：Nginx Stream 和 TCP Peek 模式下，3x-ui 面板、订阅和 Xray 入站都应监听本机端口；Xray Fallback 模式下，只有一个 Xray 主入站监听公网 `443`，并由它 fallback 到 Caddy 本地端口。切回 Nginx Stream 或 TCP Peek 前，必须先把这个 Xray 主入站从公网 `443` 移走。

普通 TLS 节点和 REALITY 节点不要混在一起判断：普通 TLS 更关注本机证书、Caddy fallback、Host/SNI 是否匹配；REALITY 更关注外部目标站点是否真实可访问、TLS 特征是否稳定。不要求 REALITY `serverName` 加入 Caddy，也不要求本机证书覆盖 REALITY `serverName`。

证书策略保持简单固定：继续使用 `acme.sh + Cloudflare DNS API`，不使用 Caddy DNS 模块，也不需要 `xcaddy`。

如果机器上已经有普通 Caddy 反代，启用 443 单入口前请先备份并记录旧站点的域名、后端地址和端口。脚本会隔离可能抢占公网 `443` 的旧 Caddy 配置，但不会自动把旧反代规则迁移成新的 443 单入口站点；启用后需要通过 `主菜单 [19 443 单入口管理中心] -> [8 管理网站/反代域名]` 手动补录旧网站。

面板域名或某个站点域名需要只允许固定 IP 访问时，用 `主菜单 [19 443 单入口管理中心] -> [9 管理域名 IP 白名单]`。白名单按 Web 域名单独保存，只会影响被选择的 Caddy/Web SNI，不会收紧 Xray 入站、REALITY 或默认分流。设置时脚本会自动尝试把 VPS 本机公网 IP 一并加入。

需要验证访问是否打通时，用 `主菜单 [19 443 单入口管理中心] -> [12 443 网络访问测试]`。它会检查 DNS、TCP、TLS SNI、面板路径、普通订阅路径和 Clash/Mihomo 路径，适合排查“面板打不开、订阅 404、REALITY 端口混乱”等问题。

第一次配置建议看完整教程；出错再看排错版。

| 文档 | 适合情况 |
|---|---|
| [443 单入口排错手册](docs/443-single-entry-troubleshooting.md) | 面板打不开、订阅 404、证书失败、REALITY 连不上 |
| [443 单入口分流详细教程](docs/443-single-entry.md) | 需要理解 Nginx stream、Caddy、REALITY 和 3x-ui 的关系 |

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

SublinkPro、妙妙屋、Sub-Store、Dockge、Komari 都按“本地监听 + Caddy/443 对外”的思路管理。新部署的订阅工具默认优先绑定 `127.0.0.1`，公网 HTTPS 访问建议通过 `主菜单 [19 443 单入口管理中心] -> [8 管理网站/反代域名]` 添加域名；如果担心旧容器绕过 443 暴露端口，可进入 `主菜单 [11 Docker 安全管理] -> [4 Docker 端口暴露审计]` 检查。

面板/订阅工具账号提示：

- 3x-ui / x-ui 和 S-UI 使用官方安装器，管理员账号、密码和面板路径由官方安装器交互设置或在安装结束时输出，请留意并保存。
- SublinkPro 安装流程暂不提供自定义后台账号密码，默认账号 `admin`，默认密码 `123456`，安装后请尽快修改。
- 妙妙屋订阅管理不预设默认账号密码，首次打开页面时创建管理员账号。
- Sub-Store 当前部署不使用登录账号密码，默认通过本地监听和随机后端路径降低暴露面；公网访问建议再加反代认证。
- Dockge 不预设默认账号密码，首次打开页面时创建管理员账号。
- Komari 安装时可选择自定义初始管理员账号和密码；不自定义时安装后查看容器日志获取默认管理员账号。

Komari 默认部署到 `/opt/komari`，数据保存在 `/opt/komari/data`。安装时可选择自定义初始管理员账号和密码；如果不自定义，安装完成后可查看容器日志获取默认管理员账号。如需 HTTPS 访问，未启用 443 单入口时可用 `主菜单 [4 普通 Caddy 反代] -> [1 添加普通 Caddy 反代]`；已启用 443 单入口时再用 `主菜单 [19 443 单入口管理中心] -> [8 管理网站/反代域名]` 添加反代域名。

<a id="standalone-tools"></a>
## 🧩 独立工具

仓库里除了源码入口 `vps.sh` 和发布版 `dist/vps.sh`，还包含两个可以单独运行的维护工具。

### 3x-ui 外置增强管理

项目包含 `xui-custom-manager.sh`，用于补充 3x-ui / x-ui 面板外更适合脚本处理的维护功能：自定义重置日期、流量校准、备份恢复、健康检查、查看日志和清理旧备份。

入口：

```text
主菜单 [5 面板、节点与订阅工具] -> [16 3x-ui 外置增强管理]
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

### 流量达量关机保护

如果 VPS 套餐有月流量限制，建议进入 `主菜单 [10 网络与内核优化] -> [7 流量达量关机保护]` 配置保护。它会安装本地 `systemd timer`，按网卡统计本周期流量，达到阈值后自动关机，避免被刷流量后产生超额账单。

支持的口径包括出站 TX、入站 RX、出入总量、任一方向达量；会自动推荐活跃网卡，并按当前网卡计数估算本周期已用流量。账单重置日支持 `1-31`，遇到 2 月或小月会自动按当月最后一天处理。统计基于系统网卡计数，不需要 `vnstat`；如果需要跨重装、跨历史周期的云厂商账单口径，请以云后台为准手动覆盖已用值，阈值建议低于套餐上限。

<a id="safety"></a>
## 🛡️ 安全与回滚

高风险功能会要求输入 `YES`。不确定时先做 `主菜单 [16 配置备份与回滚]`。

手动备份会尽量覆盖 SSH、主机名、Nginx/Caddy、443 单入口、DNS、证书、Cloudflare Token、Docker、Fail2ban、sysctl 和 3x-ui 关键配置。备份文件保存在 root 权限目录下，但其中可能包含私钥、面板数据库和 API Token，不要公开分享。

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
/etc/vps-optimize/quarantine/dns
/etc/vps-optimize/quarantine/manual-backups
/etc/vps-optimize/quarantine/manual-restore
/etc/vps-optimize/quarantine/manual-temp
/root/port-traffic-dog-quarantine
```

确认隔离内容无用后，再手动清理对应目录。

高风险操作建议：

| 功能 | 风险 | 建议 |
| --- | --- | --- |
| SSH 改端口 | 云安全组未放行会失联 | 先开安全组，保留当前 SSH 会话 |
| 仅密钥登录 | 未确认私钥可用会失联 | 先添加公钥并新开 SSH 窗口测试成功 |
| 防火墙关闭/删除规则 | 可能暴露服务或阻断连接 | 修改前记录现有规则 |
| 本机 hosts 修改 | 可能让本机解析到错误 IP | 使用菜单自动备份，必要时恢复最近备份 |
| DNS 更改优化 | DNS 不可达会导致域名解析失败 | 先确认 IPv4/IPv6 连通性，必要时恢复最近一次 DNS 备份 |
| 网卡关闭/DHCP 刷新 | 可能中断当前 SSH | 不要关闭默认公网网卡，必要时使用云控制台恢复 |
| 端口强杀 | 可能杀掉 `sshd`、数据库、面板 | 不要强杀 SSH 端口和未知关键服务 |
| Caddy 配置重置 | 可能导致反代暂时失效 | 先备份 `/etc/caddy` |
| 证书缓存隔离 | 可能需要重新签发 HTTPS 证书 | 确认域名和证书路径 |
| 旧内核清理 | 误删云厂商定制内核会影响启动 | 不要删除当前内核和 `cloud` 内核 |
| Docker 本地防穿透 | 会改变 Docker 默认端口绑定行为 | 确认容器是否需要公网直连 |
| 443 单入口 | 会接管公网 `443` | 先确认没有其他服务占用公网 `443`，失败时优先用脚本生成的 SNI stack 备份回滚 |
| 流量达量关机 | 达到阈值会执行系统关机 | 阈值留安全余量，先用“只写日志”测试，再启用关机动作 |

<a id="update-uninstall"></a>
## 🔄 更新与卸载

更新主脚本：

```text
17. 更新脚本  快捷词：u / update / upd
```

推荐通过 `cy -> [17 更新脚本]` 更新主脚本。主菜单会缓存式自动检查发布版更新；发现新版本时会在顶部提示，输入 `u` 即可热更新到 `dist/vps.sh`。自动检查只读远程版本号，不会自动覆盖脚本。更新逻辑会先执行 `bash -n`，再下载 `dist/vps.sh.sha256` 并执行 `sha256sum -c` 校验；校验失败不会覆盖 `/usr/local/bin/cy`。

手动更新：

```bash
tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh)
wget -qO "$tmp_file" https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh
bash -n "$tmp_file"
install -m 755 "$tmp_file" /usr/local/bin/cy
rm -f "$tmp_file"
cy
```

手动覆盖前至少执行 `bash -n "$tmp_file"`；如需对齐内置更新流程，也可以同时下载 `dist/vps.sh.sha256` 后用 `sha256sum -c` 校验。

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
- 3x-ui 面板和订阅证书路径是否已清空，让 Caddy 接管公网 HTTPS。
- Caddy 是否监听 `127.0.0.1:8443`。
- Nginx stream 是否监听公网 `0.0.0.0:443`。
- 云安全组是否放行 `443`。
- 面板域名 DNS 是否解析到当前服务器。

详细排错请看：[443 单入口排错手册](docs/443-single-entry-troubleshooting.md)。需要从头配置时先看：[443 单入口分流详细教程](docs/443-single-entry.md)。

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
curl -I https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh
```

如果你的环境访问 GitHub 不稳定，可以先解决 DNS、IPv4/IPv6 优先级或代理出口问题。

<a id="feedback"></a>
## 💬 反馈与联系

如有 Bug 或建议，欢迎前往 [GitHub Issues](https://github.com/Chunlion/VPS-Optimize/issues) 提交反馈。

也可以通过作者 [GitHub 主页](https://github.com/Chunlion) 展示的联系方式或邮箱联系。

## 📜 开源协议

本项目使用 [MIT License](LICENSE)。
