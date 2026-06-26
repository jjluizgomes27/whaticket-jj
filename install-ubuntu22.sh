#!/usr/bin/env bash
set -Eeuo pipefail

# Instalador Whaticket JJ - Ubuntu 22.04 sem Docker
# Domínios padrão:
#   Frontend: app.kryolo.com.br
#   Backend/API: api.kryolo.com.br
# Uso:
#   bash install-ubuntu22.sh
# Opcional:
#   FRONT_DOMAIN=app.seudominio.com.br API_DOMAIN=api.seudominio.com.br bash install-ubuntu22.sh

FRONT_DOMAIN="${FRONT_DOMAIN:-app.kryolo.com.br}"
API_DOMAIN="${API_DOMAIN:-api.kryolo.com.br}"
REPO_URL="${REPO_URL:-https://github.com/jjluizgomes27/whaticket-jj.git}"
APP_USER="${APP_USER:-deploy}"
APP_DIR="${APP_DIR:-/home/${APP_USER}/whaticket-jj}"
BACKEND_PORT="${BACKEND_PORT:-8080}"
DB_NAME="${DB_NAME:-whaticket_jj}"
DB_USER="${DB_USER:-whaticket_jj}"
NODE_MAJOR="20"

log() { echo -e "\n\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\n\033[1;33m[AVISO]\033[0m $*"; }
err() { echo -e "\n\033[1;31m[ERRO]\033[0m $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  err "Execute como root: sudo bash install-ubuntu22.sh"
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

log "Configurando Ubuntu para não abrir telas interativas do needrestart/kernel..."
mkdir -p /etc/needrestart/conf.d
cat >/etc/needrestart/conf.d/99-sem-popups.conf <<'EOF_NEED'
$nrconf{restart} = 'a';
$nrconf{kernelhints} = 0;
EOF_NEED

log "Atualizando pacotes básicos..."
apt-get update -y
apt-get install -y \
  ca-certificates curl gnupg git sudo unzip zip build-essential make g++ python3 \
  nginx certbot python3-certbot-nginx redis-server mysql-server ufw openssl \
  fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 libcups2 \
  libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 libx11-xcb1 libxcomposite1 \
  libxdamage1 libxrandr2 xdg-utils

log "Criando swap se a VPS tiver pouca memória..."
if ! swapon --show | grep -q '^'; then
  MEM_MB=$(free -m | awk '/Mem:/ {print $2}')
  if [[ "${MEM_MB}" -lt 3500 ]]; then
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap de 4GB criado."
  else
    log "Memória suficiente; swap extra não foi criado."
  fi
else
  log "Swap já existe."
fi

log "Instalando Node.js ${NODE_MAJOR} LTS e npm 10..."
apt-get remove -y nodejs npm >/dev/null 2>&1 || true
curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -
apt-get install -y nodejs
npm install -g npm@10 pm2
hash -r
node -v
npm -v
pm2 -v

log "Ativando MySQL e Redis..."
systemctl enable --now mysql
systemctl enable --now redis-server

log "Criando usuário ${APP_USER}..."
if ! id "${APP_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${APP_USER}"
fi
usermod -aG sudo "${APP_USER}"

DB_PASS="${DB_PASS:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET:-$(openssl rand -hex 32)}"

log "Criando banco MySQL ${DB_NAME}..."
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

log "Baixando projeto em ${APP_DIR}..."
mkdir -p "/home/${APP_USER}"
if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" pull --ff-only || true
else
  rm -rf "${APP_DIR}"
  git clone "${REPO_URL}" "${APP_DIR}"
fi
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"

log "Criando arquivo backend/.env..."
cat >"${APP_DIR}/backend/.env" <<EOF_BACKEND
NODE_ENV=production
PORT=${BACKEND_PORT}

BACKEND_URL=https://${API_DOMAIN}
FRONTEND_URL=https://${FRONT_DOMAIN}
PROXY_PORT=443

DB_DIALECT=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_DEBUG=false

JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}

REDIS_URI=redis://127.0.0.1:6379
REDIS_OPT_LIMITER_MAX=1
REDIS_OPT_LIMITER_DURATION=3000

USER_LIMIT=9999
CONNECTIONS_LIMIT=9999
CLOSED_SEND_BY_ME=true
SENTRY_DSN=
EOF_BACKEND

log "Criando arquivo frontend/.env..."
cat >"${APP_DIR}/frontend/.env" <<EOF_FRONTEND
REACT_APP_BACKEND_URL=https://${API_DOMAIN}
REACT_APP_HOURS_CLOSE_TICKETS_AUTO=24
GENERATE_SOURCEMAP=false
EOF_FRONTEND

chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"

log "Instalando dependências do backend..."
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/backend' && npm cache clean --force && npm install --legacy-peer-deps --include=optional"

log "Compilando backend..."
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/backend' && npm run build"

log "Executando migrations do banco..."
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/backend' && npm run db:migrate"

