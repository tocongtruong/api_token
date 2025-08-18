#!/bin/bash

# ==============================================================================
# SCRIPT TRIỂN KHAI ỨNG DỤNG FLASK API LÊN VPS (UBUNTU/DEBIAN)
# ==============================================================================

# Dừng ngay lập tức nếu có lệnh nào thất bại
set -e

# --- BƯỚC 0: KIỂM TRA QUYỀN ROOT ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Vui lòng chạy script này với quyền root (sử dụng sudo)."
  exit 1
fi

echo "🔧 BẮT ĐẦU TRIỂN KHAI FLASK API"
echo "--------------------------------------------------"

# --- BƯỚC 1: NHẬP CÁC THÔNG TIN CẦN THIẾT ---

# 1.1. Nhập tên thư mục
# Người dùng sẽ được yêu cầu nhập tên. Nếu họ chỉ nhấn Enter,
# biến 'sub_folder' sẽ được gán giá trị mặc định là 'api_token'.
read -p "📁 Nhập tên thư mục cho dự án (mặc định: api_token): " sub_folder
sub_folder=${sub_folder:-api_token}

# 1.2. Nhập tên miền
read -p "🌐 Nhập tên miền của bạn (ví dụ: api.domain.com): " domain
if [[ -z "$domain" ]]; then
  echo "❌ Tên miền không được để trống!"
  exit 1
fi

# 1.3. Nhập email cho SSL
read -p "✉️ Nhập email của bạn (dùng để đăng ký SSL Let's Encrypt): " email
if [[ -z "$email" ]]; then
  echo "❌ Email không được để trống!"
  exit 1
fi

echo "--------------------------------------------------"
echo "⚙️  Cấu hình sẽ được thiết lập với các thông tin sau:"
echo "    - Thư mục dự án: /var/www/$sub_folder"
echo "    - Tên miền: $domain"
echo "    - Email SSL: $email"
echo "--------------------------------------------------"
read -p "Nhấn Enter để tiếp tục, hoặc Ctrl+C để hủy bỏ..."

# --- BƯỚC 2: TẠO USER VÀ THƯ MỤC (CẢI TIẾN BẢO MẬT) ---
# Không bao giờ chạy ứng dụng web với quyền root.
# Chúng ta sẽ tạo một user riêng cho ứng dụng.
APP_USER="flaskapi"
if ! id -u "$APP_USER" >/dev/null 2>&1; then
    echo "👤 Tạo user mới '$APP_USER' để chạy ứng dụng..."
    useradd -r -m -s /bin/false "$APP_USER"
else
    echo "👤 User '$APP_USER' đã tồn tại, bỏ qua bước tạo user."
fi

folder_path="/var/www/$sub_folder"
echo "📁 Tạo thư mục dự án: $folder_path"
mkdir -p "$folder_path"
chown -R $APP_USER:$APP_USER "$folder_path" # Gán quyền cho user mới

# --- BƯỚC 3: CÀI ĐẶT CÁC GÓI CẦN THIẾT ---
echo "📦 Cài đặt các gói hệ thống (nginx, python, certbot...)"
apt-get update
apt-get install -y git curl python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

# --- BƯỚC 4: TẢI SOURCE CODE VÀ CÀI ĐẶT MÔI TRƯỜNG PYTHON ---
echo "🐍 Tải source code và thiết lập môi trường Python..."

# Chạy các lệnh dưới quyền của user đã tạo để đảm bảo quyền sở hữu file đúng
sudo -u $APP_USER bash <<EOF
set -e
cd "$folder_path"
echo "   - Tải app.py và requirements.txt..."
curl -O https://raw.githubusercontent.com/tocongtruong/api_token/main/app.py
curl -o requirements.txt https://raw.githubusercontent.com/tocongtruong/api_token/main/requirements.txt

echo "   - Tạo môi trường ảo (venv)..."
python3 -m venv venv

echo "   - Cài đặt các thư viện Python..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
EOF

# --- BƯỚC 5: TẠO SYSTEMD SERVICE ĐỂ QUẢN LÝ ỨNG DỤNG ---
echo "⚙️  Tạo service systemd 'api_token.service'..."
# Dùng tên file service cố định để dễ quản lý
SERVICE_NAME="api_token"
cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Gunicorn instance to serve $sub_folder
After=network.target

[Service]
User=$APP_USER
Group=www-data
WorkingDirectory=$folder_path
Environment="PATH=$folder_path/venv/bin"
ExecStart=$folder_path/venv/bin/gunicorn --workers 3 --bind unix:app.sock -m 007 app:app

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Khởi động và kích hoạt service..."
systemctl daemon-reload
systemctl restart $SERVICE_NAME
systemctl enable $SERVICE_NAME

# --- BƯỚC 6: CẤU HÌNH NGINX LÀM REVERSE PROXY ---
echo "🌐 Cấu hình Nginx..."
cat <<EOF > /etc/nginx/sites-available/$domain
server {
    listen 80;
    server_name $domain;

    location / {
        include proxy_params;
        proxy_pass http://unix:${folder_path}/app.sock;
    }
}
EOF

# Kích hoạt cấu hình mới
ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/

# Xóa file cấu hình mặc định nếu có để tránh xung đột
rm -f /etc/nginx/sites-enabled/default

echo "   - Kiểm tra cú pháp Nginx..."
nginx -t

echo "   - Khởi động lại Nginx..."
systemctl restart nginx

# --- BƯỚC 7: CẤP CHỨNG CHỈ SSL BẰNG LETSENCRYPT ---
echo "🔒 Đang lấy chứng chỉ SSL cho $domain..."
certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$email"

# --- HOÀN TẤT ---
echo "--------------------------------------------------"
echo "🎉 HOÀN TẤT! Ứng dụng Flask đã được triển khai thành công."
echo "✅ Truy cập ứng dụng của bạn tại: https://$domain"
echo "--------------------------------------------------"
