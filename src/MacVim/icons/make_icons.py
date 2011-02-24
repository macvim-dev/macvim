# Creates all of MacVim document icons.

import os
import sys

fontname = ''
facename = None

# http://www.macresearch.org/cocoa-scientists-part-xx-python-scriptersmeet-cocoa
try:
  # Make us independent of sysprefs->appearance->antialias fonts smaller than...
  # Needs to happen before docerator is imported.
  from AppKit import NSUserDefaults
  prefs = NSUserDefaults.standardUserDefaults()
  prefs.setInteger_forKey_(4, 'AppleAntiAliasingThreshold')

  import docerator
  import loadfont

  from Foundation import NSString
  from AppKit import *

  dont_create = False
except Exception, e:
  print e
  dont_create = True  # most likely because we're on tiger


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
    'MacVim-cpp': [u'C\uff0b\uff0b,C++,C++', SMALL],  # fullwidth plusses
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
    'MacVim-fscript': [u'FSCPT,FSCR,FS', SMALL],
    'MacVim-hs': [u'HS', SMALL],
    'MacVim-inc': [u'INC', LINK],
    'MacVim-ics': [u'ICS', SMALL],
    'MacVim-ini': [u'INI', LINK],
    'MacVim-io': [u'IO', LINK],
    'MacVim-bsh': [u'BSH', LINK],
    'MacVim-properties': [u'PROP', LINK],
    'MacVim-jsp': [u'JSP', SMALL],
    'MacVim-lisp': [u'LISP,LISP,LSP', SMALL],
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
    'MacVim-yaml': [u'YAML,YAML,YML', SMALL],
    'MacVim-gtd': [u'GTD', LINK],
    'MacVim-markdown': [u'MARK\u2193,M\u2193', LINK],  # down arrow
    'MacVim-rst': [u'RST', LINK],
    'MacVim-vba': [u'VBA', LINK],
}


def createLinks(icons, target):
  assert len(icons) > 0
  for name in icons:
    icnsName = '%s.icns' % name
    if os.access(icnsName, os.F_OK):
      os.remove(icnsName)
    os.symlink(target, icnsName)

if not dont_create:
  # define a few classes to render custom 16x16 icons

  class NoTextRenderer(docerator.TextRenderer):
    def drawTextAtSize(self, text, s):
      if s == 16: return  # No text at 16x16
      docerator.TextRenderer.drawTextAtSize(self, text, s)

  class NoIconRenderer(docerator.BackgroundRenderer):
    def drawIcon(self, s):
      if s == 16: return  # no "MacVim" icon on the sheet at 16x16
      docerator.BackgroundRenderer.drawIcon(self, s)

  class SmallTextRenderer(docerator.TextRenderer):
    def _attribsAtSize(self, s):
      global facename
      attribs = docerator.TextRenderer._attribsAtSize(self, s)
      if s == 16 and facename is not None:
        font = NSFont.fontWithName_size_(facename, 7.0)
        assert font
        attribs[NSFontAttributeName] = font
        attribs[NSForegroundColorAttributeName] = \
            NSColor.colorWithDeviceRed_green_blue_alpha_(
                0/255.0, 82/255.0, 0/255.0, 1)
      return attribs

    def drawTextAtSize(self, text, s):
      if s != 16:
        docerator.TextRenderer.drawTextAtSize(self, text, s)
        return
      text = NSString.stringWithString_(text.lower()[0:3])  # at most 3 chars
      attribs = self.attribsAtSize(s)
      if len(text) <= 2:
        attribs[NSKernAttributeName] = 0  # we have some space
      else:
        attribs[NSKernAttributeName] = -1  # we need all the room we can get
      text.drawInRect_withAttributes_( ((1, 2), (15, 11)), attribs)

def main():
  if dont_create:
    print "PyObjC not found, only using a stock icon for document icons."
    # Can't use the constants from docerator in this case
    import shutil
    shutil.copyfile(DEFAULT_BACKGROUND, '%s.icns' % GENERIC_ICON_NAME)
    createLinks([name for name in vimIcons if name != GENERIC_ICON_NAME],
        '%s.icns' % GENERIC_ICON_NAME)
    return

  # choose an icon font
  global fontname, facename
  # Thanks to DamienG for Envy Code R (redistributed with permission):
  # http://damieng.com/blog/2008/05/26/envy-code-r-preview-7-coding-font-released
  fonts = [('Envy Code R Bold.ttf', 'EnvyCodeR-Bold'), 
           ('/System/Library/Fonts/Monaco.dfont', 'Monaco')]
  for font in fonts:
    if loadfont.loadfont(font[0]):
      fontname, facename = font
      break
  print "Building icons with font '" + fontname + "'."

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
    if name == GENERIC_ICON_NAME:
      # The generic icon has no text; make the appicon a bit larger
      docerator.makedocicon(outname='%s.icns' % name, appicon=appIcon,
          text=text, sizes=iconsizes[size], makeicns=makeIcns,
          textrenderer=NoTextRenderer, rects={16:(0.0, 0.5533, 0.0, 0.5533)})
    else:
      # For the other icons, leave out appicon and render text in Envy Code R
      docerator.makedocicon(outname='%s.icns' % name, appicon=appIcon,
          text=text, sizes=iconsizes[size], makeicns=makeIcns,
          textrenderer=SmallTextRenderer, backgroundrenderer=NoIconRenderer)

  # ...create links later (to make sure the link targets exist)
  createLinks([name for (name, t) in vimIcons.items() if t[1] == LINK],
      '%s.icns' % GENERIC_ICON_NAME)


if __name__ == '__main__':
    main()
