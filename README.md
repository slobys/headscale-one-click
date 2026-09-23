# headscale-one-click

一键部署 **Headscale + DERP + 管理面板**，并提供 **Peer Relay** 管理，适合在 Debian / Ubuntu 云服务器上快速搭建自己的 Tailscale 控制端。

当前版本面向 Headscale `0.29.x` 与较新的 Tailscale 客户端：DERP 使用官方 `derper`，通过自签名证书 SHA256 指纹固定工作，不再修改 Tailscale 源码；连接路径可形成 **DIRECT -> Peer Relay -> DERP** 三层兜底。

## 快速开始

### 第一次安装

新服务器首次部署时，使用 root 用户执行下面这一条命令：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh --menu
```

这条命令会自动拉取 / 更新项目、补齐脚本权限，并创建快捷菜单命令 `hs`，随后**直接打开管理菜单**。首次安装时在菜单中选择“执行安装”即可。**这条长命令主要用于第一次初始化，后续日常使用只需要输入 `hs`。**

### 以后主要使用 `hs`

项目后续统一以 **`hs` 管理菜单**作为主要入口。安装完成后，使用 root 用户直接执行：

```bash
hs
```

通过 `hs` 可以统一完成安装、更新、卸载、服务状态检查、服务重启、修复、上游版本检查、Peer Relay 管理，以及查看当前安装信息和设备连接路径。

其中“查看安装信息”可以重新显示管理面板地址、客户端加入命令、DERP / Peer Relay 端口等信息；“查看设备连接路径”会从当前机器的 `tailscale status` 判断活跃连接是 **P2P 直连、Peer Relay 还是 DERP**。

如果执行 `hs` 提示命令不存在，说明当前服务器还没有完成第一次初始化，请先执行上面的首次安装命令。

## 中国大陆 VPS 下载策略

v2.1.0 开始，Tailscale 客户端不再只依赖 `https://tailscale.com/install.sh`：

- 优先检查 `/root/` 和当前目录中的 Tailscale 官方静态包
- 没有本地文件时，直接下载 `pkgs.tailscale.com` 官方静态包
- 安装前强制校验 SHA256；校验失败不会执行二进制
- 静态包线路失败后，才最后尝试官方 `install.sh`
- 如果静态升级后 `tailscaled` 启动失败，会自动恢复原来的 Tailscale 二进制、配置和服务状态
- 如果服务器原本通过 apt 安装 Tailscale，会优先复用 vendor systemd unit，避免长期覆盖包管理器的 unit

例如默认 amd64 服务器可提前准备：

```text
tailscale_1.102.4_amd64.tgz
tailscale_1.102.4_amd64.tgz.sha256
```

上传到 `/root/` 后重新执行脚本即可。也可以通过 `TAILSCALE_DOWNLOAD_BASE` 指定自己的可信镜像目录。

如果选择 Headplane，Node.js 也改为二进制包优先：脚本会尝试国内 `npmmirror` 和 Node.js 官方源，并校验 SHA256；二进制线路全部失败时才使用 NodeSource。网络受限环境可把 `node-v22.23.2-linux-x64.tar.xz`（arm64 对应 `linux-arm64`）及其 `.sha256` 文件上传到 `/root/`，也可以通过 `NODE_DOWNLOAD_BASE` 指定自己的可信 Node.js 镜像根目录。pnpm 会固定安装到 `/usr/local`，避免受 root 用户自定义 npm prefix 影响。

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
- 域名不是必需；默认可以直接使用服务器公网 IPv4

建议根据安装结束时显示的实际值放行这些端口：

- `22/tcp`：SSH
- `80/tcp`、`443/tcp`：如后续接入 HTTP / HTTPS 反代
- Headscale 对外 TCP：**首次安装随机生成一次**
- DERP TCP：**首次安装随机生成一次**
- `3478/udp`：DERP/STUN，保持固定以提高网络兼容性
- Peer Relay UDP：**首次安装随机生成并保存默认值**，实际启用 Peer Relay 时再放行

如果公网访问不了，但服务器本机能访问，优先检查云平台安全组。

## 没有域名怎么办

v2.3.0 开始，**快速安装会自动把检测到的公网 IPv4 同时作为 DERP 主机名**，无需提前购买域名或配置 DNS。

例如检测到：

```text
1.2.3.4
```

脚本会默认使用：

```text
服务器 IP：1.2.3.4
DERP 主机名：1.2.3.4
```

管理面板可以先通过 HTTP 使用：

```text
http://1.2.3.4:<安装时生成的Headscale端口>/web
```

如果后续要做正式 HTTPS 443 部署，再准备域名即可。

## 安装模式

v2.3.0 会先执行 Preflight 环境检查，再让你选择：

```text
1. 快速安装（推荐）
2. 高级安装
```

快速模式不会把“虚拟内网网段”完全隐藏掉，因为这个设置会直接影响后续设备获得的 Tailscale IP。全新安装时会明确询问；已有安装快速重跑则默认保持原网段，避免影响已经注册的设备。

