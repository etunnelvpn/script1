# E-TUNNEL VPN — Panel Menu Reference

Open the panel by typing `etunnel` in the terminal.

## Menu Options

| # | Menu | Description |
|---|------|-------------|
| 01 | SSH MENU | Create/delete/list SSH accounts, view online users, unsuspend |
| 02 | VMESS MENU | Create/delete VMESS accounts, view connection links |
| 03 | VLESS MENU | Create/delete VLESS accounts, view connection links |
| 04 | TROJAN MENU | Create/delete Trojan accounts, view connection links |
| 05 | SHADOW MENU | Create/delete UDP/Shadowsocks accounts |
| 06 | LIMIT SPEED | Set per-user bandwidth limits (tc-based) |
| 07 | VPS INFO | Show live server details (OS, RAM, IP, ISP, City) |
| 08 | DELL ALL EXP | Delete all expired accounts immediately |
| 09 | AUTOREBOOT | Schedule daily reboot at midnight |
| 10 | INFO PORT | Show all active listening ports |
| 11 | SPEEDTEST | Run network speedtest |
| 12 | RUNNING | Show all service statuses |
| 13 | CLEAR LOG | Clear watchdog and nginx logs |
| 14 | Cek Bandwith | Show network bandwidth usage |
| 15 | BCKP/RSTR | Backup or restore config |
| 16 | REBOOT | Reboot the VPS |
| 17 | RESTART | Restart all VPN services |
| 18 | DOMAIN | View or update domain |
| 19 | CERT SSL | Renew Let's Encrypt cert |
| 20 | INS. UDP | Download/reinstall UDP custom binary |
| 21 | CLEAR CACHE | Drop page cache |
| 22 | BOT NOTIF | Telegram bot notifications (coming soon) |
| 23 | UPDATE SCRIPT | Pull latest etunnel-v1.0.0.sh from GitHub |
| 25 | CHANGE BANNER | Edit or reset the SSH login banner (/etc/issue.net) |
| 0  | EXIT | Exit the panel |

## SSH Device Limit

When creating an SSH account you are asked for **Max devices (0=unlimited)**.  
A background watcher checks every 60 seconds — if a user has more concurrent  
sessions than their limit, the account is locked and all sessions are killed.  
Use option **01 → Unsuspend** to re-enable an account.

## Banner

The login banner shown to SSH users is stored in `/etc/issue.net`.  
Edit it from the panel (**[25] CHANGE BANNER**) or directly:

```bash
nano /etc/issue.net
cp /etc/issue.net /etc/motd
```
