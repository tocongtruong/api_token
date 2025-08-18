#!/bin/bash

# One Command Flask App Deployment Script
# Usage: curl -s https://raw.githubusercontent.com/tocongtruong/api_token/main/deploy.sh | sudo bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1 ${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Vui lòng chạy script này với quyền root (sudo)"
        exit 1
    fi
}

# Function to get input with timeout (for piped execution)
get_input() {
    local prompt="$1"
    local default="$2"
    local timeout="$3"
    
    if [ -t 0 ]; then
        # Interactive mode
        read -p "$prompt" input
    else
        # Non-interactive mode, use timeout
        read -t ${timeout:-10} -p "$prompt" input 2>/dev/null || true
    fi
    
    echo "${input:-$default}"
}

# Get user inputs with defaults for non-interactive mode
get_user_inputs() {
    print_header "THÔNG TIN CẤU HÌNH"
    
    # Check if running interactively
    if [ ! -t 0 ]; then
        print_warning "Chạy ở chế độ non-interactive, sử dụng cấu hình mặc định..."
        
        # Default configuration for non-interactive mode
        APP_NAME="flask-api"
        DOMAIN_NAME="your-domain.com"
        EMAIL="admin@your-domain.com"
        FLASK_PORT="5000"
        SERVICE_USER="flask-user"
        WORKERS="3"
        
        print_message "Sử dụng cấu hình mặc định:"
        echo "  - App Name: $APP_NAME"
        echo "  - Domain: $DOMAIN_NAME (BẠN CẦN SỬA SAU)"
        echo "  - Email: $EMAIL (BẠN CẦN SỬA SAU)"
        echo "  - Flask Port: $FLASK_PORT"
        echo "  - Service User: $SERVICE_USER"
        echo "  - Workers: $WORKERS"
        
        sleep 3
        return
    fi
    
    # Interactive mode
    APP_NAME=$(get_input "Nhập tên app (mặc định flask-api): " "flask-api" 10)
    APP_DIR="/home/$APP_NAME"
    
    DOMAIN_NAME=$(get_input "Nhập domain (mặc định your-domain.com): " "your-domain.com" 10)
    EMAIL=$(get_input "Nhập email (mặc định admin@$DOMAIN_NAME): " "admin@$DOMAIN_NAME" 10)
    FLASK_PORT=$(get_input "Port Flask (mặc định 5000): " "5000" 10)
    SERVICE_USER=$(get_input "Service user (mặc định flask-user): " "flask-user" 10)
    WORKERS=$(get_input "Số workers (mặc định 3): " "3" 10)
    
    print_message "Cấu hình:"
    echo "  - App: $APP_NAME tại $APP_DIR"
    echo "  - Domain: $DOMAIN_NAME"
    echo "  - Email: $EMAIL"
    echo "  - Port: $FLASK_PORT"
    echo "  - User: $SERVICE_USER"
    echo "  - Workers: $WORKERS"
}

# Update system
update_system() {
    print_header "CẬP NHẬT HỆ THỐNG"
    export DEBIAN_FRONTEND=noninteractive
    apt update -y
    apt upgrade -y
    print_message "Hệ thống đã được cập nhật"
}

# Install required packages
install_packages() {
    print_header "CÀI ĐẶT PACKAGES"
    export DEBIAN_FRONTEND=noninteractive
    apt install -y python3 python3-pip python3-venv nginx git certbot python3-certbot-nginx ufw curl wget unzip software-properties-common
    
    # Install latest Python if needed
    if ! python3 --version | grep -q "3\.[8-9]\|3\.1[0-9]"; then
        add-apt-repository ppa:deadsnakes/ppa -y
        apt update -y
        apt install -y python3.9 python3.9-venv python3.9-dev
    fi
    
    print_message "Đã cài đặt packages"
}

# Create user if not exists
create_user() {
    print_header "TẠO USER"
    if id "$SERVICE_USER" &>/dev/null; then
        print_warning "User $SERVICE_USER đã tồn tại"
    else
        useradd -m -s /bin/bash "$SERVICE_USER" || true
        usermod -aG www-data "$SERVICE_USER" || true
        print_message "Đã tạo user $SERVICE_USER"
    fi
}

