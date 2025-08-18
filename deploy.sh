#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

# Welcome message
echo -e "${GREEN}"
echo "================================================"
echo "    Flask API Token Deployment Script with SSL"
echo "================================================"
echo -e "${NC}"

# Get user inputs
print_info "Nhập tên thư mục (sẽ tạo tại /home/\$USER/):"
read -p "Tên thư mục: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    print_error "Tên thư mục không được để trống!"
    exit 1
fi

print_info "Nhập domain của VPS (ví dụ: api.example.com):"
print_warning "Lưu ý: Phải là domain thật đã trỏ về IP VPS để cài SSL"
read -p "Domain: " DOMAIN

if [ -z "$DOMAIN" ]; then
    print_error "Domain không được để trống!"
    exit 1
fi

print_info "Bạn có muốn cài đặt SSL với Let's Encrypt? (y/n) [y]:"
read -p "SSL: " INSTALL_SSL
INSTALL_SSL=${INSTALL_SSL:-y}

if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    print_info "Nhập email để đăng ký SSL certificate:"
    read -p "Email: " SSL_EMAIL
    
    if [ -z "$SSL_EMAIL" ]; then
        print_error "Email không được để trống khi cài SSL!"
        exit 1
    fi
fi

print_info "Nhập port để chạy ứng dụng (mặc định: 5000):"
read -p "Port [5000]: " APP_PORT
APP_PORT=${APP_PORT:-5000}

# Set variables
PROJECT_PATH="/home/$USER/$PROJECT_NAME"
GIT_REPO="https://github.com/tocongtruong/api_token.git"
SERVICE_NAME="flask-$PROJECT_NAME"

print_status "Bắt đầu quá trình deploy..."
print_status "Thư mục: $PROJECT_PATH"
print_status "Domain: $DOMAIN"
print_status "Port: $APP_PORT"
print_status "SSL: $([[ "$INSTALL_SSL" =~ ^[Yy]$ ]] && echo "Có" || echo "Không")"

# Update system
print_status "Cập nhật hệ thống..."
sudo apt update && sudo apt upgrade -y

# Install required packages
print_status "Cài đặt các gói cần thiết..."
sudo apt install -y python3 python3-pip python3-venv git nginx ufw

# Install Certbot for SSL
if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    print_status "Cài đặt Certbot cho SSL..."
    sudo apt install -y certbot python3-certbot-nginx
fi

# Configure firewall
print_status "Cấu hình firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# Create project directory
print_status "Tạo thư mục dự án..."
if [ -d "$PROJECT_PATH" ]; then
    print_warning "Thư mục đã tồn tại. Xóa và tạo mới..."
    rm -rf "$PROJECT_PATH"
fi
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"

# Clone repository
print_status "Clone repository từ GitHub..."
git clone "$GIT_REPO" .

# Create virtual environment
print_status "Tạo virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install dependencies
print_status "Cài đặt dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create gunicorn config
print_status "Tạo file cấu hình Gunicorn..."
cat > gunicorn_config.py << EOF
bind = "127.0.0.1:$APP_PORT"
workers = 2
worker_class = "sync"
timeout = 120
max_requests = 1000
preload_app = True
user = "$USER"
group = "www-data"
EOF

# Create systemd service
print_status "Tạo systemd service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Flask API Token Generator
After=network.target

[Service]
User=$USER
Group=www-data
WorkingDirectory=$PROJECT_PATH
Environment="PATH=$PROJECT_PATH/venv/bin"
ExecStart=$PROJECT_PATH/venv/bin/gunicorn --config gunicorn_config.py app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Create nginx config (HTTP first)
print_status "Tạo cấu hình Nginx..."
sudo tee /etc/nginx/sites-available/$SERVICE_NAME > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Increase timeout for long requests
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Remove default nginx site
sudo rm -f /etc/nginx/sites-enabled/default

# Enable nginx site
print_status "Kích hoạt site Nginx..."
sudo ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
sudo nginx -t

if [ $? -eq 0 ]; then
    print_status "Cấu hình Nginx hợp lệ"
else
    print_error "Cấu hình Nginx có lỗi!"
    exit 1
fi

# Set permissions
print_status "Thiết lập quyền..."
sudo chown -R $USER:www-data "$PROJECT_PATH"
sudo chmod -R 755 "$PROJECT_PATH"

# Start services
print_status "Khởi động các dịch vụ..."

# Reload systemd
sudo systemctl daemon-reload

# Enable and start flask service
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

# Restart nginx
sudo systemctl restart nginx

# Wait for services to start
sleep 5

# Check service status
print_status "Kiểm tra trạng thái dịch vụ..."

if sudo systemctl is-active --quiet $SERVICE_NAME; then
    print_status "✅ Flask service đang chạy"
else
    print_error "❌ Flask service không chạy được"
    print_error "Kiểm tra log: sudo journalctl -u $SERVICE_NAME -f"
    exit 1
fi

if sudo systemctl is-active --quiet nginx; then
    print_status "✅ Nginx đang chạy"
else
    print_error "❌ Nginx không chạy được"
    exit 1
fi

