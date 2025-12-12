#!/usr/bin/env bash
# /usr/local/bin/chcl_restore.sh
# Restauration d'une sauvegarde chiffrée du schéma gestion_emploi_temps
set -euo pipefail

BACKUP_DIR="/var/backups/chcl_pg/data_securisee"
PASSPHRASE_FILE="/etc/chcl/.backup_passphrase"
DB_USER="postgres"
DB_NAME="postgres"          # adapter si la base s'appelle autrement
SCHEMA_NAME="gestion_emploi_temps"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error_exit(){ echo "$*" >&2; exit 1; }

command -v gpg >/dev/null 2>&1 || error_exit "gpg manquant"
command -v pg_restore >/dev/null 2>&1 || error_exit "pg_restore manquant"

if [ ! -d "$BACKUP_DIR" ]; then error_exit "Répertoire backup non trouvé: $BACKUP_DIR"; fi
if [ ! -f "$PASSPHRASE_FILE" ]; then error_exit "Fichier passphrase absent: $PASSPHRASE_FILE"; fi

echo "Sauvegardes disponibles dans $BACKUP_DIR:"
ls -1t "$BACKUP_DIR"/*.gpg 2>/dev/null | nl -w2 -s'. '

read -rp "Numéro de la sauvegarde à restaurer (ou vide pour annuler): " NUM
if [ -z "$NUM" ]; then echo "Annulé"; exit 0; fi

BACKUP_FILE=$(ls -1t "$BACKUP_DIR"/*.gpg | sed -n "${NUM}p")
if [ -z "$BACKUP_FILE" ]; then error_exit "Numéro invalide"; fi

read -rp "CONFIRMER restauration -> écrase le schéma ${SCHEMA_NAME} dans la base ${DB_NAME} (oui/non): " CONF
if [ "$CONF" != "oui" ]; then echo "Annulé"; exit 0; fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

log "Déchiffrement de $BACKUP_FILE ..."
GPG_PASSPHRASE=$(cat "$PASSPHRASE_FILE")
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --output "$TEMP_DIR/restore.dump" --decrypt "$BACKUP_FILE"

log "Restauration (pg_restore) du schéma ${SCHEMA_NAME} ..."
sudo -u "$DB_USER" pg_restore -U "$DB_USER" -d "$DB_NAME" \
  --clean --if-exists \
  --schema="$SCHEMA_NAME" \
  --verbose "$TEMP_DIR/restore.dump"

log "Restauration terminée."
exit 0
