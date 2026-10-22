#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  php2shell CTF Lab                                   ║"
echo "║  CVE-2026-109618 / CVE-2026-109619                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Load .env if present, otherwise use defaults
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    echo "[*] Loaded flag from .env"
else
    echo "[!] No .env found — using default flag. Copy .env.example to .env to set your own."
fi

echo "[*] Starting containers on port 80 (nginx+FPM) and 8080 (Apache)..."
docker compose up -d

echo "[*] Waiting for services..."
sleep 4

echo ""
echo "[*] Verifying..."
FPM=$(curl -sf http://127.0.0.1:80/index.php 2>/dev/null | head -1)
APACHE=$(curl -sf http://127.0.0.1:8080/index.php 2>/dev/null | head -1)
echo "  nginx+FPM : ${FPM:-FAILED}  →  http://127.0.0.1:80"
echo "  Apache    : ${APACHE:-FAILED}  →  http://127.0.0.1:8080"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Lab ready!                                          ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  nginx + PHP-FPM  →  http://127.0.0.1:80            ║"
echo "║    Chains: A (LFI), B (UAF), C (handler), E (OOM)   ║"
echo "║                                                      ║"
echo "║  Apache mod_php   →  http://127.0.0.1:8080           ║"
echo "║    Chains: A, D (OOM — zero conditions)              ║"
echo "║                                                      ║"
echo "║  Flag lives at /flag.txt inside each container       ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
