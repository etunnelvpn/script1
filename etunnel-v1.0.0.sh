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
    sleep 1

    # ── 4. Purge ALL VPN packages completely ─────────────────────────
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "  ${CYAN}Purging VPN packages...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get purge -y \
            haproxy nginx nginx-full nginx-common libnginx-mod-stream \
            stunnel4 dropbear dropbear-bin \
            openvpn easy-rsa \
            dnsmasq dnsmasq-base \
            fail2ban \
            nodejs \
            2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get autoclean -y  2>/dev/null || true
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
    rm -f /usr/local/bin/etunnel              2>/dev/null
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

    # ── 15. Clean .bashrc ────────────────────────────────────────────
    sed -i '/E-TUNNEL-AUTO-PANEL/d'    /root/.bashrc 2>/dev/null
    sed -i '/E-TUNNEL-AUTO-PANEL/,/fi/d' /root/.bashrc 2>/dev/null

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
echo ""

echo -e "${YELLOW} [4/23] Dropbear ${NC}"
mkdir -p /etc/default

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
ExecStart=${DB_BIN} -F -w -p 444 -b /etc/issue.net
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
    data = b""; deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        try:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=idle)
            if not chunk: break
            data += chunk
            deadline = asyncio.get_event_loop().time() + timeout
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
    server = await asyncio.start_server(handle_client, '127.0.0.1', 8080)
    print("Universal Bridge on 127.0.0.1:8080", flush=True)
    async with server: await server.serve_forever()
if __name__ == '__main__':
    try: asyncio.run(main())
    except KeyboardInterrupt: pass
BRIDGEEOF

python3 -m py_compile /opt/universal-bridge/bridge.py && check_ok "Bridge syntax" || check_fail "Bridge syntax"
create_simple_service "universal-bridge" "Universal Bridge" "/usr/bin/python3 /opt/universal-bridge/bridge.py" "network.target ssh.service openvpn@server.service"
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
server.listen(8081, '127.0.0.1', () => { console.log('Rocket Proxy on 8081'); });
JSEOF
create_simple_service "rocket-proxy" "E-TUNNEL Rocket Proxy" "/usr/bin/node /opt/rocket/rocket-proxy.js" "network.target"
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
fuser -k 8080/tcp 8081/tcp >/dev/null 2>&1 || true
sleep 1
echo -e "  ${CYAN}rocket-proxy...${NC}"; svc_restart rocket-proxy; sleep 1; check_service "rocket-proxy" || check_fail "rocket-proxy"
echo -e "  ${CYAN}universal-bridge...${NC}"; svc_restart universal-bridge; sleep 1; check_service "universal-bridge" || check_fail "universal-bridge"
fuser -k 80/tcp >/dev/null 2>&1 || true
sleep 1
echo -e "  ${CYAN}haproxy...${NC}"; svc_restart haproxy; sleep 1; check_service "haproxy" || check_fail "haproxy"
echo -e "  ${CYAN}nginx...${NC}"; svc_restart nginx; sleep 1; check_service "nginx" || check_fail "nginx"
fuser -k 10085/tcp 10086/tcp 10087/tcp 10088/tcp 10089/tcp 10090/tcp 10091/tcp >/dev/null 2>&1 || true
sleep 1
echo -e "  ${CYAN}xray...${NC}"; svc_restart xray; sleep 2; check_service "xray" || check_fail "xray"
echo ""

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

repo_copy "panel/etunnel" "/usr/local/bin/etunnel" || \
cat > /usr/local/bin/etunnel <<'PANEL'
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
on_off() { svc_status "$1" && echo -e "${GREEN}ON/ ${NC}" || echo -e "${RED}OFF${NC}"; }

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
    SSH_COUNT=$(grep -c '.' "$ACC_DIR/ssh.txt" 2>/dev/null || echo 0)
    V2RAY_COUNT=$(grep -c '.' "$ACC_DIR/v2ray.txt" 2>/dev/null || echo 0)
    TROJAN_COUNT=$(grep -c '.' "$ACC_DIR/trojan.txt" 2>/dev/null || echo 0)
    UDP_COUNT=$(grep -c '.' "$ACC_DIR/udp.txt" 2>/dev/null || echo 0)
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

