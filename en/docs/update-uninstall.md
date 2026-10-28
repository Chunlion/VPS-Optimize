# Update and uninstall

## update script

It is recommended to update via the script menu:

```text
17. Update script
```

The main menu caches the remote version. After discovering a new version, enter `u`, `update` or `upd` to enter the update process.

The built-in update will first perform a syntax check and then download the verification file; if the verification fails, the current `cy` command will not be overwritten.

## GitHub update mirror

The script connects to GitHub directly by default. On machines that cannot reach GitHub, save a working mirror at `[9 System settings and cleanup] -> [10 GitHub update mirror]`: script self-updates use it, and other GitHub-hosted installers automatically retry through it when direct access fails.

- The setting is stored in `/etc/vps-optimize/update-mirror.conf` and survives updates.
- Enter `-` in the same menu to restore direct access.
- The package mirror tool is downloaded from the official LinuxMirrors site (linuxmirrors.cn) first; when a mirror is configured, that mirror is tried first, then the official site and GitHub.
- To replace an older `cy`, run the new script, configure a mirror if needed, then select `[17 Update script]`.

## Manual update

Run as `root`. These commands check the download, reject an empty file, and check Bash syntax. Use the menu update for full verification. Installation stops if any check fails.

```bash
(
  tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh) || exit 1
  trap 'rm -f "$tmp_file"' EXIT
  wget -qO "$tmp_file" https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh &&
    test -s "$tmp_file" &&
    bash -n "$tmp_file" &&
    install -m 755 "$tmp_file" /usr/local/bin/cy
) && cy
```

## Uninstall shortcut command

```bash
rm -f /usr/local/bin/cy
```

This will only delete the shortcut command and will not automatically restore the system configuration that has been modified by the script. System services, Nginx/Caddy configuration, firewall rules, Docker configuration, certificates and kernel parameters need to be rolled back individually according to actual conditions.
