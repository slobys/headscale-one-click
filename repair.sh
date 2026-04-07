#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

die() {
  error "$*"
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行修复脚本。"

info "开始执行基础修复流程..."

if ! command -v nginx >/dev/null 2>&1; then
  warn "未检测到 nginx，尝试安装..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y nginx
fi

if [[ ! -f /etc/systemd/system/derp.service ]]; then
  warn "未找到 derp.service，DERP 服务可能未正确安装。"
else
  info "检测到 derp.service。"
fi

if [[ ! -f /etc/headscale/config.yaml ]]; then
  warn "未找到 /etc/headscale/config.yaml，Headscale 配置可能缺失。"
else
  info "检测到 Headscale 配置文件。"
fi

if [[ ! -d /var/www/web ]]; then
  warn "未找到 /var/www/web，Headscale Web UI 目录可能缺失。"
else
  info "检测到 Headscale Web UI 目录。"
fi

if [[ -f /etc/nginx/sites-available/headscale-one-click.conf ]]; then
  info "检测到独立 Nginx 站点配置，执行语法检查..."
  if nginx -t; then
    success "Nginx 配置检查通过。"
  else
    warn "Nginx 配置检查失败，请手动检查 /etc/nginx/sites-available/headscale-one-click.conf"
  fi
elif [[ -f /etc/nginx/sites-available/default ]]; then
  info "执行 Nginx 配置检查..."
  if nginx -t; then
    success "Nginx 配置检查通过。"
  else
    warn "Nginx 配置检查失败，请手动检查 /etc/nginx/sites-available/default"
  fi
fi

info "尝试重启服务..."
systemctl daemon-reload || true
systemctl restart derp 2>/dev/null || true
systemctl restart headscale 2>/dev/null || true
systemctl restart nginx 2>/dev/null || true

info "输出服务状态摘要..."
systemctl --no-pager --full status derp 2>/dev/null || true
echo
systemctl --no-pager --full status headscale 2>/dev/null || true
echo
systemctl --no-pager --full status nginx 2>/dev/null || true

echo
success "基础修复流程执行完成。"
warn "如果问题仍未解决，建议重点检查：域名解析、端口放行、Headscale Web UI 压缩包内容，以及 derper 编译阶段是否成功。"
