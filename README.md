# Download script từ GitHub
***Cách 1: Với Ngnix:
wget https://raw.githubusercontent.com/tocongtruong/api_token/main/deploy.sh

***Cách 2: Với Caddy:
wget https://raw.githubusercontent.com/tocongtruong/api_token/refs/heads/main/deploy_caddy.sh

# Cấp quyền thực thi
chmod +x deploy.sh

chmod +x deploy_caddy.sh

# Chạy script
./deploy.sh

./deploy_caddy.sh
