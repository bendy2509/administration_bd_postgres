#!/bin/bash
# Script: chcl_backup_securise.sh
# Version: 2.0 - Sécurisée et corrigée
# Objectif: Sauvegarde de la base de données CHCL (schéma gestion_emploi_temps)
#           Compression et chiffrement GPG avec clé symétrique AES256.

# SÉCURITÉ: Arrêter le script immédiatement si une commande échoue
set -e

# ==================================
# PARAMÈTRES DE CONFIGURATION CHCL
# ==================================

# CORRECTION IMPORTANTE :
# Le nom de la base de données n'est PAS le même que le schéma !
# Votre schéma est dans la base 'postgres' ou dans une base que vous avez créée.
DB_NAME="gestion_emploi_temps"

# Utilisateur PostgreSQL
DB_USER="postgres"

# Répertoire racine pour les sauvegardes
BACKUP_ROOT="/var/backups/chcl_pg"
# Sous-répertoire pour les backups chiffrés
ENCRYPTED_BACKUP_DIR="${BACKUP_ROOT}/data_securisee"

# Nombre de jours de rétention
RETENTION_DAYS=14

# MOT DE PASSE SÉCURISÉ - NE JAMAIS METTRE EN CLAIR ICI !
# Utilisez un fichier sécurisé
PASSPHRASE_FILE="/etc/chcl/.backup_passphrase"

# ==================================
# FONCTIONS UTILITAIRES
# ==================================

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log_message "ERREUR: $1"
    exit 1
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_message "Nettoyage du répertoire temporaire"
    fi
}

# Trapper les signaux pour le nettoyage
trap cleanup EXIT INT TERM

# ==================================
# VÉRIFICATIONS PRÉALABLES
# ==================================

log_message "=== DÉMARRAGE SAUVEGARDE CHCL SÉCURISÉE ==="

# 1. Vérifier que PostgreSQL est actif
if ! systemctl is-active --quiet postgresql; then
    error_exit "PostgreSQL n'est pas actif"
fi

# 2. Vérifier la base de données
if ! sudo -u "$DB_USER" psql -U "$DB_USER" -d "$DB_NAME" -c "\q" >/dev/null 2>&1; then
    log_message "Base '$DB_NAME' introuvable, tentative avec 'postgres'..."
    DB_NAME="postgres"
    if ! sudo -u "$DB_USER" psql -U "$DB_USER" -d "$DB_NAME" -c "\q" >/dev/null 2>&1; then
        error_exit "Impossible de se connecter à PostgreSQL"
    fi
fi

# 3. Vérifier que le schéma existe
SCHEMA_EXISTS=$(sudo -u "$DB_USER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = 'gestion_emploi_temps');" | tr -d ' ')
if [ "$SCHEMA_EXISTS" != "t" ]; then
    error_exit "Le schéma 'gestion_emploi_temps' n'existe pas dans la base '$DB_NAME'"
fi

# 4. Vérifier le fichier de mot de passe
if [ ! -f "$PASSPHRASE_FILE" ] || [ ! -r "$PASSPHRASE_FILE" ]; then
    log_message "Création du fichier de mot de passe sécurisé..."
    mkdir -p /etc/chcl
    openssl rand -base64 32 | sudo tee "$PASSPHRASE_FILE" > /dev/null
    chmod 600 "$PASSPHRASE_FILE"
    chown "$DB_USER:$DB_USER" "$PASSPHRASE_FILE"
fi

# 5. Créer les répertoires
mkdir -p "$ENCRYPTED_BACKUP_DIR"
chown "$DB_USER:$DB_USER" "$BACKUP_ROOT" "$ENCRYPTED_BACKUP_DIR"
chmod 700 "$BACKUP_ROOT"

# ==================================
# PRÉPARATION
# ==================================

DATE_TIME=$(date "+%Y-%m-%d_%Hh%M")
TEMP_DIR=$(mktemp -d -p /tmp chcl_backup_XXXXXX)
chown "$DB_USER:$DB_USER" "$TEMP_DIR"
chmod 700 "$TEMP_DIR"

DUMP_FILENAME="chcl_gestion_${DATE_TIME}.dump"
ENCRYPTED_FILENAME="chcl_gestion_${DATE_TIME}.gpg"

log_message "Base: $DB_NAME"
log_message "Schéma: gestion_emploi_temps"
log_message "Répertoire temporaire: $TEMP_DIR"

# ==================================
# ÉTAPE 1: SAUVEGARDE POSTGRESQL
# ==================================

log_message "1. Création du dump PostgreSQL..."

# Version optimisée avec vérification
sudo -u "$DB_USER" pg_dump -U "$DB_USER" -d "$DB_NAME" \
    --format=custom \
    --schema=gestion_emploi_temps \
    --verbose \
    --file="$TEMP_DIR/$DUMP_FILENAME" 2>&1 | while read line; do
    log_message "pg_dump: $line"
done

