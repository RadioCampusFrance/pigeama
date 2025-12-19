######################## 🦄 PigeAMA 🖭 #############################
#                                                                  #
# Distribué avec amour mais sans garantie, conformément à la WTFPL #
#                                                                  #
# Plus d'infos sur https://man.sr.ht/~martink/pigeama/#pigeama     #
#                                                                  #
####################################################################

# Ceci est le script Liquidsoap qui écoute la carte son et écrit les fichiers.

# les lignes qui commencent par un # sont des commentaires : elles ne seront pas
# lues par Liquidsoap, donc on peut y mettre quelques explications.

# On commence par quelques réglages de Liquidsoap :
settings.log.file.set(true)
settings.log.file.path.set("$HOME/pige.log")
settings.init.daemon.set(true)
settings.init.daemon.pidfile.set(true)
settings.init.daemon.pidfile.path.set("$HOME/pige.pid")

# Sélection de l'entrée sonore :
entree = input.alsa()

# Ensuite on créé des sorties.
# Les formats de sortie sont définis avec un %, par exemple :
# %flac
# %wav
# %mp3(bitrate=192)
# %mp3.vbr(quality=2, samplerate=48000)

output.file(%$ENCODAGE,
    { time.string("$PIGE_RACINE/%Y-%m-%d/%Hh%M_%S_%z.$EXTENSION") },
    entree,
    reopen_when = { 0m }
)

# pour envoyer le flux vers Icecast, retirez les # du bloc suivant, et mettez vos paramètres
# output.icecast(
#     host="serveur.maradio.org",
#     port=9000,
#     mount="/pointdemontage",
#     user="utilisateur",
#     password="motdepasse",
#     %$ENCODAGE,
#     entree
# )
