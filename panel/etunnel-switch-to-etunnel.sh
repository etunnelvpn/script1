#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
DOMAIN=$(cat /etc/etunnel/domain 2>/dev/null)
INIT_SYS="systemd"; [ -d /run/systemd/system ] || INIT_SYS="openrc"
STUNNEL_SVC="stunnel4"; [ "$INIT_SYS" = "openrc" ] && STUNNEL_SVC="stunnel"
svc_stop()   { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl stop "$s" 2>/dev/null ;; openrc) rc-service "$s" stop 2>/dev/null ;; esac; done; }
svc_start()  { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl start "$s" 2>/dev/null ;; openrc) rc-service "$s" start 2>/dev/null ;; esac; done; }
svc_status() { case "$INIT_SYS" in systemd) systemctl is-active --quiet "$1" 2>/dev/null ;; openrc) rc-service "$1" status >/dev/null 2>&1 ;; esac; }
echo -e "${CYAN}${NC}"
echo -e "${CYAN}    Switching to E-TUNNEL Mode         ${NC}"
echo -e "${CYAN}${NC}"
echo ""
echo -e "${YELLOW}[1/5] Stopping OpenVPN + Panel...${NC}"
for svc in vpn-panel openvpn-stunnel openvpn@server openvpn ovpn-ws-bridge universal-bridge; do
    svc_stop "$svc" && echo "    Stopped: $svc"
done
sleep 1
echo ""
echo -e "${YELLOW}[2/5] Disabling openvpn.conf + restoring stunnel.conf...${NC}"
if [ -f /etc/stunnel/openvpn.conf ]; then
    mv /etc/stunnel/openvpn.conf /etc/stunnel/openvpn.conf.disabled
    echo "    Moved openvpn.conf -> .disabled"
fi
if [ -f /etc/stunnel/stunnel.conf.disabled ]; then
    mv /etc/stunnel/stunnel.conf.disabled /etc/stunnel/stunnel.conf
    echo "    Restored stunnel.conf.disabled -> .conf"
fi
echo ""
echo -e "${YELLOW}[3/5] Freeing 443 + fixing cert permissions...${NC}"
fuser -k 443/tcp >/dev/null 2>&1 || true
sleep 2
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null
chmod 755 /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/archive/$DOMAIN 2>/dev/null
chmod 644 /etc/letsencrypt/archive/$DOMAIN/*.pem /etc/letsencrypt/live/$DOMAIN/*.pem 2>/dev/null
echo "    Done"
echo ""
echo -e "${YELLOW}[4/5] Starting E-TUNNEL services in order...${NC}"
fuser -k 80/tcp 10085/tcp 10086/tcp 10087/tcp 10088/tcp 10089/tcp 10090/tcp 10091/tcp >/dev/null 2>&1 || true
sleep 1
for svc in dropbear dnsmasq xray payload-proxy rocket-proxy haproxy $STUNNEL_SVC nginx universal-bridge; do
    printf "   %-20s " "$svc"
    svc_start "$svc" 2>/dev/null
    sleep 1
    if svc_status "$svc"; then echo -e "${GREEN}${NC}"
    else echo -e "${RED}${NC}"; fi
done
echo ""
echo -e "${YELLOW}[5/5] Verification...${NC}"
sleep 2
ss -lntH "sport = :443" 2>/dev/null | grep -q . && echo -e "   ${GREEN}${NC} Nginx on 443" || echo -e "   ${RED}${NC} 443 closed"
ss -lntH "sport = :10085" 2>/dev/null | grep -q . && echo -e "   ${GREEN}${NC} Xray running" || echo -e "   ${RED}${NC} Xray stopped"
echo ""
echo -e "${GREEN}${NC}"
echo -e "${GREEN} Switched to E-TUNNEL${NC}"
echo -e "${GREEN}${NC}"