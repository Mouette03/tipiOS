# TipiOS

> A custom Raspberry Pi OS image with a first-boot web configuration portal and automatic [runTipi](https://runtipi.io) installation.

---

## 🇬🇧 English

### What is TipiOS?

TipiOS is a ready-to-flash Raspberry Pi OS image (Trixie Lite 64-bit) that guides you through initial setup via a local web portal on first boot — no keyboard, no monitor required.

Once configured, it automatically installs **runTipi**, a self-hosted app store for your Raspberry Pi (Plex, Nextcloud, Home Assistant, and 200+ more apps).

### Features

- **Zero-touch setup** — connect to the `TipiSetup` WiFi hotspot, open a browser, done
- **Web configuration portal** — hostname, SSH user/password, timezone, locale, static IP, WiFi
- **Multilingual** — English, French, German, Spanish (auto-detected, switchable at any time)
- **Automatic runTipi installation** — Docker included, starts on every reboot
- **mDNS support** — access via `tipisetup.local` without typing an IP address
- **Ethernet & WiFi** — works with both; WiFi hotspot as fallback

### First Boot Flow

```
Flash image → Power on → Connect to "TipiSetup" WiFi (no password)
→ Open http://tipisetup.local (or http://10.42.0.1)
→ Fill in the form → Click "Apply and install runTipi"
→ Watch the live log → Reboot → Access runTipi at http://<your-hostname>.local (e.g. http://tipios.local or http://192.168.1.50)
```

### Requirements

- Raspberry Pi 4 or 5
- microSD card (16 GB minimum, 32 GB recommended)
- A device with a web browser (phone, laptop, tablet)

### Building the Image

The image is built with [pi-gen](https://github.com/RPi-Distro/pi-gen) (arm64 branch).

```bash
# Clone the repo
git clone https://github.com/your-repo/tipiOS
cd tipiOS

# Build (requires Docker)
./build.sh

# Flash the resulting image
# The image is in deploy/
```

### Project Structure

```
stage-tipi/
└── 01-config/
    └── files/
        ├── app/
        │   ├── app.py            # Flask portal (port 8080)
        │   ├── setup.py          # System installation script
        │   ├── translations.py   # Shared i18n (EN/FR/DE/ES)
        │   ├── static/
        │   └── templates/
        │       ├── base.html
        │       ├── configure.html
        │       ├── progress.html
        │       └── wifi.html
        ├── start.sh              # Startup script (hostapd, dnsmasq, nftables, Flask)
        └── tipi-setup.service    # systemd service (runs on first boot only)
```

### How It Works

| Component | Role |
|-----------|------|
| `hostapd` | Creates the `TipiSetup` WiFi hotspot |
| `dnsmasq` | DHCP + DNS for connected clients |
| `nftables` | Redirects port 80 → 8080 (so `tipisetup.local` works without a port number) |
| `Flask` | Serves the configuration portal on port 8080 |
| `setup.py` | Runs as a subprocess: hostname, SSH, locale, WiFi, runTipi install |
| `avahi` | mDNS so `<hostname>.local` resolves on the local network |

### Adding a Language

Edit `stage-tipi/01-config/files/app/translations.py`:

1. Copy the `"en"` block and rename it (e.g. `"it"`)
2. Translate all values
3. Add the code to `LANG_LABELS` with its emoji + abbreviation

That's it — templates and `setup.py` pick it up automatically.

### License

MIT

---

## 🇫🇷 Français

### Qu'est-ce que TipiOS ?

TipiOS est une image Raspberry Pi OS prête à flasher (Trixie Lite 64-bit) qui guide la configuration initiale via un portail web local au premier démarrage — sans clavier, sans écran.

Une fois configuré, il installe automatiquement **runTipi**, un store d'applications auto-hébergé pour Raspberry Pi (Plex, Nextcloud, Home Assistant, et 200+ applications).

### Fonctionnalités

- **Configuration sans écran** — connectez-vous au hotspot WiFi `TipiSetup`, ouvrez un navigateur, c'est tout
- **Portail de configuration web** — hostname, utilisateur SSH, mot de passe, fuseau horaire, locale, IP statique, WiFi
- **Multilingue** — anglais, français, allemand, espagnol (changeable à tout moment)
- **Installation automatique de runTipi** — Docker inclus, démarre à chaque reboot
- **Support mDNS** — accès via `tipisetup.local` sans saisir d'adresse IP
- **Ethernet & WiFi** — fonctionne avec les deux ; hotspot WiFi en solution de repli

### Déroulement au premier démarrage

```
Flasher l'image → Démarrer → Se connecter au WiFi "TipiSetup" (sans mot de passe)
→ Ouvrir http://tipisetup.local (ou http://10.42.0.1)
→ Remplir le formulaire → Cliquer "Appliquer et installer runTipi"
→ Suivre les logs en direct → Redémarrer → Accéder à runTipi sur http://<votre-hostname>.local (ex : http://tipios.local ou http://192.168.1.50)
```

### Matériel requis

- Raspberry Pi 4 ou 5
- Carte microSD (16 Go minimum, 32 Go recommandé)
- Un appareil avec un navigateur web (téléphone, ordinateur, tablette)

### Construction de l'image

L'image est construite avec [pi-gen](https://github.com/RPi-Distro/pi-gen) (branche arm64).

```bash
# Cloner le dépôt
git clone https://github.com/your-repo/tipiOS
cd tipiOS

# Construire (nécessite Docker)
./build.sh

# Flasher l'image résultante
# L'image se trouve dans deploy/
```

### Structure du projet

```
stage-tipi/
└── 01-config/
    └── files/
        ├── app/
        │   ├── app.py            # Portail Flask (port 8080)
        │   ├── setup.py          # Script d'installation système
        │   ├── translations.py   # i18n partagé (EN/FR/DE/ES)
        │   ├── static/
        │   └── templates/
        │       ├── base.html
        │       ├── configure.html
        │       ├── progress.html
        │       └── wifi.html
        ├── start.sh              # Script de démarrage (hostapd, dnsmasq, nftables, Flask)
        └── tipi-setup.service    # Service systemd (premier démarrage uniquement)
```

### Fonctionnement

| Composant | Rôle |
|-----------|------|
| `hostapd` | Crée le hotspot WiFi `TipiSetup` |
| `dnsmasq` | DHCP + DNS pour les clients connectés |
| `nftables` | Redirige le port 80 → 8080 (pour `tipisetup.local` sans numéro de port) |
| `Flask` | Sert le portail de configuration sur le port 8080 |
| `setup.py` | S'exécute en subprocess : hostname, SSH, locale, WiFi, installation runTipi |
| `avahi` | mDNS pour que `<hostname>.local` soit résolu sur le réseau local |

### Ajouter une langue

Éditez `stage-tipi/01-config/files/app/translations.py` :

1. Copiez le bloc `"en"` et renommez-le (ex : `"it"`)
2. Traduisez toutes les valeurs
3. Ajoutez le code dans `LANG_LABELS` avec son emoji + sigle

C'est tout — les templates et `setup.py` l'utiliseront automatiquement.

### Licence

MIT
