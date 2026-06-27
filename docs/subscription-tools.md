# 订阅管理与节点工具

节点和订阅相关入口集中在：

```text
主菜单 [5 面板、节点与订阅工具]
```

## 包含内容

该入口用于管理 3x-ui、S-UI、Sing-box、Xray、SublinkPro、Sub-Store、Dockge、Komari、端口流量狗和 x-ui 增强套件等相关工具。

## 部署建议

订阅工具建议按“本地监听 + Caddy/Nginx/443 对外”的方式部署。新部署的订阅工具默认优先绑定 `127.0.0.1`。

启用 443 单入口后，公网 HTTPS 域名建议通过以下入口添加：

```text
主菜单 [19 443 单入口管理中心] -> [8 管理 Web 域名/反代]
```

未启用 443 单入口时，可以使用独立反代入口：

```text
主菜单 [4 反代]
```

详细场景见 [订阅工具接入 Caddy/Nginx 反代与 443 单入口](../tutorials/02-subscription-tools-caddy-nginx-reverse-proxy-443-single-entry.md)。

