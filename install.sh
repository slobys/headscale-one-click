#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="2.3.0"
PROJECT_REPO="slobys/headscale-one-click"
WORKDIR="/usr/local/src/headscale-one-click"
DERP_DIR="/etc/derp"
DERP_SERVICE="/etc/systemd/system/derp.service"
DERP_MAP="/etc/headscale/derp.yaml"
NGINX_SITE_NAME="headscale-one-click"
NGINX_AVAILABLE="/etc/nginx/sites-available/${NGINX_SITE_NAME}.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/${NGINX_SITE_NAME}.conf"
HEADSCALE_CONFIG="/etc/headscale/config.yaml"
HEADSCALE_UI_DIR="/var/www/web"
HEADSCALE_INTERNAL_PORT="18080"
TAILSCALE_FALLBACK_VERSION="1.102.4"
DERPER_TAILSCALE_VERSION="1.102.4"
HEADSCALE_FALLBACK_VERSION="0.29.3"
HEADSCALE_UI_FALLBACK_VERSION="2026.03.17"
HEADPLANE_FALLBACK_VERSION="0.7.1"
NODE_FALLBACK_VERSION="22.23.2"
HEADSCALE_UI_VERSION="${HEADSCALE_UI_FALLBACK_VERSION}"
PANEL_STATE_DIR="/etc/headscale-one-click"
PANEL_STATE_FILE="${PANEL_STATE_DIR}/panel.env"
PEER_RELAY_STATE_FILE="${PANEL_STATE_DIR}/peer-relay.env"
RANDOM_PORT_MIN=20000
RANDOM_PORT_MAX=64999
HEADPLANE_DIR="/opt/headplane"
HEADPLANE_CONFIG_DIR="/etc/headplane"
HEADPLANE_CONFIG="${HEADPLANE_CONFIG_DIR}/config.yaml"
HEADPLANE_SERVICE="/etc/systemd/system/headplane.service"
HEADPLANE_DATA_DIR="/var/lib/headplane"
HEADPLANE_PORT="3000"
HEADPLANE_NODE_BIN="/usr/bin/node"
APT_UPDATED=0
INSTALL_MODE="quick"

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

on_error() {
  local line="$1"
  error "脚本执行失败，出错行号：${line}"
}
trap 'on_error ${LINENO}' ERR

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行此脚本。"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$2" ]]
}

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local input_value=""

  read -r -p "${prompt_text} [默认: ${default_value}]: " input_value || true
  input_value="${input_value:-$default_value}"
  printf -v "$var_name" '%s' "$input_value"
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

curl_quick() {
  curl -fsSL --connect-timeout 15 --max-time 45 "$@"
}

fetch_latest_headscale() {
  curl_quick https://api.github.com/repos/juanfont/headscale/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_tailscale() {
  curl_quick https://api.github.com/repos/tailscale/tailscale/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headscale_ui() {
  curl_quick https://api.github.com/repos/gurucomputing/headscale-ui/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_headplane() {
  curl_quick https://api.github.com/repos/tale/headplane/releases/latest | grep '"tag_name"' | head -n 1 | sed -E 's/.*"v?([^"]+)".*/\1/'
}

fetch_latest_node22() {
  curl_quick https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt \
    | grep -oE 'node-v22\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz' \
    | head -n 1 \
    | sed -E 's/^node-v([0-9.]+)-.*/\1/'
}

detect_latest_versions() {
  info "查询 Tailscale / Headscale / Headscale-ui / Headplane 最新版本..."
  TAILSCALE_LATEST_VERSION="$(fetch_latest_tailscale 2>/dev/null || echo unknown)"
  HEADSCALE_LATEST_VERSION="$(fetch_latest_headscale 2>/dev/null || echo unknown)"
  HEADSCALE_UI_LATEST_VERSION="$(fetch_latest_headscale_ui 2>/dev/null || echo unknown)"
  HEADPLANE_LATEST_VERSION="$(fetch_latest_headplane 2>/dev/null || echo unknown)"
}

apt_update_once() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    apt update
    APT_UPDATED=1
  fi
}

install_preflight_tools() {
  local -a packages=(ca-certificates curl tar xz-utils openssl iproute2 coreutils grep sed gawk)
  local cmd=""
  local missing=0

  for cmd in curl tar xz openssl ss sha256sum grep sed awk; do
    command -v "$cmd" >/dev/null 2>&1 || missing=1
  done
  [[ "$missing" -eq 0 ]] && return 0

  info "安装环境检查所需的最小工具..."
  command -v apt >/dev/null 2>&1 || die "当前系统缺少 apt，无法自动安装基础工具。"
  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"
}

prompt_install_mode() {
  local choice=""
  echo
  echo "请选择安装模式："
  echo "1) 快速安装（推荐：稳定版本、推荐端口、Headscale-ui）"
  echo "2) 高级安装（自定义版本、端口和面板）"
  read -r -p "请输入选项 [默认: 1]: " choice || true
  choice="${choice:-1}"
  case "$choice" in
    1) INSTALL_MODE="quick" ;;
    2) INSTALL_MODE="advanced" ;;
    *) die "无效的安装模式：${choice}" ;;
  esac
}

load_existing_install_defaults() {
  EXISTING_INSTALL=0
  EXISTING_SERVER_IP=""
  EXISTING_HEADSCALE_PORT=""
  EXISTING_DERP_HOST=""
  EXISTING_DERP_PORT=""
  EXISTING_IP_PREFIX=""
  EXISTING_PEER_RELAY_PORT=""
  EXISTING_PANEL_TYPE=""
  EXISTING_PANEL_PATH=""

  if [[ -f "$PANEL_STATE_FILE" ]]; then
    EXISTING_INSTALL=1
    EXISTING_SERVER_IP="$(sed -n 's/^SERVER_IP=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_HEADSCALE_PORT="$(sed -n 's/^HEADSCALE_PORT=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_DERP_HOST="$(sed -n 's/^DERP_HOST=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_DERP_PORT="$(sed -n 's/^DERP_PORT=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_IP_PREFIX="$(sed -n 's/^IP_PREFIX=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_PEER_RELAY_PORT="$(sed -n 's/^PEER_RELAY_DEFAULT_PORT=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_PANEL_TYPE="$(sed -n 's/^PANEL_TYPE=//p' "$PANEL_STATE_FILE" | head -n 1)"
    EXISTING_PANEL_PATH="$(sed -n 's/^PANEL_PATH=//p' "$PANEL_STATE_FILE" | head -n 1)"
  elif [[ -f "$HEADSCALE_CONFIG" || -f "$DERP_SERVICE" ]]; then
    EXISTING_INSTALL=1
  fi

  if [[ -z "$EXISTING_HEADSCALE_PORT" && -f "$HEADSCALE_CONFIG" ]]; then
    EXISTING_HEADSCALE_PORT="$(sed -nE 's|^server_url:[[:space:]]*http://[^:]+:([0-9]+).*|\1|p' "$HEADSCALE_CONFIG" | head -n 1)"
  fi
  if [[ -z "$EXISTING_SERVER_IP" && -f "$HEADSCALE_CONFIG" ]]; then
    EXISTING_SERVER_IP="$(sed -nE 's|^server_url:[[:space:]]*http://([^:/]+).*|\1|p' "$HEADSCALE_CONFIG" | head -n 1)"
  fi
  if [[ -f "$DERP_SERVICE" ]]; then
    [[ -n "$EXISTING_DERP_HOST" ]] || EXISTING_DERP_HOST="$(sed -nE 's/.*-hostname[ =]+([^ ]+).*/\1/p' "$DERP_SERVICE" | head -n 1)"
    [[ -n "$EXISTING_DERP_PORT" ]] || EXISTING_DERP_PORT="$(sed -nE 's/.* -a :([0-9]+).*/\1/p' "$DERP_SERVICE" | head -n 1)"
  fi
  if [[ -z "$EXISTING_IP_PREFIX" && -f "$HEADSCALE_CONFIG" ]]; then
    EXISTING_IP_PREFIX="$(sed -nE 's/^[[:space:]]*v4:[[:space:]]*([0-9.]+)\/[0-9]+.*/\1/p' "$HEADSCALE_CONFIG" | head -n 1)"
  fi
  if [[ -z "$EXISTING_PEER_RELAY_PORT" && -f "$PEER_RELAY_STATE_FILE" ]]; then
    EXISTING_PEER_RELAY_PORT="$(sed -n 's/^PEER_RELAY_PORT=//p' "$PEER_RELAY_STATE_FILE" | head -n 1)"
  fi
  [[ "$EXISTING_PANEL_TYPE" == "headache-ui" ]] && EXISTING_PANEL_TYPE="headscale-ui"
  if [[ -z "$EXISTING_PANEL_TYPE" ]]; then
    if [[ -f "$HEADPLANE_SERVICE" || -f "$HEADPLANE_CONFIG" ]]; then
      EXISTING_PANEL_TYPE="headplane"
      EXISTING_PANEL_PATH="/admin"
    else
      EXISTING_PANEL_TYPE="headscale-ui"
      EXISTING_PANEL_PATH="/web"
    fi
  fi

  if [[ "$EXISTING_INSTALL" -eq 1 ]]; then
    info "检测到已有 Headscale One Click 安装，快速模式将尽量继承现有 IP、端口和面板设置。"
  fi
}

prompt_panel_type() {
  local default_choice="${1:-1}"
  local choice=""

  echo
  echo "请选择要安装的面板："
  echo "1) Headscale-ui（访问路径 /web）"
  echo "2) Headplane（原生部署，访问路径 /admin）"
  read -r -p "请输入选项 [默认: ${default_choice}]: " choice || true
  choice="${choice:-$default_choice}"

  case "$choice" in
    1)
      PANEL_TYPE="headscale-ui"
      PANEL_PATH="/web"
      ;;
    2)
      PANEL_TYPE="headplane"
      PANEL_PATH="/admin"
      ;;
    *)
      die "无效的面板选项：${choice}"
      ;;
  esac
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
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