# Install SSL if requested
if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    print_status "Cài đặt SSL certificate..."
    
    # Test domain connectivity
    print_status "Kiểm tra kết nối domain..."
    if curl -s --connect-timeout 10 "http://$DOMAIN" > /dev/null; then
        print_status "Domain có thể truy cập được"
        
        # Get SSL certificate
        print_status "Đang lấy SSL certificate từ Let's Encrypt..."
        sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect
        
        if [ $? -eq 0 ]; then
            print_status "✅ SSL certificate đã được cài đặt thành công"
            
            # Setup auto-renewal
            print_status "Thiết lập auto-renewal cho SSL..."
            echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
            
            PROTOCOL="https"
        else
            print_error "❌ Không thể cài đặt SSL certificate"
            print_warning "Tiếp tục với HTTP..."
            PROTOCOL="http"
        fi
    else
        print_error "❌ Không thể kết nối đến domain $DOMAIN"
        print_warning "Vui lòng kiểm tra DNS record và thử lại sau"
        print_warning "Tiếp tục với HTTP..."
        PROTOCOL="http"
    fi
else
    PROTOCOL="http"
fi

# Test the API
print_status "Kiểm tra API..."
sleep 3
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$APP_PORT/")

if [ "$HTTP_CODE" = "200" ]; then
    print_status "✅ API đang hoạt động"
else
    print_warning "⚠️  API có thể chưa sẵn sàng (HTTP Code: $HTTP_CODE)"
fi

# Create management script
print_status "Tạo script quản lý..."
cat > "$PROJECT_PATH/manage.sh" << EOF
#!/bin/bash

case "\$1" in
    start)
        sudo systemctl start $SERVICE_NAME
        echo "Service started"
        ;;
    stop)
        sudo systemctl stop $SERVICE_NAME
        echo "Service stopped"
        ;;
    restart)
        sudo systemctl restart $SERVICE_NAME
        echo "Service restarted"
        ;;
    status)
        sudo systemctl status $SERVICE_NAME
        ;;
    logs)
        sudo journalctl -u $SERVICE_NAME -f
        ;;
    update)
        cd $PROJECT_PATH
        git pull
        source venv/bin/activate
        pip install -r requirements.txt
        sudo systemctl restart $SERVICE_NAME
        echo "Application updated and restarted"
        ;;
    ssl-renew)
        sudo certbot renew
        sudo systemctl reload nginx
        echo "SSL certificate renewed"
        ;;
    ssl-status)
        sudo certbot certificates
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|update|ssl-renew|ssl-status}"
        exit 1
        ;;
esac
EOF

chmod +x "$PROJECT_PATH/manage.sh"

# Create SSL renewal script
if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    cat > "$PROJECT_PATH/ssl-check.sh" << EOF
#!/bin/bash
# Check SSL certificate expiry and renew if needed
/usr/bin/certbot renew --quiet
if [ \$? -eq 0 ]; then
    /bin/systemctl reload nginx
fi
EOF
    chmod +x "$PROJECT_PATH/ssl-check.sh"
fi

# Final summary
echo -e "${GREEN}"
echo "================================================"
echo "           DEPLOY HOÀN THÀNH!"
echo "================================================"
echo -e "${NC}"

print_status "📁 Thư mục dự án: $PROJECT_PATH"
print_status "🌐 Domain: $DOMAIN"
print_status "🔗 URL API: $PROTOCOL://$DOMAIN"
print_status "🔗 Test endpoint: $PROTOCOL://$DOMAIN/get-token?cookie=YOUR_COOKIE"
print_status "📊 Port ứng dụng: $APP_PORT"
print_status "🔧 Service name: $SERVICE_NAME"
print_status "🔒 SSL: $([[ "$INSTALL_SSL" =~ ^[Yy]$ ]] && echo "Đã cài đặt" || echo "Chưa cài đặt")"

echo -e "\n${BLUE}Các lệnh quản lý:${NC}"
echo "• Khởi động: sudo systemctl start $SERVICE_NAME"
echo "• Dừng: sudo systemctl stop $SERVICE_NAME"
echo "• Khởi động lại: sudo systemctl restart $SERVICE_NAME"
echo "• Xem trạng thái: sudo systemctl status $SERVICE_NAME"
echo "• Xem log: sudo journalctl -u $SERVICE_NAME -f"
echo "• Script quản lý: $PROJECT_PATH/manage.sh {start|stop|restart|status|logs|update}"

if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}Lệnh SSL:${NC}"
    echo "• Gia hạn SSL: $PROJECT_PATH/manage.sh ssl-renew"
    echo "• Kiểm tra SSL: $PROJECT_PATH/manage.sh ssl-status"
    echo "• SSL auto-renewal đã được thiết lập"
fi

echo -e "\n${BLUE}Kiểm tra firewall:${NC}"
echo "• Xem trạng thái: sudo ufw status"
echo "• Ports đã mở: SSH, HTTP (80), HTTPS (443)"

echo -e "\n${YELLOW}Ghi chú:${NC}"
echo "• API endpoint: $PROTOCOL://$DOMAIN/get-token?cookie=YOUR_COOKIE"
echo "• Để cập nhật code: cd $PROJECT_PATH && ./manage.sh update"
echo "• SSL certificate sẽ tự động gia hạn mỗi ngày"
echo "• Logs nginx: sudo tail -f /var/log/nginx/error.log"

print_status "Deploy hoàn thành với SSL! 🎉🔒"
