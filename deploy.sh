#!/usr/bin/env bash
#
# Deploy de los sitios estaticos (puerto 80: /thunder-team y /vj-tech).
# Uso: bash deploy.sh
# Se ejecuta en el EC2, en la raiz de este repo (sitios-deploy-vjtech).
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"

BRANCH="master"
THUNDER_DIR="sitio-team-thunder"
THUNDER_REPO="https://github.com/jricardo369/sitio-team-thunder.git"
VJTECH_DIR="landing-page-vjtech"
VJTECH_REPO="https://github.com/jricardo369/landing-page-vjtech.git"

sync_repo() {
  local dir="$1" url="$2"
  if [ -d "$dir/.git" ]; then
    echo "-- pull $dir --"
    git -C "$dir" fetch origin "$BRANCH"
    git -C "$dir" reset --hard "origin/$BRANCH"
  else
    echo "-- clone $dir --"
    git clone --branch "$BRANCH" "$url" "$dir"
  fi
}

echo "== 1. Actualizar repos de los sitios =="
sync_repo "$THUNDER_DIR" "$THUNDER_REPO"
sync_repo "$VJTECH_DIR" "$VJTECH_REPO"

echo "== 2. Build de imagenes =="
# Docker daemon debe arrancar solo tras reboot del EC2,
# si no el --restart unless-stopped no sirve de nada.
sudo systemctl enable --now docker 2>/dev/null || true
echo "-- Espacio antes de limpiar --"
df -h / | tail -1
# Limpieza ANTES del build: imagenes sin usar, cache y volumenes huerfanos
# (lo que causaba 'no space left on device').
# No toca contenedores corriendo (el backend Java en 8080 sigue intacto).
docker image prune -af || true
docker builder prune -af || true
docker volume prune -f || true
echo "-- Espacio tras limpiar --"
df -h / | tail -1
docker compose up -d --build

echo "== 3. Retirar despliegue viejo del puerto 8081 =="
docker rm -f thunders 2>/dev/null || true
docker rmi -f thunders:latest 2>/dev/null || true

echo "== 4. Limpieza y verificacion =="
docker image prune -f || true
sleep 5
docker compose ps
curl -fsS -o /dev/null -w "thunder-team/healthz -> %{http_code}\n" "http://127.0.0.1/thunder-team/healthz"
curl -fsS -o /dev/null -w "thunder-team/         -> %{http_code}\n" "http://127.0.0.1/thunder-team/"
curl -fsS -o /dev/null -w "vj-tech/              -> %{http_code}\n" "http://127.0.0.1/vj-tech/"
curl -fsS -o /dev/null -w "vj-tech/terminos.html -> %{http_code}\n" "http://127.0.0.1/vj-tech/terminos.html"
echo "OK deploy: /thunder-team y /vj-tech en puerto 80"
