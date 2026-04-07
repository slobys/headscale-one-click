# headscale-one-click

一个面向 **中国大陆云服务器 / VPS** 的 **Headscale + Headscale Web UI + DERP 一键安装项目**。

基于已经实际跑通的方案整理而来，目标不是只给出几个能跑的命令，而是做成一套更适合长期维护、公开分享和 GitHub 发布的脚本项目。

仓库地址：

```text
https://github.com/slobys/headscale-one-click
```

## 一句话说明

这是一个适合中国大陆云服务器使用的 Headscale + Headscale Web UI + DERP 一键安装项目，支持本地安装文件优先、菜单管理、版本检查、修复脚本，以及可选启用 DERP 客户端校验。

## 项目亮点

- 单脚本安装：整合 DERP、Headscale、Headscale Web UI、Nginx 配置
- 中国大陆网络友好：支持本地安装文件优先，尽量降低外部下载源不稳定带来的失败率
- 保留原方案思路：尽量贴近已验证可用的部署做法
- 带维护脚本：包含安装、更新、卸载、修复、菜单管理、版本检查
- 支持可选启用 DERP 客户端校验（`--verify-clients`）
- 适合公开发布：补齐 README、CHANGELOG、.gitignore
- 默认使用已验证的稳定版本，同时允许手动输入自定义版本

---

## 快速开始

如果你只想先跑起来，直接用下面这组命令即可：

```bash
git clone https://github.com/slobys/headscale-one-click.git
cd headscale-one-click
chmod +x install.sh update.sh uninstall.sh repair.sh menu.sh check-updates.sh
sudo ./install.sh
```

如果部署环境位于中国大陆网络，强烈建议提前把安装文件传到 `/root/` 或项目目录，再执行安装脚本。

### 方式一：直接从 GitHub 拉取后安装（推荐）

```bash
git clone https://github.com/slobys/headscale-one-click.git
cd headscale-one-click
chmod +x install.sh update.sh uninstall.sh repair.sh menu.sh check-updates.sh
sudo ./install.sh
```

### 方式二：使用菜单管理脚本

```bash
git clone https://github.com/slobys/headscale-one-click.git
cd headscale-one-click
chmod +x install.sh update.sh uninstall.sh repair.sh menu.sh check-updates.sh
sudo ./menu.sh
```

### 方式三：先检查上游是否有新版本

```bash
git clone https://github.com/slobys/headscale-one-click.git
cd headscale-one-click
chmod +x check-updates.sh
./check-updates.sh
```

### 中国大陆服务器环境强烈建议先准备本地安装文件

这是本项目成功率最高的一种用法，尤其适合：

- 阿里云 / 腾讯云 / 华为云等中国大陆云服务器
- GitHub / go.dev / tailscale.com 偶发访问不稳定的环境
- 想减少安装中途失败概率的场景

上传到 `/root/` 或脚本当前目录：

- `go1.26.1.linux-amd64.tar.gz` 或 arm64 对应版本
- `headscale_0.28.0_linux_amd64.deb` 或 arm64 对应版本
- `headscale-ui.zip`

这样会明显提高国内服务器安装成功率。

---

## 项目说明

这个项目整合了两部分：

1. `tailscale.sh` 的 DERP 安装逻辑
2. `headache.sh` 的 Headscale + Headscale Web UI + Nginx 配置逻辑

最终收敛成一个 `install.sh`，目标效果是：

```bash
chmod +x install.sh
sudo ./install.sh
```

然后按提示输入参数，自动完成：

- Go 安装
- DERP 编译和部署
- Tailscale 客户端安装
- Headscale 安装
- Headscale Web UI 解压部署
- Nginx 配置
- Headscale 配置修改
- DERP JSON 生成
- API Key 生成

---

## 适合谁用

这个项目尤其适合以下场景：

- 想在中国大陆 VPS / 云服务器上部署 Headscale
- 想同时配好 Headscale Web UI 和自建 DERP
- 不想再手工拆开多个脚本逐步执行
- 想做成可长期维护、可上传 GitHub 的脚本项目
- 想控制 DERP 被公网其他客户端白嫖的风险

## 适用环境

当前版本优先面向：

- Debian / Ubuntu
- 中国大陆 VPS / 云服务器
- root 环境
- x86_64 / arm64

> 当前版本优先按 Debian / Ubuntu 流程做，CentOS 系暂未纳入这版单脚本。

---

## 中国大陆服务器使用说明

本项目针对 **中国大陆服务器可安装** 场景，做了两个关键处理：

### 1. Go 使用国内代理

脚本内会自动设置：

```bash
go env -w GOPROXY=https://goproxy.cn,direct
```

### 2. 安装文件优先读取本地文件

如果你提前把这些文件传到 `/root/` 或当前目录，脚本会优先使用本地文件，不强依赖外网下载。

建议你提前准备：

