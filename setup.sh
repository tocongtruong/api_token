#!/bin/bash

echo "🔧 BẮT ĐẦU TRIỂN KHAI FLASK API"

# === BƯỚC 1: HỎI TÊN THƯ MỤC TRIỂN KHAI ===
read -p "📁 Nhập tên thư mục để cài (Enter để dùng mặc định 'api_token'): " sub_folder
sub_folder=${sub_folder:-api_token}
folder_path="/home/$sub_folder"

# Tạo thư mục
mkdir -p "$folder_path" || { echo "❌ Không thể tạo thư mục $folder_path"; exit 1; }
echo "✅ Đã tạo hoặc xác nhận thư mục: $folder_path"

# === BƯỚC 2: NHẬP DOMAIN ===
while true; do
  read -p "🌐 Nhập domain để chạy Flask API (bắt buộc): " domain
  if [[ -n "$domain" ]]; then
    break
  else
    echo "❌ Domain không được để trống!"
  fi
done

# === BƯỚC 3: XÁC NHẬN ===
echo ""
echo "📋 Tóm tắt cài đặt:"
echo "📁 Thư mục sẽ dùng: $folder_path"
echo "🌐 Domain sẽ dùng: $domain"
echo ""
read -p "👉 Bạn có muốn tiếp tục? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "❌ Huỷ bỏ cài đặt."
  exit 1
fi

# === BƯỚC 4: CÀI GÓI CẦN THIẾT ===
apt update && apt install -y git curl python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

# === BƯỚC 5: TẢI FILE VỀ ===
cd "$folder_path"
curl -O https://raw.githubusercontent.com/tocongtruong/api_token/main/app.py
curl -o requirements.txt https://raw.githubusercontent.com/tocongtruong/api_token/main/requirements.txt

# === BƯỚC 6: SETUP PYTHON VENV ===
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# === BƯỚC 7: TẠO SYSTEMD SERVICE ===
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

# === BƯỚC 8: CẤU HÌNH NGINX ===
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

# === BƯỚC 9: CẤP SSL ===
certbot --nginx -d "$domain" --non-interactive --agree-tos -m your-email@example.com

echo "🎉 ĐÃ TRIỂN KHAI FLASK API THÀNH CÔNG TẠI: https://$domain"