if [ $? -ne 0 ]; then
    error_exit "Échec de pg_dump"
fi

# Vérifier que le dump n'est pas vide
DUMP_SIZE=$(stat -c%s "$TEMP_DIR/$DUMP_FILENAME" 2>/dev/null || du -b "$TEMP_DIR/$DUMP_FILENAME" | cut -f1)
if [ "$DUMP_SIZE" -lt 1000 ]; then
    error_exit "Le dump semble vide ou trop petit ($DUMP_SIZE octets)"
fi

DUMP_SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$DUMP_SIZE")
log_message "Dump créé: $DUMP_FILENAME ($DUMP_SIZE_HUMAN)"

# ==================================
# ÉTAPE 2: CHIFFREMENT GPG
# ==================================

log_message "2. Chiffrement avec GPG (AES256)..."

# Lire le mot de passe depuis le fichier sécurisé
GPG_PASSPHRASE=$(cat "$PASSPHRASE_FILE")

echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
    --symmetric \
    --cipher-algo AES256 \
    --s2k-digest-algo SHA512 \
    --s2k-count 65011712 \
    --compress-algo none \
    --output "$ENCRYPTED_BACKUP_DIR/$ENCRYPTED_FILENAME" \
    "$TEMP_DIR/$DUMP_FILENAME"

if [ $? -ne 0 ]; then
    error_exit "Échec du chiffrement GPG"
fi

ENCRYPTED_SIZE=$(stat -c%s "$ENCRYPTED_BACKUP_DIR/$ENCRYPTED_FILENAME")
ENCRYPTED_SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$ENCRYPTED_SIZE")
log_message "Fichier chiffré: $ENCRYPTED_FILENAME ($ENCRYPTED_SIZE_HUMAN)"

# ==================================
# ÉTAPE 3: VÉRIFICATION DU FICHIER
# ==================================

log_message "3. Vérification du fichier chiffré..."

# Tester le déchiffrement (rapide)
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
    --decrypt --list-only "$ENCRYPTED_BACKUP_DIR/$ENCRYPTED_FILENAME" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    log_message "✓ Fichier chiffré vérifié avec succès"
else
    error_exit "Échec de la vérification du fichier chiffré"
fi

# ==================================
# ÉTAPE 4: ROTATION DES SAUVEGARDES
# ==================================

log_message "4. Rotation des sauvegardes ($RETENTION_DAYS jours)..."

OLD_BACKUPS=$(find "$ENCRYPTED_BACKUP_DIR" -name "*.gpg" -type f -mtime +$RETENTION_DAYS | wc -l)
if [ "$OLD_BACKUPS" -gt 0 ]; then
    find "$ENCRYPTED_BACKUP_DIR" -name "*.gpg" -type f -mtime +$RETENTION_DAYS -delete
    log_message "Suppression de $OLD_BACKUPS vieilles sauvegardes"
fi

# ==================================
# ÉTAPE 5: RAPPORT ET STATISTIQUES
# ==================================

BACKUP_COUNT=$(find "$ENCRYPTED_BACKUP_DIR" -name "*.gpg" -type f | wc -l)
TOTAL_SIZE=$(find "$ENCRYPTED_BACKUP_DIR" -name "*.gpg" -type f -exec stat -c%s {} \; | awk '{sum+=$1} END {print sum}')
TOTAL_SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$TOTAL_SIZE")

echo ""
echo "========================================="
echo "  RAPPORT DE SAUVEGARDE CHCL"
echo "========================================="
echo " Date:               $(date)"
echo " Base de données:    $DB_NAME"
echo " Schéma sauvegardé:  gestion_emploi_temps"
echo " Taille du dump:     $DUMP_SIZE_HUMAN"
echo " Taille chiffrée:    $ENCRYPTED_SIZE_HUMAN"
echo " Ratio:             $(echo "scale=1; $ENCRYPTED_SIZE*100/$DUMP_SIZE" | bc)%"
echo ""
echo " STATISTIQUES STOCKAGE:"
echo " Sauvegardes actives: $BACKUP_COUNT"
echo " Espace total:       $TOTAL_SIZE_HUMAN"
echo " Dernière sauvegarde: $ENCRYPTED_FILENAME"
echo ""
echo " EMPLACEMENTS:"
echo " Fichiers chiffrés:  $ENCRYPTED_BACKUP_DIR"
echo " Mot de passe GPG:   $PASSPHRASE_FILE"
echo "========================================="
log_message "SAUVEGARDE TERMINÉE AVEC SUCCÈS"

# Générer un fichier de log
LOG_FILE="$BACKUP_ROOT/backup_log_$(date +%Y%m).log"
echo "$(date '+%Y-%m-%d %H:%M:%S') | $DB_NAME | $ENCRYPTED_FILENAME | $ENCRYPTED_SIZE_HUMAN | SUCCESS" >> "$LOG_FILE"

# Nettoyage automatique via trap
exit 0