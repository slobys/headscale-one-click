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

PANEL_STATE_FILE="/etc/headscale-one-click/panel.env"
HEADPLANE_DIR="/opt/headplane"
HEADPLANE_SERVICE="/etc/systemd/system/headplane.service"
HEADPLANE_FALLBACK_VERSION="0.6.3"
HEADSCALE_UI_FALLBACK_VERSION="2026.03.17"

load_panel_state() {
  PANEL_TYPE="headache-ui"
  PANEL_PATH="/web"

  if [[ -f "$PANEL_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PANEL_STATE_FILE"
  fi
}

find_or_download_file() {
  local filename="$1"
  local output_path="$2"
  shift 2
  local urls=("$@")
  local url=""

  if [[ -f "/root/${filename}" ]]; then
    info "检测到本地文件 /root/${filename}，优先使用本地安装文件。"
    cp -f "/root/${filename}" "$output_path"
    return 0
  fi

  if [[ -f "./${filename}" ]]; then
    info "检测到当前目录文件 ${filename}，优先使用本地安装文件。"
    cp -f "./${filename}" "$output_path"
    return 0
  fi

  warn "未找到本地文件 ${filename}，尝试联网下载。"
  for url in "${urls[@]}"; do
    [[ -n "$url" ]] || continue
    info "尝试下载：${url}"
    if curl -fL --retry 3 --connect-timeout 20 --max-time 600 -o "$output_path" "$url"; then
      success "下载完成：${filename}"
      return 0
    fi
    warn "该线路下载失败，尝试下一条线路。"
  done

  die "下载失败：${filename}。可手动上传到 /root/ 或脚本当前目录后重试。"
}

curl_quick() {
  curl -fsSL --connect-timeout 15 --max-time 45 "$@"
}

fetch_latest_headscale_ui() {
  curl_quick https://api.github.com/repos/gurucomputing/headscale-ui/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headplane() {
  curl_quick https://api.github.com/repos/tale/headplane/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

prompt_version_value() {
  local var_name="$1"
  local name="$2"
  local latest_value="$3"
  local fallback_value="$4"
  local default_value="$latest_value"
  local input_value=""

  if [[ -z "$default_value" || "$default_value" == "unknown" ]]; then
    default_value="$fallback_value"
    warn "${name} 最新版本查询失败，默认使用已验证版本 ${fallback_value}。"
  fi

  read -r -p "请输入 ${name} 版本 [默认: 最新 ${default_value}，可手动输入旧版本]: " input_value || true
  input_value="${input_value:-$default_value}"
  printf -v "$var_name" '%s' "$input_value"
}

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
NGINX_CONF="/etc/nginx/sites-available/headscale-one-click.conf"
NGINX_FALLBACK_CONF="/etc/nginx/sites-available/default"

load_panel_state

if [[ "$PANEL_TYPE" == "headplane" ]]; then
  HEADPLANE_LATEST_VERSION="$(fetch_latest_headplane 2>/dev/null || echo unknown)"
  prompt_version_value HEADPLANE_VERSION "Headplane" "$HEADPLANE_LATEST_VERSION" "$HEADPLANE_FALLBACK_VERSION"

  info "准备更新 Headplane 到 v${HEADPLANE_VERSION} ..."
  [[ -d "$HEADPLANE_DIR" ]] || die "未检测到 ${HEADPLANE_DIR}，当前看起来不像已安装 Headplane。"

  mkdir -p "$WORKDIR"
  source_name="headplane-v${HEADPLANE_VERSION}.tar.gz"
  source_path="${WORKDIR}/${source_name}"
  source_url="https://github.com/tale/headplane/archive/refs/tags/v${HEADPLANE_VERSION}.tar.gz"
  backup_dir="${HEADPLANE_DIR}.bak.$(date +%s)"
  staging_dir="${WORKDIR}/headplane-v${HEADPLANE_VERSION}"

  find_or_download_file "$source_name" "$source_path" \
    "https://gh-proxy.com/${source_url}" \
    "$source_url"

  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  tar -xzf "$source_path" -C "$staging_dir" --strip-components=1

  pushd "$staging_dir" >/dev/null
  pnpm config set registry https://registry.npmmirror.com
  pnpm install --frozen-lockfile
  pnpm build
  popd >/dev/null

  mv "$HEADPLANE_DIR" "$backup_dir"
  mv "$staging_dir" "$HEADPLANE_DIR"
  rm -rf "$backup_dir"

  if [[ -f "$HEADPLANE_SERVICE" ]]; then
    systemctl daemon-reload
    systemctl restart headplane
  fi

  success "Headplane 更新完成。"
else
  HEADSCALE_UI_LATEST_VERSION="$(fetch_latest_headscale_ui 2>/dev/null || echo unknown)"
  prompt_version_value HEADSCALE_UI_VERSION "Headscale-ui" "$HEADSCALE_UI_LATEST_VERSION" "$HEADSCALE_UI_FALLBACK_VERSION"

  UI_ZIP="headscale-ui.zip"
  UI_URL="https://github.com/gurucomputing/headscale-ui/releases/download/${HEADSCALE_UI_VERSION}/${UI_ZIP}"

  mkdir -p "$WORKDIR"
  find_or_download_file "$UI_ZIP" "$WORKDIR/${UI_ZIP}" \
    "https://gh-proxy.com/${UI_URL}" \
    "$UI_URL"
  rm -rf "$HEADSCALE_UI_DIR"
  unzip -o "$WORKDIR/${UI_ZIP}" -d /var/www >/dev/null
  success "Headscale Web UI 更新完成。"
fi

if [[ -f "$NGINX_CONF" || -f "$NGINX_FALLBACK_CONF" ]]; then
  info "检测到 Nginx 配置，执行语法检查并重启。"
  nginx -t
  systemctl restart nginx
fi

systemctl restart headscale 2>/dev/null || true
systemctl restart derp 2>/dev/null || true
systemctl restart headplane 2>/dev/null || true

success "更新流程执行完成。"
warn "如果你后续要升级 Headscale 本体版本，建议先手动备份配置，再单独做版本更新。"
