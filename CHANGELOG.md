# Changelog

## v2.8 - 2026-10-22

### 新增功能

- **443端口复用：xhttp 节点路径反代**。新增 `[19] -> [2 管理 Web 域名与反向代理] -> [10 xhttp 节点路径反代]`，在同一个公网 `443` 和同一个 Web 域名下按路径分流到本地 xhttp 入站：Caddy 生成 `@xhttp_N` handle 块并置于默认 handle 之前，Nginx 生成关闭请求/响应缓冲、读写超时 1 小时的前缀 location。记录保存到 `/etc/vps-optimize/xhttp-paths.conf`（`域名|路径|本地地址|本地端口`），只登记路由，不创建或修改 3x-ui 入站；TLS 由本地 Web 反代终结。路径与面板 `webBasePath`、订阅路径重叠时拒绝，`xray-fallback` 模式下菜单不可用。
- **切换系统软件源**：新增 `[9 系统设置与清理] -> [9 切换系统软件源]`，可按中国大陆、境外、教育网或自定义地址选择镜像站；只切换系统软件包源，不自动升级软件包，也不改动 GitHub、Docker、pip/npm 源。
- **GitHub 更新镜像**：支持配置镜像前缀加速脚本下载，默认不启用；输入 `-` 恢复直连，配置持久化到 `/etc/vps-optimize/update-mirror.conf`，非法前缀（含 `@`、`*`）读取时忽略。
- **面板工具**：新增 Xray 中转（xray-relay）安装入口。

### 修复

- 换源按发行版校验：镜像清单标注每个站点实测支持的发行版，不支持当前发行版的站点自动隐藏；Debian/Ubuntu 先探测仓库元数据，探测不到时不换源，避免把系统源改坏。
- 换源可逆与输入校验：自定义地址自动剥离协议与结尾斜杠，保存前先用 `.sha256` 探测，非法内容不写入，`-` 即可恢复直连，不再需要手工删除配置文件。
- 国内机器下载换源脚本：优先 `linuxmirrors.cn` 与 `edgeone.linuxmirrors.cn`，GitHub raw 作为兜底；已配置镜像时镜像地址优先，并对 `raw.githubusercontent.com` / `github.com` 地址自动加镜像前缀重试。
- `apt update` 失败时不再继续安装软件包：更新与安装改为链式执行，避免软件源不可用时继续装包并留下半成品。
- 修复外部依赖：Aria2 改用仓库原始地址（`git.io` 短链已停止维护、上游仓库已归档）；nftables NAT 去掉第三方反代前缀直连 GitHub Release；RHEL 系 Caddy 源从不存在的 `openrepo.io` 改为官方 COPR；Python 环境改为系统软件包安装，修复该脚本仅支持 Debian/Ubuntu 却在全平台提供的问题。
- 443 流程：`修改端口、路径与 REALITY 参数` 子菜单第 4 项改为直接修改面板域名，不再只打印跳转提示。
- 增强流量达量关机保护检查器安装流程：生成时先写临时文件、规范化 BOM/CRLF 后再替换正式 checker；安装失败会显示实际首行字节、待检查文件和日志路径，并写入 `vps-traffic-guard.log` 便于排查。

### 优化

- 清理过度确认：新增 `confirm_standard_action`，部署订阅工具、安装面板、编辑配置后重启服务、重置统计基线、修复 timer、预检自动修复等可回退操作改为单次 `Y/n`，不再要求输入 `YES`；编辑配置后的 443 重新应用去掉重复确认，只保留切换预览。
- 统一中/英/俄三语菜单与帮助文案：修正英文、俄文中与中文功能不符的条目（Docker 管理、配置备份与回滚、443 入口、面板工具、系统设置等），统一二级菜单、面包屑、帮助与文档中的菜单名称；对照清单见 `copy-audit.md`。
- 合并 SSH 用户密钥登录模式里的重复入口：`密钥 + 密码登录（保留/恢复密码）` 同时承担保留密码和从仅密钥模式恢复密码登录的作用，菜单不再单独显示重复的“恢复密码登录”。
- 菜单显示：面板工具按分组重新编号，443端口复用菜单进入前清屏，诊断测试菜单改为单列，避免长标题换行错位。
- `dog.sh`：菜单项直接标注快捷词，补齐 `d/h/l` 入口，子页面标题接入三语，修正标题格式；同步三语 `dog.md` 菜单名。
- 清理 CI 驱动的过度防御代码：删除 `windows-selfcheck-wrapper` 作业及其配套的 `scripts/selfcheck-ps1-contract.ps1`（用 mock wsl 验证一个只负责转发 WSL 的包装器）；重写 `scripts/validate-traffic-guard-checker.sh`，去掉 dist/src 模板比对（dist 是 src 的拼接，比对恒等），只保留模板存在性、CRLF、shebang 与 `bash -n` 校验；精简 `build.sh` 的模块清单校验；`selfcheck.sh` 在本地缺 Go 时跳过 go test/vet（CI 仍要求），并去掉与 dist 新鲜度检查重复的 `git diff --check`；移除源码中永不触发的 `declare -F` 分支和 `-S error` 下不生效的 36 处 shellcheck 豁免。
- 详细审查记录见 `maintenance-audit.md`。

