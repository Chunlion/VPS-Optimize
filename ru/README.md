# VPS-Optimize

[Китайский](https://github.com/Chunlion/VPS-Optimize/blob/main/README.md) · [Английский](https://github.com/Chunlion/VPS-Optimize/blob/main/en/README.md) · [Русский](README.md)

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE)
[![Release](https://img.shields.io/badge/Release-latest-blue.svg)](https://github.com/Chunlion/VPS-Optimize/releases/latest)

Панель управления на Bash для повседневного администрирования VPS. Через `cy` можно выполнить первоначальную настройку системы, усиление безопасности, развёртывание панелей, настройку общего порта 443, сервисов подписок, резервного копирования, отката и диагностики неполадок.

[Документация](https://chunlion.github.io/VPS-Optimize/ru/) · [Быстрый старт](quick-start.md) · [Общий порт 443](docs/443-single-entry.md)

## Быстрый старт

> Не загружайте скрипт через недоверенный GitHub-прокси и не запускайте его от `root`.

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

При первом запуске регистрируется глобальная команда:

```bash
cy
```

При первом интерактивном запуске установщик на английском предложит выбрать упрощённый китайский, английский или русский язык. Нажмите Enter для английского. Позже язык можно изменить в пункте главного меню `[20 Язык интерфейса]`; настройка хранится в `/etc/vps-optimize/language.conf`.

## Поддерживаемые системы

| Система | Статус |
|---|---|
| Debian 11/12 | Рекомендуется |
| Ubuntu 20.04/22.04/24.04 | Рекомендуется |
| Rocky / Alma / CentOS Stream | Поддерживается |
| Alpine | Не поддерживается |
| Старые системы OpenVZ | Не рекомендуется |

## Возможности

| Раздел | Возможности |
|---|---|
| Настройка системы | Предварительная проверка, базовые инструменты, часовой пояс и базовый BBR |
| Усиление безопасности | SSH, аутентификация по открытому ключу, Fail2ban, межсетевой экран и ограничения соединений по портам |
| Панели и подписки | 3x-ui, S-UI, Sing-box, Xray, SublinkPro, Sub-Store, Dockge и Komari |
| Перенаправление и сети | Realm, Gost, FLVX, EasyTier и Tailscale |
| Общий порт 443 | Маршрутизация Web-сервисов, панелей, подписок и узлов через публичный порт `443` по SNI |
| Диагностика и откат | Состояние служб, диагностика порта 443, резервное копирование, восстановление и изолированные архивы |

## Предпросмотр панели

![Предпросмотр панели VPS-Optimize](https://i.mji.rip/2026/06/03/50e5eac2e83fbf7ef15240e3fa8c693a.png)

## Документация и поддержка

- [Быстрый старт](quick-start.md)
- [Диагностика и восстановление общего порта 443](docs/443-single-entry-troubleshooting.md)
- [Восстановление и откат](docs/recovery-runbook.md)
- [Создать Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## Лицензия

Проект распространяется по лицензии [GNU General Public License v3.0](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE).
