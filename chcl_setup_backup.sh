#!/usr/bin/env bash
# /usr/local/bin/chcl_setup_backup.sh
# Installe les scripts, crée répertoires, crée passphrase, option systemd

set -euo pipefail
INSTALL_DIR="/usr/local/bin"
BACKUP_ROOT="/var/backups/chcl_pg"
ENCRYPTED_DIR="${BACKUP_ROOT}/data_securisee"
PASSPHRASE_FILE="/etc/chcl/.backup_passphrase"
SVC_NAME="chcl-backup.service"
TIMER_NAME="chcl-backup.timer"

# Copier scripts (assumer qu'ils sont dans le répertoire courant)
if [ ! -f "./chcl_backup.sh" ] || [ ! -f "./chcl_restore.sh" ]; then
  echo "Place les fichiers chcl_backup.sh et chcl_restore.sh dans ce répertoire puis relance."
  exit 1
fi

echo "Installation des scripts..."
sudo cp ./chcl_backup.sh "$INSTALL_DIR/chcl_backup.sh"
sudo cp ./chcl_restore.sh "$INSTALL_DIR/chcl_restore.sh"
sudo chmod 750 "$INSTALL_DIR/chcl_backup.sh" "$INSTALL_DIR/chcl_restore.sh"
sudo chown root:postgres "$INSTALL_DIR/chcl_backup.sh" "$INSTALL_DIR/chcl_restore.sh"

echo "Création des répertoires de backup..."
sudo mkdir -p "$ENCRYPTED_DIR"
sudo chown postgres:postgres "$BACKUP_ROOT" "$ENCRYPTED_DIR"
sudo chmod 700 "$BACKUP_ROOT"

echo "Création du fichier de passphrase (si absent)..."
sudo mkdir -p "$(dirname "$PASSPHRASE_FILE")"
if [ ! -f "$PASSPHRASE_FILE" ]; then
  sudo openssl rand -base64 32 | sudo tee "$PASSPHRASE_FILE" > /dev/null
  sudo chmod 600 "$PASSPHRASE_FILE"
  sudo chown postgres:postgres "$PASSPHRASE_FILE"
  echo "Fichier passphrase créé: $PASSPHRASE_FILE"
else
  echo "Fichier passphrase existe déjà — pas touché."
fi

echo "Installation systemd (optionnel)..."
read -rp "Créer unit systemd pour backups automatiques toutes les nuits ? (o/n): " CH
if [ "${CH,,}" = "o" ]; then
  # service file
  sudo tee /etc/systemd/system/${SVC_NAME} > /dev/null <<EOF
[Unit]
Description=CHCL backup service (runs chcl_backup.sh)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=postgres
Group=postgres
ExecStart=${INSTALL_DIR}/chcl_backup.sh
Nice=10
EOF

  # timer - daily at 02:00
  sudo tee /etc/systemd/system/${TIMER_NAME} > /dev/null <<EOF
[Unit]
Description=Timer: CHCL nightly backup

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now ${TIMER_NAME}
  echo "Systemd timer installé et activé (${TIMER_NAME})"
fi

echo "Installation terminée. Pour tester la sauvegarde :"
echo " sudo -u postgres ${INSTALL_DIR}/chcl_backup.sh"
echo "Pour restaurer :"
echo " sudo ${INSTALL_DIR}/chcl_restore.sh"
