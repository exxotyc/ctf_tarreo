#!/usr/bin/env bash
# ============================================================
#  deploy_target.sh <equipo> <nivel>
# ------------------------------------------------------------
#  Despliega el nivel de un equipo EN DONDE CORRESPONDA:
#    - DEPLOY_MODE=local  (o sin TEAM<N>_HOST)  -> deploy_level.sh local.
#    - DEPLOY_MODE=ssh y TEAM<N>_HOST definido  -> SSH por la red de gestión (OOB)
#      a la VM del equipo y ejecuta allí REMOTE_BASE/scripts/deploy_level.sh.
#
#  Lo usan watch_and_promote.py y start_all_level1.sh para que la
#  centralización (CTFd + watcher en Gestión, targets en VLAN 250) sea
#  transparente. NO expone el socket de Docker: solo SSH.
#
#  Uso:  ./deploy_target.sh 3 2
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

T="${1:?Uso: $0 <equipo> <nivel>}"; L="${2:?Uso: $0 <equipo> <nivel>}"

# Host remoto de este equipo (si lo hay)
hostvar="TEAM${T}_HOST"
HOST="${!hostvar:-}"

if [[ "$DEPLOY_MODE" == "ssh" && -n "$HOST" ]]; then
  echo "[*] team${T} lvl${L} -> SSH ${SSH_USER}@${HOST} (OOB)"
  KEYOPT=""; [[ -n "$SSH_KEY" ]] && KEYOPT="-i $SSH_KEY"
  # shellcheck disable=SC2086
  ssh $SSH_OPTS $KEYOPT "${SSH_USER}@${HOST}" \
    "cd '${REMOTE_BASE}' && scripts/deploy_level.sh ${T} ${L}"
else
  # local (una sola máquina, o equipo sin host remoto configurado)
  "$SCRIPT_DIR/deploy_level.sh" "$T" "$L"
fi
