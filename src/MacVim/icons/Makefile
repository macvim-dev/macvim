.PHONY: clean

OUTDIR ?= .

$(OUTDIR)/MacVim-generic.icns: make_icons.py vim-noshadow-512.png loadfont.so Envy\ Code\ R\ Bold.ttf
	$(MAKE) -C makeicns
	/usr/bin/python make_icons.py $(OUTDIR)

loadfont.so: loadfont.c
	python setup.py install --install-lib .

Envy\ Code\ R\ Bold.ttf: EnvyCodeR.zip
	unzip -jo EnvyCodeR.zip

ENVYCODE_URL=http://download.damieng.com/latest/EnvyCodeR
EnvyCodeR.zip:
	curl ${ENVYCODE_URL} --location -o EnvyCodeR.zip

clean:
	$(MAKE) -C makeicns clean
	rm -f $(OUTDIR)/MacVim-*.icns loadfont.so *.pyc \
	  EnvyCodeR.zip *.ttf *.reg *.txt
	rm -rf *.egginfo build  # Created by setup.py
