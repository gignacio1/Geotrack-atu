#!/bin/bash
# Instalador GeoTrack Pro — Ubuntu VPS
# Execute com: sudo bash install.sh
set -e

INSTALL_DIR="/opt/geotrack"
SERVICE_NAME="geotrack"
CONFIG_DIR="/etc/geotrack"
CONFIG_FILE="${CONFIG_DIR}/config.json"
NODE_MIN_VERSION=18
GITHUB_REPO="https://github.com/gignacio1/Geotrack-atu.git"
GITHUB_BRANCH="main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════╗"
  echo "║        GeoTrack Pro — Instalador     ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${NC}"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERRO] Execute este instalador como root: sudo bash install.sh${NC}"
    exit 1
  fi
}

check_node() {
  if ! command -v node &>/dev/null; then
    echo -e "${YELLOW}[INFO] Node.js não encontrado. Instalando...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi

  NODE_VERSION=$(node -e "console.log(process.versions.node.split('.')[0])")
  if [ "$NODE_VERSION" -lt "$NODE_MIN_VERSION" ]; then
    echo -e "${YELLOW}[INFO] Node.js ${NODE_VERSION} encontrado. Atualizando para v20...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi

  echo -e "${GREEN}[OK] Node.js $(node --version) instalado${NC}"
}

check_git() {
  if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}[INFO] Git não encontrado. Instalando...${NC}"
    apt-get update -y
    apt-get install -y git
  fi
  echo -e "${GREEN}[OK] Git $(git --version | awk '{print $3}') instalado${NC}"
}

check_postgres() {
  echo ""
  echo -e "${BLUE}--- Verificando PostgreSQL ---${NC}"

  if ! command -v psql &>/dev/null; then
    echo -e "${YELLOW}[INFO] PostgreSQL não encontrado. Instalando...${NC}"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib
  else
    echo -e "${GREEN}[OK] PostgreSQL já instalado: $(psql --version)${NC}"
  fi

  systemctl enable postgresql >/dev/null 2>&1 || true
  systemctl start postgresql

  if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}[ERRO] Não foi possível iniciar o serviço postgresql${NC}"
    exit 1
  fi

  echo -e "${GREEN}[OK] Serviço PostgreSQL ativo${NC}"
}

choose_install_mode() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║           Modo de Instalação                         ║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║                                                      ║${NC}"
  echo -e "${CYAN}║  [1] Arquivo local  — instala os arquivos deste      ║${NC}"
  echo -e "${CYAN}║      pacote tar.gz (método clássico)                 ║${NC}"
  echo -e "${CYAN}║                                                      ║${NC}"
  echo -e "${CYAN}║  [2] GitHub         — clona o repositório oficial    ║${NC}"
  echo -e "${CYAN}║      e habilita atualização automática pelo painel   ║${NC}"
  echo -e "${CYAN}║                                                      ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  read -rp "Escolha o modo (padrão: 1): " INSTALL_MODE
  INSTALL_MODE="${INSTALL_MODE:-1}"

  if [ "$INSTALL_MODE" = "2" ]; then
    echo -e "${GREEN}[OK] Modo selecionado: GitHub (com atualização automática)${NC}"
    INSTALL_FROM_GIT=true
  else
    echo -e "${GREEN}[OK] Modo selecionado: arquivo local${NC}"
    INSTALL_FROM_GIT=false
  fi
}

