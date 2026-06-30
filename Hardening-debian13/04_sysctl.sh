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
