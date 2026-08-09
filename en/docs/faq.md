# FAQ

## When running the script, the prompt is not root

First switch to root:

```bash
sudo -i
```

Then rerun the script.

## Unable to connect after modifying the SSH port

First check whether the cloud provider's security group allows the new port. If the old SSH session is still there, do not close it.

```bash
ss -lntp | grep ssh
systemctl status ssh --no-pager || systemctl status sshd --no-pager
```

The SSH service name may be `ssh` or `sshd` in different releases.

## 443 The rear panel cannot be opened after Port 443 Reuse configuration.

Priority checks:

- Whether the single service corresponding to the current entry mode listens on the public port `443`.
- Whether the panel and subscription backends listen on local addresses.
- 3x-ui Panel certificate path has been cleared.
- Whether the web reverse proxy engine configuration passes the verification.
- Whether the cloud security group allows `443/tcp`.
- Whether the domain DNS is resolved to the current server.

For detailed troubleshooting, see [Port 443 Reuse Troubleshooting](443-single-entry-troubleshooting.md).

## Browser reports error when accessing internal port

443 In Port 443 Reuse mode, the browser only accesses the standard HTTPS address:

```text
https://panel.example.com/panel/
https://sub.example.com/
```

Do not access internal ports from the public internet:

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

## How to paste dynamic TCP parameters

Entrance:

```text
Main menu [10 Network and kernel tuning] -> [2 Dynamic TCP Parameter tuning]
```

After entering, follow the prompts to paste multiple lines of `sysctl` parameters. After pasting is completed, enter `EOF` in another line and press Enter to save.
