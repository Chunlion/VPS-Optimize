# 外部脚本与运行流程审查

审查时间：2026-10-19。HTTP 状态为当日实测，GitHub 活跃度取默认分支最近提交时间。

## 一、外部脚本清单

### 1.1 正常项（HTTP 200，上游近期有提交）

| 入口 | 地址 | 上游最近提交 | 结论 |
|---|---|---|---|
| Docker 引擎 | `get.docker.com` | 官方 | 正常 |
| Docker Compose | `github.com/docker/compose/releases/latest/download` | 官方 | 正常，资产实测 200 |
| acme.sh | `get.acme.sh` | 官方 | 正常 |
| 3x-ui 最新版 | `mhsanaei/3x-ui/master/install.sh` | 2026-10-17 | 正常 |
| S-UI | `alireza0/s-ui/master/install.sh` | 2026-10-18 | 正常 |
| 2S-UI | `shenaba/2s-ui/main/install.sh` | 2026-10-19 | 正常 |
| 3m-ui | `kazeyukiro/3m-ui/main/scripts/install.sh` | 2026-10-18 | 正常 |
| 妙妙屋X | `iluobei/miaomiaowuX/main/install.sh` | 2026-10-19 | 正常 |
| Sing-box / Xray | `233boy/*/raw/main/install.sh` | 2026-06-04 / 2026-09-02 | 正常 |
| WARP | `gitlab.com/fscarmen/warp` | 持续维护 | 正常 |
| Realm | `zywe03/realm-xwPF` | 2026-09-03 | 正常 |
| PVE | `oneclickvirt/pve` | 2026-10-19 | 正常 |
| Forwardx | `poouo/Forwardx` | 2026-10-19 | 正常 |
| FLVX | `Sagit-chu/flvx` | 2026-09-30 | 正常 |
| EasyTier | `EasyTier/EasyTier` | 2026-10-18 | 正常 |
| Tailscale | `tailscale.com/install.sh` | 官方 | 正常 |
| IP-Sentinel | `hotyue/IP-Sentinel` | 2026-10-19 | 正常 |
| VPS_BOT_X | `MEILOI/VPS_BOT_X` | 2026-05-30 | 正常 |
| 系统重装 | `bin456789/reinstall` | 2026-10-04 | 正常 |
| YABS | `yabs.sh` | 官方 | 正常 |
| 三网回程 | `zhanghanyun/backtrace` | 2025-06-10 | 可用；脚本多年未变，符合用途 |
| IP 质量 | `IP.Check.Place` | 服务 | 正常 |
| NodeQuality | `run.NodeQuality.com` | 服务 | 正常 |
| 流媒体解锁 | `check.unlock.media` | 服务 | 正常 |
| TcpQuality | `ibsgss/TcpQuality` | 2026-10-13 | 正常 |
| 延迟/DNS | `Cd1s/network-latency-tester` | 2026-07-14 | 正常 |
| BBR/内核 | `ylx2016/Linux-NetSpeed` | 2026-10-16 | 正常 |
| 1Panel/Aurora | `Aurora-Admin-Panel/deploy` | 2025-06-10 | 可用，更新变慢；面板本身稳定 |
| nftables NAT | `arloor/nftables-nat-rust` v2.0.0 | 2026-09-18 | 正常，版本已是最新 |
| vpso-mux | 本项目 Releases | 2026-09-08 | 正常，资产与 sha256 均 200 |

### 1.2 已处理的问题项

| 项目 | 问题 | 证据 | 处理 |
|---|---|---|---|
| `git.io/aria2.sh` | 短链服务已停止维护，上游仓库已归档 | `git.io` 仍 301 到 `P3TERX/aria2.sh`，该仓库 `archived=true`，最后提交 2020-12-25 | 改为仓库原始地址；文档标注“已归档” |
| `us.arloor.dev/https://github.com/...` | 依赖第三方反代域名，域名失效即无法安装 | 直连 GitHub Release 实测 200 | 改为直连，删除代理前缀 |
| `openrepo.io/repo/caddy/caddy.repo` | 第三方 Caddy RPM 源不可用 | HTTP 523（Cloudflare 源站不可达） | 改用 Caddy 官方 COPR：`dnf copr enable @caddy/caddy`；失败时按 `%rhel` 拼 COPR 仓库文件；再失败回退系统源 |
| `lxspacepy` | 脚本硬编码“仅支持 Debian/Ubuntu”，在 Rocky/Alma 上必然失败；仓库 23 星 | 脚本头部检查 `dpkg-query` / `apt-get` | 改为 `install_pkg python3 python3-pip python3-venv`（RHEL 为 `python3 python3-pip`），不再下载第三方脚本 |
| `http://v7.hostcli.com/...` | 白名单里残留，但已无调用方，且是 HTTP 源 | 全仓仅 allowlist 一处 | 删除该条目；同步删除文档中的宝塔行 |
| `fscarmen/argox` | 仓库规范名是 `ArgoX`，原地址依赖大小写重定向 | `fscarmen/ArgoX` 实测 200 | 改用规范大小写 |
| 3x-ui `v2.9.4` | 版本固定在 2.x | `master` 仍活跃 | 保留：菜单已注明“固定版本，用于复现 2.9.4 教程”，属有意兼容项 |
| `EZgost` | 锁 Gost 2.11.5，上游已到 3.x；仓库 34 星、最后提交 2025-01 | 脚本内 `ct_new_ver="2.11.5"` | 暂不改代码：该脚本的菜单与 2.x 配置格式绑定，替换会改变功能。报告建议需要 Gost 3.x 时改用官方 `go-gost` 二进制 |

