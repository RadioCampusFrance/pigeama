#
# Pour la maintenance: taper "make" depuis la branche "main" suffit, si vous avez les
# remotes suivantes et installé pandoc:
#
#    codeberg        ssh://git@codeberg.org/PigeAMA/PigeAMA.git
#    codeberg-pages  ssh://git@codeberg.org/PigeAMA/pages.git
#    github  git@github.com:RadioCampusFrance/pigeama.git
#    origin  git@git.sr.ht:~martink/pigeama
# 

all:
	pandoc -s index.md -o index.html
	git commit -a
	git switch wiki
	git merge main
	git switch main

	git push origin
	git push origin wiki
	git push codeberg
	git push codeberg-pages
	git push github
