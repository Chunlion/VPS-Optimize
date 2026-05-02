# 兼容性与环境要求

这份文档说明 VPS-Optimize 适合哪些系统、虚拟化环境、网络条件和部署方式。它的重点是帮你在运行脚本前判断风险。

本文菜单路径按“主菜单 [编号 菜单文案] -> [子编号 菜单文案]”格式书写。

## 总体建议

| 项目 | 建议 |
|---|---|
| 权限 | 使用 `root` 运行 |
| 系统 | Debian 11/12 或 Ubuntu 20.04/22.04/24.04 |
| 初始化顺序 | 先预检，再初始化，再部署面板或 443 |
| 快照 | SSH、防火墙、内核、443 单入口前必须做 |
| 安全组 | 云厂商安全组和系统防火墙都要确认 |
| DNS | 443 单入口相关域名建议 DNS only / 灰云 |

运行前先看：

```text
主菜单 [1 运维预检与风险扫描]
```

## 系统支持

| 系统 | 状态 | 说明 |
|---|---|---|
| Debian 11 | 推荐 | 稳定，适合大多数 VPS |
| Debian 12 | 推荐 | 稳定，推荐新机器优先选择 |
| Ubuntu 20.04 | 推荐 | 可用，但新机器更建议 22.04/24.04 |
| Ubuntu 22.04 | 推荐 | 稳定 |
| Ubuntu 24.04 | 推荐 | 新系统，少数第三方脚本可能需要额外验证 |
| Rocky Linux / AlmaLinux | 可用 | 部分组件依赖 `dnf` / `firewalld` 和软件源 |
| CentOS Stream | 可用 | 适合熟悉 RHEL 系的用户 |
| CentOS 7 | 不推荐 | 软件源、内核、依赖版本容易踩坑 |
| Alpine | 不支持 | 脚本大量依赖 systemd、常规包管理和 GNU 工具 |
| OpenVZ 老系统 | 不推荐 | 内核能力不足，BBR/ZRAM/网络优化可能不可用 |

## 虚拟化和内核

| 环境 | 建议 |
|---|---|
| KVM / QEMU / VMware | 推荐 |
| Hyper-V / Azure | 可用，注意安全组和防火墙 |
| LXC | 谨慎，内核和 systemd 能力取决于宿主机 |
| OpenVZ 6/7 | 不建议做内核、BBR、ZRAM、nftables 深度操作 |
| 独立服务器 | 可用，但内核和网卡参数更要谨慎 |

内核相关功能入口：

```text
主菜单 [10 网络与内核优化]
```

风险较高的子项：

| 子项 | 风险 |
|---|---|
| `[2 动态 TCP 参数调优]` | 参数错误可能影响连通性 |
| `[3 ZRAM / Swap 内存调优]` | 小内存有帮助，但要观察负载 |
| `[4 安装/切换优化内核]` | 可能影响下次启动 |
| `[5 清理旧内核]` | 删除错误内核会影响回退 |

内核相关操作前确认：

1. 已创建云快照。
2. 云厂商 VNC / 救援控制台可用。
3. 当前不是 OpenVZ 老系统。
4. 不清理当前正在运行的内核。

## 必需命令和组件

脚本会按需安装依赖，但极简系统可能缺基础命令。

| 类别 | 常见组件 |
|---|---|
| 网络 | `curl`、`wget`、`iproute2`、`ss`、`dig` 或 `nslookup` |
| 系统服务 | `systemd`、`systemctl`、`journalctl` |
| 证书 | `openssl`、`ca-certificates`、`acme.sh`、Caddy |
| 防火墙 | `ufw` 或 `firewalld`，部分工具用 `nftables` |
| 容器 | Docker、Docker Compose |
| 文本处理 | `awk`、`sed`、`grep`、`jq` |

如果预检提示 DNS、软件源、包管理器锁异常，先修这些基础问题，不要继续部署面板或 443。

## 网络要求

| 项目 | 要求 |
|---|---|
| GitHub Raw | 能下载脚本和更新 |
| 软件源 | 能安装系统依赖 |
| DNS | 能解析域名和常用源 |
| NTP 时间 | 证书签发依赖准确时间 |
| 公网 IP | 443 单入口和证书签发通常需要公网可达 |

检查：

```bash
curl -I https://raw.githubusercontent.com/
date -Is
timedatectl status
getent ahosts raw.githubusercontent.com
```

相关入口：

```text
主菜单 [1 运维预检与风险扫描]
主菜单 [15 服务健康总览]
```

## DNS 与 Cloudflare

443 单入口相关域名建议先使用 DNS only / 灰云。

| 域名类型 | 建议 |
|---|---|
| 面板域名 | DNS only / 灰云 |
| 节点域名 | DNS only / 灰云，必须能直连 VPS |
| 订阅域名 | DNS only / 灰云 |
| 普通网站域名 | 先灰云跑通，再按业务决定 |
| REALITY 伪装 SNI | 外部真实 HTTPS 站点，不指向你的 VPS |

Cloudflare Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

证书维护入口：

```text
主菜单 [19 443 单入口管理中心] -> [6 CF DNS / Caddy 证书维护]
```

## 端口模型

### 未启用 443 单入口

普通部署可能会有多个公网端口，例如：

