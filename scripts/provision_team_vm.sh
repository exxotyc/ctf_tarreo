#!/usr/bin/env bash
# ============================================================
#  provision_team_vm.sh <equipo>   (o sin args = todos los equipos con host)
# ------------------------------------------------------------
#  Prepara la VM de un equipo para el modo distribuido (Propuesta 2):
#  copia por SSH (red de gestión/OOB) a REMOTE_BASE el repo necesario para
#  desplegar niveles EN ESA VM:
#     scripts/  cves/  config.env   y   SOLO flags/team<N>/  (secreto por equipo).
#
#  Requisitos en la VM: Docker + Compose v2, python3+requests (para nada más
#  que deploy; el watcher y CTFd viven en la máquina central, NO aquí).
#  CTFd central tiene TODAS las flags (para validar); cada VM solo las suyas.
#
#  Uso:
#    ./provision_team_vm.sh 3        # aprovisiona la VM del equipo 3
#    ./provision_team_vm.sh          # todas las TEAM<N>_HOST definidas
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

provision_one() {
  local T="$1"
  local hostvar="TEAM${T}_HOST"; local HOST="${!hostvar:-}"
  if [[ -z "$HOST" ]]; then echo "[-] team${T}: sin TEAM${T}_HOST en config.env, salto."; return; fi
  echo "[*] Aprovisionando team${T} -> ${SSH_USER}@${HOST}:${REMOTE_BASE}"

  local KEYOPT=""; [[ -n "$SSH_KEY" ]] && KEYOPT="-i $SSH_KEY"
  # shellcheck disable=SC2086
  local SSHCMD="ssh $SSH_OPTS $KEYOPT"

  $SSHCMD "${SSH_USER}@${HOST}" "mkdir -p '${REMOTE_BASE}/flags'"

  # config.env SANEADO: la VM de equipo no necesita token ni password de CTFd.
  local TMPCFG; TMPCFG="$(mktemp)"
  sed -E -e 's|^CTFD_TOKEN=.*|CTFD_TOKEN=""|' \
         -e 's|^CTFD_ADMIN_PASSWORD=.*|CTFD_ADMIN_PASSWORD=""|' \
         "$BASE/config.env" > "$TMPCFG"

  # repo base (sin flags de otros equipos, sin estado runtime)
  rsync -az --delete -e "$SSHCMD" \
    --exclude 'flags/' --exclude 'instances/' --exclude 'logs/' \
    --exclude 'ctfd/' --exclude '.git/' \
    "$BASE/scripts" "$BASE/cves" \
    "${SSH_USER}@${HOST}:${REMOTE_BASE}/"
  rsync -az -e "$SSHCMD" "$TMPCFG" "${SSH_USER}@${HOST}:${REMOTE_BASE}/config.env"
  rm -f "$TMPCFG"
  # SOLO las flags de este equipo
  rsync -az --delete --relative -e "$SSHCMD" \
    "$BASE/./flags/team${T}" \
    "${SSH_USER}@${HOST}:${REMOTE_BASE}/"
  echo "[+] team${T} aprovisionado."
}

if [[ $# -ge 1 ]]; then
  provision_one "$1"
else
  for T in $(seq 1 "$NUM_TEAMS"); do provision_one "$T"; done
fi
