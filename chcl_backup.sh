#!/usr/bin/env bash
# /usr/local/bin/chcl_backup.sh
# Sauvegarde chiffrée du schéma gestion_emploi_temps
# Usage: chcl_backup.sh
set -euo pipefail

# -------------------------
# CONFIGURATION (éditer si nécessaire)
# -------------------------
DB_NAME="gestion_emploi_temps"                         # Nom de la base (par défaut 'postgres')
DB_USER="postgres"                                     # Compte système utilisé pour pg_dump
SCHEMA_NAME="gestion_emploi_temps"                     # Schéma à sauvegarder
BACKUP_ROOT="/var/backups/chcl_pg"
ENCRYPTED_BACKUP_DIR="${BACKUP_ROOT}/data_securisee"
PASSPHRASE_FILE="/etc/chcl/.backup_passphrase"
RETENTION_DAYS=14
LOG_FILE="${BACKUP_ROOT}/backup_log_$(date +%Y%m).log"

# -------------------------
# UTILITAIRES
# -------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

error_exit() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERREUR: $*" >&2
  exit 1
}

# -------------------------
# VERIFICATIONS PREALABLES
# -------------------------
log "Démarrage sauvegarde CHCL"

command -v pg_dump >/dev/null 2>&1 || error_exit "pg_dump introuvable"
command -v gpg >/dev/null 2>&1 || error_exit "gpg introuvable. Installez gnupg"

# créer arborescence si besoin
mkdir -p "$ENCRYPTED_BACKUP_DIR"
chown "$DB_USER":"$DB_USER" "$BACKUP_ROOT" "$ENCRYPTED_BACKUP_DIR" || true
chmod 700 "$BACKUP_ROOT" || true

# passphrase
if [ ! -f "$PASSPHRASE_FILE" ] || [ ! -r "$PASSPHRASE_FILE" ]; then
  log "Fichier de passphrase absent : création sécurisée (600) — réutiliser /etc/chcl/.backup_passphrase"
  mkdir -p "$(dirname "$PASSPHRASE_FILE")"
  openssl rand -base64 32 > "$PASSPHRASE_FILE"
  chmod 600 "$PASSPHRASE_FILE"
  chown "$DB_USER":"$DB_USER" "$PASSPHRASE_FILE" || true
fi

# vérifier que le schéma existe dans la base
SCHEMA_EXISTS=$(sudo -u "$DB_USER" psql -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = '${SCHEMA_NAME}');")
if [ "$SCHEMA_EXISTS" != "t" ]; then
  error_exit "Le schéma '${SCHEMA_NAME}' n'existe pas dans la base '${DB_NAME}'. Vérifie DB_NAME."
fi

# -------------------------
# PREPARATION FICHIERS
# -------------------------
DATE_TIME=$(date "+%Y-%m-%d_%Hh%M")
TEMP_DIR=$(mktemp -d -p /tmp chcl_backup_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

DUMP_FILENAME="chcl_${SCHEMA_NAME}_${DATE_TIME}.dump"
DUMP_PATH="$TEMP_DIR/$DUMP_FILENAME"
ENCRYPTED_FILENAME="${DUMP_FILENAME}.gpg"
ENCRYPTED_PATH="${ENCRYPTED_BACKUP_DIR}/${ENCRYPTED_FILENAME}"

log "Dump temporaire: $DUMP_PATH"

# -------------------------
# CREATION DU DUMP
# -------------------------
log "Exécution pg_dump --schema=${SCHEMA_NAME} ..."
sudo -u "$DB_USER" pg_dump -U "$DB_USER" -d "$DB_NAME" \
  --format=custom \
  --schema="$SCHEMA_NAME" \
  --file="$DUMP_PATH" \
  --verbose

# vérifier la taille
if [ ! -f "$DUMP_PATH" ]; then error_exit "pg_dump n'a pas produit de fichier"; fi
DUMP_SIZE=$(stat -c%s "$DUMP_PATH")
if [ "$DUMP_SIZE" -lt 1024 ]; then error_exit "Dump trop petit ($DUMP_SIZE bytes)"; fi
log "Dump créé ($DUMP_SIZE bytes)"

# -------------------------
# CHIFFREMENT GPG SYMETRIQUE
# -------------------------
GPG_PASSPHRASE=$(cat "$PASSPHRASE_FILE")
log "Chiffrement du dump avec AES256..."

echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
  --symmetric --cipher-algo AES256 \
  --output "$ENCRYPTED_PATH" "$DUMP_PATH"

if [ ! -f "$ENCRYPTED_PATH" ]; then error_exit "Échec chiffrement"; fi
ENCRYPTED_SIZE=$(stat -c%s "$ENCRYPTED_PATH")
log "Fichier chiffré: $ENCRYPTED_PATH ($ENCRYPTED_SIZE bytes)"

# -------------------------
# VERIFICATION RAPIDE
# -------------------------
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt --list-only "$ENCRYPTED_PATH" >/dev/null 2>&1 \
  || error_exit "Échec vérification fichier chiffré"

# -------------------------
# ROTATION / RETENTION (corrigé)
# -------------------------
log "Suppression des sauvegardes > ${RETENTION_DAYS} jours"

DELETED_FILES=$(find "$ENCRYPTED_BACKUP_DIR" -maxdepth 1 -name "*.gpg" -type f -mtime +"$RETENTION_DAYS" -print)

if [ -n "$DELETED_FILES" ]; then
  echo "$DELETED_FILES" | while read -r f; do
    rm -f "$f"
  done
  COUNT=$(printf "%s\n" "$DELETED_FILES" | wc -l)
  log "Supprimé $COUNT anciens fichiers"
else
  log "Aucun ancien fichier à supprimer"
fi

# -------------------------
# RAPPORT
# -------------------------
BACKUP_COUNT=$(find "$ENCRYPTED_BACKUP_DIR" -maxdepth 1 -name "*.gpg" -type f | wc -l)
TOTAL_SIZE_BYTES=$(find "$ENCRYPTED_BACKUP_DIR" -maxdepth 1 -name "*.gpg" -type f -printf "%s\n" 2>/dev/null | awk '{s+=$1} END{print s+0}')
TOTAL_SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$TOTAL_SIZE_BYTES" 2>/dev/null || echo "${TOTAL_SIZE_BYTES}B")

cat >> "$LOG_FILE" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | OK | db=${DB_NAME} | schema=${SCHEMA_NAME} | file=${ENCRYPTED_FILENAME} | size=${ENCRYPTED_SIZE} bytes
EOF

log "Sauvegarde réussie: ${ENCRYPTED_FILENAME} (total sauvegardes: ${BACKUP_COUNT}, espace: ${TOTAL_SIZE_HUMAN})"
exit 0
