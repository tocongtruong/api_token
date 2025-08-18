#!/bin/bash

# Flask App Deployment Script
# Tác giả: Auto Deploy Script
# Mô tả: Script tự động deploy Flask app với SSL, Nginx, Gunicorn và systemd service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Get user inputs
get_user_inputs() {
    print_header "THÔNG TIN CẤU HÌNH"
    
    # App directory name
    read -p "Nhập tên thư mục app (sẽ tạo tại /home/): " APP_NAME
    APP_DIR="/home/$APP_NAME"
    
    # Domain name
    read -p "Nhập domain name (ví dụ: example.com): " DOMAIN_NAME
    
    # Email for Let's Encrypt
    read -p "Nhập email cho Let's Encrypt SSL: " EMAIL
    
    # Port for Flask app
    read -p "Nhập port cho Flask app (mặc định 5000): " FLASK_PORT
    FLASK_PORT=${FLASK_PORT:-5000}
    
    # Username for service
    read -p "Nhập username để chạy service (mặc định: $APP_NAME): " SERVICE_USER
    SERVICE_USER=${SERVICE_USER:-$APP_NAME}
    
    # Number of Gunicorn workers
    read -p "Số lượng Gunicorn workers (mặc định 3): " WORKERS
    WORKERS=${WORKERS:-3}
    
    print_message "Thông tin cấu hình:"
    echo "  - App Directory: $APP_DIR"
    echo "  - Domain: $DOMAIN_NAME"
    echo "  - Email: $EMAIL"
    echo "  - Flask Port: $FLASK_PORT"
    echo "  - Service User: $SERVICE_USER"
    echo "  - Workers: $WORKERS"
    
    read -p "Tiếp tục? (y/n): " confirm
    if [[ $confirm != [yY] ]]; then
        print_error "Đã hủy bỏ."
        exit 1
    fi
}

# Update system
update_system() {
    print_header "CẬP NHẬT HỆ THỐNG"
    apt update && apt upgrade -y
    print_message "Hệ thống đã được cập nhật"
}

# Install required packages
install_packages() {
    print_header "CÀI ĐẶT PACKAGES"
    apt install -y python3 python3-pip python3-venv nginx git certbot python3-certbot-nginx ufw supervisor htop curl wget unzip
    print_message "Đã cài đặt tất cả packages cần thiết"
}

# Create user if not exists
create_user() {
    print_header "TẠO USER"
    if id "$SERVICE_USER" &>/dev/null; then
        print_warning "User $SERVICE_USER đã tồn tại"
    else
        useradd -m -s /bin/bash "$SERVICE_USER"
        usermod -aG www-data "$SERVICE_USER"
        print_message "Đã tạo user $SERVICE_USER"
    fi
}

# Create app directory and setup
setup_app_directory() {
    print_header "THIẾT LẬP THỦ MỤC APP"
    
    # Create directory
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Clone repository
    print_message "Đang clone repository..."
    git clone https://github.com/tocongtruong/api_token.git .
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"
    
    print_message "Đã setup thư mục app tại $APP_DIR"
}

# Setup Python virtual environment
setup_python_env() {
    print_header "THIẾT LẬP PYTHON ENVIRONMENT"
    
    cd "$APP_DIR"
    
    # Create virtual environment
    sudo -u "$SERVICE_USER" python3 -m venv venv
    
    # Install requirements
    sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install --upgrade pip
    sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install gunicorn
    
    if [ -f "requirements.txt" ]; then
        sudo -u "$SERVICE_USER" "$APP_DIR/venv/bin/pip" install -r requirements.txt
        print_message "Đã cài đặt requirements từ requirements.txt"
    else
        print_warning "Không tìm thấy requirements.txt"
    fi
    
    print_message "Đã thiết lập Python environment"
}

