#!/bin/bash
# 
#  E-TUNNEL VPN v1.0.0 MULTI-DISTRO
#  Based on E-TUNNEL v6.8.2 — Rebranded & Upgraded by EMMKASH TECH
#  Multi-protocol VPN: SSH, VLESS, VMESS, Trojan, OpenVPN, UDP
#  Telegram: https://t.me/emmkash
# 

# ---------------------------------------------------------------
#  BASH CHECK — install bash if missing then re-exec this script
# ---------------------------------------------------------------
if [ -z "${BASH_VERSION:-}" ]; then
    echo "[!] bash not found — attempting to install..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq bash
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache bash
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q bash
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q bash
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm bash
    else
        echo "[!] Cannot install bash — no known package manager found"
        exit 1
    fi
    if command -v bash >/dev/null 2>&1; then
        echo "[+] bash installed — restarting script..."
        exec bash "$0" "$@"
    else
        echo "[!] bash install failed — cannot continue"
        exit 1
    fi
fi

set -uo pipefail

export ETUNNEL_AUTO_PANEL=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ---------------------------------------------------------------
#  ROOT CHECK — must be root, fail immediately if not
# ---------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[!] This script must be run as root${NC}"
    echo -e "${YELLOW}    Try: sudo bash $0${NC}"
    echo -e "${YELLOW}    Or:  sudo -i && bash $0${NC}"
    exit 1
fi

LOG_FILE="/root/etunnel-install.log"
> "$LOG_FILE"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# 
#  E-TUNNEL CLEANUP — remove old installation before fresh install
# 
etunnel_cleanup() {
    echo -e "${CYAN}[Clean] Removing old E-TUNNEL installation and resetting VPS...${NC}"
    log "=== FULL CLEANUP START ==="

    local _INIT="unknown"
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && _INIT="systemd"
    command -v rc-service >/dev/null 2>&1 && _INIT="openrc"

    # ── 1. Stop ALL VPN-related services ─────────────────────────────
    local _SVCS="etunnel-watchdog etunnel-quota-check etunnel-net-recovery \
        certbot-renew-etunnel universal-bridge rocket-proxy udp-custom vpn-panel \
        openvpn-stunnel payload-proxy ovpn-ws-bridge xray \
        haproxy nginx stunnel4 stunnel dropbear dnsmasq \
        openvpn@server openvpn fail2ban"
    for s in $_SVCS; do
        case "$_INIT" in
            systemd) systemctl stop "$s" 2>/dev/null; systemctl disable "$s" 2>/dev/null ;;
            openrc)  rc-service "$s" stop 2>/dev/null; rc-update del "$s" default 2>/dev/null ;;
        esac
    done

    # ── 2. Kill any leftover processes ───────────────────────────────
    pkill -9 -f "xray"            2>/dev/null || true
    pkill -9 -f "universal-bridge" 2>/dev/null || true
    pkill -9 -f "rocket-proxy"    2>/dev/null || true
    pkill -9 -f "etunnel-watchdog" 2>/dev/null || true
    pkill -9 -f "etunnel-quota"   2>/dev/null || true
    pkill -9 -f "udp-custom"      2>/dev/null || true
    pkill -9 -f "vpn-panel"       2>/dev/null || true
    pkill -9 -f "dropbear"        2>/dev/null || true
    pkill -9 -f "dnsmasq"         2>/dev/null || true

    # ── 3. Free all ports we use ─────────────────────────────────────
    for port in 80 443 444 1194 4443 5353 8080 8081 8090 8444 \
                10085 10086 10087 10088 10089 10090 10091; do
        fuser -k ${port}/tcp 2>/dev/null || true
        fuser -k ${port}/udp 2>/dev/null || true
    done
    sleep 3

    # ── 4. Purge ALL VPN packages completely ─────────────────────────
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "  ${CYAN}Removing VPN packages one by one (low-memory safe)...${NC}"
        for _pkg in haproxy nginx-full nginx-common libnginx-mod-stream \
                    stunnel4 dropbear dropbear-bin \
                    openvpn easy-rsa dnsmasq dnsmasq-base \
                    fail2ban nodejs; do
            DEBIAN_FRONTEND=noninteractive apt-get purge -y "$_pkg" 2>/dev/null || true
        done
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>/dev/null || true
    fi

    # ── 5. Remove Xray completely ────────────────────────────────────
    if [ -f /usr/local/bin/xray ]; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null || true
        rm -f /usr/local/bin/xray 2>/dev/null || true
        rm -rf /usr/local/etc/xray 2>/dev/null || true
        rm -rf /var/log/xray 2>/dev/null || true
    fi

    # ── 6. Remove ALL E-TUNNEL / GOLAN systemd units ─────────────────
    for f_unit in etunnel-watchdog.service etunnel-watchdog.timer \
             etunnel-quota-check.service etunnel-quota-check.timer \
             etunnel-net-recovery.service certbot-renew-etunnel.service \
             certbot-renew-etunnel.timer universal-bridge.service \
             rocket-proxy.service udp-custom.service vpn-panel.service \
             openvpn-stunnel.service payload-proxy.service ovpn-ws-bridge.service; do
        rm -f "/etc/systemd/system/$f_unit" 2>/dev/null
    done

    # ── 7. Remove systemd drop-ins ───────────────────────────────────
    for svc in haproxy nginx dropbear stunnel4 stunnel xray payload-proxy \
               rocket-proxy dnsmasq udp-custom openvpn-stunnel vpn-panel \
               universal-bridge; do
        rm -rf "/etc/systemd/system/${svc}.service.d" 2>/dev/null
    done

    # ── 8. Remove OpenRC scripts ─────────────────────────────────────
    for svc in universal-bridge rocket-proxy udp-custom vpn-panel \
               openvpn-stunnel etunnel-watchdog etunnel-quota-check; do
        rm -f "/etc/init.d/$svc" "/etc/conf.d/$svc" 2>/dev/null
    done

    # ── 9a. Delete SSH/UDP users created by E-TUNNEL (never deletes root or system users)
    for _accfile in /etc/etunnel/accounts/ssh.txt /etc/etunnel/accounts/udp.txt; do
        [ -f "$_accfile" ] || continue
        while IFS= read -r _line; do
            [ -z "$_line" ] && continue
            _u=$(echo "$_line" | cut -d"|" -f1 | tr -d " ")
            [ -z "$_u" ] && continue
            # Skip root and system users (UID < 1000) and common admin accounts
            case "$_u" in root|ubuntu|admin|debian|ec2-user|centos|pi) continue ;; esac
            _uid=$(id -u "$_u" 2>/dev/null || echo 0)
            [ "$_uid" -lt 1000 ] && continue
            userdel -r "$_u" 2>/dev/null || userdel "$_u" 2>/dev/null || true
        done < "$_accfile"
    done

    # ── 9. Remove ALL config directories ─────────────────────────────
    rm -rf /etc/etunnel       2>/dev/null
    rm -rf /etc/golan         2>/dev/null
    rm -rf /opt/universal-bridge 2>/dev/null
    rm -rf /opt/rocket        2>/dev/null
    rm -rf /opt/vpn-panel     2>/dev/null
    rm -rf /root/udp          2>/dev/null
    rm -rf /root/etunnel-save 2>/dev/null
    rm -rf /etc/haproxy       2>/dev/null
    rm -rf /etc/stunnel       2>/dev/null
    rm -rf /etc/openvpn       2>/dev/null
    rm -rf /etc/nginx         2>/dev/null
    rm -rf /etc/dnsmasq.d     2>/dev/null
    rm -f  /etc/dnsmasq.conf  2>/dev/null
    rm -f  /etc/default/dropbear 2>/dev/null
    rm -f  /etc/default/openvpn  2>/dev/null

    # ── 10. Remove Let's Encrypt certs (force fresh cert on reinstall) ─
    rm -rf /etc/letsencrypt   2>/dev/null
    rm -rf /var/lib/letsencrypt 2>/dev/null
    rm -rf /var/log/letsencrypt 2>/dev/null

    # ── 11. Remove all E-TUNNEL scripts and files ────────────────────
    rm -f /usr/local/bin/menu              2>/dev/null
    rm -f /usr/local/bin/etunnel-watchdog.sh  2>/dev/null
    rm -f /usr/local/bin/etunnel-quota-check.py 2>/dev/null
    rm -f /usr/local/bin/etunnel-switch-to-ovpn.sh    2>/dev/null
    rm -f /usr/local/bin/etunnel-switch-to-etunnel.sh 2>/dev/null
    rm -f /etc/issue.net           2>/dev/null
    rm -f /root/etunnel-links.txt  2>/dev/null
    rm -f /root/etunnel-install.log 2>/dev/null
    rm -f /root/etunnel-browser-dialer-README.txt 2>/dev/null
    rm -f /var/log/etunnel-watchdog.log 2>/dev/null
    rm -f /var/log/etunnel-quota.log    2>/dev/null
    rm -f /var/run/etunnel-quota.lock   2>/dev/null

    # ── 12. Remove cron entries ──────────────────────────────────────
    crontab -l 2>/dev/null | grep -v "etunnel" | grep -v "certbot" | crontab - 2>/dev/null || true

    # ── 13. Clean sysctl entries ─────────────────────────────────────
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/etunnel-disable-ipv6/,+3d' /etc/sysctl.conf 2>/dev/null
        sed -i '/etunnel-tcp-tuning/,+23d'  /etc/sysctl.conf 2>/dev/null
        sed -i '/E-TUNNEL/d'                /etc/sysctl.conf 2>/dev/null
    fi
    rm -f /etc/sysctl.d/99-openvpn.conf          2>/dev/null
    rm -f /etc/modules-load.d/etunnel-bbr.conf   2>/dev/null
    rm -f /etc/modules-load.d/zram.conf          2>/dev/null
    rm -f /etc/security/limits.d/99-etunnel.conf 2>/dev/null
    rm -f /etc/security/pwquality.conf           2>/dev/null
    rm -f /etc/fail2ban/jail.local               2>/dev/null
    rm -rf /etc/systemd/journald.conf.d          2>/dev/null

    # ── 14. Clean SSH config ─────────────────────────────────────────
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i '/E-TUNNEL/d'   /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^Banner /d'   /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^Ciphers /d'  /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^MACs /d'     /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^KexAlgorithms /d'            /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^HostKeyAlgorithms /d'        /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^PubkeyAcceptedAlgorithms /d' /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^ClientAliveInterval /d'      /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^ClientAliveCountMax /d'      /etc/ssh/sshd_config 2>/dev/null
        sed -i '/^TCPKeepAlive /d'             /etc/ssh/sshd_config 2>/dev/null
    fi
    rm -f /etc/ssh/sshd_config.d/00-etunnel-banner.conf 2>/dev/null

    # ── 15. Clean .bashrc — remove auto-panel block completely
    if [ -f /root/.bashrc ]; then
        # Remove entire E-TUNNEL auto-panel block
        sed -i '/# E-TUNNEL-AUTO-PANEL/,/^fi/d' /root/.bashrc 2>/dev/null
        sed -i '/E-TUNNEL-AUTO-PANEL/d' /root/.bashrc 2>/dev/null
        sed -i '/ETUNNEL_AUTO_PANEL/d' /root/.bashrc 2>/dev/null
        sed -i '/usr\/local\/bin\/menu/d' /root/.bashrc 2>/dev/null
        # Remove any blank lines at end of file
        sed -i -e '/^[[:space:]]*$/{ /^\s*$/d }' /root/.bashrc 2>/dev/null || true
    fi

    # ── 16. Remove iptables rules ────────────────────────────────────
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || true
    iptables -t nat -D OUTPUT     -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8090 -m conntrack --ctstate NEW -m recent --set --name vpnpanel 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8090 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 20 --name vpnpanel -j DROP 2>/dev/null || true
    iptables -D FORWARD -i tun0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o tun0 -j ACCEPT 2>/dev/null || true

    # ── 17. Reload systemd ───────────────────────────────────────────
    [ "$_INIT" = "systemd" ] && systemctl daemon-reload 2>/dev/null || true

    # ── 18. Restart SSH so it stays accessible ───────────────────────
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

    echo -e "  ${GREEN}Full VPS reset done — ready for clean install${NC}"
    log "=== FULL CLEANUP DONE ==="
    echo ""
}
# Run cleanup (always — safe even if nothing installed)
etunnel_cleanup

