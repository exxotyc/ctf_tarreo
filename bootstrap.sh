#!/usr/bin/env bash
# ============================================================
#  bootstrap.sh — ARRANQUE COMPLETO en un servidor nuevo.
# ------------------------------------------------------------
#  Hace TODO de punta a punta, idempotente. Reejecutable sin romper nada:
#    1. Verifica requisitos (docker, compose, python3/requests, CTFD_REPO).
#    2. Genera flags           (generate_flags.sh)
#    3. Levanta CTFd :8000      (start_ctfd.sh)
#    4. Setup admin + token     (setup_ctfd_admin.py -> escribe CTFD_TOKEN)
#    5. Siembra 5 challenges    (seed_ctfd.py)
#    6. Levanta Nivel 1 x equipo(start_all_level1.sh)
#    7. Arranca el watcher      (watch_and_promote.py, en segundo plano)
#
#  Uso:
#     ./bootstrap.sh              # arranque normal
#     ./bootstrap.sh --no-watch   # todo menos lanzar el watcher
#     ./bootstrap.sh --fresh      # regenera flags desde cero (--force)
#
#  PRE-REQUISITOS en el server nuevo (ver README §Portabilidad):
#    - Copiar TODA la carpeta ~/ctf-tarreo y el repo CTFd.
#    - Ajustar config.env: CTFD_REPO, SERVER_IP, NUM_TEAMS, credenciales admin.
#    - Docker + Compose v2 instalados; python3 con 'requests'.
#    - Imágenes: con internet se descargan/construyen solas; offline hay que
#      pre-cargarlas (ver README).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
S="$BASE/scripts"

# En un clon nuevo config.env no existe (está gitignored): crearlo del ejemplo.
if [[ ! -f "$BASE/config.env" ]]; then
  if [[ -f "$BASE/config.env.example" ]]; then
    cp "$BASE/config.env.example" "$BASE/config.env"
    echo "[!] Creé config.env desde config.env.example."
    echo "    EDÍTALO (CTFD_REPO, SERVER_IP, NUM_TEAMS, credenciales admin) y re-ejecuta."
    exit 1
  else
    echo "[-] No existe config.env ni config.env.example"; exit 1
  fi
fi
# shellcheck source=/dev/null
source "$BASE/config.env"

NO_WATCH=0; GEN_ARGS=""
for a in "$@"; do
  case "$a" in
    --no-watch) NO_WATCH=1 ;;
    --fresh)    GEN_ARGS="--force" ;;
  esac
done

step() { echo; echo "========================================"; echo "  $1"; echo "========================================"; }

# ---- 1. Requisitos ----
step "1/7  Verificando requisitos"
command -v docker >/dev/null || { echo "[-] falta docker"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "[-] falta docker compose v2"; exit 1; }
command -v python3 >/dev/null || { echo "[-] falta python3"; exit 1; }
python3 -c 'import requests' 2>/dev/null || { echo "[-] falta el módulo python 'requests' (pip install requests)"; exit 1; }
[[ -d "$CTFD_REPO" ]] || { echo "[-] CTFD_REPO no existe: $CTFD_REPO (ajusta config.env)"; exit 1; }
for L in 1 2 3 4 5; do
  d=$(ls -d "$BASE"/cves/lvl${L}-* 2>/dev/null | head -1 || true)
  [[ -n "$d" ]] || { echo "[-] falta material del nivel $L en $BASE/cves/"; exit 1; }
done
mkdir -p "$BASE/logs" "$BASE/flags" "$BASE/instances"
echo "[+] OK (NUM_TEAMS=$NUM_TEAMS, CTFD_REPO=$CTFD_REPO, SERVER_IP=$SERVER_IP)"

# ---- 2. Flags ----
step "2/7  Generando flags"
bash "$S/generate_flags.sh" $GEN_ARGS

# ---- 3. CTFd ----
step "3/7  Levantando CTFd (:8000)"
bash "$S/start_ctfd.sh"

# ---- 4. Setup admin + token ----
step "4/7  Setup admin de CTFd + token de API"
python3 "$S/setup_ctfd_admin.py"
# recargar config para tomar el CTFD_TOKEN recién escrito
# shellcheck source=/dev/null
source "$BASE/config.env"

# ---- 5. Seed ----
step "5/7  Sembrando challenges + flags"
python3 "$S/seed_ctfd.py"

# ---- 6. Nivel 1 ----
step "6/7  Levantando Nivel 1 de todos los equipos"
bash "$S/start_all_level1.sh"

# ---- 7. Watcher ----
step "7/7  Promotor automático"
if [[ $NO_WATCH -eq 1 ]]; then
  echo "[=] --no-watch: no se lanza. Arráncalo luego con:"
  echo "    nohup python3 '$S/watch_and_promote.py' >> '$BASE/logs/watch.out' 2>&1 &"
else
  if pgrep -f watch_and_promote.py >/dev/null; then
    echo "[=] watcher ya estaba corriendo (pid $(pgrep -f watch_and_promote.py | tr '\n' ' '))."
  else
    nohup python3 "$S/watch_and_promote.py" >> "$BASE/logs/watch.out" 2>&1 &
    disown || true
    sleep 2
    pgrep -f watch_and_promote.py >/dev/null \
      && echo "[+] watcher corriendo (pid $(pgrep -f watch_and_promote.py | tr '\n' ' '))." \
      || echo "[!] el watcher no quedó corriendo; revisa $BASE/logs/watch.out"
  fi
fi

echo
echo "========================================"
echo "  LISTO"
echo "========================================"
echo "  CTFd:        $CTFD_URL  (admin: $CTFD_ADMIN_USER)"
echo "  Nivel 1:     puertos $((PORT_BASE+100+1))..$((PORT_BASE+100+NUM_TEAMS))"
echo "  Logs:        $BASE/logs/{promotions,firstblood}.log"
echo "  Teardown:    $S/teardown.sh --all"
