---
outline: 2
---

# 443 端口复用：部署与配置

这篇教程把面板、订阅、网站和 REALITY 节点放到同一个公网 `443` 端口。第一次部署时，按页面顺序操作即可；示例域名和端口都要替换成你的实际值。

## 先选一种入口模式

不确定时，直接选 **Nginx Stream**。它是本文的默认路线，最适合第一次部署。

| 模式 | 适合场景 | 建议 |
| --- | --- | --- |
| **Nginx Stream** | 第一次部署，想要稳定易排错 | **推荐**，先用它跑通 |
| **TCP Peek + Splice** | 已经跑通 Nginx Stream，想改用轻量的 TCP 分流 | 可在部署完成后切换 |
| **Xray Fallback** | 已经有一个能接管公网 `443` 的 Xray 主入站 | 进阶用法，不建议作为第一次方案 |

三种模式都只允许一个服务监听公网 `443`。当前实际链路是：

```text
公网 443 -> 当前 ENTRY_MODE 对应的单个入口服务
普通 HTTPS / 网站 -> Caddy 或 Nginx -> 你的本地网站
面板 / 订阅 -> Caddy 或 Nginx -> 3x-ui 的本地 HTTP 端口
REALITY 节点 -> Xray / 3x-ui 的本地入站
```

如果你只是想把 3x-ui、网站和 REALITY 放在一起，选择 Nginx Stream，继续往下做即可。

## 先看一组完整示例

下面的值只用于说明“每一栏填什么”，不要原样复制到生产环境：

| 项目 | 示例值 | 用途 |
| --- | --- | --- |
| 面板域名 | `panel.example.com` | 浏览器打开 3x-ui 面板 |
| 节点域名 | `node.example.com` | 客户端节点地址、Hosts 地址 |
| 网站域名 | `site.example.com` | 普通 HTTPS 网站 |
| REALITY 目标 | `www.example.org` | REALITY 的伪装 HTTPS 网站；示例值 |
| 面板本地端口 | `40000` | 3x-ui 只在 VPS 本机监听 |
| 订阅本地端口 | `2096` | 订阅服务只在 VPS 本机监听 |
| REALITY 本地端口 | `1443` | Xray / 3x-ui 入站，只供本机入口转发 |
| 网站后端 | `127.0.0.1:3000` | 入口转发到你的网站程序 |

照这组例子，外部用户看到的是面板 `https://panel.example.com/panel/`、订阅 `https://panel.example.com/sub/` 和节点地址 `node.example.com:443`；`40000`、`2096`、`1443`、`3000` 都不应直接暴露到公网。

记住一个最容易填错的区别：

- `panel.example.com`、`node.example.com` 是用户从公网访问的域名；
- `127.0.0.1:40000`、`127.0.0.1:2096`、`127.0.0.1:1443` 是 VPS 内部转发的地址；
- REALITY 的 `serverName` 是伪装目标，例如 `www.example.org`，它不是你的面板域名，也不是节点域名。

## 部署前准备

### 1. 准备域名和 DNS