validate_ip_prefix24() {
  local prefix="$1"
  validate_ipv4 "$prefix" || return 1
  [[ "${prefix##*.}" == "0" ]]
}

prompt_ip_prefix() {
  local default_value="$1"
  local input_value=""
  while true; do
    read -r -p "请输入 Tailscale 虚拟内网网段（/24，例如 100.64.10.0） [默认: ${default_value}]: " input_value || true
    input_value="${input_value:-$default_value}"
    input_value="${input_value%/24}"
    if validate_ip_prefix24 "$input_value"; then
      IP_PREFIX="$input_value"
      return 0
    fi
    warn "网段格式无效。当前脚本使用 /24，请填写类似 100.64.10.0 或 100.64.10.0/24 的网络地址。"
  done
}

prompt_server_ip() {
  local default_value="$1"
  local input_value=""
  while true; do
    if validate_ipv4 "$default_value"; then
      read -r -p "请输入服务器公网 IP [默认: ${default_value}]: " input_value || true
      input_value="${input_value:-$default_value}"
    else
      read -r -p "请输入服务器公网 IPv4: " input_value || true
    fi
    if validate_ipv4 "$input_value"; then
      SERVER_IP="$input_value"
      return 0
    fi
    warn "IPv4 格式无效，请重新输入，例如 1.2.3.4。"
  done
}

validate_hostname_or_ipv4() {
  local host="$1"
  local label=""
  local IFS='.'
  local -a labels=()

  validate_ipv4 "$host" && return 0
  [[ -n "$host" && "${#host}" -le 253 ]] || return 1
  [[ "$host" != *".."* ]] || return 1
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  read -r -a labels <<< "$host"
  [[ "${#labels[@]}" -ge 1 ]] || return 1
  for label in "${labels[@]}"; do
    [[ -n "$label" && "${#label}" -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

detect_public_ip() {
  local detected_ip=""
  local endpoint
  local endpoints=(
    "https://api.ipify.org"
    "https://ipv4.icanhazip.com"
    "https://ifconfig.me/ip"
  )

  for endpoint in "${endpoints[@]}"; do
    detected_ip="$(curl -fsSL --connect-timeout 5 --max-time 10 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if validate_ipv4 "$detected_ip"; then
      echo "$detected_ip"
      return 0
    fi
  done

  echo ""
}

detect_arch() {
  local machine_arch
  machine_arch="$(uname -m)"
  case "$machine_arch" in
    x86_64|amd64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    *)
      die "当前脚本暂不支持该架构：${machine_arch}"
      ;;
  esac
}

check_system() {
  [[ -f /etc/os-release ]] || die "无法识别系统类型。"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" ]] || die "当前版本先只支持 Debian / Ubuntu 系。"
  case "${ID}" in
    debian)
      (( ${VERSION_ID%%.*} >= 12 )) || die "Headscale 官方 DEB 需要 Debian 12 或更新版本。"
      ;;
    ubuntu)
      version_ge "${VERSION_ID}" "22.04" || die "Headscale 官方 DEB 需要 Ubuntu 22.04 或更新版本。"
      ;;
  esac
}

tcp_port_in_use() {
  local port="$1"
  ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"
}

udp_port_in_use() {
  local port="$1"
  ss -lunH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"
}

port_in_ephemeral_range() {
  local port="$1"
  local range_min=32768
  local range_max=60999
  if [[ -r /proc/sys/net/ipv4/ip_local_port_range ]]; then
    read -r range_min range_max < /proc/sys/net/ipv4/ip_local_port_range || true
  fi
  (( port >= range_min && port <= range_max ))
}

port_is_reserved_for_defaults() {
  local port="$1"
  case "$port" in
    22|53|80|443|3000|3478|8080|18080) return 0 ;;
  esac
  return 1
}

random_free_port() {
  local proto="$1"
  shift || true
  local -a excluded=("$@")
  local candidate=""
  local item=""
  local attempts=0
  local span=$((RANDOM_PORT_MAX - RANDOM_PORT_MIN + 1))

  while (( attempts < 500 )); do
    attempts=$((attempts + 1))
    candidate=$((RANDOM_PORT_MIN + (((RANDOM << 15) | RANDOM) % span)))
    port_is_reserved_for_defaults "$candidate" && continue
    port_in_ephemeral_range "$candidate" && continue
    for item in "${excluded[@]}"; do
      [[ -n "$item" && "$candidate" == "$item" ]] && candidate="" && break
    done
    [[ -n "$candidate" ]] || continue
    if [[ "$proto" == "tcp" ]]; then
      tcp_port_in_use "$candidate" && continue
    else
      udp_port_in_use "$candidate" && continue
    fi
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

project_owns_tcp_port() {
  local port="$1"
  [[ -f "$DERP_SERVICE" ]] && grep -qE " -a :${port}([[:space:]]|$)" "$DERP_SERVICE" && return 0
  [[ -f "$NGINX_AVAILABLE" ]] && grep -qE "^[[:space:]]*listen[[:space:]]+${port};" "$NGINX_AVAILABLE" && return 0
  [[ -f "$HEADSCALE_CONFIG" ]] && grep -qE "^listen_addr:[[:space:]]+127\.0\.0\.1:${port}([[:space:]]|$)" "$HEADSCALE_CONFIG" && return 0
  return 1
}

project_owns_udp_port() {
  local port="$1"
  [[ -f "$DERP_SERVICE" ]] && grep -qE -- "-stun-port[ =]+${port}([[:space:]]|$)" "$DERP_SERVICE"
}

check_selected_ports() {
  [[ "$HEADSCALE_PORT" != "$HEADSCALE_INTERNAL_PORT" ]] || die "Headscale 外部端口不能使用内部保留端口 ${HEADSCALE_INTERNAL_PORT}。"
  [[ "$HEADSCALE_PORT" != "$DERP_PORT" ]] || die "Headscale 和 DERP 都使用 TCP，端口不能相同：${HEADSCALE_PORT}"
  [[ "$PEER_RELAY_DEFAULT_PORT" != "3478" ]] || die "Peer Relay UDP 端口不能与 STUN 3478/udp 相同。"
  [[ "$PEER_RELAY_DEFAULT_PORT" != "$HEADSCALE_PORT" && "$PEER_RELAY_DEFAULT_PORT" != "$DERP_PORT" ]] || die "为便于维护，Peer Relay 默认端口不能与 Headscale/DERP 使用相同数字。"
  if tcp_port_in_use "$HEADSCALE_PORT" && ! project_owns_tcp_port "$HEADSCALE_PORT"; then die "Headscale 端口 ${HEADSCALE_PORT}/tcp 已被其它程序占用。"; fi
  if tcp_port_in_use "$DERP_PORT" && ! project_owns_tcp_port "$DERP_PORT"; then die "DERP 端口 ${DERP_PORT}/tcp 已被其它程序占用。"; fi
  if tcp_port_in_use "$HEADSCALE_INTERNAL_PORT" && ! project_owns_tcp_port "$HEADSCALE_INTERNAL_PORT"; then die "Headscale 内部端口 ${HEADSCALE_INTERNAL_PORT}/tcp 已被其它程序占用。"; fi
  if udp_port_in_use 3478 && ! project_owns_udp_port 3478; then die "STUN 端口 3478/udp 已被其它程序占用。"; fi
  if udp_port_in_use "$PEER_RELAY_DEFAULT_PORT" && [[ "$PEER_RELAY_DEFAULT_PORT" != "${EXISTING_PEER_RELAY_PORT:-}" ]]; then die "Peer Relay 默认端口 ${PEER_RELAY_DEFAULT_PORT}/udp 已被其它程序占用。"; fi
}

show_preflight_summary() {
  local disk_mb mem_mb github_status tailscale_status
  disk_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  mem_mb="$(awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  github_status="⚠ 不可达/较慢"
  tailscale_status="⚠ 不可达/较慢"
  curl -fsSI --connect-timeout 5 --max-time 10 https://github.com >/dev/null 2>&1 && github_status="✓ 可达" || true
  curl -fsSI --connect-timeout 5 --max-time 10 https://pkgs.tailscale.com >/dev/null 2>&1 && tailscale_status="✓ 可达" || true
  echo
  echo "========== 安装前环境检查 =========="
  echo "系统:               ${ID:-unknown} ${VERSION_ID:-unknown}"
  echo "架构:               ${ARCH}"
  echo "公网 IPv4:          ${SERVER_IP_DEFAULT:-未检测到}"
  echo "可用磁盘:           ${disk_mb} MB"
  echo "内存:               ${mem_mb} MB"
  echo "GitHub:             ${github_status}"
  echo "Tailscale Packages: ${tailscale_status}"
  echo "===================================="
  (( disk_mb >= 1024 )) || warn "根分区可用空间低于 1GB，安装可能失败。"
  (( mem_mb >= 512 )) || warn "内存低于 512MB，Headplane 编译可能失败；建议使用 Headscale-ui。"
}

show_firewall_notice() {
  cat <<EOF
${YELLOW}========== 重要提醒 ==========${NC}
原始脚本会直接关闭 ufw / firewalld / iptables。
为了更适合真实服务器环境，这个整合版不会自动清空防火墙。

请手动确认以下端口已经放行：
- DERP 端口: ${DERP_PORT}/tcp
- STUN 端口: 3478/udp
- Peer Relay 默认端口: ${PEER_RELAY_DEFAULT_PORT}/udp（启用 Peer Relay 时再放行）
- DERP HTTP 监听: 已关闭
- Headscale 端口: ${HEADSCALE_PORT}
- 如果已有反代/HTTPS，还要放行 80 / 443
${YELLOW}==============================${NC}
EOF
}

ask_system_upgrade() {
  local answer=""
  echo
  warn "是否先执行系统软件升级（apt upgrade -y）？"
  warn "升级系统可能触发其它服务重启；如服务器上已有在运行的业务，建议谨慎选择。"
  read -r -p "现在执行系统升级吗？[y/N]: " answer || true
  answer="${answer:-N}"

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    info "开始执行系统软件升级..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
  else
    info "已跳过系统软件升级。"
  fi
}

install_base_packages() {
  info "更新软件源并安装基础依赖..."
  apt_update_once
  ask_system_upgrade
  DEBIAN_FRONTEND=noninteractive apt install -y wget git openssl curl unzip nginx ca-certificates tar xz-utils iproute2
}

prepare_workdir() {
  mkdir -p "$WORKDIR"
  mkdir -p "$DERP_DIR"
}

save_panel_state() {
  mkdir -p "$PANEL_STATE_DIR"
  cat > "$PANEL_STATE_FILE" <<EOF
PANEL_TYPE=${PANEL_TYPE}
PANEL_PATH=${PANEL_PATH}
SERVER_IP=${SERVER_IP}
HEADSCALE_PORT=${HEADSCALE_PORT}
HEADSCALE_INTERNAL_PORT=${HEADSCALE_INTERNAL_PORT}
HEADSCALE_URL=http://${SERVER_IP}:${HEADSCALE_PORT}
DERP_HOST=${DOMAIN}
DERP_PORT=${DERP_PORT}
DERP_HTTP_PORT=-1
IP_PREFIX=${IP_PREFIX}
PEER_RELAY_DEFAULT_PORT=${PEER_RELAY_DEFAULT_PORT}
INSTALL_SCRIPT_VERSION=${SCRIPT_VERSION}
EOF
}

find_or_download_file() {
  local filename="$1"
  local output_path="$2"
  shift 2
  local urls=("$@")
  local url=""
  local speed_limit="${DOWNLOAD_LOW_SPEED_LIMIT:-10240}"
  local speed_time="${DOWNLOAD_LOW_SPEED_TIME:-30}"

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
    rm -f "$output_path"
    if curl -fL --retry 2 --connect-timeout 15 --max-time 300 --speed-limit "$speed_limit" --speed-time "$speed_time" -o "$output_path" "$url"; then
      success "下载完成：${filename}"
      return 0
    fi
    warn "该线路下载失败或速度过慢，尝试下一条线路。"
  done

  cat <<EOF
${RED}[ERROR]${NC} 下载失败：${filename}
可能原因：
1. 当前服务器无法稳定访问国外源
2. GitHub / tailscale.com / Node.js 源或加速线路在当前网络下超时
3. 目标版本文件名已变化

中国大陆服务器环境建议处理方式：
- 可以先在本地电脑下载好对应文件
- 上传到 /root/ 或脚本当前目录
- 然后重新执行脚本

已尝试下载地址：
$(printf '%s\n' "${urls[@]}")
EOF
  return 1
}

github_download_urls() {
  local source_url="$1"
  local custom_prefix="${GITHUB_PROXY_PREFIX:-}"

  if [[ -n "$custom_prefix" ]]; then
    case "$custom_prefix" in
      */) printf '%s\n' "${custom_prefix}${source_url}" ;;
      *) printf '%s\n' "${custom_prefix}/${source_url}" ;;
    esac
  fi

  printf '%s\n' \
    "https://ghfast.top/${source_url}" \
    "https://gh-proxy.com/${source_url}" \
    "$source_url"
}

