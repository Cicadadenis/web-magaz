#!/bin/bash

set -e

echo "🔄 Обновление системы..."
apt update && apt upgrade -y

echo "📦 Установка необходимых пакетов..."
apt install -y nginx mariadb-server git unzip curl \
php8.3 php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip php8.3-cli

echo "▶️ Запуск сервисов..."
systemctl enable nginx mariadb php8.3-fpm
systemctl start nginx mariadb php8.3-fpm

echo "🔐 Настройка MariaDB (выполни вручную если нужно)"
mysql_secure_installation || true

echo "🗄️ Создание базы данных"

read -p "Введите имя базы данных: " DB_NAME
read -p "Введите имя пользователя: " DB_USER
read -s -p "Введите пароль пользователя: " DB_PASS
echo
read -p "Введите хост (localhost): " DB_HOST
DB_HOST=${DB_HOST:-localhost}

mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$DB_HOST';
FLUSH PRIVILEGES;
EOF

echo "📁 Настройка прав Webasyst..."

read -p "Введите путь к проекту (например /var/www/web-magaz): " WEB_PATH

chown -R www-data:www-data $WEB_PATH
find $WEB_PATH -type d -exec chmod 755 {} \;
find $WEB_PATH -type f -exec chmod 644 {} \;

echo "🌐 Настройка Nginx..."

cat > /etc/nginx/sites-available/webasyst <<EOF
server {
    listen 80;
    server_name _;

    root $WEB_PATH;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
}
EOF

ln -sf /etc/nginx/sites-available/webasyst /etc/nginx/sites-enabled/webasyst
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

echo "✅ Установка завершена!"
echo "🌍 Открой сервер в браузере: http://IP_СЕРВЕРА"
