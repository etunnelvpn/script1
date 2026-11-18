#!/bin/bash
# E-TUNNEL VPN v1.0.0 Part 2 — by EMMKASH TECH

# Source helper functions exported by Part 1
[ -f "${ETUNNEL_FUNCS_FILE:-/tmp/etunnel-funcs.sh}" ] && . "${ETUNNEL_FUNCS_FILE:-/tmp/etunnel-funcs.sh}"

# Re-detect init system if variables not set
[ -z "$INIT_SYS" ] && { [ -d /run/systemd/system ] && INIT_SYS="systemd" || INIT_SYS="openrc"; }
[ -z "$PKG" ] && { command -v apt-get >/dev/null 2>&1 && PKG="apt" || PKG="unknown"; }
[ -z "$STUNNEL_SVC" ] && { [ "$PKG" = "apt" ] && STUNNEL_SVC="stunnel4" || STUNNEL_SVC="stunnel"; }
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
LOG_FILE=${LOG_FILE:-/root/etunnel-install.log}


echo -e "${YELLOW} [12/23] DNS Wildcard ${NC}"
svc_unmask dnsmasq systemd-resolved
backup_file /etc/dnsmasq.conf
cat > /etc/dnsmasq.conf <<EOF
port=5353
no-resolv
server=8.8.8.8
server=1.1.1.1
cache-size=4096
address=/${DOMAIN}/${IP}
EOF
svc_enable dnsmasq
svc_restart dnsmasq; sleep 1
svc_status dnsmasq && check_ok "dnsmasq running" || check_fail "dnsmasq"
iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || true
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || true
check_ok "iptables: UDP 53 -> 5353"
echo ""

echo -e "${YELLOW} [13/23] Banner + SSH Compatibility ${NC}"
echo -e "  ${CYAN}Pulling banner from GitHub...${NC}"
if repo_copy "issue.net" "/etc/issue.net"; then
    check_ok "Banner copied from repo clone"
elif curl -fsSL "https://raw.githubusercontent.com/etunnelvpn/script1/main/issue.net" -o /etc/issue.net 2>/dev/null; then
    check_ok "Banner pulled from GitHub"
else
    warn "GitHub pull failed — using built-in default banner"
    cat > /etc/issue.net <<'BANNER'
+================================================+
|          E-TUNNEL VPN BY EMMKASH TECH          |
|           Contact: +254112735877               |
+================================================+
|   CALLS AND GAMING NOW SUPPORTED               |
|   NO DDOS !!!                                  |
|   NO HACKING !!!                               |
|   NO TORRENT !!!                               |
|   NO SPAMMING !!!                              |
|   NO CARDING !!!                               |
|   NO FRAUD !!!                                 |
+------------------------------------------------+
|   E-TUNNEL VPN SCRIPT                          |
|   SERVER REBOOTS AT 12:00AM                    |
|   Telegram: https://t.me/emmkash               |
+================================================+
BANNER
fi
cp /etc/issue.net /etc/motd
# /etc/issue.net is now populated — add banner to dropbear and restart
if [ -f /etc/systemd/system/dropbear.service ]; then
    sed -i "s|-F -w -p 444 *$|-F -w -p 444 -b /etc/issue.net|" /etc/systemd/system/dropbear.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    svc_restart dropbear 2>/dev/null || true
fi
sed -i '\|^Banner |d' /etc/ssh/sshd_config 2>/dev/null || true
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-etunnel-banner.conf <<EOF
Banner /etc/issue.net
PrintMotd yes
PasswordAuthentication yes
PermitRootLogin yes
EOF

sed -i '/^Ciphers /d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^MACs /d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^HostKeyAlgorithms /d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^PubkeyAcceptedAlgorithms /d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i '/^KexAlgorithms /d' /etc/ssh/sshd_config 2>/dev/null || true
cat >> /etc/ssh/sshd_config <<'SSHEOF'

# E-TUNNEL - SSH Compatibility (Legacy + Modern)
HostKeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa
KexAlgorithms +diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
Ciphers +aes128-cbc,aes256-cbc,aes192-cbc,3des-cbc
MACs +hmac-sha1,hmac-md5

# E-TUNNEL SSH Stability Tuning
ClientAliveInterval 30
ClientAliveCountMax 6
TCPKeepAlive yes
SSHEOF
if sshd -t 2>/dev/null; then
    svc_restart "$SSH_SVC" 2>/dev/null || svc_restart sshd 2>/dev/null || true
    svc_restart dropbear 2>/dev/null || true
    check_ok "SSH compatibility installed"
else
    check_fail "SSH config"
fi
echo ""

echo -e "${YELLOW} [14/23] Panel (Full Layout) ${NC}"
mkdir -p /etc/etunnel/accounts /root/etunnel-save
touch /etc/etunnel/custom_ports.txt
touch /etc/etunnel/accounts/{v2ray,trojan,ssh,udp}.txt

repo_copy "panel/etunnel" "/usr/local/bin/menu" || \
cat > /usr/local/bin/menu <<'PANEL'
#!/bin/bash
# E-TUNNEL VPN Control Panel v1.0.0 by EMMKASH TECH
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'
ACC_DIR=/etc/etunnel/accounts
mkdir -p "$ACC_DIR"
touch "$ACC_DIR/ssh.txt" "$ACC_DIR/v2ray.txt" "$ACC_DIR/udp.txt" "$ACC_DIR/trojan.txt" /etc/etunnel/custom_ports.txt
DOMAIN=$(cat /etc/etunnel/domain 2>/dev/null || ls /etc/letsencrypt/live/ 2>/dev/null | head -1)
[ -z "$DOMAIN" ] && DOMAIN="server"
XRAY_CONF=/usr/local/etc/xray/config.json
INIT_SYS="systemd"; [ -d /run/systemd/system ] || INIT_SYS="openrc"
STUNNEL_SVC="stunnel4"; [ "$INIT_SYS" = "openrc" ] && STUNNEL_SVC="stunnel"

svc_status() { case "$INIT_SYS" in systemd) systemctl is-active --quiet "$1" 2>/dev/null ;; openrc) rc-service "$1" status >/dev/null 2>&1 ;; esac; }
svc_restart() { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl restart "$s" 2>/dev/null ;; openrc) rc-service "$s" restart 2>/dev/null ;; esac; done; }
pause() { read -p "  Press Enter to return..." < /dev/tty; }
on_off() { svc_status "$1" && echo "✓" || echo "✗"; }

# ── auto-expire SSH accounts ──────────────────────────────────
expire_ssh_accounts() {
    [ ! -s "$ACC_DIR/ssh.txt" ] && return
    local today; today=$(date +%Y-%m-%d)
    local tmp; tmp=$(mktemp)
    local changed=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local user expiry
        user=$(echo "$line" | awk -F' \| ' '{print $1}')
        expiry=$(echo "$line" | awk -F' \| ' '{print $3}')
        if [ -n "$expiry" ] && [[ "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            if [[ "$today" > "$expiry" ]]; then
                userdel -r "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
                changed=1
                continue
            fi
        fi
        echo "$line" >> "$tmp"
    done < "$ACC_DIR/ssh.txt"
    mv "$tmp" "$ACC_DIR/ssh.txt"
}

# ── device-limit watcher ──────────────────────────────────────
start_device_watcher() {
    [ -f /var/run/etunnel-devwatch.pid ] && kill -0 "$(cat /var/run/etunnel-devwatch.pid)" 2>/dev/null && return
    (
        while true; do
            sleep 60
            [ ! -s "$ACC_DIR/ssh.txt" ] && continue
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local user max_dev sessions
                user=$(echo "$line" | awk -F' \| ' '{print $1}')
                max_dev=$(echo "$line" | awk -F' \| ' '{print $4}')
                [[ "$max_dev" =~ ^[0-9]+$ ]] || continue
                [ "$max_dev" -eq 0 ] && continue
                sessions=$(who 2>/dev/null | awk -v u="$user" '$1==u' | wc -l)
                if [ "$sessions" -gt "$max_dev" ] 2>/dev/null; then
                    usermod -L "$user" 2>/dev/null || true
                    pkill -KILL -u "$user" 2>/dev/null || true
                    sed -i "s/^${user} |/${user} | SUSPENDED |/" "$ACC_DIR/ssh.txt" 2>/dev/null || true
                fi
            done < "$ACC_DIR/ssh.txt"
        done
    ) &
    echo $! > /var/run/etunnel-devwatch.pid
    disown
}

# ── live VPS info ─────────────────────────────────────────────
get_vps_info() {
    OS_NAME=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s)
    CPU_CORES=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo "?")
    RAM_USED=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}')
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    UPTIME_MIN=$(awk '{print int($1/60)}' /proc/uptime 2>/dev/null || echo "?")
    VPS_IP=$(curl -4 -s --max-time 4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    ISP=$(curl -s --max-time 4 "https://ipinfo.io/${VPS_IP}/org" 2>/dev/null | sed 's/AS[0-9]* //' || echo "Unknown")
    CITY=$(curl -s --max-time 4 "https://ipinfo.io/${VPS_IP}/city" 2>/dev/null || echo "Unknown")
}

# ── account counts ────────────────────────────────────────────
count_accs() {
    _count_file() {
        local f="$1"
        if [ ! -f "$f" ] || [ ! -s "$f" ]; then echo 0; return; fi
        grep -c "[a-zA-Z0-9]" "$f" 2>/dev/null || echo 0
    }
    SSH_COUNT=$(_count_file "$ACC_DIR/ssh.txt")
    V2RAY_COUNT=$(_count_file "$ACC_DIR/v2ray.txt")
    TROJAN_COUNT=$(_count_file "$ACC_DIR/trojan.txt")
    UDP_COUNT=$(_count_file "$ACC_DIR/udp.txt")
}