derper_release_urls() {
  local filename="$1"
  local source_url="https://github.com/${PROJECT_REPO}/releases/download/v${SCRIPT_VERSION}/${filename}"
  github_download_urls "$source_url"
}

install_derper_binary() {
  local asset="derper-linux-${ARCH}"
  local checksum_asset="${asset}.sha256"
  local binary_path="${WORKDIR}/${asset}"
  local checksum_path="${WORKDIR}/${checksum_asset}"
  local expected=""
  local actual=""
  local -a binary_urls=()
  local -a checksum_urls=()

  if [[ -x "$DERP_DIR/derper" ]] && "$DERP_DIR/derper" -version 2>&1 | grep -q "$DERPER_TAILSCALE_VERSION"; then
    info "检测到兼容的 DERP 预编译二进制，跳过重复下载。"
    return 0
  fi

  mapfile -t binary_urls < <(derper_release_urls "$asset")
  mapfile -t checksum_urls < <(derper_release_urls "$checksum_asset")

  find_or_download_file "$asset" "$binary_path" "${binary_urls[@]}" || die "DERP 预编译二进制下载失败。可把 ${asset} 和 ${checksum_asset} 上传到 /root/ 后重试。"
  find_or_download_file "$checksum_asset" "$checksum_path" "${checksum_urls[@]}" || die "DERP SHA256 文件下载失败。"

  expected="$(grep -oE '[0-9a-fA-F]{64}' "$checksum_path" | head -n 1 | tr 'A-F' 'a-f')"
  actual="$(sha256sum "$binary_path" | awk '{print $1}')"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "DERP SHA256 文件格式无效：${checksum_asset}"
  [[ "$actual" == "$expected" ]] || die "DERP 预编译二进制 SHA256 校验失败：${asset}"

  mkdir -p "$DERP_DIR"
  install -m 0755 "$binary_path" "$DERP_DIR/derper"
  "$DERP_DIR/derper" -version >/dev/null 2>&1 || die "DERP 二进制无法正常执行。"
  success "DERP 预编译二进制安装完成（Tailscale ${DERPER_TAILSCALE_VERSION}，无需 Go）。"
}

tailscale_download_urls() {
  local filename="$1"
  local custom_base="${TAILSCALE_DOWNLOAD_BASE:-}"

  if [[ -n "$custom_base" ]]; then
    printf '%s\n' "${custom_base%/}/${filename}"
  fi
  printf '%s\n' "https://pkgs.tailscale.com/stable/${filename}"
}

tailscale_expected_sha256() {
  local version="$1"
  local arch="$2"
  local filename="$3"
  local candidate=""
  local value=""
  local custom_base="${TAILSCALE_DOWNLOAD_BASE:-}"

  case "${version}:${arch}" in
    1.102.4:amd64)
      printf '%s\n' "50748df1045e60b5b695f19f4c56b0da36c019948b440fb456b6584a50f0d8b9"
      return 0
      ;;
    1.102.4:arm64)
      printf '%s\n' "9dd1e6a592a014bbaea0103167ffe299adeda4ba14e078ce9c2895364f6c4c3f"
      return 0
      ;;
  esac

  for candidate in "/root/${filename}.sha256" "./${filename}.sha256"; do
    if [[ -f "$candidate" ]]; then
      value="$(grep -oE '[0-9a-fA-F]{64}' "$candidate" | head -n 1 | tr 'A-F' 'a-f')"
      [[ "$value" =~ ^[0-9a-f]{64}$ ]] && {
        printf '%s\n' "$value"
        return 0
      }
    fi
  done

  value="$(curl_quick "https://pkgs.tailscale.com/stable/${filename}.sha256" 2>/dev/null | grep -oE '[0-9a-fA-F]{64}' | head -n 1 | tr 'A-F' 'a-f' || true)"
  if [[ "$value" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  if [[ -n "$custom_base" ]]; then
    value="$(curl_quick "${custom_base%/}/${filename}.sha256" 2>/dev/null | grep -oE '[0-9a-fA-F]{64}' | head -n 1 | tr 'A-F' 'a-f' || true)"
    if [[ "$value" =~ ^[0-9a-f]{64}$ ]]; then
      warn "Tailscale 校验值来自自定义下载源，请确认该镜像可信。" >&2
      printf '%s\n' "$value"
      return 0
    fi
  fi

  return 1
}

node_download_arch() {
  case "$ARCH" in
    amd64) printf '%s\n' "x64" ;;
    arm64) printf '%s\n' "arm64" ;;
    *) return 1 ;;
  esac
}

node_download_urls() {
  local version="$1"
  local filename="$2"
  local custom_base="${NODE_DOWNLOAD_BASE:-}"

  if [[ -n "$custom_base" ]]; then
    printf '%s\n' "${custom_base%/}/v${version}/${filename}"
  fi
  printf '%s\n' \
    "https://registry.npmmirror.com/-/binary/node/v${version}/${filename}" \
    "https://nodejs.org/dist/v${version}/${filename}"
}

