#!/bin/bash

echo "🔧 BẮT ĐẦU TRIỂN KHAI FLASK API"

# --- BƯỚC 1: CHỌN TÊN THƯ MỤC ---
read -p "📁 Nhập tên thư mục (mặc định: api_token): " sub_folder
sub_folder=${sub_folder:-api_token}
folder_path="/home/$sub_folder"

# --- TẠO THƯ MỤC ---
mkdir -p "$folder_path" || { echo "❌ Không thể tạo thư mục $folder_path"; exit 1; }
echo "✅ Thư mục đã tạo: $folder_path"

# --- BƯỚC 2: NHẬP DOMAIN ---
read -p "🌐 Nhập tên miền (ví dụ: api.domain.com): " domain
if [[ -z "$domain" ]]; then
  echo "❌ Domain không được để trống!"
  exit 1
fi

# --- BƯỚC 3: CÀI GÓI CẦN THIẾT ---
apt update && apt install -y git curl python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

# --- BƯỚC 4: TẢI SOURCE CODE VỀ ---
cd "$folder_path"
curl -O https://raw.githubusercontent.com/tocongtruong/api_token/main/app.py
curl -o requirements.txt https://raw.githubusercontent.com/tocongtruong/api_token/main/requirements.txt

# --- BƯỚC 5: TẠO VENV VÀ CÀI PYTHON DEPENDENCIES ---
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# --- BƯỚC 6: TẠO SYSTEMD SERVICE ---
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

# --- BƯỚC 7: CẤU HÌNH NGINX ---
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

# --- BƯỚC 8: CẤP SSL LETSENCRYPT ---
certbot --nginx -d "$domain" --non-interactive --agree-tos -m your-email@example.com

# --- HOÀN TẤT ---
echo "🎉 HOÀN TẤT! Ứng dụng Flask đã triển khai tại: https://$domain"
