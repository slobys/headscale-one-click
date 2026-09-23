# Changelog

## Unreleased

## v2.3.0 - 2026-09-23

### Added
- 新增安装前 Preflight：最小依赖、系统/架构、公网 IPv4、磁盘、内存、GitHub/Tailscale 连通性和端口冲突检查
- 新增“快速安装 / 高级安装”双模式；快速模式对新服务器使用推荐默认值，对已有安装尽量继承原有 IP、端口和面板
- 新增 GitHub Actions DERP 构建流程，为 Release 生成 amd64/arm64 预编译 derper 及 SHA256 文件
- 新增安装完成健康检查，验证 Headscale configtest、/health、Nginx、管理面板、DERP、STUN 和 Tailscale
- 新安装为 Headscale TCP、DERP TCP、Peer Relay UDP 随机生成一次未占用端口并持久化；STUN 继续固定 3478/udp

### Changed
- 目标 VPS 不再安装 Go、不再现场编译 derper，改为本地文件优先 + Release 预编译二进制 + SHA256 校验
- DERP 主机名默认使用自动检测到的公网 IPv4，域名改为可选
- 高级模式的公网服务端口默认值也改为随机未占用端口，同时允许手动覆盖；已有安装继续沿用原端口
- DERP HTTP listener 默认关闭（`-http-port -1`），不再输入或开放 3340/tcp
- HTTP Nginx 配置移除 HSTS 响应头；HSTS 留待后续 HTTPS 模式使用
- 重复安装时复用仍有效的 DERP 证书；Headscale 已是目标版本时跳过 DEB 重装；已有安装不再反复生成 API Key
- bootstrap 源码目录替换增加失败回滚
- Headplane 更新保留备份直到新服务启动成功，失败时自动回滚；面板更新不再无必要重启 Headscale / DERP

## v2.2.0 - 2026-09-23

### Added
- 管理菜单新增“查看安装信息”，可重新显示管理地址、Windows 客户端加入命令、子网路由、DERP 和 Peer Relay 信息
- 管理菜单新增“查看设备连接路径”，把 `tailscale status` 翻译为 P2P 直连 / Peer Relay / DERP / 空闲或离线
- 新安装会把 DERP 主机名、DERP/HTTP 端口、IP 网段和脚本版本写入状态文件；旧安装仍可从现有 Headscale/DERP 配置自动推断

### Changed
- 安装完成摘要和 README 的首次客户端接入命令改为 `tailscale login --login-server=...`，更贴近当前 Tailscale/Headscale 的首次登录流程

## v2.1.1 - 2026-09-23

### Changed
- Tailscale 静态包安装前保存已有 CLI、daemon、systemd unit 和 defaults；新服务启动失败时自动恢复安装前状态
- 检测到 apt/vendor 提供的 `tailscaled.service` 时优先复用，不再无条件写入 `/etc/systemd/system/` 覆盖 vendor unit
- Headplane 的 pnpm 明确安装到 `/usr/local`，避免 root 用户自定义 npm prefix 后出现 `pnpm` 不在 PATH 的问题

## v2.1.0 - 2026-09-22

### Added
- Tailscale 客户端新增本地静态包优先、官方静态包下载和 SHA256 强制校验，支持 `TAILSCALE_DOWNLOAD_BASE` 自定义可信镜像
- Headplane 的 Node.js 新增本地二进制包优先、npmmirror / nodejs.org 多线路下载和 SHA256 校验
- 上游版本检查增加 Node.js 22 最新版本

### Changed
- Tailscale 安装不再只依赖 `tailscale.com/install.sh`，静态包失败后才使用该脚本作为最后兜底
- Headplane Node.js 安装不再优先依赖 NodeSource，NodeSource 改为二进制包线路全部失败后的最后兜底
- 基础依赖增加 `xz-utils`，用于解压 Node.js 官方 `.tar.xz` 二进制包

## v2.0.0 - 2026-09-22

### Added
- 新增 `peer-relay.sh` 与“Peer Relay 管理”菜单，可配置 UDP 端口、静态公网端点、状态检查和验证命令
- 新增 Headscale 0.29 Peer Relay Grant 辅助：根据本机 Tailscale IP 生成待合并片段，但始终不自动创建、修改或覆盖用户 policy
- 新增 Headscale 升级前配置/数据库备份、minor 升级路径保护与启动前 `headscale configtest`