### 文档

- 新增三语教程「REALITY 与 xhttp 共存：独立域名与共用 443」，覆盖两种接法的完整步骤、3x-ui 入站字段、客户端参数、验证命令、排错表与已知限制（HTTP/3 需要 UDP 443、`xray-fallback` 不可用、白名单影响范围）。
- 统一 Web 白名单口径：按域名作用于 Web 域名，共用域名的 xhttp 同样受限，REALITY 与 SNI 路由不受影响；同步修正入口模式文档的路由表与匹配说明。
- 修正 FAQ 订阅示例（3x-ui 订阅为 `https://panel.example.com/sub/`，只有独立订阅工具才使用自己的域名），补齐英文、俄文缺失的「升级 Xray 后节点超时」一节，排错文档新增 xhttp 章节与症状索引。
- README、快速开始、配置路径与站点导航三语同步。

### 测试

- 新增 `tests/xhttp-paths.sh`，覆盖路径规范化、与面板/订阅路径的前缀冲突、配置读写往返、面板域名迁移与站点删除清理。
- 渲染基准新增 Caddy xhttp 断言，并更新 Nginx 单入口 Web 配置基准。
- 菜单 smoke 测试 mock 终端清屏，避免进入 443 菜单时阻塞；修正 nftables NAT 白名单断言为 GitHub Release 地址。

## v2.3 - 2026-05-27

- 修复流量达量关机保护在“任一方向达量”模式下遇到网卡计数清零后可能误算 RX/TX 方向用量的问题；状态页现在按基线、初始已用和实时网卡计数估算“本周期已用”，并单独展示本周期 RX/TX 方向累计。
- 增强自动检查 timer：增加启动后定时触发兜底、最近检查超时提示和“修复/重装自动检查 timer”入口，降低 timer 漏跑后保护失效的风险。
- 调整达量关机失败后的重试处理：只有关机命令被系统接受才保持触发状态，失败时会恢复等待下次 timer 重试。
- 增加流量保护 smoke 覆盖，包含网卡计数清零、周期切换、timer 配置和状态页文案断言。

## v2.2 - 2026-05-17

- 新增 Nginx HTTPS 反代入口，复用现有 `acme.sh + Cloudflare DNS API` 证书流程，并支持后端 HTTPS 跳过证书校验、域名 IP 白名单、查看/编辑已应用配置和清空 Nginx 反代配置。
- 新增“查看/编辑脚本已应用配置”中心，编辑前自动备份，并按 Caddy、Nginx、SSH、Docker Compose、JSON 和 443端口复用配置类型执行对应校验与应用提示。
- 新增 Docker Compose 项目配置编辑入口，可在订阅工具等 Compose 管理菜单中查看/编辑 Compose 文件，校验 `docker compose config`，并按需执行 `up -d` 应用修改。

## v2.1 - 2026-05-15

- 新增 experimental `tcp-peek` 443端口复用引擎：`vpso-mux` 使用 `MSG_PEEK` 解析 TLS ClientHello SNI，优先 `splice` 转发并支持 copy fallback；Nginx stream 仍是默认稳定模式。
- 443端口复用管理中心追加 engine 状态、`tcp-peek` 配置生成、dry-run、8444 测试端口、切换、回滚、日志和增强体检入口。
- 统一 `ENTRY_MODE` 和 `443-engine.conf` 写入值为 `nginx-stream` / `xray-fallback` / `tcp-peek`，旧 `nginx_stream` / `xray_fallback` / `tcp_peek` 只保留读取兼容和迁移提示。
- 新增 `docs/443-tcp-peek-engine.md`，说明 experimental 引擎边界、测试流程、白名单、切换和回滚。
- 增强 `vpso-mux` 高并发保护、状态刷新、慢握手处理、splice idle timeout、路由索引和 8444 路由矩阵预检。

## v1.8 - 2026-05-08

