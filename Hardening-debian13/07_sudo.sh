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
# 7. SUDO
# =============================================================================
section "7. Configuration sudo"

# Identifier l'utilisateur qui a lancé sudo (non-root)
SUDO_USER_REAL="${SUDO_USER:-}"

if [[ -z "$SUDO_USER_REAL" ]]; then
    warn "Impossible de détecter l'utilisateur sudo (SUDO_USER vide)."
    warn "Assurez-vous d'exécuter le script via 'sudo bash $0' et non directement en root."
    # On continue sans ajouter d'entrée utilisateur — à vos risques
else
    # Vérifier que l'utilisateur est déjà dans sudoers ou groupe sudo
    if id -nG "$SUDO_USER_REAL" | grep -qw "sudo"; then
        info "Utilisateur '$SUDO_USER_REAL' déjà membre du groupe sudo — OK."
    else
        warn "Utilisateur '$SUDO_USER_REAL' absent du groupe sudo !"
        warn "Ajout dans le groupe sudo pour préserver l'accès..."
        usermod -aG sudo "$SUDO_USER_REAL"
        log "Utilisateur '$SUDO_USER_REAL' ajouté au groupe sudo."
    fi

    # Entrée explicite dans sudoers.d pour garantir l'accès même après durcissement
    SUDOERS_USER="/etc/sudoers.d/99-${SUDO_USER_REAL}-access"
    echo "${SUDO_USER_REAL} ALL=(ALL:ALL) ALL" > "$SUDOERS_USER"
    chmod 440 "$SUDOERS_USER"
    # Validation syntaxique — si invalide, on supprime pour éviter de casser sudo
    if ! visudo -cf "$SUDOERS_USER" > /dev/null 2>&1; then
        err "Fichier sudoers invalide pour '$SUDO_USER_REAL' — supprimé par sécurité."
        rm -f "$SUDOERS_USER"
    else
        log "Accès sudo garanti pour '$SUDO_USER_REAL' via $SUDOERS_USER"
    fi
fi

# Paramètres de durcissement sudo (séparés de l'entrée utilisateur)
SUDOERS_DROP="/etc/sudoers.d/cis-hardening"
cat > "$SUDOERS_DROP" << 'EOF'
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
Defaults timestamp_timeout=5
Defaults passwd_timeout=1
Defaults !visiblepw
EOF
# Validation syntaxique avant de chmod
if ! visudo -cf "$SUDOERS_DROP" > /dev/null 2>&1; then
    err "Fichier $SUDOERS_DROP invalide — supprimé par sécurité."
    rm -f "$SUDOERS_DROP"
else
    chmod 440 "$SUDOERS_DROP"
    log "sudo configuré via $SUDOERS_DROP"
fi