## 二、dog.sh 菜单

| 问题 | 改动 | 理由 |
|---|---|---|
| 快捷词提示单独一行，且不指明对应菜单项 | 每个菜单项后直接标注 `[add]` `[limit]` `[reset]` `[config]` `[u]` `[uninstall]` `[tg]` `[report]`，删除单独提示行 | 少一行说明，用户不必记忆映射 |
| `d` / `h` / `l` 三个单字母入口只在提示行出现 | 末行改为 `d. 端口明细  h. 健康检查  l. 界面语言  0. 退出` | 与菜单项同排，符合“菜单即说明” |
| 顶部“原项目:”后缺空格 | 补齐空格 | 排版 |
| 子页面标题硬编码中文，英文/俄文模式仍显示中文 | 12 处标题改用 `ui_text` 三语 | 语言切换后导航标题一致 |
| “流量重置”标题缺少 `===` 包裹 | 与其它子菜单统一 | 视觉一致 |
| 文档菜单名与界面不一致（配额/日报/通知/卸载） | 三语文档同步为界面名称 | 文档可对照操作 |

功能检查：`bash -n dog.sh` 通过。`tests/dog-limits.sh` 在本机失败于 `print_json_file_health`，原因是本机未安装 `jq`（函数用 `jq -e` 判断 JSON），与本次改动无关；CI 需安装 jq。

## 三、443 端口复用流程

| 问题 | 改动 | 理由 |
|---|---|---|
| “修改端口、路径与 REALITY 参数”子菜单第 4 项只打印“请走 [2] -> [9]”，选了不执行任何操作 | 第 4 项直接调用 `edit_sni_stack_panel_domain_profile` | 菜单项应当是动作；函数本身已包含确认、证书签发、域名更新与重新应用，不存在逻辑重复 |
| 编辑入口/路由配置后，保存流程先问一次“是否重新应用”，进入切换预览还要再选一次“继续切换” | 删除前者，只保留切换预览中的确认 | 同一次操作两次确认；预览页已展示变更、回滚点，并支持查看 diff 和取消 |
| 443 菜单 15 项、二级维护菜单 16 项存在入口重叠（管理域名、修改参数、重新应用） | 保留 | 维护菜单是故障时的集中入口，主菜单是日常入口；删除会改变既有编号与文档路径，收益不足 |

未改动：入口模式切换、回滚、核心更新仍保留原有确认与预检；这些操作会中断公网 443，属于必要保护。

## 四、防御性逻辑收敛

新增 `confirm_standard_action()`：保留“变更内容 / 恢复方式 / 操作前提示”摘要，只要求一次 `Y/n`，不再因为标题里出现“安装、部署、重启、应用、重置”就升级为输入 `YES`。

| 位置 | 原确认 | 现确认 | 理由 |
|---|---|---|---|
| 订阅工具部署 ×6（SublinkPro、妙妙屋、Sub-Store、Dockge、Komari、CDT Monitor） | y + YES | 单次 Y/n | Compose 部署可停止/删除回退，不属于不可逆操作 |
| 面板安装 ×4（3x-ui、S-UI、233boy Xray、IP Sentinel） | y + YES | 单次 Y/n | 安装脚本可重复执行；菜单已明确目标 |
| 编辑配置后重启服务 ×5（vpso-mux、Traffic Guard timer、systemd-resolved、fail2ban、x-ui） | y + YES | 单次 Y/n | 重启是编辑后的应用步骤，配置可回滚 |
| 应用 sysctl | y + YES | 单次 Y/n | 有备份，参数可再次修改 |
| 重试失败的 systemd 服务 | y + YES | 单次 Y/n | 服务已处于失败状态，重启不会更糟；且跳过 sshd |
| 重置流量统计基线 | y + YES | 单次 Y/n | 配置流程中的一步，可再次重置 |
| 修复流量检查 timer ×2 | y + YES | 单次 Y/n | 幂等修复 |
| 重新同步严格 SNI 清单 | y + YES | 单次 Y/n | 可回滚，且不改变入口模式 |
| 自动修复预检问题 | y + YES | 单次 Y/n | 只安装基础包和开启 NTP |
| 编辑配置后重新应用 443 | 保存确认 + 重新应用确认 + 切换预览 | 保存确认 + 切换预览 | 三次变成两次，保留真正的风险确认 |

仍然保留 `y + YES` 的操作：磁盘重装、内核安装/切换、卸载、防火墙关闭、公网 443 入口切换、SSH 端口修改、编辑 sshd_config 后重启 SSH、白名单清除、Docker 卸载、Telegram Bot 安装（以 root 常驻）。这些要么不可逆，要么可能导致失联。

## 五、验证

- `bash -n`：`vps.sh`、`dist/vps.sh`、`dog.sh`、`xui-custom-manager.sh`、`src/*.sh`、`scripts/*.sh`、`tests/*.sh` 全部通过。
- `bash scripts/build.sh`：通过，`dist/vps.sh` 与 `.sha256` 已更新。
- `tests/golden-render.sh`：通过。
- `scripts/compat-smoke.sh`：通过（本机输出被终端回收，日志显示 `Compatibility smoke passed.`）。
- `tests/dog-limits.sh`：本机缺 `jq` 失败，非本次改动；CI 需预装 jq。
- `tests/smoke.sh`：在本机卡在联网段（9 分钟后手动终止），未取得完整结果；改动集中在确认函数与文案，未触及断言路径，但建议在 CI 跑完整套件。