links() {
  local uuid="$1" name="$2"
  local frag="&fragment=tlshello,10-20,10-20"
  echo -e "${CYAN} VLESS 443 TLS:${NC}"
  echo "vless://${uuid}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&alpn=h2,http%2F1.1&type=ws&host=${DOMAIN}&path=%2Fvless${frag}#${name}-VLESS"
  echo -e "${CYAN} VMESS 443 TLS:${NC}"
  local j="{\"v\":\"2\",\"ps\":\"${name}-VMESS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
  echo "vmess://$(echo -n "$j" | base64 -w 0)"
  echo -e "${CYAN} VLESS 80:${NC}"
  echo "vless://${uuid}@${DOMAIN}:80?encryption=none&security=none&type=ws&host=google.com&path=%2Fvless${frag}#${name}-VLESS80"
  echo -e "${CYAN} VMESS 80:${NC}"
  local j2="{\"v\":\"2\",\"ps\":\"${name}-VMESS80\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"google.com\",\"path\":\"/vmess\"}"
  echo "vmess://$(echo -n "$j2" | base64 -w 0)"
}

trojan_links() {
  local pw="$1" name="$2"
  local frag="&fragment=tlshello,10-20,10-20"
  echo -e "${CYAN} TROJAN 443 TLS:${NC}"
  echo "trojan://${pw}@${DOMAIN}:443?security=tls&sni=${DOMAIN}&alpn=h2,http%2F1.1&type=ws&host=${DOMAIN}&path=%2Ftrojan${frag}#${name}-TROJAN"
  echo -e "${CYAN} TROJAN 80:${NC}"
  echo "trojan://${pw}@${DOMAIN}:80?security=none&type=ws&host=google.com&path=%2Ftrojan${frag}#${name}-TROJAN80"
}

# run on every panel open
expire_ssh_accounts
start_device_watcher

# ═══════════════════════════════════════════════════════════════
#  MAIN LOOP
# ═══════════════════════════════════════════════════════════════
while true; do
clear
get_vps_info
count_accs

echo -e "${MAGENTA}  +--------------------------------------------------+"
echo -e "  |     PREMIUM AUTOSCRIPT BY EMMKASH TECH           |"
echo -e "  |     Contact: +254112735877                       |"
echo -e "  +--------------------------------------------------+${NC}"
echo ""
echo -e "${CYAN}  +--------------------------------------------------+"
echo -e "  | ${GREEN}* System OS      ${CYAN}= ${NC}$OS_NAME"
echo -e "${CYAN}  | ${GREEN}* Core System    ${CYAN}= ${NC}$CPU_CORES"
echo -e "${CYAN}  | ${GREEN}* Server RAM     ${CYAN}= ${NC}${RAM_USED}/${RAM_TOTAL} MB"
echo -e "${CYAN}  | ${GREEN}* Uptime Server  ${CYAN}= ${NC}${UPTIME_MIN} minutes"
echo -e "${CYAN}  | ${GREEN}* Domain         ${CYAN}= ${NC}$DOMAIN"
echo -e "${CYAN}  | ${GREEN}* IP VPS         ${CYAN}= ${NC}$VPS_IP"
echo -e "${CYAN}  | ${GREEN}* ISP            ${CYAN}= ${NC}$ISP"
echo -e "${CYAN}  | ${GREEN}* City           ${CYAN}= ${NC}$CITY"
echo -e "${CYAN}  +--------------------------------------------------+${NC}"
echo ""
echo -e "${YELLOW}             >>> YOUR ACCOUNT ON VPS <<<${NC}"
echo "  +--------------------------------------------------+"
echo "  |   SSH/OPENVPN      > ${SSH_COUNT}  ACCOUNT PREMIUM         |"
echo "  |   VMESS/WS/GRPC    > ${V2RAY_COUNT}  ACCOUNT PREMIUM         |"
echo "  |   VLESS/WS/GRPC    > ${V2RAY_COUNT}  ACCOUNT PREMIUM         |"
echo "  |   TROJAN/WS/GRPC   > ${TROJAN_COUNT}  ACCOUNT PREMIUM         |"
echo "  |   SHADOWSOCKS/WS   > ${UDP_COUNT}  ACCOUNT PREMIUM         |"
echo "  +--------------------------------------------------+"
echo ""
SSH_S=$(svc_status dropbear    && echo "✓" || echo "✗")
NGINX_S=$(svc_status nginx     && echo "✓" || echo "✗")
WS_S=$(svc_status rocket-proxy && echo "✓" || echo "✗")
DROP_S=$(svc_status dropbear   && echo "✓" || echo "✗")
XRAY_SVC=$(svc_status xray    && echo "✓" || echo "✗")
HAP_SVC=$(svc_status haproxy  && echo "✓" || echo "✗")
echo -e "${CYAN}  +--------------------+-------------------+-------------------+"
echo -e "  | SSH    : ${GREEN}${SSH_S}${NC}      ${CYAN}|${NC} NGINX  : ${GREEN}${NGINX_S}${NC}     ${CYAN}|${NC} XRAY   : ${GREEN}${XRAY_SVC}${NC}    ${CYAN}|${NC}"
echo -e "  | WS-ePRO: ${GREEN}${WS_S}${NC}      ${CYAN}|${NC} DROPBR : ${GREEN}${DROP_S}${NC}     ${CYAN}|${NC} HAPROXY: ${GREEN}${HAP_SVC}${NC}    ${CYAN}|${NC}"
echo -e "${CYAN}  +--------------------+-------------------+-------------------+${NC}"
echo ""
echo -e "${CYAN}  [01]${NC} SSH MENU         ${CYAN}[08]${NC} DELL ALL EXP    ${CYAN}[15]${NC} BCKP/RSTR"
echo -e "${CYAN}  [02]${NC} VMESS MENU       ${CYAN}[09]${NC} AUTOREBOOT      ${CYAN}[16]${NC} REBOOT"
echo -e "${CYAN}  [03]${NC} VLESS MENU       ${CYAN}[10]${NC} INFO PORT       ${CYAN}[17]${NC} RESTART"
echo -e "${CYAN}  [04]${NC} TROJAN MENU      ${CYAN}[11]${NC} SPEEDTEST       ${CYAN}[18]${NC} DOMAIN"
echo -e "${CYAN}  [05]${NC} SHADOW MENU      ${CYAN}[12]${NC} RUNNING         ${CYAN}[19]${NC} CERT SSL"
echo -e "${CYAN}  [06]${NC} LIMIT SPEED      ${CYAN}[13]${NC} CLEAR LOG       ${CYAN}[20]${NC} INS. UDP"
echo -e "${CYAN}  [07]${NC} VPS INFO         ${CYAN}[14]${NC} Cek Bandwith    ${CYAN}[21]${NC} CLEAR CACHE"
echo -e "${CYAN}  [22]${NC} BOT NOTIF        ${CYAN}[23]${NC} UPDATE SCRIPT"
echo ""
echo -e "  ${GREEN}[25] CHANGE BANNER <<<${NC}"
echo -e "  ${RED}[ 0] BACK TO EXIT MENU <<<${NC}"
echo ""
read -t 120 -p "  E-TUNNEL@VPS: " CH < /dev/tty || CH=""

case $CH in
 ""|" ") continue;;

 1|01)
  while true; do
  clear
  echo -e "${CYAN}  ══════════════ SSH MENU ══════════════${NC}"
  echo -e "  ${YELLOW}[1]${NC} Create SSH Account   ${YELLOW}[2]${NC} Delete SSH Account"
  echo -e "  ${YELLOW}[3]${NC} List SSH Accounts    ${YELLOW}[4]${NC} Show Online Users"
  echo -e "  ${YELLOW}[5]${NC} Unsuspend Account    ${YELLOW}[0]${NC} Back"
  echo ""; read -p "  Choice: " SC < /dev/tty
  case $SC in
   1)
    read -p "  Username: " U < /dev/tty
    if ! [[ "$U" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; then echo -e "${RED}  Invalid name${NC}"; pause; continue; fi
    if id "$U" >/dev/null 2>&1; then echo -e "${RED}  Exists${NC}"; pause; continue; fi
    read -p "  Password: " P < /dev/tty
    [ -z "$P" ] && { echo -e "${RED}  Empty password${NC}"; pause; continue; }
    read -p "  Days (1-365): " D < /dev/tty
    if ! [[ "$D" =~ ^[0-9]+$ ]] || [ "$D" -lt 1 ] || [ "$D" -gt 365 ]; then echo -e "${RED}  Invalid days${NC}"; pause; continue; fi
    echo -e "  ${CYAN}Max simultaneous devices (1-10, 0=unlimited):${NC}"
    read -p "  Devices: " MD < /dev/tty
    [[ "$MD" =~ ^[0-9]+$ ]] || MD=0
    EXPIRY=$(date -d "+${D} days" +%Y-%m-%d)
    if useradd -m -s /bin/bash "$U" 2>/dev/null && echo "$U:$P" | chpasswd && usermod -e "$EXPIRY" "$U" 2>/dev/null; then
      echo "$U | $P | $EXPIRY | $MD" >> "$ACC_DIR/ssh.txt"
      echo -e "${GREEN}  Created: $U${NC}"
      echo -e "  Expires : $EXPIRY"
      echo -e "  MaxDev  : $([ "$MD" = "0" ] && echo unlimited || echo $MD)"
    else echo -e "${RED}  Failed${NC}"; fi
    pause;;
   2)
    [ ! -s "$ACC_DIR/ssh.txt" ] && { echo -e "${YELLOW}  None found${NC}"; pause; continue; }
    cat -n "$ACC_DIR/ssh.txt"
    read -p "  Number (0=cancel): " IDX < /dev/tty
    [ -z "$IDX" ] || [ "$IDX" = "0" ] && continue
    LINE=$(sed -n "${IDX}p" "$ACC_DIR/ssh.txt")
    U=$(echo "$LINE" | awk -F' \| ' '{print $1}')
    if [ -n "$U" ] && id "$U" >/dev/null 2>&1; then
      userdel -r "$U" 2>/dev/null || userdel "$U" 2>/dev/null
      sed -i "${IDX}d" "$ACC_DIR/ssh.txt"
      echo -e "${GREEN}  Deleted: $U${NC}"
    else echo -e "${RED}  Error${NC}"; fi
    pause;;
   3)
    [ ! -s "$ACC_DIR/ssh.txt" ] && { echo -e "${YELLOW}  None found${NC}"; pause; continue; }
    printf "  ${CYAN}%-16s %-12s %-12s %-8s${NC}\n" "User" "Password" "Expiry" "MaxDev"
    echo "  ──────────────────────────────────────────"
    while IFS= read -r line; do
      printf "  %-16s %-12s %-12s %-8s\n" \
        "$(echo $line|awk -F'|' '{print $1}'|xargs)" \
        "$(echo $line|awk -F'|' '{print $2}'|xargs)" \
        "$(echo $line|awk -F'|' '{print $3}'|xargs)" \
        "$(echo $line|awk -F'|' '{print $4}'|xargs)"
    done < "$ACC_DIR/ssh.txt"
    pause;;
   4)
    echo -e "${CYAN}  Online SSH Users:${NC}"
    who 2>/dev/null | awk '$1!="root"{print "  " $1 " — " $2 " " $3 " " $4}' || echo "  None"
    pause;;
   5)
    read -p "  Username to unsuspend: " U < /dev/tty
    [ -z "$U" ] && { pause; continue; }
    usermod -U "$U" 2>/dev/null && echo -e "${GREEN}  Unsuspended: $U${NC}" || echo -e "${RED}  Failed${NC}"
    sed -i "s/^${U} | SUSPENDED |/${U} |/" "$ACC_DIR/ssh.txt" 2>/dev/null || true
    pause;;
   0) break;;
  esac
  done;;

 2|02)
  while true; do
  clear
  echo -e "${CYAN}  ══════════════ VMESS MENU ══════════════${NC}"
  echo -e "  ${YELLOW}[1]${NC} Create   ${YELLOW}[2]${NC} Delete   ${YELLOW}[3]${NC} List + Links   ${YELLOW}[0]${NC} Back"
  echo ""; read -p "  Choice: " VC < /dev/tty
  case $VC in
   1)
    read -p "  Account Name: " N < /dev/tty
    [ -z "$N" ] && { echo -e "${RED}  Empty${NC}"; pause; continue; }
    if ! [[ "$N" =~ ^[A-Za-z0-9_-]{1,30}$ ]]; then echo -e "${RED}  Invalid${NC}"; pause; continue; fi
    if grep -q "^${N} |" "$ACC_DIR/v2ray.txt" 2>/dev/null; then echo -e "${RED}  Exists${NC}"; pause; continue; fi
    read -p "  Validity days [30]: " D < /dev/tty; [ -z "$D" ] && D=30
    read -p "  GB limit [50|0=unlimited]: " GB < /dev/tty; [ -z "$GB" ] && GB=50
    UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    EXPIRY=$(date -d "+${D} days" +%Y-%m-%d)
    cp -f "$XRAY_CONF" "${XRAY_CONF}.bak-$(date +%s)" 2>/dev/null || true
    python3 - "$UUID" "$N" "$XRAY_CONF" <<'PY'
