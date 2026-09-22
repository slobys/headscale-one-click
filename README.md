# headscale-one-click

一键部署 **Headscale + DERP + 管理面板**，并提供 **Peer Relay** 管理，适合在 Debian / Ubuntu 云服务器上快速搭建自己的 Tailscale 控制端。

当前版本面向 Headscale `0.29.x` 与较新的 Tailscale 客户端：DERP 使用官方 `derper`，通过自签名证书 SHA256 指纹固定工作，不再修改 Tailscale 源码；连接路径可形成 **DIRECT -> Peer Relay -> DERP** 三层兜底。

## 快速安装

使用 root 用户执行：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh
```

这条命令会自动：

- 拉取 / 更新项目到 `/root/headscale-one-click`
- 补齐脚本执行权限
- 安装快捷菜单命令 `hs`
- 启动交互式安装

安装完成后，随时输入下面命令打开管理菜单：

```bash
hs
```

如果只想打开菜单，不直接安装：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh --menu
```

如果 GitHub Release 下载很慢，可以临时指定自己的加速前缀：

```bash
GITHUB_PROXY_PREFIX=https://ghfast.top bash /tmp/hs-bootstrap.sh
```

## 适用环境

- Debian 12+ / Ubuntu 22.04+
- x86_64 / arm64
- root 用户
- 建议使用全新 VPS 或没有重要业务的服务器

暂不建议直接用于 CentOS / Rocky / AlmaLinux。

## 安装前准备

你需要准备：

- 一台有公网 IP 的服务器
- 已放行所需端口的云安全组 / 防火墙
- 一个域名更佳，没有域名也可以先用公网 IP 测试

建议放行这些端口：

- `22/tcp`：SSH
- `80/tcp`、`443/tcp`：如后续接入 HTTP / HTTPS 反代
- Headscale 对外端口，默认 `8080`
- DERP 服务端口，默认 `12345/tcp`
- DERP HTTP 端口，默认 `3340`
- `3478/udp`：DERP/STUN，用于 NAT 探测
- Peer Relay UDP 端口，启用时默认 `40000/udp`

如果公网访问不了，但服务器本机能访问，优先检查云平台安全组。

## 没有域名怎么办

只是测试时，可以在安装提示里把“域名”和“服务器 IP”都填服务器公网 IP。

例如：

```text
1.2.3.4
```

这样可以先通过 HTTP 跑起来：

```text
http://1.2.3.4:8080/web
```

长期使用仍然建议准备一个域名。DERP、HTTPS 证书和客户端连接稳定性都更适合使用域名。

## 安装时会问什么

脚本会按提示询问：

- 是否执行系统升级
- 域名
- 服务器 IP
- Headscale 端口，默认 `8080`
- IP 前缀，默认 `100.64.0.0`
- DERP 服务端口，默认 `12345`
- DERP HTTP 端口，默认 `3340`
- Go 版本，默认使用上游最新版本，可手动输入旧版本
- Tailscale DERP 版本，默认使用上游最新稳定版本，可手动输入旧版本
- Headscale 版本，默认使用上游最新版本，可手动输入旧版本
- 管理面板类型
- Headscale-ui 或 Headplane 版本，默认使用上游最新版本，可手动输入旧版本

一般情况下直接回车使用默认值即可。

系统升级会执行 `apt upgrade -y`。新服务器可以执行；已经跑业务的服务器建议先跳过。

如果服务器已经安装过 Headscale，脚本会先检测版本并备份 `/etc/headscale` 与 `/var/lib/headscale`。Headscale 不允许跨 minor 跳级升级，例如 **0.27 不能直接升级到 0.29，必须先升级到 0.28，再升级到 0.29**。脚本检测到不安全的升级路径会直接停止。

## 安装完成后

管理面板地址：

```text
http://服务器IP:Headscale端口/web
```

示例：

```text
http://1.2.3.4:8080/web
```

客户端接入：

```bash
tailscale up --login-server=http://服务器IP:Headscale端口
```

示例：

```bash
tailscale up --login-server=http://1.2.3.4:8080
```

如果需要接收子网路由：

```bash
tailscale up --login-server=http://1.2.3.4:8080 --accept-routes=true
```

如果需要发布子网路由：

```bash
tailscale up --login-server=http://1.2.3.4:8080 --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset
```

## DERP 工作方式

