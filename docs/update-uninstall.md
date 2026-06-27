# 更新与卸载

## 更新脚本

推荐通过脚本菜单更新：

```text
17. 更新脚本
```

主菜单会缓存式检查远程版本。发现新版本后，输入 `u`、`update` 或 `upd` 可进入更新流程。

内置更新会先执行语法检查，再下载校验文件；校验失败时不会覆盖当前 `cy` 命令。

## 手动更新

```bash
tmp_file=$(mktemp /tmp/cy_update.XXXXXX.sh)
wget -qO "$tmp_file" https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh
bash -n "$tmp_file"
install -m 755 "$tmp_file" /usr/local/bin/cy
rm -f "$tmp_file"
cy
```

## 卸载快捷命令

```bash
rm -f /usr/local/bin/cy
```

这只会删除快捷命令，不会自动恢复脚本已经修改过的系统配置。系统服务、Nginx/Caddy 配置、防火墙规则、Docker 配置、证书和内核参数需要按实际情况单独回滚。