### Added

- 模块化源码结构：新增 `src/common.sh`、`ui.sh`、`input.sh`、`validate.sh`、`backup.sh`、`rollback.sh` 和 `src/main.sh`。
- 新增 `scripts/build.sh`，从 `src/*.sh` 生成可直接发布的单文件 `dist/vps.sh`。
- 新增旧版更新兼容入口，根目录 `vps.sh` 在本地文件不完整时会自动下载可运行脚本。
- 新增 Docker 443 场景增强：项目容器状态、端口暴露审计、订阅工具容器更新入口。
- 新增 443 网络访问测试，覆盖 DNS、TCP、TLS SNI、面板路径、普通订阅和 Clash/Mihomo 订阅路径。
- 新增系统/健康概览里的 443、Caddy、3x-ui、订阅工具、Docker 和流量保护摘要。
- 新增自动更新检查提示，主菜单会缓存式检查远程版本。
- 新增流量达量关机保护，可自动推荐活跃网卡，按出站、入站、总量或任一方向统计网卡流量，达到阈值后自动关机防止超额账单。
- 新增本机 hosts 解析管理，可查看、添加/更新、删除和恢复 `/etc/hosts` 备份。
- 新增 SSH 用户密钥登录模式，可为指定用户添加公钥，并切换密钥优先、仅密钥或恢复密码登录。
- 新增网卡管理工具，可查看网卡/路由/DNS，查看链路统计，临时启停网卡、设置 MTU 或刷新 DHCP。
- 新增 `src/README.md`，明确源码模块分工、构建顺序和菜单编号稳定规则。

### Changed

- README、INSTALL 和教程安装入口切换到 `main/dist/vps.sh` 路径。
- `run_remote_script` 去掉额外执行确认，保留危险系统操作自身的 `YES` 风险确认。
- 远程脚本下载增加 curl/wget 自动补齐、重试和 wget fallback，降低精简系统拉取失败概率。
- SublinkPro、妙妙屋订阅管理默认绑定本地地址，公网访问推荐接入 443端口复用。
- SSH 入口改为二级“SSH 安全中心”，把端口修改和密钥登录模式放在同一类维护菜单中。
- 主菜单移除重复的“添加 SSH 公钥”直达项，后续编号顺延，公钥添加统一放入 SSH 安全中心，不做数字兼容跳转。
- SSH 端口与登录模式会同步写入 `/etc/ssh/sshd_config.d/`，自动处理 `50-cloud-init.conf` 等云镜像子配置，并兼容已启用的 `ssh.socket`/`sshd.socket`。
- 流量达量关机保护仅保留在二级菜单 `主菜单 [10 网络与内核优化] -> [5 流量达量关机保护]`，主菜单不再显示直达项。
- 流量保护配置流程优化：重置日支持 `1-31`，短月份自动按当月最后一天；默认以今天作为周期起点，按所选计费模式自动估算本周期已用流量，并去掉计费模式括号说明。
- `scripts/build.sh` 改为显式模块数组，构建前检查模块存在，减少构建漏拼风险。

### Fixed

- 更新脚本改为拉取 `dist/vps.sh` 并校验运行入口完整性。
- 修复旧用户从根目录 `vps.sh` 更新时可能因模块缺失无法运行的问题。
- 修复 443 网络访问测试里 curl 失败时可能显示 `HTTP 000000` 且被误判成功的问题。
- 修复流量保护在网卡计数因重启清零后可能丢失本周期已用量的问题。
- 修复重新配置流量保护时可能沿用旧 state，导致已用量估算显示为很小增量、并且新填写抵扣不生效的问题。
- 修复 `vps-traffic-guard.service` 一次性检查异常退出后可能让 systemd 长期显示 `degraded` 的问题。
- 修复健康概览把 3x-ui 使用的 `x-ui.service` 误显示为独立 x-ui、同时把 3x-ui 显示为未安装的问题。
- 修复精简 Ubuntu 上 `/run/sshd` 缺失导致 `sshd -t`/`sshd -T` 检查失败、SSH 登录模式无法恢复的问题。
- 增加 smoke 断言，覆盖 443端口复用、远程拉取、更新兼容、流量保护和 Docker 场景增强。

### Verification

- `bash scripts/build.sh`
- `bash -n scripts/build.sh vps.sh src/*.sh dog.sh xui-custom-manager.sh`
- `bash tests/smoke.sh`
- `shellcheck -S error vps.sh src/*.sh dist/vps.sh dog.sh xui-custom-manager.sh`
- `git diff --check`
