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
  Bash-панель для повседневного администрирования VPS. Команда <code>cy</code> запускает настройку системы, усиление безопасности, развёртывание панелей и сервисов подписок, повторное использование порта 443, резервное копирование, откат и диагностику неполадок.
</p>

<p align="center">
  <a href="https://chunlion.github.io/VPS-Optimize/ru/">📚 Документация</a> · <a href="https://chunlion.github.io/VPS-Optimize/ru/quick-start">Быстрый старт</a> · <a href="https://chunlion.github.io/VPS-Optimize/ru/docs/443-single-entry">Порт 443: развёртывание и настройка</a>
</p>

## 🚀 Быстрый старт

> ⚠️ Загружайте скрипт только из этого репозитория или через доверенное зеркало. Не используйте неизвестные прокси ускорения.

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

Если GitHub недоступен напрямую, выберите зеркало самостоятельно. В примере используется `ghfast.top`:

```bash
wget -qO vps.sh https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

По умолчанию сценарий подключается к GitHub напрямую. На машинах без доступа к GitHub сохраните рабочее зеркало в `[9 Системные настройки и очистка] -> [10 Зеркало обновлений GitHub]`: через него идёт самообновление сценария, а другие установщики с GitHub автоматически повторяют загрузку через зеркало при ошибке прямого доступа. Инструмент смены зеркал пакетов загружается с официального сайта LinuxMirrors (linuxmirrors.cn) и не зависит от GitHub. Настройка хранится в `/etc/vps-optimize/update-mirror.conf` и сохраняется при обновлении. Введите `-` в том же меню, чтобы вернуться к прямому доступу. Чтобы заменить старый `cy`, запустите новый сценарий, при необходимости настройте зеркало, затем выберите `[17 Обновить скрипт]`.

При первом запуске регистрируется глобальная команда:

```bash
cy
```

При первом интерактивном запуске установщик на английском предложит выбрать упрощённый китайский, английский или русский язык. Нажмите Enter для английского. Позже язык можно изменить в пункте главного меню `[20 Язык интерфейса]`; настройка хранится в `/etc/vps-optimize/language.conf`.

### Команды главного меню

Команды не зависят от регистра и равнозначны выбору соответствующего номера главного меню. Последующие подтверждения при этом не пропускаются.

| Команда | Пункт главного меню |
|---|---|
| `proxy` | `[4 Обратный прокси]` |
| `panel` | `[5 Панели, узлы и инструменты подписки]` |
| `ssh` | `[6 Центр безопасности SSH]` |
| `firewall` | `[8 Управление брандмауэром]` |
| `bbr` | `[10 Оптимизация сети и ядра]` |
| `docker` | `[11 Управление Docker]` |
| `speed` | `[12 Тесты скорости и качества]` |
| `health` | `[15 Обзор состояния служб]` |
| `backup` | `[16 Резервное копирование и откат]` |
| `u` / `update` / `upd` | `[17 Обновить скрипт]` |
| `443` | `[19 Повторное использование порта 443]` |
| `lang` | `[20 Язык интерфейса]` |

## 🖥️ Поддерживаемые системы

| Система | Статус |
|---|---|
| Debian 11/12/13 | Рекомендуется |
| Ubuntu 20.04/22.04/24.04 | Рекомендуется |
| Rocky / Alma / CentOS Stream | Поддерживается |
| Alpine | Не поддерживается |
| Старые системы OpenVZ | Не рекомендуется |

## 🧰 Возможности

| Раздел | Возможности |
|---|---|
| Настройка системы | Предварительная проверка, базовые инструменты, часовой пояс, приоритет исходящего IPv4, базовый BBR и смена зеркала пакетов |
| Усиление безопасности | SSH, аутентификация по открытому ключу, Fail2ban, межсетевой экран и ограничения соединений по портам |
| Панели и подписки | 3x-ui, S-UI, 2S-UI, 3m-ui, Miaomiaowu, MiaomiaowuX, Sing-box, Xray, ретранслятор Xray (xray-relay), SublinkPro, Sub-Store, Dockge, Komari и CDT Monitor |
| Перенаправление и сети | Realm, Gost, FLVX, EasyTier и Tailscale |
| Повторное использование порта 443 | Web-сервисы, панель, подписки и узлы используют общий публичный порт `443`; Nginx Stream/TCP Peek маршрутизируют по SNI, узлы XHTTP могут делить Web-домен по пути, Xray Fallback использует основной вход Xray |
| Диагностика и откат | Состояние служб, диагностика порта 443, проверка свободного места, дополнительное шифрование копий, восстановление и карантин архивов |

Смена зеркала: `Главное меню [9 Системные настройки и очистка] -> [9 Сменить зеркало пакетов]`. Выберите материковый Китай, Азию, Европу, Северную или Южную Америку, Океанию либо Африку, затем конкретное зеркало. Зеркала без пакетов для текущего дистрибутива скрываются. Свой адрес доступен как дополнительная настройка. Инструмент [LinuxMirrors](https://linuxmirrors.cn/use/) загружается через настроенное зеркало GitHub. Меняются только источники системных пакетов без обновления пакетов. Источники GitHub, Docker и pip/npm настраиваются отдельно; скорость зависит от сетевого маршрута сервера.

## 📚 Документация и поддержка

- [Быстрый старт](https://chunlion.github.io/VPS-Optimize/ru/quick-start)
- [Порт 443: развёртывание и настройка](https://chunlion.github.io/VPS-Optimize/ru/docs/443-single-entry)
- [Порт 443: REALITY и XHTTP вместе](https://chunlion.github.io/VPS-Optimize/ru/tutorials/03-xhttp-reality-shared-443)
- [Диагностика и восстановление повторного использования порта 443](https://chunlion.github.io/VPS-Optimize/ru/docs/443-single-entry-troubleshooting)
- [Восстановление и откат](https://chunlion.github.io/VPS-Optimize/ru/docs/recovery-runbook)
- [CDT Monitor: трафик Alibaba Cloud CDT и управление ECS](https://chunlion.github.io/VPS-Optimize/ru/docs/cdt-monitor)
- [Создать Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## 📄 Лицензия

Проект распространяется по лицензии [GNU General Public License v3.0](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE).
