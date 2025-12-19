#!/usr/bin/env bash

######################## 🦄 PigeAMA 🖭 #############################
#                                                                  #
# Distribué avec amour mais sans garantie, conformément à la WTFPL #
#                                                                  #
# Plus d'infos sur https://man.sr.ht/~martink/pigeama/#pigeama     #
#                                                                  #
####################################################################

{ # le } qui va avec est à la fin du fichier

######################## Paramètres ########################

# Age maximum (en jours) des fichiers/dossiers dans la pige
: "${NBJOURS:=31}"

# Format des fichiers de pige: utiliser mp3|flac|wav
: "${FORMATPIGE:=mp3}"

# Peut être fourni pour essayer avec une autre version de Liquidsoap
: "${VERSION_LS:=2.4.0}"

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
if ! sudo echo OK
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

sudo apt-get update

if [[ "$ID" == "debian" ]]
then
    # copié sur https://github.com/savonet/liquidsoap/blob/main/.github/docker/Dockerfile.production#L17
    # cf. https://www.liquidsoap.info/doc-dev/ffmpeg.html#fdk-aac-support-in-ffmpeg
    sudo apt install -y ca-certificates
    echo "deb https://www.deb-multimedia.org $VERSION_CODENAME main non-free" | sudo tee -a /etc/apt/sources.list
    sudo apt-get update -oAcquire::AllowInsecureRepositories=true
    sudo apt-get install -y --allow-unauthenticated deb-multimedia-keyring
    sudo apt-get update
fi

sudo apt-get -q install -y wget ffmpeg alsa-utils gettext

######################## Les vraies fonctions et contenus ########################

install_liquidsoap() {
    printf "\n\n************ 🧴  Installation de LiquidSoap ************\n\n"

    # bricolage instable mais fonctionnel
    local ASSETS_URL="https://github.com/savonet/liquidsoap-release-assets/releases/expanded_assets/v$VERSION_LS"
    wget -nd -r -l 1 -A "liquidsoap_*$ID*$VERSION_CODENAME*ocaml4*$ARCH.deb" "$ASSETS_URL"

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



install_pige() {
    printf "\n\n************ 📻  Installation du service de pige ************\n\n"

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
            ENCODAGE="mp3(bitrate=192)"
            ;;
    esac

    wget -O - https://git.sr.ht/~martink/pigeama/blob/main/pige.liq | envsubst > "$HOME/pige.liq"

    mkdir -p "$HOME/.config/systemd/user/"
    cat > "$HOME/.config/systemd/user/pige.service" << END
[Unit]
Description=Pige d'antenne
After=network.target

[Service]
Type=simple
PIDFile=$HOME/pige.pid
WorkingDirectory=$HOME
ExecStart=`which liquidsoap` $HOME/pige.liq
Restart=always

[Install]
WantedBy=default.target
END


    sudo dd of=/etc/logrotate.d/pige << END
$HOME/pige*.log {
    compress
    rotate 10
    size 10M
    missingok
    notifempty
    sharedscripts
    postrotate
        for liq in $HOME/pige*.pid ; do
            if [ -f "\$liq" ]
            then
                pid=\`cat "\$liq" | tr -d '\\n'\`
                kill -s USR1 "\$pid"
            fi
        done
    endscript
}
END


    cat > "$HOME/nettoyeur_pige.sh" << END
#!/bin/bash
find $PIGE_RACINE/* -type f -mtime +$NBJOURS -delete
find $PIGE_RACINE/* -type d -empty -delete
END
    chmod +x "$HOME/nettoyeur_pige.sh"

    cat > "$HOME/.config/systemd/user/nettoyeur_pige.service" << END
[Unit]
Description=Nettoyage de la pige d'antenne

[Service]
Type=simple
ExecStart=$HOME/nettoyeur_pige.sh
END


    cat > "$HOME/.config/systemd/user/nettoyeur_pige.timer" << END
[Unit]
Description=Nettoyage de la pige d'antenne

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
END

    systemctl --user daemon-reload
    loginctl enable-linger
    systemctl --user enable pige
    systemctl --user enable nettoyeur_pige.timer
}



install_apache() {
    printf "\n\n************ 🪶  Installation d'Apache ************\n\n"
    sudo apt-get install -y apache2
    sudo dd of=/etc/apache2/sites-available/000-default.conf << END
ServerName pige.local

<Directory $PIGE_RACINE>
    AllowOverride All
    Require all granted
    Options +Indexes
</Directory>

DocumentRoot $PIGE_RACINE
END
    # TODO sudo ufw allow 'WWW' ?
}



install_samba() {
    printf "\n\n************ 🪟  Installation de Samba ************\n\n"
    sudo apt-get install -y samba samba-client
    sudo dd of=/etc/samba/smb.conf << END
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
}

install_avahi() {
    sudo apt-get install -y avahi-daemon
    sudo dd of=/etc/avahi/services/http.service <<END
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
  </service>
</service-group>
END

    sudo dd of=/etc/avahi/services/samba.service <<END
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
</service-group>
END

    sudo systemctl restart avahi-daemon
}


install_liquidsoap
install_pige
install_apache
install_samba
sudo hostnamectl set-hostname pige
install_avahi

printf "\n\n\n\n\n✨ ✨ ✨ ✨ ✨ ✨ 🏁 Tout est installé 🏁 ✨ ✨ ✨ ✨ ✨ ✨n\n\n\n\n"
printf "`tput bold`⚠️   REDEMARRAGE de la machine dans 10s (appuyez sur Ctrl+C pour annuler)...\n\n"
sleep 10s
sudo reboot

} 2>&1 | tee -a installation.log
