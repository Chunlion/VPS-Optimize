# VPS-Optimize

[Chinese](https://github.com/Chunlion/VPS-Optimize/blob/main/README.md) · [English](README.md) · [Russian](https://github.com/Chunlion/VPS-Optimize/blob/main/ru/README.md)

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE)
[![Release](https://img.shields.io/badge/Release-latest-blue.svg)](https://github.com/Chunlion/VPS-Optimize/releases/latest)

A Bash control panel for routine VPS administration. Use `cy` to handle system setup, security hardening, panel deployment, shared port 443, subscription tools, backup and rollback, and troubleshooting.

[Documentation](https://chunlion.github.io/VPS-Optimize/en/) · [Quick Start](quick-start.md) · [Shared Port 443](docs/443-single-entry.md)

## Quick Start

> Do not download the script through an untrusted GitHub proxy and run it as `root`.

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

The first run registers the global shortcut:

```bash
cy
```

On the first interactive run, the installer asks in English whether to use Simplified Chinese, English, or Russian. Press Enter for English. Change it later from main-menu item `[20 Interface language]`; the setting is stored in `/etc/vps-optimize/language.conf`.

## Supported Systems

| System | Status |
|---|---|
| Debian 11/12 | Recommended |
| Ubuntu 20.04/22.04/24.04 | Recommended |
| Rocky / Alma / CentOS Stream | Supported |
| Alpine | Unsupported |
| Older OpenVZ systems | Not recommended |

## What It Covers

| Area | Capabilities |
|---|---|
| System setup | Preflight checks, common tools, timezone, and basic BBR |
| Security hardening | SSH, public-key authentication, Fail2ban, firewall, and port concurrency limits |
| Panels and subscriptions | 3x-ui, S-UI, Sing-box, Xray, SublinkPro, Sub-Store, Dockge, and Komari |
| Forwarding and networking | Realm, Gost, FLVX, EasyTier, and Tailscale |
| Shared port 443 | Route Web services, panels, subscriptions, and nodes through public port `443` by SNI |
| Diagnostics and rollback | Service health, port 443 diagnostics, configuration backup, restore, and quarantine archives |

## Panel Preview

![VPS-Optimize panel preview](https://i.mji.rip/2026/06/03/50e5eac2e83fbf7ef15240e3fa8c693a.png)

## Documentation and Support

- [Quick Start](quick-start.md)
- [Shared Port 443 Troubleshooting and Recovery](docs/443-single-entry-troubleshooting.md)
- [Recovery and Rollback](docs/recovery-runbook.md)
- [Open an Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## License

Released under the [GNU General Public License v3.0](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE).
