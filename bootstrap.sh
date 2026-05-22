#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/slobys/headscale-one-click.git}"
REPO_ARCHIVE_URL="${REPO_ARCHIVE_URL:-https://codeload.github.com/slobys/headscale-one-click/tar.gz/refs/heads/main}"
REPO_ARCHIVE_MIRROR_URL="${REPO_ARCHIVE_MIRROR_URL:-https://gh-proxy.com/https://codeload.github.com/slobys/headscale-one-click/tar.gz/refs/heads/main}"
INSTALL_DIR="${INSTALL_DIR:-/root/headscale-one-click}"
SHORTCUT="${SHORTCUT:-/usr/local/bin/hs}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-60}"
BOOTSTRAP_USE_GIT="${BOOTSTRAP_USE_GIT:-0}"

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

install_basic_tools_if_missing() {
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
  fi

  info "检测到基础工具不完整，尝试自动安装 curl / tar..."
  if command -v apt >/dev/null 2>&1; then
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl tar
  else
    die "当前系统缺少 curl/tar，请先安装后重试。"
  fi
}

install_git_if_missing() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  info "需要使用 Git 兜底拉取，正在自动安装 git..."
  if command -v apt >/dev/null 2>&1; then
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y git ca-certificates
  else
    die "当前系统缺少 git，请先安装 git 后重试。"
  fi
}

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$BOOTSTRAP_TIMEOUT" "$@"
  else
    "$@"
  fi
}

download_archive() {
  local tmp_file="/tmp/headscale-one-click-main.tar.gz"
  local tmp_dir="/tmp/headscale-one-click-bootstrap.$$"
  local url

  rm -f "$tmp_file"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"

  for url in "$REPO_ARCHIVE_MIRROR_URL" "$REPO_ARCHIVE_URL"; do
    info "尝试下载项目源码包：${url}"
    if run_with_timeout curl -fL --connect-timeout 15 --retry 2 --retry-delay 2 "$url" -o "$tmp_file"; then
      tar -xzf "$tmp_file" -C "$tmp_dir"
      rm -rf "$INSTALL_DIR"
      mv "$tmp_dir"/headscale-one-click-* "$INSTALL_DIR"
      rm -f "$tmp_file"
      rm -rf "$tmp_dir"
      success "已通过源码包安装项目：${INSTALL_DIR}"
      return 0
    fi
    warn "源码包下载失败，切换下一条线路。"
  done

  rm -f "$tmp_file"
  rm -rf "$tmp_dir"
  return 1
}

sync_repo() {
  if [[ "$BOOTSTRAP_USE_GIT" != "1" ]]; then
    info "优先使用源码包安装，避免国内服务器 git clone 卡住。"
    if download_archive; then
      return 0
    fi
    warn "源码包线路不可用，将尝试 Git 拉取。"
  fi

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    info "检测到已有项目目录，正在更新：${INSTALL_DIR}"
    install_git_if_missing
    if run_with_timeout git -C "$INSTALL_DIR" pull --ff-only; then
      return 0
    fi
    warn "Git 更新超时或失败，将改用源码包刷新项目。"
    download_archive || die "项目更新失败，请检查服务器网络后重试。"
  elif [[ -e "$INSTALL_DIR" ]]; then
    warn "安装目录已存在但不是 Git 仓库，将使用源码包覆盖脚本目录：${INSTALL_DIR}"
    download_archive || die "项目目录刷新失败，请检查服务器网络后重试。"
  else
    info "正在拉取项目到：${INSTALL_DIR}"
    install_git_if_missing
    if run_with_timeout git clone "$REPO_URL" "$INSTALL_DIR"; then
      return 0
    fi
    warn "GitHub 拉取超时或失败，将改用源码包安装。"
    download_archive || die "项目拉取失败，请稍后重试，或手动下载项目后运行 install.sh。"
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
  install_basic_tools_if_missing
  sync_repo
  prepare_scripts
  run_target "${1:-install}"
}

main "$@"
