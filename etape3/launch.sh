#!/usr/bin/env bash
set -euo pipefail

# Option -v pour reset total (containers + volumes)
RESET_VOL=false
if [[ "${1:-}" == "-v" ]]; then
  RESET_VOL=true
fi

if $RESET_VOL; then
  docker compose down -v 2>/dev/null || true
else
  docker compose down 2>/dev/null || true
fi

docker compose up -d --build
docker compose ps

echo " Étape 3 (Compose) lancée."
echo " phpinfo :   http://localhost:8080/"
echo " test.php :  http://localhost:8080/test.php"
echo " Réinitialiser DB : ./launch.sh -v"
