#!/usr/bin/env bash
# ============================================================
#  start_all_level1.sh — levanta el Nivel 1 de TODOS los equipos
#  (se corre al inicio del evento). Idempotente.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

echo "[*] Levantando Nivel 1 para $NUM_TEAMS equipos..."
for T in $(seq 1 "$NUM_TEAMS"); do
  "$SCRIPT_DIR/deploy_level.sh" "$T" 1
done
echo "[+] Nivel 1 arriba para todos los equipos."
echo "    Puertos: team<N> -> $((PORT_BASE + 100 + 1))..$((PORT_BASE + 100 + NUM_TEAMS))  (druid :8888)"
