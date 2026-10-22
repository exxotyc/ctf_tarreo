#!/usr/bin/env bash
# ============================================================
#  configure-vm.sh — Configurar una VM después de clonarla
# ------------------------------------------------------------
#  Correr esto en cada VM replicada para personalizar:
#    - Número de equipo (TEAM_ID)
#    - IP de esta VM (SERVER_IP)
#    - URL de CTFd si está en otra máquina
#    - Modo de VM (team-vm = solo challenges, central = todo)
#
#  Uso: ./configure-vm.sh
#       ./configure-vm.sh --team 3 --ip 10.10.0.3  (no interactivo)
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$REPO_DIR/config.env"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
ask()  { echo -en "${CYAN}[?]${NC} $*"; }

# ---- Parsear args opcionales ----
TEAM_ARG=""
IP_ARG=""
CTFD_ARG=""
MODE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) TEAM_ARG="$2"; shift 2 ;;
    --ip)   IP_ARG="$2";   shift 2 ;;
    --ctfd) CTFD_ARG="$2"; shift 2 ;;
    --mode) MODE_ARG="$2"; shift 2 ;;
    *) echo "Uso: $0 [--team N] [--ip IP] [--ctfd URL] [--mode central|team-vm]"; exit 1 ;;
  esac
done

# ---- Verificar que config.env existe ----
if [[ ! -f "$CONFIG" ]]; then
  if [[ -f "$REPO_DIR/config.env.example" ]]; then
    cp "$REPO_DIR/config.env.example" "$CONFIG"
    ok "Creé config.env desde config.env.example."
  else
    echo "[-] No se encuentra config.env. Ejecutá primero: ./install.sh"; exit 1
  fi
fi

echo
echo "==================================================="
echo "  CTF Tarreo — Configuración de VM"
echo "==================================================="
echo

# ---- Modo de VM ----
if [[ -n "$MODE_ARG" ]]; then
  VM_MODE="$MODE_ARG"
else
  ask "Modo de esta VM:\n  1) team-vm  = VM de equipo (solo challenges de un equipo)\n  2) central  = máquina central (CTFd + todos los equipos)\nOpción [1]: "
  read -r mode_choice
  case "${mode_choice:-1}" in
    1|"team-vm") VM_MODE="team-vm" ;;
    2|"central") VM_MODE="central" ;;
    *) VM_MODE="team-vm" ;;
  esac
fi
ok "Modo: $VM_MODE"

# ---- TEAM_ID (solo para team-vm) ----
TEAM_ID=""
if [[ "$VM_MODE" == "team-vm" ]]; then
  if [[ -n "$TEAM_ARG" ]]; then
    TEAM_ID="$TEAM_ARG"
  else
    ask "Número de equipo para esta VM (ej: 1, 2, 3...): "
    read -r TEAM_ID
  fi
  [[ "$TEAM_ID" =~ ^[0-9]+$ ]] || { echo "[-] Número de equipo inválido: $TEAM_ID"; exit 1; }
  ok "Equipo: $TEAM_ID"
fi

# ---- SERVER_IP ----
CURRENT_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"
if [[ -n "$IP_ARG" ]]; then
  SERVER_IP="$IP_ARG"
else
  ask "IP de esta VM en la red del evento [${CURRENT_IP}]: "
  read -r SERVER_IP
  SERVER_IP="${SERVER_IP:-$CURRENT_IP}"
fi
ok "SERVER_IP: $SERVER_IP"

# ---- CTFD_URL (si CTFd está en otra máquina) ----
CTFD_URL=""
if [[ "$VM_MODE" == "team-vm" ]]; then
  if [[ -n "$CTFD_ARG" ]]; then
    CTFD_URL="$CTFD_ARG"
  else
    ask "URL de CTFd (dejá vacío si aún no está configurado) [http://127.0.0.1:8000]: "
    read -r CTFD_URL
    CTFD_URL="${CTFD_URL:-http://127.0.0.1:8000}"
  fi
  ok "CTFD_URL: $CTFD_URL"
fi

# ---- Actualizar config.env ----
echo
ok "Actualizando config.env..."

# Función para set/replace una variable en config.env
set_var() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$CONFIG" 2>/dev/null; then
    # Reemplazar línea existente
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$CONFIG"
  elif grep -q "^#.*${key}" "$CONFIG" 2>/dev/null; then
    # Descomentar y poner el valor
    sed -i "s|^#.*${key}=.*|${key}=\"${val}\"|" "$CONFIG"
  else
    # Agregar al final
    echo "${key}=\"${val}\"" >> "$CONFIG"
  fi
}

set_var "VM_MODE"   "$VM_MODE"
set_var "SERVER_IP" "$SERVER_IP"
[[ -n "$TEAM_ID"  ]] && set_var "TEAM_ID"   "$TEAM_ID"
[[ -n "$CTFD_URL" ]] && set_var "CTFD_URL"  "$CTFD_URL"

ok "config.env actualizado."

# ---- Hostname (opcional) ----
if [[ "$VM_MODE" == "team-vm" && -n "$TEAM_ID" ]]; then
  NEW_HOSTNAME="ctf-team${TEAM_ID}"
  ask "¿Cambiar hostname a '${NEW_HOSTNAME}'? [s/N]: "
  read -r change_host
  if [[ "${change_host,,}" == "s" || "${change_host,,}" == "si" || "${change_host,,}" == "y" ]]; then
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    ok "Hostname cambiado a: $NEW_HOSTNAME"
  fi
fi

# ---- Reiniciar servicio si está instalado ----
if systemctl is-enabled ctf-tarreo.service &>/dev/null 2>&1; then
  ask "¿Reiniciar el servicio ctf-tarreo ahora? [S/n]: "
  read -r restart_choice
  if [[ "${restart_choice,,}" != "n" && "${restart_choice,,}" != "no" ]]; then
    sudo systemctl restart ctf-tarreo.service
    ok "Servicio reiniciado."
  fi
else
  warn "El servicio ctf-tarreo no está instalado todavía."
  warn "Ejecutá primero: ./install.sh"
fi

# ---- Resumen ----
echo
echo "==================================================="
echo "  CONFIGURACIÓN COMPLETA"
echo "==================================================="
echo "  config.env:  $CONFIG"
echo "  VM_MODE:     $VM_MODE"
[[ -n "$TEAM_ID"  ]] && echo "  TEAM_ID:     $TEAM_ID"
echo "  SERVER_IP:   $SERVER_IP"
[[ -n "$CTFD_URL" ]] && echo "  CTFD_URL:    $CTFD_URL"
echo
if [[ "$VM_MODE" == "team-vm" ]]; then
  echo "Esta VM levantará los challenges del equipo $TEAM_ID."
  echo "Para arrancar manualmente:"
  echo "  sudo systemctl start ctf-tarreo"
  echo "  # o:"
  echo "  scripts/autostart.sh"
  echo
  echo "Para integrar con CTFd (cuando esté listo):"
  echo "  Editá config.env: CTFD_URL=http://<ip-ctfd>:8000"
  echo "  Editá config.env: CTFD_TOKEN=<token-admin>"
  echo "  Luego: sudo systemctl restart ctf-tarreo"
else
  echo "Esta VM levantará CTFd + todos los equipos."
  echo "  Editá config.env: CTFD_REPO, NUM_TEAMS, CTFD_ADMIN_PASSWORD"
  echo "  Luego: ./bootstrap.sh   o   sudo systemctl start ctf-tarreo"
fi
