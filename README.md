# headscale-one-click

一键部署 **Headscale + DERP + 管理面板**，适合在 Debian / Ubuntu 云服务器上快速搭建自己的 Tailscale 控制端。

脚本会自动安装 Headscale、DERP、Nginx 和管理面板，并优先使用对中国大陆服务器更友好的下载线路。

## 快速安装

使用 root 用户执行：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh
```

这条命令会自动：

- 拉取 / 更新项目到 `/root/headscale-one-click`
- 补齐脚本执行权限
- 安装快捷菜单命令 `hs`
- 启动交互式安装

安装完成后，随时输入下面命令打开管理菜单：

```bash
hs
```

如果只想打开菜单，不直接安装：

```bash
curl -L --connect-timeout 15 https://cdn.jsdelivr.net/gh/slobys/headscale-one-click@main/bootstrap.sh -o /tmp/hs-bootstrap.sh && bash /tmp/hs-bootstrap.sh --menu
```

## 适用环境

- Debian / Ubuntu
- x86_64 / arm64
- root 用户
- 建议使用全新 VPS 或没有重要业务的服务器

暂不建议直接用于 CentOS / Rocky / AlmaLinux。

## 安装前准备

你需要准备：

- 一台有公网 IP 的服务器
- 已放行所需端口的云安全组 / 防火墙
- 一个域名更佳，没有域名也可以先用公网 IP 测试

建议放行这些端口：

- `22/tcp`：SSH
- `80/tcp`、`443/tcp`：如后续接入 HTTP / HTTPS 反代
- Headscale 对外端口，默认 `8080`
- DERP 服务端口，默认 `12345`
- DERP HTTP 端口，默认 `3340`

如果公网访问不了，但服务器本机能访问，优先检查云平台安全组。

## 没有域名怎么办

只是测试时，可以在安装提示里把“域名”和“服务器 IP”都填服务器公网 IP。

例如：

```text
1.2.3.4
```

这样可以先通过 HTTP 跑起来：

```text
http://1.2.3.4:8080/web
```

长期使用仍然建议准备一个域名。DERP、HTTPS 证书和客户端连接稳定性都更适合使用域名。

## 安装时会问什么

脚本会按提示询问：

- 是否执行系统升级
- 域名
- 服务器 IP
- Headscale 端口，默认 `8080`
- IP 前缀，默认 `100.64.0.0`
- DERP 服务端口，默认 `12345`
- DERP HTTP 端口，默认 `3340`
- Go 版本，默认使用上游最新版本，可手动输入旧版本
- Headscale 版本，默认使用上游最新版本，可手动输入旧版本
- 管理面板类型
- Headscale-ui 或 Headplane 版本，默认使用上游最新版本，可手动输入旧版本

一般情况下直接回车使用默认值即可。

系统升级会执行 `apt upgrade -y`。新服务器可以执行；已经跑业务的服务器建议先跳过。

## 安装完成后

管理面板地址：

```text
http://服务器IP:Headscale端口/web
```

示例：

```text
http://1.2.3.4:8080/web
```

客户端接入：

```bash
tailscale up --login-server=http://服务器IP:Headscale端口
```

示例：

```bash
tailscale up --login-server=http://1.2.3.4:8080
```

如果需要接收子网路由：

```bash
tailscale up --login-server=http://1.2.3.4:8080 --accept-routes=true
```

如果需要发布子网路由：

```bash
tailscale up --login-server=http://1.2.3.4:8080 --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset
```

## 常用路径

```text
/root/headscale-one-click                  项目目录
/etc/headscale/config.yaml                 Headscale 配置
/etc/systemd/system/derp.service           DERP 服务
/var/www/derp.json                         DERP 配置 JSON
/var/www/web                               headache-ui 目录
/opt/headplane                             Headplane 目录
/etc/nginx/sites-available/headscale-one-click.conf  Nginx 站点配置
```

## 版本策略

脚本安装和更新时会先查询上游 latest，直接回车默认使用最新版。

如果新版本临时有兼容性问题，可以在版本输入处手动填写旧版本号回退。

你可以用下面命令检查上游版本：

```bash
hs
```

然后选择“检查上游最新版本”。

## 免责声明

本项目仅供学习、测试和自建环境使用。请确认你理解公网暴露、自签名证书、防火墙配置、DERP 源码适配和上游版本变化带来的风险。
