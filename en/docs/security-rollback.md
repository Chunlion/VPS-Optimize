# Security and rollback

High-risk functions will ask for `YES`. When in doubt, create a backup before performing modifications.

## Backup scope

The menu supports three scopes: script and service configuration, custom system directories, or both. The configuration backup covers SSH, host name, Nginx/Caddy, Port 443 Reuse, DNS, certificates, Cloudflare Token, Docker daemon configuration, Fail2ban, sysctl, and key 3x-ui configuration where available.

Enter one absolute custom directory per line and leave a blank line to finish. For example: `/etc`, `/usr`, `/home`, and `/opt/app-data`. `/`, `/proc`, `/sys`, `/dev`, `/run`, and `/tmp` are not supported. Stop related services before backing up database or Docker data directories; file copying does not guarantee consistency for active data.

When restoring top-level directories such as `/etc`, `/usr`, or `/home`, matching backed-up content is overwritten; existing files absent from the backup are not removed.

The archive can be saved to a chosen absolute directory; the default is `/etc/vps-optimize/backups/manual/`. Its full path is shown and it is loaded after creation; the selected directory is recorded, and menu `[16] -> [2]` automatically reads `.tar.gz` archives there as well as in `/backups` and `/root/backups`. For example, `/backups/etc_usr_home_20260809165222.tar.gz` appears directly in the list. It does not include Docker volumes, container business data, images, or complete firewall runtime state, and cannot replace VPS snapshots.

On a new system, use `[16] -> [2]` to load an archive, then restore it with `[3] -> [1]`; menu `[3]` can also restore from the automatic list or a specified `.tar.gz` path. The script checks for Nginx, Caddy, Docker, and 3x-ui first. Missing services are not installed automatically; install and start them after restoring the files.

The backup may contain private keys, panel database and API Token, please do not share them publicly.

## Common entrance

```text
Main menu [16 Configuration backup and rollback]
```

Common operations:

- Create a configuration backup, custom-directory backup, or both.
- Automatically read and load existing `.tar.gz` backup archives.
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
