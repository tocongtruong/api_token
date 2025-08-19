#!/bin/bash
set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info(){ echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err(){  echo -e "${RED}[ERROR]${NC} $1"; }
log_inp(){  echo -e "${BLUE}[INPUT]${NC} $1"; }

echo -e "${GREEN}================================================"
echo "   Flask API Deployment Script (Caddy + Docker Caddy)"
echo -e "================================================${NC}"

# ===== Inputs =====
log_inp "Nhập tên thư mục (sẽ tạo tại /home/\$USER/):"
read -p "Tên thư mục: " PROJECT_NAME
[ -z "${PROJECT_NAME:-}" ] && { log_err "Tên thư mục không được để trống!"; exit 1; }

log_inp "Nhập domain cho API (ví dụ: api.example.com):"
read -p "Domain: " DOMAIN
[ -z "${DOMAIN:-}" ] && { log_err "Domain không được để trống!"; exit 1; }

log_inp "Nhập port nội bộ cho app (mặc định 5000):"
read -p "Port [5000]: " APP_PORT
APP_PORT=${APP_PORT:-5000}

log_inp "Đường dẫn Caddyfile (mặc định: /home/n8n/Caddyfile):"
read -p "Caddyfile [/home/n8n/Caddyfile]: " CADDYFILE
CADDYFILE="${CADDYFILE:-/home/n8n/Caddyfile}"

log_inp "Bạn có muốn tự động restart Caddy container? (y/n) [y]:"
read -p "Restart Caddy: " RESTART_CADDY
RESTART_CADDY=${RESTART_CADDY:-y}

PROJECT_PATH="/home/$USER/$PROJECT_NAME"
GIT_REPO="https://github.com/tocongtruong/api_token.git"
SERVICE_NAME="flask-${PROJECT_NAME}"

echo\ nlog_info "Tóm tắt:"
echo "  Thư mục:   $PROJECT_PATH"
echo "  Domain:    $DOMAIN"
echo "  App port:  $APP_PORT (lắng nghe 0.0.0.0)"
echo "  Caddyfile: $CADDYFILE"
echo

# ===== System update + packages =====
log_info "Cập nhật hệ thống & cài gói cần thiết..."
sudo apt update -y
sudo apt install -y python3 python3-venv python3-pip git ufw curl

# ===== Firewall =====
log_info "Cấu hình UFW (mở 80/443, chặn $APP_PORT từ bên ngoài)..."
sudo ufw --force enable || true
sudo ufw allow 80,443/tcp || true
sudo ufw deny ${APP_PORT}/tcp || true

# ===== Project setup =====
log_info "Chuẩn bị thư mục dự án..."
if [ -d "$PROJECT_PATH" ]; then
  log_warn "Thư mục đã tồn tại → xóa và tạo mới..."
  rm -rf "$PROJECT_PATH"
fi
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"

log_info "Clone mã nguồn..."
git clone "$GIT_REPO" . || { log_err "Clone repo thất bại"; exit 1; }

log_info "Tạo virtualenv & cài dependencies..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
else
  log_warn "Không thấy requirements.txt → cài tối thiểu flask gunicorn"
  pip install flask gunicorn
fi

# ===== Gunicorn config =====
log_info "Tạo gunicorn_config.py..."
cat > gunicorn_config.py <<EOF
bind = "0.0.0.0:${APP_PORT}"
workers = 2
worker_class = "gthread"
threads = 8
timeout = 120
graceful_timeout = 20
max_requests = 1000
preload_app = True
user = "${USER}"
EOF

# ===== systemd service =====
log_info "Tạo systemd service ${SERVICE_NAME}.service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Flask API via Gunicorn (host)
After=network.target

[Service]
User=${USER}
Group=${USER}
WorkingDirectory=${PROJECT_PATH}
Environment="PATH=${PROJECT_PATH}/venv/bin"
ExecStart=${PROJECT_PATH}/venv/bin/gunicorn --config ${PROJECT_PATH}/gunicorn_config.py app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}

