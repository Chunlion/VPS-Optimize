# x-ui 增强套件 xui-custom-manager.sh 使用说明


## 功能定位

`xui-custom-manager.sh` 是 x-ui 增强套件脚本，不替换 3x-ui 程序，也不是 3x-ui 面板本身。它用于补充一些更适合脚本处理的维护功能：

- 自定义流量重置日期。
- 入站单独重置日。
- 客户端单独重置日。
- 预览 `reset-check`。
- 流量校准。
- 数据库备份/恢复。
- 配置目录和程序目录备份/恢复。
- `systemd timer` 自动检查。
- 健康检查、日志查看和旧备份清理。

重要风险：它会直接读取和写入 3x-ui SQLite 数据库 `/etc/x-ui/x-ui.db`。写库前请先创建 VPS 快照，并备份数据库。

## 版本兼容边界

支持 3x-ui 2.9.x 和 3.x。写库前必须通过只读数据库 schema 检查，关键表和字段未变化才允许继续。

其它 3x-ui 版本不在支持范围内。版本不在支持范围或 schema 检查失败时，只建议执行：

- 备份。
- 查看配置。
- 健康检查。
- 预览。
- 自检。

不要跳过版本范围和 schema 检查强行写库。如果脚本提示当前版本不支持或数据库字段不兼容，停止写库操作，先保留备份和诊断信息。

## 运行前必须做的事

1. 创建 VPS 快照。
2. 备份数据库 `/etc/x-ui/x-ui.db`。
3. 确认当前 3x-ui 版本属于 2.9.x 或 3.x。
4. 确认 3x-ui 面板里相关入站原生 `monthly` 重置已关闭，或改为 `never` / 不重置。
5. 保留当前 SSH 会话。
6. 先执行预览，不要直接执行真实重置。
7. 如果刚手动编辑过数据库，先执行预览和自检，确认配置与字段兼容。

## 快速运行