# 
#  DISTRO / INIT / PACKAGE-MANAGER DETECTION
# 
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID:-unknown}"; DISTRO_LIKE="${ID_LIKE:-}"
else
    DISTRO="unknown"; DISTRO_LIKE=""
fi

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    INIT_SYS="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYS="openrc"
else
    INIT_SYS="unknown"
fi

if command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v apk >/dev/null 2>&1; then PKG="apk"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v yum >/dev/null 2>&1; then PKG="yum"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
else PKG="unknown"; fi

SSH_SVC="ssh"
if [ "$INIT_SYS" = "openrc" ]; then SSH_SVC="sshd"; fi
if [ "$INIT_SYS" = "systemd" ] && systemctl list-unit-files sshd.service 2>/dev/null | grep -q sshd; then SSH_SVC="sshd"; fi

STUNNEL_SVC="stunnel4"
if [ "$PKG" != "apt" ]; then STUNNEL_SVC="stunnel"; fi

echo -e "${CYAN} Environment ${NC}"
echo -e "  Distro: ${GREEN}${DISTRO}${NC} | Init: ${GREEN}${INIT_SYS}${NC} | Pkg: ${GREEN}${PKG}${NC}"
echo ""

# 
#  PACKAGE MANAGER HELPERS
# 
pkg_update() {
    case "$PKG" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get update ;;
        apk) apk update ;;
        dnf) dnf makecache ;;
        yum) yum makecache ;;
        pacman) pacman -Sy --noconfirm ;;
    esac
}

pkg_install() {
    local pkg="$1"
    echo -e "  ${CYAN}Installing: ${pkg}${NC}"
    case "$PKG" in
        apt)
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" "$pkg" 2>/dev/null; then
                # attempt to repair broken deps then retry once
                DEBIAN_FRONTEND=noninteractive apt-get -f install -y \
                    -o Dpkg::Options::="--force-confdef" \
                    -o Dpkg::Options::="--force-confold" 2>/dev/null || true
                dpkg --configure -a 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    -o Dpkg::Options::="--force-confdef" \
                    -o Dpkg::Options::="--force-confold" "$pkg" 2>/dev/null || true
            fi ;;
        apk) apk add --no-cache "$pkg" ;;
        dnf) dnf install -y "$pkg" ;;
        yum) yum install -y "$pkg" ;;
        pacman) pacman -S --noconfirm --needed "$pkg" ;;
    esac
}

pkg_installed() {
    local pkg="$1"
    case "$PKG" in
        apt) dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" ;;
        apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
        dnf|yum) rpm -q "$pkg" >/dev/null 2>&1 ;;
        pacman) pacman -Q "$pkg" >/dev/null 2>&1 ;;
    esac
}

pkg_map() {
    local generic="$1"
    case "$PKG" in
        apt)
            case "$generic" in
                stunnel) echo "stunnel4" ;;
                nc) echo "netcat-openbsd" ;;
                iptables-persist) echo "iptables-persistent" ;;
                *) echo "$generic" ;;
            esac ;;
        apk)
            case "$generic" in
                stunnel) echo "stunnel" ;;
                dnsutils) echo "bind-tools" ;;
                nc) echo "netcat-openbsd" ;;
                uuid-runtime) echo "util-linux" ;;
                python3-websockets) echo "py3-websockets" ;;
                python3-flask) echo "py3-flask" ;;
                iptables-persist) echo "iptables" ;;
                *) echo "$generic" ;;
            esac ;;
        dnf|yum)
            case "$generic" in
                stunnel) echo "stunnel" ;;
                dnsutils) echo "bind-utils" ;;
                nc|netcat-openbsd) echo "nmap-ncat" ;;
                iptables-persist) echo "iptables-services" ;;
                *) echo "$generic" ;;
            esac ;;
        pacman)
            case "$generic" in
                stunnel) echo "stunnel" ;;
                dnsutils) echo "bind" ;;
                nc) echo "gnu-netcat" ;;
                iptables-persist) echo "iptables" ;;
                *) echo "$generic" ;;
            esac ;;
        *) echo "$generic" ;;
    esac
}