node_expected_sha256() {
  local version="$1"
  local filename="$2"
  local node_arch="$3"
  local candidate=""
  local value=""
  local shasums=""
  local custom_base="${NODE_DOWNLOAD_BASE:-}"

  case "${version}:${node_arch}" in
    22.23.2:x64)
      printf '%s\n' "d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307"
      return 0
      ;;
    22.23.2:arm64)
      printf '%s\n' "fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8"
      return 0
      ;;
  esac

  for candidate in "/root/${filename}.sha256" "./${filename}.sha256"; do
    if [[ -f "$candidate" ]]; then
      value="$(grep -oE '[0-9a-fA-F]{64}' "$candidate" | head -n 1 | tr 'A-F' 'a-f')"
      [[ "$value" =~ ^[0-9a-f]{64}$ ]] && {
        printf '%s\n' "$value"
        return 0
      }
    fi
  done

  for candidate in /root/SHASUMS256.txt ./SHASUMS256.txt; do
    if [[ -f "$candidate" ]]; then
      value="$(awk -v f="$filename" '$2 == f {print $1; exit}' "$candidate" | tr 'A-F' 'a-f')"
      [[ "$value" =~ ^[0-9a-f]{64}$ ]] && {
        printf '%s\n' "$value"
        return 0
      }
    fi
  done

  shasums="$(curl_quick "https://nodejs.org/dist/v${version}/SHASUMS256.txt" 2>/dev/null || true)"
  value="$(printf '%s\n' "$shasums" | awk -v f="$filename" '$2 == f {print $1; exit}' | tr 'A-F' 'a-f')"
  if [[ "$value" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  shasums="$(curl_quick "https://registry.npmmirror.com/-/binary/node/v${version}/SHASUMS256.txt" 2>/dev/null || true)"
  value="$(printf '%s\n' "$shasums" | awk -v f="$filename" '$2 == f {print $1; exit}' | tr 'A-F' 'a-f')"
  if [[ "$value" =~ ^[0-9a-f]{64}$ ]]; then
    warn "Node.js 校验值来自 npmmirror；官方校验文件当前不可达。" >&2
    printf '%s\n' "$value"
    return 0
  fi

  if [[ -n "$custom_base" ]]; then
    shasums="$(curl_quick "${custom_base%/}/v${version}/SHASUMS256.txt" 2>/dev/null || true)"
    value="$(printf '%s\n' "$shasums" | awk -v f="$filename" '$2 == f {print $1; exit}' | tr 'A-F' 'a-f')"
    if [[ "$value" =~ ^[0-9a-f]{64}$ ]]; then
      warn "Node.js 校验值来自自定义下载源，请确认该镜像可信。" >&2
      printf '%s\n' "$value"
      return 0
    fi
  fi

  return 1
}

install_derp() {
  local san_type="DNS"

  info "开始安装 DERP 服务（预编译 derper，无需 Go）..."
  install_derper_binary

  if validate_ipv4 "$DOMAIN"; then
    san_type="IP"
  fi

  if [[ -s "$DERP_DIR/${DOMAIN}.key" && -s "$DERP_DIR/${DOMAIN}.crt" ]] && openssl x509 -checkend 2592000 -noout -in "$DERP_DIR/${DOMAIN}.crt" >/dev/null 2>&1; then
    info "检测到现有 DERP 证书仍有效，继续复用，避免无必要变更证书指纹。"
  else
    info "生成 DERP 自签名证书（使用客户端证书指纹固定）..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
      -keyout "$DERP_DIR/${DOMAIN}.key" \
      -out "$DERP_DIR/${DOMAIN}.crt" \
      -subj "/CN=${DOMAIN}" \
      -addext "subjectAltName=${san_type}:${DOMAIN}"
  fi

  DERP_CERT_HASH="$(openssl x509 -in "$DERP_DIR/${DOMAIN}.crt" -outform DER | sha256sum | awk '{print $1}')"
  [[ "$DERP_CERT_HASH" =~ ^[0-9a-f]{64}$ ]] || die "DERP 证书 SHA256 指纹计算失败。"

  cat > "$DERP_SERVICE" <<EOF
[Unit]
Description=TS Derper
After=network.target
Wants=network.target

[Service]
User=root
Restart=always
ExecStart=${DERP_DIR}/derper -hostname ${DOMAIN} -a :${DERP_PORT} -http-port -1 -stun=true -stun-port 3478 -certmode manual -certdir ${DERP_DIR}
RestartPreventExitStatus=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable derp
  systemctl restart derp

  success "DERP 安装完成。"
}

install_tailscale_static() {
  local version="$1"
  local filename="tailscale_${version}_${ARCH}.tgz"
  local archive="${WORKDIR}/${filename}"
  local expected=""
  local actual=""
  local staging="${WORKDIR}/tailscale-static-${version}-${ARCH}"
  local extracted="${staging}/tailscale_${version}_${ARCH}"
  local backup_dir="${WORKDIR}/tailscale-backup-$(date +%s)"
  local had_cli=0
  local had_daemon=0
  local had_unit=0
  local had_defaults=0
  local was_active=0
  local was_enabled=0
  local has_vendor_unit=0
  local -a urls=()

  mapfile -t urls < <(tailscale_download_urls "$filename")
  find_or_download_file "$filename" "$archive" "${urls[@]}" || return 1

  expected="$(tailscale_expected_sha256 "$version" "$ARCH" "$filename" || true)"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
    warn "无法取得 ${filename} 的可信 SHA256；为避免执行未校验二进制，已停止静态安装。"
    return 1
  }
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    warn "Tailscale 静态包 SHA256 不匹配：${filename}"
    return 1
  }

  rm -rf "$staging"
  mkdir -p "$staging"
  tar -xzf "$archive" -C "$staging"
  [[ -x "${extracted}/tailscale" && -x "${extracted}/tailscaled" ]] || {
    warn "Tailscale 静态包目录结构不符合预期。"
    return 1
  }
  [[ -f "${extracted}/systemd/tailscaled.service" && -f "${extracted}/systemd/tailscaled.defaults" ]] || {
    warn "Tailscale 静态包缺少 systemd 文件。"
    return 1
  }

  mkdir -p "$backup_dir"
  if [[ -e /usr/bin/tailscale || -L /usr/bin/tailscale ]]; then
    cp -a /usr/bin/tailscale "$backup_dir/usr-bin-tailscale"
    had_cli=1
  fi
  if [[ -e /usr/sbin/tailscaled || -L /usr/sbin/tailscaled ]]; then
    cp -a /usr/sbin/tailscaled "$backup_dir/usr-sbin-tailscaled"
    had_daemon=1
  fi
  if [[ -e /etc/systemd/system/tailscaled.service || -L /etc/systemd/system/tailscaled.service ]]; then
    cp -a /etc/systemd/system/tailscaled.service "$backup_dir/tailscaled.service"
    had_unit=1
  fi
  if [[ -e /etc/default/tailscaled || -L /etc/default/tailscaled ]]; then
    cp -a /etc/default/tailscaled "$backup_dir/tailscaled.defaults"
    had_defaults=1
  fi
  systemctl is-active --quiet tailscaled 2>/dev/null && was_active=1 || true
  systemctl is-enabled --quiet tailscaled 2>/dev/null && was_enabled=1 || true
  if [[ -f /lib/systemd/system/tailscaled.service || -f /usr/lib/systemd/system/tailscaled.service ]]; then
    has_vendor_unit=1
  fi

  if ! {
    systemctl stop tailscaled 2>/dev/null || true
    install -m 0755 "${extracted}/tailscale" /usr/bin/tailscale &&
    install -m 0755 "${extracted}/tailscaled" /usr/sbin/tailscaled &&
    mkdir -p /etc/default /etc/systemd/system &&
    { [[ -f /etc/default/tailscaled ]] || install -m 0644 "${extracted}/systemd/tailscaled.defaults" /etc/default/tailscaled; } &&
    { [[ "$has_vendor_unit" -eq 1 && "$had_unit" -eq 0 ]] || install -m 0644 "${extracted}/systemd/tailscaled.service" /etc/systemd/system/tailscaled.service; } &&
    systemctl daemon-reload &&
    systemctl enable --now tailscaled &&
    systemctl is-active --quiet tailscaled;
  }; then
    warn "Tailscale 静态包安装/启动失败，正在恢复安装前状态..."
    systemctl stop tailscaled 2>/dev/null || true
    rm -f /usr/bin/tailscale /usr/sbin/tailscaled /etc/systemd/system/tailscaled.service
    [[ "$had_cli" -eq 1 ]] && cp -a "$backup_dir/usr-bin-tailscale" /usr/bin/tailscale
    [[ "$had_daemon" -eq 1 ]] && cp -a "$backup_dir/usr-sbin-tailscaled" /usr/sbin/tailscaled
    [[ "$had_unit" -eq 1 ]] && cp -a "$backup_dir/tailscaled.service" /etc/systemd/system/tailscaled.service
    if [[ "$had_defaults" -eq 1 ]]; then
      cp -a "$backup_dir/tailscaled.defaults" /etc/default/tailscaled
    else
      rm -f /etc/default/tailscaled
    fi
    systemctl daemon-reload || true
    if [[ "$was_enabled" -eq 1 ]]; then
      systemctl enable tailscaled 2>/dev/null || true
    else
      systemctl disable tailscaled 2>/dev/null || true
    fi
    [[ "$was_active" -eq 1 ]] && systemctl start tailscaled 2>/dev/null || true
    rm -rf "$backup_dir"
    return 1
  fi

  rm -rf "$backup_dir"
  return 0
}

