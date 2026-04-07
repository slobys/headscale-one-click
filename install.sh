#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="1.4.0"
WORKDIR="/usr/local/src/headscale-one-click"
DERP_DIR="/etc/derp"
DERP_SERVICE="/etc/systemd/system/derp.service"
NGINX_SITE_NAME="headscale-one-click"
NGINX_AVAILABLE="/etc/nginx/sites-available/${NGINX_SITE_NAME}.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/${NGINX_SITE_NAME}.conf"
HEADSCALE_CONFIG="/etc/headscale/config.yaml"
HEADSCALE_UI_DIR="/var/www/web"
DERP_JSON="/var/www/derp.json"

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

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local input_value=""

  read -r -p "${prompt_text} [默认: ${default_value}]: " input_value || true
  input_value="${input_value:-$default_value}"
  printf -v "$var_name" '%s' "$input_value"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

validate_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

detect_arch() {
  local machine_arch
  machine_arch="$(uname -m)"
  case "$machine_arch" in
    x86_64|amd64)
      ARCH="amd64"
      GO_ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      GO_ARCH="arm64"
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
}

show_firewall_notice() {
  cat <<EOF
${YELLOW}========== 重要提醒 ==========${NC}
原始脚本会直接关闭 ufw / firewalld / iptables。
为了更适合真实服务器环境，这个整合版不会自动清空防火墙。

请手动确认以下端口已经放行：
- DERP 端口: ${DERP_PORT}
- DERP HTTP 端口: ${HTTP_PORT}
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
  apt update
  ask_system_upgrade
  DEBIAN_FRONTEND=noninteractive apt install -y wget git openssl curl unzip nginx ca-certificates tar
}

prepare_workdir() {
  mkdir -p "$WORKDIR"
  mkdir -p "$DERP_DIR"
}

find_or_download_file() {
  local filename="$1"
  local url="$2"
  local output_path="$3"

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
  if ! curl -fL --retry 3 --connect-timeout 20 -o "$output_path" "$url"; then
    cat <<EOF
${RED}[ERROR]${NC} 下载失败：${filename}
可能原因：
1. 当前服务器无法稳定访问国外源
2. GitHub / go.dev / tailscale.com 在当前网络下超时
3. 目标版本文件名已变化

中国大陆服务器环境建议处理方式：
- 先在本地电脑下载好对应文件
- 上传到 /root/ 或脚本当前目录
- 然后重新执行脚本

当前尝试下载地址：
${url}
EOF
    return 1
  fi
}

install_go() {
  local go_version="$1"
  local go_file="go${go_version}.linux-${GO_ARCH}.tar.gz"
  local go_url="https://go.dev/dl/${go_file}"
  local go_tar="${WORKDIR}/${go_file}"

  info "安装 Go ${go_version}..."
  find_or_download_file "$go_file" "$go_url" "$go_tar"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$go_tar"

  export PATH="$PATH:/usr/local/go/bin"
  if ! grep -q '/usr/local/go/bin' /etc/profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
  fi

  go version >/dev/null 2>&1 || die "Go 安装失败。"
  go env -w GO111MODULE=on
  go env -w GOPROXY=https://goproxy.cn,direct
  success "Go 安装完成。"
}

install_derp() {
  info "开始安装 DERP 服务..."
  export PATH="$PATH:/usr/local/go/bin"

  go install tailscale.com/cmd/derper@main

  local gopath
  gopath="$(go env GOPATH)"
  local cert_go_path
  cert_go_path="$(find "${gopath}/pkg/mod" -type f -path '*tailscale.com*/cmd/derper/cert.go' | head -n 1)"

  [[ -n "$cert_go_path" ]] || die "未找到 cert.go，无法继续处理 derper 源码。"

  info "检测到 derper cert.go: ${cert_go_path}"
  grep -q 'if hi.ServerName != m.hostname' "$cert_go_path" || die "cert.go 中未找到预期代码段，可能是上游源码结构发生变化。"
  sed -i '/if hi.ServerName != m.hostname/,+2 s/^/\/\//' "$cert_go_path"
  grep -q '//.*if hi.ServerName != m.hostname' "$cert_go_path" || die "DERP 源码修改未生效，请检查当前 derper 版本是否仍兼容此方案。"

  pushd "$(dirname "$cert_go_path")" >/dev/null
  mkdir -p "$DERP_DIR"
  go build -o "$DERP_DIR/derper"
  [[ -x "$DERP_DIR/derper" ]] || die "derper 编译失败，未生成可执行文件。"
  popd >/dev/null

  info "生成 DERP 自签名证书..."
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$DERP_DIR/${DOMAIN}.key" \
    -out "$DERP_DIR/${DOMAIN}.crt" \
    -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN}"

  cat > "$DERP_SERVICE" <<EOF
[Unit]
Description=TS Derper
After=network.target
Wants=network.target

[Service]
User=root
Restart=always
ExecStart=${DERP_DIR}/derper -hostname ${DOMAIN} -a :${DERP_PORT} -http-port ${HTTP_PORT} -certmode manual -certdir ${DERP_DIR}
RestartPreventExitStatus=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable derp
  systemctl restart derp

  success "DERP 安装完成。"
}

