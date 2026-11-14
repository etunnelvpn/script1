#!/bin/bash
# E-TUNNEL VPN Watchdog — restarts dead services every 60s
LOG="/var/log/etunnel-watchdog.log"
MODE_FILE="/etc/etunnel/current-mode"
MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "etunnel")

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    SVC_STATUS() { systemctl is-active --quiet "$1" 2>/dev/null; }
    SVC_RESTART() { systemctl restart "$1" 2>/dev/null; }
elif command -v rc-service >/dev/null 2>&1; then
    SVC_STATUS() { rc-service "$1" status >/dev/null 2>&1; }
    SVC_RESTART() { rc-service "$1" restart 2>/dev/null; }
else
    exit 0
fi

if [ "$MODE" = "etunnel" ]; then
    SERVICES="haproxy nginx dropbear stunnel4 stunnel xray payload-proxy rocket-proxy dnsmasq udp-custom universal-bridge"
    PORTS="80 443 444 4443 8080 8081 10085"
else
    SERVICES="dropbear dnsmasq openvpn@server openvpn openvpn-stunnel vpn-panel universal-bridge haproxy"
    PORTS="443 1194 8090 8080 80"
fi

for svc in $SERVICES; do
    if ! SVC_STATUS "$svc"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')]  $svc down" >> "$LOG"
        SVC_RESTART "$svc"
    fi
done

for port in $PORTS; do
    if ! ss -lntH "sport = :${port}" 2>/dev/null | grep -q .; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')]  port $port closed" >> "$LOG"
    fi
done

# rotate log if > 5MB
[ -f "$LOG" ] && [ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 5242880 ] && \
    tail -1000 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
