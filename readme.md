# TP Docker #3 — Nginx, PHP-FPM et MariaDB (avec et sans Docker Compose)

## Objectif global

Dans ce TP, j’ai mis en place une architecture **multi-conteneurs Docker** composée de :
- un **serveur HTTP Nginx**,  
- un **serveur PHP-FPM** pour exécuter du code PHP,  
- et un **serveur de base de données MariaDB**.

Mon objectif était de comprendre comment :
- faire communiquer plusieurs conteneurs via un **réseau Docker**,  
- partager des volumes entre services,  
- et automatiser tout le déploiement grâce à **Docker Compose**.

---

## Étape 0 — Préparation

### Objectif

Avant de commencer, j’ai nettoyé l’environnement Docker et créé la structure du projet pour travailler proprement.

### Commandes que j’ai utilisées
```bash
docker rm -f $(docker ps -aq) 2>/dev/null || true
mkdir -p ~/docker-tp3/etape1/{app,config}
git init ~/docker-tp3
```

### Explication et justification

- La première commande supprime tous les conteneurs existants pour repartir de zéro.  
- La deuxième crée la structure du répertoire de travail.  
- Enfin, j’ai initialisé un dépôt Git afin de versionner mon travail au fur et à mesure.

### Résultat

Mon environnement était prêt, propre et organisé pour débuter les étapes suivantes.

---

## Étape 1 — Nginx + PHP-FPM

### Objectif

L’objectif de cette étape était de faire communiquer **Nginx** et **PHP-FPM** sur un même réseau Docker afin d’afficher une page PHP via Nginx.

### Commandes que j’ai utilisées
```bash
# Création du réseau
docker network create tp3net

# Lancement du conteneur PHP-FPM
docker run -d --name script   --network tp3net   -v "$PWD/app":/app   php:8.2-fpm
```

Ensuite, j’ai créé la configuration Nginx :

```bash
cat > config/default.conf <<'NGINX'
server {
    listen 80;
    server_name _;
    root /app;
    index index.php index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        root           /app;
        fastcgi_pass   script:9000;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include        fastcgi_params;
    }
}
NGINX
```

Puis j’ai lancé le conteneur Nginx :
```bash
docker run -d --name http   --network tp3net   -p 8080:80   -v "$PWD/app":/app   -v "$PWD/config/default.conf":/etc/nginx/conf.d/default.conf:ro   nginx:1.25
```

### Explication

- Le réseau `tp3net` permet aux deux conteneurs de se “voir” et de communiquer.  
- Le volume `./app` est partagé pour que Nginx et PHP utilisent le même dossier de code.  
- La directive `fastcgi_pass script:9000` indique à Nginx d’envoyer les requêtes PHP au conteneur nommé `script`.

### Résultat observé

En ouvrant **http://localhost:8080/**, j’ai vu la page `phpinfo()` s’afficher, ce qui prouve que Nginx et PHP-FPM communiquent correctement. ✅

---

## Étape 2 — Ajout de MariaDB

### Objectif

Dans cette étape, j’ai ajouté une base de données **MariaDB** et j’ai configuré PHP pour qu’il puisse interagir avec elle.

### Commandes que j’ai utilisées
```bash
# Création du réseau
docker network create tp3net2

# Création du volume pour stocker les données
docker volume create mariadb-tp3

# Lancement du conteneur MariaDB
docker run -d --name data   --network tp3net2   -e MARIADB_RANDOM_ROOT_PASSWORD=yes   -e MARIADB_DATABASE=tp3   -e MARIADB_USER=tp3   -e MARIADB_PASSWORD=tp3pass   -v mariadb-tp3:/var/lib/mysql   mariadb:11
```

Ensuite, j’ai construit une image PHP avec l’extension **mysqli** pour que PHP puisse se connecter à MariaDB :

```bash
# Dockerfile
cat > php/Dockerfile <<'DOCKER'
FROM php:8.2-fpm
RUN docker-php-ext-install mysqli
WORKDIR /app
DOCKER

# Build de l'image PHP
docker build -t tp3-php:8.2-fpm-mysqli ./php
```

