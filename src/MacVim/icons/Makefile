.PHONY: clean

OUTDIR ?= .

$(OUTDIR)/MacVim-generic.icns: make_icons.py vim-noshadow-512.png
	$(MAKE) -C makeicns
	/usr/bin/python make_icons.py $(OUTDIR)

clean:
	$(MAKE) -C makeicns clean
	rm -f $(OUTDIR)/MacVim-*.icns *.pyc
