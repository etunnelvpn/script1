#!/usr/bin/env python3
"""
E-TUNNEL VPN — Quota & Expiry Checker
Runs every 2 min via systemd timer.
Removes V2Ray/Trojan accounts that are expired or over data quota.
Removes SSH accounts that are expired.
"""
import json, os, re, subprocess, datetime, fcntl, shutil

ACC_FILE    = "/etc/etunnel/accounts/v2ray.txt"
TROJAN_FILE = "/etc/etunnel/accounts/trojan.txt"
SSH_FILE    = "/etc/etunnel/accounts/ssh.txt"
XRAY_CONF   = "/usr/local/etc/xray/config.json"
LOG_FILE    = "/var/log/etunnel-quota.log"
LOCK_FILE   = "/var/run/etunnel-quota.lock"


def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except Exception:
        pass


def query_stats():
    try:
        r = subprocess.run(
            ["/usr/local/bin/xray", "api", "statsquery",
             "--server=127.0.0.1:10085", "-pattern", "user>>>", "-reset"],
            capture_output=True, text=True, timeout=15
        )
        if r.returncode != 0:
            return {}
        users = {}
        for block in re.split(r'stat:\s*[{<]', r.stdout):
            nm = re.search(r'name:\s*"user>>>(.+?)>>>traffic>>>(\w+)"', block)
            vm = re.search(r'value:\s*(\d+)', block)
            if nm and vm:
                users[nm.group(1)] = users.get(nm.group(1), 0) + int(vm.group(1))
        return users
    except Exception:
        return {}


def process_file(acc_file, deltas, today):
    if not os.path.exists(acc_file):
        return set()
    with open(acc_file) as f:
        lines = [l.strip() for l in f if l.strip()]
    if not lines:
        return set()
    remaining = []
    removed_keys = set()
    for line in lines:
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 7:
            remaining.append(line)
            continue
        name, key, expiry, gb, level, maxc, used = parts[:7]
        try:
            used = int(used) + int(deltas.get(name, 0))
        except ValueError:
            used = int(deltas.get(name, 0))
        expired = False
        try:
            if datetime.date.fromisoformat(expiry) < today:
                expired = True
        except Exception:
            pass
        over_quota = False
        try:
            gb_int = int(gb)
            if gb_int > 0 and used >= gb_int * 1073741824:
                over_quota = True
        except ValueError:
            pass
        if expired or over_quota:
            log(f"Removed {name} (expired={expired}, over_quota={over_quota})")
            removed_keys.add(key)
        else:
            remaining.append(f"{name} | {key} | {expiry} | {gb} | {level} | {maxc} | {used}")
    with open(acc_file, "w") as f:
        if remaining:
            f.write("\n".join(remaining) + "\n")
    return removed_keys


def expire_ssh(today):
    if not os.path.exists(SSH_FILE):
        return
    with open(SSH_FILE) as f:
        lines = [l.strip() for l in f if l.strip()]
    remaining = []
    for line in lines:
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3:
            remaining.append(line)
            continue
        user, _, expiry = parts[0], parts[1], parts[2]
        try:
            if datetime.date.fromisoformat(expiry) < today:
                subprocess.run(["userdel", "-r", user], capture_output=True)
                log(f"SSH expired removed: {user}")
                continue
        except Exception:
            pass
        remaining.append(line)
    with open(SSH_FILE, "w") as f:
        if remaining:
            f.write("\n".join(remaining) + "\n")


def restart_xray():
    if os.path.exists("/run/systemd/system"):
        subprocess.run(["systemctl", "restart", "xray"], timeout=30)
    else:
        subprocess.run(["rc-service", "xray", "restart"], timeout=30)


def apply_removals(v_removed, t_removed):
    if not v_removed and not t_removed:
        return False
    try:
        shutil.copy(XRAY_CONF, XRAY_CONF + ".bak-quota")
        with open(XRAY_CONF) as f:
            conf = json.load(f)
        for ib in conf.get("inbounds", []):
            proto = ib.get("protocol", "")
            s = ib.get("settings", {})
            if "clients" not in s:
                continue
            if proto in ("vless", "vmess"):
                s["clients"] = [c for c in s["clients"] if c.get("id") not in v_removed]
            elif proto == "trojan":
                s["clients"] = [c for c in s["clients"] if c.get("password") not in t_removed]
        with open(XRAY_CONF, "w") as f:
            json.dump(conf, f, indent=2)
        restart_xray()
        return True
    except Exception:
        return False


def main():
    if not any(os.path.exists(f) for f in [ACC_FILE, TROJAN_FILE, SSH_FILE]):
        return
    try:
        lock_fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception:
        return
    try:
        deltas = query_stats()
        today  = datetime.date.today()
        v = process_file(ACC_FILE,    deltas, today)
        t = process_file(TROJAN_FILE, deltas, today)
        if v or t:
            apply_removals(v, t)
        expire_ssh(today)
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        except Exception:
            pass


if __name__ == "__main__":
    main()
