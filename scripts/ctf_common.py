"""
ctf_common.py — utilidades compartidas por seed_ctfd.py y watch_and_promote.py
"""
import os
import subprocess
import sys
import urllib.request
import urllib.error
import json

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
CONFIG = os.path.join(BASE, "config.env")

# Niveles: (id, nombre_carpeta, etiqueta_corta, puerto_interno, esquema)
LEVELS = [
    (1, "lvl1-apache-druid", "Apache Druid (CVE-2021-25646) — RCE",    8888, "http"),
    (2, "lvl2-tomcat",       "Apache Tomcat (CVE-2017-12615) — RCE",   8080, "http"),
    (3, "lvl3-glassfish",    "GlassFish (CVE-2017-1000028) — LFI",     4848, "https"),
    (4, "lvl4-php2shell-ctf","php2shell — session poison -> LFI -> RCE",80,  "http"),
    (5, "lvl5-samba",        "Samba (CVE-2017-7494) — RCE",            445,  "smb"),
]
POINTS = {1: 100, 2: 150, 3: 200, 4: 250, 5: 300}


def load_config():
    """Sourcea config.env en bash y devuelve las variables resueltas."""
    keys = ["NUM_TEAMS", "NUM_LEVELS", "CTFD_URL", "CTFD_TOKEN",
            "PORT_BASE", "SMB_BIND_BASE", "SERVER_IP", "VM_MODE", "TEAM_ID"]
    cmd = "source '%s' && for k in %s; do printf '%%s=%%s\\0' \"$k\" \"${!k}\"; done" % (
        CONFIG, " ".join(keys))
    out = subprocess.check_output(["bash", "-c", cmd])
    cfg = {}
    for item in out.split(b"\0"):
        if not item:
            continue
        k, _, v = item.decode().partition("=")
        cfg[k] = v
    # permitir override por entorno (p.ej. CTFD_TOKEN exportado)
    for k in keys:
        if os.environ.get(k):
            cfg[k] = os.environ[k]
    cfg["NUM_TEAMS"] = int(cfg["NUM_TEAMS"])
    cfg["NUM_LEVELS"] = int(cfg["NUM_LEVELS"])
    cfg["PORT_BASE"] = int(cfg["PORT_BASE"])
    cfg["SMB_BIND_BASE"] = int(cfg["SMB_BIND_BASE"])
    cfg.setdefault("VM_MODE", "central")
    cfg.setdefault("TEAM_ID", "")
    return cfg


def host_port(cfg, team, lvl):
    return cfg["PORT_BASE"] + lvl * 100 + team


def bind_port(cfg, team, lvl):
    return cfg["SMB_BIND_BASE"] + lvl * 100 + team


def read_flag(team, lvl):
    p = os.path.join(BASE, "flags", "team%d" % team, "lvl%d" % lvl, "flag.txt")
    with open(p) as f:
        return f.read().strip()


class CTFd:
    def __init__(self, url, token):
        self.url = url.rstrip("/")
        self.token = token
        if not token:
            sys.exit("[-] CTFD_TOKEN vacío. Genera el token admin en CTFd "
                     "(Settings -> Access Tokens) y ponlo en config.env.")

    def _req(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url + path, data=data, method=method)
        req.add_header("Authorization", "Token " + self.token)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                raw = r.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raise RuntimeError("HTTP %s en %s %s: %s" %
                               (e.code, method, path, e.read().decode()[:300]))

    def get(self, path):
        return self._req("GET", path)

    def post(self, path, body):
        return self._req("POST", path, body)
