#!/bin/bash

echo "🔧 BẮT ĐẦU TRIỂN KHAI FLASK API"

# --- HỎI TÊN THƯ MỤC ---
read -p "📁 Nhập tên thư mục (bấm Enter để dùng mặc định 'api_token'): " sub_folder
sub_folder=${sub_folder:-api_token}
folder_path="/home/$sub_folder"

# --- HỎI TÊN MIỀN ---
read -p "🌐 Nhập tên miền (ví dụ: api.domain.com): " domain

# --- CÀI GÓI CẦN THIẾT ---
apt update && apt install -y git curl python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

# --- TẠO THƯ MỤC & TẢI FILE ---
mkdir -p "$folder_path"
cd "$folder_path"

echo "📥 Tải file từ GitHub..."
curl -O https://raw.githubusercontent.com/tocongtruong/api_token/main/app.py
curl -o requirements.txt https://raw.githubusercontent.com/tocongtruong/api_token/main/requirements.txt

# --- TẠO PYTHON VENV & CÀI DEPENDENCIES ---
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# --- TẠO SYSTEMD SERVICE ---
cat <<EOF > /etc/systemd/system/api_token.service
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable api_token
systemctl restart api_token

# --- CẤU HÌNH NGINX ---
cat <<EOF > /etc/nginx/sites-available/$domain
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

ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# --- CẤP SSL ---
certbot --nginx -d "$domain" --non-interactive --agree-tos -m your-email@example.com

echo "✅ ĐÃ TRIỂN KHAI THÀNH CÔNG TẠI: https://$domain"
