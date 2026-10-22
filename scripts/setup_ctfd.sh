#!/usr/bin/env bash
# ============================================================
#  setup_ctfd.sh — TODA la pega de CTFd en un solo comando (y solo CTFd).
# ------------------------------------------------------------
#  Hace, en orden e idempotente:
#    1. Levanta CTFd (:8000) desde CTFD_REPO        (start_ctfd.sh)
#    2. Completa el setup inicial + crea el admin + genera el token de API
#       y lo escribe en config.env                  (setup_ctfd_admin.py)
#    3. Siembra los 5 challenges + todas las flags   (seed_ctfd.py)
#
#  NO toca los contenedores de reto, ni el watcher, ni las VMs: solo CTFd.
#  Requiere las flags ya generadas (scripts/generate_flags.sh) para el paso 3.
#
#  Uso:
#     ./setup_ctfd.sh              # levanta + configura + siembra
#     ./setup_ctfd.sh --no-seed    # solo levantar + admin/token (sin sembrar)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

NO_SEED=0
[[ "${1:-}" == "--no-seed" ]] && NO_SEED=1

step() { echo; echo "----------------------------------------"; echo "  $1"; echo "----------------------------------------"; }

# ---- Requisitos mínimos (solo lo que CTFd necesita) ----
command -v docker >/dev/null || { echo "[-] falta docker"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "[-] falta docker compose v2"; exit 1; }
command -v python3 >/dev/null || { echo "[-] falta python3"; exit 1; }
python3 -c 'import requests' 2>/dev/null || { echo "[-] falta el módulo python 'requests' (pip install requests)"; exit 1; }
[[ -d "$CTFD_REPO" ]] || { echo "[-] CTFD_REPO no existe: $CTFD_REPO (ajusta config.env)"; exit 1; }

# ---- 1. Levantar CTFd ----
step "1/3  Levantando CTFd (:8000)"
bash "$SCRIPT_DIR/start_ctfd.sh"

# ---- 2. Admin + token ----
step "2/3  Setup admin + token de API"
python3 "$SCRIPT_DIR/setup_ctfd_admin.py"
# recargar config para tomar el CTFD_TOKEN recién escrito
# shellcheck source=/dev/null
source "$BASE/config.env"

# ---- 3. Seed ----
if [[ $NO_SEED -eq 1 ]]; then
  step "3/3  Seed OMITIDO (--no-seed)"
else
  step "3/3  Sembrando challenges + flags"
  if ! ls "$BASE"/flags/team1/lvl1/flag.txt >/dev/null 2>&1; then
    echo "[-] No hay flags generadas. Corre primero: scripts/generate_flags.sh"; exit 1
  fi
  python3 "$SCRIPT_DIR/seed_ctfd.py"
fi

echo
echo "========================================"
echo "  CTFd LISTO"
echo "========================================"
echo "  URL:    $CTFD_URL   (admin: $CTFD_ADMIN_USER)"
echo "  Token:  guardado en config.env (CTFD_TOKEN)"
[[ $NO_SEED -eq 0 ]] && echo "  Retos:  5 challenges + flags sembrados"
echo "  Bajar:  scripts/teardown.sh --ctfd"
