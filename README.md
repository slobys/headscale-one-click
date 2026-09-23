# headscale-one-click

一键部署 **Headscale + DERP + 管理面板**，并提供 **Peer Relay** 管理，适合 Debian / Ubuntu VPS 自建 Tailscale 控制端。

> 正式版：**v2.3.0**
> 连接路径：**DIRECT -> Peer Relay -> DERP**

## 快速开始

### 第一次安装

使用 root 用户执行：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh --menu
```

命令会自动拉取项目、创建 `hs` 快捷命令，并直接打开管理菜单。首次安装选择“执行安装”即可。

### 以后只需要

```bash
hs
```

安装、更新、卸载、修复、服务状态、Peer Relay、安装信息和连接路径，都从 `hs` 菜单进入。

## v2.3.0 主要功能

- Headscale 0.29.x + Headscale-ui / Headplane
- DERP 预编译二进制 + SHA256 校验，目标 VPS **无需 Go**
- Peer Relay 管理，保留 DERP 最终兜底
- Headscale / DERP / Peer Relay 公网端口首次随机生成并持久化
- 快速安装可自定义 Tailscale 虚拟内网网段
- 安装前检查、端口冲突检测、安装后健康检查
- 更新失败自动回滚
- 支持国内 VPS 本地文件优先与多线路下载

## 安装模式

```text
1. 快速安装（推荐）
2. 高级安装
```

快速安装会自动选择已验证版本和推荐配置，但仍会询问 **Tailscale 虚拟内网网段**：

```text
默认：100.64.0.0/24
例如：100.64.10.0/24
```

全新安装会随机生成一次 Headscale TCP、DERP TCP、Peer Relay UDP 端口并保存。已有安装会尽量保留原 IP、端口、虚拟网段和面板配置。

## 支持环境

Debian 12+ / Ubuntu 22.04+，支持 x86_64 与 arm64，需要 root 和公网 IPv4。**域名不是必需**，可以直接使用公网 IP。

## 需要放行的端口

实际端口以安装摘要或 `hs -> 查看安装信息` 为准。

| 用途 | 端口 |
|---|---|
| SSH | `22/tcp` |
| Headscale | 随机 TCP |
| DERP | 随机 TCP |
| STUN | `3478/udp` |
| Peer Relay | 随机 UDP，启用时放行 |
| HTTP / HTTPS | `80/443`，仅反代时需要 |

DERP 的额外 HTTP listener 默认关闭。

## 客户端加入

先通过：

```text
hs -> 查看安装信息
```

获取实际 Headscale 地址，然后执行：

```bash
tailscale login --login-server=http://服务器IP:Headscale端口
```

Windows PowerShell 如果找不到 `tailscale`：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" login --login-server=http://服务器IP:Headscale端口
```

接收子网路由：

```bash
tailscale up --login-server=http://服务器IP:Headscale端口 --accept-routes=true
```

发布家庭局域网，例如 `192.168.2.0/24`：

```bash
tailscale up --login-server=http://服务器IP:Headscale端口 --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset
```

## Peer Relay

进入：

```text
hs -> Peer Relay 管理
```

Peer Relay 服务器需要先登录当前 Headscale。脚本会使用安装时保存的随机 UDP 端口，并生成 `tailscale.com/cap/relay` Grant 片段。

脚本**不会自动覆盖 Headscale policy**。Peer Relay 不能完全替代 DERP，DERP 仍作为最终兜底。

常用检查：

```bash
tailscale debug peer-relay-servers
tailscale status
tailscale ping <目标设备>
```

## 说明

- DERP 支持公网 IP + 自签名证书 SHA256 指纹固定，无域名也能部署。
- Tailscale、DERP、Node.js 等支持本地文件优先；网络受限时可提前上传安装包到 `/root/`。
- Headscale 升级会检查版本路径并自动备份，避免跨 minor 跳级或直接降级。
- 已有安装快速重跑时，不会擅自更换端口或虚拟网段。

本项目适合学习、测试和自建环境。公网部署时请同时做好云安全组、访问策略和认证配置。
