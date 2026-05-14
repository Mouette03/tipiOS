#!/bin/bash
# TipiOS — Script de démarrage du portail de configuration
# Lancé par systemd au premier démarrage uniquement.

# PAS de set -e : on veut gérer chaque erreur nous-mêmes sans tuer le script

HOTSPOT_SSID="TipiSetup"
HOTSPOT_PSK="TipiSetup2024!"
HOTSPOT_CON="TipiHotspot"
LOG="/boot/firmware/tipi-setup.log"

log() { echo "[tipi-setup] $*"; }

# Rediriger toute la sortie (stdout + stderr) vers le log + console
exec > >(tee -a "$LOG") 2>&1
log "=== Démarrage tipi-setup $(date) ==="

# ------------------------------------------------------------------ #
#  1. Attendre NetworkManager + débloquer le WiFi                     #
# ------------------------------------------------------------------ #
for i in $(seq 1 15); do
    nmcli general status 2>/dev/null | grep -q 'connecté\|connected\|disconnected\|déconnecté' && break || sleep 1
done

rfkill unblock wifi 2>/dev/null || true
rfkill unblock all  2>/dev/null || true
log "rfkill unblock effectué"

iw reg set US 2>/dev/null || true
log "Domaine réglementaire : $(iw reg get 2>/dev/null | head -1 || echo inconnu)"

# ------------------------------------------------------------------ #
#  2. Hotspot : créer seulement s'il n'est pas déjà actif             #
# ------------------------------------------------------------------ #
hotspot_active() {
    nmcli -t -f NAME,STATE con show --active 2>/dev/null | grep -q "^${HOTSPOT_CON}:activated"
}

if hotspot_active; then
    log "Hotspot '${HOTSPOT_SSID}' déjà actif — skip création"
elif ip link show wlan0 &>/dev/null; then
    log "Interface wlan0 présente — attente disponibilité NM (max 30s)..."
    WLAN_READY=0
    for i in $(seq 1 30); do
        state=$(nmcli -t -f DEVICE,STATE dev status 2>/dev/null | grep "^wlan0:" | cut -d: -f2)
        case "$state" in
            disconnected|déconnecté)
                WLAN_READY=1
                log "wlan0 prêt (état: $state) après ${i}s"
                break
                ;;
            unavailable|indisponible)
                nmcli dev set wlan0 managed yes 2>/dev/null || true
                sleep 1
                ;;
            connected|connecté)
                # wlan0 déjà connecté à un réseau — on essaie quand même le mode AP
                WLAN_READY=1
                log "wlan0 connecté — tentative hotspot en parallèle"
                break
                ;;
            *)
                sleep 1
                ;;
        esac
    done

    if [ "$WLAN_READY" = "1" ]; then
        nmcli con delete "${HOTSPOT_CON}" 2>/dev/null || true
        if nmcli dev wifi hotspot \
                ifname wlan0 \
                con-name "${HOTSPOT_CON}" \
                ssid "${HOTSPOT_SSID}" \
                password "${HOTSPOT_PSK}"; then
            log "Hotspot '${HOTSPOT_SSID}' actif — IP RPi : 10.42.0.1"
        else
            log "ERREUR hotspot (code $?) — état NM :"
            nmcli dev status 2>&1 || true
            rfkill list 2>&1 || true
        fi
    else
        log "ERREUR : wlan0 toujours indisponible après 30s"
        nmcli dev status 2>&1 || true
    fi
else
    log "Pas d'interface wlan0 — hotspot ignoré"
    ip link 2>&1 | head -10 || true
fi

# ------------------------------------------------------------------ #
#  3. Lancement du portail web Flask (port 80)                        #
# ------------------------------------------------------------------ #
log "Démarrage du portail de configuration (port 80)..."
python3 /opt/tipi-setup/app.py
EXIT_CODE=$?
log "Flask terminé avec code $EXIT_CODE"
exit $EXIT_CODE
