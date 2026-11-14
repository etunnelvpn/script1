#!/bin/bash
# E-TUNNEL VPN — Switch to OpenVPN mode
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
DOMAIN=$(cat /etc/etunnel/domain 2>/dev/null)
INIT_SYS="systemd"; [ -d /run/systemd/system ] || INIT_SYS="openrc"
svc_stop()   { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl stop  "$s" 2>/dev/null ;; openrc) rc-service "$s" stop    2>/dev/null ;; esac; done; }
svc_start()  { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl start "$s" 2>/dev/null ;; openrc) rc-service "$s" start   2>/dev/null ;; esac; done; }
svc_status() { case "$INIT_SYS" in systemd) systemctl is-active --quiet "$1" 2>/dev/null ;; openrc) rc-service "$1" status >/dev/null 2>&1 ;; esac; }

echo -e "${CYAN}  Switching to OpenVPN Mode${NC}"
echo ""

echo -e "${YELLOW}[1/6] Stopping E-TUNNEL services...${NC}"
for svc in nginx haproxy xray payload-proxy rocket-proxy stunnel4 stunnel dnsmasq universal-bridge; do
    svc_stop "$svc" && echo "    Stopped: $svc"
done
sleep 1

echo -e "${YELLOW}[2/6] Disabling stunnel.conf...${NC}"
[ -f /etc/stunnel/stunnel.conf ] && ! [ -f /etc/stunnel/stunnel.conf.disabled ] && \
    mv /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.conf.disabled && echo "    Moved -> .disabled"

echo -e "${YELLOW}[3/6] Preparing openvpn stunnel...${NC}"
if [ -f /etc/stunnel/openvpn.conf.disabled ]; then
    mv /etc/stunnel/openvpn.conf.disabled /etc/stunnel/openvpn.conf
    echo "    Restored openvpn.conf"
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
fi

echo -e "${YELLOW}[4/6] Freeing port 443...${NC}"
fuser -k 443/tcp >/dev/null 2>&1 || true; sleep 2

echo -e "${YELLOW}[5/6] Starting OpenVPN + Stunnel + Bridge...${NC}"
svc_start openvpn@server openvpn; sleep 2
svc_status "openvpn@server" && echo "    openvpn running" || echo -e "   ${RED} openvpn failed${NC}"
svc_start openvpn-stunnel; sleep 2
svc_status openvpn-stunnel && echo "    stunnel on 443" || echo -e "   ${RED} stunnel failed${NC}"
svc_start universal-bridge; sleep 1
svc_status universal-bridge && echo "    bridge running" || echo -e "   ${RED} bridge failed${NC}"
svc_start haproxy; sleep 1
svc_status haproxy && echo "    haproxy on 80" || echo -e "   ${RED} haproxy failed${NC}"

echo -e "${YELLOW}[6/6] Starting VPN Panel...${NC}"
svc_start vpn-panel; sleep 1
svc_status vpn-panel && echo "    Panel on 8090" || echo -e "   ${RED} Panel failed${NC}"

echo ""
echo -e "${GREEN} Switched to OpenVPN${NC}"
PANEL_USER=$(cat /etc/etunnel/vpn-panel-user 2>/dev/null || echo "etunneladmin")
PANEL_PASS=$(cat /etc/etunnel/vpn-panel-pass 2>/dev/null || echo "-")
echo -e "   URL : ${YELLOW}http://${DOMAIN}:8090${NC}"
echo -e "   User: ${GREEN}${PANEL_USER}${NC}  Pass: ${GREEN}${PANEL_PASS}${NC}"
echo "openvpn" > /etc/etunnel/current-mode
