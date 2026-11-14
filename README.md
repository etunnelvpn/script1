# E-TUNNEL VPN v1.0.0

**By EMMKASH TECH** · Telegram: [@emmkash](https://t.me/emmkash) · Contact: +254112735877

Multi-protocol VPN auto-installer for Ubuntu/Debian VPS.  
One command installs and configures everything: SSH, VLESS, VMESS, Trojan, OpenVPN, UDP.

---

## ⚡ Install — Run This One Command on Your VPS

```bash
curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel-v1.0.0.sh -o /tmp/etunnel.sh && bash /tmp/etunnel.sh
```

> Must be run as **root**. You will be asked to enter your domain name during setup.

**With domain pre-set (skips the prompt):**

```bash
curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel-v1.0.0.sh -o /tmp/etunnel.sh && bash /tmp/etunnel.sh yourdomain.com
```

---

## What the script does automatically

1. Clones this repo to `/tmp/etunnel-repo` on the VPS
2. Installs all required packages (nginx, haproxy, xray, dropbear, stunnel, openvpn, etc.)
3. Issues a Let's Encrypt SSL certificate for your domain
4. Deploys and starts all services
5. Sets your SSH login banner from `issue.net` in this repo
6. Opens the control panel — type `etunnel` anytime to reopen it

---

## Supported Systems

| OS | Version |
|---|---|
| Ubuntu | 24.04 ✅ |
| Ubuntu | 22.04 ✅ |
| Ubuntu | 20.04 ✅ |
| Ubuntu | 18.04 ✅ |
| Debian | 10 / 11 / 12 ✅ |

---

## What Gets Installed

| Component | Port | Details |
|---|---|---|
| SSH | 22 | Standard SSH |
| Dropbear SSH | 444 | Lightweight SSH |
| Stunnel → SSH | 8444 | SSH over TLS |
| HAProxy | 80 | Traffic router |
| Nginx Stream | 443 | TLS termination |
| Nginx HTTP/2 | 4443 | V2Ray proxy |
| Xray (VLESS/VMESS/Trojan) | 10086–10091 | WebSocket |
| Universal Bridge | 8080 | SSH + OpenVPN + WS |
| Rocket Proxy | 8081 | WebSocket → SSH |
| OpenVPN | 1194 | TCP mode |
| VPN Web Panel | 8090 | OpenVPN config manager |
| dnsmasq | 5353 | DNS wildcard |
| UDP Custom | — | UDP tunnel |
| fail2ban | — | SSH brute-force protection |

---

## Control Panel

After install, open the panel anytime:

```bash
etunnel
```

**What you can do from the panel:**

| Menu | Action |
|---|---|
| 01 SSH MENU | Create / delete SSH accounts, set device limit, unsuspend |
| 02 VMESS MENU | Create / delete VMESS accounts + connection links |
| 03 VLESS MENU | Create / delete VLESS accounts + connection links |
| 04 TROJAN MENU | Create / delete Trojan accounts + connection links |
| 05 SHADOW MENU | Create / delete UDP accounts |
| 06 LIMIT SPEED | Per-user bandwidth limits |
| 07 VPS INFO | Live server stats (OS, RAM, IP, ISP, city) |
| 08 DELL ALL EXP | Delete all expired accounts now |
| 09 AUTOREBOOT | Schedule daily reboot at midnight |
| 10 INFO PORT | Show all active ports |
| 11 SPEEDTEST | Run network speed test |
| 12 RUNNING | Show all service statuses |
| 13 CLEAR LOG | Clear logs |
| 14 Cek Bandwith | Show bandwidth usage |
| 15 BCKP/RSTR | Backup / restore config |
| 16 REBOOT | Reboot the VPS |
| 17 RESTART | Restart all services |
| 18 DOMAIN | Update domain |
| 19 CERT SSL | Renew SSL certificate |
| 20 INS. UDP | Reinstall UDP binary |
| 21 CLEAR CACHE | Drop system cache |
| 23 UPDATE SCRIPT | Pull latest script from GitHub |
| 25 CHANGE BANNER | Edit SSH login banner (`/etc/issue.net`) |

---

## SSH Device Limit

When creating an SSH account you choose **max simultaneous devices** (1–10, or 0 for unlimited).  
If a user logs in from more devices at the same time than their limit allows, the account is **automatically locked** and all sessions killed. Unsuspend via panel → SSH MENU → Unsuspend.

---

## Auto-Expiry

Accounts are cleaned up automatically every 2 minutes:
- **SSH** — expired accounts are deleted (user removed from system)
- **V2Ray / Trojan** — expired or over data-quota accounts are removed from Xray config

---

## SSH Login Banner

Stored in `issue.net` in this repo. On fresh install the script copies it to `/etc/issue.net` on the VPS.  
To update the banner on a running VPS: panel → **[25] CHANGE BANNER** → Pull from GitHub.

---

## Mode Switching

```bash
etunnel-switch-to-ovpn.sh       # Switch to OpenVPN mode (port 443)
etunnel-switch-to-etunnel.sh    # Switch back to E-TUNNEL mode
```

---

## After Install

All credentials and connection links are saved to:
```
/root/etunnel-links.txt
```

---

## Requirements

- Fresh Ubuntu / Debian VPS
- Root access
- A domain name pointed to your VPS IP (for SSL)
- Port 80 open inbound (Let's Encrypt challenge)

---

## Repository Structure

```
etunnel-v1.0.0.sh                   ← Run this on the VPS to install everything
issue.net                            ← SSH login banner (pulled to VPS on install)
README.md                            ← This file

panel/
├── etunnel                          ← Control panel script → /usr/local/bin/etunnel
├── etunnel-watchdog.sh              ← Service watchdog → /usr/local/bin/
├── etunnel-quota-check.py           ← Expiry/quota checker → /usr/local/bin/
├── etunnel-switch-to-ovpn.sh        ← Mode switcher → /usr/local/bin/
└── etunnel-switch-to-etunnel.sh     ← Mode switcher → /usr/local/bin/

components/
├── universal-bridge/bridge.py       ← SSH+OpenVPN+WS bridge → /opt/universal-bridge/
├── rocket-proxy/rocket-proxy.js     ← WS→SSH proxy → /opt/rocket/
└── vpn-panel/app.py                 ← OpenVPN web panel → /opt/vpn-panel/

config/
├── haproxy.cfg                      ← HAProxy config → /etc/haproxy/
├── nginx-ssl-router.conf            ← Nginx stream config → /etc/nginx/stream-enabled/
└── xray-config.json                 ← Xray config template

services/
├── etunnel-watchdog.service/.timer
├── etunnel-quota-check.service/.timer
├── etunnel-net-recovery.service
├── universal-bridge.service
├── rocket-proxy.service
├── vpn-panel.service
├── openvpn-stunnel.service
└── certbot-renew-etunnel.service/.timer
```

---

*E-TUNNEL VPN — EMMKASH TECH · +254112735877 · https://t.me/emmkash*
