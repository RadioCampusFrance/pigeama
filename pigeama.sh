#!/usr/bin/env bash

########################  PigeAMA ########################
#
#   Copyright © Martin Kirchgessner <martin.kirch@gmail.com>
#

######################## Paramètres ########################

# Age maximum (en jours) des fichiers/dossiers dans la pige
${NBJOURS:=31}

# Format des fichiers de pige: utiliser mp3|flac|wav|ogg
${FORMATPIGE:=flac}


######################## Pré-requis ########################
set -o errexit
set -o nounset
set -o pipefail
if [[ "${DEBUG-0}" == "1" ]] # ajoutez DEBUG=1 pour avoir plus de traces d'erreur
then
    set -o xtrace
fi
if [[ ! "$(which dpkg)" ]]
then
    printf "\n\nPigeAMA ne fonctionne qu'avec Debian ou dérivées (Ubuntu, etc.).\n\n"
    exit 1
fi
printf "PigeAMA a besoin des droits d'administration (sudo) :\n"
if ! sudo -v
then
    printf "\nImpossible de 'sudo', abandon.\n"
fi


######################## Environnement ########################

message() {
    printf "$@" | tee -a installation.log
}

message "Lancement de pigeama.sh: `date`\n"
message "\n\n************ 🚀  Mise à jour et installation des basiques **************\n\n"

export DEBIAN_FRONTEND=noninteractive
cd
sudo chmod go+rx .
PIGE_RACINE="$HOME/pige"
mkdir $PIGE_RACINE
chmod go+rw $PIGE_RACINE

ARCH="$(dpkg --print-architecture)" # amd64, arm, etc.
source /etc/os-release # on va utiliser ID et VERSION_CODENAME

if [[ "$ID" == "debian" ]]
then
    # on active "non-free", car Liquidsoap a besoin de libfdk-aac2 même si on ne va pas s'en servir
    sudo apt install -y software-properties-common
    sudo apt-add-repository non-free
fi

sudo apt update
sudo apt -y upgrade
sudo apt install -y curl wget ffmpeg


######################## Les vraies fonctions et contenus ########################

install_liquidsoap() {
    message "\n\n************ 🧴  Installation de LiquidSoap ************\n\n"

    # bricolage instable mais fonctionnel
    local LATEST=$(curl -w '%{redirect_url}' https://github.com/savonet/liquidsoap/releases/latest)
    local ASSETS_URL=${LATEST/tag/expanded_assets}
    wget -nd -r -l 1 -R '*dbgsym*' -A "liquidsoap*$ID*$VERSION_CODENAME*$ARCH.deb" "$ASSETS_URL"

    local PACKAGE=$(ls -tr liquidsoap*.deb |tail)
    message "\n\n************ Téléchargé: $PACKAGE **************\n"

    sudo apt install -y --install-recommends ./$PACKAGE

    message "\n\n************ Installé: `liquidsoap --version`\n"
}


read -r -d '' __PIGE_SCRIPT << END
settings.log.file.set(true)
settings.log.file.path.set("$HOME/pige.log")
settings.init.daemon.set(true)
settings.init.daemon.pidfile.set(true)
settings.init.daemon.pidfile.path.set("$HOME/pige.pid")

output.file(%$FORMATPIGE,
    "$PIGE_RACINE/%Y-%m-%d/%Hh%M_%S.$FORMATPIGE",
    input.alsa(),
    reopen_when = {0m}
)

END


read -r -d '' __PIGE_SERVICE << END
[Unit]
Description=Pige d'antenne
After=network.target

[Service]
Type=forking
PIDFile=$HOME/pige.pid
WorkingDirectory=$HOME
ExecStart=`which liquidsoap` $HOME/pige.liq
Restart=always

[Install]
WantedBy=default.target

END


read -r -d '' __NETTOYEUR_SCRIPT << END
#!/bin/bash
find $PIGE_RACINE/* -type f -mtime $NBJOURS -delete
find $PIGE_RACINE -type d -empty -delete

END


read -r -d '' __NETTOYEUR_SERVICE << END
[Unit]
Description=Nettoyage de la pige d'antenne

[Service]
Type=simple
ExecStart=$HOME/nettoyeur_pige.sh

END


read -r -d '' __NETTOYEUR_TIMER << END
[Unit]
Description=Nettoyage de la pige d'antenne

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target

END


install_pige() {
    message "\n\n************ 📻  Installation du service de pige ************\n\n"

    mkdir -p "$HOME/.config/systemd/user/"

    echo "$__PIGE_SCRIPT" > "$HOME/pige.liq"
    echo "$__PIGE_SERVICE" > "$HOME/.config/systemd/user/pige.service"

    echo "$__NETTOYEUR_SCRIPT" > "$HOME/nettoyeur_pige.sh"
    echo "$__NETTOYEUR_SERVICE" > "$HOME/.config/systemd/user/nettoyeur_pige.service"
    echo "$__NETTOYEUR_TIMER" > "$HOME/.config/systemd/user/nettoyeur_pige.timer"

    systemctl --user daemon-reload
    loginctl enable-linger
    systemctl --user enable pige
    systemctl --user enable nettoyeur_pige.timer
}


read -r -d '' __CONF_APACHE << END
ServerName pige.local

<Directory $PIGE_RACINE>
    AllowOverride All
    Require all granted
    Options +Indexes
</Directory>

DocumentRoot $PIGE_RACINE

END

install_apache() {
    message "\n\n************ 🪶  Installation d'Apache ************\n\n"
    sudo apt install -y apache2
    sudo echo "$__CONF_APACHE" > /etc/apache2/sites-available/000-default.conf
    # TODO sudo ufw allow 'WWW' ?
}


read -r -d '' __CONF_SAMBA << END
[global]
workgroup = PIGE
log file = /var/log/samba/%m
log level = 1
server role = standalone server
map to guest = bad dser

[guest]
path = $PIGE_RACINE
read only = yes
guest ok = yes
browseable = yes

END

install_samba() {
    message "\n\n************ 🪟  Installation de Samba ************\n\n"
    sudo apt install -y samba samba-client
    sudo echo "$__CONF_SAMBA" > /etc/samba/smb.conf
}


install_liquidsoap
install_pige
install_apache
install_samba

message "\n\n\n\n\n✨ ✨ ✨ ✨ ✨ ✨ 🏁 Tout est installé 🏁 ✨ ✨ ✨ ✨ ✨ ✨n\n\n\n\n"
message "`tput bold`⚠️   REDEMARRAGE de la machine dans 10s (appuyez sur Ctrl+C pour annuler)...\n\n"
sleep 10s
sudo reboot
