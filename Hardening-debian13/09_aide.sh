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
# 9. AIDE (intégrité des fichiers)
# =============================================================================
section "9. AIDE — intégrité fichiers"

if [ ! -f /var/lib/aide/aide.db ]; then
    info "Initialisation de la base AIDE (peut prendre quelques minutes)..."
    aideinit -y -f 2>/dev/null || aide --init
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    log "Base AIDE initialisée."
else
    warn "Base AIDE déjà existante — ignorée."
fi

# Cron hebdomadaire
CRON_AIDE="/etc/cron.d/aide-check"
cat > "$CRON_AIDE" << 'EOF'
# Vérification AIDE chaque dimanche à 03h00
0 3 * * 0 root /usr/bin/aide --check >> /var/log/aide-check.log 2>&1
EOF
log "Cron AIDE créé : $CRON_AIDE"
