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
#  1. Attendre NetworkManager + débloquer le WiFi                     #
# ------------------------------------------------------------------ #
for i in $(seq 1 15); do
    nmcli general status 2>/dev/null | grep -q 'connecté\|connected\|disconnected\|déconnecté' && break || sleep 1
done

# Débloquer le WiFi (rfkill soft/hard block fréquent sur RPi au boot)
rfkill unblock wifi 2>/dev/null || true
rfkill unblock all  2>/dev/null || true
log "rfkill unblock effectué"

# Configurer le domaine réglementaire WiFi (OBLIGATOIRE sur RPi)
# Sans code pays, le chipset reste inactif et NM rapporte wlan0 unavailable
iw reg set US 2>/dev/null || log "iw reg set échoué"
log "Domaine réglementaire : $(iw reg get 2>/dev/null | head -1 || echo inconnu)"

# ------------------------------------------------------------------ #
#  2. Attendre que wlan0 soit DISPONIBLE dans NetworkManager (max 30s) #
# ------------------------------------------------------------------ #
WLAN_READY=0
if ip link show wlan0 &>/dev/null; then
    log "Interface wlan0 présente — attente disponibilité NM..."
    for i in $(seq 1 30); do
        state=$(nmcli -t -f DEVICE,STATE dev status 2>/dev/null | grep "^wlan0:" | cut -d: -f2)
        log "  wlan0 état ($i/30) : ${state:-inconnu}"
        case "$state" in
            disconnected|déconnecté|disconnected*)
                WLAN_READY=1
                break
                ;;
            unavailable|indisponible)
                # Essayer de forcer NM à reprendre le device
                nmcli dev set wlan0 managed yes 2>/dev/null || true
                sleep 1
                ;;
            *)
                sleep 1
                ;;
        esac
    done
else
    log "Pas d'interface wlan0 — hotspot non démarré"
    ip link 2>&1 | head -20
fi

# ------------------------------------------------------------------ #
#  3. Créer le hotspot WiFi                                           #
# ------------------------------------------------------------------ #
if [ "$WLAN_READY" = "1" ]; then
    log "wlan0 prêt — création du hotspot..."

    # Supprimer l'ancienne connexion si elle existe
    nmcli con delete "${HOTSPOT_CON}" 2>/dev/null || true

    if nmcli dev wifi hotspot \
            ifname wlan0 \
            con-name "${HOTSPOT_CON}" \
            ssid "${HOTSPOT_SSID}" \
            password "${HOTSPOT_PSK}"; then
        log "Hotspot '${HOTSPOT_SSID}' actif — IP RPi : 10.42.0.1"
    else
        log "ERREUR : nmcli dev wifi hotspot a échoué (code $?)"
        nmcli dev status 2>&1
        rfkill list 2>&1
    fi
elif ip link show wlan0 &>/dev/null; then
    log "ERREUR : wlan0 toujours indisponible après 30s — état NM :"
    nmcli dev status 2>&1
    rfkill list 2>&1
fi

# ------------------------------------------------------------------ #
#  3. Lancement du portail web Flask (port 80)                        #
# ------------------------------------------------------------------ #
log "Démarrage du portail de configuration (port 80)..."

# Flask tourne en root (systemd), pas besoin de setcap pour le port 80
exec python3 /opt/tipi-setup/app.py
