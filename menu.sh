#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PANEL_STATE_FILE="/etc/headscale-one-click/panel.env"
PEER_RELAY_STATE_FILE="/etc/headscale-one-click/peer-relay.env"
HEADSCALE_CONFIG="/etc/headscale/config.yaml"
DERP_SERVICE="/etc/systemd/system/derp.service"
DERP_MAP="/etc/headscale/derp.yaml"

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

load_panel_state() {
  PANEL_TYPE="headscale-ui"
  PANEL_PATH="/web"
  SERVER_IP=""
  HEADSCALE_PORT=""
  HEADSCALE_INTERNAL_PORT="18080"
  HEADSCALE_URL=""
  DERP_HOST=""
  DERP_PORT=""
  DERP_HTTP_PORT=""
  IP_PREFIX=""
  INSTALL_SCRIPT_VERSION=""
  PEER_RELAY_DEFAULT_PORT=""

  if [[ -f "$PANEL_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PANEL_STATE_FILE"
  fi
  [[ "${PANEL_TYPE:-}" == "headache-ui" ]] && PANEL_TYPE="headscale-ui"
  return 0
}


read_headscale_server_url() {
  local url="${HEADSCALE_URL:-}"
  if [[ -z "$url" && -f "$HEADSCALE_CONFIG" ]]; then
    url="$(awk -F': ' '/^server_url:/ {print $2; exit}' "$HEADSCALE_CONFIG" | tr -d '"')"
  fi
  if [[ -z "$url" && -n "${SERVER_IP:-}" && -n "${HEADSCALE_PORT:-}" ]]; then
    url="http://${SERVER_IP}:${HEADSCALE_PORT}"
  fi
  printf '%s\n' "$url"
}

infer_derp_state() {
  if [[ -f "$DERP_SERVICE" ]]; then
    [[ -n "${DERP_HOST:-}" ]] || DERP_HOST="$(sed -nE 's/.*-hostname[ =]+([^ ]+).*/\1/p' "$DERP_SERVICE" | head -n 1)"
    [[ -n "${DERP_PORT:-}" ]] || DERP_PORT="$(sed -nE 's/.* -a :([0-9]+).*/\1/p' "$DERP_SERVICE" | head -n 1)"
    [[ -n "${DERP_HTTP_PORT:-}" ]] || DERP_HTTP_PORT="$(sed -nE 's/.*-http-port[ =]+([0-9]+).*/\1/p' "$DERP_SERVICE" | head -n 1)"
  fi
  if [[ -z "${IP_PREFIX:-}" && -f "$HEADSCALE_CONFIG" ]]; then
    IP_PREFIX="$(sed -nE 's/^[[:space:]]*v4:[[:space:]]*([^[:space:]#]+).*/\1/p' "$HEADSCALE_CONFIG" | head -n 1)"
  fi
  return 0
}

show_install_info() {
  local server_url=""
  local panel_url=""
  local peer_relay_status="未启用"
  local peer_relay_port=""
  local verify_status="未启用"

  load_panel_state
  peer_relay_port="${PEER_RELAY_DEFAULT_PORT:-40000}"
  infer_derp_state
  server_url="$(read_headscale_server_url)"

  if [[ -n "$server_url" ]]; then
    panel_url="${server_url}${PANEL_PATH}"
  else
    panel_url="无法自动识别"
  fi

  if [[ -f "$PEER_RELAY_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PEER_RELAY_STATE_FILE"
    peer_relay_status="已启用"
    peer_relay_port="${PEER_RELAY_PORT:-${PEER_RELAY_DEFAULT_PORT:-40000}}"
  fi

  if [[ -f "$DERP_SERVICE" ]] && grep -q -- '-verify-client-url ' "$DERP_SERVICE"; then
    verify_status="已启用（Headscale /verify）"
  fi

  echo
  echo "================ 当前安装信息 ================"
  echo
  echo "访问地址："
  echo "- 管理面板（${PANEL_TYPE:-headscale-ui}）: ${panel_url}"
  [[ -n "$server_url" ]] && echo "- Headscale 控制地址: ${server_url}"
  echo
  echo "Windows / 普通客户端首次加入："
  if [[ -n "$server_url" ]]; then
    echo "  tailscale login --login-server=${server_url}"
    echo
    echo "Windows 如果提示 tailscale 命令不存在："
    echo "  & \"C:\\Program Files\\Tailscale\\tailscale.exe\" login --login-server=${server_url}"
  else
    echo "  无法自动识别 Headscale 地址，请检查 ${HEADSCALE_CONFIG}"
  fi
  echo
  echo "子网路由示例："
  if [[ -n "$server_url" ]]; then
    echo "  tailscale up --login-server=${server_url} --accept-routes=true"
    echo "  tailscale up --login-server=${server_url} --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset"
  fi
  echo
  echo "DERP："
  echo "- DERP 主机名: ${DERP_HOST:-未知}"
  echo "- DERP Map: ${DERP_MAP}"
  echo "- DERP TCP 端口: ${DERP_PORT:-未知}"
  if [[ "${DERP_HTTP_PORT:-}" == "-1" ]]; then
    echo "- DERP HTTP listener: 已关闭"
  else
    echo "- DERP HTTP 端口: ${DERP_HTTP_PORT:-未知}"
  fi
  echo "- STUN UDP 端口: 3478"
  echo "- 客户端校验: ${verify_status}"
  [[ -n "${IP_PREFIX:-}" ]] && echo "- Tailscale 虚拟内网网段: ${IP_PREFIX%/24}/24"
  echo
  echo "Peer Relay："
  echo "- 状态: ${peer_relay_status}"
  echo "- UDP 端口: ${peer_relay_port}"
  echo "- 管理入口: hs -> 9. Peer Relay 管理"
  echo "- 连接路径: DIRECT -> Peer Relay -> DERP"
  if [[ -n "${INSTALL_SCRIPT_VERSION:-}" ]]; then
    echo
    echo "安装脚本版本: ${INSTALL_SCRIPT_VERSION}"
  fi
  echo
  echo "=============================================="
}

classify_tailscale_status_line() {
  local line="$1"
  case "$line" in
    *"peer-relay"*) printf '%s\n' "Peer Relay" ;;
    *"direct"*) printf '%s\n' "P2P 直连" ;;
    *"relay "*) printf '%s\n' "DERP" ;;
    *"offline"*) printf '%s\n' "离线" ;;
    *) printf '%s\n' "空闲/未建立" ;;
  esac
}

