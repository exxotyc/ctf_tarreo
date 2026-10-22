# CLAUDE.md — Contexto para Claude Code en el servidor del CTF

> Este archivo lo lee Claude Code automáticamente al abrirse en `~/ctf-tarreo`.
> También puedes pegar su contenido como primer prompt. Léelo entero antes de actuar.

## Qué es esto (contexto autorizado)

Infraestructura para un **CTF universitario autorizado** (evento educativo de seguridad,
estilo "tarreo"). Son 5 niveles secuenciales sobre **contenedores Docker deliberadamente
vulnerables** (imágenes vulhub + un reto php2shell ya armado). El objetivo es legítimo y
defensivo/educativo: montar, operar y verificar el entorno del evento. NO se ataca a
terceros; todo corre en esta PC/red aislada del evento contra instancias propias.

Trabajo siempre dentro de `~/ctf-tarreo`. No descargues material nuevo salvo que falte algo.

## Estado y arranque

**Un solo comando levanta todo (idempotente):**
```bash
cd ~/ctf-tarreo && ./bootstrap.sh
```
Hace: requisitos → flags → CTFd (:8000) → admin+token API → seed de 5 challenges →
Nivel 1 de todos los equipos → watcher de promoción automática.
Variantes: `--no-watch` (sin promotor), `--fresh` (regenera flags desde cero).

**Bajar todo:** `scripts/teardown.sh --all`  ·  **solo retos:** `scripts/teardown.sh`

## Arquitectura

- **Config central:** `config.env` (la sourcean todos los scripts). Variables clave:
  `NUM_TEAMS` (default 5, bajable el día del evento), `SERVER_IP` (IP del server en la red
  del evento — ponla real), `CTFD_REPO` (ruta del repo CTFd ya clonado), `CTFD_TOKEN`
  (lo genera el bootstrap), `CTFD_ADMIN_*` (credenciales admin).
- **Una instancia Docker aislada por equipo+nivel.** Proyecto compose = `team<N>_lvl<L>`
  (red propia, sin choques). Nunca comparten contenedor.
- **Puertos:** `HOST = 8000 + nivel*100 + equipo` → L1 8101-8105 … L5 8501-8505.
  Samba añade bind-shell `9000+500+equipo` → 9501-9505. CTFd en `:8000`.
- **Flags:** siempre en `/flag.txt` dentro del contenedor, solo accesible tras explotar.
  Niveles 1/2/3/5: `FLAG{team<N>_lvl<L>_<8hex>}` montada `:ro` desde
  `flags/team<N>/lvl<L>/flag.txt`. Nivel 4 (php2shell): `php2shell{...<8hex>}` única por
  equipo, inyectada por env `FLAG` (el contenedor escribe `/flag.txt` solo; NO se monta `:ro`).
- **Promoción:** `watch_and_promote.py` hace polling a CTFd; identifica equipo+nivel por el
  **valor de la flag enviada** (cada una es única) y despliega el nivel L+1 de ese equipo.
  Logs en `logs/promotions.log` y `logs/firstblood.log`.

### Niveles
| L | Carpeta `cves/` | Vuln | Tipo | Puerto interno |
|:-:|---|---|---|:-:|
| 1 | lvl1-apache-druid | CVE-2021-25646 (JS embebido) | RCE | 8888 http |
| 2 | lvl2-laravel | CVE-2021-3129 (Laravel Ignition 2.5.1) | RCE | 80 http |
| 3 | lvl3-glassfish | CVE-2017-1000028 (UTF-8 overlong → traversal) | LFI | 4848 **https** |
| 4 | lvl4-php2shell-ctf | session poisoning → LFI → RCE | RCE | 80 http (nginx+FPM) |
| 5 | lvl5-samba | CVE-2017-7494 (SambaCry) | RCE | 445 SMB + 6699 |

## Scripts (todos idempotentes)
- `bootstrap.sh` — arranque completo (ver arriba).
- `scripts/generate_flags.sh [--force]` — genera flags; no pisa las existentes salvo `--force`.
- `scripts/deploy_level.sh <eq> <lvl>` — genera el compose de esa instancia y la levanta.
  `DRY_RUN=1` solo renderiza el YAML sin levantar.
- `scripts/start_all_level1.sh` — Nivel 1 de todos los equipos.
- `scripts/start_ctfd.sh` — levanta CTFd desde `CTFD_REPO`.
- `scripts/setup_ctfd_admin.py` — crea admin y genera token API → `config.env`.
- `scripts/seed_ctfd.py` — crea 5 challenges (100/150/200/250/300) + todas las flags.
- `scripts/watch_and_promote.py` — promotor automático (correr en background).
- `scripts/teardown.sh [--ctfd|--all]` — baja y limpia (`down -v`).
- `scripts/ctf_common.py` — utilidades compartidas (carga config, cliente CTFd API).

## GOTCHAS verificados (importan para que el CTF sea justo)
1. **php2shell (lvl4):** PHP 8.2 rechaza `PHPSESSID` con `_` (solo `A-Za-z0-9-,`). El solver
   incluido usa `ctf_pwn_session_1337` (con `_`) y **falla**; hay que usar un ID alfanumérico
   (ej. `ctfpwn1337`) y mandar el campo `PHP_SESSION_UPLOAD_PROGRESS` **antes** del fichero
   en el multipart. Cadena verificada end-to-end.
2. **glassfish (lvl3):** es **HTTPS** en su puerto (usa `-k`/`verify=False`). `/flag.txt` en la
   raíz SÍ es alcanzable con el payload de 10×`../` (cada `../` = `%c0%ae%c0%ae/`); proceso root,
   flag `chmod 644`. No necesita excepción al path.
3. **samba (lvl5):** SMB no es HTTP. El `payload.c` incluido apunta a `172.17.0.1`: cada equipo
   debe recompilar su `.so` con SU IP (reverse) o usar bind-shell (`:950N`→6699). En una sola PC
   el SMB va en puertos altos (`:850N`), no 445 real por equipo.
4. **Offline:** durante la competencia NO hay internet. Las imágenes deben estar pre-cargadas
   (ver README §1.bis, `docker save`/`docker load`). El build de CTFd y el pull de
   `php:8.2-fpm`/`nginx:alpine` ocurren en el setup previo con red.

## Reglas de operación
- **Idempotencia primero:** si algo falla a mitad de evento, re-ejecuta el script; no está
  diseñado para romper lo que ya funciona. Prefiere `deploy_level.sh` / `bootstrap.sh` a
  comandos docker manuales.
- **No regenerar flags** con `--force` una vez sembrado CTFd (invalidaría lo enviado). 
- **No expongas el socket de Docker** a los contenedores. **No subas `config.env`** a un repo
  (tiene token y contraseña en claro).
- **Verificación antes de abrir al público:** sigue el checklist del `README.md` §4 (probar los
  5 exploits end-to-end contra el equipo 1 y confirmar que llegan a `/flag.txt`).
- Ante errores de browser/herramientas o complejidad inesperada, detente y pregunta en vez de
  insistir a ciegas.

## Diagnóstico rápido
```bash
docker ps --format '{{.Names}} {{.Status}} {{.Ports}}' | grep -E 'ctfd|team[0-9]'  # qué hay arriba
cat logs/promotions.log logs/firstblood.log                                        # promociones
pgrep -f watch_and_promote.py                                                      # watcher vivo?
DRY_RUN=1 scripts/deploy_level.sh 1 3 && cat instances/team1/lvl3/docker-compose.yml  # ver un compose
```

El detalle completo (orden del día del evento, tabla de puertos, checklist, portabilidad a
otro server) está en `README.md`.