# Create Gunicorn configuration
create_gunicorn_config() {
    print_header "TẠO GUNICORN CONFIG"
    
    cat > "$APP_DIR/gunicorn.conf.py" << EOF
# Gunicorn configuration file
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
access_log = "/var/log/gunicorn/$APP_NAME.access.log"
error_log = "/var/log/gunicorn/$APP_NAME.error.log"
log_level = "info"
EOF
    
    # Create log directories
    mkdir -p /var/log/gunicorn
    mkdir -p /var/run/gunicorn
    chown -R "$SERVICE_USER:$SERVICE_USER" /var/log/gunicorn
    chown -R "$SERVICE_USER:$SERVICE_USER" /var/run/gunicorn
    
    chown "$SERVICE_USER:$SERVICE_USER" "$APP_DIR/gunicorn.conf.py"
    print_message "Đã tạo Gunicorn configuration"
}

# Create systemd service
create_systemd_service() {
    print_header "TẠO SYSTEMD SERVICE"
    
    cat > "/etc/systemd/system/$APP_NAME.service" << EOF
[Unit]
Description=$APP_NAME Flask App
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
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$APP_NAME.service"
    
    print_message "Đã tạo systemd service"
}

# Configure Nginx
configure_nginx() {
    print_header "CẤU HÌNH NGINX"
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Create Nginx configuration
    cat > "/etc/nginx/sites-available/$APP_NAME" << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    
    # SSL configuration will be added by certbot
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    
    location / {
        limit_req zone=api burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:$FLASK_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
    
    # Static files (if any)
    location /static {
        alias $APP_DIR/static;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Enable site
    ln -sf "/etc/nginx/sites-available/$APP_NAME" "/etc/nginx/sites-enabled/"
    
    # Test Nginx configuration
    nginx -t
    
    print_message "Đã cấu hình Nginx"
}

# Setup SSL with Let's Encrypt
setup_ssl() {
    print_header "THIẾT LẬP SSL"
    
    # Start services
    systemctl restart nginx
    systemctl start "$APP_NAME.service"
    
    # Get SSL certificate
    certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME" --email "$EMAIL" --agree-tos --non-interactive --redirect
    
    # Setup auto-renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    print_message "Đã thiết lập SSL certificate"
}

# Configure firewall
setup_firewall() {
    print_header "CẤU HÌNH FIREWALL"
    
    # Reset firewall
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (be careful!)
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 'Nginx Full'
    
    # Enable firewall
    ufw --force enable
    
    print_message "Đã cấu hình firewall"
}

# Create monitoring script
create_monitoring() {
    print_header "TẠO SCRIPT MONITORING"
    
    cat > "/usr/local/bin/monitor_$APP_NAME.sh" << EOF
#!/bin/bash

APP_NAME="$APP_NAME"
APP_URL="https://$DOMAIN_NAME/health"
LOG_FILE="/var/log/\$APP_NAME-monitor.log"

# Check if service is running
if ! systemctl is-active --quiet "\$APP_NAME.service"; then
    echo "\$(date): Service \$APP_NAME is not running. Attempting to restart..." >> "\$LOG_FILE"
    systemctl restart "\$APP_NAME.service"
    sleep 5
fi

# Check if app responds
if ! curl -f -s "\$APP_URL" > /dev/null; then
    echo "\$(date): App is not responding. Restarting service..." >> "\$LOG_FILE"
    systemctl restart "\$APP_NAME.service"
    systemctl restart nginx
fi
EOF
    
    chmod +x "/usr/local/bin/monitor_$APP_NAME.sh"
    
    # Add to crontab for monitoring every 5 minutes
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/monitor_$APP_NAME.sh") | crontab -
    
    print_message "Đã tạo script monitoring"
}

# Create management scripts
create_management_scripts() {
    print_header "TẠO MANAGEMENT SCRIPTS"
    
    # Start script
    cat > "/usr/local/bin/start_$APP_NAME.sh" << EOF
#!/bin/bash
systemctl start $APP_NAME.service
systemctl start nginx
systemctl status $APP_NAME.service
EOF
    
    # Stop script
    cat > "/usr/local/bin/stop_$APP_NAME.sh" << EOF
#!/bin/bash
systemctl stop $APP_NAME.service
systemctl status $APP_NAME.service
EOF
    
    # Restart script
    cat > "/usr/local/bin/restart_$APP_NAME.sh" << EOF
#!/bin/bash
systemctl restart $APP_NAME.service
systemctl restart nginx
systemctl status $APP_NAME.service
EOF
    
    # Update script
    cat > "/usr/local/bin/update_$APP_NAME.sh" << EOF
#!/bin/bash
cd $APP_DIR
systemctl stop $APP_NAME.service
sudo -u $SERVICE_USER git pull origin main
sudo -u $SERVICE_USER $APP_DIR/venv/bin/pip install -r requirements.txt
systemctl start $APP_NAME.service
systemctl status $APP_NAME.service
EOF
    
    # Logs script
    cat > "/usr/local/bin/logs_$APP_NAME.sh" << EOF
#!/bin/bash
echo "=== Application Logs ==="
journalctl -u $APP_NAME.service -f --no-pager
EOF
    
    # Make executable
    chmod +x "/usr/local/bin/start_$APP_NAME.sh"
    chmod +x "/usr/local/bin/stop_$APP_NAME.sh"
    chmod +x "/usr/local/bin/restart_$APP_NAME.sh"
    chmod +x "/usr/local/bin/update_$APP_NAME.sh"
    chmod +x "/usr/local/bin/logs_$APP_NAME.sh"
    
    print_message "Đã tạo management scripts"
}

# Final setup and start services
final_setup() {
    print_header "HOÀN THIỆN SETUP"
    
    # Restart services
    systemctl restart "$APP_NAME.service"
    systemctl restart nginx
    
    # Check status
    sleep 3
    
    if systemctl is-active --quiet "$APP_NAME.service"; then
        print_message "✅ Flask app service đang chạy"
    else
        print_error "❌ Flask app service không chạy được"
        journalctl -u "$APP_NAME.service" --no-pager -n 10
    fi
    
    if systemctl is-active --quiet nginx; then
        print_message "✅ Nginx đang chạy"
    else
        print_error "❌ Nginx không chạy được"
    fi
    
    print_message "✅ Setup hoàn tất!"
}

# Display final information
show_final_info() {
    print_header "THÔNG TIN QUAN TRỌNG"
    
    echo -e "${GREEN}🎉 Flask app đã được deploy thành công!${NC}"
    echo ""
    echo "📁 App Directory: $APP_DIR"
    echo "🌐 Domain: https://$DOMAIN_NAME"
    echo "👤 Service User: $SERVICE_USER"
    echo "🔧 Service Name: $APP_NAME.service"
    echo ""
    echo -e "${BLUE}Management Commands:${NC}"
    echo "  • start_$APP_NAME.sh     - Khởi động app"
    echo "  • stop_$APP_NAME.sh      - Dừng app"
    echo "  • restart_$APP_NAME.sh   - Khởi động lại app"
    echo "  • update_$APP_NAME.sh    - Cập nhật code từ git"
    echo "  • logs_$APP_NAME.sh      - Xem logs"
    echo "  • monitor_$APP_NAME.sh   - Monitoring script"
    echo ""
    echo -e "${BLUE}Systemctl Commands:${NC}"
    echo "  • systemctl status $APP_NAME.service"
    echo "  • systemctl restart $APP_NAME.service"
    echo "  • journalctl -u $APP_NAME.service -f"
    echo ""
    echo -e "${BLUE}Log Files:${NC}"
    echo "  • App logs: journalctl -u $APP_NAME.service"
    echo "  • Nginx logs: /var/log/nginx/"
    echo "  • Gunicorn logs: /var/log/gunicorn/"
    echo "  • Monitor logs: /var/log/$APP_NAME-monitor.log"
    echo ""
    echo -e "${YELLOW}⚠️  Lưu ý quan trọng:${NC}"
    echo "  • SSL certificate sẽ tự động gia hạn"
    echo "  • Monitoring script chạy mỗi 5 phút"
    echo "  • Firewall đã được cấu hình (SSH, HTTP, HTTPS)"
    echo "  • App sẽ tự động khởi động khi reboot server"
    echo ""
    echo -e "${GREEN}✅ Truy cập app tại: https://$DOMAIN_NAME${NC}"
}

# Main execution
main() {
    print_header "FLASK APP DEPLOYMENT SCRIPT"
    
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
    setup_ssl
    setup_firewall
    create_monitoring
    create_management_scripts
    final_setup
    show_final_info
}

# Run main function
main "$@"
