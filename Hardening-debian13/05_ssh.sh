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
# 5. SSH — DURCISSEMENT
# =============================================================================
section "5. Durcissement SSH"

SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%F)"

set_ssh() {
    local key="$1"; local val="$2"
    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        sed -i "s|^#\?${key}.*|${key} ${val}|" "$SSHD_CONFIG"
    else
        echo "${key} ${val}" >> "$SSHD_CONFIG"
    fi
}

set_ssh "Protocol"              "2"
set_ssh "PermitRootLogin"       "no"
set_ssh "MaxAuthTries"          "3"
set_ssh "PubkeyAuthentication"  "yes"
set_ssh "PasswordAuthentication" "no"
set_ssh "PermitEmptyPasswords"  "no"
set_ssh "X11Forwarding"         "no"
set_ssh "AllowTcpForwarding"    "no"
set_ssh "ClientAliveInterval"   "300"
set_ssh "ClientAliveCountMax"   "0"
set_ssh "LoginGraceTime"        "60"
set_ssh "MaxSessions"           "2"
set_ssh "TCPKeepAlive"          "no"
set_ssh "Compression"           "no"
set_ssh "Banner"                "/etc/issue.net"

echo "Authorized access only. All activity is logged." > /etc/issue.net

sshd -t && systemctl restart ssh
log "SSH durci et redémarré."
