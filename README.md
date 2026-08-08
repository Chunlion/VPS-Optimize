# ⚡ VPS-Optimize

[🌐 简体中文](README.md) · [English](en/README.md) · [Русский](ru/README.md)

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/Release-latest-blue.svg)](https://github.com/Chunlion/VPS-Optimize/releases/latest)

面向 VPS 日常运维的 Bash 控制面板。通过 `cy` 集中完成系统初始化、安全加固、面板部署、443 单入口、订阅工具、备份回滚和故障排查。

[📚 文档网站](https://chunlion.github.io/VPS-Optimize/) · [快速开始](quick-start.md) · [443 单入口](docs/443-single-entry.md)

## 🚀 快速开始

> ⚠️ 不要通过来源不明的 GitHub 加速代理下载脚本后直接以 `root` 运行。

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行会注册全局快捷命令：

```bash
cy
```

首次交互运行会用英文提示选择简体中文、English 或 Русский；直接回车默认 English。之后可从主菜单 `[20 界面语言]` 修改，设置保存在 `/etc/vps-optimize/language.conf`。

## 🖥️ 支持系统

| 系统 | 状态 |
|---|---|
| Debian 11/12 | 推荐 |
| Ubuntu 20.04/22.04/24.04 | 推荐 |
| Rocky / Alma / CentOS Stream | 可用 |
| Alpine | 不支持 |
| OpenVZ 老系统 | 不建议 |

## 🧰 主要功能

| 场景 | 功能 |
|---|---|
| 系统初始化 | 预检、常用工具、时区和基础 BBR |
| 安全加固 | SSH、公钥登录、Fail2ban、防火墙、端口并发限制 |
| 面板与订阅 | 3x-ui、S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari |
| 转发与组网 | Realm、Gost、FLVX 哆啦转发面板、EasyTier、Tailscale |
| 443 单入口 | Web、面板、订阅和节点共用公网 `443`，按 SNI 路由 |
| 诊断与回滚 | 服务健康、443 链路体检、配置备份、恢复和隔离归档 |

## 📚 文档与反馈

- [快速开始](quick-start.md)
- [443 单入口排错与恢复](docs/443-single-entry-troubleshooting.md)
- [失联与回滚急救](docs/recovery-runbook.md)
- [提交 Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## 📄 许可证

本项目使用 [GNU General Public License v3.0](LICENSE)。
