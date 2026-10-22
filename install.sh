#!/usr/bin/env bash
# ============================================================
#  install.sh — Prepara una VM nueva para ctf-tarreo
# ------------------------------------------------------------
#  Instala dependencias, clona el repo (o usa el directorio actual),
#  crea config.env, instala el servicio systemd para auto-arranque.
#
#  Uso en VM nueva:
#    git clone https://github.com/exxotyc/ctf_tarreo.git ~/ctf-tarreo
#    cd ~/ctf-tarreo && bash install.sh
#
#  Uso desde el repo ya clonado (ej. esta misma carpeta):
#    bash install.sh
#
#  Requiere: Debian/Ubuntu, acceso sudo.
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="$REPO_DIR/systemd"
SERVICE_NAME="ctf-tarreo"
CURRENT_USER="$(id -un)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }
step() { echo; echo -e "${YELLOW}========================================${NC}"; echo "  $*"; echo -e "${YELLOW}========================================${NC}"; }

# ---- Verificar que no corremos como root ----
[[ "$(id -u)" -eq 0 ]] && err "No ejecutar como root. Usá el usuario normal con sudo disponible."

# ---- 1. Docker ----
step "1/5  Docker"
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  ok "Docker y Compose v2 ya instalados."
else
  warn "Instalando Docker CE + Compose plugin..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  ok "Docker instalado."
fi

# Agregar usuario al grupo docker (evita sudo en cada comando)
if ! groups "$CURRENT_USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$CURRENT_USER"
  warn "Usuario '$CURRENT_USER' agregado al grupo 'docker'."
  warn "IMPORTANTE: cerrar sesión y volver a entrar (o ejecutar 'newgrp docker') para que el cambio tome efecto."
  warn "Luego volver a ejecutar este script si algo falla por permisos de Docker."
fi

# ---- 2. Python3 + requests ----
step "2/5  Python3 + requests"
if ! command -v python3 &>/dev/null; then
  sudo apt-get install -y -qq python3 python3-pip
fi
if ! python3 -c 'import requests' 2>/dev/null; then
  pip3 install --quiet requests 2>/dev/null || sudo apt-get install -y -qq python3-requests
fi
ok "Python3 + requests OK"

# ---- 3. config.env ----
step "3/5  Configuración inicial"
if [[ ! -f "$REPO_DIR/config.env" ]]; then
  cp "$REPO_DIR/config.env.example" "$REPO_DIR/config.env"
  ok "Creé config.env desde config.env.example."
  warn "EDITÁ config.env antes de continuar:"
  echo "  VM_MODE=central       -> esta VM tiene CTFd + todos los equipos"
  echo "  VM_MODE=team-vm       -> esta VM es de un equipo (challenges solamente)"
  echo "  TEAM_ID=1             -> número de equipo (solo para VM_MODE=team-vm)"
  echo "  SERVER_IP=<ip>        -> IP de esta VM en la red del evento"
  echo "  CTFD_URL=http://...   -> URL de CTFd (si es externo)"
else
  ok "config.env ya existe, no se sobreescribe."
fi

# ---- 4. Servicio systemd ----
step "4/5  Servicio systemd (auto-arranque)"
mkdir -p "$SYSTEMD_DIR"

SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=CTF Tarreo — auto-arranque de contenedores y servicios
Documentation=file://${REPO_DIR}/README.md
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=${CURRENT_USER}
WorkingDirectory=${REPO_DIR}
ExecStart=${REPO_DIR}/scripts/autostart.sh
ExecStop=${REPO_DIR}/scripts/teardown.sh --all
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ctf-tarreo

[Install]
WantedBy=multi-user.target
EOF
ok "Archivo de servicio generado: $SERVICE_FILE"

# Instalar el servicio en systemd
sudo cp "$SERVICE_FILE" "/etc/systemd/system/$SERVICE_NAME.service"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME.service"
ok "Servicio '$SERVICE_NAME' habilitado para arrancar con el sistema."

# ---- 5. Permisos de ejecución ----
step "5/5  Permisos de scripts"
chmod +x "$REPO_DIR/bootstrap.sh" \
         "$REPO_DIR/configure-vm.sh" \
         "$REPO_DIR/scripts/"*.sh \
         "$REPO_DIR/scripts/"*.py 2>/dev/null || true
ok "Permisos OK"

# ---- Resumen ----
echo
echo -e "${GREEN}========================================"
echo "  INSTALACIÓN COMPLETA"
echo -e "========================================${NC}"
echo
echo "  Repo:     $REPO_DIR"
echo "  Config:   $REPO_DIR/config.env"
echo "  Servicio: /etc/systemd/system/$SERVICE_NAME.service"
echo
echo "Próximos pasos:"
echo "  1. Editá config.env con tu VM_MODE, SERVER_IP, etc."
echo "  2. Si VM_MODE=central, cloná CTFd:"
echo "       git clone https://github.com/CTFd/CTFd.git ~/CTFd"
echo "       (y ajustá CTFD_REPO en config.env)"
echo "  3. Para iniciar manualmente ahora:"
echo "       sudo systemctl start $SERVICE_NAME"
echo "     O directamente:"
echo "       ./bootstrap.sh"
echo
echo "  Para clonar esta VM para otros equipos:"
echo "       ./configure-vm.sh   (en cada VM clonada)"
echo
if ! groups "$CURRENT_USER" | grep -q '\bdocker\b'; then
  echo -e "${YELLOW}  RECORDÁ: cerrá sesión y volvé a entrar para aplicar el grupo docker.${NC}"
fi
