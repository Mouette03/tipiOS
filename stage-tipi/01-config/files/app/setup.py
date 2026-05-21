#!/usr/bin/env python3
"""
TipiOS — Script d'installation système
Lancé par app.py via subprocess. Toutes les sorties sont capturées et
relayées en temps réel vers le portail web.

Protocole de sortie :
  TIPI_STEP:<message>   → étape en cours (badge coloré)
  TIPI_DONE:<message>   → étape réussie (badge vert)
  TIPI_ERROR:<message>  → erreur non fatale (badge rouge)
  TIPI_IP:<adresse>     → IP finale de runTipi
  <autre>               → log brut (affiché en gris)
"""

import json
import os
import pwd
import re
import subprocess
import sys


# ---------------------------------------------------------------------------
# Helpers de log
# ---------------------------------------------------------------------------

def step(msg: str):  print(f"TIPI_STEP:{msg}",  flush=True)
def done(msg: str):  print(f"TIPI_DONE:{msg}",  flush=True)
def err(msg: str):   print(f"TIPI_ERROR:{msg}", flush=True)
def out(msg: str):   print(msg,                 flush=True)


def run_cmd(cmd: list, env=None, check=True) -> subprocess.CompletedProcess:
    """Exécute une commande et streame sa sortie ligne par ligne."""
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )
    for line in iter(proc.stdout.readline, ""):
        line = line.rstrip()
        if line:
            out(line)
    proc.wait()
    if check and proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd)
    return proc


def validate_ip(ip: str) -> bool:
    pattern = re.compile(r"^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$")
    if not pattern.match(ip):
        return False
    return all(0 <= int(p) <= 255 for p in ip.split("/")[0].split("."))


# ---------------------------------------------------------------------------
# Étapes de configuration
# ---------------------------------------------------------------------------

def configure_hostname(hostname: str):
    step("Configuration du hostname...")
    subprocess.run(["hostnamectl", "set-hostname", hostname], check=True)

    with open("/etc/hosts", "r") as f:
        hosts = f.read()
    if "127.0.1.1" in hosts:
        hosts = re.sub(r"127\.0\.1\.1\s+\S+", f"127.0.1.1\t{hostname}", hosts)
    else:
        hosts += f"\n127.0.1.1\t{hostname}\n"
    with open("/etc/hosts", "w") as f:
        f.write(hosts)

    done(f"Hostname : {hostname}")


def configure_timezone(timezone: str):
    step(f"Fuseau horaire → {timezone}")
    subprocess.run(["timedatectl", "set-timezone", timezone], check=True)
    done(f"Fuseau horaire configuré : {timezone}")


def configure_locale(locale: str):
    step(f"Locale → {locale}")
    try:
        locale_gen_path = "/etc/locale.gen"
        with open(locale_gen_path, "r") as f:
            content = f.read()
        # Décommenter la ligne correspondante
        content = content.replace(f"# {locale} ", f"{locale} ")
        with open(locale_gen_path, "w") as f:
            f.write(content)
        run_cmd(["locale-gen"])
        run_cmd(["update-locale", f"LANG={locale}"])
        done(f"Locale : {locale}")
    except Exception as e:
        err(f"Locale (non bloquant) : {e}")