import json,sys
u=sys.argv[1]; name=sys.argv[2]; p=sys.argv[3]
with open(p) as f: c=json.load(f)
for ib in c["inbounds"]:
    s=ib.get("settings",{})
    if "clients" not in s or ib["protocol"] not in ("vmess",): continue
    s["clients"].append({"id":u,"email":name,"level":0,"alterId":0})
with open(p,"w") as f: json.dump(c,f,indent=2)
PY
    if svc_restart xray; then
      echo "$N | $UUID | $EXPIRY | $GB | 0 | 0 | 0" >> "$ACC_DIR/v2ray.txt"
      echo -e "${GREEN}  Created: $N${NC}"; links "$UUID" "$N"
    else echo -e "${RED}  Xray restart failed${NC}"; fi
    pause;;
   2)
    [ ! -s "$ACC_DIR/v2ray.txt" ] && { echo -e "${YELLOW}  None found${NC}"; pause; continue; }
    cat -n "$ACC_DIR/v2ray.txt"
    read -p "  Number (0=cancel): " IDX < /dev/tty
    [ -z "$IDX" ] || [ "$IDX" = "0" ] && continue
    LINE=$(sed -n "${IDX}p" "$ACC_DIR/v2ray.txt")
    UUID=$(echo "$LINE"|awk -F' \| ' '{print $2}'|xargs)
    [ -n "$UUID" ] && python3 - "$UUID" "$XRAY_CONF" <<'PY'
import json,sys
u=sys.argv[1]; p=sys.argv[2]
with open(p) as f: c=json.load(f)
for ib in c["inbounds"]:
    if "clients" in ib.get("settings",{}):
        ib["settings"]["clients"]=[cl for cl in ib["settings"]["clients"] if cl.get("id")!=u]
with open(p,"w") as f: json.dump(c,f,indent=2)
PY
    svc_restart xray; sed -i "${IDX}d" "$ACC_DIR/v2ray.txt"
    echo -e "${GREEN}  Done${NC}"; pause;;
   3)
    [ ! -s "$ACC_DIR/v2ray.txt" ] && { echo -e "${YELLOW}  None found${NC}"; pause; continue; }
    while IFS='|' read -r N U EXP GB LVL MC USED; do
      N=$(echo "$N"|xargs); U=$(echo "$U"|xargs); GB=$(echo "$GB"|xargs)
      echo -e "${YELLOW}  $N${NC} | Expiry: $(echo $EXP|xargs) | ${GB}GB"
      links "$U" "$N"; echo ""
    done < "$ACC_DIR/v2ray.txt"; pause;;
   0) break;;
  esac
  done;;

 3|03)
  while true; do
  clear
  echo -e "${CYAN}  ══════════════ VLESS MENU ══════════════${NC}"
  echo -e "  ${YELLOW}[1]${NC} Create   ${YELLOW}[2]${NC} Delete   ${YELLOW}[3]${NC} List + Links   ${YELLOW}[0]${NC} Back"
  echo ""; read -p "  Choice: " VC < /dev/tty
  case $VC in
   1)
    read -p "  Account Name: " N < /dev/tty
    [ -z "$N" ] && { echo -e "${RED}  Empty${NC}"; pause; continue; }
    if ! [[ "$N" =~ ^[A-Za-z0-9_-]{1,30}$ ]]; then echo -e "${RED}  Invalid${NC}"; pause; continue; fi
    read -p "  Validity days [30]: " D < /dev/tty; [ -z "$D" ] && D=30
    read -p "  GB limit [50|0=unlimited]: " GB < /dev/tty; [ -z "$GB" ] && GB=50
    UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    EXPIRY=$(date -d "+${D} days" +%Y-%m-%d)
    cp -f "$XRAY_CONF" "${XRAY_CONF}.bak-$(date +%s)" 2>/dev/null || true
    python3 - "$UUID" "$N" "$XRAY_CONF" <<'PY'
import json,sys
u=sys.argv[1]; name=sys.argv[2]; p=sys.argv[3]
with open(p) as f: c=json.load(f)
for ib in c["inbounds"]:
    s=ib.get("settings",{})
    if "clients" not in s or ib["protocol"] not in ("vless",): continue
    s["clients"].append({"id":u,"email":name,"level":0})
with open(p,"w") as f: json.dump(c,f,indent=2)
PY
    if svc_restart xray; then
      echo "$N | $UUID | $EXPIRY | $GB | 0 | 0 | 0" >> "$ACC_DIR/v2ray.txt"
      echo -e "${GREEN}  Created: $N${NC}"
      echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&alpn=h2,http%2F1.1&type=ws&host=${DOMAIN}&path=%2Fvless#${N}-VLESS"
    else echo -e "${RED}  Failed${NC}"; fi
    pause;;
   2)
    [ ! -s "$ACC_DIR/v2ray.txt" ] && { echo -e "${YELLOW}  None${NC}"; pause; continue; }
    cat -n "$ACC_DIR/v2ray.txt"
    read -p "  Number (0=cancel): " IDX < /dev/tty
    [ -z "$IDX" ] || [ "$IDX" = "0" ] && continue
    LINE=$(sed -n "${IDX}p" "$ACC_DIR/v2ray.txt")
    UUID=$(echo "$LINE"|awk -F' \| ' '{print $2}'|xargs)
    [ -n "$UUID" ] && python3 - "$UUID" "$XRAY_CONF" <<'PY'
import json,sys
u=sys.argv[1]; p=sys.argv[2]
with open(p) as f: c=json.load(f)
for ib in c["inbounds"]:
    if "clients" in ib.get("settings",{}):
        ib["settings"]["clients"]=[cl for cl in ib["settings"]["clients"] if cl.get("id")!=u]
with open(p,"w") as f: json.dump(c,f,indent=2)
PY
    svc_restart xray; sed -i "${IDX}d" "$ACC_DIR/v2ray.txt"
    echo -e "${GREEN}  Done${NC}"; pause;;
   3)
    [ ! -s "$ACC_DIR/v2ray.txt" ] && { echo -e "${YELLOW}  None${NC}"; pause; continue; }
    while IFS='|' read -r N U EXP GB LVL MC USED; do
      N=$(echo "$N"|xargs); U=$(echo "$U"|xargs)
      echo -e "${YELLOW}  $N${NC} | Expiry: $(echo $EXP|xargs)"
      echo "vless://${U}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&path=%2Fvless#${N}-VLESS"
      echo ""
    done < "$ACC_DIR/v2ray.txt"; pause;;
   0) break;;
  esac
  done;;

 4|04)
  while true; do
  clear
  echo -e "${CYAN}  ══════════════ TROJAN MENU ══════════════${NC}"
  echo -e "  ${YELLOW}[1]${NC} Create   ${YELLOW}[2]${NC} Delete   ${YELLOW}[3]${NC} List + Links   ${YELLOW}[0]${NC} Back"
  echo ""; read -p "  Choice: " TC < /dev/tty
  case $TC in
   1)
    read -p "  Name: " N < /dev/tty
    [ -z "$N" ] && { echo -e "${RED}  Empty${NC}"; pause; continue; }
    if ! [[ "$N" =~ ^[A-Za-z0-9_-]{1,30}$ ]]; then echo -e "${RED}  Invalid${NC}"; pause; continue; fi
    read -p "  Password [random]: " TPW < /dev/tty
    [ -z "$TPW" ] && TPW=$(openssl rand -hex 16)
    read -p "  Validity [30]: " D < /dev/tty; [ -z "$D" ] && D=30
    read -p "  GB [50|0=unlimited]: " GB < /dev/tty; [ -z "$GB" ] && GB=50
    EXPIRY=$(date -d "+${D} days" +%Y-%m-%d)
    python3 - "$TPW" "$N" "$XRAY_CONF" <<'PYTROJ'