clean_pkg_locks() {
    case "$PKG" in
        apt)
            pkill -9 -f "apt" 2>/dev/null || true
            pkill -9 -f "dpkg" 2>/dev/null || true
            sleep 1
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock 2>/dev/null || true
            dpkg --configure -a 2>/dev/null || true ;;
        apk)
            rm -f /var/lib/apk/lock 2>/dev/null || true
            rm -f /lib/apk/db/lock 2>/dev/null || true ;;
        *) : ;;
    esac
}

save_iptables() {
    case "$PKG" in
        apt)
            netfilter-persistent save >/dev/null 2>&1 || true ;;
        apk)
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
            mkdir -p /etc/local.d
            cat > /etc/local.d/iptables-restore.start <<'IPTR'
#!/bin/sh
iptables-restore < /etc/iptables/rules.v4 2>/dev/null || true
ip6tables-restore < /etc/iptables/rules.v6 2>/dev/null || true
IPTR
            chmod +x /etc/local.d/iptables-restore.start
            svc_enable local >/dev/null 2>&1 || true ;;
        dnf|yum)
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
            svc_enable iptables >/dev/null 2>&1 || true ;;
        pacman)
            iptables-save > /etc/iptables/iptables.rules 2>/dev/null || true ;;
    esac
}

# 
#  INIT SYSTEM HELPERS
# 
svc_start()   { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl start "$s" 2>/dev/null ;; openrc) rc-service "$s" start 2>/dev/null ;; esac; done; }
svc_stop()    { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl stop "$s" 2>/dev/null ;; openrc) rc-service "$s" stop 2>/dev/null ;; esac; done; }
svc_enable()  { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl enable "$s" 2>/dev/null ;; openrc) rc-update add "$s" default 2>/dev/null ;; esac; done; }
svc_disable() { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl disable "$s" 2>/dev/null ;; openrc) rc-update del "$s" default 2>/dev/null ;; esac; done; }
svc_restart() { for s in "$@"; do case "$INIT_SYS" in systemd) systemctl restart "$s" 2>/dev/null ;; openrc) rc-service "$s" restart 2>/dev/null ;; esac; done; }
svc_status()  { case "$INIT_SYS" in systemd) systemctl is-active --quiet "$1" 2>/dev/null ;; openrc) rc-service "$1" status >/dev/null 2>&1 ;; esac; }
svc_exists()  { case "$INIT_SYS" in systemd) systemctl list-unit-files "$1.service" >/dev/null 2>&1 ;; openrc) [ -x "/etc/init.d/$1" ] ;; esac; }
svc_daemon_reload() { [ "$INIT_SYS" = "systemd" ] && systemctl daemon-reload 2>/dev/null; return 0; }
svc_mask()    { [ "$INIT_SYS" = "systemd" ] && systemctl mask "$1" 2>/dev/null; return 0; }
svc_unmask()  { [ "$INIT_SYS" = "systemd" ] && systemctl unmask "$1" 2>/dev/null; return 0; }

check_ok() {
    if [ $? -eq 0 ]; then echo -e "  ${GREEN} $1${NC}"; log " $1"; return 0
    else echo -e "  ${RED} $1${NC}"; log " $1"; return 1; fi
}

check_fail() {
    echo -e "${RED}${NC}"
    echo -e "${RED}    Failed at: $1${NC}"
    echo -e "${RED}${NC}"
    tail -20 "$LOG_FILE"; exit 1
}

warn() { echo -e "  ${YELLOW}  $1${NC}"; log " $1"; return 0; }

check_service() {
    local svc=$1
    if svc_status "$svc"; then
        echo -e "  ${GREEN} $svc running${NC}"; return 0
    else
        echo -e "  ${RED} $svc stopped!${NC}"
        case "$INIT_SYS" in
            systemd) journalctl -u "$svc" -n 3 --no-pager 2>/dev/null | sed 's/^/   /' ;;
            openrc) tail -3 /var/log/messages 2>/dev/null | sed 's/^/   /' ;;
        esac
        return 1
    fi
}

check_port() {
    local port=$1 name=$2
    if ss -lntH "sport = :${port}" 2>/dev/null | grep -q .; then
        echo -e "  ${GREEN} Port ${port} (${name})${NC}"; return 0
    else
        echo -e "  ${RED} Port ${port} (${name})${NC}"; return 1
    fi
}

backup_file() { [ -f "$1" ] && cp -f "$1" "${1}.bak-$(date +%s)" 2>/dev/null || true; }
ipt_ins() { iptables -C "$@" 2>/dev/null || iptables -I "$@" 2>/dev/null || true; }
ipt_app() { iptables -C "$@" 2>/dev/null || iptables -A "$@" 2>/dev/null || true; }

# 
#  SERVICE CREATION (WITH WORKDIR SUPPORT)
# 
create_simple_service() {
    local name="$1" desc="$2" exec="$3" after="${4:-network.target}" env_vars="${5:-}" workdir="${6:-}"
    if [ "$INIT_SYS" = "systemd" ]; then
        {
            echo "[Unit]"
            echo "Description=${desc}"
            echo "After=${after}"
            echo ""
            echo "[Service]"
            echo "Type=simple"
            echo "User=root"
            [ -n "$workdir" ] && echo "WorkingDirectory=${workdir}"
            [ -n "$env_vars" ] && echo "$env_vars"
            echo "ExecStart=${exec}"
            echo "Restart=always"
            echo "RestartSec=3"
            echo "LimitNOFILE=1048576"
            echo "StandardOutput=journal"
            echo "StandardError=journal"
            echo ""
            echo "[Install]"
            echo "WantedBy=multi-user.target"
        } > /etc/systemd/system/${name}.service
        systemctl daemon-reload
    elif [ "$INIT_SYS" = "openrc" ]; then
        local cmd=$(echo "$exec" | awk '{print $1}')
        local args=$(echo "$exec" | cut -d' ' -f2-)
        {
            echo "#!/sbin/openrc-run"
            echo "name=\"${name}\""
            echo "description=\"${desc}\""
            echo "command=\"${cmd}\""
            echo "command_args=\"${args}\""
            echo "command_background=true"
            echo "pidfile=\"/run/${name}.pid\""
            [ -n "$workdir" ] && echo "directory=\"${workdir}\""
            echo "depend() {"
            echo "    need net"
            echo "    after ${after%.target}"
            echo "}"
        } > /etc/init.d/${name}
        chmod +x /etc/init.d/${name}
        if [ -n "$env_vars" ]; then
            echo "$env_vars" | sed 's/^Environment="//;s/"$//' > /etc/conf.d/${name}
        fi
    fi
}

create_oneshot_timer() {
    local name="$1" desc="$2" exec="$3" cron_schedule="$4" on_boot="${5:-30}" interval="${6:-60}"
    if [ "$INIT_SYS" = "systemd" ]; then
        cat > /etc/systemd/system/${name}.service <<EOF
[Unit]
Description=${desc}
After=network.target

[Service]
Type=oneshot
ExecStart=${exec}
EOF
        cat > /etc/systemd/system/${name}.timer <<EOF
[Unit]
Description=${desc} Timer

[Timer]
OnBootSec=${on_boot}
OnUnitActiveSec=${interval}
Persistent=true
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
        systemctl daemon-reload
        systemctl enable ${name}.timer >/dev/null 2>&1
        systemctl start ${name}.timer >/dev/null 2>&1
    elif [ "$INIT_SYS" = "openrc" ]; then
        local cron_cmd=""
        command -v crond >/dev/null 2>&1 && cron_cmd="crond"
        command -v cron >/dev/null 2>&1 && cron_cmd="cron"
        if [ -n "$cron_cmd" ]; then
            (crontab -l 2>/dev/null | grep -v "${exec}"; echo "${cron_schedule} ${exec}") | crontab -
            svc_enable "$cron_cmd" >/dev/null 2>&1 || true
            svc_start "$cron_cmd" >/dev/null 2>&1 || true
        fi
    fi
}

# 
#  SYSTEM TUNING FUNCTIONS
# 
disable_ipv6() {
    if ! grep -q "etunnel-disable-ipv6" /etc/sysctl.conf 2>/dev/null; then
        cat >> /etc/sysctl.conf <<EOF

# E-TUNNEL - Disable IPv6 (etunnel-disable-ipv6)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        sysctl -p > /dev/null 2>&1 || true
    fi
}