install_tailscale() {
  local target_version="$1"
  local current_version=""

  info "安装 Tailscale 客户端..."
  if command_exists tailscale; then
    current_version="$(tailscale version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
    if [[ -n "$current_version" ]] && version_ge "$current_version" "$target_version"; then
      if systemctl enable --now tailscaled 2>/dev/null && systemctl is-active --quiet tailscaled; then
        info "检测到 Tailscale ${current_version} 且 tailscaled 运行正常，跳过安装。"
        return 0
      fi
      warn "检测到 Tailscale ${current_version}，但 tailscaled 服务异常，将继续执行修复安装。"
    fi
  fi

  info "优先使用可校验的 Tailscale 官方静态包（支持 /root 本地文件优先）..."
  if install_tailscale_static "$target_version"; then
    success "Tailscale 客户端静态包安装完成。"
    return 0
  fi

  warn "Tailscale 静态包线路不可用，最后尝试官方 install.sh..."
  if curl -fsSL --connect-timeout 15 --max-time 90 https://tailscale.com/install.sh | sh; then
    if command_exists tailscale && systemctl enable --now tailscaled && systemctl is-active --quiet tailscaled; then
      success "Tailscale 客户端通过官方 install.sh 安装完成。"
      return 0
    fi
    warn "官方 install.sh 已执行，但 Tailscale 命令或 tailscaled 服务仍不正常。"
  fi

  cat <<EOF
${RED}[ERROR]${NC} Tailscale 客户端安装失败。

中国大陆服务器建议：
1. 在其它网络下载 tailscale_${target_version}_${ARCH}.tgz
2. 同时下载 tailscale_${target_version}_${ARCH}.tgz.sha256
3. 上传到 /root/
4. 重新执行安装

也可以通过 TAILSCALE_DOWNLOAD_BASE 指定你自己的可信镜像目录。
EOF
  return 1
}

install_headscale() {
  local headscale_version="$1"
  local current_version=""
  local current_major=""
  local current_minor=""
  local target_major=""
  local target_minor=""
  local backup_root=""
  local runtime_mask="/run/systemd/system/headscale.service"
  local created_runtime_mask=0
  local deb_name="headscale_${headscale_version}_linux_${ARCH}.deb"
  local deb_url="https://github.com/juanfont/headscale/releases/download/v${headscale_version}/${deb_name}"
  local deb_file="${WORKDIR}/${deb_name}"
  local -a download_urls=()

  target_major="${headscale_version%%.*}"
  target_minor="$(cut -d. -f2 <<< "$headscale_version")"
  if command_exists headscale; then
    current_version="$(headscale version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
  fi

  if [[ -n "$current_version" && "$current_version" == "$headscale_version" ]]; then
    info "检测到 Headscale ${current_version} 已是目标版本，跳过 DEB 重装。"
    return 0
  fi

  if [[ -n "$current_version" ]]; then
    current_major="${current_version%%.*}"
    current_minor="$(cut -d. -f2 <<< "$current_version")"
    [[ "$target_major" == "$current_major" ]] || die "检测到 Headscale ${current_version}，不能直接跨主版本升级到 ${headscale_version}。"
    (( target_minor >= current_minor )) || die "Headscale 不支持从 ${current_version} 降级到 ${headscale_version}。"
    (( target_minor <= current_minor + 1 )) || die "Headscale 要求逐个 minor 升级：当前 ${current_version}，目标 ${headscale_version}。请先升级到 0.$((current_minor + 1)).x 的最新补丁版。"

    backup_root="/root/headscale-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_root"
    [[ -d /etc/headscale ]] && cp -a /etc/headscale "$backup_root/etc-headscale"
    [[ -d /var/lib/headscale ]] && cp -a /var/lib/headscale "$backup_root/var-lib-headscale"
    success "Headscale 升级前备份已保存：${backup_root}"

    if (( target_minor >= 29 )) && [[ -f "$HEADSCALE_CONFIG" ]]; then
      if grep -q '^randomize_client_port:' "$HEADSCALE_CONFIG"; then
        die "检测到 Headscale 0.29 已删除的 randomize_client_port。0.29 会拒绝启动；请先把该设置迁移到 policy.path 指向的策略文件顶层 randomizeClientPort，再删除旧配置键后重试。备份已保存：${backup_root}"
      fi

      if grep -q '^ephemeral_node_inactivity_timeout:' "$HEADSCALE_CONFIG"; then
        warn "检测到已弃用的 ephemeral_node_inactivity_timeout。Headscale 0.29 仍兼容该键，本脚本不会擅自改写；建议后续迁移到 node.ephemeral.inactivity_timeout。"
      fi
    fi
    systemctl stop headscale 2>/dev/null || true
  fi

  info "安装 Headscale ${headscale_version}..."
  mapfile -t download_urls < <(github_download_urls "$deb_url")
  find_or_download_file "$deb_name" "$deb_file" "${download_urls[@]}"
  mv -f "$deb_file" "${WORKDIR}/headscale.deb"

  # Headscale 官方 DEB 的 postinst 会自动 start/restart 服务。
  # 先做临时 runtime mask，确保数据库/配置备份完成后，由本脚本 configtest 通过再启动。
  if [[ -d /run/systemd/system ]]; then
    if systemctl is-enabled headscale.service 2>/dev/null | grep -qx 'masked'; then
      die "headscale.service 当前已被管理员 mask。请先确认原因并手动 unmask 后再升级。"
    fi
    if [[ -e "$runtime_mask" || -L "$runtime_mask" ]]; then
      die "检测到自定义 runtime unit：${runtime_mask}。为避免覆盖现有 systemd 设置，已停止安装。"
    fi
    ln -s /dev/null "$runtime_mask"
    created_runtime_mask=1
    systemctl daemon-reload
  fi

  # 保留已有 Headscale 配置，避免升级时 dpkg 因 conffile 交互而卡住或覆盖用户配置。
  if ! dpkg --force-confold -i "${WORKDIR}/headscale.deb"; then
    if ! DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -f -y; then
      if [[ "$created_runtime_mask" -eq 1 ]]; then
        rm -f "$runtime_mask"
        systemctl daemon-reload || true
      fi
      die "Headscale DEB 安装失败。"
    fi
  fi

  if [[ "$created_runtime_mask" -eq 1 ]]; then
    rm -f "$runtime_mask"
    systemctl daemon-reload
  fi

  systemctl enable headscale
  systemctl stop headscale 2>/dev/null || true
  success "Headscale 软件包安装完成，等待配置校验后启动。"
}

install_headscale_ui() {
  local headscale_ui_version="$1"
  local ui_zip_name="headscale-ui.zip"
  local ui_zip_path="${WORKDIR}/${ui_zip_name}"
  local ui_url="https://github.com/gurucomputing/headscale-ui/releases/download/${headscale_ui_version}/${ui_zip_name}"
  local -a download_urls=()

  info "获取 Headscale Web UI ${headscale_ui_version}..."
  mapfile -t download_urls < <(github_download_urls "$ui_url")
  find_or_download_file "$ui_zip_name" "$ui_zip_path" "${download_urls[@]}"

  info "部署 Headscale Web UI..."
  mkdir -p /var/www
  rm -rf "$HEADSCALE_UI_DIR"
  unzip -o "$ui_zip_path" -d /var/www >/dev/null

  [[ -f "${HEADSCALE_UI_DIR}/index.html" ]] || die "Headscale Web UI 解压后未找到 ${HEADSCALE_UI_DIR}/index.html，请检查压缩包目录结构是否与博客使用版本一致。"
  success "Headscale Web UI 部署完成。"
}

install_node_binary() {
  local version="$1"
  local node_arch=""
  local filename=""
  local archive=""
  local expected=""
  local actual=""
  local staging=""
  local extracted=""
  local dest=""
  local tool=""
  local -a urls=()

  node_arch="$(node_download_arch)" || return 1
  filename="node-v${version}-linux-${node_arch}.tar.xz"
  archive="${WORKDIR}/${filename}"
  staging="${WORKDIR}/node-static-${version}-${node_arch}"
  extracted="${staging}/node-v${version}-linux-${node_arch}"
  dest="/usr/local/lib/nodejs/node-v${version}-linux-${node_arch}"

  mapfile -t urls < <(node_download_urls "$version" "$filename")
  find_or_download_file "$filename" "$archive" "${urls[@]}" || return 1

  expected="$(node_expected_sha256 "$version" "$filename" "$node_arch" || true)"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
    warn "无法取得 ${filename} 的可信 SHA256；为避免执行未校验二进制，已停止 Node.js 二进制安装。"
    return 1
  }
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    warn "Node.js 二进制包 SHA256 不匹配：${filename}"
    return 1
  }

  rm -rf "$staging"
  mkdir -p "$staging"
  tar -xJf "$archive" -C "$staging"
  [[ -x "${extracted}/bin/node" ]] || {
    warn "Node.js 二进制包目录结构不符合预期。"
    return 1
  }

  mkdir -p /usr/local/lib/nodejs /usr/local/bin
  rm -rf "$dest"
  mv "$extracted" "$dest"
  for tool in node npm npx corepack; do
    if [[ -e "${dest}/bin/${tool}" ]]; then
      ln -sfn "${dest}/bin/${tool}" "/usr/local/bin/${tool}"
    fi
  done
  export PATH="/usr/local/bin:${PATH}"
  hash -r
  return 0
}

