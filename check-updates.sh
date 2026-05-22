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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "缺少依赖命令：$1"
    exit 1
  }
}

curl_quick() {
  curl -fsSL --connect-timeout 15 --max-time 45 "$@"
}

fetch_latest_go() {
  curl_quick https://golang.google.cn/VERSION?m=text | head -n 1 | sed 's/^go//'
}

fetch_latest_headscale() {
  curl_quick https://api.github.com/repos/juanfont/headscale/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headscale_ui() {
  curl_quick https://api.github.com/repos/gurucomputing/headscale-ui/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headplane() {
  curl_quick https://api.github.com/repos/tale/headplane/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

main() {
  require_cmd curl
  require_cmd sed
  require_cmd grep

  info "检查上游最新版本..."

  local go_version="unknown"
  local headscale_version="unknown"
  local headscale_ui_version="unknown"
  local headplane_version="unknown"

  go_version="$(fetch_latest_go 2>/dev/null || echo unknown)"
  headscale_version="$(fetch_latest_headscale 2>/dev/null || echo unknown)"
  headscale_ui_version="$(fetch_latest_headscale_ui 2>/dev/null || echo unknown)"
  headplane_version="$(fetch_latest_headplane 2>/dev/null || echo unknown)"

  echo
  echo "当前建议关注的上游最新版本："
  echo "- Go:            ${go_version}"
  echo "- Headscale:     ${headscale_version}"
  echo "- Headscale-ui:  ${headscale_ui_version}"
  echo "- Headplane:     ${headplane_version}"
  echo

  warn "安装和更新流程默认会使用查询到的最新版。"
  warn "如遇到上游兼容性问题，可在版本输入处手动填写旧版本。"
}

main "$@"
