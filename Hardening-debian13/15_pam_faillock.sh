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
# 15. PAM_FAILLOCK — Verrouillage compte après échecs d'authentification
# =============================================================================
section "15. pam_faillock"

PAM_AUTH="/etc/pam.d/common-auth"

if grep -q "pam_faillock" "$PAM_AUTH"; then
    warn "pam_faillock déjà présent dans $PAM_AUTH — aucune modification."
    exit 0
fi

BACKUP="${PAM_AUTH}.bak-$(date +%Y%m%d%H%M%S)"
cp "$PAM_AUTH" "$BACKUP"
log "Backup créé : $BACKUP"

if ! grep -q "pam_unix.so" "$PAM_AUTH"; then
    err "Ligne pam_unix.so introuvable dans $PAM_AUTH — abandon, fichier non standard."
    exit 1
fi

if ! grep -q "pam_deny.so" "$PAM_AUTH"; then
    err "Ligne pam_deny.so introuvable dans $PAM_AUTH — abandon, fichier non standard."
    exit 1
fi

DENY=3
UNLOCK_TIME=300

# 1) preauth AVANT pam_unix.so
sed -i "/pam_unix.so/i auth required pam_faillock.so preauth silent deny=${DENY} unlock_time=${UNLOCK_TIME}" "$PAM_AUTH"

# 2) authfail JUSTE APRÈS pam_unix.so — impératif : doit précéder pam_deny.so (requisite)
#    sinon pam_deny.so coupe la pile avant que pam_faillock n'enregistre l'échec.
sed -i "/pam_unix.so/a auth [default=die] pam_faillock.so authfail deny=${DENY} unlock_time=${UNLOCK_TIME}" "$PAM_AUTH"

# 3) CRITIQUE : la ligne pam_unix.so a un saut "success=N" qui compte le nombre de
#    lignes à sauter en cas de succès. On vient d'insérer 1 ligne (authfail) juste
#    après elle — il faut donc INCRÉMENTER ce compteur de 1, sinon le flux de succès
#    "atterrit" sur la ligne pam_deny.so (requisite) qui échoue TOUJOURS, et casse
#    l'authentification même avec un mot de passe correct.
CURRENT_JUMP=$(grep -oP '(?<=success=)\d+' "$PAM_AUTH" | head -1)
if [[ -n "$CURRENT_JUMP" ]]; then
    NEW_JUMP=$((CURRENT_JUMP + 1))
    sed -i "s/\[success=${CURRENT_JUMP} default=ignore\]\(\s*\)pam_unix.so/[success=${NEW_JUMP} default=ignore]\1pam_unix.so/" "$PAM_AUTH"
    log "Compteur de saut pam_unix.so ajusté : success=${CURRENT_JUMP} → success=${NEW_JUMP} (pour sauter la ligne authfail insérée)."
else
    err "Impossible de détecter le compteur success=N sur la ligne pam_unix.so — restauration du backup."
    cp "$BACKUP" "$PAM_AUTH"
    exit 1
fi

# Validation de l'ordre : authfail doit être AVANT pam_deny.so dans le fichier
LINE_AUTHFAIL=$(grep -n "pam_faillock.so authfail" "$PAM_AUTH" | head -1 | cut -d: -f1)
LINE_DENY=$(grep -n "pam_deny.so" "$PAM_AUTH" | head -1 | cut -d: -f1)

if [[ -n "$LINE_AUTHFAIL" && -n "$LINE_DENY" && "$LINE_AUTHFAIL" -lt "$LINE_DENY" ]]; then
    log "Ordre PAM validé : preauth → pam_unix → authfail → pam_deny."
    log "pam_faillock configuré : deny=${DENY} unlock_time=${UNLOCK_TIME}s (${UNLOCK_TIME}/60 min)."
else
    err "Ordre PAM incorrect détecté après modification — restauration du backup."
    cp "$BACKUP" "$PAM_AUTH"
    exit 1
fi

# Nécessaire pour que le déverrouillage automatique soit bien pris en compte
PAM_ACCOUNT="/etc/pam.d/common-account"
if ! grep -q "pam_faillock" "$PAM_ACCOUNT"; then
    cp "$PAM_ACCOUNT" "${PAM_ACCOUNT}.bak-$(date +%Y%m%d%H%M%S)"
    echo "account required pam_faillock.so" >> "$PAM_ACCOUNT"
    log "Ligne pam_faillock ajoutée à $PAM_ACCOUNT."
else
    warn "pam_faillock déjà présent dans $PAM_ACCOUNT — ignoré."
fi

echo ""
cat << EOF
${BOLD}${YELLOW}--- Aide-mémoire pam_faillock ---${NC}
Voir le statut d'un compte      : sudo faillock --user TONUSER
Déverrouiller manuellement      : sudo faillock --user TONUSER --reset
Déverrouillage automatique      : ${UNLOCK_TIME}s (${UNLOCK_TIME}/60 min) après le dernier échec
Backup de common-auth           : $BACKUP
EOF