快速安装会自动使用已验证版本和 Headscale-ui；新服务器默认直接使用公网 IP 作为 DERP 主机名，并为 Headscale TCP、DERP TCP、Peer Relay UDP **随机生成一次未占用端口**。同时会单独询问一次 **Tailscale 虚拟内网网段**，默认 `100.64.0.0/24`，可以按自己的规划修改，例如 `100.64.10.0/24`。这些设置会写入状态文件，以后升级、重启继续复用。已经部署过本项目的服务器会继承原来的 IP、端口、虚拟网段和面板设置，不会因为升级突然更换。

高级安装可以自定义：

- 服务器公网 IP
- DERP 主机名（无域名可直接填公网 IP）
- Headscale 端口，默认提供一个未占用随机值
- Tailscale 虚拟内网网段，默认 `100.64.0.0/24`
- DERP 服务端口，默认提供一个不同的未占用随机值
- Peer Relay 默认 UDP 端口，默认提供一个未占用随机值
- Tailscale 客户端版本
- Headscale 版本
- 管理面板及其版本

DERP 的额外 HTTP listener 默认关闭，不再要求输入或放行 `3340/tcp`。目标 VPS 也不再安装 Go。

随机端口只在**首次安装**生成一次，并会主动避开常见端口、当前已监听端口和 Linux 临时端口范围。随机端口可以减少默认端口被批量扫描产生的噪声，但它不是核心安全机制，仍需要依赖 Headscale 身份认证、DERP `/verify`、Peer Relay Grant、云安全组以及后续 HTTPS。

Tailscale 客户端和 DERP 已拆分管理：Tailscale 客户端可使用所选版本；DERP 使用项目 Release 中预编译、已校验的固定测试版本。如果服务器已经安装了相同或更新的 Tailscale 客户端，则直接复用。

系统升级会执行 `apt upgrade -y`。新服务器可以执行；已经跑业务的服务器建议先跳过。

如果服务器已经安装过 Headscale，脚本会先检测版本并备份 `/etc/headscale` 与 `/var/lib/headscale`。Headscale 不允许跨 minor 跳级升级，例如 **0.27 不能直接升级到 0.29，必须先升级到 0.28，再升级到 0.29**。脚本检测到不安全的升级路径会直接停止。

## 安装完成后

管理面板地址：

```text
http://服务器IP:Headscale端口/web
```

例如安装时生成的 Headscale 端口为 `25678`：

```text
http://1.2.3.4:25678/web
```

实际端口以安装摘要或 `hs -> 10. 查看安装信息` 为准。

客户端首次接入（Windows / Linux / macOS 均可指定自定义控制服务器）：

```bash
tailscale login --login-server=http://服务器IP:Headscale端口
```

例如安装时生成的 Headscale 端口为 `25678`：

```bash
tailscale login --login-server=http://1.2.3.4:25678
```

Windows 如果 PowerShell 找不到 `tailscale` 命令，可使用：

```powershell
& "C:\\Program Files\\Tailscale\\tailscale.exe" login --login-server=http://1.2.3.4:25678
```

执行后会打开 Headscale 的注册页面；按照页面给出的 Auth ID，在服务器端完成批准后，Windows 客户端就会加入你的 Headscale 网络。

如果需要接收子网路由：

```bash
tailscale up --login-server=http://1.2.3.4:25678 --accept-routes=true
```

如果需要发布子网路由：

```bash
tailscale up --login-server=http://1.2.3.4:25678 --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset
```

## DERP 工作方式

v2.3.0 起，目标服务器**不再安装 Go，也不再现场编译 derper**。项目 Release 会通过 GitHub Actions 生成：

```text
derper-linux-amd64
derper-linux-amd64.sha256
derper-linux-arm64
derper-linux-arm64.sha256
```

脚本优先使用 `/root/` 或当前目录中的本地文件，没有时再从项目 Release 多线路下载，并在执行前强制校验 SHA256。

脚本还会：

- 生成或复用带正确 IP/DNS SAN 的自签名证书
- 计算证书 DER SHA256 指纹
- 在 `/etc/headscale/derp.yaml` 中写入 `certname: sha256-raw:<指纹>`
- 让 Headscale 直接从本地文件加载 DERP Map
- 显式启用 STUN `3478/udp`
- 关闭额外 DERP HTTP listener（`-http-port -1`）
- 安装时默认建议启用 Headscale `/verify` 接口校验 DERP 客户端，并设置 fail-closed

因此目标 VPS 不需要 Go、GOPROXY 或编译环境，也无需 `InsecureForTests`。

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

快速安装默认使用项目内已验证的稳定版本；高级安装会查询上游 latest，并允许手动选择旧版本。网络查询失败时自动使用项目内 fallback。DERP 本体固定使用 Release 中经过项目测试的预编译版本。

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
