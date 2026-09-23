# headscale-one-click v2.3.0 Release Notes

## 标题建议

```text
v2.3.0 - 安装流程重构与免 Go DERP
```

## Release 文案

```markdown
## headscale-one-click v2.3.0

这一版重点重构首次安装和重复安装流程，让国内 VPS 更接近“一条命令、快速确认、失败可恢复”，同时让目标服务器彻底摆脱 Go 编译依赖。

### 核心变化
- 新增 Preflight 环境检查：系统、架构、公网 IPv4、磁盘、内存、网络和端口冲突
- 新增“快速安装 / 高级安装”双模式
- 快速安装对新服务器采用推荐稳定值；已有安装会继承原来的 IP、端口和面板
- 新服务器首次安装会随机生成 Headscale TCP、DERP TCP、Peer Relay UDP 端口并永久保存；STUN 保持 3478/udp
- 随机端口会避开常见端口、已监听端口和 Linux 临时端口范围；高级模式仍可手动修改
- DERP 主机名默认直接使用公网 IPv4，无域名也能安装
- DERP 改为项目 Release 预编译二进制 + SHA256 校验，目标 VPS 不再安装 Go
- GitHub Actions 自动构建 `derper-linux-amd64/arm64` 和对应 `.sha256`
- DERP HTTP listener 默认关闭，不再需要 3340/tcp
- 安装结束增加 Headscale /health、Nginx、面板、DERP、STUN、Tailscale 健康检查
- Headplane 更新失败自动回滚，bootstrap 目录替换失败也会恢复旧版本
- 重跑安装时尽量复用 DERP 证书、跳过同版本 Headscale DEB 重装并避免重复生成 API Key
- 完整保留 v2.2.0 的安装信息回看和设备连接路径查看功能

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
- Peer Relay 需要放行安装时生成并保存的 UDP 端口；已有安装继续沿用原端口
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
Headscale One Click v2.3.0 重构了安装链路：先做环境体检，再进入快速/高级模式；DERP 改为 GitHub Release 预编译二进制，目标 VPS 不再安装 Go，并增加端口冲突、健康检查和失败回滚。
```
