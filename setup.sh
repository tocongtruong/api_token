#!/bin/bash

# Flask App Deployment Script for Ubuntu VPS
# Author: Auto-generated deployment script
# Description: Deploy Flask API Token app to Ubuntu VPS

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root for security reasons"
   exit 1
fi

print_status "=== Flask App Deployment Script ==="
echo

# Get project directory name
echo -n "Nhập tên thư mục project (nhấn Enter để dùng mặc định 'api_token'): "
read PROJECT_DIR
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="api_token"
fi

# Get domain name
echo -n "Nhập domain name (ví dụ: example.com hoặc IP): "
read DOMAIN
if [ -z "$DOMAIN" ]; then
    print_error "Domain name không được để trống!"
    exit 1
fi

# Set project path
PROJECT_PATH="/home/$(whoami)/$PROJECT_DIR"

print_status "Thư mục project: $PROJECT_PATH"
print_status "Domain: $DOMAIN"
echo

# Update system packages
print_status "Cập nhật system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
print_status "Cài đặt các packages cần thiết..."
sudo apt install -y python3 python3-pip python3-venv git nginx supervisor ufw

# Create project directory
print_status "Tạo thư mục project..."
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"

# Clone or update repository
if [ -d ".git" ]; then
    print_status "Cập nhật code từ repository..."
    git pull origin main
else
    print_status "Clone repository..."
    git clone https://github.com/tocongtruong/api_token.git .
fi

# Create virtual environment
print_status "Tạo Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
print_status "Cài đặt Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create systemd service file
print_status "Tạo systemd service..."
sudo tee /etc/systemd/system/${PROJECT_DIR}.service > /dev/null <<EOF
[Unit]
Description=Flask API Token App
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$PROJECT_PATH
Environment=PATH=$PROJECT_PATH/venv/bin
ExecStart=$PROJECT_PATH/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:7123 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Create Nginx configuration
print_status "Cấu hình Nginx..."
sudo tee /etc/nginx/sites-available/${PROJECT_DIR} > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:7123;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss;
}
EOF

# Enable Nginx site
sudo ln -sf /etc/nginx/sites-available/${PROJECT_DIR} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
print_status "Kiểm tra cấu hình Nginx..."
sudo nginx -t

# Configure firewall
print_status "Cấu hình firewall..."
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443

# Start and enable services
print_status "Khởi động các services..."
sudo systemctl daemon-reload
sudo systemctl enable ${PROJECT_DIR}
sudo systemctl start ${PROJECT_DIR}
sudo systemctl enable nginx
sudo systemctl restart nginx

# Check service status
print_status "Kiểm tra trạng thái services..."
sleep 3

if sudo systemctl is-active --quiet ${PROJECT_DIR}; then
    print_success "Flask app service đang chạy"
else
    print_error "Flask app service không chạy được"
    print_status "Checking logs..."
    sudo journalctl -u ${PROJECT_DIR} --no-pager -l
    exit 1
fi

if sudo systemctl is-active --quiet nginx; then
    print_success "Nginx service đang chạy"
else
    print_error "Nginx service không chạy được"
    exit 1
fi

# Create log rotation
print_status "Cấu hình log rotation..."
sudo tee /etc/logrotate.d/${PROJECT_DIR} > /dev/null <<EOF
/var/log/${PROJECT_DIR}/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 $(whoami) $(whoami)
    postrotate
        systemctl reload ${PROJECT_DIR}
    endscript
}
EOF

# Create update script
print_status "Tạo script cập nhật..."
tee "$PROJECT_PATH/update.sh" > /dev/null <<EOF
#!/bin/bash
cd $PROJECT_PATH
git pull origin main
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart ${PROJECT_DIR}
echo "App đã được cập nhật!"
EOF

chmod +x "$PROJECT_PATH/update.sh"

# Create management scripts
tee "$PROJECT_PATH/manage.sh" > /dev/null <<EOF
#!/bin/bash

case \$1 in
    start)
        sudo systemctl start ${PROJECT_DIR}
        echo "App đã được khởi động"
        ;;
    stop)
        sudo systemctl stop ${PROJECT_DIR}
        echo "App đã được dừng"
        ;;
    restart)
        sudo systemctl restart ${PROJECT_DIR}
        echo "App đã được khởi động lại"
        ;;
    status)
        sudo systemctl status ${PROJECT_DIR}
        ;;
    logs)
        sudo journalctl -u ${PROJECT_DIR} -f
        ;;
    update)
        ./update.sh
        ;;
    *)
        echo "Sử dụng: \$0 {start|stop|restart|status|logs|update}"
        exit 1
        ;;
esac
EOF

chmod +x "$PROJECT_PATH/manage.sh"

# Final status check
print_status "Kiểm tra kết nối cuối cùng..."
sleep 2

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:7123/ || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    print_success "App đang chạy thành công trên localhost:7123"
else
    print_warning "App có thể chưa sẵn sàng (HTTP Status: $HTTP_STATUS)"
fi

echo
print_success "=== DEPLOYMENT HOÀN THÀNH ==="
echo
print_status "Thông tin deployment:"
echo -e "  • Project directory: ${BLUE}$PROJECT_PATH${NC}"
echo -e "  • Domain: ${BLUE}http://$DOMAIN${NC}"
echo -e "  • Local URL: ${BLUE}http://localhost:7123${NC}"
echo -e "  • Service name: ${BLUE}${PROJECT_DIR}${NC}"
echo
print_status "API Endpoints:"
echo -e "  • Home: ${BLUE}http://$DOMAIN/${NC}"
echo -e "  • Get Token: ${BLUE}http://$DOMAIN/get-token?cookie=YOUR_COOKIE${NC}"
echo
print_status "Quản lý app:"
echo -e "  • Xem status: ${YELLOW}cd $PROJECT_PATH && ./manage.sh status${NC}"
echo -e "  • Xem logs: ${YELLOW}cd $PROJECT_PATH && ./manage.sh logs${NC}"
echo -e "  • Restart app: ${YELLOW}cd $PROJECT_PATH && ./manage.sh restart${NC}"
echo -e "  • Update app: ${YELLOW}cd $PROJECT_PATH && ./manage.sh update${NC}"
echo
print_status "Cấu hình SSL (khuyến nghị):"
echo -e "  • Cài đặt Certbot: ${YELLOW}sudo apt install certbot python3-certbot-nginx${NC}"
echo -e "  • Tạo SSL cert: ${YELLOW}sudo certbot --nginx -d $DOMAIN${NC}"
echo
echo
print_success "Deployment thành công! App của bạn đã sẵn sàng sử dụng."