install_headplane_runtime() {
  local node_version=""
  local node_major=""
  local node_target_version=""
  local pnpm_version=""

  if command_exists node; then
    node_version="$(node -v | sed 's/^v//')"
    node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  fi

  if [[ -n "$node_major" && "$node_major" -eq 22 ]] && version_ge "$node_version" "22.18.0"; then
    info "检测到兼容的 Node.js v${node_version}，跳过安装 Node.js。"
  else
    node_target_version="$(fetch_latest_node22 2>/dev/null || echo "$NODE_FALLBACK_VERSION")"
    [[ -n "$node_target_version" ]] || node_target_version="$NODE_FALLBACK_VERSION"
    info "安装 Headplane 所需 Node.js 22（目标 v${node_target_version}，要求 >=22.18 且 <23）..."

    if ! install_node_binary "$node_target_version"; then
      warn "Node.js 二进制包线路不可用，最后尝试 NodeSource..."
      apt update
      DEBIAN_FRONTEND=noninteractive apt install -y gnupg build-essential
      curl -fsSL --connect-timeout 15 --max-time 90 https://deb.nodesource.com/setup_22.x | bash -
      DEBIAN_FRONTEND=noninteractive apt install -y nodejs
    fi
    hash -r
    node_version="$(node -v | sed 's/^v//')"
    node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  fi

  [[ -n "$node_major" && "$node_major" -eq 22 ]] && version_ge "$node_version" "22.18.0" || die "当前 Node.js 版本不兼容 Headplane：v${node_version:-unknown}。请使用 22.18.x 到 22.x 最新稳定版。"
  HEADPLANE_NODE_BIN="$(command -v node)"
  [[ -x "$HEADPLANE_NODE_BIN" ]] || die "无法定位可执行的 Node.js。"

  if command_exists pnpm; then
    pnpm_version="$(pnpm -v)"
    if version_ge "$pnpm_version" "10.4.0"; then
      info "检测到兼容的 pnpm ${pnpm_version}，跳过安装 pnpm。"
    else
      info "检测到 pnpm ${pnpm_version}，但版本过低，升级到 10.4.0 ..."
      npm --registry=https://registry.npmmirror.com install -g --prefix /usr/local pnpm@10.4.0
    fi
  else
    info "安装 pnpm 10.4.0 ..."
    npm --registry=https://registry.npmmirror.com install -g --prefix /usr/local pnpm@10.4.0
  fi

  command_exists node || die "Node.js 安装失败。"
  command_exists pnpm || die "pnpm 安装失败。"
}

install_headplane() {
  local headplane_version="$1"
  local source_name="headplane-v${headplane_version}.tar.gz"
  local source_path="${WORKDIR}/${source_name}"
  local source_url="https://github.com/tale/headplane/archive/refs/tags/v${headplane_version}.tar.gz"
  local cookie_secret=""
  local -a download_urls=()

  info "开始安装 Headplane ${headplane_version}（原生模式）..."
  install_headplane_runtime

  rm -rf "$HEADPLANE_DIR"
  mapfile -t download_urls < <(github_download_urls "$source_url")
  find_or_download_file "$source_name" "$source_path" "${download_urls[@]}"
  mkdir -p "$HEADPLANE_DIR"
  tar -xzf "$source_path" -C "$HEADPLANE_DIR" --strip-components=1

  pushd "$HEADPLANE_DIR" >/dev/null
  pnpm config set registry https://registry.npmmirror.com
  pnpm install --frozen-lockfile
  pnpm build
  popd >/dev/null

  mkdir -p "$HEADPLANE_CONFIG_DIR" "$HEADPLANE_DATA_DIR"
  cookie_secret="$(openssl rand -hex 16)"

  cat > "$HEADPLANE_CONFIG" <<EOF
server:
  host: "127.0.0.1"
  port: ${HEADPLANE_PORT}
  base_url: "http://${SERVER_IP}:${HEADSCALE_PORT}"
  cookie_secret: "${cookie_secret}"
  cookie_secure: false
  cookie_max_age: 86400
  data_path: "${HEADPLANE_DATA_DIR}"

headscale:
  url: "http://127.0.0.1:${HEADSCALE_INTERNAL_PORT}"
  public_url: "http://${SERVER_IP}:${HEADSCALE_PORT}"
  config_path: "${HEADSCALE_CONFIG}"
  config_strict: false

integration:
  docker:
    enabled: false
  kubernetes:
    enabled: false
    pod_name: "headscale"
  proc:
    enabled: true
EOF

  cat > "$HEADPLANE_SERVICE" <<EOF
[Unit]
Description=Headplane Service
After=network.target headscale.service
Requires=network.target headscale.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=${HEADPLANE_DIR}
ExecStart=${HEADPLANE_NODE_BIN} ${HEADPLANE_DIR}/build/server/index.js
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable headplane
  systemctl restart headplane
  success "Headplane 部署完成。"
}

configure_nginx() {
  info "配置 Nginx..."

  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

  cat > "$NGINX_AVAILABLE" <<EOF
##
map \$http_upgrade \$connection_upgrade {
 default keep-alive;
 "websocket" upgrade;
 "" close;
}
server {
 listen ${HEADSCALE_PORT};
 listen [::]:${HEADSCALE_PORT};
 server_name ${SERVER_IP};
EOF

  if [[ "$PANEL_TYPE" == "headplane" ]]; then
    cat >> "$NGINX_AVAILABLE" <<EOF
 location = /admin {
 return 301 /admin/;
 }
 location /admin/ {
 proxy_pass http://127.0.0.1:${HEADPLANE_PORT};
 proxy_http_version 1.1;
 proxy_set_header Upgrade \$http_upgrade;
 proxy_set_header Connection \$connection_upgrade;
 proxy_set_header Host \$http_host;
 proxy_buffering off;
 proxy_set_header X-Real-IP \$remote_addr;
 proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
 proxy_set_header X-Forwarded-Proto \$scheme;
 }
 location / {
 proxy_pass http://127.0.0.1:${HEADSCALE_INTERNAL_PORT};
 proxy_http_version 1.1;
 proxy_set_header Upgrade \$http_upgrade;
 proxy_set_header Connection \$connection_upgrade;
 proxy_set_header Host \$http_host;
 proxy_buffering off;
 proxy_set_header X-Real-IP \$remote_addr;
 proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
 proxy_set_header X-Forwarded-Proto \$scheme;
 }
}
EOF
  else
    cat >> "$NGINX_AVAILABLE" <<EOF
 location / {
 proxy_pass http://127.0.0.1:${HEADSCALE_INTERNAL_PORT};
 proxy_http_version 1.1;
 proxy_set_header Upgrade \$http_upgrade;
 proxy_set_header Connection \$connection_upgrade;
 proxy_set_header Host \$http_host;
 proxy_buffering off;
 proxy_set_header X-Real-IP \$remote_addr;
 proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
 proxy_set_header X-Forwarded-Proto \$scheme;
 }
 location /web {
 index index.html;
 alias /var/www/web;
 }
}
EOF
  fi

  ln -sfn "$NGINX_AVAILABLE" "$NGINX_ENABLED"

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
  success "Nginx 配置完成。"
}

