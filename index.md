---
layout: home

hero:
  eyebrow: 面向长期维护设计
  name: VPS-Optimize
  text: 从首次配置，到持续维护你的 VPS
  tagline: 检测、备份、优化、验证和回滚，关键操作都有清晰路径。
  image:
    light: /assets/entry-routing-zh.webp
    dark: /assets/entry-routing-zh-dark.webp
    alt: 端口 443 经 VPS-Optimize 分配到 Web、Xray 和 TCP Peek 的示意图
    caption: 单一公网入口 · 配置共享 · 状态可见
  actions:
    - theme: brand
      text: 查看使用流程
      link: /quick-start
    - theme: alt
      text: 项目源码
      link: https://github.com/Chunlion/VPS-Optimize

workflow:
  label: VPS-Optimize 维护流程
  steps:
    - icon: fa-solid fa-magnifying-glass
      title: 检测
      details: 检查系统、网络与服务状态，识别潜在问题。
    - icon: fa-solid fa-database
      title: 备份
      details: 保存关键配置与状态，保留恢复路径。
    - icon: fa-solid fa-bolt
      title: 优化
      details: 按需调整系统与网络配置，减少无效变更。
    - icon: fa-solid fa-shield-halved
      title: 验证
      details: 检查服务可用性与关键指标，确认变更生效。
    - icon: fa-solid fa-rotate-left
      title: 回滚
      details: 出现异常时恢复配置，回到稳定状态。

story:
  kicker: 项目理念
  title: 维护不是一次性任务
  description: VPS-Optimize 将检测、备份、变更、验证和回滚组织为统一流程，保留关键状态与日志，便于长期维护和问题排查。
  principles:
    - icon: fa-solid fa-list-check
      title: 标准化流程
      text: 一致的操作步骤与输出
    - icon: fa-solid fa-shield-halved
      title: 安全可控
      text: 关键变更前保留备份
    - icon: fa-solid fa-chart-column
      title: 状态可观测
      text: 关键指标与日志集中查看
  terminalLabel: VPS-Optimize 状态示例
  terminalHeader: 项目 / 状态
  terminalRows:
    - label: 系统环境
      value: 正常
    - label: 配置备份
      value: 可用
    - label: 443端口复用
      value: 运行中
    - label: 关键服务
      value: 运行中
    - label: 防火墙
      value: 已启用
  primaryIcon: fa-solid fa-shield-halved
  primaryTitle: 更稳妥
  primaryText: 变更前保留恢复路径，降低配置错误带来的影响。
  secondaryIcon: fa-regular fa-clock
  secondaryTitle: 更清晰
  secondaryText: 检测结果和服务状态集中呈现，便于定位问题。
---
