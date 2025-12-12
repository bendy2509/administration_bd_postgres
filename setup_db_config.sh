#!/bin/bash
# Script: chcl_setup_backup.sh
# Configuration initiale

echo "=== CONFIGURATION SAUVEGARDE CHCL ==="

# Créer les répertoires
sudo mkdir -p /var/backups/chcl_pg/data_securisee
sudo chown postgres:postgres /var/backups/chcl_pg -R
sudo chmod 700 /var/backups/chcl_pg

# Créer le fichier de mot de passe
sudo mkdir -p /etc/chcl
sudo openssl rand -base64 32 | sudo tee /etc/chcl/.backup_passphrase > /dev/null
sudo chmod 600 /etc/chcl/.backup_passphrase
sudo chown postgres:postgres /etc/chcl/.backup_passphrase

# Copier les scripts
sudo cp db_backup.sh /usr/local/bin/
sudo cp restore_db.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/chcl_*.sh
sudo chown postgres:postgres /usr/local/bin/chcl_*.sh

# Tester
echo "Test de la sauvegarde..."
sudo -u postgres /usr/local/bin/db_backup.sh

# Configurer cron (optionnel)
echo "Configurer une tâche cron quotidienne ? (o/n)"
read CHOIX
if [ "$CHOIX" = "o" ]; then
    (sudo crontab -u postgres -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/db_backup.sh >> /var/log/chcl_backup.log 2>&1") | sudo crontab -u postgres -
    echo "Cron configuré pour 2h du matin"
fi

echo "Configuration terminée!"