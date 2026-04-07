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

[[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行更新脚本。"

cat <<EOF
这个 update.sh 适合做以下事情：
- 重新部署 Headscale Web UI
- 重新生成/覆盖 Nginx 配置
- 重启 headscale / nginx / derp

注意：
- 当前版本不会自动升级 Go
- 当前版本不会自动升级 Tailscale 客户端
- 当前版本不会自动替你切换 Headscale 大版本
EOF

read -r -p "是否继续执行更新流程？[y/N]: " answer
answer="${answer:-N}"
[[ "$answer" =~ ^[Yy]$ ]] || {
  warn "已取消更新。"
  exit 0
}

WORKDIR="/usr/local/src/headscale-one-click"
HEADSCALE_UI_DIR="/var/www/web"
NGINX_CONF="/etc/nginx/sites-available/default"

read -r -p "请输入 Headscale Web UI 压缩包文件名 [默认: headscale-ui.zip]: " UI_ZIP
UI_ZIP="${UI_ZIP:-headscale-ui.zip}"

if [[ -f "/root/${UI_ZIP}" ]]; then
  info "检测到 /root/${UI_ZIP}，准备更新 Headscale Web UI。"
  mkdir -p "$WORKDIR"
  cp -f "/root/${UI_ZIP}" "$WORKDIR/${UI_ZIP}"
  rm -rf "$HEADSCALE_UI_DIR"
  unzip -o "$WORKDIR/${UI_ZIP}" -d /var/www >/dev/null
  success "Headscale Web UI 更新完成。"
else
  warn "未检测到 /root/${UI_ZIP}，跳过 Headscale Web UI 更新。"
fi

if [[ -f "$NGINX_CONF" ]]; then
  info "检测到 Nginx 配置，执行语法检查并重启。"
  nginx -t
  systemctl restart nginx
fi

systemctl restart headscale 2>/dev/null || true
systemctl restart derp 2>/dev/null || true

success "更新流程执行完成。"
warn "如果你后续要升级 Headscale 本体版本，建议先手动备份配置，再单独做版本更新。"