- `go1.26.1.linux-amd64.tar.gz` 或 arm64 对应版本
- `headscale_0.28.0_linux_amd64.deb` 或 arm64 对应版本
- `headscale-ui.zip`

这样在中国大陆服务器环境中的安装成功率会高很多。

---

## 文件结构

```bash
headscale-one-click/
├─ README.md
├─ CHANGELOG.md
├─ .gitignore
├─ install.sh
├─ update.sh
├─ uninstall.sh
├─ repair.sh
└─ menu.sh
```

---

## 安装前准备

### 1）准备域名

用于 DERP 自签名证书，例如：

```text
derp.example.com
```

### 2）确认服务器公网 IP

脚本需要你输入公网 IP，例如：

```text
1.2.3.4
```

### 3）准备 Headscale Web UI 压缩包

由于 Headscale Web UI 资源在中国大陆网络环境中下载不一定稳定，建议先把压缩包上传到：

- `/root/headscale-ui.zip`

或者脚本当前目录。

### 4）手动放行端口

这版脚本不会直接像原始脚本那样清空防火墙。

请你自行确认这些端口已放行：

- Headscale 端口
- DERP 服务端口
- DERP HTTP 端口
- 如果用 80/443 反代，也要放行 80/443

---

## 使用方法

先给脚本执行权限：

```bash
chmod +x install.sh
```

然后执行：

```bash
sudo ./install.sh
```

### 关于系统升级选项

安装脚本会先询问是否执行：

```bash
apt upgrade -y
```

默认建议根据实际环境决定：

- 新系统 / 干净测试机：可以选择执行
- 已跑业务的 VPS / 面板机 / NAS：更建议谨慎，必要时先跳过

这样可以减少安装过程中因系统升级触发其它服务重启而带来的干扰。

脚本会依次询问：

- 是否先执行系统升级（`apt upgrade -y`）
- 域名
- 服务器 IP
- Headscale 端口
- IP 前缀
- DERP 端口
- HTTP 端口
- Go 版本
- Headscale 版本
- Headscale Web UI 压缩包文件名

常见示例：

- 域名：`derp.example.com`
- 服务器IP：`1.2.3.4`
- Headscale端口：`8080`
- IP前缀：`100.64.0.0`
- DERP端口：`12345`
- HTTP端口：`3340`
- Go版本：`1.26.1`
- Headscale版本：`0.28.0`
- Headscale Web UI 压缩包：`headscale-ui.zip`

---

## DERP 客户端校验说明

这是本项目比较实用、也比较有辨识度的一个功能点。

原方案里的“防白嫖”功能，本质上是通过为 `derp` 增加：

```bash
--verify-clients
```

来限制谁可以使用当前服务器提供的 DERP 中继服务。

### 它的实际作用

- 降低公网其他客户端滥用 DERP 中继的风险
- 减少带宽、流量和中继资源被无关节点占用
- 让 DERP 更偏向只服务于当前 Headscale 网络节点

### 为什么不建议一开始就默认强开

因为如果 Headscale、DERP、客户端接入流程还没完全跑通，过早启用它，可能会导致：

- 自己的客户端也无法正常通过 DERP
- 看起来像 DERP 挂了
- 增加排障难度

所以当前脚本采用的是：

- 安装完成后询问是否启用
- 默认不强制启用
- 建议在确认环境已经正常后再打开

### 手动开启方法

编辑：

```bash
/etc/systemd/system/derp.service
```

在 `ExecStart` 最后追加：

```bash
--verify-clients
```

然后执行：

```bash
systemctl daemon-reload
systemctl restart derp
```

## 安装完成后

安装完成后，可通过下面地址访问：

```text
http://服务器IP:Headscale端口/web
```

例如：

```text
http://1.2.3.4:8080/web
```

客户端接入命令：

```bash
tailscale up --login-server=http://服务器IP:Headscale端口
```

例如：

```bash
tailscale up --login-server=http://1.2.3.4:8080
```

子网路由参考：

```bash
tailscale up --login-server=http://1.2.3.4:8080 --accept-routes=true
```

或：

```bash
tailscale up --login-server=http://1.2.3.4:8080 --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset
```

---

## 与原始脚本相比的调整

这版整合脚本保留了你原始方案的核心逻辑，但做了这些整理：

- 把两个脚本合并成一个 `install.sh`
- 增加错误处理和日志输出
- 增加系统与架构检测
- 增加本地安装文件优先逻辑
- 不默认直接关闭系统防火墙
- Nginx 改为独立站点配置，避免直接覆盖默认站点
- 增加 Headscale Web UI 解压结果校验
- 增加 DERP 源码修改生效校验
- 安装顺序更清晰
- 更适合直接作为 GitHub 项目发布

---

## 注意事项

### 1）这版仍然保留了原方案的 DERP 修改方式

也就是对 `cert.go` 做注释处理，以适配你当前验证可用的方案。

这意味着：

