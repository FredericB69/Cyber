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
# 6. POLITIQUE DE MOTS DE PASSE
# =============================================================================
section "6. Politique mots de passe"

# pwquality
PWQCONF="/etc/security/pwquality.conf"
cp "$PWQCONF" "${PWQCONF}.bak.$(date +%F)" 2>/dev/null || true
cat > "$PWQCONF" << 'EOF'
minlen       = 14
dcredit      = -1
ucredit      = -1
ocredit      = -1
lcredit      = -1
maxrepeat    = 3
maxclassrepeat = 4
gecoscheck   = 1
EOF
log "pwquality configuré."

# login.defs
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
log "login.defs mis à jour."

# pam_faillock désactivé (cf. blocages répétés) — section retirée volontairement
warn "pam_faillock désactivé dans ce script — à reconfigurer manuellement si besoin."
