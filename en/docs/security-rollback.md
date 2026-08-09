# Security and rollback

High-risk functions will ask for `YES`. When in doubt, create a backup before performing modifications.

## Backup scope

The menu supports three scopes: script and service configuration, custom system directories, or both. The configuration backup covers SSH, host name, Nginx/Caddy, Port 443 Reuse, DNS, certificates, Cloudflare Token, Docker daemon configuration, Fail2ban, sysctl, and key 3x-ui configuration where available.

Enter one absolute custom directory per line and leave a blank line to finish. For example: `/opt/app-data` and `/var/lib/myapp`. `/`, top-level directories, `/proc`, `/sys`, `/dev`, `/run`, and `/tmp` are not supported. Stop related services before backing up database or Docker data directories; file copying does not guarantee consistency for active data.

The archive can be saved to a chosen absolute directory; the default is `/etc/vps-optimize/backups/manual/`. It does not include Docker volumes, container business data, images, or complete firewall runtime state, and cannot replace VPS snapshots.

On a new system, use main menu `[16] -> [3]`, select the specified backup archive path, and enter a path such as `/root/backup_20260101_120000.tar.gz`. The script checks for Nginx, Caddy, Docker, and 3x-ui first. Missing services are not installed automatically; install and start them after restoring the files.

The backup may contain private keys, panel database and API Token, please do not share them publicly.

## Common entrance

```text
Main menu [16 Configuration backup and rollback]
```

Common operations:

- Create a configuration backup, custom-directory backup, or both.
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
