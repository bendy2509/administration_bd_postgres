#!/bin/bash
# 05_ssl_configuration.sh

echo "=== CONFIGURATION SSL POUR POSTGRESQL ==="

# 1. Générer les certificats
openssl req -new -text -out server.req -nodes -subj "/CN=chcl-postgres"
openssl rsa -in privkey.pem -out server.key
openssl req -x509 -in server.req -text -key server.key -out server.crt

# 2. Configurer PostgreSQL
sudo cp server.crt server.key /etc/postgresql/17/main/
sudo chown postgres:postgres /etc/postgresql/17/main/server.*
sudo chmod 600 /etc/postgresql/17/main/server.key

# 3. Modifier postgresql.conf
sudo sed -i "s/^#ssl = off/ssl = on/" /etc/postgresql/17/main/postgresql.conf
sudo sed -i "s|^#ssl_cert_file =.*|ssl_cert_file = 'server.crt'|" /etc/postgresql/17/main/postgresql.conf
sudo sed -i "s|^#ssl_key_file =.*|ssl_key_file = 'server.key'|" /etc/postgresql/17/main/postgresql.conf

# 4. Configurer pg_hba.conf pour SSL obligatoire
sudo tee -a /etc/postgresql/17/main/pg_hba.conf << 'EOF'
# Connexions SSL obligatoires
hostssl all             all             0.0.0.0/0               scram-sha-256
EOF

# 5. Redémarrer
sudo systemctl restart postgresql

echo "SSL configuré avec succès!"