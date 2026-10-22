#!/usr/bin/env bash
# ============================================================
#  block_ai_egress.sh — bloquea/alerta acceso a servicios de IA
# ------------------------------------------------------------
#  REQUISITO CLAVE: solo funciona si el DNS de los participantes es ESTE host
#  (dnsmasq local como resolver del evento). Si usan DNS propio, DoH, VPN o
#  datos móviles, lo esquivan -> es un DISUASIVO, no una garantía. Combínalo
#  con proctoring y con bloquear por firewall los resolvers DoH conocidos.
#
#  Método: sinkhole DNS con dnsmasq -> cada dominio de monitoring/ai-domains.txt
#  resuelve a 0.0.0.0 (y ::). Genera /etc/dnsmasq.d/ctf-ai-block.conf.
#
#  Uso (apply/clear requieren root):
#     sudo ./block_ai_egress.sh apply     # instala el sinkhole y recarga dnsmasq
#     sudo ./block_ai_egress.sh clear      # lo quita
#     ./block_ai_egress.sh print           # dry-run: muestra la config (sin root)
#     ./block_ai_egress.sh test <dominio>  # comprueba si resuelve a sinkhole
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
LIST="$BASE/monitoring/ai-domains.txt"
OUT="/etc/dnsmasq.d/ctf-ai-block.conf"

ACTION="${1:-}"

gen() {
  echo "# Generado por block_ai_egress.sh — sinkhole de dominios de IA (CTF Tarreo)"
  grep -vE '^\s*(#|$)' "$LIST" | while read -r d; do
    d="$(echo "$d" | tr -d '[:space:]')"
    [[ -z "$d" ]] && continue
    echo "address=/${d}/0.0.0.0"
    echo "address=/${d}/::"
  done
}

reload_dnsmasq() {
  if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    systemctl reload dnsmasq 2>/dev/null || systemctl restart dnsmasq
  else
    echo "[!] dnsmasq no está activo. Instálalo/activa y asegúrate de que los"
    echo "    participantes usen ESTE host como DNS (DHCP option 6)."
  fi
}

require_root() { [[ "$(id -u)" -eq 0 ]] || { echo "[-] 'apply'/'clear' requieren root (sudo)"; exit 1; }; }

case "$ACTION" in
  apply)
    require_root
    [[ -f "$LIST" ]] || { echo "[-] falta $LIST"; exit 1; }
    mkdir -p /etc/dnsmasq.d
    gen > "$OUT"
    n=$(grep -c '^address=' "$OUT" || true)
    echo "[+] Escrito $OUT ($n entradas)."
    reload_dnsmasq
    echo "[+] Sinkhole activo. Recuerda: el DHCP del evento debe entregar este host como DNS."
    ;;
  clear)
    require_root
    rm -f "$OUT" && echo "[+] Eliminado $OUT"
    reload_dnsmasq
    ;;
  print)
    gen
    ;;
  test)
    dom="${2:?Uso: $0 test <dominio>}"
    echo "Resolviendo $dom ..."; getent hosts "$dom" || echo "(sin resolución)"
    echo "(si apunta a 0.0.0.0 / :: => bloqueado por el sinkhole)"
    ;;
  *)
    echo "Uso: $0 {apply|clear|print|test <dominio>}   (apply/clear con sudo)"; exit 2;;
esac
