import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'zh-CN',
  title: 'VPS-Optimize',
  description: '面向 VPS 初始化、系统优化、网络参数调整与服务器维护的脚本工具',
  base: '/VPS-Optimize/',
  cleanUrls: true,
  lastUpdated: true,
  srcExclude: [
    'AGENTS.md',
    'CHANGELOG.md',
    'README.md',
    'src/**',
    '.github/**'
  ],
  head: [
    ['meta', { name: 'theme-color', content: '#f7fbff' }],
    ['meta', { name: 'referrer', content: 'strict-origin-when-cross-origin' }]
  ],
  markdown: {
    lineNumbers: true,
    theme: {
      light: 'github-light',
      dark: 'one-dark-pro'
    }
  },
  themeConfig: {
    siteTitle: 'VPS-Optimize',
    nav: [
      { text: '首页', link: '/' },
      { text: '快速开始', link: '/quick-start' },
      {
        text: '文档',
        items: [
          { text: '文档首页', link: '/' },
          { text: '443 单入口', link: '/docs/443-single-entry' },
          { text: '3x-ui + REALITY + 443', link: '/tutorials/01-3x-ui-reality-443' },
          { text: '订阅工具接入 443', link: '/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
          { text: '安全与回滚', link: '/docs/security-rollback' },
          { text: '常见问题', link: '/docs/faq' }
        ]
      },
      { text: 'GitHub', link: 'https://github.com/Chunlion/VPS-Optimize' }
    ],
    sidebar: {
      '/': [
        {
          text: '使用指南',
          items: [
            { text: '文档首页', link: '/' },
            { text: '快速开始', link: '/quick-start' },
            { text: '使用前必读', link: '/docs/before-use' },
            { text: '支持系统', link: '/docs/supported-systems' }
          ]
        },
        {
          text: '核心功能',
          items: [
            { text: '443 单入口', link: '/docs/443-single-entry' },
            { text: 'TCP Peek 引擎', link: '/docs/443-tcp-peek-engine' },
            { text: '订阅管理与节点工具', link: '/docs/subscription-tools' }
          ]
        },
        {
          text: '场景教程',
          items: [
            { text: '3x-ui + REALITY + 443', link: '/tutorials/01-3x-ui-reality-443' },
            { text: '订阅工具接入 443', link: '/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
            { text: '已有服务器迁移', link: '/docs/existing-server-migration' },
            { text: '失联与回滚急救', link: '/docs/recovery-runbook' }
          ]
        },
        {
          text: '工具',
          items: [
            { text: '配置路径', link: '/docs/config-paths' },
            { text: '端口流量狗', link: '/docs/dog' },
            { text: 'x-ui 增强套件', link: '/docs/xui-custom-manager' }
          ]
        },
        {
          text: '维护与排错',
          items: [
            { text: '443 排错/恢复', link: '/docs/443-single-entry-troubleshooting' },
            { text: '安全与回滚', link: '/docs/security-rollback' },
            { text: '更新与卸载', link: '/docs/update-uninstall' },
            { text: '常见问题', link: '/docs/faq' }
          ]
        }
      ]
    },
    outline: {
      level: [2, 3],
      label: '本页目录'
    },
    docFooter: {
      prev: '上一页',
      next: '下一页'
    },
    lastUpdated: {
      text: '最后更新',
      formatOptions: {
        dateStyle: 'medium',
        timeStyle: 'short'
      }
    },
    search: {
      provider: 'local',
      options: {
        translations: {
          button: {
            buttonText: '搜索文档',
            buttonAriaLabel: '搜索文档'
          },
          modal: {
            displayDetails: '显示详细列表',
            resetButtonTitle: '清除搜索',
            backButtonTitle: '关闭搜索',
            noResultsText: '没有找到结果',
            footer: {
              selectText: '选择',
              selectKeyAriaLabel: '回车',
              navigateText: '切换',
              navigateUpKeyAriaLabel: '上箭头',
              navigateDownKeyAriaLabel: '下箭头',
              closeText: '关闭',
              closeKeyAriaLabel: 'ESC'
            }
          }
        }
      }
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/Chunlion/VPS-Optimize' }
    ]
  }
})
