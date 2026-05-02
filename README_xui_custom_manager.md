# 3x-ui 外置增强管理

`xui-custom-manager.sh` 是给 3x-ui / x-ui 准备的外置维护工具。它不替换 3x-ui 程序，只补充面板外更适合脚本处理的维护能力。

## 它能做什么

| 能力 | 说明 |
| --- | --- |
| 自定义重置日期 | 按入站或客户端设置每月几号重置流量 |
| dry-run 预览 | 重置前先看会影响哪些入站和客户端 |
| 流量校准 | 手动校准已用流量，统一使用 GiB |
| 备份恢复 | 备份和恢复数据库、配置目录、程序目录 |
| 健康检查 | 检查配置、状态文件、定时器和 monthly 冲突 |
| 日志查看 | 查看外置脚本运行日志 |
| 旧备份清理 | 只删除用户明确选择的单个备份文件 |

它不会做这些事：

```text
不会编译或替换 3x-ui 程序
不会自动修改面板里的 traffic_reset
不会自动清零所有流量
不会修改流量上限 total
不会跳过备份直接写数据库
```

## 快速运行

单独运行：

```bash
wget -qO xui-custom-manager.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/xui-custom-manager.sh && chmod +x xui-custom-manager.sh && ./xui-custom-manager.sh
```

也可以从 VPS-Optimize 主面板进入：

```text
4. 面板、节点与订阅工具
16. 3x-ui 外置增强管理
```

首次打开菜单时，脚本会注册快捷命令：

```bash
xcm
```

## 推荐使用方式

| 目标 | 推荐入口 |
| --- | --- |
| 打开管理菜单 | `xcm` |
| 预览自定义重置 | 菜单里的“立即检查一次”，或 `--reset-check --dry-run` |
| 真实执行一次检查 | `--reset-check` |
| 查看是否有 monthly 冲突 | 健康检查 / dry-run |
| 校准已用流量 | 流量校准菜单 |
| 恢复旧状态 | 备份恢复菜单 |

## 两个执行入口

### `/usr/local/bin/xcm`

这是手动入口，适合用户打开菜单：

```text
每次运行优先从 GitHub raw 拉取最新版
拉取成功后更新本地缓存
拉取失败时使用本地缓存
只给用户手动使用，不给 timer 调用
```

### `/usr/local/bin/xui-custom-manager.sh`

这是本地稳定执行器，适合 systemd timer 调用：

```text
启用自定义重置时自动安装或更新
timer 只调用这个本地文件
不依赖 GitHub
不会每天联网拉取脚本
```

## 自定义重置日期

启用后，systemd timer 会每天运行一次：

```text
/usr/bin/env bash /usr/local/bin/xui-custom-manager.sh --reset-check
```

状态文件用于记录本月是否已执行，避免重复重置：

```text
/var/lib/xui-custom-manager/reset-state.json
```

如果错过日期会补执行。例如设置每月 10 号，10 号机器离线，11 号上线时会补执行一次。

日期规则：

```text
default_day、入站日期、客户端日期范围都是 1-31
如果某月没有对应日期，例如 2 月没有 31 号，则使用当月最后一天
```

## monthly 冲突提醒

使用外置自定义重置日期前，建议在 3x-ui 面板里把对应入站的原生 monthly 重置改成：

```text
never / 不重置
```

脚本只做检测和提醒：

```text
不接管面板原生 monthly
不会自动把 traffic_reset='monthly' 改成 never
如果外置管理的入站仍启用 monthly，菜单、dry-run 和健康检查会显示提醒
```

这样可以避免 3x-ui 原生 monthly 和外置脚本重复重置。

## dry-run 预览

菜单里的“自定义重置日期 -> 立即检查一次”会先执行 dry-run。

dry-run 会做：

```text
预览本次会重置哪些入站和客户端
显示不会重置的原因
显示 monthly 冲突提醒
```

dry-run 不会做：

```text
不写数据库
不停止或启动 x-ui
不更新状态文件
```

确认预览结果后，输入 `YES` 才会真实执行重置。

命令行预览：

```bash
./xui-custom-manager.sh --reset-check --dry-run
./xui-custom-manager.sh --dry-run
```

真实执行一次检查：

```bash
./xui-custom-manager.sh --reset-check
```

## 流量校准

流量校准只修改已用流量字段：

| 对象 | 修改字段 |
| --- | --- |
| 入站 | `inbounds.up` / `inbounds.down` |
| 客户端 | `client_traffics.up` / `client_traffics.down` |

不会修改：

```text
total
流量上限
其他入站配置
```

清零流量和修改流量上限请在 3x-ui 面板里操作。

所有流量显示和输入统一使用 GiB：

```text
1 GiB = 1024^3 bytes
```

写数据库前会自动使用 SQLite `.backup` 备份数据库，并要求输入 `YES` 确认。

## 备份恢复

可以备份和恢复：

```text
x-ui 数据库
x-ui 配置目录
x-ui 程序目录
```

恢复前脚本会先备份当前状态，并要求输入 `YES`。如果恢复失败，你仍然有恢复前备份可以回退。

备份目录默认是：

```text
/root/x-ui-backups
```

旧备份清理不会批量删除。脚本只删除用户明确选择的单个文件，避免误删整批备份。

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

## 配置示例

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

含义：

| 字段 | 说明 |
| --- | --- |
| `enabled` | 是否启用外置重置 |
| `default_day` | 默认每月几号重置 |
| `inbounds.<id>.day` | 指定入站的重置日期 |
| `reset_inbound` | 是否重置入站总流量 |
| `reset_clients_without_custom_day` | 是否重置未单独设置日期的客户端 |
| `clients.<email>.day` | 指定客户端的重置日期 |

## 安全说明

1. 写数据库前会先备份数据库；备份目录权限为 `700`，数据库备份尽量设为 `600`。
2. 恢复数据库、程序目录或配置目录前，会先备份当前状态，并要求输入 `YES`。
3. 配置文件和状态文件使用临时文件原子替换，并设置为 `600`。
4. 旧备份清理不会批量删除；每次只删除用户明确选择的单个文件。
5. 如果配置文件或状态文件 JSON 损坏，脚本会提示错误并停止，不会直接覆盖旧文件。

## 常见问题

### 为什么不自动关闭 3x-ui 原生 monthly

因为那是面板内的业务配置。脚本只负责提醒冲突，不替用户改 `traffic_reset`，避免误改已有策略。

### dry-run 显示会重置，但真实执行没发生

检查：

```text
是否输入 YES 确认
配置文件是否启用 enabled
systemd timer 是否启用
状态文件是否记录本月已执行
日志是否有错误
```

查看日志：

```bash
tail -n 100 /var/log/xui-custom-manager.log
```

### 恢复数据库前需要停 x-ui 吗

脚本恢复时会处理停止和启动流程。手动操作时，建议先停止 x-ui，再替换数据库，最后启动 x-ui。

### 能不能用十进制 GB

脚本统一使用 GiB：

```text
1 GiB = 1024^3 bytes
```

这样和很多 Linux 工具及 SQLite 内部字节计算更一致。