apply_tcp_tuning() {
    local BBR_ALGO="bbr"
    if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q "bbr2"; then BBR_ALGO="bbr2"; fi
    if ! grep -q "etunnel-tcp-tuning" /etc/sysctl.conf 2>/dev/null; then
        cat >> /etc/sysctl.conf <<EOF

# E-TUNNEL - TCP Tuning (etunnel-tcp-tuning)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = ${BBR_ALGO}
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 2097152
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    fi
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    sysctl -p > /dev/null 2>&1 || true
    mkdir -p /etc/modules-load.d 2>/dev/null || true
    echo "tcp_bbr" >> /etc/modules-load.d/etunnel-bbr.conf 2>/dev/null || true
    echo "sch_fq" >> /etc/modules-load.d/etunnel-bbr.conf 2>/dev/null || true
    if [ -d /etc/security/limits.d ]; then
        cat > /etc/security/limits.d/99-etunnel.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    fi
}

apply_hyper_speed_and_ram_tuning() {
    local ram_total
    ram_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [ -z "$ram_total" ] || ! [[ "$ram_total" =~ ^[0-9]+$ ]]; then
        warn "Could not detect RAM  skipping swap tuning"
        return 0
    fi
    if [ "$ram_total" -lt 1500 ]; then
        if [ ! -f /swapfile ]; then
            log "Low memory detected (${ram_total}MB). Allocating 1GB SWAP..."
            fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 >/dev/null 2>&1
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile >/dev/null 2>&1
            grep -q "/swapfile" /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
    fi
}

setup_zram() {
    local ram_total
    ram_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [ -z "$ram_total" ] || ! [[ "$ram_total" =~ ^[0-9]+$ ]]; then
        warn "Could not detect RAM  skipping ZRAM"; return 0
    fi
    if [ "$ram_total" -ge 1024 ]; then
        log "RAM ${ram_total}MB  ZRAM not required"; return 0
    fi
    log "Low memory (${ram_total}MB). Setting up ZRAM..."
    if [ "$PKG" = "apt" ]; then
        pkg_install zram-tools
        if pkg_installed zram-tools; then
            backup_file /etc/default/zramswap
            cat > /etc/default/zramswap <<'ZRAMCFG'
ALGO=lz4
PERCENT=25
PRIORITY=100
ZRAMCFG
            modprobe zram 2>/dev/null || true
            echo "zram" > /etc/modules-load.d/zram.conf 2>/dev/null || true
            systemctl enable zramswap >/dev/null 2>&1 || true
            systemctl restart zramswap >/dev/null 2>&1 || systemctl start zramswap >/dev/null 2>&1 || true
        fi
    fi
}

fix_password_policy() {
    if [ -f /etc/pam.d/common-password ]; then
        cp /etc/pam.d/common-password /etc/pam.d/common-password.bak 2>/dev/null || true
        printf 'password\t[success=1 default=ignore]\tpam_unix.so sha512 shadow nullok\npassword\trequisite\tpam_deny.so\npassword\trequired\tpam_permit.so\n' > /etc/pam.d/common-password
    fi
    if [ -f /etc/security/pwquality.conf ] || [ "$PKG" = "apt" ]; then
        cat > /etc/security/pwquality.conf <<'PWQEOF'
minlen = 1
minclass = 0
dcredit = 0
ucredit = 0
lcredit = 0
ocredit = 0
maxrepeat = 0
maxclassrepeat = 0
maxsequence = 0
dictcheck = 0
usercheck = 0
gecoscheck = 0
enforcing = 0
PWQEOF
    fi
}

fix_cert_permissions() {
    local DOMAIN="$1"
    # Certbot sometimes saves as domain-0001, domain-0002 etc — find the real path
    local CERT_DIR=""
    for d in "/etc/letsencrypt/live/${DOMAIN}" "/etc/letsencrypt/live/${DOMAIN}-0001" \
              "/etc/letsencrypt/live/${DOMAIN}-0002" "/etc/letsencrypt/live/${DOMAIN}-0003"; do
        if [ -f "${d}/fullchain.pem" ]; then CERT_DIR="$d"; break; fi
    done
    # fallback: find any dir containing a valid cert for this domain
    if [ -z "$CERT_DIR" ]; then
        CERT_DIR=$(find /etc/letsencrypt/live -name "fullchain.pem" 2>/dev/null | \
            xargs -I{} dirname {} 2>/dev/null | head -1)
    fi
    [ -z "$CERT_DIR" ] && return 1
    chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null
    chmod 755 "${CERT_DIR}" 2>/dev/null
    chmod 644 "${CERT_DIR}"/*.pem 2>/dev/null
    mkdir -p /etc/etunnel/certs
    cp -L "${CERT_DIR}/fullchain.pem" /etc/etunnel/certs/fullchain.pem
    cp -L "${CERT_DIR}/privkey.pem"   /etc/etunnel/certs/privkey.pem
    chmod 755 /etc/etunnel /etc/etunnel/certs
    chmod 644 /etc/etunnel/certs/*.pem 2>/dev/null
}

clean_nginx_conf() {
    if [ -f /etc/nginx/nginx.conf ]; then
        if grep -qE "/etc/haproxy/certs/|/etc/letsencrypt/.*/.*\.crt" /etc/nginx/nginx.conf 2>/dev/null; then
            cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak-$(date +%s) 2>/dev/null || true
            local NGINX_USER="www-data"
            [ "$PKG" = "apk" ] && NGINX_USER="nginx"
            [ "$PKG" = "dnf" ] && NGINX_USER="nginx"
            [ "$PKG" = "yum" ] && NGINX_USER="nginx"
            [ "$PKG" = "pacman" ] && NGINX_USER="http"
            cat > /etc/nginx/nginx.conf <<NGINXBASE
user ${NGINX_USER};
worker_processes auto;
worker_rlimit_nofile 1048576;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
events {
    worker_connections 65535;
    use epoll;
    multi_accept on;
}
http {
    sendfile on; tcp_nopush on; tcp_nodelay on;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types; default_type application/octet-stream;
    access_log /var/log/nginx/access.log; gzip on;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINXBASE
        fi
    fi
}

try_letsencrypt() {
    local DOMAIN="$1"
    local LE_DIR="/etc/letsencrypt/live/${DOMAIN}"
    if [ -f "$LE_DIR/fullchain.pem" ] && \
       openssl x509 -in "$LE_DIR/fullchain.pem" -noout -issuer 2>/dev/null | grep -qi "Let's Encrypt"; then
        return 0
    fi
    local RIP=$(dig +short "${DOMAIN}" 2>/dev/null | tail -1)
    if [ "$RIP" != "$IP" ]; then return 1; fi
    fuser -k 80/tcp >/dev/null 2>&1 || true
    sleep 1
    if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
        -m "admin@${DOMAIN}" --preferred-challenges http --http-01-port 80 \
        --keep-until-expiring; then
        return 0
    fi
    return 1
}

svc_stunnel() {
    local action="$1"
    if svc_exists "$STUNNEL_SVC"; then
        case "$action" in
            start) svc_start "$STUNNEL_SVC" ;;
            stop) svc_stop "$STUNNEL_SVC" ;;
            restart) svc_restart "$STUNNEL_SVC" ;;
            enable) svc_enable "$STUNNEL_SVC" ;;
            status) svc_status "$STUNNEL_SVC" ;;
        esac
    else
        return 1
    fi
}

# 
#  MODE SWITCH SCRIPTS
# 
cat > /usr/local/bin/etunnel-switch-to-ovpn.sh << 'SWITCH_OVPN'
repo_copy "panel/etunnel-switch-to-ovpn.sh" "/usr/local/bin/etunnel-switch-to-ovpn.sh" || \
cat > /usr/local/bin/etunnel-switch-to-ovpn.sh << 'SWITCH_OVPN'
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
SWITCH_OVPN
chmod +x /usr/local/bin/etunnel-switch-to-ovpn.sh

