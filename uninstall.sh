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

PANEL_STATE_FILE="/etc/headscale-one-click/panel.env"
PEER_RELAY_STATE_FILE="/etc/headscale-one-click/peer-relay.env"
DERP_MAP="/etc/headscale/derp.yaml"
GRANT_SNIPPET_FILE="/etc/headscale-one-click/peer-relay-grant.hujson"
HEADPLANE_DIR="/opt/headplane"
HEADPLANE_CONFIG_DIR="/etc/headplane"
HEADPLANE_DATA_DIR="/var/lib/headplane"
HEADPLANE_SERVICE="/etc/systemd/system/headplane.service"
CERTBOT_VENV="/opt/headscale-one-click/certbot"
CERTBOT_RENEW_SERVICE="/etc/systemd/system/headscale-one-click-certbot-renew.service"
CERTBOT_RENEW_TIMER="/etc/systemd/system/headscale-one-click-certbot-renew.timer"
ACME_WEBROOT="/var/www/headscale-one-click-acme"
ACME_NGINX_AVAILABLE="/etc/nginx/sites-available/headscale-one-click-acme.conf"
ACME_NGINX_ENABLED="/etc/nginx/sites-enabled/headscale-one-click-acme.conf"

load_panel_state() {
  PANEL_TYPE="headscale-ui"

  if [[ -f "$PANEL_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PANEL_STATE_FILE"
  fi
  [[ "$PANEL_TYPE" == "headache-ui" ]] && PANEL_TYPE="headscale-ui"
  return 0
}

load_panel_state

cat <<EOF
你即将卸载以下内容：
- DERP 服务与证书
- Headscale 服务
- 当前已安装的管理面板文件
- 当前脚本生成的 Nginx 独立站点配置
- 项目专用 Certbot 运行环境与自动续期 Timer
- /etc/headscale/derp.yaml（脚本生成的自建 DERP Map）
- Peer Relay 本地状态和 Grant 示例片段

注意：
- 不会自动删除 Tailscale 客户端
- 不会删除或修改你自己的 Headscale policy
- 不会自动删除 /etc/letsencrypt 中已经签发的证书，以免影响其它服务
- 不会自动清空你系统其它业务文件
EOF

read -r -p "确认继续卸载？[y/N]: " answer
answer="${answer:-N}"
[[ "$answer" =~ ^[Yy]$ ]] || {
  warn "已取消卸载。"
  exit 0
}

if [[ -f "$PEER_RELAY_STATE_FILE" ]] && command -v tailscale >/dev/null 2>&1; then
  info "关闭由本项目启用的 Peer Relay..."
  tailscale set --relay-server-port="" --relay-server-static-endpoints="" 2>/dev/null || true
fi

info "停止并禁用服务..."
systemctl stop derp 2>/dev/null || true
systemctl disable derp 2>/dev/null || true
systemctl stop headscale 2>/dev/null || true
systemctl disable headscale 2>/dev/null || true
systemctl stop headplane 2>/dev/null || true
systemctl disable headplane 2>/dev/null || true
systemctl stop headscale-one-click-certbot-renew.timer 2>/dev/null || true
systemctl disable headscale-one-click-certbot-renew.timer 2>/dev/null || true

info "删除 DERP 服务文件与证书..."
rm -f /etc/systemd/system/derp.service
rm -rf /etc/derp

info "删除面板文件与自建 DERP Map..."
rm -rf /var/www/web
rm -f "$DERP_MAP"
rm -rf "$HEADPLANE_DIR"
rm -rf "$HEADPLANE_CONFIG_DIR"
rm -rf "$HEADPLANE_DATA_DIR"
rm -f "$HEADPLANE_SERVICE"
rm -f "$PANEL_STATE_FILE"
rm -f "$PEER_RELAY_STATE_FILE"
rm -f "$GRANT_SNIPPET_FILE"
rm -rf "$CERTBOT_VENV" "$ACME_WEBROOT"
rm -f "$CERTBOT_RENEW_SERVICE" "$CERTBOT_RENEW_TIMER"

info "删除脚本生成的 Nginx 配置..."
rm -f /etc/nginx/sites-enabled/headscale-one-click.conf
rm -f /etc/nginx/sites-available/headscale-one-click.conf
rm -f "$ACME_NGINX_ENABLED" "$ACME_NGINX_AVAILABLE"

info "尝试卸载 Headscale..."
apt-get remove -y headscale 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

systemctl daemon-reload
nginx -t >/dev/null 2>&1 && systemctl restart nginx || true

success "卸载完成。"
warn "为避免误删其它用途依赖，本脚本没有删除 Tailscale，也保留 /etc/letsencrypt 中已签发证书。"
