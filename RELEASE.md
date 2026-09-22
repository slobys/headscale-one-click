# headscale-one-click v2.2.0 Release Notes

## 标题建议

```text
v2.2.0 - 管理信息与连接路径增强
```

## Release 文案

```markdown
## headscale-one-click v2.2.0

这一版重点增强安装后的日常管理和排障体验，不改变 Headscale 0.29 + Peer Relay + 原生 DERP 的总体架构。

### 核心变化
- `hs` 菜单新增 `10. 查看安装信息`
- `hs` 菜单新增 `11. 查看设备连接路径`
- “查看安装信息”可重新显示管理面板地址、Headscale 控制地址、Windows 客户端加入命令、子网路由示例、DERP 主机名/端口和 Peer Relay 状态
- 兼容旧安装：即使旧版 `panel.env` 缺字段，也会从 Headscale 配置和 `derp.service` 自动推断
- “查看设备连接路径”会把 `tailscale status` 翻译为 P2P 直连 / Peer Relay / DERP / 离线 / 空闲
- 安装完成摘要与 README 的首次接入命令改用 `tailscale login --login-server=...`
- 新安装会保存更多状态字段，后续无需重新安装也能重现安装信息
- 完整保留 v2.1.1 的大陆 VPS 下载增强、Tailscale 回滚保护和 pnpm 路径修复

### 连接顺序

```text
DIRECT -> Peer Relay -> DERP
```

### Peer Relay 安全策略
脚本只生成 `tailscale.com/cap/relay` Grant 片段并保存到 `/etc/headscale-one-click/peer-relay-grant.hujson`，不会自动创建、修改或覆盖 Headscale policy。

如果检测到已有 `policy.path`，会提示把 Grant 手工合并到现有 `grants`；如果没有检测到文件策略，会提醒先确认是否由面板/数据库管理 policy。policy 一旦定义 `grants`，还必须同时保留正常访问规则，避免其它流量因未匹配 Grant 被意外阻断。

### 大陆服务器安装增强
- Tailscale 客户端：本地静态包 -> 官方静态包 -> `tailscale.com/install.sh` 最后兜底
- Tailscale 官方静态包安装前强制 SHA256 校验
- 支持 `TAILSCALE_DOWNLOAD_BASE` 指定自有可信镜像
- Headplane Node.js：本地包 -> npmmirror -> nodejs.org -> NodeSource 最后兜底
- Node.js 二进制包同样进行 SHA256 校验
- 上游版本检查新增 Node.js 22
- 支持 `NODE_DOWNLOAD_BASE` 指定自有可信 Node.js 镜像

网络受限时，可提前把 Tailscale `.tgz + .sha256` 或 Node.js `.tar.xz + .sha256` 上传到 `/root/`，脚本会优先使用本地文件。

### 使用方式

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh
bash /tmp/hs-bootstrap.sh
```

安装后输入：

```bash
hs
```

选择“Peer Relay 管理”即可启用或检查 Peer Relay。

### 注意事项
- 支持 Debian 12+ / Ubuntu 22.04+
- Headscale 升级必须逐 minor 进行，例如 0.27 -> 0.28 -> 0.29
- DERP 需要放行 TCP 服务端口和 UDP 3478
- Peer Relay 需要放行所配置的 UDP 端口，默认 40000
- Peer Relay 参与设备需要 Tailscale 1.86+
- Peer Relay 可用性受客户端、平台和 NAT 环境影响，DERP 仍应保留作为最终兜底
- 自定义镜像需自行确认可信；脚本会校验 SHA256，但镜像和校验文件来自同一自定义源时仍应关注供应链风险
```

## 仓库描述建议

```text
One-click Headscale 0.29 + DERP + Peer Relay deployment and management for self-hosted Tailscale networks.
```

## Topics 建议

```text
headscale tailscale derp peer-relay vpn self-hosted linux bash nginx china vps
```

## 博客 / 视频配套简介

```text
Headscale One Click v2.2.0 在 v2.1.1 的大陆 VPS 安装可靠性基础上，新增安装信息回看和设备连接路径查看功能，并把首次加入 Headscale 的客户端命令统一为 `tailscale login --login-server=...`，安装后维护更直观。
```
