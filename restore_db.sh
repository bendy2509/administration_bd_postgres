#!/bin/bash
# Script: restore_db.sh
# Pour restaurer la sauvegarde

set -e

# Configuration
BACKUP_DIR="/var/backups/chcl_pg/data_securisee"
PASSPHRASE_FILE="/etc/chcl/.backup_passphrase"
DB_USER="postgres"
DB_NAME="gestion_emploi_temps"

echo "=== RESTAURATION CHCL ==="

# Lister les sauvegardes disponibles
echo "Sauvegardes disponibles:"
ls -lh "$BACKUP_DIR"/*.gpg | nl

read -p "Numéro de la sauvegarde à restaurer: " NUM

BACKUP_FILE=$(ls "$BACKUP_DIR"/*.gpg | sed -n "${NUM}p")
if [ -z "$BACKUP_FILE" ]; then
    echo "Numéro invalide"
    exit 1
fi

echo "Restauration de: $(basename "$BACKUP_FILE")"

# Demander confirmation
read -p "Êtes-vous sûr? Cela écrasera le schéma gestion_emploi_temps! (oui/non): " CONFIRM
if [ "$CONFIRM" != "oui" ]; then
    echo "Annulé"
    exit 0
fi

# Créer un répertoire temporaire
TEMP_DIR=$(mktemp -d)
chown "$DB_USER:$DB_USER" "$TEMP_DIR"

# Déchiffrer
echo "Déchiffrement..."
GPG_PASSPHRASE=$(cat "$PASSPHRASE_FILE")
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
    --decrypt --output "$TEMP_DIR/restore.dump" "$BACKUP_FILE"

# Restaurer
echo "Restauration dans PostgreSQL..."
sudo -u "$DB_USER" pg_restore -U "$DB_USER" -d "$DB_NAME" \
    --clean --if-exists \
    --schema=gestion_emploi_temps \
    --verbose \
    "$TEMP_DIR/restore.dump"

# Nettoyer
rm -rf "$TEMP_DIR"
echo "Restauration terminée avec succès!"