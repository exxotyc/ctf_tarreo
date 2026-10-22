#!/usr/bin/env bash
# ============================================================
#  firewall_isolation.sh — aísla el acceso de red entre equipos (single-host)
# ------------------------------------------------------------
#  Garantiza que cada equipo SOLO pueda alcanzar los puertos de SUS contenedores
#  y no los de los demás. Equivalente, en un solo host, a las reglas de OPNsense
#  de la Propuesta 2.
#
#  Mecanismo: cadena iptables DOCKER-USER (el punto soportado por Docker para
#  filtrar tráfico hacia contenedores publicados). Se matchea por:
#    - IP de origen del equipo (TEAM<N>_IP en config.env), y
#    - puerto ORIGINAL de destino (--ctorigdstport), que conserva el puerto
#      publicado en el host pese al DNAT de Docker.
#  Regla por puerto P (dueño = equipo T): DROP a conexiones NUEVAS cuyo origen
#  NO sea la IP de T. CTFd (:CTFD_PORT) queda abierto a todos.
#
#  Puertos por equipo T: PORT_BASE+lvl*100+T (lvl 1..5) + SMB_BIND_BASE+500+T.
#
#  Uso (requiere root):
#     sudo ./firewall_isolation.sh apply     # aplica las reglas (idempotente)
#     sudo ./firewall_isolation.sh clear      # las quita
#     ./firewall_isolation.sh status          # muestra las reglas activas
#     ./firewall_isolation.sh print           # imprime lo que aplicaría (dry-run, sin root)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

CHAIN="CTF-ISO"                 # nuestra cadena propia, colgada de DOCKER-USER
ACTION="${1:-}"
IPT="iptables"

team_ip() { local v="TEAM${1}_IP"; echo "${!v:-}"; }

# Lista de "puerto owner_team" para todos los equipos
port_owners() {
  local T L p
  for T in $(seq 1 "$NUM_TEAMS"); do
    for L in $(seq 1 "$NUM_LEVELS"); do
      p=$(( PORT_BASE + L*100 + T )); echo "$p $T"
    done
    # samba bind-shell (lvl5)
    echo "$(( SMB_BIND_BASE + 500 + T )) $T"
  done
}

build_rules() {
  # imprime los comandos iptables (sin "iptables" delante) a aplicar en CHAIN
  local p T ip
  while read -r p T; do
    ip="$(team_ip "$T")"
    [[ -z "$ip" ]] && continue   # equipo sin IP => no se restringe su puerto
    # Bloquea conexiones NUEVAS a este puerto desde cualquier origen != dueño
    echo "-A $CHAIN -m conntrack --ctstate NEW --ctdir ORIGINAL --ctorigdstport $p ! -s $ip -j DROP"
  done < <(port_owners)
}

require_root() { [[ "$(id -u)" -eq 0 ]] || { echo "[-] 'apply'/'clear' requieren root (usa sudo)"; exit 1; }; }

ensure_hook() {
  # DOCKER-USER debe existir (lo crea Docker). Insertamos el salto a CHAIN una vez.
  $IPT -nL DOCKER-USER >/dev/null 2>&1 || { echo "[-] No existe la cadena DOCKER-USER (¿Docker instalado/activo?)"; exit 1; }
  $IPT -nL "$CHAIN" >/dev/null 2>&1 || $IPT -N "$CHAIN"
  $IPT -C DOCKER-USER -j "$CHAIN" 2>/dev/null || $IPT -I DOCKER-USER 1 -j "$CHAIN"
}

case "$ACTION" in
  apply)
    require_root; ensure_hook
    $IPT -F "$CHAIN"                       # idempotente: limpia y repuebla
    n=0
    while read -r rule; do
      # shellcheck disable=SC2086
      $IPT $rule; n=$((n+1))
    done < <(build_rules)
    echo "[+] Aislamiento aplicado: $n reglas en $CHAIN (CTFd :$CTFD_PORT abierto a todos)."
    echo "    Equipos con IP definida:"
    for T in $(seq 1 "$NUM_TEAMS"); do ip="$(team_ip "$T")"; printf "      team%s -> %s\n" "$T" "${ip:-<SIN IP: puertos no restringidos>}"; done
    ;;
  clear)
    require_root
    $IPT -C DOCKER-USER -j "$CHAIN" 2>/dev/null && $IPT -D DOCKER-USER -j "$CHAIN" || true
    $IPT -F "$CHAIN" 2>/dev/null || true
    $IPT -X "$CHAIN" 2>/dev/null || true
    echo "[+] Aislamiento retirado."
    ;;
  status)
    ${IPT} -nL "$CHAIN" --line-numbers 2>/dev/null || echo "(cadena $CHAIN no existe; aislamiento no aplicado)"
    ;;
  print)
    echo "# Reglas que aplicaría (dry-run). CTFd :$CTFD_PORT NO se toca (abierto)."
    echo "# iptables -N $CHAIN ; iptables -I DOCKER-USER 1 -j $CHAIN"
    build_rules | sed 's/^/iptables /'
    ;;
  *)
    echo "Uso: $0 {apply|clear|status|print}   (apply/clear requieren sudo)"; exit 2;;
esac
