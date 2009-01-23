# Creates a document icon from an app icon and an optional text.

# The font is not quite right, use this script to create a document icon
# for 'PDF' and compare the D with the D in Preview's pdf.icns

# http://www.macresearch.org/cocoa-scientists-part-xx-python-scriptersmeet-cocoa
try:
  import docerator
  dont_create = False
except:
  dont_create = True  # most likely because we're on tiger

import os
import sys


# icon types
LARGE = 0  # 512, 128, 32, 16; about 96kB
SMALL = 1  # 128, 32, 16; about 36kB
LINK = 2  # Create link to generic icon; 4kB (== smallest block size on HFS+)

iconsizes = {
    SMALL: [128, 32, 16],
    LARGE: [512, 128, 32, 16],
}


# Resources
MAKEICNS = 'makeicns/makeicns'
APPICON = 'vim-noshadow-512.png'
DEFAULT_BACKGROUND = '/System/Library/CoreServices/CoreTypes.bundle/' + \
    'Contents/Resources/GenericDocumentIcon.icns'


# List of icons to create
GENERIC_ICON_NAME = 'MacVim-generic'
vimIcons = {
    GENERIC_ICON_NAME: [u'', LARGE],
    'MacVim-vim': [u'VIM', LARGE],
    'MacVim-txt': [u'TXT', SMALL],
    'MacVim-tex': [u'TEX', SMALL],
    'MacVim-h': [u'H', SMALL],
    'MacVim-c': [u'C', SMALL],
    'MacVim-m': [u'M', SMALL],
    'MacVim-mm': [u'MM', SMALL],
    'MacVim-cpp': [u'C\uff0b\uff0b', SMALL],  # fullwidth plusses
    'MacVim-java': [u'JAVA', SMALL],
    'MacVim-f': [u'FTRAN', SMALL],
    'MacVim-html': [u'HTML', SMALL],
    'MacVim-xml': [u'XML', SMALL],
    'MacVim-js': [u'JS', SMALL],
    'MacVim-perl': [u'PERL,PL', SMALL],
    'MacVim-py': [u'PYTHON,PY', SMALL],
    'MacVim-php': [u'PHP', SMALL],
    'MacVim-rb': [u'RUBY,RB', SMALL],
    'MacVim-bash': [u'SH', SMALL],
    'MacVim-patch': [u'DIFF', SMALL],
    'MacVim-applescript': [u'\uf8ffSCPT,\uf8ffS', SMALL],  # apple sign
    'MacVim-as': [u'FLASH', LINK],
    'MacVim-asp': [u'ASP', LINK],
    'MacVim-bib': [u'BIB', LINK],
    'MacVim-cs': [u'C#', LINK],
    'MacVim-csfg': [u'CFDG', LINK],
    'MacVim-csv': [u'CSV', LINK],
    'MacVim-tsv': [u'TSV', LINK],
    'MacVim-cgi': [u'CGI', LINK],
    'MacVim-cfg': [u'CFG', LINK],
    'MacVim-css': [u'CSS', SMALL],
    'MacVim-dtd': [u'DTD', LINK],
    'MacVim-dylan': [u'DYLAN', LINK],
    'MacVim-erl': [u'ERLANG,ERL', SMALL],
    'MacVim-fscript': [u'FSCPT,FSCR', SMALL],
    'MacVim-hs': [u'HS', SMALL],
    'MacVim-inc': [u'INC', LINK],
    'MacVim-ics': [u'ICS', SMALL],
    'MacVim-ini': [u'INI', LINK],
    'MacVim-io': [u'IO', LINK],
    'MacVim-bsh': [u'BSH', LINK],
    'MacVim-properties': [u'PROP', LINK],
    'MacVim-jsp': [u'JSP', SMALL],
    'MacVim-lisp': [u'LISP', SMALL],
    'MacVim-log': [u'LOG', SMALL],
    'MacVim-wiki': [u'WIKI', SMALL],
    'MacVim-ps': [u'PS', LINK],
    #'MacVim-plist': [u'PLIST', SMALL],
    'MacVim-sch': [u'SCHEME,SCM', SMALL],
    'MacVim-sql': [u'SQL', SMALL],
    'MacVim-tcl': [u'TCL', SMALL],
    'MacVim-xsl': [u'XSL', LINK],
    'MacVim-vcf': [u'VCARD,VCF', SMALL],
    'MacVim-vb': [u'VBASIC,VB', LINK],
    'MacVim-yaml': [u'YAML', SMALL],
    'MacVim-gtd': [u'GTD', LINK],
}


def createLinks(icons, target):
  assert len(icons) > 0
  for name in icons:
    icnsName = '%s.icns' % name
    if os.access(icnsName, os.F_OK):
      os.remove(icnsName)
    os.symlink(target, icnsName)


def main():
  if dont_create:
    print "PyObjC not found, only using a stock icon for document icons."
    # Can't use the constants from docerator in this case
    import shutil
    shutil.copyfile(DEFAULT_BACKGROUND, '%s.icns' % GENERIC_ICON_NAME)
    createLinks([name for name in vimIcons if name != GENERIC_ICON_NAME],
        '%s.icns' % GENERIC_ICON_NAME)
    return

  srcdir = os.getcwd()
  if len(sys.argv) > 1:
    os.chdir(sys.argv[1])
  appIcon = os.path.join(srcdir, APPICON)
  makeIcns = os.path.join(srcdir, MAKEICNS)
  

  # create LARGE and SMALL icons first...
  for name, t in vimIcons.iteritems():
    text, size = t
    if size == LINK: continue
    print name
    docerator.makedocicon(outname='%s.icns' % name, appicon=appIcon, text=text,
        sizes=iconsizes[size], makeicns=makeIcns)

  # ...create links later (to make sure the link targets exist)
  createLinks([name for (name, t) in vimIcons.items() if t[1] == LINK],
      '%s.icns' % GENERIC_ICON_NAME)


if __name__ == '__main__':
    main()
