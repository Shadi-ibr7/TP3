#!/usr/bin/env bash
set -euo pipefail

# Nettoyage
docker rm -f http script 2>/dev/null || true
docker network rm tp3net 2>/dev/null || true

# Réseau dédié
docker network create tp3net

# Dossiers attendus : app/ (avec index.php) et config/default.conf
if [[ ! -f app/index.php ]]; then
  echo "⚠️ app/index.php manquant. Création d'un phpinfo minimal."
  mkdir -p app
  cat > app/index.php <<'PHP'
<?php phpinfo();
PHP
fi

if [[ ! -f config/default.conf ]]; then
  echo "⚠️ config/default.conf manquant. Génération d'une conf Nginx par défaut."
  mkdir -p config
  cat > config/default.conf <<'NGINX'
server {
  listen 80;
  server_name _;
  root /app;
  index index.php index.html;

  location / { try_files $uri $uri/ =404; }

  location ~ \.php$ {
    root           /app;
    fastcgi_pass   script:9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include        fastcgi_params;
  }
}
NGINX
fi

# PHP-FPM (SCRIPT)
docker run -d --name script \
  --network tp3net \
  -v "$PWD/app":/app \
  php:8.2-fpm

# Nginx (HTTP)
docker run -d --name http \
  --network tp3net \
  -p 8080:80 \
  -v "$PWD/app":/app \
  -v "$PWD/config/default.conf":/etc/nginx/conf.d/default.conf:ro \
  nginx:1.25

echo " Étape 1 lancée. Teste : http://localhost:8080/"
