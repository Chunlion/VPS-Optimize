---
layout: home

hero:
  eyebrow: VPS 初始化与日常维护
  name: VPS-Optimize
  text: 配置有序，维护有据。
  tagline: 在一个 Bash 菜单中完成系统与网络调优、服务部署和故障排查。按需操作，变更前先备份。
  guide:
    title: 一个公网入口，三种可选模式
    note: 每次只启用一种模式，按部署需求选择。
    modes:
      - name: nginx-stream
        description: Nginx 监听 443，按 SNI 转发连接。
      - name: xray-fallback
        description: Xray 主入站监听 443，处理回落。
      - name: tcp-peek
        description: TCP Peek 监听 443，探测后转发连接。
    link: /docs/443-tcp-peek-engine
    action: 了解入口模式与配置
  actions:
    - theme: brand
      text: 快速开始
      link: /quick-start
    - theme: alt
      text: 项目源码
      link: https://github.com/Chunlion/VPS-Optimize

workflow:
  label: 建议维护步骤，点击查看相关文档
  steps:
    - icon: fa-solid fa-magnifying-glass
      title: 检测
      details: 检查系统、网络与服务状态，识别潜在问题。
      link: /docs/before-use
    - icon: fa-solid fa-database
      title: 备份
      details: 保存所需配置，业务数据另行备份。
      link: /docs/security-rollback
    - icon: fa-solid fa-bolt
      title: 优化
      details: 按需调整系统与网络配置，减少无效变更。
      link: /quick-start
    - icon: fa-solid fa-shield-halved
      title: 验证
      details: 检查服务状态，确认实际访问结果。
      link: /docs/faq
    - icon: fa-solid fa-rotate-left
      title: 回滚
      details: 按备份范围恢复配置，再检查服务。
      link: /docs/recovery-runbook

story:
  kicker: 变更与恢复
  title: 先留好退路，再调整配置。
  description: 从菜单检查服务、备份配置和查看日志。配置恢复仅覆盖备份内容，不能替代 VPS 快照或业务数据备份。
  principles:
    - icon: fa-solid fa-list-check
      title: 按需操作
      text: 从菜单选择所需功能
    - icon: fa-solid fa-shield-halved
      title: 备份配置
      text: 变更前确认备份范围
    - icon: fa-solid fa-chart-column
      title: 排查问题
      text: 结合服务状态与日志
  terminalLabel: 状态示例 · 非实时数据
  terminalHeader: 项目 / 状态
  terminalRows:
    - label: 系统环境
      value: 正常
    - label: 配置备份
      value: 可用
    - label: 443 端口复用
      value: 运行中
    - label: 关键服务
      value: 运行中
    - label: 防火墙
      value: 已启用
  primaryIcon: fa-solid fa-shield-halved
  primaryTitle: 更稳妥
  primaryText: 保留 SSH 会话，提前准备快照与恢复入口。
  secondaryIcon: fa-regular fa-clock
  secondaryTitle: 更清晰
  secondaryText: 检测结果和服务状态集中呈现，便于定位问题。
---
