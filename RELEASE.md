# headscale-one-click v2.0.0 Release Notes

## 标题建议

```text
v2.0.0 - Headscale 0.29 + Peer Relay + 原生 DERP
```

## Release 文案

```markdown
## headscale-one-click v2.0.0

这一版重点升级连接层与长期维护能力：适配 Headscale 0.29，DERP 不再修改 Tailscale 源码，并新增 Peer Relay 管理。

### 核心变化
- Headscale fallback 更新到 0.29.3
- Tailscale/derper fallback 更新到 1.102.4
- Headplane fallback 更新到 0.7.1
- DERP 直接使用官方 derper，不再修改 cert.go
- 自签 DERP 证书使用 SHA256 指纹固定
- DERP Map 改为本地 /etc/headscale/derp.yaml
- 显式启用 STUN 3478/udp
- DERP 客户端校验改为 Headscale /verify，并使用 fail-closed
- 新增 Peer Relay 管理：端口、静态端点、Grant、状态与验证
- Headscale 升级前自动备份，并阻止跨 minor 跳级/降级
- Headscale 配置启动前执行 configtest

### 连接顺序

```text
DIRECT -> Peer Relay -> DERP
```

### Peer Relay 安全策略
脚本只生成 `tailscale.com/cap/relay` Grant 片段并保存到 `/etc/headscale-one-click/peer-relay-grant.hujson`，不会自动创建、修改或覆盖 Headscale policy。

如果检测到已有 `policy.path`，会提示把 Grant 手工合并到现有 `grants`；如果没有检测到文件策略，会提醒先确认是否由面板/数据库管理 policy。policy 一旦定义 `grants`，还必须同时保留正常访问规则，避免其它流量因未匹配 Grant 被意外阻断。

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
Headscale One Click v2 将 Headscale 0.29、官方 DERP、Peer Relay 和管理面板整合到一套脚本中。DERP 不再魔改源码，增加证书指纹固定、STUN 与 Headscale /verify 校验；Peer Relay 可作为直连失败后的高速中继，并继续以 DERP 作为最终兜底。
```
