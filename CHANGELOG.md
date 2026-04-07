# Changelog

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