configure_headscale() {
  info "修改 Headscale 配置..."
  [[ -f "$HEADSCALE_CONFIG" ]] || die "未找到 ${HEADSCALE_CONFIG}，无法继续修改 Headscale 配置。"
  [[ "${DERP_CERT_HASH:-}" =~ ^[0-9a-f]{64}$ ]] || die "DERP 证书指纹不存在，无法生成安全的 DERP Map。"
  local custom_derp_urls=""

  cp -f "$HEADSCALE_CONFIG" "${HEADSCALE_CONFIG}.bak.$(date +%s)"

  grep -q '^server_url:' "$HEADSCALE_CONFIG" || die "Headscale 配置中未找到 server_url 字段，当前版本配置模板可能已变化。"
  grep -q '^listen_addr:' "$HEADSCALE_CONFIG" || die "Headscale 配置中未找到 listen_addr 字段，当前版本配置模板可能已变化。"
  grep -q 'v4: 100.64.0.0/10' "$HEADSCALE_CONFIG" || warn "未找到默认 v4 网段，稍后请手动确认 prefixes.v4 是否已正确修改。"

  sed -i "s|^server_url:.*|server_url: http://${SERVER_IP}:${HEADSCALE_PORT}|" "$HEADSCALE_CONFIG"
  sed -i "s|^listen_addr:.*|listen_addr: 127.0.0.1:${HEADSCALE_INTERNAL_PORT}|" "$HEADSCALE_CONFIG"
  sed -i "s|^\([[:space:]]*\)v4: 100.64.0.0/10|\1v4: ${IP_PREFIX}/24|" "$HEADSCALE_CONFIG"
  sed -i "s|^\([[:space:]]*\)v6: fd7a:115c:a1e0::/48|#\1v6: fd7a:115c:a1e0::/48|" "$HEADSCALE_CONFIG"

  if grep -q '^trusted_proxies: \[\]' "$HEADSCALE_CONFIG"; then
    sed -i 's|^trusted_proxies: \[\]|trusted_proxies:\n  - "127.0.0.1/32"\n  - "::1/128"|' "$HEADSCALE_CONFIG"
  elif grep -q '^trusted_proxies:' "$HEADSCALE_CONFIG"; then
    if ! grep -A8 '^trusted_proxies:' "$HEADSCALE_CONFIG" | grep -q '127.0.0.1/32'; then
      warn "trusted_proxies 已有自定义配置，未自动覆盖；请确认其中包含 127.0.0.1/32 和 ::1/128。"
    fi
  fi

  # 保持本项目原有行为：不使用 Tailscale 官方 DERP，只加载本机自建 DERP Map。
  # 如果用户已经配置了其它 DERP URL，则停止而不是覆盖。
  custom_derp_urls="$(awk '
    /^derp:/ { in_derp=1; next }
    in_derp && /^[^[:space:]]/ { in_derp=0; in_urls=0 }
    in_derp && /^  urls:/ { in_urls=1; next }
    in_urls && /^  [[:alnum:]_]+:/ { in_urls=0 }
    in_urls && /^[[:space:]]+- / { print }
  ' "$HEADSCALE_CONFIG" | grep -v 'https://controlplane.tailscale.com/derpmap/default' || true)"
  if [[ -n "$custom_derp_urls" ]]; then
    die "检测到现有自定义 derp.urls，本脚本不会覆盖。请先手动确认是否保留这些 DERP URL，再重新执行。"
  fi
  if grep -q '^  urls:$' "$HEADSCALE_CONFIG"; then
    sed -i 's|^  urls:$|  urls: []|' "$HEADSCALE_CONFIG"
    sed -i '/^[[:space:]]*- https:\/\/controlplane\.tailscale\.com\/derpmap\/default[[:space:]]*$/d' "$HEADSCALE_CONFIG"
  elif ! grep -q '^  urls: \[\]$' "$HEADSCALE_CONFIG"; then
    die "无法安全识别 Headscale derp.urls 配置格式，脚本已停止，避免覆盖现有 DERP 设置。"
  fi
  sed -i '/^[[:space:]]*- http:\/\/127\.0\.0\.1\/d\/derp\.json[[:space:]]*$/d' "$HEADSCALE_CONFIG"

  if grep -q '^  paths: \[\]' "$HEADSCALE_CONFIG"; then
    sed -i "s|^  paths: \[\]|  paths:\n    - ${DERP_MAP}|" "$HEADSCALE_CONFIG"
  elif grep -qF "${DERP_MAP}" "$HEADSCALE_CONFIG"; then
    :
  else
    die "Headscale derp.paths 已有自定义内容，脚本不会覆盖。请手动加入 ${DERP_MAP} 后重试。"
  fi

  grep -q "^server_url: http://${SERVER_IP}:${HEADSCALE_PORT}" "$HEADSCALE_CONFIG" || die "server_url 修改失败，请检查 Headscale 配置文件格式是否变化。"
  grep -q "^listen_addr: 127.0.0.1:${HEADSCALE_INTERNAL_PORT}" "$HEADSCALE_CONFIG" || die "listen_addr 修改失败，请检查 Headscale 配置文件格式是否变化。"

  cat > "$DERP_MAP" <<EOF
regions:
  900:
    regionid: 900
    regioncode: myderp
    regionname: My DERP
    nodes:
      - name: 900a
        regionid: 900
        hostname: "${DOMAIN}"
        ipv4: "${SERVER_IP}"
        stunport: 3478
        derpport: ${DERP_PORT}
        certname: "sha256-raw:${DERP_CERT_HASH}"
EOF
  chmod 0644 "$DERP_MAP"

  info "执行 Headscale 配置校验..."
  headscale -c "$HEADSCALE_CONFIG" configtest || die "Headscale configtest 失败，已停止启动；请根据上方错误检查配置。"
  systemctl restart headscale
  success "Headscale 配置完成。"
}

create_apikey() {
  info "生成 Headscale API Key..."
  local attempt
  for attempt in 1 2 3 4 5; do
    if headscale apikeys create; then
      return 0
    fi
    warn "API Key 生成失败，等待 Headscale 就绪后重试（${attempt}/5）..."
    sleep 3
  done

  if ! headscale apikeys create; then
    warn "API Key 自动生成失败，但主体安装已完成。可稍后手动执行：headscale apikeys create"
  fi
}

enable_verify_clients_if_needed() {
  local answer=""
  echo
  warn "是否启用 DERP 客户端校验（通过 Headscale /verify）？"
  warn "建议先确认 Headscale、DERP、客户端接入都已经正常后再启用。"
  warn "启用后会限制未通过验证的客户端使用当前 DERP 中继服务。"
  read -r -p "现在启用吗？[Y/n]: " answer || true
  answer="${answer:-Y}"

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    if grep -q -- '-verify-client-url ' "$DERP_SERVICE"; then
      info "检测到 derp.service 已启用 Headscale /verify 校验，跳过重复修改。"
    else
      sed -i "s|^ExecStart=.*|& -verify-client-url http://127.0.0.1:${HEADSCALE_INTERNAL_PORT}/verify -verify-client-url-fail-open=false|" "$DERP_SERVICE"
      systemctl daemon-reload
      systemctl restart derp
      success "已启用 DERP 客户端校验（Headscale /verify，验证服务异常时拒绝放行）。"
    fi
  else
    info "已跳过启用 DERP 客户端校验，后续可手动开启。"
  fi
}

post_install_health_check() {
  local failures=0
  local panel_url="http://127.0.0.1:${HEADSCALE_PORT}${PANEL_PATH%/}/"

  echo
  echo "========== 安装验收 =========="
  if headscale -c "$HEADSCALE_CONFIG" configtest >/dev/null 2>&1; then echo "Headscale configtest   ✓"; else echo "Headscale configtest   ✗"; failures=$((failures + 1)); fi
  if systemctl is-active --quiet headscale; then echo "Headscale service      ✓"; else echo "Headscale service      ✗"; failures=$((failures + 1)); fi
  if curl -fsS --connect-timeout 3 --max-time 5 "http://127.0.0.1:${HEADSCALE_INTERNAL_PORT}/health" >/dev/null 2>&1; then echo "Headscale /health      ✓"; else echo "Headscale /health      ✗"; failures=$((failures + 1)); fi
  if nginx -t >/dev/null 2>&1; then echo "Nginx config           ✓"; else echo "Nginx config           ✗"; failures=$((failures + 1)); fi
  if systemctl is-active --quiet nginx; then echo "Nginx service          ✓"; else echo "Nginx service          ✗"; failures=$((failures + 1)); fi
  if curl -fsS --connect-timeout 3 --max-time 5 -H "Host: ${SERVER_IP}" "$panel_url" >/dev/null 2>&1; then echo "管理面板               ✓"; else echo "管理面板               ✗"; failures=$((failures + 1)); fi
  if systemctl is-active --quiet derp; then echo "DERP service           ✓"; else echo "DERP service           ✗"; failures=$((failures + 1)); fi
  if tcp_port_in_use "$DERP_PORT"; then echo "DERP TCP ${DERP_PORT}        ✓"; else echo "DERP TCP ${DERP_PORT}        ✗"; failures=$((failures + 1)); fi
  if udp_port_in_use 3478; then echo "STUN UDP 3478         ✓"; else echo "STUN UDP 3478         ✗"; failures=$((failures + 1)); fi
  if command_exists tailscale && systemctl is-active --quiet tailscaled; then echo "Tailscale client       ✓"; else echo "Tailscale client       ✗"; failures=$((failures + 1)); fi
  if [[ "$PANEL_TYPE" == "headplane" ]]; then
    if systemctl is-active --quiet headplane; then echo "Headplane service      ✓"; else echo "Headplane service      ✗"; failures=$((failures + 1)); fi
  fi
  echo "Peer Relay             ○ 尚未配置/按需启用"
  echo "=============================="

  if [[ "$failures" -eq 0 ]]; then
    success "安装验收全部通过。"
    return 0
  fi
  warn "安装主体已完成，但有 ${failures} 项验收未通过。请先查看上方项目，再使用 hs 菜单排查。"
  return 1
}

show_summary() {
  local panel_url="http://${SERVER_IP}:${HEADSCALE_PORT}${PANEL_PATH}"

  cat <<EOF

${GREEN}安装完成。${NC}

访问地址：
- 管理面板（${PANEL_TYPE}）: ${panel_url}

客户端首次接入命令：
  tailscale login --login-server=http://${SERVER_IP}:${HEADSCALE_PORT}

Tailscale 虚拟内网网段：
  ${IP_PREFIX}/24

子网路由示例：
  tailscale up --login-server=http://${SERVER_IP}:${HEADSCALE_PORT} --accept-routes=true
  tailscale up --login-server=http://${SERVER_IP}:${HEADSCALE_PORT} --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset

DERP：
- 自建 DERP Map: ${DERP_MAP}
- 证书使用 SHA256 指纹固定
- 使用项目 Release 预编译 derper，目标服务器无需 Go
- DERP HTTP listener 已关闭
- 请确认 UDP 3478（STUN）和 TCP ${DERP_PORT} 已放行

Peer Relay：
- 默认 UDP 端口: ${PEER_RELAY_DEFAULT_PORT}（首次安装随机生成并保存）
- 安装完成后输入 hs，选择“Peer Relay 管理”
- 连接优先级：DIRECT -> Peer Relay -> DERP
EOF
}

