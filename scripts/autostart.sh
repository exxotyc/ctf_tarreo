#!/usr/bin/env bash
# ============================================================
#  autostart.sh — Llamado por systemd en cada arranque de VM
# ------------------------------------------------------------
#  Lee VM_MODE de config.env y actúa:
#
#  VM_MODE=central (default):
#    Corre bootstrap.sh completo (CTFd + challenges + watcher).
#    Idempotente: si todo ya está levantado, no rompe nada.
#
#  VM_MODE=team-vm:
#    Reinicia los contenedores de challenges del equipo TEAM_ID
#    que estaban desplegados antes del último apagado.
#    Opcionalmente arranca el watcher local si CTFD_TOKEN está
#    configurado (útil cuando CTFd está en otra máquina).
#
#  Uso directo: ./scripts/autostart.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$BASE/config.env"
LOG_DIR="$BASE/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/autostart.log"

ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts())] $*" | tee -a "$LOG"; }
die()  { log "ERROR: $*"; exit 1; }

log "=== autostart.sh iniciado ==="

# ---- Cargar config ----
[[ -f "$CONFIG" ]] || die "No existe config.env en $BASE. Ejecutá install.sh primero."
# shellcheck source=/dev/null
source "$CONFIG"

VM_MODE="${VM_MODE:-central}"
TEAM_ID="${TEAM_ID:-}"
log "VM_MODE=$VM_MODE  TEAM_ID=${TEAM_ID:-<no definido>}"

# ---- Esperar a Docker ----
log "Esperando Docker..."
for i in $(seq 1 30); do
  docker info &>/dev/null && break
  sleep 2
  [[ $i -eq 30 ]] && die "Docker no disponible después de 60s."
done
log "Docker disponible."

# ============================================================
#  Modo CENTRAL: arranque completo (CTFd + todos los equipos)
# ============================================================
if [[ "$VM_MODE" == "central" ]]; then
  log "Modo central: ejecutando bootstrap.sh..."
  exec bash "$BASE/bootstrap.sh" 2>&1 | tee -a "$LOG"
fi

# ============================================================
#  Modo TEAM-VM: reiniciar contenedores del equipo
# ============================================================
if [[ "$VM_MODE" == "team-vm" ]]; then
  [[ -n "$TEAM_ID" ]] || die "VM_MODE=team-vm pero TEAM_ID no está definido en config.env."

  log "Modo team-vm: reiniciando contenedores del equipo $TEAM_ID..."
  bash "$SCRIPT_DIR/restart_team_containers.sh" "$TEAM_ID"

  # ---- Arrancar watcher local (si CTFd está configurado y token disponible) ----
  if [[ -n "${CTFD_TOKEN:-}" && -n "${CTFD_URL:-}" ]]; then
    if pgrep -f watch_and_promote.py >/dev/null 2>&1; then
      log "Watcher ya estaba corriendo (pid $(pgrep -f watch_and_promote.py | tr '\n' ' '))."
    else
      log "Arrancando watcher (CTFD_URL=$CTFD_URL, TEAM_ID=$TEAM_ID)..."
      export TEAM_ID_FILTER="$TEAM_ID"
      nohup python3 "$SCRIPT_DIR/watch_and_promote.py" \
        >> "$LOG_DIR/watch.out" 2>&1 &
      disown || true
      sleep 2
      if pgrep -f watch_and_promote.py >/dev/null 2>&1; then
        log "Watcher corriendo (pid $(pgrep -f watch_and_promote.py | tr '\n' ' '))."
      else
        log "WARN: watcher no quedó corriendo. Revisá $LOG_DIR/watch.out"
      fi
    fi
  else
    log "CTFD_TOKEN o CTFD_URL no configurados: watcher no arranca."
    log "Para habilitar la promoción automática, editá config.env con:"
    log "  CTFD_URL=http://<ip-ctfd>:8000"
    log "  CTFD_TOKEN=<token-admin-ctfd>"
    log "  Luego: sudo systemctl restart ctf-tarreo"
  fi
  log "=== autostart.sh completado (team-vm) ==="
  exit 0
fi

die "VM_MODE='$VM_MODE' no reconocido. Usá 'central' o 'team-vm' en config.env."
