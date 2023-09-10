#!/usr/bin/env bash

######################## 🦄 PigeAMA 🖭 ##########################
#                                                               #
# Encore et toujours distribué sans garantie, conformément à la #
#              WTFPL : http://www.wtfpl.net/                    #
#                                                               #
#################################################################

{ # le } qui va avec est à la fin du fichier

######################## Paramètres ########################

# Age maximum (en jours) des fichiers/dossiers dans la pige
: "${NBJOURS:=31}"

# Format des fichiers de pige: utiliser mp3|flac|wav
: "${FORMATPIGE:=mp3}"

# Peut être fourni pour essayer avec une autre version de Liquidsoap
: "${VERSION_LS:=2.2.1}"

######################## Pré-requis ########################
set -o errexit
set -o nounset
set -o pipefail
if [[ "${DEBUG-0}" == "1" ]] # ajoutez DEBUG=1 pour avoir plus de traces d'erreur
then
    set -o xtrace
fi

printf "Lancement de pigeama.sh: `date`\n"

if [[ ! "$(which dpkg)" ]]
then
    printf "\n\nPigeAMA ne fonctionne qu'avec Debian ou dérivées (Ubuntu, etc.).\n\n"
    exit 1
fi
printf "PigeAMA a besoin des droits d'administration (sudo), il est possible que le mot de passe vous soit demandé régulièrement.\n"
if ! sudo -v
then
    printf "\nImpossible de 'sudo', abandon.\n"
fi


######################## Environnement ########################

printf "\n\n************ 🚀  Installation des basiques **************\n\n"

export DEBIAN_FRONTEND=noninteractive
cd
sudo chmod go+rx .
PIGE_RACINE="$HOME/pige"
mkdir -p $PIGE_RACINE
chmod go+rw $PIGE_RACINE

ARCH="$(dpkg --print-architecture)" # amd64, arm, etc.
source /etc/os-release # on va utiliser ID et VERSION_CODENAME

if [[ "$ID" == "debian" ]]
then
    # on active "non-free", car Liquidsoap a besoin de libfdk-aac2 même si on ne va pas s'en servir
    sudo apt-get install -q -y software-properties-common
    sudo apt-add-repository -y non-free
    sudo apt-get update
fi

sudo apt-get -q install -y curl wget ffmpeg

######################## Les vraies fonctions et contenus ########################

install_liquidsoap() {
    printf "\n\n************ 🧴  Installation de LiquidSoap ************\n\n"

    # bricolage instable mais fonctionnel
    local ASSETS_URL="https://github.com/savonet/liquidsoap/releases/expanded_assets/v$VERSION_LS"
    wget -nd -r -l 1 -R '*dbgsym*' -A "liquidsoap_*$ID*$VERSION_CODENAME*$ARCH.deb" "$ASSETS_URL"

    local PACKAGE=$(ls -tr liquidsoap*.deb |tail)
    if [ "$PACKAGE" = "" ];
    then
	    printf "\n\n⚠️  Impossible de trouver un paquet Liquidsoap pour votre système ($ID $VERSION_CODENAME) ou architecture ($ARCH).\n"
        printf "Vérifiez qu'il est dans la liste sur $ASSETS_URL\n"
	    exit 1
    fi
    printf "\n\n************ Téléchargé: $PACKAGE **************\n"

    sudo apt-get install -y --install-recommends ./$PACKAGE

    printf "\n\n************ Installé: `liquidsoap --version`\n"
}


case "$FORMATPIGE" in
    flac)
        EXTENSION="flac"
        ENCODAGE="flac"
        ;;
    wav)
        EXTENSION="wav"
        ENCODAGE="wav"
        ;;
    # ogg)  # HS avec Liquidsoap2.2.1 - essayer avec %ffmpeg ?
    #     EXTENSION="ogg"
    #     ENCODAGE="vorbis(samplerate=44100, channels=2, quality=0.3)"
    #     ;;
    *) # dans le doute, mp3 !
        EXTENSION="mp3"
        ENCODAGE="mp3(bitrate=128)"
        ;;
esac

