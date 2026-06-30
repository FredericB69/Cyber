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
# 8. AUDITD
# =============================================================================
section "8. Configuration auditd"

AUDIT_RULES="/etc/audit/rules.d/cis-hardening.rules"
cat > "$AUDIT_RULES" << 'EOF'
# Supprimer toutes les règles existantes
-D
# Buffer
-b 8192
# Échecs : panic
-f 2

# ── Temps système ────────────────────────────────────────────────────────────
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# ── Identité / utilisateurs ──────────────────────────────────────────────────
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/group   -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# ── Réseau ───────────────────────────────────────────────────────────────────
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network/ -p wa -k system-locale

# ── Contrôle d'accès obligatoire ────────────────────────────────────────────
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy

# ── Logs ─────────────────────────────────────────────────────────────────────
-w /var/log/auth.log -p wa -k auth-log
-w /var/log/syslog   -p wa -k syslog

# ── Accès non autorisés ──────────────────────────────────────────────────────
-a always,exit -F arch=b64 -S open -F dir=/etc -F success=0 -k unauth-access
-a always,exit -F arch=b64 -S open -F dir=/bin -F success=0 -k unauth-access

# ── Élévation de privilèges ──────────────────────────────────────────────────
-w /bin/su   -p x -k priv-esc
-w /usr/bin/sudo -p x -k priv-esc
-a always,exit -F arch=b64 -S setuid -k priv-esc

# ── Exécutions ───────────────────────────────────────────────────────────────
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec

# Immuabilité (doit être en dernier)
-e 2
EOF

systemctl enable auditd
systemctl restart auditd
log "auditd configuré et redémarré."
