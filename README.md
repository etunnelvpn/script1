# GOLAN400 v6.8.2 — VPS Auto Install Script

A multi-protocol VPN server auto-installer for Ubuntu VPS.

## Supported Systems

| OS | Version | Status |
|---|---|---|
| Ubuntu | 24.04 | ✅ |
| Ubuntu | 22.04 | ✅ |
| Ubuntu | 20.04 | ✅ |
| Ubuntu | 18.04 | ✅ |

## Install Command

```bash
curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/golan400-v6.8.2-final.sh -o /tmp/golan.sh && (command -v bash >/dev/null 2>&1 || (apt-get install -y bash 2>/dev/null || apk add bash 2>/dev/null)) && bash /tmp/golan.sh
```

> Run as **root** on a fresh VPS. You will be prompted to enter your domain name.

## With Domain (optional)

```bash
curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/golan400-v6.8.2-final.sh -o /tmp/golan.sh && (command -v bash >/dev/null 2>&1 || (apt-get install -y bash 2>/dev/null || apk add bash 2>/dev/null)) && bash /tmp/golan.sh yourdomain.com
```

## What Gets Installed

| Component | Details |
|---|---|
| **SSH SSL** | Dropbear on port 444, Stunnel on 8444 |
| **V2Ray / Xray** | VLESS + VMESS + Trojan over WebSocket |
| **Nginx** | Stream on 443, HTTP on 4443 |
| **HAProxy** | Port 80 traffic router |
| **Universal Bridge** | Port 8080 — SSH + OpenVPN + WS |
| **Rocket Proxy** | Port 8081 — WebSocket to SSH |
| **OpenVPN** | TCP on 1194, Stunnel on 443 (switchable) |
| **VPN Panel** | Web panel on port 8090 |
| **DNS** | dnsmasq wildcard on port 5353 |
| **UDP Custom** | UDP tunnel binary |
| **fail2ban** | SSH brute-force protection |

## Ports Used

| Port | Service |
|---|---|
| 22 | SSH |
| 80 | HAProxy (router) |
| 443 | Nginx Stream (TLS) |
| 444 | Dropbear SSH |
| 1194 | OpenVPN TCP |
| 4443 | Nginx HTTP/2 |
| 8080 | Universal Bridge |
| 8081 | Rocket Proxy |
| 8090 | VPN Web Panel |
| 8444 | Stunnel → SSH |
| 10086 | VMess WS |
| 10087 | VLESS WS |
| 10090 | Trojan WS |

## Control Panel

After install, type `golan` in the terminal to open the control panel:

```
golan
```

From the panel you can:
- Create / delete SSH accounts
- Create / delete V2Ray (VLESS, VMESS) accounts
- Create / delete Trojan accounts
- Create / delete UDP accounts
- Add custom VLESS ports
- Switch between GOLAN mode and OpenVPN mode
- View connection links and QR codes
- Restart all services

## Mode Switching

```bash
# Switch to OpenVPN mode
golan-switch-to-ovpn.sh

# Switch back to GOLAN mode
golan-switch-to-golan.sh
```

## After Install

Credentials and connection links are saved to:
```
/root/golan-links.txt
```

## Requirements

- Fresh Ubuntu VPS (root access)
- A domain name pointed to your VPS IP
- Port 80 open (for Let's Encrypt SSL)
