# 端口流量狗 dog.sh 使用说明


## 功能定位

`dog.sh` 是一个端口级流量监控、配额、限速和日报趋势工具，适合按端口观察用量、给端口设置用量上限、限制带宽，以及通过 Telegram 查询端口流量。

它依赖系统组件工作，主要包括：

- `nftables counter`：记录被监控端口匹配到的流量计数。
- `tc`：实现端口相关限速。
- `cron`：执行开机恢复、定时保存、日报快照和重置检查。
- `conntrack`：辅助连接状态相关处理。
- `ss`、`jq`、`bc`、`curl` 等工具：用于端口、JSON、单位换算和下载。

它适合做端口级监控，不等同于 VPS 商家账单流量。商家账单通常按网卡、虚拟化平台或计费系统统计，口径与本工具不同。

## 快速安装/运行

在服务器上以 `root` 运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh)
```

脚本需要 `root` 权限，因为它会写入 `nftables`、`tc` 和 `crontab`。安装后通常可以使用快捷命令：

```bash
dog
```

运行前建议保留当前 SSH 会话；在生产机器上修改配额、限速、重置或卸载前，先导出配置或创建 VPS 快照。

## 统计口径说明

- `dog.sh` 的流量统计来自 `nftables counter`。
- 统计的是被监控端口匹配到的 TCP/UDP `input` / `output` / `forward` 流量。
- 显示总量通常是 `input + output`。
- 它不是网卡级总流量，也不是商家账单级统计。
- 非监控端口流量不会计入。
- 回环、内网、Docker、转发、重传包、平台侧封装或商家计费规则等场景，都可能导致结果与 VPS 商家面板存在差异。

因此，不建议用 `dog.sh` 的结果和 VPS 商家面板做精确对账。它更适合观察端口级趋势和做端口级控制。

## 准确性边界

- 实时端口累计适合参考，前提是对应 `nftables` counter 和链规则存在，并且没有被清空、重建或被其它工具覆盖。
- 日报趋势基于定时快照增量，可能存在小时级跨日误差。
- 重启、异常断电、内核计数丢失或脚本退出前未及时持久化时，可能出现漏算或回退。
- 端口段统计是范围聚合，不区分范围内每个端口的单独用量。
- 如果 Docker、转发、NAT 或其它网络组件改写了流量路径，计数可能与预期不同。
- 不建议用它和 VPS 商家面板做精确对账，商家后台仍应作为账单参考。

## 配额与限速说明

配额用于端口级用量控制。脚本会基于已匹配到的端口计数设置配额规则，超过配额后按当前规则限制对应端口流量。

限速依赖 `tc`，只对脚本配置并匹配到的端口规则生效。如果网卡识别、`tc` 规则或其它网络工具冲突，限速可能不符合预期。

建议给配额留余量，不要贴近商家月流量上限。例如商家给 1 TB 月流量时，端口配额不要刚好设置为 1 TB。商家统计口径通常更大，可能包含系统更新、面板、Docker 镜像、DNS、探针和非监控端口流量。

## 日报与趋势

日报由 `cron` 定时执行快照任务生成。当前脚本会按小时采集当前端口 counter，与上一次快照做增量差值，并写入日报文件。

常见报表包括：

- 昨日报表。
- 指定日期报表。
- 近 7 日趋势。

这些报表适合查看趋势，不是严格的 `00:00:00` 到 `23:59:59` 账单切分。跨日边界取决于定时快照执行时刻，可能存在快照间隔误差。

## 常用操作

- 添加端口监控：进入 `1. 添加/删除端口监控`，选择添加端口，支持单端口、多个端口和端口段。
- 删除端口监控：进入 `1. 添加/删除端口监控`，选择删除端口。
- 设置配额：进入 `2. 配额/限速管理`，为端口设置月流量配额。
- 设置限速：进入 `2. 配额/限速管理`，为端口设置带宽限制。
- 查看日报：进入 `8. 日报与趋势报表`。
- Telegram 查询：进入 `7. 通知管理 (Telegram 查询)`，部署交互式查询机器人后使用 `/t`、`/all`、`/yday`、`/trend`、`/day YYYY-MM-DD`。
- 更新脚本：进入 `5. 检查并热更新脚本`。
- 卸载脚本：进入 `6. 卸载脚本`。卸载前建议先导出配置。

## 文件路径

| 路径或位置 | 说明 |
|---|---|
| `/etc/port-traffic-dog/config.json` | 主配置文件，包含端口、配额、限速、Telegram 等配置 |
| `/etc/port-traffic-dog/logs/traffic.log` | 日志文件 |
| `/etc/port-traffic-dog/traffic_data.json` | 退出或恢复相关的实时计数备份 |
| `/etc/port-traffic-dog/daily_usage.json` | 日报累计数据 |
| `/etc/port-traffic-dog/daily_snapshot_state.json` | 日报快照状态 |
| `/usr/local/bin/port-traffic-dog.sh` | 本地脚本路径，存在时用于定时任务 |
| `crontab` 中 dog 相关任务 | 开机恢复、`--save-data`、`--daily-snapshot`、`--daily-reset-check` 等任务 |

查看当前定时任务：

```bash
crontab -l | grep -E 'port-traffic-dog|dog.sh|--save-data|--daily-snapshot|--daily-reset-check'
```

## 排错

### `dog` 无法启动

确认快捷命令是否存在：

```bash
command -v dog
```

也可以直接重新运行远程脚本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dog.sh)
```

