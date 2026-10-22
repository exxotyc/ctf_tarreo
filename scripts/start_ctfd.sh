#!/usr/bin/env bash
# ============================================================
#  start_ctfd.sh — levanta CTFd desde el repo YA clonado (CTFD_REPO)
#  en el puerto 8000. No re-clona nada.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

if [[ ! -d "$CTFD_REPO" ]]; then
  echo "[-] No existe CTFD_REPO=$CTFD_REPO (ajusta config.env)"; exit 1
fi

echo "[*] Levantando CTFd desde $CTFD_REPO ..."
echo "    (la primera vez construye la imagen: requiere internet SOLO en el setup previo)"
# Levanta el stack (ctfd:8000, db, cache, nginx:80). Idempotente.
docker compose -p ctfd -f "$CTFD_REPO/docker-compose.yml" up -d --build

echo "[*] Esperando a que CTFd responda en $CTFD_URL ..."
for i in $(seq 1 60); do
  if curl -sf "$CTFD_URL/setup" >/dev/null 2>&1 || curl -sf "$CTFD_URL/" >/dev/null 2>&1; then
    echo "[+] CTFd responde en $CTFD_URL"
    echo "    1) Abre $CTFD_URL y completa el setup inicial (crea el admin)."
    echo "    2) Genera el token admin: Settings -> Access Tokens -> Generate  (ponlo en config.env: CTFD_TOKEN=...)"
    exit 0
  fi
  sleep 2
done
echo "[!] CTFd no respondió a tiempo; revisa 'docker compose -p ctfd logs'."
exit 1
