#!/bin/bash
# Configurador de Domínio + SSL para GeoTrack Pro
# Configura Nginx como reverse proxy e emite certificado SSL via Let's Encrypt
# Execute com: sudo bash setup-domain.sh
set -e

INSTALL_DIR="/opt/geotrack"
ENV_FILE="${INSTALL_DIR}/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║   GeoTrack Pro — Configuração de Domínio     ║"
  echo "║          Nginx + SSL (Let's Encrypt)         ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERRO] Execute como root: sudo bash setup-domain.sh${NC}"
    exit 1
  fi
}

check_geotrack_installed() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}[ERRO] GeoTrack Pro não está instalado em ${INSTALL_DIR}${NC}"
    echo -e "${YELLOW}       Execute primeiro: sudo bash install.sh${NC}"
    exit 1
  fi
}

get_app_port() {
  APP_PORT=$(grep "^PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
  APP_PORT="${APP_PORT:-3000}"
  echo -e "${GREEN}[OK] Porta da aplicação detectada: ${APP_PORT}${NC}"
}

install_nginx() {
  echo ""
  echo -e "${BLUE}--- Verificando Nginx ---${NC}"
  if ! command -v nginx &>/dev/null; then
    echo -e "${YELLOW}[INFO] Nginx não encontrado. Instalando...${NC}"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  else
    echo -e "${GREEN}[OK] Nginx já instalado: $(nginx -v 2>&1)${NC}"
  fi

  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl start nginx
  echo -e "${GREEN}[OK] Nginx ativo${NC}"
}

install_certbot() {
  echo ""
  echo -e "${BLUE}--- Verificando Certbot ---${NC}"
  if ! command -v certbot &>/dev/null; then
    echo -e "${YELLOW}[INFO] Certbot não encontrado. Instalando...${NC}"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx
  else
    echo -e "${GREEN}[OK] Certbot já instalado${NC}"
  fi
}

ask_domain() {
  echo ""
  echo -e "${BLUE}--- Configuração do Domínio ---${NC}"
  echo ""
  echo -e "${YELLOW}  Importante: o domínio precisa estar apontado (registro A)${NC}"
  echo -e "${YELLOW}  para o IP público desta VPS antes de prosseguir.${NC}"
  echo ""
  read -rp "Domínio principal (ex: rastreio.minhaempresa.com): " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo -e "${RED}[ERRO] Domínio não pode ser vazio${NC}"
    exit 1
  fi

  read -rp "Adicionar também o subdomínio www.${DOMAIN}? (s/N): " ADD_WWW
  EXTRA_DOMAIN=""
  if [[ "$ADD_WWW" =~ ^[Ss]$ ]]; then
    EXTRA_DOMAIN="www.${DOMAIN}"
  fi

  read -rp "E-mail para notificações do Let's Encrypt: " EMAIL
  if [ -z "$EMAIL" ]; then
    echo -e "${RED}[ERRO] E-mail não pode ser vazio${NC}"
    exit 1
  fi
}

create_nginx_site() {
  echo ""
  echo -e "${BLUE}--- Criando configuração Nginx ---${NC}"

  SITE_FILE="/etc/nginx/sites-available/geotrack"
  SERVER_NAMES="$DOMAIN"
  if [ -n "$EXTRA_DOMAIN" ]; then
    SERVER_NAMES="${DOMAIN} ${EXTRA_DOMAIN}"
  fi

  cat > "$SITE_FILE" <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAMES};

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
NGINXEOF

  ln -sf "$SITE_FILE" /etc/nginx/sites-enabled/geotrack

  # Remove site default se existir
  if [ -L /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl reload nginx
  echo -e "${GREEN}[OK] Site Nginx configurado para ${SERVER_NAMES}${NC}"
}

configure_firewall() {
  if command -v ufw &>/dev/null; then
    echo ""
    echo -e "${BLUE}--- Liberando portas no firewall (ufw) ---${NC}"
    ufw allow 'Nginx Full' >/dev/null 2>&1 || true
    echo -e "${GREEN}[OK] Portas 80/443 liberadas no ufw${NC}"
  fi
}

issue_ssl() {
  echo ""
  echo -e "${BLUE}--- Emitindo certificado SSL (Let's Encrypt) ---${NC}"

  CERTBOT_DOMAINS="-d ${DOMAIN}"
  if [ -n "$EXTRA_DOMAIN" ]; then
    CERTBOT_DOMAINS="${CERTBOT_DOMAINS} -d ${EXTRA_DOMAIN}"
  fi

  if certbot --nginx ${CERTBOT_DOMAINS} \
       --non-interactive --agree-tos --email "${EMAIL}" \
       --redirect; then
    echo -e "${GREEN}[OK] Certificado SSL emitido e HTTPS habilitado${NC}"
  else
    echo -e "${RED}[ERRO] Falha ao emitir certificado.${NC}"
    echo -e "${YELLOW}Verifique se:${NC}"
    echo "  - O domínio aponta para o IP desta VPS (registro A)"
    echo "  - As portas 80 e 443 estão abertas"
    echo "  - O DNS já propagou (pode levar alguns minutos)"
    exit 1
  fi

  # Renovação automática
  systemctl enable certbot.timer >/dev/null 2>&1 || true
  systemctl start certbot.timer >/dev/null 2>&1 || true
  echo -e "${GREEN}[OK] Renovação automática ativada${NC}"
}

print_summary() {
  echo ""
  echo -e "${GREEN}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║       Domínio configurado com sucesso!       ║"
  echo "╠══════════════════════════════════════════════╣"
  printf "║  Acesso: https://%-27s ║\n" "${DOMAIN}"
  if [ -n "$EXTRA_DOMAIN" ]; then
    printf "║          https://%-27s ║\n" "${EXTRA_DOMAIN}"
  fi
  echo "║                                              ║"
  echo "║  Renovação SSL: automática (certbot.timer)   ║"
  echo "║                                              ║"
  echo "║  Comandos úteis:                             ║"
  echo "║  • Testar Nginx:    nginx -t                 ║"
  echo "║  • Reload Nginx:    systemctl reload nginx   ║"
  echo "║  • Ver certificado: certbot certificates     ║"
  echo "║  • Renovar manual:  certbot renew            ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ---- Execução principal ----
print_banner
check_root
check_geotrack_installed
get_app_port
ask_domain
install_nginx
install_certbot
create_nginx_site
configure_firewall
issue_ssl
print_summary