sleep 2
if sudo systemctl is-active --quiet ${SERVICE_NAME}; then
  log_info "✅ Flask service đang chạy."
else
  log_err "❌ Flask service không chạy. Xem log: sudo journalctl -u ${SERVICE_NAME} -f"
  exit 1
fi

# ===== Test local health =====
log_info "Kiểm tra endpoint nội bộ..."
if curl -sS --max-time 5 "http://127.0.0.1:${APP_PORT}/health" | grep -qi "ok"; then
  log_info "✅ Endpoint nội bộ OK."
else
  log_warn "⚠️ Không thấy phản hồi /health. Vẫn tiếp tục."
fi

# ===== Caddyfile update =====
if [ ! -f "$CADDYFILE" ]; then
  log_err "Không tìm thấy Caddyfile tại: $CADDYFILE"
  echo "Hãy cung cấp đúng đường dẫn file đang được mount vào container Caddy."
  exit 1
fi

log_info "Backup Caddyfile..."
cp -a "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d%H%M%S)"

log_info "Thêm site block cho ${DOMAIN} vào Caddyfile (nếu chưa có)..."
if grep -qE "^[[:space:]]*${DOMAIN}[[:space:]]*{" "$CADDYFILE"; then
  log_warn "Đã tồn tại block cho domain này. Không chèn thêm."
else
  cat >> "$CADDYFILE" <<'EOF'

# === Auto-added by deploy script ===
EOF
  cat >> "$CADDYFILE" <<EOF
${DOMAIN} {
    encode zstd gzip
    reverse_proxy host.docker.internal:${APP_PORT}
    # Optional security headers
    header {
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}
EOF
  log_info "Đã append block cho ${DOMAIN}."
fi

# ===== Ensure extra_hosts for Caddy =====
COMPOSE_FILE="$(dirname $CADDYFILE)/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
  if ! grep -q "host.docker.internal:host-gateway" "$COMPOSE_FILE"; then
    log_info "Thêm extra_hosts cho Caddy trong docker-compose.yml..."
    sed -i '/caddy:/a\    extra_hosts:\n      - "host.docker.internal:host-gateway"' "$COMPOSE_FILE"
  fi
fi

# ===== Restart/Reload Caddy in Docker =====
if [[ "$RESTART_CADDY" =~ ^[Yy]$ ]]; then
  log_info "Thử restart Caddy container..."
  if docker ps --format '{{.Names}}' | grep -q '^caddy$'; then
    docker restart caddy || true
  else
    CADDY_DIR=$(dirname "$CADDYFILE")
    if [ -f "${CADDY_DIR}/docker-compose.yml" ] || [ -f "${CADDY_DIR}/docker-compose.yaml" ]; then
      ( cd "$CADDY_DIR" && docker compose restart caddy ) || true
    else
      if docker ps --format '{{.Names}}' | grep -q 'caddy'; then
        docker exec caddy caddy validate --config /etc/caddy/Caddyfile || true
        docker restart caddy || true
      else
        log_warn "Không xác định được container Caddy. Hãy tự restart caddy bằng docker compose."
      fi
    fi
  fi
else
  log_warn "Bỏ qua restart Caddy theo yêu cầu."
fi

echo\ nlog_info "Hoàn tất!"
echo "  📁 Project:     ${PROJECT_PATH}"
echo "  🌐 Domain:      https://${DOMAIN}"
echo "  🔌 App (local): http://127.0.0.1:${APP_PORT}/"
echo "  🔧 Service:     ${SERVICE_NAME}"
echo
echo "Lệnh hữu ích:"
echo "  • Xem log service:  sudo journalctl -u ${SERVICE_NAME} -f"
echo "  • Restart service:  sudo systemctl restart ${SERVICE_NAME}"
echo "  • Kiểm tra UFW:     sudo ufw status"
echo "  • Nếu cần, restart Caddy:  docker restart caddy  (hoặc: docker compose restart caddy)"
echo
log_info "Hãy đảm bảo DNS của ${DOMAIN} trỏ về IP VPS. Caddy trong Docker sẽ tự xin/renew SSL."