install_tailscale() {
  info "安装 Tailscale 客户端..."
  if ! curl -fsSL https://tailscale.com/install.sh | sh; then
    cat <<EOF
${YELLOW}[WARN]${NC} Tailscale 客户端自动安装失败。
这通常是因为当前中国大陆服务器环境无法稳定访问 tailscale.com。

可先手动安装 Tailscale 客户端，然后再重新运行本脚本后续步骤。
官方安装说明：
https://tailscale.com/download/linux
EOF
    return 1
  fi
  success "Tailscale 客户端安装完成。"
}

install_headscale() {
  local headscale_version="$1"
  local deb_name="headscale_${headscale_version}_linux_${ARCH}.deb"
  local deb_url="https://github.com/juanfont/headscale/releases/download/v${headscale_version}/${deb_name}"
  local deb_file="${WORKDIR}/${deb_name}"

  info "安装 Headscale ${headscale_version}..."
  find_or_download_file "$deb_name" "$deb_url" "$deb_file"
  mv -f "$deb_file" "${WORKDIR}/headscale.deb"
  dpkg -i "${WORKDIR}/headscale.deb" || apt-get install -f -y

  systemctl enable headscale
  systemctl restart headscale
  success "Headscale 安装完成。"
}

install_headscale_ui() {
  local ui_zip_name="headscale-ui.zip"
  local ui_zip_path="${WORKDIR}/${ui_zip_name}"

  [[ -f "/root/${ui_zip_name}" ]] || [[ -f "./${ui_zip_name}" ]] || die "未找到 ${ui_zip_name}。中国大陆服务器环境建议先把 Headscale Web UI 压缩包上传到 /root/ 或当前目录。"

  if [[ -f "/root/${ui_zip_name}" ]]; then
    cp -f "/root/${ui_zip_name}" "$ui_zip_path"
  else
    cp -f "./${ui_zip_name}" "$ui_zip_path"
  fi

  info "部署 Headscale Web UI..."
  mkdir -p /var/www
  rm -rf "$HEADSCALE_UI_DIR"
  unzip -o "$ui_zip_path" -d /var/www >/dev/null

  [[ -f "${HEADSCALE_UI_DIR}/index.html" ]] || die "Headscale Web UI 解压后未找到 ${HEADSCALE_UI_DIR}/index.html，请检查压缩包目录结构是否与博客使用版本一致。"
  success "Headscale Web UI 部署完成。"
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
 location / {
 proxy_pass http://127.0.0.1:8080;
 proxy_http_version 1.1;
 proxy_set_header Upgrade \$http_upgrade;
 proxy_set_header Connection \$connection_upgrade;
 proxy_set_header Host \$host;
 proxy_buffering off;
 proxy_set_header X-Real-IP \$remote_addr;
 proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
 proxy_set_header X-Forwarded-Proto \$scheme;
 add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
 }
 location /web {
 index index.html;
 alias /var/www/web;
 }
}
server {
 listen 80;
 listen [::]:80;
 server_name 127.0.0.1;
 root /var/www;
 index index.html index.htm index.nginx-debian.html;
 location /d {
 alias /var/www;
 autoindex on;
 }
 location / {
 try_files \$uri \$uri/ =404;
 }
}
EOF

  ln -sfn "$NGINX_AVAILABLE" "$NGINX_ENABLED"

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
  success "Nginx 配置完成。"
}

