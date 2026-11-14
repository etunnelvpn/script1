# E-TUNNEL VPN — Install Guide

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel-v1.0.0.sh \
  -o /tmp/etunnel.sh && sudo bash /tmp/etunnel.sh
```

## With Domain Pre-set

```bash
curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel-v1.0.0.sh \
  -o /tmp/etunnel.sh && sudo bash /tmp/etunnel.sh yourdomain.com
```

## Requirements

- Ubuntu 18.04 / 20.04 / 22.04 / 24.04 (root access)
- Domain pointed to your VPS IP (for SSL)
- Port 80 open (Let's Encrypt challenge)

## After Install

| Action | Command |
|--------|---------|
| Open panel | `etunnel` |
| Switch to OpenVPN mode | `etunnel-switch-to-ovpn.sh` |
| Switch to E-TUNNEL mode | `etunnel-switch-to-etunnel.sh` |
| View saved credentials | `cat /root/etunnel-links.txt` |
| View install log | `cat /root/etunnel-install.log` |

## Ports Reference

| Port | Protocol |
|------|----------|
| 22   | SSH |
| 80   | HAProxy router |
| 443  | Nginx TLS stream |
| 444  | Dropbear SSH |
| 1194 | OpenVPN TCP |
| 4443 | Nginx HTTP/2 |
| 8080 | Universal Bridge |
| 8081 | Rocket Proxy |
| 8090 | OpenVPN Web Panel |
| 8444 | Stunnel → SSH |
| 10086| VMess WS |
| 10087| VLESS WS |
| 10090| Trojan WS |