- 准备一个面板域名、一个节点域名（例如 `panel.example.com`、`node.example.com`）。
- 在 DNS 服务商处把它们解析到 VPS。面板和节点域名可以使用 CDN，但 REALITY 的 `serverName` / `target` 最好选一个稳定、能直接访问且没有 CDN 防护的真实 HTTPS 网站。
- 如果坚持把 CDN 域名作为 REALITY SNI，请在完成部署后打开 [SNI 清洗与 REALITY 回落防护](#sni-清洗与-reality-回落防护)。否则，未通过 REALITY 验证的请求可能把服务器当作 CDN 转发器，持续消耗带宽。
- 保留当前 SSH 连接，并确认云平台安全组和系统防火墙允许 SSH 与 TCP `443`。

域名用途可以按下面的方式分配：

| 域名 | DNS 指向 | 用在什么地方 |
| --- | --- | --- |
| `panel.example.com` | VPS 公网 IP | 面板域名、Web 反代域名 |
| `node.example.com` | VPS 公网 IP | 节点地址、Hosts 地址 |
| `www.example.org` | 目标网站自己的地址 | REALITY `serverName` / `target`，不要改成 VPS IP |

面板域名和节点域名是否经过 CDN，取决于你的访问需求；REALITY 目标则优先选择不经过 CDN 的真实 HTTPS 网站。不要把三者混成一个域名，也不要把 `node.example.com` 填到 REALITY 的伪装目标栏。

### 2. 准备 Cloudflare DNS API（使用 Cloudflare 时）

脚本使用 `acme.sh + Cloudflare DNS API` 完成 DNS-01 验证和证书签发。先把域名添加到 Cloudflare，并确认对应 Zone 处于 `Active` 状态。这里需要的是受限 API Token，不是 Global API Key。

申请步骤：

1. 打开 [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)，登录后选择 `Create Token`。
2. 找到 `Edit zone DNS` 模板，选择 `Use template`。
3. 确认权限包含 `Zone - DNS - Edit` 和 `Zone - Zone - Read`。新版界面可能把 `Edit` 显示为 `Write`，含义相同；不要添加账户管理等无关权限。
4. 在 `Zone Resources` 中选择 `Include - Specific zone`，再选择实际使用的根域名。例如面板域名是 `panel.example.com`，这里应选择 `example.com`。需要为多个根域名签发证书时，逐个加入对应 Zone。
5. `Client IP Address Filtering` 可以留空。若限制为 VPS 公网 IP，服务器 IP 变化后必须同步更新 Token 条件。
6. 选择 `Continue to summary`，确认后创建 Token。Token 只完整显示一次，请立即复制并妥善保存，不要写进文档、截图或聊天记录。

首次部署时，把 Token 粘贴到脚本的 `CF Token` 提示处，不要填写邮箱、Zone ID 或 Global API Key。已经部署过时，可进入主菜单 `[19 443端口复用管理中心]` → `[12 CF DNS / Caddy 证书维护]` → `[8 更新 Cloudflare API Token]`。脚本会在线校验 Token；校验失败时优先检查权限、授权 Zone 和可选的 IP 限制。

Cloudflare 官方说明：[创建 API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)。

如果域名记录显示为橙色云朵，面板和普通网站可以保持原样；REALITY 的 `serverName` 不要选择这个 CDN 域名，除非你愿意同时开启后面的 SNI 清洗和回落限速。

### 3. 先确认 443 没有被别的服务占用

在 VPS 上执行：

```bash
ss -lntp | grep ':443'
```

如果已经有 Nginx、Caddy 或其他程序占用 `443`，先记下它的用途。切换入口时脚本会检查冲突，但不会替你猜测哪些服务可以停止。

## 按顺序部署

### 1. 安装 3x-ui，并让面板只在本机提供服务

安装 3x-ui 时：

> **3x-ui 2.x（包括 v2.9.4 及更早版本）**：旧安装器可能没有 `Skip SSL`，无法跳过时按其流程完成安装即可。进入本文第 4 步的 443 配置向导后，确认“清空 3x-ui 旧证书路径”；脚本会自动清理面板和订阅的证书路径。自动清理失败时，按提示在 3x-ui 中手动清空并重启面板，再继续向导。

1. 面板证书选择 `Skip SSL (advanced — behind reverse proxy / SSH tunnel only)`。
2. 监听 IP：`127.0.0.1`（即 `监听 IP：127.0.0.1`）。
3. 面板端口和访问路径按你的习惯设置，记下它们，后面会填入反代配置。为了对应本文示例，可以填写：

   ```text
   面板端口：40000
   面板路径：/panel/
   ```

   如果安装器没有让你设置路径，就记下它显示的默认路径，不要自行猜一个新路径。

这样面板不会直接暴露到公网，外部访问统一经过 `443`。

安装完成后不要用 `http://服务器IP:40000` 作为长期访问方式；先完成本文的 443 配置，再使用 `https://panel.example.com/panel/`（路径以你的面板实际显示为准）。

如果面板设置页还能看到“证书文件”和“证书密钥文件”，两项都清空。公网 HTTPS 由 Caddy 或 Nginx 处理，3x-ui 只提供本机 HTTP 页面。

### 2. 设置订阅服务的本地地址

在 3x-ui 的订阅设置中，这一页只配置本机后端；公网订阅地址由面板域名和 URI 路径组成：

- 监听地址填 `127.0.0.1`；
- 监听域名留空；
- 订阅端口使用一个未占用的本地端口，例如截图中的 `53541`；
- URI 路径按你实际设置填写，例如 `/sublinkqq/`；使用默认示例时可填 `/sub/`、`/clash/`；
- 反向代理 URI 填 `https://panel.example.com/sublinkqq/`，即 `https://面板域名 + URI 路径`；
- 不要填 `node.example.com`，也不要给订阅服务单独配置公网证书。

按示例填写时，订阅服务的本地部分是：

```text
监听地址：127.0.0.1
监听域名：留空
监听端口：53541
URI 路径：/sublinkqq/
反向代理 URI：https://panel.example.com/sublinkqq/
```

按上例，客户端最终使用 `https://panel.example.com/sublinkqq/`；`53541` 只是 VPS 内部端口，不能写进分享链接。若 URI 路径是 `/sub/`，订阅地址就是 `https://panel.example.com/sub/`。

如果订阅设置页有“订阅证书文件”和“订阅密钥文件”，同样清空；否则 3x-ui 可能继续尝试在本机端口上提供另一套 HTTPS，造成端口或重定向混乱。

### 3. 配置 REALITY 入站

在 3x-ui 新建或编辑 VLESS REALITY 入站，按下面的原则填写：

- 监听地址：`127.0.0.1`；
- 监听端口：例如 `1443`，不要直接占用公网 `443`；
- 传输：TCP；
- 安全：REALITY；
- `serverName` / `target`：填写你准备好的真实 HTTPS 网站；
- `serverNames`：与上面的 SNI 保持一致；
- 指纹：常用的 `chrome` 即可；
- `Fallbacks`：留空，除非你明确知道自己在配置什么。

按上面的示例，关键几栏会是：

```text
监听地址：127.0.0.1
监听端口：1443
serverName / target：www.example.org
serverNames：www.example.org
Fingerprint：chrome
```

UUID、私钥、公钥和 shortId 由 3x-ui 的生成按钮创建；不要把别人的示例值直接复制过来。创建完成后，记下入站名称（例如 `VLESS-REALITY`），后面的 Hosts 需要选择它。

节点分享链接中的地址最后应使用你的节点域名和端口 `443`，而不是 `127.0.0.1:1443`。

### 4. 运行 443 配置向导

在脚本主菜单选择：

```text
主菜单 [19 443端口复用管理中心] -> [2 安装 / 切换 443 入口模式]
```

第一次部署建议这样填：

1. 入口模式选择 **Nginx Stream**。
2. Web 反代引擎选择 Caddy 或 Nginx；不确定时用默认值。
3. 填写面板域名、节点域名和 REALITY SNI。
4. 面板后端按示例填写 `127.0.0.1` 和 `40000`；订阅后端填写 `127.0.0.1` 和 `2096`。
5. 新增普通网站时，`后端地址：127.0.0.1`，端口例如 `3000`。如果网站在 Docker 中，请把容器端口发布到宿主机回环地址（例如 `127.0.0.1:3000:3000`），然后在这里填主机端口 `3000`。
6. 确认域名、端口和服务用途后再保存。

保存前脚本会检查后端是否可连接。检查失败时先修正地址或端口，不要为了继续而强行保存。后端端口不应直接开放到公网。

### 5. 回到 3x-ui 完成域名关联

配置向导完成后回到 3x-ui：

- 确认面板仍监听 `127.0.0.1`；
- 确认订阅监听地址为 `127.0.0.1`、监听域名留空；反向代理 URI 为“面板域名 + URI 路径”；
- **3x-ui v3.4.0 及之后：打开 `Hosts / 主机`，新增 Host**，把节点域名指向对应的 REALITY 入站。按本文示例逐项填写：
  - 入站：选择刚才创建的 VLESS REALITY 入站（本地监听 `127.0.0.1:1443`）；
  - 地址：`node.example.com`；
  - 端口：`443`；
  - Security / SNI / Fingerprint / ALPN：与该 REALITY 入站和客户端保持一致，例如 `REALITY`、`www.example.org`、`chrome`，ALPN 按入站实际值填写。
- **3x-ui v3.3.1 及之前：在对应 REALITY 入站里打开 `External Proxy`**。类型选择与入站一致，地址填 `node.example.com`，端口填 `443`；不要填 `127.0.0.1:1443`。
- 复制节点链接，确认客户端地址是节点域名、端口是 `443`。

`Hosts` 里的“地址”是用户访问的公网节点域名，不是本机监听地址；“入站”才是把这个域名关联到哪个 REALITY 入站。按示例，正确结果应当是：

```text
客户端地址：node.example.com
客户端端口：443
Hosts 地址：node.example.com
Hosts 端口：443
REALITY 入站监听：127.0.0.1:1443
REALITY SNI：www.example.org
```

如果生成的节点链接仍然是 `127.0.0.1:1443` 或 `node.example.com:1443`，说明 Hosts / External Proxy 没有填好，先修正这里再测试客户端。

### 6. 验证并备份

先用浏览器打开面板域名，再用客户端测试节点。确认无误后运行菜单中的配置备份。

可以在 VPS 上做两个不会改配置的检查：

```bash
ss -lntp | grep -E ':(443|40000|2096|1443)'
curl -I https://panel.example.com/panel/
curl -I https://panel.example.com/sub/
```

预期是：公网只需要看到入口监听 `443`；`40000`、`2096`、`1443` 可以只绑定 `127.0.0.1`；面板和订阅返回 HTTP 响应。示例路径如果与你的面板不同，以实际路径为准。

如果面板打不开，先检查本机端口和当前入口状态，再看[排错与恢复](443-single-entry-troubleshooting.md)。

## 模式切换与回滚

### 切换到 TCP Peek + Splice

TCP Peek 的优点是分流组件更轻量，并且能在连接早期按 SNI 处理流量。它不是另一套面板配置，**配置过程和 Nginx Stream 一样**：先把域名、面板、订阅和 REALITY 跑通，再切换入口。

执行：

```text
主菜单 [19 443端口复用管理中心] -> [2 安装 / 切换 443 入口模式] -> [3 TCP Peek + Splice]
```

脚本会先检查依赖、端口和后端连通性。切换期间保留当前 SSH 连接，确认新入口正常后再关闭旧连接。

### 使用 Xray Fallback

只有在你已经有一个配置完整的 Xray 主入站时才选择此模式。它由 Xray 接管公网 `443`，普通 HTTPS 再回落到 Caddy 或 Nginx。本模式不适合用脚本的 SNI 路由菜单管理多个 Xray 入站。

### 回滚上一次切换

如果切换后服务异常，执行：

```text
主菜单 [19 443端口复用管理中心] -> [7 回滚上一次入口模式切换]
```

回滚后重新检查面板域名、节点链接和 `ss -lntp | grep ':443'` 的监听结果。

## 常用维护

### 管理 Web 域名和反代

新增或修改网站时使用：

```text
主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代]
```

切换 Caddy / Nginx：选择 `[8 切换 Web 反代引擎]`。两者共用域名和证书配置，切换前先确认后端端口可访问。

完整路径是：

```text
主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代] -> [8 切换 Web 反代引擎]
```

脚本会重新生成所选引擎的配置，并继续使用已有域名、证书和后端。不要同时手动启动另一套 Caddy/Nginx 配置，否则它可能抢占 `443` 或本地 Web 端口。

新增网站时，按“域名 -> 后端地址 -> 后端端口”的顺序填写。例如你的程序在 VPS 上监听 `127.0.0.1:3000`，就填写：

```text
域名：site.example.com
后端地址：127.0.0.1
后端端口：3000
```

保存后用浏览器打开 `https://site.example.com`。如果程序实际只监听 Docker 容器内部地址，先发布到宿主机的 `127.0.0.1`，不要把容器名或容器内部专用主机名当作 VPS 后端地址。

### 反向代理 URL 怎么填

先分清服务类型：3x-ui 订阅填写 `https://panel.example.com + URI 路径`，例如 `https://panel.example.com/sub/`；SublinkPro、Sub-Store 等独立订阅工具使用自己的 Web 域名，不能套用 3x-ui 的填写方式。

独立工具的 DNS、Web 域名、后端地址、外部 URL 和验证步骤统一放在[独立订阅工具反代教程](../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md)。在完成域名解析和 Web 反代之前，不要直接填写 `https://tool.example.com/`。

### 管理域名 IP 白名单

Web 白名单只限制网站和面板域名，不限制 REALITY 节点流量。入口模式为 `nginx-stream` 或 `tcp-peek` 时，可在入口菜单选择 `[4] -> [5 域名 IP 白名单]`；管理 Web 域名时也可使用：

```text
主菜单 [19 443端口复用管理中心] -> [8 管理 Web 域名/反代] -> [5 管理域名 IP 白名单]
```

`xray-fallback`，无论使用 Caddy 还是 Nginx 本地 Web 反代，都只把白名单用于 Web 域名，不能把它当作 REALITY 用户鉴权。

## SNI 清洗与 REALITY 回落防护

当 REALITY 的 SNI 使用 CDN 域名时，建议同时打开：

1. **SNI 清洗**：只允许已经登记的 Web 域名、SNI 路由和 REALITY SNI 进入入口；未知 SNI 直接丢弃。
2. **回落限速**：只限制没有通过 REALITY 验证、又被回落处理的连接。

Nginx Stream 和 TCP Peek 支持这两项保护；Xray Fallback 没有前置的 SNI 清洗，但仍可使用回落限速。SNI 清洗不会代替 REALITY 密钥、UUID 等正常验证，也不会影响已经正确配置的节点。

在脚本中打开：

```text
主菜单 [19 443端口复用管理中心] -> [17 SNI 清洗 / REALITY 防护]
```

常用操作：

1. `[1] 启用严格 SNI 门禁`：Nginx Stream / TCP Peek 只放行已登记的 SNI。
2. `[3] 重新同步当前 SNI 清单`：新增域名或路由后使用，避免新域名被误拦截。
3. `[4] 设置 REALITY 回落限速`：只限制验证失败后进入回落的连接；脚本会生成一组随机参数，并在修改前要求确认。
4. `[5] 清除 REALITY 回落限速`：恢复 Xray 默认行为，同样需要确认。

回落限速只支持使用本机 SQLite 的 3x-ui。检测到 PostgreSQL 时，菜单 `[4]` 和 `[5]` 会标记为不可用，脚本不会修改远程数据库。

修改回落限速会重启面板或 Xray 服务。先确认节点没有正在进行的重要传输，并保留脚本生成的备份；如果只是普通非 CDN 目标，通常不需要额外开启回落限速。

严格 SNI 门禁的清单会根据已经登记的 Web 域名、SNI 路由和 REALITY SNI 自动生成。新增域名、修改节点 SNI 后，先保存配置，再执行 `[3] 重新同步当前 SNI 清单`；否则新域名可能被当成未知 SNI 拒绝。它只负责过滤未知 SNI，不负责验证 UUID、密钥或其他 REALITY 身份信息。

### 多个 REALITY 入站怎么配置

可以，但要使用 **Nginx Stream** 或 **TCP Peek + Splice**。这两个模式由入口按 SNI 把公网 `443` 分到多个本地入站；`xray-fallback` 不支持这种多 SNI 分流。

按下面的例子配置：

| 入站 | 3x-ui 本地监听 | 客户端 SNI | 443 分流记录 |
| --- | --- | --- | --- |
| `VLESS-REALITY-A` | `127.0.0.1:1443` | `sni-a.example.net` | `sni-a.example.net -> 127.0.0.1:1443` |
| `VLESS-REALITY-B` | `127.0.0.1:2443` | `sni-b.example.net` | `sni-b.example.net -> 127.0.0.1:2443` |

操作顺序：

1. 在 3x-ui 中分别创建两个 REALITY 入站；每个入站使用不同的本地端口和可区分的 SNI。脚本只负责记录分流，不会创建或修改 3x-ui 入站。
2. 入口模式保持 Nginx Stream 或 TCP Peek。
3. 打开 `主菜单 [19 443端口复用管理中心] -> [15 Xray 入站管理]`，分别添加两条 `SNI -> 本地地址 -> 本地端口` 记录。每次保存后，脚本都会提示是否立即同步到当前入口；连续添加多条时可以先不应用，全部录入后再执行一次“同步到当前入口模式”。
4. 打开 `主菜单 [19 443端口复用管理中心] -> [17 SNI 清洗 / REALITY 防护] -> [4 设置 REALITY 回落限速]`。菜单会列出所有 REALITY 入站；每次选择一个入站，设置只会应用到当前选中的入站，两个入站都要保护就重复执行两次。
5. 路由同步到当前入口时，严格 SNI 清单也会按已保存的域名和路由重新生成。

回落限速是“按入站保存”的，不是全局总开关，也不是按用户区分。每个入站必须使用不同的本地端口和不同的 SNI；对 A 入站开启限速，不会自动保护 B 入站。当前没有一次为所有入站批量设置限速的功能，需要逐个选择并设置。严格 SNI 门禁是共享入口规则，会同时覆盖所有已登记的 SNI。使用 PostgreSQL 的 3x-ui 时，脚本为避免误改远程数据库，不支持此回落限速功能；该功能仅支持本机 SQLite 3x-ui。

`xray-fallback` 可以在 Xray 内部存在多个入站，但公网 `443` 只由一个 Xray 主入站接管，脚本不会把多个 SNI 再分到多个本地入站。需要多入站共用 `443` 时，请切换到 Nginx Stream 或 TCP Peek + Splice。

如果可以选择，仍然优先使用没有 CDN 防护的真实 HTTPS 网站作为 REALITY 目标；这能减少误配置时的流量风险。

## 验证与排错

按下面顺序检查，通常不需要重装：

1. `ss -lntp | grep ':443'`：确认只有当前入口服务监听公网 `443`。
2. 浏览器打开面板域名：确认 Web 反代和证书正常。
3. 浏览器打开订阅地址：确认路径、端口和域名一致。
4. 客户端连接节点：确认分享链接使用域名和端口 `443`，REALITY 的 SNI 使用目标网站。
5. `403/401` 优先检查 Web 白名单、CDN/WAF 和 Host/SNI；`502` 检查后端地址和端口；超时检查防火墙、云安全组和 `443` 监听。
6. 在脚本中使用 `主菜单 [19 443端口复用管理中心] -> [13 443 链路体检]` 查看入口、证书、Web 和 Xray 路由；需要测试公网 DNS/TCP/TLS 时使用 `[14 443 网络访问测试]`。
7. 仍然失败时查看[排错与恢复](443-single-entry-troubleshooting.md)；需要了解入口差异时查看[入口模式与原理](443-tcp-peek-engine.md)。

## 不要这样做

- 不要让 3x-ui 面板、订阅或后端端口直接监听公网。
- 不要让两个服务同时监听公网 `443`。
- 不要把面板域名、节点域名或本机地址当作 REALITY 的伪装目标。
- 不要在没有 SSH 保底连接和备份的情况下切换入口。
- 不要把示例域名、端口和路径原样复制到生产环境。