cat > /usr/local/bin/etunnel-switch-to-etunnel.sh << 'SWITCH_ETUNNEL'
repo_copy "panel/etunnel-switch-to-etunnel.sh" "/usr/local/bin/etunnel-switch-to-etunnel.sh" || \
cat > /usr/local/bin/etunnel-switch-to-etunnel.sh << 'SWITCH_ETUNNEL'
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
SWITCH_ETUNNEL
chmod +x /usr/local/bin/etunnel-switch-to-etunnel.sh

# 
#  INSTALLATION START
# 

# ── [0a] Clone repo to /tmp/etunnel-repo ─────────────────────────────────────
REPO_URL="https://github.com/etunnelvpn/script1"
REPO_DIR="/tmp/etunnel-repo"
echo -e "${CYAN} Cloning E-TUNNEL repo from GitHub...${NC}"
rm -rf "$REPO_DIR" 2>/dev/null || true
if command -v git >/dev/null 2>&1; then
    git clone --depth=1 "$REPO_URL" "$REPO_DIR" 2>/dev/null && \
        check_ok "Repo cloned" || warn "git clone failed — will use inline fallbacks"
else
    # git not available yet — install it then clone
    pkg_install git 2>/dev/null || true
    git clone --depth=1 "$REPO_URL" "$REPO_DIR" 2>/dev/null && \
        check_ok "Repo cloned" || warn "Could not clone repo — will use inline fallbacks"
fi
# helper: copy from repo if available, otherwise proceed with inline heredoc
repo_copy() {
    local src="$1" dst="$2"
    if [ -f "${REPO_DIR}/${src}" ]; then
        cp -f "${REPO_DIR}/${src}" "$dst"
        return 0
    fi
    return 1   # caller falls back to heredoc
}
echo ""
echo -e "${BLUE}${NC}"
echo -e "${BLUE}  E-TUNNEL VPN v1.0.0 by EMMKASH TECH            ${NC}"
echo -e "${BLUE}  Multi-protocol VPN — SSH/V2Ray/Trojan/OpenVPN  ${NC}"
echo -e "${BLUE}  Telegram: https://t.me/emmkash                 ${NC}"
echo -e "${BLUE}${NC}"
echo ""

echo -e "${YELLOW} [Pre] Initial Setup ${NC}"
clean_pkg_locks
echo -e "  ${GREEN} pkg locks clean${NC}"

# Fix broken apt state before anything else (common on VPS after partial upgrades)
if [ "$PKG" = "apt" ]; then
    echo -e "  ${CYAN}Checking for broken packages...${NC}"
    if apt-get check 2>&1 | grep -q "Unmet dep\|broken"; then
        echo -e "  ${YELLOW}Broken packages detected — fixing...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get -f install -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true
        echo -e "  ${GREEN} Broken packages fixed${NC}"
    fi
fi

if [ "$PKG" = "apt" ]; then
    echo -e "  ${CYAN}Updating system packages (this may take a few minutes)...${NC}"
    echo ""
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    # repair any broken state before upgrading
    apt-get -f install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null || true
    echo ""
    echo -e "  ${GREEN} apt update + upgrade done${NC}"
fi

if [ -e /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
fi
rm -f /etc/resolv.conf 2>/dev/null || true
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
chmod 644 /etc/resolv.conf
if command -v chattr >/dev/null 2>&1; then
    if chattr +i /etc/resolv.conf 2>/dev/null; then
        if ! timeout 3 nslookup google.com >/dev/null 2>&1; then
            chattr -i /etc/resolv.conf 2>/dev/null || true
            warn "DNS failed - removed chattr"
        fi
    fi
fi
echo -e "  ${GREEN} DNS configured${NC}"

if ! command -v curl >/dev/null 2>&1; then pkg_install curl; fi
if ! command -v dig >/dev/null 2>&1; then pkg_install "$(pkg_map dnsutils)"; fi
if [ "$PKG" = "apk" ]; then
    pkg_install bash
    pkg_install shadow
fi

disable_ipv6
apply_tcp_tuning
apply_hyper_speed_and_ram_tuning
setup_zram
fix_password_policy
echo -e "  ${GREEN} IPv6 off + BBR + Hyper TCP + Smart SWAP + ZRAM${NC}"
echo ""

if [ -n "${1:-}" ]; then
    DOMAIN="$1"
    echo -e "${GREEN} Domain: ${DOMAIN}${NC}"
else
    echo -e "${CYAN}${NC}"
    echo -e "${YELLOW}Please enter your domain name:${NC}"
    echo -e "${CYAN}Example: example.com${NC}"
    echo -e "${CYAN}${NC}"
    read -p "Domain: " DOMAIN < /dev/tty
    if [ -z "$DOMAIN" ]; then echo -e "${RED} No domain entered!${NC}"; exit 1; fi
fi

if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    echo -e "${RED} Invalid domain: $DOMAIN${NC}"; exit 1
fi

IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
mkdir -p /etc/etunnel
echo "$DOMAIN" > /etc/etunnel/domain

echo -e "${CYAN}Domain: ${DOMAIN}${NC}"
echo -e "${CYAN}IP:     ${IP}${NC}"
echo -e "${CYAN}Log:    ${LOG_FILE}${NC}"
echo ""

log "=== E-TUNNEL VPN v1.0.0 Install Start ==="
log "Distro: ${DISTRO} | Init: ${INIT_SYS} | Pkg: ${PKG}"
log "Domain: ${DOMAIN}"; log "IP: ${IP}"

echo -e "${YELLOW} [0/23] Requirements check ${NC}"
if [ "$(id -u)" -ne 0 ]; then check_fail "must be root"; fi
check_ok "root privileges"

# OS version check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VER="${VERSION_ID:-unknown}"
    case "$OS_ID" in
        ubuntu)
            case "$OS_VER" in
                18.04|20.04|22.04|24.04)
                    echo -e "  ${GREEN} OS supported: Ubuntu ${OS_VER}${NC}"
                    log "OS: Ubuntu ${OS_VER} " ;;
                *)
                    warn "Ubuntu ${OS_VER} not officially tested  continuing anyway" ;;
            esac ;;
        debian)
            echo -e "  ${GREEN} OS supported: Debian ${OS_VER}${NC}"
            log "OS: Debian ${OS_VER} " ;;
        alpine)
            echo -e "  ${GREEN} OS supported: Alpine ${OS_VER}${NC}"
            log "OS: Alpine ${OS_VER} " ;;
        centos|rhel|fedora|rocky|almalinux)
            echo -e "  ${YELLOW}  OS: ${OS_ID} ${OS_VER}  limited support${NC}"
            log "OS: ${OS_ID} ${OS_VER} " ;;
        *)
            warn "Unknown OS: ${OS_ID} ${OS_VER}  continuing anyway" ;;
    esac
else
    warn "Cannot detect OS  continuing anyway"
fi

curl -4 -s --max-time 5 -o /dev/null https://google.com && check_ok "Internet connection" || check_fail "No internet"
RESOLVED_IP=$(dig +short ${DOMAIN} 2>/dev/null | tail -1)
if [ "$RESOLVED_IP" = "$IP" ]; then check_ok "DNS points to server"
else warn "DNS does not point to server - continuing"; fi
echo ""

echo -e "${YELLOW} [1/23] Installing packages ${NC}"
pkg_update
check_ok "package index updated"

PACKAGES_GENERIC="haproxy stunnel dropbear nginx-full libnginx-mod-stream curl socat openssl certbot uuid-runtime python3 dnsmasq nc fail2ban nodejs openvpn easy-rsa python3-flask python3-websockets"
DEBIAN_FRONTEND=noninteractive

MISSING=""
for g in $PACKAGES_GENERIC; do
    mapped=$(pkg_map "$g")
    if ! pkg_installed "$mapped"; then
        pkg_install "$mapped" || true
    fi
    if pkg_installed "$mapped"; then
        echo -e "  ${GREEN} ${mapped}${NC}"
    else
        pkg_install "$g" || true
        if pkg_installed "$g"; then
            echo -e "  ${GREEN} ${g}${NC}"
        else
            echo -e "  ${RED} ${g}${NC}"; MISSING="$MISSING $g"
        fi
    fi
done

# install pip3 if missing then install python packages
if ! command -v pip3 >/dev/null 2>&1; then
    pkg_install python3-pip || true
fi
if ! python3 -c "import flask" 2>/dev/null; then
    echo -e "  ${CYAN}Installing: flask (pip3)${NC}"
    pip3 install flask --break-system-packages 2>/dev/null || pip3 install flask 2>/dev/null || true
