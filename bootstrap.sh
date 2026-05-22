#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/slobys/headscale-one-click.git}"
INSTALL_DIR="${INSTALL_DIR:-/root/headscale-one-click}"
SHORTCUT="${SHORTCUT:-/usr/local/bin/hs}"

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

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行此命令。"
}

install_git_if_missing() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  info "检测到 git 未安装，尝试自动安装 git..."
  if command -v apt >/dev/null 2>&1; then
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y git ca-certificates curl
  else
    die "当前系统缺少 git，请先安装 git 后重试。"
  fi
}

sync_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    info "检测到已有项目目录，正在更新：${INSTALL_DIR}"
    git -C "$INSTALL_DIR" pull --ff-only
  elif [[ -e "$INSTALL_DIR" ]]; then
    die "安装目录已存在但不是 Git 仓库：${INSTALL_DIR}，请先手动处理后重试。"
  else
    info "正在拉取项目到：${INSTALL_DIR}"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

prepare_scripts() {
  chmod +x \
    "${INSTALL_DIR}/install.sh" \
    "${INSTALL_DIR}/update.sh" \
    "${INSTALL_DIR}/uninstall.sh" \
    "${INSTALL_DIR}/repair.sh" \
    "${INSTALL_DIR}/menu.sh" \
    "${INSTALL_DIR}/check-updates.sh" \
    "${INSTALL_DIR}/bootstrap.sh"

  cat > "$SHORTCUT" <<EOF
#!/usr/bin/env bash
cd "$INSTALL_DIR" || exit 1
exec bash ./menu.sh "\$@"
EOF
  chmod +x "$SHORTCUT"
  success "已安装快捷命令：hs"
}

run_target() {
  local action="${1:-install}"

  cd "$INSTALL_DIR"

  case "$action" in
    install|--install)
      exec bash ./install.sh
      ;;
    menu|--menu)
      exec bash ./menu.sh
      ;;
    update|--update)
      exec bash ./update.sh
      ;;
    check|--check)
      exec bash ./check-updates.sh
      ;;
    repair|--repair)
      exec bash ./repair.sh
      ;;
    *)
      warn "未知参数：${action}，已进入管理菜单。"
      exec bash ./menu.sh
      ;;
  esac
}

main() {
  require_root "$@"
  install_git_if_missing
  sync_repo
  prepare_scripts
  run_target "${1:-install}"
}

main "$@"
