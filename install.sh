#!/bin/bash
set -e

echo "🔄 Отключаем автоматические обновления (unattended-upgrades)..."
sudo systemctl stop unattended-upgrades || true
sudo systemctl disable --now unattended-upgrades || true
sudo killall -9 unattended-upgrades 2>/dev/null || true

# Удаляем возможные старые блокировки
echo "🗑️ Очистка блокировок apt..."
sudo rm -f /var/lib/dpkg/lock-frontend
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/lib/apt/lists/lock

# Исправляем возможные незавершённые пакеты
sudo dpkg --configure -a || true

echo "🔄 Обновление системы..."
sudo apt update
sudo apt upgrade -y

echo "📦 Установка необходимых пакетов..."
sudo apt install -y nginx mariadb-server git unzip curl \
    php8.3 php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd \
    php8.3-mbstring php8.3-xml php8.3-zip php8.3-cli

echo "▶️ Запуск сервисов..."
sudo systemctl enable --now nginx mariadb php8.3-fpm

echo "🔐 Настройка MariaDB (выполни вручную если нужно)..."
mysql_secure_installation || true

echo "🗄️ Создание базы данных"
read -p "Введите имя базы данных: " DB_NAME
read -p "Введите имя пользователя: " DB_USER
read -s -p "Введите пароль пользователя: " DB_PASS
echo
read -p "Введите хост (по умолчанию localhost): " DB_HOST
DB_HOST=${DB_HOST:-localhost}

sudo mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$DB_HOST';
FLUSH PRIVILEGES;
EOF

echo "📁 Настройка прав Webasyst..."
read -p "Введите путь к проекту (например /var/www/web-magaz): " WEB_PATH
sudo chown -R www-data:www-data "$WEB_PATH"
sudo find "$WEB_PATH" -type d -exec chmod 755 {} \;
sudo find "$WEB_PATH" -type f -exec chmod 644 {} \;

echo "🌐 Настройка Nginx..."
sudo tee /etc/nginx/sites-available/webasyst > /dev/null <<EOF
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

sudo ln -sf /etc/nginx/sites-available/webasyst /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo "✅ Установка завершена!"
echo "🌍 Откройте в браузере: http://$(curl -s ifconfig.me || echo 'ВАШ_IP')"
