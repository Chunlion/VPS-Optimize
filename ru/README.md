# ⚡ VPS-Optimize

<p align="center">
  <a href="../README.md">Китайский</a> · <a href="../en/README.md">Английский</a> · <a href="README.md">🌐 Русский</a>
</p>

<p align="center">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&amp;logoColor=white">
  <a href="../LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPLv3-blue.svg"></a>
  <a href="https://github.com/Chunlion/VPS-Optimize/releases/latest"><img alt="Release" src="https://img.shields.io/badge/Release-latest-blue.svg"></a>
</p>

<p align="center">
  Панель управления на Bash для повседневного администрирования VPS. Через <code>cy</code> можно выполнить первоначальную настройку системы, усиление безопасности, развёртывание панелей, настройку повторного использования порта 443, сервисов подписок, резервного копирования, отката и диагностики неполадок.
</p>

<p align="center">
  <a href="https://chunlion.github.io/VPS-Optimize/ru/">📚 Документация</a> · <a href="https://chunlion.github.io/VPS-Optimize/ru/quick-start">Быстрый старт</a> · <a href="https://chunlion.github.io/VPS-Optimize/ru/docs/443-single-entry">Повторное использование порта 443</a>
</p>

## 🚀 Быстрый старт

> ⚠️ Не загружайте скрипт через недоверенный GitHub-прокси и не запускайте его от `root`.

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

При первом запуске регистрируется глобальная команда:

```bash
cy
```

При первом интерактивном запуске установщик на английском предложит выбрать упрощённый китайский, английский или русский язык. Нажмите Enter для английского. Позже язык можно изменить в пункте главного меню `[20 Язык интерфейса]`; настройка хранится в `/etc/vps-optimize/language.conf`.

## 🖥️ Поддерживаемые системы

| Система | Статус |
|---|---|
| Debian 11/12 | Рекомендуется |
| Ubuntu 20.04/22.04/24.04 | Рекомендуется |
| Rocky / Alma / CentOS Stream | Поддерживается |
| Alpine | Не поддерживается |
| Старые системы OpenVZ | Не рекомендуется |

## 🧰 Возможности

| Раздел | Возможности |
|---|---|
| Настройка системы | Предварительная проверка, базовые инструменты, часовой пояс и базовый BBR |
| Усиление безопасности | SSH, аутентификация по открытому ключу, Fail2ban, межсетевой экран и ограничения соединений по портам |
| Панели и подписки | 3x-ui, S-UI, Sing-box, Xray, SublinkPro, Sub-Store, Dockge и Komari |
| Перенаправление и сети | Realm, Gost, FLVX, EasyTier и Tailscale |
| Повторное использование порта 443 | Маршрутизация Web-сервисов, панелей, подписок и узлов через публичный порт `443` по SNI |
| Диагностика и откат | Состояние служб, диагностика порта 443, резервное копирование, восстановление и изолированные архивы |

## 📚 Документация и поддержка

- [Быстрый старт](https://chunlion.github.io/VPS-Optimize/ru/quick-start)
- [Диагностика и восстановление повторного использования порта 443](https://chunlion.github.io/VPS-Optimize/ru/docs/443-single-entry-troubleshooting)
- [Восстановление и откат](https://chunlion.github.io/VPS-Optimize/ru/docs/recovery-runbook)
- [Создать Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## 📄 Лицензия

Проект распространяется по лицензии [GNU General Public License v3.0](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE).