import json,sys
pw=sys.argv[1]; name=sys.argv[2]; p=sys.argv[3]
with open(p) as f: c=json.load(f)
for ib in c["inbounds"]:
    if ib.get("protocol")!="trojan": continue
    s=ib.get("settings",{})
    if "clients" not in s: continue
    s["clients"].append({"password":pw,"email":name})
with open(p,"w") as f: json.dump(c,f,indent=2)
PYTROJ
    if svc_restart xray; then
      echo "$N | $TPW | $EXPIRY | $GB | 0 | 0 | 0" >> "$ACC_DIR/trojan.txt"
      echo -e "${GREEN}  Created: $N${NC}"; trojan_links "$TPW" "$N"
    else echo -e "${RED}  Failed${NC}"; fi
    pause;;
   2)
    [ ! -s "$ACC_DIR/trojan.txt" ] && { echo -e "${YELLOW}  None${NC}"; pause; continue; }
    cat -n "$ACC_DIR/trojan.txt"
    read -p "  Number (0=cancel): " IDX < /dev/tty
    [ -z "$IDX" ] || [ "$IDX" = "0" ] && continue
    TPW=$(sed -n "${IDX}p" "$ACC_DIR/trojan.txt"|awk -F' \| ' '{print $2}'|xargs)
    [ -n "$TPW" ] && python3 - "$TPW" "$XRAY_CONF" <<'PYTDEL'
import json,sys
pw=sys.argv[1]; p=sys.argv[2]
with open(p) as f: c=json.load(f)
for ib in c["inbounds"]:
    if ib.get("protocol")!="trojan": continue
    s=ib.get("settings",{})
    if "clients" in s: s["clients"]=[cl for cl in s["clients"] if cl.get("password")!=pw]
with open(p,"w") as f: json.dump(c,f,indent=2)
PYTDEL
    svc_restart xray; sed -i "${IDX}d" "$ACC_DIR/trojan.txt"
    echo -e "${GREEN}  Done${NC}"; pause;;
   3)
    [ ! -s "$ACC_DIR/trojan.txt" ] && { echo -e "${YELLOW}  None${NC}"; pause; continue; }
    while IFS='|' read -r N TPW EXP GB LVL MC USED; do
      N=$(echo "$N"|xargs); TPW=$(echo "$TPW"|xargs)
      echo -e "${YELLOW}  $N${NC}"; trojan_links "$TPW" "$N"; echo ""
    done < "$ACC_DIR/trojan.txt"; pause;;
   0) break;;
  esac
  done;;

 5|05)
  while true; do
  clear
  echo -e "${CYAN}  ══════════════ SHADOW/UDP MENU ══════════════${NC}"
  echo -e "  ${YELLOW}[1]${NC} Create   ${YELLOW}[2]${NC} Delete   ${YELLOW}[3]${NC} List   ${YELLOW}[0]${NC} Back"
  echo ""; read -p "  Choice: " UC < /dev/tty
  case $UC in
   1)
    read -p "  Username: " U < /dev/tty
    if ! [[ "$U" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; then echo -e "${RED}  Invalid${NC}"; pause; continue; fi
    if id "$U" >/dev/null 2>&1; then echo -e "${RED}  Exists${NC}"; pause; continue; fi
    read -p "  Password: " P < /dev/tty
    [ -z "$P" ] && { echo -e "${RED}  Empty${NC}"; pause; continue; }
    read -p "  Days: " D < /dev/tty
    if useradd -m -s /bin/bash "$U" 2>/dev/null && echo "$U:$P" | chpasswd && usermod -e "$(date -d "+${D} days" +%Y-%m-%d)" "$U" 2>/dev/null; then
      echo "$U | $P | $(date -d "+${D} days" +%Y-%m-%d)" >> "$ACC_DIR/udp.txt"
      echo -e "${GREEN}  Done${NC}"
    else echo -e "${RED}  Failed${NC}"; fi
    pause;;
   2)
    [ ! -s "$ACC_DIR/udp.txt" ] && { echo -e "${YELLOW}  None${NC}"; pause; continue; }
    cat -n "$ACC_DIR/udp.txt"
    read -p "  Number (0=cancel): " IDX < /dev/tty
    [ -z "$IDX" ] || [ "$IDX" = "0" ] && continue
    U=$(sed -n "${IDX}p" "$ACC_DIR/udp.txt"|awk -F' \| ' '{print $1}')
    if [ -n "$U" ] && id "$U" >/dev/null 2>&1; then
      userdel -r "$U" 2>/dev/null || userdel "$U" 2>/dev/null
      sed -i "${IDX}d" "$ACC_DIR/udp.txt"; echo -e "${GREEN}  Done${NC}"
    else echo -e "${RED}  Error${NC}"; fi
    pause;;
   3) cat "$ACC_DIR/udp.txt" 2>/dev/null || echo "  None"; pause;;
   0) break;;
  esac
  done;;

 6|06)
  echo -e "${CYAN}  ${YELLOW}[1]${NC} Set speed limit   ${YELLOW}[2]${NC} Remove limit   ${YELLOW}[0]${NC} Back"
  read -p "  Choice: " SLC < /dev/tty
  case $SLC in
   1)
    read -p "  Username: " U < /dev/tty; read -p "  Speed (e.g. 1mbit): " SPD < /dev/tty
    tc qdisc add dev eth0 root handle 1: htb default 10 2>/dev/null || true
    UID_NUM=$(id -u "$U" 2>/dev/null)
    tc class add dev eth0 parent 1: classid 1:${UID_NUM} htb rate "$SPD" 2>/dev/null && \
      echo -e "${GREEN}  Limit set${NC}" || echo -e "${RED}  Failed${NC}"; pause;;
   2)
    read -p "  Username: " U < /dev/tty; UID_NUM=$(id -u "$U" 2>/dev/null)
    tc class del dev eth0 classid 1:${UID_NUM} 2>/dev/null && \
      echo -e "${GREEN}  Removed${NC}" || echo -e "${RED}  Not found${NC}"; pause;;
  esac;;

 7|07)
  clear; get_vps_info
  echo -e "${CYAN}  ══════════════ VPS INFORMATION ══════════════${NC}"
  echo -e "  OS         : $OS_NAME"
  echo -e "  CPU Cores  : $CPU_CORES"
  echo -e "  RAM        : ${RAM_USED}/${RAM_TOTAL} MB"
  echo -e "  Uptime     : ${UPTIME_MIN} min"
  echo -e "  Domain     : $DOMAIN"
  echo -e "  IP         : $VPS_IP"
  echo -e "  ISP        : $ISP"
  echo -e "  City       : $CITY"
  echo ""
  echo -e "${CYAN}  Active Ports:${NC}"
  ss -lntp 2>/dev/null | grep -E ':(22|80|443|444|4443|8080|8081|8090|8444|10085|10086|10087|10090) ' | awk '{print "  " $4}'
  pause;;

 8|08)
  echo -e "${CYAN}  Cleaning expired accounts...${NC}"
  expire_ssh_accounts
  echo -e "  ${GREEN}SSH expired accounts removed${NC}"
  echo -e "  ${CYAN}V2Ray/Trojan handled automatically by quota checker${NC}"
  pause;;

 9|09)
  (crontab -l 2>/dev/null | grep -v "reboot"; echo "0 0 * * * /sbin/reboot") | crontab -
  echo -e "  ${GREEN}Autoreboot scheduled at 00:00 daily${NC}"; pause;;

 10)
  clear
  echo -e "${CYAN}  ══════════════ PORT INFO ══════════════${NC}"
  ss -lntp 2>/dev/null | grep -E ':(22|80|443|444|1194|4443|8080|8081|8090|8444|10085|10086|10087|10088|10089|10090|10091) ' | \
    awk '{printf "  %-30s %s\n",$4,$NF}'
  pause;;

 11)
  echo -e "${CYAN}  Running speedtest...${NC}"
  if command -v speedtest-cli >/dev/null 2>&1; then speedtest-cli --simple
  elif command -v speedtest >/dev/null 2>&1; then speedtest
  else pip3 install speedtest-cli --break-system-packages 2>/dev/null || true
       command -v speedtest-cli >/dev/null 2>&1 && speedtest-cli --simple || echo -e "  ${RED}Not available${NC}"
  fi; pause;;

 12)
  clear
  echo -e "${CYAN}  ══════════════ SERVICE STATUS ══════════════${NC}"
  for svc in haproxy "$STUNNEL_SVC" dropbear nginx xray rocket-proxy dnsmasq udp-custom vpn-panel openvpn@server universal-bridge; do
    svc_status "$svc" && echo -e "  ${GREEN}●${NC} $svc [RUNNING]" || echo -e "  ${RED}●${NC} $svc [STOPPED]"
  done; pause;;

 13)
  > /var/log/etunnel-watchdog.log 2>/dev/null
  > /var/log/etunnel-quota.log 2>/dev/null
  > /var/log/nginx/access.log 2>/dev/null
  > /var/log/nginx/error.log 2>/dev/null
  echo -e "  ${GREEN}Logs cleared${NC}"; pause;;

 14)
  echo -e "${CYAN}  Network stats:${NC}"
  if command -v vnstat >/dev/null 2>&1; then vnstat -d
  else awk 'NR>2{printf "  %-10s RX: %s bytes  TX: %s bytes\n",$1,$2,$10}' /proc/net/dev; fi
  pause;;

 15)
  echo -e "${CYAN}  ${YELLOW}[1]${NC} Backup   ${YELLOW}[2]${NC} Restore   ${YELLOW}[0]${NC} Back"
  read -p "  Choice: " BRC < /dev/tty
  case $BRC in
   1)
    BKFILE="/root/etunnel-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar czf "$BKFILE" /etc/etunnel /usr/local/bin/menu /usr/local/etc/xray/config.json 2>/dev/null
    echo -e "  ${GREEN}Backup: $BKFILE${NC}";;
   2)
    ls /root/etunnel-backup-*.tar.gz 2>/dev/null || { echo -e "  ${YELLOW}No backups${NC}"; pause; continue; }
    read -p "  Backup file path: " BKF < /dev/tty
    [ -f "$BKF" ] && tar xzf "$BKF" -C / && echo -e "  ${GREEN}Restored${NC}" || echo -e "  ${RED}Not found${NC}";;
  esac; pause;;

 16)
  read -p "  Reboot now? [y/N]: " CONF < /dev/tty
  [ "$CONF" = "y" ] || [ "$CONF" = "Y" ] && reboot;;

 17)
  echo -e "${CYAN}  Restarting all services...${NC}"
  for svc in dropbear "$STUNNEL_SVC" haproxy nginx xray rocket-proxy dnsmasq udp-custom universal-bridge vpn-panel openvpn@server; do
    svc_restart "$svc"
    sleep 1
    if svc_status "$svc"; then
      echo -e "  ${GREEN}✓ $svc${NC}"
    else
      echo -e "  ${RED}✗ $svc${NC}"
      journalctl -u "$svc" -n 2 --no-pager 2>/dev/null | tail -2 | sed "s/^/    /"
    fi
  done; pause;;

 18)
  echo -e "  Current domain: ${GREEN}$DOMAIN${NC}"
  read -p "  New domain (blank=keep): " NEWDOM < /dev/tty
  if [ -n "$NEWDOM" ]; then
    echo "$NEWDOM" > /etc/etunnel/domain
    DOMAIN="$NEWDOM"
    echo -e "  ${GREEN}Updated to: $NEWDOM${NC}"
  fi; pause;;

 19)
  echo -e "${CYAN}  SSL for: $DOMAIN${NC}"
  echo -e "  ${YELLOW}[1]${NC} Renew LE   ${YELLOW}[2]${NC} Show info   ${YELLOW}[0]${NC} Back"
  read -p "  Choice: " SSLC < /dev/tty
  case $SSLC in
   1)
    fuser -k 80/tcp >/dev/null 2>&1 || true; sleep 1
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
      -m "admin@${DOMAIN}" --keep-until-expiring && \
      echo -e "  ${GREEN}Renewed${NC}" || echo -e "  ${RED}Failed${NC}"; pause;;
   2)
    openssl x509 -in "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" -noout -dates -issuer 2>/dev/null || \
      echo -e "  ${YELLOW}No cert found${NC}"; pause;;
  esac;;

 20)
  mkdir -p /root/udp
  echo -e "${CYAN}  Downloading UDP Custom...${NC}"
  wget --no-check-certificate "https://github.com/etunnelvpn/UDP-Custom-Script/raw/main/udp-custom-linux-amd64" -O /root/udp/udp-custom && \
    chmod +x /root/udp/udp-custom && echo -e "  ${GREEN}Done${NC}" || echo -e "  ${RED}Failed${NC}"
  case "$INIT_SYS" in systemd) systemctl restart udp-custom 2>/dev/null ;; openrc) rc-service udp-custom restart 2>/dev/null ;; esac
  pause;;

 21)
  sync; echo 3 > /proc/sys/vm/drop_caches
  echo -e "  ${GREEN}Cache cleared${NC}"; pause;;

 22)
  echo -e "  ${YELLOW}Bot notification feature — coming soon${NC}"; pause;;

 23)
  clear
  echo -e "${CYAN}  ══════════════ UPDATE SCRIPT ══════════════${NC}"
  echo -e "  Pulling latest files from GitHub..."
  echo ""
  REPO="https://raw.githubusercontent.com/etunnelvpn/script1/main"
  UPDATED=0
  FAILED=0
  _upd() {
    local src="$1" dst="$2" label="$3"
    if curl -fsSL "${REPO}/${src}" -o /tmp/_etunnel_upd 2>/dev/null; then
      cp /tmp/_etunnel_upd "$dst"
      chmod +x "$dst" 2>/dev/null || true
      echo -e "  ${GREEN}Updated:${NC} $label"
      UPDATED=$((UPDATED+1))
    else
      echo -e "  ${RED}Failed :${NC} $label"
      FAILED=$((FAILED+1))
    fi
  }
  _upd "panel/etunnel"                    "/usr/local/bin/menu"                       "Control Panel (menu)"
  _upd "panel/etunnel-watchdog.sh"        "/usr/local/bin/etunnel-watchdog.sh"        "Watchdog"
  _upd "panel/etunnel-quota-check.py"     "/usr/local/bin/etunnel-quota-check.py"     "Quota Checker"
  _upd "panel/etunnel-switch-to-ovpn.sh"  "/usr/local/bin/etunnel-switch-to-ovpn.sh"  "Switch to OpenVPN"
  _upd "panel/etunnel-switch-to-etunnel.sh" "/usr/local/bin/etunnel-switch-to-etunnel.sh" "Switch to E-TUNNEL"
  _upd "components/universal-bridge/bridge.py" "/opt/universal-bridge/bridge.py"      "Universal Bridge"
  _upd "components/rocket-proxy/rocket-proxy.js" "/opt/rocket/rocket-proxy.js"        "Rocket Proxy"
  _upd "components/vpn-panel/app.py"      "/opt/vpn-panel/app.py"                     "VPN Panel"
  _upd "config/haproxy.cfg"               "/etc/haproxy/haproxy.cfg"                  "HAProxy config"
  _upd "issue.net"                        "/etc/issue.net"                            "SSH Banner"
  cp /etc/issue.net /etc/motd 2>/dev/null || true
  echo ""
  echo -e "  ${GREEN}Updated: $UPDATED file(s)${NC}  ${RED}Failed: $FAILED${NC}"
  if [ $UPDATED -gt 0 ]; then
    echo -e "  ${CYAN}Restarting affected services...${NC}"
    svc_restart universal-bridge rocket-proxy vpn-panel 2>/dev/null || true
    echo -e "  ${GREEN}Done — no reinstall needed${NC}"
  fi
  rm -f /tmp/_etunnel_upd 2>/dev/null || true
  pause;;

 25)
  clear
  echo -e "${CYAN}  ══════════════════ CHANGE BANNER ══════════════════${NC}"
  echo -e "  Current /etc/issue.net:"
  echo -e "${YELLOW}"
  cat /etc/issue.net 2>/dev/null || echo "  (empty)"
  echo -e "${NC}"
  echo -e "  ${YELLOW}[1]${NC} Edit banner   ${YELLOW}[2]${NC} Pull from GitHub (reset)   ${YELLOW}[0]${NC} Back"
  read -p "  Choice: " BNC < /dev/tty
  case $BNC in
   1)
    echo -e "  Type new banner line by line. Type END on its own line to finish:"
    > /etc/issue.net
    while IFS= read -r bline < /dev/tty; do
      [ "$bline" = "END" ] && break
      echo "$bline" >> /etc/issue.net
    done
    cp /etc/issue.net /etc/motd
    echo -e "  ${GREEN}Banner updated${NC}";;
   2)
    echo -e "  ${CYAN}Pulling banner from GitHub...${NC}"
    if curl -fsSL "https://raw.githubusercontent.com/etunnelvpn/script1/main/issue.net" -o /etc/issue.net 2>/dev/null; then
      cp /etc/issue.net /etc/motd
      echo -e "  ${GREEN}Banner pulled from GitHub and applied${NC}"
    else
      echo -e "  ${RED}Could not reach GitHub — banner unchanged${NC}"
    fi;;
  esac; pause;;

 0) clear; exit 0;;
 *) echo -e "  ${RED}Invalid choice${NC}"; sleep 1;;
