#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
#  Nettoyage
# ────────────────────────────────────────────────
docker rm -f http script data 2>/dev/null || true
docker network rm tp3net2 2>/dev/null || true

# Option -v = reset complet de la base
RESET_DB=false
if [[ "${1:-}" == "-v" ]]; then
  RESET_DB=true
fi
$RESET_DB && docker volume rm mariadb-tp3 2>/dev/null || true

# ────────────────────────────────────────────────
#  Réseau
# ────────────────────────────────────────────────
docker network create tp3net2 1>/dev/null || true

# ────────────────────────────────────────────────
#  Préparation des dossiers et fichiers
# ────────────────────────────────────────────────
mkdir -p app config php db/init

# Fichier config Nginx si absent
if [[ ! -f config/default.conf ]]; then
  cat > config/default.conf <<'NGINX'
server {
  listen 80;
  server_name _;
  root /app;
  index index.php index.html;

  location / { try_files $uri $uri/ /index.php; }

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

# Dockerfile PHP (avec mysqli)
if [[ ! -f php/Dockerfile ]]; then
  cat > php/Dockerfile <<'DOCKER'
FROM php:8.2-fpm
RUN docker-php-ext-install mysqli
WORKDIR /app
DOCKER
fi

# test.php avec le code correct (ton code final)
cat > app/test.php <<'PHP'
<?php
// Affiche les erreurs mysqli clairement
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    // ⚠️ Identifiants qu’on a définis au lancement de MariaDB
    $mysqli = new mysqli('data', 'tp3', 'tp3pass', 'tp3');
    $mysqli->set_charset('utf8mb4');

    // 1) Assurer que la table existe (créée si absente)
    $mysqli->query("
        CREATE TABLE IF NOT EXISTS matable (
            id INT AUTO_INCREMENT PRIMARY KEY,
            compteur INT NOT NULL
        )
    ");

    // 2) Écriture : insère compteur = (max existant + 1)
    $mysqli->query("
        INSERT INTO matable (compteur)
        SELECT COALESCE(MAX(compteur), 0) + 1 FROM matable
    ");

    // 3) Lecture : compter les lignes (et afficher la dernière valeur)
    $res = $mysqli->query("SELECT compteur FROM matable ORDER BY id DESC LIMIT 1");
    $last = $res->fetch_assoc()['compteur'] ?? 0;
    $res->close();

    $res2 = $mysqli->query("SELECT COUNT(*) AS n FROM matable");
    $n = $res2->fetch_assoc()['n'] ?? 0;
    $res2->close();

    printf("Dernier compteur : %d<br />", $last);
    printf("Nombre de lignes : %d<br />", $n);

} catch (mysqli_sql_exception $e) {
    echo "Erreur MySQL : " . $e->getMessage();
} finally {
    if (isset($mysqli) && $mysqli instanceof mysqli) {
        $mysqli->close();
    }
}
?>
PHP

# index.php si absent (phpinfo)
if [[ ! -f app/index.php ]]; then
  cat > app/index.php <<'PHP'
<?php phpinfo();
PHP
fi

# ────────────────────────────────────────────────
#  Conteneur MariaDB
# ────────────────────────────────────────────────
docker volume create mariadb-tp3 1>/dev/null || true

docker run -d --name data \
  --network tp3net2 \
  -e MARIADB_RANDOM_ROOT_PASSWORD=yes \
  -e MARIADB_DATABASE=tp3 \
  -e MARIADB_USER=tp3 \
  -e MARIADB_PASSWORD=tp3pass \
  -v mariadb-tp3:/var/lib/mysql \
  -v "$PWD/db/init":/docker-entrypoint-initdb.d \
  mariadb:11

# ────────────────────────────────────────────────
#  PHP-FPM avec mysqli
# ────────────────────────────────────────────────
docker build -t tp3-php:8.2-fpm-mysqli ./php
docker run -d --name script \
  --network tp3net2 \
  -v "$PWD/app":/app \
  tp3-php:8.2-fpm-mysqli

# ────────────────────────────────────────────────
#  Nginx
# ────────