__PIGE_SCRIPT=$(cat << END
settings.log.file.set(true)
settings.log.file.path.set("$HOME/pige.log")
settings.init.daemon.set(true)
settings.init.daemon.pidfile.set(true)
settings.init.daemon.pidfile.path.set("$HOME/pige.pid")

output.file(%$ENCODAGE,
    {time.string("$PIGE_RACINE/%Y-%m-%d/%Hh%M_%S.$EXTENSION")},
    input.alsa(),
    reopen_when = {0m}
)

END
)

__PIGE_SERVICE=$(cat << END
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
)

__NETTOYEUR_SCRIPT=$(cat << END
#!/bin/bash
find $PIGE_RACINE/* -type f -mtime $NBJOURS -delete
find $PIGE_RACINE -type d -empty -delete

END
)

__NETTOYEUR_SERVICE=$(cat << END
[Unit]
Description=Nettoyage de la pige d'antenne

[Service]
Type=simple
ExecStart=$HOME/nettoyeur_pige.sh

END
)

__NETTOYEUR_TIMER=$(cat << END
[Unit]
Description=Nettoyage de la pige d'antenne

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target

END
)

__LOGROTATE=$(cat << END
$HOME/pige*.log {
  compress
  rotate 10
  size 10M
  missingok
  notifempty
  sharedscripts
  postrotate
    for liq in $HOME/pige*.pid ; do
      if test \$liq != '$HOME/pige*.pid' ; then
        kill -s USR1 $(cat \$liq)
      fi
    done
  endscript
}

END
)

install_pige() {
    printf "\n\n************ 📻  Installation du service de pige ************\n\n"

    mkdir -p "$HOME/.config/systemd/user/"

    echo "$__PIGE_SCRIPT" > "$HOME/pige.liq"
    echo "$__PIGE_SERVICE" > "$HOME/.config/systemd/user/pige.service"
    echo "$__LOGROTATE" | sudo dd of=/etc/logrotate.d/pige

    echo "$__NETTOYEUR_SCRIPT" > "$HOME/nettoyeur_pige.sh"
    echo "$__NETTOYEUR_SERVICE" > "$HOME/.config/systemd/user/nettoyeur_pige.service"
    echo "$__NETTOYEUR_TIMER" > "$HOME/.config/systemd/user/nettoyeur_pige.timer"

    systemctl --user daemon-reload
    loginctl enable-linger
    systemctl --user enable pige
    systemctl --user enable nettoyeur_pige.timer
}


__CONF_APACHE=$(cat << END
ServerName pige.local

<Directory $PIGE_RACINE>
    AllowOverride All
    Require all granted
    Options +Indexes
</Directory>

DocumentRoot $PIGE_RACINE

END
)

install_apache() {
    printf "\n\n************ 🪶  Installation d'Apache ************\n\n"
    sudo apt-get install -y apache2
    echo "$__CONF_APACHE" | sudo dd of=/etc/apache2/sites-available/000-default.conf
    # TODO sudo ufw allow 'WWW' ?
}


__CONF_SAMBA=$(cat << END
[global]
# "workgroup" doit etre different de "netbios name"
workgroup = RADIO
netbios name = PIGE
log file = /var/log/samba/%m
log level = 1
server role = standalone server
map to guest = bad user

[PIGE]
path = $PIGE_RACINE
read only = yes
guest ok = yes
browseable = yes

END
)

install_samba() {
    printf "\n\n************ 🪟  Installation de Samba ************\n\n"
    sudo apt-get install -y samba samba-client
    echo "$__CONF_SAMBA" | sudo dd of=/etc/samba/smb.conf
}


install_liquidsoap
install_pige
install_apache
install_samba
sudo hostnamectl set-hostname pige

printf "\n\n\n\n\n✨ ✨ ✨ ✨ ✨ ✨ 🏁 Tout est installé 🏁 ✨ ✨ ✨ ✨ ✨ ✨n\n\n\n\n"
printf "`tput bold`⚠️   REDEMARRAGE de la machine dans 10s (appuyez sur Ctrl+C pour annuler)...\n\n"
sleep 10s
sudo reboot

} 2>&1 | tee -a installation.log
