# ⚡ VPS-Optimize

<p align="center">
  <a href="README.md">🌐 简体中文</a> · <a href="en/README.md">English</a> · <a href="ru/README.md">Русский</a>
</p>

<p align="center">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&amp;logoColor=white">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPLv3-blue.svg"></a>
  <a href="https://github.com/Chunlion/VPS-Optimize/releases/latest"><img alt="Release" src="https://img.shields.io/badge/Release-latest-blue.svg"></a>
</p>

<p align="center">
  面向 VPS 日常运维的 Bash 控制面板。使用 <code>cy</code> 完成系统初始化、安全加固、面板与订阅工具部署、443端口复用、备份回滚和故障排查。
</p>

<p align="center">
  <a href="https://chunlion.github.io/VPS-Optimize/">📚 文档网站</a> · <a href="https://chunlion.github.io/VPS-Optimize/quick-start">快速开始</a> · <a href="https://chunlion.github.io/VPS-Optimize/docs/443-single-entry">443端口复用：部署与配置</a>
</p>

## 🚀 快速开始

> ⚠️ 请从本仓库或 GitHub Raw 获取脚本；不要通过来源不明的 GitHub 加速代理下载后直接以 `root` 运行。

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行会注册全局快捷命令：

```bash
cy
```

首次交互运行会用英文提示选择简体中文、English 或 Русский；直接回车默认 English。之后可从主菜单 `[20 界面语言]` 修改，设置保存在 `/etc/vps-optimize/language.conf`。

### 主菜单快捷词

快捷词不区分大小写，作用等同于选择对应的主菜单编号，不会跳过后续确认。

| 快捷词 | 主菜单项 |
|---|---|
| `proxy` | `[4 反代（Caddy/Nginx）]` |
| `panel` | `[5 面板、节点与订阅工具]` |
| `ssh` | `[6 SSH 安全中心]` |
| `firewall` | `[8 防火墙规则管理]` |
| `bbr` | `[10 网络与内核优化]` |
| `docker` | `[11 Docker 管理]` |
| `speed` | `[12 测速与质量检测]` |
| `health` | `[15 服务健康总览]` |
| `backup` | `[16 配置备份与回滚]` |
| `u` / `update` / `upd` | `[17 更新脚本]` |
| `443` | `[19 443端口复用管理中心]` |
| `lang` | `[20 界面语言]` |

## 🖥️ 支持系统

| 系统 | 状态 |
|---|---|
| Debian 11/12/13 | 推荐 |
| Ubuntu 20.04/22.04/24.04 | 推荐 |
| Rocky / Alma / CentOS Stream | 可用 |
| Alpine | 不支持 |
| OpenVZ 老系统 | 不建议 |

## 🧰 主要功能

| 场景 | 功能 |
|---|---|
| 系统初始化 | 预检、常用工具、时区、IPv4 出站优先和基础 BBR |
| 安全加固 | SSH、公钥登录、Fail2ban、防火墙、端口并发限制 |
| 面板与订阅 | 3x-ui、S-UI、2S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari、CDT Monitor |
| 转发与组网 | Realm、Gost、FLVX 哆啦转发面板、EasyTier、Tailscale |
| 443端口复用 | Web、面板、订阅和节点共享公网 `443`，按 SNI 路由；同一时间仅由当前入口服务监听 |
| 诊断与回滚 | 服务健康、443 链路体检、空间预检、可选加密备份、恢复和隔离归档 |

## 📚 文档与反馈

- [快速开始](https://chunlion.github.io/VPS-Optimize/quick-start)
- [443端口复用：部署与配置](https://chunlion.github.io/VPS-Optimize/docs/443-single-entry)
- [443端口复用排错与恢复](https://chunlion.github.io/VPS-Optimize/docs/443-single-entry-troubleshooting)
- [失联与回滚急救](https://chunlion.github.io/VPS-Optimize/docs/recovery-runbook)
- [CDT Monitor：阿里云 CDT 流量与 ECS 管理](https://chunlion.github.io/VPS-Optimize/docs/cdt-monitor)
- [提交 Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## 📄 许可证

本项目使用 [GNU General Public License v3.0](LICENSE)。
