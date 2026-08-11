import { defineConfig } from 'vitepress'

const socialLinks = [
  { icon: 'github' as const, link: 'https://github.com/Chunlion/VPS-Optimize' }
]

const zhTheme = {
  siteTitle: 'VPS-Optimize',
  nav: [
    { text: '首页', link: '/' },
    { text: '快速开始', link: '/quick-start' },
    {
      text: '文档',
      items: [
        { text: '文档首页', link: '/' },
        { text: '443端口复用：部署与配置', link: '/docs/443-single-entry' },
        { text: '443端口复用：独立订阅工具反代', link: '/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
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
        text: '443端口复用',
        items: [
          { text: '部署与配置', link: '/docs/443-single-entry' },
          { text: '独立订阅工具反代', link: '/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
          { text: '入口模式与原理', link: '/docs/443-tcp-peek-engine' },
          { text: '排错与恢复', link: '/docs/443-single-entry-troubleshooting' }
        ]
      },
      {
        text: '场景教程',
        items: [
          { text: '已有服务器迁移', link: '/docs/existing-server-migration' },
          { text: '失联与回滚急救', link: '/docs/recovery-runbook' }
        ]
      },
      {
        text: '工具',
        items: [
          { text: '订阅管理与节点工具', link: '/docs/subscription-tools' },
          { text: '配置路径', link: '/docs/config-paths' },
          { text: '端口流量狗', link: '/docs/dog' },
          { text: 'x-ui 增强套件', link: '/docs/xui-custom-manager' },
          { text: '第三方脚本来源', link: '/docs/third-party-scripts' }
        ]
      },
      {
        text: '维护与排错',
        items: [
          { text: '安全与回滚', link: '/docs/security-rollback' },
          { text: '更新与卸载', link: '/docs/update-uninstall' },
          { text: '常见问题', link: '/docs/faq' }
        ]
      }
    ]
  },
  outline: { level: [2, 3] as [number, number], label: '本页目录' },
  docFooter: { prev: '上一页', next: '下一页' },
  lastUpdated: { text: '最后更新' },
  langMenuLabel: '切换语言',
  search: {
    provider: 'local' as const,
    options: {
      translations: {
        button: { buttonText: '搜索文档', buttonAriaLabel: '搜索文档' },
        modal: {
          displayDetails: '显示详细列表',
          resetButtonTitle: '清除搜索',
          backButtonTitle: '关闭搜索',
          noResultsText: '没有找到结果',
          footer: {
            selectText: '选择', selectKeyAriaLabel: '回车', navigateText: '切换',
            navigateUpKeyAriaLabel: '上箭头', navigateDownKeyAriaLabel: '下箭头',
            closeText: '关闭', closeKeyAriaLabel: 'ESC'
          }
        }
      }
    }
  },
  socialLinks
}

const enTheme = {
  siteTitle: 'VPS-Optimize',
  nav: [
    { text: 'Home', link: '/en/' },
    { text: 'Quick Start', link: '/en/quick-start' },
    {
      text: 'Documentation',
      items: [
        { text: 'Documentation Home', link: '/en/' },
        { text: 'Port 443 Reuse: Setup and Configuration', link: '/en/docs/443-single-entry' },
        { text: 'Port 443 Reuse: Standalone Subscription Tool Proxy', link: '/en/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
        { text: 'Security and Rollback', link: '/en/docs/security-rollback' },
        { text: 'FAQ', link: '/en/docs/faq' }
      ]
    },
    { text: 'GitHub', link: 'https://github.com/Chunlion/VPS-Optimize' }
  ],
  sidebar: {
    '/en/': [
      {
        text: 'Getting Started',
        items: [
          { text: 'Documentation Home', link: '/en/' },
          { text: 'Quick Start', link: '/en/quick-start' },
          { text: 'Before You Begin', link: '/en/docs/before-use' },
          { text: 'Supported Systems', link: '/en/docs/supported-systems' }
        ]
      },
      {
        text: 'Port 443 Reuse',
        items: [
          { text: 'Setup and Configuration', link: '/en/docs/443-single-entry' },
          { text: 'Standalone Subscription Tool Proxy', link: '/en/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
          { text: 'Entry Modes and Internals', link: '/en/docs/443-tcp-peek-engine' },
          { text: 'Troubleshooting and Recovery', link: '/en/docs/443-single-entry-troubleshooting' }
        ]
      },
      {
        text: 'Deployment Guides',
        items: [
          { text: 'Migrate an Existing Server', link: '/en/docs/existing-server-migration' },
          { text: 'Recovery and Rollback', link: '/en/docs/recovery-runbook' }
        ]
      },
      {
        text: 'Tools',
        items: [
          { text: 'Subscriptions and Nodes', link: '/en/docs/subscription-tools' },
          { text: 'Configuration Paths', link: '/en/docs/config-paths' },
          { text: 'dog.sh Traffic Monitor', link: '/en/docs/dog' },
          { text: 'x-ui Extension', link: '/en/docs/xui-custom-manager' },
          { text: 'Third-party Script Sources', link: '/en/docs/third-party-scripts' }
        ]
      },
      {
        text: 'Maintenance',
        items: [
          { text: 'Security and Rollback', link: '/en/docs/security-rollback' },
          { text: 'Update and Uninstall', link: '/en/docs/update-uninstall' },
          { text: 'FAQ', link: '/en/docs/faq' }
        ]
      }
    ]
  },
  outline: { level: [2, 3] as [number, number], label: 'On this page' },
  docFooter: { prev: 'Previous', next: 'Next' },
  lastUpdated: { text: 'Last updated' },
  langMenuLabel: 'Change language',
  search: { provider: 'local' as const },
  socialLinks
}

const ruTheme = {
  siteTitle: 'VPS-Optimize',
  nav: [
    { text: 'Главная', link: '/ru/' },
    { text: 'Быстрый старт', link: '/ru/quick-start' },
    {
      text: 'Документация',
      items: [
        { text: 'Главная документации', link: '/ru/' },
        { text: 'Порт 443: развёртывание и настройка', link: '/ru/docs/443-single-entry' },
        { text: 'Порт 443: прокси отдельного сервиса подписок', link: '/ru/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
        { text: 'Безопасность и откат', link: '/ru/docs/security-rollback' },
        { text: 'Частые вопросы', link: '/ru/docs/faq' }
      ]
    },
    { text: 'GitHub', link: 'https://github.com/Chunlion/VPS-Optimize' }
  ],
  sidebar: {
    '/ru/': [
      {
        text: 'Начало работы',
        items: [
          { text: 'Главная документации', link: '/ru/' },
          { text: 'Быстрый старт', link: '/ru/quick-start' },
          { text: 'Перед началом', link: '/ru/docs/before-use' },
          { text: 'Поддерживаемые системы', link: '/ru/docs/supported-systems' }
        ]
      },
      {
        text: 'Порт 443',
        items: [
          { text: 'Развёртывание и настройка', link: '/ru/docs/443-single-entry' },
          { text: 'Прокси отдельного сервиса подписок', link: '/ru/tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry' },
          { text: 'Режимы входа и принципы работы', link: '/ru/docs/443-tcp-peek-engine' },
          { text: 'Диагностика и восстановление', link: '/ru/docs/443-single-entry-troubleshooting' }
        ]
      },
      {
        text: 'Руководства',
        items: [
          { text: 'Миграция существующего сервера', link: '/ru/docs/existing-server-migration' },
          { text: 'Восстановление и откат', link: '/ru/docs/recovery-runbook' }
        ]
      },
      {
        text: 'Инструменты',
        items: [
          { text: 'Подписки и узлы', link: '/ru/docs/subscription-tools' },
          { text: 'Пути конфигурации', link: '/ru/docs/config-paths' },
          { text: 'Мониторинг трафика dog.sh', link: '/ru/docs/dog' },
          { text: 'Расширение x-ui', link: '/ru/docs/xui-custom-manager' },
          { text: 'Источники сторонних скриптов', link: '/ru/docs/third-party-scripts' }
        ]
      },
      {
        text: 'Обслуживание',
        items: [
          { text: 'Безопасность и откат', link: '/ru/docs/security-rollback' },
          { text: 'Обновление и удаление', link: '/ru/docs/update-uninstall' },
          { text: 'Частые вопросы', link: '/ru/docs/faq' }
        ]
      }
    ]
  },
  outline: { level: [2, 3] as [number, number], label: 'На этой странице' },
  docFooter: { prev: 'Назад', next: 'Далее' },
  lastUpdated: { text: 'Последнее обновление' },
  langMenuLabel: 'Сменить язык',
  search: { provider: 'local' as const },
  socialLinks
}

export default defineConfig({
  title: 'VPS-Optimize',
  description: '面向 VPS 初始化、系统优化、网络参数调整与服务器维护的脚本工具',
  base: '/VPS-Optimize/',
  cleanUrls: true,
  lastUpdated: true,
  locales: {
    root: {
      label: '简体中文',
      lang: 'zh-CN',
      title: 'VPS-Optimize',
      description: '面向 VPS 初始化、系统优化、网络参数调整与服务器维护的脚本工具',
      themeConfig: zhTheme
    },
    en: {
      label: 'English',
      lang: 'en-US',
      link: '/en/',
      title: 'VPS-Optimize',
      description: 'A Bash control panel for VPS setup, optimization, security, deployment, and maintenance',
      themeConfig: enTheme
    },
    ru: {
      label: 'Русский',
      lang: 'ru-RU',
      link: '/ru/',
      title: 'VPS-Optimize',
      description: 'Панель управления Bash для настройки, оптимизации, защиты и обслуживания VPS',
      themeConfig: ruTheme
    }
  },
  srcExclude: [
    'AGENTS.md',
    'CHANGELOG.md',
    'README.md',
    'src/**',
    '.github/**'
  ],
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/VPS-Optimize/favicon.svg' }],
    ['meta', { name: 'theme-color', content: '#f7fbff' }],
    ['meta', { name: 'referrer', content: 'strict-origin-when-cross-origin' }]
  ],
  markdown: {
    lineNumbers: true,
    theme: { light: 'github-light', dark: 'one-dark-pro' }
  }
})