如果提示权限问题，先切换到 `root`：

```bash
sudo -i
```

### 缺少 `nft` / `tc` / `ss` / `jq` / `bc` / `conntrack`

脚本会尝试自动安装依赖。如果安装失败，先确认系统包管理器可用、软件源正常，再手动安装对应包。Debian/Ubuntu 常见包包括 `nftables`、`iproute2`、`jq`、`bc`、`curl`、`cron`、`conntrack`。

### 流量一直为 0

优先检查：

- 端口是否已经添加到监控列表。
- 服务是否真的在该端口收发 TCP/UDP 流量。
- `nftables` counter 是否存在。
- `input` / `output` / `forward` 链里是否有对应 counter 规则。
- 是否有其它防火墙脚本重建了 nftables 表。

可以在菜单中使用统计健康检查；如果 counter 或链规则缺失，重新应用监控规则。

### 重启后统计变少

可能原因：

- 重启或断电前计数没有及时保存到 `/etc/port-traffic-dog/traffic_data.json`。
- `nftables` counter 被系统或其它脚本清空。
- 开机恢复任务没有执行。

建议检查 `crontab`、`traffic_data.json` 和日志。重要配额场景不要把阈值设置得太贴近商家流量上限。

### 日报没有数据

检查：

- `cron` 是否运行。
- `crontab` 中是否存在 `--daily-snapshot` 任务。
- `/etc/port-traffic-dog/daily_usage.json` 是否存在且 JSON 有效。
- 监控端口是否有实际流量。

### 配额没有生效

检查：

- 端口是否已添加监控。
- 配额是否为当前端口设置。
- `nftables` quota 和 counter 规则是否存在。
- 是否有其它防火墙工具覆盖了脚本规则。

配额只对脚本匹配到的端口规则生效。

### 限速没有生效

检查：

- `tc` 是否存在。
- 默认网卡识别是否正确。
- 端口是否已有监控规则。
- 是否有其它脚本或面板同时修改 `tc`。

限速只对脚本配置并匹配到的端口规则生效。

### 和商家面板不一致

这是预期内的常见情况。`dog.sh` 是端口级统计，商家面板通常是整机或平台账单级统计。非监控端口、系统更新、Docker 拉取镜像、面板通信、探针、DNS、内网转发、回环、重传包和平台侧计费规则都可能造成差异。

商家后台仍是最终账单参考。

## 卸载与清理

进入菜单 `6. 卸载脚本` 可以卸载。卸载会删除当前运行中的 `nftables` 规则、`tc` 限速、`cron` 任务和配置文件相关内容。卸载前建议先导出配置，并确认有 VPS 快照或其它可回滚手段。

如果脚本把旧配置隔离到类似 `/root/port-traffic-dog-quarantine` 的目录，确认不再需要后再手动清理。
