#!/bin/bash
# TipiOS — Script de démarrage du portail de configuration
# Lancé par systemd au premier démarrage uniquement.

set -e

HOTSPOT_SSID="TipiSetup"
HOTSPOT_PSK="TipiSetup2024!"
HOTSPOT_CON="TipiHotspot"
LOG="/boot/firmware/tipi-setup.log"

log() { echo "[tipi-setup] $*"; }

# Rediriger toute la sortie vers le log (une seule fois)
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
if ip link show wlan0 &>/dev/null; then
    log "Interface wlan0 détectée — création du hotspot..."

    # Supprimer l'ancienne connexion si elle existe
    nmcli con delete "${HOTSPOT_CON}" 2>/dev/null || true

    # Créer et activer le hotspot en une seule commande (device explicite)
    if nmcli dev wifi hotspot \
            ifname wlan0 \
            con-name "${HOTSPOT_CON}" \
            ssid "${HOTSPOT_SSID}" \
            password "${HOTSPOT_PSK}"; then
        log "Hotspot '${HOTSPOT_SSID}' actif — IP RPi : 10.42.0.1"
    else
        log "ERREUR : nmcli dev wifi hotspot a échoué (code $?)"
        # Afficher l'état des devices NM pour diagnostiquer
        nmcli dev status >> "$LOG" 2>&1 || true
    fi
else
    log "Pas d'interface wlan0 — hotspot non démarré"
    ip link >> "$LOG" 2>&1 || true
fi

# ------------------------------------------------------------------ #
#  3. Lancement du portail web Flask (port 80)                        #
# ------------------------------------------------------------------ #
log "Démarrage du portail de configuration (port 80)..."

# Flask tourne en root (systemd), pas besoin de setcap pour le port 80
exec python3 /opt/tipi-setup/app.py
