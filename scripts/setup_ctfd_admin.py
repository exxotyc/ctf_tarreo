#!/usr/bin/env python3
# ============================================================
#  setup_ctfd_admin.py — completa el setup inicial de CTFd (crea el admin)
#  y genera un token de API, escribiéndolo en config.env (CTFD_TOKEN).
#
#  Idempotente:
#    - Si CTFd ya está configurado, no repite el setup.
#    - Si ya hay un CTFD_TOKEN válido en config.env, no crea otro.
#
#  Requiere: CTFd arriba (start_ctfd.sh) y el módulo 'requests'.
# ============================================================
import os
import re
import sys
import requests
from ctf_common import load_config, CONFIG

cfg = load_config()
B = cfg["CTFD_URL"].rstrip("/")
USER = cfg.get("CTFD_ADMIN_USER", "admin")
EMAIL = cfg.get("CTFD_ADMIN_EMAIL", "admin@ctf.local")
PASSWORD = cfg.get("CTFD_ADMIN_PASSWORD", "CtfTarreo2026!")
MODE = cfg.get("CTFD_USER_MODE", "users")

s = requests.Session()


def nonce(path):
    html = s.get(B + path, timeout=15).text
    m = (re.search(r"'csrfNonce':\s*\"([0-9a-f]+)\"", html)
         or re.search(r'name="nonce"\s+value="([0-9a-f]+)"', html))
    return m.group(1) if m else None


def token_works(tok):
    if not tok:
        return False
    try:
        r = requests.get(B + "/api/v1/users", timeout=10,
                         headers={"Authorization": "Token " + tok})
        return r.status_code == 200
    except Exception:
        return False


def write_token(tok):
    with open(CONFIG) as f:
        txt = f.read()
    if re.search(r'^CTFD_TOKEN=.*$', txt, flags=re.M):
        txt = re.sub(r'^CTFD_TOKEN=.*$', 'CTFD_TOKEN="%s"' % tok, txt, flags=re.M)
    else:
        txt += '\nCTFD_TOKEN="%s"\n' % tok
    with open(CONFIG, "w") as f:
        f.write(txt)


def main():
    # 0) ¿ya hay token válido?
    if token_works(cfg.get("CTFD_TOKEN")):
        print("[=] Ya existe un CTFD_TOKEN válido; no se crea otro.")
        return 0

    # 1) ¿CTFd ya configurado?
    r = s.get(B + "/setup", timeout=15, allow_redirects=False)
    configured = r.status_code in (301, 302) and "/setup" not in r.headers.get("Location", "")
    if configured:
        print("[=] CTFd ya estaba configurado; salto el setup.")
    else:
        n = nonce("/setup")
        if not n:
            sys.exit("[-] No pude obtener el nonce de /setup (¿CTFd arriba?).")
        data = {
            "ctf_name": "CTF Tarreo", "ctf_description": "CTF universitario - 5 niveles",
            "user_mode": MODE, "challenge_visibility": "private",
            "account_visibility": "public", "score_visibility": "public",
            "registration_visibility": "public", "verify_emails": "false", "team_size": "",
            "name": USER, "email": EMAIL, "password": PASSWORD,
            "ctf_theme": "core-beta", "theme_color": "", "start": "", "end": "",
            "nonce": n, "_submit": "Finish",
        }
        rr = s.post(B + "/setup", data=data, timeout=30, allow_redirects=True)
        print("[+] Setup CTFd -> %s (admin '%s')" % (rr.status_code, USER))

    # 2) login admin
    n = nonce("/login")
    if n:
        s.post(B + "/login", data={"name": USER, "password": PASSWORD, "nonce": n}, timeout=15)

    # 3) generar token
    n = nonce("/settings")
    tr = s.post(B + "/api/v1/tokens",
                headers={"CSRF-Token": n, "Content-Type": "application/json"},
                json={"expiration": None}, timeout=15)
    j = tr.json()
    val = j.get("data", {}).get("value")
    if not val:
        sys.exit("[-] No se obtuvo token: %s" % j)
    write_token(val)
    print("[+] Token de API generado y guardado en config.env.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
