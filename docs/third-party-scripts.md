# 第三方脚本来源

本页列出 VPS-Optimize 当前会下载并作为脚本执行的第三方项目。二进制下载、系统软件包仓库、API 服务和本项目自有的 `dog.sh`、`xui-custom-manager.sh` 不在此表中。

远程脚本可能随上游更新而变化。执行前请核对项目地址和脚本内容。

## 安装与管理

| VPS-Optimize 入口 | 项目名称 | 项目地址 |
|---|---|---|
| acme.sh 证书安装 | acme.sh | <https://github.com/acmesh-official/acme.sh> |
| Docker 引擎安装 | Docker Engine | <https://github.com/docker/docker-install> |
| Docker Compose 二进制 | Docker Compose | <https://github.com/docker/compose> |
| Python 环境安装 | lxspacepy | <https://github.com/lx969788249/lxspacepy> |
| WARP 解锁/网络工具 | WARP | <https://gitlab.com/fscarmen/warp> |
| Realm 端口转发 | Realm-xwPF | <https://github.com/zywe03/realm-xwPF> |
| Gost 隧道 | EZgost | <https://github.com/qqrrooty/EZgost> |
| 极光面板 | Aurora Admin Panel | <https://github.com/Aurora-Admin-Panel/deploy> |
| nftables NAT 转发 | nftables-nat-rust | <https://github.com/arloor/nftables-nat-rust> |
| Aria2 下载工具 | aria2.sh | <https://github.com/P3TERX/aria2.sh> |
| 宝塔面板安装（HTTP 源已拒绝执行） | HostCLI | <https://www.hostcli.com/> |
| PVE 管理脚本 | oneclickvirt/pve | <https://github.com/oneclickvirt/pve> |
| Argox 转发面板 | Argox | <https://github.com/fscarmen/argox> |
| Forwardx 转发面板 | Forwardx | <https://github.com/poouo/Forwardx> |
| FLVX 哆啦转发面板 | FLVX | <https://github.com/Sagit-chu/flvx> |
| BBR / 多内核调优 | Linux-NetSpeed | <https://github.com/ylx2016/Linux-NetSpeed> |
| IP-Sentinel | IP-Sentinel | <https://github.com/hotyue/IP-Sentinel> |
| 3x-ui 管理 | 3x-ui | <https://github.com/mhsanaei/3x-ui> |
| S-UI 管理 | S-UI | <https://github.com/alireza0/s-ui> |
| 2S-UI 安装 | 2S-UI | <https://github.com/shenaba/2s-ui> |
| EasyTier 组网 | EasyTier | <https://github.com/EasyTier/EasyTier> |
| Tailscale 组网 | Tailscale | <https://github.com/tailscale/tailscale> |
| Sing-box 管理 | 233boy/sing-box | <https://github.com/233boy/sing-box> |
| Xray 管理 | 233boy/Xray | <https://github.com/233boy/Xray> |
| Telegram VPS Bot 远程管理 | VPS_BOT_X | <https://github.com/MEILOI/VPS_BOT_X> |

## 测试与诊断

| VPS-Optimize 入口 | 项目名称 | 项目地址 |
|---|---|---|
| YABS 硬件性能测试（跳过网络测速） | yet-another-bench-script | <https://github.com/masonr/yet-another-bench-script> |
| 三网回程路由测试 | backtrace | <https://github.com/zhanghanyun/backtrace> |
| IP 质量 / 欺诈度检测 | IPQuality | <https://github.com/xykt/IPQuality> |
| NodeQuality 完整报告（硬件、IP、网络与回程） | NodeQuality | <https://github.com/LloydAsp/NodeQuality> |
| 流媒体解锁检测 | RegionRestrictionCheck | <https://github.com/lmc999/RegionRestrictionCheck> |
| TcpQuality TCP 质量测试 | TcpQuality | <https://github.com/ibsgss/TcpQuality> |
| 网站延迟与 DNS 检测 | network-latency-tester | <https://github.com/Cd1s/network-latency-tester> |
| 网络质量检测（低流量，跳过带宽测速） | NetQuality | <https://github.com/xykt/NetQuality> |

## 系统重装

| VPS-Optimize 入口 | 项目名称 | 项目地址 |
|---|---|---|
| 系统重装 | reinstall | <https://github.com/bin456789/reinstall> |

HostCLI 没有公开源码仓库；其入口是 HTTP，VPS-Optimize 会在下载前拒绝执行，因此仅保留项目页用于追溯。