fi
if ! python3 -c "import websockets" 2>/dev/null; then
    echo -e "  ${CYAN}Installing: websockets (pip3)${NC}"
    pip3 install websockets --break-system-packages 2>/dev/null || pip3 install websockets 2>/dev/null || true
fi

if [ "$PKG" = "apt" ]; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections 2>/dev/null || true
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections 2>/dev/null || true
    pkg_install iptables-persistent || true
fi

# if nginx-full failed due to broken deps, fall back to plain nginx
if ! command -v nginx >/dev/null 2>&1; then
    echo -e "  ${CYAN}nginx-full unavailable — installing nginx...${NC}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx 2>/dev/null || true
fi

if [ -n "$MISSING" ]; then
    warn "Some packages failed to install:$MISSING (continuing)"
fi
echo ""

echo -e "${YELLOW} [2/23] Stopping services ${NC}"
for svc in haproxy nginx stunnel4 stunnel dropbear payload-proxy dnsmasq systemd-resolved udp-custom rocket-proxy openvpn@server openvpn openvpn-stunnel vpn-panel universal-bridge ovpn-ws-bridge; do
    svc_stop "$svc"
done
svc_disable nginx >/dev/null 2>&1 || true
fuser -k 80/tcp 8080/tcp 8081/tcp 443/tcp 10085/tcp 10086/tcp 10087/tcp 10088/tcp 10089/tcp 10090/tcp 10091/tcp >/dev/null 2>&1 || true
sleep 2
check_ok "Services stopped"
echo ""

echo -e "${YELLOW} [3/23] SSL Certificate ${NC}"
mkdir -p /etc/letsencrypt/live/${DOMAIN} /etc/etunnel/certs
# Reuse existing cert if valid — avoid LetsEncrypt rate limits (max 5/week)
if [ -f "/etc/etunnel/certs/fullchain.pem" ] && \
   openssl x509 -in "/etc/etunnel/certs/fullchain.pem" -noout -checkend 86400 2>/dev/null; then
    SSL_MODE="lets-encrypt"
    check_ok "Certificate exists and valid — reusing (skipping certbot)"
    echo "$SSL_MODE" > /etc/etunnel/ssl-mode
    echo ""
else
SSL_MODE="self-signed"
# Check for existing Let's Encrypt cert — certbot may have saved as domain-0001, -0002, etc.
_EXISTING_CERT_DIR=""
for _d in "/etc/letsencrypt/live/${DOMAIN}" \
           "/etc/letsencrypt/live/${DOMAIN}-0001" \
           "/etc/letsencrypt/live/${DOMAIN}-0002" \
           "/etc/letsencrypt/live/${DOMAIN}-0003"; do
    if [ -f "${_d}/fullchain.pem" ] && \
       openssl x509 -in "${_d}/fullchain.pem" -noout -issuer 2>/dev/null | grep -qi "Let's Encrypt"; then
        _EXISTING_CERT_DIR="$_d"; break
    fi
done
if [ -n "$_EXISTING_CERT_DIR" ]; then
    SSL_MODE="lets-encrypt"
    cp -L "${_EXISTING_CERT_DIR}/fullchain.pem" /etc/etunnel/certs/fullchain.pem
    cp -L "${_EXISTING_CERT_DIR}/privkey.pem"   /etc/etunnel/certs/privkey.pem
    check_ok "Let's Encrypt certificate exists"
else
    if try_letsencrypt "$DOMAIN"; then
        SSL_MODE="lets-encrypt"
        # Locate the directory certbot actually wrote to (may have -0001 suffix)
        _NEW_CERT_DIR=""
        for _d in "/etc/letsencrypt/live/${DOMAIN}" \
                   "/etc/letsencrypt/live/${DOMAIN}-0001" \
                   "/etc/letsencrypt/live/${DOMAIN}-0002" \
                   "/etc/letsencrypt/live/${DOMAIN}-0003"; do
            if [ -f "${_d}/fullchain.pem" ]; then _NEW_CERT_DIR="$_d"; break; fi
        done
        # Fallback: search all live dirs
        if [ -z "$_NEW_CERT_DIR" ]; then
            _NEW_CERT_DIR=$(find /etc/letsencrypt/live -name "fullchain.pem" 2>/dev/null | \
                xargs -I{} dirname {} 2>/dev/null | head -1)
        fi
        if [ -n "$_NEW_CERT_DIR" ]; then
            cp -L "${_NEW_CERT_DIR}/fullchain.pem" /etc/etunnel/certs/fullchain.pem
            cp -L "${_NEW_CERT_DIR}/privkey.pem"   /etc/etunnel/certs/privkey.pem
        fi
        check_ok "New Let's Encrypt certificate"
    else
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "/etc/etunnel/certs/privkey.pem" \
            -out "/etc/etunnel/certs/fullchain.pem" \
            -subj "/CN=${DOMAIN}" 2>/dev/null
        SSL_MODE="self-signed"; warn "Used self-signed certificate"
    fi
