# 3x-ui 外置增强管理脚本

`xui-custom-manager.sh` 是给 3x-ui / x-ui 准备的外置维护工具，主要补充面板里没有或不方便直接操作的功能。

它不负责编译或替换 3x-ui 程序。脚本重点放在已经安装好的 3x-ui / x-ui 环境上，做流量重置、数据库校准、备份恢复和健康检查。

## 快速运行

```bash
wget -qO xui-custom-manager.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh && chmod +x xui-custom-manager.sh && ./xui-custom-manager.sh
```

也可以从 VPS-Optimize 主面板进入：

```text
4. 面板、节点与订阅工具
16. 3x-ui 外置增强管理
```

## 适用场景

- 需要按指定日期分别重置入站自身流量或不同客户端流量。
- 需要手动触发一次自定义重置检查。
- 需要禁用 3x-ui 原版 monthly 自动重置，改用外置规则。
- 需要在面板更新后继续沿用之前设置的外置重置日期。
- 需要查看、校准或修改 `up` / `down` / `total` 流量数据。
- 需要备份或恢复 x-ui 数据库、配置目录、程序目录。
- 需要检查 x-ui 服务状态、数据库完整性、关键端口监听和最近日志。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 自定义每月重置日期 | 入站和客户端分开设置；客户端没有单独日期时，默认不会跟随入站重置 |
| 手动重置检查 | 不等 systemd timer，立即执行一次规则检查 |
| systemd timer | 安装或更新外置自动重置定时器，并检测面板更新 |
| 禁用原版 monthly 重置 | 只处理外置配置里已启用的入站，避免误改未托管入站 |
| 外置规则复查 | 每次重置检查都会读取原外置配置，并把已启用外置规则的入站 `traffic_reset='monthly'` 恢复为 `never` |
| 流量查看与校准 | 入站和客户端分开修改；多个客户端会逐个写入并独立计算 `all_time` |
| 备份恢复 | 备份和恢复数据库、配置目录、程序目录 |
| 健康检查 | 检查服务、数据库、日志关键词和监听端口 |
| 旧备份清理 | 每类备份只删除用户明确选择的单个旧备份文件 |

## 默认路径

| 配置项 | 默认值 |
| --- | --- |
| 配置文件 | `/etc/xui-custom-manager.conf` |
| x-ui 数据库 | `/etc/x-ui/x-ui.db` |
| x-ui 配置目录 | `/etc/x-ui` |
| x-ui 程序目录 | `/usr/local/x-ui` |
| 备份目录 | `/root/x-ui-backups` |
| 日志文件 | `/var/log/xui-custom-manager.log` |
| 重置配置 | `/etc/xui-custom-reset.json` |
| 重置状态 | `/var/lib/xui-custom-manager/reset-state.json` |
| systemd service | `/etc/systemd/system/xui-custom-reset.service` |
| systemd timer | `/etc/systemd/system/xui-custom-reset.timer` |

如需改默认路径，可以创建 `/etc/xui-custom-manager.conf`：

```bash
BACKUP_DIR="/root/x-ui-backups"
XUI_DB="/etc/x-ui/x-ui.db"
EXPECTED_LISTEN_PORTS="40000 1443 2096"
```

## 命令参数

```bash
./xui-custom-manager.sh
./xui-custom-manager.sh --run-reset-check
./xui-custom-manager.sh --show-reset-config
```

`--run-reset-check` 适合给 systemd service 调用；`--show-reset-config` 用于快速查看当前自定义重置配置。

## 面板更新后的重置日期

自定义重置日期保存在 `/etc/xui-custom-reset.json`，不保存在面板程序文件里，所以普通更新 3x-ui / x-ui 面板不会覆盖这些日期。

安装 `systemd timer` 后，脚本每天会执行一次 `--run-reset-check`。执行时会记录并比较 `XUI_BIN` 指向的面板程序状态；如果检测到面板程序已经更新，会提示继续沿用原来的外置配置。

无论是否检测到程序文件变化，脚本每次检查都会读取 `/etc/xui-custom-reset.json`，自动确认已启用外置规则的入站是否又变成 `traffic_reset='monthly'`。如果发现这种情况，脚本会备份数据库后把它改回 `never`，避免原版 monthly 重置和外置自定义日期同时生效。

如果刚更新完面板、想立即复查，可以在菜单中执行：

```text
2. 手动执行一次自定义重置检查
```

## 安全建议

1. 修改数据库、恢复备份或禁用原版重置前，先做快照或执行脚本内备份。
2. 数据库写入类操作会临时停止 `x-ui`，完成后会尝试重新启动服务。
3. 恢复程序目录或数据库前，请确认选择的是正确备份。
4. 旧备份清理不会批量删除；每类备份只删除一个明确选择的文件。
5. 如果面板正在线上使用，建议在低峰期执行流量校准和恢复操作。
