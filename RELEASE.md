# headscale-one-click v1.5.0 Release Notes

## 标题建议

```text
v1.5.0 - 首个可用发布版
```

## Release 文案

```markdown
## headscale-one-click v1.5.0

首个可用发布版，基于实际可跑通的博客方案整理而来，目标是把 Headscale、Headscale UI 和 DERP 的部署过程收敛成一个更适合国内服务器使用的一键脚本项目。

### 当前已支持
- 一键安装 Headscale
- 一键部署 Headscale UI
- 一键部署 DERP
- 自动配置 Nginx
- 支持本地安装包优先，提升国内服务器部署成功率
- 支持更新、卸载、修复、菜单管理
- 支持检查 Go / Headscale / Headscale UI 上游最新版本
- 支持可选启用 DERP 防白嫖校验（`--verify-clients`）

### 项目特点
- 基于现有可用脚本整理，不是空想重写
- 优先考虑国内 VPS / 国内云服务器场景
- 默认使用已整理的稳定版本
- 支持手动输入自定义版本
- 适合继续扩展成公开可维护项目

### 使用方式
```bash
git clone https://github.com/slobys/headscale-one-click.git
cd headscale-one-click
chmod +x install.sh update.sh uninstall.sh repair.sh menu.sh check-updates.sh
sudo ./install.sh
```

### 建议
如果你使用的是国内服务器，建议提前准备本地安装包并上传到 `/root/` 或项目目录，以提高安装成功率。

### 注意事项
- 当前版本主要面向 Debian / Ubuntu
- Headscale / DERP / UI 上游版本未来变化后，可能需要继续适配
- 建议在确认环境完全可用后，再启用 `--verify-clients`
```

## 仓库描述建议

```text
One-click installer for Headscale, Headscale UI and DERP server, optimized for China mainland VPS.
```

## Topics 建议

```text
headscale tailscale derp vpn self-hosted linux bash nginx china vps
```

## 博客 / 视频配套简介

```text
这是一个面向国内服务器场景整理的 Headscale + Headscale UI + DERP 一键安装项目，基于已实际跑通的部署方案封装，支持本地安装包优先、菜单管理、更新修复和 DERP 防白嫖校验，更适合长期维护和公开分享。
```
