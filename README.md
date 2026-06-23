# 🚀 VPS-Optimize

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/Release-latest-blue.svg)](https://github.com/Chunlion/VPS-Optimize/releases/latest)
![Stars](https://img.shields.io/github/stars/Chunlion/VPS-Optimize?style=social)

一个 `cy` 命令，完成 VPS 初始化、安全加固、面板部署、443 单入口、订阅工具和故障排查。

一个面向 VPS 日常运维的 Bash 控制面板，把新机器预检、系统初始化、安全加固、网络优化、面板部署、订阅工具、备份回滚和 `443` 单入口分流集中到一个 `cy` 命令里。

它适合有一定 Linux/VPS 基础、希望少记命令但仍保留可控性的用户。后续维护通常只需要进入 `cy` 面板选择对应入口。

> ⚠️ 脚本会修改系统服务、防火墙、内核参数、Nginx/Caddy 配置、Docker 配置和证书文件。动 SSH、防火墙、内核、证书、`443` 单入口前，请先做快照或备份，并保留当前 SSH 会话。

## ✨ 核心能力

| 场景 | 能做什么 |
| --- | --- |
| 新机器初始化 | 预检系统、安装常用工具、设置时区、开启基础 BBR |
| 安全加固 | SSH 加固、公钥登录、Fail2ban、防火墙规则管理和端口并发连接限制 |
| 面板与订阅 | 3x-ui、S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari |
| 网络与诊断 | 内核优化、测速、443 链路测试、流量达量关机、端口排查、服务健康总览 |
| 443 单入口 | Web / 节点入口统一走公网 `443`，按 SNI 分流到面板、订阅、网站和 REALITY，并支持按域名设置 IP 白名单 |
| 备份回滚 | 重要配置备份、列表查看、恢复、隔离归档，以及脚本已应用配置的安全查看/编辑 |

## 📚 目录

- [⚡ 快速开始](#quick-start)
- [🗂️ 文档导航](#docs)
- [✅ 运行前检查清单](#pre-run-checklist)
- [🖥️ 支持系统矩阵](#supported-systems)
- [⚠️ 使用前必读](#before-you-start)
- [📖 场景教程](#tutorials)
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

在服务器上使用 `root` 运行。

国内：

```bash
wget -qO vps.sh https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

国外：

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行后会注册全局快捷命令，以后直接输入：

```bash
cy
```

面板预览：

![VPS-Optimize 面板预览](https://i.mji.rip/2026/06/03/50e5eac2e83fbf7ef15240e3fa8c693a.png)

<a id="docs"></a>
## 🗂️ 文档导航

| 文档 | 适合情况 |
|---|---|
| [docs/443-single-entry.md](docs/443-single-entry.md) | 443 单入口主教程 |
| [docs/443-tcp-peek-engine.md](docs/443-tcp-peek-engine.md) | 了解 443 单入口技术实现 |
| [docs/443-single-entry-troubleshooting.md](docs/443-single-entry-troubleshooting.md) | 面板、证书、订阅或节点访问异常 |
| [docs/existing-server-migration.md](docs/existing-server-migration.md) | 已有 3x-ui、Caddy/Nginx、网站或订阅工具，需要迁移 |
| [docs/recovery-runbook.md](docs/recovery-runbook.md) | SSH 失联、防火墙误封、443 改坏、服务起不来 |
| [docs/config-paths.md](docs/config-paths.md) | 真正排错时查配置、证书、备份路径 |
| [docs/dog.md](docs/dog.md) | 端口流量狗 dog.sh 使用说明 |
| [docs/xui-custom-manager.md](docs/xui-custom-manager.md) | x-ui 增强套件说明 |

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

2. 云厂商安全组和系统防火墙是两层东西。脚本能管理系统里的 `ufw` / `firewalld`，但不能替你打开阿里云、甲骨文、AWS、Azure 等网页后台安全组。`主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制]` 会额外写入 `iptables` / `ip6tables` connlimit 规则，用于按公网端口限制每来源 IP 的 TCP 并发连接数；它不是 UFW/firewalld 端口放行规则。添加或删除 connlimit 规则后，脚本会自动尝试刷新持久化快照；`主菜单 [8 防火墙规则管理] -> [6 端口并发连接限制] -> [5 保存/检查重启持久化]` 用于查看状态或失败后重试。Debian/Ubuntu 优先使用已有 `netfilter-persistent` / `iptables-persistent`；RHEL/Rocky/Alma/CentOS Stream 只在检测到已有 `iptables-services` 路径（如 `iptables.service` 或 `/etc/sysconfig/iptables`）时写入。未检测到可靠持久化能力或保存失败时，脚本会明确提示当前规则只在本次运行期生效。

3. 修改 SSH 端口前，先在云厂商安全组放行新端口，并保留一个未断开的 SSH 会话。

4. 启用 443 单入口后，公网 `443` 只应由当前入口模式对应的单个服务监听：`nginx-stream` 对应 `nginx`，`xray-fallback` 对应 Xray 主入站，`tcp-peek` 对应 `tcppeek` / `vpso-mux`。除 `xray-fallback` 下用户准备的 Xray 主入站外，Caddy、3x-ui 面板、订阅服务、网站后端和额外本地 Xray 入站默认都应监听 `127.0.0.1`。如果对公网 `443` 做端口并发连接限制，它只能限制整个 `443` 入口，不能精准限制某个 Xray/3x-ui 入站、某个 SNI、UUID 或用户。

5. 不建议在没有快照、备份或救援控制台的生产机器上直接运行高风险功能。

<a id="tutorials"></a>
## 📖 场景教程

| 场景 | 教程 |
|---|---|
| 部署 3x-ui + REALITY 并接入 443 | [01-3x-ui-reality-443.md](tutorials/01-3x-ui-reality-443.md) |
| 用 Caddy/Nginx 反代或 443 单入口接入订阅工具 | [02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md](tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md) |
| 已有服务器迁移到 443 单入口 | [existing-server-migration.md](docs/existing-server-migration.md) |
| 失联、回滚和急救 | [recovery-runbook.md](docs/recovery-runbook.md) |

<a id="shortcuts"></a>
## ⌨️ 快捷输入

主面板支持常用快捷词：`443` / `sni` 进入 443 单入口，`caddy` / `nginx` 进入反代，`h` 看健康总览，`b` 做备份，`u` 更新脚本，`q` 退出。

`dog` 面板常用快捷词：`add`、`limit`、`tg`、`report`、`u`、`q`。

基础组件入口：`主菜单 [3 基础组件与常用服务]`，包含 Forwardx 转发面板和 nftables NAT 转发。

<a id="single-443-entry"></a>
## 🧩 443 单入口分流

443 单入口用于解决多个服务争抢公网 `443` 的问题。域名和端口都只是示例，使用时换成你的实际值。

```text
公网 443 -> 当前入口模式对应的单个服务
  nginx-stream  -> Nginx stream 按 SNI 分流
  tcp-peek      -> vpso-mux 按 SNI 分流
  xray-fallback -> Xray 主入站接管 443 并 fallback 到本地 Web 反代引擎

panel.example.com       -> Caddy/Nginx 本地 Web 反代 -> 3x-ui 面板
sub.example.com         -> Caddy/Nginx 本地 Web 反代 -> SublinkPro / Sub-Store / 其他 HTTP 后端
dockge.example.com      -> Caddy/Nginx 本地 Web 反代 -> Dockge
REALITY 伪装 SNI        -> Xray / 3x-ui REALITY 入站
未知 SNI                -> Xray / 3x-ui REALITY 入站
```

最重要的规则：

- 公网 `443` 同一时间只能由一个入口服务监听：`nginx`、`xray` 或 `tcppeek`。
- `ENTRY_MODE` 支持 `nginx-stream`、`xray-fallback`、`tcp-peek`；如果 `/etc/vps-optimize/sni-stack.env` 没有 `ENTRY_MODE`，按 `nginx-stream` 兼容读取。
- 证书继续使用 `acme.sh + Cloudflare DNS API`，不改成 Caddy DNS 模块。
- 443 单入口下的 Web 反代引擎可以选择 Caddy 或 Nginx；切换时复用域名、证书、后端和 Web 白名单，并隔离另一套旧配置。
- Web 白名单只保护 Web 域名，不影响 Xray 节点流量；Nginx Stream/TCP Peek 下会在入口层拦截，`xray-fallback + Nginx 本地 Web 反代` 禁止新增 Web 白名单。
- Xray 入站管理只记录 `SNI -> 本地地址:端口`，不会编辑 3x-ui 入站。
- REALITY 的 `serverName` / `dest` 通常是外部真实 HTTPS 目标，不要求写进 Web 反代引擎。

TCP Peek + Splice 的配置过程和 Nginx Stream 一样；正式切换使用 `[5] 切换到 TCP Peek + Splice 模式`，需要撤销时使用 `[7] 回滚上一次入口模式切换`。

完整教程看 [443 单入口分流详细教程](docs/443-single-entry.md)，排错看 [443 单入口排错手册](docs/443-single-entry-troubleshooting.md)。

<a id="node-tools"></a>
## 📡 订阅管理与节点工具

节点和订阅相关入口集中在 `主菜单 [5 面板、节点与订阅工具]`。

这里包含 3x-ui、x-ui 增强套件、S-UI、Sing-box、Xray、SublinkPro、妙妙屋、Sub-Store、Dockge、Komari 和 dog 流量计。

订阅工具建议按“本地监听 + Caddy/Nginx/443 对外”的方式部署。新部署的订阅工具默认优先绑定 `127.0.0.1`。已经启用 443 单入口时，公网 HTTPS 访问到 `主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]` 添加域名；未启用 443 单入口时，可以在 `主菜单 [4 反代]` 里选择 Caddy 或 Nginx HTTPS 反代，Nginx 反代会直接监听公网 80/443，不能和 443 单入口同时抢占公网 `443`。Nginx 反代复用现有 `acme.sh + Cloudflare DNS API` 证书流程，证书仍安装到 `/etc/caddy/certs/${domain}.crt|key` 并软链到 `/root/cert/`。[4 反代] 里的后端 HTTPS 跳过证书校验、域名 IP 白名单、查看/编辑已应用配置和清空反代配置都同时提供 Caddy/Nginx 入口。

Docker Compose 项目都有管理入口。停止服务会保留数据；归档目录需要输入 `ARCHIVE` 二次确认，避免误删配置和数据库。

<a id="standalone-tools"></a>
## 🧩 独立工具

项目包含两个可以单独运行的维护工具。

### x-ui 增强套件

项目包含 `xui-custom-manager.sh`，用于补充 3x-ui / x-ui 面板外更适合脚本处理的维护功能：自定义重置日期、校准已用流量、备份恢复、健康检查、查看日志和清理旧备份。

入口：

```text
主菜单 [5 面板、节点与订阅工具] -> [2 x-ui 增强套件]
```

单独运行：

```bash
wget -qO xui-custom-manager.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh && chmod +x xui-custom-manager.sh && ./xui-custom-manager.sh
```

首次打开后会自动注册 `xcm` 快捷命令。`xcm` 是手动入口，会优先拉取最新版；systemd timer 只调用本地稳定执行器 `/usr/local/bin/xui-custom-manager.sh --reset-check`。
在 VPS-Optimize 主菜单也可以直接输入 `xcm` 或 `外置` 进入这个工具。

详细说明请看：[x-ui 增强套件说明](docs/xui-custom-manager.md)。

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

进入管理菜单。详细说明请看：[端口流量狗 dog.sh 使用说明](docs/dog.md)。

流量达量关机保护不单独成文档，入口在 `主菜单 [10 网络与内核优化] -> [5 流量达量关机保护]`。状态页的“本周期已用”按所选计费模式、基线和初始已用做实时估算；“网卡原始计数”只是系统自开机累计，开机久时可能远大于本周期已用，不应直接当作账单周期用量。如果最近检查时间超时，可在同一菜单使用“修复/重装自动检查 timer”；检查器安装或修复失败时会显示待检查文件、实际首行字节和日志路径，并写入 `/var/log/vps-traffic-guard.log`；达量后若关机命令未被系统接受，下一次 timer 会继续重试。云厂商后台仍是最终账单参考。

<a id="safety"></a>
## 🛡️ 安全与回滚

高风险功能会要求输入 `YES`。不确定时先做 `主菜单 [16 配置备份与回滚]`。

备份会尽量覆盖 SSH、主机名、Nginx/Caddy、443 单入口、DNS、证书、Cloudflare Token、Docker、Fail2ban、sysctl 和 3x-ui 关键配置。备份里可能包含私钥、面板数据库和 API Token，不要公开分享。

配置完后需要查看或微调脚本已应用的配置，可走 `主菜单 [16 配置备份与回滚] -> [5 查看/编辑脚本已应用配置]`。这个入口会先显示文件内容、编辑前自动备份，并按类型执行 `caddy validate`、`nginx -t`、`sshd -t`、Compose config、JSON 校验或 443 入口重新应用确认。

脚本对目录级清理采用“隔离/归档优先”的策略。常见备份、隔离和证书路径见 [配置和文件路径](docs/config-paths.md)。

几个最容易失联的操作要额外小心：SSH 改端口、仅密钥登录、关闭网卡、改防火墙、切换 443 入口模式、启用流量达量关机。做这些事前，建议先确认云厂商安全组、保留当前 SSH 会话，并准备好快照或救援控制台。

<a id="update-uninstall"></a>
## 🔄 更新与卸载

更新主脚本：

```text
17. 更新脚本  快捷词：u / update / upd
```

推荐通过 `cy -> [17 更新脚本]` 更新主脚本。主菜单会缓存式自动检查更新；发现新版本时会在顶部提示，输入 `u` 即可更新当前脚本。自动检查只读远程版本号，不会自动覆盖脚本。更新逻辑会先执行 `bash -n`，再下载 `dist/vps.sh.sha256` 并执行 `sha256sum -c` 校验；校验失败不会覆盖 `/usr/local/bin/cy`。

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

下面的 `40000`、`8443` 等端口是示例端口；如果你改过端口，以实际监听和脚本保存的配置为准。

优先检查：

- 3x-ui 面板是否监听 `127.0.0.1:40000`。
- 3x-ui 面板和订阅证书路径是否已清空，让 Web 反代引擎接管公网 HTTPS。
- 当前 Web 反代引擎是否监听 `127.0.0.1:8443`。
- 当前入口模式对应的单个服务是否监听公网 `0.0.0.0:443`：`nginx-stream` 看 `nginx`，`xray-fallback` 看 Xray / 3x-ui / x-ui 托管的 Xray，`tcp-peek` 看 `tcppeek` / `vpso-mux`。
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

### 动态 TCP 参数怎么粘贴

入口：`主菜单 [10 网络与内核优化] -> [2 动态 TCP 参数调优]`。进入后按提示把 Omnitt 或其他来源给出的 `sysctl` 参数粘贴进去，粘贴完成后按回车，再另起一行输入 `EOF` 并回车保存。示例值只供参考，实际参数应以你的服务器和网络测试结果为准。

可以直接粘贴多行 `sysctl` 参数块，例如每行一个 `net.ipv4.tcp_xxx = value`、`net.core.default_qdisc = fq`，多值参数如 `net.ipv4.tcp_rmem = 4096 87380 67108864` 也可以保留空格。若误复制成单行长串，例如多个 `key = value` 连在同一行、用分号分隔，或带有 `sysctl -w net.core.default_qdisc=fq` 这样的命令前缀，脚本会尽量拆分并归一化成配置行。

如果某一项无法识别，脚本会停止应用并回滚原配置。语法问题会提示类似 `参数语法错误，已停止应用` 或 `第 N 项语法错误`；当前内核没有对应参数时会提示 `第 N 项当前内核不支持`，并附带 `sysctl 输出` 方便定位。看到这类提示时，优先删除或替换提示里的那一项，不要整段反复强行套用。

### 🔄 更新脚本失败

检查 DNS 和 GitHub 连通性：

```bash
getent ahosts raw.githubusercontent.com
```

<a id="feedback"></a>
## 💬 反馈与联系

如有 Bug 或建议，欢迎前往 [GitHub Issues](https://github.com/Chunlion/VPS-Optimize/issues) 提交反馈。

Telegram 群：[t.me/cutyy_github](https://t.me/cutyy_github)。

也可以通过作者 [GitHub 主页](https://github.com/Chunlion) 展示的联系方式或邮箱联系。

## 📜 开源协议

本项目使用 [GNU General Public License v3.0](LICENSE)。
