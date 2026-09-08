---
layout: home

hero:
  eyebrow: VPS setup & maintenance
  name: VPS-Optimize
  text: Set up with clarity. Maintain with confidence.
  tagline: System tuning, service deployment, and troubleshooting from one Bash menu. Choose what you need and back up before making changes.
  guide:
    title: One public port. Three entry modes.
    note: Only one mode runs at a time. Choose for your deployment.
    modes:
      - name: nginx-stream
        description: Nginx listens on 443 and forwards connections by SNI.
      - name: xray-fallback
        description: The main Xray inbound listens on 443 and handles fallbacks.
      - name: tcp-peek
        description: TCP Peek listens on 443, inspects and forwards connections.
    link: /en/docs/443-tcp-peek-engine
    action: Explore entry modes and configuration
  actions:
    - theme: brand
      text: Quick Start
      link: /en/quick-start
    - theme: alt
      text: Source Code
      link: https://github.com/Chunlion/VPS-Optimize

workflow:
  label: Suggested maintenance steps. Follow each link for guidance.
  steps:
    - icon: fa-solid fa-magnifying-glass
      title: Detect
      details: Check the system, network, and services for potential issues.
      link: /en/docs/before-use
    - icon: fa-solid fa-database
      title: Back up
      details: Save required configuration. Back up application data separately.
      link: /en/docs/security-rollback
    - icon: fa-solid fa-bolt
      title: Optimize
      details: Adjust the system and network only where needed.
      link: /en/quick-start
    - icon: fa-solid fa-shield-halved
      title: Verify
      details: Check service state and test actual access.
      link: /en/docs/faq
    - icon: fa-solid fa-rotate-left
      title: Roll back
      details: Restore what the backup covers, then check services.
      link: /en/docs/recovery-runbook

story:
  kicker: Changes & recovery
  title: Prepare a way back before making changes.
  description: Check services, back up configuration, and read logs from the menu. Restoration covers only saved content; it does not replace VPS snapshots or application backups.
  principles:
    - icon: fa-solid fa-list-check
      title: Choose actions
      text: Select what you need
    - icon: fa-solid fa-shield-halved
      title: Back up config
      text: Check backup coverage
    - icon: fa-solid fa-chart-column
      title: Diagnose issues
      text: Review status and logs
  terminalLabel: Example status · Not live data
  terminalHeader: Item / Status
  terminalRows:
    - label: System environment
      value: Healthy
    - label: Configuration backup
      value: Available
    - label: Port 443 Reuse
      value: Running
    - label: Key services
      value: Running
    - label: Firewall
      value: Enabled
  primaryIcon: fa-solid fa-shield-halved
  primaryTitle: Safer changes
  primaryText: Keep SSH open and prepare a snapshot and recovery access.
  secondaryIcon: fa-regular fa-clock
  secondaryTitle: Clearer diagnosis
  secondaryText: Review checks and service state in one place when problems occur.
---
