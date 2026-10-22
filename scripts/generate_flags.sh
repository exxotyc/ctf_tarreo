#!/usr/bin/env bash
# ============================================================
#  generate_flags.sh — genera flags/team<N>/lvl<L>/flag.txt
# ============================================================
#  Formato:
#    lvl 1,2,3,5 :  FLAG{team<N>_lvl<L>_<8hex>}
#    lvl 4       :  php2shell{s3ss10n_p01s0n_t0_lf1_t0_rce_<8hex>}  (único por equipo)
#
#  Idempotente: NO sobrescribe una flag ya existente (para no invalidar
#  lo ya sembrado en CTFd). Usa --force para regenerar TODO desde cero.
#
#  Uso:  ./generate_flags.sh [--force]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

rand8() { openssl rand -hex 4; }   # 8 hex chars

echo "[*] Generando flags para NUM_TEAMS=$NUM_TEAMS, NUM_LEVELS=$NUM_LEVELS (force=$FORCE)"

for T in $(seq 1 "$NUM_TEAMS"); do
  for L in $(seq 1 "$NUM_LEVELS"); do
    dir="$BASE/flags/team${T}/lvl${L}"
    f="$dir/flag.txt"
    mkdir -p "$dir"

    if [[ -f "$f" && $FORCE -eq 0 ]]; then
      echo "    = team${T}/lvl${L}: ya existe, se conserva ($(cat "$f"))"
      continue
    fi

    h="$(rand8)"
    if [[ "$L" -eq 4 ]]; then
      flag="php2shell{s3ss10n_p01s0n_t0_lf1_t0_rce_${h}}"
    else
      flag="FLAG{team${T}_lvl${L}_${h}}"
    fi

    printf '%s\n' "$flag" > "$f"
    chmod 644 "$f"   # world-readable: el proceso del contenedor (root/www-data/nobody) debe poder leerlo tras explotar
    echo "    + team${T}/lvl${L}: $flag"
  done
done

echo "[+] Flags en $BASE/flags/"
