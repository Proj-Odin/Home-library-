#!/bin/bash

# ==============================
# Secure Media Server Setup Script
# ==============================
# - HandBrakeCLI + presets
# - Glances system dashboard
# - NGINX reverse proxy (HTTPS + Basic Auth)
# - Firewall (UFW) + Fail2Ban
# - Cron job to monitor CPU use
# ==============================

# ----------- CONFIGURABLE VARIABLES -----------
DOMAIN="your.domain.com"        # Replace with your actual domain
EMAIL="admin@your.domain.com"   # For Let's Encrypt registration
GLANCES_PORT=61208              # Internal Glances web port
AUTH_USER="monitor"             # Login username for Glances
AUTH_PASS="changeme123"         # Change this password!
PRESET_DIR="/etc/handbrake"

# ----------- SYSTEM PREP -----------
echo "[+] Updating and installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip nginx apache2-utils certbot python3-certbot-nginx ufw fail2ban curl unzip htop sysstat cpulimit handbrake-cli

# ----------- HANDBRAKE PRESETS -----------
echo "[+] Creating preset directory and downloading presets..."
sudo mkdir -p "$PRESET_DIR"
sudo curl -o "$PRESET_DIR/Plex_HandBrake_Presets_All_Formats.json" \
  https://chat.openai.com/sandbox/mnt/data/Plex_HandBrake_Presets_All_Formats.json

# ----------- INSTALL GLANCES -----------
echo "[+] Installing Glances system monitor with web UI..."
sudo pip3 install glances[web]

# ----------- BASIC AUTH FOR GLANCES -----------
echo "[+] Setting up Basic Auth for Glances..."
sudo htpasswd -bc /etc/nginx/.htpasswd "$AUTH_USER" "$AUTH_PASS"

# ----------- CREATE SYSTEMD SERVICE FOR GLANCES -----------
echo "[+] Creating systemd service for Glances..."
sudo tee /etc/systemd/system/glances-web.service > /dev/null <<EOF
[Unit]
Description=Glances Web UI
After=network.target

[Service]
ExecStart=/usr/local/bin/glances -w --bind 127.0.0.1 --port $GLANCES_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable glances-web
sudo systemctl start glances-web

# ----------- CONFIGURE NGINX PROXY -----------
echo "[+] Setting up NGINX reverse proxy for Glances..."
sudo tee /etc/nginx/sites-available/glances > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$GLANCES_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/glances /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# ----------- LET’S ENCRYPT SSL -----------
echo "[+] Getting Let's Encrypt certificate..."
sudo certbot --nginx --non-interactive --agree-tos \
  --email "$EMAIL" -d "$DOMAIN" --redirect

# ----------- UFW FIREWALL -----------
echo "[+] Configuring firewall..."
sudo ufw allow 'Nginx Full'
sudo ufw allow ssh
sudo ufw --force enable

# ----------- FAIL2BAN SETUP -----------
echo "[+] Enabling Fail2Ban for basic intrusion protection..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# ----------- CPU USAGE LIMIT TOOLS -----------
echo "[+] Ensuring cpulimit is available for managing CPU load..."
sudo apt install -y cpulimit

# ----------- CRON JOB FOR RESOURCE LOGGING -----------
echo "[+] Creating cron job to monitor HandBrakeCLI usage..."
sudo tee /etc/cron.d/handbrake_monitor > /dev/null <<EOF
*/5 * * * * root ps -C HandBrakeCLI -o %cpu,%mem,cmd >> /var/log/handbrake_usage.log 2>&1
EOF

# ----------- DONE -----------
echo "[+] All done!"
echo "Access Glances securely at: https://$DOMAIN"
echo "Glances login: $AUTH_USER"
echo "Presets saved in: $PRESET_DIR/Plex_HandBrake_Presets_All_Formats.json"
