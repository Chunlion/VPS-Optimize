---
layout: home

hero:
  eyebrow: Для регулярного обслуживания
  name: VPS-Optimize
  text: От первой настройки до регулярного обслуживания VPS
  tagline: Проверка, резервное копирование, оптимизация, контроль и откат в одном понятном процессе.
  image:
    light: /assets/entry-routing-ru.webp
    dark: /assets/entry-routing-ru-dark.webp
    alt: Маршрутизация порта 443 через VPS-Optimize к Web, Xray и TCP Peek
    caption: Один внешний вход · Общая конфигурация · Видимое состояние
  actions:
    - theme: brand
      text: Посмотреть порядок работы
      link: /ru/quick-start
    - theme: alt
      text: Исходный код
      link: https://github.com/Chunlion/VPS-Optimize

workflow:
  label: Процесс обслуживания VPS-Optimize
  steps:
    - icon: fa-solid fa-magnifying-glass
      title: Проверка
      details: Проверка системы, сети и служб для поиска возможных проблем.
    - icon: fa-solid fa-database
      title: Резервная копия
      details: Сохранение важных настроек и пути восстановления.
    - icon: fa-solid fa-bolt
      title: Оптимизация
      details: Изменение только необходимых параметров системы и сети.
    - icon: fa-solid fa-shield-halved
      title: Контроль
      details: Проверка доступности служб и результата изменений.
    - icon: fa-solid fa-rotate-left
      title: Откат
      details: Восстановление сохранённых настроек при сбое.

story:
  kicker: Подход проекта
  title: Обслуживание — не разовая задача
  description: VPS-Optimize объединяет проверку, резервное копирование, изменения, контроль и откат в одном процессе, сохраняя важные состояния и журналы для регулярного обслуживания.
  principles:
    - icon: fa-solid fa-list-check
      title: Единый процесс
      text: Последовательные действия и вывод
    - icon: fa-solid fa-shield-halved
      title: Контроль изменений
      text: Резервная копия до важных операций
    - icon: fa-solid fa-chart-column
      title: Видимое состояние
      text: Статус и журналы в одном месте
  terminalLabel: Пример состояния VPS-Optimize
  terminalHeader: Компонент / Состояние
  terminalRows:
    - label: Системное окружение
      value: Норма
    - label: Резервная копия
      value: Доступна
    - label: Единый порт 443
      value: Работает
    - label: Основные службы
      value: Работают
    - label: Межсетевой экран
      value: Включён
  primaryIcon: fa-solid fa-shield-halved
  primaryTitle: Надёжнее
  primaryText: Перед изменением важных настроек сохраняется путь восстановления.
  secondaryIcon: fa-regular fa-clock
  secondaryTitle: Понятнее
  secondaryText: Результаты проверок и состояние служб собраны в одном месте.
---