新版不再修改 `cmd/derper/cert.go`，而是直接编译官方稳定版 `derper`。

脚本会：

- 生成带正确 IP/DNS SAN 的自签名证书
- 计算证书 DER SHA256 指纹
- 在 `/etc/headscale/derp.yaml` 中写入 `certname: sha256-raw:<指纹>`
- 让 Headscale 直接从本地文件加载 DERP Map，不再通过 Nginx 暴露 `/var/www/derp.json`
- 显式启用 STUN `3478/udp`
- 安装时默认建议启用 Headscale `/verify` 接口校验 DERP 客户端，并设置 fail-closed；也可以在提示时选择跳过

因此现在无需魔改 Tailscale 源码，也无需 `InsecureForTests`。

使用自签名 DERP 证书指纹固定的客户端建议使用 Tailscale `1.82+`；如果要参与 Peer Relay，则需要 `1.86+`。

## Peer Relay

安装完成后执行：

```bash
hs
```

选择：

```text
9. Peer Relay 管理
```

可以查看状态、启用/重新配置、关闭，以及查看验证命令。默认 Peer Relay 端口为 `40000/udp`。

Peer Relay 节点必须先作为普通 Tailscale 客户端登录当前 Headscale，并要求 Tailscale `1.86+`。脚本会检查登录状态，未认证时先提示 Headscale 登录命令，不会直接开启 Relay。

启用时，脚本会根据本机实际 Tailscale IP 生成 `tailscale.com/cap/relay` Grant，并保存到 `/etc/headscale-one-click/peer-relay-grant.hujson`。**脚本不会自动创建、修改或覆盖你的 Headscale policy**：如果已经配置 `policy.path`，会提示把 Grant 合并到现有 `grants` 数组；如果没有检测到文件策略，会提醒先确认是否由面板/数据库管理 policy。policy 一旦定义了 `grants`，未匹配到 Grant 的普通流量会被拒绝，因此不要只加入 Relay Grant 而漏掉正常访问规则。

Peer Relay 的实际可用性还取决于客户端版本、平台支持、NAT 和防火墙环境，因此不要删除 DERP；它仍然是最终兜底。

常用验证命令：

```bash
tailscale debug peer-relay-servers
tailscale status | grep peer-relay
tailscale ping <目标设备>
```

正常的连接选择顺序：

```text
DIRECT -> Peer Relay -> DERP
```

Peer Relay 并不会替代 DERP；DERP 仍然是最终兜底。

## 常用路径

```text
/root/headscale-one-click                  项目目录
/etc/headscale/config.yaml                 Headscale 配置
/etc/systemd/system/derp.service           DERP 服务
/etc/headscale/derp.yaml                   自建 DERP Map
/etc/headscale-one-click/peer-relay.env    Peer Relay 状态
/etc/headscale-one-click/peer-relay-grant.hujson  待手动合并的 Relay Grant 片段
/var/www/web                               Headscale-ui 目录
/opt/headplane                             Headplane 目录
/etc/nginx/sites-available/headscale-one-click.conf  Nginx 站点配置
```

## 版本策略

脚本安装时会查询上游 latest，直接回车默认使用最新版；网络查询失败时使用项目内已验证的 fallback 版本。

Headscale 升级属于数据库迁移操作，脚本不会允许 minor 降级或跨 minor 跳级。已有 Headscale 环境在安装新版本前会自动备份；修改配置后会先执行 `headscale configtest`，通过后才启动服务。

Headscale 0.29 已移除旧的 `randomize_client_port` 配置项。如果旧配置仍存在，脚本会先完成备份，然后**停止升级**并提示你把该设置迁移到 policy 的顶层 `randomizeClientPort`；脚本不会擅自注释或改变原语义。

如果 0.28 旧配置仍包含 `ephemeral_node_inactivity_timeout`，脚本只会提示该字段已弃用，不会自动重写用户配置。安装官方 DEB 时会临时阻止其 `postinst` 自动启动 Headscale，解除后先执行 `configtest`，只有配置通过才由脚本启动服务。

你可以用下面命令检查上游版本：

```bash
hs
```

然后选择“检查上游最新版本”。

## 免责声明

本项目仅供学习、测试和自建环境使用。请确认你理解公网暴露、自签名证书、证书指纹固定、防火墙配置、访问策略以及上游版本变化带来的风险。