setup_database() {
  echo ""
  echo -e "${BLUE}--- Configuração do Banco de Dados ---${NC}"
  echo ""
  echo "  [1] Criar um novo banco PostgreSQL automaticamente neste servidor"
  echo "  [2] Pular — já tenho um banco e vou informar a URL manualmente"
  echo ""
  read -rp "Escolha uma opção (padrão: 1): " DB_OPTION
  DB_OPTION="${DB_OPTION:-1}"

  if [ "$DB_OPTION" = "2" ]; then
    echo -e "${YELLOW}[INFO] Etapa de criação ignorada. A URL será solicitada adiante.${NC}"
    return
  fi

  check_postgres

  read -rp "Nome do banco de dados (padrão: geotrack): " DB_NAME
  DB_NAME="${DB_NAME:-geotrack}"

  read -rp "Usuário do banco (padrão: geotrack): " DB_USER
  DB_USER="${DB_USER:-geotrack}"

  while true; do
    read -rsp "Senha do usuário ${DB_USER}: " DB_PASS
    echo ""
    if [ -z "$DB_PASS" ]; then
      echo -e "${RED}[ERRO] Senha não pode ser vazia${NC}"
      continue
    fi
    read -rsp "Confirme a senha: " DB_PASS2
    echo ""
    if [ "$DB_PASS" != "$DB_PASS2" ]; then
      echo -e "${RED}[ERRO] As senhas não conferem${NC}"
      continue
    fi
    break
  done

  DB_PASS_ESC="${DB_PASS//\'/\'\'}"

  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
    echo -e "${YELLOW}[INFO] Usuário '${DB_USER}' já existe — atualizando senha${NC}"
    sudo -u postgres psql -c "ALTER USER \"${DB_USER}\" WITH ENCRYPTED PASSWORD '${DB_PASS_ESC}';" >/dev/null
  else
    sudo -u postgres psql -c "CREATE USER \"${DB_USER}\" WITH ENCRYPTED PASSWORD '${DB_PASS_ESC}';" >/dev/null
    echo -e "${GREEN}[OK] Usuário '${DB_USER}' criado${NC}"
  fi

  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    echo -e "${YELLOW}[INFO] Banco '${DB_NAME}' já existe${NC}"
  else
    sudo -u postgres psql -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";" >/dev/null
    echo -e "${GREEN}[OK] Banco '${DB_NAME}' criado${NC}"
  fi

  sudo -u postgres psql -c "ALTER DATABASE \"${DB_NAME}\" OWNER TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"${DB_NAME}\" TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -d "${DB_NAME}" -c "ALTER SCHEMA public OWNER TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -d "${DB_NAME}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"${DB_USER}\";" >/dev/null
  sudo -u postgres psql -d "${DB_NAME}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"${DB_USER}\";" >/dev/null

  echo -e "${GREEN}[OK] Permissões concedidas a '${DB_USER}' no banco '${DB_NAME}'${NC}"

  DB_PASS_URL=$(node -e "console.log(encodeURIComponent(process.argv[1]))" "$DB_PASS")
  DATABASE_URL_AUTO="postgresql://${DB_USER}:${DB_PASS_URL}@localhost:5432/${DB_NAME}"
}

configure_license() {
  echo ""
  echo -e "${BLUE}--- Configuração da Licença ---${NC}"

  if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}[INFO] Configuração de licença já existe em ${CONFIG_FILE}${NC}"
    read -rp "Deseja reconfigurar a licença? (s/N): " RECONFIG
    if [[ ! "$RECONFIG" =~ ^[Ss]$ ]]; then
      echo -e "${GREEN}[OK] Configuração existente mantida${NC}"
      return
    fi
  fi

  echo ""
  read -rp "Digite sua chave de licença: " LICENSE_KEY
  if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}[ERRO] Chave de licença não pode ser vazia${NC}"
    exit 1
  fi

  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<CONFIGEOF
{
  "licenseKey": "${LICENSE_KEY}"
}
CONFIGEOF

  chmod 600 "$CONFIG_FILE"
  echo -e "${GREEN}[OK] Licença configurada em ${CONFIG_FILE}${NC}"
}

configure_database() {
  echo ""
  echo -e "${BLUE}--- Configuração do Banco de Dados ---${NC}"

  if [ -n "${DATABASE_URL_AUTO:-}" ]; then
    DB_URL="${DATABASE_URL_AUTO}"
    echo -e "${GREEN}[OK] Usando banco criado automaticamente: ${DB_NAME}@localhost${NC}"
  else
    echo ""
    echo -e "${YELLOW}  Exemplo: postgresql://usuario:senha@localhost:5432/nome_do_banco${NC}"
    read -rp "URL de conexão: " DB_URL

    DB_URL="${DB_URL#DATABASE_URL=}"
    DB_URL="${DB_URL#database_url=}"

    if [ -z "$DB_URL" ]; then
      echo -e "${RED}[ERRO] URL do banco não pode ser vazia${NC}"
      exit 1
    fi
  fi

  ENV_FILE="${INSTALL_DIR}/.env"
  if [ -f "$ENV_FILE" ]; then
    sed -i '/^DATABASE_URL=/d' "$ENV_FILE"
  fi
  echo "DATABASE_URL=${DB_URL}" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo -e "${GREEN}[OK] Banco de dados configurado${NC}"
}

configure_port() {
  echo ""
  read -rp "Porta do sistema (padrão: 3000): " PORT
  PORT="${PORT:-3000}"
  ENV_FILE="${INSTALL_DIR}/.env"
  if grep -q "^PORT=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s/^PORT=.*/PORT=${PORT}/" "$ENV_FILE"
  else
    echo "PORT=${PORT}" >> "$ENV_FILE"
  fi
  echo -e "${GREEN}[OK] Sistema vai rodar na porta ${PORT}${NC}"
}

