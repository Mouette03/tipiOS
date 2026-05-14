#!/bin/bash -e
# pi-gen run.sh — Installe et configure tipi-setup dans le rootfs

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
set -x  # afficher chaque commande exécutée dans les logs

# ---- Neutraliser le wizard de premier démarrage RPi OS ----
# mask = plus fort que disable, empêche tout démarrage même indirect
systemctl mask userconfig.service || true
systemctl mask rpi-first-boot-wizard.service || true

# Supprimer les unit files du wizard s'ils existent
rm -f /lib/systemd/system/userconfig.service \
      /lib/systemd/system/rpi-first-boot-wizard.service \
      /etc/systemd/system/userconfig.service \
      2>/dev/null || true

# Supprimer le déclencheur piwiz (interface graphique)
rm -f /etc/xdg/autostart/piwiz.desktop 2>/dev/null || true

# Créer le fichier marqueur utilisé par certaines versions de RPi OS
# pour indiquer que la configuration initiale est déjà faite
touch /boot/firmware/firstrun_done 2>/dev/null || touch /boot/firstrun_done 2>/dev/null || true

# NE PAS supprimer firstrun.sh : dans Trixie c'est lui qui crée l'utilisateur
# (FIRST_USER_NAME / FIRST_USER_PASS). Le supprimer empêche toute connexion.

# Activer le service tipi-setup
systemctl enable tipi-setup.service

# Activer Avahi (mDNS / .local)
systemctl enable avahi-daemon.service

# Configurer nsswitch pour résoudre les noms .local via mDNS
sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf

# Hostname de provisionnement (sera remplacé au premier démarrage)
echo "tipisetup" > /etc/hostname
sed -i '/127\.0\.1\.1/d' /etc/hosts
echo "127.0.1.1   tipisetup" >> /etc/hosts

# Répertoire de templates Flask (chemin absolu pour le service)
echo 'FLASK_TEMPLATE_FOLDER=/opt/tipi-setup/templates' >> /etc/environment

set +x
EOF
