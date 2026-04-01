#!/bin/bash
# =============================================
# Неинтерактивный LEMP + Webasyst (исправлено nginx + mariadb)
# Ubuntu 24.04
# =============================================

set -e

export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

echo "🔄 Отключаем автоматические обновления..."
sudo systemctl stop unattended-upgrades 2>/dev/null || true
sudo systemctl disable --now unattended-upgrades 2>/dev/null || true

echo "🗑️ Очистка блокировок..."
sudo rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock /var/lib/apt/lists/lock

echo "🔧 Исправляем повреждённые пакеты..."
sudo dpkg --configure -a || true
sudo apt --fix-broken install -y || true

echo "🛠️ Исправляем mariadb-common..."
sudo mkdir -p /etc/mysql
sudo touch /etc/mysql/mariadb.cnf /etc/mysql/my.cnf /etc/mysql/my.cnf.fallback

echo "🔄 Обновление системы..."
sudo apt update
sudo apt upgrade -y

echo "📦 Очистка старого MariaDB..."
sudo apt purge -y mariadb* mysql* libmariadb* 2>/dev/null || true
sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null || true

echo "📦 Установка пакетов (без вопросов)..."
sudo apt install -y -o DPkg::Options::="--force-confnew" -o DPkg::Options::="--force-confdef" \
    nginx mariadb-server mariadb-client \
    php8.3 php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd \
    php8.3-mbstring php8.3-xml php8.3-zip php8.3-cli \
    git unzip curl

echo "▶️ Запуск сервисов..."
sudo systemctl enable --now mariadb php8.3-fpm

# Создаём snippets/fastcgi-php.conf, если его нет (частая причина ошибки nginx)
echo "📝 Создаём fastcgi-php.conf (если отсутствует)..."
sudo mkdir -p /etc/nginx/snippets
sudo tee /etc/nginx/snippets/fastcgi-php.conf > /dev/null <<'EOF'
# regex to split $uri to $fastcgi_script_name and $fastcgi_path
fastcgi_split_path_info ^(.+\.php)(/.+)$;

# Check that the PHP script exists before passing it
try_files $fastcgi_script_name =404;

# Buffer sizes
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;

# Timeout
fastcgi_read_timeout 300;

# Pass to PHP-FPM
include fastcgi_params;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
fastcgi_param PATH_INFO $fastcgi_path_info;
EOF

echo "🔐 Настройка MariaDB (неинтерактивно)..."
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '';" 2>/dev/null || true
sudo mysql_secure_installation --defaults-extra-file=<(echo "[client]
user=root
password=") --use-default || true

echo "🗄️ Создание базы данных"
read -p "Введите имя базы данных: " DB_NAME
read -p "Введите имя пользователя БД: " DB_USER
read -s -p "Введите пароль пользователя БД: " DB_PASS
echo
read -p "Хост (по умолчанию localhost): " DB_HOST
DB_HOST=${DB_HOST:-localhost}

sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$DB_HOST';
FLUSH PRIVILEGES;
EOF

echo "✅ База данных создана!"

echo "📁 Настройка прав проекта"
read -p "Введите путь к папке Webasyst (например /var/www/web-magaz): " WEB_PATH

sudo mkdir -p "$WEB_PATH"
sudo chown -R www-data:www-data "$WEB_PATH"
sudo find "$WEB_PATH" -type d -exec chmod 755 {} \;
sudo find "$WEB_PATH" -type f -exec chmod 644 {} \;

echo "🌐 Создание конфига Nginx..."
sudo tee /etc/nginx/sites-available/webasyst > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    root $WEB_PATH;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/webasyst /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

echo "🔍 Проверка конфигурации Nginx..."
sudo nginx -t

echo "▶️ Перезапуск Nginx..."
sudo systemctl restart nginx

echo ""
echo "✅ Установка завершена!"
echo "🌍 Откройте в браузере: http://$(curl -s ifconfig.me || hostname -I | awk '{print \$1}')"
echo "📌 Загрузите файлы Webasyst в $WEB_PATH"
