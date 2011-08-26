.PHONY: clean getenvy

OUTDIR ?= .

# This script is called during the build phase with OUTDIR set to the Resources
# folder of the app bundle.  The default action is to simply copy all files
# named MacVim-*.icns to OUTDIR.
#
# The files in version control are all links to the MacVim-generic.icns file.
# In order to get prettier document icons, call "make all" in this folder
# before building.  This will call the document generation program which
# overwrites the MacVim-*.icns links with actual icons (see make_icons.py).
#
# The Envy Code R font can be used to render small icons that are more legible.
# In order to use ECR, call "make getenvy" before calling "make all".  This
# step requires an internet connection.

$(OUTDIR)/MacVim-generic.icns:
	cp -pR MacVim-*.icns "$(OUTDIR)"/

all: make_icons.py vim-noshadow-512.png loadfont.so
	rm -f MacVim-*.icns
	$(MAKE) -C makeicns
	/usr/bin/python make_icons.py "$(OUTDIR)"

loadfont.so: loadfont.c
	/usr/bin/python setup.py install --install-lib .

getenvy: Envy\ Code\ R\ Bold.ttf

Envy\ Code\ R\ Bold.ttf: EnvyCodeR.zip
	unzip -jo EnvyCodeR.zip
	# unzip uses the file date from the zip file. Change the file date to
	# "now", so that the zip is not unzipped in every `make` run.`
	touch Envy\ Code\ R\ Bold.ttf

ENVYCODE_URL=http://download.damieng.com/fonts/original/EnvyCodeR-PR7.zip
EnvyCodeR.zip:
	curl ${ENVYCODE_URL} --location -o EnvyCodeR.zip

clean:
	$(MAKE) -C makeicns clean
	rm -f "$(OUTDIR)"/MacVim-*.icns loadfont.so *.pyc \
	  EnvyCodeR.zip *.ttf *.reg *.txt
	rm -rf *.egginfo build  # Created by setup.py