generate_secrets() {
  ENV_FILE="${INSTALL_DIR}/.env"

  if grep -q "^JWT_SECRET=" "$ENV_FILE" 2>/dev/null; then
    echo -e "${YELLOW}[INFO] JWT_SECRET já existe no .env — mantendo${NC}"
  else
    JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(48).toString('hex'))")
    echo "JWT_SECRET=${JWT_SECRET}" >> "$ENV_FILE"
    echo -e "${GREEN}[OK] JWT_SECRET gerado automaticamente${NC}"
  fi

  if grep -q "^SESSION_SECRET=" "$ENV_FILE" 2>/dev/null; then
    echo -e "${YELLOW}[INFO] SESSION_SECRET já existe no .env — mantendo${NC}"
  else
    SESSION_SECRET=$(node -e "console.log(require('crypto').randomBytes(48).toString('hex'))")
    echo "SESSION_SECRET=${SESSION_SECRET}" >> "$ENV_FILE"
    echo -e "${GREEN}[OK] SESSION_SECRET gerado automaticamente${NC}"
  fi
}

install_files() {
  echo ""
  echo -e "${BLUE}--- Instalando arquivos (modo local) ---${NC}"

  mkdir -p "$INSTALL_DIR"

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  cp -r "${SCRIPT_DIR}/dist" "${INSTALL_DIR}/"
  cp "${SCRIPT_DIR}/package.json" "${INSTALL_DIR}/"

  touch "${INSTALL_DIR}/.env"

  echo -e "${GREEN}[OK] Arquivos copiados para ${INSTALL_DIR}${NC}"

  echo ""
  echo -e "${BLUE}--- Instalando dependências ---${NC}"
  cd "$INSTALL_DIR"
  npm install --silent
  cd - > /dev/null

  echo -e "${GREEN}[OK] Dependências instaladas${NC}"
}

install_from_git() {
  echo ""
  echo -e "${BLUE}--- Instalando via GitHub (com atualização automática) ---${NC}"

  check_git

  if [ -d "${INSTALL_DIR}/.git" ]; then
    echo -e "${YELLOW}[INFO] Repositório já existe em ${INSTALL_DIR} — atualizando...${NC}"
    cd "$INSTALL_DIR"
    git fetch origin "${GITHUB_BRANCH}"
    git reset --hard "origin/${GITHUB_BRANCH}"
    cd - > /dev/null
  else
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
      echo -e "${YELLOW}[INFO] Fazendo backup de ${INSTALL_DIR} para ${INSTALL_DIR}.bak...${NC}"
      mv "$INSTALL_DIR" "${INSTALL_DIR}.bak"
    fi
    echo -e "${BLUE}[INFO] Clonando repositório...${NC}"
    git clone --branch "${GITHUB_BRANCH}" --depth 1 "${GITHUB_REPO}" "${INSTALL_DIR}"
  fi

  touch "${INSTALL_DIR}/.env"

  echo ""
  echo -e "${BLUE}--- Instalando dependências ---${NC}"
  cd "$INSTALL_DIR"
  npm install --silent
  cd - > /dev/null

  echo -e "${GREEN}[OK] Repositório clonado em ${INSTALL_DIR} — atualização automática habilitada!${NC}"
}

create_service() {
  echo ""
  echo -e "${BLUE}--- Configurando serviço systemd ---${NC}"

  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SVCEOF
[Unit]
Description=GeoTrack Pro — Sistema de Rastreamento
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/node ${INSTALL_DIR}/dist/index.cjs
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
  echo -e "${GREEN}[OK] Serviço systemd configurado (Restart=always para suportar atualização automática)${NC}"
}

start_service() {
  echo ""
  echo -e "${BLUE}--- Iniciando GeoTrack Pro ---${NC}"
  systemctl start "${SERVICE_NAME}"
  sleep 3

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo -e "${GREEN}[OK] GeoTrack Pro iniciado com sucesso!${NC}"
  else
    echo -e "${RED}[ERRO] Falha ao iniciar. Verifique os logs:${NC}"
    echo "  journalctl -u ${SERVICE_NAME} -n 50"
    exit 1
  fi
}

print_summary() {
  PORT=$(grep "^PORT=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "3000")
  echo ""
  echo -e "${GREEN}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║       GeoTrack Pro instalado com sucesso!    ║"
  echo "╠══════════════════════════════════════════════╣"
  echo "║                                              ║"
  printf "║  Acesso: http://IP-DA-VPS:%-17s  ║\n" "${PORT}"
  echo "║                                              ║"
  if [ "${INSTALL_FROM_GIT}" = "true" ]; then
  echo "║  Atualização automática: HABILITADA          ║"
  echo "║  Use o painel admin → Geral → Atualização    ║"
  echo "║                                              ║"
  fi
  echo "║  Comandos úteis:                             ║"
  echo "║  • Ver status:  systemctl status geotrack    ║"
  echo "║  • Ver logs:    journalctl -u geotrack -f    ║"
  echo "║  • Parar:       systemctl stop geotrack      ║"
  echo "║  • Reiniciar:   systemctl restart geotrack   ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ---- Execução principal ----
print_banner
check_root
check_node
choose_install_mode
setup_database

if [ "${INSTALL_FROM_GIT}" = "true" ]; then
  install_from_git
else
  install_files
fi

configure_license
configure_database
configure_port
generate_secrets
create_service
start_service
print_summary