main() {
  local confirm=""
  local reinstall_panel=1
  local current_headscale=""
  local current_tailscale=""
  local default_headscale_port=""
  local default_derp_port=""
  local default_peer_relay_port=""

  require_root
  check_system
  install_preflight_tools
  detect_arch
  prepare_workdir
  SERVER_IP_DEFAULT="$(detect_public_ip)"
  load_existing_install_defaults
  show_preflight_summary
  prompt_install_mode

  if [[ "$INSTALL_MODE" == "quick" ]]; then
    if [[ "$EXISTING_INSTALL" -eq 1 ]]; then
      SERVER_IP="${EXISTING_SERVER_IP:-$SERVER_IP_DEFAULT}"
      if ! validate_ipv4 "$SERVER_IP"; then
        prompt_server_ip "$SERVER_IP_DEFAULT"
      fi
      DOMAIN="${EXISTING_DERP_HOST:-$SERVER_IP}"
      [[ -n "$EXISTING_HEADSCALE_PORT" ]] || die "检测到已有安装，但无法识别原 Headscale 端口。请改用高级模式确认配置，脚本不会擅自更换端口。"
      [[ -n "$EXISTING_DERP_PORT" ]] || die "检测到已有安装，但无法识别原 DERP 端口。请改用高级模式确认配置，脚本不会擅自更换端口。"
      HEADSCALE_PORT="$EXISTING_HEADSCALE_PORT"
      DERP_PORT="$EXISTING_DERP_PORT"
      PEER_RELAY_DEFAULT_PORT="${EXISTING_PEER_RELAY_PORT:-40000}"
      PANEL_TYPE="${EXISTING_PANEL_TYPE:-headscale-ui}"
      PANEL_PATH="${EXISTING_PANEL_PATH:-/web}"
      reinstall_panel=0
    else
      if validate_ipv4 "$SERVER_IP_DEFAULT"; then
        SERVER_IP="$SERVER_IP_DEFAULT"
      else
        prompt_server_ip ""
      fi
      DOMAIN="$SERVER_IP"
      HEADSCALE_PORT="$(random_free_port tcp)" || die "无法为 Headscale 生成可用随机端口。"
      DERP_PORT="$(random_free_port tcp "$HEADSCALE_PORT")" || die "无法为 DERP 生成可用随机端口。"
      PEER_RELAY_DEFAULT_PORT="$(random_free_port udp "$HEADSCALE_PORT" "$DERP_PORT")" || die "无法为 Peer Relay 生成可用随机端口。"
      PANEL_TYPE="headscale-ui"
      PANEL_PATH="/web"
    fi
    if [[ "$EXISTING_INSTALL" -eq 1 ]]; then
      IP_PREFIX="${EXISTING_IP_PREFIX:-100.64.0.0}"
      info "已有安装：继续使用 Tailscale 虚拟内网网段 ${IP_PREFIX}/24，快速模式不会自动修改。"
    else
      prompt_ip_prefix "100.64.0.0"
    fi
    current_tailscale="$(tailscale version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
    current_headscale="$(headscale version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
    TAILSCALE_VERSION="${current_tailscale:-$TAILSCALE_FALLBACK_VERSION}"
    HEADSCALE_VERSION="${current_headscale:-$HEADSCALE_FALLBACK_VERSION}"
    if [[ "$PANEL_TYPE" == "headplane" ]]; then
      HEADPLANE_VERSION="$HEADPLANE_FALLBACK_VERSION"
    else
      HEADSCALE_UI_VERSION="$HEADSCALE_UI_FALLBACK_VERSION"
    fi
    info "快速模式：新安装默认使用公网 IP 作为 DERP 主机名，并为公网服务随机生成一次端口；已有安装会继承原配置。"
  else
    prompt_server_ip "${EXISTING_SERVER_IP:-${SERVER_IP_DEFAULT:-}}"
    prompt_value DOMAIN "请输入 DERP 主机名（无域名可直接使用公网 IP）" "${EXISTING_DERP_HOST:-$SERVER_IP}"
    default_headscale_port="${EXISTING_HEADSCALE_PORT:-}"
    [[ -n "$default_headscale_port" ]] || default_headscale_port="$(random_free_port tcp)" || die "无法生成 Headscale 默认随机端口。"
    default_derp_port="${EXISTING_DERP_PORT:-}"
    [[ -n "$default_derp_port" ]] || default_derp_port="$(random_free_port tcp "$default_headscale_port")" || die "无法生成 DERP 默认随机端口。"
    default_peer_relay_port="${EXISTING_PEER_RELAY_PORT:-}"
    if [[ -z "$default_peer_relay_port" ]]; then
      if [[ "$EXISTING_INSTALL" -eq 1 ]]; then
        default_peer_relay_port="40000"
      else
        default_peer_relay_port="$(random_free_port udp "$default_headscale_port" "$default_derp_port")" || die "无法生成 Peer Relay 默认随机端口。"
      fi
    fi
    prompt_value HEADSCALE_PORT "请输入 Headscale 端口" "$default_headscale_port"
    prompt_ip_prefix "${EXISTING_IP_PREFIX:-100.64.0.0}"
    prompt_value DERP_PORT "请输入 DERP 服务端口" "$default_derp_port"
    prompt_value PEER_RELAY_DEFAULT_PORT "请输入 Peer Relay 默认 UDP 端口（启用时使用）" "$default_peer_relay_port"
    detect_latest_versions
    prompt_version_value TAILSCALE_VERSION "Tailscale 客户端" "$TAILSCALE_LATEST_VERSION" "$TAILSCALE_FALLBACK_VERSION"
    prompt_version_value HEADSCALE_VERSION "Headscale" "$HEADSCALE_LATEST_VERSION" "$HEADSCALE_FALLBACK_VERSION"
    if [[ "${EXISTING_PANEL_TYPE:-}" == "headplane" ]]; then
      prompt_panel_type 2
    else
      prompt_panel_type 1
    fi
    if [[ "$PANEL_TYPE" == "headplane" ]]; then
      prompt_version_value HEADPLANE_VERSION "Headplane" "$HEADPLANE_LATEST_VERSION" "$HEADPLANE_FALLBACK_VERSION"
    else
      prompt_version_value HEADSCALE_UI_VERSION "Headscale-ui" "$HEADSCALE_UI_LATEST_VERSION" "$HEADSCALE_UI_FALLBACK_VERSION"
    fi
  fi

  validate_ipv4 "$SERVER_IP" || die "服务器 IP 格式不正确。"
  validate_hostname_or_ipv4 "$DOMAIN" || die "DERP 主机名格式不正确；只允许标准 DNS 主机名或 IPv4 地址。"
  validate_ip_prefix24 "$IP_PREFIX" || die "Tailscale 虚拟内网网段格式不正确；当前脚本使用 /24，应类似 100.64.10.0。"
  validate_port "$HEADSCALE_PORT" || die "Headscale 端口无效。"
  validate_port "$DERP_PORT" || die "DERP 端口无效。"
  validate_port "$PEER_RELAY_DEFAULT_PORT" || die "Peer Relay 默认端口无效。"
  check_selected_ports

  echo
  echo "========== 安装计划 =========="
  echo "模式:          ${INSTALL_MODE}"
  echo "服务器 IP:     ${SERVER_IP}"
  echo "DERP 主机名:   ${DOMAIN}"
  echo "Headscale:     ${HEADSCALE_VERSION} / TCP ${HEADSCALE_PORT}"
  echo "Tailscale:     ${TAILSCALE_VERSION}"
  echo "虚拟内网网段: ${IP_PREFIX}/24"
  echo "DERP:          Tailscale ${DERPER_TAILSCALE_VERSION} 预编译版 / TCP ${DERP_PORT} / UDP 3478"
  echo "Peer Relay:    UDP ${PEER_RELAY_DEFAULT_PORT}（按需启用）"
  echo "管理面板:      ${PANEL_TYPE}"
  echo "DERP HTTP:     已关闭"
  echo "=============================="
  read -r -p "确认开始安装？[Y/n]: " confirm || true
  confirm="${confirm:-Y}"
  [[ "$confirm" =~ ^[Yy]$ ]] || { warn "已取消安装。"; exit 0; }

  show_firewall_notice
  install_base_packages
  install_derp
  install_tailscale "$TAILSCALE_VERSION"
  install_headscale "$HEADSCALE_VERSION"
  configure_headscale
  if [[ "$reinstall_panel" -eq 1 ]]; then
    if [[ "$PANEL_TYPE" == "headplane" ]]; then
      install_headplane "$HEADPLANE_VERSION"
    else
      install_headscale_ui "$HEADSCALE_UI_VERSION"
    fi
  else
    info "快速升级检测到已有面板，跳过重复安装面板文件。"
  fi
  configure_nginx
  save_panel_state
  if [[ "$EXISTING_INSTALL" -eq 0 ]]; then
    create_apikey
  else
    info "已有安装：跳过自动生成新的 API Key；需要时可手动执行 headscale apikeys create。"
  fi
  enable_verify_clients_if_needed
  post_install_health_check || true
  show_summary
}

main "$@"
