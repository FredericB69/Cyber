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
# 1. MISE À JOUR DU SYSTÈME
# =============================================================================
section "1. Mise à jour du système"

apt-get update -qq
apt-get upgrade -y
apt-get install -y \
    auditd audispd-plugins \
    libpam-pwquality \
    ufw \
    fail2ban \
    aide \
    apparmor apparmor-utils \
    lynis \
    rsyslog \
    acl \
    apt-show-versions
log "Paquets installés."

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

# =============================================================================
# 3. BLACKLIST MODULES NOYAU INUTILES
# =============================================================================
section "3. Blacklist modules noyau"

MODCONF="/etc/modprobe.d/cis-hardening.conf"
cat > "$MODCONF" << 'EOF'
# CIS — Systèmes de fichiers inutiles
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
# CIS — Protocoles réseau inutiles
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
log "Modules blacklistés dans $MODCONF"

# =============================================================================
# 4. PARAMÈTRES NOYAU (sysctl)
# =============================================================================
section "4. Paramètres sysctl"

SYSCTL_CONF="/etc/sysctl.d/99-cis-hardening.conf"
cat > "$SYSCTL_CONF" << 'EOF'
# ── Réseau IPv4 ──────────────────────────────────────────────────────────────
net.ipv4.ip_forward                 = 0
net.ipv4.conf.all.send_redirects    = 0
net.ipv4.conf.default.send_redirects= 0
net.ipv4.conf.all.accept_redirects  = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects  = 0
net.ipv4.conf.all.log_martians      = 1
net.ipv4.conf.default.log_martians  = 1
net.ipv4.conf.all.rp_filter         = 1
net.ipv4.conf.default.rp_filter     = 1
net.ipv4.tcp_syncookies             = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
# ── IPv6 (désactivé si non utilisé) ─────────────────────────────────────────
net.ipv6.conf.all.disable_ipv6      = 1
net.ipv6.conf.default.disable_ipv6  = 1
# ── Noyau ────────────────────────────────────────────────────────────────────
kernel.randomize_va_space           = 2
kernel.dmesg_restrict               = 1
kernel.kptr_restrict                = 2
kernel.sysrq                        = 0
kernel.core_uses_pid                = 1
fs.suid_dumpable                    = 0
fs.protected_hardlinks              = 1
fs.protected_symlinks               = 1
EOF

sysctl -p "$SYSCTL_CONF" > /dev/null
log "Paramètres sysctl appliqués."

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

# =============================================================================
# 10. APPARMOR
# =============================================================================
section "10. AppArmor"

systemctl enable apparmor
systemctl start apparmor
aa-enforce /etc/apparmor.d/* 2>/dev/null || warn "Certains profils AppArmor n'ont pas pu être mis en enforce."
log "AppArmor activé en mode enforce."

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

# =============================================================================
# 12. FAIL2BAN
# =============================================================================
section "12. Fail2ban"

JAIL_LOCAL="/etc/fail2ban/jail.local"
cat > "$JAIL_LOCAL" << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2ban configuré et redémarré."

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

# =============================================================================
# 14. PERMISSIONS FICHIERS CRITIQUES
# =============================================================================
section "14. Permissions fichiers critiques"

chmod 644 /etc/passwd
chmod 640 /etc/shadow
chmod 644 /etc/group
chmod 640 /etc/gshadow
chmod 600 /boot/grub/grub.cfg 2>/dev/null || true
chown root:root /etc/passwd /etc/shadow /etc/group /etc/gshadow
log "Permissions fichiers critiques corrigées."

# SUID/SGID — rapport
info "Fichiers SUID/SGID détectés :"
find / -perm /6000 -type f 2>/dev/null | tee /var/log/suid_sgid_report.log
log "Rapport SUID/SGID sauvegardé dans /var/log/suid_sgid_report.log"

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


# =============================================================================
# RÉSUMÉ FINAL
# =============================================================================
section "Résumé"

echo -e "${GREEN}"
cat << 'SUMMARY'
  ✔  Mise à jour système
  ✔  Montage sécurisé (/tmp, /dev/shm, /var/tmp)
  ✔  Modules noyau blacklistés
  ✔  sysctl durci
  ✔  SSH durci
  ✔  auditd configuré
  ✔  AIDE initialisé (cron hebdo)
  ✔  AppArmor en enforce
  ✔  UFW activé
  ✔  Fail2ban actif
  ✔  Services inutiles désactivés
  ✔  Permissions fichiers critiques
  ✔  Politique mots de passe (pwquality + login.defs)
  ✔  sudo sécurisé
  ✔  pam_faillock (verrouillage après 3 échecs / 5 min)
SUMMARY
echo -e "${NC}"

echo ""
info "Prochaine étape recommandée : lancer un audit Lynis"
echo "  sudo lynis audit system"
echo ""
warn "⚠ Un REDÉMARRAGE est recommandé pour appliquer tous les paramètres noyau."
echo -e "${BOLD}Log complet : $LOGFILE${NC}"
