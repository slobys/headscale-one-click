#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

pause() {
  read -r -p "按回车继续..." _
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "请使用 root 用户运行菜单脚本。"
    exit 1
  fi
}

show_status() {
  echo
  info "服务状态："
  systemctl status derp --no-pager 2>/dev/null || true
  echo
  systemctl status headscale --no-pager 2>/dev/null || true
  echo
  systemctl status nginx --no-pager 2>/dev/null || true
}

show_access_info() {
  echo
  info "常用信息"
  echo "- Headscale 配置文件: /etc/headscale/config.yaml"
  echo "- DERP 服务文件: /etc/systemd/system/derp.service"
  echo "- DERP JSON: /var/www/derp.json"
  echo "- Headscale UI 目录: /var/www/web"
  echo "- Nginx 站点配置: /etc/nginx/sites-available/headscale-one-click.conf"
  echo
  echo "常用命令："
  echo "- 查看 DERP 日志: journalctl -u derp -f"
  echo "- 查看 Headscale 日志: journalctl -u headscale -f"
  echo "- 查看 Nginx 日志: journalctl -u nginx -f"
}

restart_services() {
  info "重启 derp / headscale / nginx ..."
  systemctl restart derp 2>/dev/null || true
  systemctl restart headscale 2>/dev/null || true
  systemctl restart nginx 2>/dev/null || true
  success "服务重启完成。"
}

show_menu() {
  clear
  echo "=========================================="
  echo "  Headscale One Click 管理菜单"
  echo "=========================================="
  echo "1. 执行安装"
  echo "2. 执行更新"
  echo "3. 执行卸载"
  echo "4. 查看服务状态"
  echo "5. 重启服务"
  echo "6. 查看常用路径与命令"
  echo "7. 执行修复"
  echo "8. 检查上游最新版本"
  echo "0. 退出"
  echo "=========================================="
}

main() {
  require_root

  while true; do
    show_menu
    read -r -p "请输入选项: " choice
    case "$choice" in
      1)
        bash "$BASE_DIR/install.sh"
        pause
        ;;
      2)
        bash "$BASE_DIR/update.sh"
        pause
        ;;
      3)
        bash "$BASE_DIR/uninstall.sh"
        pause
        ;;
      4)
        show_status
        pause
        ;;
      5)
        restart_services
        pause
        ;;
      6)
        show_access_info
        pause
        ;;
      7)
        bash "$BASE_DIR/repair.sh"
        pause
        ;;
      8)
        bash "$BASE_DIR/check-updates.sh"
        pause
        ;;
      0)
        success "已退出。"
        exit 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        pause
        ;;
    esac
  done
}

main "$@"
