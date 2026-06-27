# 快速开始

VPS-Optimize 是一个面向 VPS 日常维护的 Bash 脚本入口，适合用于新服务器初始化、系统优化、网络参数调整、基础安全配置、节点部署辅助和常见故障排查。

脚本会修改 SSH、防火墙、内核参数、Nginx/Caddy 配置、Docker 配置、证书文件和 443 单入口相关服务。运行前先创建 VPS 快照，保留当前 SSH 会话，并确认云厂商安全组已放行 SSH 端口。

## 运行前检查

- 已创建 VPS 快照。
- 当前 SSH 会话保持不断开。
- 云厂商安全组已放行 SSH 端口。
- 域名 DNS 已解析到当前 VPS。
- 如使用 Cloudflare，相关域名保持 DNS only。
- 已准备 Cloudflare API Token。
- 已确认服务器系统版本在支持范围内。

## 国内安装

```bash
wget -qO vps.sh https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

## 国外安装

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

## 快捷命令

首次运行后会注册全局快捷命令，以后直接输入：

```bash
cy
```

## 支持系统

| 系统 | 支持状态 | 备注 |
|---|---|---|
| Debian 11/12 | 推荐 | 稳定性较好 |
| Ubuntu 20.04/22.04/24.04 | 推荐 | 稳定性较好 |
| Rocky/Alma/CentOS Stream | 可用 | 部分组件依赖软件源 |
| Alpine | 不支持 | 不建议运行 |
| OpenVZ 老系统 | 不建议 | 内核功能可能缺失 |

## 下一步

| 目标 | 文档 |
|---|---|
| 配置 443 单入口 | [443 单入口](docs/443-single-entry.md) |
| 部署 3x-ui + REALITY + 443 | [3x-ui + REALITY + 443](tutorials/01-3x-ui-reality-443.md) |
| 接入订阅工具 | [订阅工具接入 443](tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md) |
| 查看端口流量 | [端口流量狗](docs/dog.md) |
| 使用 x-ui 增强工具 | [x-ui 增强套件](docs/xui-custom-manager.md) |
| 排查 443 问题 | [443 排错/恢复](docs/443-single-entry-troubleshooting.md) |
| 处理失联和回滚 | [失联与回滚急救](docs/recovery-runbook.md) |