esac
done
PANEL

chmod +x /usr/local/bin/menu
bash -n /usr/local/bin/menu && check_ok "Panel syntax valid" || check_fail "Panel"
cp /usr/local/bin/menu /root/etunnel-save/etunnel 2>/dev/null || true

if ! grep -q "E-TUNNEL-AUTO-PANEL" /root/.bashrc 2>/dev/null; then
cat >> /root/.bashrc <<'RC'
# E-TUNNEL-AUTO-PANEL
if [ -t 0 ] && [ -x /usr/local/bin/menu ] && [ -z "$ETUNNEL_AUTO_PANEL" ]; then
    export ETUNNEL_AUTO_PANEL=1
    /usr/local/bin/menu
fi
RC
fi
echo ""

echo -e "${YELLOW} [15/23] fail2ban ${NC}"
if [ -d /etc/fail2ban ]; then
    cat > /etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
port = 22,443,444
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
JAIL
    svc_enable fail2ban
    svc_restart fail2ban
    sleep 2
    echo -e "  ${GREEN} fail2ban running${NC}"
else
    warn "fail2ban not installed - skipping"
fi
echo ""

echo -e "${YELLOW} [16/23] iptables ${NC}"
ipt_ins INPUT -p tcp --dport 22 -j ACCEPT
ipt_ins INPUT -p tcp --dport 80 -j ACCEPT
ipt_ins INPUT -p tcp --dport 443 -j ACCEPT
ipt_ins INPUT -p tcp --dport 444 -j ACCEPT
ipt_ins INPUT -p tcp --dport 53 -j ACCEPT
ipt_ins INPUT -p udp --dport 53 -j ACCEPT
ipt_ins INPUT -p tcp --dport 1194 -j ACCEPT
ipt_ins INPUT -p tcp --dport 8090 -j ACCEPT
ipt_app INPUT -p tcp --dport 8090 -m conntrack --ctstate NEW -m recent --set --name vpnpanel
ipt_app INPUT -p tcp --dport 8090 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 20 --name vpnpanel -j DROP
save_iptables
echo -e "  ${GREEN} iptables saved${NC}"
echo ""

echo -e "${YELLOW} [17/23] systemd Drop-ins ${NC}"
if [ "$INIT_SYS" = "systemd" ]; then
    for svc in haproxy nginx dropbear stunnel4 xray payload-proxy rocket-proxy dnsmasq udp-custom openvpn-stunnel vpn-panel universal-bridge; do
        mkdir -p /etc/systemd/system/${svc}.service.d
        cat > /etc/systemd/system/${svc}.service.d/99-etunnel-stable.conf <<EOF
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Restart=always
RestartSec=3
LimitNOFILE=1048576
OOMPolicy=continue
EOF
    done
    svc_daemon_reload
    check_ok "systemd drop-ins"
else
    echo -e "  ${YELLOW}  OpenRC  skipped${NC}"
