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

fetch_latest_go() {
  curl -fsSL https://go.dev/VERSION?m=text | head -n 1 | sed 's/^go//'
}

fetch_latest_headscale() {
  curl -fsSL https://api.github.com/repos/juanfont/headscale/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headscale_ui() {
  curl -fsSL https://api.github.com/repos/gurucomputing/headscale-ui/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headplane() {
  curl -fsSL https://api.github.com/repos/tale/headplane/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
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
  echo "- headache-ui:   ${headscale_ui_version}"
  echo "- Headplane:     ${headplane_version}"
  echo

  warn "注意：此脚本只负责检查最新版本，不会自动修改 install.sh。"
  warn "更推荐的维护方式是：先手动测试新版本，再决定是否更新仓库默认值。"
}

main "$@"