Puis j’ai relancé mes conteneurs PHP et Nginx :
```bash
docker run -d --name script   --network tp3net2   -v "$PWD/app":/app   tp3-php:8.2-fpm-mysqli

docker run -d --name http   --network tp3net2   -p 8080:80   -v "$PWD/app":/app   -v "$PWD/config/default.conf":/etc/nginx/conf.d/default.conf:ro   nginx:1.25
```

### Explication

- Le réseau `tp3net2` relie maintenant **Nginx**, **PHP**, et **MariaDB**.  
- J’ai créé un utilisateur `tp3` avec un mot de passe `tp3pass` pour que PHP puisse se connecter.  
- L’extension `mysqli` était indispensable pour que PHP dialogue avec la base MariaDB.

### Résultat observé

- En ouvrant **http://localhost:8080/** → j’ai bien vu la page `phpinfo()`.  
- En ouvrant **http://localhost:8080/test.php** → mon script a pu insérer et lire des données dans la base.  
- À chaque rafraîchissement, le compteur s’incrémentait :
  ```
  Dernier compteur : 2
  Nombre de lignes : 2
  Dernier compteur : 3
  Nombre de lignes : 3
  ```

Cela prouve que la communication entre Nginx, PHP et MariaDB fonctionne parfaitement. ✅

---

## Étape 3 — Conversion en Docker Compose

### Objectif

L’objectif de cette dernière étape était de transformer ma configuration manuelle en un **fichier `docker-compose.yml`**, pour tout lancer automatiquement.

### Commandes que j’ai utilisées
```bash
mkdir -p ~/docker-tp3/etape3/{app,config,php}
cp ~/docker-tp3/etape2/app/* ~/docker-tp3/etape3/app/
cp ~/docker-tp3/etape2/config/default.conf ~/docker-tp3/etape3/config/
cp ~/docker-tp3/etape2/php/Dockerfile ~/docker-tp3/etape3/php/
```

Ensuite, j’ai écrit mon fichier `docker-compose.yml` :

```yaml
version: "3.9"

services:
  data:
    image: mariadb:11
    container_name: data
    environment:
      MARIADB_RANDOM_ROOT_PASSWORD: "yes"
      MARIADB_DATABASE: tp3
      MARIADB_USER: tp3
      MARIADB_PASSWORD: tp3pass
    volumes:
      - dbdata:/var/lib/mysql
    networks:
      - tp3net

  script:
    build:
      context: ./php
      dockerfile: Dockerfile
    container_name: script
    volumes:
      - ./app:/app
    depends_on:
      - data
    networks:
      - tp3net

  http:
    image: nginx:1.25
    container_name: http
    ports:
      - "8080:80"
    volumes:
      - ./app:/app
      - ./config/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - script
    networks:
      - tp3net

networks:
  tp3net:

volumes:
  dbdata:
```

Enfin, j’ai lancé toute l’infrastructure :
```bash
docker compose up -d --build
```

### Explication

- Le fichier `docker-compose.yml` décrit les trois services (`data`, `script`, `http`) et leurs dépendances.  
- `depends_on` permet de définir l’ordre de démarrage (base → PHP → Nginx).  
- Les volumes assurent la persistance et le partage du code.  
- Le paramètre `build:` automatise la création de l’image PHP avec `mysqli`.

### Résultat observé

Après lancement, j’ai vérifié :
```bash
docker compose ps
```
Tous les services étaient **Up**, et les pages suivantes fonctionnaient :
- **http://localhost:8080/** → `phpinfo()`  
- **http://localhost:8080/test.php** → compteur qui augmente à chaque actualisation ✅

---

## Conclusion

### Ce que j’ai réalisé

- **Étape 1** : mise en place de Nginx et PHP-FPM sur un même réseau.  
- **Étape 2** : ajout de MariaDB et connexion avec PHP via `mysqli`.  
- **Étape 3** : automatisation complète avec Docker Compose.

### Ce que j’ai appris

- Créer un **réseau Docker** personnalisé pour connecter plusieurs conteneurs.  
- Monter des **volumes** pour partager le code et stocker les données.  
- Configurer Nginx pour exécuter du PHP via FastCGI.  
- Construire une **image PHP personnalisée** avec des extensions supplémentaires.  
- Écrire et comprendre un fichier **docker-compose.yml** complet et fonctionnel.

### Commande finale pour tout relancer
```bash
docker compose down -v && docker compose up -d --build
```

Cette commande reconstruit et relance automatiquement toute la stack.
