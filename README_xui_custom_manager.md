# 3x-ui 外置增强管理脚本

`xui-custom-manager.sh` 是给 3x-ui / x-ui 准备的外置维护工具，只专注做面板外更适合脚本处理的维护功能：

- 自定义重置日期
- 流量校准
- 备份恢复
- 健康检查
- 查看日志
- 清理旧备份

它不编译、不替换 3x-ui 程序，也不会自动修改面板里的 `traffic_reset`。

## 快速运行

```bash
wget -qO xui-custom-manager.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh && chmod +x xui-custom-manager.sh && ./xui-custom-manager.sh
```

也可以从 VPS-Optimize 主面板进入：

```text
4. 面板、节点与订阅工具
16. 3x-ui 外置增强管理
```

首次打开菜单时，脚本会自动注册快捷命令：

```bash
xcm
```

## 推荐架构

`/usr/local/bin/xcm` 是手动入口：

- 每次运行优先从 GitHub raw 拉取最新版 `xui-custom-manager.sh`。
- 拉取成功后更新本地缓存并打开菜单。
- 拉取失败时使用本地缓存版本。
- `xcm` 只给用户手动打开菜单用，不给 timer 调用。

`/usr/local/bin/xui-custom-manager.sh` 是本地稳定执行器：

- 启用自定义重置时自动安装或更新。
- systemd timer 只调用这个本地文件。
- 不依赖 GitHub，不会每天联网拉取脚本。

systemd timer：

- 只在启用“自定义重置日期”时安装并启用。
- 每天执行一次 `/usr/bin/env bash /usr/local/bin/xui-custom-manager.sh --reset-check`。
- 使用 `/var/lib/xui-custom-manager/reset-state.json` 记录本月是否已重置，避免重复执行。
- 支持错过日期后补执行：例如设置每月 10 号，10 号离线、11 号上线时会补执行一次。

## monthly 提醒

使用外置自定义重置日期前，建议在 3x-ui 面板里把对应入站的原生 monthly 重置改成 `never` / 不重置。

脚本只做检测和提醒：

- 不接管面板原生 monthly。
- 不会自动把 `traffic_reset='monthly'` 改成 `never`。
- 如果外置管理的入站仍启用 monthly，菜单、dry-run 和健康检查会显示提醒，避免重复重置。

## 流量校准

流量校准只修改已用流量字段：

- 入站：只写 `inbounds.up` / `inbounds.down`
- 客户端：只写 `client_traffics.up` / `client_traffics.down`
- 不修改 `total`
- 不提供清零流量或修改上限入口

清零流量和修改流量上限请在 3x-ui 面板里操作。

所有流量显示和输入统一使用 GiB：

```text
1 GiB = 1024^3 bytes
```

写数据库前会自动使用 SQLite `.backup` 备份数据库，并要求输入 `YES` 确认。

## dry-run 预览

菜单里的“自定义重置日期 -> 立即检查一次”会先执行 dry-run：

- 预览本次会重置哪些入站和客户端。
- 显示不会重置的原因。
- 显示 monthly 冲突提醒。
- 不写数据库。
- 不停止或启动 x-ui。
- 不更新状态文件。

确认预览结果后，输入 `YES` 才会真实执行重置。

也可以直接命令行预览：

```bash
./xui-custom-manager.sh --reset-check --dry-run
./xui-custom-manager.sh --dry-run
```

真实执行一次检查：

```bash
./xui-custom-manager.sh --reset-check
```

## 默认路径

| 项目 | 路径 |
| --- | --- |
| 手动入口 | `/usr/local/bin/xcm` |
| 本地稳定执行器 | `/usr/local/bin/xui-custom-manager.sh` |
| 用户配置 | `/etc/xui-custom-reset.json` |
| 状态文件 | `/var/lib/xui-custom-manager/reset-state.json` |
| 备份目录 | `/root/x-ui-backups` |
| 日志文件 | `/var/log/xui-custom-manager.log` |
| x-ui 数据库 | `/etc/x-ui/x-ui.db` |
| x-ui 配置目录 | `/etc/x-ui` |
| x-ui 程序目录 | `/usr/local/x-ui` |
| systemd service | `/etc/systemd/system/xui-custom-reset.service` |
| systemd timer | `/etc/systemd/system/xui-custom-reset.timer` |

可选配置文件：

```bash
/etc/xui-custom-manager.conf
```

常用覆盖项示例：

```bash
BACKUP_DIR="/root/x-ui-backups"
XUI_DB="/etc/x-ui/x-ui.db"
XUI_ETC_DIR="/etc/x-ui"
XUI_PROGRAM_DIR="/usr/local/x-ui"
```

## 配置结构

`/etc/xui-custom-reset.json` 示例：

```json
{
  "enabled": true,
  "default_day": 1,
  "inbounds": {
    "1": {
      "enabled": true,
      "day": 10,
      "reset_inbound": true,
      "reset_clients_without_custom_day": false,
      "clients": {
        "user@example.com": {
          "enabled": true,
          "day": 20
        }
      }
    }
  }
}
```

`default_day`、入站日期和客户端日期范围都是 `1-31`。如果某月没有对应日期，例如 2 月没有 31 号，会使用当月最后一天。

## 安全说明

1. 写数据库前会先备份数据库；备份目录权限为 `700`，数据库备份尽量设为 `600`。
2. 恢复数据库、程序目录或配置目录前，会先备份当前状态，并要求输入 `YES`。
3. 配置文件和状态文件使用临时文件原子替换，并设置为 `600`。
4. 旧备份清理不会批量删除；每次只删除用户明确选择的单个文件。
5. 如果配置文件或状态文件 JSON 损坏，脚本会提示错误并停止，不会直接覆盖旧文件。
