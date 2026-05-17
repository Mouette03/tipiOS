#!/bin/bash -e
# pi-gen 00-run.sh — Installe et configure tipi-setup dans le rootfs
# IMPORTANT : nommé 00-run.sh (avec préfixe numérique) comme requis par pi-gen

# ---- Arborescence ----
install -v -d "${ROOTFS_DIR}/opt/tipi-setup/templates"
install -v -d "${ROOTFS_DIR}/var/lib/tipi-setup"
install -v -d "${ROOTFS_DIR}/etc/NetworkManager/dnsmasq-shared.d"

# ---- Fichiers de l'application ----
install -v -m 755 files/start.sh                          "${ROOTFS_DIR}/opt/tipi-setup/start.sh"
install -v -m 644 files/app/app.py                        "${ROOTFS_DIR}/opt/tipi-setup/app.py"
install -v -m 644 files/app/setup.py                      "${ROOTFS_DIR}/opt/tipi-setup/setup.py"
install -v -m 644 files/app/templates/base.html           "${ROOTFS_DIR}/opt/tipi-setup/templates/base.html"
install -v -m 644 files/app/templates/wifi.html           "${ROOTFS_DIR}/opt/tipi-setup/templates/wifi.html"
install -v -m 644 files/app/templates/configure.html      "${ROOTFS_DIR}/opt/tipi-setup/templates/configure.html"
install -v -m 644 files/app/templates/progress.html       "${ROOTFS_DIR}/opt/tipi-setup/templates/progress.html"

# ---- Systemd service ----
install -v -m 644 files/tipi-setup.service                "${ROOTFS_DIR}/etc/systemd/system/tipi-setup.service"

# ---- DNS captif (NetworkManager hotspot) ----
install -v -m 644 files/dnsmasq-captive.conf              "${ROOTFS_DIR}/etc/NetworkManager/dnsmasq-shared.d/captive-portal.conf"

# ---- Marqueur de premier démarrage ----
touch "${ROOTFS_DIR}/var/lib/tipi-setup/.not-configured"

# ---- Activation dans le chroot ----
on_chroot << EOF
set -x  # afficher chaque commande exécutée dans les logs pi-gen

# ---- Neutraliser le wizard de premier démarrage RPi OS ----
systemctl mask userconfig.service || true
systemctl mask rpi-first-boot-wizard.service || true
rm -f /lib/systemd/system/userconfig.service \
      /lib/systemd/system/rpi-first-boot-wizard.service \
      /etc/systemd/system/userconfig.service \
      /etc/xdg/autostart/piwiz.desktop 2>/dev/null || true

# ---- Domaine réglementaire WiFi (brcmfmac / RPi 4+5) ----
# cfg80211 = couche WiFi kernel, ieee80211_regdom s'applique avant que brcmfmac verrouille
echo 'options cfg80211 ieee80211_regdom=US' > /etc/modprobe.d/cfg80211.conf
# CRDA fallback
echo 'REGDOMAIN=US' > /etc/default/crda
# wpa_supplicant.conf : NM lit ce fichier via son plugin wpa_supplicant
mkdir -p /etc/wpa_supplicant
printf 'country=US\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\n' \
    > /etc/wpa_supplicant/wpa_supplicant.conf
# Désactiver le service wpa_supplicant standalone (NM le gère en interne)
systemctl disable wpa_supplicant.service 2>/dev/null || true

# Activer le service tipi-setup
systemctl enable tipi-setup.service
systemctl enable avahi-daemon.service

# Configurer nsswitch pour résoudre les noms .local via mDNS
sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf

# Hostname de provisionnement (sera remplacé via portail web)
echo "tipisetup" > /etc/hostname
sed -i '/127\.0\.1\.1/d' /etc/hosts
echo "127.0.1.1   tipisetup" >> /etc/hosts

set +x
EOF
