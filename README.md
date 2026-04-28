# 🚀 VPS 全能控制面板：从入门到起飞的终极方案

## 一、 📖 项目简述

这不仅是一个简单的 Bash 脚本，它是专为 VPS 玩家打造的**全能瑞士军刀** 。它集成了**环境初始化、深度系统调优、多重安全加固、极致网络加速**以及**主流节点建站**功能。

👉 **核心信条**：告别碎片化脚本，**全局快捷键一键唤出**，让你的服务器管理直击痛点，效率翻倍 ！

---

## 二、 ✨ 核心功能矩阵

### 1. 🛡️ 基础环境与安全加固
* ✅ **一键初始化**：自动安装 `curl`、`wget`、`jq` 等必备工具，校准时区，并强制激活**原生 BBR** 。
* ✅ **SSH 深度加固**：支持自定义 SSH 端口，内置**防失联检查机制**，自动配置 `ufw/firewalld` 放行规则 。
* ✅ **Fail2ban 防爆破**：一键安装并自动绑定当前 SSH 端口，十分钟内尝试失败 5 次即封禁 IP 24 小时 。
* ✅ **SSH 密钥管理**：一键添加公钥实现免密登录，从根源免疫密码爆破 。

### 2. 🚀 网络与性能调优
* ✅ **极致网络加速**：集成 `ylx2016` 终极 BBR 加速脚本，并支持 **Omnitt 动态 TCP 调优** 。
* ✅ **智能内存榨取**：根据物理内存自动匹配 **ZRAM 压缩策略**（激进/积极/保守），让小鸡（低配 VPS）也能稳如老狗。
* ✅ **IPv4/IPv6 优先级管理**：一键切换 IPv4 优先，解决部分环境下 IPv6 导致的连接超时问题。

### 3. 📦 环境部署与进阶组件
* ✅ **全能软件库**：一键部署 **Docker**、Python、宝塔面板、哪吒探针、WARP、Sing-box 以及 Caddy 反代。
* ✅ **Sing-box / Xray 多脚本入口**：内置甬哥四合一脚本、**233boy Sing-box 一键脚本** 与 **233boy Xray 一键脚本**，按个人习惯选择部署方式。
* ✅ **Caddy 自动化**：支持模块化管理反代配置，提供**跳过 TLS 验证**及一键清理证书残留功能。
* ✅ **新增：Nginx Stream + Caddy + REALITY 443 单入口分流**：公网只暴露 `443`，由 Nginx 按 SNI 分流到 Caddy、REALITY 和本地面板，避免 3x-ui 面板与 Xray 入站直接暴露公网。
* ✅ **新增：订阅管理与 Compose 工具**：快速部署和更新 SublinkPro、妙妙屋订阅管理、Sub-Store，并可安装 Dockge 管理 compose.yaml stack。
* ✅ **新增：IP Sentinel**：防止服务器 IP 被错误定位至中国大陆（防送中）。

### 4. 📊 测速与诊断工具
* ✅ **综合测试合集**：内置 YABS 硬件测试、融合怪测速、流媒体解锁检测及回程路由追踪。
* ✅ **端口实时排查**：可视化查看端口占用情况，并支持**一键强杀**冲突进程。