### Changed
- DERP 改为直接使用官方稳定版 `derper`，移除 `cert.go` 源码修改方案
- DERP 自签证书改为 SHA256 指纹固定，使用本地 `/etc/headscale/derp.yaml`，移除 `InsecureForTests` 与 Nginx DERP Map 暴露
- DERP 显式启用 STUN `3478/udp`，客户端校验从 `--verify-clients` 改为 Headscale `/verify` admission controller 且 fail-closed
- Headscale fallback 更新为 `0.29.3`，Tailscale/derper fallback 更新为 `1.102.4`，Headplane fallback 更新为 `0.7.1`
- Headscale 0.29 检测到旧 `randomize_client_port` 时先备份再停止升级，要求用户显式迁移到 policy `randomizeClientPort`；同时补充 localhost `trusted_proxies`
- Headscale 0.28 -> 0.29 升级检测到已弃用的 `ephemeral_node_inactivity_timeout` 时只给出迁移提示，不自动重写用户配置
- Headscale API Key 恢复使用上游默认有效期，不再自动创建 9999 天超长期 Key
- 安装 Headscale 官方 DEB 时临时阻止包的 `postinst` 自动启动服务，解除后先 `configtest` 再启动
- Nginx 删除仅用于旧 DERP JSON 的 localhost 80 端口与 `autoindex` 配置

## v1.6.0 - 2026-09-22

### Added
- 新增 `bootstrap.sh` 一条命令入口，自动拉取 / 更新项目、补齐执行权限、安装 `hs` 菜单快捷命令并启动安装
- `README.md` 快速开始改为优先展示一条命令安装方式，同时保留手动 `git clone` 用法

### Changed
- 面板选择、状态文件默认值和路径说明统一为 `Headscale-ui`
- GitHub Release 大文件下载增加 `ghfast.top` 加速线路、低速自动切换和 `GITHUB_PROXY_PREFIX` 手动代理前缀
- DERP 编译改为使用 Tailscale 最新稳定 release，不再使用 `@main` 预发布源码，并保留手动输入旧版本号的能力
- `install.sh` 安装时会自动查询 Go、Tailscale DERP、Headscale、Headscale-ui、Headplane 上游最新版，直接回车默认使用最新版，同时保留手动输入旧版本号的能力
- `update.sh` 更新 Headscale-ui / Headplane 时默认查询并使用上游最新版，同时保留手动输入旧版本号的能力
- 精简 `README.md`，删除重复安装方式、维护者发布建议和项目内部说明，改为面向使用者的安装与使用说明
- 修复 `repair.sh` 对 Headplane 配置格式的错误转换，保持 Headplane v0.6.x 需要的 `server:` 嵌套配置格式
- `repair.sh` 会自动把异常顶层配置恢复为 Headplane v0.6.x 使用的 `server:` 嵌套配置格式
- Headplane systemd 服务改为使用官方默认配置路径，不再额外设置 `HEADPLANE_CONFIG_PATH`
- API Key 自动生成增加重试，降低 Headscale 刚重启未就绪时的失败概率
- Nginx 反代 Host 头改用 `$http_host`，避免 Headplane 在非标准端口下登录时报 `Unexpected Server Error`
- 移除 Headplane 安装选项中的实验性 / 测试用途提示
- 菜单更新流程改为识别当前独立 Nginx 站点配置 `headscale-one-click.conf`，并保留旧 `default` 配置兜底
- 检查上游版本增加网络超时，避免 GitHub/Go 源访问慢时菜单长时间卡住
- 菜单清屏失败时不再中断，提升非标准终端兼容性

## v1.5.6 - 2026-05-21

### Changed
- `install.sh` 默认 Go 版本更新为 `1.26.3`
- `install.sh` 与 `update.sh` 默认 Headplane 版本更新为 `0.6.3`，同步上游安全修复版本
- `install.sh` 将 Headscale 内部监听端口固定为 `127.0.0.1:18080`，避免和 Nginx 对外访问端口冲突
- `install.sh` 调整安装顺序，先修改 Headscale 监听端口再启动 Nginx 反代
- `install.sh` 新增多线路下载逻辑，Go、Headscale、headscale-ui 与 Headplane 源码包会自动尝试国内友好线路
- `install.sh` 为 Headplane 依赖安装设置 npm/pnpm 国内镜像
- `update.sh` 支持自动下载 headscale-ui 与 Headplane 源码包，不再要求手动上传压缩包或依赖 Git 仓库目录
- `README.md` 同步更新本地安装文件和默认版本说明

## v1.5.5 - 2026-04-07

### Changed
- `install.sh` 新增公网 IPv4 自动识别逻辑，服务器 IP 输入项会默认填入检测到的公网地址，同时保留手动修改能力
- `README.md` 同步补充服务器 IP 默认值来源说明

