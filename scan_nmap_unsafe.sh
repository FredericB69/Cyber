#!/bin/bash

# Script de scan Nmap pour détecter les ports non sécurisés (ouverts) entre 1 et 1024,
# identifier les versions des services et scanner les vulnérabilités..
# Usage: ./scan_nmap_unsafe.sh [OPTIONS] <cible>

# --- Couleurs pour l'affichage ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Fonction d'affichage de l'aide ---
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [OPTIONS] <cible>"
    echo "Options:"
    echo "  -v, --verbose     Mode verbeux (affiche la commande Nmap exécutée)"
    echo "  -s, --save FILE   Sauvegarde les résultats dans un fichier texte"
    echo "  -x, --xml FILE    Sauvegarde les résultats au format XML (pour analyse avancée)"
    echo "  -a, --aggressive  Mode agressif (scan plus approfondi, plus lent)"
    echo "  -h, --help        Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 192.168.1.1"
    echo "  $0 -v -s scan_result.txt -x scan_result.xml 192.168.1.1"
    echo "  $0 -a -s full_scan.txt example.com"
    exit 1
}

# --- Variables par défaut ---
VERBOSE=false
SAVE_FILE=""
XML_FILE=""
AGGRESSIVE=false

# --- Analyse des arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--save)
            SAVE_FILE="$2"
            shift 2
            ;;
        -x|--xml)
            XML_FILE="$2"
            shift 2
            ;;
        -a|--aggressive)
            AGGRESSIVE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

# --- Vérification du nombre d'arguments ---
if [[ $# -ne 1 ]]; then
    echo -e "${RED}Erreur : Il faut spécifier une cible (IP ou nom d'hôte).${NC}"
    usage
fi

TARGET="$1"

# --- Vérification que nmap est installé ---
if ! command -v nmap &> /dev/null; then
    echo -e "${RED}Erreur : nmap n'est pas installé.${NC}"
    echo "Installez-le avec :"
    echo "  - Sur Debian/Ubuntu : sudo apt install nmap"
    echo "  - Sur CentOS/RHEL : sudo yum install nmap"
    echo "  - Sur macOS : brew install nmap"
    exit 1
fi

# --- Vérification que la cible est valide ---
if ! [[ "$TARGET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && ! [[ "$TARGET" =~ ^[a-zA-Z0-9\-\.]+$ ]]; then
    echo -e "${RED}Erreur : La cible '$TARGET' ne semble pas être une IP ou un nom d'hôte valide.${NC}"
    exit 1
fi

# --- Construction de la commande Nmap ---
NMAP_CMD="nmap -p 1-1024 --open -sV --script vuln -T4"

if $AGGRESSIVE; then
    NMAP_CMD="$NMAP_CMD -A"
fi

if [[ -n "$XML_FILE" ]]; then
    NMAP_CMD="$NMAP_CMD -oX $XML_FILE"
fi

if $VERBOSE; then
    echo -e "${YELLOW}[+] Commande Nmap exécutée :${NC}"
    echo "$NMAP_CMD $TARGET"
    echo ""
fi

# --- Affichage du début du scan ---
echo -e "${BLUE}[+] Scan en cours des ports 1-1024 sur $TARGET...${NC}"
echo -e "${CYAN}  - Détection des ports ouverts${NC}"
echo -e "${CYAN}  - Identification des versions des services${NC}"
echo -e "${CYAN}  - Scan des vulnérabilités${NC}"
if $AGGRESSIVE; then
    echo -e "${CYAN}  - Mode agressif activé${NC}"
fi
echo ""

# --- Exécution du scan Nmap ---
NMAP_OUTPUT=$(eval "$NMAP_CMD $TARGET" 2>&1)
NMAP_EXIT_CODE=$?

# --- Vérification des erreurs Nmap ---
if [[ $NMAP_EXIT_CODE -ne 0 ]]; then
    echo -e "${RED}Erreur lors du scan Nmap (code: $NMAP_EXIT_CODE) :${NC}"
    echo "$NMAP_OUTPUT"
    exit 1
fi

# --- Sauvegarde dans un fichier texte (si demandé) ---
if [[ -n "$SAVE_FILE" ]]; then
    echo "$NMAP_OUTPUT" > "$SAVE_FILE"
    echo -e "${GREEN}[+] Résultats sauvegardés dans : $SAVE_FILE${NC}"
fi

# --- Affichage des résultats ---
echo -e "${GREEN}[+] Résultats du scan :${NC}"
echo "----------------------------------------"
echo "$NMAP_OUTPUT"
echo "----------------------------------------"

# --- Extraction des ports ouverts ---
OPEN_PORTS=$(echo "$NMAP_OUTPUT" | grep -Eo '[0-9]{1,5}/open' | cut -d'/' -f1)

if [[ -z "$OPEN_PORTS" ]]; then
    echo -e "${GREEN}[+] Aucun port ouvert détecté entre 1 et 1024.${NC}"
else
    echo -e "${YELLOW}[!] Ports ouverts (non sécurisés) détectés :${NC} $(echo "$OPEN_PORTS" | tr '\n' ' ')"
    echo ""

    # --- Extraction des versions des services ---
    echo -e "${PURPLE}[+] Versions des services :${NC}"
    echo "$NMAP_OUTPUT" | grep -E '^[0-9]+/tcp.*open' | awk '{print "  - Port "$1" : "$3" ("$4")"}'
    echo ""

    # --- Extraction des vulnérabilités ---
    VULN_SECTION=$(echo "$NMAP_OUTPUT" | grep -A 10 "VULNERABILITY")
    if [[ -n "$VULN_SECTION" ]]; then
        echo -e "${RED}[!] Vulnérabilités détectées :${NC}"
        echo "$VULN_SECTION" | grep -E '^\|  \_' | sed 's/^/  /'
        echo ""
        echo -e "${RED}[!] Attention : Ces vulnérabilités peuvent représenter des risques de sécurité.${NC}"
        echo "   Pensez à les corriger (mises à jour, configurations, etc.)."
    else
        echo -e "${GREEN}[+] Aucune vulnérabilité détectée.${NC}"
    fi
fi

exit 0
