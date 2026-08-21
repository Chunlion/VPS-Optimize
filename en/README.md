# ⚡ VPS-Optimize

<p align="center">
  <a href="../README.md">Chinese</a> · <a href="README.md">🌐 English</a> · <a href="../ru/README.md">Russian</a>
</p>

<p align="center">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&amp;logoColor=white">
  <a href="../LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPLv3-blue.svg"></a>
  <a href="https://github.com/Chunlion/VPS-Optimize/releases/latest"><img alt="Release" src="https://img.shields.io/badge/Release-latest-blue.svg"></a>
</p>

<p align="center">
  A Bash control panel for day-to-day VPS operations. Use <code>cy</code> for system setup, security hardening, panel and subscription-tool deployment, Port 443 Reuse, backup and rollback, and troubleshooting.
</p>

<p align="center">
  <a href="https://chunlion.github.io/VPS-Optimize/en/">📚 Documentation</a> · <a href="https://chunlion.github.io/VPS-Optimize/en/quick-start">Quick Start</a> · <a href="https://chunlion.github.io/VPS-Optimize/en/docs/443-single-entry">Port 443 Reuse: Setup and Configuration</a>
</p>

## 🚀 Quick Start

> ⚠️ Download the script from this repository or GitHub Raw. Do not run a file obtained through an untrusted GitHub proxy as `root`.

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

The first run registers the global shortcut:

```bash
cy
```

On the first interactive run, the installer asks in English whether to use Simplified Chinese, English, or Russian. Press Enter for English. Change it later from main-menu item `[20 Interface language]`; the setting is stored in `/etc/vps-optimize/language.conf`.

### Main-menu shortcuts

Shortcuts are case-insensitive and behave like selecting the corresponding main-menu number. They do not bypass later confirmations.

| Shortcut | Main-menu item |
|---|---|
| `proxy` | `[4 Reverse proxy]` |
| `panel` | `[5 Panels, nodes, subscriptions]` |
| `ssh` | `[6 SSH security center]` |
| `firewall` | `[8 Firewall rules]` |
| `bbr` | `[10 Network and kernel tuning]` |
| `docker` | `[11 Docker security management]` |
| `speed` | `[12 Speed and quality tests]` |
| `health` | `[15 Service health overview]` |
| `backup` | `[16 Configuration backup]` |
| `u` / `update` / `upd` | `[17 Update script]` |
| `443` | `[19 Port 443 Reuse manager]` |
| `lang` | `[20 Interface language]` |

## 🖥️ Supported Systems

| System | Status |
|---|---|
| Debian 11/12/13 | Recommended |
| Ubuntu 20.04/22.04/24.04 | Recommended |
| Rocky / Alma / CentOS Stream | Supported |
| Alpine | Unsupported |
| Older OpenVZ systems | Not recommended |

## 🧰 What It Covers

| Area | Capabilities |
|---|---|
| System setup | Preflight checks, common tools, timezone, and basic BBR |
| Security hardening | SSH, public-key authentication, Fail2ban, firewall, and port concurrency limits |
| Panels and subscriptions | 3x-ui, S-UI, Sing-box, Xray, SublinkPro, Sub-Store, Dockge, and Komari |
| Forwarding and networking | Realm, Gost, FLVX, EasyTier, and Tailscale |
| Port 443 Reuse | Route Web services, panels, subscriptions, and nodes through public port `443` by SNI; only the active entry service listens on that port |
| Diagnostics and rollback | Service health, port 443 diagnostics, space checks, optional encrypted backups, restore, and quarantine archives |

## 📚 Documentation and Support

- [Quick Start](https://chunlion.github.io/VPS-Optimize/en/quick-start)
- [Port 443 Reuse: Setup and Configuration](https://chunlion.github.io/VPS-Optimize/en/docs/443-single-entry)
- [Port 443 Reuse Troubleshooting and Recovery](https://chunlion.github.io/VPS-Optimize/en/docs/443-single-entry-troubleshooting)
- [Recovery and Rollback](https://chunlion.github.io/VPS-Optimize/en/docs/recovery-runbook)
- [Open an Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## 📄 License

Released under the [GNU General Public License v3.0](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE).
