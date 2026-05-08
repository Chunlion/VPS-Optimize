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
- 新增流量达量关机保护，可按出站、入站、总量或任一方向统计网卡流量，达到阈值后自动关机防止超额账单。
- 新增 `src/README.md`，明确源码模块分工、构建顺序和菜单编号稳定规则。

### Changed

- README、INSTALL 和教程安装入口切换到 `main/dist/vps.sh` 发布版路径，并说明源码版与发布版关系。
- `run_remote_script` 去掉额外执行确认，保留危险系统操作自身的 `YES` 风险确认。
- 远程脚本下载增加 curl/wget 自动补齐、重试和 wget fallback，降低精简系统拉取失败概率。
- SublinkPro、妙妙屋订阅管理默认绑定本地地址，公网访问推荐接入 443 单入口。
- 主菜单保持原编号兼容，调整显示分组：流量达量关机保护归入“网络性能与容器”。
- `scripts/build.sh` 改为显式模块数组，构建前检查模块存在，减少发布版漏拼风险。

### Fixed

- 更新脚本改为拉取 `dist/vps.sh` 并校验发布版不依赖 `src/`。
- 修复旧用户从根目录 `vps.sh` 更新时可能因模块缺失无法运行的问题。
- 增加发布版 smoke 断言，覆盖 443 单入口、远程拉取、更新兼容、流量保护和 Docker 场景增强。

### Verification

- `bash scripts/build.sh`
- `bash -n scripts/build.sh vps.sh src/*.sh dog.sh xui-custom-manager.sh`
- `bash tests/smoke.sh`
- `shellcheck -S error vps.sh src/*.sh dist/vps.sh dog.sh xui-custom-manager.sh`
- `git diff --check`
