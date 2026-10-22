#!/usr/bin/env python3
# ============================================================
#  watch_and_promote.py — polling a la API de CTFd; cuando un equipo
#  resuelve el nivel L, despliega automáticamente su nivel L+1.
# ------------------------------------------------------------
#  Identificación robusta: cada flag es ÚNICA por equipo+nivel, así que
#  el valor enviado (campo 'provided' de la submission correcta) determina
#  exactamente qué equipo resolvió qué nivel — sin depender del modo
#  users/teams de CTFd.
#
#  - Promueve team N al nivel L+1 salvo que L==5 o L+1 ya esté desplegado.
#  - Loguea todo (equipo, nivel, timestamp) -> logs/promotions.log
#    y el primer resuelto de cada nivel -> logs/firstblood.log
#  - Idempotente: relee submissions desde el inicio; nunca promueve dos veces.
#
#  Uso (segundo plano):
#    nohup python3 watch_and_promote.py >> ../logs/watch.out 2>&1 &
# ============================================================
import os
import sys
import time
import subprocess
from datetime import datetime
from ctf_common import load_config, CTFd, BASE, read_flag

HERE = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(BASE, "logs")
os.makedirs(LOG_DIR, exist_ok=True)
PROMO_LOG = os.path.join(LOG_DIR, "promotions.log")
FB_LOG = os.path.join(LOG_DIR, "firstblood.log")
DEPLOY = os.path.join(HERE, "deploy_level.sh")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "7"))


def ts():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log(path, msg):
    line = "[%s] %s" % (ts(), msg)
    print(line, flush=True)
    with open(path, "a") as f:
        f.write(line + "\n")


def build_flag_map(cfg):
    """valor_flag -> (team, level)"""
    m = {}
    for t in range(1, cfg["NUM_TEAMS"] + 1):
        for l in range(1, cfg["NUM_LEVELS"] + 1):
            try:
                m[read_flag(t, l)] = (t, l)
            except FileNotFoundError:
                pass
    return m


def deploy(team, lvl):
    log(PROMO_LOG, "Desplegando team%d nivel%d ..." % (team, lvl))
    r = subprocess.run(["bash", DEPLOY, str(team), str(lvl)],
                       capture_output=True, text=True)
    if r.returncode == 0:
        log(PROMO_LOG, "OK team%d nivel%d desplegado." % (team, lvl))
    else:
        log(PROMO_LOG, "ERROR team%d nivel%d: %s" % (team, lvl, r.stderr.strip()[:300]))


def fetch_correct(api):
    """Todas las submissions correctas (paginado)."""
    out, page = [], 1
    while True:
        res = api.get("/api/v1/submissions?type=correct&per_page=100&page=%d" % page)
        data = res.get("data", [])
        out.extend(data)
        meta = res.get("meta", {}).get("pagination", {})
        if not data or page >= meta.get("pages", page):
            break
        page += 1
    return out


def main():
    cfg = load_config()
    api = CTFd(cfg["CTFD_URL"], cfg["CTFD_TOKEN"])
    flag_map = build_flag_map(cfg)

    promoted = set()      # (team, lvl_resuelto) ya promovidos a lvl+1
    firstblood = set()    # niveles con primer resuelto ya logueado

    log(PROMO_LOG, "watch_and_promote iniciado (poll=%ds, teams=%d)."
        % (POLL_SECONDS, cfg["NUM_TEAMS"]))

    while True:
        try:
            for sub in fetch_correct(api):
                provided = (sub.get("provided") or "").strip()
                hit = flag_map.get(provided)
                if not hit:
                    continue  # flag no reconocida (p.ej. de otro origen)
                team, lvl = hit

                # First blood por nivel
                if lvl not in firstblood:
                    firstblood.add(lvl)
                    log(FB_LOG, "FIRST BLOOD nivel%d -> team%d" % (lvl, team))

                # Promoción L -> L+1
                if lvl >= cfg["NUM_LEVELS"]:
                    continue
                key = (team, lvl)
                if key in promoted:
                    continue
                promoted.add(key)
                log(PROMO_LOG, "team%d resolvió nivel%d -> promoviendo a nivel%d"
                    % (team, lvl, lvl + 1))
                deploy(team, lvl + 1)
        except Exception as e:  # red/CTFd caído: reintentar
            log(PROMO_LOG, "WARN: %s" % str(e)[:300])
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n[*] detenido.")
