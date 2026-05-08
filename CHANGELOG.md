# Changelog

## Unreleased

- 暂无。

## v1.8 - 2026-05-08

### Added

- 模块化源码结构：新增 `src/common.sh`、`ui.sh`、`input.sh`、`validate.sh`、`backup.sh`、`rollback.sh` 和 `src/main.sh`。
- 新增 `scripts/build.sh`，从 `src/*.sh` 生成可直接发布的单文件 `dist/vps.sh`。
- 新增旧版更新兼容入口，根目录 `vps.sh` 在缺少 `src/` 时会自动切换到发布版。
- 新增 Docker 443 场景增强：项目容器状态、端口暴露审计、订阅工具容器更新入口。
- 新增 443 网络访问测试，覆盖 DNS、TCP、TLS SNI、面板路径、普通订阅和 Clash/Mihomo 订阅路径。
- 新增系统/健康概览里的 443、Caddy、3x-ui、订阅工具、Docker 和流量保护摘要。
- 新增自动更新检查提示，主菜单会缓存式检查远程发布版版本。
- 新增流量达量关机保护，可自动推荐活跃网卡，按出站、入站、总量或任一方向统计网卡流量，达到阈值后自动关机防止超额账单。
- 新增本机 hosts 解析管理，可查看、添加/更新、删除和恢复 `/etc/hosts` 备份。
- 新增 SSH 用户密钥登录模式，可为指定用户添加公钥，并切换密钥优先、仅密钥或恢复密码登录。
- 新增网卡管理工具，可查看网卡/路由/DNS，查看链路统计，临时启停网卡、设置 MTU 或刷新 DHCP。
- 新增 `src/README.md`，明确源码模块分工、构建顺序和菜单编号稳定规则。

### Changed

- README、INSTALL 和教程安装入口切换到 `main/dist/vps.sh` 发布版路径，并说明源码版与发布版关系。
- `run_remote_script` 去掉额外执行确认，保留危险系统操作自身的 `YES` 风险确认。
- 远程脚本下载增加 curl/wget 自动补齐、重试和 wget fallback，降低精简系统拉取失败概率。
- SublinkPro、妙妙屋订阅管理默认绑定本地地址，公网访问推荐接入 443 单入口。
- SSH 入口改为二级“SSH 安全中心”，把端口修改和密钥登录模式放在同一类维护菜单中。
- SSH 端口与登录模式会同步写入 `/etc/ssh/sshd_config.d/`，自动处理 `50-cloud-init.conf` 等云镜像子配置，并兼容已启用的 `ssh.socket`/`sshd.socket`。
- 流量达量关机保护仅保留在二级菜单 `[10 网络与内核优化] -> [7]`，主菜单不再显示 `[20]` 直达项。
- 流量保护配置流程优化：重置日支持 `1-31`，短月份自动按当月最后一天；默认以今天作为周期起点，按所选计费模式自动估算本周期已用流量，并去掉计费模式括号说明。
- `scripts/build.sh` 改为显式模块数组，构建前检查模块存在，减少发布版漏拼风险。

### Fixed

- 更新脚本改为拉取 `dist/vps.sh` 并校验发布版不依赖 `src/`。
- 修复旧用户从根目录 `vps.sh` 更新时可能因模块缺失无法运行的问题。
- 修复 443 网络访问测试里 curl 失败时可能显示 `HTTP 000000` 且被误判成功的问题。
- 修复流量保护在网卡计数因重启清零后可能丢失本周期已用量的问题。
- 修复 `vps-traffic-guard.service` 一次性检查异常退出后可能让 systemd 长期显示 `degraded` 的问题。
- 增加发布版 smoke 断言，覆盖 443 单入口、远程拉取、更新兼容、流量保护和 Docker 场景增强。

### Verification

- `bash scripts/build.sh`
- `bash -n scripts/build.sh vps.sh src/*.sh dog.sh xui-custom-manager.sh`
- `bash tests/smoke.sh`
- `shellcheck -S error vps.sh src/*.sh dist/vps.sh dog.sh xui-custom-manager.sh`
- `git diff --check`