def create_user(username: str, password: str):
    step(f"Création de l'utilisateur '{username}'...")

    # Créer l'utilisateur s'il n'existe pas
    result = subprocess.run(["id", username], capture_output=True)
    if result.returncode != 0:
        subprocess.run(
            ["useradd", "-m", "-s", "/bin/bash", "-G", "sudo", username],
            check=True,
        )

    # Définir le mot de passe via chpasswd (pas d'expansion shell, sécurisé)
    proc = subprocess.Popen(
        ["chpasswd"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    _, stderr = proc.communicate(input=f"{username}:{password}".encode())
    if proc.returncode != 0:
        raise RuntimeError(f"chpasswd a échoué : {stderr.decode()}")

    done(f"Utilisateur '{username}' créé")


def add_ssh_key(username: str, ssh_key: str):
    if not ssh_key:
        return
    step("Ajout de la clé SSH publique...")
    try:
        pw = pwd.getpwnam(username)
        ssh_dir = f"/home/{username}/.ssh"
        auth_keys = f"{ssh_dir}/authorized_keys"

        os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
        with open(auth_keys, "a") as f:
            f.write(ssh_key.strip() + "\n")
        os.chmod(auth_keys, 0o600)
        os.chown(ssh_dir, pw.pw_uid, pw.pw_gid)
        os.chown(auth_keys, pw.pw_uid, pw.pw_gid)
        done("Clé SSH publique ajoutée")
    except Exception as e:
        err(f"Clé SSH (non bloquant) : {e}")


def configure_ssh(ssh_port: str, disable_password_auth: bool, ssh_key: str):
    step(f"Configuration SSH (port {ssh_port})...")
    try:
        with open("/etc/ssh/sshd_config", "r") as f:
            sshd = f.read()

        # Port
        if re.search(r"^#?Port\s+\d+", sshd, re.MULTILINE):
            sshd = re.sub(r"^#?Port\s+\d+", f"Port {ssh_port}", sshd, flags=re.MULTILINE)
        else:
            sshd = f"Port {ssh_port}\n" + sshd

        # Désactiver auth par mdp si clé SSH fournie
        if disable_password_auth and ssh_key:
            sshd = re.sub(
                r"^#?PasswordAuthentication\s+\w+",
                "PasswordAuthentication no",
                sshd,
                flags=re.MULTILINE,
            )

        # Activer SSH (sécurité)
        sshd = re.sub(r"^#?PermitRootLogin\s+\w+", "PermitRootLogin no", sshd, flags=re.MULTILINE)

        with open("/etc/ssh/sshd_config", "w") as f:
            f.write(sshd)

        subprocess.run(["systemctl", "restart", "ssh"], check=True)
        done(f"SSH configuré sur le port {ssh_port}")
    except Exception as e:
        err(f"Configuration SSH : {e}")


def configure_static_ip(static_ip: str, static_gw: str, static_dns: str):
    if not static_ip or not static_gw:
        return
    if not validate_ip(static_ip) or not validate_ip(static_gw):
        err("IP statique invalide — ignorée")
        return

    step(f"Configuration de l'IP statique ({static_ip})...")
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "NAME,DEVICE", "con", "show", "--active"],
            capture_output=True, text=True,
        )
        eth_con = None
        for line in result.stdout.strip().splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and parts[1] == "eth0":
                eth_con = parts[0]
                break

        if not eth_con:
            err("Connexion Ethernet active introuvable — IP statique ignorée")
            return

        ip_cidr = static_ip if "/" in static_ip else f"{static_ip}/24"
        subprocess.run(["nmcli", "con", "mod", eth_con, "ipv4.addresses", ip_cidr], check=True)
        subprocess.run(["nmcli", "con", "mod", eth_con, "ipv4.gateway", static_gw], check=True)
        subprocess.run(["nmcli", "con", "mod", eth_con, "ipv4.dns", static_dns], check=True)
        subprocess.run(["nmcli", "con", "mod", eth_con, "ipv4.method", "manual"], check=True)
        subprocess.run(["nmcli", "con", "up", eth_con], check=True)
        done(f"IP statique appliquée : {static_ip}")
    except Exception as e:
        err(f"IP statique : {e}")


def system_update():
    step("Mise à jour du système (apt update)...")
    env = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
    run_cmd(["apt-get", "update", "-y"], env=env, check=False)
    done("Index des paquets mis à jour")

    step("Installation des mises à jour disponibles...")
    run_cmd([
        "apt-get", "upgrade", "-y",
        "-o", "Dpkg::Options::=--force-confdef",
        "-o", "Dpkg::Options::=--force-confold",
    ], env=env, check=False)
    done("Système à jour")


def connect_wifi(wifi_ssid: str, wifi_password: str):
    """Connecte wlan0 au WiFi choisi — appelé EN DERNIER (coupe le hotspot)."""
    if not wifi_ssid:
        return
    import time
    step(f"Connexion WiFi → '{wifi_ssid}'...")
    try:
        # Arrêter hostapd et dnsmasq avant de rendre wlan0 à NM
        subprocess.run(["pkill", "-f", "tipi-hostapd.conf"], capture_output=True)
        subprocess.run(["pkill", "-f", "tipi-dnsmasq"], capture_output=True)
        subprocess.run(["pkill", "hostapd"], capture_output=True)
        time.sleep(1)
        # Remettre wlan0 sous gestion NetworkManager
        subprocess.run(["nmcli", "dev", "set", "wlan0", "managed", "yes"],
                       capture_output=True)
        time.sleep(2)

        # Supprimer tout profil existant pour éviter les conflits de key-mgmt
        subprocess.run(["nmcli", "con", "delete", "tipi-wifi"],
                       capture_output=True)

        # Créer un profil propre avec les paramètres de sécurité explicites
        if wifi_password:
            add_cmd = [
                "nmcli", "con", "add",
                "type", "wifi",
                "ifname", "wlan0",
                "con-name", "tipi-wifi",
                "ssid", wifi_ssid,
                "wifi-sec.key-mgmt", "wpa-psk",
                "wifi-sec.psk", wifi_password,
            ]
        else:
            # Réseau ouvert — pas de section sécurité
            add_cmd = [
                "nmcli", "con", "add",
                "type", "wifi",
                "ifname", "wlan0",
                "con-name", "tipi-wifi",
                "ssid", wifi_ssid,
            ]

        result = subprocess.run(add_cmd, capture_output=True, text=True)
        if result.returncode != 0:
            err(f"WiFi — création profil : {(result.stderr or result.stdout).strip()}")
            return

        result = subprocess.run(
            ["nmcli", "con", "up", "tipi-wifi"],
            capture_output=True, text=True, timeout=40,
        )
        if result.returncode == 0:
            done(f"WiFi connecté : {wifi_ssid}")
        else:
            err(f"WiFi — connexion échouée : {(result.stderr or result.stdout).strip()}")
    except subprocess.TimeoutExpired:
        err("WiFi — délai dépassé (40 s)")
    except Exception as e:
        err(f"WiFi : {e}")


