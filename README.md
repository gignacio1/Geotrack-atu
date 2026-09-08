# GeoTrack Pro — Repositório de Atualização

Arquivos compilados e ofuscados do GeoTrack Pro para distribuição automática.

## Instalação rápida (VPS Ubuntu/Debian)

```bash
curl -fsSL https://raw.githubusercontent.com/gignacio1/Geotrack-atu/main/scripts/install.sh -o /tmp/geotrack-install.sh && sudo bash /tmp/geotrack-install.sh
```

Na tela de instalação, escolha **2 — GitHub**.

## Atualização automática

Após instalar no modo GitHub:

**Painel admin → Configurações → Geral → Atualização do Sistema → Verificar → Atualizar agora**

O sistema reinicia automaticamente após a atualização.

## Comandos úteis

```bash
systemctl status geotrack
journalctl -u geotrack -f
systemctl restart geotrack
```
