#!/usr/bin/env bash
# ============================================================
#  teardown.sh — baja y limpia TODAS las instancias y (opcional) CTFd.
# ------------------------------------------------------------
#  Uso:
#    ./teardown.sh            # baja todas las instancias team*_lvl* (-v)
#    ./teardown.sh --ctfd     # además baja el stack de CTFd
#    ./teardown.sh --all      # instancias + CTFd + mata watch_and_promote
# ============================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

WITH_CTFD=0; KILL_WATCH=0
for a in "$@"; do
  case "$a" in
    --ctfd) WITH_CTFD=1 ;;
    --all)  WITH_CTFD=1; KILL_WATCH=1 ;;
  esac
done

echo "[*] Bajando instancias de retos..."
for T in $(seq 1 "$NUM_TEAMS"); do
  for L in $(seq 1 "$NUM_LEVELS"); do
    COMPOSE="$BASE/instances/team${T}/lvl${L}/docker-compose.yml"
    PROJ="team${T}_lvl${L}"
    if [[ -f "$COMPOSE" ]]; then
      docker compose -p "$PROJ" -f "$COMPOSE" down -v --remove-orphans 2>/dev/null \
        && echo "    - $PROJ bajado" || echo "    ! $PROJ (nada que bajar)"
    fi
  done
done

# Barrido de seguridad: cualquier proyecto team*_lvl* que haya quedado colgado
echo "[*] Barrido de proyectos residuales team*_lvl*..."
docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null \
  | sort -u | grep -E '^team[0-9]+_lvl[0-9]+$' | while read -r p; do
      docker compose -p "$p" down -v --remove-orphans 2>/dev/null && echo "    - $p (residual) bajado"
  done

if [[ $KILL_WATCH -eq 1 ]]; then
  echo "[*] Deteniendo watch_and_promote..."
  pkill -f watch_and_promote.py 2>/dev/null && echo "    - watcher detenido" || echo "    ! no corría"
fi

if [[ $WITH_CTFD -eq 1 ]]; then
  echo "[*] Bajando CTFd..."
  docker compose -p ctfd -f "$CTFD_REPO/docker-compose.yml" down -v --remove-orphans 2>/dev/null \
    && echo "    - CTFd bajado" || echo "    ! CTFd no corría"
fi

echo "[+] Teardown completo."