# Setup app directory
setup_app_directory() {
    print_header "THIẾT LẬP APP"
    
    APP_DIR="/home/$APP_NAME"
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Clone repository
    if [ -d ".git" ]; then
        print_message "Repository đã tồn tại, đang pull..."
        git pull origin main || git pull origin master || true
    else
        print_message "Đang clone repository..."
        git clone https://github.com/tocongtruong/api_token.git . || {
            print_error "Không thể clone repository"
            exit 1
        }
    fi
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"
    print_message "Đã setup app directory"
}

# Setup Python environment
setup_python_env() {
    print_header "THIẾT LẬP PYTHON ENV"
    
    cd "$APP_DIR"
    
    # Create virtual environment
    sudo -u "$SERVICE_USER" python3 -m venv venv
    
    # Upgrade pip and install packages
    sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install --upgrade pip
    sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install gunicorn
    
    # Install requirements if exists
    if [ -f "requirements.txt" ]; then
        sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install -r requirements.txt
        print_message "Đã cài requirements.txt"
    else
        print_warning "Không tìm thấy requirements.txt, cài packages cơ bản..."
        sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install flask requests
    fi
    
    print_message "Đã setup Python environment"
}

# Create Gunicorn config
create_gunicorn_config() {
    print_header "TẠO GUNICORN CONFIG"
    
    # Create log directories
    mkdir -p /var/log/gunicorn
    mkdir -p /var/run/gunicorn
    chown -R "$SERVICE_USER:$SERVICE_USER" /var/log/gunicorn
    chown -R "$SERVICE_USER:$SERVICE_USER" /var/run/gunicorn
    
    cat > "$APP_DIR/gunicorn.conf.py" << EOF
import multiprocessing

bind = "127.0.0.1:$FLASK_PORT"
workers = $WORKERS
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 30
keepalive = 2
preload_app = True
daemon = False
user = "$SERVICE_USER"
group = "$SERVICE_USER"
pidfile = "/var/run/gunicorn/$APP_NAME.pid"
errorlog = "/var/log/gunicorn/$APP_NAME.error.log"
accesslog = "/var/log/gunicorn/$APP_NAME.access.log"
loglevel = "info"
EOF
    
    chown "$SERVICE_USER:$SERVICE_USER" "$APP_DIR/gunicorn.conf.py"
    print_message "Đã tạo Gunicorn config"
}

# Create systemd service
create_systemd_service() {
    print_header "TẠO SYSTEMD SERVICE"
    
    cat > "/etc/systemd/system/$APP_NAME.service" << EOF
[Unit]
Description=$APP_NAME Flask Application
After=network.target

[Service]
Type=notify
User=$SERVICE_USER
Group=$SERVICE_USER
RuntimeDirectory=gunicorn
WorkingDirectory=$APP_DIR
Environment=PATH=$APP_DIR/venv/bin
ExecStart=$APP_DIR/venv/bin/gunicorn --config gunicorn.conf.py app:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$APP_NAME.service"
    print_message "Đã tạo systemd service"
}

