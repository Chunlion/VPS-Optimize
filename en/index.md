---
layout: home

hero:
  eyebrow: Built for ongoing maintenance
  name: VPS-Optimize
  text: From first setup to ongoing VPS maintenance
  tagline: Detect, back up, optimize, verify, and roll back through one clear workflow.
  image:
    light: /assets/entry-routing-en.webp
    dark: /assets/entry-routing-en-dark.webp
    alt: Port 443 routed through VPS-Optimize to Web, Xray, and TCP Peek
    caption: One public ingress · Shared configuration · Visible status
  actions:
    - theme: brand
      text: View the Workflow
      link: /en/quick-start
    - theme: alt
      text: Source Code
      link: https://github.com/Chunlion/VPS-Optimize

workflow:
  label: VPS-Optimize maintenance workflow
  steps:
    - icon: fa-solid fa-magnifying-glass
      title: Detect
      details: Check the system, network, and services for potential issues.
    - icon: fa-solid fa-database
      title: Back up
      details: Save critical configuration and keep a recovery path.
    - icon: fa-solid fa-bolt
      title: Optimize
      details: Adjust the system and network only where needed.
    - icon: fa-solid fa-shield-halved
      title: Verify
      details: Confirm service availability and the result of each change.
    - icon: fa-solid fa-rotate-left
      title: Roll back
      details: Restore saved configuration when a change fails.

story:
  kicker: Project approach
  title: Maintenance is not a one-time task
  description: VPS-Optimize combines detection, backup, changes, verification, and rollback in one workflow while keeping key status and logs visible for ongoing maintenance.
  principles:
    - icon: fa-solid fa-list-check
      title: Standard workflow
      text: Consistent steps and output
    - icon: fa-solid fa-shield-halved
      title: Controlled changes
      text: Backups before critical updates
    - icon: fa-solid fa-chart-column
      title: Visible state
      text: Key status and logs together
  terminalLabel: VPS-Optimize status example
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
  primaryText: Keep a recovery path before changing critical configuration.
  secondaryIcon: fa-regular fa-clock
  secondaryTitle: Clearer diagnosis
  secondaryText: Review checks and service state in one place when problems occur.
---