## v1.5.4 - 2026-04-07

### Changed
- `install.sh` 取消 Headscale Web UI 压缩包文件名输入项，统一固定使用 `headscale-ui.zip`
- `README.md` 同步更新安装说明，明确 Go / Headscale 填写版本号，Headscale Web UI 使用固定文件名

## v1.5.3 - 2026-04-07

### Changed
- `install.sh` 将系统升级（`apt upgrade -y`）改为安装时可选询问，避免默认触发系统业务服务重启
- `README.md` 补充系统升级选项说明，帮助在新系统与生产环境之间做更稳妥的选择

## v1.5.2 - 2026-04-07

### Changed
- 统一项目术语，将 `Headscale UI` 调整为 `Headscale Web UI`
- 统一项目术语，将“防白嫖”调整为更适合项目文档的“DERP 客户端校验”表述
- 统一文档与脚本文案中的“本地安装包”为“本地安装文件”，“国内服务器”为“中国大陆服务器环境”
- 同步更新 `README.md`、`RELEASE.md` 与相关脚本提示文案

## v1.5.1 - 2026-04-07

### Changed
- 优化 `README.md` 首页结构，前置一句话介绍、快速开始、适用人群和国内服务器使用提示
- 提升项目首页展示效果，使其更适合 GitHub 首页阅读与博客引流

## v1.5.0 - 2026-04-07

### Changed
- `install.sh` 新增可选交互开关，可在安装完成后选择是否启用 DERP 防白嫖校验（`--verify-clients`）
- `README.md` 新增“DERP 防白嫖说明”章节，解释实际作用、启用时机与手动开启方法

## v1.4.0 - 2026-04-07

### Changed
- `install.sh` 默认版本更新为 Go `1.26.1` 与 Headscale `0.28.0`
- 新增 `check-updates.sh`，用于检查 Go、Headscale、Headscale UI 上游最新版本
- `menu.sh` 新增版本检查入口
- `README.md` 补充稳定版本策略、自定义版本说明和版本检查使用方法

## v1.3.1 - 2026-04-07

### Changed
- 更新 `README.md` 首页快速开始，补充 Git clone 拉取命令、菜单启动命令和仓库地址展示
- 强化国内服务器场景说明，强调本地安装包优先的推荐用法

## v1.3.0 - 2026-04-07

### Changed
- `install.sh` 改为使用独立 Nginx 站点配置，避免直接覆盖默认站点
- 为 Headscale UI 解压结果增加 `index.html` 校验，降低 UI 包结构变化导致的安装假成功风险
- 为 DERP `cert.go` 修改增加前后校验，降低上游源码结构变化带来的隐性失败风险
- 为 Headscale 配置修改增加备份、字段检查与修改结果校验
- 为 Tailscale 客户端安装失败增加更明确的国内网络提示
- 为 API Key 生成失败增加更清晰的后续手动处理提示
- 同步更新 `uninstall.sh`、`repair.sh`、`menu.sh` 和 `README.md`

## v1.2.0 - 2026-04-07

### Added
- 新增 `repair.sh`，用于基础排查、Nginx 配置校验和服务重启
- 更新 `menu.sh`，新增修复入口
- 更新 `install.sh` 下载失败提示，增强国内服务器场景下的引导信息
- 更新 `README.md`，补充修复脚本与发布前检查建议

## v1.1.0 - 2026-04-07

### Added
- 新增 `update.sh`，用于重新部署 Headscale UI、校验 Nginx 配置并重启相关服务
- 新增 `menu.sh`，提供安装、更新、卸载、状态查看、服务重启的菜单管理入口
- 更新 `README.md`，补齐多脚本管理说明与当前项目结构

## v1.0.0 - 2026-04-07

### Added
- 新增 `install.sh`，将 DERP、Tailscale、Headscale、Headscale UI、Nginx 配置整合为一个单脚本安装流程
- 新增国内服务器友好逻辑：优先读取 `/root/` 或当前目录中的本地安装包
- 新增 `README.md`，补齐项目说明、安装步骤、注意事项和 GitHub 发布信息
- 新增 `uninstall.sh`，用于卸载 DERP、Headscale、Headscale UI 以及脚本生成的 Nginx 配置
- 新增 `.gitignore`，避免测试安装包和临时文件误提交到仓库

### Notes
- 当前方案基于现有可用脚本整理，优先保留原博客可运行逻辑
- 当前更适合 Debian / Ubuntu 环境
- 当前仍保留 DERP 相关源码修改思路，后续如上游变更，可能需要进一步适配
