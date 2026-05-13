#!/bin/bash -e
# pi-gen — Installation des paquets du stage tipi

apt-get install -y --no-install-recommends $(cat "${STAGE_DIR}/packages")