echo -e "${MAGENTA}  ┌──────────────────────────────────────────────────────────┐${NC}"
echo -e "${MAGENTA}  │       PREMIUM AUTOSCRIPT BY EMMKASH TECH                 │${NC}"
echo -e "${MAGENTA}  │       Contact: +254112735877                             │${NC}"
echo -e "${MAGENTA}  └──────────────────────────────────────────────────────────┘${NC}"
echo ""

echo -e "${CYAN}  ┌──────────────────────────────────────────────────────────┐${NC}"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "System OS"     "$OS_NAME"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "Core System"   "$CPU_CORES"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "Server RAM"    "${RAM_USED}/${RAM_TOTAL} MB"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "Uptime Server" "${UPTIME_MIN} minutes"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "Domain"        "$DOMAIN"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "IP VPS"        "$VPS_IP"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "ISP"           "$ISP"
printf "${CYAN}  │${NC}  ${GREEN}●${NC} %-18s = %-32s${CYAN}│${NC}\n" "City"          "$CITY"
echo -e "${CYAN}  └──────────────────────────────────────────────────────────┘${NC}"
echo ""

echo -e "  ${YELLOW}          >>> YOUR ACCOUNT ON VPS <<<${NC}"
echo -e "${CYAN}  ┌──────────────────────────────────────────────────────────┐${NC}"
printf "${CYAN}  │${NC}    SSH/OPENVPN      ${CYAN}►${NC} %-4s ACCOUNT PREMIUM                ${CYAN}│${NC}\n" "$SSH_COUNT"
printf "${CYAN}  │${NC}    VMESS/WS/GRPC    ${CYAN}►${NC} %-4s ACCOUNT PREMIUM                ${CYAN}│${NC}\n" "$V2RAY_COUNT"
printf "${CYAN}  │${NC}    VLESS/WS/GRPC    ${CYAN}►${NC} %-4s ACCOUNT PREMIUM                ${CYAN}│${NC}\n" "$V2RAY_COUNT"
printf "${CYAN}  │${NC}    TROJAN/WS/GRPC   ${CYAN}►${NC} %-4s ACCOUNT PREMIUM                ${CYAN}│${NC}\n" "$TROJAN_COUNT"
printf "${CYAN}  │${NC}    SHADOWSOCKS/WS   ${CYAN}►${NC} %-4s ACCOUNT PREMIUM                ${CYAN}│${NC}\n" "$UDP_COUNT"
echo -e "${CYAN}  └──────────────────────────────────────────────────────────┘${NC}"
echo ""

SSH_S=$(on_off dropbear); NGINX_S=$(on_off nginx)
XRAY_S=$(svc_status xray && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}")
WS_S=$(on_off rocket-proxy); DROP_S=$(on_off dropbear)
HAP_S=$(svc_status haproxy && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}")
echo -e "${CYAN}  ┌──────────────────────┬──────────────────────┬────────────────────┐${NC}"
printf "${CYAN}  │${NC} SSH    : %-13b${CYAN}│${NC} NGINX   : %-13b${CYAN}│${NC} XRAY  : %-11b${CYAN}│${NC}\n" "$SSH_S" "$NGINX_S" "$XRAY_S"
printf "${CYAN}  │${NC} WS-ePRO: %-13b${CYAN}│${NC} DROPBEAR: %-13b${CYAN}│${NC} HAPROXY: %-10b${CYAN}│${NC}\n" "$WS_S" "$DROP_S" "$HAP_S"
echo -e "${CYAN}  └──────────────────────┴──────────────────────┴────────────────────┘${NC}"
echo ""