# Configure Nginx
configure_nginx() {
    print_header "CẤU HÌNH NGINX"
    
    # Backup original config
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup 2>/dev/null || true
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Create Nginx configuration
    cat > "/etc/nginx/sites-available/$APP_NAME" << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    # SSL configuration (will be updated by certbot)
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    location / {
        proxy_pass http://127.0.0.1:$FLASK_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    location /static {
        alias $APP_DIR/static;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Enable site
    ln -sf "/etc/nginx/sites-available/$APP_NAME" "/etc/nginx/sites-enabled/"
    
    # Test configuration
    nginx -t || {
        print_error "Nginx configuration error"
        cat "/etc/nginx/sites-available/$APP_NAME"
        exit 1
    }
    
    print_message "Đã cấu hình Nginx"
}

# Setup basic SSL (will be replaced by Let's Encrypt later)
setup_basic_ssl() {
    print_header "THIẾT LẬP SSL CƠ BẢN"
    
    # Create self-signed certificate for initial setup
    if [ ! -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
        make-ssl-cert generate-default-snakeoil --force-overwrite
    fi
    
    print_message "Đã tạo SSL certificate tạm thời"
}

# Setup Let's Encrypt SSL
setup_letsencrypt() {
    print_header "THIẾT LẬP LET'S ENCRYPT SSL"
    
    # Start services first
    systemctl start "$APP_NAME.service"
    systemctl restart nginx
    
    # Wait a bit for services to start
    sleep 5
    
    # Get SSL certificate
    if [[ "$DOMAIN_NAME" != "your-domain.com" && "$DOMAIN_NAME" != "localhost" ]]; then
        certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME" \
            --email "$EMAIL" \
            --agree-tos \
            --non-interactive \
            --redirect || {
            print_warning "SSL certificate setup failed. Continuing with self-signed certificate."
        }
        
        # Setup auto-renewal
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    else
        print_warning "Domain mặc định được sử dụng. Vui lòng cập nhật domain thực và chạy lại SSL setup."
    fi
    
    print_message "Đã thiết lập SSL"
}

# Configure firewall
setup_firewall() {
    print_header "CẤU HÌNH FIREWALL"
    
    # Enable UFW if not enabled
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow essential services
    ufw allow ssh
    ufw allow 'Nginx Full'
    
    # Enable firewall
    ufw --force enable
    
    print_message "Đã cấu hình firewall"
}

# Create management scripts
create_management_scripts() {
    print_header "TẠO MANAGEMENT SCRIPTS"
    
    # Create scripts directory
    mkdir -p /usr/local/bin
    
    # Status script
    cat > "/usr/local/bin/${APP_NAME}-status" << EOF
#!/bin/bash
echo "=== $APP_NAME Service Status ==="
systemctl status $APP_NAME.service
echo ""
echo "=== Nginx Status ==="
systemctl status nginx
echo ""
echo "=== Listening Ports ==="
ss -tlnp | grep :$FLASK_PORT
ss -tlnp | grep :80
ss -tlnp | grep :443
EOF
    
    # Restart script
    cat > "/usr/local/bin/${APP_NAME}-restart" << EOF
#!/bin/bash
echo "Restarting $APP_NAME..."
systemctl restart $APP_NAME.service
systemctl restart nginx
echo "Done!"
${APP_NAME}-status
EOF
    
    # Update script
    cat > "/usr/local/bin/${APP_NAME}-update" << EOF
#!/bin/bash
echo "Updating $APP_NAME..."
cd $APP_DIR
systemctl stop $APP_NAME.service
sudo -u $SERVICE_USER git pull origin main
sudo -u $SERVICE_USER $APP_DIR/venv/bin/pip install -r requirements.txt
systemctl start $APP_NAME.service
systemctl restart nginx
echo "Update completed!"
${APP_NAME}-status
EOF
    
    # Logs script
    cat > "/usr/local/bin/${APP_NAME}-logs" << EOF
#!/bin/bash
echo "=== Application Logs ==="
journalctl -u $APP_NAME.service -f --no-pager
EOF
    
    # SSL renewal script
    cat > "/usr/local/bin/${APP_NAME}-ssl-renew" << EOF
#!/bin/bash
echo "Renewing SSL certificate..."
certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME --email $EMAIL --agree-tos --non-interactive --redirect
systemctl restart nginx
echo "SSL renewal completed!"
EOF
    
    # Make all scripts executable
    chmod +x /usr/local/bin/${APP_NAME}-*
    
    print_message "Đã tạo management scripts"
}

# Final setup
final_setup() {
    print_header "HOÀN THIỆN SETUP"
    
    # Start services
    systemctl daemon-reload
    systemctl restart "$APP_NAME.service"
    systemctl restart nginx
    
    # Wait for services to start
    sleep 3
    
    # Check service status
    if systemctl is-active --quiet "$APP_NAME.service"; then
        print_message "✅ $APP_NAME service đang chạy"
    else
        print_error "❌ $APP_NAME service lỗi"
        journalctl -u "$APP_NAME.service" --no-pager -n 10
    fi
    
    if systemctl is-active --quiet nginx; then
        print_message "✅ Nginx đang chạy"
    else
        print_error "❌ Nginx lỗi"
    fi
    
    # Test app
    if curl -s http://localhost:$FLASK_PORT > /dev/null; then
        print_message "✅ Flask app phản hồi"
    else
        print_warning "⚠️ Flask app không phản hồi, kiểm tra logs"
    fi
    
    print_message "Setup hoàn tất!"
}

# Show final information
show_final_info() {
    print_header "THÔNG TIN TRIỂN KHAI"
    
    echo -e "${GREEN}🎉 Flask App đã được deploy thành công!${NC}"
    echo ""
    echo -e "${BLUE}📋 Thông tin cấu hình:${NC}"
    echo "  📁 App Directory: $APP_DIR"
    echo "  🌐 Domain: https://$DOMAIN_NAME"
    echo "  👤 Service User: $SERVICE_USER"
    echo "  🔧 Service Name: $APP_NAME.service"
    echo "  📡 Port: $FLASK_PORT"
    echo ""
    echo -e "${BLUE}🛠️ Management Commands:${NC}"
    echo "  ${APP_NAME}-status     - Kiểm tra trạng thái"
    echo "  ${APP_NAME}-restart    - Khởi động lại"
    echo "  ${APP_NAME}-update     - Cập nhật từ git"
    echo "  ${APP_NAME}-logs       - Xem logs"
    echo "  ${APP_NAME}-ssl-renew  - Gia hạn SSL"
    echo ""
    echo -e "${BLUE}📊 Systemctl Commands:${NC}"
    echo "  systemctl status $APP_NAME.service"
    echo "  systemctl restart $APP_NAME.service"
    echo "  journalctl -u $APP_NAME.service -f"
    echo ""
    echo -e "${BLUE}📝 Log Files:${NC}"
    echo "  App: journalctl -u $APP_NAME.service"
    echo "  Nginx: /var/log/nginx/"
    echo "  Gunicorn: /var/log/gunicorn/"
    echo ""
    echo -e "${YELLOW}⚠️ Lưu ý quan trọng:${NC}"
    if [[ "$DOMAIN_NAME" == "your-domain.com" ]]; then
        echo "  🔴 DOMAIN: Cần thay đổi domain trong cấu hình Nginx"
        echo "     Sửa file: /etc/nginx/sites-available/$APP_NAME"
        echo "     Sau đó chạy: ${APP_NAME}-ssl-renew"
    fi
    if [[ "$EMAIL" == "admin@your-domain.com" ]]; then
        echo "  🔴 EMAIL: Cần cập nhật email cho SSL certificate"
    fi
    echo "  ✅ App tự động khởi động khi reboot"
    echo "  ✅ SSL certificate tự động gia hạn (nếu domain hợp lệ)"
    echo "  ✅ Firewall đã được cấu hình"
    echo ""
    echo -e "${GREEN}🚀 Truy cập app:${NC}"
    echo "  HTTP:  http://$DOMAIN_NAME"
    echo "  HTTPS: https://$DOMAIN_NAME"
    echo "  Local: http://localhost:$FLASK_PORT"
    echo ""
    echo -e "${GREEN}✨ Deploy hoàn tất! Happy coding! ✨${NC}"
}

# Main execution
main() {
    print_header "FLASK APP ONE-COMMAND DEPLOY"
    
    check_root
    get_user_inputs
    update_system
    install_packages
    create_user
    setup_app_directory
    setup_python_env
    create_gunicorn_config
    create_systemd_service
    configure_nginx
    setup_basic_ssl
    setup_firewall
    create_management_scripts
    final_setup
    setup_letsencrypt  # SSL setup after services are running
    show_final_info
}

# Trap errors
trap 'print_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