show_connection_paths() {
  local output=""
  local line=""
  local ip=""
  local name=""
  local path=""
  local count=0

  echo
  info "设备连接路径（从当前这台机器的视角）"
  if ! command -v tailscale >/dev/null 2>&1; then
    warn "未检测到 tailscale 命令。"
    return 0
  fi

  if ! output="$(tailscale status 2>&1)"; then
    warn "无法读取 Tailscale 状态。当前设备可能尚未登录 Headscale。"
    echo "$output"
    return 0
  fi

  printf '%-18s %-28s %-18s\n' "IP" "设备" "当前路径"
  printf '%-18s %-28s %-18s\n' "------------------" "----------------------------" "------------------"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    ip="$(awk '{print $1}' <<< "$line")"
    name="$(awk '{print $2}' <<< "$line")"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$ip" == *:* ]] || continue
    [[ -n "$name" ]] || name="未知"
    path="$(classify_tailscale_status_line "$line")"
    printf '%-18s %-28s %-18s\n' "$ip" "$name" "$path"
    count=$((count + 1))
  done <<< "$output"

  if [[ "$count" -eq 0 ]]; then
    warn "没有解析到设备；下面显示原始状态供检查："
    echo "$output"
  fi

  echo
  echo "说明："
  echo "- P2P 直连 = 当前连接直接到对端"
  echo "- Peer Relay = 当前连接经过你配置的 Peer Relay"
  echo "- DERP = 当前连接经过 DERP"
  echo "- 空闲/未建立 = 当前没有足够的活跃连接信息"
  echo "- 这是当前机器到各设备的视角；另一台设备看到的路径可能不同"
  echo
  echo "精确验证某台设备：tailscale ping <设备名或 Tailscale IP>"
}

show_status() {
  echo
  info "服务状态："
  systemctl status derp --no-pager 2>/dev/null || true
  echo
  systemctl status headscale --no-pager 2>/dev/null || true
  echo
  systemctl status nginx --no-pager 2>/dev/null || true
  echo
  systemctl status headplane --no-pager 2>/dev/null || true
}

show_access_info() {
  local panel_type="headscale-ui"
  local panel_path="/web"

  load_panel_state

  echo
  info "常用信息"
  echo "- Headscale 配置文件: /etc/headscale/config.yaml"
  echo "- DERP 服务文件: /etc/systemd/system/derp.service"
  echo "- DERP Map: /etc/headscale/derp.yaml"
  echo "- 当前面板类型: ${PANEL_TYPE:-$panel_type}"
  echo "- 当前面板路径: ${PANEL_PATH:-$panel_path}"
  echo "- Headscale-ui 目录: /var/www/web"
  echo "- Headplane 目录: /opt/headplane"
  echo "- Headplane 配置: /etc/headplane/config.yaml"
  echo "- Peer Relay 管理脚本: ${BASE_DIR}/peer-relay.sh"
  echo "- Peer Relay 状态: /etc/headscale-one-click/peer-relay.env"
  echo "- Nginx 站点配置: /etc/nginx/sites-available/headscale-one-click.conf"
  echo
  echo "常用命令："
  echo "- 查看 DERP 日志: journalctl -u derp -f"
  echo "- 查看 Headscale 日志: journalctl -u headscale -f"
  echo "- 查看 Nginx 日志: journalctl -u nginx -f"
  echo "- 查看 Headplane 日志: journalctl -u headplane -f"
}