```text
SSH: 22 或自定义端口
Caddy: 80/443
3x-ui 面板: 40000
订阅服务: 2096
Docker 工具: 3000/3001/5001 等
```

这时要同时管理云安全组和系统防火墙。

### 启用 443 单入口

推荐目标：

| 组件 | 监听位置 |
|---|---|
| Nginx stream | `0.0.0.0:443` |
| Caddy | `127.0.0.1:8443` |
| 3x-ui 面板 | `127.0.0.1:40000` |
| 3x-ui 订阅 | `127.0.0.1:2096` |
| REALITY | `127.0.0.1:1443` |
| 网站或订阅工具后端 | `127.0.0.1:后端端口` |

公网通常只需要：

```text
SSH 端口
443/tcp
```

检查端口：

```bash
ss -lntp
```

相关入口：

```text
主菜单 [13 端口排查与释放]
主菜单 [19 443 单入口管理中心] -> [3 443 单入口链路体检]
```

## IPv6-only 和双栈

| 环境 | 建议 |
|---|---|
| IPv4 + IPv6 双栈 | 推荐，最少坑 |
| 纯 IPv4 | 可用 |
| 纯 IPv6 | 谨慎，部分源、证书、第三方脚本可能不稳定 |
| NAT VPS | 谨慎，公网端口映射和证书验证要额外确认 |

如果是纯 IPv6 或 NAT 机器，先确认：

```bash
curl -4 icanhazip.com
curl -6 icanhazip.com
ss -lntp
```

443 单入口需要外部能访问到你的入口端口，否则证书、面板、订阅和 REALITY 都会受到影响。

## 小内存机器

| 内存 | 建议 |
|---|---|
| 512MB | 只做轻量功能，谨慎 Docker 和多面板 |
| 1GB | 可以跑基础面板，建议启用 ZRAM |
| 2GB | 常规使用较稳 |
| 4GB+ | 可同时跑面板、订阅工具、监控等 |

小内存机器建议：

```text
主菜单 [10 网络与内核优化] -> [3 ZRAM / Swap 内存调优]
```

不要同时部署过多 Docker 服务。Caddy、3x-ui、Sub-Store、Dockge、监控面板叠加后，小机器容易 OOM。

## Docker 和 Compose

Docker 相关功能需要：

| 要求 | 说明 |
|---|---|
| systemd | 用于 Docker 服务管理 |
| 可用软件源 | 安装 Docker 包 |
| 足够磁盘 | 镜像、日志、卷都会占空间 |
| 明确端口 | 避免后端端口暴露公网 |

安装入口：

```text
主菜单 [3 基础组件与反代分流] -> [1 Docker 引擎]
```

Docker 安全入口：

```text
主菜单 [11 Docker 安全管理]
```

如果容器只应该给 Caddy 访问，后端优先绑定 `127.0.0.1`，或者使用 Docker 本地防穿透。

## 端口流量狗兼容性

`dog.sh` 依赖：

```text
nftables
iproute2: tc, ss
jq
bc
curl
cron
conntrack
```

适合 Debian / Ubuntu。OpenVZ、极简系统、没有 nftables 能力的系统可能无法完整工作。

入口：

```text
主菜单 [4 面板、节点与订阅工具] -> [14 端口流量监控]
```

独立文档见 [../README_dog.md](../README_dog.md)。

## 3x-ui 外置增强管理兼容性

`xui-custom-manager.sh` 默认假设 3x-ui / x-ui 使用常见路径：

```text
/etc/x-ui/x-ui.db
/etc/x-ui
/usr/local/x-ui
```

如果你的面板不是官方安装器结构，先确认数据库和服务路径再使用。

入口：

```text
主菜单 [4 面板、节点与订阅工具] -> [16 3x-ui 外置增强管理]
```

独立文档见 [../README_xui_custom_manager.md](../README_xui_custom_manager.md)。

## 不建议直接运行的情况

| 情况 | 建议 |
|---|---|
| 没有快照，也没有 VNC/救援控制台 | 不要改 SSH、防火墙、内核、443 |
| 已有复杂生产业务但没盘点 | 先看 [existing-server-migration.md](existing-server-migration.md) |
| 端口占用不清楚 | 先跑 `ss -lntp` 和服务健康总览 |
| Cloudflare Token 权限不清楚 | 先在 Cloudflare 控制台确认权限 |
| 纯 IPv6 / NAT 环境不确定 | 先确认公网入口可达 |
| 系统时间不同步 | 先修 NTP，再签证书 |

## 最小安全流程

第一次使用建议按这个顺序：

```text
主菜单 [1 运维预检与风险扫描]
主菜单 [16 配置备份与回滚] -> [1 创建全量配置备份]
主菜单 [2 基础环境初始化]
主菜单 [15 服务健康总览]
```

再根据目标继续：

| 目标 | 下一步 |
|---|---|
| SSH 加固 | `主菜单 [5 SSH 安全加固]` |
| 面板和节点 | `主菜单 [4 面板、节点与订阅工具]` |
| 443 单入口 | `主菜单 [19 443 单入口管理中心]` |
| Docker 工具 | `主菜单 [3 基础组件与反代分流] -> [1 Docker 引擎]` |
