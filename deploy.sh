#!/bin/bash
# ==========================================
# DevOps Intern Stage 1 - Automated Deployment Script
# Author: Christian Okoro
# ==========================================

set -euo pipefail

LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Trap for unexpected errors ---
trap 'echo "[ERROR] An unexpected error occurred. Check $LOG_FILE for details." >&2' ERR

# --- Helper function ---
function prompt() {
  read -rp "$1: " var
  echo "$var"
}

echo "Starting Automated Deployment..."

# =======================================================
# 1. Collect Parameters from User Input
# =======================================================
GIT_URL=$(prompt "Enter your GitHub repository URL (e.g. https://github.com/Christianchika/My-Website.git)")
PAT=$(prompt "Enter your GitHub Personal Access Token (PAT)")
BRANCH=$(prompt "Enter branch name (default: main)")
BRANCH=${BRANCH:-main}
SSH_USER=$(prompt "Enter remote server username")
SERVER_IP=$(prompt "Enter remote server IP address")
SSH_KEY=$(prompt "Enter path to SSH private key (e.g. ~/.ssh/id_rsa)")

# Use port 80 by default
APP_PORT=80

# =======================================================
# 2. Clone or Update Repository
# =======================================================
echo "Cloning repository..."
if [ -d "app_repo" ]; then
  cd app_repo
  git pull origin "$BRANCH"
else
  git clone -b "$BRANCH" "https://${PAT}@${GIT_URL#https://}" app_repo
  cd app_repo
fi

# =======================================================
# 3. Verify Docker Setup Files
# =======================================================
if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
  echo "[ERROR] No Dockerfile or docker-compose.yml found in repository."
  exit 1
fi
echo "Docker setup files found."

# =======================================================
# 4. SSH Connectivity Test
# =======================================================
echo "Testing SSH connection..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'"

# =======================================================
# 5. Prepare Remote Environment
# =======================================================
echo "Preparing remote server environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<'EOF'
set -e
sudo apt update -y
sudo apt install -y docker.io docker-compose nginx rsync
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER || true
echo "Docker, Nginx, and Rsync installed successfully"
EOF

# =======================================================
# 6. Transfer Project Files
# =======================================================
echo "Transferring project files..."
# Adjust path to rsync if using MSYS2 on Windows
C:/msys64/usr/bin/rsync.exe -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" . "$SSH_USER@$SERVER_IP:~/app_deploy"

# =======================================================
# 7. Build and Run Docker Container
# =======================================================
PROJECT_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-_')
echo "Building and running Docker container '$PROJECT_NAME'..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF
cd ~/app_deploy
docker-compose down || true
docker build -t "$PROJECT_NAME" .
docker run -d --name "$PROJECT_NAME" -p 80:80 "$PROJECT_NAME"
echo "Container deployed successfully on port 80"
EOF

# =======================================================
# 8. Configure Nginx Reverse Proxy
# =======================================================
NGINX_CONF="/etc/nginx/sites-available/mywebsite"
echo "Setting up Nginx reverse proxy..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF
sudo bash -c 'cat > $NGINX_CONF <<NGINXCONF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINXCONF'
sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
echo "Nginx configured successfully"
EOF

# =======================================================
# 9. Validate Deployment
# =======================================================
echo "Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -I http://localhost || true"

echo "Deployment completed successfully!"
echo "Visit your app at http://$SERVER_IP"

# =======================================================
# 10. Logging & Cleanup Info
# =======================================================
echo "Logs saved to: $LOG_FILE"
echo "Script can be safely re-run for idempotent deployment."





