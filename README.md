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
* ✅ **全能软件库**：一键部署 **Docker**、Python、宝塔面板、哪吒探针、WARP 以及 Caddy 反代。
* ✅ **Caddy 自动化**：支持模块化管理反代配置，提供**跳过 TLS 验证**及一键清理证书残留功能。
* ✅ **新增：Nginx Stream + Caddy + REALITY 443 单入口分流**：公网只暴露 `443`，由 Nginx 按 SNI 分流到 Caddy、REALITY 和本地面板，避免 3x-ui 面板与 Xray 入站直接暴露公网。
* ✅ **新增：SublinkPro**：快速部署节点订阅转换与管理平台，数据持久化存储。
* ✅ **新增：IP Sentinel**：防止服务器 IP 被错误定位至中国大陆（防送中）。

### 4. 📊 测速与诊断工具
* ✅ **综合测试合集**：内置 YABS 硬件测试、融合怪测速、流媒体解锁检测及回程路由追踪。
* ✅ **端口实时排查**：可视化查看端口占用情况，并支持**一键强杀**冲突进程。

![简介](https://i.mji.rip/2026/04/20/7444789776a94109fb33d8ed7fac6b04.png)

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

---

## 四、 🧩 443 单入口分流教程

这个功能位于：

```text
3. 软件安装与反代分流
18. Nginx Stream + Caddy + REALITY 443 单入口分流
```

它的目标很简单：**公网只开放一个 443，所有流量先进入 Nginx stream，再按 SNI 分流**。

```text
公网 443 -> Nginx stream

面板域名 panel.example.com
-> 127.0.0.1:8443
-> Caddy
-> 127.0.0.1:40000
-> 3x-ui 面板

展示站域名 site.example.com，可选
-> 127.0.0.1:8443
-> Caddy
-> 127.0.0.1:3000
-> SublinkPro 或其他 HTTP 服务

REALITY 伪装 SNI your-reality-sni.example.com
-> 127.0.0.1:1443
-> Xray / 3x-ui REALITY 入站

未知 SNI
-> 127.0.0.1:1443
-> Xray / 3x-ui REALITY 入站
```

### 1. 脚本里怎么填

普通用户建议一路使用默认本地监听地址：

```text
面板域名：panel.example.com
展示站域名：可留空
REALITY 伪装 SNI：your-reality-sni.example.com(请替换成你自己选择的外部真实 HTTPS 站点)
Nginx 公网监听地址：0.0.0.0
Nginx 公网监听端口：443
Caddy 本地监听地址：127.0.0.1
Caddy 本地监听端口：8443
Xray REALITY 本地监听地址：127.0.0.1
Xray REALITY 本地监听端口：1443
3x-ui 面板监听地址：127.0.0.1
3x-ui 面板端口：40000
3x-ui 订阅服务监听地址：127.0.0.1
3x-ui 订阅服务端口：2096
展示站后端地址：127.0.0.1
展示站后端端口：3000
Cloudflare API Token：用于 DNS 签发证书
```

注意三件事：

```text
面板域名、展示站域名、REALITY SNI 不能相同。
REALITY SNI 要写外部真实 HTTPS 站点，不要直接照抄模板域名。
公网 443 只能由 Nginx stream 监听，Caddy / Xray / 3x-ui 都走本地端口。
```

### 2. DNS 和证书准备

至少准备一个面板域名：

```text
panel.example.com
```

如果你想让节点地址和面板地址分开，可以再准备：

```text
node.example.com
```

推荐关系：

```text
面板入口：panel.example.com
节点地址：node.example.com
REALITY SNI：your-reality-sni.example.com
```

Cloudflare API Token 至少需要：

```text
Zone.Zone.Read
Zone.DNS.Edit
```

### 3. 3x-ui 面板设置

脚本配置好 Caddy 后，**不要在 3x-ui 面板里再填写 SSL 证书路径**。

3x-ui 面板应该这样设置：

```text
面板监听地址：127.0.0.1
面板端口：40000
webBasePath：/
面板 SSL / HTTPS：关闭
证书路径：留空
私钥路径：留空
Panel URL / Public URL / External URL：https://panel.example.com/
Subscription URI Path：/sub/
Subscription External URL：https://panel.example.com/sub/
```

为什么证书不填进 3x-ui？

因为这套架构是：

```text
浏览器 HTTPS -> Nginx stream -> Caddy 终止 TLS -> HTTP 反代到 3x-ui
```

证书只给 Caddy 用，3x-ui 只做本地 HTTP 后端。这样更稳，也不容易出现重定向循环。

### 4. 3x-ui 中配置 REALITY 入站

在 3x-ui 里新增或编辑 VLESS 入站：

```text
协议：vless
监听：127.0.0.1
端口：1443
传输：TCP (RAW)
decryption：none
Fallbacks：留空
```

REALITY 部分：

```text
安全：Reality
uTLS：chrome
Target / dest：your-reality-sni.example.com:443
SNI / serverNames：your-reality-sni.example.com
Short IDs：生成或填写 1 个或多个 shortId
SpiderX：/
公钥 / 私钥：点击生成，服务端保存私钥，客户端使用公钥
```

不要把 `Target / dest` 写成：

```text
127.0.0.1:8443
panel.example.com:443
```

也不要使用 Xray fallback 分流网站，因为现在分流已经由 Nginx stream 负责。

### 5. External Proxy 怎么填

服务端 REALITY 入站真实监听：

```text
127.0.0.1:1443
```

但客户端应该连接公网：

```text
node.example.com:443
```

所以在 3x-ui 入站里打开 `External Proxy`，建议填写：

```text
类型：相同
地址：node.example.com
端口：443
备注：可留空
```

如果暂时没有节点域名，也可以填：

```text
地址：panel.example.com
端口：443
```

保存后复制节点链接，应该能看到类似：

```text
vless://uuid@node.example.com:443?security=reality&sni=your-reality-sni.example.com&...
```

如果链接里还是 `:1443`，说明 External Proxy 没有生效，SublinkPro 转换后也可能继续得到错误端口。

### 6. SublinkPro 订阅转换建议

推荐流程：

```text
3x-ui 订阅链接 -> SublinkPro -> Clash / Mihomo 客户端
```

关键点：

```text
3x-ui 订阅外部地址应为：https://panel.example.com/sub/
3x-ui 节点 External Proxy 端口应为：443
SublinkPro 只负责转换，不建议靠它修复错误端口
```

这样 Clash / Mihomo 客户端里看到的节点会使用：

```text
server: node.example.com
port: 443
sni: your-reality-sni.example.com
```

流量统计仍然由 3x-ui 按用户/入站统计，不需要手动复制裸 vless 信息。

### 7. 常见错误判断

`ERR_SSL_PROTOCOL_ERROR` 通常是访问了内部端口。不要访问：

```text
https://panel.example.com:8443/
https://panel.example.com:40000/
https://panel.example.com:1443/
```

访问：

```text
https://panel.example.com/面板url根路径
```

`ERR_TOO_MANY_REDIRECTS` 通常是 3x-ui 面板还开着 SSL 或强制 HTTPS。关闭面板 SSL，并清空证书/私钥路径。

`HTTP 404` 先检查：

```bash
curl -I http://127.0.0.1:40000/
```

如果本地也是 404，检查 `webBasePath` 是否为 `/`。

`502 Bad Gateway` 通常是 3x-ui 没启动、端口不对，或 3x-ui 开了 HTTPS 但 Caddy 按 HTTP 连接。

### 8. 验证命令

检查监听：

```bash
ss -lntp | grep -E ':443|:8443|:1443|:40000|:2096|:3000'
```

期望类似：

```text
0.0.0.0:443       -> nginx
127.0.0.1:8443    -> caddy
127.0.0.1:1443    -> xray / 3x-ui REALITY
127.0.0.1:40000   -> 3x-ui 面板
127.0.0.1:2096    -> 3x-ui 订阅，可选
127.0.0.1:3000    -> 展示站后端，可选
```

检查配置：

```bash
nginx -t
caddy validate --config /etc/caddy/Caddyfile
```

测试面板证书：

```bash
openssl s_client -connect 服务器IP:443 -servername panel.example.com
```

测试 REALITY SNI：

```bash
openssl s_client -connect 服务器IP:443 -servername your-reality-sni.example.com
```

### 9. 后续维护菜单

如果已经跑过一次 `443 单入口分流向导`，后续可以进入：

```text
3. 软件安装与反代分流
19. CF DNS / Caddy 维护菜单
```

常用维护项：

```text
11. 443 单入口链路体检：检查 Nginx、Caddy、REALITY、面板端口和 SNI 分流。
12. 重新应用上次 443 分流配置：读取 /etc/vps-optimize/sni-stack.env 并重新生成配置。
13. 订阅端口 / External Proxy 检查提示：确认订阅里节点端口是否应为 443。
14. 回滚 443 单入口配置：从最近一次备份恢复 Nginx/Caddy 相关配置。
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
* **反馈建议**：本项目部分逻辑由 AI 整合多位技术大神的开源作品而成，如有 Bug 请前往 GitHub 提交 Issue。

---

## 七、 📜 开源协议

本项目遵循 [MIT License](https://opensource.org/licenses/MIT) 协议。如果觉得好用，请给个 **Star ⭐️** 支持一下！
