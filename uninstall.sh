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

[[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行卸载脚本。"

cat <<EOF
你即将卸载以下内容：
- DERP 服务与证书
- Headscale 服务
- Headscale Web UI 文件
- 当前脚本生成的 Nginx 独立站点配置
- /var/www/derp.json

注意：
- 不会自动删除 Tailscale 客户端
- 不会自动删除 Go 环境
- 不会自动清空你系统其它业务文件
EOF

read -r -p "确认继续卸载？[y/N]: " answer
answer="${answer:-N}"
[[ "$answer" =~ ^[Yy]$ ]] || {
  warn "已取消卸载。"
  exit 0
}

info "停止并禁用服务..."
systemctl stop derp 2>/dev/null || true
systemctl disable derp 2>/dev/null || true
systemctl stop headscale 2>/dev/null || true
systemctl disable headscale 2>/dev/null || true

info "删除 DERP 服务文件与证书..."
rm -f /etc/systemd/system/derp.service
rm -rf /etc/derp

info "删除 Headscale Web UI 与 DERP JSON..."
rm -rf /var/www/web
rm -f /var/www/derp.json

info "删除脚本生成的 Nginx 配置..."
rm -f /etc/nginx/sites-enabled/headscale-one-click.conf
rm -f /etc/nginx/sites-available/headscale-one-click.conf

info "尝试卸载 Headscale..."
apt-get remove -y headscale 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

systemctl daemon-reload
nginx -t >/dev/null 2>&1 && systemctl restart nginx || true

success "卸载完成。"
warn "如果你后续还想继续复用这台机器，本脚本特意没有删除 Tailscale 和 Go，避免误删其它用途依赖。"
