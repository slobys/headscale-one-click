# headscale-one-click v2.1.1 Release Notes

## 标题建议

```text
v2.1.1 - 大陆 VPS 安装可靠性修复
```

## Release 文案

```markdown
## headscale-one-click v2.1.1

这是 v2.1.0 的可靠性修复版，重点处理“服务器原本已有 Tailscale”以及静态升级失败时的回滚问题，不改变 Headscale 0.29 + Peer Relay + 原生 DERP 的总体架构。

### 核心修复
- Tailscale 静态升级前自动备份已有 CLI、daemon、systemd unit 和 `/etc/default/tailscaled`
- 新 `tailscaled` 无法启动时自动恢复原二进制、配置、enable 状态和运行状态
- 如果检测到 apt/vendor 的 `tailscaled.service`，优先继续复用，不再无条件创建 systemd override
- Headplane 的 pnpm 固定安装到 `/usr/local`，避免自定义 npm prefix 导致脚本安装成功但找不到 pnpm
- 保留 v2.1.0 的本地包优先、多线路下载、SHA256 校验和大陆 VPS 安装增强

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
Headscale One Click v2.1.1 在 v2.1.0 的大陆 VPS 下载增强基础上，新增 Tailscale 静态升级失败自动回滚、apt/vendor systemd unit 复用，以及 pnpm 固定安装路径，降低升级现有服务器时的风险。
```
