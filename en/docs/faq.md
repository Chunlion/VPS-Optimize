# FAQ

## The script requires root access

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

## The panel is unreachable after configuring port 443 sharing

Priority checks:

- Whether the single service corresponding to the current entry mode listens on the public port `443`.
- Whether the panel and subscription backends listen on local addresses.
- 3x-ui Panel certificate path has been cleared.
- Whether the web reverse proxy engine configuration passes the verification.
- Whether the cloud security group allows `443/tcp`.
- Whether the domain DNS is resolved to the current server.

For detailed troubleshooting, see [Port 443 Reuse Troubleshooting](443-single-entry-troubleshooting.md).

## Browser reports error when accessing internal port

In port 443 sharing mode, the browser only accesses the standard HTTPS address:

```text
https://panel.example.com/panel/
https://panel.example.com/sub/
```

A 3x-ui subscription uses the panel domain plus its URI path. Only standalone subscription tools such as SublinkPro or Sub-Store use their own domain, for example `https://tool.example.com/`. Do not access internal ports from the public internet:

```text
https://panel.example.com:8443/
https://panel.example.com:1443/
https://panel.example.com:40000/
```

## Can an xhttp node share port 443 with the panel

Yes, with two possible wirings:

- **Shared Web domain**: `Main menu [19 Port 443 Reuse manager] -> [2 Manage Web domains and reverse proxies] -> [10 xhttp node path reverse proxy]`. The xhttp inbound in 3x-ui must listen on `127.0.0.1` with TLS disabled; TLS stays on the local Caddy/Nginx. The client uses the same domain and the registered path.
- **Dedicated node domain**: same as an ordinary TLS node. Register the domain and local port under `[4 Manage Xray SNI forwarding rules]`, and let the xhttp inbound use its own certificate.

With a shared domain, the domain's Web allowlist limits xhttp too. `xray-fallback` does not support path reverse proxying, and xhttp over HTTP/3 needs UDP `443`, which the entry does not listen on. Full steps are in [REALITY and xhttp Together](../tutorials/03-xhttp-reality-shared-443.md).

## How to paste dynamic TCP parameters

Entrance:

```text
Main menu [10 Network and kernel optimization] -> [2 Dynamic TCP Parameter tuning]
```

After entering, follow the prompts to paste multiple lines of `sysctl` parameters. After pasting is completed, enter `EOF` in another line and press Enter to save.