service_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

show_service_failure() {
  local service="$1"
  echo
  systemctl status "$service" --no-pager -l 2>/dev/null | tail -n 20 || true
  echo
  echo "最近日志："
  journalctl -u "$service" -n 20 --no-pager 2>/dev/null || true
}

restart_service_checked() {
  local service="$1"
  local label="$2"
  local health_port="18080"

  if ! service_exists "$service"; then
    warn "${label} 未安装，已跳过。"
    return 0
  fi

  case "$service" in
    headscale)
      info "重启前检查 Headscale 配置 ..."
      load_panel_state
      health_port="${HEADSCALE_INTERNAL_PORT:-18080}"
      if ! headscale -c "$HEADSCALE_CONFIG" configtest; then
        error "Headscale configtest 失败，为避免控制端掉线，已取消重启。"
        return 1
      fi
      ;;
    nginx)
      info "重启前检查 Nginx 配置 ..."
      if ! nginx -t; then
        error "Nginx 配置检查失败，已取消重启。"
        return 1
      fi
      ;;
  esac

  info "正在重启 ${label} ..."
  if ! systemctl restart "$service"; then
    error "${label} 重启命令执行失败。"
    show_service_failure "$service"
    return 1
  fi

  sleep 1
  if ! systemctl is-active --quiet "$service"; then
    error "${label} 重启后未处于运行状态。"
    show_service_failure "$service"
    return 1
  fi

  if [[ "$service" == "headscale" ]] && command -v curl >/dev/null 2>&1; then
    local ok=0
    local i
    for i in {1..10}; do
      if curl -fsS --max-time 2 "http://127.0.0.1:${health_port}/health" >/dev/null 2>&1; then
        ok=1
        break
      fi
      sleep 1
    done
    if [[ "$ok" -ne 1 ]]; then
      warn "Headscale 服务已启动，但本机 /health 暂未响应，请稍后再查看状态。"
    fi
  fi

  success "${label} 已成功重启。"
}

restart_all_services() {
  local confirm=""
  local failures=0

  echo
  warn "全部重启会包含 Headscale。重启 Headscale 时，管理面板中的设备可能短暂显示离线，通常会自动重连。"
  read -r -p "确认全部重启？[y/N]: " confirm || true
  [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || {
    info "已取消。"
    return 0
  }

  restart_service_checked derp "DERP" || failures=$((failures + 1))
  restart_service_checked nginx "Nginx" || failures=$((failures + 1))
  restart_service_checked headplane "Headplane" || failures=$((failures + 1))
  restart_service_checked headscale "Headscale" || failures=$((failures + 1))

  echo
  if [[ "$failures" -eq 0 ]]; then
    success "全部已安装服务重启完成。"
  else
    error "有 ${failures} 个服务重启失败，请根据上面的状态和日志处理。"
    return 1
  fi
}

restart_services() {
  local choice=""

  while true; do
    echo
    echo "=========================================="
    echo "  重启服务"
    echo "=========================================="
    echo "1. 重启 DERP"
    echo "2. 重启 Headscale"
    echo "3. 重启 Nginx"
    echo "4. 重启 Headplane"
    echo "5. 全部重启"
    echo "0. 返回"
    echo "=========================================="
    read -r -p "请输入选项: " choice || true

    case "${choice:-}" in
      1)
        restart_service_checked derp "DERP" || true
        pause
        ;;
      2)
        echo
        warn "重启 Headscale 会让设备在管理面板中短暂显示离线。"
        read -r -p "确认重启 Headscale？[y/N]: " choice || true
        if [[ "${choice,,}" == "y" || "${choice,,}" == "yes" ]]; then
          restart_service_checked headscale "Headscale" || true
        else
          info "已取消。"
        fi
        pause
        ;;
      3)
        restart_service_checked nginx "Nginx" || true
        pause
        ;;
      4)
        restart_service_checked headplane "Headplane" || true
        pause
        ;;
      5)
        restart_all_services || true
        pause
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        ;;
    esac
  done
}

show_menu() {
  clear 2>/dev/null || true
  echo "=========================================="
  echo "  Headscale One Click 管理菜单"
  echo "=========================================="
  echo "1. 执行安装"
  echo "2. 执行更新"
  echo "3. 执行卸载"
  echo "4. 查看服务状态"
  echo "5. 重启服务（选择服务）"
  echo "6. 查看常用路径与命令"
  echo "7. 执行修复"
  echo "8. 检查上游最新版本"
  echo "9. Peer Relay 管理"
  echo "10. 查看安装信息"
  echo "11. 查看设备连接路径"
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
      9)
        bash "$BASE_DIR/peer-relay.sh"
        pause
        ;;
      10)
        show_install_info
        pause
        ;;
      11)
        show_connection_paths
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
