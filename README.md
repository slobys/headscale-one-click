# headscale-one-click

一键部署 **Headscale + HTTPS 443 + DERP + Peer Relay + 管理面板**，适合 Debian / Ubuntu VPS 自建 Tailscale 控制端。

> 当前 main：**v2.3.1**
> 连接路径：**DIRECT -> Peer Relay -> DERP**

## 快速开始

### 第一次安装

使用 root 用户执行：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh --menu
```

命令会自动拉取项目、创建 `hs` 快捷命令并打开管理菜单。首次选择“执行安装”即可。

### 以后只需要

```bash
hs
```

安装、更新、卸载、修复、服务状态、Peer Relay、安装信息和连接路径，都从 `hs` 菜单进入。

## v2.3.1 网络结构

```text
Tailscale 客户端
       │
       │ HTTPS 443
       ▼
      Nginx
       │
       ▼
Headscale 127.0.0.1:18080

DERP        → 随机 TCP
Peer Relay  → 随机 UDP
STUN        → 3478/UDP
```

Headscale 控制端固定使用 **HTTPS 443**，避免 Tailscale 在连接异常后强制回退 443 时掉线。

## 不需要域名

快速安装默认直接使用服务器公网 IPv4，例如：

```text
https://39.106.53.251
```

脚本会自动：

- 安装项目专用 Certbot 5.4+
- 通过 Let's Encrypt 申请公网 IP HTTPS 证书
- 配置 Nginx 443
- 创建证书自动续期 Timer
- 续期成功后自动 reload Nginx

IP 地址证书是短期证书，因此 **80/tcp 必须保持可访问，用于自动续期验证**。

高级模式也可以填写自己的域名。

## 安装模式

```text
1. 快速安装（推荐）
2. 高级安装
```

快速安装会自动选择已验证版本和推荐配置，并询问 **Tailscale 虚拟内网网段**。该网段必须位于 `100.64.0.0/10`：

```text
默认：100.64.0.0/24
例如：100.64.10.0/24
例如：100.68.68.0/24
```

不能使用 `10.x`、`172.16.x` 或 `192.168.x` 作为 Tailscale 虚拟网段。

## 需要放行的端口

| 用途 | 端口 |
|---|---|
| SSH | `22/tcp` |
| Headscale HTTPS | **`443/tcp` 固定** |
| Let's Encrypt 验证 | **`80/tcp` 固定** |
| DERP | 首次安装随机 TCP |
| STUN | `3478/udp` |
| Peer Relay | 首次安装随机 UDP，启用时放行 |

实际 DERP / Peer Relay 端口可通过：

```text
hs -> 查看安装信息
```

查看。

## 客户端加入

安装完成后统一使用 HTTPS 地址：

```bash
tailscale login --login-server=https://服务器公网IP
```

例如：

```bash
tailscale login --login-server=https://39.106.53.251
```

Windows PowerShell 如果找不到 `tailscale`：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" login --login-server=https://39.106.53.251
```

接收子网路由：

```bash
tailscale up --login-server=https://39.106.53.251 --accept-routes=true
```

发布家庭局域网，例如 `192.168.2.0/24`：

```bash
tailscale up --login-server=https://39.106.53.251 --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset
```

## Headscale API Key

全新安装会自动创建并显示一个 API Key；已有安装会询问是否创建新的 Key。

以后也可以直接进入：

```text
hs -> 12. 创建 Headscale API Key
```

完整 API Key 只会在创建时显示一次，请立即保存；如果丢失，需要重新创建新的 Key。

## HTTPS 证书续期

脚本会安装 `headscale-one-click-certbot-renew.timer`，每天自动检查两次证书是否需要续期，续期成功后自动 reload Nginx。

不需要每隔几天手动重新申请证书，但公网 `80/tcp` 必须保持可访问，以便 Let's Encrypt 完成 HTTP-01 续期验证。

## 从 v2.3.0 升级

旧版使用类似：

```text
http://公网IP:随机端口
```

升级到 v2.3.1 后，正式控制地址会切换为：

```text
https://公网IP
```

旧随机 HTTP 端口会暂时保留为兼容入口，避免已有客户端在迁移过程中突然全部失联；新客户端请统一使用 HTTPS 443。

证书申请或 Nginx 443 配置失败时，安装脚本不会切换 Headscale `server_url`，旧入口会继续保留。

## Peer Relay

进入：

```text
hs -> Peer Relay 管理
```

脚本会使用安装时保存的随机 UDP 端口，并生成 `tailscale.com/cap/relay` Grant 片段。

脚本**不会自动覆盖 Headscale policy**。Peer Relay 不能完全替代 DERP，DERP 仍作为最终兜底。

常用检查：

```bash
tailscale debug peer-relay-servers
tailscale status
tailscale ping <目标设备>
```

## 说明

- DERP 使用项目 Release 预编译二进制 + SHA256 校验，目标 VPS 无需 Go。
- Tailscale、DERP、Node.js 等支持本地文件优先，适合网络受限 VPS。
- 已有安装会尽量保留 DERP、Peer Relay、面板和虚拟网段配置。
- 公网部署请同时正确配置云安全组，特别是 `80/tcp`、`443/tcp`、DERP 和 STUN 端口。

本项目适合学习、测试和自建环境。