- 更接近你现有脚本的行为
- 但也意味着后续上游源码变动时，可能需要重新调整

### 2）Headscale Web UI 建议本地上传

中国大陆服务器环境中，很多外部下载源不稳定。Headscale Web UI 最好先下载好，再上传到服务器。

### 3）如果后面继续按博客做“白嫖”设置

可手动编辑：

```bash
/etc/systemd/system/derp.service
```

在 `ExecStart` 最后追加：

```bash
--verify-clients
```

然后执行：

```bash
systemctl daemon-reload
systemctl restart derp
```

---

## 管理脚本

### 安装

```bash
sudo ./install.sh
```

### 更新

```bash
sudo ./update.sh
```

当前 `update.sh` 主要用于：

- 重新部署 Headscale Web UI
- 校验并重启 Nginx
- 重启 Headscale / DERP 服务

### 卸载

```bash
sudo ./uninstall.sh
```

用于删除：

- derp.service
- DERP 证书
- Headscale Web UI
- 当前脚本生成的 Nginx 独立站点配置
- Headscale

### 修复

```bash
sudo ./repair.sh
```

适合用于基础排查和快速修复，会尝试：

- 检查 nginx 是否存在
- 检查 DERP / Headscale 配置文件是否存在
- 检查 Headscale Web UI 目录是否存在
- 校验 Nginx 配置
- 重启 derp / headscale / nginx

### 菜单管理

```bash
sudo ./menu.sh
```

适合不想记命令的场景，可以通过菜单执行安装、更新、卸载、修复、查看状态和重启服务。

---

## 版本策略说明

这个项目不建议做成“永远自动追最新版本安装”。

原因很简单：

- Go 会更新
- Headscale 会更新
- Headscale Web UI 也会更新
- 上游 release 文件名、配置模板、压缩包结构都可能变化

如果安装脚本强行永远追最新，长期来看反而更容易翻车。

所以当前项目采用的是：

### 默认策略
- `install.sh` 默认使用当前已整理的稳定版本
- 你也可以在运行时手动输入其它版本

### 长期维护策略
- 通过 `check-updates.sh` 查看上游是否有新版本
- 先手动测试新版本是否兼容
- 确认可用后，再更新仓库默认值

这比“盲目自动追最新”更适合公开一键脚本项目长期维护。

## 推荐仓库名

```text
headscale-one-click
```

## 推荐仓库描述

```text
One-click installer for Headscale, Headscale UI and DERP server, optimized for China mainland VPS.
```

## 推荐 Topics

```text
headscale tailscale derp vpn self-hosted linux bash china nginx
```

---

## GitHub 上传命令

```bash
git init
git add .
git commit -m "feat: add one-click installer for headscale derp and ui"
git branch -M main
git remote add origin <repository-url>
git push -u origin main
```

如果你要做一个更像公开项目的首发仓库，推荐提交前确认以下几点：

- `README.md` 里的端口、文件名、版本号是否与你视频/博客一致
- `install.sh` 中默认版本是否需要固定
- 是否把测试用安装文件留在仓库外，不要一起提交
- 是否补一个仓库截图或博客链接，方便 GitHub 首页展示

---

## 发布前自检建议

正式发 GitHub 之前，建议你自己再过一遍这几项：

1. 在一台全新 Debian / Ubuntu 机器上完整跑一次 `install.sh`
2. 确认 `/root/` 本地安装文件优先逻辑正常
3. 确认 `headscale-ui.zip` 解压后目录结构确实落在 `/var/www/web`
4. 确认 `http://服务器IP:Headscale端口/web` 能正常打开
5. 确认 `headscale apikeys create --expiration 9999d` 在目标版本中可用
6. 确认 `menu.sh`、`update.sh`、`repair.sh` 都能正常执行
7. 确认博客中的命令示例与你仓库 README 一致

---

## 博客 / 视频配套建议

如果后续计划将本项目配套到博客或视频中，建议这样组织：

- 博客正文讲原理和操作步骤
- GitHub 仓库放最终脚本项目
- README 首页只讲最核心的安装与使用
- 把“中国大陆服务器建议先上传本地安装文件”写在前面显眼位置

这样读者更容易跟着跑，也更像一个完整作品。

---

## 后续可继续扩展

如果后续计划将本项目继续扩展为更完整的公开项目，建议继续增加：

- 一键申请 HTTPS 证书
- 一键创建 namespace / preauth key / users
- DERP / Headscale 状态检测增强
- 自动检测公网 IP / 域名解析
- 一键切换 DERP / Headscale 下载源
- 自动备份并恢复 Headscale 关键配置

---

## 免责声明

本项目仅供学习、测试、自建环境部署参考。

请在理解以下风险后再用于公网环境：

- 自签名证书风险
- 防火墙策略风险
- DERP 修改源码风险
- 上游文件名或源码结构变化风险
- 公网暴露风险