fi
echo ""

echo -e "${YELLOW} [18/23] Watchdog ${NC}"
repo_copy "panel/etunnel-watchdog.sh" "/usr/local/bin/etunnel-watchdog.sh" || \
cat > /usr/local/bin/etunnel-watchdog.sh <<'WDPY'
#!/bin/bash
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
[ -f "$LOG" ] && [ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 5242880 ] && \
    tail -1000 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
WDPY
chmod +x /usr/local/bin/etunnel-watchdog.sh
create_oneshot_timer "etunnel-watchdog" "E-TUNNEL Watchdog" "/usr/local/bin/etunnel-watchdog.sh" "* * * * *" 30 60
echo "etunnel" > /etc/etunnel/current-mode
check_ok "Watchdog enabled"
echo ""

echo -e "${YELLOW} [18b/23] Quota Checker ${NC}"
repo_copy "panel/etunnel-quota-check.py" "/usr/local/bin/etunnel-quota-check.py" || \
cat > /usr/local/bin/etunnel-quota-check.py <<'PYCHECK'
#!/usr/bin/env python3
import json, os, re, subprocess, datetime, fcntl, shutil
ACC_FILE = "/etc/etunnel/accounts/v2ray.txt"
TROJAN_FILE = "/etc/etunnel/accounts/trojan.txt"
XRAY_CONF = "/usr/local/etc/xray/config.json"
LOG_FILE = "/var/log/etunnel-quota.log"
LOCK_FILE = "/var/run/etunnel-quota.lock"
def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except Exception: pass
def query_stats():
    try:
        r = subprocess.run(["/usr/local/bin/xray", "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>", "-reset"], capture_output=True, text=True, timeout=15)
        if r.returncode != 0: return {}
        users = {}
        for block in re.split(r'stat:\s*[{<]', r.stdout):
            nm = re.search(r'name:\s*"user>>>(.+?)>>>traffic>>>(\w+)"', block)
            vm = re.search(r'value:\s*(\d+)', block)
            if nm and vm: users[nm.group(1)] = users.get(nm.group(1), 0) + int(vm.group(1))
        return users
    except Exception: return {}
def process_file(acc_file, deltas, today):
    if not os.path.exists(acc_file): return set()
    with open(acc_file) as f: lines = [l.strip() for l in f if l.strip()]
    if not lines: return set()
    remaining = []; removed_keys = set()
    for line in lines:
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 7: remaining.append(line); continue
        name, key, expiry, gb, level, maxc, used = parts[:7]
        try: used = int(used) + int(deltas.get(name, 0))
        except ValueError: used = int(deltas.get(name, 0))
        expired = False
        try:
            if datetime.date.fromisoformat(expiry) < today: expired = True
        except Exception: pass
        over_quota = False
        try:
            gb_int = int(gb)
            if gb_int > 0 and used >= gb_int * 1073741824: over_quota = True
        except ValueError: pass
        if expired or over_quota:
            log(f"Removed {name}"); removed_keys.add(key)
        else:
            remaining.append(f"{name} | {key} | {expiry} | {gb} | {level} | {maxc} | {used}")
    with open(acc_file, "w") as f:
        if remaining: f.write("\n".join(remaining) + "\n")
    return removed_keys
def restart_xray():
    if os.path.exists("/run/systemd/system"):
        subprocess.run(["systemctl", "restart", "xray"], timeout=30)
    else:
        subprocess.run(["rc-service", "xray", "restart"], timeout=30)
def apply_removals(v_removed, t_removed):
    if not v_removed and not t_removed: return False
    try:
        shutil.copy(XRAY_CONF, XRAY_CONF + ".bak-quota")
        with open(XRAY_CONF) as f: conf = json.load(f)
        for ib in conf.get("inbounds", []):
            proto = ib.get("protocol", ""); s = ib.get("settings", {})
            if "clients" not in s: continue
            if proto in ("vless", "vmess"):
                s["clients"] = [c for c in s["clients"] if c.get("id") not in v_removed]
            elif proto == "trojan":
                s["clients"] = [c for c in s["clients"] if c.get("password") not in t_removed]
        with open(XRAY_CONF, "w") as f: json.dump(conf, f, indent=2)
        restart_xray(); return True
    except Exception: return False
def main():
    if not os.path.exists(ACC_FILE) and not os.path.exists(TROJAN_FILE): return
    try:
        lock_fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception: return
    try:
        deltas = query_stats(); today = datetime.date.today()
        v = process_file(ACC_FILE, deltas, today)
        t = process_file(TROJAN_FILE, deltas, today)
        if v or t: apply_removals(v, t)
        # Also expire SSH accounts
        ssh_file = "/etc/etunnel/accounts/ssh.txt"
        if os.path.exists(ssh_file):
            with open(ssh_file) as f: lines = [l.strip() for l in f if l.strip()]
            remaining = []
            for line in lines:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) < 3: remaining.append(line); continue
                user, _, expiry = parts[0], parts[1], parts[2]
                try:
                    if datetime.date.fromisoformat(expiry) < today:
                        subprocess.run(["userdel","-r",user], capture_output=True)
                        log(f"SSH expired: {user}")
                        continue
                except Exception: pass
                remaining.append(line)
            with open(ssh_file,"w") as f:
                if remaining: f.write("\n".join(remaining)+"\n")
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN); os.close(lock_fd)
        except Exception: pass
if __name__ == "__main__": main()
PYCHECK
chmod +x /usr/local/bin/etunnel-quota-check.py
create_oneshot_timer "etunnel-quota-check" "E-TUNNEL Quota Checker" "/usr/bin/python3 /usr/local/bin/etunnel-quota-check.py" "*/2 * * * *" 60 120
check_ok "Quota checker enabled"
echo ""

echo -e "${YELLOW} [19/23] System protection ${NC}"
if [ "$INIT_SYS" = "systemd" ]; then
    mkdir -p /var/log/journal /etc/systemd/journald.conf.d
    systemd-tmpfiles --create --prefix /var/log/journal > /dev/null 2>&1 || true
    cat > /etc/systemd/journald.conf.d/99-etunnel-persistent.conf <<'JEOF'
[Journal]
Storage=persistent
SystemMaxUse=100M
MaxRetentionSec=7day
JEOF
    systemctl restart systemd-journald 2>/dev/null || true
    echo -e "  ${GREEN} Journald persistent${NC}"
else
    echo -e "  ${YELLOW}  Journald skipped${NC}"
fi

if [ "$INIT_SYS" = "systemd" ]; then
    if ! systemctl list-timers --all 2>/dev/null | grep -q "certbot"; then
        # Try repo first, fall back to inline
        repo_copy "services/certbot-renew-etunnel.service" "/etc/systemd/system/certbot-renew-etunnel.service" || \
        cat > /etc/systemd/system/certbot-renew-etunnel.service <<'CBEOF'
[Unit]
Description=Certbot Renewal
[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload haproxy nginx"
CBEOF
        repo_copy "services/certbot-renew-etunnel.timer" "/etc/systemd/system/certbot-renew-etunnel.timer" || \
        cat > /etc/systemd/system/certbot-renew-etunnel.timer <<'CBTE'
[Unit]
Description=Certbot Timer
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
CBTE
        systemctl daemon-reload
        systemctl enable --now certbot-renew-etunnel.timer > /dev/null 2>&1
        echo -e "  ${GREEN} certbot timer${NC}"
    fi
else
    if command -v crond >/dev/null 2>&1 || command -v cron >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "certbot"; echo "0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook 'rc-service nginx reload; rc-service haproxy reload' 2>/dev/null") | crontab -
        echo -e "  ${GREEN} certbot cron${NC}"
    fi
fi

if [ "$INIT_SYS" = "systemd" ]; then
    repo_copy "services/etunnel-net-recovery.service" "/etc/systemd/system/etunnel-net-recovery.service" || \
    cat > /etc/systemd/system/etunnel-net-recovery.service <<'NETRECOV'
[Unit]
Description=E-TUNNEL Network Recovery
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'MODE=$(cat /etc/etunnel/current-mode 2>/dev/null || echo etunnel); if [ "$MODE" = "etunnel" ]; then systemctl is-active --quiet haproxy || systemctl restart haproxy nginx xray dropbear stunnel4 payload-proxy rocket-proxy dnsmasq universal-bridge; else systemctl is-active --quiet openvpn@server || systemctl restart openvpn@server openvpn-stunnel vpn-panel universal-bridge haproxy; fi'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
NETRECOV
    systemctl daemon-reload
    systemctl enable --now etunnel-net-recovery.service > /dev/null 2>&1
    echo -e "  ${GREEN} Network recovery${NC}"
else
    echo -e "  ${YELLOW}  Network recovery via systemd skipped${NC}"
fi
echo ""

echo -e "${YELLOW} [19b/23] UDP Custom ${NC}"
mkdir -p /root/udp
if [ ! -f /root/udp/udp-custom ]; then
    echo -e "  ${CYAN}Downloading UDP Custom binary...${NC}"
    wget --no-check-certificate "https://github.com/etunnelvpn/UDP-Custom-Script/raw/main/udp-custom-linux-amd64" -O /root/udp/udp-custom || warn "udp-custom download failed"
    chmod +x /root/udp/udp-custom 2>/dev/null || true
fi
if [ ! -f /root/udp/config.json ]; then
    echo -e "  ${CYAN}Downloading UDP Custom config...${NC}"
    wget --no-check-certificate "https://raw.githubusercontent.com/etunnelvpn/UDP-Custom-Script/main/config.json" -O /root/udp/config.json || warn "config download failed"
fi
create_simple_service "udp-custom" "UDP Custom" "/root/udp/udp-custom server" "network.target" "" "/root/udp/"
svc_enable udp-custom
svc_restart udp-custom 2>/dev/null || true
sleep 2
svc_status udp-custom && check_ok "UDP Custom running" || warn "UDP Custom stopped"
echo ""

echo -e "${YELLOW} [20/23] OpenVPN ${NC}"
mkdir -p /etc/openvpn/keys
EASYRSA_DIR="/etc/openvpn/easy-rsa"
EASYRSA_SRC=""
[ -d /usr/share/easy-rsa ] && EASYRSA_SRC="/usr/share/easy-rsa"
[ -d /usr/lib/easy-rsa ] && EASYRSA_SRC="/usr/lib/easy-rsa"
[ -d /usr/share/easy-rsa/easyrsa3 ] && EASYRSA_SRC="/usr/share/easy-rsa/easyrsa3"

