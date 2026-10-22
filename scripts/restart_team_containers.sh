#!/usr/bin/env bash
# ============================================================
#  restart_team_containers.sh <TEAM_ID>
# ------------------------------------------------------------
#  Reinicia todos los contenedores de challenges que ya estaban
#  desplegados para un equipo (ej: después de reiniciar la VM).
#
#  Busca todos los docker-compose.yml en instances/team<N>/
#  y ejecuta 'docker compose up -d' en cada uno.
#
#  Si TEAM_ID no tiene ningún nivel desplegado, levanta el nivel 1.
#
#  Uso: ./scripts/restart_team_containers.sh 3
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

T="${1:?Uso: $0 <TEAM_ID>}"
INSTANCES_DIR="$BASE/instances/team${T}"
LOG_DIR="$BASE/logs"
mkdir -p "$LOG_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_DIR/autostart.log"; }

log "--- restart_team_containers.sh team$T ---"

# Verificar si hay instancias desplegadas para este equipo
deployed=()
for lvl in 1 2 3 4 5; do
  compose="$INSTANCES_DIR/lvl${lvl}/docker-compose.yml"
  if [[ -f "$compose" ]]; then
    deployed+=("$lvl")
  fi
done

if [[ ${#deployed[@]} -eq 0 ]]; then
  log "No hay instancias previas para team$T. Levantando nivel 1..."
  bash "$SCRIPT_DIR/deploy_level.sh" "$T" "1"
  log "Nivel 1 del equipo $T levantado."
  exit 0
fi

log "Niveles desplegados para team$T: ${deployed[*]}"

# Reiniciar cada nivel en orden
for lvl in "${deployed[@]}"; do
  compose="$INSTANCES_DIR/lvl${lvl}/docker-compose.yml"
  project="team${T}_lvl${lvl}"
  log "Reiniciando $project..."
  if docker compose -f "$compose" -p "$project" up -d 2>&1 | tee -a "$LOG_DIR/autostart.log"; then
    log "OK: $project levantado."
  else
    log "WARN: error levantando $project. Intentando re-deploy..."
    bash "$SCRIPT_DIR/deploy_level.sh" "$T" "$lvl" 2>&1 | tee -a "$LOG_DIR/autostart.log" || \
      log "ERROR: no se pudo levantar team$T nivel$lvl. Revisá los logs."
  fi
done

log "--- restart_team_containers.sh completado para team$T (${#deployed[@]} nivel(es)) ---"
