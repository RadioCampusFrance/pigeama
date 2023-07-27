#!/usr/bin/env bash

########################  LibrePige ########################
#
#   Copyright © Martin Kirchgessner <martin.kirch@gmail.com>
#




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
    printf "\n\nLibrePige ne fonctionne qu'avec Debian ou dérivées (Ubuntu, etc.).\n\n"
    exit 1
fi
printf "LibrePige a besoin des droits d'administration (sudo) :\n"
if ! sudo -v
then
    printf "\nImpossible de 'sudo', abandon.\n"
fi


######################## Environnement ########################

export DEBIAN_FRONTEND=noninteractive
cd
printf "\n\n************ Mise à jour et installation des basiques **************\n"

ARCH="$(dpkg --print-architecture)" # amd64, arm, etc.
source /etc/os-release # on va utiliser ID et VERSION_CODENAME

if [[ "$ID" == "debian" ]]
then
    # on active "non-free", car Liquidsoap a besoin de libfdk-aac2 même si on ne va pas s'en servir
    sudo apt install -y software-properties-common
    sudo apt-add-repository non-free
    sudo apt-get update
fi

sudo apt-get update
sudo apt-get -y upgrade
sudo apt install -y curl wget ffmpeg

######################## Les vraies fonctions  ########################

install_liquidsoap() {
    # bricolage instable mais fonctionnel
    local LATEST=$(curl -w '%{redirect_url}' https://github.com/savonet/liquidsoap/releases/latest)
    local ASSETS_URL=${LATEST/tag/expanded_assets}
    wget -nd -r -l 1 -R '*dbgsym*' -A "liquidsoap*$ID*$VERSION_CODENAME*$ARCH.deb" "$ASSETS_URL"

    local PACKAGE=$(ls -tr liquidsoap*.deb |tail)
    printf "\n\n************ Téléchargé: $PACKAGE **************\n"

    sudo apt-get install -y --install-recommends ./$PACKAGE

    printf "\n\n************ Installé: "
    liquidsoap --version
}

install_liquidsoap
