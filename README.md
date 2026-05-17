# GeoTrack Pro — Repositório de Atualização

  ## Instalação rápida (VPS Ubuntu/Debian)

  Cole este comando na VPS e siga as instruções na tela:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/gignacio1/Geotrack-atu/main/scripts/install.sh -o /tmp/geotrack-install.sh && sudo bash /tmp/geotrack-install.sh
  ```

  > Quando aparecer **"Modo de Instalação"**, escolha **2 — GitHub** para habilitar a atualização automática pelo painel admin.

  ---

  ## Configurar domínio + SSL (opcional)

  Após a instalação, para configurar um domínio com HTTPS:

  ```bash
  sudo bash /opt/geotrack/scripts/setup-domain.sh
  ```

  ---

  ## Atualização automática

  Após instalar no modo GitHub, para atualizar quando uma nova versão for publicada:

  **Painel admin → Configurações → Geral → Atualização do Sistema → Verificar → Atualizar agora**

  O sistema reinicia automaticamente após a atualização.

  ---

  ## Comandos úteis na VPS

  ```bash
  systemctl status geotrack       # ver status
  journalctl -u geotrack -f       # ver logs em tempo real
  systemctl restart geotrack      # reiniciar manualmente
  ```

  ---

  ## v1.5.6
  - Checksum XOR nos comandos RST (bloqueio/desbloqueio via GPRS)
  - Favicon personalizado
  - Sistema de atualização automática via painel admin
  - Instalador com modo arquivo local e modo GitHub
  