configure_headscale() {
  info "修改 Headscale 配置..."
  [[ -f "$HEADSCALE_CONFIG" ]] || die "未找到 ${HEADSCALE_CONFIG}，无法继续修改 Headscale 配置。"

  cp -f "$HEADSCALE_CONFIG" "${HEADSCALE_CONFIG}.bak.$(date +%s)"

  grep -q '^server_url:' "$HEADSCALE_CONFIG" || die "Headscale 配置中未找到 server_url 字段，当前版本配置模板可能已变化。"
  grep -q 'v4: 100.64.0.0/10' "$HEADSCALE_CONFIG" || warn "未找到默认 v4 网段，稍后请手动确认 prefixes.v4 是否已正确修改。"
  grep -q 'https://controlplane.tailscale.com/derpmap/default' "$HEADSCALE_CONFIG" || warn "未找到默认 derpmap 配置项，稍后请手动确认 DERP 地址是否已正确写入。"

  sed -i "s|^server_url:.*|server_url: http://${SERVER_IP}:${HEADSCALE_PORT}|" "$HEADSCALE_CONFIG"
  sed -i "s|^\([[:space:]]*\)v4: 100.64.0.0/10|\1v4: ${IP_PREFIX}/24|" "$HEADSCALE_CONFIG"
  sed -i "s|^\([[:space:]]*\)v6: fd7a:115c:a1e0::/48|#\1v6: fd7a:115c:a1e0::/48|" "$HEADSCALE_CONFIG"
  sed -i "s|^\([[:space:]]*\)- https://controlplane.tailscale.com/derpmap/default|#\1- https://controlplane.tailscale.com/derpmap/default\n\1- http://127.0.0.1/d/derp.json|" "$HEADSCALE_CONFIG"

  grep -q "^server_url: http://${SERVER_IP}:${HEADSCALE_PORT}" "$HEADSCALE_CONFIG" || die "server_url 修改失败，请检查 Headscale 配置文件格式是否变化。"

  cat > "$DERP_JSON" <<EOF
{
 "Regions": {
  "900": {
   "RegionID": 900,
   "RegionCode": "myderp",
   "Nodes": [
    {
     "Name": "a",
     "RegionID": 900,
     "DERPPort": ${DERP_PORT},
     "IPv4": "${SERVER_IP}",
     "InsecureForTests": true
    }
   ]
  }
 }
}
EOF

  systemctl restart headscale
  systemctl restart nginx
  success "Headscale 配置完成。"
}

create_apikey() {
  info "生成 Headscale API Key..."
  if ! headscale apikeys create --expiration 9999d; then
    warn "API Key 自动生成失败，但主体安装已完成。可稍后手动执行：headscale apikeys create --expiration 9999d"
  fi
}

enable_verify_clients_if_needed() {
  local answer=""
  echo
  warn "是否启用 DERP 客户端校验（--verify-clients）？"
  warn "建议先确认 Headscale、DERP、客户端接入都已经正常后再启用。"
  warn "启用后会限制未通过验证的客户端使用当前 DERP 中继服务。"
  read -r -p "现在启用吗？[y/N]: " answer || true
  answer="${answer:-N}"

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    if grep -q -- '--verify-clients' "$DERP_SERVICE"; then
      info "检测到 derp.service 已启用 --verify-clients，跳过重复修改。"
    else
      sed -i 's|^ExecStart=.*|& --verify-clients|' "$DERP_SERVICE"
      systemctl daemon-reload
      systemctl restart derp
      success "已启用 DERP 客户端校验（--verify-clients）。"
    fi
  else
    info "已跳过启用 DERP 客户端校验，后续可手动开启。"
  fi
}

show_summary() {
  cat <<EOF

${GREEN}安装完成。${NC}

访问地址：
- Headscale Web UI: http://${SERVER_IP}:${HEADSCALE_PORT}/web

客户端接入命令：
  tailscale up --login-server=http://${SERVER_IP}:${HEADSCALE_PORT}

子网路由示例：
  tailscale up --login-server=http://${SERVER_IP}:${HEADSCALE_PORT} --accept-routes=true
  tailscale up --login-server=http://${SERVER_IP}:${HEADSCALE_PORT} --accept-routes=true --accept-dns=false --advertise-routes=192.168.2.0/24 --reset

如需后续手动开启 DERP 客户端校验，可编辑：
  /etc/systemd/system/derp.service
在 ExecStart 最后追加：
  --verify-clients

然后执行：
  systemctl daemon-reload
  systemctl restart derp
EOF
}

main() {
  require_root
  check_system
  detect_arch
  prepare_workdir

  prompt_value DOMAIN "请输入域名" "derp.example.com"
  prompt_value SERVER_IP "请输入服务器IP" "127.0.0.1"
  prompt_value HEADSCALE_PORT "请输入Headscale端口" "8080"
  prompt_value IP_PREFIX "请输入IP前缀（例如：100.64.0.0）" "100.64.0.0"
  prompt_value DERP_PORT "请输入Derp服务端口" "12345"
  prompt_value HTTP_PORT "请输入HTTP端口" "3340"
  prompt_value GO_VERSION "请输入 Go 版本（不要带 go 前缀，例如 1.26.1）" "1.26.1"
  prompt_value HEADSCALE_VERSION "请输入 Headscale 版本" "0.28.0"

  validate_ipv4 "$SERVER_IP" || die "服务器IP格式不正确。"
  validate_ipv4 "$IP_PREFIX" || die "IP前缀格式不正确，应类似 100.64.0.0"
  validate_port "$HEADSCALE_PORT" || die "Headscale端口无效。"
  validate_port "$DERP_PORT" || die "Derp端口无效。"
  validate_port "$HTTP_PORT" || die "HTTP端口无效。"

  show_firewall_notice
  install_base_packages
  install_go "$GO_VERSION"
  install_derp
  install_tailscale
  install_headscale "$HEADSCALE_VERSION"
  install_headscale_ui
  configure_nginx
  configure_headscale
  create_apikey
  enable_verify_clients_if_needed
  show_summary
}

main "$@"
