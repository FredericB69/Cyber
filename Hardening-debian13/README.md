# Durcissement Debian 13 — CIS Benchmark / ANSSI BP-028

Scripts de durcissement Linux pour Debian 13, basés sur les recommandations CIS Benchmark et ANSSI BP-028. Conçus et testés sur un homelab (VM VirtualBox, LVM).

## Approche

Le durcissement est découpé en **15 scripts indépendants** plutôt qu'un seul bloc monolithique. Chaque script peut être exécuté et validé séparément, ce qui permet de :

- tester chaque point un par un sans tout risquer d'un coup
- garder un accès de secours (terminal/console root déjà ouvert) pendant les sections sensibles (SSH, sudo, PAM)
- revenir en arrière facilement (snapshot VM) si un point pose problème, sans perdre le travail déjà validé

Un script global (`harden_debian13_cis.sh`) recompile l'ensemble dans le bon ordre, **avec les sections sensibles placées en dernier** (politique mots de passe, sudo, pam_faillock) — sur le principe que si quelque chose casse l'accès, ce soit après que tout le reste ait été appliqué avec succès.

## Liste des scripts

| #  | Script                          | Description                                          | Risque |
|----|----------------------------------|-------------------------------------------------------|--------|
| 1  | `01_maj_systeme.sh`              | Mise à jour système + installation paquets sécurité   | Faible |
| 2  | `02_montage_securise.sh`         | tmpfs durci pour `/tmp`, `/dev/shm`, `/var/tmp`        | Faible |
| 3  | `03_blacklist_modules.sh`        | Blacklist modules noyau inutiles                       | Faible |
| 4  | `04_sysctl.sh`                   | Paramètres noyau réseau/sécurité                       | Faible |
| 5  | `05_ssh.sh`                      | Durcissement SSH                                       | Moyen  |
| 6  | `06_politique_mdp.sh`            | pwquality + login.defs                                 | Faible |
| 7  | `07_sudo.sh`                     | Configuration sudo + sudoers.d                          | Élevé  |
| 8  | `08_auditd.sh`                   | Règles d'audit auditd                                   | Faible |
| 9  | `09_aide.sh`                     | Intégrité fichiers (AIDE) + cron hebdo                  | Faible |
| 10 | `10_apparmor.sh`                 | AppArmor en mode enforce                                | Faible |
| 11 | `11_ufw.sh`                      | Pare-feu UFW                                            | Moyen  |
| 12 | `12_fail2ban.sh`                 | Fail2ban (protection brute-force SSH)                  | Faible |
| 13 | `13_services_inutiles.sh`        | Désactivation services réseau inutiles                 | Faible |
| 14 | `14_permissions_fichiers.sh`     | Permissions fichiers critiques (`passwd`, `shadow`...) | Faible |
| 15 | `15_pam_faillock.sh`             | Verrouillage compte après échecs d'authentification    | Élevé  |

## Usage

Exécution individuelle (recommandé pour un premier passage) :

```bash
sudo bash 01_maj_systeme.sh
sudo bash 02_montage_securise.sh
# ... etc, dans l'ordre numéroté
```

Exécution complète (une fois chaque section validée séparément) :

```bash
sudo bash harden_debian13_cis.sh
```

**Important** : exécuter avec `sudo bash script.sh` depuis un utilisateur normal — **pas** `su -` puis exécution en root direct. Le script 7 (`sudo.sh`) dépend de la variable `$SUDO_USER` pour identifier quel compte préserver l'accès sudo ; cette variable est vide si le script est lancé depuis une session déjà root.

## ⚠️ Précautions avant exécution des scripts à risque élevé

Pour les scripts 5, 7 et 15, qui touchent à l'authentification (SSH, sudo, PAM) :

1. **Garder une session déjà connectée et authentifiée ouverte** (terminal/console séparé du terminal d'exécution), au cas où l'accès se romprait.
2. **Idéal en environnement VM** : prendre un snapshot avant chaque section sensible.
3. Après exécution, valider immédiatement dans le terminal de secours que l'accès fonctionne toujours (`sudo -l`, nouvelle connexion SSH test) avant de fermer quoi que ce soit.

## Pièges rencontrés (retours d'expérience)

### pam_faillock — ordre de la pile PAM

Insérer une ligne `pam_faillock.so authfail` dans `/etc/pam.d/common-auth` sans ajuster le reste de la pile casse l'authentification, **même avec un mot de passe correct**. Deux pièges distincts :

1. **Placement** : la ligne `authfail` doit être insérée juste après `pam_unix.so`, **avant** `pam_deny.so` (qui est en mode `requisite` et échoue systématiquement). Si elle est ajoutée en fin de fichier, elle ne sera jamais évaluée en cas d'échec.

2. **Compteur de saut (`success=N`)** : la ligne `pam_unix.so` porte un contrôle du type `[success=N default=ignore]`, qui indique combien de lignes sauter en cas de succès. Insérer une nouvelle ligne juste après `pam_unix.so` **sans incrémenter ce compteur** fait atterrir le flux de succès sur `pam_deny.so` — qui échoue toujours, cassant l'authentification pour tout le monde, y compris avec un mot de passe correct.

Le script `15_pam_faillock.sh` détecte et corrige ce compteur automatiquement, avec backup et validation de l'ordre avant application.

### Vérifier/déverrouiller un compte bloqué par pam_faillock

```bash
sudo faillock --user NOM_UTILISATEUR              # voir le statut
sudo faillock --user NOM_UTILISATEUR --reset       # déverrouiller manuellement
```

Vérifier aussi qu'il ne s'agit pas d'un verrouillage `shadow` distinct :

```bash
sudo passwd -S NOM_UTILISATEUR    # 'L' = locked au niveau shadow (différent de faillock)
sudo passwd -u NOM_UTILISATEUR    # déverrouiller si 'L'
```

## Configuration pam_faillock retenue

- `deny=3` (verrouillage après 3 échecs, conforme CIS)
- `unlock_time=300` (déverrouillage automatique après 5 min)
- `even_deny_root` non activé (root désactivé sur ce système, accès uniquement via sudo)

## Récupération en cas de blocage total (login impossible)

Si malgré les précautions le système devient inaccessible au login :

1. Redémarrer la VM, sélectionner **"Advanced options for Debian" → "recovery mode"** dans GRUB
2. Choisir **"root – Drop to root shell prompt"**
3. Remonter le filesystem en lecture-écriture :
   ```bash
   mount -o remount,rw /
   ```
4. Déverrouiller le compte et/ou restaurer les backups PAM créés automatiquement par les scripts (`/etc/pam.d/common-auth.bak-*`, `/etc/pam.d/common-account.bak-*`)
5. Valider la syntaxe sudoers avant de quitter : `visudo -cf /etc/sudoers`

## Contexte

Scripts développés et testés sur Debian 13 (VM VirtualBox, LVM) dans le cadre d'un apprentissage Linux/sysadmin et pentesting en homelab.
