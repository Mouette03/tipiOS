#!/bin/bash
# TipiOS — Script de démarrage du portail de configuration
# Lancé par systemd au premier démarrage uniquement.

set -e

HOTSPOT_SSID="TipiSetup"
HOTSPOT_PSK="TipiSetup2024!"
HOTSPOT_CON="TipiHotspot"

log() { echo "[tipi-setup] $*" ; }

# ------------------------------------------------------------------ #
#  1. Hotspot WiFi (si interface wlan0 disponible)                    #
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
        wifi-sec.psk "${HOTSPOT_PSK}"

    nmcli con up "${HOTSPOT_CON}" && \
        log "Hotspot '${HOTSPOT_SSID}' actif — IP RPi : 10.42.0.1" || \
        log "Avertissement : impossible de démarrer le hotspot"
else
    log "Pas d'interface wlan0 — hotspot non démarré"
fi

# ------------------------------------------------------------------ #
#  2. Annonce mDNS                                                    #
# ------------------------------------------------------------------ #
# Avahi est déjà actif via systemd. L'hostname "tipisetup" sera
# annoncé sur tous les réseaux → http://tipisetup.local

# ------------------------------------------------------------------ #
#  3. Lancement du portail web Flask (port 80)                        #
# ------------------------------------------------------------------ #
log "Démarrage du portail de configuration (port 80)..."
exec python3 /opt/tipi-setup/app.py