echo -e "${CYAN}  ┌──────────────────────────┬────────────────────────────┬──────────────────────┐${NC}"
printf "${CYAN}  │${NC} ${YELLOW}[01]${NC} %-21s${CYAN}│${NC} ${YELLOW}[08]${NC} %-23s${CYAN}│${NC} ${YELLOW}[15]${NC} %-18s${CYAN}│${NC}\n" "SSH MENU"       "DELL ALL EXP"   "BCKP/RSTR"
printf "${CYAN}  │${NC} ${YELLOW}[02]${NC} %-21s${CYAN}│${NC} ${YELLOW}[09]${NC} %-23s${CYAN}│${NC} ${YELLOW}[16]${NC} %-18s${CYAN}│${NC}\n" "VMESS MENU"     "AUTOREBOOT"     "REBOOT"
printf "${CYAN}  │${NC} ${YELLOW}[03]${NC} %-21s${CYAN}│${NC} ${YELLOW}[10]${NC} %-23s${CYAN}│${NC} ${YELLOW}[17]${NC} %-18s${CYAN}│${NC}\n" "VLESS MENU"     "INFO PORT"      "RESTART"
printf "${CYAN}  │${NC} ${YELLOW}[04]${NC} %-21s${CYAN}│${NC} ${YELLOW}[11]${NC} %-23s${CYAN}│${NC} ${YELLOW}[18]${NC} %-18s${CYAN}│${NC}\n" "TROJAN MENU"    "SPEEDTEST"      "DOMAIN"
printf "${CYAN}  │${NC} ${YELLOW}[05]${NC} %-21s${CYAN}│${NC} ${YELLOW}[12]${NC} %-23s${CYAN}│${NC} ${YELLOW}[19]${NC} %-18s${CYAN}│${NC}\n" "SHADOW MENU"    "RUNNING"        "CERT SSL"
printf "${CYAN}  │${NC} ${YELLOW}[06]${NC} %-21s${CYAN}│${NC} ${YELLOW}[13]${NC} %-23s${CYAN}│${NC} ${YELLOW}[20]${NC} %-18s${CYAN}│${NC}\n" "LIMIT SPEED"    "CLEAR LOG"      "INS. UDP"
printf "${CYAN}  │${NC} ${YELLOW}[07]${NC} %-21s${CYAN}│${NC} ${YELLOW}[14]${NC} %-23s${CYAN}│${NC} ${YELLOW}[21]${NC} %-18s${CYAN}│${NC}\n" "VPS INFO"       "Cek Bandwith"   "CLEAR CACHE"
printf "${CYAN}  │${NC} ${YELLOW}[22]${NC} %-21s${CYAN}│${NC} ${YELLOW}[23]${NC} %-23s${CYAN}│${NC}                      ${CYAN}│${NC}\n" "BOT NOTIF"      "UPDATE SCRIPT"
echo -e "${CYAN}  └──────────────────────────┴────────────────────────────┴──────────────────────┘${NC}"
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
  for svc in haproxy "$STUNNEL_SVC" dropbear nginx xray rocket-proxy dnsmasq udp-custom vpn-panel openvpn@server openvpn-stunnel universal-bridge; do
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
    tar czf "$BKFILE" /etc/etunnel /usr/local/bin/etunnel /usr/local/etc/xray/config.json 2>/dev/null
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
  for svc in dropbear "$STUNNEL_SVC" haproxy nginx xray rocket-proxy dnsmasq udp-custom universal-bridge vpn-panel openvpn@server; do
    svc_restart "$svc" && echo -e "  ${GREEN}● $svc${NC}" || echo -e "  ${RED}● $svc${NC}"
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
  echo -e "${CYAN}  Updating E-TUNNEL script...${NC}"
  curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel-v1.0.0.sh -o /tmp/etunnel-update.sh && \
    bash /tmp/etunnel-update.sh && echo -e "  ${GREEN}Update done${NC}" || \
    echo -e "  ${RED}Failed — check internet${NC}"; pause;;

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

chmod +x /usr/local/bin/etunnel
bash -n /usr/local/bin/etunnel && check_ok "Panel syntax valid" || check_fail "Panel"
cp /usr/local/bin/etunnel /root/etunnel-save/etunnel 2>/dev/null || true

if ! grep -q "E-TUNNEL-AUTO-PANEL" /root/.bashrc 2>/dev/null; then
cat >> /root/.bashrc <<'RC'
# E-TUNNEL-AUTO-PANEL
if [ -t 0 ] && [ -x /usr/local/bin/etunnel ] && [ -z "$ETUNNEL_AUTO_PANEL" ]; then
    export ETUNNEL_AUTO_PANEL=1
    /usr/local/bin/etunnel
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
echo -e "${YELLOW} Type 'etunnel' anytime to open the control panel${NC}"
echo -e "${YELLOW} Opening panel in 3 seconds...${NC}"
sleep 3
/usr/local/bin/etunnel || true