if [ ! -f "$EASYRSA_DIR/pki/ca.crt" ] && [ -n "$EASYRSA_SRC" ]; then
    rm -rf "$EASYRSA_DIR" 2>/dev/null || true
    install -d -m 700 "$EASYRSA_DIR"
    cp -r "$EASYRSA_SRC"/* "$EASYRSA_DIR"/
    cd "$EASYRSA_DIR"
    ./easyrsa init-pki > /dev/null 2>&1
    printf '\n' | ./easyrsa build-ca nopass > /dev/null 2>&1
    ./easyrsa gen-dh > /dev/null 2>&1
    ./easyrsa --batch build-server-full server nopass > /dev/null 2>&1
    ./easyrsa gen-crl > /dev/null 2>&1
    cp pki/ca.crt pki/dh.pem pki/crl.pem pki/issued/server.crt pki/private/server.key /etc/openvpn/keys/ 2>/dev/null
    chmod 644 /etc/openvpn/keys/crl.pem 2>/dev/null || true
    cd /
fi
check_ok "OpenVPN certificates"

cat > /etc/openvpn/server.conf <<'OVPNEOF'
port 1194
proto tcp
dev tun
user nobody
group nogroup
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server.crt
key /etc/openvpn/keys/server.key
dh /etc/openvpn/keys/dh.pem
crl-verify /etc/openvpn/keys/crl.pem
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
duplicate-cn
push "redirect-gateway def1"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
tcp-nodelay
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256
mssfix 1400
persist-key
persist-tun
verb 1
OVPNEOF

cat > /etc/stunnel/openvpn.conf <<'STUNOVPN'
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
STUNOVPN
mv /etc/stunnel/openvpn.conf /etc/stunnel/openvpn.conf.disabled 2>/dev/null || true

if [ "$INIT_SYS" = "openrc" ] && [ ! -f /etc/init.d/openvpn-stunnel ]; then
    cat > /etc/init.d/openvpn-stunnel <<'OSV'
#!/sbin/openrc-run
name="openvpn-stunnel"
description="Stunnel for OpenVPN on port 443"
command="/usr/bin/stunnel"
command_args="/etc/stunnel/openvpn.conf"
command_background=true
pidfile="/var/run/stunnel-openvpn.pid"
depend() {
    need net
    after openvpn
}
OSV
    chmod +x /etc/init.d/openvpn-stunnel
elif [ "$INIT_SYS" = "systemd" ]; then
    cat > /etc/systemd/system/openvpn-stunnel.service <<'OVPNSVC'
[Unit]
Description=Stunnel for OpenVPN (443)
After=network.target openvpn@server.service
[Service]
Type=forking
PIDFile=/var/run/stunnel-openvpn.pid
ExecStart=/usr/bin/stunnel4 /etc/stunnel/openvpn.conf
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
OVPNSVC
fi

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn.conf
sysctl -p /etc/sysctl.d/99-openvpn.conf > /dev/null 2>&1
PUB_NIC=$(ip -o -4 route get 8.8.8.8 | awk '{print $5; exit}')
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$PUB_NIC" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$PUB_NIC" -j MASQUERADE
ipt_app FORWARD -i tun0 -j ACCEPT
ipt_app FORWARD -o tun0 -j ACCEPT
ipt_app INPUT -i tun0 -j ACCEPT
ipt_app OUTPUT -o tun0 -j ACCEPT
save_iptables
check_ok "OpenVPN network"
echo ""

echo -e "${YELLOW} [21/23] VPN Panel ${NC}"
PANEL_DIR="/opt/vpn-panel"
CONFIG_DIR="/opt/vpn-panel/configs"
mkdir -p "$PANEL_DIR" "$CONFIG_DIR"

PANEL_USER="etunneladmin"
PANEL_PASS=$(openssl rand -hex 12)
echo "$PANEL_USER" > /etc/etunnel/vpn-panel-user
echo "$PANEL_PASS" > /etc/etunnel/vpn-panel-pass
chmod 600 /etc/etunnel/vpn-panel-pass

# Pull app.py from repo
repo_copy "components/vpn-panel/app.py" "$PANEL_DIR/app.py" || true
# (inline heredoc below runs only if repo_copy failed)
[ -f "$PANEL_DIR/app.py" ] || cat > "$PANEL_DIR/app.py" <<'PYEOF'
import os, subprocess, shutil, functools
from flask import Flask, request, render_template_string, send_from_directory, redirect, abort, Response
app = Flask(__name__)
CONFIG_DIR = "/opt/vpn-panel/configs"
EASYRSA_DIR = "/etc/openvpn/easy-rsa"
os.makedirs(CONFIG_DIR, exist_ok=True)
PUB_IP = os.environ.get('PUB_IP', '')
if not PUB_IP:
    try: PUB_IP = subprocess.check_output(['curl', '-s', '--max-time', '3', 'https://api.ipify.org']).decode().strip()
    except Exception: PUB_IP = "127.0.0.1"
CUSTOM_DOMAIN = os.environ.get('CUSTOM_DOMAIN', '')
REMOTE = CUSTOM_DOMAIN if CUSTOM_DOMAIN else PUB_IP
PANEL_USER = os.environ.get('PANEL_USER', 'etunneladmin')
PANEL_PASS = os.environ.get('PANEL_PASS', '')

def check_auth(auth):
    if not auth or not PANEL_PASS: return False
    return auth.username == PANEL_USER and auth.password == PANEL_PASS

def requires_auth(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        auth = request.authorization
        if not check_auth(auth):
            return Response('Authentication required', 401, {'WWW-Authenticate': 'Basic realm="E-TUNNEL VPN Panel"'})
        return f(*args, **kwargs)
    return wrapper

def get_users():
    try:
        users = []
        for f in os.listdir(CONFIG_DIR):
            if not f.endswith(".ovpn"): continue
            if f.endswith("-ws.ovpn") or f.endswith("-connect.ovpn") or f.endswith("-bhz.ovpn") or f.endswith("-etunnel.ovpn"): continue
            users.append(f.replace(".ovpn", ""))
        return sorted(users)
    except Exception: return []

HTML = '''<!DOCTYPE html>
<html lang="en" dir="ltr">
<head><meta charset="UTF-8"><title>OpenVPN Panel</title>
<style>body{font-family:Tahoma;background:linear-gradient(135deg,#667eea,#764ba2);min-height:100vh;display:flex;justify-content:center;padding:20px;margin:0}
.container{max-width:800px;width:100%;background:white;padding:35px;border-radius:20px}
h2{color:#2d3436;text-align:center}
.input-group{display:flex;gap:10px;margin:20px 0}
.input-group input{flex:1;padding:12px;border:2px solid #dfe6e9;border-radius:10px}
.input-group button{padding:12px 24px;background:#00b894;color:white;border:none;border-radius:10px;font-weight:bold;cursor:pointer}
.user-item{display:flex;justify-content:space-between;padding:12px;background:#f8f9fa;border-radius:10px;margin-bottom:8px;flex-wrap:wrap;gap:8px}
.download-link{background:#0984e3;color:white;padding:6px 12px;border-radius:8px;text-decoration:none;font-size:12px}
.ws-link{background:#6c5ce7}.connect-link{background:#e17055}
.delete-link{background:#d63031;color:white;padding:6px 12px;border-radius:8px;text-decoration:none;font-size:12px}
</style></head><body><div class="container">
<h2>OpenVPN Panel </h2><p style="text-align:center;color:#636e72;">Server: {{ server_ip }}</p>
<form method="POST" action="/create" class="input-group"><input type="text" name="username" placeholder="Username" required><button>Create</button></form>
<div style="margin-top:25px;border-top:2px solid #f1f2f6;padding-top:20px"><h3>Users:</h3>
{% if users %}{% for user in users %}<div class="user-item"><span> {{ user }}</span><div>
<a class="download-link" href="/download/{{ user }}.ovpn">Direct</a>
<a class="download-link ws-link" href="/download/{{ user }}-ws.ovpn">WS</a>
<a class="download-link connect-link" href="/download/{{ user }}-connect.ovpn">Connect</a>
<a class="delete-link" href="/delete/{{ user }}" onclick="return confirm('Delete {{ user }}?');">Delete</a>
</div></div>{% endfor %}{% else %}<p style="text-align:center;color:#b2bec3;">No users found</p>{% endif %}
</div></div></body></html>'''

def restart_openvpn():
    if os.path.exists("/run/systemd/system"):
        subprocess.run(["systemctl", "restart", "openvpn@server"], capture_output=True, check=False)
    else:
        subprocess.run(["rc-service", "openvpn", "restart"], capture_output=True, check=False)

@app.route('/')
@requires_auth
def index(): return render_template_string(HTML, users=get_users(), server_ip=REMOTE)

@app.route('/create', methods=['POST'])
@requires_auth
def create_user():
    client = request.form.get('username', '').strip().replace(" ", "_").replace("..", "_")
    if not client or '..' in client or '/' in client: return redirect('/')
    ovpn_file = os.path.join(CONFIG_DIR, f"{client}.ovpn")
    if os.path.exists(ovpn_file): return redirect('/')
    try:
        subprocess.run(["./easyrsa", "--batch", "build-client-full", client, "nopass"], capture_output=True, check=False, cwd=EASYRSA_DIR)
        ca = open(os.path.join(EASYRSA_DIR, "pki/ca.crt")).read()
        cert = open(os.path.join(EASYRSA_DIR, f"pki/issued/{client}.crt")).read()
        key = open(os.path.join(EASYRSA_DIR, f"pki/private/{client}.key")).read()
        
        ovpn_direct = f"""client
dev tun
proto tcp
remote {REMOTE} 443
connect-retry 1 2
connect-timeout 4
resolv-retry 10
nobind
persist-key
persist-tun
remote-cert-tls server
tls-version-min 1.2
cipher AES-256-GCM
auth SHA256
verb 4
auth-nocache
reneg-sec 0
tun-mtu 1500
mssfix 1400
dhcp-option DNS 1.1.1.1
dhcp-option DNS 8.8.8.8
<ca>
{ca}</ca>
<cert>
{cert}</cert>
<key>
{key}</key>
"""
        with open(ovpn_file, "w") as f: f.write(ovpn_direct)
        
        ovpn_ws = f"""client
dev tun
proto tcp
remote {REMOTE} 80 tcp-client
connect-timeout  4
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
verb 4
auth-nocache
reneg-sec 0
tun-mtu 1500
mssfix 1400
dhcp-option DNS 1.1.1.1
dhcp-option DNS 8.8.8.8
<ca>
{ca}</ca>
<cert>
{cert}</cert>
<key>
{key}</key>
"""
        with open(os.path.join(CONFIG_DIR, f"{client}-ws.ovpn"), "w") as f:
            f.write(ovpn_ws)
            
        ovpn_connect = f"""client
dev tun
proto tcp
remote {REMOTE} 443 tcp-client
http-proxy {REMOTE} 80
http-proxy-option CUSTOM-HEADER Host domain.com
auth-nocache
resolv-retry infinite
route-method exe
cipher AES-128-CBC
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3
<ca>
{ca}</ca>
<cert>
{cert}</cert>
<key>
{key}</key>
"""
        with open(os.path.join(CONFIG_DIR, f"{client}-connect.ovpn"), "w") as f:
            f.write(ovpn_connect)
            
    except Exception as e: print(f"Error: {e}")
    return redirect('/')

@app.route('/delete/<username>')
@requires_auth
def delete_user(username):
    if '..' in username or '/' in username or not username.replace('_', '').isalnum(): abort(400)
    for f in [os.path.join(CONFIG_DIR, f"{username}.ovpn"), os.path.join(CONFIG_DIR, f"{username}-ws.ovpn"), os.path.join(CONFIG_DIR, f"{username}-connect.ovpn")]:
        if os.path.exists(f): os.remove(f)
    try:
        subprocess.run(["./easyrsa", "--batch", "revoke", username], capture_output=True, check=False, cwd=EASYRSA_DIR)
        subprocess.run(["./easyrsa", "gen-crl"], capture_output=True, check=False, cwd=EASYRSA_DIR)
        crl_src = os.path.join(EASYRSA_DIR, "pki/crl.pem")
        if os.path.exists(crl_src): shutil.copy(crl_src, "/etc/openvpn/keys/crl.pem")
        restart_openvpn()
    except Exception: pass
    return redirect('/')

@app.route('/download/<filename>')
@requires_auth
def download_file(filename):
    if '..' in filename or not filename.endswith('.ovpn'): abort(400)
    return send_from_directory(CONFIG_DIR, filename, as_attachment=True)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8090, debug=False, threaded=True)
PYEOF

if [ "$INIT_SYS" = "systemd" ]; then
    cat > /etc/systemd/system/vpn-panel.service <<VPNSVC
[Unit]
Description=OpenVPN Web Panel
After=network.target openvpn@server.service
[Service]
Type=simple
WorkingDirectory=$PANEL_DIR
Environment="PUB_IP=$IP"
Environment="CUSTOM_DOMAIN=$DOMAIN"
Environment="PANEL_USER=$PANEL_USER"
Environment="PANEL_PASS=$PANEL_PASS"
ExecStart=/usr/bin/python3 $PANEL_DIR/app.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
VPNSVC
elif [ "$INIT_SYS" = "openrc" ]; then
    cat > /etc/init.d/vpn-panel <<'VPNSVCO'
#!/sbin/openrc-run
name="vpn-panel"
description="OpenVPN Web Panel"
command="/usr/bin/python3"
command_args="/opt/vpn-panel/app.py"
command_background=true
pidfile="/run/vpn-panel.pid"
directory="/opt/vpn-panel"
export PUB_IP
export CUSTOM_DOMAIN
export PANEL_USER
export PANEL_PASS
depend() {
    need net
    after openvpn
}
VPNSVCO
    chmod +x /etc/init.d/vpn-panel
    cat > /etc/conf.d/vpn-panel <<CONFD
PUB_IP="$IP"
CUSTOM_DOMAIN="$DOMAIN"
PANEL_USER="$PANEL_USER"
PANEL_PASS="$PANEL_PASS"
CONFD
fi

svc_enable openvpn@server openvpn vpn-panel 2>/dev/null || true
check_ok "VPN Panel ready"
echo ""

echo -e "${YELLOW} [22/23] Final verification ${NC}"
echo -e "${YELLOW}Services:${NC}"
for svc in haproxy "$STUNNEL_SVC" dropbear nginx xray rocket-proxy dnsmasq universal-bridge; do
    check_service "$svc"
done
echo ""
echo -e "${YELLOW}Ports:${NC}"
check_port 443 "Nginx Stream" || true
check_port 80 "HAProxy" || true
check_port 53 "DNS" || true
check_port 444 "Dropbear" || true
check_port 8444 "Stunnel SSH" || true
check_port 4443 "Nginx HTTP" || true
check_port 8080 "Universal Bridge" || true
check_port 8081 "Rocket" || true
check_port 10085 "Xray API" || true
check_port 10086 "VMESS 443" || true
check_port 10087 "VLESS 443" || true
check_port 10090 "TROJAN 443" || true
echo ""

echo -e "${YELLOW} [22b/23] DPI Evasion Enhancement ${NC}"
XRAY_VER=$(/usr/local/bin/xray version 2>/dev/null | head -1 | awk '{print $2}')
echo -e "  ${GREEN}${NC} Xray version: ${XRAY_VER:-unknown}"

FP_RESULT=$(python3 - "/usr/local/etc/xray/config.json" <<'FPEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f: cfg = json.load(f)
except Exception: print("ERROR"); sys.exit(0)
changed = False
for ob in cfg.get("outbounds", []):
    ss = ob.get("streamSettings") or {}
    if ss.get("security") == "tls":
        tls = ss.setdefault("tlsSettings", {})
        if tls.get("fingerprint") != "firefox":
            tls["fingerprint"] = "firefox"; changed = True
if changed:
    with open(path, "w") as f: json.dump(cfg, f, indent=2)
    print("APPLIED")
else: print("NOCHANGE")
FPEOF
)
case "$FP_RESULT" in
    APPLIED)
        echo -e "  ${GREEN}${NC} Outbound TLS fingerprint -> firefox"
        if /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json > /dev/null 2>&1; then
            svc_restart xray; sleep 2
            svc_status xray && echo -e "  ${GREEN}${NC} Xray restarted" || echo -e "  ${RED}${NC} Xray restart failed"
        else echo -e "  ${RED}${NC} Config invalid - no restart"; fi ;;
    *) echo -e "  ${GREEN}${NC} No outbound TLS - CVE not applicable" ;;
esac

echo ""
echo -e "  ${CYAN} ECH (manual upgrade path):${NC}"
echo -e "     Your setup uses WS+TLS+fragment (strong DPI evasion)."
echo -e "     ECH requires DNS HTTPS records - not auto-applied."
echo ""

cat > /root/etunnel-browser-dialer-README.txt <<'BDREADME'
E-TUNNEL - Browser Dialer (Optional, Client-Side)
Browser Dialer gives browser-perfect TLS fingerprint.
Requirements: Xray Browser Dialer extension + env variable XRAY_BROWSER_DIALER
Documentation only. No service installed.
BDREADME
echo -e "  ${GREEN}${NC} /root/etunnel-browser-dialer-README.txt"
echo ""

cat > /root/etunnel-links.txt <<EOF
 E-TUNNEL VPN v1.0.0 by EMMKASH TECH 
Distro: ${DISTRO} | Init: ${INIT_SYS} | Pkg: ${PKG}
Domain: ${DOMAIN}
IP: ${IP}
UUID: ${UUID}
Trojan PW: ${TROJAN_PW}
SSL Mode: ${SSL_MODE}

 HTTP Custom - OpenVPN Mode 
Server: ${DOMAIN} | Port: 80 | Host: domain.com | SSL: OFF
Payload:
GET /cdn HTTP/1.30[crlf]Host: domain.com[crlf][crlf]GET-RAY / HTTP/1.900[crlf]Host:[host][crlf]Connection: Upgrade[crlf]User-Agent: [E-TUNNEL-VPN][crlf]Upgrade: websocket[crlf][crlf]

 OpenVPN Panel 
URL: http://${DOMAIN}:8090
User: ${PANEL_USER}
Pass: ${PANEL_PASS}

 To open panel: type 'etunnel' in terminal 
EOF
chmod 600 /root/etunnel-links.txt

echo -e "${BLUE}${NC}"
echo -e "${BLUE}    E-TUNNEL VPN v1.0.0 — INSTALL COMPLETE        ${NC}"
echo -e "${BLUE}    Multi-protocol VPN — SSH/V2Ray/Trojan/OpenVPN  ${NC}"
echo -e "${BLUE}    Telegram: https://t.me/emmkash                 ${NC}"
echo -e "${BLUE}${NC}"
echo ""
echo -e "   Domain   : ${GREEN}${DOMAIN}${NC}"
echo -e "   IP       : ${GREEN}${IP}${NC}"
echo -e "   UUID     : ${GREEN}${UUID}${NC}"
echo -e "   Trojan PW: ${GREEN}${TROJAN_PW}${NC}"
echo -e "   SSL Mode : ${GREEN}${SSL_MODE}${NC}"
echo -e "   OS       : ${GREEN}${DISTRO}${NC} (${INIT_SYS})"
echo ""
echo -e "${CYAN} Universal Bridge${NC}: port 8080 — SSH + OpenVPN + CONNECT"
echo -e "${CYAN} OpenVPN Panel   ${NC}: http://${DOMAIN}:8090"
echo -e "   User: ${GREEN}${PANEL_USER}${NC}  Pass: ${GREEN}${PANEL_PASS}${NC}"
echo ""
echo -e "   Details saved to: ${YELLOW}/root/etunnel-links.txt${NC}"
echo ""
echo -e "${YELLOW} Type 'menu' anytime to open the control panel${NC}"
echo -e "${YELLOW} Opening panel in 3 seconds...${NC}"
sleep 3
/usr/local/bin/menu || true