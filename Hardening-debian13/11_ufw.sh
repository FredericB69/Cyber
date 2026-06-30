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
# 11. UFW — PARE-FEU
# =============================================================================
section "11. UFW — Pare-feu"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward
ufw allow ssh
ufw logging on
ufw --force enable
log "UFW configuré et activé."
