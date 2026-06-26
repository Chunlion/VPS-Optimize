# 🚀 VPS-Optimize

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/Release-latest-blue.svg)](https://github.com/Chunlion/VPS-Optimize/releases/latest)
![Stars](https://img.shields.io/github/stars/Chunlion/VPS-Optimize?style=social)

VPS-Optimize 是一个面向 VPS 日常运维的 Bash 控制面板，通过 `cy` 命令集中处理系统初始化、安全加固、面板部署、443 单入口、订阅工具、备份回滚和故障排查。

完整文档：https://chunlion.github.io/VPS-Optimize/

## ⚡ 快速运行

国内：

```bash
wget -qO vps.sh https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

国外：

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

首次运行后会注册快捷命令：

```bash
cy
```

## 🖥️ 支持系统

| 系统 | 状态 |
|---|---|
| Debian 11/12 | 推荐 |
| Ubuntu 20.04/22.04/24.04 | 推荐 |
| Rocky / Alma / CentOS Stream | 可用 |
| Alpine | 不支持 |
| OpenVZ 老系统 | 不建议 |

## ✨ 主要特点

| 场景 | 功能 |
|---|---|
| 系统初始化 | 预检、常用工具、时区、基础 BBR |
| 安全加固 | SSH、公钥登录、Fail2ban、防火墙、端口并发限制 |
| 面板与订阅 | 3x-ui、S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari |
| 443 单入口 | Web、面板、订阅和节点共用公网 `443`，按 SNI 分流 |
| 诊断与回滚 | 服务健康、443 链路体检、配置备份、恢复和隔离归档 |

## 🧭 面板预览

![VPS-Optimize 面板预览](https://i.mji.rip/2026/06/03/50e5eac2e83fbf7ef15240e3fa8c693a.png)

## 💬 反馈联系

- Issues：https://github.com/Chunlion/VPS-Optimize/issues
- Telegram：https://t.me/cutyy_github
- GitHub：https://github.com/Chunlion

## 📜 开源协议

本项目使用 [GNU General Public License v3.0](LICENSE)。
