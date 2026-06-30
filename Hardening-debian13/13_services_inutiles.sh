#!/usr/bin/env bash
set -euo pipefail

# --- Couleurs -----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# --- Log ----------------------------------------------------------------------
LOGFILE="/var/log/harden_debian_cis.log"
exec > >(tee -a "$LOGFILE") 2>&1

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"; }

# --- Vérification root --------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    err "Ce script doit être exécuté en root (sudo)."
    exit 1
fi
# =============================================================================
# 13. SERVICES INUTILES — DÉSACTIVATION
# =============================================================================
section "13. Désactivation services inutiles"

SERVICES_TO_DISABLE=(
    avahi-daemon
    cups
    isc-dhcp-server
    isc-dhcp-server6
    slapd
    nfs-server
    rpcbind
    bind9
    vsftpd
    apache2
    dovecot
    smbd
    nmbd
    squid
    snmpd
    rsync
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc"
        systemctl disable "$svc"
        warn "Service désactivé : $svc"
    fi
done
log "Vérification services inutiles terminée."
