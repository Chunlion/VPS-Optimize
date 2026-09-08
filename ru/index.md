---
layout: home

hero:
  eyebrow: Настройка и обслуживание VPS
  name: VPS-Optimize
  text: Порядок в настройках. Ясность в обслуживании.
  tagline: Настройка системы и сети, развёртывание служб и диагностика из одного меню Bash. Выбирайте нужные действия и сохраняйте копию перед изменениями.
  guide:
    title: Один внешний порт. Три режима входа.
    note: Одновременно работает только один режим. Выберите подходящий для вашей схемы.
    modes:
      - name: nginx-stream
        description: Nginx слушает порт 443 и направляет соединения по SNI.
      - name: xray-fallback
        description: Основной вход Xray слушает порт 443 и обрабатывает fallback.
      - name: tcp-peek
        description: TCP Peek слушает порт 443, анализирует и направляет соединения.
    link: /ru/docs/443-tcp-peek-engine
    action: Режимы входа и настройка
  actions:
    - theme: brand
      text: Быстрый старт
      link: /ru/quick-start
    - theme: alt
      text: Исходный код
      link: https://github.com/Chunlion/VPS-Optimize

workflow:
  label: Рекомендуемые шаги обслуживания со ссылками на инструкции
  steps:
    - icon: fa-solid fa-magnifying-glass
      title: Проверка
      details: Проверка системы, сети и служб для поиска возможных проблем.
      link: /ru/docs/before-use
    - icon: fa-solid fa-database
      title: Резервная копия
      details: Сохраните настройки. Данные приложений копируйте отдельно.
      link: /ru/docs/security-rollback
    - icon: fa-solid fa-bolt
      title: Оптимизация
      details: Изменение только необходимых параметров системы и сети.
      link: /ru/quick-start
    - icon: fa-solid fa-shield-halved
      title: Контроль
      details: Проверьте состояние служб и фактическую доступность.
      link: /ru/docs/faq
    - icon: fa-solid fa-rotate-left
      title: Откат
      details: Восстановите сохранённые настройки и проверьте службы.
      link: /ru/docs/recovery-runbook

story:
  kicker: Изменения и восстановление
  title: Подготовьте путь назад до изменений.
  description: Проверяйте службы, сохраняйте настройки и читайте журналы из меню. Восстанавливается только содержимое копии; она не заменяет снимок VPS или копию данных приложений.
  principles:
    - icon: fa-solid fa-list-check
      title: Выбор действий
      text: Нужные функции в меню
    - icon: fa-solid fa-shield-halved
      title: Копия настроек
      text: Проверьте её состав
    - icon: fa-solid fa-chart-column
      title: Диагностика
      text: Состояние и журналы
  terminalLabel: Пример состояния · Не текущие данные
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
  primaryText: Сохраните сеанс SSH, подготовьте снимок VPS и доступ к восстановлению.
  secondaryIcon: fa-regular fa-clock
  secondaryTitle: Понятнее
  secondaryText: Результаты проверок и состояние служб собраны в одном месте.
---
