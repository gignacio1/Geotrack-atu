#!/bin/bash
# Script para fazer push dos arquivos compilados pro repositório de atualização
# Execute na raiz do projeto GeoTrack Pro após fazer o build
# Uso: bash scripts/push-update-repo.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO_URL="https://github.com/gignacio1/Geotrack-atu.git"
BRANCH="main"
TMP_DIR="/tmp/geotrack-push-atu"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════╗"
echo "║   GeoTrack Pro — Push Repositório de Update  ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -f "dist/index.cjs" ] || [ ! -d "dist/public" ]; then
  echo -e "${RED}[ERRO] dist/index.cjs ou dist/public não encontrados.${NC}"
  echo "Execute o build antes: bash scripts/build-linux.sh"
  exit 1
fi

echo -e "${YELLOW}[INFO] Informe seu GitHub Personal Access Token (PAT com permissão 'repo'):${NC}"
read -rsp "Token: " GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_TOKEN" ]; then
  echo -e "${RED}[ERRO] Token não pode ser vazio.${NC}"
  exit 1
fi

REPO_AUTH_URL="https://gignacio1:${GITHUB_TOKEN}@github.com/gignacio1/Geotrack-atu.git"

echo -e "${BLUE}[INFO] Preparando arquivos...${NC}"
rm -rf "$TMP_DIR"

# Clona o estado atual em vez de criar uma raiz nova e usar push --force.
# Assim, as instalações existentes continuam tendo histórico compatível.
git -c credential.helper="" clone --depth=1 "$REPO_AUTH_URL" "$TMP_DIR"
mkdir -p "$TMP_DIR/dist/public" "$TMP_DIR/scripts"

cp dist/index.cjs "$TMP_DIR/dist/index.cjs"
rm -rf "$TMP_DIR/dist/public/"*
cp -r dist/public/* "$TMP_DIR/dist/public/"
cp scripts/package.production.json "$TMP_DIR/package.json"
cp scripts/install.sh "$TMP_DIR/scripts/install.sh"
cp scripts/setup-domain.sh "$TMP_DIR/scripts/setup-domain.sh"
chmod +x "$TMP_DIR/scripts/install.sh" "$TMP_DIR/scripts/setup-domain.sh"

cat > "$TMP_DIR/README.md" << 'EOF'
# GeoTrack Pro — Repositório de Atualização

Arquivos compilados e ofuscados do GeoTrack Pro para distribuição automática.

## Instalação rápida (VPS Ubuntu/Debian)

```bash
curl -fsSL https://raw.githubusercontent.com/gignacio1/Geotrack-atu/main/scripts/install.sh -o /tmp/geotrack-install.sh && sudo bash /tmp/geotrack-install.sh
```

Na tela de instalação, escolha **2 — GitHub**.

## Atualização automática

No painel admin → Configurações → Geral → Atualização do Sistema → Verificar → Atualizar agora.
EOF

echo -e "${BLUE}[INFO] Atualizando repositório git...${NC}"
cd "$TMP_DIR"
git add -A
VERSION=$(date +"%Y.%m.%d-%H%M")
if git diff --cached --quiet; then
  echo -e "${YELLOW}[INFO] Nenhuma alteração para publicar.${NC}"
  rm -rf "$TMP_DIR"
  exit 0
fi
git config user.email "geotrack@deploy.local"
git config user.name "GeoTrack Deploy"
git commit -q -m "release: v${VERSION} — atualização automática"

echo -e "${BLUE}[INFO] Fazendo push para GitHub...${NC}"
git -c credential.helper="" push origin "$BRANCH"

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════╗"
echo "║         Push realizado com sucesso!          ║"
echo "╠══════════════════════════════════════════════╣"
echo "║                                              ║"
echo "║  Repositório: gignacio1/Geotrack-atu         ║"
echo "║  Branch: main                                ║"
echo "║  Clientes já podem atualizar pelo painel!    ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

rm -rf "$TMP_DIR"
