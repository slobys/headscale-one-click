#!/usr/bin/env bash
set -Eeuo pipefail

PANEL_STATE_FILE="/etc/headscale-one-click/panel.env"
PEER_RELAY_STATE_FILE="/etc/headscale-one-click/peer-relay.env"
HEADSCALE_CONFIG="/etc/headscale/config.yaml"
GRANT_SNIPPET_FILE="/etc/headscale-one-click/peer-relay-grant.hujson"
DEFAULT_PORT="40000"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

die() {
  error "$*"
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行此脚本。"
}

version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$2" ]]
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

validate_policy_selector() {
  local selector="$1"
  [[ "$selector" =~ ^[A-Za-z0-9_.*:@/+\-]+$ ]]
}

validate_ipv4() {
  local ip="$1"
  local IFS='.'
  local -a octets=()
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a octets <<< "$ip"
  [[ "${#octets[@]}" -eq 4 ]] || return 1
  local octet
  for octet in "${octets[@]}"; do
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

load_state() {
  SERVER_IP=""
  HEADSCALE_PORT="8080"
  HEADSCALE_INTERNAL_PORT="18080"
  if [[ -f "$PANEL_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PANEL_STATE_FILE"
  fi
}

headscale_server_url() {
  local url=""
  if [[ -f "$HEADSCALE_CONFIG" ]]; then
    url="$(awk -F': ' '/^server_url:/ {print $2; exit}' "$HEADSCALE_CONFIG" | tr -d '"')"
  fi
  if [[ -z "$url" && -n "${SERVER_IP:-}" ]]; then
    url="http://${SERVER_IP}:${HEADSCALE_PORT}"
  fi
  printf '%s\n' "$url"
}

tailscale_version() {
  tailscale version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1
}

require_peer_relay_client() {
  command -v tailscale >/dev/null 2>&1 || die "未安装 Tailscale 客户端。请先执行主安装脚本。"
  local version
  version="$(tailscale_version || true)"
  [[ -n "$version" ]] || die "无法识别 Tailscale 客户端版本。"
  version_ge "$version" "1.86.0" || die "Peer Relay 需要 Tailscale 1.86 或更高版本，当前为 ${version}。"
}

is_connected() {
  tailscale status --json 2>/dev/null | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'
}

ensure_connected() {
  local server_url
  local answer=""
  local relay_hostname=""
  server_url="$(headscale_server_url)"
  [[ -n "$server_url" ]] || die "无法从 Headscale 配置读取 server_url。"

  if is_connected; then
    return 0
  fi

  warn "当前服务器上的 Tailscale 尚未登录这个 Headscale。"
  relay_hostname="$(hostname -s 2>/dev/null || echo relay)-relay"
  echo "请先执行："
  echo "  tailscale up --login-server=${server_url} --hostname=${relay_hostname}"
  echo
  read -r -p "现在执行这条登录命令吗？[y/N]: " answer || true
  if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    tailscale up --login-server="$server_url" --hostname="$relay_hostname" || true
  fi

  is_connected || die "Tailscale 仍未完成认证。请在 Headscale 完成注册/授权后，再重新进入 Peer Relay 管理。"
}

detect_public_ip() {
  local ip="${SERVER_IP:-}"
  local endpoint
  if validate_ipv4 "$ip" && [[ "$ip" != "127.0.0.1" ]]; then
    printf '%s\n' "$ip"
    return 0
  fi
  for endpoint in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip="$(curl -fsSL --connect-timeout 5 --max-time 10 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if validate_ipv4 "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  return 1
}

policy_path() {
  [[ -f "$HEADSCALE_CONFIG" ]] || return 0
  awk '
    /^policy:/ {inside=1; next}
    inside && /^[^[:space:]]/ {inside=0}
    inside && /^[[:space:]]+path:/ {
      sub(/^[[:space:]]*path:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      print
      exit
    }
  ' "$HEADSCALE_CONFIG"
}

write_grant_snippet() {
  local relay_ip="$1"
  local relay_src="$2"
  local configured_policy=""

  mkdir -p "$(dirname "$GRANT_SNIPPET_FILE")"
  configured_policy="$(policy_path)"
  cat > "$GRANT_SNIPPET_FILE" <<EOF
// 将下面这个对象合并到现有 policy 的 "grants" 数组中。
{
  "src": ["${relay_src}"],
  "dst": ["${relay_ip}"],
  "app": {
    "tailscale.com/cap/relay": []
  }
}
EOF
  chmod 0644 "$GRANT_SNIPPET_FILE"

  echo
  if [[ -n "$configured_policy" ]]; then
    info "检测到当前 policy：${configured_policy}"
    echo '请把下面 Grant 合并到该 policy 的 "grants" 数组中：'
  else
    warn "当前 Headscale 没有检测到 policy.path（可能尚未使用文件策略，也可能由面板/数据库管理 policy）。"
    warn "如果 policy 定义了 grants，未匹配到 Grant 的普通流量会被拒绝；不要只放这一条 Relay Grant。"
    echo "请把这条 Grant 合并到你实际使用的 policy，并同时保留正常网络访问所需的 Grant："
  fi
  cat "$GRANT_SNIPPET_FILE"
  echo
  echo "Grant 片段已保存：${GRANT_SNIPPET_FILE}"
  echo "合并后建议执行："
  echo "  headscale -c ${HEADSCALE_CONFIG} configtest"
  echo "  systemctl reload headscale || systemctl restart headscale"
}

save_relay_state() {
  local port="$1"
  local endpoint="$2"
  local relay_ip="$3"
  local relay_src="$4"
  mkdir -p "$(dirname "$PEER_RELAY_STATE_FILE")"
  {
    printf 'PEER_RELAY_PORT=%q\n' "$port"
    printf 'PEER_RELAY_ENDPOINT=%q\n' "$endpoint"
    printf 'PEER_RELAY_IP=%q\n' "$relay_ip"
    printf 'PEER_RELAY_SRC=%q\n' "$relay_src"
  } > "$PEER_RELAY_STATE_FILE"
  chmod 0600 "$PEER_RELAY_STATE_FILE"
}

show_status() {
  echo
  info "Peer Relay 状态"
  if ! command -v tailscale >/dev/null 2>&1; then
    warn "未安装 Tailscale。"
    return 0
  fi
  echo "- Tailscale: $(tailscale_version || echo unknown)"
  if is_connected; then
    echo "- Headscale 登录状态: 已连接"
    echo "- 本机 Tailscale IPv4: $(tailscale ip -4 2>/dev/null | head -n 1 || echo unknown)"
  else
    echo "- Headscale 登录状态: 未连接"
  fi
  if [[ -f "$PEER_RELAY_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PEER_RELAY_STATE_FILE"
    echo "- 配置端口: ${PEER_RELAY_PORT:-unknown}/udp"
    echo "- 静态端点: ${PEER_RELAY_ENDPOINT:-未设置}"
    echo "- Relay Tailscale IP: ${PEER_RELAY_IP:-unknown}"
    echo "- Grant src: ${PEER_RELAY_SRC:-unknown}"
  else
    echo "- 脚本状态: 尚未通过本脚本启用"
  fi
  echo
  tailscale debug peer-relay-servers 2>/dev/null || true
  echo
  tailscale status 2>/dev/null | grep -E 'peer-relay|direct|relay' || true
}

enable_relay() {
  local port=""
  local public_ip=""
  local endpoint=""
  local endpoint_input=""
  local relay_ip=""
  local relay_src=""

  require_peer_relay_client
  ensure_connected

  read -r -p "Peer Relay UDP 端口 [默认: ${DEFAULT_PORT}]: " port || true
  port="${port:-$DEFAULT_PORT}"
  validate_port "$port" || die "无效端口：${port}"

  public_ip="$(detect_public_ip || true)"
  if [[ -n "$public_ip" ]]; then
    read -r -p "静态公网端点 [默认: ${public_ip}:${port}；输入 - 表示不设置]: " endpoint_input || true
    endpoint_input="${endpoint_input:-${public_ip}:${port}}"
  else
    read -r -p "静态公网端点 [格式 IP:端口；留空表示自动发现]: " endpoint_input || true
  fi
  [[ "$endpoint_input" == "-" ]] && endpoint_input=""
  endpoint="$endpoint_input"
  [[ "$endpoint" =~ [[:space:]] ]] && die "静态端点不能包含空格。"

  relay_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  [[ -n "$relay_ip" ]] || die "无法读取本机 Tailscale IPv4，无法生成安全的 Relay Grant。"

  echo
  warn "Peer Relay Grant 的 src 决定哪些设备会尝试使用这台中继。"
  warn "优先填写稳定位置的 hostname、tag 或 IP 集合；不要无必要使用 *。"
  read -r -p "Grant src [默认: autogroup:member]: " relay_src || true
  relay_src="${relay_src:-autogroup:member}"
  validate_policy_selector "$relay_src" || die "Grant src 含有不支持的字符；请使用 hostname、IP、tag、group、autogroup 或 *。"
  [[ "$relay_src" != "*" ]] || warn "你选择了 *，这会让所有节点都尝试使用该 Peer Relay；官方不建议无条件这样配置。"

  write_grant_snippet "$relay_ip" "$relay_src"

  warn "Peer Relay 的可用性会受客户端版本、平台支持和 NAT/防火墙环境影响；请保留 DERP 作为最终兜底。"
  if [[ -n "$endpoint" ]]; then
    tailscale set --relay-server-port="$port" --relay-server-static-endpoints="$endpoint"
  else
    tailscale set --relay-server-port="$port" --relay-server-static-endpoints=""
  fi

  save_relay_state "$port" "$endpoint" "$relay_ip" "$relay_src"
  success "Peer Relay 已在 UDP ${port} 上启用。"
  warn "请在云安全组/防火墙放行 UDP ${port}。"
  [[ -n "$endpoint" ]] && echo "- 广播静态端点：${endpoint}"
  warn "Relay 服务已开启，但必须把上方 Grant 合并到 Headscale policy 后，客户端才会获得 Relay 权限。"
  echo "- 连接优先级：DIRECT -> Peer Relay -> DERP"
  echo "- 检查：tailscale debug peer-relay-servers"
  echo "- 实际流量：tailscale status | grep peer-relay"
}

disable_relay() {
  require_peer_relay_client
  tailscale set --relay-server-port="" --relay-server-static-endpoints=""
  rm -f "$PEER_RELAY_STATE_FILE"
  success "已关闭本机 Peer Relay。"
  warn "脚本从未自动修改 Headscale policy；如果你曾手动合并 Relay Grant，可自行删除对应 tailscale.com/cap/relay 条目。"
}

show_verification() {
  cat <<'EOF'
Peer Relay 验证命令：

  tailscale debug peer-relay-servers
  tailscale status | grep peer-relay
  tailscale ping <目标设备>

判断路径：
  direct      = P2P 直连
  peer-relay  = 正在使用 Peer Relay
  relay       = DERP 中继

正常优先级：
  DIRECT -> Peer Relay -> DERP
EOF
}

show_menu() {
  echo
  echo "=========================================="
  echo "  Peer Relay 管理"
  echo "=========================================="
  echo "1. 查看状态"
  echo "2. 启用 / 重新配置 Peer Relay"
  echo "3. 关闭 Peer Relay"
  echo "4. 查看验证命令"
  echo "0. 返回"
  echo "=========================================="
}

main() {
  require_root
  load_state

  while true; do
    show_menu
    read -r -p "请输入选项: " choice || true
    case "${choice:-}" in
      1) show_status ;;
      2) enable_relay ;;
      3) disable_relay ;;
      4) show_verification ;;
      0) exit 0 ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
  done
}

main "$@"
