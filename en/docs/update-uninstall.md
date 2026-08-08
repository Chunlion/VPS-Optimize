# Update and uninstall

## update script

It is recommended to update via the script menu:

```text
17. Update script
```

The main menu caches the remote version. After discovering a new version, enter `u`, `update` or `upd` to enter the update process.

The built-in update will first perform a syntax check and then download the verification file; if the verification fails, the current `cy` command will not be overwritten.

## Manual update

```bash
tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh)
wget -qO "$tmp_file" https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh
bash -n "$tmp_file"
install -m 755 "$tmp_file" /usr/local/bin/cy
rm -f "$tmp_file"
cy
```

## Uninstall shortcut command

```bash
rm -f /usr/local/bin/cy
```

This will only delete the shortcut command and will not automatically restore the system configuration that has been modified by the script. System services, Nginx/Caddy configuration, firewall rules, Docker configuration, certificates and kernel parameters need to be rolled back individually according to actual conditions.
