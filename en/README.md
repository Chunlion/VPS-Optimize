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

> ⚠️ Download the script only from this repository or a mirror you trust. Avoid unknown acceleration proxies.

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
```

If GitHub is unreachable directly, choose a mirror yourself. This example uses `ghfast.top`:

```bash
wget -qO vps.sh https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh
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
| `panel` | `[5 Panels, nodes, and subscription tools]` |
| `ssh` | `[6 SSH security center]` |
| `firewall` | `[8 Firewall rules]` |
| `bbr` | `[10 Network and kernel optimization]` |
| `docker` | `[11 Docker management]` |
| `speed` | `[12 Speed and quality tests]` |
| `health` | `[15 Service health overview]` |
| `backup` | `[16 Configuration backup and rollback]` |
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
| System setup | Preflight checks, common tools, timezone, IPv4 outbound preference, basic BBR, and package mirror switching |
| Security hardening | SSH, public-key authentication, Fail2ban, firewall, and port concurrency limits |
| Panels and subscriptions | 3x-ui, S-UI, 2S-UI, 3m-ui, Miaomiaowu, MiaomiaowuX, Sing-box, Xray, Xray relay (xray-relay), SublinkPro, Sub-Store, Dockge, Komari, and CDT Monitor |
| Forwarding and networking | Realm, Gost, FLVX, EasyTier, and Tailscale |
| Port 443 Reuse | Share public port `443` across Web services, panels, subscriptions, and nodes; Nginx Stream/TCP Peek route by SNI, XHTTP nodes can share a Web domain by path, while Xray Fallback uses the Xray main inbound |
| Diagnostics and rollback | Service health, port 443 diagnostics, space checks, optional encrypted backups, restore, and quarantine archives |

Mirror selection: `Main menu [9 System settings and cleanup] -> [9 Switch package mirrors]`. Choose mainland China, Asia, Europe, North America, South America, Oceania, or Africa, then select a mirror. Mirrors that do not serve the current distribution are hidden. Custom addresses are an advanced option. The [LinuxMirrors](https://linuxmirrors.cn/use/) tool is downloaded through the configured GitHub mirror. This changes system package sources without upgrading packages. GitHub, Docker, and pip/npm sources are configured separately; download speed depends on the server's network route.

## 📚 Documentation and Support

- [Quick Start](https://chunlion.github.io/VPS-Optimize/en/quick-start)
- [Port 443 Reuse: Setup and Configuration](https://chunlion.github.io/VPS-Optimize/en/docs/443-single-entry)
- [Port 443 Reuse: REALITY and XHTTP Together](https://chunlion.github.io/VPS-Optimize/en/tutorials/03-xhttp-reality-shared-443)
- [Port 443 Reuse Troubleshooting and Recovery](https://chunlion.github.io/VPS-Optimize/en/docs/443-single-entry-troubleshooting)
- [Recovery and Rollback](https://chunlion.github.io/VPS-Optimize/en/docs/recovery-runbook)
- [CDT Monitor: Alibaba Cloud CDT Traffic and ECS Management](https://chunlion.github.io/VPS-Optimize/en/docs/cdt-monitor)
- [Open an Issue](https://github.com/Chunlion/VPS-Optimize/issues) · [Telegram](https://t.me/cutyy_github) · [GitHub](https://github.com/Chunlion)

## 📄 License

Released under the [GNU General Public License v3.0](https://github.com/Chunlion/VPS-Optimize/blob/main/LICENSE).