![VPS-Optimize 面板预览](https://i.mji.rip/2026/04/28/551fa3d4709c7e1ee7c9a4827f9eed23.png)

---

## 三、 💻 安装与快捷使用

### 第一步：获取超级权限
确保以 `root` 用户登录。如果不是，先执行：
```bash
sudo -i
```

### 第二步：一键运行脚本
执行以下命令开始安装并运行面板：
```bash
wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/vps.sh && chmod +x vps.sh && ./vps.sh
```

### 第三步：全局快捷唤出
脚本运行后会完成初始化。以后只需在终端输入：
```bash
cy
```
即可随时进入控制面板。

### 节点脚本入口

面板与节点相关工具集中在：

```text
4. 面板与节点部署
```

其中节点与订阅工具入口包括：

```text
2. 安装 Sing-box（甬哥四合一脚本）
3. 安装 Sing-box（233boy 一键脚本）
4. 安装 Xray（233boy 一键脚本）
5. 安装 SublinkPro（订阅转换与管理面板）
6. 安装 妙妙屋订阅管理（Docker Compose）
7. 安装 Sub-Store（HTTP-META / Docker Compose）
8. 更新订阅管理工具（SublinkPro / 妙妙屋 / Sub-Store）
9. 安装 Dockge（Docker Compose 管理面板）
```

233boy 文档：

```text
Sing-box：https://233boy.com/sing-box/sing-box-script/
Xray：https://233boy.com/xray/xray-script/
```

安装完成后，233boy Sing-box 通常可以用 `sing-box` 或 `sb` 进入管理面板；233boy Xray 通常可以用 `xray` 进入管理面板。

---

## 四、 🧩 443 单入口分流

这个功能用于把 3x-ui 面板、订阅入口、REALITY 入站、SublinkPro、Dockge、妙妙屋、Sub-Store 或普通网站统一收进公网 `443`。

```text
公网 443 -> Nginx stream 按 SNI 分流

panel.example.com -> Caddy -> 3x-ui 面板
site.example.com  -> Caddy -> 本地网站/订阅管理工具
REALITY SNI       -> Xray / 3x-ui REALITY 入站
未知 SNI          -> Xray / 3x-ui REALITY 入站
```

首次初始化：

```text
3. 软件安装与反代分流
18. 443 单入口分流向导
```

后续新增或删除网站/反代域名：

```text
3. 软件安装与反代分流
20. 管理 443 网站/反代域名
```

详细配置、3x-ui 参数、REALITY 入站、External Proxy、订阅转换和排错说明请看：

👉 [443 单入口分流详细教程](docs/443-single-entry.md)

核心原则：

```text
公网 443 只能由 Nginx stream 监听。
Caddy、Xray REALITY、3x-ui 面板、订阅服务、网站后端默认都只监听 127.0.0.1。
3x-ui 面板不要填写 Caddy 证书路径，SSL/HTTPS 应关闭。
REALITY dest/serverNames 必须写外部真实 HTTPS 站点，不要写面板域名。
```

---

## 五、 🔴 避坑指南

1. **端口冲突警告**：如果你使用了面板自带的 SSL 申请功能，**严禁**再使用脚本中的「Caddy 一键反代」，否则两者会因抢夺 `80` 端口导致全部宕机。
2. **443 单入口模式警告**：启用「Nginx Stream + Caddy + REALITY 443 单入口分流」后，**不要**再让 Caddy、Xray 或 3x-ui 面板直接监听公网 `443`。
3. **3x-ui 证书路径警告**：在单入口模式下，证书只给 Caddy 用，3x-ui 面板 SSL 应关闭，证书路径和私钥路径应留空。
4. **REALITY 参数警告**：REALITY 的 `dest` / `Target` 和 `serverNames` / `SNI` 必须写外部真实站点，不要写面板域名，也不要写本机 Caddy 地址。
5. **内核清理风险**：在执行「卸载冗余旧内核」时，**绝对不要**勾选正在运行的内核或 `Cloud` 内核，否则重启后服务器将变成一块“板砖”。
6. **安全组放行**：如果你使用的是阿里云、甲骨文等有外层防火墙的平台，修改 SSH 端口后**必须**手动在网页后台开启新端口，否则必失联。
7. **虚拟化架构限制**：`LXC` 或 `OpenVZ` 架构的 VPS 无法更换内核，且可能无法正常使用 `ZRAM` 调优。

---

## 六、 🔄 更新与维护

* **热更新**：面板内置了自更新功能。只需在主菜单选择 `17`，即可同步 GitHub 最新代码并自动重载，无需重新下载脚本。
* **反馈与联系**：如有 Bug 或建议，欢迎前往 GitHub 提交 Issue，也可以通过作者 GitHub 主页展示的邮箱联系。

---

## 七、 📜 开源协议

本项目遵循 [MIT License](https://opensource.org/licenses/MIT) 协议。如果觉得好用，请给个 **Star ⭐️** 支持一下！
