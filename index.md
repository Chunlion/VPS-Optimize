---
layout: home

hero:
  name: VPS-Optimize
  text: VPS 初始化与服务器维护指南
  tagline: 面向 VPS 初始化、系统优化、网络参数调整与服务器维护的脚本工具。
  actions:
    - theme: brand
      text: 快速开始
      link: /quick-start
    - theme: alt
      text: GitHub
      link: https://github.com/Chunlion/VPS-Optimize

features:
  - title: VPS 初始化
    details: 快速完成基础环境配置、常用工具安装、时区与软件源准备。适合新服务器上线前统一环境。
  - title: 系统环境检测
    details: 检测系统版本、CPU 架构、虚拟化环境、网络连通性和关键服务状态，便于运行前预检。
  - title: 网络参数优化
    details: 提供常见内核网络参数调整入口，辅助优化连接队列、转发、缓冲区等服务器网络表现。
  - title: TCP 优化
    details: 辅助配置拥塞控制算法、队列管理策略和 BBR 相关选项，适合配合快照与回滚准备使用。
  - title: 443 单入口
    details: 统一公网 443 入口，辅助处理面板、订阅、网站和 REALITY 节点分流，减少端口暴露和冲突。
  - title: 维护与回滚
    details: 提供更新、清理、状态查看、配置备份、恢复回滚和故障排查入口，用于日常维护。
---

## 常用文档

| 目标 | 文档 |
|---|---|
| 安装并运行 | [快速开始](quick-start.md) |
| 配置 443 单入口 | [443 单入口](docs/443-single-entry.md) |
| 部署 3x-ui + REALITY + 443 | [3x-ui + REALITY + 443](tutorials/01-3x-ui-reality-443.md) |
| 接入订阅工具 | [订阅工具接入 443](tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md) |
| 处理安全与回滚 | [安全与回滚](docs/security-rollback.md) |
| 排查常见问题 | [常见问题](docs/faq.md) |
