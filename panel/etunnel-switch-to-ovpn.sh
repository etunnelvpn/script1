#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
DOMAIN=$(cat /etc/etunnel/domain 2>/dev/null)
INIT_SYS="systemd"; [ -d /run/systemd/system ] || INIT_SYS="openrc"
svc_stop()   { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl stop "$s" 2>/dev/null ;; openrc) rc-service "$s" stop 2>/dev/null ;; esac; done; }
svc_start()  { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl start "$s" 2>/dev/null ;; openrc) rc-service "$s" start 2>/dev/null ;; esac; done; }
svc_status() { case "$INIT_SYS" in systemd) systemctl is-active --quiet "$1" 2>/dev/null ;; openrc) rc-service "$1" status >/dev/null 2>&1 ;; esac; }
echo -e "${CYAN}${NC}"
echo -e "${CYAN}    Switching to OpenVPN Mode       ${NC}"
echo -e "${CYAN}${NC}"
echo ""
echo -e "${YELLOW}[1/6] Stopping E-TUNNEL services...${NC}"
for svc in nginx haproxy xray payload-proxy rocket-proxy stunnel4 stunnel dnsmasq universal-bridge; do
    svc_stop "$svc" && echo "    Stopped: $svc"
done
sleep 1
echo ""
echo -e "${YELLOW}[2/6] Disabling normal stunnel.conf...${NC}"
if [ -f /etc/stunnel/stunnel.conf ] && [ ! -f /etc/stunnel/stunnel.conf.disabled ]; then
    mv /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.conf.disabled
    echo "    Moved stunnel.conf -> .disabled"
fi
echo ""
echo -e "${YELLOW}[3/6] Preparing openvpn.conf...${NC}"
if [ -f /etc/stunnel/openvpn.conf.disabled ]; then
    mv /etc/stunnel/openvpn.conf.disabled /etc/stunnel/openvpn.conf
    echo "    Restored openvpn.conf.disabled -> .conf"
elif [ ! -f /etc/stunnel/openvpn.conf ]; then
    cat > /etc/stunnel/openvpn.conf <<'EOF'
pid = /var/run/stunnel-openvpn.pid
cert = /etc/openvpn/keys/server.crt
key = /etc/openvpn/keys/server.key
sslVersionMin = TLSv1.2
options = NO_SSLv2
options = NO_SSLv3
ciphers = HIGH:!aNULL:!MD5
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
verify = 0

[openvpn]
accept = 443
connect = 127.0.0.1:1194
EOF
    echo "    Created new openvpn.conf"
fi
echo ""
echo -e "${YELLOW}[4/6] Freeing port 443...${NC}"
fuser -k 443/tcp >/dev/null 2>&1 || true
sleep 2
echo "    Done"
echo ""
echo -e "${YELLOW}[5/6] Starting OpenVPN + Stunnel + Bridge...${NC}"
svc_start openvpn@server openvpn 2>/dev/null
sleep 2
if svc_status "openvpn@server"; then echo "    openvpn@server running"; else echo -e "   ${RED} openvpn@server failed${NC}"; fi
svc_start openvpn-stunnel 2>/dev/null; sleep 2
svc_status openvpn-stunnel && echo "    openvpn-stunnel running on 443" || echo -e "   ${RED} openvpn-stunnel failed${NC}"
svc_start universal-bridge 2>/dev/null; sleep 1
svc_status universal-bridge && echo "    universal-bridge running" || echo -e "   ${RED} universal-bridge failed${NC}"
svc_start haproxy 2>/dev/null; sleep 1
svc_status haproxy && echo "    haproxy running on 80" || echo -e "   ${RED} haproxy failed${NC}"
echo ""
echo -e "${YELLOW}[6/6] Starting OpenVPN Panel...${NC}"
svc_start vpn-panel 2>/dev/null; sleep 1
svc_status vpn-panel && echo "    Panel running on 8090" || echo -e "   ${RED} OpenVPN Panel failed${NC}"
echo ""
echo -e "${GREEN}${NC}"
echo -e "${GREEN} Switched to OpenVPN${NC}"
echo -e "${GREEN}${NC}"
PANEL_USER=$(cat /etc/etunnel/vpn-panel-user 2>/dev/null || echo "etunneladmin")
PANEL_PASS=$(cat /etc/etunnel/vpn-panel-pass 2>/dev/null || echo "-")
echo -e "${CYAN} Panel Credentials:${NC}"
echo -e "   URL:  ${YELLOW}http://${DOMAIN}:8090${NC}"
echo -e "   User: ${GREEN}${PANEL_USER}${NC}"
echo -e "   Pass: ${GREEN}${PANEL_PASS}${NC}"
echo ""