fi
chmod 755 /etc/etunnel /etc/etunnel/certs
chmod 644 /etc/etunnel/certs/*.pem 2>/dev/null
check_ok "Certificate permissions fixed"
echo "$SSL_MODE" > /etc/etunnel/ssl-mode

fi  # end of cert reuse check

echo ""

echo -e "${YELLOW} [4/23] Dropbear ${NC}"
mkdir -p /etc/default

# Pre-create /etc/issue.net so dropbear can read it at startup
if [ ! -f /etc/issue.net ]; then
    printf '+================================================+\n|          E-TUNNEL VPN BY EMMKASH TECH          |\n|           Contact: +254112735877               |\n+================================================+\n' > /etc/issue.net
fi
# Find dropbear binary
DB_BIN=""
for b in /usr/sbin/dropbear /usr/bin/dropbear /sbin/dropbear; do
    [ -x "$b" ] && DB_BIN="$b" && break
done
[ -z "$DB_BIN" ] && DB_BIN=$(command -v dropbear 2>/dev/null || echo "/usr/sbin/dropbear")

if [ "$PKG" = "apk" ]; then
    cat > /etc/conf.d/dropbear <<EOF
DROPBEAR_OPTS="-w -p 444"
DROPBEAR_BANNER="/etc/issue.net"
EOF
    svc_enable dropbear >/dev/null 2>&1 || true
else
    # Set NO_START=0 so the SysV wrapper allows start
    cat > /etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=444
DROPBEAR_EXTRA_ARGS="-w -p 444 -b /etc/issue.net"
EOF

    if [ "$INIT_SYS" = "systemd" ]; then
        # Ubuntu 22.04: dropbear ships as SysV wrapper — bypass it entirely
        # Create a native systemd unit that runs dropbear directly
        rm -f /etc/systemd/system/dropbear.service 2>/dev/null || true
        rm -rf /etc/systemd/system/dropbear.service.d 2>/dev/null || true
        cat > /etc/systemd/system/dropbear.service <<EOF
[Unit]
Description=Dropbear SSH server on port 444
After=network.target syslog.target

[Service]
Type=simple
ExecStart=${DB_BIN} -F -w -p 444
Restart=always
RestartSec=3
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable dropbear 2>/dev/null || true
    fi
fi
check_ok "Dropbear config"
echo ""

echo -e "${YELLOW} [5/23] Stunnel ${NC}"
mkdir -p /etc/haproxy /etc/stunnel
cat /etc/etunnel/certs/fullchain.pem \
    /etc/etunnel/certs/privkey.pem > /etc/haproxy/ssl.pem
chmod 600 /etc/haproxy/ssl.pem
backup_file /etc/stunnel/stunnel.conf
cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel.pid
foreground = no
[ssh_ssl]
accept = 127.0.0.1:8444
connect = 127.0.0.1:22
cert = /etc/haproxy/ssl.pem
EOF
check_ok "Stunnel config"
echo ""

echo -e "${YELLOW} [6/23] HAProxy (Port 80) ${NC}"
backup_file /etc/haproxy/haproxy.cfg
repo_copy "config/haproxy.cfg" "/etc/haproxy/haproxy.cfg" || \
cat > /etc/haproxy/haproxy.cfg <<'HAPCFG'
global
    log /dev/log local0
    maxconn 65535
defaults
    mode tcp
    timeout connect 10s
    timeout client 1h
    timeout server 1h
    timeout tunnel 1h
    option tcp-smart-accept
    option tcp-smart-connect

frontend main_80
    bind *:80
    mode tcp
    tcp-request inspect-delay 2s

    acl is_vless_p80  req.payload(0,10) -m beg "GET /vless"
    acl is_vmess_p80  req.payload(0,10) -m beg "GET /vmess"
    acl is_trojan_p80 req.payload(0,11) -m beg "GET /trojan"
    acl is_ssh_p80    req.payload(0,4) -m str "SSH-"
    acl is_connect    req.payload(0,8) -m beg "CONNECT "
    acl is_ws_payload req.payload(0,4) -m beg "GET "

    tcp-request content accept if is_connect
    tcp-request content accept if is_ws_payload

    use_backend v2ray_vless_p80 if is_vless_p80
    use_backend v2ray_vmess_p80 if is_vmess_p80
    use_backend v2ray_trojan_p80 if is_trojan_p80
    use_backend ssh_direct_p80 if is_ssh_p80
    default_backend universal_bridge_backend

backend universal_bridge_backend
    mode tcp
    server universal_bridge 127.0.0.1:8080 check

backend v2ray_vless_p80
    mode tcp
    server xray_vless_p80 127.0.0.1:10088 check

backend v2ray_vmess_p80
    mode tcp
    server xray_vmess_p80 127.0.0.1:10089 check

backend v2ray_trojan_p80
    mode tcp
    server xray_trojan_p80 127.0.0.1:10091 check

backend ssh_direct_p80
    mode tcp
    server sshd_direct 127.0.0.1:22 check
HAPCFG
haproxy -c -f /etc/haproxy/haproxy.cfg > /dev/null 2>&1 && check_ok "HAProxy config valid" || check_fail "HAProxy config"
echo ""

echo -e "${YELLOW} [7/23] Nginx ${NC}"
clean_nginx_conf
rm -f /etc/nginx/sites-enabled/default
mkdir -p /etc/nginx/stream-enabled
repo_copy "config/nginx-ssl-router.conf" "/etc/nginx/stream-enabled/ssl-router.conf" || \
cat > /etc/nginx/stream-enabled/ssl-router.conf << 'EOF'
stream {
    map $ssl_preread_alpn_protocols $backend {
        ~h2          v2ray_backend;
        ~http/1.1    v2ray_backend;
        default      ssh_ssl_backend;
    }
    upstream v2ray_backend { server 127.0.0.1:4443; }
    upstream ssh_ssl_backend { server 127.0.0.1:8444; }
    server {
        listen 443 reuseport;
        proxy_pass $backend;
        ssl_preread on;
        proxy_timeout 1h;
        proxy_connect_timeout 10s;
    }
}
EOF
if ! grep -q "stream-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
    if grep -q "^http {" /etc/nginx/nginx.conf 2>/dev/null; then
        sed -i '/^http {/i include /etc/nginx/stream-enabled/*.conf;' /etc/nginx/nginx.conf
    else
        echo "include /etc/nginx/stream-enabled/*.conf;" >> /etc/nginx/nginx.conf
    fi
fi
cat > /etc/nginx/sites-enabled/xray-proxy <<EOF
server {
    listen 4443 ssl http2 default_server reuseport;
    server_name _;
    ssl_certificate /etc/etunnel/certs/fullchain.pem;
    ssl_certificate_key /etc/etunnel/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location /vmess {
        proxy_pass http://127.0.0.1:10086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_buffering off;
    }
    location /vless {
        proxy_pass http://127.0.0.1:10087;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_buffering off;
    }
    location /trojan {
        proxy_pass http://127.0.0.1:10090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_buffering off;
    }
    location / { return 404; }
}
EOF
nginx -t > /dev/null 2>&1 && check_ok "Nginx config valid" || check_fail "Nginx config"
echo ""

echo -e "${YELLOW} [8/23] Universal Bridge ${NC}"
mkdir -p /opt/universal-bridge
repo_copy "components/universal-bridge/bridge.py" "/opt/universal-bridge/bridge.py" || \
cat > /opt/universal-bridge/bridge.py << 'BRIDGEEOF'
#!/usr/bin/env python3
import asyncio, hashlib, base64, socket
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
def make_accept_key(key):
    return base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
async def read_payload(reader, timeout=1.0, idle=0.3):
    data = b""; loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        try:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=idle)
            if not chunk: break
            data += chunk
            deadline = asyncio.get_event_loop().time() + timeout  # compatible py3.8+
        except asyncio.TimeoutError: break
    return data
async def handle_client(cr, cw):
    peer = cw.get_extra_info('peername')
    print(f"[+] New: {peer}", flush=True)
    try:
        sock = cw.get_extra_info('socket')
        if sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except: pass
    payload = await read_payload(cr, 1.0, 0.3)
    if not payload: cw.close(); return
    first = payload.split(b'\r\n', 1)[0].decode('utf-8', errors='ignore')
    forward_first = b""; target = None; proto = ""
    if first.startswith('CONNECT '):
        cw.write(b'HTTP/1.1 200 Connection established\r\nProxy-Agent: E-TUNNEL\r\n\r\n'); await cw.drain()
        target = ('127.0.0.1', 1194); proto = "OpenVPN-CONNECT"
        try: forward_first = await asyncio.wait_for(cr.read(64), timeout=3)
        except: pass
    else:
        ws_key = 'dGhlIHNhbXBsZSBub25jZQ=='
        try:
            for line in payload.decode('utf-8', errors='ignore').split('\r\n'):
                if ':' in line:
                    k, v = line.split(':', 1)
                    if k.strip().lower() == 'sec-websocket-key': ws_key = v.strip(); break
        except: pass
        cw.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + make_accept_key(ws_key) + '\r\n\r\n').encode())
        await cw.drain()
        try: forward_first = await asyncio.wait_for(cr.read(64), timeout=5)
        except: pass
        if forward_first.startswith(b'SSH-'): target = ('127.0.0.1', 22); proto = "SSH"
        else: target = ('127.0.0.1', 1194); proto = "OpenVPN-WS"
    try:
        tr, tw = await asyncio.open_connection(*target)
        ts = tw.get_extra_info('socket')
        if ts:
            ts.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            ts.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception as e:
        print(f"[!] {proto} fail: {e}", flush=True); cw.close(); return
    if forward_first:
        try: tw.write(forward_first); await tw.drain()
        except: pass
    print(f"[+] Active: {peer} <-> {proto}", flush=True)
    async def pump(src, dst):
        try:
            while True:
                try: data = await asyncio.wait_for(src.read(65536), timeout=600)
                except asyncio.TimeoutError: continue
                if not data: break
                try: dst.write(data); await dst.drain()
                except: break
        except: pass
    try:
        await asyncio.gather(pump(cr, tw), pump(tr, cw))
    finally:
        try: tw.close()
        except: pass
        try: cw.close()
        except: pass
        print(f"[-] Closed: {peer} ({proto})", flush=True)
async def main():
    import time, socket as _sock
    for _attempt in range(10):
        try:
            server = await asyncio.start_server(handle_client, '127.0.0.1', 8080)
            print('Universal Bridge on 127.0.0.1:8080', flush=True)
            async with server: await server.serve_forever()
            return
        except OSError:
            print(f'[~] Port 8080 busy, retrying {_attempt+1}/10...', flush=True)
            await asyncio.sleep(3)
if __name__ == '__main__':
    try: asyncio.run(main())
    except KeyboardInterrupt: pass
BRIDGEEOF

python3 -m py_compile /opt/universal-bridge/bridge.py && check_ok "Bridge syntax" || check_fail "Bridge syntax"
PY3_BIN=$(command -v python3 2>/dev/null || echo "/usr/bin/python3")
create_simple_service "universal-bridge" "Universal Bridge" "${PY3_BIN} /opt/universal-bridge/bridge.py" "network.target"
check_ok "Universal Bridge installed"
echo ""

echo -e "${YELLOW} [9/23] Rocket Proxy ${NC}"
mkdir -p /opt/rocket
repo_copy "components/rocket-proxy/rocket-proxy.js" "/opt/rocket/rocket-proxy.js" || \
cat > /opt/rocket/rocket-proxy.js <<'JSEOF'
const http = require('http');
const net = require('net');
const server = http.createServer((req, res) => { res.writeHead(403); res.end('Forbidden'); });
server.on('upgrade', (req, socket, head) => {
    socket.setNoDelay(true);
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n');
    const sshSocket = net.connect(22, '127.0.0.1', () => {
        sshSocket.setNoDelay(true);
        if (head && head.length) sshSocket.write(head);
        socket.on('data', (c) => { if (!sshSocket.destroyed) sshSocket.write(c); });
        sshSocket.on('data', (c) => { if (!socket.destroyed) socket.write(c); });
        socket.on('end', () => sshSocket.end());
        sshSocket.on('end', () => socket.end());
        socket.on('error', () => sshSocket.destroy());
        sshSocket.on('error', () => socket.destroy());
    });
});
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;
function startServer(attempt) {
    server.listen(8081, '127.0.0.1', () => { console.log('Rocket Proxy on 8081'); });
}
server.on('error', (e) => {
    if (e.code === 'EADDRINUSE') {
        console.log('[~] Port 8081 busy, retrying in 3s...');
        setTimeout(() => { server.close(); startServer(); }, 3000);
    }
});
startServer();
JSEOF
# Find Node.js binary and create service with hardcoded path
NODE_BIN=$(command -v nodejs 2>/dev/null || command -v node 2>/dev/null)
if [ -z "$NODE_BIN" ]; then
    warn "Node.js not found — rocket-proxy will be unavailable"
    NODE_BIN="/usr/bin/nodejs"
fi
echo -e "  ${CYAN}Node.js: ${NODE_BIN}${NC}"
create_simple_service "rocket-proxy" "E-TUNNEL Rocket Proxy" "${NODE_BIN} /opt/rocket/rocket-proxy.js" "network.target"
check_ok "Rocket Proxy"
echo ""

echo -e "${YELLOW} [10/23] Xray ${NC}"
pkill -9 -f install-release 2>/dev/null || true
pkill -9 -f xray 2>/dev/null || true
echo -e "  ${CYAN}Downloading and installing Xray...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
[ -f "/usr/local/bin/xray" ] && check_ok "Xray installed" || check_fail "Xray"
rm -rf /etc/systemd/system/xray.service.d/
svc_daemon_reload
UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
TROJAN_PW=$(openssl rand -hex 16)
echo "$TROJAN_PW" > /etc/etunnel/trojan_default_pw
mkdir -p /var/log/xray
svc_stop systemd-resolved dnsmasq
svc_disable systemd-resolved dnsmasq
svc_mask systemd-resolved
fuser -k 53/tcp 53/udp >/dev/null 2>&1 || true
sleep 1
backup_file /usr/local/etc/xray/config.json
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "api": { "tag": "api", "services": ["HandlerService", "StatsService"] },
  "stats": {},
  "dns": { "servers": ["8.8.8.8", "1.1.1.1"] },
  "policy": { "levels": { "0": { "handshake": 3, "connIdle": 300, "uplinkOnly": 0, "downlinkOnly": 0 } }, "system": { "statsInboundUplink": true, "statsInboundDownlink": true } },
  "routing": { "rules": [ { "type": "field", "inboundTag": ["api"], "outboundTag": "api" } ] },
  "inbounds": [
    { "tag": "api", "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" } },
    { "tag": "vmess-ws-443", "port": 10086, "listen": "127.0.0.1", "protocol": "vmess", "settings": { "clients": [{ "id": "${UUID}", "alterId": 0, "level": 0, "email": "admin-default" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" }, "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls"] } },
    { "tag": "vless-ws-443", "port": 10087, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "${UUID}", "level": 0, "email": "admin-default" }], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" }, "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls"] } },
    { "tag": "vless-ws-80", "port": 10088, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "${UUID}", "level": 0, "email": "admin-default" }], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" }, "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } } },
    { "tag": "vmess-ws-80", "port": 10089, "listen": "127.0.0.1", "protocol": "vmess", "settings": { "clients": [{ "id": "${UUID}", "alterId": 0, "level": 0, "email": "admin-default" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" }, "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } } },
    { "tag": "trojan-ws-443", "port": 10090, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{ "password": "${TROJAN_PW}", "email": "admin-trojan" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" }, "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } }, "sniffing": { "enabled": true, "destOverride": ["http", "tls"] } },
    { "tag": "trojan-ws-80", "port": 10091, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{ "password": "${TROJAN_PW}", "email": "admin-trojan" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" }, "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } } }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct", "streamSettings": { "sockopt": { "tcpMptcp": true, "tcpNoDelay": true, "tcpFastOpen": true } } },
    { "protocol": "blackhole", "tag": "block" },
    { "protocol": "freedom", "tag": "api" }
  ]
}
EOF
if /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json > /dev/null 2>&1; then
    check_ok "Xray config valid"
else check_fail "Xray config invalid"; fi
echo ""

echo -e "${YELLOW} [11/23] Starting services ${NC}"
svc_enable dropbear "$STUNNEL_SVC" haproxy nginx xray rocket-proxy universal-bridge >/dev/null 2>&1
echo -e "  ${CYAN}dropbear...${NC}"
systemctl daemon-reload 2>/dev/null || true
svc_restart dropbear; sleep 2
if ! check_service "dropbear" 2>/dev/null; then
    warn "dropbear failed — retrying once..."
    systemctl daemon-reload 2>/dev/null || true
    svc_restart dropbear; sleep 2
    check_service "dropbear" 2>/dev/null || warn "dropbear still failed — SSH port 22 still works, continuing"
fi
echo -e "  ${CYAN}${STUNNEL_SVC}...${NC}"; svc_restart "$STUNNEL_SVC"; sleep 1; check_service "$STUNNEL_SVC" || check_fail "stunnel"
# Kill anything on 8080/8081 before starting bridge services
fuser -k 8080/tcp 8081/tcp 2>/dev/null || true
pkill -9 -f "bridge.py" 2>/dev/null || true
pkill -9 -f "rocket-proxy.js" 2>/dev/null || true
sleep 3
echo -e "  ${CYAN}rocket-proxy...${NC}"; svc_restart rocket-proxy; sleep 1; check_service "rocket-proxy" || warn "rocket-proxy failed — WebSocket SSH on 8081 unavailable, continuing"
echo -e "  ${CYAN}universal-bridge...${NC}"; svc_restart universal-bridge; sleep 2; check_service "universal-bridge" || warn "universal-bridge failed — OpenVPN WS proxy unavailable, continuing"
fuser -k 80/tcp >/dev/null 2>&1 || true
sleep 1
echo -e "  ${CYAN}haproxy...${NC}"; svc_restart haproxy; sleep 1; check_service "haproxy" || check_fail "haproxy"
echo -e "  ${CYAN}nginx...${NC}"; svc_restart nginx; sleep 1; check_service "nginx" || check_fail "nginx"
fuser -k 10085/tcp 10086/tcp 10087/tcp 10088/tcp 10089/tcp 10090/tcp 10091/tcp >/dev/null 2>&1 || true
sleep 1
echo -e "  ${CYAN}xray...${NC}"; svc_restart xray; sleep 2; check_service "xray" || check_fail "xray"
echo ""


# ── Download and run Part 2 ─────────────────────────────────────────────
echo -e "${CYAN} Downloading installer part 2...${NC}"
PART2_URL="https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel-v1.0.0-p2.sh"
curl -fsSL "$PART2_URL" -o /tmp/etunnel-p2 2>/dev/null || {
    echo -e "${RED}[!] Failed to download part 2 — check internet${NC}"; exit 1
}
chmod +x /tmp/etunnel-p2

# Export variables
export DOMAIN IP UUID TROJAN_PW SSL_MODE DISTRO INIT_SYS PKG
export PANEL_USER PANEL_PASS
export STUNNEL_SVC SSH_SVC LOG_FILE

# Export all functions by writing them to a temp file Part 2 will source
declare -f > /tmp/etunnel-funcs.sh
export ETUNNEL_FUNCS_FILE="/tmp/etunnel-funcs.sh"

# Run Part 2 with bash (not exec) so it can source the functions
bash /tmp/etunnel-p2 "$@"