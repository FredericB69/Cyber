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
# 2. MONTAGE SÉCURISÉ (tmpfs pour /tmp et /dev/shm)
# =============================================================================
section "2. Options de montage sécurisées"

FSTAB="/etc/fstab"
cp "$FSTAB" "${FSTAB}.bak.$(date +%F)"

add_fstab_entry() {
    local entry="$1"
    local mountpoint="$2"
    if ! grep -q "$mountpoint" "$FSTAB"; then
        echo "$entry" >> "$FSTAB"
        log "Ajouté dans fstab : $mountpoint"
    else
        warn "Entrée déjà présente pour $mountpoint — ignorée."
    fi
}

add_fstab_entry "tmpfs   /tmp      tmpfs   defaults,nodev,nosuid,noexec   0 0" "/tmp"
add_fstab_entry "tmpfs   /dev/shm  tmpfs   defaults,nodev,nosuid,noexec   0 0" "/dev/shm"
add_fstab_entry "/tmp    /var/tmp  none    bind,nodev,nosuid,noexec        0 0" "/var/tmp"

mount -o remount /tmp    2>/dev/null || warn "/tmp : remount ignoré (déjà en tmpfs ou en cours d'utilisation)"
mount -o remount /dev/shm 2>/dev/null || warn "/dev/shm : remount ignoré"
