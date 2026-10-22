#!/usr/bin/env bash
# ============================================================
#  deploy_level.sh <equipo> <nivel>
# ------------------------------------------------------------
#  - Genera instances/team<N>/lvl<L>/docker-compose.yml parametrizado.
#  - Puerto host = PORT_BASE + (nivel*100) + equipo   (8101..8505)
#  - Monta flags/team<N>/lvl<L>/flag.txt -> /flag.txt:ro
#    (excepto lvl4 php2shell, que escribe /flag.txt vía env FLAG nativo).
#  - Levanta con proyecto team<N>_lvl<L> (aislado, red propia).
#  - Idempotente: 'docker compose up -d' se puede re-ejecutar sin romper nada.
#
#  Uso:  ./deploy_level.sh 1 1
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$BASE/config.env"

T="${1:-}"; L="${2:-}"
if [[ -z "$T" || -z "$L" ]]; then echo "Uso: $0 <equipo> <nivel>"; exit 2; fi
if (( T < 1 || T > NUM_TEAMS )); then echo "[-] equipo $T fuera de rango (1..$NUM_TEAMS)"; exit 2; fi
if (( L < 1 || L > NUM_LEVELS )); then echo "[-] nivel $L fuera de rango (1..$NUM_LEVELS)"; exit 2; fi

PROJ="team${T}_lvl${L}"
HOST_PORT=$(( PORT_BASE + L*100 + T ))
FLAG_FILE="$BASE/flags/team${T}/lvl${L}/flag.txt"
INST_DIR="$BASE/instances/team${T}/lvl${L}"
CVE_DIR=""
case "$L" in
  1) CVE_DIR="$BASE/cves/lvl1-apache-druid" ;;
  2) CVE_DIR="$BASE/cves/lvl2-tomcat" ;;
  3) CVE_DIR="$BASE/cves/lvl3-glassfish" ;;
  4) CVE_DIR="$BASE/cves/lvl4-php2shell-ctf" ;;
  5) CVE_DIR="$BASE/cves/lvl5-samba" ;;
esac

if [[ ! -f "$FLAG_FILE" ]]; then
  echo "[-] Falta $FLAG_FILE — ejecuta primero generate_flags.sh"; exit 1
fi
mkdir -p "$INST_DIR"
COMPOSE="$INST_DIR/docker-compose.yml"

# ------------------------------------------------------------
#  Generar el compose del nivel
# ------------------------------------------------------------
case "$L" in
  1)  # apache-druid CVE-2021-25646  (interno 8888, RCE como root)
    cat > "$COMPOSE" <<EOF
services:
  web:
    image: vulhub/apache-druid:0.20.0
    ports: ["${HOST_PORT}:8888"]
    volumes:
      - "${FLAG_FILE}:/flag.txt:ro"
    restart: unless-stopped
EOF
    ;;

  2)  # tomcat CVE-2017-12615/12617 PUT JSP RCE (interno 8080, proceso root)
      # EXCEPCIÓN de path: el webshell ejecuta con CWD=/usr/local/tomcat y la shell
      # queda confinada ahí, así que la flag se monta en ESE directorio (cat flag.txt).
    TOMCAT_IMG="ctf-tarreo-tomcat:lvl2"
    if ! docker image inspect "$TOMCAT_IMG" >/dev/null 2>&1; then
      echo "[*] Construyendo imagen $TOMCAT_IMG (una sola vez, compartida por todos los equipos)..."
      docker build -t "$TOMCAT_IMG" "$CVE_DIR"
    fi
    cat > "$COMPOSE" <<EOF
services:
  tomcat:
    image: ${TOMCAT_IMG}
    ports: ["${HOST_PORT}:8080"]
    volumes:
      - "${FLAG_FILE}:/usr/local/tomcat/flag.txt:ro"
    restart: unless-stopped
EOF
    ;;

  3)  # glassfish CVE-2017-1000028 LFI  (interno 4848 HTTPS, proceso root)
    cat > "$COMPOSE" <<EOF
services:
  glassfish:
    image: vulhub/glassfish:4.1
    ports: ["${HOST_PORT}:4848"]
    environment:
      - ADMIN_PASSWORD=vulhub_default_password
    volumes:
      - "${FLAG_FILE}:/flag.txt:ro"
    restart: unless-stopped
EOF
    ;;

  4)  # php2shell  (interno 80 nginx+fpm). Flag vía env FLAG nativo (no RO mount).
      # webroot/configs en :ro para aislar equipos (sesiones viven en /tmp del contenedor).
    FLAG_VALUE="$(cat "$FLAG_FILE")"
    cat > "$COMPOSE" <<EOF
services:
  php-fpm:
    image: php:8.2-fpm
    volumes:
      - "${CVE_DIR}/webroot:/var/www/html:ro"
      - "${CVE_DIR}/configs/php-fpm.ini:/usr/local/etc/php/php.ini:ro"
      - "${CVE_DIR}/configs/www.conf:/usr/local/etc/php-fpm.d/www.conf:ro"
    environment:
      - FLAG=${FLAG_VALUE}
    security_opt: [seccomp:unconfined]
    privileged: true
    command: >
      bash -c "mkdir -p /tmp/sessions && chmod 1777 /tmp/sessions &&
               echo \"\$\${FLAG}\" > /flag.txt && chmod 444 /flag.txt && php-fpm"
    restart: unless-stopped
  nginx:
    image: nginx:alpine
    ports: ["${HOST_PORT}:80"]
    volumes:
      - "${CVE_DIR}/webroot:/var/www/html:ro"
      - "${CVE_DIR}/configs/nginx.conf:/etc/nginx/conf.d/default.conf:ro"
    depends_on: [php-fpm]
    restart: unless-stopped
EOF
    ;;

  5)  # samba CVE-2017-7494  (interno 445 SMB + 6699 bind-shell, proceso root)
    BIND_PORT=$(( SMB_BIND_BASE + L*100 + T ))
    cat > "$COMPOSE" <<EOF
services:
  samba:
    image: vulhub/samba:4.6.3
    tty: true
    volumes:
      - "${CVE_DIR}/smb.conf:/usr/local/samba/etc/smb.conf:ro"
      - "${FLAG_FILE}:/flag.txt:ro"
    ports:
      - "${HOST_PORT}:445"
      - "${BIND_PORT}:6699"
    restart: unless-stopped
EOF
    ;;
esac

# ------------------------------------------------------------
#  Levantar (idempotente)
# ------------------------------------------------------------
echo "[*] team${T} nivel${L}  ->  proyecto=${PROJ}  puerto_host=${HOST_PORT}"
[[ "$L" -eq 5 ]] && echo "    (samba: SMB=${HOST_PORT}->445 , bind-shell=$((SMB_BIND_BASE + L*100 + T))->6699)"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "[DRY_RUN] compose generado en $COMPOSE (no se levanta nada)"; exit 0
fi
docker compose -p "$PROJ" -f "$COMPOSE" up -d

echo "[+] team${T} lvl${L} desplegado."
