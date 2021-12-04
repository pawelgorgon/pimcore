
sudo su
apt-get -y -qqq update && apt-get -y -qqq upgrade
apt-get -y -qqq install mc openssh-server curl software-properties-common

apt-get -y -qqq install nginx
systemctl stop nginx.service
systemctl start nginx.service
systemctl enable nginx.service

add-apt-repository -y ppa:ondrej/php
apt-get -y -qqq update
apt-get -y -qqq install php8.0-fpm php8.0-mbstring php8.0-gd php8.0-intl php8.0-curl php8.0-zip php8.0-xml php8.0-redis php8.0-mysql php8.0-imagick
sed -i "s/file_uploads =.*/file_uploads = On/g" /etc/php/8.0/fpm/php.ini
sed -i "s/allow_url_fopen =.*/allow_url_fopen = On/g" /etc/php/8.0/fpm/php.ini
sed -i "s/memory_limit =.*/memory_limit = 256M/g" /etc/php/8.0/fpm/php.ini
sed -i "s/upload_max_filesize =.*/upload_max_filesize = 200M/g" /etc/php/8.0/fpm/php.ini
sed -i "s/post_max_size =.*/post_max_size = 200M/g" /etc/php/8.0/fpm/php.ini
sed -i "s/max_execution_time =.*/max_execution_time = 300/g" /etc/php/8.0/fpm/php.ini
sed -i "s/cgi.fix_pathinfo =.*/cgi.fix_pathinfo = 0/g" /etc/php/8.0/fpm/php.ini
sed -i "s/date.timezone =.*/date.timezone = Europe\/Warsaw/g" /etc/php/8.0/fpm/php.ini
systemctl stop php8.0-fpm.service
systemctl start php8.0-fpm.service
systemctl enable php8.0-fpm.service

apt-get -y -qqq install mariadb-server
systemctl stop mariadb.service
systemctl start mariadb.service
systemctl enable mariadb.service
mysql_secure_installation
mysql -u root -p <<EOF
CREATE DATABASE pimcore charset=utf8mb4;
CREATE USER 'pimcore'@'localhost' IDENTIFIED BY 'pimcore';
GRANT ALL ON pimcore.* TO 'pimcore'@'localhost';
FLUSH PRIVILEGES;
EXIT
EOF

curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer

cd /var/www
COMPOSER_MEMORY_LIMIT=-1 composer create-project pimcore/demo pimcore
chown -R www-data:www-data /var/www/pimcore
chmod -R 775 /var/www/pimcore

tee -a /etc/nginx/sites-available/pimcore < EOF
upstream php-pimcore10 {
    server unix:/var/run/php/php8.0-fpm.sock;
}
server {
    listen 80;
    server_name pimcore.local;
    root /var/www/pimcore/public;
    index index.php;
    client_max_body_size 100m;
    access_log  /var/log/access.log;
    error_log   /var/log/error.log error;
    rewrite ^/cache-buster-(?:\d+)/(.*) /$1 last;
    location ~* /var/assets/.*\.php(/|$) {
        return 404;
    }
    location ~* /\.(?!well-known/) {
        deny all;
        log_not_found off;
        access_log off;
    }
    location ~* (?:\.(?:bak|conf(ig)?|dist|fla|in[ci]|log|psd|sh|sql|sw[op])|~)$ {
        deny all;
    }
    location ~* ^/admin/(adminer|external) {
        rewrite .* /index.php$is_args$args last;
    }
    location ~* .*/(image|video)-thumb__\d+__.* {
        try_files /var/tmp/thumbnails$uri /index.php;
        expires 2w;
        access_log off;
        add_header Cache-Control "public";
    }
    location ~* ^(?!/admin)(.+?)\.((?:css|js)(?:\.map)?|jpe?g|gif|png|svgz?|eps|exe|gz|zip|mp\d|ogg|ogv|webm|pdf|docx?|xlsx?|pptx?)$ {
        try_files /var/assets$uri $uri =404;
        expires 2w;
        access_log off;
        log_not_found off;
        add_header Cache-Control "public";
    }
    location / {
        error_page 404 /meta/404;
        try_files $uri /index.php$is_args$args;
    }
    location ~ ^/index\.php(/|$) {
        send_timeout 1800;
        fastcgi_read_timeout 1800;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        set $path_info $fastcgi_path_info;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        fastcgi_pass php-pimcore10;
        internal;
    }
    location /fpm- {
        access_log off;
        include fastcgi_params;
        location /fpm-status {
            allow 127.0.0.1;
            deny all;
            fastcgi_pass php-pimcore10;
        }
        location /fpm-ping {
            fastcgi_pass php-pimcore10;
        }
    }
    location /nginx-status {
        allow 127.0.0.1;
        deny all;
        access_log off;
        stub_status;
    }
}
EOF
ln -s /etc/nginx/sites-available/pimcore /etc/nginx/sites-enabled/
systemctl reload nginx.service


cd /var/www/pimcore
./vendor/bin/pimcore-install

