#!/bin/bash

echo "🔧 BẮT ĐẦU TRIỂN KHAI FLASK API"

# --- HỎI ĐƯỜNG DẪN THƯ MỤC TRIỂN KHAI ---
read -p "📁 Nhập đường dẫn thư mục (bấm Enter để dùng /home/api_token): " folder_path
folder_path=${folder_path:-/home/api_token}

# --- HỎI TÊN MIỀN ---
read -p "🌐 Nhập tên miền (ví dụ: api.domain.com): " domain

# --- CÀI ĐẶT CÁC GÓI CẦN THIẾT ---
echo "📦 Đang cập nhật và cài đặt gói cần thiết..."
apt update && apt install -y git python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

# --- TẠO THƯ MỤC VÀ CLONE REPO ---
echo "📂 Tạo thư mục và tải source code..."
mkdir -p "$folder_path"
cd "$folder_path"
git clone https://github.com/tocongtruong/api_token.git . || { echo "❌ Lỗi clone repo!"; exit 1; }

# --- TẠO VENV & CÀI PYTHON DEPENDENCIES ---
echo "🐍 Tạo môi trường ảo Python..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# --- TẠO GUNICORN SYSTEMD SERVICE ---
echo "🧩 Tạo service systemd..."
SERVICE_FILE="/etc/systemd/system/api_token.service"
cat <<EOF > $SERVICE_FILE
[Unit]
Description=Flask API - api_token
After=network.target

[Service]
User=root
WorkingDirectory=$folder_path
Environment="PATH=$folder_path/venv/bin"
ExecStart=$folder_path/venv/bin/gunicorn -w 4 -b 127.0.0.1:8000 app:app

[Install]
WantedBy=multi-user.target
EOF

# --- KHỞI ĐỘNG SERVICE ---
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable api_token
systemctl restart api_token

# --- CẤU HÌNH NGINX ---
echo "🔧 Cấu hình nginx..."
NGINX_FILE="/etc/nginx/sites-available/$domain"
cat <<EOF > $NGINX_FILE
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf $NGINX_FILE /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# --- CẤP SSL ---
echo "🔐 Đang cấp chứng chỉ SSL..."
certbot --nginx -d "$domain" --non-interactive --agree-tos -m your-email@example.com

# --- HOÀN TẤT ---
echo "✅ Flask API đã triển khai tại: https://$domain"
