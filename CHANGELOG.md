# Changelog

## Unreleased

- 合并 SSH 用户密钥登录模式里的重复入口：`密钥 + 密码登录（保留/恢复密码）` 同时承担保留密码和从仅密钥模式恢复密码登录的作用，菜单不再单独显示重复的“恢复密码登录”。
- 增强流量达量关机保护检查器安装流程：生成时会先写临时文件、规范化 BOM/CRLF 后再替换正式 checker；安装失败会显示实际首行字节、待检查文件和日志路径，并写入 `vps-traffic-guard.log` 便于排查。

## v2.3 - 2026-05-27

- 修复流量达量关机保护在“任一方向达量”模式下遇到网卡计数清零后可能误算 RX/TX 方向用量的问题；状态页现在按基线、初始已用和实时网卡计数估算“本周期已用”，并单独展示本周期 RX/TX 方向累计。
- 增强自动检查 timer：增加启动后定时触发兜底、最近检查超时提示和“修复/重装自动检查 timer”入口，降低 timer 漏跑后保护失效的风险。
- 调整达量关机失败后的重试处理：只有关机命令被系统接受才保持触发状态，失败时会恢复等待下次 timer 重试。
- 增加流量保护 smoke 覆盖，包含网卡计数清零、周期切换、timer 配置和状态页文案断言。

## v2.2 - 2026-05-17

- 新增 Nginx HTTPS 反代入口，复用现有 `acme.sh + Cloudflare DNS API` 证书流程，并支持后端 HTTPS 跳过证书校验、域名 IP 白名单、查看/编辑已应用配置和清空 Nginx 反代配置。
- 新增“查看/编辑脚本已应用配置”中心，编辑前自动备份，并按 Caddy、Nginx、SSH、Docker Compose、JSON 和 443 单入口配置类型执行对应校验与应用提示。
- 新增 Docker Compose 项目配置编辑入口，可在订阅工具等 Compose 管理菜单中查看/编辑 Compose 文件，校验 `docker compose config`，并按需执行 `up -d` 应用修改。

## v2.1 - 2026-05-15

- 新增 experimental `tcp-peek` 443 单入口引擎：`vpso-mux` 使用 `MSG_PEEK` 解析 TLS ClientHello SNI，优先 `splice` 转发并支持 copy fallback；Nginx stream 仍是默认稳定模式。
- 443 单入口管理中心追加 engine 状态、`tcp-peek` 配置生成、dry-run、8444 测试端口、切换、回滚、日志和增强体检入口。
- 统一 `ENTRY_MODE` 和 `443-engine.conf` 写入值为 `nginx-stream` / `xray-fallback` / `tcp-peek`，旧 `nginx_stream` / `xray_fallback` / `tcp_peek` 只保留读取兼容和迁移提示。
- 新增 `docs/443-tcp-peek-engine.md`，说明 experimental 引擎边界、测试流程、白名单、切换和回滚。
- 增强 `vpso-mux` 高并发保护、状态刷新、慢握手处理、splice idle timeout、路由索引和 8444 路由矩阵预检。

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
- 主菜单移除重复的“添加 SSH 公钥”直达项，后续编号顺延，公钥添加统一放入 SSH 安全中心，不做数字兼容跳转。
- SSH 端口与登录模式会同步写入 `/etc/ssh/sshd_config.d/`，自动处理 `50-cloud-init.conf` 等云镜像子配置，并兼容已启用的 `ssh.socket`/`sshd.socket`。
- 流量达量关机保护仅保留在二级菜单 `主菜单 [10 网络与内核优化] -> [7 流量达量关机保护]`，主菜单不再显示直达项。
- 流量保护配置流程优化：重置日支持 `1-31`，短月份自动按当月最后一天；默认以今天作为周期起点，按所选计费模式自动估算本周期已用流量，并去掉计费模式括号说明。
- `scripts/build.sh` 改为显式模块数组，构建前检查模块存在，减少发布版漏拼风险。

### Fixed

- 更新脚本改为拉取 `dist/vps.sh` 并校验发布版不依赖 `src/`。
- 修复旧用户从根目录 `vps.sh` 更新时可能因模块缺失无法运行的问题。
- 修复 443 网络访问测试里 curl 失败时可能显示 `HTTP 000000` 且被误判成功的问题。
- 修复流量保护在网卡计数因重启清零后可能丢失本周期已用量的问题。
- 修复重新配置流量保护时可能沿用旧 state，导致已用量估算显示为很小增量、并且新填写抵扣不生效的问题。
- 修复 `vps-traffic-guard.service` 一次性检查异常退出后可能让 systemd 长期显示 `degraded` 的问题。
- 修复健康概览把 3x-ui 使用的 `x-ui.service` 误显示为独立 x-ui、同时把 3x-ui 显示为未安装的问题。
- 修复精简 Ubuntu 上 `/run/sshd` 缺失导致 `sshd -t`/`sshd -T` 检查失败、SSH 登录模式无法恢复的问题。
- 增加发布版 smoke 断言，覆盖 443 单入口、远程拉取、更新兼容、流量保护和 Docker 场景增强。

### Verification

- `bash scripts/build.sh`
- `bash -n scripts/build.sh vps.sh src/*.sh dog.sh xui-custom-manager.sh`
- `bash tests/smoke.sh`
- `shellcheck -S error vps.sh src/*.sh dist/vps.sh dog.sh xui-custom-manager.sh`
- `git diff --check`
