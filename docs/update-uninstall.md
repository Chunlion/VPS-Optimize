# 更新与卸载

## 更新脚本

推荐通过脚本菜单更新：

```text
17. 更新脚本
```

主菜单会缓存式检查远程版本。发现新版本后，输入 `u`、`update` 或 `upd` 可进入更新流程。

内置更新会先执行语法检查，再下载校验文件；校验失败时不会覆盖当前 `cy` 命令。

## GitHub 更新镜像

脚本默认直连 GitHub。访问不了 GitHub 的机器，先在 `[9 系统设置与清理] -> [10 GitHub 更新镜像]` 保存一个可用镜像：脚本自身更新会走它，其它 GitHub 安装脚本直连失败时也会自动改走它重试。

- 配置保存在 `/etc/vps-optimize/update-mirror.conf`，更新脚本后保留。
- 在同一菜单输入 `-` 可恢复直连。
- 系统换源工具优先从 LinuxMirrors 官方站点（linuxmirrors.cn）下载；配置了镜像时先试镜像，再回退官方站点与 GitHub。
- 已有旧版 `cy` 时，先运行新版并按需设置镜像，再选择 `[17 更新脚本]` 完成替换。

## 手动更新

以 `root` 身份执行。下面的命令仅检查下载是否成功、文件是否非空及 Bash 语法；需要完整校验时使用菜单更新。任一步失败都不会继续安装。

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

## 卸载快捷命令

```bash
rm -f /usr/local/bin/cy
```

这只会删除快捷命令，不会自动恢复脚本已经修改过的系统配置。系统服务、Nginx/Caddy 配置、防火墙规则、Docker 配置、证书和内核参数需要按实际情况单独回滚。

