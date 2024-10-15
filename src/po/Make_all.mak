#
# Common po Makefile, defines the list of languages.
#

LANGUAGES = \
		af \
		am \
		ca \
		cs \
		da \
		de \
		en_GB \
		eo \
		es \
		fi \
		fr \
		ga \
		hu \
		it \
		ja \
		ko.UTF-8 \
		lv \
		nb \
		nl \
		no \
		pl \
		pt_BR \
		ru \
		sk \
		sr \
		sv \
		tr \
		uk \
		vi \
		zh_CN.UTF-8 \
		zh_TW.UTF-8 \

# MacVim: Don't bundle non-UTF-8 or encoding converted locale files as we always have iconv
		#cs.cp1250 \
		#ja.euc-jp \
		#ja.sjis \
		#ko \
		#pl.cp1250 \
		#pl.UTF-8 \
		#ru.cp1251 \
		#sk.cp1250 \
		#uk.cp1251 \
		#zh_CN \
		#zh_CN.cp936 \
		#zh_TW \


# MacVim: We removed the non-UTF-8 base locales for these, so we upgrade the
# <locale>.UTF-8 ones as base locales.
LANGUAGES_UTF8_ONLY = \
		ko \
		zh_CN \
		zh_TW \

POFILES = \
		af.po \
		am.po \
		ca.po \
		cs.po \
		da.po \
		de.po \
		en_GB.po \
		eo.po \
		es.po \
		fi.po \
		fr.po \
		ga.po \
		hu.po \
		it.po \
		ja.po \
		ko.UTF-8.po \
		lv.po \
		nb.po \
		nl.po \
		no.po \
		pl.po \
		pt_BR.po \
		ru.po \
		sk.po \
		sr.po \
		sv.po \
		tr.po \
		uk.po \
		vi.po \
		zh_CN.UTF-8.po \
		zh_TW.UTF-8.po \

# MacVim: Don't bundle non-UTF-8 or encoding converted locale files as we always have iconv
		#cs.cp1250.po \
		#ja.euc-jp.po \
		#ja.sjis.po \
		#ko.po \
		#pl.cp1250.po \
		#pl.UTF-8.po \
		#ru.cp1251.po \
		#sk.cp1250.po \
		#uk.cp1251.po \
		#zh_CN.po \
		#zh_CN.cp936.po \
		#zh_TW.po \


MOFILES = \
		af.mo \
		am.mo \
		ca.mo \
		cs.mo \
		da.mo \
		de.mo \
		en_GB.mo \
		eo.mo \
		es.mo \
		fi.mo \
		fr.mo \
		ga.mo \
		hu.mo \
		it.mo \
		ja.mo \
		ko.UTF-8.mo \
		lv.mo \
		nb.mo \
		nl.mo \
		no.mo \
		pl.mo \
		pt_BR.mo \
		ru.mo \
		sk.mo \
		sr.mo \
		sv.mo \
		tr.mo \
		uk.mo \
		vi.mo \
		zh_CN.UTF-8.mo \
		zh_TW.UTF-8.mo \


MOCONVERTED = \

# MacVim: Don't bundle non-UTF-8 or encoding converted locale files as we always have iconv
		#cs.cp1250.mo \
		#ja.euc-jp.mo \
		#ja.sjis.mo \
		#ko.mo \
		#pl.cp1250.mo \
		#pl.UTF-8.mo \
		#ru.cp1251.mo \
		#sk.cp1250.mo \
		#uk.cp1251.mo \
		#zh_CN.mo \
		#zh_CN.cp936.mo \
		#zh_TW.mo \


CHECKFILES = \
		af.ck \
		ca.ck \
		cs.ck \
		da.ck \
		de.ck \
		en_GB.ck \
		eo.ck \
		es.ck \
		fi.ck \
		fr.ck \
		ga.ck \
		hu.ck \
		it.ck \
		ja.ck \
		ko.UTF-8.ck \
		lv.ck \
		nb.ck \
		nl.ck \
		no.ck \
		pl.ck \
		pt_BR.ck \
		ru.ck \
		sk.ck \
		sr.ck \
		sv.ck \
		tr.ck \
		uk.ck \
		vi.ck \
		zh_CN.UTF-8.ck \
		zh_TW.UTF-8.ck \

# MacVim: Don't bundle non-UTF-8 or encoding converted locale files as we always have iconv
		#cs.cp1250.ck \
		#ja.euc-jp.ck \
		#ja.sjis.ck \
		#ko.ck \
		#pl.cp1250.ck \
		#pl.UTF-8.ck \
		#ru.cp1251.ck \
		#sk.cp1250.ck \
		#uk.cp1251.ck \
		#zh_CN.ck \
		#zh_CN.cp936.ck \
		#zh_TW.ck \

PO_VIM_INPUTLIST = \
	../../runtime/optwin.vim \
	../../runtime/defaults.vim

PO_VIM_JSLIST = \
	optwin.js \
	defaults.js

# Arguments for xgettext to pick up messages to translate from the source code.
XGETTEXT_KEYWORDS = --keyword=_ --keyword=N_ --keyword=NGETTEXT:1,2 --keyword=PLURAL_MSG:2,4