在服务器上以 `root` 运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh)
```

脚本需要 `root` 权限，因为它会访问 `/etc/x-ui`、备份目录、日志目录和 systemd unit。首次打开后会注册快捷命令：

```bash
xcm
```

常用命令：

```bash
xcm
bash /usr/local/bin/xui-custom-manager.sh --reset-check --dry-run
bash /usr/local/bin/xui-custom-manager.sh --self-test
```

## 自定义重置逻辑

自定义重置由 `/etc/xui-custom-reset.json` 控制，核心概念如下：

- 全局启用/禁用：全局关闭时，自动检查会跳过真实重置。
- 默认重置日：没有单独设置的入站可使用默认日期。
- 入站单独重置日：可以为某个入站设置每月几号重置。
- 客户端单独重置日：可以为某个客户端设置独立日期。
- 未单独设置日期的客户端是否跟随入站：由对应入站规则控制。
- 入站自身 `up/down` 是否重置：由对应入站规则控制。

日期范围是 1-31。每月日期超过当月天数时，会按当月最后一天处理。例如设置 31 号，2 月会按 2 月最后一天处理。

使用外置自定义重置时，不要同时开启 3x-ui 原生 `monthly` 和外置自定义重置，避免重复重置或状态难以判断。

## 写库行为说明

真实执行会修改 3x-ui 数据库中的已用流量字段：

- 入站：`inbounds.up`、`inbounds.down`。
- 客户端：`client_traffics.up`、`client_traffics.down`。

真实执行不会修改 `total` 流量上限。客户端会按官方逻辑重新启用。脚本会写入 reset state，用于记录本月是否已经执行，避免同月重复重置。

写库前会自动备份数据库。执行时会停止并重启 `x-ui`，以减少数据库写入和服务运行之间的冲突。执行后请检查日志和面板状态。

预览模式不会写数据库、不会停止或启动 `x-ui`、不会写 reset state。

## 流量校准说明

流量校准用于手动修改数据库里的已用流量：

- 入站校准会修改 `inbounds.up` / `inbounds.down`。
- 客户端校准会修改 `client_traffics.up` / `client_traffics.down`。

校准不会修改 `total` 上限。写入前会显示修改前后数值，必须输入 `YES` 才会写库。写库前会自动备份数据库，并在写入后尝试启动 `x-ui`。

版本不在支持范围或 schema 检查失败时，禁止使用真实写库校准。

## 自动 timer

启用自定义重置后，脚本会安装或更新：

- `xui-custom-reset.service`
- `xui-custom-reset.timer`

默认 timer 每日 `00:10` 执行一次：

```text
OnCalendar=*-*-* 00:10:00
```

service 执行：

```text
/usr/bin/env bash /usr/local/bin/xui-custom-manager.sh --reset-check
```

查看 timer 状态：

```bash
systemctl status xui-custom-reset.timer --no-pager
```

查看自动检查日志：

```bash
journalctl -u xui-custom-reset.service -n 100 --no-pager
tail -n 100 /var/log/xui-custom-manager.log
```

timer 可以在菜单中启用或停用。版本不在支持范围或 schema 检查失败时，不应自动安装或启用 timer。

## 文件路径

| 路径 | 说明 |
|---|---|
| `/etc/xui-custom-manager.conf` | 外置管理器配置 profile |
| `/etc/xui-custom-reset.json` | 自定义重置规则配置 |
| `/root/x-ui-backups` | 数据库、配置目录、程序目录备份目录 |
| `/etc/x-ui/x-ui.db` | 3x-ui SQLite 数据库 |
| `/var/log/xui-custom-manager.log` | 外置管理器日志 |
| `/var/lib/xui-custom-manager/reset-state.json` | 每月重置状态文件 |
| `/etc/systemd/system/xui-custom-reset.service` | 自动检查 service |
| `/etc/systemd/system/xui-custom-reset.timer` | 自动检查 timer |
| `/usr/local/bin/xui-custom-manager.sh` | 本地稳定执行器 |
| `/usr/local/bin/xcm` | 手动快捷入口 |

## 备份与恢复

脚本支持备份：

- 数据库 `/etc/x-ui/x-ui.db`。
- 配置目录 `/etc/x-ui`。
- 程序目录 `/usr/local/x-ui`。

恢复前会再次备份当前状态。恢复会覆盖当前数据库、配置目录或程序目录，因此执行前必须确认备份文件来源可靠，并保留 VPS 快照或其它回滚手段。

旧备份清理只应删除明确选择的文件。不要批量删除备份目录。

## 排错

### 数据库不存在

确认 3x-ui 是否已安装，数据库路径是否为 `/etc/x-ui/x-ui.db`。如果路径不同，需要通过 `/etc/xui-custom-manager.conf` 覆盖 `XUI_DB`，但不要在未确认结构兼容时写库。

### 数据库字段不兼容

停止写库操作。不要猜测字段结构。可以执行备份、查看、预览、自检，并保留错误输出用于排查。

### 当前 3x-ui 版本不在支持范围

不要执行写库功能。只建议执行备份、查看、预览和自检。不要强行开启 timer，也不要执行真实 `reset-check` 或流量校准写库。

### timer 没运行

检查：

```bash
systemctl status xui-custom-reset.timer --no-pager
systemctl list-timers | grep xui-custom-reset
```

确认当前 3x-ui 是 2.9.x 或 3.x，且 schema 检查通过后，再从菜单中启用自动检查。

### reset-check 没执行

先跑预览：

```bash
bash /usr/local/bin/xui-custom-manager.sh --reset-check --dry-run
```

再看日志：

```bash
journalctl -u xui-custom-reset.service -n 100 --no-pager
tail -n 100 /var/log/xui-custom-manager.log
```

### 配置 JSON 损坏

检查 `/etc/xui-custom-reset.json` 是否为合法 JSON。损坏时先备份当前文件，再从 `/root/x-ui-backups` 或 VPS 快照恢复。

### 状态文件损坏

状态文件是 `/var/lib/xui-custom-manager/reset-state.json`。损坏时不要直接覆盖生产状态。先备份当前文件，再结合日志和数据库确认是否已经执行过本月重置，避免重复重置。

### 写库失败

不要重复执行真实写库。检查数据库权限、字段兼容、磁盘空间、`x-ui` 是否可停止/启动，以及备份文件是否已生成。保留日志后再决定是否恢复备份。

### x-ui 重启失败

查看服务状态和日志：

```bash
systemctl status x-ui --no-pager
journalctl -u x-ui -n 100 --no-pager
```

如果真实写库前已经生成数据库备份，可以根据故障情况恢复备份。恢复前确认会覆盖当前数据。

## 禁止事项

- 不要在未备份数据库时执行写库功能。
- 不要跳过版本范围和 schema 检查强行写库。
- 不要同时开启 3x-ui 原生 `monthly` 和外置自定义重置。
- 不要手动编辑数据库后立即运行真实重置，先执行预览和自检。
- 不要在没有 VPS 快照或数据库备份的生产机器上测试写库功能。
