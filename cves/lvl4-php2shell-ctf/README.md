# php2shell — CTF Lab

**CVE-2026-109618 / CVE-2026-109619** — PHP Pre-Auth RCE · Docker · CTFd-ready

Five independent RCE chains exploiting `session.upload_progress` and the Zend engine's OOM
bailout. PHP 5.4 through 8.5.11. No application vulnerability required for some chains.

---

## Quick Start

```bash
# 1. Clone and enter
git clone <repo> && cd php2shell-ctf

# 2. (Optional) set a custom flag
cp .env.example .env
vi .env          # edit FLAG=

# 3. Start (port 80 + 8080)
chmod +x start.sh && ./start.sh
```

That's it. The lab will be live at:

| Service | URL | Chains |
|---------|-----|--------|
| nginx + PHP-FPM | `http://127.0.0.1:80` | A, B, C, E |
| Apache mod_php | `http://127.0.0.1:8080` | A, D |

The flag lives at `/flag.txt` inside each container.

---

## Endpoints

| Path | Purpose | Chain |
|------|---------|-------|
| `/index.php` | Default — `session_start()` | — |
| `/nosession.php` | No session | — |
| `/vuln.php?page=FILE` | LFI sink — `include($page)` | A |
| `/app_serialize.php` | Sets `php_serialize` handler | C (polluter) |
| `/destruct_test.php` | `Evil` class + `session_start()` | C (trigger) |
| `/session_oom.php` | `session_start()` — OOM if session huge | E |
| `/fatal.php` | Allocates until OOM | D/E test |
| `/app/upload.php` | `.user.ini`: `php_serialize` handler | C |
| `/api/endpoint.php` | `.user.ini`: `php` handler + `Evil` class | C |

---

## Attack Chains

| Chain | Vector | Pre-auth | Extra conditions | SAPI |
|-------|--------|:--------:|-----------------|------|
| **A** | Session injection → LFI | Yes | App has any LFI sink | All |
| **B** | var_destroy UAF → handler overwrite | No | App calls `unserialize()` | All |
| **C** | Handler mismatch → `__destruct` | Yes | Two dirs, different `serialize_handler` | FPM |
| **D** | OOM corruption → stale `EG()` | Yes | **None** | mod_php |
| **E** | FPM session OOM → stale `BG()` | Yes | Any `session_start()` | FPM |

**Chain A** is the primary intended path for CTF players. Chain D is the most critical
real-world vector (zero-dependency, any Apache mod_php install).

---

## Chain A Walkthrough (primary)

```
session.upload_progress.enabled = On
  ↓
POST /index.php with PHP_SESSION_UPLOAD_PROGRESS=<?php system(...); ?>
  + Cookie: PHPSESSID=<controlled_id>
  ↓
/tmp/sessions/sess_<controlled_id> now contains the PHP payload
  ↓
GET /vuln.php?page=/tmp/sessions/sess_<controlled_id>&cmd=cat+/flag.txt
  ↓
RCE
```

```bash
python3 solution/solve_chain_a.py --host 127.0.0.1 --port 80 --cmd "cat /flag.txt"
```

---

## Connecting to CTFd

See [`ctfd/ctfd_import.md`](ctfd/ctfd_import.md) for three methods:
- Manual UI import
- `ctfd-cli`
- `ctfcli`

The challenge descriptor is in [`ctfd/challenge.yml`](ctfd/challenge.yml).
**Update the `flags:` field to match your `.env` flag before importing.**

---

## Port / environment customisation

| Variable | Default | Effect |
|----------|---------|--------|
| `FLAG` | `php2shell{s3ss10n_p01s0n_t0_lf1_t0_rce}` | Flag written to `/flag.txt` in each container |

To expose on a different port, edit the `ports:` lines in `docker-compose.yml`:
```yaml
ports: ["1337:80"]   # external:internal
```

---

## Cleanup

```bash
docker compose down -v
```

---

## Structure

```
php2shell-ctf/
├── docker-compose.yml      # nginx+FPM (port 80) + Apache (port 8080)
├── start.sh                # One-click start
├── .env.example            # FLAG variable template
├── configs/
│   ├── nginx.conf          # Reverse proxy → PHP-FPM
│   ├── php-fpm.ini         # upload_progress On, session path /tmp/sessions
│   ├── php-apache.ini      # memory_limit=32M for easy OOM (Chain D)
│   └── www.conf            # pm=static, max_children=1 (Chain E deterministic)
├── webroot/                # PHP app (generated at runtime by start.sh)
│   ├── index.php / vuln.php / destruct_test.php …
│   ├── app/                # php_serialize handler (.user.ini)
│   └── api/                # php handler + Evil class (.user.ini)
├── ctfd/
│   ├── challenge.yml       # CTFd challenge descriptor
│   └── ctfd_import.md      # Import instructions
└── solution/               # Admin-only solvers
    ├── solve_chain_a.py    # Session injection → LFI → RCE
    └── solve_chain_c.py    # Handler mismatch → __destruct → RCE
```

---

## Disclaimer

For **authorized security testing and educational purposes only**.

---

*Based on the php2shell research by [Qi Deng](https://github.com/ikow) — CVE-2026-109618 / CVE-2026-109619*
