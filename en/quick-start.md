# Quick Start

VPS-Optimize is a Bash-based control panel for routine VPS administration. It covers new-server setup, system and network tuning, basic security, node deployment, and common troubleshooting.

The script can change SSH and firewall settings, kernel parameters, Nginx/Caddy and Docker configuration, certificates, and Port 443 Reuse services. Before running it, create a VPS snapshot, keep the current SSH session open, and make sure your cloud provider's security group allows the SSH port.

## Before You Begin

- Create a VPS snapshot.
- Keep the current SSH session open.
- Allow the SSH port in the cloud provider's security group.
- Point the required DNS records to this VPS.
- If you use Cloudflare, keep the relevant records in DNS-only mode.
- Prepare a Cloudflare API token when certificate automation is required.
- Confirm that the server runs a supported operating system.

## Installation in Mainland China

```bash
wget -qO vps.sh https://ghfast.top/https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh &&./vps.sh
```

## Direct Installation

```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh &&./vps.sh
```

## Shortcut Command

After the first run, use the global shortcut:

```bash
cy
```

## Interface Language

On the first interactive run, before any language has been saved, the installer asks you to choose a language in English:

```text
Select interface language:
  1. English
  2. 简体中文 (Simplified Chinese)
  3. Русский (Russian)
```

Press Enter to select English by default. You can change the language later from main-menu item `[20 Interface language]`. The selection is saved in `/etc/vps-optimize/language.conf`. For one run only, set `VPSO_LANG=zh`, `VPSO_LANG=en`, or `VPSO_LANG=ru` before the command.

## Supported Systems

| System | Status | Notes |
|---|---|---|
| Debian 11/12/13 | Recommended | Well supported |
| Ubuntu 20.04/22.04/24.04 | Recommended | Well supported |
| Rocky/Alma/CentOS Stream | Supported | Some components depend on configured repositories |
| Alpine | Unsupported | Do not run the script |
| Older OpenVZ systems | Not recommended | Required kernel features may be unavailable |

## Continue Reading

| Goal | Documentation |
|---|---|
| Deploy or configure Port 443 Reuse | [Port 443 Reuse: Setup and Configuration](docs/443-single-entry.md) |
| Publish subscription tools | [Subscription Tools on Port 443](tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md) |
| Monitor port traffic | [dog.sh Traffic Monitor](docs/dog.md) |
| Use the x-ui extension | [x-ui Extension](docs/xui-custom-manager.md) |
| Troubleshoot port 443 | [Port 443 Troubleshooting](docs/443-single-entry-troubleshooting.md) |
| Recover from a lockout or bad change | [Recovery and Rollback](docs/recovery-runbook.md) |
