# x-ui Extension Guide


## Functional positioning

`xui-custom-manager.sh` is a x-ui enhancement suite script and does not replace the 3x-ui program, nor is it the 3x-ui panel itself. It is used to supplement some maintenance functions more suitable for scripting:

- Custom traffic reset date.
- Inbound individual reset day.
- Client reset date individually.
- Preview `reset-check`.
- Flow calibration.
- Database backup/restore.
- Configuration directory and program directory backup/restore.
- `systemd timer` automatic check.
- Health checks, log viewing and old backup cleaning.

Important risk: this tool supports SQLite deployments only and directly reads and writes the 3x-ui SQLite database at `/etc/x-ui/x-ui.db`. Create a VPS snapshot and back up the database before any write.

## Version compatibility boundary

Supports SQLite-based 3x-ui 2.9.x and 3.x. Before writing to the database, the read-only schema check must pass and the required tables and fields must be unchanged.

PostgreSQL is not supported. Do not use this tool to read or write the 3x-ui database when `XUI_DB_TYPE` in `/etc/default/x-ui`, `/etc/sysconfig/x-ui`, or `/etc/conf.d/x-ui` is `postgres`, `postgresql`, or `pg`.

Other 3x-ui versions are not supported. When the version is not in the supported range or the schema check fails, it is only recommended to execute:

- Backup.
- View configuration.
- Health check.
- Preview.
- Self-check.

Don't force-write the library, skipping version ranges and schema checks. If the script prompts that the current version is not supported or the database fields are incompatible, stop writing the database and retain the backup and diagnostic information first.

## What you need to do before running

1. Create a VPS snapshot.
2. Confirm that SQLite is in use, then back up `/etc/x-ui/x-ui.db`.
3. Confirm that the current 3x-ui version belongs to 2.9.x or 3.x.
4. Confirm that the relevant inbound native `monthly` reset in the 3x-ui panel is turned off, or changed to `never` / no reset.
5. Preserve the current SSH session.
6. Perform a preview first, do not perform a real reset directly.
7. If you have just manually edited the database, perform a preview and self-check first to confirm that the configuration is compatible with the fields.

## Run quickly