log "Executando seeds padrão..."
if ! sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/backend' && npm run db:seed"; then
  warn "Seeds não rodaram ou já existiam. Continuando instalação."
fi

log "Preparando pasta pública do backend..."
mkdir -p "${APP_DIR}/backend/public"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}/backend/public"

log "Instalando dependências do frontend..."
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/frontend' && npm cache clean --force && npm install --legacy-peer-deps"

log "Compilando frontend..."
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/frontend' && CI=false NODE_OPTIONS=--openssl-legacy-provider npm run build"

log "Configurando PM2 para backend..."
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/backend' && pm2 delete whaticket-jj-backend >/dev/null 2>&1 || true"
sudo -H -u "${APP_USER}" bash -lc "cd '${APP_DIR}/backend' && pm2 start dist/server.js --name whaticket-jj-backend --time --update-env"
sudo -H -u "${APP_USER}" bash -lc "pm2 save"
pm2 startup systemd -u "${APP_USER}" --hp "/home/${APP_USER}" >/tmp/pm2-startup.txt || true
bash /tmp/pm2-startup.txt >/dev/null 2>&1 || true

log "Configurando Nginx..."
cat >/etc/nginx/sites-available/whaticket-jj.conf <<EOF_NGINX
server {
    listen 80;
    server_name ${FRONT_DOMAIN};

    root ${APP_DIR}/frontend/build;
    index index.html;
    client_max_body_size 100M;

    location / {
        try_files \$uri /index.html;
    }
}

server {
    listen 80;
    server_name ${API_DOMAIN};

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF_NGINX

ln -sf /etc/nginx/sites-available/whaticket-jj.conf /etc/nginx/sites-enabled/whaticket-jj.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

log "Configurando firewall..."
ufw allow OpenSSH >/dev/null || true
ufw allow 'Nginx Full' >/dev/null || true
ufw --force enable >/dev/null || true

log "Tentando emitir SSL com Certbot para ${FRONT_DOMAIN} e ${API_DOMAIN}..."
if certbot --nginx -d "${FRONT_DOMAIN}" -d "${API_DOMAIN}" --non-interactive --agree-tos -m "admin@${FRONT_DOMAIN#*.}" --redirect; then
  log "SSL instalado com sucesso."
else
  warn "SSL não foi instalado. Verifique se DNS de ${FRONT_DOMAIN} e ${API_DOMAIN} apontam para esta VPS. O sistema ficou em HTTP temporariamente."
fi

log "Criando comando de atualização em /root/update-whaticket-jj.sh..."
cat >/root/update-whaticket-jj.sh <<EOF_UPDATE
#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="${APP_DIR}"
APP_USER="${APP_USER}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
mkdir -p /etc/needrestart/conf.d
cat >/etc/needrestart/conf.d/99-sem-popups.conf <<'EOF_NEED'
\$nrconf{restart} = 'a';
\$nrconf{kernelhints} = 0;
EOF_NEED
cd "\$APP_DIR"
git pull --ff-only
chown -R "\$APP_USER:\$APP_USER" "\$APP_DIR"
sudo -H -u "\$APP_USER" bash -lc "cd '\$APP_DIR/backend' && npm install --legacy-peer-deps --include=optional && npm run build && npm run db:migrate"
sudo -H -u "\$APP_USER" bash -lc "cd '\$APP_DIR/frontend' && npm install --legacy-peer-deps && CI=false NODE_OPTIONS=--openssl-legacy-provider npm run build"
sudo -H -u "\$APP_USER" bash -lc "pm2 restart whaticket-jj-backend --update-env && pm2 save"
nginx -t && systemctl reload nginx
echo "Atualização finalizada."
EOF_UPDATE
chmod +x /root/update-whaticket-jj.sh

PUBLIC_IP=$(curl -fsSL https://api.ipify.org || true)
cat >/root/whaticket-jj-acessos.txt <<EOF_INFO
Whaticket JJ instalado

Frontend: https://${FRONT_DOMAIN}
API: https://${API_DOMAIN}
Pasta: ${APP_DIR}
Usuário Linux: ${APP_USER}
Banco: ${DB_NAME}
Usuário DB: ${DB_USER}
Senha DB: ${DB_PASS}
Backend porta local: ${BACKEND_PORT}
IP detectado: ${PUBLIC_IP}

Login padrão provável após seed:
E-mail: admin@admin.com
Senha: 123456

Atualizar projeto:
bash /root/update-whaticket-jj.sh

Ver logs backend:
sudo -iu ${APP_USER} pm2 logs whaticket-jj-backend

Status:
sudo -iu ${APP_USER} pm2 status
systemctl status nginx --no-pager
EOF_INFO
chmod 600 /root/whaticket-jj-acessos.txt

log "Instalação finalizada. Dados salvos em /root/whaticket-jj-acessos.txt"
echo
cat /root/whaticket-jj-acessos.txt
