# Security and rollback

High-risk functions will ask for `YES`. When in doubt, create a backup before performing modifications.

## Backup scope

"Full configuration backup" in the menu refers to the script management configuration backup, which will try to cover SSH, host name, Nginx/Caddy, Port 443 Reuse, DNS, certificate, Cloudflare Token, Docker daemon configuration, Fail2ban, sysctl and 3x-ui key configurations.

It does not include the Docker volume, container business data, images, and complete firewall operating status, and cannot replace VPS snapshots. The Compose project also needs to back up the data directory and volume separately.

The backup may contain private keys, panel database and API Token, please do not share them publicly.

## Common entrance

```text
Main menu [16 Configuration backup and rollback]
```

Common operations:

- Create a full configuration backup (script management configuration, not including complete business data).
- View a list of existing backups.
- One-click rollback from backup.
- View or edit the script's applied configuration.

## high risk operations

Before these operations, it is recommended to confirm the cloud security group, retain the current SSH session, and prepare a snapshot or rescue console:

- Modify the SSH port.
- Turn on key-only login.
- Modify firewall rules.
- Toggle 443 entry mode.
- Modify certificate and reverse proxy configuration.
- Enable traffic volume shutdown.

For complex troubleshooting, see [lockout and Rollback First Aid Manual](recovery-runbook.md).
