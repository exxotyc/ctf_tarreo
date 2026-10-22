#!/usr/bin/env python3
# ============================================================
#  seed_ctfd.py — crea los 5 challenges en CTFd vía API REST.
# ------------------------------------------------------------
#  - 1 challenge por nivel, puntaje 100/150/200/250/300.
#  - Descripción con instrucciones de conexión y tabla de puertos por equipo.
#  - Carga TODAS las flags válidas (una por equipo) leídas de
#    flags/team<N>/lvl<L>/flag.txt  (cada una como flag estática).
#  - Idempotente: no duplica challenges ni flags ya existentes.
#
#  Requisitos:
#    1) CTFd corriendo (start_ctfd.sh) y setup inicial completado.
#    2) CTFD_TOKEN en config.env (o exportado en el entorno).
#
#  Cómo generar el token admin la PRIMERA vez:
#    - Abre http://127.0.0.1:8000, completa el setup (crea admin).
#    - Admin -> Settings -> Access Tokens -> Generate Token.
#    - Pega el valor en config.env:  CTFD_TOKEN="ctfd_xxx..."
#
#  Uso:  python3 seed_ctfd.py
# ============================================================
import sys
from ctf_common import load_config, CTFd, LEVELS, POINTS, host_port, bind_port, read_flag


def build_description(cfg, lvl_id, label, internal_port, scheme):
    nt = cfg["NUM_TEAMS"]
    ip = cfg["SERVER_IP"]
    lines = []
    lines.append("**%s**" % label)
    lines.append("")
    lines.append("La flag está en `/flag.txt` dentro del contenedor. "
                 "Solo se obtiene explotando el reto (no hay ruta HTTP directa).")
    lines.append("")
    if scheme == "https":
        lines.append("> Nota: el servicio usa **HTTPS** con certificado autofirmado "
                     "(usa `-k` / `verify=False`).")
    if scheme == "smb":
        lines.append("> Servicio **SMB** (puerto 445). El share escribible es `myshare` "
                     "(`/home/share`). Puerto extra por equipo = **bind-shell 6699**.")
    lines.append("")
    lines.append("**Tu instancia (según tu número de equipo):**")
    lines.append("")
    lines.append("| Equipo | Conexión |")
    lines.append("|:------:|----------|")
    for t in range(1, nt + 1):
        hp = host_port(cfg, t, lvl_id)
        if scheme == "smb":
            conn = "`%s` (SMB :%d · bind :%d)" % (ip, hp, bind_port(cfg, t, lvl_id))
        else:
            conn = "%s://%s:%d" % (scheme, ip, hp)
        lines.append("| %d | %s |" % (t, conn))
    lines.append("")
    lines.append("_Cada equipo resuelve contra SU propia instancia; todas comparten la "
                 "misma flag-list en CTFd pero el valor correcto es el de tu puerto._")
    return "\n".join(lines)


def main():
    cfg = load_config()
    api = CTFd(cfg["CTFD_URL"], cfg["CTFD_TOKEN"])

    # Challenges existentes por nombre -> id
    existing = {}
    for ch in api.get("/api/v1/challenges?view=admin").get("data", []):
        existing[ch["name"]] = ch["id"]

    for lvl_id, folder, label, internal_port, scheme in LEVELS:
        name = "Nivel %d — %s" % (lvl_id, label.split(" —")[0].split(" (")[0].strip())
        desc = build_description(cfg, lvl_id, label, internal_port, scheme)
        value = POINTS[lvl_id]

        if name in existing:
            chid = existing[name]
            print("[=] '%s' ya existe (id=%d), reuso." % (name, chid))
        else:
            ch = api.post("/api/v1/challenges", {
                "name": name,
                "category": "Nivel %d" % lvl_id,
                "description": desc,
                "value": value,
                "type": "standard",
                "state": "visible",
            })
            chid = ch["data"]["id"]
            print("[+] Creado '%s' (id=%d, %d pts)" % (name, chid, value))

        # Flags existentes de este challenge (contenidos)
        have = set()
        for fl in api.get("/api/v1/flags?view=admin").get("data", []):
            if fl.get("challenge_id") == chid:
                have.add(fl.get("content"))

        added = 0
        for t in range(1, cfg["NUM_TEAMS"] + 1):
            flag = read_flag(t, lvl_id)
            if flag in have:
                continue
            api.post("/api/v1/flags", {
                "challenge_id": chid,
                "content": flag,
                "type": "static",
                "data": "",
            })
            added += 1
        print("    flags: %d cargadas de %d equipos (%d nuevas)"
              % (len(have) + added, cfg["NUM_TEAMS"], added))

    print("[+] Seed completo.")


if __name__ == "__main__":
    sys.exit(main())