def install_runtipi():
    step("Installation de runTipi (Docker inclus — patience)...")
    try:
        # Commande officielle : curl -L https://setup.runtipi.io | bash
        curl = subprocess.Popen(
            ["curl", "-L", "--max-time", "120", "https://setup.runtipi.io"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        bash = subprocess.Popen(
            ["bash"],
            stdin=curl.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        curl.stdout.close()  # permet à curl de recevoir SIGPIPE si bash se termine

        for line in iter(bash.stdout.readline, ""):
            line = line.rstrip()
            if line:
                out(line)

        bash.wait()
        curl.wait()

        if bash.returncode != 0:
            # Le script peut échouer à démarrer runTipi si le port 80 est pris ;
            # le service systemd est déjà enregistré et démarrera au prochain reboot.
            err(f"runTipi : le démarrage initial a échoué (code {bash.returncode}) — il démarrera au reboot.")
        else:
            done("runTipi installé avec succès !")
    except Exception as e:
        err(f"Installation runTipi : {e}")


def get_final_ip() -> str | None:
    for iface in ["eth0", "wlan0"]:
        try:
            r = subprocess.run(
                ["ip", "-4", "addr", "show", iface],
                capture_output=True, text=True,
            )
            m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", r.stdout)
            if m and not m.group(1).startswith("10.42."):
                return m.group(1)
        except Exception:
            pass
    return None


# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) != 2:
        print("Usage: setup.py <config.json>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    try:
        with open(config_path) as f:
            cfg = json.load(f)
    except Exception as e:
        err(f"Lecture de la configuration impossible : {e}")
        sys.exit(1)
    finally:
        # Supprimer le fichier de config dès qu'il est lu (contient le mdp)
        try:
            os.remove(config_path)
        except Exception:
            pass

    hostname             = cfg.get("hostname", "tipios")
    username             = cfg.get("username", "")
    password             = cfg.get("password", "")
    ssh_port             = str(cfg.get("ssh_port", "22"))
    ssh_key              = cfg.get("ssh_key", "").strip()
    disable_password_auth = bool(cfg.get("disable_password_auth", False))
    timezone             = cfg.get("timezone", "Europe/Paris")
    locale               = cfg.get("locale", "fr_FR.UTF-8")
    static_ip            = cfg.get("static_ip", "")
    static_gw            = cfg.get("static_gw", "")
    static_dns           = cfg.get("static_dns", "8.8.8.8")
    wifi_ssid             = cfg.get("wifi_ssid", "").strip()
    wifi_password         = cfg.get("wifi_password", "").strip()

    # Validation minimale
    if not username or not password:
        err("Nom d'utilisateur ou mot de passe manquant")
        sys.exit(1)

    # --- Pipeline d'installation ---
    configure_hostname(hostname)
    configure_timezone(timezone)
    configure_locale(locale)
    create_user(username, password)
    add_ssh_key(username, ssh_key)
    configure_ssh(ssh_port, disable_password_auth, ssh_key)
    configure_static_ip(static_ip, static_gw, static_dns)
    system_update()
    # WiFi EN DERNIER : coupe le hotspot, l'utilisateur voit la page progress jusqu'au bout
    if wifi_ssid:
        step(f"⚠️ Le hotspot va s'arrêter — reconnectez-vous à votre WiFi puis ouvrez http://{hostname}.local")
    connect_wifi(wifi_ssid, wifi_password)
    install_runtipi()

    # --- Affichage de l'IP finale ---
    final_ip = get_final_ip()
    if final_ip:
        print(f"TIPI_IP:{final_ip}", flush=True)
    done("Configuration terminée !")


if __name__ == "__main__":
    main()
