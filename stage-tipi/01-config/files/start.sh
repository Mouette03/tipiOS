#!/bin/bash
# TipiOS — Script de démarrage du portail de configuration
# Lancé par systemd au premier démarrage uniquement.

set -e

HOTSPOT_SSID="TipiSetup"
HOTSPOT_PSK="TipiSetup2024!"
HOTSPOT_CON="TipiHotspot"
LOG="/boot/firmware/tipi-setup.log"

log() { echo "[tipi-setup] $*" | tee -a "$LOG" ; }

# Rediriger toute la sortie vers le log pour déboguer
exec > >(tee -a "$LOG") 2>&1
log "=== Démarrage tipi-setup $(date) ==="

# ------------------------------------------------------------------ #
#  1. Attendre que le réseau soit prêt (max 10s)                      #
# ------------------------------------------------------------------ #
for i in $(seq 1 10); do
    nmcli general status 2>/dev/null | grep -q 'connected\|disconnected' && break || sleep 1
done

# ------------------------------------------------------------------ #
#  2. Hotspot WiFi (si interface wlan0 disponible)                    #
# ------------------------------------------------------------------ #
if ip link show wlan0 &>/dev/null 2>&1; then
    log "Interface wlan0 détectée — création du hotspot..."

    # Supprimer l'ancienne connexion si elle existe
    nmcli con delete "${HOTSPOT_CON}" 2>/dev/null || true

    nmcli con add \
        type wifi \
        ifname wlan0 \
        con-name "${HOTSPOT_CON}" \
        autoconnect no \
        ssid "${HOTSPOT_SSID}" \
        802-11-wireless.mode ap \
        ipv4.method shared \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "${HOTSPOT_PSK}" && \
        log "Connexion hotspot créée" || log "ERREUR création hotspot"

    nmcli con up "${HOTSPOT_CON}" && \
        log "Hotspot '${HOTSPOT_SSID}' actif — IP RPi : 10.42.0.1" || \
        log "AVERTISSEMENT : impossible de démarrer le hotspot"
else
    log "Pas d'interface wlan0 — hotspot non démarré"
fi

# ------------------------------------------------------------------ #
#  3. Lancement du portail web Flask (port 80)                        #
# ------------------------------------------------------------------ #
log "Démarrage du portail de configuration (port 80)..."

# Flask tourne en root (systemd), pas besoin de setcap pour le port 80
exec python3 /opt/tipi-setup/app.py
