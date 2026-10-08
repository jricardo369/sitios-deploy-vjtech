#!/usr/bin/env bash
#
# Deploy de los sitios (puerto 80: /thunder-team, /vj-tech y /app-gastos).
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
GASTOS_DIR="app-gastos-web"
GASTOS_REPO="https://github.com/jricardo369/app-gastos-web.git"

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

echo "== 0. Verificar puerto 80 =="
echo "-- contenedores publicando el 80 --"
docker ps --filter "publish=80" --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}' || true
# Contenedores de OTRO proyecto en el 80: no tocarlos, abortar con diagnostico.
# (Los propios del proyecto 'sitios' los recrea el compose mas abajo sin problema.)
TODOS_80="$(docker ps --filter "publish=80" -q || true)"
PROPIOS_80="$(docker ps --filter "publish=80" --filter "label=com.docker.compose.project=sitios" -q || true)"
EXTERNOS_80=""
for id in $TODOS_80; do
  case " $PROPIOS_80 " in
    *" $id "*) ;;
    *) EXTERNOS_80="$EXTERNOS_80 $id" ;;
  esac
done
if [ -n "$EXTERNOS_80" ]; then
  echo "ERROR: el puerto 80 lo ocupa(n) contenedor(es) ajeno(s) a este deploy:$EXTERNOS_80"
  docker ps --filter "publish=80" --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}'
  echo "Decide que hacer con ellos (ej: docker rm -f <id>) y reintenta el deploy."
  exit 1
fi
echo "-- procesos del host escuchando en el 80 --"
if sudo -n true 2>/dev/null; then
  sudo ss -ltnp 2>/dev/null | grep ':80 ' || echo "(host libre en el 80)"
else
  echo "(sin sudo sin password: no se pudo inspeccionar el host)"
fi

echo "== 1. Actualizar repos de los sitios =="
sync_repo "$THUNDER_DIR" "$THUNDER_REPO"
sync_repo "$VJTECH_DIR" "$VJTECH_REPO"
sync_repo "$GASTOS_DIR" "$GASTOS_REPO"

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
docker compose up -d --build --force-recreate

echo "== 3. Retirar despliegue viejo del puerto 8081 =="
docker rm -f thunders 2>/dev/null || true
docker rmi -f thunders:latest 2>/dev/null || true

echo "== 4. Limpieza y verificacion =="
docker image prune -f || true
docker compose ps
check_url() {
  local url="$1" i code
  for i in $(seq 1 20); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
    if [ "$code" = "200" ]; then
      echo "$url -> $code"
      return 0
    fi
    sleep 3
  done
  echo "$url -> $code (tras 60s de reintentos)"
  return 1
}
FALLO=0
check_url "http://127.0.0.1/thunder-team/healthz" || FALLO=1
check_url "http://127.0.0.1/thunder-team/" || FALLO=1
check_url "http://127.0.0.1/vj-tech/" || FALLO=1
check_url "http://127.0.0.1/vj-tech/terminos.html" || FALLO=1
check_url "http://127.0.0.1/app-gastos/" || FALLO=1
# Ruta del router Angular (SPA fallback -> index.html)
check_url "http://127.0.0.1/app-gastos/login" || FALLO=1
if [ "$FALLO" -ne 0 ]; then
  echo "== Diagnostico del fallo =="
  docker compose ps || true
  echo "--- logs proxy ---"
  docker compose logs --tail=60 proxy || true
  echo "--- logs apps ---"
  docker compose logs --tail=20 thunder vjtech gastos || true
  exit 1
fi
echo "OK deploy: /thunder-team, /vj-tech y /app-gastos en puerto 80"