Run as `root` on the server:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh)
```

The script requires `root` permissions because it accesses the `/etc/x-ui`, backup directory, log directory, and systemd unit. Shortcut commands will be registered after opening for the first time:

```bash
xcm
```

Commonly used commands:

```bash
xcm
bash /usr/local/bin/xui-custom-manager.sh --reset-check --dry-run
bash /usr/local/bin/xui-custom-manager.sh --self-test
```

## Custom reset logic

Custom reset is controlled by `/etc/xui-custom-reset.json`, the core concept is as follows:

- Global Enable/Disable: When globally off, the automatic check skips the real reset.
- Default reset date: Inbounds without separate settings can use the default date.
- Inbound individual reset day: You can set the day of the month for a certain inbound reset.
- Client independent reset date: You can set an independent date for a client.
- Whether clients whose dates are not set individually follow the inbound: controlled by the corresponding inbound rules.
- Whether the inbound self `up/down` is reset: controlled by the corresponding inbound rules.

Date range is 1-31. When the monthly date exceeds the number of days in the month, it will be processed as the last day of the month. For example, if the 31st is set, February will be processed as the last day of February.

When using an external custom reset, do not enable 3x-ui native `monthly` and external custom reset at the same time to avoid repeated resets or difficulty in determining the status.

## Writing library behavior description

Real execution will modify the used traffic field in the 3x-ui database:

- Inbound: `inbounds.up`, `inbounds.down`.
- Client: `client_traffics.up`, `client_traffics.down`.

Real execution will not modify the `total` traffic limit. The client will be re-enabled according to official logic. The script will write reset state to record whether it has been executed this month to avoid repeated resets in the same month.

The database will be automatically backed up before writing to the database. `x-ui` will be stopped and restarted during execution to reduce conflicts between database writes and service runs. Please check the log and panel status after execution.

Preview mode will not write to the database, stop or start `x-ui`, or write reset state.

## Flow Calibration Instructions

Flow calibration is used to manually modify the used flow rate in the database:

- Inbound calibration modifies `inbounds.up` / `inbounds.down`.
- Client calibration will modify `client_traffics.up` / `client_traffics.down`.

Calibration does not modify the `total` limit. Before writing, the script shows the values before and after the change and asks for confirmation; press Enter to continue or enter `n` to cancel. The database is backed up automatically before writing, and the script attempts to start `x-ui` afterward.

When the version is outside the supported range or the schema check fails, the use of real write library calibration is prohibited.

## automatic timer

When custom reset is enabled, the script installs or updates:

- `xui-custom-reset.service`
- `xui-custom-reset.timer`

The default timer is executed once every day at `00:10`:

```text
OnCalendar=*-*-* 00:10:00
```

service execution:

```text
/usr/bin/env bash /usr/local/bin/xui-custom-manager.sh --reset-check
```

View timer status:

```bash
systemctl status xui-custom-reset.timer --no-pager
```

View the automatic check log:

```bash
journalctl -u xui-custom-reset.service -n 100 --no-pager
tail -n 100 /var/log/xui-custom-manager.log
```

The timer can be enabled or disabled in the menu. The timer should not be automatically installed or enabled when the version is not supported or when the schema check fails.

## file path

| path | Description |
|---|---|
| `/etc/xui-custom-manager.conf` | External manager configuration profile |
| `/etc/xui-custom-reset.json` | Custom reset rule configuration |
| `/root/x-ui-backups` | Database, configuration directory, program directory backup directory |
| `/etc/x-ui/x-ui.db` | 3x-ui SQLite database |
| `/var/log/xui-custom-manager.log` | External manager log |
| `/var/lib/xui-custom-manager/reset-state.json` | Reset status file monthly |
| `/etc/systemd/system/xui-custom-reset.service` | Automatically check service |
| `/etc/systemd/system/xui-custom-reset.timer` | Automatically check timer |
| `/usr/local/bin/xui-custom-manager.sh` | local stable actuator |
| `/usr/local/bin/xcm` | Manual quick entry |

## Backup and recovery

Script supports backup:

- Database `/etc/x-ui/x-ui.db`.
- Configuration directory `/etc/x-ui`.
- Program directory `/usr/local/x-ui`.

The current state will be backed up again before recovery. Restoration will overwrite the current database, configuration directory or program directory, so before execution, you must confirm that the source of the backup file is reliable and retain VPS snapshots or other rollback means.

Old backup cleanup should only delete explicitly selected files. Do not delete backup directories in bulk.

## Troubleshooting

### Database does not exist

Confirm that 3x-ui uses SQLite and that the database path is `/etc/x-ui/x-ui.db`. For another SQLite file, override `XUI_DB` in `/etc/xui-custom-manager.conf`. PostgreSQL is not supported; never write an unverified schema.

### Database fields are incompatible

Stop writing to the library. Don't guess at field structure. You can perform backup, view, preview, self-test, and retain error output for troubleshooting.

### The current 3x-ui version is not supported

Do not execute the library writing function. It is only recommended to perform backup, viewing, preview and self-test. Do not forcibly enable the timer, and do not perform real `reset-check` or flow calibration writing to the library.

### timer is not running

Check:

```bash
systemctl status xui-custom-reset.timer --no-pager
systemctl list-timers | grep xui-custom-reset
```

After confirming that the current 3x-ui is 2.9.x or 3.x and the schema check passes, enable automatic checking from the menu.

### reset-check is not executed

Run preview first:

```bash
bash /usr/local/bin/xui-custom-manager.sh --reset-check --dry-run
```

Look at the log again:

```bash
journalctl -u xui-custom-reset.service -n 100 --no-pager
tail -n 100 /var/log/xui-custom-manager.log
```

### Configuration JSON is corrupted

Check whether `/etc/xui-custom-reset.json` is legal JSON. If damaged, first back up the current file and then restore from `/root/x-ui-backups` or VPS snapshot.

### Corrupted status file

The status file is `/var/lib/xui-custom-manager/reset-state.json`. Do not directly overwrite the production status when damaged. Back up the current file first, and then use the log and database to confirm whether a reset has been performed this month to avoid repeated resets.

### Failed to write library

Do not repeat the actual writing of the library. Check database permissions, field compatibility, disk space, whether `x-ui` can be stopped/started, and whether the backup file has been generated. Keep the logs before deciding whether to restore the backup.

### x-ui Restart failed

View service status and logs:

```bash
systemctl status x-ui --no-pager
journalctl -u x-ui -n 100 --no-pager
```

If a database backup has been generated before actual writing to the database, the backup can be restored based on the failure situation. Confirm before restoring that current data will be overwritten.

## Prohibited matters

- Do not perform the database write function without backing up the database.
- Don't force-write the library, skipping version ranges and schema checks.
- Do not enable 3x-ui native `monthly` and external custom reset at the same time.
- Do not run a real reset immediately after manually editing the database, perform a preview and self-test first.
- Do not test write functionality on a production machine without a VPS snapshot or database backup.
